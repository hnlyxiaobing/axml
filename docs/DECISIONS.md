# axml · 设计决策记录（DECISIONS.md）

> 本文件记录影响本仓库结构与 API 形态的设计决策（背景 → 决策 → 理由 → 后果），自足可读。
> 部分决策源自开发期决策记录 ADR-0001 / ADR-0002 / ADR-0003 / ADR-0010（开发期文档，不随本仓库分发）；此处保留结论与理由全文，读者无需访问本仓库之外的任何文件。

## D1 · `resources.arsc` 解析器归属 `axml`（而非 `apk` 容器层）

**背景**：APK 资源表 `resources.arsc` 与二进制 XML（`AndroidManifest.xml`、`res/*.xml`）共享同一套字符串池结构与 `ResChunk` 头结构，两者仅外层 chunk 类型不同（`RES_TABLE_TYPE` 0x0002 / `RES_XML_TYPE` 0x0003）。本库需要提供 `resources.arsc` 解析能力，而归属有三种候选：放进 `apk` 容器库、单开一个新模块、或作为 `axml` 内的加法性新增。

**决策**：`resources.arsc` 解析器作为 **`axml` 单包内的加法性新增**落地（`parse_arsc` 及配套类型与 `axml::parse` 并列的公开 API）——不新建模块、不进 `apk`、不动 `dex`。`apk` 的 `resource_table()` 维持只产出原始字节/索引（`ResourceTableRef`），由组合根把 bytes 交给本库解析，与 `manifest()` → `axml::parse` 的既有分工完全同构。

**理由**：
- `resources.arsc` 与 AXML 共享字符串池、chunk 头、`Res_value` 等结构，放进 `axml` 可直接复用同一套严格解析器与错误模型；单开新模块会与 `axml` 的公共结构大量重复。
- 放进 `apk` 会违反「容器层只产出字节与索引、不编排下游解析」的边界（见 D2）。
- 本库的上界是「一个库只解析一种格式」：AXML 与其同层资源表属于同一格式家族（同一套 ResChunk / 字符串池 / Res_value 结构）。

**后果**：
- `axml` 公开 API 呈**加法性**扩张（`../pkg.generated.mbti` 快照纯新增 +153 行 / -0 行，AXML 侧签名逐字未动）。
- `apk` / `dex` 的公开签名不受影响；`apk` 依旧不返回任何下游类型。
- 降级边界（qualifier 最优匹配、动态引用改写等刻意不做的项）记录于 `API.md` 降级项清单。

## D2 · 零跨模块 import；`apk` 只给出 `ManifestRef.raw : Bytes`，由组合根调用本库

**背景**：本库与 `apk` / `dex` 等是各自独立的 MoonBit 模块（各自 `../moon.mod`），MoonBit 是名义类型系统——两个模块里结构完全相同的 struct 也不是同一类型。若让 `apk` 内部调用 `axml` 并返回 `AxmlDoc`，会把下游格式类型泄漏给容器层使用者、使 `apk` 成为中心节点并产生循环依赖风险，且下游解析库一变 `apk` 的 API 就被迫跟着变。

**决策**：
1. 各模块**零跨模块 import**，`../moon.pkg` 无显式依赖，可独立 `moon check`；本库 `../moon.mod` 独立、零第三方依赖。
2. 跨模块传递只用中性纯值（如 `Bytes`）：`apk::manifest()` 只返回 `ManifestRef { entry_name, raw : Bytes }`，**不返回 `AxmlDoc`**；由**组合根**（使用方工程里的适配代码，不是库）把 `raw` 交给 `axml::parse`，并把错误映射为上层诊断。
3. 错误不跨模块传播：本库统一 `raise AxmlError` / `raise ArscError`，由组合根决定如何上抛或降级。

**理由**：容器读取与格式解析是可独立复用的能力（业界同构：apktool 把资源解码与 DEX 反汇编分开，jadx 用自研 zip reader 独立读取容器）；零 import 让各库可并行演进、独立校验，API 边界被迫写成中性值类型，天然满足「后端可替换、实现细节不泄漏」。

**后果**：调用方需要多写 2–3 行传递代码（组合根），并自己知道 `raw` 是 AXML 格式——这是逆向工具链的合理知识；换来的是 `apk` 的接口稳定性不依赖本库的格式演进，任何使用者可以只依赖其中一库。

## D3 · 具体数据结构用真实类型定义，不用 `declare` 声明 struct

一句话：`declare` 在 moonc 中只支持函数签名与抽象类型，不能声明 struct/enum（`declare cannot be followed by struct/enum/trait/suberror/type alias`），且具体类型只有类型形状、不含业务逻辑，因此本包的具体数据结构（struct / enum / type alias / suberror）一律用**真实类型定义**、函数体全部真实实现（不留 `declare` 存根，源自开发期决策记录 ADR-0001）。

## D4 · `iceBear67/classfile@0.2.0` 只作设计参照，不作依赖

**背景**：需要 Java classfile 二进制布局（结构表 + 边界校验）的写法参照，mooncakes 上存在现成包 `iceBear67/classfile@0.2.0`。

**决策**：该包**只作设计参照**（借鉴其结构组织与校验写法），**不引入为依赖**；本库维持零第三方依赖（`../moon.pkg` 无显式 import）。

**理由**：
- 该包 `build_status = legacy`，仍带 `moon.pkg.json`；现行 moon 工具链不再接受 JSON manifest 的包，直接依赖会失败。
- 引入任何第三方包都会带来网络 / 版本 / 许可耦合，破坏「独立 `moon check`」的性质；本库解析 AXML / resources.arsc 并不需要它。
- 依赖政策（若未来引入）：新增依赖必须同时通过用途、许可、维护、平台、风险五条门槛并留痕（源自开发期决策记录 ADR-0010）。

**后果**：`../moon.mod` 无依赖、`../moon.pkg` 无显式 import；`../pkg.generated.mbti` 中出现的 `moonbitlang/core/debug` 仅来自 `AxmlError` 的 `#derive(Debug)`。
