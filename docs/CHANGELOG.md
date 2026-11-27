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
- CLI 新增 `--config <qualifiers>` 选项（仅与 `--resolve` 同用，缺 `--resolve` 时退出码 2）；**早期实现仅把 `dev_config` 用于名字级回退 `resolve_res_ref`（`lookup_with`），`--resolve` 取值主路径仍走 `lookup`（默认配置优先）**，未按设备配置选值。该早期未实现状态已由下方「P0-1 W3」交付的 `resolve_attr_value_with_config` 与 CLI 接线取代（见 `docs/API.md` D15）。
- 快照 diff：纯加法
- 测试增量：+2 执行用例（T-W3-1 ext 对旧子集 29 组 token 与旧函数逐字段一致；T-W3-2 新 token 解析 + 旧函数拒绝 5 组扩展 token）
- CLI 实测：T-W3-5（缺 `--resolve` → stderr 报错、退出码 2）已测；**当时 T-W3-3 未达标**（L4 用例仅断言退出码 0 与 label 出现，夹具单配置，未验证 zh 配置值）；**当时 T-W3-4 未自动化**（仅覆盖未知选项 → 退出码 2，无逐字节基线比对）。两项均已由下方「P0-1 W3」「P0-4 T-W3-4」后续交付取代，不再代表当前状态。

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
- 测试增量：当时 +17 执行用例（`cmd/cli/cli_e2e_test.mbt`；夹具全程序化构造，无外部依赖）；当前 L4 为 18 例，后续 W3 配置选值用例见「P0-1 W3」：
  - 退出码 0：tree / pool / sem 记录行逐字节冻结、`--json` 单行输出
  - 退出码 1：AXML 解析失败、APK 条目缺失、截断 ZIP、非法 `--config` 限定符
  - 退出码 2：用法错误矩阵 9 例（缺/未知子命令、未知选项、缺输入、非法 view、`--arsc`/`--config` 缺 `--resolve`、`--entry` 对非 ZIP、`--resolve` 无表）+ 无输入字节时 2 例；`dump --help` / 顶层 `--help` -> 退出码 0（1 例，契约冻结）
  - 场景：APK 直读（手工构造 Store 型 ZIP）与裸 AXML dump 输出一致、`--entry` 指定条目、`--resolve --arsc` 引用解析为 `MyApp`、`--config` 选项/限定符解析/名字级回退接线（**当时未验证按配置选值，已由「P0-1 W3」补证**）、未知选项冻结
- 复验：`moon test` 152/152 执行通过 + 3 `#skip`（2026-11-19）；真实 CLI 回归（base/fx-multidex 的 tree/sem/json、`--resolve` 解析 `Fx Multidex`、用法错 2 / IO 错 1）逐项一致

## P0 · 文档一致性同步（2026-11-19）

- README 状态行 103/103 → 129/129；能力清单补 `encode` / `--config` / 主题求值 / 动态引用视图 / 多表联合；非目标补 W9/W10/idmap
- README API 索引补齐 mbti 缺失声明（`resolve_attr_value_multi`、`resolve_attr_value_with_theme`、`DynamicRefView`、`from_qualifiers_ext`、`dynamic_ref_view`、`library_by_id`、`ResTableSet`、两个错误枚举及 `to_repr`）
- 开发计划：DoD 逐项勾选、裁决记录改为闭环、风险表补 W9
- `docs/API.md`：新增 D11–D13；错误模型表按源码签名修正（`BadChunkType`/`InvalidStringIndex`/`InvalidNodeIndex`/`UnsupportedEncoding`/`VendorVariant`/`BadHeader`/`BadIndex`）
- 新增 pub 声明：无；快照 diff：零变更；测试：129/129 不变

## 文档-代码对抗性核对订正（2026-11-19）

本次核对以源码/测试实跑为证据，订正了以下夸大或过时表述（不改变任何代码逻辑）：

- W3：早期 `--config` 未接入 `--resolve` 取值主路径，仅名字级回退用 `lookup_with`；当时 T-W3-3 未达标、T-W3-4 未自动化。**该状态已由下方 P0-1/P0-4 后续交付取代**（当前 API/CLI 语义见 `docs/API.md` D15）
- W2：T-W2-3 双通道一致性脚本未落地（仓库无脚本，`tests/ASSETS.md` §2 已改）
- W6：多表解析实际按 `tables` 顺序首个命中，未使用 `package_by_id`（上文 W6 条目）
- W9：`ResConfig.raw` 空/短零填充表述不实，实际 `size > raw.length()` 报 `BadTable`（`docs/API.md` D14）
- 计数：`moon test` 实测 152/152 + 3 skip，155 个 test 声明；测试系统设计原 135/135、138 声明与「cmd/main 无测试」已订正
- 开发计划 DoD 不再声称「T-W*-* 验收全绿」；§2 缺失能力清单移除已交付的 vNN 项，补入 T-W2-3 与 `--config` 选值缺口
- 注释/帮助文本：`tests/ASSETS.md` 记录行格式实为 §3（原多处误写 §4/§7）；`arsc.mbt` fraction 注释「×100」订正为「不乘 100」；`ci.yml` 不再把不存在的 `pkg.generated.mbti.r1` 当作实存文件描述

## 缺口修复轮：W2/W3/W9 缺口闭环 + L1/性质/L5 补齐（2026-11-19）

以「文档-代码对抗性核对报告」确认的缺口为输入，只做修复 + 测试 + 文档同步；`moon test` 170/170（+3 `#skip`，共 173 声明），wasm/native 双目标各 170/170；五门禁全绿，`pkg.generated.mbti` diff 纯加法（仅 +1 行：`resolve_attr_value_with_config`）。

### P0-1 W3：`--config` 接入引用取值主路径（D15 更新）

- 新增公开函数 `resolve_attr_value_with_config(AxmlDoc, ResTable, XmlAttribute, ResConfig) -> ResolvedAttr`（`arsc_match.mbt`，纯加法）：引用路径走 `lookup_with`（qualifier 最优匹配）命中优先，未命中回退 `lookup`（默认配置优先），再未命中 `Unresolved`；配套内部 `lookup_best`/`resolve_id_with_config_depth`/`try_resolve_raw_ref_with_config`
- CLI：`--config` 提供时 `resolve_attr` 改走新函数；未提供时仍走旧 `resolve_attr_value`（既有输出逐字节不变，golden 基线冻结）；帮助文本同步
- 事实订正：真实 fx-multidex manifest 的 `android:label` 为**内嵌字面量**（字符串池无 `@string/app_name`），任何实现都无法在该样本上观测配置选值——原审计「运行时反证」前提不成立；新增受控自产 fx-config fixture 对（`tools/genconfig` 生成，ASSETS §1 登记）承载 `moon run` 端到端实跑
- 测试：`arsc_match_test.mbt` +2（zh 命中/en 回退/空 config 等同默认/旧函数冻结/文本引用/lookup 层策略）；`cli_e2e_test.mbt` +1（双配置表 4 断言）
- 实跑：`dump fx-config.AndroidManifest.xml --resolve --arsc fx-config.resources.arsc --config zh` → `AT|1|application|…|label|Fx 多维`；无 `--config` → `Fx Multidex`

### P0-2 W2：T-W2-3 双通道一致性门禁落地

- 新增 `tools/check_fixtures`（executable 包，零第三方依赖）：①ASSETS §1 文件存在 + 实测 SHA-256（内置最小 SHA-256，FIPS 180-4/CAVP 向量 + 1000×'a' 多块向量（PowerShell Get-FileHash 独立实测）启动自测）；②`fixtures_test.mbt` FIXTURE-BEGIN/END 内嵌块逐字节比对（首个差异打印文件/偏移/期望/实际）；③内嵌块反向登记完备；退出码 0/1，文件缺失不静默跳过，无内嵌块样本显式「仅哈希」
- 新增 `tools/genconfig`（溯源生成器）：程序化构造 fx-config fixture 对（manifest `android:label` 为 Reference 0x7f010000 + arsc string/app_name 双配置）
- fixture 集 10 → 12 文件（ASSETS §1 更新）；红→绿实证：篡改单字节 → FAIL（SHA-256 不一致）exit 1 → 还原 → exit 0
- CI：five-gates job 增补 Gate 3b `moon run tools/check_fixtures`；Gate 5 快照 diff 纳入 tools/*/pkg.generated.mbti

### P0-3 W9：`encode_arsc` 空/短 `ResConfig.raw` 序列化回编（D14 更新）

- `arsc_encode.mbt`：新增 `encode_config_bytes`——`size < 4` → `BadTable`；`raw.length() >= size` → 取前 `size` 字节原样回写（解析产物语义不变）；空/短 `raw` → 按已解码 qualifier 字段序列化 `size` 字节镜像（size 字段自描述 + `enc_pack_locale` 2 位 ASCII/3 位 15 位压缩 + 其余零填充）；type chunk 内 config 镜像补齐 4 字节对齐（AOSP `entriesStart` 对齐要求，实测 size=63 未对齐会被解析侧拒绝）
- 测试：`arsc_encode_test.mbt` +2（W9-5 构造型配置往返字段等价：`from_qualifiers("")`/`"zh-rCN"`/富限定符 BCP47 三字母 + size=4/63/64/65 边界 + `size<4` 拒绝 + over-long raw 截断）

### P0-4 T-W3-4：CLI 字节冻结基线

- 新增 `tests/cli-golden/` 22 个场景基线文件 + `cmd/cli/cli_golden_test.mbt`：views×6 / APK×3 / resolve+config×4 / errors+help×9，逐字节比较（退出码 + stdout/stderr 全部行）；基线缺失时落盘并判失败（已提交基线在 CI 恒存在，恒 fail-closed）
- 红→绿实证：临时改帮助文本 1 字符 → 2 基线 MISMATCH；还原后 19/19 绿

### P1-1 L1：截断/位翻转/变异（`fuzz_test.mbt` +4）

- 截断扫描：9 个入库 fixture（素数步长抽样 + chunk 头/池偏移表/entry 偏移表/entriesStart 边界必采）9188 例 + W8 `encode`/W9 `encode_arsc` 产物 343 例；断言仅声明错误或成功、无 panic
- 位翻转：564 例（chunk type/headerSize/size、stringCount、attributeCount、type/typeSpec entryCount、entry offset、`Res_value.size`）；`Res_value.size=8` 按 AOSP「size≥8 接受、多余忽略」仅 bit3 可观察，良性位文档化排除
- 变异：1050 固定种子（xorshift32）替换/插入/删除变异体，7 fixture，不 panic + 错误属声明集合

### P1-2 性质测试（`property_test.mbt` +4）

- P3 解析确定性（4 fixture 两次解析指纹相等）；P4 配置退化律（默认存在 ≡ / 无默认文档化分叉 None vs chunk-first）；P6 渲染一致律（`resolve_id` ≡ `format_value`，`lookup` 同条目口径）；P10 防火墙律（W3 旧 ≡ 新+全零设备、W4 非 ?attr 一致、W6 单表集合 ≡ 单表、W9 往返指纹）

### P1-3 L5：双目标等价 + 变异自检

- 本地 `moon test --target native` 与 wasm 同套用例各 170/170；CI 新增 `l5-native` job
- 变异自检红→绿：①字符串计数校验 off-by-one（3+ 红）②chunk size 步进错误（3 红）③bag 压平顺序反转（2 红）；逐一还原后 170/170 绿

### 文档同步

- 开发计划：状态行、W2/W3/W9 条目、§2 能力表与缺失清单、§8 DoD 全勾选
- 测试系统设计：头部/§2 计数 170/170+3skip（173 声明）、§3 F-B/F-C、§4 P3/P4/P6/P7/P10 + 截断/变异、§6.1 F5/F6/F7/S1/S2/C2/C5/C6、§7 设备配置与冻结行、§8 L5、§9 命令、§10 清单
- `docs/API.md` D14（零填充真实语义）/D15（取值主路径）改写；README 状态行/能力/§5/§6 同步；`tests/ASSETS.md` §1（12 文件）/§2（门禁落地）
- 新增 pub 声明：`resolve_attr_value_with_config`（快照纯加法 +1 行）；零新第三方依赖；零新错误变体

## 过程资料归档（2026-11-19）

- 本轮「文档-代码对抗性核对」与「缺口修复轮」的过程工作目录（审计报告、任务清单、验证日志、下一轮提示词、落地报告）已清理，不再保留重复副本
- 有效结论去向：核对订正与修复证据见本文件上方两个条目；残留风险（3 位 locale 未与 aapt2 差分、CI 云上首跑未验证、fx-config 为受控自产、P2 未立项）见开发计划 §9 风险登记与 README §6；降级语义见 `docs/API.md` D14/D15；fixture 登记见 `tests/ASSETS.md` §1/§2
