# axml · 设计契约（DESIGN.md）

> R2 冻结前整改轮 / 2026-11-07 ｜ 状态：实现完成并通过门禁，API 冻结前 P0 整改中（R1「有条件接受」的整改项）

## 1. 分层位置与职责

L1 逆向输入层，纯 MoonBit 叶子库。唯一职责：**AXML 字节流 → 文档树**。输入不含 ZIP 封装，输出不含 manifest 语义。

## 2. 模块边界 / 依赖方向 / 数据流

```
组合根 ──(ManifestRef.raw : Bytes)──► axml::parse ──► AxmlDoc ──► 组合根读取元素/属性
```

- 零跨模块 import（ADR-0002）。`apk` 不调用本库，`dex` 与本库互不知晓。
- 数据流是单向纯值：`Bytes` → `AxmlDoc`（无句柄、无 I/O、无缓存）。

## 3. 核心数据结构

| 类型 | 作用 |
|---|---|
| `AxmlDoc { pool, nodes, roots, resource_map }` | 解析结果；`nodes` 为线性节点表，`children`/`parent` 用索引，避免递归所有权歧义 |
| `StringPool { encoding, strings, styles }` | 字符串池视图；下标与 chunk 内 string index 一一对应 |
| `XmlNode { line, ns, name, attributes, children, parent, chunk }` | 元素节点 |
| `XmlAttribute { ns, name, raw_value, value_type, res0, raw_data, line }` | typed attribute；`raw_data` 保留 32 位原值 |
| `ChunkType` / `StringEncoding` / `ValueType` | AOSP `RES_*` 常量与 `Res_value.dataType` 的枚举化 |
| `StringIndex` / `NodeIndex` | 索引类型别名（`pub type ... = Int32`），防止裸 `Int32` 混用 |

> R2：原 `DocumentView` trait 已删除——`elements` 无 `raise` 与 `AxmlDoc::elements raise AxmlError` 不兼容，且全仓无实现者/消费者。本包不导出任何 trait，`AxmlDoc::elements` / `AxmlDoc::string_at` 为具体方法。

## 4. 错误模型

`AxmlError` 为 `pub suberror`（可见性维持现状，本轮不放宽），并 `#derive(Debug)` 导出 `AxmlError::to_repr(Self) -> @debug.Repr`。构造函数全部携带**字节偏移 / 索引 / 上下文**，类型以 `pkg.generated.mbti` 为准：`UnexpectedEof(Int32)`、`BadChunkType(Int32, UInt32)`、`BadHeaderSize(Int32, Int32)`、`BadStringPool(Int32, String)`、`InvalidStringIndex(Int32)`、`InvalidNodeIndex(Int32)`、`UnsupportedEncoding(String)`、`VendorVariant(String)`，共 8 个变体。

规则：全部 `raise AxmlError`；禁止 `panic` / `abort` / 静默默认值；错误**不跨模块传播**，由组合根映射。

## 5. 资源生命周期

全部为纯值（`Bytes` 由 MoonBit 引用计数管理）。**无外部句柄、无释放函数、无 close 语义**。`parse` 不转移输入所有权、不缓存输入引用；返回值为只读、可跨线程共享。

## 6. 线程 / 并发边界

无可变全局状态、无静态缓存；`parse` 是纯函数，可并发调用不同 AXML；返回的 `AxmlDoc` 只读。

## 7. 平台约束与外部依赖

- `preferred_target = "wasm"`（骨架原值，未改动），全后端可用。
- 外部依赖：无。规范依据 AOSP `ResourceTypes.h`（Apache-2.0）。
- 已知格式风险：UTF8_FLAG=0x100；`ResChunk_header{type, headerSize, size}`；`ResXMLTree_attrExt` 中 `attributeSize=20`；未知 chunk 按 `headerSize/size` 跳过；厂商变体（`attributeStart`/`attributeSize < 20`）报 `VendorVariant`；未知字符串池标志位报 `UnsupportedEncoding`。

## 8. 输入输出类型与错误传播（纯 MoonBit 库）

| 输入 | 输出 | 错误传播 |
|---|---|---|
| `data : Bytes`（完整 AXML chunk，调用方持有） | `AxmlDoc` 纯值 | `AxmlError`，带偏移 |
| `AxmlDoc + StringIndex` / `AxmlDoc + NodeIndex` | `String` / `XmlNode` | `InvalidStringIndex` / `InvalidNodeIndex` |
| `XmlNode` | `Array[XmlAttribute]` | 无（纯读取） |

本包不使用 `declare`：全部 5 个导出函数均为真实实现（ADR-0001 的底线仍适用——具体数据结构与函数体都要可校验，不得停留在签名声明）。

## 9. 可替换性与实现细节不泄漏

上层只看到 `AxmlDoc` / `XmlNode` 等中性值类型，看不到 chunk 偏移计算、字符串池解码缓冲、厂商变体探测策略。后续若换成调用外部 AXML 解析器，只需保持这些值类型不变。

## 10. 测试策略

| 层次 | 内容 |
|---|---|
| 黑盒 (`_test.mbt`) | UTF-8 / UTF-16 黄金样本（在测试代码内程序化构造，不依赖工作区外资产）；`elements()` / `string_at()` 逐字段断言；与 `aapt2 dump xmltree` 的差分待真实 APK 资产就绪（Q1）后补做 |
| 白盒 (`_wbtest.mbt`) | Little-endian 读取器截断偏移、UTF-8/UTF-16 解码边界、字符串池 `headerSize`/`stringsStart`/`stylesStart` 校验、`value_type_of` 映射 |
| 畸形输入 | 截断 chunk、非法 magic、非法字符串索引、未知 chunk 类型 |
| 门禁 | `moon fmt --check` / `moon check --deny-warn` / `moon build` / `moon test`（`moon info` 快照再生成由主控统一执行） |

## 11. 验收标准（R2 冻结前实测状态）

1. 程序化构造的 UTF-8 / UTF-16 黄金样本解析结果逐字段断言通过（当前 26 个黑盒用例）；
2. 所有畸形样本（截断、非法 magic、非法字符串索引、厂商变体布局）返回带偏移的 `AxmlError`，无 panic、无静默默认值（当前 14 个白盒用例）；
3. 门禁全绿：`moon check --deny-warn`、`moon build`、`moon test`、`moon fmt --check`（合计 40 个用例）；
4. 原「与 `aapt2` 逐字段一致 / 两个真实 APK 无崩溃」两条依赖 `docs/open-questions.md` Q1 的真实 APK 资产，工作区就绪后补做差分验收。

## 12. 未解决问题 / 待验证假设

- 厂商魔改 AXML（AndResGuard / sparse flags）的实际分布未知，需真实 APK 样本（`docs/open-questions.md` Q1）。
- `aapt2` 官方是否有差分/fuzz 套件未证实（Q6）；若无则自建畸形样本生成器。

## 13. 当前状态与 TODO

`axml.mbt` / `decode.mbt` 含全部公开类型与 5 个导出函数的**真实实现**，每条公开 API 有 `///` 文档注释并标注参数所有权、错误、线程与非目标。R1 之后的实现轮已完成：40 个用例（26 黑盒 + 14 白盒）全过，`moon check --deny-warn` 0 error / 0 warning。

- **R2 冻结前 P0 整改**：删除 `DocumentView` trait（`elements` 无 `raise` 与 `AxmlDoc::elements raise AxmlError` 不兼容，且全仓无实现者/消费者）；`API.md` / `DESIGN.md` / `README*` 与 `pkg.generated.mbti` 快照逐项对账修正。
- **剩余 TODO**：`res0` / `data` 的语义解释（代码内 `TODO` 标注，当前按 API.md 保留原值）；真实 APK 与 `aapt2` 差分验收（依赖 Q1 资产）。

## References

`../docs/research-and-verification.md` §2.1 · `../docs/adr/ADR-0001`、`ADR-0002`、`ADR-0003` · AOSP `ResourceTypes.h` · `https://apktool.org/`
