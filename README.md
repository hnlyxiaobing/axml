# hnlyxiaobing/axml

**Android 二进制 XML（AXML）解析器 —— 把 AXML 字节流解析为文档树，纯 MoonBit 实现。**

> 状态（R2 冻结前整改轮，2026-11-07）：**实现完成并通过全部门禁**。`parse` 与全部访问器均为真实实现（包内无 `declare` 存根、无 `0068` 告警）：`moon check --deny-warn` 0 error / 0 warning，`moon test` 40/40，`moon fmt --check` 通过。R2 P0 整改：删除无实现者的 `DocumentView` trait，并完成 API / 设计 / README 与 `pkg.generated.mbti` 快照的逐项对账。

## 定位与为什么存在

路线图「拼图一」实测 mooncakes.io（2026-11-06 复核）：`axml` / `arsc` / `dalvik` / `smali` 均无可用包，`dex` 唯一命中是生物序列误报。AXML 是 `AndroidManifest.xml` 在 APK 内的二进制形态，缺了它就无法在 MoonBit 侧读取任何 APK 清单。规范来自 AOSP `frameworks/base/include/androidfw/ResourceTypes.h`（Apache-2.0），公开且稳定，因此判定为**纯 MoonBit 自研**（`docs/capability-matrix.md` #02）。

本库是 `apk` 的下游（但**不被引擎 import**）、APK 审计工具与 CI manifest 检查的共用底座。按 ADR-0003，`apk` 只产出 `ManifestRef.raw : Bytes`，由**组合根**调用本库。

## 能力范围 / 非目标

- **做**：`RES_XML_TYPE` chunk 解析；字符串池 UTF-8 / UTF-16 双编码；节点树（namespace / start / end element / cdata）；typed attribute 的 `res0` / `dataType` / `data`；resource map 索引保留。
- **不做**：资源引用语义（`@ref` / `?attr`）、manifest 语义（package/activity/权限的解释属上层）、`resources.arsc`、AXML 回编、XML 序列化、厂商变体的自动修复。
- **上界**：一个库只解析一种格式；**下界**：不抽象跨格式通用接口（架构原则 P1）；不提供 trait 形式的视图/遍历契约（R2 已删除 `DocumentView`）。

## 公开接口（速览）

`parse(Bytes) -> AxmlDoc raise AxmlError`、`AxmlDoc::{elements, string_at, node_at}`、`XmlNode::attrs`——全部为具体方法，本包**不导出任何 trait**。完整签名与语义见 `API.md`。

## 依赖

- **零依赖**：独立 `moon.mod`，`moon.pkg` 无显式 import（零跨模块依赖），`moon check` 独立通过；`pkg.generated.mbti` 中的 `moonbitlang/core/debug` 仅来自 `AxmlError` 的 `#derive(Debug)`。
- 后续轮：无第三方依赖计划；`iceBear67/classfile@0.2.0` 仅作**设计参照**（该包 `build_status=legacy`、仍带 `moon.pkg.json`，v0.10.19 下不可直接依赖，见 ADR-0010）。

## 平台与许可风险

- 平台：全后端（`preferred_target = "wasm"`，未改动）；桌面即可测试。
- 许可：本仓库 Apache-2.0；规范来自 AOSP Apache-2.0。无外部二进制、无再分发风险。
- 风险：字符串池 UTF-8/UTF-16 边界、`Res_value` 的 `res0`/`dataType` 语义、厂商魔改 AXML 变体（如 AndResGuard / sparse flags）。策略是**严格校验 + 带偏移报错 + 降级告警**，不 panic（参照 apktool 的 `--keep-broken-res` 思路）。

## 测试与验收

- **测试策略**：黄金样本（UTF-8 / UTF-16）在测试代码内**程序化构造**并逐字段断言；畸形 chunk / 越界索引 / 非法 headerSize / 厂商变体布局注入测试。工作区没有真实 APK 资产（`docs/open-questions.md` Q1），因此**不以程序化样本冒充真实格式兼容结论**。
- **已实测验收**：`moon test` 40/40（26 黑盒 + 14 白盒）；`moon check --deny-warn`、`moon build`、`moon fmt --check` 全绿。
- **待补做**：与 `aapt2 dump xmltree` 逐字段差分、真实 APK 解析无崩溃（依赖 Q1 资产就绪）。

## 当前状态 / 本轮产物

| 项 | 状态 |
|---|---|
| `axml.mbt` / `decode.mbt` 类型、错误模型与解析实现 | ✅ 真实实现（无 `declare` 存根、无 `0068` 告警） |
| `pkg.generated.mbti` API 快照 | ✅ 现状有效；`moon info` 再生成由主控统一执行（子代理不运行、不改写） |
| `DocumentView` trait | ✅ R2 已删除（`elements` 无 `raise` 与 `AxmlDoc::elements raise AxmlError` 不兼容，且全仓无实现者/消费者） |
| 厂商变体处理 | ✅ `attributeStart`/`attributeSize > 20` 按步长跳过，`< 20` 报 `VendorVariant` |
| `res0` / `data` 语义解释 | ❌ 保留原值，代码内 `TODO` 标注 |
| 门禁 | ✅ `moon check --deny-warn` · `moon build` · `moon test` 40/40 · `moon fmt --check` |

## 文档索引

`DESIGN.md`（设计契约）· `API.md`（签名清单）· `../docs/architecture.md` · `../docs/adr/ADR-0001`、`ADR-0002`、`ADR-0003` · `../docs/moon-check-report.md`
