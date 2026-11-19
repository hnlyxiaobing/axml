///|
/// `encode_arsc` 值级回编（W9）黑盒测试。往返律：
/// `parse_arsc(encode_arsc(t))` 与规范化后的 `t` 语义等价（同包/类型/条目与值
/// 内容、键名池/类型池/全局池字符串一致），不要求字节级一致（dense 写出口径）。
/// 拒绝路径：sparse/offset16/compact 布局 → `BadTable`（复用既有变体，不新增）。

///|
/// 8 位小写十六进制（本地指纹用，`format_value` 的 aapt2 渲染已含类型+数据）。
fn w9_hex8(v : UInt32) -> String {
  let digits = "0123456789abcdef"
  let mut s = ""
  let mut x = v
  while x != 0U {
    let d = (x & 15U).reinterpret_as_int()
    s = digits[d:d + 1].to_owned() + s
    x = x >> 4
  }
  while s.length() < 8 {
    s = "0" + s
  }
  s
}

///|
/// 条目取值规范指纹（roundtrip 对比用）：简单值 `S:format`；复杂 bag
/// `C:parenthex:count:[namehex=format;...]`（name 用本地 hex，值用 format_value）。
fn w9_value_fp(table : @axml.ResTable, value : @axml.ResEntryValue) -> String {
  match value {
    Simple(v) => "S:\{@axml.ResTable::format_value(table, v)}"
    Complex(bag) => {
      let builder = StringBuilder(capacity=64)
      builder.write_string("C:\{w9_hex8(bag.parent)}:\{bag.maps.length()}:")
      for m in bag.maps {
        builder.write_string(
          "\{w9_hex8(m.name)}=\{@axml.ResTable::format_value(table, m.value)};",
        )
      }
      builder.to_string()
    }
  }
}

///|
/// 表级规范指纹（roundtrip 对比用）：逐包 + 逐 type 逐条目。
fn w9_table_fp(table : @axml.ResTable) -> String {
  let builder = StringBuilder(capacity=256)
  builder.write_string("pool=\{table.global_pool.strings.length()}:")
  for p in table.packages {
    builder.write_string(
      "\n[pkg id=\{p.id} name=\{p.name} tid=\{p.type_id_offset} types=\{p.types.length()} libs=\{p.libraries.length()}]",
    )
    for t in p.types {
      builder.write_string(
        "\n  [spec id=\{t.id} entryCount=\{t.entry_count} flags=\{t.spec_flags.length()}]",
      )
      for cfg in t.configs {
        builder.write_string(
          "\n    [cfg id=\{cfg.id} flags=\{cfg.flags} entries=\{cfg.entries.length()} lang=\{cfg.config.language}]",
        )
        for e in cfg.entries {
          match e {
            None => builder.write_string("\n      None")
            Some(en) =>
              builder.write_string(
                "\n      \{en.key_name}=\{w9_value_fp(table, en.value)}",
              )
          }
        }
      }
    }
  }
  builder.to_string()
}

///|
/// 构造纯 dense 程序化资源表（供 W9 往返测试，避开 sparse/offset16/compact）。
/// 包 0x7f "com.w9.test"，类型池 ["string","color","bool","style"]：
/// - string/app_name 默认 "Hello" + zh-rCN "你好"（两配置，dense 双槽）
/// - string/bye "Bye"
/// - color/tint "#ff2255aa"
/// - bool/flag "true"
/// - style/theme 为 bag（parent=0，含 ATTR_TYPE 与 ATTR_BAG_FLAGS 两 map）
/// 含一个 library chunk（动态包 0x02 "dynamic.pkg"）。
fn w9_table_bytes() -> Bytes {
  // 全局池承载 String 型值（Res_value.data 为全局池下标）。
  // 注：ar_pool_utf8 仅支持 ASCII（逐字符单字节），非 ASCII 由 W9-4 真实
  // fixture 经 encode_string_pool 正确 UTF-8 往返覆盖。
  let global = ar_pool_utf8(["Hello", "World", "Bye"])
  let type_pool = ar_pool_utf16(["string", "color", "bool", "style"])
  let key_pool = ar_pool_utf16(["app_name", "bye", "tint", "flag", "theme"])
  let default_cfg = ar_config64(0, 0, "", "", 0, 0, 0, 0)
  let zh_cfg = ar_config64(0, 0, "zh", "CN", 0, 0, 0, 0)
  // string 类型（id 1）：app_name 默认 "Hello" + zh "World"（双槽），bye "Bye"
  let str_spec = ar_spec(1, [0U, 0U, 0U])
  let str_default = ar_type_chunk(
    1,
    0,
    2,
    default_cfg,
    ar_slots([0, 16]),
    ar_cat([ar_simple(0, 0x03, 0U), ar_simple(1, 0x03, 2U)]),
  )
  let str_zh = ar_type_chunk(
    1,
    0,
    1,
    zh_cfg,
    ar_slots([0]),
    ar_simple(0, 0x03, 1U),
  )
  // color（id 2）：tint 默认
  let color_spec = ar_spec(2, [0U])
  let color_chunk = ar_type_chunk(
    2,
    0,
    1,
    default_cfg,
    ar_slots([0]),
    ar_simple(2, 0x1c, 4278255530U),
  )
  // bool（id 3）：flag 默认
  let bool_spec = ar_spec(3, [0U])
  let bool_chunk = ar_type_chunk(
    3,
    0,
    1,
    default_cfg,
    ar_slots([0]),
    ar_simple(3, 0x12, 1U),
  )
  // style（id 4）：theme bag
  let style_spec = ar_spec(4, [0U])
  let theme_bag = ar_bag(4, 0U, [
    ar_map(0x01000000, 0x10, 0x0300U),
    ar_map(0x01000001, 0x12, 1U),
  ])
  let style_chunk = ar_type_chunk(
    4,
    0,
    1,
    default_cfg,
    ar_slots([0]),
    theme_bag,
  )
  let library = ar_library_chunk([(2, "dynamic.pkg")])
  let children = ar_cat([
    str_spec, str_default, str_zh, color_spec, color_chunk, bool_spec, bool_chunk,
    style_spec, style_chunk, library,
  ])
  let pkg = ar_package(127, "com.w9.test", type_pool, key_pool, children, 0)
  let body = ar_cat([global, pkg])
  ar_cat([ar_w2(0x0002), ar_w2(12), ar_w4(12 + body.length()), ar_w4(1), body])
}

///|
/// 构造仅含非空全局池、无包的表字节（外层头 + 全局池）。
fn w9_global_only_bytes() -> Bytes {
  let pool = ar_pool_utf8(["globalA", "globalB"])
  let header = ar_cat([
    ar_w2(0x0002),
    ar_w2(12),
    ar_w4(12 + pool.length()),
    ar_w4(0),
  ])
  ar_cat([header, pool])
}

///|
/// W9-1：空资源表往返——`encode_arsc(parse_arsc(base))` 与 base 逐字节一致。
test "W9-1: 空资源表 encode_arsc 往返逐字节一致" {
  let base = ar_fixture_base_arsc()
  let t = @axml.parse_arsc(base)
  let out = @axml.encode_arsc(t)
  assert_eq(out.length(), base.length(), msg="长度一致")
  for i in 0..<base.length() {
    assert_eq(out.at(i), base.at(i), msg="字节 \{i} 一致")
  }
  let t2 = @axml.parse_arsc(out)
  assert_eq(t2.package_count, 0, msg="packageCount=0")
  assert_eq(t2.packages.length(), 0, msg="无包")
}

///|
/// W9-1：非空全局池 + 无包表往返语义等价。
test "W9-1: 全局池表 encode_arsc 往返语义等价" {
  let t = @axml.parse_arsc(w9_global_only_bytes())
  assert_eq(t.package_count, 0, msg="packageCount=0")
  assert_eq(
    t.global_pool.strings,
    ["globalA", "globalB"],
    msg="全局池字符串",
  )
  let out = @axml.encode_arsc(t)
  let t2 = @axml.parse_arsc(out)
  assert_eq(t2.package_count, 0, msg="往返后 packageCount=0")
  assert_eq(
    t2.global_pool.strings,
    ["globalA", "globalB"],
    msg="往返后全局池字符串",
  )
}

///|
/// W9-2：dense 简单值表往返语义等价（包/类型/条目/值全字段）。
test "W9-2: dense 简单值表 encode_arsc 往返语义等价" {
  let t = @axml.parse_arsc(w9_table_bytes())
  let out = @axml.encode_arsc(t)
  let t2 = @axml.parse_arsc(out)
  assert_eq(w9_table_fp(t2), w9_table_fp(t), msg="往返规范指纹一致")
  let hit = match @axml.ResTable::lookup(t2, ar_id(0x7f, 1, 0)) {
    Some(h) => h
    None => fail("app_name 未命中")
  }
  assert_eq(hit.entry_name, "app_name", msg="条目名")
  assert_eq(
    @axml.ResTable::format_value(t2, ar_value_of(hit.entry)),
    "Hello",
    msg="默认值",
  )
  let all = @axml.ResTable::lookup_all(t2, ar_id(0x7f, 1, 0))
  assert_eq(all.length(), 2, msg="app_name 两配置")
  assert_eq(all.at(1).config.language, "zh", msg="zh 配置保留")
  assert_eq(
    @axml.ResTable::format_value(t2, ar_value_of(all.at(1).entry)),
    "World",
    msg="zh 值",
  )
}

///|
/// W9-3：bag + library + 配置变体往返语义等价。
test "W9-3: bag/library/config 变体 encode_arsc 往返" {
  let t = @axml.parse_arsc(w9_table_bytes())
  let out = @axml.encode_arsc(t)
  let t2 = @axml.parse_arsc(out)
  let theme = match @axml.ResTable::lookup(t2, ar_id(0x7f, 4, 0)) {
    Some(h) => h
    None => fail("theme 未命中")
  }
  match theme.entry.value {
    Complex(bag) => {
      assert_eq(bag.parent, 0U, msg="bag parent=0")
      assert_eq(bag.maps.length(), 2, msg="两个 map")
      assert_eq(bag.maps.at(0).name, 0x01000000, msg="ATTR_TYPE name")
      assert_eq(bag.maps.at(0).value.data, 0x0300, msg="ATTR_TYPE data 保留")
      assert_eq(bag.maps.at(1).name, 0x01000001, msg="ATTR_BAG_FLAGS name")
    }
    Simple(_) => fail("theme 应为 bag")
  }
  let pkg = t2.packages.at(0)
  assert_eq(pkg.libraries.length(), 1, msg="一个 library")
  assert_eq(pkg.libraries.at(0).package_id, 2, msg="动态包 id")
  assert_eq(pkg.libraries.at(0).name, "dynamic.pkg", msg="动态包名")
  assert_eq(w9_table_fp(t2), w9_table_fp(t), msg="往返规范指纹一致")
}

///|
/// W9-3：sparse / offset16 / compact 布局显式拒绝（BadTable，不新增变体）。
test "W9-3: sparse/offset16/compact 布局 encode_arsc 拒绝" {
  let t = @axml.parse_arsc(ar_table_bytes())
  let raised = try {
    ignore(@axml.encode_arsc(t))
    false
  } catch {
    err =>
      match err {
        @axml.ArscError::BadTable(_) => true
        _ => false
      }
  }
  assert_true(raised, msg="含不可逆布局的表应报 BadTable")
}

///|
/// W9-4：真实 AXML/ARSC fixture 往返语义等价（fx-multidex，dense 真实样本）。
test "W9-4: fx-multidex 真实资源表 encode_arsc 往返" {
  let src = fixture_fx_multidex_arsc()
  let t = @axml.parse_arsc(src)
  let out = @axml.encode_arsc(t)
  let t2 = @axml.parse_arsc(out)
  assert_eq(t2.package_count, t.package_count, msg="packageCount")
  assert_eq(t2.packages.length(), t.packages.length(), msg="包数")
  let p1 = t.packages.at(0)
  let p2 = t2.packages.at(0)
  assert_eq(p2.name, p1.name, msg="包名")
  assert_eq(p2.id, p1.id, msg="包 id")
  assert_eq(p2.type_pool.strings, p1.type_pool.strings, msg="类型池")
  assert_eq(p2.key_pool.strings, p1.key_pool.strings, msg="键名池")
  assert_eq(p2.types.length(), p1.types.length(), msg="类型数")
  let flag = match @axml.ResTable::lookup(t2, ar_id(0x7f, 1, 0)) {
    Some(h) => h
    None => fail("bool/fx_flag 未命中")
  }
  assert_eq(
    @axml.ResTable::format_value(t2, ar_value_of(flag.entry)),
    "true",
    msg="bool 值",
  )
  let name_hits = @axml.ResTable::lookup_all(t2, ar_id(0x7f, 3, 0))
  assert_eq(name_hits.length(), 2, msg="app_name 两配置")
  assert_eq(name_hits.at(1).config.language, "zh", msg="zh 配置")
  assert_eq(
    @axml.ResTable::format_value(t2, ar_value_of(name_hits.at(1).entry)),
    "Fx 多维",
    msg="zh 值",
  )
  assert_eq(w9_table_fp(t2), w9_table_fp(t), msg="往返规范指纹一致")
}

///|
/// W9-5 辅助（W9 修复）：逐字段比较两个 `ResConfig` 的已解码 qualifier
/// （`raw` 为序列化镜像产物，不参与语义等价）。
fn w9_cfg_eq(
  got : @axml.ResConfig,
  want : @axml.ResConfig,
  tag : String,
) -> Unit raise {
  assert_eq(got.size, want.size, msg="\{tag}: size")
  assert_eq(got.mcc, want.mcc, msg="\{tag}: mcc")
  assert_eq(got.mnc, want.mnc, msg="\{tag}: mnc")
  assert_eq(got.language, want.language, msg="\{tag}: language")
  assert_eq(got.country, want.country, msg="\{tag}: country")
  assert_eq(got.orientation, want.orientation, msg="\{tag}: orientation")
  assert_eq(got.touchscreen, want.touchscreen, msg="\{tag}: touchscreen")
  assert_eq(got.density, want.density, msg="\{tag}: density")
  assert_eq(got.keyboard, want.keyboard, msg="\{tag}: keyboard")
  assert_eq(got.navigation, want.navigation, msg="\{tag}: navigation")
  assert_eq(got.input_flags, want.input_flags, msg="\{tag}: inputFlags")
  assert_eq(got.screen_width, want.screen_width, msg="\{tag}: screenWidth")
  assert_eq(got.screen_height, want.screen_height, msg="\{tag}: screenHeight")
  assert_eq(got.sdk_version, want.sdk_version, msg="\{tag}: sdkVersion")
  assert_eq(got.screen_layout, want.screen_layout, msg="\{tag}: screenLayout")
  assert_eq(got.ui_mode, want.ui_mode, msg="\{tag}: uiMode")
  assert_eq(
    got.smallest_screen_width_dp,
    want.smallest_screen_width_dp,
    msg="\{tag}: smallestScreenWidthDp",
  )
  assert_eq(got.screen_width_dp, want.screen_width_dp, msg="\{tag}: widthDp")
  assert_eq(got.screen_height_dp, want.screen_height_dp, msg="\{tag}: heightDp")
  assert_eq(got.locale_script, want.locale_script, msg="\{tag}: localeScript")
  assert_eq(got.color_mode, want.color_mode, msg="\{tag}: colorMode")
}

///|
/// W9-5 辅助：构造单包单类型单条目、给定配置的构造型 `ResTable`
/// （条目值为 IntDec，避免全局池耦合；配置 raw 为空 = 构造型）。
fn w9_struct_table(cfg : @axml.ResConfig) -> @axml.ResTable {
  let entry : @axml.ResEntry = {
    key: 0,
    key_name: "solo",
    flags: 0,
    value: @axml.ResEntryValue::Simple({
      data_type: @axml.ResDataType::IntDec,
      data: 42U,
    }),
  }
  let pkg : @axml.ResPackage = {
    id: 0x7f,
    name: "w9.cfg",
    type_id_offset: 0,
    type_pool: mr_pool(["string"]),
    key_pool: mr_pool(["solo"]),
    types: [
      {
        id: 1,
        types_count: 1,
        entry_count: 1,
        spec_flags: [0x40000000U],
        configs: [{ id: 1, flags: 0, config: cfg, entries: [Some(entry)], }],
      },
    ],
    libraries: [],
  }
  { global_pool: mr_pool([]), packages: [pkg], package_count: 1, }
}

///|
/// W9-5（W9 修复）：`from_qualifiers` 构造型配置（raw 为空）回编成功，
/// `parse_arsc` 后已解码 qualifier 字段逐字段等价；zh 值经 `lookup_with` 命中。
test "W9-5: 构造型配置 encode_arsc 往返字段等价" {
  let def = @axml.ResConfig::from_qualifiers("") catch { _ => abort("def") }
  let zh = @axml.ResConfig::from_qualifiers("zh-rCN") catch { _ => abort("zh") }
  let rich = @axml.ResConfig::from_qualifiers_ext(
    "sw600dp-w960dp-h540dp-land-night-xhdpi-v21-b+fil",
  ) catch {
    _ => abort("rich")
  }
  // —— 默认 + zh 双配置构造型表 ——
  let entry_def : @axml.ResEntry = {
    key: 0,
    key_name: "solo",
    flags: 0,
    value: @axml.ResEntryValue::Simple({
      data_type: @axml.ResDataType::IntDec,
      data: 1U,
    }),
  }
  let entry_zh : @axml.ResEntry = {
    key: 0,
    key_name: "solo",
    flags: 0,
    value: @axml.ResEntryValue::Simple({
      data_type: @axml.ResDataType::IntDec,
      data: 2U,
    }),
  }
  let pkg : @axml.ResPackage = {
    id: 0x7f,
    name: "w9.cfg",
    type_id_offset: 0,
    type_pool: mr_pool(["string"]),
    key_pool: mr_pool(["solo"]),
    types: [
      {
        id: 1,
        types_count: 2,
        entry_count: 1,
        spec_flags: [0x40000000U],
        configs: [
          { id: 1, flags: 0, config: def, entries: [Some(entry_def)], },
          { id: 1, flags: 0, config: zh, entries: [Some(entry_zh)], },
        ],
      },
    ],
    libraries: [],
  }
  let dual : @axml.ResTable = {
    global_pool: mr_pool([]),
    packages: [pkg],
    package_count: 1,
  }
  let out = @axml.encode_arsc(dual)
  let t2 = @axml.parse_arsc(out)
  let hits = @axml.ResTable::lookup_all(t2, ar_id(0x7f, 1, 0))
  assert_eq(hits.length(), 2, msg="双配置均保留")
  w9_cfg_eq(hits.at(0).config, def, "默认配置")
  w9_cfg_eq(hits.at(1).config, zh, "zh-rCN 配置")
  // zh-rCN 设备经 lookup_with 命中 zh-rCN 条目（zh-rCN 配置要求设备同语言同地区）
  let zh_dev = @axml.ResConfig::from_qualifiers("zh-rCN") catch {
    _ => abort("dev")
  }
  match t2.lookup_with(ar_id(0x7f, 1, 0), zh_dev) {
    None => fail("lookup_with 应命中 zh")
    Some(hit) =>
      match hit.entry.value {
        Simple(v) => assert_eq(v.data, 2U, msg="zh 条目值（IntDec 2）")
        Complex(_) => fail("solo 应为简单条目")
      }
  }
  // —— 富限定符构造型配置（尺寸/density/night/v21/BCP47 三字母）——
  let t3 = @axml.parse_arsc(@axml.encode_arsc(w9_struct_table(rich)))
  let hits3 = @axml.ResTable::lookup_all(t3, ar_id(0x7f, 1, 0))
  assert_eq(hits3.length(), 1, msg="富配置保留")
  w9_cfg_eq(hits3.at(0).config, rich, "富限定符配置")
  assert_true(
    hits3.at(0).config.matches(rich),
    msg="回读配置匹配同构造型设备",
  )
}

///|
/// W9-5：config size 边界 4/63/64/65 均可回编且 size 字段自描述回读；
/// size < 4 仍报 `BadTable`；`raw.length() >= size` 时取前 size 字节。
test "W9-5: config size 边界（4/63/64/65）与拒绝路径" {
  // —— 63/64/65 边界：raw 为空 -> 字段序列化 + 零填充（全部已解码字段落盘）——
  for sz in [63, 64, 65] {
    let cfg : @axml.ResConfig = {
      size: sz,
      mcc: 310,
      mnc: 4,
      language: "en",
      country: "US",
      orientation: 1,
      touchscreen: 3,
      density: 480,
      keyboard: 2,
      navigation: 1,
      input_flags: 2,
      screen_width: 1080,
      screen_height: 1920,
      sdk_version: 21,
      screen_layout: 0x03,
      ui_mode: 0x20,
      smallest_screen_width_dp: 600,
      screen_width_dp: 960,
      screen_height_dp: 540,
      locale_script: "Latn",
      color_mode: 0x0C,
      raw: Bytes::make(0, b'\x00'),
    }
    let t = @axml.parse_arsc(@axml.encode_arsc(w9_struct_table(cfg)))
    let hits = @axml.ResTable::lookup_all(t, ar_id(0x7f, 1, 0))
    assert_eq(hits.length(), 1, msg="size=\{sz} 条目保留")
    w9_cfg_eq(hits.at(0).config, cfg, "size=\{sz}")
  }
  // —— size=4 边界：仅 size 字段落盘，其余已解码字段解析恒为 0 ——
  let sz4 : @axml.ResConfig = {
    size: 4,
    mcc: 0,
    mnc: 0,
    language: "",
    country: "",
    orientation: 0,
    touchscreen: 0,
    density: 0,
    keyboard: 0,
    navigation: 0,
    input_flags: 0,
    screen_width: 0,
    screen_height: 0,
    sdk_version: 0,
    screen_layout: 0,
    ui_mode: 0,
    smallest_screen_width_dp: 0,
    screen_width_dp: 0,
    screen_height_dp: 0,
    locale_script: "",
    color_mode: 0,
    raw: Bytes::make(0, b'\x00'),
  }
  let t4 = @axml.parse_arsc(@axml.encode_arsc(w9_struct_table(sz4)))
  let hits4 = @axml.ResTable::lookup_all(t4, ar_id(0x7f, 1, 0))
  assert_eq(hits4.length(), 1, msg="size=4 条目保留")
  w9_cfg_eq(hits4.at(0).config, sz4, "size=4")
  // —— size < 4 拒绝 ——
  let tiny : @axml.ResConfig = {
    size: 3,
    mcc: 0,
    mnc: 0,
    language: "",
    country: "",
    orientation: 0,
    touchscreen: 0,
    density: 0,
    keyboard: 0,
    navigation: 0,
    input_flags: 0,
    screen_width: 0,
    screen_height: 0,
    sdk_version: 0,
    screen_layout: 0,
    ui_mode: 0,
    smallest_screen_width_dp: 0,
    screen_width_dp: 0,
    screen_height_dp: 0,
    locale_script: "",
    color_mode: 0,
    raw: Bytes::make(0, b'\x00'),
  }
  let raised = try {
    ignore(@axml.encode_arsc(w9_struct_table(tiny)))
    false
  } catch {
    err =>
      match err {
        @axml.ArscError::BadTable(_) => true
        _ => false
      }
  }
  assert_true(raised, msg="size<4 应报 BadTable")
  // —— raw.length() >= size：取前 size 字节（多出的尾部不回写）——
  let full_raw : Array[Byte] = []
  for i in 0..<70 {
    full_raw.push(((i * 7 + 1) & 0xFF).to_byte())
  }
  // 前 4 字节手工写 size=64（自描述），保证回读 size 一致
  full_raw[0] = b'\x40'
  full_raw[1] = b'\x00'
  full_raw[2] = b'\x00'
  full_raw[3] = b'\x00'
  let over : @axml.ResConfig = {
    size: 64,
    mcc: 0,
    mnc: 0,
    language: "",
    country: "",
    orientation: 0,
    touchscreen: 0,
    density: 0,
    keyboard: 0,
    navigation: 0,
    input_flags: 0,
    screen_width: 0,
    screen_height: 0,
    sdk_version: 0,
    screen_layout: 0,
    ui_mode: 0,
    smallest_screen_width_dp: 0,
    screen_width_dp: 0,
    screen_height_dp: 0,
    locale_script: "",
    color_mode: 0,
    raw: Bytes::from_array(full_raw),
  }
  let t_over = @axml.parse_arsc(@axml.encode_arsc(w9_struct_table(over)))
  let hits_over = @axml.ResTable::lookup_all(t_over, ar_id(0x7f, 1, 0))
  assert_eq(hits_over.length(), 1, msg="over-long raw 条目保留")
  let back = hits_over.at(0).config
  assert_eq(back.size, 64, msg="size 自描述")
  assert_eq(back.raw.length(), 64, msg="raw 截断到 size")
  for i in 0..<64 {
    assert_eq(
      back.raw.at(i),
      full_raw.at(i),
      msg="over-long raw 前 64 字节逐字节一致（i=\{i}）",
    )
  }
}

///|
/// W9-5 辅助：构造仅 `locale_script` 非零、size=40 的构造型配置
/// （raw 为空，走字段序列化路径）。
fn w9_cfg_script(script : String) -> @axml.ResConfig {
  {
    size: 40,
    mcc: 0,
    mnc: 0,
    language: "",
    country: "",
    orientation: 0,
    touchscreen: 0,
    density: 0,
    keyboard: 0,
    navigation: 0,
    input_flags: 0,
    screen_width: 0,
    screen_height: 0,
    sdk_version: 0,
    screen_layout: 0,
    ui_mode: 0,
    smallest_screen_width_dp: 0,
    screen_width_dp: 0,
    screen_height_dp: 0,
    locale_script: script,
    color_mode: 0,
    raw: Bytes::make(0, b'\x00'),
  }
}

///|
/// W9-5（localeScript NUL 填充）：`locale_script` 不足 4 字节时，镜像
/// 36..40 偏移必须逐字节补 NUL；超过 4 字节时截断为前 4 字节。
test "W9-5: localeScript 4 字节 NUL 填充" {
  let cases : Array[(String, Array[Int32], String)] = [
    ("", [0, 0, 0, 0], ""),
    ("Lat", [0x4C, 0x61, 0x74, 0], "Lat"),
    ("Latn", [0x4C, 0x61, 0x74, 0x6E], "Latn"),
    ("LatnX", [0x4C, 0x61, 0x74, 0x6E], "Latn"),
  ]
  for case in cases {
    let (script, want, want_back) = case
    let t = @axml.parse_arsc(
      @axml.encode_arsc(w9_struct_table(w9_cfg_script(script))),
    )
    let hits = @axml.ResTable::lookup_all(t, ar_id(0x7f, 1, 0))
    assert_eq(hits.length(), 1, msg="script=\{script} 条目保留")
    let cfg = hits.at(0).config
    for i in 0..<4 {
      assert_eq(
        cfg.raw.at(36 + i).to_int(),
        want[i],
        msg="script=\{script} 偏移 36+\{i}",
      )
    }
    assert_eq(cfg.locale_script, want_back, msg="script=\{script} 回读")
  }
}
