///|
/// R4：aapt2 式 qualifier 最优匹配 / bag 压平 / ?attr 主题求值 测试。
/// 表侧为**程序化构造的合成 ResTable**（不依赖外部字节样本），
/// 覆盖正常路径与错误路径（环 / 缺失 / 非复杂条目 / 非法限定符）。

///|
fn mr_pool(strings : Array[String]) -> @axml.StringPool {
  { encoding: @axml.StringEncoding::Utf8, strings, styles: Bytes::new(0), }
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
    raw: Bytes::new(0),
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
  assert_eq(c.country, "rUS")
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
