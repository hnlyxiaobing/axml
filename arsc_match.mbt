///|
/// R4 加法性增强：aapt2 式配置最优匹配、bag 压平、`?attr` 主题求值。
///
/// 边界（如实登记，见 docs/API.md 降级项）：
/// - 配置匹配覆盖 AOSP `ResConfig::match` 的常用子集：mcc/mnc/locale/
///   screenLayout/smallestWidth/width/height(dp)/orientation/uiMode/colorMode/
///   density/touchscreen/keyboard/navigation/inputFlags/screen(px)/sdkVersion；
///   未覆盖维度（如 layoutDirection、localeScript 细分）按「资源未指定 = 任意」降级。
/// - 最优匹配按 AOSP `isBetterThan` 的**优先级顺序**逐维比较；同维内：通配劣于
///   具体、尺寸维取更接近设备且不超过设备的值、密度维取精确匹配优先再取更高密度。
/// - bag 压平按 parent 链自根向子覆盖同名 map；环/缺失/非复杂条目报 `ArscError`。
/// - `?attr` 求值只沿 `Attribute`/`DynamicAttribute` 值继续（普通 `Reference`
///   视为终点值，不当作主题引用）；环/缺失报 `ArscError`。

///|
/// 按限定符文本构造设备/资源配置（aapt2 qualifier 子集）：
/// `mcc310`、`mnc004`、`en`、`en-rUS`、`sw600dp`、`w1024dp`、`h768dp`、
/// `port`/`land`、`night`/`notnight`、`car`/`desk`/`television`/`watch`、
/// `ldpi`/`mdpi`/`hdpi`/`xhdpi`/`xxhdpi`/`xxxhdpi`/`nodpi`/`anydpi`/`NNNdpi`。
/// 未知 token 报 `BadQualifier(token)`；空串返回默认配置。
pub fn ResConfig::from_qualifiers(s : String) -> ResConfig raise ArscError {
  let cfg : ResConfig = {
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
  if s == "" {
    return cfg
  }
  let mut out = cfg
  let mut cur = ""
  let tokens : Array[String] = []
  for c in s {
    if c == '-' {
      tokens.push(cur)
      cur = ""
    } else {
      cur = cur + c.to_string()
    }
  }
  tokens.push(cur)
  for t in tokens {
    if t.length() == 0 {
      raise ArscError::BadQualifier(t)
    }
    if t.has_prefix("mcc") && t.length() > 3 {
      out = { ..out, mcc: qual_int(t, 3), }
    } else if t.has_prefix("mnc") && t.length() > 3 {
      out = { ..out, mnc: qual_int(t, 3), }
    } else if t.has_prefix("sw") && t.has_suffix("dp") && t.length() > 4 {
      out = { ..out, smallest_screen_width_dp: qual_int(t, 2), }
    } else if t.has_prefix("w") && t.has_suffix("dp") && t.length() > 3 {
      out = { ..out, screen_width_dp: qual_int(t, 1), }
    } else if t.has_prefix("h") && t.has_suffix("dp") && t.length() > 3 {
      out = { ..out, screen_height_dp: qual_int(t, 1), }
    } else if t == "port" {
      out = { ..out, orientation: 1, }
    } else if t == "land" {
      out = { ..out, orientation: 2, }
    } else if t == "night" {
      out = { ..out, ui_mode: 0x20, }
    } else if t == "notnight" {
      out = { ..out, ui_mode: 0x10, }
    } else if t == "car" {
      out = { ..out, ui_mode: 0x03, }
    } else if t == "desk" {
      out = { ..out, ui_mode: 0x02, }
    } else if t == "television" {
      out = { ..out, ui_mode: 0x04, }
    } else if t == "appliance" {
      out = { ..out, ui_mode: 0x05, }
    } else if t == "watch" {
      out = { ..out, ui_mode: 0x06, }
    } else if t == "ldpi" {
      out = { ..out, density: 120, }
    } else if t == "mdpi" {
      out = { ..out, density: 160, }
    } else if t == "tvdpi" {
      out = { ..out, density: 213, }
    } else if t == "hdpi" {
      out = { ..out, density: 240, }
    } else if t == "xhdpi" {
      out = { ..out, density: 320, }
    } else if t == "xxhdpi" {
      out = { ..out, density: 480, }
    } else if t == "xxxhdpi" {
      out = { ..out, density: 640, }
    } else if t == "nodpi" {
      out = { ..out, density: 0xFFFF, }
    } else if t == "anydpi" {
      out = { ..out, density: 0xFFFE, }
    } else if t.has_suffix("dpi") && t.length() > 3 {
      out = { ..out, density: qual_int(t, 0), }
    } else if t.has_prefix("r") && t.length() == 3 {
      out = { ..out, country: t, }
    } else if t.length() == 2 || t.length() == 3 {
      // 语言码（ISO 639-1 / 639-2/3）
      for c in t {
        if !is_ascii_alpha(c) {
          raise ArscError::BadQualifier(t)
        }
      }
      out = { ..out, language: t, }
    } else {
      raise ArscError::BadQualifier(t)
    }
  }
  out
}

///|
/// 解析限定符中从 `start` 起的十进制数字段（`NNNdpi` 等）。
fn qual_int(t : String, start : Int32) -> Int32 raise ArscError {
  let mut v = 0
  let mut i = start
  let mut done = false
  while i < t.length() && !done {
    let c = t.at(i)
    if c >= '0' && c <= '9' {
      v = v * 10 + (c.to_int() - '0'.to_int())
      i = i + 1
    } else if i == t.length() - 2 && t.at(i) == 'd' && t.at(i + 1) == 'p' {
      done = true
    } else {
      raise ArscError::BadQualifier(t)
    }
  }
  v
}

///|
fn is_ascii_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
/// 该配置能否作用于给定设备配置（`self` 为资源侧，全零/未指定维度 = 任意）。
pub fn ResConfig::matches(self : ResConfig, device : ResConfig) -> Bool {
  (self.mcc == 0 || self.mcc == device.mcc) &&
  (self.mnc == 0 || self.mnc == device.mnc) &&
  (self.language == "" || self.language == device.language) &&
  (self.country == "" || self.country == device.country) &&
  (self.orientation == 0 || self.orientation == device.orientation) &&
  (self.touchscreen == 0 || self.touchscreen == device.touchscreen) &&
  (self.keyboard == 0 || self.keyboard == device.keyboard) &&
  (self.navigation == 0 || self.navigation == device.navigation) &&
  (self.input_flags == 0 || self.input_flags == device.input_flags) &&
  (self.screen_layout == 0 || self.screen_layout == device.screen_layout) &&
  (self.ui_mode == 0 || self.ui_mode == device.ui_mode) &&
  (self.color_mode == 0 || self.color_mode == device.color_mode) &&
  (self.locale_script == "" || self.locale_script == device.locale_script) &&
  density_matches(self.density, device.density) &&
  size_matches(self.smallest_screen_width_dp, device.smallest_screen_width_dp) &&
  size_matches(self.screen_width_dp, device.screen_width_dp) &&
  size_matches(self.screen_height_dp, device.screen_height_dp) &&
  size_matches(self.screen_width, device.screen_width) &&
  size_matches(self.screen_height, device.screen_height) &&
  sdk_matches(self.sdk_version, device.sdk_version)
}

///|
/// 密度匹配：未指定 / anydpi / nodpi 视为任意；否则要求等于设备密度。
fn density_matches(res : Int32, device : Int32) -> Bool {
  res == 0 || res == 0xFFFE || res == 0xFFFF || res == device
}

///|
/// 尺寸匹配（dp/px）：资源值不得超过设备值（设备未给值时按任意处理）。
fn size_matches(res : Int32, device : Int32) -> Bool {
  res == 0 || (device > 0 && res <= device)
}

///|
/// SDK 匹配：资源 sdkVersion 不得高于设备。
fn sdk_matches(res : Int32, device : Int32) -> Bool {
  res == 0 || (device > 0 && res <= device)
}

///|
/// 逐维「更优」比较：返回 1 = self 更优，-1 = other 更优，0 = 平手。
/// 前提：两者均已通过 `matches`（调用方保证）。
pub fn ResConfig::is_better_than(
  self : ResConfig,
  other : ResConfig,
  device : ResConfig,
) -> Bool {
  let dims : Array[Int32] = [
    better_wildcard(self.mcc, other.mcc),
    better_wildcard(self.mnc, other.mnc),
    better_wildcard_str(self.language, other.language),
    better_wildcard_str(self.country, other.country),
    better_wildcard(self.screen_layout, other.screen_layout),
    better_size(self.smallest_screen_width_dp, other.smallest_screen_width_dp),
    better_size(self.screen_width_dp, other.screen_width_dp),
    better_size(self.screen_height_dp, other.screen_height_dp),
    better_wildcard(self.orientation, other.orientation),
    better_wildcard(self.ui_mode, other.ui_mode),
    better_wildcard(self.color_mode, other.color_mode),
    better_density(self.density, other.density, device.density),
    better_wildcard(self.touchscreen, other.touchscreen),
    better_wildcard(self.keyboard, other.keyboard),
    better_wildcard(self.navigation, other.navigation),
    better_wildcard(self.input_flags, other.input_flags),
    better_size(self.screen_width, other.screen_width),
    better_size(self.screen_height, other.screen_height),
    better_size(self.sdk_version, other.sdk_version),
  ]
  for d in dims {
    if d != 0 {
      return d > 0
    }
  }
  false
}

///|
/// 通配（0）劣于具体值；两者都具体或都通配时视为平手。
fn better_wildcard(a : Int32, b : Int32) -> Int32 {
  if a == 0 && b == 0 {
    0
  } else if a == 0 {
    -1
  } else if b == 0 {
    1
  } else {
    0
  }
}

///|
/// 字符串维度（locale）：空串为通配。
fn better_wildcard_str(a : String, b : String) -> Int32 {
  if a == "" && b == "" {
    0
  } else if a == "" {
    -1
  } else if b == "" {
    1
  } else {
    0
  }
}

///|
/// 尺寸维度：通配劣于具体；都具体时取更接近设备上限的较大值。
fn better_size(a : Int32, b : Int32) -> Int32 {
  if a == 0 && b == 0 {
    0
  } else if a == 0 {
    -1
  } else if b == 0 {
    1
  } else if a == b {
    0
  } else if a > b {
    1
  } else {
    -1
  }
}

///|
/// 密度维度：通配劣于具体；精确匹配最优；否则更高密度优先。
fn better_density(a : Int32, b : Int32, device : Int32) -> Int32 {
  let wa = a == 0 || a == 0xFFFE || a == 0xFFFF
  let wb = b == 0 || b == 0xFFFE || b == 0xFFFF
  if wa && wb {
    0
  } else if wa {
    -1
  } else if wb {
    1
  } else if a == device && b != device {
    1
  } else if b == device && a != device {
    -1
  } else if a == b {
    0
  } else if a > b {
    1
  } else {
    -1
  }
}

///|
/// 资源 id 在给定设备配置下的最优命中（aapt2 式 qualifier 最优匹配）。
/// 无配置匹配设备时返回 `None`（上层可回退默认配置）。
pub fn ResTable::lookup_with(
  self : ResTable,
  id : UInt32,
  device : ResConfig,
) -> ResLookup? {
  let hits = self.lookup_all(id)
  let mut best : ResLookup? = None
  for hit in hits {
    if !hit.config.matches(device) {
      continue
    }
    match best {
      None => best = Some(hit)
      Some(b) =>
        if hit.config.is_better_than(b.config, device) {
          best = Some(hit)
        }
    }
  }
  best
}

///|
/// bag 压平结果：自根到子覆盖同名 map 后的最终属性映射（保序，子值原地覆盖）。
pub(all) struct FlattenedBag {
  id : UInt32
  attrs : Array[ResMap]
}

///|
/// 在压平后的映射中按 name（属性 id）取值。
fn flatten_find(attrs : Array[ResMap], name : UInt32) -> ResMap? {
  for m in attrs {
    if m.name == name {
      return Some(m)
    }
  }
  None
}

///|
/// 压平一个复杂条目（bag）的 parent 继承链：自根向子覆盖同名 map。
/// 目标不存在/是简单值 → `BagNotComplex`；parent 缺失 → `BagMissingParent`；
/// parent 链成环 → `BagCycle`。全部不 panic。
pub fn ResTable::flatten_bag(
  self : ResTable,
  id : UInt32,
  device : ResConfig,
) -> FlattenedBag raise ArscError {
  let visited : Array[UInt32] = []
  let levels : Array[ResBag] = []
  let mut cur = id
  let mut running = true
  while running {
    if visited.contains(cur) {
      raise ArscError::BagCycle(cur)
    }
    visited.push(cur)
    match self.lookup_with(cur, device) {
      None =>
        if cur == id {
          raise ArscError::BagNotComplex(cur)
        } else {
          raise ArscError::BagMissingParent(cur)
        }
      Some(hit) =>
        match hit.entry.value {
          Simple(_) => raise ArscError::BagNotComplex(cur)
          Complex(bag) => {
            levels.push(bag)
            if bag.parent == 0 {
              running = false
            } else {
              cur = bag.parent
            }
          }
        }
    }
  }
  let attrs : Array[ResMap] = []
  let mut i = levels.length() - 1
  while i >= 0 {
    for m in levels.at(i).maps {
      match flatten_find(attrs, m.name) {
        Some(_) => {
          // 子值覆盖：原地替换
          let mut j = 0
          while j < attrs.length() {
            if attrs.at(j).name == m.name {
              attrs[j] = m
            }
            j = j + 1
          }
        }
        None => attrs.push(m)
      }
    }
    i = i - 1
  }
  { id, attrs, }
}

///|
/// 求值主题里的 `?attr` 引用：在压平后的 theme bag 中找 `attr_id`，
/// 若其值是 `Attribute`/`DynamicAttribute`（即 `?attr/…`）则沿链继续；
/// 普通 `Reference`（`@…`）视为终点返回值。
/// 缺失 → `AttrMissing`；引用链成环 → `AttrCycle`。
pub fn ResTable::eval_theme_attr(
  self : ResTable,
  theme_id : UInt32,
  attr_id : UInt32,
  device : ResConfig,
) -> ResValue raise ArscError {
  let flat = self.flatten_bag(theme_id, device)
  let visited : Array[UInt32] = []
  let mut cur = attr_id
  let mut result : ResValue = { data_type: Null, data: 0U, }
  let mut running = true
  while running {
    if visited.contains(cur) {
      raise ArscError::AttrCycle(cur)
    }
    visited.push(cur)
    match flatten_find(flat.attrs, cur) {
      None => raise ArscError::AttrMissing(cur)
      Some(m) =>
        match m.value.data_type {
          Attribute | DynamicAttribute => cur = m.value.data
          _ => {
            result = m.value
            running = false
          }
        }
    }
  }
  result
}
