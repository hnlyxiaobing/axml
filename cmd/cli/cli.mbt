///|
/// axml-cli：二进制 AXML / APK 清单 CLI 核心（hnlyxiaobing/axml 公开 API 驱动）。
/// 契约（根 README.md）：退出码 0=成功 / 1=解析或IO错误 / 2=用法错误；
/// 默认记录行输出（规范化口径见 tests/ASSETS.md §3），`--json` 机器可读。
/// APK 容器条目读取使用宽松 ZIP 读取器（zipmin.mbt，零跨模块依赖）。
/// 本包为库包（可测试）；可执行入口 `hnlyxiaobing/axml/cmd/main` 仅调用 `run_main`。
///
/// L4 E2E：逻辑（选项解析 + 校验 + 解析 + 渲染）经 `cmd_dump_core` 收敛为
/// 内存字节输入 + `Sink` 输出，由公开入口 `cli_run` 在 `moon test` 原生承载
/// 场景断言（退出码 + stdout/stderr 行）；真实运行入口 `run` 保持文件读取与
/// 逐字节输出契约不变。

///|
let tool_name = "axml-cli"

///|
/// 帮助文本（stdout，exit 0）。
fn usage_text() -> String {
  join_lines([
    "\{tool_name} —— 二进制 AXML / APK 清单工具（hnlyxiaobing/axml 公开 API 驱动）",
    "",
    "用法:",
    "  \{tool_name} dump <apk|axml文件> [--view tree|sem|pool] [--entry <name>]",
    "      [--resolve] [--arsc <resources.arsc>] [--config <qualifiers>] [--json]",
    "      tree（默认）：manifest 树，EL|depth|ns|name + AT|depth|elem|ns|name|value",
    "      sem：语义摘要，SEM|package/versionCode/versionName/minSdk/targetSdk/label/activity/permission",
    "      pool：字符串池，POOL|count + STR|i|text",
    "      --entry <name> 指定 APK 内的 AXML 条目（默认 AndroidManifest.xml）",
    "      --resolve 把资源引用解析为人类可读值（@string/app_name → MyApp；",
    "      名字级 @type/name 与原值 @0x%08x 为降级回退）；资源表取 --arsc <file>，",
    "      缺省时取 APK 内 resources.arsc",
    "      --config <qualifiers> 设备限定符串（扩展版），参与引用取值的最优匹配；",
    "      未命中时回退默认配置；名字级回退同走 lookup_with；例：--config sw600dp-port-v21-b+en+US",
    "  \{tool_name} --help",
    "",
    "输入: .apk（ZIP 容器，自动取清单条目）或原始二进制 .axml/.xml（按魔数判别）。",
    "输出: 默认人类可读记录行（规范化口径见 tests/ASSETS.md §3）；",
    "      --json 输出单行 JSON（stdout）；错误信息一律走 stderr。",
    "退出码: 0=成功 1=解析或IO错误 2=用法错误",
  ])
}

///|
/// 读取输入文件；路径为空或不可读时返回 `ok=false`（退出码 1 由调用方返回）。
async fn read_input(path : String) -> (Bytes, Bool) {
  if path == "" {
    return (b"", false)
  }
  if !@fs.exists(path) {
    eprintln("error: 无法读取文件：\{path}")
    return (b"", false)
  }
  (@fs.read_binary(path), true)
}

///|
/// 输入是否为 ZIP/APK 容器（本地头魔数 PK）。
fn is_zip_container(data : Bytes) -> Bool {
  data.length() >= 2 && data[0].to_int() == 0x50 && data[1].to_int() == 0x4B
}

///|
/// 从 APK 容器取条目字节（宽松 ZIP 读取器，见 zipmin.mbt）；找不到时经汇输出错误并返回 `None`。
fn zip_entry(data : Bytes, name : String, sink : Sink) -> Bytes? raise {
  match zip_min_get(data, name, sink) {
    Some(v) => Some(v)
    None => {
      err_line(sink, "error: APK 中找不到条目：\{name}")
      None
    }
  }
}

///|
/// 从 APK 容器静默取条目字节（可选条目，如 resources.arsc）。
fn zip_entry_quiet(data : Bytes, name : String, sink : Sink) -> Bytes? raise {
  zip_min_get(data, name, sink)
}

///|
/// `dump` 子命令已解析选项。
priv struct DumpOpts {
  view : String
  entry : String?
  resolve : Bool
  json : Bool
  dev_config : @axml.ResConfig?
  in_path : String
  arsc_path : String?
}

///|
/// `dump` 子命令选项解析结果：成功（含 options）/ 已输出帮助（退出码 0）/ 用法错误（退出码 2）。
priv enum DumpParse {
  Parsed(DumpOpts)
  HelpShown
  UsageError
}

///|
/// 解析 `dump` 子命令选项；用法错误经汇输出并返回 `UsageError`（调用方返回 2），
/// `--help`/`-h` 经汇输出用法并返回 `HelpShown`（调用方返回 0）。
/// `--config` 限定符解析（`from_qualifiers_ext`）失败时向上抛出，由调用方按退出码 1 处理。
fn parse_dump(rest : ArrayView[String], sink : Sink) -> DumpParse raise {
  let mut in_path = ""
  let mut view = "tree"
  let mut entry : String? = None
  let mut resolve = false
  let mut arsc_path : String? = None
  let mut json = false
  let mut config : String? = None
  for xs = rest {
    match xs {
      ["--json", .. r] => {
        json = true
        continue r
      }
      ["--view", v, .. r] => {
        view = v
        continue r
      }
      ["--entry", v, .. r] => {
        entry = Some(v)
        continue r
      }
      ["--resolve", .. r] => {
        resolve = true
        continue r
      }
      ["--arsc", v, .. r] => {
        arsc_path = Some(v)
        continue r
      }
      ["--config", v, .. r] => {
        config = Some(v)
        continue r
      }
      ["--help", ..] => {
        out_line(sink, usage_text())
        return HelpShown
      }
      ["-h", ..] => {
        out_line(sink, usage_text())
        return HelpShown
      }
      [p, .. r] => {
        if p.has_prefix("-") {
          err_line(sink, "error: 未知选项：\{p}")
          err_line(
            sink,
            "用法: \{tool_name} dump <apk|axml文件> [--view tree|sem|pool] [--entry <name>] [--json]",
          )
          return UsageError
        }
        if in_path != "" {
          err_line(sink, "error: 多余的位置参数：\{p}")
          return UsageError
        }
        in_path = p
        continue r
      }
      [] => break
    }
  }
  if in_path == "" {
    err_line(sink, "error: dump 需要 <apk|axml文件> 参数")
    err_line(
      sink,
      "用法: \{tool_name} dump <apk|axml文件> [--view tree|sem|pool] [--entry <name>] [--json]",
    )
    return UsageError
  }
  if view != "tree" && view != "sem" && view != "pool" {
    err_line(sink, "error: --view 取值应为 tree / sem / pool：\{view}")
    return UsageError
  }
  if arsc_path is Some(_) && !resolve {
    err_line(sink, "error: --arsc 需要与 --resolve 同用")
    return UsageError
  }
  if config is Some(_) && !resolve {
    err_line(sink, "error: --config 需要与 --resolve 同用")
    return UsageError
  }
  // 构造设备配置（--config 指定时走扩展版解析）
  let mut dev_config : @axml.ResConfig? = None
  if config is Some(c) {
    dev_config = Some(@axml.ResConfig::from_qualifiers_ext(c))
  }
  Parsed(DumpOpts::{
    view,
    entry,
    resolve,
    json,
    dev_config,
    in_path,
    arsc_path,
  })
}

///|
/// `dump` 核心逻辑：选项校验（输入相关）+ 解析 + 渲染，全部经 `Sink` 输出。
/// 入参为已解析字节（`axml_bytes` 为 AXML 或经 zip 提取的条目；`is_zip` 标记原输入
/// 是否为 APK 容器，供 `--entry` 校验）；`arsc_bytes` 为已解析资源表字节（`None` 表示无表）。
/// 解析错误（arsc/axml/sem）向上抛出，由调用方捕获为退出码 1。
fn cmd_dump_core(
  opts : DumpOpts,
  axml_bytes : Bytes,
  is_zip : Bool,
  arsc_bytes : Bytes?,
  sink : Sink,
) -> Int32 raise {
  // `--entry` 仅对 APK（ZIP 容器）输入有效
  if opts.entry is Some(_) && !is_zip {
    err_line(sink, "error: --entry 仅对 APK（ZIP 容器）输入有效")
    return 2
  }
  // 资源引用解析上下文（--resolve）：表字节已由调用方解析
  let mut table : @axml.ResTable? = None
  if opts.resolve {
    match arsc_bytes {
      Some(b) => table = Some(@axml.parse_arsc(b))
      None =>
        err_line(
          sink, "error: --resolve 需要资源表：请加 --arsc <file> 或使用含 resources.arsc 的 APK",
        )
    }
    if table is None {
      return 2
    }
  }
  let doc = @axml.parse(axml_bytes)
  let ctx = RefCtx::{
    doc,
    table,
    resolve: opts.resolve,
    dev_config: opts.dev_config,
  }
  if opts.json {
    if opts.view == "tree" {
      let nodes : Array[String] = []
      for r in doc.roots {
        nodes.push(tree_json(ctx, doc, r))
      }
      let mut s = ""
      let mut first = true
      for n in nodes {
        if !first {
          s = s + ","
        }
        first = false
        s = s + n
      }
      out_line(
        sink,
        "{\"tool\":\"\{tool_name}\",\"file\":\{json_escape(opts.in_path)},\"view\":\"tree\",\"nodes\":[\{s}]}",
      )
    } else if opts.view == "sem" {
      let info = sem_info(ctx, doc)
      let perms : Array[String] = []
      for p in info.permissions {
        perms.push(json_escape(p))
      }
      let mut ps = ""
      let mut first = true
      for p in perms {
        if !first {
          ps = ps + ","
        }
        first = false
        ps = ps + p
      }
      let label = if info.has_label { json_escape(info.label) } else { "null" }
      out_line(
        sink,
        "{\"tool\":\"\{tool_name}\",\"file\":\{json_escape(opts.in_path)},\"view\":\"sem\",\"package\":\{json_escape(info.pkg_name)},\"version_code\":\{json_escape(info.version_code)},\"version_name\":\{json_escape(info.version_name)},\"min_sdk\":\{json_escape(info.min_sdk)},\"target_sdk\":\{json_escape(info.target_sdk)},\"label\":\{label},\"activity\":\{json_escape(info.activity)},\"permissions\":[\{ps}]}",
      )
    } else {
      let strings : Array[String] = []
      for s in doc.pool.strings {
        strings.push(json_escape(s))
      }
      let mut ss = ""
      let mut first = true
      for s in strings {
        if !first {
          ss = ss + ","
        }
        first = false
        ss = ss + s
      }
      out_line(
        sink,
        "{\"tool\":\"\{tool_name}\",\"file\":\{json_escape(opts.in_path)},\"view\":\"pool\",\"count\":\{doc.pool.strings.length()},\"strings\":[\{ss}]}",
      )
    }
  } else if opts.view == "tree" {
    for l in tree_lines(ctx, doc) {
      out_line(sink, l)
    }
  } else if opts.view == "sem" {
    for l in sem_lines(sem_info(ctx, doc)) {
      out_line(sink, l)
    }
  } else {
    for l in pool_lines(doc) {
      out_line(sink, l)
    }
  }
  0
}

///|
/// `dump` 子命令（真实文件路径入口，async；读取文件后委托 `cmd_dump_core`）。
async fn cmd_dump(rest : ArrayView[String], sink : Sink) -> Int32 {
  match parse_dump(rest, sink) {
    UsageError => 2
    HelpShown => 0
    Parsed(opts) => {
      let (data, ok) = read_input(opts.in_path)
      if !ok {
        return 1
      }
      let mut axml_bytes = data
      let is_zip = is_zip_container(data)
      let mut arsc_bytes : Bytes? = None
      if is_zip {
        let entry_name = match opts.entry {
          Some(v) => v
          None => "AndroidManifest.xml"
        }
        match zip_entry(data, entry_name, sink) {
          Some(b) => axml_bytes = b
          None => return 1
        }
        arsc_bytes = zip_entry_quiet(data, "resources.arsc", sink)
      }
      // `--arsc <file>` 覆盖 APK 内 resources.arsc
      if opts.arsc_path is Some(p) {
        let (ab, aok) = read_input(p)
        if !aok {
          return 1
        }
        arsc_bytes = Some(ab)
      }
      cmd_dump_core(opts, axml_bytes, is_zip, arsc_bytes, sink)
    }
  }
}

///|
/// CLI E2E 结果（公开字段；供 `moon test` 原生承载 L4 场景断言）。
pub(all) struct CliResult {
  code : Int32
  out : Array[String]
  err : Array[String]
}

///|
/// 解析选项失败（含 `--config` 限定符解析错误）时的早退结果。
fn e2e_abort(sink : Sink, code : Int32) -> CliResult {
  CliResult::{ code, out: sink.out_lines, err: sink.err_lines, }
}

///|
/// 公开 E2E 入口：对**内存字节**输入运行 CLI 核心（选项解析 + 校验 + 解析 + 渲染），
/// 捕获 stdout/stderr 行与退出码，供 `moon test` 断言 CLI 对外契约（退出码 0/1/2、
/// 记录行 EL/AT/SEM/POOL/STR、错误文本逐字节冻结）。
///
/// 语义（与真实文件入口 `cmd_dump` 逐项等价）：
/// - `input` 为原始 AXML 字节或 APK 容器（按魔数判别）；`input` 为 APK 时自动提取
///   `--entry`（默认 AndroidManifest.xml）与 resources.arsc，等价于真实入口的 zip 分支。
/// - `arsc` 为资源表字节，等价于 `--arsc <file>` 读取后的字节（内存等价物）；为 `None`
///   且 `--resolve` 时走「需要资源表」用法错误（退出码 2），与真实入口一致。
/// - 文件路径参数（`in_path`/`--arsc <path>`）在 `cli_run` 中仅记录于 JSON 的 `file`
///   字段，不触发文件读取（测试场景无文件系统依赖）。
pub fn cli_run(args : Array[String], input : Bytes, arsc : Bytes?) -> CliResult {
  let sink = capture_sink()
  // 子命令分派与真实入口 `run` 逐项一致（缺子命令 / help / 未知子命令 / dump）。
  if args.length() <= 1 {
    err_line(sink, "error: 缺少子命令（dump）")
    err_line(sink, "运行 \{tool_name} --help 查看用法")
    return e2e_abort(sink, 2)
  }
  let sub = args[1]
  if sub == "dump" {
    e2e_run_dump(args[2:], input, arsc, sink)
  } else if sub == "--help" || sub == "-h" || sub == "help" {
    out_line(sink, usage_text())
    e2e_abort(sink, 0)
  } else {
    err_line(sink, "error: 未知子命令：\{sub}")
    err_line(sink, "运行 \{tool_name} --help 查看用法")
    e2e_abort(sink, 2)
  }
}

///|
/// `cli_run` 的 `dump` 分支：选项解析 + 字节输入执行，错误统一捕获为退出码。
fn e2e_run_dump(
  rest : ArrayView[String],
  input : Bytes,
  arsc : Bytes?,
  sink : Sink,
) -> CliResult {
  // `--config` 限定符解析失败（退出码 1）在此捕获，与真实入口 `run` 的 catch 一致。
  let parsed = parse_dump(rest, sink) catch {
    e => {
      err_line(sink, "error: \{e}")
      return e2e_abort(sink, 1)
    }
  }
  let opts = match parsed {
    Parsed(o) => o
    HelpShown => return e2e_abort(sink, 0)
    UsageError => return e2e_abort(sink, 2)
  }
  let code = cli_run_with_opts(opts, input, arsc, sink) catch {
    e => {
      err_line(sink, "error: \{e}")
      1
    }
  }
  e2e_abort(sink, code)
}

///|
/// `cli_run` 的内部字节入口（raise）：APK 提取 / 表字节解析后委托 `cmd_dump_core`。
/// 解析错误（zip/arsc/axml）向上抛出，由 `cli_run` 捕获为退出码 1。
fn cli_run_with_opts(
  opts : DumpOpts,
  input : Bytes,
  arsc : Bytes?,
  sink : Sink,
) -> Int32 raise {
  let is_zip = is_zip_container(input)
  let mut axml_bytes = input
  let mut arsc_bytes = arsc
  if is_zip {
    let entry_name = match opts.entry {
      Some(v) => v
      None => "AndroidManifest.xml"
    }
    match zip_entry(input, entry_name, sink) {
      Some(b) => axml_bytes = b
      None => return 1
    }
    // `--arsc` 参数（内存字节）优先；否则取 APK 内 resources.arsc
    if arsc_bytes is None {
      arsc_bytes = zip_entry_quiet(input, "resources.arsc", sink)
    }
  }
  cmd_dump_core(opts, axml_bytes, is_zip, arsc_bytes, sink)
}

///|
/// 运行入口（真实进程）：返回进程退出码；库抛出的解析错误统一按“解析错误”返回 1。
async fn run(args : Array[String], sink : Sink) -> Int32 {
  if args.length() <= 1 {
    err_line(sink, "error: 缺少子命令（dump）")
    err_line(sink, "运行 \{tool_name} --help 查看用法")
    return 2
  }
  let sub = args[1]
  let rest = args[2:]
  if sub == "dump" {
    cmd_dump(rest, sink) catch {
      e => {
        err_line(sink, "error: \{e}")
        1
      }
    }
  } else if sub == "--help" || sub == "-h" || sub == "help" {
    out_line(sink, usage_text())
    0
  } else {
    err_line(sink, "error: 未知子命令：\{sub}")
    err_line(sink, "运行 \{tool_name} --help 查看用法")
    2
  }
}

///|
/// 进程入口的库封装：以真实 stdout/stderr 运行 CLI 并返回退出码。
/// 供可执行包 `hnlyxiaobing/axml/cmd/main` 调用（保持 main 包仅作入口）。
pub async fn run_main(args : Array[String]) -> Int32 {
  // 兜底：真实入口的解析/IO 错误统一按退出码 1 处理（与 `run` 内部 catch 一致）。
  run(args, real_sink()) catch {
    e => {
      eprintln("error: \{e}")
      1
    }
  }
}
