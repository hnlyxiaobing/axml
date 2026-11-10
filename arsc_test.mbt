// Blackbox tests for the resources.arsc parser. Run `moon test` to execute.
//
// 样本策略（与 axml_test.mbt / fixtures_test.mbt 同口径，不冒充真实格式兼容）：
// 1) 真实样本（内嵌字面量，来源与 SHA-256 见文件头注释；同字节样本亦入库
//    tests/fixtures/，登记见 tests/ASSETS.md）：
//    - base.apk / tvshell-debug.apk 的 resources.arsc（各 40 字节，空资源表）。
//      aapt2 交叉核对：`aapt2 dump resources <apk>` 仅输出 "Binary APK" 无任何
//      package/type/resource 行，与本库解析出的 package_count=0、全局池为空一致。
//    - framework-res.apk 的 resources.arsc（1759752 字节）过大不内嵌：开发期以
//      临时整表解析 + aapt2 dump resources 关键条目交叉核对后删除（结论见
//      tests/ASSETS.md §3）；其类型池 chunk（488 字节）永久内嵌于 arsc_wbtest.mbt。
// 2) 覆盖 header/字符串池/TypeSpec/Type/Entry/Res_value 的样本在测试代码中程序化
//    构造（明确标注为程序化，不代表真实 APK 兼容结论）。
//
// 真实样本 SHA-256：
//   base.apk                 D5824D09A5E9E3D6109D9298E72A9887566D35B9A8F89A56DE124D53AF0A94C3
//   base.resources.arsc      1FA3CB291285348EC1B33C85E7317D989467707F4791C4E5302F2D312D1E18C8
//   tvshell-debug.apk        24FA4F0BE0731806612DAFC486AF3ECD5978BF22BB8272314FFC62A6B1492093
//   tvshell-debug.resources.arsc  1FA3CB291285348EC1B33C85E7317D989467707F4791C4E5302F2D312D1E18C8
//   framework-res.apk        AD041A4703EE0C3E4BFB593608AC05500039BF3BDF21452E28EE1D2FED3514DC
//   framework-res.resources.arsc AA8BDA9CACF640E4BB7BD552AF4BF025D38EAEAF0C07CD04C5FBC15B3B8587B4

///|
/// 真实样本：base.apk -> resources.arsc（40 字节，RES_TABLE_TYPE + 空字符串池）。
/// 来源：受控自建 base.apk 的 resources.arsc 条目（SHA-256 见文件头注释），
/// 同字节样本入库 tests/fixtures/base.resources.arsc（见 tests/ASSETS.md）。
// FIXTURE-BEGIN arsc/base.resources.arsc
fn ar_fixture_base_arsc() -> Bytes {
  b"\x02\x00\x0c\x00\x28\x00\x00\x00\x00\x00\x00\x00\x01\x00\x1c\x00\x1c\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x1c\x00\x00\x00\x00\x00\x00\x00"
}
// FIXTURE-END arsc/base.resources.arsc

///|
/// 真实样本：tvshell-debug.apk -> resources.arsc（40 字节，与 base 的空表字节相同）。
/// 来源：受控自建 tvshell-debug.apk 的 resources.arsc 条目（SHA-256 见文件头注释），
/// 同字节样本入库 tests/fixtures/tvshell-debug.resources.arsc（见 tests/ASSETS.md）。
// FIXTURE-BEGIN arsc/tvshell-debug.resources.arsc
fn ar_fixture_tvshell_arsc() -> Bytes {
  b"\x02\x00\x0c\x00\x28\x00\x00\x00\x00\x00\x00\x00\x01\x00\x1c\x00\x1c\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x1c\x00\x00\x00\x00\x00\x00\x00"
}
// FIXTURE-END arsc/tvshell-debug.resources.arsc

///|
/// 8 位字面量助手。
fn ar_b(n : Int32) -> Byte {
  (n & 255).to_byte()
}

///|
/// 单字节 Bytes。
fn ar_byte(n : Int32) -> Bytes {
  Bytes::from_array([ar_b(n)])
}

///|
/// 小端 16 位字。
fn ar_w2(n : Int32) -> Bytes {
  Bytes::from_array([ar_b(n), ar_b(n >> 8)])
}

///|
/// 小端 32 位字。
fn ar_w4(n : Int32) -> Bytes {
  Bytes::from_array([ar_b(n), ar_b(n >> 8), ar_b(n >> 16), ar_b(n >> 24)])
}

///|
/// 小端 32 位无符号字。
fn ar_w4u(v : UInt32) -> Bytes {
  Bytes::from_array([
    (v & 255U).to_byte(),
    ((v >> 8) & 255U).to_byte(),
    ((v >> 16) & 255U).to_byte(),
    ((v >> 24) & 255U).to_byte(),
  ])
}

///|
/// 字节串拼接。
fn ar_cat(parts : Array[Bytes]) -> Bytes {
  let mut acc = b""
  for p in parts {
    acc = acc + p
  }
  acc
}

///|
/// 资源 id 组装（0xPPTTNNNN）。
fn ar_id(pp : Int32, tt : Int32, ee : Int32) -> UInt32 {
  (pp.reinterpret_as_uint() << 24) |
  (tt.reinterpret_as_uint() << 16) |
  ee.reinterpret_as_uint()
}

///|
/// UTF-8 字符串池条目（字符数 + 字节数 + 载荷 + NUL，ASCII 假定 1 字符 = 1 字节）。
fn ar_utf8_entry(s : String) -> Bytes {
  let mut payload = b""
  for c in s {
    payload = payload + ar_byte(c.to_int())
  }
  let n = s.length()
  let len = if n < 0x80 {
    Bytes::from_array([ar_b(n)])
  } else {
    Bytes::from_array([ar_b(0x80 | (n >> 8)), ar_b(n)])
  }
  ar_cat([len, len, payload, b"\x00"])
}

///|
/// UTF-8 字符串池 chunk（flags=0x100）。
fn ar_pool_utf8(entries : Array[String]) -> Bytes {
  let mut table = b""
  let mut data = b""
  for e in entries {
    table = table + ar_w4(data.length())
    data = data + ar_utf8_entry(e)
  }
  let count = entries.length()
  let body = ar_cat([
    ar_w4(count),
    ar_w4(0),
    ar_w4(0x100),
    ar_w4(28 + table.length()),
    ar_w4(0),
    table,
    data,
  ])
  ar_cat([ar_w2(0x0001), ar_w2(28), ar_w4(8 + body.length()), body])
}

///|
/// 由字符串取 UTF-16 code unit 数组（ASCII）。
fn ar_units(s : String) -> Array[Int32] {
  let out : Array[Int32] = []
  for c in s {
    out.push(c.to_int())
  }
  out
}

///|
/// UTF-16 字符串池条目（unit 数 + 载荷 + 16 位 NUL）。
fn ar_utf16_entry(units : Array[Int32]) -> Bytes {
  let mut payload = b""
  for u in units {
    payload = payload + ar_w2(u)
  }
  ar_cat([ar_w2(units.length()), payload, b"\x00\x00"])
}

///|
/// UTF-16 字符串池 chunk（flags=0）。
fn ar_pool_utf16(entries : Array[String]) -> Bytes {
  let mut table = b""
  let mut data = b""
  for e in entries {
    table = table + ar_w4(data.length())
    data = data + ar_utf16_entry(ar_units(e))
  }
  let count = entries.length()
  let body = ar_cat([
    ar_w4(count),
    ar_w4(0),
    ar_w4(0),
    ar_w4(28 + table.length()),
    ar_w4(0),
    table,
    data,
  ])
  ar_cat([ar_w2(0x0001), ar_w2(28), ar_w4(8 + body.length()), body])
}

///|
/// 定长 128×u16 NUL 结尾包名（256 字节）。
fn ar_utf16z(s : String) -> Bytes {
  let units = ar_units(s)
  let mut out = b""
  let mut i = 0
  while i < 128 {
    if i < units.length() {
      out = out + ar_w2(units.at(i))
    } else {
      out = out + b"\x00\x00"
    }
    i = i + 1
  }
  out
}

///|
/// `ResTable_package` chunk（headerSize=288，含 typeIdOffset）。
/// typeStrings=288、keyStrings=288+type_pool 长度（相对 chunk 起始）。
fn ar_package(
  id : Int32,
  name : String,
  type_pool : Bytes,
  key_pool : Bytes,
  children : Bytes,
  type_id_offset : Int32,
) -> Bytes {
  let body = ar_cat([
    ar_w4(id),
    ar_utf16z(name),
    ar_w4(288),
    ar_w4(0),
    ar_w4(288 + type_pool.length()),
    ar_w4(0),
    ar_w4(type_id_offset),
    type_pool,
    key_pool,
    children,
  ])
  ar_cat([ar_w2(0x0200), ar_w2(288), ar_w4(8 + body.length()), body])
}

///|
/// `ResTable_typeSpec` chunk（headerSize=16 + entryCount 个 u32 掩码）。
fn ar_spec(id : Int32, masks : Array[UInt32]) -> Bytes {
  let mut body = ar_cat([
    ar_byte(id),
    ar_byte(0),
    ar_w2(0),
    ar_w4(masks.length()),
  ])
  for m in masks {
    body = body + ar_w4u(m)
  }
  ar_cat([ar_w2(0x0202), ar_w2(16), ar_w4(8 + body.length()), body])
}

///|
/// 64 字节 `ResTable_config`（size=64），可选设 mcc/mnc/语言/地区/方向/density/sdk/swdp。
fn ar_config64(
  mcc : Int32,
  mnc : Int32,
  lang : String,
  country : String,
  orientation : Int32,
  density : Int32,
  sdk : Int32,
  swdp : Int32,
) -> Bytes {
  let lang_u = ar_units(lang)
  let country_u = ar_units(country)
  let lang0 = if lang_u.length() > 0 { lang_u.at(0) } else { 0 }
  let lang1 = if lang_u.length() > 1 { lang_u.at(1) } else { 0 }
  let c0 = if country_u.length() > 0 { country_u.at(0) } else { 0 }
  let c1 = if country_u.length() > 1 { country_u.at(1) } else { 0 }
  let head = ar_cat([
    ar_w4(64),
    ar_w2(mcc),
    ar_w2(mnc),
    Bytes::from_array([ar_b(lang0), ar_b(lang1), ar_b(c0), ar_b(c1)]),
    Bytes::from_array([ar_b(orientation), ar_b(0)]),
    ar_w2(density),
    b"\x00\x00\x00\x00",
    ar_w2(0),
    ar_w2(0),
    ar_w2(sdk),
    ar_w2(0),
    b"\x00\x00",
    ar_w2(swdp),
    ar_w2(0),
    ar_w2(0),
  ])
  // 尾部：localeScript(4) + localeVariant(8) + screenLayout2/colorMode/pad(4) + 12 = 28。
  let tail = ar_cat([
    b"\x00\x00\x00\x00", b"\x00\x00\x00\x00\x00\x00\x00\x00", b"\x00\x00\x00\x00",
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
  ])
  ar_cat([head, tail])
}

///|
/// `ResTable_type` chunk（flags：0=dense、1=SPARSE、2=OFFSET16）。
fn ar_type_chunk(
  id : Int32,
  flags : Int32,
  entry_count : Int32,
  config : Bytes,
  slots : Bytes,
  entries : Bytes,
) -> Bytes {
  let header_size = 20 + config.length()
  let entries_start = header_size + slots.length()
  let body = ar_cat([
    ar_byte(id),
    ar_byte(flags),
    ar_w2(0),
    ar_w4(entry_count),
    ar_w4(entries_start),
    config,
    slots,
    entries,
  ])
  ar_cat([ar_w2(0x0201), ar_w2(header_size), ar_w4(8 + body.length()), body])
}

///|
/// dense u32 entry offsets 槽（-1 表示 NO_ENTRY）。
fn ar_slots(offsets : Array[Int32]) -> Bytes {
  let mut out = b""
  for o in offsets {
    out = out + ar_w4(o)
  }
  out
}

///|
/// FLAG_OFFSET16 u16 entry offsets 槽（0xFFFF 表示 NO_ENTRY），尾部补零到 4 字节对齐。
fn ar_slots16(offsets : Array[Int32]) -> Bytes {
  let mut out = b""
  for o in offsets {
    out = out + ar_w2(o)
  }
  if (out.length() & 3) != 0 {
    out = out + b"\x00\x00"
  }
  out
}

///|
/// FLAG_SPARSE 槽（ResTable_sparseTypeEntry{idx:u16, offset/4:u16}）。
fn ar_slots_sparse(pairs : Array[(Int32, Int32)]) -> Bytes {
  let mut out = b""
  for p in pairs {
    out = out + ar_w2(p.0) + ar_w2(p.1)
  }
  out
}

///|
/// 简单条目（8 字节头 + 8 字节 Res_value）。
fn ar_simple(key : Int32, data_type : Int32, data : UInt32) -> Bytes {
  ar_cat([
    ar_w2(8),
    ar_w2(0),
    ar_w4(key),
    ar_w2(8),
    Bytes::from_array([ar_b(0), ar_b(data_type)]),
    ar_w4u(data),
  ])
}

///|
/// compact 条目（FLAG_COMPACT：key:u16 + flags:u16(高字节=dataType) + data:u32）。
fn ar_compact(key : Int32, data_type : Int32, data : UInt32) -> Bytes {
  ar_cat([ar_w2(key), ar_w2(8 | (data_type << 8)), ar_w4u(data)])
}

///|
/// 复杂条目（bag）：16 字节 ResTable_map_entry + count 个 12 字节 ResTable_map。
fn ar_bag(key : Int32, parent : UInt32, maps : Array[Bytes]) -> Bytes {
  let mut body = ar_cat([
    ar_w2(16),
    ar_w2(1),
    ar_w4(key),
    ar_w4u(parent),
    ar_w4(maps.length()),
  ])
  for m in maps {
    body = body + m
  }
  body
}

///|
/// bag 映射项（name:u32 + 8 字节 Res_value）。
fn ar_map(name : UInt32, data_type : Int32, data : UInt32) -> Bytes {
  ar_cat([
    ar_w4u(name),
    ar_w2(8),
    Bytes::from_array([ar_b(0), ar_b(data_type)]),
    ar_w4u(data),
  ])
}

///|
/// `RES_TABLE_LIBRARY_TYPE` chunk（headerSize=12，每项 260 字节：u32 packageId +
/// 128×u16 NUL 结尾名）。用于回归 library 条目步长。
fn ar_library_chunk(libs : Array[(Int32, String)]) -> Bytes {
  let mut entries = b""
  for p in libs {
    entries = entries + ar_w4(p.0) + ar_utf16z(p.1)
  }
  let body = ar_cat([ar_w4(libs.length()), entries])
  ar_cat([ar_w2(0x0203), ar_w2(12), ar_w4(8 + body.length()), body])
}

///|
/// 程序化黄金表（非真实 APK）：
/// 全局池 UTF-8 ["MyApp","Hello","hi"]；类型池/键名池 UTF-16（对齐 framework-res
/// 的双编码布局）；包 com.example.app(id=0x7f, typeIdOffset=0)；
/// 类型 1 string（默认 + zh-rCN 两配置）、2 color、3 dimen、4 bool、5 integer、
/// 6 misc（Res_value 全类型 + compact + bag）、7 style（bag 继承）、
/// 8 sparse（FLAG_SPARSE）、9 off16（FLAG_OFFSET16 含 NO_ENTRY 洞）。
fn ar_table_bytes() -> Bytes {
  let global = ar_pool_utf8(["MyApp", "Hello", "hi"])
  let type_pool = ar_pool_utf16([
    "string", "color", "dimen", "bool", "integer", "misc", "style", "sparse", "off16",
  ])
  let key_pool = ar_pool_utf16([
    "app_name", "hello", "primary", "pad", "enabled", "not_ready", "count", "bits",
    "flag", "ratio", "weird", "bag", "theme", "base_theme", "s0", "s5", "o0", "o2",
  ])
  let default_cfg = ar_config64(0, 0, "", "", 0, 0, 0, 0)
  let zh_cfg = ar_config64(0, 0, "zh", "CN", 0, 0, 0, 0)
  // 类型 1 string：默认配置 app_name→"MyApp"、hello→"Hello"；zh-rCN 配置 app_name→"hi"。
  let string_spec = ar_spec(1, [1073741824U, 0U])
  let string_default = ar_type_chunk(
    1,
    0,
    2,
    default_cfg,
    ar_slots([0, 16]),
    ar_cat([ar_simple(0, 0x03, 0U), ar_simple(1, 0x03, 1U)]),
  )
  let string_zh = ar_type_chunk(
    1,
    0,
    2,
    zh_cfg,
    ar_slots([0, -1]),
    ar_simple(0, 0x03, 2U),
  )
  // 类型 2 color：#ff112233。
  let color_spec = ar_spec(2, [0U])
  let color_chunk = ar_type_chunk(
    2,
    0,
    1,
    default_cfg,
    ar_slots([0]),
    ar_simple(2, 0x1c, 4279312947U),
  )
  // 类型 3 dimen：48dp。
  let dimen_spec = ar_spec(3, [0U])
  let dimen_chunk = ar_type_chunk(
    3,
    0,
    1,
    default_cfg,
    ar_slots([0]),
    ar_simple(3, 0x05, 12289U),
  )
  // 类型 4 bool：true / false。
  let bool_spec = ar_spec(4, [0U, 0U])
  let bool_chunk = ar_type_chunk(
    4,
    0,
    2,
    default_cfg,
    ar_slots([0, 16]),
    ar_cat([ar_simple(4, 0x12, 1U), ar_simple(5, 0x12, 0U)]),
  )
  // 类型 5 integer：42。
  let int_spec = ar_spec(5, [0U])
  let int_chunk = ar_type_chunk(
    5,
    0,
    1,
    default_cfg,
    ar_slots([0]),
    ar_simple(6, 0x10, 42U),
  )
  // 类型 6 misc：Res_value 全数据类型 + compact + bag。
  let misc_spec = ar_spec(6, [
    0U, 0U, 0U, 0U, 0U, 0U, 0U, 0U, 0U, 0U, 0U, 0U, 0U, 0U, 0U, 0U,
  ])
  let misc_entries = ar_cat([
    ar_simple(0, 0x00, 0U),
    ar_simple(1, 0x01, ar_id(0x7f, 1, 0)),
    ar_simple(2, 0x07, ar_id(0x7f, 1, 1)),
    ar_simple(3, 0x04, 1069547520U),
    ar_simple(4, 0x05, 4097U),
    ar_simple(5, 0x06, 768U),
    ar_simple(6, 0x10, 4294967291U),
    ar_simple(7, 0x11, 3405691582U),
    ar_simple(8, 0x12, 1U),
    ar_simple(9, 0x1c, 2148606515U),
    ar_simple(10, 0x1d, 11189196U),
    ar_simple(11, 0x1e, 2748U),
    ar_simple(12, 0x1f, 2748U),
    ar_simple(13, 0x2a, 7U),
    ar_compact(14, 0x10, 7U),
    ar_bag(15, ar_id(0x7f, 7, 0), [
      ar_map(ar_id(1, 0, 0), 0x10, 1U),
      ar_map(ar_id(0x7f, 1, 0), 0x01, ar_id(0x7f, 1, 1)),
    ]),
  ])
  let misc_chunk = ar_type_chunk(
    6,
    0,
    16,
    default_cfg,
    ar_slots([
      0, 16, 32, 48, 64, 80, 96, 112, 128, 144, 160, 176, 192, 208, 224, 232,
    ]),
    misc_entries,
  )
  // 类型 7 style：两个 bag（parent 继承）。
  let style_spec = ar_spec(7, [0U, 0U])
  let style_chunk = ar_type_chunk(
    7,
    0,
    2,
    default_cfg,
    ar_slots([0, 28]),
    ar_cat([
      ar_bag(13, 0U, [ar_map(ar_id(0x7f, 6, 8), 0x12, 1U)]),
      ar_bag(12, ar_id(0x7f, 7, 0), [ar_map(ar_id(0x7f, 6, 8), 0x10, 3U)]),
    ]),
  )
  // 类型 8 sparse：只有 idx 0 与 5 两个条目（AOSP FLAG_SPARSE 语义）。
  let sparse_spec = ar_spec(8, [0U, 0U, 0U, 0U, 0U, 0U])
  let sparse_chunk = ar_type_chunk(
    8,
    1,
    2,
    default_cfg,
    ar_slots_sparse([(0, 0), (5, 4)]),
    ar_cat([ar_simple(14, 0x10, 100U), ar_simple(15, 0x10, 500U)]),
  )
  // 类型 9 off16：u16 槽 [0, 0xFFFF(洞), 4]。
  let off16_spec = ar_spec(9, [0U, 0U, 0U])
  let off16_chunk = ar_type_chunk(
    9,
    2,
    3,
    default_cfg,
    ar_slots16([0, 65535, 4]),
    ar_cat([ar_simple(16, 0x10, 1U), ar_simple(17, 0x10, 2U)]),
  )
  let children = ar_cat([
    string_spec, string_default, string_zh, color_spec, color_chunk, dimen_spec,
    dimen_chunk, bool_spec, bool_chunk, int_spec, int_chunk, misc_spec, misc_chunk,
    style_spec, style_chunk, sparse_spec, sparse_chunk, off16_spec, off16_chunk,
  ])
  let pkg = ar_package(127, "com.example.app", type_pool, key_pool, children, 0)
  let body = ar_cat([global, pkg])
  ar_cat([ar_w2(0x0002), ar_w2(12), ar_w4(12 + body.length()), ar_w4(1), body])
}

///|
/// 取解析错误的辅助（与 axml_test.mbt 同模式）。
fn ar_arsc_err(data : Bytes) -> @axml.ArscError raise {
  let result = Ok(@axml.parse_arsc(data)) catch { err => Err(err) }
  match result {
    Ok(_) => fail("expected parse_arsc to raise ArscError")
    Err(e) => e
  }
}

///|
/// 解析是否以 `ArscError` 结束（true = 报错）；panic 不会被吞掉，测试直接失败。
fn ar_raises(b : Bytes) -> Bool {
  let mut raised = false
  try ignore(@axml.parse_arsc(b)) catch {
    _ => raised = true
  } noraise {
    _ => ()
  }
  raised
}

///|
/// 简单条目取值辅助（复杂条目在 bag 测试里单独 match）。
fn ar_value_of(entry : @axml.ResEntry) -> @axml.ResValue raise {
  match entry.value {
    Simple(v) => v
    Complex(_) => fail("expected simple entry")
  }
}

///|
/// 按 id 取格式化值。
fn ar_fmt(table : @axml.ResTable, tt : Int32, ee : Int32) -> String raise {
  match @axml.ResTable::lookup(table, ar_id(0x7f, tt, ee)) {
    Some(h) => @axml.ResTable::format_value(table, ar_value_of(h.entry))
    None => fail("lookup 未命中")
  }
}

///|
/// 构造 AXML 属性（resolve_attr_value 测试用）。
fn ar_attr(
  value_type : @axml.ValueType,
  raw_data : UInt32,
  raw_value : String?,
) -> @axml.XmlAttribute {
  {
    ns: None,
    name: "label",
    raw_value,
    value_type,
    res0: ar_b(0),
    raw_data,
    line: 1,
  }
}

///|
/// 构造最小 AXML 文档（字符串池 ["Hello"]，供 String 型属性取字面量）。
fn ar_doc() -> @axml.AxmlDoc {
  {
    pool: { encoding: Utf8, strings: ["Hello"], styles: b"", },
    nodes: [],
    roots: [],
    resource_map: [],
  }
}

///|
/// 真实样本：base.apk 空资源表可解析（与 aapt2 dump resources 无 package 一致）。
test "arsc real: base.apk 空资源表" {
  let table = @axml.parse_arsc(ar_fixture_base_arsc())
  assert_eq(table.package_count, 0, msg="packageCount 声明为 0")
  assert_eq(table.packages.length(), 0, msg="无包")
  assert_eq(table.global_pool.strings.length(), 0, msg="全局池为空")
  assert_true(
    table.global_pool.encoding is Utf8,
    msg="空池按 UTF8_FLAG 解码",
  )
}

///|
/// 真实样本：tvshell-debug.apk 空资源表可解析。
test "arsc real: tvshell-debug.apk 空资源表" {
  let table = @axml.parse_arsc(ar_fixture_tvshell_arsc())
  assert_eq(table.package_count, 0, msg="packageCount 声明为 0")
  assert_eq(table.packages.length(), 0, msg="无包")
  assert_eq(table.global_pool.strings.length(), 0, msg="全局池为空")
}

///|
/// 程序化：表头/包身份/类型名映射。
test "arsc table: 表头与包身份" {
  let table = @axml.parse_arsc(ar_table_bytes())
  assert_eq(table.package_count, 1, msg="packageCount=1")
  assert_eq(table.packages.length(), 1, msg="1 个包")
  let pkg = table.packages.at(0)
  assert_eq(pkg.id, 127, msg="包 id 0x7f")
  assert_eq(pkg.name, "com.example.app", msg="包名")
  assert_eq(pkg.type_id_offset, 0, msg="typeIdOffset")
  assert_eq(pkg.types.length(), 9, msg="9 个 typeSpec")
  assert_eq(pkg.type_pool.strings.length(), 9, msg="类型池 9 串")
  assert_eq(pkg.key_pool.strings.length(), 18, msg="键名池 18 串")
  assert_true(table.global_pool.encoding is Utf8, msg="全局池 UTF-8")
  assert_true(pkg.type_pool.encoding is Utf16, msg="类型池 UTF-16")
  assert_true(pkg.key_pool.encoding is Utf16, msg="键名池 UTF-16")
  assert_true(
    @axml.ResTable::package_by_id(table, 127) is Some(_),
    msg="package_by_id 命中",
  )
  assert_true(
    @axml.ResTable::package_by_id(table, 1) is None,
    msg="package_by_id 未命中",
  )
}

///|
/// 程序化：id 查询（默认配置优先）+ lookup_all 多配置。
test "arsc lookup: 默认配置优先" {
  let table = @axml.parse_arsc(ar_table_bytes())
  let hit = match @axml.ResTable::lookup(table, ar_id(0x7f, 1, 0)) {
    Some(h) => h
    None => fail("lookup 0x7f010000 未命中")
  }
  assert_eq(hit.package_name, "com.example.app", msg="包名")
  assert_eq(hit.type_name, "string", msg="类型名")
  assert_eq(hit.entry_name, "app_name", msg="条目名")
  assert_eq(hit.type_id, 1, msg="类型 id")
  assert_eq(hit.entry_id, 0, msg="条目 id")
  assert_true(hit.config.is_default(), msg="选中默认配置")
  assert_eq(
    @axml.ResTable::format_value(table, ar_value_of(hit.entry)),
    "MyApp",
    msg="默认配置值",
  )
  let all = @axml.ResTable::lookup_all(table, ar_id(0x7f, 1, 0))
  assert_eq(all.length(), 2, msg="两个配置命中")
  assert_eq(all.at(1).config.language, "zh", msg="第二命中语言")
  assert_eq(all.at(1).config.country, "CN", msg="第二命中地区")
  assert_eq(
    @axml.ResTable::format_value(table, ar_value_of(all.at(1).entry)),
    "hi",
    msg="zh-rCN 值",
  )
  assert_true(
    @axml.ResTable::lookup(table, ar_id(0x7f, 1, 2)) is None,
    msg="越界条目未命中",
  )
  assert_true(
    @axml.ResTable::lookup(table, ar_id(0x7f, 9, 1)) is None,
    msg="NO_ENTRY 洞未命中",
  )
  assert_true(
    @axml.ResTable::lookup(table, ar_id(1, 1, 0)) is None,
    msg="错包未命中",
  )
}

///|
/// 程序化：按名字查 id。
test "arsc find_id: 类型名 + 条目名" {
  let table = @axml.parse_arsc(ar_table_bytes())
  assert_eq(
    @axml.ResTable::find_id(table, "string", "hello"),
    Some(ar_id(0x7f, 1, 1)),
    msg="hello -> 0x7f010001",
  )
  assert_eq(
    @axml.ResTable::find_id(table, "style", "theme"),
    Some(ar_id(0x7f, 7, 1)),
    msg="theme -> 0x7f070001",
  )
  assert_true(
    @axml.ResTable::find_id(table, "string", "nope") is None,
    msg="未命中",
  )
  assert_true(
    @axml.ResTable::find_id(table, "nope", "x") is None,
    msg="未知类型",
  )
}

///|
/// 程序化：Res_value 各类型渲染（与 aapt2 dump resources 渲染对齐）。
test "arsc values: Res_value 全数据类型渲染" {
  let table = @axml.parse_arsc(ar_table_bytes())
  assert_eq(ar_fmt(table, 6, 0), "(null)", msg="TYPE_NULL")
  assert_eq(ar_fmt(table, 6, 1), "@string/app_name", msg="TYPE_REFERENCE")
  assert_eq(
    ar_fmt(table, 6, 2),
    "@string/hello (dynamic)",
    msg="TYPE_DYNAMIC_REFERENCE 如实标注",
  )
  assert_eq(ar_fmt(table, 6, 3), "1.500000", msg="TYPE_FLOAT")
  assert_eq(ar_fmt(table, 6, 4), "16.000000dp", msg="TYPE_DIMENSION")
  assert_eq(ar_fmt(table, 6, 5), "3.000000%", msg="TYPE_FRACTION")
  assert_eq(ar_fmt(table, 6, 6), "-5", msg="TYPE_INT_DEC")
  assert_eq(ar_fmt(table, 6, 7), "0xcafebabe", msg="TYPE_INT_HEX")
  assert_eq(ar_fmt(table, 6, 8), "true", msg="TYPE_INT_BOOLEAN")
  assert_eq(ar_fmt(table, 6, 9), "#80112233", msg="TYPE_INT_COLOR_ARGB8")
  assert_eq(ar_fmt(table, 6, 10), "#aabbcc", msg="TYPE_INT_COLOR_RGB8")
  assert_eq(ar_fmt(table, 6, 11), "#0abc", msg="TYPE_INT_COLOR_ARGB4")
  assert_eq(ar_fmt(table, 6, 12), "#abc", msg="TYPE_INT_COLOR_RGB4")
  assert_eq(
    ar_fmt(table, 6, 13),
    "(unknown type 0x2a=0x00000007)",
    msg="未知类型保留原值",
  )
  assert_eq(ar_fmt(table, 6, 14), "7", msg="compact 条目内联值")
  assert_eq(ar_fmt(table, 2, 0), "#ff112233", msg="color 类型")
  assert_eq(ar_fmt(table, 3, 0), "48.000000dp", msg="dimen 类型")
  assert_eq(ar_fmt(table, 5, 0), "42", msg="integer 类型")
}

///|
/// 程序化：compact 条目（FLAG_COMPACT）与复杂条目（bag）。
test "arsc entries: compact 与 bag" {
  let table = @axml.parse_arsc(ar_table_bytes())
  let compact_hit = match @axml.ResTable::lookup(table, ar_id(0x7f, 6, 14)) {
    Some(h) => h
    None => fail("compact 条目未命中")
  }
  assert_true((compact_hit.entry.flags & 8) != 0, msg="FLAG_COMPACT 置位")
  assert_eq(compact_hit.entry.key_name, "s0", msg="compact key 16 位解码")
  let bag_hit = match @axml.ResTable::lookup(table, ar_id(0x7f, 6, 15)) {
    Some(h) => h
    None => fail("bag 条目未命中")
  }
  match bag_hit.entry.value {
    Complex(bag) => {
      assert_eq(bag.parent, ar_id(0x7f, 7, 0), msg="bag parent")
      assert_eq(bag.maps.length(), 2, msg="map 数")
      assert_eq(bag.maps.at(0).name, ar_id(1, 0, 0), msg="ATTR_TYPE 内部 id")
      assert_true(bag.maps.at(0).value.data_type is IntDec, msg="map 值类型")
      assert_eq(
        bag.maps.at(1).value.data,
        ar_id(0x7f, 1, 1),
        msg="map 引用值",
      )
    }
    Simple(_) => fail("应为复杂条目")
  }
}

///|
/// 程序化：FLAG_SPARSE 与 FLAG_OFFSET16 语义（按 AOSP GetEntryOffset）。
test "arsc types: sparse 与 offset16 offsets" {
  let table = @axml.parse_arsc(ar_table_bytes())
  assert_eq(ar_fmt(table, 8, 0), "100", msg="sparse idx 0")
  assert_eq(ar_fmt(table, 8, 5), "500", msg="sparse idx 5（非连续）")
  assert_true(
    @axml.ResTable::lookup(table, ar_id(0x7f, 8, 3)) is None,
    msg="sparse 空洞",
  )
  assert_eq(ar_fmt(table, 9, 0), "1", msg="offset16 槽 0")
  assert_true(
    @axml.ResTable::lookup(table, ar_id(0x7f, 9, 1)) is None,
    msg="offset16 NO_ENTRY(0xFFFF)",
  )
  assert_eq(ar_fmt(table, 9, 2), "2", msg="offset16 槽 2")
}

///|
/// 程序化：resolve_id 跟随引用链 + bag 渲染 + 未命中降级。
test "arsc resolve_id: 引用链与降级" {
  let table = @axml.parse_arsc(ar_table_bytes())
  assert_eq(
    @axml.ResTable::resolve_id(table, ar_id(0x7f, 1, 0)),
    "MyApp",
    msg="string 直取值",
  )
  assert_eq(
    @axml.ResTable::resolve_id(table, ar_id(0x7f, 6, 1)),
    "MyApp",
    msg="引用链到最终值",
  )
  assert_eq(
    @axml.ResTable::resolve_id(table, ar_id(0x7f, 7, 1)),
    "@style/theme",
    msg="bag 渲染为引用名",
  )
  assert_eq(
    @axml.ResTable::resolve_id(table, ar_id(0x7f, 0, 0)),
    "@0x7f000000",
    msg="未命中保留原 id",
  )
}

///|
/// 程序化：RES_TABLE_LIBRARY_TYPE 解析使用 260 字节步长（AOSP ResTable_lib_entry）。
test "arsc library: 动态包映射步长 260" {
  let global = ar_pool_utf8(["v"])
  let type_pool = ar_pool_utf16(["t"])
  let key_pool = ar_pool_utf16(["k"])
  let lib_chunk = ar_library_chunk([(1, "lib.one"), (2, "lib.two")])
  let pkg = ar_package(127, "x", type_pool, key_pool, lib_chunk, 0)
  let body = ar_cat([global, pkg])
  let table = @axml.parse_arsc(
    ar_cat([ar_w2(0x0002), ar_w2(12), ar_w4(12 + body.length()), ar_w4(1), body]),
  )
  let p = table.packages.at(0)
  assert_eq(p.libraries.length(), 2, msg="两个 library 项")
  assert_eq(p.libraries.at(0).package_id, 1, msg="package_id 1")
  assert_eq(p.libraries.at(0).name, "lib.one", msg="lib.one")
  assert_eq(p.libraries.at(1).package_id, 2, msg="package_id 2")
  assert_eq(p.libraries.at(1).name, "lib.two", msg="lib.two")
}

///|
/// 程序化：resolve_attr_value 原始 0x7f…… 引用形式。
test "arsc attr: 0x7f…… 原始引用解析" {
  let table = @axml.parse_arsc(ar_table_bytes())
  let res = @axml.resolve_attr_value(
    ar_doc(),
    table,
    ar_attr(Reference, ar_id(0x7f, 1, 0), None),
  )
  assert_eq(res.text, "MyApp", msg="人类可读值")
  assert_true(res.id is Some(_), msg="id 已识别")
  assert_true(res.origin is FromId, msg="来自原始 id")
}

///|
/// 程序化：resolve_attr_value @string/xxx 文本形式。
test "arsc attr: @string/xxx 文本形式解析" {
  let table = @axml.parse_arsc(ar_table_bytes())
  let res = @axml.resolve_attr_value(
    ar_doc(),
    table,
    ar_attr(String, 0U, Some("@string/app_name")),
  )
  assert_eq(res.text, "MyApp", msg="人类可读值")
  assert_true(res.origin is FromName, msg="来自名字")
  let res2 = @axml.resolve_attr_value(
    ar_doc(),
    table,
    ar_attr(Null, 0U, Some("@string/hello")),
  )
  assert_eq(res2.text, "Hello", msg="Null 类型 + 文本引用同样解析")
  let res3 = @axml.resolve_attr_value(
    ar_doc(),
    table,
    ar_attr(Reference, ar_id(0x7f, 1, 1), Some("@0x7f010001")),
  )
  assert_eq(res3.text, "Hello", msg="@0x… 十六进制文本形式")
  assert_true(res3.origin is FromId, msg="十六进制文本归入 FromId")
}

///|
/// 程序化：resolve_attr_value 字面量与缺口降级（不抛错）。
test "arsc attr: 字面量与缺口降级" {
  let table = @axml.parse_arsc(ar_table_bytes())
  let lit = @axml.resolve_attr_value(
    ar_doc(),
    table,
    ar_attr(IntBoolean, 1U, None),
  )
  assert_eq(lit.text, "true", msg="布尔字面量")
  assert_true(lit.origin is Literal, msg="Literal")
  let missing = @axml.resolve_attr_value(
    ar_doc(),
    table,
    ar_attr(Reference, ar_id(1, 3, 298), None),
  )
  assert_eq(missing.text, "@0x0103012a", msg="表外 id 保留原文本")
  assert_true(missing.origin is Unresolved(_), msg="Unresolved")
  let bad_name = @axml.resolve_attr_value(
    ar_doc(),
    table,
    ar_attr(Null, 0U, Some("@string/missing")),
  )
  assert_true(bad_name.origin is Unresolved(_), msg="名字未命中降级")
  let bad_str = @axml.resolve_attr_value(
    ar_doc(),
    table,
    ar_attr(String, 99U, None),
  )
  assert_true(
    bad_str.origin is Unresolved(_),
    msg="字符串索引越界降级",
  )
  let dynamic = @axml.resolve_attr_value(
    ar_doc(),
    table,
    ar_attr(Unknown(7), ar_id(0x7f, 1, 1), None),
  )
  assert_true(
    dynamic.origin is Unresolved(_),
    msg="动态引用如实标注为未改写",
  )
  assert_eq(
    dynamic.text,
    "Hello (dynamic)",
    msg="动态引用仍给出可读值",
  )
}

///|
/// 真实样本交叉核对：受控构建样本 fx-multidex-v2v3.apk -> resources.arsc
/// （1052 字节，fixture_fx_multidex_arsc() 内嵌于 fixtures_test.mbt，
/// 字节来自 tests/fixtures/fx-multidex.resources.arsc；aapt2 dump resources
/// 黄金为 golden_fx_multidex_arsc()）。断言逐条对应黄金：
/// bool/fx_flag 0x7f010000=true、color/fx_tint 0x7f020000=#ff2255aa、
/// string/app_name 0x7f030000="Fx Multidex"（zh="Fx 多维"）、
/// string/fx_action 0x7f030001="press"（aapt2 黄金字符串带引号，本库输出裸串）。
test "arsc real: fx-multidex 受控构建样本交叉核对" {
  let table = @axml.parse_arsc(fixture_fx_multidex_arsc())
  assert_eq(table.package_count, 1, msg="packageCount=1")
  let pkg = table.packages.at(0)
  assert_eq(pkg.name, "com.fx.multidex", msg="包名")
  assert_eq(pkg.id, 127, msg="包 id 0x7f")
  assert_eq(pkg.types.length(), 3, msg="bool/color/string 三个 typeSpec")
  let flag = match @axml.ResTable::lookup(table, ar_id(0x7f, 1, 0)) {
    Some(h) => h
    None => fail("bool/fx_flag 未命中")
  }
  assert_eq(flag.type_name, "bool", msg="类型名")
  assert_eq(flag.entry_name, "fx_flag", msg="条目名")
  assert_eq(
    @axml.ResTable::format_value(table, ar_value_of(flag.entry)),
    "true",
    msg="bool 值",
  )
  let tint = match @axml.ResTable::lookup(table, ar_id(0x7f, 2, 0)) {
    Some(h) => h
    None => fail("color/fx_tint 未命中")
  }
  assert_eq(tint.entry_name, "fx_tint", msg="条目名")
  assert_eq(
    @axml.ResTable::format_value(table, ar_value_of(tint.entry)),
    "#ff2255aa",
    msg="color 值",
  )
  let name_hits = @axml.ResTable::lookup_all(table, ar_id(0x7f, 3, 0))
  assert_eq(name_hits.length(), 2, msg="app_name 默认 + zh 两配置")
  assert_eq(name_hits.at(0).entry_name, "app_name", msg="条目名")
  assert_true(name_hits.at(0).config.is_default(), msg="首选默认配置")
  assert_eq(
    @axml.ResTable::format_value(table, ar_value_of(name_hits.at(0).entry)),
    "Fx Multidex",
    msg="默认值",
  )
  assert_eq(name_hits.at(1).config.language, "zh", msg="zh 配置")
  assert_eq(
    @axml.ResTable::format_value(table, ar_value_of(name_hits.at(1).entry)),
    "Fx 多维",
    msg="zh 值",
  )
  assert_eq(
    @axml.ResTable::resolve_id(table, ar_id(0x7f, 3, 1)),
    "press",
    msg="fx_action 值",
  )
  assert_eq(
    @axml.ResTable::find_id(table, "string", "app_name"),
    Some(ar_id(0x7f, 3, 0)),
    msg="名字反查 id",
  )
}

///|
/// 真实样本衔接：framework-res.apk -> AndroidManifest.xml（fixtures_test.mbt
/// 内嵌的 fixture_framework_res_manifest）。本用例消费该
/// fixture 冒烟 @axml.parse（AXML 链），与 resources.arsc 解析链共享真实样本证据链；
/// 同时使该 fixture 在黑盒测试包内被引用（消除 unused 告警）。
test "arsc real: framework-res 清单可解析" {
  let doc = @axml.parse(fixture_framework_res_manifest())
  assert_true(doc.elements().length() > 0, msg="清单含元素")
  assert_true(
    @axml.parse_arsc(ar_fixture_base_arsc()).packages.is_empty(),
    msg="arsc 链同轮可用",
  )
}

///|
/// 程序化：畸形输入——截断/外层头部/尾随垃圾。
test "arsc malformed: 截断/头部/尾随垃圾" {
  let full = ar_table_bytes()
  let cut = Bytes::from_array(full[0:20].to_array())
  let e1 = ar_arsc_err(cut)
  guard e1 is Eof(_) else { fail("截断应报 Eof") }
  let e2 = ar_arsc_err(ar_cat([ar_w2(0x0003), ar_w2(8), ar_w4(12), ar_w4(0)]))
  guard e2 is BadChunk(0, 3) else { fail("非 RES_TABLE_TYPE 应报 BadChunk") }
  let e3 = ar_arsc_err(ar_cat([ar_w2(0x0002), ar_w2(10), ar_w4(12), ar_w4(0)]))
  guard e3 is BadHeader(0, 10) else {
    fail("headerSize 污染应报 BadHeader")
  }
  let e4 = ar_arsc_err(ar_cat([full, b"\x00"]))
  guard e4 is BadHeader(4, _) else { fail("尾随垃圾应报 BadHeader") }
}

///|
/// 回归：截断点落在字符串池/条目载荷内部时，外层 `size` 仍声称完整长度；
/// 必须在入口按 `size > 输入长度` 拒绝，绝不能越界读取或 panic。
test "arsc malformed: 任意截断点都报 ArscError 而非 panic" {
  let src = fixture_fx_multidex_arsc()
  let mut cut = 0
  while cut < src.length() {
    assert_true(
      ar_raises(fx_cut(src, cut)),
      msg="截断到 \{cut} 字节应报 ArscError",
    )
    cut = cut + 1
  }
}

///|
test "arsc malformed: 外层 size 超出输入时报 Eof" {
  let src = fixture_fx_multidex_arsc()
  let inflated = fx_set_u32(src, 4, src.length() + 4)
  let e = ar_arsc_err(inflated)
  guard e is Eof(off) else { fail("外层 size 超长应报 Eof") }
  assert_eq(off, src.length())
}

///|
/// 程序化：畸形输入——缺全局池/超额包/继承包/无前置 spec。
test "arsc malformed: 资源表语义错误" {
  let global = ar_pool_utf8(["v"])
  // 缺全局池：只放一个包 chunk。
  let pkg_only = ar_package(
    127,
    "x",
    ar_pool_utf8(["t"]),
    ar_pool_utf8(["k"]),
    b"",
    0,
  )
  let body1 = ar_cat([pkg_only])
  let t1 = ar_cat([
    ar_w2(0x0002),
    ar_w2(12),
    ar_w4(12 + body1.length()),
    ar_w4(1),
    body1,
  ])
  let e1 = ar_arsc_err(t1)
  guard e1 is BadPool(_, _) else { fail("缺全局池应报 BadPool") }
  // 超额包：packageCount=0 但含一个包。
  let pkg2 = ar_package(
    127,
    "x",
    ar_pool_utf8(["t"]),
    ar_pool_utf8(["k"]),
    b"",
    0,
  )
  let body2 = ar_cat([global, pkg2])
  let t2 = ar_cat([
    ar_w2(0x0002),
    ar_w2(12),
    ar_w4(12 + body2.length()),
    ar_w4(0),
    body2,
  ])
  let e2 = ar_arsc_err(t2)
  guard e2 is BadTable(_, _) else { fail("超额包应报 BadTable") }
  // 继承包：typeStrings=0。
  let inherit_pkg = ar_cat([
    ar_w2(0x0200),
    ar_w2(288),
    ar_w4(288),
    ar_w4(127),
    ar_utf16z("x"),
    ar_w4(0),
    ar_w4(0),
    ar_w4(0),
    ar_w4(0),
    ar_w4(0),
  ])
  let body3 = ar_cat([global, inherit_pkg])
  let t3 = ar_cat([
    ar_w2(0x0002),
    ar_w2(12),
    ar_w4(12 + body3.length()),
    ar_w4(1),
    body3,
  ])
  let e3 = ar_arsc_err(t3)
  guard e3 is BadTable(_, _) else { fail("继承包应报 BadTable") }
  // type chunk 无前置 spec。
  let lone_type = ar_type_chunk(
    1,
    0,
    1,
    ar_config64(0, 0, "", "", 0, 0, 0, 0),
    ar_slots([0]),
    ar_simple(0, 0x10, 1U),
  )
  let pkg4 = ar_package(
    127,
    "x",
    ar_pool_utf8(["t"]),
    ar_pool_utf8(["k"]),
    lone_type,
    0,
  )
  let body4 = ar_cat([global, pkg4])
  let t4 = ar_cat([
    ar_w2(0x0002),
    ar_w2(12),
    ar_w4(12 + body4.length()),
    ar_w4(1),
    body4,
  ])
  let e4 = ar_arsc_err(t4)
  guard e4 is BadTable(_, _) else { fail("无前置 spec 应报 BadTable") }
}

///|
/// 程序化：type chunk 内部边界（entriesStart 未对齐 / entry offset 越界）。
test "arsc malformed: type chunk 边界" {
  let global = ar_pool_utf8(["v"])
  let type_pool = ar_pool_utf8(["t"])
  let key_pool = ar_pool_utf8(["k"])
  let config = ar_config64(0, 0, "", "", 0, 0, 0, 0)
  let header_size = 20 + config.length()
  // entriesStart 未对齐：slots 后插 2 字节填充。
  let body1 = ar_cat([
    ar_byte(1),
    ar_byte(0),
    ar_w2(0),
    ar_w4(1),
    ar_w4(header_size + 4 + 2),
    config,
    ar_w4(0),
    b"\x00\x00",
    ar_simple(0, 0x10, 1U),
  ])
  let bad_type1 = ar_cat([
    ar_w2(0x0201),
    ar_w2(header_size),
    ar_w4(8 + body1.length()),
    body1,
  ])
  let pkg1 = ar_package(
    127,
    "x",
    type_pool,
    key_pool,
    ar_cat([ar_spec(1, [0U]), bad_type1]),
    0,
  )
  let body_t1 = ar_cat([global, pkg1])
  let t1 = ar_cat([
    ar_w2(0x0002),
    ar_w2(12),
    ar_w4(12 + body_t1.length()),
    ar_w4(1),
    body_t1,
  ])
  let e1 = ar_arsc_err(t1)
  guard e1 is BadTable(_, _) else {
    fail("entriesStart 未对齐应报 BadTable")
  }
  // entry offset 越界。
  let body2 = ar_cat([
    ar_byte(1),
    ar_byte(0),
    ar_w2(0),
    ar_w4(1),
    ar_w4(header_size + 4),
    config,
    ar_w4(1000),
    ar_simple(0, 0x10, 1U),
  ])
  let bad_type2 = ar_cat([
    ar_w2(0x0201),
    ar_w2(header_size),
    ar_w4(8 + body2.length()),
    body2,
  ])
  let pkg2 = ar_package(
    127,
    "x",
    type_pool,
    key_pool,
    ar_cat([ar_spec(1, [0U]), bad_type2]),
    0,
  )
  let body_t2 = ar_cat([global, pkg2])
  let t2 = ar_cat([
    ar_w2(0x0002),
    ar_w2(12),
    ar_w4(12 + body_t2.length()),
    ar_w4(1),
    body_t2,
  ])
  let e2 = ar_arsc_err(t2)
  guard e2 is BadTable(_, _) else { fail("entry offset 越界应报 BadTable") }
}
