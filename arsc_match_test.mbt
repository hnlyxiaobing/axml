///|
/// R4：aapt2 式 qualifier 最优匹配 / bag 压平 / ?attr 主题求值 测试。
/// 表侧为**程序化构造的合成 ResTable**（不依赖外部字节样本），
/// 覆盖正常路径与错误路径（环 / 缺失 / 非复杂条目 / 非法限定符）。

///|
fn mr_pool(strings : Array[String]) -> @axml.StringPool {
  {
    encoding: @axml.StringEncoding::Utf8,
    strings,
    styles: Bytes::make(0, b'\x00'),
  }
}

///|
fn mr_value(t : @axml.ResDataType, d : UInt32) -> @axml.ResValue {
  { data_type: t, data: d, }
}

///|
fn mr_map(name : UInt32, v : @axml.ResValue) -> @axml.ResMap {
  { name, value: v, }
}

///|
fn mr_bag(parent : UInt32, maps : Array[@axml.ResMap]) -> @axml.ResEntry {
  {
    key: 0,
    key_name: "Entry",
    flags: 1,
    value: @axml.ResEntryValue::Complex({ parent, maps, }),
  }
}

///|
fn mr_simple(t : @axml.ResDataType, d : UInt32) -> @axml.ResEntry {
  {
    key: 0,
    key_name: "",
    flags: 0,
    value: @axml.ResEntryValue::Simple(mr_value(t, d)),
  }
}

///|
/// 构造合成表：包 0x7f，类型 1（style），条目
/// 0 = 子主题（parent=1，覆盖 colorPrimary，textColor 为 ?attr 链），
/// 1 = 基主题（colorPrimary 红色、attr002→attr003、attr003=15），
/// 2 = 简单值条目（用于 BagNotComplex）。
fn mr_table() -> @axml.ResTable {
  let config : @axml.ResConfig = {
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
    raw: Bytes::make(0, b'\x00'),
  }
  let entries : Array[@axml.ResEntry?] = [
    Some(
      mr_bag(0x7f010001, [
        mr_map(0x7f020000, mr_value(@axml.ResDataType::Reference, 0x7f030000)),
        mr_map(0x7f020001, mr_value(@axml.ResDataType::Attribute, 0x7f020002)),
      ]),
    ),
    Some(
      mr_bag(0, [
        mr_map(
          0x7f020000,
          mr_value(@axml.ResDataType::IntColorArgb8, 0xFF112233),
        ),
        mr_map(0x7f020002, mr_value(@axml.ResDataType::Attribute, 0x7f020003)),
        mr_map(0x7f020003, mr_value(@axml.ResDataType::IntDec, 15)),
      ]),
    ),
    Some(mr_simple(@axml.ResDataType::IntDec, 7)),
  ]
  let pkg : @axml.ResPackage = {
    id: 0x7f,
    name: "test",
    type_id_offset: 0,
    type_pool: mr_pool(["style"]),
    key_pool: mr_pool(["AppTheme", "BaseTheme", "Plain"]),
    types: [
      {
        id: 1,
        types_count: 1,
        entry_count: 3,
        spec_flags: [0x40000000U, 0x40000000U, 0x40000000U],
        configs: [{ id: 1, flags: 0, config, entries, }],
      },
    ],
    libraries: [],
  }
  { global_pool: mr_pool([]), packages: [pkg], package_count: 1, }
}

///|
fn mr_default() -> @axml.ResConfig {
  @axml.ResConfig::from_qualifiers("") catch {
    _ => abort("default config")
  }
}

///|
/// qualifier 解析：典型设备配置。
test "r4 arsc: from_qualifiers 解析" {
  let c = @axml.ResConfig::from_qualifiers("en-rUS-sw600dp-land-night-xhdpi") catch {
    _ => abort("qualifier parse")
  }
  assert_eq(c.language, "en")
  assert_eq(c.country, "US")
  assert_eq(c.smallest_screen_width_dp, 600)
  assert_eq(c.orientation, 2)
  assert_eq(c.ui_mode, 0x20)
  assert_eq(c.density, 320)
  let d = @axml.ResConfig::from_qualifiers("") catch { _ => abort("empty") }
  assert_true(d.is_default(), msg="空串 = 默认配置")
  let mut bad = false
  ignore(@axml.ResConfig::from_qualifiers("watch-xylophone")) catch {
    @axml.ArscError::BadQualifier(t) => {
      assert_eq(t, "xylophone")
      bad = true
    }
    _ => ()
  }
  assert_true(bad, msg="未知 token 应报 BadQualifier")
}

///|
/// 地区限定符：去掉 'r' 前缀；支持 2 字母 ISO 与 3 位 UN M.49 数字码。
test "r4 arsc: from_qualifiers 地区" {
  let c1 = @axml.ResConfig::from_qualifiers("en-rUS") catch {
    _ => abort("en-rUS")
  }
  assert_eq(c1.country, "US", msg="rUS 应解析为 US")
  let c2 = @axml.ResConfig::from_qualifiers("es-r419") catch {
    _ => abort("es-r419")
  }
  assert_eq(c2.language, "es", msg="语言 es")
  assert_eq(c2.country, "419", msg="UN M.49 地区")
}

///|
/// 配置匹配：通配 / 精确 / 尺寸上界 / SDK 上界。
test "r4 arsc: 配置匹配" {
  let device = @axml.ResConfig::from_qualifiers("en-rUS-sw600dp-land-xhdpi") catch {
    _ => abort("device")
  }
  let def = mr_default()
  assert_true(def.matches(device), msg="默认配置匹配任意设备")
  let en = @axml.ResConfig::from_qualifiers("en") catch { _ => abort("en") }
  assert_true(en.matches(device), msg="语言 en 匹配")
  let fr = @axml.ResConfig::from_qualifiers("fr") catch { _ => abort("fr") }
  assert_true(!fr.matches(device), msg="语言 fr 不匹配")
  let sw800 = @axml.ResConfig::from_qualifiers("sw800dp") catch {
    _ => abort("sw800")
  }
  assert_true(
    !sw800.matches(device),
    msg="sw800dp 超过设备 600dp，不匹配",
  )
  let sw600 = @axml.ResConfig::from_qualifiers("sw600dp") catch {
    _ => abort("sw600")
  }
  assert_true(sw600.matches(device), msg="sw600dp 等于设备上界，匹配")
  let night = @axml.ResConfig::from_qualifiers("night") catch {
    _ => abort("night")
  }
  assert_true(!night.matches(device), msg="night 不匹配日间设备")
}

///|
/// 最优匹配：同维具体优于通配，多级具体逐维胜出。
test "r4 arsc: qualifier 最优匹配" {
  let device = @axml.ResConfig::from_qualifiers("en-rUS-land-xhdpi") catch {
    _ => abort("device")
  }
  let def = mr_default()
  let en = @axml.ResConfig::from_qualifiers("en") catch { _ => abort("en") }
  let en_land = @axml.ResConfig::from_qualifiers("en-land") catch {
    _ => abort("en-land")
  }
  let lang_land_night = @axml.ResConfig::from_qualifiers("en-land-night") catch {
    _ => abort("eln")
  }
  assert_true(en.is_better_than(def, device), msg="en 优于默认")
  assert_true(
    en_land.is_better_than(en, device),
    msg="en-land 优于 en（land 维）",
  )
  assert_true(
    !lang_land_night.matches(device),
    msg="night 不匹配设备（先经 matches 过滤）",
  )
  assert_true(en_land.matches(device), msg="en-land 匹配设备")
  // 密度：精确匹配优先于更高密度
  let hdpi = @axml.ResConfig::from_qualifiers("hdpi") catch {
    _ => abort("hdpi")
  }
  let xhdpi = @axml.ResConfig::from_qualifiers("xhdpi") catch {
    _ => abort("xhdpi")
  }
  let xxhdpi = @axml.ResConfig::from_qualifiers("xxhdpi") catch {
    _ => abort("xxhdpi")
  }
  assert_true(
    xhdpi.is_better_than(hdpi, device),
    msg="xhdpi 精确匹配优于 hdpi",
  )
  assert_true(
    xhdpi.is_better_than(xxhdpi, device),
    msg="xhdpi 精确匹配优于 xxhdpi",
  )
}

///|
/// lookup_with 端到端：合成表默认配置命中。
test "r4 arsc: lookup_with 命中" {
  let table = mr_table()
  let device = @axml.ResConfig::from_qualifiers("en-rUS-xhdpi") catch {
    _ => abort("device")
  }
  match table.lookup_with(0x7f010000U, device) {
    None => fail("lookup_with 应命中 AppTheme")
    Some(hit) => {
      assert_eq(hit.entry_name, "Entry")
      assert_eq(hit.type_name, "style")
      assert_eq(hit.package_name, "test")
    }
  }
  assert_true(
    table.lookup_with(0x7f010099U, device) is None,
    msg="未知条目应返回 None",
  )
}

///|
/// bag 压平：parent 链自根向子覆盖，子值胜出。
test "r4 arsc: bag 压平" {
  let table = mr_table()
  let def = mr_default()
  let flat = table.flatten_bag(0x7f010000U, def) catch {
    e => abort("flatten 失败: \{e.to_repr()}")
  }
  assert_eq(flat.id, 0x7f010000U)
  assert_eq(flat.attrs.length(), 4, msg="theme 2 项 + base 新增 2 项")
  // colorPrimary 被子主题覆盖为引用值
  let mut color = None
  let mut attr003 = None
  for m in flat.attrs {
    if m.name == 0x7f020000U {
      color = Some(m.value)
    }
    if m.name == 0x7f020003U {
      attr003 = Some(m.value)
    }
  }
  match color {
    None => fail("压平结果应含 colorPrimary")
    Some(v) =>
      assert_true(
        v.data_type is @axml.ResDataType::Reference && v.data == 0x7f030000U,
        msg="子主题覆盖 colorPrimary 为 @color 引用",
      )
  }
  match attr003 {
    None => fail("压平结果应含 attr003")
    Some(v) => assert_eq(v.data, 15U, msg="base 的 attr003 = 15")
  }
}

///|
/// ?attr 主题求值：多级链求到最终字面量；普通 @ref 视为终点。
test "r4 arsc: ?attr 主题求值" {
  let table = mr_table()
  let def = mr_default()
  // ?textColor -> ?attr002 -> 15
  let v = table.eval_theme_attr(0x7f010000U, 0x7f020001U, def) catch {
    e => abort("eval 失败: \{e.to_repr()}")
  }
  assert_true(
    v.data_type is @axml.ResDataType::IntDec,
    msg="求值结果为 IntDec",
  )
  assert_eq(v.data, 15U)
  // colorPrimary 是普通 @ref，不应继续沿链
  let c = table.eval_theme_attr(0x7f010000U, 0x7f020000U, def) catch {
    e => abort("eval 失败: \{e.to_repr()}")
  }
  assert_true(
    c.data_type is @axml.ResDataType::Reference,
    msg="普通引用为 Reference",
  )
  assert_eq(c.data, 0x7f030000U)
  let mut missing = false
  ignore(table.eval_theme_attr(0x7f010000U, 0x7f020099U, def)) catch {
    @axml.ArscError::AttrMissing(id) => {
      assert_eq(id, 0x7f020099U)
      missing = true
    }
    _ => ()
  }
  assert_true(missing, msg="缺失 attr 应报 AttrMissing")
}

///|
/// 错误路径：非复杂条目 / parent 缺失 / parent 成环 / ?attr 成环。
test "r4 arsc: 压平与求值错误路径" {
  let table = mr_table()
  let def = mr_default()
  let mut not_complex = false
  ignore(table.flatten_bag(0x7f010002U, def)) catch {
    @axml.ArscError::BagNotComplex(id) => {
      assert_eq(id, 0x7f010002U)
      not_complex = true
    }
    _ => ()
  }
  assert_true(not_complex, msg="简单值应报 BagNotComplex")
  let mut missing_parent = false
  ignore(table.flatten_bag(0x7f010099U, def)) catch {
    @axml.ArscError::BagNotComplex(id) => {
      assert_eq(id, 0x7f010099U)
      missing_parent = true
    }
    _ => ()
  }
  assert_true(missing_parent, msg="目标不存在应报 BagNotComplex")
  // parent 自环保留独立样本表；?attr 互环用无自环的 cycle_table
  let bagcycle_table = mr_bagcycle_table()
  let cycle_table = mr_cycle_table()
  let mut bag_cycle = false
  ignore(bagcycle_table.flatten_bag(0x7f010000U, def)) catch {
    @axml.ArscError::BagCycle(id) => {
      assert_eq(id, 0x7f010000U)
      bag_cycle = true
    }
    _ => ()
  }
  assert_true(bag_cycle, msg="parent 自环应报 BagCycle")
  let mut attr_cycle = false
  ignore(cycle_table.eval_theme_attr(0x7f010000U, 0x7f020010U, def)) catch {
    @axml.ArscError::AttrCycle(id) => {
      assert_eq(id, 0x7f020010U)
      attr_cycle = true
    }
    _ => ()
  }
  assert_true(attr_cycle, msg="?attr 互环应报 AttrCycle")
}

///|
/// 环样本表（?attr 互环，无 bag parent 自环）：attr010↔attr011 互指。
fn mr_cycle_table() -> @axml.ResTable {
  let config = mr_default()
  let entries : Array[@axml.ResEntry?] = [
    Some(
      mr_bag(0, [
        mr_map(0x7f020010, mr_value(@axml.ResDataType::Attribute, 0x7f020011)),
        mr_map(0x7f020011, mr_value(@axml.ResDataType::Attribute, 0x7f020010)),
      ]),
    ),
  ]
  let pkg : @axml.ResPackage = {
    id: 0x7f,
    name: "cyc",
    type_id_offset: 0,
    type_pool: mr_pool(["style"]),
    key_pool: mr_pool(["Cyc"]),
    types: [
      {
        id: 1,
        types_count: 1,
        entry_count: 1,
        spec_flags: [0x40000000U],
        configs: [{ id: 1, flags: 0, config, entries, }],
      },
    ],
    libraries: [],
  }
  { global_pool: mr_pool([]), packages: [pkg], package_count: 1, }
}

///|
/// parent 自环样本表（用于 BagCycle）。
fn mr_bagcycle_table() -> @axml.ResTable {
  let config = mr_default()
  let entries : Array[@axml.ResEntry?] = [
    Some(
      mr_bag(0x7f010000, [
        mr_map(0x7f020010, mr_value(@axml.ResDataType::IntDec, 1)),
      ]),
    ),
  ]
  let pkg : @axml.ResPackage = {
    id: 0x7f,
    name: "bagcyc",
    type_id_offset: 0,
    type_pool: mr_pool(["style"]),
    key_pool: mr_pool(["Self"]),
    types: [
      {
        id: 1,
        types_count: 1,
        entry_count: 1,
        spec_flags: [0x40000000U],
        configs: [{ id: 1, flags: 0, config, entries, }],
      },
    ],
    libraries: [],
  }
  { global_pool: mr_pool([]), packages: [pkg], package_count: 1, }
}

///|
/// 错误路径：BagMissingParent 显式用例——根条目存在且为 Complex，
/// 但其 parent id 在表中不存在（表仅有 root entry，无 parent entry）。
test "r4 arsc: 压平 BagMissingParent" {
  let table = mr_bagmissingparent_table()
  let def = mr_default()
  let mut got_parent = 0U
  let mut raised = false
  ignore(table.flatten_bag(0x7f010000U, def)) catch {
    @axml.ArscError::BagMissingParent(id) => {
      raised = true
      got_parent = id
    }
    _ => ()
  }
  assert_true(raised, msg="parent 缺失应显式抛出 BagMissingParent")
  assert_eq(
    got_parent,
    0x7f010099U,
    msg="BagMissingParent 须携带缺失的 parent id",
  )
}

///|
/// BagMissingParent 样本表：一个 bag（id=0x7f010000）存在且为 Complex，
/// parent 指向 0x7f010099——后者在表中不存在（entries 只有 1 项）。
fn mr_bagmissingparent_table() -> @axml.ResTable {
  let config = mr_default()
  let entries : Array[@axml.ResEntry?] = [
    Some(
      mr_bag(0x7f010099, [
        mr_map(0x7f020000, mr_value(@axml.ResDataType::IntDec, 42)),
      ]),
    ),
  ]
  let pkg : @axml.ResPackage = {
    id: 0x7f,
    name: "miss",
    type_id_offset: 0,
    type_pool: mr_pool(["style"]),
    key_pool: mr_pool(["Orphan"]),
    types: [
      {
        id: 1,
        types_count: 1,
        entry_count: 1,
        spec_flags: [0x40000000U],
        configs: [{ id: 1, flags: 0, config, entries, }],
      },
    ],
    libraries: [],
  }
  { global_pool: mr_pool([]), packages: [pkg], package_count: 1, }
}

///|
/// W3 辅助：逐字段比较两个 `ResConfig`（`from_qualifiers` 与 `_ext` 等价性断言）。
fn mr_config_eq(a : @axml.ResConfig, b : @axml.ResConfig) -> Bool {
  a.size == b.size &&
  a.mcc == b.mcc &&
  a.mnc == b.mnc &&
  a.language == b.language &&
  a.country == b.country &&
  a.orientation == b.orientation &&
  a.touchscreen == b.touchscreen &&
  a.density == b.density &&
  a.keyboard == b.keyboard &&
  a.navigation == b.navigation &&
  a.input_flags == b.input_flags &&
  a.screen_width == b.screen_width &&
  a.screen_height == b.screen_height &&
  a.sdk_version == b.sdk_version &&
  a.screen_layout == b.screen_layout &&
  a.ui_mode == b.ui_mode &&
  a.smallest_screen_width_dp == b.smallest_screen_width_dp &&
  a.screen_width_dp == b.screen_width_dp &&
  a.screen_height_dp == b.screen_height_dp &&
  a.locale_script == b.locale_script &&
  a.color_mode == b.color_mode &&
  a.raw == b.raw
}

///|
/// T-W3-1：`from_qualifiers_ext` 对旧子集全部 token 与旧函数逐字段一致。
test "W3 qualifier: ext 对旧子集逐字段一致" {
  let cases : Array[String] = [
    "", "en", "en-rUS", "es-r419", "mcc310", "mnc004", "sw600dp", "w1024dp", "h768dp",
    "port", "land", "night", "notnight", "car", "desk", "television", "appliance",
    "watch", "ldpi", "mdpi", "tvdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi", "nodpi",
    "anydpi", "480dp", "en-rUS-sw600dp-land-night-xhdpi",
  ]
  for c in cases {
    let old = @axml.ResConfig::from_qualifiers(c) catch {
      _ => abort("旧函数解析失败: \{c}")
    }
    let ext = @axml.ResConfig::from_qualifiers_ext(c) catch {
      _ => abort("ext 解析失败: \{c}")
    }
    assert_true(mr_config_eq(old, ext), msg="\{c}: 逐字段一致")
  }
}

///|
/// T-W3-2：ext 新 token 正确解析，旧函数对同类输入仍报 `BadQualifier`。
test "W3 qualifier: ext 新 token 与旧函数拒绝" {
  let v21 = @axml.ResConfig::from_qualifiers_ext("v21") catch {
    _ => abort("v21")
  }
  assert_eq(v21.sdk_version, 21, msg="vNN → sdk_version")
  let bcp = @axml.ResConfig::from_qualifiers_ext("b+en+US") catch {
    _ => abort("b+en+US")
  }
  assert_eq(bcp.language, "en", msg="b+ 语言")
  assert_eq(bcp.country, "US", msg="b+ 地区")
  let bcp_zh = @axml.ResConfig::from_qualifiers_ext("b+zh") catch {
    _ => abort("b+zh")
  }
  assert_eq(bcp_zh.language, "zh", msg="b+ 无地区")
  let long = @axml.ResConfig::from_qualifiers_ext("long") catch {
    _ => abort("long")
  }
  assert_eq(long.screen_layout & 0x08, 0x08, msg="long 置位 screenLayout")
  let round = @axml.ResConfig::from_qualifiers_ext("round") catch {
    _ => abort("round")
  }
  assert_eq(round.screen_layout & 0x04, 0x04, msg="round 置位 screenLayout")
  let widecg = @axml.ResConfig::from_qualifiers_ext("widecg") catch {
    _ => abort("widecg")
  }
  assert_eq(widecg.screen_layout & 0xC000, 0xC000, msg="widecg 置位")
  let highdr = @axml.ResConfig::from_qualifiers_ext("highdr") catch {
    _ => abort("highdr")
  }
  assert_eq(highdr.color_mode & 0x08, 0x08, msg="highdr 置位 colorMode")
  let navhidden = @axml.ResConfig::from_qualifiers_ext("navhidden") catch {
    _ => abort("navhidden")
  }
  assert_eq(navhidden.navigation, 0x10, msg="navhidden → navigation")
  let keysexposed = @axml.ResConfig::from_qualifiers_ext("keysexposed") catch {
    _ => abort("keysexposed")
  }
  assert_eq(keysexposed.keyboard, 1, msg="keysexposed → keyboard")
  let qwerty = @axml.ResConfig::from_qualifiers_ext("qwerty") catch {
    _ => abort("qwerty")
  }
  assert_eq(qwerty.input_flags & 0x04, 0x04, msg="qwerty 置位 inputFlags")
  let dpad = @axml.ResConfig::from_qualifiers_ext("dpad") catch {
    _ => abort("dpad")
  }
  assert_eq(dpad.navigation, 1, msg="dpad → navigation")
  let finger = @axml.ResConfig::from_qualifiers_ext("finger") catch {
    _ => abort("finger")
  }
  assert_eq(finger.touchscreen, 1, msg="finger → touchscreen")
  let trackball = @axml.ResConfig::from_qualifiers_ext("trackball") catch {
    _ => abort("trackball")
  }
  assert_eq(trackball.navigation, 3, msg="trackball → navigation")
  // —— 旧函数对扩展 token 必须仍拒绝（语义冻结）——
  let rejects : Array[String] = ["v21", "long", "round", "b+en+US", "qwerty"]
  for c in rejects {
    let mut got = ""
    ignore(@axml.ResConfig::from_qualifiers(c)) catch {
      @axml.ArscError::BadQualifier(t) => got = t
      _ => ()
    }
    assert_eq(got, c, msg="旧函数应拒绝 \{c}")
  }
  // 未知 token 新旧同报 BadQualifier
  let mut ext_bad = ""
  ignore(@axml.ResConfig::from_qualifiers_ext("xylophone")) catch {
    @axml.ArscError::BadQualifier(t) => ext_bad = t
    _ => ()
  }
  assert_eq(ext_bad, "xylophone", msg="ext 未知 token 报 BadQualifier")
}

///|
/// T-W4-1：theme bag 中 `?attr` 链求到最终字面量（FromTheme）。
test "W4 theme: ?attr 链求到最终字面量" {
  let table = mr_table()
  let def = mr_default()
  // theme 0x7f010000 中 attr 0x7f020001 是 ?attr → 0x7f020002 → IntDec 15
  let r = @axml.resolve_attr_value_with_theme(
    ar_doc(),
    table,
    ar_attr(Attribute, 0x7f020001, None),
    0x7f010000,
    def,
  )
  assert_eq(r.text, "15", msg="链终点字面量")
  assert_true(r.origin is FromTheme, msg="origin 为 FromTheme")
  assert_true(r.id is None, msg="字面量终点无 id")
  // 动态属性（0x08）同样走主题求值
  let r2 = @axml.resolve_attr_value_with_theme(
    ar_doc(),
    table,
    ar_attr(Unknown(8), 0x7f020001, None),
    0x7f010000,
    def,
  )
  assert_eq(r2.text, "15", msg="动态属性链求值")
}

///|
/// T-W4-2：AttrMissing / AttrCycle / theme 非 bag 均降级 `Unresolved`，不抛错。
test "W4 theme: 求值失败降级 Unresolved 不抛错" {
  let table = mr_table()
  let cyc = mr_cycle_table()
  let def = mr_default()
  // attr 缺失
  let missing = @axml.resolve_attr_value_with_theme(
    ar_doc(),
    table,
    ar_attr(Attribute, 0x7f020099, None),
    0x7f010000,
    def,
  )
  assert_true(missing.origin is Unresolved(_), msg="AttrMissing 降级")
  assert_eq(missing.id, Some(0x7f020099U), msg="保留原始 attr id")
  // theme 不是 bag（简单值条目）
  let not_bag = @axml.resolve_attr_value_with_theme(
    ar_doc(),
    table,
    ar_attr(Attribute, 0x7f020001, None),
    0x7f010002,
    def,
  )
  assert_true(not_bag.origin is Unresolved(_), msg="theme 非 bag 降级")
  // ?attr 互环
  let cycle = @axml.resolve_attr_value_with_theme(
    ar_doc(),
    cyc,
    ar_attr(Attribute, 0x7f020010, None),
    0x7f010000,
    def,
  )
  assert_true(cycle.origin is Unresolved(_), msg="AttrCycle 降级")
  // theme id 不在表中
  let absent_theme = @axml.resolve_attr_value_with_theme(
    ar_doc(),
    table,
    ar_attr(Attribute, 0x7f020001, None),
    0x7f01FFFF,
    def,
  )
  assert_true(absent_theme.origin is Unresolved(_), msg="theme 缺失降级")
}

///|
/// T-W4-3：非 `?attr` 类型结果与旧 `resolve_attr_value` 逐字段一致。
test "W4 theme: 非引用类型与旧函数一致" {
  let table = mr_table()
  let def = mr_default()
  let cases : Array[(String, @axml.XmlAttribute)] = [
    ("Reference 命中", ar_attr(Reference, 0x7f010000, None)),
    ("Reference 未命中", ar_attr(Reference, 0x7f030000, None)),
    ("动态引用", ar_attr(Unknown(7), 0x7f010000, None)),
    ("布尔", ar_attr(IntBoolean, 1U, None)),
    ("字符串", ar_attr(String, 0U, None)),
    ("文本引用未命中", ar_attr(Null, 0U, Some("@string/missing"))),
  ]
  for c in cases {
    let old = @axml.resolve_attr_value(ar_doc(), table, c.1)
    let new = @axml.resolve_attr_value_with_theme(
      ar_doc(),
      table,
      c.1,
      0x7f010000,
      def,
    )
    assert_eq(old.text, new.text, msg="\{c.0}: text 一致")
    assert_eq(old.id, new.id, msg="\{c.0}: id 一致")
    let old_u = old.origin is Unresolved(_)
    let new_u = new.origin is Unresolved(_)
    assert_eq(old_u, new_u, msg="\{c.0}: origin 类别一致")
  }
}

///|
/// W5 辅助：带 `RES_TABLE_LIBRARY_TYPE` 映射的合成表。
/// 包 0x7f；类型 1 两个条目，值均为动态引用（运行时包字节 0x01 / 0x03）；
/// libraries = [(1, "lib.foo"), (2, "lib.bar")]。
fn mr_lib_table() -> @axml.ResTable {
  let config = mr_default()
  let entries : Array[@axml.ResEntry?] = [
    Some(mr_simple(@axml.ResDataType::DynamicReference, 0x01010002)),
    Some(mr_simple(@axml.ResDataType::DynamicReference, 0x03010002)),
  ]
  let pkg : @axml.ResPackage = {
    id: 0x7f,
    name: "dyn",
    type_id_offset: 0,
    type_pool: mr_pool(["attr"]),
    key_pool: mr_pool(["a1", "a2"]),
    types: [
      {
        id: 1,
        types_count: 1,
        entry_count: 2,
        spec_flags: [0x40000000U, 0x40000000U],
        configs: [{ id: 1, flags: 0, config, entries, }],
      },
    ],
    libraries: [
      { package_id: 1, name: "lib.foo", },
      { package_id: 2, name: "lib.bar", },
    ],
  }
  { global_pool: mr_pool([]), packages: [pkg], package_count: 1, }
}

///|
/// T-W5-1：library 命中/未命中两路径（`library_by_id` + `dynamic_ref_view`）。
test "W5 dynamic: library 映射命中与未命中" {
  let table = mr_lib_table()
  match table.library_by_id(1) {
    None => fail("library_by_id(1) 应命中")
    Some(lib) => assert_eq(lib.name, "lib.foo", msg="命中名字")
  }
  assert_true(table.library_by_id(9) is None, msg="未命中返回 None")
  let hit = table.dynamic_ref_view(0x01010002)
  assert_eq(hit.origin_id, 0x01010002U, msg="保留原始 id")
  assert_eq(hit.runtime_package_id, 1, msg="运行时包字节")
  assert_eq(hit.library_name, Some("lib.foo"), msg="命中库名")
  // 0x03 未登记 → library_name=None（值化降级，不报错）
  let miss = table.dynamic_ref_view(0x03010002)
  assert_eq(miss.runtime_package_id, 3, msg="未登记包字节")
  assert_true(miss.library_name is None, msg="未命中库名 None")
}

///|
/// T-W5-2：旧 API 对动态引用仍输出 `(dynamic)` / Unresolved，零变化。
test "W5 dynamic: 旧 API 不改写动态引用" {
  let table = mr_lib_table()
  let fmt = @axml.ResTable::format_value(table, {
    data_type: @axml.ResDataType::DynamicReference,
    data: 0x01010002,
  })
  assert_eq(fmt, "@0x01010002 (dynamic)", msg="format_value 如实标注")
  let r = @axml.resolve_attr_value(
    ar_doc(),
    table,
    ar_attr(Unknown(7), 0x01010002, None),
  )
  assert_eq(r.text, "@0x01010002", msg="未命中表时保留原 id")
  assert_true(r.origin is Unresolved(_), msg="origin 为 Unresolved")
}

///|
/// W3 辅助：双配置合成表。string/app_name（0x7f010000）：
/// 默认配置 "Fx Multidex" + zh 配置 "Fx 多维"（fx-multidex 真实样本同构）。
fn mc_table() -> @axml.ResTable {
  let default_cfg = mr_default()
  let zh_cfg = @axml.ResConfig::from_qualifiers("zh") catch {
    _ => abort("zh config")
  }
  let app_name : UInt32 = 0U
  let default_entry : @axml.ResEntry = {
    key: 0,
    key_name: "app_name",
    flags: 0,
    value: @axml.ResEntryValue::Simple({
      data_type: @axml.ResDataType::String,
      data: app_name,
    }),
  }
  let zh_entry : @axml.ResEntry = {
    key: 0,
    key_name: "app_name",
    flags: 0,
    value: @axml.ResEntryValue::Simple({
      data_type: @axml.ResDataType::String,
      data: 1U,
    }),
  }
  let spec : @axml.ResTypeSpec = {
    id: 1,
    types_count: 2,
    entry_count: 1,
    spec_flags: [0x40000000U],
    configs: [
      { id: 1, flags: 0, config: default_cfg, entries: [Some(default_entry)], },
      { id: 1, flags: 0, config: zh_cfg, entries: [Some(zh_entry)], },
    ],
  }
  let pkg : @axml.ResPackage = {
    id: 0x7f,
    name: "com.fx.multidex",
    type_id_offset: 0,
    type_pool: mr_pool(["string"]),
    key_pool: mr_pool(["app_name"]),
    types: [spec],
    libraries: [],
  }
  {
    global_pool: mr_pool(["Fx Multidex", "Fx 多维"]),
    packages: [pkg],
    package_count: 1,
  }
}

///|
/// T-W3-3（库层）：带设备配置取值——zh 设备取 zh 值；en 设备回退默认；
/// 空设备配置等同默认；旧 `resolve_attr_value` 语义冻结仍默认优先；
/// 文本引用形式 `@string/app_name` 同样按配置选值；未命中 id 降级 Unresolved。
test "W3 config: resolve_attr_value_with_config 按设备配置选值" {
  let table = mc_table()
  let doc = ar_doc()
  let ref_attr = ar_attr(Reference, 0x7f010000, None)
  // —— 旧函数语义冻结：默认配置优先 ——
  let old = @axml.resolve_attr_value(doc, table, ref_attr)
  assert_eq(old.text, "Fx Multidex", msg="旧函数仍默认优先")
  assert_true(old.origin is FromId, msg="旧函数 origin 不变")
  // —— zh 设备：命中 zh 配置 ——
  let zh = @axml.ResConfig::from_qualifiers("zh") catch { _ => abort("zh") }
  let rz = @axml.resolve_attr_value_with_config(doc, table, ref_attr, zh)
  assert_eq(rz.text, "Fx 多维", msg="zh 设备取 zh 值")
  assert_true(rz.origin is FromId, msg="origin 为 FromId")
  assert_eq(rz.id, Some(0x7f010000U), msg="保留引用 id")
  // —— en 设备：zh 不匹配 en，回退默认配置 ——
  let en = @axml.ResConfig::from_qualifiers("en") catch { _ => abort("en") }
  let re = @axml.resolve_attr_value_with_config(doc, table, ref_attr, en)
  assert_eq(re.text, "Fx Multidex", msg="en 设备回退默认值")
  // —— 空设备配置：等同默认 ——
  let empty = mr_default()
  let r0 = @axml.resolve_attr_value_with_config(doc, table, ref_attr, empty)
  assert_eq(r0.text, "Fx Multidex", msg="空设备配置等同默认")
  // —— 文本引用形式 raw_value：按配置选值 ——
  let txt = ar_attr(String, 0U, Some("@string/app_name"))
  let rt = @axml.resolve_attr_value_with_config(doc, table, txt, zh)
  assert_eq(rt.text, "Fx 多维", msg="文本引用按配置选值")
  assert_true(rt.origin is FromName, msg="文本引用 origin 为 FromName")
  let rt_old = @axml.resolve_attr_value(doc, table, txt)
  assert_eq(
    rt_old.text,
    "Fx Multidex",
    msg="文本引用旧函数仍默认优先",
  )
  // —— 未命中 id：Unresolved ——
  let miss = ar_attr(Reference, 0x7f010099, None)
  let rm = @axml.resolve_attr_value_with_config(doc, table, miss, zh)
  assert_true(rm.origin is Unresolved(_), msg="未命中 id 降级 Unresolved")
  assert_eq(rm.text, "@0x7f010099", msg="未命中保留原 id 文本")
}

///|
/// T-W3-3（lookup 层）：`lookup_best` 策略——`lookup_with` 命中优先，
/// 未命中回退 `lookup`（默认优先）；仅有 zh 配置（无默认）时 zh 设备命中 zh、
/// en 设备回退 chunk 顺序首个命中。
test "W3 config: lookup_with 命中优先 / 回退默认" {
  let table = mc_table()
  let zh = @axml.ResConfig::from_qualifiers("zh") catch { _ => abort("zh") }
  let en = @axml.ResConfig::from_qualifiers("en") catch { _ => abort("en") }
  // zh 设备：lookup_with 直接命中 zh 配置
  match table.lookup_with(0x7f010000U, zh) {
    None => fail("lookup_with 应命中 zh 配置")
    Some(hit) =>
      assert_true(hit.config.language == "zh", msg="命中 zh 配置")
  }
  // en 设备：lookup_with 无匹配（zh 不匹配、默认配置在 lookup_with 中仍匹配）
  // —— 注意：默认配置 matches 任意设备，故 en 设备经 lookup_with 命中默认配置
  match table.lookup_with(0x7f010000U, en) {
    None => fail("默认配置应匹配任意设备")
    Some(hit) =>
      assert_true(hit.config.is_default(), msg="en 设备命中默认配置")
  }
  // 仅 zh 配置的表：en 设备 lookup_with 未命中 -> lookup_best 回退 lookup
  let zh_only_cfg = @axml.ResConfig::from_qualifiers("zh") catch {
    _ => abort("zh")
  }
  let zh_only_entry : @axml.ResEntry = {
    key: 0,
    key_name: "solo",
    flags: 0,
    value: @axml.ResEntryValue::Simple({
      data_type: @axml.ResDataType::IntDec,
      data: 42U,
    }),
  }
  let spec : @axml.ResTypeSpec = {
    id: 1,
    types_count: 1,
    entry_count: 1,
    spec_flags: [0x40000000U],
    configs: [
      { id: 1, flags: 0, config: zh_only_cfg, entries: [Some(zh_only_entry)], },
    ],
  }
  let pkg : @axml.ResPackage = {
    id: 0x7f,
    name: "solo",
    type_id_offset: 0,
    type_pool: mr_pool(["string"]),
    key_pool: mr_pool(["solo"]),
    types: [spec],
    libraries: [],
  }
  let zh_only : @axml.ResTable = {
    global_pool: mr_pool([]),
    packages: [pkg],
    package_count: 1,
  }
  match zh_only.lookup_with(0x7f010000U, en) {
    Some(_) => fail("仅 zh 配置不应匹配 en 设备")
    None => ()
  }
  match zh_only.lookup(0x7f010000U) {
    None => fail("lookup 应按 chunk 顺序命中")
    Some(_) => ()
  }
}
