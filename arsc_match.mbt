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
  parse_quals(s, false)
}

///|
/// 限定符扩展版：在 `from_qualifiers` 子集基础上增加
/// `vNN`（sdk_version）、`long`/`notlong`、`round`/`notround`、
/// `widecg`/`nowidecg`、`highdr`/`lowdr`、
/// `b+<lang>[+<region>]`（BCP47 子集）、
/// `navhidden`/`navexposed`、`keysexposed`/`keyssoft`/`keyshidden`、
/// `qwerty`/`12key`、`dpad`/`wheel`/`nonav`、
/// `finger`/`nofinger`、`stylus`/`nostylus`、`trackball`/`notouch`。
/// 未知 token 仍复用 `BadQualifier`。
pub fn ResConfig::from_qualifiers_ext(s : String) -> ResConfig raise ArscError {
  parse_quals(s, true)
}

///|
/// 限定符解析共享实现：`allow_ext=true` 时接受扩展 token。
fn parse_quals(s : String, allow_ext : Bool) -> ResConfig raise ArscError {
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
    raw: Bytes::make(0, b'\x00'),
  }
  if s == "" {
    return cfg
  }
  let mut out = cfg
  let tokens = split_tokens(s)
  for t in tokens {
    if t.length() == 0 {
      raise ArscError::BadQualifier(t)
    }
    out = apply_qual_token(out, t, allow_ext)
  }
  out
}

///|
/// 按 `-` 拆分限定符串（不含 `-` 的 BCP47 `b+` 整体为单 token）。
fn split_tokens(s : String) -> Array[String] {
  let tokens : Array[String] = []
  let mut cur = ""
  for c in s {
    if c == '-' {
      tokens.push(cur)
      cur = ""
    } else {
      cur = cur + c.to_string()
    }
  }
  tokens.push(cur)
  tokens
}

///|
/// 单个限定符 token 的解析与应用。`allow_ext` 决定是否接受扩展 token。
fn apply_qual_token(
  out : ResConfig,
  t : String,
  allow_ext : Bool,
) -> ResConfig raise ArscError {
  // —— BCP47 子集：b+en 或 b+en+US 整体一个 token（含 '+' 不含 '-'）——
  if t.has_prefix("b+") && t.length() > 2 {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    let rest = t[2:].to_owned()
    let idx = find_plus(rest)
    if idx == -1 {
      validate_bcp47_lang(rest)
      return { ..out, language: rest, }
    }
    let lang = rest[:idx].to_owned()
    let region = rest[idx + 1:].to_owned()
    validate_bcp47_lang(lang)
    validate_bcp47_region(region)
    return { ..out, language: lang, country: region, }
  }
  // —— 前缀 token ——
  if t.has_prefix("mcc") && t.length() > 3 {
    return { ..out, mcc: qual_int(t, 3), }
  }
  if t.has_prefix("mnc") && t.length() > 3 {
    return { ..out, mnc: qual_int(t, 3), }
  }
  if t.has_prefix("sw") && t.has_suffix("dp") && t.length() > 4 {
    return { ..out, smallest_screen_width_dp: qual_int(t, 2), }
  }
  if t.has_prefix("w") && t.has_suffix("dp") && t.length() > 3 {
    return { ..out, screen_width_dp: qual_int(t, 1), }
  }
  if t.has_prefix("h") && t.has_suffix("dp") && t.length() > 3 {
    return { ..out, screen_height_dp: qual_int(t, 1), }
  }
  if t.has_prefix("v") && t.length() > 1 && allow_ext {
    let num = t[1:].to_owned()
    for c in num {
      if c < '0' || c > '9' {
        raise ArscError::BadQualifier(t)
      }
    }
    return { ..out, sdk_version: num_to_int(num), }
  }
  if t.has_suffix("dp") && t.length() > 3 {
    return { ..out, density: qual_int(t, 0), }
  }
  if t.has_prefix("r") && t.length() >= 3 && t.length() <= 4 {
    let region = t[1:].to_owned()
    if region.length() == 2 {
      for c in region {
        if !is_ascii_alpha(c) {
          raise ArscError::BadQualifier(t)
        }
      }
    } else if region.length() == 3 {
      for c in region {
        if c < '0' || c > '9' {
          raise ArscError::BadQualifier(t)
        }
      }
    } else {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, country: region, }
  }
  // —— 精确 token ——
  if t == "port" {
    return { ..out, orientation: 1, }
  }
  if t == "land" {
    return { ..out, orientation: 2, }
  }
  if t == "night" {
    return { ..out, ui_mode: 0x20, }
  }
  if t == "notnight" {
    return { ..out, ui_mode: 0x10, }
  }
  if t == "car" {
    return { ..out, ui_mode: 0x03, }
  }
  if t == "desk" {
    return { ..out, ui_mode: 0x02, }
  }
  if t == "television" {
    return { ..out, ui_mode: 0x04, }
  }
  if t == "appliance" {
    return { ..out, ui_mode: 0x05, }
  }
  if t == "watch" {
    return { ..out, ui_mode: 0x06, }
  }
  if t == "ldpi" {
    return { ..out, density: 120, }
  }
  if t == "mdpi" {
    return { ..out, density: 160, }
  }
  if t == "tvdpi" {
    return { ..out, density: 213, }
  }
  if t == "hdpi" {
    return { ..out, density: 240, }
  }
  if t == "xhdpi" {
    return { ..out, density: 320, }
  }
  if t == "xxhdpi" {
    return { ..out, density: 480, }
  }
  if t == "xxxhdpi" {
    return { ..out, density: 640, }
  }
  if t == "nodpi" {
    return { ..out, density: 0xFFFF, }
  }
  if t == "anydpi" {
    return { ..out, density: 0xFFFE, }
  }
  // —— 扩展 token（allow_ext=true 才接受）——
  if t == "long" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, screen_layout: out.screen_layout | 0x08, }
  }
  if t == "notlong" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, screen_layout: out.screen_layout & (0x08 : Int32).lnot(), }
  }
  if t == "round" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, screen_layout: out.screen_layout | 0x04, }
  }
  if t == "notround" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, screen_layout: out.screen_layout & (0x04 : Int32).lnot(), }
  }
  if t == "widecg" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, screen_layout: out.screen_layout | 0xC000, }
  }
  if t == "nowidecg" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return {
      ..out,
      screen_layout: out.screen_layout & (0xC000 : Int32).lnot(),
    }
  }
  if t == "highdr" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, color_mode: out.color_mode | 0x08, }
  }
  if t == "lowdr" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, color_mode: out.color_mode | 0x04, }
  }
  if t == "navhidden" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, navigation: 0x10, }
  }
  if t == "navexposed" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, navigation: 0x20, }
  }
  if t == "keysexposed" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, keyboard: 1, }
  }
  if t == "keyssoft" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, keyboard: 2, input_flags: out.input_flags | 0x03, }
  }
  if t == "keyshidden" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return {
      ..out,
      keyboard: 3,
      input_flags: out.input_flags & (0x03 : Int32).lnot(),
    }
  }
  if t == "qwerty" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, input_flags: out.input_flags | 0x04, }
  }
  if t == "12key" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, input_flags: out.input_flags & (0x04 : Int32).lnot(), }
  }
  if t == "dpad" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, navigation: 1, }
  }
  if t == "wheel" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, navigation: 2, }
  }
  if t == "nonav" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, navigation: 0, }
  }
  if t == "finger" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, touchscreen: 1, }
  }
  if t == "nofinger" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, touchscreen: 2, }
  }
  if t == "stylus" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, touchscreen: 3, }
  }
  if t == "nostylus" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, touchscreen: 4, }
  }
  if t == "trackball" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, navigation: 3, }
  }
  if t == "notouch" {
    if !allow_ext {
      raise ArscError::BadQualifier(t)
    }
    return { ..out, touchscreen: 0, }
  }
  // —— 语言码（ISO 639-1/639-2/3）——
  if t.length() == 2 || t.length() == 3 {
    for c in t {
      if !is_ascii_alpha(c) {
        raise ArscError::BadQualifier(t)
      }
    }
    return { ..out, language: t, }
  }
  raise ArscError::BadQualifier(t)
}

///|
/// 在 `s` 中查找第一个 `+` 的下标（-1 表示未找到）。
fn find_plus(s : String) -> Int32 {
  let mut i = 0
  for c in s {
    if c == '+' {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// BCP47 语言码验证（2–3 个 ASCII alpha）。
fn validate_bcp47_lang(lang : String) -> Unit raise ArscError {
  if lang.length() < 2 || lang.length() > 3 {
    raise ArscError::BadQualifier("b+lang")
  }
  for c in lang {
    if !is_ascii_alpha(c) {
      raise ArscError::BadQualifier("b+lang")
    }
  }
  ()
}

///|
/// BCP47 地区码验证（2 个 alpha 或 3 位数字）。
fn validate_bcp47_region(region : String) -> Unit raise ArscError {
  if region.length() == 2 {
    for c in region {
      if !is_ascii_alpha(c) {
        raise ArscError::BadQualifier("b+region")
      }
    }
  } else if region.length() == 3 {
    for c in region {
      if c < '0' || c > '9' {
        raise ArscError::BadQualifier("b+region")
      }
    }
  } else {
    raise ArscError::BadQualifier("b+region")
  }
  ()
}

///|
/// `num`（全数字串）→ Int32。
fn num_to_int(s : String) -> Int32 {
  let mut v = 0
  for c in s {
    v = v * 10 + (c.to_int() - '0'.to_int())
  }
  v
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
