# axml 测试资产登记

> 建立：2026-11-19 ｜ 本仓库自包含证据链：fixture 来源、许可、SHA-256 全量登记

## 1. 入库 fixture（12 个文件，路径 `tests/fixtures/`）

### base / tvshell-debug（受控自建）

| 文件 | SHA-256 | 来源 | 许可 |
|---|---|---|---|
| base.AndroidManifest.xml | `c7a39304785e6eeb0cb9efc799613f10c21c22ee1c2b729f010015431b501091` | 受控自建：aapt2 编译极简 AndroidManifest（package=`com.example`, 单 activity），产出 APK 后 dump 抽取 AXML | 随仓库 Apache-2.0 |
| base.resources.arsc | `1fa3cb291285348ec1b33c85e7317d989467707f4791c4e5302f2d312d1e18c8` | 受控自建：同 base manifest 编译的资源表 | 随仓库 Apache-2.0 |
| tvshell-debug.AndroidManifest.xml | `23064a1732eee67d9be1d155a9eb08c8b0269590b3c4c6ed3c6fcd444e5c62fd` | 受控自建：aapt2 编译含 application / debug 标志 / 多 activity 的 manifest | 随仓库 Apache-2.0 |
| tvshell-debug.resources.arsc | `1fa3cb291285348ec1b33c85e7317d989467707f4791c4e5302f2d312d1e18c8` | 受控自建：同 tvshell-debug manifest 编译的资源表 | 随仓库 Apache-2.0 |

### fx-multidex（官方工具链自产）

| 文件 | SHA-256 | 来源 | 许可 |
|---|---|---|---|
| fx-multidex.AndroidManifest.xml | `b0f3496eb429813c88bcee7d6b9b17ce69711a3b147137ee94a3e91b7aedc271` | aapt2 编译 minSdkVersion=21、multidexEnabled=true 的 manifest | 随仓库 Apache-2.0 |
| fx-multidex.resources.arsc | `ad89335ab8192aa4cd4e07b8930cf68f13fb5fc7b9eda2179deb80b5acce1fdd` | 同 fx-multidex manifest 编译的资源表 | 随仓库 Apache-2.0 |

### fx-config（受控自产，MoonBit 程序化生成）

| 文件 | SHA-256 | 来源 | 许可 |
|---|---|---|---|
| fx-config.AndroidManifest.xml | `bb735f5ccf5732bb55021d4a1fb921f3cc496003fd41662a783e4f48c511466b` | 受控自产：`moon run tools/genconfig` 程序化构造（manifest > application，`android:label` 为 Reference 型 0x7f010000，经 `@axml.encode` 回编） | 随仓库 Apache-2.0 |
| fx-config.resources.arsc | `add60ee1b4e14c5d1adef2ab9c5cbdca7fbc836270976b5dcb043fe80d509c43` | 受控自产：同上工具生成（string/app_name 默认 "Fx Multidex" + zh "Fx 多维"，构造型配置经 `@axml.encode_arsc` 零填充路径回编） | 随仓库 Apache-2.0 |

> 用途说明：真实 fx-multidex manifest 的 `android:label` 为内嵌字面量（字符串池
> 无 `@string/app_name`），`--config` 选值无法在该样本上观测；fx-config 对为
> T-W3-3 的 `moon run` 端到端实跑提供可引用的 manifest（见 docs/CHANGELOG
> 2026-11-19 W3 修复条目）。

### framework-res（AOSP Apache-2.0）

| 文件 | SHA-256 | 来源 | 许可 |
|---|---|---|---|
| framework-res.AndroidManifest.xml | `12db5c25e648911823241b2a535b44b7349e8d98f13f50ab0885c07985c8b89b` | AOSP `framework-res.apk` 内置 manifest dump | Apache-2.0（AOSP 默认许可） |

### 畸形派生物（截断/头部污染）

| 文件 | SHA-256 | 来源 | 许可 |
|---|---|---|---|
| edge-arsc-badheadersize.bin | `ae7bd7ab0ecf03f59c8d5267e4d7df7a858bda2a65f58576a453e9f23960d969` | 由 base.resources.arsc 程序化截断/头部字段污染产生 | 随仓库 Apache-2.0 |
| edge-arsc-badtype.bin | `3fe1df62b0c32cf39f327ccd2ad9b574bd36b0c5ca9dbcc79c28224bf1bacaf9` | 程序化 chunk type 字节污染 | 随仓库 Apache-2.0 |
| edge-arsc-truncated.bin | `a9756c656dc26b2f9f246df24f6ef47929d427e267ad3651e396487ad4378f2b` | base.resources.arsc 全前缀截断样本之一 | 随仓库 Apache-2.0 |

## 2. 双通道说明：文件 ↔ 内嵌常量

- 回归主力依赖 `fixtures_test.mbt` 内嵌字节常量（`FIXTURE-BEGIN` / `FIXTURE-END` 标记块）；`tests/fixtures/*.bin` 为同源文件备份。
- **一致性门禁（T-W2-3，已落地）**：`moon run tools/check_fixtures`（仓库根目录；CI 于 `moon test` 后同 job 执行）执行 fail-closed 三链校验——① §1 每个文件存在且实测 SHA-256（工具内置最小实现，启动自测标准向量）与登记一致；② `fixtures_test.mbt` 内嵌块与文件逐字节一致（首个差异打印偏移与期望/实际）；③ 内嵌块反向必须已登记。无内嵌块的样本输出「仅哈希」状态。任一失败退出码 1，文件缺失不静默跳过。

## 3. 黄金规范化口径（CLI 记录行冻结契约）

```
EL|depth|ns|name
AT|depth|elem|ns|name|value
SEM|key|value
POOL|count
STR|i|text
```

- hex 渲染用 `hex_min` 最小宽度语义（高位非零输出更多数位）
- 定点数 `fixed6` 六位；fraction **不乘 100**（与 aapt2 dump 一致）
- 动态引用保持原样（`(dynamic)` / `Unresolved`）
- 引用链深度 > 16 输出 `(too deep)`；无 visited 环检测

## 4. SKIPPED 用例显式清单（永不计入通过）

| 用例 | 原因 |
|---|---|
| `axml malformed: checksum 污染` | AXML 无 checksum 字段，N/A |
| `golden axml tree framework-res` | tree/pool 黄金过大未登记；sem 差分已启用 |
| `axml L3 device` | 真机测试本轮不执行 |

## 5. 许可红线

- 第三方 APK / .so / 模型**不入库**；许可不明真实样本只登记「仓库外本地路径 + SHA-256 + 显式 SKIPPED」。
- 入库 fixture 须为：受控自建、官方工具链自产、AOSP Apache-2.0 或明确许可的确定来源。
