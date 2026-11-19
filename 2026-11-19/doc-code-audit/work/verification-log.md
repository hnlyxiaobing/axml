# 验证过程与命令记录

环境：Windows / PowerShell 5 / MoonBit 工具链；工作区 `d:\MoonBit\Second_Quarter_Competition\axml`；日期 2026-11-19。

## 1. 构建与测试

```
moon check --deny-warn   # 通过
moon build               # 通过
moon test                # Total tests: 152, passed: 152, failed: 0
moon fmt                 # 通过
moon info                # 通过；git diff -- pkg.generated.mbti 为空
```

测试声明统计（`Select-String '^test "'`）：

| 文件 | 声明数 | 备注 |
|---|---|---|
| axml_test.mbt | 36 | |
| axml_wbtest.mbt | 14 | |
| arsc_test.mbt | 23 | |
| arsc_wbtest.mbt | 6 | |
| arsc_match_test.mbt | 16 | W3 3 + W4 3 + W5 2 + 既有 8 |
| arsc_encode_test.mbt | 6 | W9 |
| encode_fixtures_test.mbt | 5 | W8-3 |
| fixtures_test.mbt | 21 | 含 2 `#skip` |
| fixtures_malformed_test.mbt | 11 | 含 1 `#skip` |
| cmd/main/cli_e2e_test.mbt | 17 | L4 |
| 合计 | 155 | 152 执行 + 3 skip |

## 2. fixture 哈希核对（T-W1-2）

逐文件 `Get-FileHash -Algorithm SHA256` 与 `tests/ASSETS.md` §1 登记比对：

```
OK base.AndroidManifest.xml
OK base.resources.arsc
OK edge-arsc-badheadersize.bin
OK edge-arsc-badtype.bin
OK edge-arsc-truncated.bin
OK framework-res.AndroidManifest.xml
OK fx-multidex.AndroidManifest.xml
OK fx-multidex.resources.arsc
OK tvshell-debug.AndroidManifest.xml
OK tvshell-debug.resources.arsc
mismatches=0
```

## 3. W3 `--config` 取值路径（关键反证）

- `cmd/main/util.mbt`：`resolve_attr` 先调 `resolve_attr_value(table, value)`；仅当返回 `@0x…` 时才调 `resolve_res_ref(..., dev_config)`。
- `arsc.mbt`：`resolve_attr_value` 对 Reference 调 `resolve_id`；`resolve_id`/`resolve_id_depth` 使用 `self.lookup(id)`，非 `lookup_with`。
- `arsc.mbt` `lookup`：默认配置命中优先返回，否则返回 chunk 顺序首个命中。
- `lookup_with` 在 CLI 侧仅出现于 `resolve_res_ref`（产出 `@type/name`，不是取值）。
- `cmd/main/cli_e2e_test.mbt` 的 L4 用例 `L4 config with resolve wired`：表仅含 `id=1` 单配置，断言退出码 0 与输出含 `label`，未断言 zh 值。
- **运行时反证（真实 fixture）**：`tests/fixtures/fx-multidex.resources.arsc` 的 `string/app_name` 同时有默认值 `"Fx Multidex"` 与 `zh` 值 `"Fx 多维"`（见 `fixtures_test.mbt` 的 `ARSCVAL|...|app_name|zh`）。实跑：
  - `moon run cmd/main -- dump tests\fixtures\fx-multidex.AndroidManifest.xml --resolve --arsc tests\fixtures\fx-multidex.resources.arsc` → `AT|1|application|...|label|Fx Multidex`
  - 加 `--config zh` → 仍为 `AT|1|application|...|label|Fx Multidex`（退出码 0），**未输出 `Fx 多维`**。
- 结论：多配置表中 `--config zh-rCN` 不会改变 `--resolve` 输出值；T-W3-3 未达标（已运行时证实）。

## 4. W2 双通道脚本（T-W2-3）

- `Get-ChildItem -Recurse -Include *.ps1,*.sh,*.py,*.mbtx`（排除 `_build`）：无结果。
- 测试代码 grep `read_file|@fs\.|open\(|read_to_end|tests/fixtures`：无结果。
- `fixtures_test.mbt` 使用内嵌 `FIXTURE-BEGIN/END` 字面量；文件仅在人工哈希核对时被读取。
- 结论：一致性门禁未自动化。

## 5. W6 多表选择算法

- `arsc.mbt` `resolve_attr_value_multi`：`for t in set.tables { match t.lookup(id) ... }`，首个命中返回。
- 未引用 `package_by_id`；文档原写“按包字节选表，package_by_id 命中优先”，已订正。

## 6. W9 `ResConfig.raw`

- `arsc_encode.mbt` `encode_type`：`if cfg.config.size < 4 || cfg.config.size > cfg.config.raw.length() { raise BadTable }`；随后 `if raw.length() > 0 { raw.sub(0,size) } else { Bytes::make(size) }`。
- 对 `from_qualifiers` 构造的 `size=64, raw=[]`：`64 > 0` → `BadTable`，零填充分支不可达。
- 文档原“空/短为零填充”已订正为实际行为。

## 7. 代码注释/帮助文本引用核对

- `tests/ASSETS.md` 实际章节：§1 入库 fixture、§2 双通道一致性、§3 黄金规范化口径、§4 SKIPPED、§5 许可红线。
- 原引用 §4/§6/§7/§8 的位置均为失效章节号；已逐处改为 §1/§3 或删除。
- `arsc.mbt` fraction 注释原写“×100”，与实现（不乘 100）及 README/测试口径矛盾；已改。
- `ci.yml` 注释把不存在的 `pkg.generated.mbti.r1` 描述为实存基线；已改为“当前仓库内不存在”。

## 8. 未能运行时反证的项

- aapt2 外部 oracle / R runner / 双目标等价 / 变异扫描：本机未执行，均按文档自身“未建”登记为未完成。
- W8 的 namespace 声明位置：仅能从实现确认“不重建”，原始字节级保真未验证。
