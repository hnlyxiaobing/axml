# 任务清单提取（过程记录）

来源文档：

- `docs/2026-11-16-resource-fidelity-dev-plan.md`（W1–W10、M8-1~3、W9-1~4、DoD）
- `docs/2026-11-16-test-system-design.md`（L0–L5、R runner、P1–P11 性质/变异、截断/位翻转、§10 落地清单）
- `README.md`（能力/非目标/状态声明，作为需核对的“完成声明”）
- `docs/CHANGELOG.md`（逐工作包完成记录，作为需核对的“完成声明”）
- `docs/API.md`（D1–D13 降级登记 + 错误簿记）
- `tests/ASSETS.md`（W1 交付物；§2 一致性门禁声明）

## 全量任务与实测结论

| 来源/ID | 文档要求或声明 | 实测结论 | 证据 |
|---|---|---|---|
| W1 | 重建 ASSETS/API/CHANGELOG；修 README/注释漂移 | 基本完成；本次补修残留章节引用与帮助文本 | 三文件实存；10 个 fixture SHA-256 与 §1 登记 10/10 匹配；`moon test` 通过 |
| W1 T-W1-1 | 全仓库 grep 无失效文件引用 | 审计前不成立（多处 §4/§6/§7/§8 指向不存在章节；`.r1`）；已订正 | 见更正清单 |
| W1 T-W1-2 | ASSETS 哈希与文件一致 | 通过 | PowerShell 逐文件比对 mismatches=0 |
| W1 T-W1-3 | README 记录行清单与 CLI 输出一致 | 通过 | README §5 列 `EL/AT/SEM/POOL/STR`；render.mbt 实际输出同 |
| W1 T-W1-4 | 五门禁全绿、快照零 diff | 通过 | `moon check --deny-warn`/`build`/`test`/`fmt`/`info`；`pkg.generated.mbti` diff 为空 |
| W1 T-W1-5 | 帮助文本引用文件实存 | 文件实存；章节号原误写 §4，已改 §3 | `cmd/main/main.mbt` |
| W2 目标 | 20/20 错误簿记 + 锁定双通道一致性 | 部分完成 | 20 个变体在测试中均出现；双通道脚本缺失 |
| W2 T-W2-1 | BagMissingParent 显式用例 | 通过 | `arsc_match_test.mbt` 用例 `r4 arsc: 压平 BagMissingParent` |
| W2 T-W2-2 | 20/20 簿记双向核对 | 通过 | 20 个错误构造器名逐一出现在 `*test.mbt` |
| W2 T-W2-3 | fixture 文件↔内嵌常量一致性脚本 | **未完成** | 仓库无 .ps1/.sh/.py；测试不读 `tests/fixtures`（grep 无 `read_file`/`@fs`）；仅人工哈希比对 |
| W2 T-W2-4 | 五门禁、快照零 diff | 通过 | 同上 |
| W3 目标 | `lookup_with` 接入 CLI + qualifier 扩展 | 部分完成 | 扩展完成；CLI 仅接入名字级回退 |
| W3 T-W3-1 | ext 对旧子集逐字段一致 | 通过（29 组） | `arsc_match_test.mbt` L516-532 |
| W3 T-W3-2 | v21/b+en+US 等新 token；旧函数仍拒绝 | 通过 | 同文件 L536+ |
| W3 T-W3-3 | `--config zh` 命中 zh 配置值 | **未达标（运行时证实）** | `util.mbt` `resolve_attr` 调 `resolve_attr_value`→`ResTable::lookup`（默认优先）；`lookup_with` 只在名字级回退。实跑 fx-multidex：加 `--config zh` 仍输出 `Fx Multidex` 而非 `Fx 多维` |
| W3 T-W3-4 | 无 `--config` 输出逐字节不变 | **未自动化** | 仅未知选项→退出码 2；无基线逐字节比对 |
| W3 T-W3-5 | `--config` 缺 `--resolve` → 2 | 通过 | `cli_e2e_test.mbt` |
| W3 T-W3-6 | 快照纯加法 + 五门禁 | 通过 | mbti diff 空 |
| W4 | `resolve_attr_value_with_theme`（FromTheme + 降级不抛错） | 完成 | `arsc.mbt` L560-640；3 个测试（主题链/非引用一致/降级） |
| W5 | `DynamicRefView`/`library_by_id`/`dynamic_ref_view` | 完成 | 源码符号存在；2 个测试；API D1 |
| W6 | `ResTableSet`/`resolve_attr_value_multi`/`package_by_id` | 功能完成；文档算法描述错误 | 实际按 `set.tables` 顺序 `lookup` 首个命中，**未用 package_by_id**；3 个测试 |
| W7 | overlay/idmap | 已裁决不立项（降级保留） | 无相关实现即符合裁决 |
| W8 M8-1 | 字符串池/空文档/资源映射往返 | 完成 | `encode.mbt`；5 个 axml_test 用例 |
| W8 M8-2 | 元素/属性/命名空间元数据往返 | 完成（namespace 声明 chunk 不重建） | `encode.mbt`；5 个 axml_test 用例 |
| W8 M8-3 | 真实 fixture 语义往返 + CLI 规范化一致 | 完成 | `encode_fixtures_test.mbt` 5 例 |
| W9 W9-1~4 | `encode_arsc` dense 往返、bag/library、错误路径 | 完成（解析所得表） | `arsc_encode.mbt`；`arsc_encode_test.mbt` 6 例 |
| W9 声明 | `ResConfig.raw` 空/短零填充 | **不实** | `arsc_encode.mbt` L128 `size > raw.length()` → `BadTable`；零填充分支不可达 |
| W10 | XML 文本→AXML | 已裁决不立项 | 无实现符合裁决 |
| L0 | 错误簿记 20/20 | 完成 | 同 W2 |
| L1 | 位翻转/变异/全前缀扫描 | **未完成** | 无对应用例；测试系统设计自标 ◇ |
| L2 | 双通道一致 + 簿记 | 部分完成 | T-W2-3 缺 |
| L3 | aapt2 差分 oracle | **未完成**（可选） | 无脚本；未运行外部 oracle |
| L4 | CLI 退出码矩阵 + 记录行冻结 | 完成 17 例；其中 T-W3-3 验证不足 | `cmd/main/cli_e2e_test.mbt` 17 个 test |
| L5 | 快照纯加法 + 双目标等价 + 变异自检 | 部分完成 | mbti 零 diff；双目标/变异未建 |
| R | 样本仓库外 runner | **未建**（可选） | 无脚本 |
| P1/P2/P5/P8/P9/P11 | 已承载 | 通过 | 相应用例存在 |
| P3/P4/P6/P7/P10 | 待建/部分 | 未完成/部分 | 设计文档自标；P7=T-W2-3 |
| README 状态 | 152/152、3 skip、L4 17 例 | 属实 | `moon test` 实测 |
| README 能力 | `--config` 设备配置匹配 | 夸大 | 已订正为“名字级回退” |
| CHANGELOG W3/W6/W9 | 完成声明 | 部分夸大/描述错误 | 已在原条目订正并追加核对附注 |
| API D1–D13 | 降级现状 | 与实现一致 | 源码核对 |
| API 缺 D14 | 代码注释引用 D14 但文档无此条 | 已补 | `arsc_encode.mbt` L8 引用；现已补 D14/D15 |
