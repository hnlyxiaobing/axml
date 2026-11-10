# axml · 设计契约（DESIGN.md）

> 2026-11-07 ｜ 状态：实现完成并通过全部门禁

## 1. 分层位置与职责

L1 逆向输入层，纯 MoonBit 叶子库。职责：**AXML 字节流 → 文档树** 与
**resources.arsc 字节流 → 资源表**（加法性新增，见 §14）。输入不含 ZIP
封装，输出不含 manifest 语义。

## 2. 模块边界 / 依赖方向 / 数据流

```
组合根 ──(ManifestRef.raw : Bytes)──► axml::parse ──► AxmlDoc ──► 组合根读取元素/属性
```

- 零跨模块 import（见 `DECISIONS.md` D2）。`apk` 不调用本库，`dex` 与本库互不知晓。
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

> 注：早期草案中的 `DocumentView` trait 已删除——`elements` 无 `raise` 与 `AxmlDoc::elements raise AxmlError` 不兼容，且全仓无实现者/消费者。本包不导出任何 trait，`AxmlDoc::elements` / `AxmlDoc::string_at` 为具体方法。

## 4. 错误模型

`AxmlError` 为 `pub suberror`（可见性维持现状，不放宽），并 `#derive(Debug)` 导出 `AxmlError::to_repr(Self) -> @debug.Repr`。构造函数全部携带**字节偏移 / 索引 / 上下文**，类型以 `../pkg.generated.mbti` 为准：`UnexpectedEof(Int32)`、`BadChunkType(Int32, UInt32)`、`BadHeaderSize(Int32, Int32)`、`BadStringPool(Int32, String)`、`InvalidStringIndex(Int32)`、`InvalidNodeIndex(Int32)`、`UnsupportedEncoding(String)`、`VendorVariant(String)`，共 8 个变体。

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

本包不使用 `declare`：全部 5 个导出函数均为真实实现（具体数据结构用真实类型定义、不靠 `declare` 声明 struct——见 `DECISIONS.md` D3；具体数据结构与函数体都要可校验，不得停留在签名声明）。

## 9. 可替换性与实现细节不泄漏

上层只看到 `AxmlDoc` / `XmlNode` 等中性值类型，看不到 chunk 偏移计算、字符串池解码缓冲、厂商变体探测策略。后续若换成调用外部 AXML 解析器，只需保持这些值类型不变。

## 10. 测试策略

| 层次 | 内容 |
|---|---|
| 黑盒 (`_test.mbt`) | UTF-8 / UTF-16 黄金样本（在测试代码内程序化构造）；`elements()` / `string_at()` 逐字段断言；真实样本黄金差分（`../tests/fixtures/` 来源样本，黄金常量内嵌 `../fixtures_test.mbt`，方法与结论见 `../tests/ASSETS.md` §5） |
| 白盒 (`_wbtest.mbt`) | Little-endian 读取器截断偏移、UTF-8/UTF-16 解码边界、字符串池 `headerSize`/`stringsStart`/`stylesStart` 校验、`value_type_of` 映射 |
| 畸形输入 | 截断 chunk、非法 magic、非法字符串索引、未知 chunk 类型 |
| 门禁 | `moon fmt --check` / `moon check --deny-warn` / `moon build` / `moon test` / `moon clean`（全部实测 exit 0） |

## 11. 验收标准（实测状态）

1. 程序化构造的 UTF-8 / UTF-16 黄金样本解析结果逐字段断言通过（当前 26 个黑盒用例）；
2. 所有畸形样本（截断、非法 magic、非法字符串索引、厂商变体布局）返回带偏移的 `AxmlError`，无 panic、无静默默认值（当前 14 个白盒用例）；
3. 门禁全绿：`moon check --deny-warn`、`moon build`、`moon test`（101/101）、`moon fmt --check`；
4. 与 `aapt2 dump` 的逐字段差分已对入库真实样本完成（tvshell-debug / base / fx-multidex 的清单与资源表、framework-res 的清单 sem；方法与结论见 `../tests/ASSETS.md` §5，黄金值已内嵌于测试代码）；更大第三方样本许可不明、未入库。

## 12. 未解决问题 / 待验证假设

- 厂商魔改 AXML（AndResGuard / sparse flags）的实际分布未知，需更多真实 APK 样本（当前样本集见 `../tests/ASSETS.md`）。
- 未发现 `aapt2` 官方差分 / fuzz 测试套件的一手证据；本仓库以程序化派生畸形样本自建边角用例（`../tests/ASSETS.md` §8）。

## 13. 当前状态与 TODO

`../axml.mbt` / `../decode.mbt` 含全部公开类型与 5 个导出函数的**真实实现**；加法性新增
`../arsc.mbt` / `../arsc_decode.mbt`（resources.arsc 解析链，10 个导出函数 + 16 个类型，
见 §14 与 API.md）。每条公开 API 有 `///` 文档注释。当前 `moon test` 101/101
（AXML 黑盒 26 + AXML 白盒 14 + arsc 黑盒 17 + arsc 白盒 6 + 真实样本黄金/畸形系列 27），
`moon check --deny-warn` 0 error / 0 warning。

- **已完成**：删除 `DocumentView` trait（无实现者/消费者且签名不兼容）；API/设计/README 与 `../pkg.generated.mbti` 快照对账。
- **剩余 TODO**：`res0` / `data` 的语义解释（AXML 侧代码内 `TODO` 标注，按 API.md 保留原值）；`?attr` 主题求值与 qualifier 最优匹配（降级项，见 §14）。

## 14. resources.arsc 解析链（加法性新增）

### 14.1 格式覆盖（AOSP ResourceTypes.h / LoadedArsc.cpp 逐项复刻）

| 结构 | 处理 |
|---|---|
| `ResTable_header`（RES_TABLE_TYPE 0x0002） | headerSize==12 校验；`size` 短于输入报尾随垃圾、长于输入报截断 |
| 全局字符串池 | 复用 AXML 侧严格解析器（UTF-8/UTF-16 双编码）；缺失报 `BadPool` |
| `ResTable_package` | headerSize 284（旧）/288（新，含 typeIdOffset）；包名 UTF-16Z；typeStrings/keyStrings 偏移定位类型池/键名池 |
| `ResTable_typeSpec` | id/entryCount/逐条目 config 掩码（SPEC_PUBLIC）；同 id 重复取首个（AOSP 同） |
| `ResTable_type` | entryCount/entriesStart/`ResTable_config`（28~64 字节版本，常用 qualifier 逐字段解码）；dense u32 / FLAG_OFFSET16(u16, 值×4, 0xFFFF=NO_ENTRY) / FLAG_SPARSE(ResTable_sparseTypeEntry{idx,offset/4}，按 AOSP GetEntryOffset 语义) 三种 offsets 全支持 |
| `ResTable_entry` | 简单（+Res_value）、复杂 bag（parent + count 个 ResTable_map）、compact（FLAG_COMPACT：key u16 + flags 高字节 dataType + data 内联，按 AOSP `ResTable_entry::value()`）|
| `Res_value` | `TYPE_*` 全集 16 变体解码 + `Unknown` 保留；dimension/fraction complex 解码（mantissa/radix/unit） |
| `RES_TABLE_LIBRARY_TYPE` | 解析为 `ResLibrary` 供展示；**不做动态引用改写** |
| overlayable/policy/staged alias/未知 chunk | 按 headerSize/size 跳过（降级） |

边界校验对齐 `LoadedArsc.cpp::VerifyResTableType/VerifyResTableEntry`：offsets 与
entry data 不重叠、entriesStart 4 字节对齐、entry/value/map 边界逐项检查，违反即
`BadTable/BadHeader/Eof` 带偏移报错，无 panic、无静默默认值。

### 14.2 查询选择策略（文档化）

`ResTable::lookup(id)`：**默认配置优先**——多配置命中时选 qualifier 全零
（`ResConfig::is_default`）的配置；无默认配置时取 chunk 顺序首个命中。
`lookup_all` 暴露全部配置命中供上层自行选择。**不做** aapt2 式
locale/density/SDK 最优匹配（降级项，见 API.md 降级项 1）。

### 14.3 属性引用解析（resolve_attr_value）

输入 = 已解析 `AxmlDoc` + `ResTable` + `XmlAttribute`；输出 `ResolvedAttr{text, id, origin}`，
`text` 即解析后的人类可读值（如 `@string/app_name` → `MyApp`）。解析顺序：
typed Reference/Attribute 的 `raw_data` id（FromId）→ `raw_value` 文本形式
`@type/name`/`@pkg:type/name`/`@0x…`（FromName/FromId）→ String 池字面量与
typed 字面量（Literal）。全部缺口降级为 `Unresolved(原因)`，不抛错。

### 14.4 真实样本佐证（SHA-256 见 ../arsc_test.mbt 文件头）

| 样本 | 处理 | 交叉核对 |
| --- | --- | --- |
| base.apk / tvshell-debug.apk → resources.arsc（各 40 字节，空表） | 字节内嵌 ../arsc_test.mbt（FIXTURE 注释溯源） | `aapt2 dump resources` 仅 "Binary APK" 无 package ↔ 解析 package_count=0、全局池为空 |
| fx-multidex-v2v3.apk → resources.arsc（1052 字节，受控构建） | fixture 内嵌 `../fixtures_test.mbt`，本包测试解析 | aapt2 黄金（golden_fx_multidex_arsc）逐条：bool=true、color=#ff2255aa、string 默认/zh 双配置、名字反查 |
| framework-res.apk → resources.arsc（1759752 字节，Apache-2.0） | **临时整表解析测试后删除**（体积口径）；类型池 488 字节 chunk 永久内嵌 ../arsc_wbtest.mbt | aapt2 dump resources 关键条目逐条一致（string/cancel zh 双配置、color、dimen 三配置、bool、integer、fraction、style bag parent+12 maps）；base.apk `theme=@0x0103012a` 端到端 → `@style/Theme.DeviceDefault.NoActionBar.Fullscreen` |

### 14.5 测试（23 个 arsc 用例）

- 黑盒 `../arsc_test.mbt`（17）：程序化表覆盖 header/双编码池/typeSpec/type/entry
  全形态（dense/offset16/sparse/compact/bag）/Res_value 全类型、id 查询、
  find_id、resolve_id、resolve_attr_value 三形式与降级、畸形输入（截断/头部/
  尾随垃圾/缺池/超额包/继承包/无前置 spec/entriesStart 未对齐/entry 越界）；
  真实样本 4 项（两空表 + fx-multidex 交叉核对 + framework-res 清单衔接）。
- 白盒 `../arsc_wbtest.mbt`（6）：framework-res 类型池真实字节、AxmlError→ArscError
  映射、locale 解包（ASCII/压缩 UN M.49）、ResTable_config 28/64 字节两版本、
  `TYPE_*` 全映射、fixed6 渲染。

## References

- 设计决策（resources.arsc 归属、模块边界与组合根、类型声明策略、依赖政策）见 `DECISIONS.md`；测试样本来源/哈希/黄金口径见 `../tests/ASSETS.md`。
- AOSP `frameworks/base/include/androidfw/ResourceTypes.h` 与 `LoadedArsc.cpp`（Apache-2.0）：resources.arsc 语义基准（sparse/OFFSET16/compact/entry 边界校验）。
- 业界职责划分与容错启示：apktool 把「资源解码」与「DEX 反汇编」分开，并提供 `--keep-broken-res` 降级；jadx 用自研 zip reader 独立读取容器——容器读取与格式解析是可独立复用的能力。对本库的直接结论：**严格校验 + 带偏移报错 + 降级跳过**——按 `headerSize/size` 跳过未知 chunk，对厂商变体与畸形输入返回带偏移的显式错误而非 panic。`https://apktool.org/`
