# axml · 公开 API（API.md）

> 与 `pkg.generated.mbti` 快照逐项对账（R2 冻结前整改，2026-11-07）。全部函数均为**真实实现**，包内**没有 `declare` 存根**；`moon check --deny-warn` 0 error / 0 warning。
> 错误传播统一为 `raise AxmlError`；无外部句柄、无释放函数（本库不存在 close/detach 语义）。
> 本包**不导出任何 trait**：`DocumentView` 已在 R2 删除——其 `elements(Self) -> Array[XmlNode]` 无 `raise`，与 `AxmlDoc::elements` 的 `raise AxmlError` 不兼容，且全仓无实现者、无消费者。`AxmlDoc::elements` / `AxmlDoc::string_at` 保留为具体方法（见下表）。

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

（与 `pkg.generated.mbti` 的 `AxmlError` 块逐项一致，共 8 个变体；`AxmlError` 可见性维持 `pub suberror` 现状，本轮不放宽。）

## 非目标（明确不在 API 内）

资源引用解析、manifest 语义、`resources.arsc`、回编、厂商变体自动修复、跨格式通用接口、任何 trait 形式的视图/遍历契约。

## 状态

| 门禁 | 结果 |
|---|---|
| `moon check --deny-warn` | ✅ 0 error / 0 warning（无 `0068`：包内已无 `declare`） |
| `moon build` | ✅ |
| `moon test` | ✅ 40 / 40 |
| `moon fmt --check` | ✅ |

API 快照：`pkg.generated.mbti`。本轮**未运行 `moon info`、未手工编辑快照**；删除 `DocumentView` 后的接口差异由 moon 工具链在执行规定的门禁命令（`moon check --deny-warn` / `moon build`）时自动同步（diff 仅为该 trait 块的移除），最终快照再生成与复核仍由主控统一执行。实现：✅ `parse` 与全部访问器均为真实实现；唯一保留的 TODO 是 `res0`/`data` 的语义解释。
