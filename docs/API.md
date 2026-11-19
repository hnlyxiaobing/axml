# axml API 与降级登记

> 建立：2026-11-19 ｜ 承接原源码注释中 `docs/DESIGN.md` 的降级与边界登记（现全部统一指向本文件；`docs/DESIGN.md` 不存在）

## 1. 降级项（全部为冻结语义，见开发文档边界裁决 §3）

| # | 能力 | 现状语义 | 归属裁决 |
|---|---|---|---|
| D1 | 动态引用（ResDataType 0x07/0x08） | 旧 API `resolve_id` 恒输出 `(dynamic)` 文本；`resolve_attr_value` 恒 `Unresolved`。**不改写** | 库求值职责（真缺口）；已由 W5 `dynamic_ref_view` 暴露映射事实 |
| D2 | overlayable / policy / staged alias chunk | 按大小跳过，不解析 | 格式级信任归属 APK 容器模块；本库仅做结构跳过 |
| D3 | styles chunk | 保留原始字节，不解析 | 语义未确定，保留原值 |
| D4 | namespace 前缀→URI 映射 | chunk 仅校验字符串引用后跳过，**不记录映射** | 解析侧可用，未暴露 |
| D5 | `from_qualifiers` qualifier 子集 | 不支持 `vNN`（SDK）、`long/round/widecg/hdr`、输入设备族、`b+<lang>[+<region>]` BCP47 | 接受新 token 属行为变更，走新函数 `from_qualifiers_ext` 防火墙（W3） |
| D6 | `resolve_id` 引用链深度 | 深度 > 16 输出 `(too deep)`；无 visited 集环检测。**无** `(cycle)` 文本（注释漂移已修） | 环检测仅 bag/attr 链（`flatten_bag`/`eval_theme_attr`），引用链无真环检测 |
| D7 | CLI zipmin | Store/Deflate，**不做 CRC-32 校验**；inflate 上限退化为 1GiB | 保留为 CLI 便利层，文档声明「尽力读取、不提供容器完整性结论」 |
| D8 | sem 视图 label | 仅取 `raw_value` 字面量，即使 `--resolve` 也不解析引用型 label | 现状冻结；变更须另行裁决 |
| D9 | 单表 API 无框架表时 `0x01…` 引用 | 保持原样/Unresolved | 非目标边界；多表联合走 W6 新类型 `ResTableSet` |
| D10 | ResConfig 构造路径区分 | `from_qualifiers` 构造的 config `size=64`、`raw` 为空字节；解析所得 config `raw`=原始字节 | 恒等式断言须按构造路径区分，不得混用 |
| D11 | overlay/idmap 求值 | 不解析 idmap（AXML/ARSC 之外的第三种二进制格式）；overlayable 可由上层用现有 AXML+sem 组合 | M4 复核维持不立项（W7 关闭） |
| D12 | `resources.arsc` 回写 | `encode_arsc(ResTable) -> Bytes raise ArscError` 已交付（W9）；sparse/offset16/compact 显式拒绝（`BadTable`），dense 往返语义等价 | 值级回编职责（与 W8 同类） |
| D13 | XML 文本→AXML 编译 | 不提供；文本构建继续交给 aapt2/上层工具 | 构建期资源编译非本库职责；M4 裁决不立项（W10 关闭） |
| D14 | `encode_arsc` 的 `ResConfig` 回写 | **2026-11-19 修复落地**：`size < 4` → `BadTable`；`raw.length() >= size` → 取前 `size` 字节原样回写（解析产物 raw 长度恒等于 size，与旧口径一致）；空/短 `raw`（`from_qualifiers` 构造型配置）→ 由 `encode_config_bytes` 按已解码 qualifier 字段序列化 `size` 字节镜像：前 4 字节写 `size`（自描述），按 AOSP `ResTable_config` 偏移写入 mcc/mnc/locale（2 位 ASCII 原样/3 位 15 位压缩，与 `unpack_locale` 对应）/…/localeScript/colorMode，其余零填充；config 镜像在 type chunk 内补齐 4 字节对齐（`entriesStart` 对齐要求，`size` 字段保持真实值）。往返后已解码字段逐字段等价（`raw` 为序列化镜像，不参与语义等价） | 值级回编要求 config 自描述；实证 `arsc_encode_test.mbt` W9-5（含 size=4/63/64/65 边界与 `size<4` 拒绝） |
| D15 | CLI `--config` 的设备配置选值 | **2026-11-19 修复落地**：提供 `--config` 时取值主路径走 `resolve_attr_value_with_config`（`lookup_with` qualifier 最优匹配命中优先 → 未命中回退 `lookup` 默认优先 → 再未命中 `Unresolved`）；未提供 `--config` 时继续走旧 `resolve_attr_value`（既有输出逐字节不变）；名字级回退 `resolve_res_ref` 同走 `lookup_with`。库层新公开函数为纯加法（`pkg.generated.mbti` diff 仅 1 行），旧 `resolve_attr_value` 语义冻结 | 实证：库层 `arsc_match_test.mbt` W3 config 2 例 + L4 `cli_e2e_test.mbt` 双配置 4 断言 + `moon run` 端到端（fx-config fixture 对，见 `tests/ASSETS.md` §1；真实 fx-multidex manifest 的 label 为内嵌字面量，非引用，不适用该演示） |

## 2. 错误模型实数（冻结，不可新增错误变体）

### AxmlError（8 变体）

| 变体 | 语义 |
|---|---|
| `UnexpectedEof(Int32)` | 输入在声明长度前耗尽（偏移为被截断项的起始偏移） |
| `BadChunkType(Int32, UInt32)` | chunk 类型非法或位置非法（偏移 + 实际类型） |
| `BadHeaderSize(Int32, Int32)` | headerSize 不符合类型声明（偏移 + 实际值） |
| `BadStringPool(Int32, String)` | 字符串池结构损坏：NUL 缺失、重复池、坏编码等 |
| `InvalidStringIndex(Int32)` | 字符串引用越界 |
| `InvalidNodeIndex(Int32)` | 节点引用越界 |
| `UnsupportedEncoding(String)` | 字符串池标志位不支持（原因详情） |
| `VendorVariant(String)` | 厂商变体布局（原因详情，含偏移与字段值） |

### ArscError（12 变体）

| 变体 | 语义 |
|---|---|
| `Eof(Int32)` | ARSC 外层 size 超出输入 |
| `BadChunk(Int32, UInt32)` | chunk 类型/结构损坏 |
| `BadHeader(Int32, Int32)` | chunk 头字段异常（偏移 + 实际值） |
| `BadPool(Int32, String)` | 字符串池语义错误 |
| `BadIndex(Int32)` | 字符串/条目索引越界（ARSC 侧的 InvalidStringIndex 等价） |
| `BadTable(Int32, String)` | 表级结构损坏（继承包、type chunk 边界等） |
| `BadQualifier(String)` | qualifier token 不支持 |
| `BagNotComplex(UInt32)` | 目标条目存在但非 bag（Simple 值）或目标不存在 |
| `BagMissingParent(UInt32)` | bag parent 链中某 parent id 在表中不存在（根 id 为 Complex） |
| `BagCycle(UInt32)` | bag parent 链成环 |
| `AttrMissing(UInt32)` | `?attr` 主题 id 不存在 |
| `AttrCycle(UInt32)` | `?attr` 主题链成环 |

**禁止新增错误变体**：破坏性变更须 ADR + 用户裁决 + CHANGELOG + 主版本四件例外流程。解析失败优先复用既有变体或用值字段表达校验失败。
