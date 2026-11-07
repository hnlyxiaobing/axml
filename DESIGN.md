# axml · 设计契约（DESIGN.md）

> Round-1 / 2026-11-06 ｜ 状态：架构与声明可评审，无业务逻辑

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
| `StringIndex` / `NodeIndex` | 索引类型别名，防止裸 Int 混用 |
| `DocumentView` trait | 只读视图契约，便于后续替换遍历实现 |

## 4. 错误模型

`AxmlError` 为 `pub suberror`，构造函数全部携带**字节偏移 / 索引 / 上下文**：`UnexpectedEof(Int)`、`BadChunkType(Int, UInt)`、`BadHeaderSize(Int, Int)`、`BadStringPool(Int, String)`、`InvalidStringIndex(Int)`、`InvalidNodeIndex(Int)`、`UnsupportedEncoding(String)`、`VendorVariant(String)`。

规则：全部 `raise AxmlError`；禁止 `panic` / `abort` / 静默默认值；错误**不跨模块传播**，由组合根映射。

## 5. 资源生命周期

全部为纯值（`Bytes` 由 MoonBit 引用计数管理）。**无外部句柄、无释放函数、无 close 语义**。`parse` 不转移输入所有权、不缓存输入引用；返回值为只读、可跨线程共享。

## 6. 线程 / 并发边界

无可变全局状态、无静态缓存；`parse` 是纯函数，可并发调用不同 AXML；返回的 `AxmlDoc` 只读。

## 7. 平台约束与外部依赖

- `preferred_target = "wasm"`（骨架原值，未改动），全后端可用。
- 外部依赖：无。规范依据 AOSP `ResourceTypes.h`（Apache-2.0）。
- 已知格式风险：UTF8_FLAG=0x100；`ResChunk_header{type, headerSize, size}`；`ResXMLTree_attrExt` 中 `attributeSize=20`；未知 chunk 按 `headerSize/size` 跳过。

## 8. 输入输出类型与错误传播（纯 MoonBit 库）

| 输入 | 输出 | 错误传播 |
|---|---|---|
| `data : Bytes`（完整 AXML chunk，调用方持有） | `AxmlDoc` 纯值 | `AxmlError`，带偏移 |
| `AxmlDoc + StringIndex` | `String` / `XmlNode` | `InvalidStringIndex` / `InvalidNodeIndex` |
| `XmlNode` | `Array[XmlAttribute]` | 无（纯读取） |

`declare` 只能声明函数签名与抽象类型；具体数据结构用真实类型定义（ADR-0001）。

## 9. 可替换性与实现细节不泄漏

上层只看到 `AxmlDoc` / `XmlNode` 等中性值类型，看不到 chunk 偏移计算、字符串池解码缓冲、厂商变体探测策略。后续若换成调用外部 AXML 解析器，只需保持这些值类型不变。

## 10. 测试策略

| 层次 | 内容 |
|---|---|
| 黑盒 (`_test.mbt`) | UTF-8 / UTF-16 黄金样本；`elements()` / `string_at()` 逐字段断言；与 `aapt2 dump xmltree` 差分 |
| 白盒 (`_wbtest.mbt`) | 字符串池解码边界、`headerSize` 校验、索引越界 |
| 畸形输入 | 截断 chunk、非法 magic、非法字符串索引、未知 chunk 类型 |
| 门禁 | `moon fmt --check` / `moon check` / `moon test --enable-coverage` / `moon info` |

## 11. 验收标准（实现轮）

1. 读出目标 APK 的 package / activity / 权限，与 `aapt2` 逐字段一致；
2. 两个真实 APK 的 manifest 解析无崩溃、无 panic；
3. 所有畸形样本返回带偏移的 `AxmlError`；
4. `moon check --deny-warn` 在 R4 转绿。

## 12. 未解决问题 / 待验证假设

- 厂商魔改 AXML（AndResGuard / sparse flags）的实际分布未知，需真实 APK 样本（`docs/open-questions.md` Q1）。
- `aapt2` 官方是否有差分/fuzz 套件未证实（Q6）；若无则自建畸形样本生成器。

## 13. 当前状态与 TODO

`axml.mbt` 已写入全部类型与 5 个 `declare` 函数，每条公开 API 有 `///` 文档注释并标注参数所有权、错误、线程、非目标与 `TODO(实现轮)`。**未实现任何解析逻辑**。

## References

`../docs/research-and-verification.md` §2.1 · `../docs/adr/ADR-0001`、`ADR-0002`、`ADR-0003` · AOSP `ResourceTypes.h` · `https://apktool.org/`
