///|
/// Android 二进制资源表（resources.arsc）解析库：类型、错误模型与查询接口。
///
/// 本文件包含全部公开类型、查询/解析 API 与格式化实现；chunk 级字节解析在
/// `arsc_decode.mbt`（不导出）。规范依据：AOSP
/// `frameworks/base/libs/androidfw/include/androidfw/ResourceTypes.h` 与
/// `LoadedArsc.cpp`（Apache-2.0）；sparse / OFFSET16 / compact entry 语义均按
/// AOSP `LoadedPackage::GetEntryOffset` / `ResTable_entry::value()` 复刻。
/// 加法性新增（R2 冻结基线不动：`AxmlError` 与 AXML 侧 API 均未改动）。

///|
/// resources.arsc 解析错误。
///
/// 字节层/字符串池层错误映射自 `AxmlError`（构造一一对应，见 `axml_err`），
/// 资源表结构语义错误以 `BadTable(offset, detail)` 报告，`offset` 为输入缓冲区
/// 中的绝对字节偏移。全部可恢复、可定位，禁止 panic。
#derive(Debug)
pub suberror ArscError {
  Eof(Int32)
  BadChunk(Int32, UInt32)
  BadHeader(Int32, Int32)
  BadPool(Int32, String)
  BadIndex(Int32)
  BadTable(Int32, String)
}

///|
pub extend ArscError with Debug::{to_repr}

///|
/// `Res_value.dataType` 的完整枚举（AOSP `Res_value::TYPE_*` 全集）。
/// `Unknown` 保留原始类型字节以便上层降级而不丢失信息。
///
/// 语义标注：`DynamicReference` / `DynamicAttribute`（0x07/0x08）是需要经
/// `RES_TABLE_LIBRARY_TYPE` 动态包映射改写后才能使用的引用；本库**不做改写**，
/// 只按原样保留 id 并如实标注（见 API.md 降级项）。
pub(all) enum ResDataType {
  Null
  Reference
  Attribute
  String
  Float
  Dimension
  Fraction
  DynamicReference
  DynamicAttribute
  IntDec
  IntHex
  IntBoolean
  IntColorArgb8
  IntColorRgb8
  IntColorArgb4
  IntColorRgb4
  Unknown(Int32)
}

///|
/// 单个 `Res_value`：32 位数据 + 数据类型。
pub(all) struct ResValue {
  data_type : ResDataType
  data : UInt32
}

///|
/// 复杂条目（bag）内的一对 name/value 映射（AOSP `ResTable_map`）。
/// `name` 通常是属性资源 id；attr bag 中可能是 `ATTR_TYPE`（0x01000000）等内部 id。
pub(all) struct ResMap {
  name : UInt32
  value : ResValue
}

///|
/// 复杂条目（bag）：父资源 id + 映射数组（AOSP `ResTable_map_entry`）。
/// `parent` 为 0 表示无父；AOSP 视其为 TYPE_DYNAMIC_REFERENCE，本库保留原值。
pub(all) struct ResBag {
  parent : UInt32
  maps : Array[ResMap]
}

///|
/// 条目取值：简单值（含 compact 编码）或复杂 bag。
pub(all) enum ResEntryValue {
  Simple(ResValue)
  Complex(ResBag)
}

///|
/// 单个资源条目（AOSP `ResTable_entry`）。
/// `key` 为键名池下标，`key_name` 为解码后的键名（便捷冗余）；
/// `flags` 保留 FLAG_COMPLEX/FLAG_PUBLIC/FLAG_WEAK/FLAG_COMPACT 原始位。
pub(all) struct ResEntry {
  key : Int32
  key_name : String
  flags : Int32
  value : ResEntryValue
}

///|
/// 一个资源配置（AOSP `ResTable_config`）。
/// 常用 qualifier 字段逐项解出；未覆盖字段完整保留在 `raw`（原始 config 字节）中，
/// 按字段偏移解码，`size` 大于 36 时追加 localeScript 等扩展字段（降级见 API.md）。
pub(all) struct ResConfig {
  size : Int32
  mcc : Int32
  mnc : Int32
  language : String
  country : String
  orientation : Int32
  touchscreen : Int32
  density : Int32
  keyboard : Int32
  navigation : Int32
  input_flags : Int32
  screen_width : Int32
  screen_height : Int32
  sdk_version : Int32
  screen_layout : Int32
  ui_mode : Int32
  smallest_screen_width_dp : Int32
  screen_width_dp : Int32
  screen_height_dp : Int32
  locale_script : String
  color_mode : Int32
  raw : Bytes
}

///|
/// 一个（类型, 配置）资源组（AOSP `ResTable_type`）。
/// `flags` 保留 FLAG_SPARSE(0x01)/FLAG_OFFSET16(0x02) 原始位；
/// `entries` 下标即 entry index，`None` 表示该配置下此条目不存在（NO_ENTRY）。
pub(all) struct ResTypeConfig {
  id : Int32
  flags : Int32
  config : ResConfig
  entries : Array[ResEntry?]
}

///|
/// 一个资源类型（AOSP `ResTable_typeSpec` + 其全部配置变体）。
/// `id` 为 chunk 内原始类型 id（1-based）；资源 id 中的类型字节 = `id + type_id_offset`。
/// `spec_flags` 为每条目的配置掩码（含 SPEC_PUBLIC=0x40000000）。
pub(all) struct ResTypeSpec {
  id : Int32
  types_count : Int32
  entry_count : Int32
  spec_flags : Array[UInt32]
  configs : Array[ResTypeConfig]
}

///|
/// `RES_TABLE_LIBRARY_TYPE` 动态包映射项（仅供展示；本库不改写动态引用）。
pub(all) struct ResLibrary {
  package_id : Int32
  name : String
}

///|
/// 一个资源包（AOSP `ResTable_package`）。
/// `type_pool` / `key_pool` 为类型名池与键名池；`types` 按 chunk 顺序排列。
pub(all) struct ResPackage {
  id : Int32
  name : String
  type_id_offset : Int32
  type_pool : StringPool
  key_pool : StringPool
  types : Array[ResTypeSpec]
  libraries : Array[ResLibrary]
}

///|
/// resources.arsc 解析结果：全局值字符串池 + 包数组。
/// `package_count` 为 `ResTable_header.packageCount` 声明值（校验实际包数不超过它）。
pub(all) struct ResTable {
  global_pool : StringPool
  packages : Array[ResPackage]
  package_count : Int32
}

///|
/// 资源 id 查询命中：包/类型/条目名 + 最优配置与该配置下的条目。
pub(all) struct ResLookup {
  package_name : String
  type_name : String
  entry_name : String
  type_id : Int32
  entry_id : Int32
  config : ResConfig
  entry : ResEntry
}

///|
/// 属性值解析路径标注。
pub(all) enum ResolveOrigin {
  Literal
  FromId
  FromName
  Unresolved(String)
}

///|
/// 属性值解析结果：`text` 为解析后的人类可读值；`id` 为识别到的资源 id（非引用为 None）；
/// `origin` 标注解析路径或未解析原因。
pub(all) struct ResolvedAttr {
  text : String
  id : UInt32?
  origin : ResolveOrigin
}

///|
/// 解析一段完整 resources.arsc 字节流（含 RES_TABLE_TYPE 头，不含 ZIP 封装）。
///
/// - 参数：`data` 只读，调用方持有所有权，本函数不转移、不缓存。
/// - 返回：`ResTable` 纯值；无句柄、无需释放、可跨线程共享。
/// - 错误：`ArscError`，带字节偏移。偏移语义与 AXML 侧一致：`Eof(off)` 指被截断项
///   起始偏移；`BadChunk`/`BadHeader`/`BadTable` 的 offset 指出错结构起始。
/// - 校验：外层 header、全局字符串池、包头、类型池/键名池、typeSpec/type 的
///   entry offsets（dense u32 / FLAG_OFFSET16 u16 / FLAG_SPARSE 二分表）与
///   entry 边界均按 AOSP `LoadedArsc.cpp` 校验；违反即报错，不 panic。
/// - 降级：未知 chunk（如 overlayable/staged alias）按 headerSize/size 跳过；
///   未知 `Res_value.dataType` 保留在 `Unknown`；动态引用不改写（见 API.md §降级）。
pub fn parse_arsc(data : Bytes) -> ResTable raise ArscError {
  parse_table(data)
}

///|
/// 按包 id 查找包。
pub fn ResTable::package_by_id(self : ResTable, id : Int32) -> ResPackage? {
  for p in self.packages {
    if p.id == id {
      return Some(p)
    }
  }
  None
}

///|
/// 该配置是否为默认配置（全部 qualifier 字段为 0）。
/// 多配置选择策略据此实现「默认配置优先」（见 `ResTable::lookup`）。
pub fn ResConfig::is_default(self : ResConfig) -> Bool {
  self.mcc == 0 &&
  self.mnc == 0 &&
  self.language == "" &&
  self.country == "" &&
  self.orientation == 0 &&
  self.touchscreen == 0 &&
  self.density == 0 &&
  self.keyboard == 0 &&
  self.navigation == 0 &&
  self.input_flags == 0 &&
  self.screen_width == 0 &&
  self.screen_height == 0 &&
  self.sdk_version == 0 &&
  self.screen_layout == 0 &&
  self.ui_mode == 0 &&
  self.smallest_screen_width_dp == 0 &&
  self.screen_width_dp == 0 &&
  self.screen_height_dp == 0 &&
  self.locale_script == "" &&
  self.color_mode == 0
}

///|
/// 资源 id（0xPPTTNNNN）→ (package, type, name, 最优值) 查询。
///
/// 选择策略（文档化，D1）：**默认配置优先**——同一 (包,类型,条目) 存在多个
/// `ResTable_type` 配置变体时，返回 qualifier 全零（`ResConfig::is_default`）的
/// 配置中的条目；无默认配置时返回 chunk 顺序中的第一个命中配置。
/// **降级**：不做 aapt2 式 locale/density/SDK 的最优匹配（qualifier 选择属 D1 降级项）。
/// 未命中返回 `None`（包/类型/条目任一缺失均视为未命中，不报错）。
pub fn ResTable::lookup(self : ResTable, id : UInt32) -> ResLookup? {
  let hits = self.collect_hits(id)
  if hits.is_empty() {
    return None
  }
  let mut best = hits.at(0)
  for hit in hits {
    if hit.config.is_default() {
      best = hit
      break
    }
  }
  Some(best)
}

///|
/// 资源 id 的全部配置命中（按 chunk 顺序）。用于观察多配置差异。
pub fn ResTable::lookup_all(self : ResTable, id : UInt32) -> Array[ResLookup] {
  self.collect_hits(id)
}

///|
/// 收集某 id 在所有配置中的命中（chunk 顺序）。
fn ResTable::collect_hits(self : ResTable, id : UInt32) -> Array[ResLookup] {
  let out : Array[ResLookup] = []
  let pkg_id = ((id >> 24) & 255U).reinterpret_as_int()
  let type_id = ((id >> 16) & 255U).reinterpret_as_int()
  let entry_id = (id & 65535U).reinterpret_as_int()
  for p in self.packages {
    if p.id != pkg_id {
      continue
    }
    for spec in p.types {
      if spec.id + p.type_id_offset != type_id {
        continue
      }
      let type_name = pool_string(p.type_pool, spec.id - p.type_id_offset - 1)
      for cfg in spec.configs {
        if entry_id < cfg.entries.length() {
          match cfg.entries.at(entry_id) {
            Some(entry) =>
              out.push({
                package_name: p.name,
                type_name,
                entry_name: entry.key_name,
                type_id,
                entry_id,
                config: cfg.config,
                entry,
              })
            None => ()
          }
        }
      }
    }
  }
  out
}

///|
/// 按名字查资源 id：(类型名, 条目名) → id。
///
/// 多个包命中时取 `packages` 顺序中的第一个；同名类型存在于多个类型 id 时
/// （如 framework 的 attr 与 ^attr-private）按类型 id 升序取第一个命中。
/// 未命中返回 `None`。
pub fn ResTable::find_id(
  self : ResTable,
  type_name : String,
  entry_name : String,
) -> UInt32? {
  for p in self.packages {
    for spec in p.types {
      let idx = spec.id - p.type_id_offset - 1
      if pool_string(p.type_pool, idx) == type_name {
        for cfg in spec.configs {
          let mut i = 0
          while i < cfg.entries.length() {
            match cfg.entries.at(i) {
              Some(entry) =>
                if entry.key_name == entry_name {
                  let id = ((p.id.reinterpret_as_uint() & 255U) << 24) |
                    (
                      (
                        (spec.id + p.type_id_offset).reinterpret_as_uint() &
                        255U
                      ) <<
                      16
                    ) |
                    (i.reinterpret_as_uint() & 65535U)
                  return Some(id)
                }
              None => ()
            }
            i = i + 1
          }
        }
      }
    }
  }
  None
}

///|
/// 读字符串池第 `index` 项；越界返回 None（查询路径降级，不报错）。
fn pool_string(pool : StringPool, index : Int32) -> String {
  if index < 0 || index >= pool.strings.length() {
    return "(invalid string index \{index})"
  }
  pool.strings.at(index)
}

///|
/// `Res_value` → 人类可读文本（aapt2 dump resources 风格）。
///
/// 渲染规则（文档化）：dimension/fraction/float 用 6 位小数（如 `48.000000dp`、
/// `3.000000%`）；颜色为小写 `#aarrggbb`/`#rrggbb`/`#argb`/`#rgb`（AOSP
/// printf 最小宽度语义，高位非零时输出更多数位）；布尔 `true/false`；
/// 整数十进制、十六进制 `0x%08x`；字符串取原值（aapt2 在 dump 中会额外加引号）；
/// 引用渲染为 `@type/name`（表内可解析时）或 `@0x%08x`；动态引用以 `(dynamic)`
/// 后缀如实标注（不改写 id）。
pub fn ResTable::format_value(self : ResTable, value : ResValue) -> String {
  match value.data_type {
    Null => if value.data == 0U { "(null)" } else { "(empty)" }
    Reference => self.format_ref(value.data)
    Attribute => "?\{self.format_ref(value.data)}"
    DynamicReference => "\{self.format_ref(value.data)} (dynamic)"
    DynamicAttribute => "?\{self.format_ref(value.data)} (dynamic)"
    String => pool_string(self.global_pool, value.data.reinterpret_as_int())
    Float => fixed6(Float::reinterpret_from_uint(value.data).to_double())
    Dimension => complex_number(value.data, false)
    Fraction => complex_number(value.data, true)
    IntDec => "\{value.data.reinterpret_as_int()}"
    IntHex => "0x\{hex8(value.data)}"
    IntBoolean => if value.data == 0U { "false" } else { "true" }
    IntColorArgb8 => "#\{hex_min(value.data, 8)}"
    IntColorRgb8 => "#\{hex_min(value.data, 6)}"
    IntColorArgb4 => "#\{hex_min(value.data, 4)}"
    IntColorRgb4 => "#\{hex_min(value.data, 3)}"
    Unknown(t) =>
      "(unknown type 0x\{hex2(t.reinterpret_as_uint())}=0x\{hex8(value.data)})"
  }
}

///|
/// 引用 id → `@type/name`（表内可解析）或 `@0x%08x`（不可解析）。
fn ResTable::format_ref(self : ResTable, id : UInt32) -> String {
  let hits = self.collect_hits(id)
  if hits.is_empty() {
    return "@0x\{hex8(id)}"
  }
  let hit = hits.at(0)
  "@\{hit.type_name}/\{hit.entry_name}"
}

///|
/// 资源 id → 人类可读值：跟随引用链到最终值（带环检测，深度上限 16）。
///
/// - 简单值：返回 `format_value` 文本（字符串直接是其值，如 `app_name` → `MyApp`）。
/// - 引用：递归解析；成环/超深以 `@0x%08x (cycle)` / `@0x%08x (too deep)` 标注。
/// - 复杂条目（bag）：渲染为 `@type/name`（bag 无法压平成单一文本，属文档化降级）。
/// - 未命中：`@0x%08x`。**不抛错**——全部缺口以文本如实标注。
pub fn ResTable::resolve_id(self : ResTable, id : UInt32) -> String {
  self.resolve_id_depth(id, 0)
}

///|
/// 带深度的引用解析。
fn ResTable::resolve_id_depth(
  self : ResTable,
  id : UInt32,
  depth : Int32,
) -> String {
  if depth > 16 {
    return "@0x\{hex8(id)} (too deep)"
  }
  match self.lookup(id) {
    None => "@0x\{hex8(id)}"
    Some(hit) =>
      match hit.entry.value {
        Simple(v) =>
          match v.data_type {
            Reference =>
              if v.data == id {
                "@0x\{hex8(id)} (self reference)"
              } else {
                self.resolve_id_depth(v.data, depth + 1)
              }
            DynamicReference =>
              "\{self.resolve_id_depth(v.data, depth + 1)} (dynamic)"
            _ => self.format_value(v)
          }
        Complex(_) => "@\{hit.type_name}/\{hit.entry_name}"
      }
  }
}

///|
/// AXML 属性值 → 人类可读值（AXML 文档 + 资源表联合解析）。
///
/// 解析顺序（文档化）：
/// 1. `value_type` 为 `Reference`/`Attribute`/动态引用：按 `raw_data` 中的
///    0xPPTTNNNN 解析（`FromId`，id 是权威来源）；
/// 2. `raw_value` 形如 `@type/name` / `@pkg:type/name` / `@0x...`：按名字/十六进制
///    定位后解析（`FromName` / `FromId`），覆盖 `@string/xxx` 文本形式输入；
/// 3. `value_type` 为 `String`：取 AXML 文档字符串池中的字面量（`Literal`）；
/// 4. 其余类型（int/bool/color/dimension 等）：按 `format_value` 文本化（`Literal`）。
///
/// 任何缺口（id 不在表、名字未命中、字符串索引越界）都不抛错，返回
/// `Unresolved(原因)` 并保留可读的原始文本。**不解析** `?attr/theme` 引用链
/// （属性引用的语义解析属 D1 降级项，见 API.md）。
pub fn resolve_attr_value(
  doc : AxmlDoc,
  table : ResTable,
  attr : XmlAttribute,
) -> ResolvedAttr {
  let dt = res_data_type_of_attr(attr.value_type, attr.raw_data)
  match dt {
    Reference | Attribute | DynamicReference | DynamicAttribute => {
      let id = attr.raw_data
      match table.lookup(id) {
        Some(_) =>
          {
            text: if dt is DynamicReference || dt is DynamicAttribute {
              "\{table.resolve_id(id)} (dynamic)"
            } else {
              table.resolve_id(id)
            },
            id: Some(id),
            origin: if dt is DynamicReference || dt is DynamicAttribute {
              Unresolved(
                "动态引用未改写（RES_TABLE_LIBRARY_TYPE 映射不生效）",
              )
            } else {
              FromId
            },
          }
        None =>
          {
            text: "@0x\{hex8(id)}",
            id: Some(id),
            origin: Unresolved("资源 id 不在表中"),
          }
      }
    }
    _ =>
      match attr.raw_value {
        Some(raw) =>
          match try_resolve_raw_ref(table, raw) {
            Some(hit) => hit
            None => resolve_attr_literal(doc, table, attr, dt)
          }
        None => resolve_attr_literal(doc, table, attr, dt)
      }
  }
}

///|
/// 非引用属性值的文本化（String 取 AXML 池字面量，其余按 `format_value`）。
fn resolve_attr_literal(
  doc : AxmlDoc,
  table : ResTable,
  attr : XmlAttribute,
  dt : ResDataType,
) -> ResolvedAttr {
  match dt {
    String =>
      match safe_string_at(doc, attr.raw_data.reinterpret_as_int()) {
        Some(s) => { text: s, id: None, origin: Literal, }
        None =>
          {
            text: attr.raw_value.unwrap_or(
              "(invalid string index \{attr.raw_data.reinterpret_as_int()})",
            ),
            id: None,
            origin: Unresolved("AXML 字符串池下标越界"),
          }
      }
    _ =>
      match attr.raw_value {
        Some(raw) => { text: raw, id: None, origin: Literal, }
        None =>
          {
            text: table.format_value({ data_type: dt, data: attr.raw_data, }),
            id: None,
            origin: Literal,
          }
      }
  }
}

///|
/// `raw_value` 文本中的引用形式解析：`@type/name`、`@pkg:type/name`、`@0x%08x`。
/// 返回 `None` 表示输入不是引用形式（普通字面量/非法引用名），由调用方按字面量降级。
fn try_resolve_raw_ref(table : ResTable, raw : String) -> ResolvedAttr? {
  if raw.has_prefix("@0x") || raw.has_prefix("@0X") {
    match parse_hex_id(raw[3:].to_owned()) {
      Some(id) =>
        match table.lookup(id) {
          Some(_) =>
            Some({ text: table.resolve_id(id), id: Some(id), origin: FromId, })
          None =>
            Some({
              text: "@0x\{hex8(id)}",
              id: Some(id),
              origin: Unresolved("资源 id 不在表中"),
            })
        }
      None => None
    }
  } else if raw.has_prefix("@") {
    match parse_ref_name(raw[1:].to_owned()) {
      Some((type_name, entry_name)) =>
        match table.find_id(type_name, entry_name) {
          Some(id) =>
            Some({ text: table.resolve_id(id), id: Some(id), origin: FromName, })
          None =>
            Some({
              text: raw,
              id: None,
              origin: Unresolved("表中无该名字的资源"),
            })
        }
      None => None
    }
  } else {
    None
  }
}

///|
/// `pkg:type/name` 或 `type/name` → (type_name, entry_name)；包名前缀忽略
/// （本库不支持跨包名字解析，属文档化降级）。
fn parse_ref_name(s : String) -> (String, String)? {
  let mut body = s
  match body.find(":") {
    Some(colon) => body = body[colon + 1:].to_owned()
    None => ()
  }
  match body.find("/") {
    Some(slash) => Some((body[:slash].to_owned(), body[slash + 1:].to_owned()))
    None => None
  }
}

///|
/// 十六进制资源 id 文本（不含 `0x` 前缀）→ UInt32。
fn parse_hex_id(s : String) -> UInt32? {
  if s.is_empty() || s.length() > 8 {
    return None
  }
  let mut acc = 0U
  for c in s {
    let d = match c {
      '0' => Some(0)
      '1' => Some(1)
      '2' => Some(2)
      '3' => Some(3)
      '4' => Some(4)
      '5' => Some(5)
      '6' => Some(6)
      '7' => Some(7)
      '8' => Some(8)
      '9' => Some(9)
      'a' | 'A' => Some(10)
      'b' | 'B' => Some(11)
      'c' | 'C' => Some(12)
      'd' | 'D' => Some(13)
      'e' | 'E' => Some(14)
      'f' | 'F' => Some(15)
      _ => None
    }
    match d {
      Some(v) => acc = (acc << 4) | v.reinterpret_as_uint()
      None => return None
    }
  }
  Some(acc)
}

///|
/// AXML 侧 `ValueType` → 资源表侧 `ResDataType`（`Unknown` 用完整映射补齐）。
fn res_data_type_of_attr(vt : ValueType, raw : UInt32) -> ResDataType {
  match vt {
    Null => Null
    Reference => Reference
    Attribute => Attribute
    String => String
    Float => Float
    Dimension => Dimension
    Fraction => Fraction
    IntDec => IntDec
    IntHex => IntHex
    IntBoolean => IntBoolean
    Unknown(t) => {
      ignore(raw)
      res_data_type_of(t)
    }
  }
}

///|
/// 安全读取 AXML 文档字符串池（越界返回 None）。
fn safe_string_at(doc : AxmlDoc, index : Int32) -> String? {
  if index < 0 || index >= doc.pool.strings.length() {
    return None
  }
  Some(doc.pool.strings.at(index))
}

///|
/// `Res_value.dataType` 字节 → `ResDataType`（AOSP `Res_value::TYPE_*` 全集）。
fn res_data_type_of(data_type : Int32) -> ResDataType {
  match data_type {
    0x00 => Null
    0x01 => Reference
    0x02 => Attribute
    0x03 => String
    0x04 => Float
    0x05 => Dimension
    0x06 => Fraction
    0x07 => DynamicReference
    0x08 => DynamicAttribute
    0x10 => IntDec
    0x11 => IntHex
    0x12 => IntBoolean
    0x1c => IntColorArgb8
    0x1d => IntColorRgb8
    0x1e => IntColorArgb4
    0x1f => IntColorRgb4
    _ => Unknown(data_type)
  }
}

///|
/// 复杂数值解码（AOSP `Res_value::COMPLEX_*`）：dimension/fraction。
/// data 布局：bit0-3 单位、bit4-5 radix、bit8-31 有符号 23 位尾数。
/// fraction 按 aapt2 风格 ×100 渲染为百分数。
fn complex_number(data : UInt32, is_fraction : Bool) -> String {
  let unit = (data & 15U).reinterpret_as_int()
  let radix = ((data >> 4) & 3U).reinterpret_as_int()
  let mbits = (data >> 8) & 16777215U
  let mut v = mbits.to_double()
  if mbits >= 8388608U {
    v = v - 16777216.0
  }
  if radix == 1 {
    v = v / 128.0
  } else if radix == 2 {
    v = v / 32768.0
  } else if radix == 3 {
    v = v / 8388608.0
  }
  if is_fraction {
    // 与 aapt2 dump resources 一致：分数按原始 complex 值 + `%` 渲染，不乘 100。
    let suffix = if unit == 1 { "%p" } else { "%" }
    "\{fixed6(v)}\{suffix}"
  } else {
    let unit_name = match unit {
      0 => "px"
      1 => "dp"
      2 => "sp"
      3 => "pt"
      4 => "in"
      5 => "mm"
      _ => "(unit\{unit})"
    }
    "\{fixed6(v)}\{unit_name}"
  }
}

///|
/// 6 位定点小数渲染（aapt2 `%f` 风格）。
fn fixed6(x : Double) -> String {
  let neg = x < 0.0
  let a = if neg { 0.0 - x } else { x }
  let ip = a.floor()
  let mut frac = ((a - ip) * 1000000.0).round()
  let mut whole = ip
  if frac >= 1000000.0 {
    whole = whole + 1.0
    frac = 0.0
  }
  let mut digits = "\{frac.to_int()}"
  while digits.length() < 6 {
    digits = "0" + digits
  }
  let sign = if neg { "-" } else { "" }
  "\{sign}\{whole.to_int()}.\{digits}"
}

///|
/// 颜色/十六进制渲染（AOSP `ResTable::valueToString` 的 printf 语义：
/// `%08x/%06x/%04x/%03x` 为**最小宽度**，数据高位非零时输出更多数位，
/// 不做掩码截断；如 RGB4 + 0xffaaaaaa 渲染为 `#ffaaaaaa`，与 aapt2 一致）。
fn hex_min(v : UInt32, width : Int32) -> String {
  let digits = "0123456789abcdef"
  let mut s = ""
  let mut x = v
  let mut n = 0
  while n < 8 {
    let d = (x & 15U).to_byte().to_int()
    s = digits[d:d + 1].to_owned() + s
    x = x >> 4
    n = n + 1
    if x == 0U {
      break
    }
  }
  while s.length() < width {
    s = "0" + s
  }
  s
}

///|
/// 8 位小写十六进制（资源 id / `%08x`）。
fn hex8(v : UInt32) -> String {
  hex_min(v, 8)
}

///|
/// 2 位小写十六进制。
fn hex2(v : UInt32) -> String {
  let digits = "0123456789abcdef"
  let hi = ((v >> 4) & 15U).to_byte().to_int()
  let lo = (v & 15U).to_byte().to_int()
  digits[hi:hi + 1].to_owned() + digits[lo:lo + 1].to_owned()
}
