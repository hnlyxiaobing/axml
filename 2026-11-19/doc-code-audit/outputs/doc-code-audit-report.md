# axml 文档-代码对抗性核对报告

- 日期：2026-11-19
- 工作区：`d:\MoonBit\Second_Quarter_Competition\axml`
- 方法：提取全部任务型文档（开发计划、测试系统设计、README、CHANGELOG、API 登记、ASSETS 登记）→ 逐条落到源码符号、测试用例、构建/测试结果 → 对不实表述就地最小订正 → 本报告只记录可复现证据。
- 结论摘要：**主线工作包 W1–W6、W8、W9 与 L0/L4 大部分真实交付（`moon test` 152/152，3 个 `#skip`）**；但文档存在 3 处实质性夸大/失真：**W3 的 CLI `--config` 未接入取值主路径**、**W2 的 T-W2-3 双通道脚本门禁完全未落地**、**W9 的 `ResConfig.raw` 零填充描述与实现相反**。另有计数漂移、失效章节引用与若干状态标记过时，均已订正。

---

## 1. 实测基线

| 检查 | 结果 |
|---|---|
| `moon check --deny-warn` | 通过 |
| `moon build` | 通过 |
| `moon test` | **Total tests: 152, passed: 152, failed: 0** |
| `moon fmt` | 通过 |
| `moon info` + `git diff -- pkg.generated.mbti` | 接口无变化（diff 为空） |
| test 声明总数 | 155 = 152 执行 + 3 `#skip` |
| fixture 哈希 | 10/10 与 `tests/ASSETS.md` §1 登记一致（人工脚本比对 `mismatches=0`） |

分发：`axml_test` 36、`axml_wbtest` 14、`arsc_test` 23、`arsc_wbtest` 6、`arsc_match_test` 16、`arsc_encode_test` 6、`encode_fixtures_test` 5、`fixtures_test` 21（2 skip）、`fixtures_malformed_test` 11（1 skip）、`cli_e2e_test` 17。

---

## 2. 任务清单与逐条核验

### 2.1 已完成（有源码符号 + 真实测试双重证据）

| 任务 | 证据 |
|---|---|
| W1 文档/测试资产重建 | `tests/ASSETS.md`、`docs/API.md`、`docs/CHANGELOG.md` 实存；10 个哈希全部匹配；README 记录行清单与 CLI 实际输出一致 |
| W1 注释/帮助文本修正 | 本轮补修残留章节引用；五门禁通过、接口零变化 |
| W2 错误簿记 20/20 | `AxmLangError` 8 + `ArscError` 12 个变体名均出现在 `*test.mbt`；含 `BagMissingParent` 显式用例 |
| W3 qualifier 扩展 | `ResConfig::from_qualifiers_ext`（`arsc_match.mbt`）支持 vNN/BCP47/UI mode/input/color mode 等；`arsc_match_test.mbt` 29 组旧子集逐字段一致 + 新 token 用例 |
| W4 主题求值 | `resolve_attr_value_with_theme`（`arsc.mbt`）返回 `FromTheme`，主题链求值、非引用一致、失败降级不抛错 3 例通过 |
| W5 动态引用视图 | `DynamicRefView`/`ResTable::library_by_id`/`dynamic_ref_view` 实存；动态引用不抛错、library 命中/未命中 2 例通过 |
| W6 多表联合解析 | `ResTableSet`/`resolve_attr_value_multi` 实存；id/名字/未命中 3 例通过 |
| W8 AXML 回编 | `encode` 实存；UTF-8/UTF-16 池、resource map、元素/属性/CDATA 往返；`encode_fixtures_test.mbt` 5 例；M8-1/2/3 全部落地 |
| W9 ARSC 回编 | `encode_arsc` 实存；空表/全局池/包结构/bag/library/错误路径 6 例通过；dense 布局 |
| L4 CLI E2E | `cmd/main/cli_e2e_test.mbt` 17 例，覆盖退出码 0/1/2、ZIP 直读、`--entry`、`--resolve`、记录行冻结 |
| W7/W10 裁决项 | 均为“不立项”，代码中确无对应实现，符合裁决 |

### 2.2 未完成或部分完成（文档曾声称完成）

#### （1）W3 `--config` 未接入取值主路径 —— 重大不一致

文档原声称 `--resolve` 取值“有 `--config` 时改走 `lookup_with`”，T-W3-3（zh 命中 zh 值）已落地。实际调用链：

1. `cmd/main/util.mbt`：`resolve_attr` 先调用 `resolve_attr_value`；
2. `arsc.mbt`：Reference 走 `resolve_id`/`resolve_id_depth`，二者使用 `self.lookup(id)`；
3. `lookup` 的语义是“默认配置命中优先，否则 chunk 顺序首个命中”；
4. `dev_config` 只在 `resolve_res_ref` 中使用，产出的是 `@type/name` 名字级回退，**不是取值**；
5. 因此多配置表中 `--config zh-rCN` 仍输出默认配置值。

测试侧证据：L4 用例 `L4 config with resolve wired` 的 arsc 夹具只有 `id=1` 单配置，断言仅为“退出码 0 + 输出含 label”，**无法证明按配置选值**。T-W3-4（无新选项输出逐字节不变）也未自动化，仅有“未知选项 → 2”一例。

运行时反证（真实 fixture，可复现）：`fx-multidex.resources.arsc` 的 `string/app_name` 同时有默认 `"Fx Multidex"` 与 `zh` 值 `"Fx 多维"`：

```
moon run cmd/main -- dump tests\fixtures\fx-multidex.AndroidManifest.xml \
  --resolve --arsc tests\fixtures\fx-multidex.resources.arsc
# AT|1|application|...|label|Fx Multidex

# 加 --config zh 后：
# AT|1|application|...|label|Fx Multidex   （仍为默认值，未输出 "Fx 多维"）
```

结论：T-W3-1/2/5/6 完成；**T-W3-3 未达标（已运行时证实）、T-W3-4 未验证**。已在开发计划、测试系统设计、README、CHANGELOG、CLI 帮助与 `docs/API.md` D15 如实登记。

#### （2）W2 T-W2-3 双通道一致性脚本完全未落地

- 仓库内不存在任何 `.ps1/.sh/.py/.mbtx` 脚本；
- 测试代码不读取 `tests/fixtures/`（grep `read_file|@fs.|open(|read_to_end` 无命中），回归实际只跑 `fixtures_test.mbt` 的内嵌常量单通道；
- 文件与内嵌常量的逐字节等价**没有自动校验**；本次仅人工完成“文件 SHA-256 ↔ ASSETS 登记”比对；
- `tests/ASSETS.md` §2 原文声称“W2 脚本层 job，无脚本环境显式 SKIPPED”，与实际“无任何脚本”不符。

结论：W2 的 20/20 簿记完成，但“锁定双通道一致性”的目标未达成。

#### （3）W9 `ResConfig.raw` “空/短零填充”描述与实现相反

`arsc_encode.mbt` `encode_type`：

```
if cfg.config.size < 4 || cfg.config.size > cfg.config.raw.length() {
  raise BadTable
}
```

`from_qualifiers` 构造的配置为 `size=64`、`raw` 空，`64 > 0` 直接报 `BadTable`；所谓“空/短零填充到 size”的 `else` 分支不可达。W9 的 6 个测试全部基于 `parse_arsc` 读出的配置（`raw` 长度等于 `size`），因此没有暴露该限制。

#### （4）测试体系中的未建项（文档自身已标待建，本次确认仍缺失）

- L1：位翻转、随机变异（≥1000 体）、全部 fixture 全前缀扫描、W8/W9 编码产物入截断扫描集 —— 均无对应测试；本次还把“W8 encode 产物已入扫描集”的错误状态改为“仅再 parse，未做全前缀扫描”。
- L3：aapt2 差分 oracle 与 R runner —— 未建、未运行。
- L5：wasm/native 双目标等价门禁、变异自检 —— 未建；快照纯加法与接口零 diff 已满足。
- P3/P4/P6/P7 —— 未建（P7 即 T-W2-3）。
- P10 防火墙律 —— 仅由 W4-3/W6-3 等局部一致性用例承载，无逐包统一机制。

#### （5）计数与状态漂移（已订正）

- 测试系统设计头部与 §2 原为 135/135、138 声明，实测 152/152、155 声明；同页“`cmd/main` 无测试”与 17 例 L4 矛盾。
- 开发计划 B22 原写 16 例，实际 17 例。
- 开发计划 §2 把已交付的 vNN qualifier 仍列为“真缺口”，且“回编/写入”仍标 ✘。
- 新测试基线使 F-A 的 `axml_test 26 例`、`arsc_match 8 例`、F7/S2 的“W3 已实现”、§7 的“zh 命中值”“无新选项真实回归”等表述过时。

---

## 3. 文档更正清单（均为事实性订正，无代码逻辑改动）

### 3.1 代码内注释 / 用户可见帮助文本

| 位置 | 原表述 | 订正 |
|---|---|---|
| `arsc.mbt` fraction 注释 | “fraction 按 aapt2 风格 ×100 渲染” | “与 aapt2 dump 一致，不乘 100” |
| `cmd/main/main.mbt` 头注释与 `--help` 输出 | 记录行口径见 `tests/ASSETS.md §4` | 改为 §3（ASSETS 实际章节） |
| `cmd/main/main.mbt` `--config` 帮助 | “指定后资源匹配走 lookup_with” | “参与名字级回退 lookup_with；取值主路径仍默认配置优先（D15）” |
| `cmd/main/util.mbt` `dev_config` 注释 | “指定后资源匹配走 lookup_with” | 明确仅名字级回退使用，主路径仍 `lookup` |
| `cmd/main/util.mbt`、`render.mbt` | `ASSETS.md §4` | §3 |
| `fixtures_test.mbt` 多处 | §4/§5/§6/§7 | §3 或 §1；删除不存在的“接线说明 §7” |
| `fixtures_malformed_test.mbt` | “派生命令见 §8” | “派生样本登记见 §1”（实际未记录命令） |
| `arsc_test.mbt` | framework-res 结论见 §3 | 来源/登记见 §1 |
| `.github/workflows/ci.yml` | “`pkg.generated.mbti.r1` 是 R1 基线存档”（文件不存在） | 明确“当前仓库内不存在、不由 moon info 生成” |

### 3.2 `docs/2026-11-16-resource-fidelity-dev-plan.md`

- 顶部状态行：补充“W2 T-W2-3 未落地、W3 `--config` 未接入取值主路径”。
- B22：16 例 → 17 例。
- §2 能力表：“设备配置最优匹配”改为“CLI 仅解析 + 名字级回退”；“回编/写入”由 ✘ 改为 ✔ 格式级回编。
- §2 缺失能力清单：移除已交付的 vNN，补入 T-W2-3 与 `--config` 选值缺口。
- W1：记录行章节 §4 → §3；注明“畸形派生命令”实际未记录；注明 ×100 注释由本次复核补做。
- W2：目标加“未完全达成”说明；实现要点与验收明确 T-W2-3 未完成。
- W3：目标、实现要点、验收改写为“仅名字级回退；T-W3-3 未达标、T-W3-4 未自动化”。
- W6：改为“按 `set.tables` 顺序首个命中，未使用 `package_by_id`”。
- W8：实现要点明确“不重建 namespace 声明 chunk”。
- W9：改为“`size > raw.length()` 报 `BadTable`，零填充分支不可达”。
- §8 DoD：“T-W*-* 验收全绿”取消勾选并注明例外；去掉“无新选项输出逐字节不变”的既成事实口吻。

### 3.3 `docs/2026-11-16-test-system-design.md`

- 头部：135/135 → 152/152，并注明 3 个 skip。
- §2：138/135 → 155/152；补 `cli_e2e_test` 17、删除“`cmd/main` 无测试”。
- §3：F-A 计数 26→36、8→16；F-B 改为“哈希已人工核对、逐字节比对未自动化”；F-C 注明 W1 已重建。
- §4：P5 的 T-W3-1 标记为已完成；P10 改为部分承载；截断扫描明确 W8/W9 产物未入扫描集。
- §6.1：F7/S1/S2 改为 W3 部分实现、T-W3-3 未验证、T-W3-4 未自动化。
- §7：设备配置行改为“单配置夹具，未验证 zh 值”；无新选项冻结行改为“无逐字节基线比对”。
- §10：L4 条目注明 T-W3-3 未验证、T-W3-4 未自动化。

### 3.4 `README.md`

- `--config` 能力描述由“设备限定符匹配”改为“解析 + 名字级回退；取值主路径默认配置优先（D15）”。
- §6 未自动化项补入“fixture 文件↔内嵌常量一致性脚本（T-W2-3）”。

### 3.5 `tests/ASSETS.md`

- §2 一致性门禁由“W2 脚本 job / 缺失即 SKIPPED”改为“哈希已人工比对；逐字节比对未自动化；脚本落地前不得声称门禁生效”。

### 3.6 `docs/API.md`

- 新增 D14：`encode_arsc` 的 `ResConfig.raw` 回写条件与 `BadTable` 行为。
- 新增 D15：CLI `--config` 仅接名字级回退，不按设备配置选值。
- 文件头澄清 `docs/DESIGN.md` 不存在、登记已统一到本文件。

### 3.7 `docs/CHANGELOG.md`

- W3 条目：删除“取值走 lookup_with”，标注仅名字级回退；T-W3-3 未达标、T-W3-4 未自动化。
- W6 条目：删除“package_by_id 命中优先”，改为按 tables 顺序首个命中。
- W9 条目：删除“空/短零填充”，改为 `size > raw.length()` 报 `BadTable`。
- L4 条目：`--config` 场景改为“选项/解析/名字级回退接线（未验证按配置选值）”。
- 末尾新增“文档-代码对抗性核对订正（2026-11-19）”，汇总上述事实性更正。

---

## 4. 存疑 / 未能运行时验证

1. **aapt2 外部差分 / R runner / 双目标等价 / 变异扫描**：本机未执行，也未发现脚本；只能确认“未建”，不能评估实际差分通过率。
2. **W8 的 namespace 文本前缀**：`AxmlDoc` 不保留声明位置，往返等价是“解析模型级”而非“原始字节级”；文档已明确“不重建 namespace 声明 chunk”，但若使用方要求字节级保真，仍属已知边界。
3. **W9 对构造型资源的可用性**：`encode_arsc` 只对 `parse_arsc` 产物可靠；用 `from_qualifiers` 构造的配置无法回编，文档已登记为 D14，是否修复属行为变更，需另行裁决。

---

## 5. 对文档可信度的总体判断

- 主线实现（解析、匹配、主题求值、多表、AXML/ARSC 回编、CLI E2E）**确有代码与测试支撑**，不是空壳；W8/W9 的往返测试是真实的语义断言。
- 但此前文档在“CLI 配置匹配”“双通道门禁”“W9 零填充”三处**把设计意图写成了既成事实**，且计数/章节引用长期漂移，说明“完成声明”不能直接采信。
- 本次订正后，开发计划、测试系统设计、README、API、ASSETS、CHANGELOG 的完成状态与实测一致；剩余未完成项已显式标注，不再以“已完成”面目出现。
