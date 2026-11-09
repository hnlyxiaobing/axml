///|
/// Internal byte-level chunk decoder for resources.arsc (not exported).
///
/// 语义基准：AOSP `ResourceTypes.h` 结构定义 + `LoadedArsc.cpp` 校验逻辑
/// （`VerifyResTableType` / `VerifyResTableEntry` / `GetEntryOffset`）。
/// 错误映射契约：
/// - `Eof(offset)`：以 `offset` 开头的读取项被截断；
/// - `BadChunk(offset, type)` / `BadHeader(offset, size)`：chunk 类型/头部尺寸非法；
/// - `BadPool(offset, detail)`：字符串池结构或内容非法（映射自 `AxmlError`）；
/// - `BadIndex(index)`：字符串池下标越界（映射自 `AxmlError`）；
/// - `BadTable(offset, detail)`：资源表结构语义违反 AOSP 约束。
/// 所有偏移均为输入缓冲区中的绝对字节偏移。禁止 panic。

///|
/// `AxmlError` → `ArscError`（字节层/字符串池层复用 AXML 解码器）。
fn axml_err(e : AxmlError) -> ArscError {
  match e {
    UnexpectedEof(o) => Eof(o)
    BadChunkType(o, t) => BadChunk(o, t)
    BadHeaderSize(o, s) => BadHeader(o, s)
    BadStringPool(o, d) => BadPool(o, d)
    InvalidStringIndex(i) => BadIndex(i)
    InvalidNodeIndex(i) => BadIndex(i)
    UnsupportedEncoding(d) => BadPool(0, d)
    VendorVariant(d) => BadTable(0, d)
  }
}

///|
fn r_u8(data : Bytes, off : Int32, limit : Int32) -> Int32 raise ArscError {
  read_u8(data, off, limit) catch {
    e => raise axml_err(e)
  }
}

///|
fn r_u16(data : Bytes, off : Int32, limit : Int32) -> Int32 raise ArscError {
  read_u16(data, off, limit) catch {
    e => raise axml_err(e)
  }
}

///|
fn r_u32(data : Bytes, off : Int32, limit : Int32) -> Int32 raise ArscError {
  read_u32(data, off, limit) catch {
    e => raise axml_err(e)
  }
}

///|
fn r_u32u(data : Bytes, off : Int32, limit : Int32) -> UInt32 raise ArscError {
  read_u32u(data, off, limit) catch {
    e => raise axml_err(e)
  }
}

///|
/// 解析一个字符串池 chunk（复用 AXML 侧严格解析器，错误映射到 `ArscError`）。
fn arsc_pool(
  data : Bytes,
  off : Int32,
  csize : Int32,
) -> StringPool raise ArscError {
  parse_string_pool(data, off, csize) catch {
    e => raise axml_err(e)
  }
}

///|
/// UTF-16 NUL 结尾定长字符串（包名/库名：最多 `max_units` 个 code unit）。
fn utf16z(
  data : Bytes,
  off : Int32,
  max_units : Int32,
  limit : Int32,
) -> String raise ArscError {
  let mut n = 0
  while n < max_units {
    let u = r_u16(data, off + 2 * n, limit)
    if u == 0 {
      break
    }
    n = n + 1
  }
  decode_utf16(data, off, n) catch {
    e => raise axml_err(e)
  }
}

///|
/// 解析整个 resources.arsc 文件。
/// 外层 `RES_TABLE_TYPE`：type==0x0002、headerSize==12；`size` 短于输入视为
/// 尾随垃圾报 `BadHeader`（与 `parse` 一致），长于输入在读取时报 `Eof`。
/// 全局字符串池必须存在（缺失报 `BadPool`）；多余字符串池与未知 chunk 跳过。
fn parse_table(data : Bytes) -> ResTable raise ArscError {
  let limit = data.length()
  let table_type = r_u16(data, 0, limit)
  if table_type != 0x0002 {
    raise BadChunk(0, table_type.reinterpret_as_uint())
  }
  let header_size = r_u16(data, 2, limit)
  if header_size != 12 {
    raise BadHeader(0, header_size)
  }
  let size = r_u32(data, 4, limit)
  if size < limit {
    raise BadHeader(4, size)
  }
  let package_count = r_u32(data, 8, limit)
  let mut global_pool : StringPool? = None
  let packages : Array[ResPackage] = []
  let mut off = 12
  while off < size {
    let chunk_type = r_u16(data, off, limit)
    let chunk_header_size = r_u16(data, off + 2, limit)
    let chunk_size = r_u32(data, off + 4, limit)
    if chunk_size < 8 {
      raise BadHeader(off, chunk_size)
    }
    if chunk_header_size < 8 || chunk_header_size > chunk_size {
      raise BadHeader(off, chunk_header_size)
    }
    if off + chunk_size > size {
      raise Eof(off)
    }
    if chunk_type == 0x0001 {
      // 全局值字符串池：只取第一个（与 AOSP 一致），其余忽略。
      if global_pool is None {
        if chunk_header_size != 28 {
          raise BadHeader(off, chunk_header_size)
        }
        global_pool = Some(arsc_pool(data, off, chunk_size))
      }
    } else if chunk_type == 0x0200 {
      if packages.length() >= package_count {
        raise BadTable(
          off, "more RES_TABLE_PACKAGE_TYPE chunks than packageCount",
        )
      }
      packages.push(parse_package(data, off, chunk_size))
    } else {
      // 其余顶层 chunk（不应出现）按 headerSize/size 跳过。
      ()
    }
    off = off + chunk_size
  }
  let global_pool = match global_pool {
    Some(p) => p
    None => raise BadPool(12, "missing global RES_STRING_POOL_TYPE chunk")
  }
  { global_pool, packages, package_count, }
}

///|
/// 解析 `RES_TABLE_PACKAGE_TYPE` chunk（起始于 `off`，长度 `csize`）。
///
/// AOSP 约束：headerSize >= 284（无 typeIdOffset 的旧包）或 288（新包）；
/// typeStrings/keyStrings 为相对包头的偏移且必须指向字符串池；继承包
/// （offsets 为 0）不在支持范围，报 `BadTable`。包内子 chunk：
/// 0x0202 typeSpec / 0x0201 type / 0x0203 library 解析，其余（0x0204 overlayable、
/// 0x0205 policy、0x0206 staged alias 等）按大小跳过（降级项）。
fn parse_package(
  data : Bytes,
  off : Int32,
  csize : Int32,
) -> ResPackage raise ArscError {
  let limit = off + csize
  let header_size = r_u16(data, off + 2, limit)
  if header_size < 284 || header_size > csize {
    raise BadHeader(off, header_size)
  }
  let id = r_u32(data, off + 8, limit)
  let name = utf16z(data, off + 12, 128, limit)
  let type_strings_off = r_u32(data, off + 268, limit)
  let key_strings_off = r_u32(data, off + 276, limit)
  let type_id_offset = if header_size >= 288 {
    r_u32(data, off + 284, limit)
  } else {
    0
  }
  if type_id_offset < 0 || type_id_offset > 255 {
    raise BadTable(off + 284, "typeIdOffset out of range")
  }
  if type_strings_off <= 0 || key_strings_off <= 0 {
    raise BadTable(
      off, "inheriting package (typeStrings/keyStrings == 0) is unsupported",
    )
  }
  let type_pool_at = off + type_strings_off
  let key_pool_at = off + key_strings_off
  if type_pool_at < off + header_size || type_pool_at + 28 > limit {
    raise BadTable(off + 268, "typeStrings offset out of package chunk")
  }
  if key_pool_at < off + header_size || key_pool_at + 28 > limit {
    raise BadTable(off + 276, "keyStrings offset out of package chunk")
  }
  if r_u16(data, type_pool_at, limit) != 0x0001 {
    raise BadChunk(type_pool_at, r_u32u(data, type_pool_at, limit))
  }
  if r_u16(data, key_pool_at, limit) != 0x0001 {
    raise BadChunk(key_pool_at, r_u32u(data, key_pool_at, limit))
  }
  let type_pool_size = r_u32(data, type_pool_at + 4, limit)
  let key_pool_size = r_u32(data, key_pool_at + 4, limit)
  if type_pool_at + type_pool_size > limit {
    raise Eof(type_pool_at)
  }
  if key_pool_at + key_pool_size > limit {
    raise Eof(key_pool_at)
  }
  let type_pool = arsc_pool(data, type_pool_at, type_pool_size)
  let key_pool = arsc_pool(data, key_pool_at, key_pool_size)
  let types : Array[ResTypeSpec] = []
  let libraries : Array[ResLibrary] = []
  let mut p = off + header_size
  while p < limit {
    let child_type = r_u16(data, p, limit)
    let child_header_size = r_u16(data, p + 2, limit)
    let child_size = r_u32(data, p + 4, limit)
    if child_size < 8 {
      raise BadHeader(p, child_size)
    }
    if child_header_size < 8 || child_header_size > child_size {
      raise BadHeader(p, child_header_size)
    }
    if p + child_size > limit {
      raise Eof(p)
    }
    if p == type_pool_at || p == key_pool_at {
      // 已按偏移解析的类型/键名池。
      ()
    } else if child_type == 0x0001 {
      // 多余字符串池（AOSP 记警告后忽略）。
      ()
    } else if child_type == 0x0202 {
      let spec = parse_typespec(data, p, child_size, child_header_size)
      let mut seen = false
      for t in types {
        if t.id == spec.id {
          seen = true
        }
      }
      if !seen {
        // AOSP：同 id 的重复 typeSpec 只取第一个，后续忽略。
        types.push(spec)
      }
    } else if child_type == 0x0201 {
      parse_type_into(data, p, child_size, child_header_size, types, key_pool)
    } else if child_type == 0x0203 {
      parse_library(data, p, child_size, child_header_size, libraries)
    } else {
      // 0x0204/0x0205/0x0206 及未知 chunk：跳过（降级项，见 docs/API.md）。
      ()
    }
    p = p + child_size
  }
  { id, name, type_id_offset, type_pool, key_pool, types, libraries, }
}

///|
/// 解析 `RES_TABLE_TYPE_SPEC_TYPE` chunk。`entryCount` 上限 0xFFFF（AOSP），
/// 其后是 entryCount 个 u32 配置掩码（SPEC_PUBLIC=0x40000000）。
fn parse_typespec(
  data : Bytes,
  off : Int32,
  csize : Int32,
  header_size : Int32,
) -> ResTypeSpec raise ArscError {
  let limit = off + csize
  if header_size < 16 {
    raise BadHeader(off, header_size)
  }
  let id = r_u8(data, off + 8, limit)
  if id == 0 {
    raise BadTable(off + 8, "RES_TABLE_TYPE_SPEC_TYPE with id 0")
  }
  let types_count = r_u16(data, off + 10, limit)
  let entry_count = r_u32(data, off + 12, limit)
  if entry_count < 0 || entry_count > 0xFFFF {
    raise BadTable(off + 12, "typeSpec entryCount out of range")
  }
  if entry_count * 4 > csize - header_size {
    raise BadTable(off, "typeSpec chunk too small for entry flags")
  }
  let spec_flags : Array[UInt32] = []
  let mut i = 0
  while i < entry_count {
    spec_flags.push(r_u32u(data, off + header_size + 4 * i, limit))
    i = i + 1
  }
  { id, types_count, entry_count, spec_flags, configs: [], }
}

///|
/// 解析 `RES_TABLE_TYPE_TYPE` chunk 并挂到既有 typeSpec（同 id）上。
/// AOSP 要求 type chunk 必须位于其 typeSpec 之后，否则报错。
fn parse_type_into(
  data : Bytes,
  off : Int32,
  csize : Int32,
  header_size : Int32,
  types : Array[ResTypeSpec],
  key_pool : StringPool,
) -> Unit raise ArscError {
  let limit = off + csize
  if header_size < 24 {
    // kResTableTypeMinSize：ResTable_type 固定字段 + config.size。
    raise BadHeader(off, header_size)
  }
  let id = r_u8(data, off + 8, limit)
  if id == 0 {
    raise BadTable(off + 8, "RES_TABLE_TYPE_TYPE with id 0")
  }
  let flags = r_u8(data, off + 9, limit)
  let entry_count = r_u32(data, off + 12, limit)
  let entries_start = r_u32(data, off + 16, limit)
  if entry_count < 0 || entry_count > 0xFFFF {
    raise BadTable(off + 12, "type entryCount out of range")
  }
  let offsets_len = if (flags & 0x02) != 0 {
    entry_count * 2
  } else {
    entry_count * 4
  }
  if (entries_start & 3) != 0 {
    raise BadTable(off + 16, "entriesStart not 4-byte aligned")
  }
  if entries_start < header_size || entries_start > csize {
    raise BadTable(off + 16, "entriesStart outside type chunk")
  }
  if entries_start - header_size < offsets_len {
    raise BadTable(off, "entry offsets overlap entry data")
  }
  let config = parse_config(data, off + 20, off + header_size)
  let entries = parse_entries(
    data, off, csize, header_size, flags, entry_count, entries_start, limit, key_pool,
  )
  let cfg : ResTypeConfig = { id, flags, config, entries, }
  let mut i = 0
  while i < types.length() {
    if types.at(i).id == id {
      types.at(i).configs.push(cfg)
      return
    }
    i = i + 1
  }
  raise BadTable(
    off, "RES_TABLE_TYPE_TYPE without preceding RES_TABLE_TYPE_SPEC_TYPE",
  )
}

///|
/// 解析 entry offsets 与 ResTable_entry 数据（dense u32 / OFFSET16 u16 / SPARSE）。
/// 语义逐项对齐 AOSP `LoadedPackage::GetEntryOffset`：
/// - dense：u32 偏移，0xFFFFFFFF(NO_ENTRY) 表示缺失；
/// - FLAG_OFFSET16：u16 偏移，真实偏移 = 值*4，0xFFFF 表示缺失；
/// - FLAG_SPARSE：ResTable_sparseTypeEntry{ idx:u16, offset:u16 } 表，idx 即
///   entry 下标、真实偏移 = offset*4，仅列出存在的条目。
fn parse_entries(
  data : Bytes,
  off : Int32,
  csize : Int32,
  header_size : Int32,
  flags : Int32,
  entry_count : Int32,
  entries_start : Int32,
  limit : Int32,
  key_pool : StringPool,
) -> Array[ResEntry?] raise ArscError {
  let entries : Array[ResEntry?] = []
  let sparse = (flags & 0x01) != 0
  let offset16 = (flags & 0x02) != 0
  if sparse {
    let mut max_idx = -1
    let mut i = 0
    while i < entry_count {
      let slot = off + header_size + 4 * i
      let idx = r_u16(data, slot, limit)
      ignore(r_u16(data, slot + 2, limit))
      if idx > max_idx {
        max_idx = idx
      }
      i = i + 1
    }
    let total = if max_idx + 1 > entry_count {
      max_idx + 1
    } else {
      entry_count
    }
    let mut j = 0
    while j < total {
      entries.push(None)
      j = j + 1
    }
    i = 0
    while i < entry_count {
      let slot = off + header_size + 4 * i
      let idx = r_u16(data, slot, limit)
      let entry_off = r_u16(data, slot + 2, limit) * 4
      let entry = parse_entry(
        data, off, csize, entries_start, entry_off, limit, key_pool,
      )
      entries[idx] = Some(entry)
      i = i + 1
    }
  } else {
    let mut i = 0
    while i < entry_count {
      let entry_off = if offset16 {
        let raw = r_u16(data, off + header_size + 2 * i, limit)
        if raw == 0xFFFF {
          entries.push(None)
          i = i + 1
          continue
        }
        raw * 4
      } else {
        let raw = r_u32(data, off + header_size + 4 * i, limit)
        if raw == -1 {
          entries.push(None)
          i = i + 1
          continue
        }
        if raw < 0 {
          raise BadTable(off + header_size + 4 * i, "negative entry offset")
        }
        raw
      }
      let entry = parse_entry(
        data, off, csize, entries_start, entry_off, limit, key_pool,
      )
      entries.push(Some(entry))
      i = i + 1
    }
  }
  entries
}

///|
/// 解析单个 `ResTable_entry`（相对 type chunk 的 `entry_off`，绝对位置
/// `off + entries_start + entry_off`）。边界校验对齐 AOSP `VerifyResTableEntry`；
/// compact entry（FLAG_COMPACT）按 AOSP `ResTable_entry::value()` 内联解码：
/// key 为 16 位、dataType 编码在 flags 高字节、data 内联。
fn parse_entry(
  data : Bytes,
  off : Int32,
  csize : Int32,
  entries_start : Int32,
  entry_off : Int32,
  limit : Int32,
  key_pool : StringPool,
) -> ResEntry raise ArscError {
  if (entry_off & 3) != 0 {
    raise BadTable(off, "entry offset not 4-byte aligned")
  }
  if entry_off > csize - 8 {
    raise BadTable(off, "entry offset beyond type chunk")
  }
  let e = off + entries_start + entry_off
  if e + 8 > limit {
    raise Eof(e)
  }
  let size = r_u16(data, e, limit)
  let flags = r_u16(data, e + 2, limit)
  if (flags & 0x0008) != 0 {
    // Compact entry：整项 8 字节，值内联（key:u16, flags:u16, data:u32）。
    let key = r_u16(data, e, limit)
    let data_type = r_u16(data, e + 2, limit) >> 8
    let value = r_u32u(data, e + 4, limit)
    return {
      key,
      key_name: pool_string(key_pool, key),
      flags,
      value: Simple({ data_type: res_data_type_of(data_type), data: value, }),
    }
  }
  if size < 8 {
    raise BadHeader(e, size)
  }
  if entry_off > csize - size {
    raise BadTable(e, "entry size beyond type chunk")
  }
  let key = r_u32(data, e + 4, limit)
  if (flags & 0x0001) != 0 {
    // 复杂条目（bag）：parent + count + count 个 ResTable_map。
    if size < 16 {
      raise BadHeader(e, size)
    }
    let parent = r_u32u(data, e + 8, limit)
    let count = r_u32(data, e + 12, limit)
    if count < 0 || count > (csize - entry_off - size) / 12 {
      raise BadTable(e + 12, "map count exceeds type chunk")
    }
    let maps : Array[ResMap] = []
    let mut i = 0
    while i < count {
      let m = e + size + 12 * i
      let name = r_u32u(data, m, limit)
      let value = parse_value(data, m + 4, limit)
      maps.push({ name, value, })
      i = i + 1
    }
    return {
      key,
      key_name: pool_string(key_pool, key),
      flags,
      value: Complex({ parent, maps, }),
    }
  }
  // 简单条目：Res_value 紧随其后。
  if entry_off > csize - size - 8 {
    raise BadTable(e, "no room for Res_value after entry")
  }
  let value = parse_value(data, e + size, limit)
  { key, key_name: pool_string(key_pool, key), flags, value: Simple(value), }
}

///|
/// 解析 `Res_value`（8 字节：size:u16, res0:u8, dataType:u8, data:u32）。
/// `size >= 8` 即接受（AOSP 同），多余字节忽略；`res0` 未使用。
fn parse_value(
  data : Bytes,
  off : Int32,
  limit : Int32,
) -> ResValue raise ArscError {
  let size = r_u16(data, off, limit)
  if size < 8 {
    raise BadHeader(off, size)
  }
  let data_type = r_u8(data, off + 3, limit)
  let raw = r_u32u(data, off + 4, limit)
  { data_type: res_data_type_of(data_type), data: raw, }
}

///|
/// 解析 `ResTable_config`（位于 type chunk 头部 `off`，至 `limit` 为止）。
/// 按字段偏移解码常用 qualifier；未覆盖字段保留在 `raw`。语言/地区按 AOSP
/// `unpackLanguageOrRegion` 解包（两位 ASCII 或 15 位压缩三字母码）。
fn parse_config(
  data : Bytes,
  off : Int32,
  limit : Int32,
) -> ResConfig raise ArscError {
  let size = r_u32(data, off, limit)
  if size < 4 || off + size > limit {
    raise BadHeader(off, size)
  }
  let end = off + size
  let mcc = if size >= 6 { r_u16(data, off + 4, end) } else { 0 }
  let mnc = if size >= 8 { r_u16(data, off + 6, end) } else { 0 }
  let language = if size >= 10 {
    unpack_locale(data, off + 8, end, false)
  } else {
    ""
  }
  let country = if size >= 12 {
    unpack_locale(data, off + 10, end, true)
  } else {
    ""
  }
  let orientation = if size >= 13 { r_u8(data, off + 12, end) } else { 0 }
  let touchscreen = if size >= 14 { r_u8(data, off + 13, end) } else { 0 }
  let density = if size >= 16 { r_u16(data, off + 14, end) } else { 0 }
  let keyboard = if size >= 17 { r_u8(data, off + 16, end) } else { 0 }
  let navigation = if size >= 18 { r_u8(data, off + 17, end) } else { 0 }
  let input_flags = if size >= 19 { r_u8(data, off + 18, end) } else { 0 }
  let screen_width = if size >= 22 { r_u16(data, off + 20, end) } else { 0 }
  let screen_height = if size >= 24 { r_u16(data, off + 22, end) } else { 0 }
  let sdk_version = if size >= 26 { r_u16(data, off + 24, end) } else { 0 }
  let screen_layout = if size >= 29 { r_u8(data, off + 28, end) } else { 0 }
  let ui_mode = if size >= 30 { r_u8(data, off + 29, end) } else { 0 }
  let smallest_screen_width_dp = if size >= 32 {
    r_u16(data, off + 30, end)
  } else {
    0
  }
  let screen_width_dp = if size >= 34 { r_u16(data, off + 32, end) } else { 0 }
  let screen_height_dp = if size >= 36 { r_u16(data, off + 34, end) } else { 0 }
  let locale_script = if size >= 40 { ascii4(data, off + 36, end) } else { "" }
  let color_mode = if size >= 50 { r_u8(data, off + 49, end) } else { 0 }
  let raw = Bytes::from_array(data[off:end].to_array())
  {
    size,
    mcc,
    mnc,
    language,
    country,
    orientation,
    touchscreen,
    density,
    keyboard,
    navigation,
    input_flags,
    screen_width,
    screen_height,
    sdk_version,
    screen_layout,
    ui_mode,
    smallest_screen_width_dp,
    screen_width_dp,
    screen_height_dp,
    locale_script,
    color_mode,
    raw,
  }
}

///|
/// 校验后的 Unicode 标量值转 `Char`（错误映射到 `ArscError`）。
fn schar(cp : Int32, at : Int32) -> Char raise ArscError {
  scalar_to_char(cp, at) catch {
    e => raise axml_err(e)
  }
}

///|
/// AOSP `unpackLanguageOrRegion`：两位 ASCII（高位置零）或 15 位压缩三字母码。
/// 压缩布局（大端 u16，bit15 恒 1）：first=bit0-4、second=bit5-9、third=bit10-14；
/// 语言以 'a'(97) 为基，地区（UN M.49 数字码）以 '0'(48) 为基。
fn unpack_locale(
  data : Bytes,
  off : Int32,
  limit : Int32,
  is_region : Bool,
) -> String raise ArscError {
  let high = r_u8(data, off, limit)
  let low = r_u8(data, off + 1, limit)
  if (high & 0x80) == 0 {
    let builder = StringBuilder(size_hint=2)
    if high != 0 {
      builder.write_char(schar(high, off))
      if low != 0 {
        builder.write_char(schar(low, off + 1))
      }
    }
    return builder.to_string()
  }
  let base = if is_region { 48 } else { 97 }
  let first = (low & 0x1F) + base - 1
  let second = (((low >> 5) | ((high & 0x03) << 3)) & 0x1F) + base - 1
  let third = ((high >> 2) & 0x1F) + base - 1
  let builder = StringBuilder(size_hint=3)
  builder.write_char(schar(first, off))
  builder.write_char(schar(second, off))
  builder.write_char(schar(third, off))
  builder.to_string()
}

///|
/// 4 字节 ASCII 串（localeScript），遇 NUL 截断。
fn ascii4(data : Bytes, off : Int32, limit : Int32) -> String raise ArscError {
  let builder = StringBuilder(size_hint=4)
  let mut i = 0
  while i < 4 {
    let c = r_u8(data, off + i, limit)
    if c == 0 {
      break
    }
    builder.write_char(schar(c, off + i))
    i = i + 1
  }
  builder.to_string()
}

///|
/// 解析 `RES_TABLE_LIBRARY_TYPE` 动态包映射（packageId:u32 + name:u16[128]）。
/// 仅供展示；本库不改写动态引用（见 docs/API.md 降级项）。
fn parse_library(
  data : Bytes,
  off : Int32,
  csize : Int32,
  header_size : Int32,
  libraries : Array[ResLibrary],
) -> Unit raise ArscError {
  let limit = off + csize
  if header_size < 12 {
    raise BadHeader(off, header_size)
  }
  let count = r_u32(data, off + 8, limit)
  if count < 0 || count > (csize - header_size) / 264 {
    raise BadTable(off + 8, "library count exceeds chunk")
  }
  let mut i = 0
  while i < count {
    let e = off + header_size + 264 * i
    let package_id = r_u32(data, e, limit)
    let name = utf16z(data, e + 4, 128, limit)
    libraries.push({ package_id, name, })
    i = i + 1
  }
}
