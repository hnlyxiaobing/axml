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
- CLI 新增 `--config <qualifiers>` 选项（仅与 `--resolve` 同用，缺 `--resolve` 时退出码 2）；**实际实现仅把 `dev_config` 用于名字级回退 `resolve_res_ref`（`lookup_with`），`--resolve` 取值主路径仍走 `lookup`（默认配置优先）**，未按设备配置选值（2026-11-19 对抗性复核订正；见 `docs/API.md` D15）
- 快照 diff：纯加法
- 测试增量：+2 执行用例（T-W3-1 ext 对旧子集 29 组 token 与旧函数逐字段一致；T-W3-2 新 token 解析 + 旧函数拒绝 5 组扩展 token）
- CLI 实测：T-W3-5（缺 `--resolve` → stderr 报错、退出码 2）已测；**T-W3-3 未达标**（L4 用例仅断言退出码 0 与 label 出现，夹具单配置，未验证 zh 配置值）；**T-W3-4 未自动化**（仅覆盖未知选项 → 退出码 2，无逐字节基线比对）

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
- 三路解析：① raw_data 内联 id（**按 `set.tables` 顺序逐表 `lookup`，首个命中者胜出；未使用 `package_by_id` 按包字节选表**）② raw_value 文本引用（`@type/name` / `@0x…`，按 tables 顺序首个命中）③ 纯字面量；全部未命中 → `Unresolved`，不抛错
- 单表 API 语义不变；不自动加载/内置任何框架资源
- 快照 diff：纯加法（+1 struct、+1 pub fn）
- 测试增量：+3 执行用例（T-W6-1 框架表 0x01… 解析 / T-W6-2 空表集与未命中降级 / T-W6-3 单表与旧函数逐字段一致）

## M3 裁决（2026-11-19）

- W8 AXML 格式级回编：方案 B 通过，立项；先以 M8-1 验证往返律。
- W7 overlay/idmap：不立项，维持既有跳过行为与降级登记，本包关闭。
- `sem --resolve-label`：不新增选项，按既有输出保持并文档化限制。

## W8 · AXML 格式级回编 M8-1（2026-11-19）

- 新增 pub 声明：`encode(AxmlDoc) -> Bytes raise AxmlError`（`encode.mbt`）
- 范围（M8-1）：重建 RES_XML_TYPE 文件头 + UTF-8/UTF-16 字符串池（保留原编码与字符串顺序，不设 SORTED）+ RES_XML_RESOURCE_MAP；空文档（无元素/无根）往返成立
- 往返律：`parse(encode(doc))` 在 UTF-8、UTF-16（含 BMP 外代理对、空串）与 resource map 受控样本上语义等价；`encode(parse(encode(parse(src))))` 与首次产物逐字节一致
- 限制（显式拒绝，不静默丢信息）：节点表/根索引非空或样式块非空 → `VendorVariant`，留待 M8-2；字符串超过 UTF-8 池前缀上限 → `BadStringPool`
- 不做 arsc 写入、不做 XML 文本→AXML 编译；不保证与 aapt2 字节级一致
- 快照 diff：纯加法（+1 pub fn）
- 测试增量：+5 执行用例（T-W8-1：UTF-8 空文档往返 / UTF-16 空文档往返 / resource map 往返 / 二次往返幂等 / 节点显式拒绝）

## W8 · AXML 格式级回编 M8-2（2026-11-19）

- 新增 pub 声明：无（`encode` 语义扩展，签名不变）
- 范围（M8-2）：元素/属性/CDATA 回编；START_ELEMENT 使用标准 attributeStart/attributeSize=20 布局，END_ELEMENT/CDATA 按解析侧固定布局重建
- 保真字段：元素 line/ns/name、属性 ns/name/rawValue/`ValueType`（含 `Unknown`）/res0/raw_data/line、树结构（children/parent/roots）、CDATA 文本与行号
- 不重建：namespace 声明 chunk（`AxmlDoc` 不保留前缀与声明位置，解析侧跳过，往返不受影响）
- 显式拒绝（不静默丢信息）：样式块 → `VendorVariant`；节点引用字符串不在池中 → `BadStringPool`；越界/重复访问/未被引用的节点 → `InvalidNodeIndex`
- 快照 diff：零变更（签名未变）
- 测试增量：净 +5 执行用例（新增 6：UTF-8 golden 往返 / UTF-16 golden 往返 / 多根 + 顶层 CDATA / 属性元数据含 `Unknown` 类型 / 元素文档二次编码稳定 / 缺失池字符串拒绝；移除 M8-1 的「节点显式拒绝」1 项）

## W8 · AXML 格式级回编 M8-3（2026-11-19）

- 新增 pub 声明：无（仅新增验收测试与文档）
- 真实样本：base / tvshell-debug / fx-multidex / framework-res 四个入库 AndroidManifest AXML
- 往返律：`parse(encode(doc))` 与 `doc` 逐字段等价（字符串池、resource map、根顺序、节点/属性全字段），且 CLI 规范化 tree/pool 逐行一致
- 产物稳定性：encode 结果再次 parse 成功、二次 encode 逐字节相同（不 panic）
- 快照 diff：零变更
- 测试增量：+5 执行用例（T-W8-2 ×4 真实样本；T-W8-3 ×1 产物再 parse 与稳定），总 129/129

## M4 · 边界裁决（2026-11-19）

- `resources.arsc` 回写：方案 B 通过，立项 W9（值级回编 `encode_arsc`，里程碑 W9-1..W9-4，待启动；已于同日 W9 条目交付）；不做资源编译/打包
- W7 overlay/idmap：复核维持不立项（idmap 属 AXML/ARSC 之外的第三种二进制格式）
- XML 文本→AXML 编译：不立项，维持非目标（构建期职责归 aapt2）
- 落地文档：开发计划 §3/§4/§5/§6/§8/§9、README §1/§6、`docs/API.md` D11–D13
- 新增 pub 声明：无；快照 diff：零变更；测试：129/129 不变

## W9 · resources.arsc 值级回编（2026-11-19）

- 新增 pub 声明：`encode_arsc(ResTable) -> Bytes raise ArscError`（`arsc_encode.mbt`）
- 范围：全局池 + package（名称/类型池/键名池/typeIdOffset）+ typeSpec（id + entry_count + spec_flags）+ type（dense 布局，config + entries）+ 简单值（全部 15 种 ResDataType）+ bag（parent + maps）+ library chunk
- 恢复性 dense：写入槽为 u32 偏移（flags=0），稀疏/offset16/compact 显式拒绝（`BadTable`，复用既有变体，不新增错误）
- `ResConfig.raw` 按 `size` 切片原样回写；**`size > raw.length()` 直接报 `BadTable`（`from_qualifiers` 构造的 `size=64`、`raw` 空配置不可回编），不存在「空/短零填充」可达分支**（2026-11-19 对抗性复核订正；`arsc_encode.mbt` L128，见 `docs/API.md` D14）
- 包名/库名固定 128×u16 NUL 填充，>128 码元拒绝（`BadTable`）
- 往返律：`parse_arsc(encode_arsc(t))` 与规范化 `t` 语义等价（不要求与 aapt2 字节一致）；空表逐字节一致
- 快照 diff：纯加法（+1 pub fn）
- 测试增量：+6 执行用例（W9-1 空表逐字节往返 / 非空全局池往返；W9-2 dense 简单值往返（含双配置 + 颜色/布尔）; W9-3 bag/library/config 变体往返 + sparse/offset16/compact 显式拒绝；W9-4 fx-multidex 真实 ARSC 语义往返）

## L4 · CLI 场景 E2E（原生 `moon test` 承载）（2026-11-19）

- 补齐 B22「`cmd/main` 无自动化测试」缺口：L4 按测试系统设计 §9 选择「`moon test` 原生承载」，不引入脚本层依赖
- **行为保持型重构**（CLI 对外契约零漂移）：
  - 新增 `cmd/main/sink.mbt`：`Sink` 输出汇（真实模式转发 stdout/stderr；捕获模式缓冲行），`out_line`/`err_line` 统一出口
  - `main.mbt` 拆为「选项解析 `parse_dump` + 输入无关核心 `cmd_dump_core`（raise）+ 真实文件入口 `cmd_dump`（async）」，全部输出改经 `Sink`
  - `zipmin.mbt` 错误输出改经 `Sink`（`zip_min_entries`/`zip_min_extract`/`zip_min_get`/`zip_entry`/`zip_entry_quiet` 均增 `sink` 参数）
- 新增 pub 声明（纯加法，`.mbti` 仅新增）：
  - `cli_run(Array[String], Bytes, Bytes?) -> CliResult`：内存字节输入 + 捕获 stdout/stderr + 退出码的 E2E 入口
  - `pub(all) struct CliResult { code : Int32, out : Array[String], err : Array[String] }`
  - 私有类型 `DumpOpts` / `Sink` 以 opaque `type` 形式出现在 `.mbti`（与既有 `RefCtx`/`SemInfo`/`ZEntry` 同形，非新增可见 API 面）
- 子命令分派在 `cli_run` 中与真实入口 `run` 逐项一致（缺子命令/`--help`/未知子命令/`dump`），保证退出码矩阵端到端可断言
- 快照 diff：纯加法（+1 pub fn、+1 pub(all) struct、+2 opaque type）
- 测试增量：+17 执行用例（`cmd/main/cli_e2e_test.mbt`；夹具全程序化构造，无外部依赖）：
  - 退出码 0：tree / pool / sem 记录行逐字节冻结、`--json` 单行输出
  - 退出码 1：AXML 解析失败、APK 条目缺失、截断 ZIP、非法 `--config` 限定符
  - 退出码 2：用法错误矩阵 9 例（缺/未知子命令、未知选项、缺输入、非法 view、`--arsc`/`--config` 缺 `--resolve`、`--entry` 对非 ZIP、`--resolve` 无表）+ 无输入字节时 2 例；`dump --help` / 顶层 `--help` -> 退出码 0（1 例，契约冻结）
  - 场景：APK 直读（手工构造 Store 型 ZIP）与裸 AXML dump 输出一致、`--entry` 指定条目、`--resolve --arsc` 引用解析为 `MyApp`、`--config` 选项/限定符解析/名字级回退接线（**未验证按配置选值**）、未知选项冻结
- 复验：`moon test` 152/152 执行通过 + 3 `#skip`（2026-11-19）；真实 CLI 回归（base/fx-multidex 的 tree/sem/json、`--resolve` 解析 `Fx Multidex`、用法错 2 / IO 错 1）逐项一致

## P0 · 文档一致性同步（2026-11-19）

- README 状态行 103/103 → 129/129；能力清单补 `encode` / `--config` / 主题求值 / 动态引用视图 / 多表联合；非目标补 W9/W10/idmap
- README API 索引补齐 mbti 缺失声明（`resolve_attr_value_multi`、`resolve_attr_value_with_theme`、`DynamicRefView`、`from_qualifiers_ext`、`dynamic_ref_view`、`library_by_id`、`ResTableSet`、两个错误枚举及 `to_repr`）
- 开发计划：DoD 逐项勾选、裁决记录改为闭环、风险表补 W9
- `docs/API.md`：新增 D11–D13；错误模型表按源码签名修正（`BadChunkType`/`InvalidStringIndex`/`InvalidNodeIndex`/`UnsupportedEncoding`/`VendorVariant`/`BadHeader`/`BadIndex`）
- 新增 pub 声明：无；快照 diff：零变更；测试：129/129 不变

## 文档-代码对抗性核对订正（2026-11-19）

本次核对以源码/测试实跑为证据，订正了以下夸大或过时表述（不改变任何代码逻辑）：

- W3：`--config` 未接入 `--resolve` 取值主路径，仅名字级回退用 `lookup_with`；T-W3-3 未达标、T-W3-4 未自动化（上文 W3/L4 条目与 `docs/API.md` D15）
- W2：T-W2-3 双通道一致性脚本未落地（仓库无脚本，`tests/ASSETS.md` §2 已改）
- W6：多表解析实际按 `tables` 顺序首个命中，未使用 `package_by_id`（上文 W6 条目）
- W9：`ResConfig.raw` 空/短零填充表述不实，实际 `size > raw.length()` 报 `BadTable`（`docs/API.md` D14）
- 计数：`moon test` 实测 152/152 + 3 skip，155 个 test 声明；测试系统设计原 135/135、138 声明与「cmd/main 无测试」已订正
- 开发计划 DoD 不再声称「T-W*-* 验收全绿」；§2 缺失能力清单移除已交付的 vNN 项，补入 T-W2-3 与 `--config` 选值缺口
- 注释/帮助文本：`tests/ASSETS.md` 记录行格式实为 §3（原多处误写 §4/§7）；`arsc.mbt` fraction 注释「×100」订正为「不乘 100」；`ci.yml` 不再把不存在的 `pkg.generated.mbti.r1` 当作实存文件描述
