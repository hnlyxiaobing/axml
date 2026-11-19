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

## W3 · CLI 设备配置匹配 + qualifier 扩展（2026-11-19）

- 新增 pub 声明：`ResConfig::from_qualifiers_ext(String) -> Self raise ArscError`（旧 `from_qualifiers` 语义冻结）
- CLI 新增 `--config <qualifiers>` 选项（仅与 `--resolve` 同用，缺 `--resolve` 时退出码 2）；有 `--config` 时取值走 `lookup_with`，未命中回退 `lookup`
- 快照 diff：纯加法
- 测试增量：+2 执行用例（T-W3-1 ext 对旧子集 29 组 token 与旧函数逐字段一致；T-W3-2 新 token 解析 + 旧函数拒绝 5 组扩展 token）
- CLI 实测：T-W3-3/4（带 `--config` 与基线输出逐字节一致——fixture 无多语言变体时正确回退）；T-W3-5（缺 `--resolve` → stderr 报错、退出码 2）

## W4 · 主题感知属性解析（2026-11-19）

- 新增 pub 声明：`resolve_attr_value_with_theme(AxmlDoc, ResTable, XmlAttribute, UInt32, ResConfig) -> ResolvedAttr`
- 对 `?attr` 值沿 theme bag 链求值；求值失败（AttrMissing/AttrCycle/Bag*）降级为 `Unresolved(原因)`，保持不抛错契约
- 快照 diff：纯加法（W3–W5 补齐后唯一变更：`resolve_attr_value_with_theme` 去掉 `raise`，与计划 mbti 草案一致）
- 测试增量：+3 执行用例（T-W4-1 链求值 → FromTheme；T-W4-2 AttrMissing/AttrCycle/theme 非 bag/theme 缺失四路降级 Unresolved；T-W4-3 非 `?attr` 六类与旧函数逐字段一致）
- 实现对齐计划：`eval_theme_attr` 抛错全部捕获降级，函数不再抛错

## W5 · 动态引用映射视图（2026-11-19）

- 新增 pub 声明：`ResTable::library_by_id(Self, Int32) -> ResLibrary?`、`ResTable::dynamic_ref_view(Self, UInt32) -> DynamicRefView`、`pub(all) struct DynamicRefView`
- 只暴露 `RES_TABLE_LIBRARY_TYPE` 映射事实，不改写引用（旧 API 语义不变）
- 快照 diff：纯加法
- 测试增量：+2 执行用例（T-W5-1 library 命中/未命中两路径；T-W5-2 旧 API 对动态引用仍输出 `(dynamic)`/Unresolved，零变化）

## W6 · 多表联合解析（2026-11-19）

- 新增 pub 声明：`ResTableSet`（`tables : Array[ResTable]`）、`resolve_attr_value_multi(AxmlDoc, ResTableSet, XmlAttribute) -> ResolvedAttr`
- 三路解析：① raw_data 内联 id（按包字节选表，`package_by_id` 命中优先）② raw_value 文本引用（`@type/name` / `@0x…`，按 tables 顺序首个命中）③ 纯字面量；全部未命中 → `Unresolved`，不抛错
- 单表 API 语义不变；不自动加载/内置任何框架资源
- 快照 diff：纯加法（+1 struct、+1 pub fn）
- 测试增量：+3 执行用例（T-W6-1 框架表 0x01… 解析 / T-W6-2 空表集与未命中降级 / T-W6-3 单表与旧函数逐字段一致）
