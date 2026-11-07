///|
/// axml-cli：二进制 AXML / APK 清单 CLI（hnlyxiaobing/axml 公开 API 驱动）。
/// 契约（根 README.md）：退出码 0=成功 / 1=解析或IO错误 / 2=用法错误；
/// 默认记录行输出（与 fixtures/golden/axml/*.norm.txt 口径一致），`--json` 机器可读。
/// APK 容器条目读取使用 moonbitlang/core/archive/zip（零跨模块依赖）。

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
    "      [--resolve] [--arsc <resources.arsc>] [--json]",
    "      tree（默认）：manifest 树，EL|depth|ns|name + AT|depth|elem|ns|name|value",
    "      sem：语义摘要，SEM|package/versionCode/versionName/minSdk/targetSdk/label/activity/permission",
    "      pool：字符串池，POOL|count + STR|i|text",
    "      --entry <name> 指定 APK 内的 AXML 条目（默认 AndroidManifest.xml）",
    "      --resolve 把资源引用解析为人类可读值（@string/app_name → MyApp；",
    "      名字级 @type/name 与原值 @0x%08x 为降级回退）；资源表取 --arsc <file>，",
    "      缺省时取 APK 内 resources.arsc",
    "  \{tool_name} --help",
    "",
    "输入: .apk（ZIP 容器，自动取清单条目）或原始二进制 .axml/.xml（按魔数判别）。",
    "输出: 默认人类可读记录行（规范化口径与 fixtures/golden/axml/*.norm.txt 一致）；",
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
/// 从 APK 容器取条目字节（宽松 ZIP 读取器，见 zipmin.mbt）；找不到时输出错误并返回 `None`。
fn zip_entry(data : Bytes, name : String) -> Bytes? raise {
  match zip_min_get(data, name) {
    Some(v) => Some(v)
    None => {
      eprintln("error: APK 中找不到条目：\{name}")
      None
    }
  }
}

///|
/// 从 APK 容器静默取条目字节（可选条目，如 resources.arsc）。
fn zip_entry_quiet(data : Bytes, name : String) -> Bytes? raise {
  zip_min_get(data, name)
}

///|
/// `dump` 子命令。
async fn cmd_dump(rest : ArrayView[String]) -> Int32 {
  let mut in_path = ""
  let mut view = "tree"
  let mut entry : String? = None
  let mut resolve = false
  let mut arsc_path : String? = None
  let mut json = false
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
      ["--help", ..] => {
        println(usage_text())
        return 0
      }
      ["-h", ..] => {
        println(usage_text())
        return 0
      }
      [p, .. r] => {
        if p.has_prefix("-") {
          eprintln("error: 未知选项：\{p}")
          eprintln(
            "用法: \{tool_name} dump <apk|axml文件> [--view tree|sem|pool] [--entry <name>] [--json]",
          )
          return 2
        }
        if in_path != "" {
          eprintln("error: 多余的位置参数：\{p}")
          return 2
        }
        in_path = p
        continue r
      }
      [] => break
    }
  }
  if in_path == "" {
    eprintln("error: dump 需要 <apk|axml文件> 参数")
    eprintln(
      "用法: \{tool_name} dump <apk|axml文件> [--view tree|sem|pool] [--entry <name>] [--json]",
    )
    return 2
  }
  if view != "tree" && view != "sem" && view != "pool" {
    eprintln("error: --view 取值应为 tree / sem / pool：\{view}")
    return 2
  }
  if arsc_path is Some(_) && !resolve {
    eprintln("error: --arsc 需要与 --resolve 同用")
    return 2
  }
  let (data, ok) = read_input(in_path)
  if !ok {
    return 1
  }
  let mut axml_bytes = data
  let mut arsc_bytes : Bytes? = None
  if is_zip_container(data) {
    let entry_name = match entry {
      Some(v) => v
      None => "AndroidManifest.xml"
    }
    match zip_entry(data, entry_name) {
      Some(b) => axml_bytes = b
      None => return 1
    }
    arsc_bytes = zip_entry_quiet(data, "resources.arsc")
  } else if entry is Some(_) {
    eprintln("error: --entry 仅对 APK（ZIP 容器）输入有效")
    return 2
  }
  // 资源引用解析上下文（--resolve）：资源表取 --arsc <file> 或 APK 内 resources.arsc
  let mut table : @axml.ResTable? = None
  if resolve {
    match arsc_path {
      Some(p) => {
        let (ab, aok) = read_input(p)
        if !aok {
          return 1
        }
        table = Some(@axml.parse_arsc(ab))
      }
      None =>
        match arsc_bytes {
          Some(b) => table = Some(@axml.parse_arsc(b))
          None => ()
        }
    }
    if table is None {
      eprintln(
        "error: --resolve 需要资源表：请加 --arsc <file> 或使用含 resources.arsc 的 APK",
      )
      return 2
    }
  }
  let doc = @axml.parse(axml_bytes)
  let ctx = RefCtx::{ doc, table, resolve, }
  if json {
    if view == "tree" {
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
      println(
        "{\"tool\":\"\{tool_name}\",\"file\":\{json_escape(in_path)},\"view\":\"tree\",\"nodes\":[\{s}]}",
      )
    } else if view == "sem" {
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
      println(
        "{\"tool\":\"\{tool_name}\",\"file\":\{json_escape(in_path)},\"view\":\"sem\",\"package\":\{json_escape(info.pkg_name)},\"version_code\":\{json_escape(info.version_code)},\"version_name\":\{json_escape(info.version_name)},\"min_sdk\":\{json_escape(info.min_sdk)},\"target_sdk\":\{json_escape(info.target_sdk)},\"label\":\{label},\"activity\":\{json_escape(info.activity)},\"permissions\":[\{ps}]}",
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
      println(
        "{\"tool\":\"\{tool_name}\",\"file\":\{json_escape(in_path)},\"view\":\"pool\",\"count\":\{doc.pool.strings.length()},\"strings\":[\{ss}]}",
      )
    }
  } else if view == "tree" {
    for l in tree_lines(ctx, doc) {
      println(l)
    }
  } else if view == "sem" {
    for l in sem_lines(sem_info(ctx, doc)) {
      println(l)
    }
  } else {
    for l in pool_lines(doc) {
      println(l)
    }
  }
  0
}

///|
/// 运行入口：返回进程退出码；库抛出的解析错误统一按“解析错误”返回 1。
async fn run(args : Array[String]) -> Int32 {
  if args.length() <= 1 {
    eprintln("error: 缺少子命令（dump）")
    eprintln("运行 \{tool_name} --help 查看用法")
    return 2
  }
  let sub = args[1]
  let rest = args[2:]
  if sub == "dump" {
    cmd_dump(rest) catch {
      e => {
        eprintln("error: \{e}")
        1
      }
    }
  } else if sub == "--help" || sub == "-h" || sub == "help" {
    println(usage_text())
    0
  } else {
    eprintln("error: 未知子命令：\{sub}")
    eprintln("运行 \{tool_name} --help 查看用法")
    2
  }
}

///|
async fn main {
  let code = run(@env.args())
  if code != 0 {
    @env.exit(code)
  }
}
