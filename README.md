# axml · 二进制 XML 与资源表解析

> 独立发布单元 ｜ L1 逆向输入 ｜ `preferred_target = wasm` ｜ Apache-2.0
> 状态：`moon test` **170/170** 通过（2026-11-19 本机实测，另有 3 个 `#skip` 用例不计入，共 173 声明；含 L4 CLI 场景 E2E 18 例 + 字节冻结基线 22 场景，`cmd/cli` 原生承载（`cmd/main` 仅进程入口）；wasm/native 双目标各 170/170）；本文件是本仓库**唯一**说明文档。
> 公开 API 以 `pkg.generated.mbti` 为准（由 `moon info` 生成，禁手工编辑）；加法性变更须登记簿记 + 快照审阅 + 快照门禁。

## 1. 定位与边界

把 Android 二进制 XML 与 `resources.arsc` 解析成可读的节点树、属性、字符串池与资源引用值。

**能力**

- AXML chunk（字符串池 / resource map / namespace / start-end element）解析与 tree / sem / pool 三种视图
- AXML 格式级回编 `encode`（字符串池 / resource map / 元素 / 属性 / CDATA，语义往返）
- `resources.arsc` 全链：package / typeSpec / type entry / 字符串池，bag 压平，`?attr` 主题求值
- `resources.arsc` 值级回编 `encode_arsc`（dense 布局语义往返，sparse/offset16/compact 显式拒绝）
- qualifier 匹配与 aapt2 式最优匹配、引用链深度上限 + 自引用检查（bag/attr 链带环检测）
- `--config` 设备限定符解析（`from_qualifiers_ext`）+ 引用取值最优匹配（`resolve_attr_value_with_config`：`lookup_with` 命中优先、未命中回退默认配置）+ 名字级回退 `lookup_with`；未提供 `--config` 时取值主路径保持默认配置优先（语义见 `docs/API.md` D15）
- 主题感知联合解析（`resolve_attr_value_with_theme` / `eval_theme_attr`）
- 动态引用映射视图 `dynamic_ref_view`（`origin_id` / `runtime_package_id` / `library_name`）
- 多表联合解析 `ResTableSet` + `resolve_attr_value_multi`
- `--resolve` 把资源引用解析为可读值（名字级 `@type/name` → 最终值 → `@0x%08x` 降级）
- `axml-cli dump`（`--view tree|sem|pool` / `--entry` / `--resolve` / `--arsc` / `--json`）

**非目标**

- 不做 aapt2 的构建期资源编译与打包（含 XML 文本→AXML 编译）
- 不解析 overlay/idmap（idmap 属 AXML/ARSC 之外的第三种二进制格式）
- 不解析框架资源（`0x01…` 引用在无框架资源表时保持原样）
- 不导出 trait；不 import 任何其他工作区模块

## 2. 关键设计决策（本仓库自足记录）

- `resources.arsc` 完整展开归 `axml`（ADR-0003 2026-11-07 补记）；`apk` 只产原始字节。
- 零第三方依赖；`classfile@0.2.0` 仅作设计参照、不纳入构建。
- 不使用 `declare` 声明具体 struct/enum（E4193），类型面用真实定义。
- R4 已把 qualifier 最优匹配 / bag 压平 / `?attr` 求值从「降级项」转为已实现，旧文档中的降级清单已作废。

## 3. 公开 API 索引（自动抽取 `pkg.generated.mbti` 的 `pub` 声明行；完整字段见快照）

```text
pub fn encode(AxmlDoc) -> Bytes raise AxmlError
pub fn encode_arsc(ResTable) -> Bytes raise ArscError
pub fn parse(Bytes) -> AxmlDoc raise AxmlError
pub fn parse_arsc(Bytes) -> ResTable raise ArscError
pub fn resolve_attr_value(AxmlDoc, ResTable, XmlAttribute) -> ResolvedAttr
pub fn resolve_attr_value_multi(AxmlDoc, ResTableSet, XmlAttribute) -> ResolvedAttr
pub fn resolve_attr_value_with_theme(AxmlDoc, ResTable, XmlAttribute, UInt32, ResConfig) -> ResolvedAttr
pub(all) struct AxmlDoc {
pub fn AxmlDoc::elements(Self) -> Array[XmlNode] raise AxmlError
pub fn AxmlDoc::node_at(Self, Int32) -> XmlNode raise AxmlError
pub fn AxmlDoc::string_at(Self, Int32) -> String raise AxmlError
pub(all) enum ChunkType {
pub(all) struct DynamicRefView {
pub(all) struct FlattenedBag {
pub(all) struct ResBag {
pub(all) struct ResConfig {
pub fn ResConfig::from_qualifiers(String) -> Self raise ArscError
pub fn ResConfig::from_qualifiers_ext(String) -> Self raise ArscError
pub fn ResConfig::is_better_than(Self, Self, Self) -> Bool
pub fn ResConfig::is_default(Self) -> Bool
pub fn ResConfig::matches(Self, Self) -> Bool
pub(all) enum ResDataType {
pub(all) struct ResEntry {
pub(all) enum ResEntryValue {
pub(all) struct ResLibrary {
pub(all) struct ResLookup {
pub(all) struct ResMap {
pub(all) struct ResPackage {
pub(all) struct ResTable {
pub fn ResTable::dynamic_ref_view(Self, UInt32) -> DynamicRefView
pub fn ResTable::eval_theme_attr(Self, UInt32, UInt32, ResConfig) -> ResValue raise ArscError
pub fn ResTable::find_id(Self, String, String) -> UInt32?
pub fn ResTable::flatten_bag(Self, UInt32, ResConfig) -> FlattenedBag raise ArscError
pub fn ResTable::format_value(Self, ResValue) -> String
pub fn ResTable::library_by_id(Self, Int32) -> ResLibrary?
pub fn ResTable::lookup(Self, UInt32) -> ResLookup?
pub fn ResTable::lookup_all(Self, UInt32) -> Array[ResLookup]
pub fn ResTable::lookup_with(Self, UInt32, ResConfig) -> ResLookup?
pub fn ResTable::package_by_id(Self, Int32) -> ResPackage?
pub fn ResTable::resolve_id(Self, UInt32) -> String
pub(all) struct ResTableSet {
pub(all) struct ResTypeConfig {
pub(all) struct ResTypeSpec {
pub(all) struct ResValue {
pub(all) enum ResolveOrigin {
pub(all) struct ResolvedAttr {
pub(all) enum StringEncoding {
pub(all) struct StringPool {
pub(all) enum ValueType {
pub(all) struct XmlAttribute {
pub(all) struct XmlNode {
pub fn XmlNode::attrs(Self) -> Array[XmlAttribute]
pub type NodeIndex = Int32
pub type StringIndex = Int32
pub suberror ArscError {
pub fn ArscError::to_repr(Self) -> @debug.Repr
pub suberror AxmlError {
pub fn AxmlError::to_repr(Self) -> @debug.Repr
```

## 4. 依赖、平台与许可

零第三方依赖；`preferred_target = wasm`；Apache-2.0。

## 5. 命令行与验证

- `moon run cmd/main --target native -- dump <apk|axml> [--view ...] [--resolve] [--json]`；输出行 `EL|` `AT|` `SEM|` `POOL|` `STR|`（完整格式见 `tests/ASSETS.md` §3）。
- CLI 契约自动化：L4 场景 E2E 由 `cmd/cli/cli_e2e_test.mbt` 在 `moon test` 原生承载（退出码 0/1/2 矩阵 + 记录行逐字节冻结 + APK 直读 + 用法错误），经公开入口 `cli_run` 断言；T-W3-4 命令矩阵字节冻结基线为 `tests/cli-golden/`（22 个场景基线文件，`cmd/cli/cli_golden_test.mbt` 逐字节比较）。
- fixture 一致性门禁（T-W2-3）：`moon run tools/check_fixtures`——`tests/ASSETS.md` §1 哈希 + `fixtures_test.mbt` 内嵌块逐字节 + 反向登记完备（fail-closed；CI Gate 3b 同步执行）。
- 复验：`moon clean` → `moon check --deny-warn` → `moon build` → `moon test` → `moon test --target native` → `moon run tools/check_fixtures` → `moon fmt --check` → `moon info` 后检查 `pkg.generated.mbti` 无意外 diff。
- 本仓库为独立 Git 仓库，文档与 CI 均自包含，不依赖工作区其他目录。

## 6. 风险与未决

- 与 `apk` 侧 `resources.arsc` 实现并存，未去重。
- 框架资源引用在无 framework-res 资源表时只能保持原始值；`DocumentView` 已从公开面删除。
- 写侧闭环已覆盖 AXML（`encode`）与 ARSC（`encode_arsc`）；XML 文本→AXML 编译为明确非目标。
- 未自动化项：L3 aapt2 差分与真机 R runner（外部 oracle 依赖，未立项）。已于 2026-11-19 落地：wasm/native 双目标门禁（CI `l5-native` job，本地 wasm/native 各 170/170）、L1 截断/位翻转/变异（`fuzz_test.mbt`）、fixture 文件↔内嵌常量一致性门禁（T-W2-3，`tools/check_fixtures`）、CLI 字节冻结基线（T-W3-4，`tests/cli-golden/`）。
- 残留未验证：`enc_pack_locale` 的 3 位 locale 压缩编码未与 aapt2 真实产物差分（现有真实 fixture 均为 2 位 ASCII locale）；CI 云上首跑（Gate 3b、`l5-native`）待 push 后确认。完整风险登记见开发计划 §9。

