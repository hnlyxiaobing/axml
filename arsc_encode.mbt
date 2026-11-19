///|
/// resources.arsc 值级回编（W9）：`ResTable → Bytes`，补全「解析→修改→回编」闭环。
///
/// 往返律定义为 `parse_arsc(encode_arsc(t))` 与规范化后的 `t` 语义等价（同包/
/// 类型/条目与值内容，键名池、类型池、全局池字符串一致），**不要求**与 aapt2
/// 产物字节级一致（值级回编，非构建期资源编译）。
///
/// 写出口径（文档化，见 docs/API.md D14）：
/// - entry offsets 一律写 **dense u32 槽**（`ResTypeConfig.flags` 位 0x01/0x02 置位
///   的 sparse/offset16 原始布局**显式拒绝**，不静默改写标志位）；
/// - compact 条目（`ResEntry.flags & 0x0008`）**显式拒绝**（dense 规范化会丢失
///   compact 标志位）；
/// - `ResConfig.raw`：`raw.length() >= size` 时取前 `size` 字节原样回写；
///   空/短 `raw`（构造型配置）按已解码 qualifier 字段序列化 `size` 字节镜像
///   （size 字段自描述 + 其余零填充），见 `encode_config_bytes` 与 docs/API.md D14；
/// - 字符串池按解析侧编码（UTF-8/UTF-16）与顺序重建。
///
/// 拒绝一律复用 `BadTable(0, detail)`，**不新增错误变体**（API 冻结硬约束）。
pub fn encode_arsc(table : ResTable) -> Bytes raise ArscError {
  let header : Array[Byte] = []
  enc_u16(header, 0x0002)
  enc_u16(header, 12)
  enc_u32(header, 0) // size 占位，最后回填
  enc_u32(header, table.packages.length())
  let global = encode_arsc_pool(table.global_pool)
  let packages : Array[Bytes] = []
  for p in table.packages {
    packages.push(encode_package(p))
  }
  let total = header.length() + global.length() + byte_len(packages)
  // 回填外层 size（表头 + 全局池 + 全部包）
  enc_u32_overwrite(header, 4, total)
  enc_cat([Bytes::from_array(header), global, enc_cat(packages)])
}

///|
/// 编码单个 `RES_TABLE_PACKAGE_TYPE` chunk（headerSize=288，含 typeIdOffset）。
/// 包内顺序：typeSpec/type/library 子 chunk 依 `ResPackage.types` 与 `libraries`
/// 顺序重建；type 池与键名池紧贴头部固定偏移（288 / 288+type_pool 长度）。
fn encode_package(p : ResPackage) -> Bytes raise ArscError {
  let type_pool = encode_arsc_pool(p.type_pool)
  let key_pool = encode_arsc_pool(p.key_pool)
  let children : Array[Bytes] = []
  for spec in p.types {
    children.push(encode_spec(spec))
    for cfg in spec.configs {
      children.push(encode_type_cfg(cfg))
    }
  }
  if !p.libraries.is_empty() {
    children.push(encode_library(p.libraries))
  }
  let type_strings_off = 288
  let key_strings_off = 288 + type_pool.length()
  let head : Array[Byte] = []
  enc_u32(head, p.id)
  enc_pkg_name(head, p.name)
  enc_u32(head, type_strings_off)
  enc_u32(head, 0)
  enc_u32(head, key_strings_off)
  enc_u32(head, 0)
  enc_u32(head, p.type_id_offset)
  let total = head.length() +
    type_pool.length() +
    key_pool.length() +
    byte_len(children)
  let out : Array[Byte] = []
  enc_u16(out, 0x0200)
  enc_u16(out, 288)
  enc_u32(out, 8 + total)
  enc_cat_into(out, head)
  enc_cat_bytes(out, type_pool)
  enc_cat_bytes(out, key_pool)
  for c in children {
    enc_cat_bytes(out, c)
  }
  Bytes::from_array(out)
}

///|
/// 包名：固定 128×u16 NUL 结尾（256 字节，与解析侧 `utf16z` 对齐）。
fn enc_pkg_name(out : Array[Byte], name : String) -> Unit raise ArscError {
  let units = enc_utf16_units(name)
  if units.length() > 128 {
    raise BadTable(0, "package name exceeds 128 UTF-16 units")
  }
  for i in 0..<128 {
    if i < units.length() {
      enc_u16(out, units.at(i))
    } else {
      enc_u16(out, 0)
    }
  }
}

///|
/// 编码 `RES_TABLE_TYPE_SPEC_TYPE` chunk（id + types_count + entry_count + 掩码）。
fn encode_spec(spec : ResTypeSpec) -> Bytes raise ArscError {
  if spec.entry_count < 0 || spec.entry_count > 0xFFFF {
    raise BadTable(0, "typeSpec entryCount out of range")
  }
  let body : Array[Byte] = []
  enc_u8(body, spec.id)
  enc_u8(body, 0)
  enc_u16(body, spec.types_count)
  enc_u32(body, spec.entry_count)
  for m in spec.spec_flags {
    enc_u32(body, m.reinterpret_as_int())
  }
  let out : Array[Byte] = []
  enc_u16(out, 0x0202)
  enc_u16(out, 16)
  enc_u32(out, 8 + body.length())
  enc_cat_into(out, body)
  Bytes::from_array(out)
}

///|
/// 编码一个 `RES_TABLE_TYPE_TYPE` chunk（dense u32 槽写出口径）。
/// sparse（flags&0x01）/offset16（flags&0x02）原始布局显式拒绝（BadTable）。
fn encode_type_cfg(cfg : ResTypeConfig) -> Bytes raise ArscError {
  if (cfg.flags & 0x01) != 0 || (cfg.flags & 0x02) != 0 {
    raise BadTable(
      0, "sparse/offset16 entry layout is rejected (dense write-out)",
    )
  }
  if cfg.entries.length() > 0xFFFF {
    raise BadTable(0, "type entryCount out of range")
  }
  let config_bytes = encode_config_bytes(cfg.config)
  // config 镜像补齐到 4 字节（AOSP 语义：entriesStart 须 4 对齐；config.size
  // 字段保持真实值，解析侧按 size 截取，尾部补零不影响解码）。
  let cfg_len = (config_bytes.length() + 3) / 4 * 4
  let config_padded : Array[Byte] = []
  enc_cat_bytes(config_padded, config_bytes)
  for _ in 0..<(cfg_len - config_bytes.length()) {
    config_padded.push(b'\x00')
  }
  let header_size = 20 + cfg_len
  // 先写 entries 数据并记录每项 offset（相对 entries_start）
  let entry_data : Array[Byte] = []
  let offsets : Array[Int32] = []
  for e in cfg.entries {
    match e {
      None => offsets.push(-1)
      Some(en) => {
        offsets.push(entry_data.length())
        encode_entry(en, entry_data)
      }
    }
  }
  let entries_start = header_size + 4 * cfg.entries.length()
  let body : Array[Byte] = []
  enc_u8(body, cfg.id)
  enc_u8(body, 0)
  enc_u16(body, 0)
  enc_u32(body, cfg.entries.length())
  enc_u32(body, entries_start)
  enc_cat_into(body, config_padded)
  for o in offsets {
    enc_u32(body, o)
  }
  enc_cat_into(body, entry_data)
  let out : Array[Byte] = []
  enc_u16(out, 0x0201)
  enc_u16(out, header_size)
  enc_u32(out, 8 + body.length())
  enc_cat_into(out, body)
  Bytes::from_array(out)
}

///|
/// 编码 `ResTable_config` 镜像字节（W9 修复，见 docs/API.md D14）：
/// - `size < 4` → `BadTable`（size 字段自描述的最小长度）；
/// - `raw.length() >= size` → 取前 `size` 字节原样回写（parse 产物的 raw 长度恒等于
///   size，与旧口径一致）；
/// - `raw.length() < size` → 按已解码 qualifier 字段序列化出 `size` 字节镜像：
///   前 4 字节写 `size`（自描述，`parse_config` 依赖），随后按 AOSP
///   `ResTable_config` 字段偏移写入 mcc/mnc/locale（`pack_locale`）/orientation/
///   touchscreen/density/keyboard/navigation/inputFlags/screenSize/version/
///   screenLayout/uiMode/smallestScreenWidthDp/widthDp/heightDp/localeScript/
///   colorMode，未覆盖偏移与超出已解码字段的尾部保留 0。
///   构造型配置（`from_qualifiers` 等，raw 为空）由此获得可回读的字段镜像；
///   镜像字节（回读后的 `raw`）是序列化产物，不参与语义等价比较。
fn encode_config_bytes(cfg : ResConfig) -> Bytes raise ArscError {
  if cfg.size < 4 {
    raise BadTable(0, "config size below 4")
  }
  let size = cfg.size
  let raw_len = cfg.raw.length()
  if raw_len >= size {
    return Bytes::from_array(cfg.raw[0:size].to_array())
  }
  let img : Array[Byte] = []
  for _ in 0..<size {
    img.push(b'\x00')
  }
  enc_put_u32(img, 0, size)
  if size >= 6 {
    enc_put_u16(img, 4, cfg.mcc)
  }
  if size >= 8 {
    enc_put_u16(img, 6, cfg.mnc)
  }
  if size >= 10 {
    enc_pack_locale(img, 8, cfg.language)
  }
  if size >= 12 {
    enc_pack_locale(img, 10, cfg.country)
  }
  if size >= 13 {
    img[12] = cfg.orientation.to_byte()
  }
  if size >= 14 {
    img[13] = cfg.touchscreen.to_byte()
  }
  if size >= 16 {
    enc_put_u16(img, 14, cfg.density)
  }
  if size >= 17 {
    img[16] = cfg.keyboard.to_byte()
  }
  if size >= 18 {
    img[17] = cfg.navigation.to_byte()
  }
  if size >= 19 {
    img[18] = cfg.input_flags.to_byte()
  }
  if size >= 22 {
    enc_put_u16(img, 20, cfg.screen_width)
  }
  if size >= 24 {
    enc_put_u16(img, 22, cfg.screen_height)
  }
  if size >= 26 {
    enc_put_u16(img, 24, cfg.sdk_version)
  }
  if size >= 29 {
    img[28] = cfg.screen_layout.to_byte()
  }
  if size >= 30 {
    img[29] = cfg.ui_mode.to_byte()
  }
  if size >= 32 {
    enc_put_u16(img, 30, cfg.smallest_screen_width_dp)
  }
  if size >= 34 {
    enc_put_u16(img, 32, cfg.screen_width_dp)
  }
  if size >= 36 {
    enc_put_u16(img, 34, cfg.screen_height_dp)
  }
  if size >= 40 {
    // localeScript：4 字节 ASCII，不足补 NUL
    let mut i = 0
    for c in cfg.locale_script {
      if i < 4 {
        img[36 + i] = c.to_int().to_byte()
      }
      i = i + 1
    }
    while i < 4 {
      img[36 + i] = b'\x00'
      i = i + 1
    }
  }
  if size >= 50 {
    img[49] = cfg.color_mode.to_byte()
  }
  Bytes::from_array(img)
}

///|
/// AOSP `packLanguageOrRegion`：两位 ASCII 原样写；三位压缩为 15 位
/// （大端 u16，bit15=1，'a'/'0' 基）；过长或含非 ASCII 报 `BadTable`。
fn enc_pack_locale(
  img : Array[Byte],
  off : Int32,
  s : String,
) -> Unit raise ArscError {
  if s == "" {
    return
  }
  let n = s.length()
  if n == 2 || n == 3 {
    let mut ok = true
    for c in s {
      if !((c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9')) {
        ok = false
      }
    }
    if ok {
      if n == 2 {
        img[off] = s[0].to_int().to_byte()
        img[off + 1] = s[1].to_int().to_byte()
        return
      }
      // 15 位压缩（大端 u16，bit15=1；码点 1-based，与 unpack_locale 对应）：
      // first=bit0-4、second=bit5-9、third=bit10-14
      let base = if s[0] >= '0' && s[0] <= '9' {
        '0'.to_int()
      } else {
        'a'.to_int()
      }
      let first = s[0].to_int() - base + 1
      let second = s[1].to_int() - base + 1
      let third = s[2].to_int() - base + 1
      let packed = 0x8000 |
        (first & 0x1F) |
        ((second & 0x1F) << 5) |
        ((third & 0x1F) << 10)
      img[off] = ((packed >> 8) & 0xFF).to_byte()
      img[off + 1] = (packed & 0xFF).to_byte()
      return
    }
  }
  raise BadTable(0, "config locale not representable: \{s}")
}

///|
/// 小端 u16 写入镜像数组。
fn enc_put_u16(img : Array[Byte], off : Int32, v : Int32) -> Unit {
  img[off] = (v & 0xFF).to_byte()
  img[off + 1] = ((v >> 8) & 0xFF).to_byte()
}

///|
/// 小端 u32 写入镜像数组。
fn enc_put_u32(img : Array[Byte], off : Int32, v : Int32) -> Unit {
  img[off] = (v & 0xFF).to_byte()
  img[off + 1] = ((v >> 8) & 0xFF).to_byte()
  img[off + 2] = ((v >> 16) & 0xFF).to_byte()
  img[off + 3] = ((v >> 24) & 0xFF).to_byte()
}

///|
/// 编码单个 `ResTable_entry`：简单条目写 8 字节头 + 8 字节 Res_value；
/// 复杂条目（bag）写 16 字节头 + count 个 12 字节 ResTable_map。
/// compact 条目（flags&0x0008）显式拒绝（dense 写出口径）。
fn encode_entry(en : ResEntry, out : Array[Byte]) -> Unit raise ArscError {
  if (en.flags & 0x0008) != 0 {
    raise BadTable(0, "compact entry is rejected (dense write-out)")
  }
  match en.value {
    Simple(v) => {
      enc_u16(out, 8)
      enc_u16(out, 0)
      enc_u32(out, en.key)
      encode_value(v, out)
    }
    Complex(bag) => {
      enc_u16(out, 16)
      enc_u16(out, 1)
      enc_u32(out, en.key)
      enc_u32(out, bag.parent.reinterpret_as_int())
      enc_u32(out, bag.maps.length())
      for m in bag.maps {
        enc_u32(out, m.name.reinterpret_as_int())
        encode_value(m.value, out)
      }
    }
  }
}

///|
/// 编码 8 字节 `Res_value`（size=8、res0=0、dataType、data）。
fn encode_value(v : ResValue, out : Array[Byte]) -> Unit {
  enc_u16(out, 8)
  enc_u8(out, 0)
  enc_u8(out, enc_data_type(v.data_type))
  enc_u32(out, v.data.reinterpret_as_int())
}

///|
/// `ResDataType` → `Res_value.dataType` 字节（与 `res_data_type_of` 互逆）。
fn enc_data_type(dt : ResDataType) -> Int32 {
  match dt {
    Null => 0x00
    Reference => 0x01
    Attribute => 0x02
    String => 0x03
    Float => 0x04
    Dimension => 0x05
    Fraction => 0x06
    DynamicReference => 0x07
    DynamicAttribute => 0x08
    IntDec => 0x10
    IntHex => 0x11
    IntBoolean => 0x12
    IntColorArgb8 => 0x1c
    IntColorRgb8 => 0x1d
    IntColorArgb4 => 0x1e
    IntColorRgb4 => 0x1f
    Unknown(n) => n
  }
}

///|
/// 编码 `RES_TABLE_LIBRARY_TYPE` chunk（headerSize=12，每项 260 字节）。
fn encode_library(libs : Array[ResLibrary]) -> Bytes raise ArscError {
  let body : Array[Byte] = []
  enc_u32(body, libs.length())
  for l in libs {
    enc_u32(body, l.package_id)
    enc_lib_name(body, l.name)
  }
  let out : Array[Byte] = []
  enc_u16(out, 0x0203)
  enc_u16(out, 12)
  enc_u32(out, 8 + body.length())
  enc_cat_into(out, body)
  Bytes::from_array(out)
}

///|
/// 库名：固定 128×u16 NUL 结尾（与解析侧 `parse_library` 步长 260 对齐）。
fn enc_lib_name(out : Array[Byte], name : String) -> Unit raise ArscError {
  let units = enc_utf16_units(name)
  if units.length() > 128 {
    raise BadTable(0, "library name exceeds 128 UTF-16 units")
  }
  for i in 0..<128 {
    if i < units.length() {
      enc_u16(out, units.at(i))
    } else {
      enc_u16(out, 0)
    }
  }
}

///|
/// 编码字符串池（复用 AXML 侧 `encode_string_pool`，错误映射到 `ArscError`）。
fn encode_arsc_pool(pool : StringPool) -> Bytes raise ArscError {
  encode_string_pool(pool) catch {
    e => raise axml_err(e)
  }
}

///|
/// 字符串的 UTF-16 code unit 数组（供定长 NUL 结尾名用）。
fn enc_utf16_units(s : String) -> Array[Int32] {
  let out : Array[Int32] = []
  for c in s {
    let cp = c.to_int()
    if cp <= 0xFFFF {
      out.push(cp)
    } else {
      out.push(0xD800 + ((cp - 0x10000) >> 10))
      out.push(0xDC00 + ((cp - 0x10000) & 0x3FF))
    }
  }
  out
}

///|
/// 拼接字节片段数组（复用 W8 的 `enc_cat` 语义，返回数组版）。
fn byte_len(parts : Array[Bytes]) -> Int32 {
  let mut n = 0
  for p in parts {
    n = n + p.length()
  }
  n
}

///|
/// 把字节片段数组追加进 `out`。
fn enc_cat_into(out : Array[Byte], part : Array[Byte]) -> Unit {
  for b in part {
    out.push(b)
  }
}

///|
/// 把 `Bytes` 片段追加进 `out`。
fn enc_cat_bytes(out : Array[Byte], part : Bytes) -> Unit {
  for i in 0..<part.length() {
    out.push(part.at(i))
  }
}

///|
/// 回填 `out` 中从 `off` 起的 4 字节 u32 值（覆盖写）。
fn enc_u32_overwrite(out : Array[Byte], off : Int32, n : Int32) -> Unit {
  out[off] = (n & 0xFF).to_byte()
  out[off + 1] = ((n >> 8) & 0xFF).to_byte()
  out[off + 2] = ((n >> 16) & 0xFF).to_byte()
  out[off + 3] = ((n >> 24) & 0xFF).to_byte()
}
