# hnlyxiaobing/axml

**Android 二进制 XML（AXML）解析器 —— 把 AXML 字节流解析为文档树，纯 MoonBit 实现。**

> 状态：**Round-1 架构与声明可评审**。已写入数据结构与 `declare` 签名，`moon check` 0 error（5 条预期 `0068` 告警）。**无业务逻辑**。

## 定位与为什么存在

路线图「拼图一」实测 mooncakes.io（2026-11-06 复核）：`axml` / `arsc` / `dalvik` / `smali` 均无可用包，`dex` 唯一命中是生物序列误报。AXML 是 `AndroidManifest.xml` 在 APK 内的二进制形态，缺了它就无法在 MoonBit 侧读取任何 APK 清单。规范来自 AOSP `frameworks/base/include/androidfw/ResourceTypes.h`（Apache-2.0），公开且稳定，因此判定为**纯 MoonBit 自研**（`docs/capability-matrix.md` #02）。

本库是 `apk` 的下游（但**不被引擎 import**）、APK 审计工具与 CI manifest 检查的共用底座。按 ADR-0003，`apk` 只产出 `ManifestRef.raw : Bytes`，由**组合根**调用本库。

## 能力范围 / 非目标

- **做**：`RES_XML_TYPE` chunk 解析；字符串池 UTF-8 / UTF-16 双编码；节点树（namespace / start / end element / cdata）；typed attribute 的 `res0` / `dataType` / `data`；resource map 索引保留。
- **不做**：资源引用语义（`@ref` / `?attr`）、manifest 语义（package/activity/权限的解释属上层）、`resources.arsc`、AXML 回编、XML 序列化、厂商变体的自动修复。
- **上界**：一个库只解析一种格式；**下界**：不抽象跨格式通用接口（架构原则 P1）。

## 公开接口（速览）

`parse(Bytes) -> AxmlDoc raise AxmlError`、`AxmlDoc::{elements, string_at, node_at}`、`XmlNode::attrs`。完整签名与语义见 `API.md`。

## 依赖

- **本轮零依赖**：独立 `moon.mod`，无 `moon.pkg` import，`moon check` 独立通过。
- 后续轮：无第三方依赖计划；`iceBear67/classfile@0.2.0` 仅作**设计参照**（该包 `build_status=legacy`、仍带 `moon.pkg.json`，v0.10.19 下不可直接依赖，见 ADR-0010）。

## 平台与许可风险

- 平台：全后端（`preferred_target = "wasm"`，未改动）；桌面即可测试。
- 许可：本仓库 Apache-2.0；规范来自 AOSP Apache-2.0。无外部二进制、无再分发风险。
- 风险：字符串池 UTF-8/UTF-16 边界、`Res_value` 的 `res0`/`dataType` 语义、厂商魔改 AXML 变体（如 AndResGuard / sparse flags）。策略是**严格校验 + 带偏移报错 + 降级告警**，不 panic（参照 apktool 的 `--keep-broken-res` 思路）。

## 测试与验收

- **测试策略**：真实 APK 的 AXML 黄金样本（UTF-8 / UTF-16 各一）；与 `aapt2 dump xmltree` 逐字段差分；畸形 chunk / 越界索引 / 非法 headerSize 注入测试；`moon test --enable-coverage`。
- **验收标准**（实现轮）：正确读出目标 APK 的 package、activity、权限，与 aapt2 输出逐字段一致；两个真实 APK 的 manifest 解析无崩溃。
- 依赖资产：真实 APK 目前**不在本工作区**（`docs/open-questions.md` Q1）。

## 当前状态 / 本轮产物

| 项 | 状态 |
|---|---|
| `axml.mbt` 数据结构 + `declare` 签名 + 文档注释 | ✅ |
| `pkg.generated.mbti` API 快照 | ✅（由 `moon check` 生成） |
| 解析逻辑 / 黄金测试 / 厂商变体处理 | ❌ 后续轮，代码中以 `TODO(实现轮)` 标注 |
| `moon check` | ✅ 0 error（5 × `0068`，预期） |

## 文档索引

`DESIGN.md`（设计契约）· `API.md`（签名清单）· `../docs/architecture.md` · `../docs/adr/ADR-0001`、`ADR-0002`、`ADR-0003` · `../docs/moon-check-report.md`
