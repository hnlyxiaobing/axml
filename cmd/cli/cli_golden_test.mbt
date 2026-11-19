///|
/// T-W3-4：CLI 字节冻结基线（golden freeze）。
///
/// 把既有命令矩阵（tree/sem/pool、--json、APK 直读、--entry、--resolve、
/// --config、退出码 0/1/2、help）的 `cli_run` 完整输出（退出码 + stdout/stderr
/// 逐行）固化为 `tests/cli-golden/*.txt` 基线，逐字节比较。
///
/// - 输入全部为程序化构造字节（encode/encode_arsc/合成 ZIP），无时间戳/绝对路径
///   等易变内容（JSON `file` 字段取自 args 字面量）。
/// - 基线文件缺失时：写入当前输出作为基线并**判失败**（需复核后重跑）；
///   已提交的基线在 CI 中恒存在，故 CI 恒为 fail-closed 强制比对。
/// - 新增/修改 CLI 选项或输出文案时本门禁必红：改输出后运行
///   `moon test -p hnlyxiaobing/axml/cmd/cli` 即失败，按提示更新基线并评审 diff。
async test "T-W3-4: CLI golden freeze（命令矩阵逐字节基线）" {
  // —— 夹具字节（与 cli_e2e_test 同源构造器）——
  let rich = @axml.encode(e2e_rich_doc())
  let ref_doc = @axml.encode(e2e_ref_doc())
  let table = @axml.encode_arsc(e2e_res_table())
  let dual = @axml.encode_arsc(e2e_dual_config_table())
  let apk = e2e_zip([("AndroidManifest.xml", rich)])
  let corrupt : Bytes = b"\x03\x00\x08\x00\x99\x99\x00\x00"
  // —— 场景矩阵：文件名 -> (args, input, arsc) ——
  let cases : Array[(String, Array[String], Bytes, Bytes?)] = [
    ("views-tree", ["axml-cli", "dump", "x.axml"], rich, None),
    ("views-sem", ["axml-cli", "dump", "x.axml", "--view", "sem"], rich, None),
    ("views-pool", ["axml-cli", "dump", "x.axml", "--view", "pool"], rich, None),
    ("views-json-tree", ["axml-cli", "dump", "x.axml", "--json"], rich, None),
    (
      "views-json-sem",
      ["axml-cli", "dump", "x.axml", "--view", "sem", "--json"],
      rich,
      None,
    ),
    (
      "views-json-pool",
      ["axml-cli", "dump", "x.axml", "--view", "pool", "--json"],
      rich,
      None,
    ),
    ("apk-tree", ["axml-cli", "dump", "app.apk"], apk, None),
    (
      "apk-entry",
      ["axml-cli", "dump", "app.apk", "--entry", "AndroidManifest.xml"],
      apk,
      None,
    ),
    (
      "apk-missing-entry",
      ["axml-cli", "dump", "app.apk", "--entry", "nope.xml"],
      apk,
      None,
    ),
    (
      "resolve-table",
      ["axml-cli", "dump", "x.axml", "--resolve", "--arsc", "r.arsc"],
      ref_doc,
      Some(table),
    ),
    (
      "config-zh",
      [
        "axml-cli", "dump", "x.axml", "--resolve", "--arsc", "r.arsc", "--config",
        "zh",
      ],
      ref_doc,
      Some(dual),
    ),
    (
      "config-none",
      ["axml-cli", "dump", "x.axml", "--resolve", "--arsc", "r.arsc"],
      ref_doc,
      Some(dual),
    ),
    (
      "config-en-fallback",
      [
        "axml-cli", "dump", "x.axml", "--resolve", "--arsc", "r.arsc", "--config",
        "en",
      ],
      ref_doc,
      Some(dual),
    ),
    (
      "config-empty",
      [
        "axml-cli", "dump", "x.axml", "--resolve", "--arsc", "r.arsc", "--config",
        "",
      ],
      ref_doc,
      Some(dual),
    ),
    (
      "errors-resolve-no-table",
      ["axml-cli", "dump", "x.axml", "--resolve"],
      ref_doc,
      None,
    ),
    (
      "errors-unknown-option",
      ["axml-cli", "dump", "x.axml", "--bogus"],
      rich,
      None,
    ),
    ("errors-unknown-subcommand", ["axml-cli", "bogus"], rich, None),
    ("errors-missing-subcommand", ["axml-cli"], rich, None),
    ("errors-help-dump", ["axml-cli", "dump", "--help"], rich, None),
    ("errors-help-top", ["axml-cli", "--help"], rich, None),
    (
      "errors-invalid-config",
      [
        "axml-cli", "dump", "x.axml", "--resolve", "--arsc", "r.arsc", "--config",
        "xylophone",
      ],
      ref_doc,
      Some(table),
    ),
    ("errors-parse-corrupt", ["axml-cli", "dump", "x.axml"], corrupt, None),
  ]
  let mut failures = 0
  for case in cases {
    let (name, args, input, arsc) = case
    let r = @cli.cli_run(args, input, arsc)
    let actual = golden_text(name, r)
    let path = "tests/cli-golden/" + name + ".txt"
    if !@fs.exists(path) {
      // 基线缺失：落盘当前输出并判失败（需人工复核后重跑）
      @fs.write_binary(path, @utf8.encode(actual)[:])
      println("golden baseline written: \{path}")
      failures = failures + 1
      continue
    }
    let want = @utf8.decode(@fs.read_binary(path))
    if want != actual {
      println(
        "GOLDEN MISMATCH \{name}:\n--- expected ---\n\{want}\n--- actual ---\n\{actual}",
      )
      failures = failures + 1
    }
  }
  assert_eq(
    failures,
    0,
    msg="CLI golden 基线应全部一致（见上方 MISMATCH 详情）",
  )
}

///|
/// 单场景规范化文本：`== <name> ==` + 退出码 + stdout/stderr 逐行（`out|`/`err|`）。
fn golden_text(name : String, r : @cli.CliResult) -> String {
  let sb = StringBuilder(capacity=256)
  sb.write_string("== ")
  sb.write_string(name)
  sb.write_string(" ==\n")
  sb.write_string("exit|")
  sb.write_string("\{r.code}\n")
  for l in r.out {
    sb.write_string("out|")
    sb.write_string(l)
    sb.write_string("\n")
  }
  for l in r.err {
    sb.write_string("err|")
    sb.write_string(l)
    sb.write_string("\n")
  }
  sb.to_string()
}
