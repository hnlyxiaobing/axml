# axml · 公开 API（API.md）

> 与 `pkg.generated.mbti` 快照逐项对账（2026-11-07，resources.arsc 解析链为加法性新增）。全部函数均为**真实实现**，包内**没有 `declare` 存根**；`moon check --deny-warn` 0 error / 0 warning。
> 错误传播：AXML 侧统一 `raise AxmlError`，resources.arsc 侧统一 `raise ArscError`；无外部句柄、无释放函数（本库不存在 close/detach 语义）。
> 本包**不导出任何 trait**：`DocumentView` 已删除——其 `elements(Self) -> Array[XmlNode]` 无 `raise`，与 `AxmlDoc::elements` 的 `raise AxmlError` 不兼容，且全仓无实现者、无消费者。`AxmlDoc::elements` / `AxmlDoc::string_at` 保留为具体方法（见下表）。

## 类型

| 类型 | 种类 | 说明 |
|---|---|---|
| `AxmlDoc` | `pub(all) struct` | 解析结果；`pool` / `nodes` / `roots` / `resource_map` |
| `StringPool` | `pub(all) struct` | 字符串池；`encoding` / `strings` / `styles` |
| `XmlNode` | `pub(all) struct` | 节点；`children` / `parent` 用 `nodes` 索引 |
| `XmlAttribute` | `pub(all) struct` | typed attribute；`res0` / `raw_data` 保留原值 |
| `ChunkType` | `pub(all) enum` | `RES_STRING_POOL_TYPE` / `RES_XML_*` 类别 |
| `StringEncoding` | `pub(all) enum` | `Utf8` / `Utf16` |
| `ValueType` | `pub(all) enum` | `Res_value.dataType` 子集 + `Unknown(Int32)` |
| `AxmlError` | `pub suberror`（`#derive(Debug)`，导出 `AxmlError::to_repr`） | 8 个带偏移/索引的错误构造 |
| `StringIndex` / `NodeIndex` | `pub type` | `Int32` 别名 |

可见性关键字以快照为准：结构体/枚举为 `pub(all)`，错误为 `pub suberror`，别名为 `pub type`；本包无 `pub(open)` trait。

## 函数签名

| 签名 | 参数与所有权 | 返回 / 错误 | 资源与线程约束 | 剩余 TODO |
|---|---|---|---|---|
| `parse(data : Bytes) -> AxmlDoc raise AxmlError` | `data` 只读，调用方持有；不缓存、不转移 | `AxmlDoc` 纯值 / `AxmlError`（带字节偏移） | 无句柄；纯函数可并发；返回值只读 | `res0`/`data` 语义解释（当前按 API.md 保留原值） |
| `AxmlDoc::elements(self) -> Array[XmlNode] raise AxmlError` | `self` 只读 | 按 chunk 顺序的元素节点（已过滤 `CData` 等非元素节点）/ `InvalidNodeIndex`（索引表校验失败） | 无状态 | — |
| `AxmlDoc::string_at(self, index : StringIndex) -> String raise AxmlError` | `self` 只读；`index` 为池下标 | 解码后字符串 / `InvalidStringIndex(index)` | 无状态 | — |
| `AxmlDoc::node_at(self, index : NodeIndex) -> XmlNode raise AxmlError` | 同上 | 节点 / `InvalidNodeIndex(index)` | 无状态 | — |
| `XmlNode::attrs(self) -> Array[XmlAttribute]` | `self` 只读 | 原始顺序属性列表（不去重、不解析命名空间） | 无错误、无状态 | — |

## 错误构造速查

`UnexpectedEof(Int32)` · `BadChunkType(Int32, UInt32)` · `BadHeaderSize(Int32, Int32)` · `BadStringPool(Int32, String)` · `InvalidStringIndex(Int32)` · `InvalidNodeIndex(Int32)` · `UnsupportedEncoding(String)` · `VendorVariant(String)`

（与 `pkg.generated.mbti` 的 `AxmlError` 块逐项一致，共 8 个变体；`AxmlError` 可见性维持 `pub suberror` 现状，不放宽。）

## 非目标（明确不在 API 内）

manifest 语义、回编、厂商变体自动修复、跨格式通用接口、任何 trait 形式的视图/遍历契约；
resources.arsc 侧：动态引用改写（`RES_TABLE_LIBRARY_TYPE` 映射不生效）、aapt2 式
qualifier 最优匹配、overlay（RRO/idmap）语义、继承包、bag 压平、`?attr` 主题引用链
（详见下文降级项）。

> **加法性新增（2026-11-07）**：resources.arsc 解析链落地，原「不处理
> `resources.arsc`」的非目标相应收窄为上述降级项；AXML 侧公开签名冻结不动
> （快照 diff 为纯新增 153 行、0 删除）。

## resources.arsc 解析 API（加法性新增）

### 类型

| 类型 | 种类 | 说明 |
|---|---|---|
| `ResTable` | `pub(all) struct` | 解析结果：`global_pool : StringPool` / `packages : Array[ResPackage]` / `package_count : Int32` |
| `ResPackage` | `pub(all) struct` | 资源包：`id` / `name` / `type_id_offset` / `type_pool` / `key_pool` / `types` / `libraries` |
| `ResTypeSpec` | `pub(all) struct` | 类型：`id`（chunk 原始 id，资源 id 类型字节 = `id + type_id_offset`）/ `types_count` / `entry_count` / `spec_flags` / `configs` |
| `ResTypeConfig` | `pub(all) struct` | (类型,配置) 组：`id` / `flags`（FLAG_SPARSE/FLAG_OFFSET16 原值）/ `config` / `entries : Array[ResEntry?]`（下标即 entry index，`None`=NO_ENTRY） |
| `ResConfig` | `pub(all) struct` | 22 字段配置视图 + `raw : Bytes` 原始字节；`is_default(Self) -> Bool` |
| `ResEntry` | `pub(all) struct` | 条目：`key` / `key_name` / `flags` / `value` |
| `ResEntryValue` | `pub(all) enum` | `Simple(ResValue)` / `Complex(ResBag)` |
| `ResBag` | `pub(all) struct` | bag：`parent : UInt32` + `maps : Array[ResMap]` |
| `ResMap` | `pub(all) struct` | bag 映射：`name : UInt32` + `value : ResValue` |
| `ResValue` | `pub(all) struct` | `data_type : ResDataType` + `data : UInt32` |
| `ResDataType` | `pub(all) enum` | AOSP `TYPE_*` 全集 16 变体 + `Unknown(Int32)` |
| `ResLookup` | `pub(all) struct` | 命中：`package_name` / `type_name` / `entry_name` / `type_id` / `entry_id` / `config` / `entry` |
| `ResolvedAttr` | `pub(all) struct` | 属性解析结果：`text : String`（人类可读值）/ `id : UInt32?` / `origin : ResolveOrigin` |
| `ResolveOrigin` | `pub(all) enum` | `Literal` / `FromId` / `FromName` / `Unresolved(String)` |
| `ResLibrary` | `pub(all) struct` | 动态包映射项：`package_id` / `name`（仅展示） |
| `ArscError` | `pub suberror`（`#derive(Debug)`，导出 `to_repr`） | 12 个变体（R4 增 `BadQualifier/BagNotComplex/BagMissingParent/BagCycle/AttrMissing/AttrCycle`），见下 |
| `FlattenedBag` | `pub(all) struct` | R4：`id : UInt32` + `attrs : Array[ResMap]`（parent 链压平后的最终映射，保序、子值覆盖） |

### 函数签名

| 签名 | 语义 | 错误/降级 |
|---|---|---|
| `parse_arsc(data : Bytes) -> ResTable raise ArscError` | resources.arsc 全量解析（表头/全局池/包/类型池/键名池/typeSpec/type/entry/Res_value） | 结构违反 AOSP 约束即带偏移报错；未知 chunk 跳过 |
| `ResTable::lookup(Self, UInt32) -> ResLookup?` | id(0xPPTTNNNN) → (包,类型,名,最优值)；**默认配置优先**（qualifier 全零者胜，否则 chunk 顺序首个命中） | 未命中 `None`；不做 aapt2 式 qualifier 最优匹配（降级） |
| `ResTable::lookup_all(Self, UInt32) -> Array[ResLookup]` | 全部配置命中（chunk 顺序） | — |
| `ResTable::find_id(Self, String, String) -> UInt32?` | (类型名, 条目名) → id；多包/多类型同名取首个命中 | 未命中 `None` |
| `ResTable::package_by_id(Self, Int32) -> ResPackage?` | 包 id 查找 | — |
| `ResTable::format_value(Self, ResValue) -> String` | 值 → 人类可读文本（aapt2 dump resources 风格，见渲染规则） | 字符串索引越界降级为标注文本 |
| `ResTable::resolve_id(Self, UInt32) -> String` | id → 人类可读值，跟随引用链（深度≤16、环检测）；简单值直取、bag 渲染 `@type/name` | 未命中/成环/超深以 `@0x%08x` + 标注降级，不抛错 |
| `resolve_attr_value(AxmlDoc, ResTable, XmlAttribute) -> ResolvedAttr` | AXML 属性 → 人类可读值（`ResolvedAttr.text`）；解析顺序：typed Reference/Attribute id（FromId）→ `raw_value` 的 `@type/name`/`@0x...` 文本形式（FromName/FromId）→ String 池字面量/typed 字面量（Literal） | 一切缺口 `Unresolved(原因)`，不抛错；动态引用文本带 `(dynamic)` 并标 `Unresolved` |
| `ResConfig::is_default(Self) -> Bool` | qualifier 全零判定（lookup 选择策略基础） | — |
| `ResConfig::from_qualifiers(String) -> ResConfig raise ArscError` | R4：限定符文本 → 配置（`mcc310`/`en-rUS`/`sw600dp`/`land`/`night`/`xhdpi` 等子集） | 未知 token 报 `BadQualifier` |
| `ResConfig::matches(Self, ResConfig) -> Bool` | R4：资源配置能否作用于设备配置（未指定维度 = 任意；尺寸/SDK 取上界；密度 anydpi/nodpi = 任意） | — |
| `ResConfig::is_better_than(Self, ResConfig, ResConfig) -> Bool` | R4：逐维优先级比较（通配劣于具体、尺寸取接近上界、密度精确优先再取高密度）；调用方应先 `matches` 过滤 | — |
| `ResTable::lookup_with(Self, UInt32, ResConfig) -> ResLookup?` | R4：按设备配置做 aapt2 式最优匹配（`lookup_all` + `matches` + `is_better_than`） | 无匹配 `None`（可回退 `lookup`） |
| `ResTable::flatten_bag(Self, UInt32, ResConfig) -> FlattenedBag raise ArscError` | R4：bag parent 继承链压平（自根向子覆盖同名 map） | 非复杂条目 `BagNotComplex`；parent 缺失 `BagMissingParent`；成环 `BagCycle` |
| `ResTable::eval_theme_attr(Self, UInt32, UInt32, ResConfig) -> ResValue raise ArscError` | R4：`?attr` 主题求值（跨 `Attribute`/`DynamicAttribute` 多级链；普通 `@ref` 为终点） | 缺失 `AttrMissing`；成环 `AttrCycle` |

### 值渲染规则（`format_value`，与 aapt2 dump resources 对齐）

- dimension/fraction/float：6 位小数（`48.000000dp` / `3.000000%` / `1.500000`）；
  fraction 按**原始 complex 值 + `%`** 渲染（不乘 100，与 aapt2 一致）；单位
  `px/dp/sp/pt/in/mm`，fraction-parent 为 `%p`。
- 颜色：`#aarrggbb`/`#rrggbb`/`#argb`/`#rgb`，AOSP printf **最小宽度**语义
  （`%08x/%06x/%04x/%03x`，高位非零输出更多数位，如 RGB4+0xffaaaaaa → `#ffaaaaaa`）。
- 整数：十进制（有符号）/ `0x%08x`；布尔 `true/false`；null `(null)`/`(empty)`。
- 字符串：池原值（aapt2 dump 会额外加引号，本库输出裸串）。
- 引用：`@type/name`（可解析）或 `@0x%08x`；属性引用 `?type/name`；动态引用追加
  ` (dynamic)` 并在 `ResolveOrigin` 标注未改写。
- 未知 dataType：`(unknown type 0x%02x=0x%08x)` 保留原值。

### 错误构造速查（ArscError）

`Eof(Int32)` · `BadChunk(Int32, UInt32)` · `BadHeader(Int32, Int32)` · `BadPool(Int32, String)` · `BadIndex(Int32)` · `BadTable(Int32, String)`
（字节层/字符串池层由 `AxmlError` 映射而来，偏移语义与 AXML 侧一致；`BadTable` 为
资源表结构语义错误。）

### 降级项（如实标注）

1. **qualifier 选择**：多配置只做「默认配置优先 + chunk 顺序」，不做 locale/density/SDK 最优匹配；
2. **动态引用**：`TYPE_DYNAMIC_REFERENCE/ATTRIBUTE` 与 bag parent 不做运行时包映射改写，原 id 保留并标注 `(dynamic)`；
3. **overlay**：`RES_TABLE_OVERLAYABLE/POLICY/STAGED_ALIAS` chunk 跳过不解释；idmap/RRO 语义不支持；
4. **继承包**：`typeStrings/keyStrings == 0` 的继承包报 `BadTable`（不支持）；
5. **bag**：不压平 map 继承链，`resolve_id` 对 bag 渲染 `@type/name`；
6. **`?attr` 引用链**：属性引用只解析到属性条目，不做主题求值；
7. **ResTable_config**：常用 qualifier 字段解码，其余保留在 `raw`；BCP-47 扩展（localeVariant/numbering system）不解包；
8. **compact entry**：按 AOSP 内联解码支持（key u16 + flags 高字节 dataType），无降级；sparse/OFFSET16 按 AOSP 语义支持。

## 状态

| 门禁 | 结果 |
|---|---|
| `moon clean` | ✅ exit 0 |
| `moon check --deny-warn` | ✅ exit 0（0 error / 0 warning） |
| `moon build` | ✅ exit 0 |
| `moon test` | ✅ exit 0，90/90（AXML 黑盒 26 + AXML 白盒 14 + arsc 黑盒 17 + arsc 白盒 6 + 真实样本黄金/畸形系列 27） |
| `moon fmt --check` | ✅ exit 0 |

API 快照：`pkg.generated.mbti`（`moon info` 再生成：**+153 行 / -0 行**，纯加法性，
AXML 侧冻结签名逐字未动）。实现：`arsc.mbt`（类型/查询/解析/渲染）+ `arsc_decode.mbt`
（chunk 级解码，不导出），全部真实实现、无 `declare` 存根。
