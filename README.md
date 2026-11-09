# hnlyxiaobing/axml

**Android 二进制 XML（AXML）解析器 —— 把 AXML 字节流解析为文档树，纯 MoonBit 实现。**

> 状态（2026-11-09，R4）：**实现完成并通过全部门禁**。全部导出函数为真实实现（包内无 `declare` 存根）：`moon clean` / `moon check --deny-warn`（0 error / 0 warning）/ `moon build` / `moon test` **97/97** / `moon fmt --check` 全 exit 0。**R4 新增（加法性）**：aapt2 式 qualifier 最优匹配、bag 压平、`?attr` 主题求值（`arsc_match.mbt`，快照 +17 行 / -0 行）。API / 设计 / README 与 `pkg.generated.mbti` 快照已逐项对账；`DocumentView` trait 因无实现者/消费者且 `elements` 签名不兼容而删除。

## 定位与为什么存在

选型实测（2026-11-06 复查 mooncakes.io）：`axml` / `arsc` / `dalvik` / `smali` 均无可用包，`dex` 唯一命中是生物序列误报。AXML 是 `AndroidManifest.xml` 在 APK 内的二进制形态，缺了它就无法在 MoonBit 侧读取任何 APK 清单。规范来自 AOSP `frameworks/base/include/androidfw/ResourceTypes.h`（Apache-2.0），公开且稳定，因此判定为**纯 MoonBit 自研**。

本库是 `apk` 的下游（但**不被引擎 import**）、APK 审计工具与 CI manifest 检查的共用底座。按 `docs/DECISIONS.md` 的模块边界决策（D2），`apk` 只产出 `ManifestRef.raw : Bytes`，由**组合根**调用本库。

## 能力范围 / 非目标

- **做**：`RES_XML_TYPE` chunk 解析；字符串池 UTF-8 / UTF-16 双编码；节点树（namespace / start / end element / cdata）；typed attribute 的 `res0` / `dataType` / `data`；resource map 索引保留。**（加法性新增）** `resources.arsc` 解析：表头 / 全局池 / `ResTable_package` / typeSpec / type（dense·OFFSET16·sparse 三种 entry offsets）/ entry（simple·bag·compact）/ `Res_value` 全类型；id → (包,类型,名,最优值) 查询（默认配置优先 + **R4 `lookup_with` 按设备配置最优匹配**）；AXML 属性引用 → 人类可读值（`resolve_attr_value`）；**R4**：`ResConfig::from_qualifiers`（限定符文本）、`ResConfig::{matches, is_better_than}`、`ResTable::flatten_bag`（parent 链压平）、`ResTable::eval_theme_attr`（`?attr` 多级求值）。
- **不做**：动态引用改写、overlay/idmap 语义、继承包、manifest 语义（package/activity/权限的解释属上层）；AXML 回编、XML 序列化、厂商变体的自动修复。**R4 已把 qualifier 最优匹配 / bag 压平 / `?attr` 主题求值从降级项转为已实现**（覆盖范围与边界见下）。
- **上界**：一个库只解析一种格式（AXML + 其同层资源表）；**下界**：不抽象跨格式通用接口；不提供 trait 形式的视图/遍历契约（曾有 `DocumentView` trait，已删除）。

## 公开接口（速览）

AXML 侧：`parse(Bytes) -> AxmlDoc raise AxmlError`、`AxmlDoc::{elements, string_at, node_at}`、`XmlNode::attrs`。resources.arsc 侧（加法性新增）：`parse_arsc(Bytes) -> ResTable raise ArscError`、`ResTable::{lookup, lookup_all, find_id, package_by_id, format_value, resolve_id}`、`ResConfig::is_default`、`resolve_attr_value(AxmlDoc, ResTable, XmlAttribute) -> ResolvedAttr`。全部为具体方法，本包**不导出任何 trait**。完整签名与语义见 `docs/API.md`。

## 依赖

- **零依赖**：独立 `moon.mod`，`moon.pkg` 无显式 import（零跨模块依赖），`moon check` 独立通过；`pkg.generated.mbti` 中的 `moonbitlang/core/debug` 仅来自 `AxmlError` 的 `#derive(Debug)`。
- 无第三方依赖计划；`iceBear67/classfile@0.2.0` 仅作**设计参照**（该包 `build_status=legacy`、仍带 `moon.pkg.json`，现行工具链不接受 JSON manifest、不可直接依赖；决策见 `docs/DECISIONS.md` D4）。

## 平台与许可风险

- 平台：全后端（`preferred_target = "wasm"`，未改动）；桌面即可测试。
- 许可：本仓库 Apache-2.0；规范来自 AOSP Apache-2.0。无外部二进制、无再分发风险。
- 风险：字符串池 UTF-8/UTF-16 边界、`Res_value` 的 `res0`/`dataType` 语义、厂商魔改 AXML 变体（如 AndResGuard / sparse flags）。策略是**严格校验 + 带偏移报错 + 降级告警**，不 panic（参照 apktool 的 `--keep-broken-res` 思路）。

## 测试与验收

- **测试策略**：黄金样本在测试代码内**程序化构造**并逐字段断言（AXML + arsc 均是）；畸形 chunk / 越界索引 / 非法 headerSize / 厂商变体布局注入测试；**真实样本佐证**（不以程序化样本冒充真实格式兼容）：base.apk / tvshell-debug.apk 的空 `resources.arsc`（40 字节内嵌 + SHA-256）、受控构建 fx-multidex 的非平凡 `resources.arsc`（1052 字节，aapt2 黄金逐条交叉核对）、framework-res（1.76MB，Apache-2.0）临时整表解析 + aapt2 关键条目交叉核对后删除（类型池真实字节 488B 永久内嵌白盒）。样本登记（来源 / 提取方式 / 哈希 / 黄金口径）见 `tests/ASSETS.md`。
- **已实测验收**：`moon test` **97/97**（AXML 黑盒 26 + AXML 白盒 14 + resources.arsc 黑盒 17 + 白盒 6 + 真实样本黄金/畸形系列 27 + **R4 合成表 7**；另有 3 个 `#skip` 用例显式跳过、不计入通过数）；`moon clean` / `moon check --deny-warn` / `moon build` / `moon fmt --check` 全 exit 0。
- **R4 覆盖边界**：qualifier 匹配覆盖 mcc/mnc/locale/screenLayout/sw/w/h(dp)/orientation/uiMode/colorMode/density/touchscreen/keyboard/navigation/inputFlags/screen(px)/sdkVersion 子集，未覆盖维度按「资源未指定 = 任意」降级；`?attr` 求值只沿 `Attribute`/`DynamicAttribute`，普通 `@ref` 视为终点。
- **待补做**：更多真实 APK 样本（含厂商魔改变体与第三方样本，取得许可后）的差分复核；动态引用改写。

## 当前状态 / 产物清单

| 项 | 状态 |
|---|---|
| `axml.mbt` / `decode.mbt` 类型、错误模型与解析实现 | ✅ 真实实现（无 `declare` 存根、无 `0068` 告警） |
| `arsc.mbt` / `arsc_decode.mbt` / `arsc_match.mbt`（resources.arsc 解析链 + R4 匹配/压平/求值） | ✅ 真实实现（chunk 全形态 + 查询 + 属性引用解析 + qualifier 最优匹配 + bag 压平 + `?attr` 求值） |
| `pkg.generated.mbti` API 快照 | ✅ `moon info` 已再生成（纯加法性 +153 行 / -0 行） |
| `DocumentView` trait | ✅ 已删除（`elements` 无 `raise` 与 `AxmlDoc::elements raise AxmlError` 不兼容，且全仓无实现者/消费者） |
| 厂商变体处理 | ✅ `attributeStart`/`attributeSize > 20` 按步长跳过，`< 20` 报 `VendorVariant` |
| `res0` / `data` 语义解释（AXML 侧） | ❌ 保留原值，代码内 `TODO` 标注 |
| 门禁 | ✅ `moon clean` · `moon check --deny-warn` · `moon build` · `moon test` 97/97 · `moon fmt --check` 全 exit 0 |

## 文档索引

`docs/DESIGN.md`（设计契约）· `docs/API.md`（签名清单）· `docs/DECISIONS.md`（设计决策记录）· `tests/ASSETS.md`（测试样本登记与黄金口径）
