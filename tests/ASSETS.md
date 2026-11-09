# axml 测试样本登记（tests/ASSETS.md）

> 登记 `tests/fixtures/` 全部样本的来源、生成/提取方式、SHA-256 与黄金口径，自足可读。
> 黄金期望值已内嵌于测试代码（`fixtures_test.mbt` 的 GOLDEN-BEGIN/END 字符串常量），`moon test` 即回归，不依赖任何外部脚本或外部文件。
> SHA-256 为对仓库内实际文件的实测值；来源 APK 的 SHA-256 为开发期登记值。

## 1. 已入库样本总表

| 文件 | 字节 | 来源 | SHA-256 |
|---|---|---|---|
| `tests/fixtures/base.AndroidManifest.xml` | 2552 | `base.apk`（受控自建，SHA-256 `D5824D09A5E9E3D6109D9298E72A9887566D35B9A8F89A56DE124D53AF0A94C3`）的 `AndroidManifest.xml` 条目 | `C7A39304785E6EEB0CB9EFC799613F10C21C22EE1C2B729F010015431B501091` |
| `tests/fixtures/base.resources.arsc` | 40 | 同上 `resources.arsc` 条目（空资源表） | `1FA3CB291285348EC1B33C85E7317D989467707F4791C4E5302F2D312D1E18C8` |
| `tests/fixtures/tvshell-debug.AndroidManifest.xml` | 2128 | `tvshell-debug.apk`（受控自建，SHA-256 `24FA4F0BE0731806612DAFC486AF3ECD5978BF22BB8272314FFC62A6B1492093`）的 `AndroidManifest.xml` 条目 | `23064A1732EEE67D9BE1D155A9EB08C8B0269590B3C4C6ED3C6FCD444E5C62FD` |
| `tests/fixtures/tvshell-debug.resources.arsc` | 40 | 同上 `resources.arsc` 条目（空资源表） | `1FA3CB291285348EC1B33C85E7317D989467707F4791C4E5302F2D312D1E18C8` |
| `tests/fixtures/fx-multidex.AndroidManifest.xml` | 2284 | `fx-multidex-v2v3.apk`（受控构建，SHA-256 `E2A736C749636EA6F09172ED56EED43BD37DD6EFA816AD48775E419A85B4EB2B`）的 `AndroidManifest.xml` 条目 | `B0F3496EB429813C88BCEE7D6B9B17CE69711A3B147137EE94A3E91B7AEDC271` |
| `tests/fixtures/fx-multidex.resources.arsc` | 1052 | 同上 `resources.arsc` 条目（非平凡资源表） | `AD89335AB8192AA4CD4E07B8930CF68F13FB5FC7B9EDA2179DEB80B5ACCE1FDD` |
| `tests/fixtures/framework-res.AndroidManifest.xml` | 204248 | `framework-res.apk`（AOSP 框架资源包，Apache-2.0，SHA-256 `AD041A4703EE0C3E4BFB593608AC05500039BF3BDF21452E28EE1D2FED3514DC`）的 `AndroidManifest.xml` 条目 | `12DB5C25E648911823241B2A535B44B7349E8D98F13F50AB0885C07985C8B89B` |
| `tests/fixtures/edge-arsc-truncated.bin` | 20 | 程序化派生（`fx-multidex.resources.arsc` 截断，见 §8） | `A9756C656DC26B2F9F246DF24F6EF47929D427E267AD3651E396487AD4378F2B` |
| `tests/fixtures/edge-arsc-badheadersize.bin` | 40 | 程序化派生（空表外层 headerSize 12→8，见 §8） | `AE7BD7AB0ECF03F59C8D5267E4D7DF7A858BDA2A65F58576A453E9F23960D969` |
| `tests/fixtures/edge-arsc-badtype.bin` | 1052 | 程序化派生（外层 chunk type 0x0002→0x0007，见 §8） | `3FE1DF62B0C32CF39F327CCD2AD9B574BD36B0C5CA9DBCC79C28224BF1BACAF9` |

样本性质：
- `base.*` / `tvshell-debug.*`：**受控自建** APK（开发期固定构建脚本产出，来源清晰），条目按字节提取。
- `fx-multidex.*`：**受控构建** APK（javac/d8/aapt2/zipalign/apksigner 固定流水线自产，见 §3），条目按字节提取。
- `framework-res.AndroidManifest.xml`：**AOSP 框架资源包**（Apache-2.0）条目提取。
- `edge-arsc-*.bin`：**程序化派生边角样本**（⚠ 非真实格式兼容证据，仅测畸形容错）。

另：`arsc_test.mbt` / `arsc_wbtest.mbt` / `fixtures_test.mbt` 内嵌的字节常量与对应 `tests/fixtures/` 文件字节一致（含 framework-res 资源表的类型池 chunk，见 §7）。

## 2. 样本实测属性（`aapt2 dump badging`）

| 样本来源 | package | versionCode / versionName | minSdk / targetSdk | 备注 |
|---|---|---|---|---|
| base.apk | `com.mg.motionshell` | 空 / 空 | 21 / 28 | 无 dex 条目（仅 manifest + arsc） |
| tvshell-debug.apk | `com.cteno.tvshell` | 空 / 空 | 21 / 28 | 单 `classes.dex` |
| fx-multidex-v2v3.apk | `com.fx.multidex` | `7` / `1.2.3` | 21 / 28 | 多 dex（classes.dex + classes2.dex） |
| framework-res.apk | `android` | `28` / `9` | 28 / 28 | AOSP 框架资源包 |

## 3. 提取与生成方式

- **条目提取**（base / tvshell-debug / fx-multidex / framework-res）：从来源 APK 的 ZIP 条目按字节提取（`ZipFile.ExtractToFile` 等价语义），校验口径为「fixture 文件 == 来源条目字节 == 测试内嵌字节常量」（SHA-256 三者一致，任一漂移即失败）。
- **受控构建**（fx-multidex 系列）：`javac --release 11` → `d8 --min-api 21`（classes.dex 与 classes2.dex 两桶）→ `aapt2 compile/link`（manifest + res）→ ZIP 组装（条目 STORED、固定时间戳 1980-01-01）→ `zipalign -f 4` → `apksigner sign`（v1-only 与 v2+v3 两个签名变体；v1 变体再经 repack 固定时间戳）。测试密钥仅用于夹具签名（口令写死以便可复现），无任何信任价值。同一命令链连续两次构建的产物 SHA-256 一致（可复现）。
- **framework-res 来源的两个大文件不入库**：`framework-res.apk`（9900852 B）与其 `resources.arsc`（1759752 B）体量过大，仅临时整表解析 + `aapt2 dump resources` 关键条目交叉核对（string/cancel 的 zh 双配置、color、dimen 三配置、bool、integer、fraction、style bag parent+12 maps 等逐条一致）后删除；永久保留的只有清单条目（204248 B，已内嵌，见 §6）与资源表类型池 chunk（488 B，内嵌 `arsc_wbtest.mbt`，见 §7）。

## 4. 黄金期望值与规范化口径

黄金期望值**内嵌于测试代码**：`fixtures_test.mbt` 中 GOLDEN-BEGIN/END 标记内的字符串常量即黄金值本体（标记名沿用开发期规范化产物的命名 `*.norm.txt`，那些中间文件不随仓库分发）。`moon test` 即回归。

规范化原则：只保留结构化字段，去掉 `(line=N)`、`(Raw: …)`、时间戳、绝对路径等易变文本。各视图行格式（解析侧由 `fixtures_test.mbt` 的 `fx_canon_*` 渲染，工具侧由 `aapt2 dump` 输出按同口径规范化）：

| 视图 | 规范化来源 | 行格式 |
|---|---|---|
| tree | `aapt2 dump xmltree` | `EL\|depth\|ns\|name`、`AT\|depth\|elem\|ns\|name\|value`（值按 aapt2 规则渲染） |
| pool | `aapt2 dump xmlstrings` | `POOL\|count`、`STR\|i\|text` |
| sem | `aapt2 dump badging` | `SEM\|package/versionCode/versionName/minSdk/targetSdk/label/activity/permission` |
| arsc | `aapt2 dump resources` | `ARSC\|packages\|N`、`ARSCPKG\|name\|id`（2 位小写 hex）、`ARSTYPE\|pkg\|type\|id\|entryCount`、`ARSCENT\|pkg\|type/entry\|0x%08x\|PUBLIC/-`（PUBLIC = `entry.flags & 0x0002`）、`ARSCVAL\|pkg\|type/entry\|config\|value`（字符串带引号、config 为裸限定符）、`ARSCFLAG\|…`（bag map 子行） |

## 5. 差分复核方法与结论（开发期）

**方法**：开发期用独立差分脚本把 `aapt2 dump xmltree / xmlstrings / badging / resources` 的输出按 §4 口径规范化，与本库解析输出逐字段逐行 diff（工具侧 == 解析侧 == 黄金，三方一致才通过）。该脚本与中间 `.norm.txt` 文件均不随仓库分发；黄金值已内嵌于 `fixtures_test.mbt`，日常回归只需 `moon test`。

**结论**（逐字段差分全部通过）：
- tvshell-debug 与 base 的清单：tree / pool / sem 三视图全通。
- fx-multidex 的清单（tree / pool / sem）与资源表（arsc）全通。
- framework-res 的清单：sem 视图全通（tree/pool 黄金因规范化后体量过大未登记，对应 `#skip` 用例显式标注、不计入通过数）。
- resources.arsc：40 字节空表（`ARSC|packages|0`）与 1052 字节非平凡表逐条一致（bool/fx_flag=true、color/fx_tint=#ff2255aa、string/app_name 默认/zh 双配置、名字反查）；`aapt2 dump resources` 对空表仅输出 "Binary APK" 无 package 行 ↔ 本库解析 `package_count=0`、全局池为空。

## 6. framework-res 清单内嵌可行性实测

204248 字节清单以 4096 字节分块字面量内嵌（单行超长字面量会触发编译器 `[0033] text_segment` 类告警，分块内嵌无此问题）。对照注入前后指标：

| 指标 | 注入前 | 注入后 | 差异 |
|---|---|---|---|
| `fixtures_test.mbt` 源文件 | 58 280 B | 876 146 B | +817 866 B |
| `moon clean && moon build`（冷构建） | 1 s | 1 s | 无影响（测试文件不进 build 目标） |
| `moon test`（编译 + 全量运行） | 18 s | 23 s | +5 s（+28%） |
| `_build` 产物合计 | 15 005 268 B | 16 015 654 B | ≈ +1.0 MB |
| `moon check --deny-warn` | 通过 | 通过 | 无体积类告警 |

结论：**可接受**，清单已内嵌、sem 解析侧差分启用；tree/pool 规范化黄金（数十 KB 文本常量）按体量口径不登记、不内嵌（`#skip` 用例显式标注）。

## 7. resources.arsc 解析链接线

- 解析侧入口：`@axml.parse_arsc(Bytes) -> ResTable raise ArscError`；解析侧黄金渲染 `fx_canon_arsc`（`fixtures_test.mbt`）按 §4 的 arsc 行格式输出，与 `aapt2 dump resources` 规范化同构。
- 接入用例：`golden axml arsc {fx-multidex, tvshell-debug, base}`（非平凡表 + zh 配置 + 两空表）。
- framework-res 资源表的**类型池 chunk**（488 B，位于整表偏移 @298688，UTF-16、23 串类型名，含占位名 `?22`）永久内嵌于 `arsc_wbtest.mbt` 做白盒断言；其 22 个 type 行与 23 串类型名与 `aapt2 dump resources` 逐项一致。整表 SHA-256（登记值）`AA8BDA9CACF640E4BB7BD552AF4BF025D38EAEAF0C07CD04C5FBC15B3B8587B4`。
- 两空表样本（base / tvshell-debug 的 `resources.arsc`，各 40 B，同一 SHA-256）为 `RES_TABLE_TYPE` 头 + 空字符串池，黄金恒为 `ARSC|packages|0`。

## 8. 程序化边角样本派生命令（⚠ 非真实格式兼容证据）

```powershell
# 由仓库内真实/受控样本派生（与测试内断言字节一致）：
$fx = [IO.File]::ReadAllBytes('tests/fixtures/fx-multidex.resources.arsc')
$tv = [IO.File]::ReadAllBytes('tests/fixtures/tvshell-debug.resources.arsc')
[IO.File]::WriteAllBytes('tests/fixtures/edge-arsc-truncated.bin', $fx[0..19])       # 截断 20 B
$e2 = [byte[]]$tv.Clone(); $e2[2] = 8; $e2[3] = 0
[IO.File]::WriteAllBytes('tests/fixtures/edge-arsc-badheadersize.bin', $e2)          # headerSize 12->8
$e3 = [byte[]]$fx.Clone(); $e3[0] = 7; $e3[1] = 0
[IO.File]::WriteAllBytes('tests/fixtures/edge-arsc-badtype.bin', $e3)                # type 0x0002->0x0007
```

对当前解析器的行为断言在 `fixtures_malformed_test.mbt`（arsc 边角样本全部报 `AxmlError` 而非 panic）。

## 9. 未入库第三方样本

未入库第三方样本：许可不明、未入库、开发期差分复核过。
