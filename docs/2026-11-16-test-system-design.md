# axml 测试系统设计（第一性原理）

> 建立：2026-11-16 ｜ 状态：设计生效，随开发文档逐包落地；M0–M4 已交付，覆盖 **170/170** 通过 + 3 `#skip`（共 173 声明；2026-11-19 二次实测；对抗性复核发现的 T-W2-3、T-W3-3/T-W3-4 缺口已于同日修复，见 §6.1/§10）｜ 适用仓库：本仓库（独立自包含）
> 配套文档：[2026-11-16-resource-fidelity-dev-plan.md](2026-11-16-resource-fidelity-dev-plan.md)（`T-W*-*` 验收 ID 一一对应；`B#` 现状证据行均出自该文档 §0 基线表，为 2026-11-16 源码实测核对结论）

## 1. 第一性原理：本库的正确性是什么

本库的数学形态：`Bytes → (AxmlDoc | ResTable 纯值结构) | 带字节偏移的 Error`，以及
`(结构, 引用 id [, 表集合, 设备配置, 主题 id]) → (可读值, 解析路径 origin)`。
正确性不可约简为以下断言，每条必须有测试层承载：

| # | 断言 | 含义 | 反例（测试必须抓住） |
|---|---|---|---|
| A1 | 寻址忠实 | chunk 偏移、字符串索引、节点顺序、属性 typed 值、config 字段与 AOSP `ResourceTypes` 语义一致 | 字符串池偏移差一字节读到相邻串；attributeCount 误读吞掉下一 chunk；fraction 误乘 100（B23 注释陷阱） |
| A2 | 完整性 fail-closed | 可校验项不一致必被报告；**未校验 ≠ 通过**。AXML/ARSC 无 checksum 字段，完整性 = 结构校验（size/headerSize/索引/NUL/严格 UTF/尾随垃圾，B1/B2/B19）；CLI zipmin **不做 CRC-32**（B16），只声明「尽力读取」，永不输出容器完整性结论 | 尾随垃圾被静默接受；外层 size 超长不报截断；把「zipmin 读出来了」当成「容器完好」 |
| A3 | 边界纯净 | 只输出声明的纯值类型；不产出容器信任结论、不做 manifest 业务风险判断、动态引用不改写（B9）、无框架表时 `0x01…` 保持原样 | 单表 API 擅自改写动态引用；sem 视图输出「exported 危险」类下游结论 |
| A4 | 输入安全 | 任意畸形输入不 panic/不越界/内存有界（attributeCount 先于读取预检 B1；inflate 上限取中央目录 usize、未知退化为 1GiB B16） | 截断输入 panic；伪造 entryCount 触发无界分配；压缩炸弹解压无上限 |
| A5 | 契约稳定 | mbti 快照只加法；CLI 记录行 `EL\|AT\|SEM\|POOL\|STR\|` 与退出码 0/1/2 冻结（B13）；旧函数语义永不改变（防火墙） | 给既有 pub(all) struct 加字段；`from_qualifiers` 静默接受原被拒的 `v21`；无新选项时 CLI 输出漂移 |
| A6 | 平台等价 | wasm 与 native 同输入同输出（值结构与渲染文本逐字节一致） | 整型溢出/字节序处理在两后端分歧（现状无自动化门禁，B22） |

设计推论：A1/A2 → 性质测试 + 穷举扫描；A2 语义 → 恒等式断言 + 错误簿记；A4 → 截断扫描 + 变异语料 + 边界值；A5/A6 → 门禁与差分；真实符合性 → 外部 oracle 层（许可约束下本地可选）。

## 2. 测试分层

```text
L0 单元与程序化 fixture（每个 pub fn 行为样例）
L1 性质与变异（变形律/截断扫描/位翻转/边界值）
L2 受控黄金差分（入库 fixture + 逐字段黄金记录）
L3 外部 oracle 差分（aapt2，本地可选，SKIPPED 纪律）
L4 CLI 场景 E2E（预期场景 + 安全拒绝语料 + 退出码矩阵）
L5 元契约门禁（快照/错误簿记/双目标等价/变异自检）
R  真实样本本地 runner（仓库外路径 + SHA-256 门禁 + 显式 SKIPPED）
```

断言×层承载表：

| 断言 | 主承载层 | 辅助层 |
|---|---|---|
| A1 寻址忠实 | L0 + L2 | L3（aapt2 差分） |
| A2 fail-closed | L1（截断/位翻转/边界） | L0 畸形样例、L5 错误簿记 |
| A3 边界纯净 | L0（origin/降级断言） | L5 恒等式门禁 |
| A4 输入安全 | L1（截断扫描 + 变异语料） | L4 安全拒绝语料 |
| A5 契约稳定 | L5（快照 + 簿记） | L4（记录行/退出码冻结）、L0 防火墙律 |
| A6 平台等价 | L5（双目标差分） | — |

现状测试基线（2026-11-19 二次实测）：**173 个 `test` 声明 = 170 执行通过 + 3 `#skip`**（`moon test` 报告 "Total tests: 170, passed: 170, failed: 0"，3 `#skip` 不计入该总数）。
分布：`axml_test.mbt` 36、`axml_wbtest.mbt` 14、`arsc_test.mbt` 23、`arsc_wbtest.mbt` 6、`arsc_match_test.mbt` 18、`arsc_encode_test.mbt` 8、`encode_fixtures_test.mbt` 5、`fixtures_test.mbt` 21（含 2 skip）、`fixtures_malformed_test.mbt` 11（含 1 skip）、`fuzz_test.mbt` 4（L1 截断/位翻转/变异）、`property_test.mbt` 4（P3/P4/P6/P10）、`cmd/cli/cli_e2e_test.mbt` 18、`cmd/cli/cli_golden_test.mbt` 1（T-W3-4 字节冻结）、`tools/check_fixtures/check_fixtures_wbtest.mbt` 4（T-W2-3 门禁单测）。`cmd/cli` 的 L4 E2E 已由 `moon test` 原生承载（B22 已闭合；`cmd/main` 仅保留进程入口）。

**`#skip` 显式清单（永不计入通过）**：

| 用例 | 原因 | 归属 |
|---|---|---|
| `axml malformed: checksum 污染 [SKIPPED: AXML 无 checksum 字段]` | 格式无 checksum，N/A（完整性由结构校验承担） | 永久 N/A，保留声明 |
| `golden axml tree framework-res [SKIPPED: tree/pool 黄金过大未登记]` | 规范化黄金体积过大未内嵌；sem 差分已启用 | L2 缺口，黄金登记归 W1 口径 |
| `axml L3 device [SKIPPED: 本轮不执行真机测试]` | 需真机 + adb 样本 | R runner 启用条件 |

## 3. fixture 体系

| 类 | 形态 | 入库 | 许可 | 现状 |
|---|---|---|---|---|
| F-A 程序化构造 | 测试代码字节 builder | 是 | 随仓库 | 已建成：`axml_test.mbt` 36 例、`arsc_test.mbt` 畸形/结构例、`arsc_match_test.mbt` 18 例均程序化构造（B1/B5/B10） |
| F-B 受控文件 fixture | `tests/fixtures/*.bin` 12 个 | 是 | 哈希登记 | **双通道一致律已自动化（T-W2-3，2026-11-19）**：`tools/check_fixtures` 门禁校验 ASSETS §1 SHA-256 + `fixtures_test.mbt` 内嵌块逐字节一致 + 内嵌块反向登记完备（fail-closed，退出码 0/1），CI Gate 3b 执行；12 文件中 9 个有内嵌块逐字节校验、3 个畸形派生物仅哈希校验 |
| F-C 生成器资产 | 确定性构建产出 | 是 | 自产/受控自建 | base/tvshell-debug 受控自建、fx-multidex 官方工具链自产、framework-res AOSP Apache-2.0（W1 已在本仓库重建来源与哈希登记，B17 已闭合）；fx-config 对受控自产（`tools/genconfig` 程序化生成，T-W3-3 端到端实跑承载） |
| F-D 真实第三方样本 | 仓库外本地路径 | **否（红线）** | 许可不明 | R runner 承载；真机用例 `#skip` 保留 |

红线：F-D 永不入库；fixture 哈希变更须同步登记 + 黄金记录（防样本漂移假绿）。
builder 能力清单（现有构造维度，新解析路径必须补齐对应维度）：

- AXML：外层 type/headerSize/size 三元组污染；字符串池（UTF-8/UTF-16、SORTED/UTF8 标志、8/16 位扩展长度、styles 区、缺 NUL、过长编码/代理项/超 U+10FFFF）；resource map；namespace 引用越界；元素 attributeStart/attributeSize 厂商变体；属性 16 种 Res_value 类型与 size≠8；cdata；未闭合/不平衡元素；未知 chunk 追加。
- ARSC：表头/包身份；typeSpec 标志；dense u32 / FLAG_OFFSET16 / FLAG_SPARSE / compact entry；bag（parent 链/环/缺 parent）；library chunk（步长 260）；config 逐字段（含 15 位压缩 locale）；继承包（typeStrings/keyStrings==0）；外层 size 超长/尾随垃圾。
- qualifier：mcc/mnc/语言/地区/rXX/sw·w·hdp/port/land/night/dpi 族 token 与非法 token（B10）。

## 4. L1 性质与变异

**变形律 P#**（✔=已有用例承载，◇=待建）：

| # | 律 | 现状 |
|---|---|---|
| P1 | 未知 chunk 追加不变性：在合法文档尾部前插入未知 chunk，解析结果不变 | ✔ `axml_test.mbt` 未知 chunk 跳过用例（B3） |
| P2 | 尾随垃圾必拒：合法文档 + 任意非零尾随字节 → `BadHeaderSize`/`BadChunk` | ✔ `trailing bytes after the document raise BadHeaderSize`、`arsc malformed: 截断/头部/尾随垃圾` |
| P3 | 解析确定性：同字节两次 parse 结果逐字段相等（纯函数无隐藏状态） | ✔ `property_test.mbt`「P3: 同字节两次 parse/parse_arsc 逐字段相等」（fx-multidex/framework-res 清单 + 双 arsc，2026-11-19） |
| P4 | 配置退化律：`lookup_with(id, 全零 config)` ≡ `lookup(id)`（默认配置存在时） | ✔ `property_test.mbt`「P4: lookup_with 全零 config 退化律」（默认存在两表 ≡；无默认表按文档化分叉断言 None vs chunk-first，2026-11-19） |
| P5 | 空 qualifier 律：`is_default(from_qualifiers(""))` 为 true；`from_qualifiers_ext` 对旧子集 token 与旧函数逐字段一致 | 前半 ✔（B10 用例）；后半 ✔ T-W3-1 已落地（29 组 token 逐字段一致） |
| P6 | 渲染一致律：简单值 id 的 `resolve_id` 文本 ≡ `format_value` 直渲染 | ✔ `property_test.mbt`「P6: resolve_id 文本 ≡ format_value 直渲染」（合成表 + fx-multidex arsc 全条目遍历；引用类值不适用该口径，2026-11-19） |
| P7 | 双通道一致律：`fixtures_test.mbt` 内嵌字节 ≡ `tests/fixtures/*.bin` 文件（逐字节） | ✔ **T-W2-3 已落地（2026-11-19）**：`tools/check_fixtures` 门禁（CI Gate 3b），9/12 文件内嵌逐字节 + 12/12 哈希 + 反向登记完备 |
| P8 | 动态引用冻结律：旧 API 对 0x07/0x08 动态引用恒 `Unresolved`/`(dynamic)`，任何新包合入后不变 | ✔ 现状断言（B9）；W5 合入时复验 T-W5-2 |
| P9 | bag 压平保序律：子条目覆盖父条目、输出顺序稳定 | ✔ `r4 arsc: bag 压平`（B11） |
| P10 | 防火墙律：新函数合入前后，旧函数全部既有用例零改动绿 | ✔ `property_test.mbt`「P10: 新增函数防火墙律」（W3 旧函数 ≡ 新函数+全零设备、W4 非 ?attr 一致、W6 单表集合 ≡ 单表、W9 往返指纹，2026-11-19）；既有 T-W4-3/W6-3 继续承载 |
| P11 | 往返律：`parse(encode(doc))` 与 `doc` 规范化等价 | ✔ **W8 已实现**（T-W8-1/2/3 往返用例），现状已落地 |

**位翻转**：对关键字段（chunk type/headerSize/size、stringCount、attributeCount、entry offset、Res_value.size）做单 bit 翻转。注意：AXML 无 checksum，部分翻转后仍是**合法输入**——断言口径为「要么报声明的错误类型，要么输出与翻转前不同/与重算黄金一致」，**不得断言全部必错**（那是 checksum 格式的口径，误用即假绿）。

**边界值矩阵**：空输入/1 字节；headerSize=0/最小合法值/±1；外层 size 恰好 EOF/EOF±1；stringCount=0；attributeCount=0/0xFFFF（预检先于读取，B1）；字符串索引=0xFFFFFFFF；引用链深度 16/17（`(too deep)` 边界，B8）；inflate 输出恰好上限/上限+1（B16）。

**截断扫描**：✔ 已有 `axml malformed: 任意截断点都报 AxmlError 而非 panic`（真实清单全前缀）与 arsc 截断用例；✔ **2026-11-19 全量落地（`fuzz_test.mbt`）**：全部入库 fixture（edge-* 派生物本身即截断家族由 base 覆盖）+ **W8 `encode` / W9 `encode_arsc` 产物**入扫描集——大样本素数步长抽样（7/13/97）+ chunk 头/池偏移表/entry 偏移表/entriesStart 边界必采 + 尾部 8 字节必采；实测样本量 9188（fixture）+ 343（W8/W9 产物），断言仅声明错误或成功、无 panic。

**变异语料**：✔ **2026-11-19 落地（`fuzz_test.mbt`「L1: 1000 固定种子变异体不 panic」）**：xorshift32 固定种子、替换/插入/删除三态、1050 变异体覆盖 7 个 fixture；断言不 panic 且错误属声明变体集（checked error 静态保证）+ 成功亦允许。**位翻转**：✔ 同文件「L1: 单 bit 翻转关键字段」564 例——chunk type/headerSize/size、stringCount、attributeCount、type entryCount、typeSpec entryCount、entry offset、`Res_value.size`；`Res_value.size=8` 按 AOSP「size≥8 接受、多余忽略」语义仅 bit3（8→0）可观察，bit0-2/4-7 为文档化良性翻转不纳入断言。

## 5. L3 oracle 矩阵 + R runner

| oracle | 差分对象 | 规范化口径 |
|---|---|---|
| `aapt2 dump xmltree` | EL/AT 记录行（元素树、属性 typed 值） | 只比本库声明输出的字段；hex 用 `hex_min` 最小宽度语义、定点 `fixed6` 六位、fraction **不乘 100**（B6/B23，与 aapt2 dump 一致） |
| `aapt2 dump xmlstrings` | POOL/STR 记录行（字符串池计数与内容） | 逐串比对，含 UTF-8/UTF-16 两态 |
| `aapt2 dump badging` | SEM 记录行（manifest 语义字段） | 仅字段级比对；label 只比字面量（引用型 label 不解析是现状契约，B15），不比下游风险结论 |
| `aapt2 dump resources` | ARSC 值渲染 / config 字符串 | 16 类型渲染文本；config 按 AOSP 字段顺序规范化 |

纪律：oracle 缺失 → 显式 SKIPPED + 原因（退出码 78 口径），不得写成通过；oracle 版本随结果登记。现有黄金常量即开发期与工具侧逐字段差分的内嵌结果（B17 所述口径，W1 重建登记后自包含）。
R runner：样本仓库外路径 + 登记哈希 → 哈希不符拒绝执行 → 规范化差分 → 报告「本地已差分 + 哈希 + 日期」；入库 `#skip` 用例保留不删（§2 清单），真实结论永不进入通过计数。framework-res 的 tree/pool 黄金过大未登记项在 R runner 中以「本地差分 + 哈希登记」承接，不内嵌大常量。

## 6. 覆盖矩阵与错误簿记

### 6.1 能力×场景×安全 覆盖矩阵

现状列引开发文档 B# 行；缺口列指 W#（✔=有自动化承载，◐=部分，✘=无，◇=待建）。

| ID | 能力/场景 | L0 | L1 | L2 | L3 | L4 | 现状(P4) | 缺口→W# |
|---|---|---|---|---|---|---|---|---|
| F1 | AXML chunk/节点树解析 | ✔ | ✔截断 | ✔ | ✔xmltree | ✔ | B1/B3 | L4 E2E 已落地（2026-11-19） |
| F2 | UTF-8/16 严格字符串池 | ✔ | ✔畸形 | ✔ | ✔xmlstrings | ✘ | B2 | — |
| F3 | resource map / namespace / styles 降级 | ✔ | ◐ | ✔ | — | ✘ | B4（namespace 映射不暴露、styles 不解析为已声明降级） | 降级已登记（W1，`docs/API.md` D3/D4） |
| F4 | ARSC 全结构（sparse/offset16/compact/bag/library） | ✔ | ✔截断 | ✔ | ✔resources | ✘ | B5 | — |
| F5 | Res_value 16 类型渲染 | ✔ | ✔位翻转（L1 已落地） | ✔ | ✔resources | ✘ | B6/B23 | 注释已修正（W1）；位翻转 2026-11-19 落地（含 Res_value.size 良性位文档化） |
| F6 | 引用解析（resolve_id/resolve_attr_value） | ✔ | ✔ | ✔ | ◐ | ✔ | B7/B8/B9 | 环检测口径已修正（W1）；动态引用视图 W5 已交付；L4 已覆盖 `--resolve` E2E；P6 渲染一致律已落地 |
| F7 | qualifier 匹配（from_qualifiers/lookup_with） | ✔ | ✔ | — | ◐ | ✔ | **W3 全量交付**：`from_qualifiers_ext` 已落地、旧函数冻结；CLI `--config` 已接入取值主路径 `resolve_attr_value_with_config`（最优匹配优先、未命中回退默认） | T-W3-3 已完成（库层 2 例 + L4 双配置 4 断言 + fx-config 实跑）；T-W3-4 已完成（golden 基线） |
| F8 | bag 压平 / ?attr 主题求值 | ✔ | ✔环 | — | — | ✘ | **已实现**（W2 补 BagMissingParent 显式用例；W4 主题求值已交付） | — |
| F9 | 动态引用映射视图 | ◐解析侧 | — | ✔library | — | ✘ | **已实现**（W5 `dynamic_ref_view` 暴露映射事实，不改写） | — |
| F10 | 多表联合解析 | ✘ | ✘ | ◐framework-res 可解析 | — | ✘ | **已实现**（W6 `ResTableSet` + `resolve_attr_value_multi`） | — |
| F11 | overlay/idmap | ✘ | ✘ | ✘ | — | ✘ | **已裁决非目标**（M3/M4 两次排除：idmap 为第三二进制格式，overlayable 分析属上游工具） | 声明降级，不再立项 |
| F12 | AXML 回编 encode | ✔ | ✘ | ✔ | — | ✘ | **W8 已实现**（`encode(AxmlDoc)->Bytes`，T-W8-1/2/3 往返已落地） | — |
| S1 | CLI dump 预期场景（EL/AT/SEM/POOL/STR） | ✘ | — | ✔黄金 | ✔badging | **✔** | B13/B22 | **L4 已落地**；T-W3-4 已自动化（`tests/cli-golden/` 22 基线逐字节冻结，含 help/退出码矩阵） |
| S2 | CLI `--config` 设备配置场景 | ✘ | — | — | ◐ | ✔ | **W3 全量实现**：`--config` 接入取值主路径（最优匹配 → 回退默认） | T-W3-3 已验证（双配置表 zh→`Fx 多维`/无 config→默认/en→默认/空→默认 4 断言 + fx-config `moon run` 实跑） |
| S3 | CLI `--entry` APK 直读场景 | ✘ | — | ◐ | — | ✔ | zipmin 已由 L4 覆盖 | **L4 已落地**（APK 直读 == 裸 dump、`--entry`、条目缺失 → 退出码 1） |
| C1 | 尾随垃圾/截断必拒（fail-closed） | ✔ | ✔ | ✔ | — | ✔ | B1/B19 | L4 已覆盖 CLI 侧（解析失败/截断 ZIP → 退出码 1）；大型变异语料仍归 L1 脚本层 |
| C2 | 任意畸形不 panic/内存有界 | ✔ | ✔AXML+ARSC 全 fixture 截断扫描（L1 已落地） | ✔ | — | ✔（golden 含畸形输入退出码 1） | B1/B16/B19 | 2026-11-19 L1 落地：9188+343 截断样本 + 1050 变异体，无 panic |
| C3 | 容器信任不越界（zipmin 无 CRC 显式声明） | ✘ | — | — | — | ✔ | B16（注释漂移） | 声明已修正（W1）；**L4 已落地**「无容器完整性结论输出」断言（记录行前缀白名单 + APK 输出 == 裸 dump） |
| C4 | 许可红线（F-D 不入库） | — | — | ✔登记 | — | — | **已落地**（W1 重建 ASSETS.md 哈希登记，T-W1-2） | — |
| C5 | 契约冻结（快照/记录行/退出码） | ◐ | — | — | — | ✔ | B13/B21/B22 | 快照门禁已有；**T-W3-4 已落地**：`tests/cli-golden/` 22 基线 + `cli_golden_test.mbt` 逐字节比较（含红→绿实证） |
| C6 | 双目标等价 | — | — | — | — | — | B22（CI 仅 wasm）→ **已落地** | L5：本地 wasm/native 同套用例各 170/170（2026-11-19）；CI 新增 `l5-native` job |

### 6.2 错误变体触发簿记（20/20 强制，现状 20/20）

2026-11-16 建立，2026-11-19 W2–W4 落地后复核为 **20/20**（变体名显式出现在断言中才计入）。`AxmlError` 8 变体 + `ArscError` 12 变体（B12）。

| 变体 | 触发用例（现状，显式断言变体名） | 新增触发（待建） |
|---|---|---|
| AxmlError::UnexpectedEof | `truncated input raises UnexpectedEof at the cut point`；`unclosed elements raise UnexpectedEof…`；`axml malformed: 外层 size 超出输入时报 UnexpectedEof` 等 6 处 | — |
| AxmlError::BadChunkType | `bad outer chunk type raises BadChunkType`；`a second string pool raises BadChunkType` 等 5 处 | — |
| AxmlError::BadHeaderSize | `bad outer headerSize raises BadHeaderSize`；`trailing bytes after the document raise BadHeaderSize`；`Res_value size other than 8 raises BadHeaderSize` 等 6 处 | — |
| AxmlError::BadStringPool | `corrupt string pool raises BadStringPool`；`string entries require NUL terminators`；`decode_utf16 rejects unpaired surrogates` 等 9 处 | — |
| AxmlError::InvalidStringIndex | `invalid string indices raise InvalidStringIndex`；`axml malformed: 首元素 name 索引污染…` 等 3 处 | — |
| AxmlError::InvalidNodeIndex | `node_at raises InvalidNodeIndex for out-of-range indices`；`elements raises InvalidNodeIndex for a corrupt node table` | — |
| AxmlError::UnsupportedEncoding | `unknown string pool flags raise UnsupportedEncoding`；`parse_string_pool rejects unknown encoding flags` | — |
| AxmlError::VendorVariant | `vendor variant attribute layout raises VendorVariant` | — |
| ArscError::Eof | `arsc malformed: 外层 size 超出输入时报 Eof`；`arsc malformed: 截断/头部/尾随垃圾` | — |
| ArscError::BadChunk | `arsc malformed: 截断/头部/尾随垃圾` | — |
| ArscError::BadHeader | `arsc malformed: 截断/头部/尾随垃圾` | — |
| ArscError::BadPool | `arsc malformed: 资源表语义错误` | — |
| ArscError::BadIndex | `arsc wb: axml_err 映射`（白盒映射断言）+ `arsc malformed: 截断/头部/尾随垃圾` 黑盒触发 | — |
| ArscError::BadTable | `arsc malformed: 资源表语义错误`；`arsc malformed: type chunk 边界` | — |
| ArscError::BadQualifier | `r4 arsc: from_qualifiers 解析` + W3 `from_qualifiers_ext` 对未知 token 复用本变体（T-W3-2，L535） | — |
| ArscError::BagNotComplex | `r4 arsc: 压平与求值错误路径` | — |
| ArscError::BagMissingParent | `r4 arsc: 压平 BagMissingParent`（T-W2-1：parent id 不存在且根 id 为 Complex，断言变体名与 id 值） | — |
| ArscError::BagCycle | `r4 arsc: 压平与求值错误路径` | — |
| ArscError::AttrMissing | `r4 arsc: ?attr 主题求值` + W4 联合解析降级 `Unresolved`（T-W4-2） | — |
| ArscError::AttrCycle | `r4 arsc: 压平与求值错误路径` + W4 同上（T-W4-2） | — |

簿记门禁：本表与测试代码**双向核对**（表→代码：每行用例实存且断言变体名；代码→表：新增变体断言必登记），缺一即红（T-W2-2）。禁止新增错误变体（硬约束），本表行数恒 20，除非四件例外流程通过。

### 6.3 恒等式断言（语义契约，全路径成立）

- `resolve_attr_value` 全路径**不抛错**：任何输入下 origin ∈ {FromId, FromName, Literal, Unresolved}（B9）；W4 新函数同契约（T-W4-2）。
- 动态引用恒等式：旧 API 下 0x07/0x08 类型 origin 恒 `Unresolved`（P8）；W5 视图只暴露映射事实，不改写（T-W5-2）。
- 无框架表恒等式：单表 API 对 `0x01…` 引用输出与表内容无关地保持原样/Unresolved；W6 多表通道不改变该式（T-W6-3）。
- 配置构造恒等式：`from_qualifiers` 产物 `size=64`、`raw` 为空；解析所得 config `raw`=原始字节——断言按构造路径区分，不得混用（B24）。
- 防火墙恒等式：任一 W# 合入后，旧函数全部既有用例零改动绿（P10，每包 DoD）。
- zipmin 诚实恒等式：CLI 输出中**不存在**任何「CRC 通过/容器完好」类结论字段（C3；B16 声明口径）。

## 7. L4 CLI 场景 E2E

**现状（2026-11-19 落地）**：B22 已闭合。L4 按 §9「二选一，倾向前者」选择 **`moon test` 原生承载**，落在 `cmd/cli/cli_e2e_test.mbt`（17 执行用例），无脚本层依赖。承载方式：CLI 逻辑收敛到库包 `cmd/cli`（`cmd/main` 仅进程入口），把「选项解析 + 校验 + 解析 + 渲染」收敛为 `cmd_dump_core`（输出经 `Sink`），并以公开入口 `cli_run(args, input : Bytes, arsc : Bytes?) -> CliResult` 接受**内存字节**输入、捕获 stdout/stderr 行与退出码；真实文件入口 `cmd_dump`/`run` 逐字节契约不变。夹具全部程序化构造（合成 `AxmlDoc`/`ResTable` 经 `encode`/`encode_arsc` 往返；手工构造 Store 型 ZIP 覆盖 APK 直读），不依赖外部样本。

| 场景 | 命令序列 | 断言要点（退出码+输出） | 落地用例 |
|---|---|---|---|
| 正常 dump | `main <fixture.axml>` | 退出码 0；记录行仅 `EL\|AT\|SEM\|POOL\|STR\|` 前缀；与黄金逐字节一致 | tree/pool/sem 记录行逐字节冻结（3 例）；`--json` 单行（1 例） |
| 引用解析 | `main <fixture> --resolve --arsc <table>` | 退出码 0；AT 值列为可读文本；无表可解析项保持 `@0x%08x` | `--resolve --arsc` → `MyApp`（1 例） |
| 设备配置（W3 后） | `main <fixture> --resolve --arsc <table> --config zh` | 退出码 0；zh 配置命中值；无匹配回退默认（T-W3-3） | ✔ 已验证（2026-11-19）：`config selects value by device qualifiers` 双配置表 4 断言（zh→`Fx 多维`/无 config→`Fx Multidex`/en→默认/空→默认）+ `config with resolve wired`（1 例）；非法限定符 → 退出码 1（1 例） |
| 无新选项冻结 | 全部既有命令组合 | 输出逐字节与基线一致（T-W3-4，防契约漂移） | ✔ 已自动化（2026-11-19）：`tests/cli-golden/` 22 基线文件 + `cli_golden_test.mbt` 逐字节比较（22 场景：views×6/APK×3/resolve+config×4/errors+help×9；基线缺失落盘判失败，CI 恒 fail-closed；红→绿实证：改帮助文本 1 字符 → 2 基线红） |
| APK 直读 | `main <apk> --entry AndroidManifest.xml` | 退出码 0；与裸 AXML dump 一致；**无容器完整性结论输出**（C3） | APK 直读 == 裸 dump（1 例）；`--entry` 指定（1 例）；条目缺失 → 退出码 1（1 例） |
| 用法错误 | `--arsc` 缺 `--resolve`；`--resolve` 无表；`--entry` 对非 ZIP；`--config` 缺 `--resolve`（W3 后） | 退出码 **2**，逐例断言（B13；T-W3-5） | 用法错误矩阵 9 例 + 无输入字节 2 例 |
| 解析失败 | 畸形/截断 fixture | 退出码 **1**；stderr 含带偏移错误文本；stdout 无部分树输出 | 非法 AXML（1 例）；截断 ZIP（1 例） |
| 安全拒绝语料 | 尾随垃圾/伪造 attributeCount/压缩炸弹样本 | 退出码 1 或 2（按入口），不 panic、不挂起、无落盘 | APK 条目缺失/截断 ZIP（退出码 1）；大型压缩炸弹语料仍归 L1 脚本层 |

记录行契约冻结口径（B13，变更即破坏）：`EL|depth|ns|name`、`AT|depth|elem|ns|name|value`、`SEM|key|value`、`POOL|count`、`STR|i|text`。退出码矩阵 **0/1/2 逐例断言**；README §5 与本表同提交更新（W1 修正 DEX 记录行误植后冻结）。

## 8. L5 元契约门禁

1. **快照门禁**（已有，B21）：`moon info` + `git diff --exit-code -- pkg.generated.mbti cmd/main/pkg.generated.mbti cmd/cli/pkg.generated.mbti tools/check_fixtures/pkg.generated.mbti tools/genconfig/pkg.generated.mbti`；W3–W9 合入时 diff 必须**纯加法**（新 pub fn/struct/enum），零新错误变体。
2. **双目标等价**（✔ 已落地 2026-11-19）：同一套 `moon test` 用例在 wasm 与 native 两目标全绿（本仓库测试无 target 分支逻辑）；本地实测 wasm 170/170 + native 170/170；CI 新增 `l5-native` job（ubuntu-latest，`moon test --target native`）。
3. **错误簿记门禁**（W2 建立）：§6.2 与测试代码双向核对，缺一即红（T-W2-2）。
4. **变异自检**（✔ 已完成 2026-11-19，红→绿实证）：注入 3 类缺陷逐一验证套件变红后还原复绿——
   - 字符串计数校验 off-by-one（`decode.mbt` `>` → `>=`）→ 3+ 用例红（`BadPool`：golden arsc tvshell/base、`arsc real: base.apk 空资源表`）；
   - chunk size 步进错误（`arsc_decode.mbt` `off + chunk_size` → `off + chunk_size - 1`）→ 3 用例红（P3/P6/P10 解析失败 `Eof`）；
   - bag 覆盖顺序反转（`flatten_bag` 压平序父先子后）→ 2 用例红（`r4 arsc: bag 压平`、`r4 arsc: ?attr 主题求值`）。
   任一注入后套件仍绿 = 测试系统失效，先修测试再合入。
5. **计数纪律**：`#skip`/SKIPPED/退出码 78 不计通过（§2 清单单列）；测试过滤串以 `*` 结尾防空转假绿；「通过」须附命令+日期+计数。

## 9. CI 集成与执行入口

五门禁不变（B21 现状 ci.yml，工具链版本钉死断言），2026-11-19 增补两步：Gate 3b `moon run tools/check_fixtures`（T-W2-3 fixture 一致性，five-gates job 内）；新增 `l5-native` job（`moon test --target native`，L5 双目标）。L0/L1/L2/L4 挂 `moon test`；L3/R 仍为可选（SKIPPED 纪律）。

复验命令（本仓库自包含）：

```powershell
moon check --deny-warn
moon build
moon test            # 基线：170/170 执行通过 + 3 #skip（2026-11-19，缺口修复轮落地后）
moon test --target native   # L5 双目标：同套用例 native 全绿（170/170）
moon run tools/check_fixtures   # T-W2-3：registered=12 embedded=9 failures=0，exit 0
moon fmt --check
moon info
git diff --exit-code -- pkg.generated.mbti cmd/main/pkg.generated.mbti cmd/cli/pkg.generated.mbti tools/check_fixtures/pkg.generated.mbti tools/genconfig/pkg.generated.mbti
```

## 10. 维护规则与验收清单

1. 新增 pub API ⇒ 同提交附 L0 样例 + L1 性质 + 矩阵/簿记更新；无测试不合入。
2. 新增解析路径 ⇒ 进截断扫描 fixture 集（W8 encode 产物、W9 encode_arsc 产物强制；W7 idmap 已裁决非目标，不立项）。
3. fixture 哈希变更 ⇒ `tests/ASSETS.md` 登记 + 黄金同提交更新（W1 重建后生效）；双通道一致性脚本红即停（T-W2-3）。
4. 每包合入 ⇒ 开发文档 DoD 勾选 + 本矩阵现状列刷新 + `docs/CHANGELOG.md` 测试增量登记。
5. 「通过」须可复验：命令 + 日期 + 计数；SKIPPED 永远单列。

**落地验收清单（逐层勾选，未裁决包不预写通过）**：

- [x] L0：簿记 20/20（W2，T-W2-1/T-W2-2；2026-11-19 复核）
- [x] L1：全 fixture 截断扫描 + 位翻转 + 变异语料 ≥1000（2026-11-19 落地：`fuzz_test.mbt` 4 例——截断 9188+343、位翻转 564、变异 1050；W8/W9 编码产物入扫描集；`moon test` 原生承载，非脚本层）
- [x] L2：双通道一致性（W2，T-W2-3 2026-11-19 落地：`tools/check_fixtures` 三链校验 + CI Gate 3b；9/12 内嵌逐字节 + 12/12 哈希 + 3 个畸形样本「仅哈希」显式状态；篡改红→还原绿实证）；内嵌字节单通道继续由 `moon test` 回归
- [ ] L3：aapt2 差分本地复核 + 版本登记（可选，SKIPPED 纪律；外部 oracle 依赖，未立项）
- [x] L4：CLI 退出码矩阵 0/1/2 逐例 + 记录行冻结（`cmd/cli/cli_e2e_test.mbt` 18 例 + `cli_golden_test.mbt` 22 场景基线；T-W3-3 已验证、T-W3-4 已自动化）
- [x] L5：快照纯加法（每包已过）；双目标差分（2026-11-19：本地 wasm/native 各 170/170 + CI `l5-native` job）；变异自检 3 缺陷红→绿（2026-11-19 实证，见 §8.4）
- [ ] R：仓库外样本 runner + 哈希门禁（真机 `#skip` 保留）
- [x] W8 对应行（F12、P11）：**已实现**（encode 往返 T-W8-1/2/3 已落地并进入通过计数；encode 产物已入 L1 截断扫描集）。W9 对应行（arsc encode_arsc 值级回编）**已实现**（T-W9-1/2/3/4/5 已落地；encode_arsc 产物已入 L1 截断扫描集）。
- [ ] W7 对应行（F11 overlay/idmap）：**已裁决非目标**（M3/M4 两次排除），声明降级/维持不立项；不得改为通过。