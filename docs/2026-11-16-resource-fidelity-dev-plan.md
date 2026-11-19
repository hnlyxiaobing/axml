# axml 资源层解析忠实性与解析纵深开发文档

> 建立：2026-11-16 ｜ 状态：M0–M2 已交付（W1–W6，2026-11-19；W3–W5 验收测试已补齐）；M3 裁决：W8 立项并交付（M8-1/M8-2/M8-3，129/129）、W7 不立项（维持降级）、`sem --resolve-label` 不改（文档化限制） ｜ 适用仓库：本仓库（独立自包含）
> 配套文档：[2026-11-16-test-system-design.md](2026-11-16-test-system-design.md)（验收测试 ID `T-W*-*` 出自该文档）
> 本文所有「现状」结论均为 2026-11-16 对本仓库源码的实测核对（五门禁本机实跑全绿），非转述历史文档。

## 0. 现状基线（实测核对，开发前必读）

| # | 事实 | 证据位置 |
|---|---|---|
| B1 | AXML 全 chunk 解析已实现：外层 type/headerSize/size fail-closed（size 短于输入报尾随垃圾、长于输入立即报截断）、重复字符串池拒绝、节点 chunk 必须在池后、node 头固定 16、attributeCount 先于读取预检、结束标签名称/命名空间匹配校验、未闭合元素报错 | `axml.mbt` `parse`/`parse_start_element`/`parse_end_element`；`axml_test.mbt` 26 例 |
| B2 | UTF-8/UTF-16 严格解码已实现：拒绝过长编码、代理项码点、超 U+10FFFF、坏续延字节、孤立代理、缺 NUL 终止符；支持 8/16 位扩展长度前缀 | `decode.mbt` `decode_utf8`/`decode_utf16`/`decode_utf8_entry`/`decode_utf16_entry`；`axml_wbtest.mbt` 14 例 |
| B3 | 未知 chunk 按 headerSize/size 跳过；厂商变体（attributeStart/attributeSize < 20）报 `VendorVariant`；未知字符串池标志位报 `UnsupportedEncoding`；Res_value.size != 8 报 `BadHeaderSize` | `axml.mbt` L207-210/L271-275/L291-294；`decode.mbt` L284-288；`axml_test.mbt` 对应用例 |
| B4 | resource map 解析为 `Array[UInt32]`；namespace chunk 仅校验字符串引用后跳过，**不记录 prefix→URI 映射**；styles 保留原始字节不解析 | `axml.mbt` L176-187/L200-206；`decode.mbt` L333-337 |
| B5 | ARSC 全链已实现：dense u32 / FLAG_OFFSET16 u16 / FLAG_SPARSE 表 / compact entry / bag entry / library chunk（步长 260）/ config 逐字段解码 / `unpackLanguageOrRegion`（两位 ASCII 与 15 位压缩三字母码，地区 UN M.49 基 '0'）；overlayable(0x0204)/policy(0x0205)/staged alias(0x0206) 按大小跳过；继承包（typeStrings/keyStrings==0）报 `BadTable` | `arsc_decode.mbt` `parse_entries`/`parse_entry`/`parse_library`/`parse_config`/`unpack_locale`/`parse_package`；`arsc_test.mbt` 20 例 |
| B6 | `Res_value` 16 类型全映射（含 0x07/0x08 动态引用、0x1c-0x1f 颜色）；`format_value` aapt2 风格渲染：`hex_min` 最小宽度语义（高位非零输出更多数位）、`fixed6` 六位定点、`complex_number` fraction **不乘 100** | `arsc.mbt` `res_data_type_of`/`format_value`/`hex_min`/`fixed6`/`complex_number`；`arsc_test.mbt`「全数据类型渲染」、`arsc_wbtest.mbt` fixed6 |
| B7 | `lookup` 默认配置优先（无默认取 chunk 顺序首个）、`lookup_all`/`find_id`/`package_by_id` 已实现；`format_ref` 取首个命中的名字 | `arsc.mbt` `lookup`/`collect_hits`/`find_id`/`format_ref`；`arsc_test.mbt`「默认配置优先」 |
| B8 | **漂移**：`resolve_id` 注释声称成环输出 `@0x%08x (cycle)`，实际代码只有深度上限（depth>16 → `(too deep)`）与自引用检查（`(self reference)`），**无 visited 集环检测**，`(cycle)` 文本从未产出；README「引用链…环检测」对引用链不成立（真环检测仅在 bag/attr 链，见 B11） | `arsc.mbt` `resolve_id_depth` L450-477 vs 注释 L441 |
| B9 | `resolve_attr_value` 四路径已实现（FromId/FromName/Literal/Unresolved），不抛错；动态引用不改写（origin 恒 `Unresolved`）；`?attr` 属性按 id 走 `resolve_id`，**不做主题求值**（`eval_theme_attr` 是独立 API，未接入联合解析） | `arsc.mbt` `resolve_attr_value`/`try_resolve_raw_ref`/`resolve_attr_literal`；`arsc_test.mbt` attr 3 例 |
| B10 | qualifier 匹配已实现：`from_qualifiers` 支持 mcc/mnc/语言码/rXX/rNNN/sw·w·hdp/port/land/night/notnight/car/desk/television/appliance/watch/dpi 族；**`vNN`（SDK 限定符）不支持**——"v21" 落入语言码分支因数字报 `BadQualifier`；long/round/widecg/hdr 等亦不支持。`matches`/`is_better_than`（AOSP 优先级顺序子集）/`lookup_with` 已实现 | `arsc_match.mbt` `from_qualifiers` L131-141（语言分支）/`matches`/`is_better_than`/`lookup_with`；`arsc_match_test.mbt` 8 例 |
| B11 | `flatten_bag`/`eval_theme_attr` 带 visited 集环检测（`BagCycle`/`AttrCycle`）；**`BagMissingParent` 变体无任何显式测试**（全部测试文件 grep 0 命中；现有「parent 缺失」用例实际断言的是根 id 不存在的 `BagNotComplex`） | `arsc_match.mbt` L368-460；`arsc_match_test.mbt`「压平与求值错误路径」L320-363 |
| B12 | 错误变体实数：`AxmlError` 8 个、`ArscError` **12 个**（Eof/BadChunk/BadHeader/BadPool/BadIndex/BadTable + R4 新增 BadQualifier/BagNotComplex/BagMissingParent/BagCycle/AttrMissing/AttrCycle）；20 个变体中 19 个有显式断言用例 | `pkg.generated.mbti` L17-43；测试文件变体名 grep 簿记 |
| B13 | **漂移**：CLI 实际记录行仅 `EL\|`/`AT\|`/`SEM\|`/`POOL\|`/`STR\|`；README §5 列出的 `HDR\|`/`CLZ\|`/`ANN\|`/`SVC\|`/`XREF\|`/`MREF\|` 是 DEX 侧工具记录行，本 CLI 从不产出（跨模块描述误植）。退出码 0/1/2；`--arsc` 缺 `--resolve` → 2；`--resolve` 无表 → 2；`--entry` 对非 ZIP 输入 → 2 | `cmd/main/main.mbt` `cmd_dump`/`run`；`cmd/main/render.mbt` `tree_walk`/`sem_lines`/`pool_lines`；README §5 |
| B14 | **真缺口**：CLI `--resolve` 走 `lookup`（默认配置优先），库的 `lookup_with`/`from_qualifiers` 设备配置匹配能力**未接入 CLI**，无 `--config` 类选项 | `cmd/main/util.mbt` `resolve_res_ref`/`resolve_attr`；`cmd/main/main.mbt` L164-187 |
| B15 | sem 视图 label 仅取 `raw_value` 字面量（`attr_raw`），即使 `--resolve` 也不解析引用型 label；申报书场景 1「--resolve 得到可读 label」对引用型 label 不成立 | `cmd/main/render.mbt` `sem_info` L103-110 |
| B16 | **漂移**：`main.mbt` 头注释称「APK 容器条目读取使用 moonbitlang/core/archive/zip」，实际使用自研宽松读取器 `zipmin.mbt` + `core/compress/flate`。zipmin 范围：仅 Store/Deflate、无 ZIP64、**不做 CRC-32 校验**、inflate 上限取中央目录 usize（未知退化为 1GiB）、跳过 extra 区域不遍历链（容忍 aapt2 对齐裸填充） | `cmd/main/main.mbt` L5 vs `cmd/main/zipmin.mbt` 头注释/`zip_min_extract`；`cmd/main/moon.pkg` |
| B17 | **漂移+自包含缺口**：`tests/ASSETS.md` 不存在（`tests/` 下仅 fixtures/ 10 个文件），但被 ≥10 处代码注释与 **CLI 帮助文本**（用户可见）引用；资产登记（来源/SHA-256/黄金口径）实际只存在于工作区级登记文件，不随本仓库分发。fixture 来源：base/tvshell-debug 为受控自建、fx-multidex 为官方工具链自产、framework-res 为 AOSP Apache-2.0 [仅据工作区登记] | `fixtures_test.mbt` L4-10、`arsc_test.mbt` L5-11、`fixtures_malformed_test.mbt` L3、`cmd/main/main.mbt` L4/L29、`cmd/main/render.mbt` L3/L84、`cmd/main/util.mbt` L156；`tests/` 目录实测 |
| B18 | **漂移**：`docs/` 目录为空；`docs/DESIGN.md`/`docs/API.md` 被 `axml.mbt`/`arsc.mbt`/`arsc_decode.mbt`/`arsc_match.mbt`/`ci.yml` 多处引用但不存在；ci.yml 注释还引用不存在的 `pkg.generated.mbti.r1`；仓库无 CHANGELOG | `axml.mbt` L124/L128、`arsc.mbt` L49/L114/L233/L281/L492、`arsc_decode.mbt` L164/L255/L670、`arsc_match.mbt` L4、`.github/workflows/ci.yml` L16/L122；`docs/` 目录实测 |
| B19 | 五门禁 2026-11-16 本机实测全绿：`moon check --deny-warn` / `build` / `test` **103/103** / `fmt --check` / `info`+快照无 diff。3 个 `#skip` 不计通过：①checksum 污染（AXML 无 checksum 字段，N/A）②framework-res tree/pool 黄金过大未登记 ③真机测试本轮不执行 | 本机实跑输出；`fixtures_malformed_test.mbt` L235、`fixtures_test.mbt` L542/L571 |
| B20 | `tests/fixtures/*.bin` 10 个文件**不被任何测试读取**；回归实际依赖 `fixtures_test.mbt` 内嵌字节常量（FIXTURE-BEGIN/END 标记）；文件↔内嵌一致性无自动化校验 | `fixtures_test.mbt` L18-30 等；全测试文件无文件读取调用 |
| B21 | 零第三方依赖（`moon.mod` 无 import）；CLI 仅用 core（async/fs/compress/flate/env）；`preferred_target=wasm`；CI 为 wasm 五门禁 + 工具链版本钉死断言（moon 0.1.20261104 / moonc v0.10.20+65efd5b93） | `moon.mod`、`cmd/main/moon.pkg`、`.github/workflows/ci.yml` |
| B22 | **测试缺口**：`cmd/main` 无任何测试文件（CLI 契约无自动化回归）；CI 仅 wasm 目标，无 wasm/native 双目标等价门禁 | `cmd/main/` 目录实测；`ci.yml` L55 |
| B23 | **漂移**：`complex_number` 头注释称 fraction「×100 渲染为百分数」，实现注释与代码均为「不乘 100」（与 aapt2 dump 一致，实现正确） | `arsc.mbt` L719 vs L736-738 |
| B24 | `from_qualifiers` 构造的 config `size=64`、`raw` 为空字节；解析所得 config `raw`=原始字节。恒等式断言须按构造路径区分 | `arsc_match.mbt` L22-45；`arsc_decode.mbt` `parse_config` L584 |

**对历史口径的修正**（显式承认先前结论被推翻处）：

1. 申报书称「`ArscError` 6 变体」→ 实测 **12 变体**（R4 加法新增 6 个后文档未更新，B12）。
2. README §5 记录行清单混入 DEX 侧记录行（`HDR|CLZ|ANN|SVC|XREF|MREF|`）→ 本 CLI 仅 `EL|AT|SEM|POOL|STR|`（B13）。
3. README「引用链深度限制与环检测」→ 引用链（`resolve_id`）实为**深度上限 + 自引用检查**，无 visited 环检测；`(cycle)` 注释文本从未产出（B8）。
4. `main.mbt`「使用 core/archive/zip」→ 实为自研 zipmin + core/compress/flate（B16）。
5. 申报书场景 1「`--resolve` 直接得到可读 label」→ label 不参与 resolve，引用型 label 保持原样（B15）。
6. 「调研范围内 mooncakes.io 未见同类」→ 本次调研 mooncakes 搜索接口实测不可用（HTTP 422），结论须限定为「调研时点 2026-11-16、已发布包 + 可用索引范围内未见同语言同类库」，不冒充已穷举。

## 1. 硬约束（每个工作包都必须满足）

1. **API 冻结**：`pkg.generated.mbti` 为冻结基线，只允许纯加法（新 pub fn / 新 struct / 新 enum）。禁止给既有 `pub(all)` struct 加字段；**禁止新增错误变体**（破坏性变更须 ADR+用户裁决+CHANGELOG+主版本四件例外）；校验失败用值字段表达，解析失败复用既有变体；语义变更走新函数新类型防火墙，旧 API 语义永不改变。
2. **加法三件套**：快照随源码同提交且 diff 纯加法 + `docs/CHANGELOG.md` 登记 + CI 快照门禁绿。
3. **依赖不动**：本模块零第三方依赖，保持零依赖；CLI 仅可用 moonbitlang/core 既有包。core/compress/flate 的 `inflate_exact` 为一次性解压接口（`max_output` 参数），任何 ZIP 侧扩展只能用理论上界预检，不得假设流式限额。
4. **许可红线**：第三方 APK/.so/模型不入库；许可不明真实样本只允许「仓库外本地路径 + SHA-256 登记 + 显式 SKIPPED」；入库测试资产用确定性生成器自产或受控自建（现状 fixture 均满足，B17；登记文件须按 W1 重建为本仓库自包含）。
5. **五门禁**全绿才可合入：`moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check` / `moon info`+快照 diff；`#skip`/SKIPPED/退出码 78 不得写成通过。
6. **边界不变量**（非目标清单，含语义防火墙）：不做 aapt2 构建期资源编译与打包（W8 回编若裁决通过，仅做格式级 encode，不做资源编译）；无框架资源表时 `0x01…` 引用保持原样（W6 提供显式多表通道后，单表 API 语义仍不变）；不导出 trait；不 import 任何其他工作区模块；既有 CLI 记录行格式与退出码冻结，新能力只加新选项/新函数。
7. **文档自包含**：本仓库 docs/ 与注释不得引用、链接或假定可访问工作区其他目录；跨库事务只声明归属（ARSC 完整展开归本库；APK 容器模块只产原始字节——归属声明，非链接）。

## 2. 业界对标摘要（P2 结论，证据三级标注）

**功能覆盖对比**（行=能力，列=本模块 + 5 个最接近对标；✔=有、◐=部分/降级、✘=无、—=未核实）：

| 能力 | axml（本库） | androguard (Python) | ARSCLib (Java) | androidbinary (Go) | adbkit-apkreader (JS) | axmldec (C++ 工具) |
|---|---|---|---|---|---|---|
| AXML chunk/节点树/typed 属性 | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| UTF-8/UTF-16 字符串池 | ✔ 严格 | ✔ | ✔ | ✔ | ✔ | ✔ |
| ARSC 全结构（sparse/offset16/compact/bag） | ✔ | ✔ | ✔ | ◐ | ✘ | ✘ |
| 设备配置最优匹配 | ✔ 库层（CLI 未接入，B14） | ◐ | ✔ | ✔（GetResource 带 config） | ✘ | ✘ |
| 引用解析为可读值 | ✔（单表） | ✔ | ✔ | ✔ | ✘（留 resourceId:0x…） | ✘ |
| bag 压平 / ?attr 主题求值 | ✔ | ◐ | ✔ | — | ✘ | ✘ |
| 回编/写入/创建资源 | ✘（非目标） | ✘ | ✔（读写创建+JSON/XML 往返） | ✘ | ✘ | ✘ |
| manifest 语义对象 | ◐（CLI sem 字段级） | ✔ | ✔ | ✔（Manifest struct） | ✔（深度语义） | ✘ |
| 字节偏移错误模型 / fail-closed | ✔ | ◐ | ◐ | ◐ | ◐ | ◐ |
| 纯值零依赖 + wasm/native 双目标 | ✔ | ✘ | ✘ | ✘ | ✘ | ✘ |

- 证据等级：ARSCLib/androidbinary/adbkit-apkreader/axmldec 能力结论 = [已联网核实 2026-11-16，一手 README]；androguard = [已知常识]+二手用法片段；表中 ◐/— 与各家 star 数、维护状态 = [需联网核实]。
- **最接近 1–3 名**：① shogo82148/androidbinary（Go，MIT）——同为「解析 only + 配置感知取值 + 高层 label/icon」组合，重叠度最高；② REAndroid/ARSCLib（Java）——读侧超集且含写侧（本库非目标）；③ androguard（Python）——AXML+ARSC+语义全栈。
- **差异化判断**：本库是「已有成熟解析能力的 MoonBit 独立重写 + 组合语义差异化」——严格 fail-closed 结构校验（尾随垃圾拒绝、NUL/UTF 严格）、字节偏移错误模型、纯值零依赖、wasm/native 双目标、AXML×ARSC 单库联合解析。该组合在检索范围内未见同语言同类 [需联网核实：mooncakes 搜索接口 422 不可用，结论限定为已发布包+可用索引、调研时点 2026-11-16]。
- **缺失能力清单**：已声明非目标=回编/资源编译、框架资源（无表时）、overlay/idmap（申报书「后续」）；**真缺口**=CLI 设备配置接入（B14）、主题感知联合解析（B9）、`vNN` 等 qualifier 子集（B10）、动态引用改写视图（B5/B9）、多表联合解析、`BagMissingParent` 测试（B11）、CLI E2E 与双目标等价自动化（B22）。

## 3. 边界裁决（P3 结论）

**本质职责（一句话）**：把 AXML/ARSC 字节忠实解码为可查询的纯值结构，并在**给定表集合内**把资源引用解析为可读值——字节 → (结构, 值, 解析路径) | 带偏移错误。

**边界判据**：凡改变「AXML/ARSC 字节本身的解码/求值语义」的能力归本库；容器级信任（CRC/签名/ZIP 结构完整性）归 APK 容器模块；构建期资源生成归 aapt2（非目标）；manifest 业务风险判断（exported 是否危险等）归上层工具，本库只出字段。

**灰区裁决清单**：

| 灰区 | 裁决 |
|---|---|
| CLI 内 zipmin 宽松 ZIP 读取（无 CRC）与容器模块职责重叠 | **保留**为 CLI 便利层；文档显式声明「尽力读取、不提供容器完整性结论」；**不加 CRC 校验**（会改变既有 CLI 对损坏容器的接受行为，且信任结论归属容器模块）。冻结+归属声明 |
| sem 视图已含 manifest 语义（launcher 解析等） | 冻结现有 sem 行为与记录行；新语义能力走新选项/新函数，不改既有输出（B15 label 限制按现状文档化） |
| ARSC 实现与 APK 容器侧并存未去重（README 风险项） | 本库为 ARSC 完整展开权威归属（ADR-0003 口径）；容器侧只产原始字节。跨库一致性以归属声明锁定，不删代码 |
| `resolve_id` 环检测文档漂移（B8） | **只修文档**使口径与代码一致；不改既有输出文本（`(too deep)` 语义冻结）。如需真环检测另立新函数（本轮不做，登记为可选） |
| `from_qualifiers` 扩展 `vNN` 等 token | 接受原被拒输入属行为变更 → 走**新函数** `from_qualifiers_ext` 防火墙，旧函数语义永不改变（W3） |
| 动态引用改写 | 属本库求值职责（真缺口）；新函数新类型，旧 API 的 `Unresolved` 标注语义不变（W5） |

## 4. 工作包总览

| 包 | 名称 | 优先级 | 规模 | API 影响 | 对应缺口(B#) |
|---|---|---|---|---|---|
| W1 | 文档与资产登记重建（漂移清理） | P0 | S | 无 | B8/B13/B16/B17/B18/B23 |
| W2 | 错误簿记补齐 + 双通道一致性 | P0 | S | 无 | B11/B12/B20 |
| W3 | CLI 设备配置匹配 `--config` + qualifier 扩展新函数 | P1 | M | 加法：1 新 pub fn + CLI 新选项 | B10/B14 |
| W4 | 主题感知属性解析新函数 | P1 | M | 加法：1 新 pub fn | B9 |
| W5 | 动态引用映射视图新函数 | P2 | M | 加法：2 新 pub fn + 1 新 struct | B5/B9 |
| W6 | 多表联合解析新类型 | P2 | M | 加法：1 新 struct + 1 新 pub fn | B9/非目标边界 |
| W7 | overlay/idmap 支持（**裁决不通过，维持降级**） | P3 | L | 加法：新类型+新函数 | B5 |
| W8 | AXML 格式级回编（**已交付 M8-1/M8-2/M8-3**） | P3 | XL | 加法：1 新 pub fn | 申报书「后续」 |

## 5. 工作包详细设计

### W1 文档与资产登记重建（P0/S，零风险）

**目标**：消除 B8/B13/B16/B17/B18/B23 全部文档漂移，重建本仓库自包含的证据链登记。
**非目标**：不改任何代码行为、不改 API、不改 CLI 输出（帮助文本中失效引用改为实存文件除外）。
**新增 API**：无。
**实现要点**：
- 新建 `tests/ASSETS.md`：10 个 fixture 的 SHA-256 全量登记 + 来源/许可（受控自建/官方工具链自产/AOSP Apache-2.0）+ 黄金规范化口径（EL/AT、SEM、POOL/STR 记录行格式，即现 CLI 帮助所称 §4）+ 畸形派生命令 + 内嵌常量与文件双通道说明；许可不明第三方样本只登记「仓库外路径约定 + 哈希 + 显式 SKIPPED」，不入库。
- 新建 `docs/API.md`：降级项清单（动态引用不改写、overlayable/policy/staged-alias 跳过、styles 不解析、namespace 映射不暴露、跨包名字前缀忽略、qualifier 子集边界、`resolve_id` 深度上限语义）+ 错误模型实数（AxmlError 8 / ArscError 12）；使既有注释引用实存。
- 新建 `docs/CHANGELOG.md`：登记本包及后续各包。
- README 修正：§5 记录行清单改为 `EL| AT| SEM| POOL| STR|`；「引用链深度限制与环检测」改为「引用链深度上限与自引用检查；bag/attr 链带环检测」；§6 风险项补「tests/fixtures 文件与内嵌常量一致性由 W2 脚本门禁锁定」。
- 注释修正：`arsc.mbt` L441 `(cycle)` 口径、L719 ×100 矛盾、`main.mbt` L5 zip 描述、`ci.yml` 失效引用（`pkg.generated.mbti.r1`、docs/API.md 提示改为实存路径）。
- `docs/DESIGN.md` 引用处理：在 `docs/API.md` 内承接降级策略章节，`axml.mbt` 注释改指 `docs/API.md`（不新建空壳 DESIGN.md）。
**验收**：T-W1-1（全仓库 grep 无失效文件引用）；T-W1-2（ASSETS.md 哈希与 tests/fixtures 实测一致）；T-W1-3（README 记录行清单与 CLI 实际输出一致）；T-W1-4（五门禁全绿、快照零 diff）；T-W1-5（帮助文本引用的文件实存）。

### W2 错误簿记补齐 + 双通道一致性（P0/S）

**目标**：错误变体显式用例 20/20（补 B11 缺口）；锁定 fixture 文件↔内嵌常量一致性（B20）。
**非目标**：不改解析代码；不新增错误变体。
**新增 API**：无。
**实现要点**：
- `arsc_match_test.mbt` 新增用例：构造 bag 其 parent id 在表中不存在（根 id 存在且为 Complex），断言 `BagMissingParent(parent_id)` 变体名与 id 值。
- 配套文档 `docs/API.md` 错误簿记表：20 变体 × 触发用例名，双向可核对（测试系统设计 §6.2）。
- 脚本层一致性检查（可选 job，仓库内脚本）：① tests/fixtures 10 文件 SHA-256 与 ASSETS.md 登记比对；② 提取 `fixtures_test.mbt` FIXTURE-BEGIN/END 块字节与对应文件逐字节比对；缺失脚本运行环境时显式 SKIPPED（退出码 78 口径），不得写成通过。
**验收**：T-W2-1（BagMissingParent 显式用例绿）；T-W2-2（簿记表 20/20 与测试代码双向核对无缺）；T-W2-3（一致性脚本对本仓库 fixture 全绿）；T-W2-4（五门禁全绿、快照零 diff）。

### W3 CLI 设备配置匹配 `--config` + qualifier 扩展（P1/M）

**目标**：把库层 `lookup_with` 最优匹配接入 CLI（B14）；以新函数扩展 qualifier 子集（B10），旧 `from_qualifiers` 语义冻结。
**非目标**：不改无 `--config` 时的任何输出字节；不改 `from_qualifiers` 对既有 token 的行为；不做 sem label 引用解析（B15 按现状文档化，变更须另行裁决）。
**新增 API（mbti 草案，纯加法）**：

```text
pub fn ResConfig::from_qualifiers_ext(String) -> Self raise ArscError
```

**实现要点**：
- `from_qualifiers_ext` 在旧子集基础上增加：`vNN`（sdk_version）、`long`/`notlong`、`round`/`notround`、`widecg`/`nowidecg`、`highdr`/`lowdr`、`navhidden`/`navexposed`、`keysexposed`/`keyssoft`/`keyshidden`、`qwerty`/`12key`、`dpad`/`wheel`/`nonav`、`finger`/`nofinger`、`stylus`/`nostylus`、`trackball`/`notouch`、`b+<lang>[+<region>]`（BCP47 子集，映射 language/country）；未知 token 仍复用 `BadQualifier`。旧函数不动（防火墙）。
- CLI 新选项 `--config <qualifiers>`：仅与 `--resolve` 同用（否则退出码 2，与 `--arsc` 约束同构）；解析用 `from_qualifiers_ext`；`--resolve` 取值路径在有 `--config` 时改走 `lookup_with(id, device)`，未命中回退 `lookup`（默认配置优先），再退 `@0x%08x`。
- `util.mbt` 新增内部渲染分支，不动既有 `attr_value` 无 resolve 路径；帮助文本追加选项说明（加法）。
- 落点：`arsc_match.mbt`（新函数）、`cmd/main/main.mbt`（选项）、`cmd/main/util.mbt`（分支）。
**验收**：T-W3-1（ext 对旧子集全部 token 与旧函数结果逐字段一致）；T-W3-2（`v21`/`b+en+US` 等新 token 正确、旧函数对 `v21` 仍报 BadQualifier）；T-W3-3（`--config zh` 命中 zh 配置值、无匹配回退默认）；T-W3-4（无 `--config` 时全部既有 CLI 输出逐字节不变）；T-W3-5（`--config` 缺 `--resolve` → 退出码 2）；T-W3-6（快照 diff 纯加法 + 五门禁）。

### W4 主题感知属性解析新函数（P1/M）

**目标**：打通 `?attr` 属性在联合解析中的主题求值（B9），旧 `resolve_attr_value` 语义不变。
**非目标**：不改旧函数；不做跨表主题（W6 职责）；不新增错误变体。
**新增 API（mbti 草案，纯加法）**：

```text
pub fn resolve_attr_value_with_theme(
  AxmlDoc, ResTable, XmlAttribute, UInt32, ResConfig
) -> ResolvedAttr
```

**实现要点**：参数为主题资源 id 与设备配置。`value_type` 为 Attribute/DynamicAttribute（或 raw_value 形如 `?attr/…`/`?0x…`）时调 `eval_theme_attr(table, theme_id, attr_id, device)`，成功 → `{ text: format_value(结果), id: Some(attr_id), origin: FromId }`；`eval_theme_attr` 抛错（AttrMissing/AttrCycle/Bag* 等）一律捕获降级为 `Unresolved(原因文本)`，**保持不抛错契约**；其余类型委托旧 `resolve_attr_value`。落点 `arsc.mbt` 末尾新块。
**验收**：T-W4-1（theme bag 中 `?attr` 链求到最终字面量）；T-W4-2（AttrMissing/AttrCycle 降级为 Unresolved 且不抛错）；T-W4-3（非引用类型结果与旧函数逐字段一致）；T-W4-4（旧函数全部既有用例零改动绿）；T-W4-5（快照 diff 纯加法 + 五门禁）。

### W5 动态引用映射视图新函数（P2/M）

**目标**：把已解析的 `RES_TABLE_LIBRARY_TYPE` 映射暴露为可查询视图（B5/B9），为上层改写动态引用提供忠实数据；旧 API 的「不改写」语义不变。
**非目标**：不做跨表最终值解析（需共享库自身 arsc，W6 之后另议）；不改 `resolve_id`/`format_value` 输出。
**新增 API（mbti 草案，纯加法）**：

```text
pub(all) struct DynamicRefView {
  origin_id : UInt32
  runtime_package_id : Int32
  library_name : String?
}
pub fn ResTable::library_by_id(Self, Int32) -> ResLibrary?
pub fn ResTable::dynamic_ref_view(Self, UInt32) -> DynamicRefView
```

**实现要点**：`dynamic_ref_view` 取 id 的包字节，在各包 `libraries` 中查 `package_id` 匹配项；未命中 `library_name=None`（值化降级，不报错）。开发时须先对 AOSP `LoadedArsc` 动态引用语义做一次核对并在 docs/API.md 登记口径（本包只暴露映射事实，不声称完成改写）。落点 `arsc.mbt`。
**验收**：T-W5-1（library chunk 样本命中/未命中两路径）；T-W5-2（旧 API 对动态引用仍输出 `(dynamic)`/Unresolved，零变化）；T-W5-3（快照 diff 纯加法 + 五门禁）。

### W6 多表联合解析新类型（P2/M）

**目标**：显式提供框架/共享库资源表通道，使 `0x01…` 引用在**调用方提供框架表时**可解析；单表 API 与「无框架表保持原样」非目标口径不变。
**非目标**：不自动加载/内置任何框架资源；不改旧函数；不新增错误变体。
**新增 API（mbti 草案，纯加法）**：

```text
pub(all) struct ResTableSet {
  tables : Array[ResTable]
}
pub fn resolve_attr_value_multi(AxmlDoc, ResTableSet, XmlAttribute) -> ResolvedAttr
```

**实现要点**：按 id 包字节选表（`package_by_id` 命中者优先），名字级解析按 tables 顺序首个命中；全部未命中 → `Unresolved`，不抛错。framework-res 的 arsc 已可被 `parse_arsc` 解析（现有 fixture 用例证实），本包只做组合。落点 `arsc.mbt`。
**验收**：T-W6-1（应用表+框架表联合，`0x01…` 属性解析为框架值）；T-W6-2（空表集/未命中降级 Unresolved）；T-W6-3（单表结果与旧函数一致）；T-W6-4（快照 diff 纯加法 + 五门禁）。

### W7 overlay/idmap 支持（P3/L，**裁决不通过，维持降级**）

**目标**：解析 overlayable(0x0204)/policy(0x0205)/staged alias(0x0206) chunk 与 idmap 文件，支撑 RRO 资源覆盖分析。
**非目标**：不做运行时 overlay 合成语义；不改既有跳过行为对应的旧 API 输出。
**新增 API（mbti 草案，纯加法；错误复用 `BadTable`/`BadHeader`/`Eof`）**：

```text
pub(all) struct ResOverlayable { name : String, actor : String, policy_flags : UInt32 }
pub(all) struct IdMap { target_package_id : Int32, entries : Array[IdMapEntry] }
pub(all) struct IdMapEntry { target_id : UInt32, overlay_id : UInt32? }
pub fn parse_idmap(Bytes) -> IdMap raise ArscError
pub fn ResPackage::overlayables(Self) -> Array[ResOverlayable]  // 新类型防火墙：见实现要点
```

**实现要点**：既有 `ResPackage` 不可加字段 → overlayable 数据须挂新类型（如 `parse_arsc_ext(Bytes) -> ResTableExt`，`ResTableExt { table : ResTable, overlayables : Array[...] }`），mbti 草案以新类型为准，上述 `ResPackage::overlayables` 不落地。idmap 为独立文件格式（魔数 0x504D4449），按 AOSP `Idmap.cpp` 校验。
**降级方案（裁决不通过时）**：维持跳过 + docs/API.md 登记，本包关闭。
**裁决结论（2026-11-19）**：不立项。维持既有跳过行为与降级登记，本包关闭，不新增 overlayable/idmap API。
**验收**：T-W7-1（程序化 overlayable/idmap fixture 解析逐字段）；T-W7-2（畸形 idmap 全前缀截断不 panic）；T-W7-3（旧 API 零变化）；T-W7-4（快照纯加法 + 五门禁）。

### W8 AXML 格式级回编（P3/XL，**裁决通过；M8-1/M8-2/M8-3 已交付**）

**目标**：`AxmlDoc → Bytes` 格式级 encode，满足「解析→修改→回编」逆向工作流；不做资源编译/打包（非目标不变）。
**非目标**：不做 arsc 写入；不做 XML 文本→AXML 编译；不保证与 aapt2 产物字节级一致（只保证语义往返）。
**新增 API（mbti 草案，纯加法）**：

```text
pub fn encode(AxmlDoc) -> Bytes raise AxmlError
```

**实现要点**：重建字符串池（UTF-16 优先， SORTED 可选）、resource map、namespace/element/cdata chunk；索引越界复用 `InvalidStringIndex`/`InvalidNodeIndex`。里程碑拆分：M8-1 字符串池+空文档往返；M8-2 元素/属性往返；M8-3 真实 fixture 语义往返（`parse(encode(doc))` 与 `doc` 规范化等价）；每里程碑独立五门禁，止损条件=往返律在受控 fixture 上无法闭合即停。
**裁决结论（2026-11-19）**：方案 B 通过，W8 立项。
**M8-1 交付（2026-11-19）**：`encode` 落地，范围=字符串池（保留 UTF-8/UTF-16 编码与顺序）+ resource map + 空文档；`parse(encode(doc))` 在 UTF-8/UTF-16（含代理对）与 resource map 受控样本上往返成立，编码产物二次往返逐字节稳定。节点表非空与样式块非空以 `VendorVariant` 显式拒绝（不静默丢信息），留待 M8-2。
**M8-2 交付（2026-11-19）**：元素/属性/CDATA 回编落地；START_ELEMENT 固定 attributeStart/attributeSize=20，END_ELEMENT 与 CDATA 按解析侧布局重建；`ValueType`（含 `Unknown`）、`res0`、`raw_data`、`line`、ns/rawValue 可选索引全部保真。往返律在 UTF-8/UTF-16 golden、多根 + 顶层 CDATA、未知属性类型等受控样本上闭合；未被根/父引用的节点、重复访问（多父/环）、缺失池字符串均显式报错。命名空间声明 chunk 不重建（`AxmlDoc` 不保留前缀/声明位置，解析侧本就跳过）。样式块仍以 `VendorVariant` 拒绝。
**M8-3 交付（2026-11-19）**：真实入库 AXML fixture（base / tvshell-debug / fx-multidex / framework-res）全部 `parse(encode(doc))` 逐字段等价，CLI 规范化 tree/pool 逐行一致；encode 产物二次往返逐字节稳定、再 parse 不 panic。W8 至此全部交付，往返律在程序化与真实样本上均闭合。
**降级方案**：维持解析 only 定位，申报书「后续」项如实保留。
**验收**：T-W8-1（空文档/单元素往返）；T-W8-2（全部入库 AXML fixture 语义往返律）；T-W8-3（encode 产物再 parse 不 panic）；T-W8-4（快照纯加法 + 五门禁）。

## 6. 里程碑与合入顺序

```text
M0（第1日）  W1 → W2        零风险文档/簿记先行
M1          W3 → W4        高价值低成本：CLI 配置匹配 + 主题求值
M2          W5 → W6        解析纵深：动态映射视图 + 多表联合
M3（裁决后） W7 / W8        大工程：overlay/idmap、回编（各自独立里程碑）
```

排序判据：先零风险文档、再安全/正确性缺口（错误簿记）、再高价值低成本、最后大工程；每包独立提交、独立过五门禁。

**须用户裁决项**：① W7 overlay/idmap 是否立项；② W8 回编是否立项（XL，建议先做 M8-1 验证往返律再决定全量）；③ sem label 是否新增 `--resolve-label` 选项（默认建议：不改，按 B15 文档化限制）。

## 7. 簿记与变更管理

- `docs/CHANGELOG.md`（W1 建立）：每包登记「日期/工作包/新增 pub 声明/快照 diff 结论/测试增量」。
- README API 索引随 `moon info` 快照同步（禁手编 mbti）；CLI 帮助文本与 README §5 同提交更新。
- 破坏性需求一律走四件例外流程（ADR+用户裁决+CHANGELOG+主版本），本轮各包均不触发。

## 8. 完成定义（DoD，逐包勾选）

- [ ] 新增 API 与 mbti 草案一致（偏差回写本文）
- [ ] 快照 diff 纯加法，CHANGELOG 已登记
- [ ] T-W*-* 验收全绿；#skip 显式标注原因
- [ ] 五门禁全绿；CLI 对外契约零意外漂移（无新选项时输出逐字节不变）
- [ ] 畸形语料无 panic（新增解析路径进截断扫描）
- [ ] 零新第三方依赖；零许可不明二进制入库
- [ ] README 能力/非目标同步；本文状态行更新「已交付+日期」

## 9. 风险登记

| 风险 | 等级 | 缓解 |
|---|---|---|
| `from_qualifiers_ext` 新 token 与 AOSP 语义偏差（如 b+ BCP47 回退规则） | 中 | 以 AOSP `ResourceTypes.cpp` 为基准逐 token 核对；未覆盖维度按「资源未指定=任意」如实降级并登记 |
| W4 主题求值把 `eval_theme_attr` 错误降级为文本后，上层误以为已解析 | 中 | origin 恒为 `Unresolved(原因)`，测试断言 origin 而非仅 text |
| W5 动态引用语义核对不足导致视图误导 | 中 | 只暴露映射事实（library_name），文档明确「未完成改写」；AOSP 核对记录进 docs/API.md |
| W8 往返律在厂商变体样本上不闭合 | 高 | 里程碑止损；厂商变体输入 encode 报 `VendorVariant`（复用既有变体），不静默丢信息 |
| fixture 登记重建时哈希与内嵌常量不一致（样本漂移假绿） | 中 | W2 双通道一致性脚本先行，哈希不符即红 |
| CLI 新选项破坏既有脚本解析 | 低 | 无新选项时输出逐字节冻结（T-W3-4）；帮助文本仅加法 |