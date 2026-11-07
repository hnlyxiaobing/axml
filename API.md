# axml · 公开 API（API.md）

> 与 `pkg.generated.mbti` 一致。全部函数均为 `declare`（**无实现**，`moon check` 产生预期 `0068` 告警）。
> 错误传播统一为 `raise AxmlError`；无外部句柄、无释放函数。

## 类型

| 类型 | 种类 | 说明 |
|---|---|---|
| `AxmlDoc` | `pub(all) struct` | 解析结果；`pool` / `nodes` / `roots` / `resource_map` |
| `StringPool` | `pub(all) struct` | 字符串池；`encoding` / `strings` / `styles` |
| `XmlNode` | `pub(all) struct` | 节点；`children` / `parent` 用 `nodes` 索引 |
| `XmlAttribute` | `pub(all) struct` | typed attribute；`res0` / `raw_data` 保留原值 |
| `ChunkType` | `pub(all) enum` | `RES_STRING_POOL_TYPE` / `RES_XML_*` 类别 |
| `StringEncoding` | `pub(all) enum` | `Utf8` / `Utf16` |
| `ValueType` | `pub(all) enum` | `Res_value.dataType` 子集 + `Unknown(Int)` |
| `AxmlError` | `pub suberror` | 8 个带偏移/索引的错误构造 |
| `StringIndex` / `NodeIndex` | `pub type` | `Int` 别名 |
| `DocumentView` | `pub trait` | `elements` / `string_at` 只读视图契约 |

## 函数签名

| 签名 | 参数与所有权 | 返回 / 错误 | 资源与线程约束 | TODO |
|---|---|---|---|---|
| `parse(data : Bytes) -> AxmlDoc raise AxmlError` | `data` 只读，调用方持有；不缓存、不转移 | `AxmlDoc` 纯值 / `AxmlError`（带字节偏移） | 无句柄；纯函数可并发；返回值只读 | UTF-8/UTF-16 解码、res0/data 语义、厂商变体降级 |
| `AxmlDoc::elements(self) -> Array[XmlNode] raise AxmlError` | `self` 只读 | 按 chunk 顺序的元素节点 / `InvalidNodeIndex` 等 | 无状态 | 过滤 `XmlTree` / `CData` 等非元素节点 |
| `AxmlDoc::string_at(self, index : StringIndex) -> String raise AxmlError` | `self` 只读；`index` 为池下标 | 解码后字符串 / `InvalidStringIndex(index)` | 无状态 | 越界与非法编码处理 |
| `AxmlDoc::node_at(self, index : NodeIndex) -> XmlNode raise AxmlError` | 同上 | 节点 / `InvalidNodeIndex(index)` | 无状态 | 索引校验 |
| `XmlNode::attrs(self) -> Array[XmlAttribute]` | `self` 只读 | 原始顺序属性列表（不去重、不解析命名空间） | 无错误、无状态 | — |

## 错误构造速查

`UnexpectedEof(offset)` · `BadChunkType(offset, found)` · `BadHeaderSize(offset, found)` · `BadStringPool(offset, detail)` · `InvalidStringIndex(index)` · `InvalidNodeIndex(index)` · `UnsupportedEncoding(detail)` · `VendorVariant(detail)`

## 非目标（明确不在 API 内）

资源引用解析、manifest 语义、`resources.arsc`、回编、厂商变体自动修复、跨格式通用接口。

## 状态

`moon check`：✅ 0 error，5 × `0068`。API 快照：`pkg.generated.mbti`。实现：❌ 后续轮。
