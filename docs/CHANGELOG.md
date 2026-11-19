# axml CHANGELOG

> 登记开发计划各工作包合入：日期 / 工作包 / 新增 pub 声明 / 快照 diff 结论 / 测试增量

## 2026-11-19 · 基线确认（pre-M0）

- 五门禁全绿：`moon check --deny-warn` / `moon build` / `moon test` 103+3skip / `moon fmt --check` / `moon info` + 快照零 diff
- 本次运行修复了 9 处 deprecated API 调用（`StringBuilder.size_hint→capacity`、`Bytes::new→Bytes::make`、`inflate_exact max_output→max_output_bytes`），属工具链适配，无 API 变更、无语义变更
- 快照 diff：零变更
- 测试：103/103 执行通过 + 3 `#skip`（checksum N/A、framework-res 黄金未登记、真机不执行）

## W1 · 文档与资产登记重建（2026-11-19）

- 新增文档：`docs/API.md`（降级项 + 错误模型）、`docs/CHANGELOG.md`（本文件）、`tests/ASSETS.md`（fixture 登记）
- 注释漂移修正：`arsc.mbt` `resolve_id` `(cycle)` → `(too deep)` 实际语义；全部 `docs/DESIGN.md` / `docs/API.md` 引用统一指向新建的 `docs/API.md`
- README.md §5 记录行清单修正：删除 DEX 侧误植项（`HDR|CLZ|ANN|SVC|XREF|MREF|`），仅保留实际 CLI 产出的 `EL|` `AT|` `SEM|` `POOL|` `STR|`
- README.md §1 修正「引用链深度限制与环检测」→ 实际语义（bag/attr 链带环检测、引用链仅深度上限 + 自引用检查）
- 新增 pub 声明：无
- 快照 diff：零变更
- 测试增量：无

## W2 · 错误簿记补齐（2026-11-19）

- 新增 `arsc_match_test.mbt` BagMissingParent 显式用例（20/20 错误变体簿记补齐）
- 新增 pub 声明：无
- 快照 diff：零变更
- 测试增量：+1 执行用例
