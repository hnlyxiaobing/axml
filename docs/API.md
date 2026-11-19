# axml API 与降级登记

> 建立：2026-11-19 ｜ 承接所有源码注释中 `docs/API.md` / `docs/DESIGN.md` 的降级与边界登记

## 1. 降级项（全部为冻结语义，见开发文档边界裁决 §3）

| # | 能力 | 现状语义 | 归属裁决 |
|---|---|---|---|
| D1 | 动态引用（ResDataType 0x07/0x08） | 旧 API `resolve_id` 恒输出 `(dynamic)` 文本；`resolve_attr_value` 恒 `Unresolved`。**不改写** | 库求值职责（真缺口），后续通过新函数 `dynamic_ref_view` 暴露映射事实 |
| D2 | overlayable / policy / staged alias chunk | 按大小跳过，不解析 | 格式级信任归属 APK 容器模块；本库仅做结构跳过 |
| D3 | styles chunk | 保留原始字节，不解析 | 语义未确定，保留原值 |
| D4 | namespace 前缀→URI 映射 | chunk 仅校验字符串引用后跳过，**不记录映射** | 解析侧可用，未暴露 |
| D5 | `from_qualifiers` qualifier 子集 | 不支持 `vNN`（SDK）、`long/round/widecg/hdr`、输入设备族、`b+<lang>[+<region>]` BCP47 | 接受新 token 属行为变更，走新函数 `from_qualifiers_ext` 防火墙（W3） |
| D6 | `resolve_id` 引用链深度 | 深度 > 16 输出 `(too deep)`；无 visited 集环检测。**无** `(cycle)` 文本（注释漂移已修） | 环检测仅 bag/attr 链（`flatten_bag`/`eval_theme_attr`），引用链无真环检测 |
| D7 | CLI zipmin | Store/Deflate，**不做 CRC-32 校验**；inflate 上限退化为 1GiB | 保留为 CLI 便利层，文档声明「尽力读取、不提供容器完整性结论」 |
| D8 | sem 视图 label | 仅取 `raw_value` 字面量，即使 `--resolve` 也不解析引用型 label | 现状冻结；变更须另行裁决 |
| D9 | 单表 API 无框架表时 `0x01…` 引用 | 保持原样/Unresolved | 非目标边界；多表联合走 W6 新类型 `ResTableSet` |
| D10 | ResConfig 构造路径区分 | `from_qualifiers` 构造的 config `size=64`、`raw` 为空字节；解析所得 config `raw`=原始字节 | 恒等式断言须按构造路径区分，不得混用 |

## 2. 错误模型实数（冻结，不可新增错误变体）

### AxmlError（8 变体）

| 变体 | 语义 |
|---|---|
| `UnexpectedEof(Int32)` | 输入在声明长度前耗尽（偏移为 EOF 位置） |
| `BadChunkType(Int32, UInt16)` | 外层 chunk type 不在合法范围（偏移+实际类型） |
| `BadHeaderSize(Int32, Int32)` | headerSize 不符合类型声明（偏移+实际值） |
| `BadStringPool(Int32, String)` | 字符串池结构损坏：NUL 缺失、重复池、坏编码等 |
| `InvalidStringIndex(Int32, Int32)` | 字符串引用越界 |
| `InvalidNodeIndex(Int32, Int32)` | 节点引用越界 |
| `UnsupportedEncoding(Int32, UInt32)` | 字符串池标志位不支持 |
| `VendorVariant(Int32, Int32)` | attributeStart/attributeSize 小于 20（厂商变体） |

### ArscError（12 变体）

| 变体 | 语义 |
|---|---|
| `Eof(Int32)` | ARSC 外层 size 超出输入 |
| `BadChunk(Int32, UInt32)` | chunk 类型/结构损坏 |
| `BadHeader(Int32, String)` | chunk 头字段异常 |
| `BadPool(Int32, String)` | 字符串池语义错误 |
| `BadIndex(Int32, Int32)` | 字符串/条目索引越界（ARSC 侧的 InvalidStringIndex 等价） |
| `BadTable(Int32, String)` | 表级结构损坏（继承包、type chunk 边界等） |
| `BadQualifier(String)` | qualifier token 不支持 |
| `BagNotComplex(UInt32)` | 目标条目存在但非 bag（Simple 值）或目标不存在 |
| `BagMissingParent(UInt32)` | bag parent 链中某 parent id 在表中不存在（根 id 为 Complex） |
| `BagCycle(UInt32)` | bag parent 链成环 |
| `AttrMissing(UInt32)` | `?attr` 主题 id 不存在 |
| `AttrCycle(UInt32)` | `?attr` 主题链成环 |

**禁止新增错误变体**：破坏性变更须 ADR + 用户裁决 + CHANGELOG + 主版本四件例外流程。解析失败优先复用既有变体或用值字段表达校验失败。
