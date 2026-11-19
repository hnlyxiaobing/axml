///|
/// L4：CLI 场景 E2E（axml-cli，原生 `moon test` 承载）。
///
/// 通过公开入口 `@main.cli_run`（内存字节输入 + 捕获 stdout/stderr + 退出码）逐例断言
/// CLI 对外契约（B13/A5 冻结）：
/// - 退出码 0=成功 / 1=解析或IO错误 / 2=用法错误；
/// - 记录行前缀仅 EL| / AT| / SEM| / POOL| / STR|；
/// - 错误信息一律走 stderr，`--json` 单行 JSON 走 stdout。
///
/// 夹具为**程序化构造**的合成 `AxmlDoc` / `ResTable`，经 `@axml.encode` /
/// `@axml.encode_arsc` 往返为合法字节（不依赖外部样本文件），并手工构造一个
/// Store 型 ZIP/APK 容器以覆盖「APK 直读」。

///|
/// 合成字符串池。
fn e2e_pool(strings : Array[String]) -> @axml.StringPool {
  {
    encoding: @axml.StringEncoding::Utf8,
    strings,
    styles: Bytes::make(0, b'\x00'),
  }
}

///|
/// 合成字符串属性（raw_value 字面量）。
fn e2e_attr(name : String, value : String) -> @axml.XmlAttribute {
  {
    ns: None,
    name,
    raw_value: Some(value),
    value_type: @axml.ValueType::String,
    res0: (0).to_byte(),
    raw_data: 0U,
    line: 1,
  }
}

///|
/// 合成引用属性（无 raw_value，raw_data 为资源 id）。
fn e2e_ref_attr(name : String, res_id : UInt32) -> @axml.XmlAttribute {
  {
    ns: None,
    name,
    raw_value: None,
    value_type: @axml.ValueType::Reference,
    res0: (0).to_byte(),
    raw_data: res_id,
    line: 1,
  }
}

///|
/// 合成元素节点。
fn e2e_node(
  name : String,
  attrs : Array[@axml.XmlAttribute],
  children : Array[Int32],
) -> @axml.XmlNode {
  {
    line: 1,
    ns: None,
    name,
    attributes: attrs,
    children,
    parent: None,
    chunk: @axml.ChunkType::StartElement,
  }
}

///|
/// 简单清单文档：单 manifest 元素 + package 属性（tree/pool/json 视图夹具）。
fn e2e_simple_doc() -> @axml.AxmlDoc {
  let node = e2e_node("manifest", [e2e_attr("package", "com.example.app")], [])
  {
    pool: e2e_pool(["manifest", "package", "com.example.app"]),
    nodes: [node],
    roots: [0],
    resource_map: [],
  }
}

///|
/// 富清单文档：覆盖 SEM 全部字段。
fn e2e_rich_doc() -> @axml.AxmlDoc {
  let manifest = e2e_node(
    "manifest",
    [
      e2e_attr("package", "com.example.app"),
      e2e_attr("versionCode", "1"),
      e2e_attr("versionName", "1.0"),
    ],
    [1, 2, 3, 4],
  )
  let uses_sdk = e2e_node(
    "uses-sdk",
    [e2e_attr("minSdkVersion", "21"), e2e_attr("targetSdkVersion", "30")],
    [],
  )
  let application = e2e_node("application", [e2e_attr("label", "MyApp")], [])
  let uses_permission = e2e_node(
    "uses-permission",
    [e2e_attr("name", "android.permission.INTERNET")],
    [],
  )
  let activity = e2e_node("activity", [e2e_attr("name", ".MainActivity")], [5])
  let intent_filter = e2e_node("intent-filter", [], [6, 7])
  let action = e2e_node(
    "action",
    [e2e_attr("name", "android.intent.action.MAIN")],
    [],
  )
  let category = e2e_node(
    "category",
    [e2e_attr("name", "android.intent.category.LAUNCHER")],
    [],
  )
  {
    pool: e2e_pool([
      "manifest", "package", "com.example.app", "versionCode", "1", "versionName",
      "1.0", "uses-sdk", "minSdkVersion", "21", "targetSdkVersion", "30", "application",
      "label", "MyApp", "uses-permission", "name", "android.permission.INTERNET",
      "activity", ".MainActivity", "intent-filter", "action", "android.intent.action.MAIN",
      "category", "android.intent.category.LAUNCHER",
    ]),
    nodes: [
      manifest, uses_sdk, application, uses_permission, activity, intent_filter,
      action, category,
    ],
    roots: [0],
    resource_map: [],
  }
}

///|
/// 单引用清单文档：manifest 上挂一个 Reference 属性（label -> 0x7f010000）。
fn e2e_ref_doc() -> @axml.AxmlDoc {
  let node = e2e_node("manifest", [e2e_ref_attr("label", 0x7f010000U)], [])
  {
    pool: e2e_pool(["manifest", "label"]),
    nodes: [node],
    roots: [0],
    resource_map: [],
  }
}

///|
/// 合成默认 ResConfig：`raw` 为 64 字节且首 4 字节写 size=64（与解析侧一致，
/// 满足 `encode_arsc` 的 `size <= raw.length` 与 size 字段自描述要求）。
fn e2e_default_config() -> @axml.ResConfig {
  let raw : Array[Byte] = []
  e2e_u16(raw, 64)
  e2e_u16(raw, 0)
  for _ in 0..<60 {
    raw.push(b'\x00')
  }
  let cfg : @axml.ResConfig = {
    size: 64,
    mcc: 0,
    mnc: 0,
    language: "",
    country: "",
    orientation: 0,
    touchscreen: 0,
    density: 0,
    keyboard: 0,
    navigation: 0,
    input_flags: 0,
    screen_width: 0,
    screen_height: 0,
    sdk_version: 0,
    screen_layout: 0,
    ui_mode: 0,
    smallest_screen_width_dp: 0,
    screen_width_dp: 0,
    screen_height_dp: 0,
    locale_script: "",
    color_mode: 0,
    raw: Bytes::from_array(raw),
  }
  cfg
}

///|
/// 合成资源表：包 0x7f，类型 1=string，条目 0=app_name -> 全局池字符串 "MyApp"。
fn e2e_res_table() -> @axml.ResTable {
  let config = e2e_default_config()
  let entry : @axml.ResEntry = {
    key: 0,
    key_name: "app_name",
    flags: 0,
    value: @axml.ResEntryValue::Simple({
      data_type: @axml.ResDataType::String,
      data: 0U,
    }),
  }
  let spec : @axml.ResTypeSpec = {
    id: 1,
    types_count: 1,
    entry_count: 1,
    spec_flags: [0x40000000U],
    configs: [{ id: 1, flags: 0, config, entries: [Some(entry)], }],
  }
  let pkg : @axml.ResPackage = {
    id: 0x7f,
    name: "com.example.app",
    type_id_offset: 0,
    type_pool: e2e_pool(["string"]),
    key_pool: e2e_pool(["app_name"]),
    types: [spec],
    libraries: [],
  }
  { global_pool: e2e_pool(["MyApp"]), packages: [pkg], package_count: 1, }
}

///|
/// 小端 u16 写入。
fn e2e_u16(buf : Array[Byte], v : Int32) -> Unit {
  buf.push((v & 0xFF).to_byte())
  buf.push(((v >> 8) & 0xFF).to_byte())
}

///|
/// 小端 u32 写入。
fn e2e_u32(buf : Array[Byte], v : Int32) -> Unit {
  buf.push((v & 0xFF).to_byte())
  buf.push(((v >> 8) & 0xFF).to_byte())
  buf.push(((v >> 16) & 0xFF).to_byte())
  buf.push(((v >> 24) & 0xFF).to_byte())
}

///|
/// ASCII 名字写入（每字符一字节）。
fn e2e_name(buf : Array[Byte], s : String) -> Unit {
  for c in s.iter() {
    buf.push(c.to_int().to_byte())
  }
}

///|
/// 构造 Store 型 ZIP/APK 容器（未压缩，不含 CRC 校验）。
/// 宽松读取器 zipmin 只校验中央目录与 local 头，不校验 CRC。
fn e2e_zip(entries : Array[(String, Bytes)]) -> Bytes {
  let lh : Array[Byte] = []
  let central : Array[Byte] = []
  let mut offset = 0
  for (name, data) in entries {
    let namelen = name.length()
    let usize = data.length()
    // local file header
    e2e_u32(lh, 0x04034b50)
    e2e_u16(lh, 20)
    e2e_u16(lh, 0)
    e2e_u16(lh, 0)
    e2e_u16(lh, 0)
    e2e_u16(lh, 0x21)
    e2e_u32(lh, 0)
    e2e_u32(lh, usize)
    e2e_u32(lh, usize)
    e2e_u16(lh, namelen)
    e2e_u16(lh, 0)
    e2e_name(lh, name)
    for b in data {
      lh.push(b)
    }
    // central directory header
    e2e_u32(central, 0x02014b50)
    e2e_u16(central, 20)
    e2e_u16(central, 20)
    e2e_u16(central, 0)
    e2e_u16(central, 0)
    e2e_u16(central, 0)
    e2e_u16(central, 0x21)
    e2e_u32(central, 0)
    e2e_u32(central, usize)
    e2e_u32(central, usize)
    e2e_u16(central, namelen)
    e2e_u16(central, 0)
    e2e_u16(central, 0)
    e2e_u16(central, 0)
    e2e_u16(central, 0)
    e2e_u32(central, 0)
    e2e_u32(central, offset)
    e2e_name(central, name)
    offset = offset + 30 + namelen + usize
  }
  let cd_off = lh.length()
  let cd_size = central.length()
  let eocd : Array[Byte] = []
  e2e_u32(eocd, 0x06054b50)
  e2e_u16(eocd, 0)
  e2e_u16(eocd, 0)
  e2e_u16(eocd, entries.length())
  e2e_u16(eocd, entries.length())
  e2e_u32(eocd, cd_size)
  e2e_u32(eocd, cd_off)
  e2e_u16(eocd, 0)
  let out : Array[Byte] = []
  for b in lh {
    out.push(b)
  }
  for b in central {
    out.push(b)
  }
  for b in eocd {
    out.push(b)
  }
  Bytes::from_array(out)
}

///|
/// helper：stderr 行拼接（断言消息用）。
fn join_err(r : @main.CliResult) -> String {
  let mut s = ""
  let mut first = true
  for l in r.err {
    if !first {
      s = s + " | "
    }
    first = false
    s = s + l
  }
  s
}

///|
/// helper：args 可读化（断言消息用）。
fn debug_args(args : Array[String]) -> String {
  let mut s = ""
  let mut first = true
  for a in args {
    if !first {
      s = s + ","
    }
    first = false
    s = s + a
  }
  s
}

///|
/// L4-1：正常 dump（tree 视图）退出码 0，记录行逐字节冻结。
test "L4 exit 0: tree dump record lines frozen" {
  let input = @axml.encode(e2e_simple_doc())
  let r = @main.cli_run(["axml-cli", "dump", "app.axml"], input, None)
  assert_eq(r.code, 0, msg="tree dump exit 0 (err=\{join_err(r)})")
  assert_eq(
    r.out,
    ["EL|0||manifest", "AT|0|manifest||package|com.example.app"],
    msg="tree record lines byte-exact",
  )
  assert_true(r.err.is_empty(), msg="tree dump writes nothing to stderr")
}

///|
/// L4-1：pool 视图退出码 0，POOL/STR 记录行逐字节冻结。
test "L4 exit 0: pool view record lines frozen" {
  let input = @axml.encode(e2e_simple_doc())
  let r = @main.cli_run(
    ["axml-cli", "dump", "app.axml", "--view", "pool"],
    input,
    None,
  )
  assert_eq(r.code, 0, msg="pool view exit 0")
  assert_eq(
    r.out,
    ["POOL|3", "STR|0|manifest", "STR|1|package", "STR|2|com.example.app"],
    msg="pool record lines byte-exact",
  )
}

///|
/// L4-1：sem 视图退出码 0，SEM 记录行逐字节冻结（全字段）。
test "L4 exit 0: sem view record lines frozen" {
  let input = @axml.encode(e2e_rich_doc())
  let r = @main.cli_run(
    ["axml-cli", "dump", "app.axml", "--view", "sem"],
    input,
    None,
  )
  assert_eq(r.code, 0, msg="sem view exit 0 (err=\{join_err(r)})")
  assert_eq(
    r.out,
    [
      "SEM|package|com.example.app", "SEM|versionCode|1", "SEM|versionName|1.0",
      "SEM|minSdk|21", "SEM|targetSdk|30", "SEM|label|MyApp", "SEM|activity|com.example.app.MainActivity",
      "SEM|permission|android.permission.INTERNET",
    ],
    msg="sem record lines byte-exact",
  )
}

///|
/// L4-1：--json 输出单行 JSON 到 stdout，退出码 0。
test "L4 exit 0: json output single line" {
  let input = @axml.encode(e2e_simple_doc())
  let r = @main.cli_run(["axml-cli", "dump", "app.axml", "--json"], input, None)
  assert_eq(r.code, 0, msg="json dump exit 0")
  assert_eq(r.out.length(), 1, msg="json is single line")
  let line = r.out.at(0)
  assert_true(line.has_prefix("{\"tool\":\"axml-cli\""), msg="json tool field")
  assert_true(line.contains("\"view\":\"tree\""), msg="json view field")
  assert_true(line.contains("com.example.app"), msg="json carries attr value")
}

///|
/// L4 退出码 1：解析错误（非法 AXML 字节）。
test "L4 exit 1: parse error" {
  let r = @main.cli_run(["axml-cli", "dump", "bad.axml"], b"not-an-axml", None)
  assert_eq(r.code, 1, msg="parse error exit 1")
  assert_true(r.out.is_empty(), msg="parse error writes nothing to stdout")
  assert_true(r.err.length() >= 1, msg="parse error writes to stderr")
  assert_true(
    r.err.at(0).has_prefix("error:"),
    msg="stderr line prefixed error:",
  )
}

///|
/// L4 退出码 2：用法错误矩阵逐例。
test "L4 exit 2: usage error matrix" {
  let input = @axml.encode(e2e_simple_doc())
  let cases : Array[(Array[String], String)] = [
    (["axml-cli"], "缺少子命令"),
    (["axml-cli", "bogus"], "未知子命令"),
    (["axml-cli", "dump", "x.axml", "--wat"], "未知选项"),
    (["axml-cli", "dump"], "需要 <apk|axml文件> 参数"),
    (["axml-cli", "dump", "x.axml", "--view", "bogus"], "--view 取值"),
    (
      ["axml-cli", "dump", "x.axml", "--arsc", "r.arsc"],
      "需要与 --resolve 同用",
    ),
    (
      ["axml-cli", "dump", "x.axml", "--config", "zh"],
      "需要与 --resolve 同用",
    ),
    (["axml-cli", "dump", "x.axml", "--entry", "m.xml"], "仅对 APK"),
    (["axml-cli", "dump", "x.axml", "--resolve"], "需要资源表"),
  ]
  for (args, expect) in cases {
    let r = @main.cli_run(args, input, None)
    assert_eq(r.code, 2, msg="args \{debug_args(args)} -> exit 2")
    assert_true(r.out.is_empty(), msg="usage error stdout empty")
    assert_true(
      r.err.length() >= 1 && r.err.at(0).contains(expect),
      msg="args \{debug_args(args)} -> stderr contains '\{expect}' (got \{join_err(r)})",
    )
  }
}

///|
/// L4：缺子命令/未知子命令在无输入字节时同样退出码 2。
test "L4 exit 2: usage errors without input bytes" {
  let c1 = @main.cli_run(["axml-cli"], b"", None)
  assert_eq(c1.code, 2, msg="no subcommand -> 2")
  assert_true(
    c1.err.at(0).contains("缺少子命令"),
    msg="missing subcommand text",
  )
  let c2 = @main.cli_run(["axml-cli", "bogus"], b"", None)
  assert_eq(c2.code, 2, msg="unknown subcommand -> 2")
  assert_true(
    c2.err.at(0).contains("未知子命令"),
    msg="unknown subcommand text",
  )
}

///|
/// L4：`dump --help` 与 `--help` 子命令均输出用法到 stdout，退出码 0（契约冻结）。
test "L4 exit 0: dump --help and top-level help" {
  let input = @axml.encode(e2e_simple_doc())
  let h1 = @main.cli_run(["axml-cli", "dump", "--help"], input, None)
  assert_eq(h1.code, 0, msg="dump --help exit 0")
  assert_true(h1.err.is_empty(), msg="help writes nothing to stderr")
  assert_true(
    h1.out.length() >= 1 && h1.out.at(0).contains("用法"),
    msg="dump --help prints usage",
  )
  let h2 = @main.cli_run(["axml-cli", "--help"], input, None)
  assert_eq(h2.code, 0, msg="top-level --help exit 0")
  assert_true(
    h2.out.length() >= 1 && h2.out.at(0).contains("用法"),
    msg="top-level --help prints usage",
  )
  assert_true(h2.err.is_empty(), msg="top-level help stderr empty")
}

///|
/// L4：APK（ZIP 容器）直读 -> 退出码 0，输出与原始 AXML dump 一致。
test "L4 apk direct read equals raw dump" {
  let axml_bytes = @axml.encode(e2e_simple_doc())
  let apk = e2e_zip([("AndroidManifest.xml", axml_bytes)])
  let raw = @main.cli_run(["axml-cli", "dump", "app.axml"], axml_bytes, None)
  let via_apk = @main.cli_run(["axml-cli", "dump", "app.apk"], apk, None)
  assert_eq(via_apk.code, 0, msg="apk dump exit 0 (err=\{join_err(via_apk)})")
  assert_eq(via_apk.out, raw.out, msg="apk dump output equals raw dump")
}

///|
/// L4：APK 直读 + --entry 指定条目退出码 0。
test "L4 apk with explicit --entry" {
  let axml_bytes = @axml.encode(e2e_simple_doc())
  let apk = e2e_zip([("AndroidManifest.xml", axml_bytes)])
  let r = @main.cli_run(
    ["axml-cli", "dump", "app.apk", "--entry", "AndroidManifest.xml"],
    apk,
    None,
  )
  assert_eq(r.code, 0, msg="explicit entry exit 0")
  assert_eq(r.out.at(0), "EL|0||manifest", msg="entry dump first line")
}

///|
/// L4：APK 内条目缺失 -> 退出码 1（找不到条目）。
test "L4 apk missing entry exit 1" {
  let axml_bytes = @axml.encode(e2e_simple_doc())
  let apk = e2e_zip([("AndroidManifest.xml", axml_bytes)])
  let r = @main.cli_run(
    ["axml-cli", "dump", "app.apk", "--entry", "nope.xml"],
    apk,
    None,
  )
  assert_eq(r.code, 1, msg="missing entry exit 1")
  assert_true(
    r.err.at(0).contains("找不到条目"),
    msg="stderr says entry missing",
  )
}

///|
/// L4：--resolve 无表 -> 退出码 2（需要资源表）。
test "L4 resolve without table exit 2" {
  let input = @axml.encode(e2e_ref_doc())
  let r = @main.cli_run(
    ["axml-cli", "dump", "x.axml", "--resolve"],
    input,
    None,
  )
  assert_eq(r.code, 2, msg="resolve without table exit 2")
  assert_true(
    r.err.at(0).contains("需要资源表"),
    msg="stderr mentions table",
  )
}

///|
/// L4：--resolve + 表（内存字节）-> 引用属性解析为人类可读值，退出码 0。
test "L4 resolve with table resolves reference" {
  let input = @axml.encode(e2e_ref_doc())
  let arsc = @axml.encode_arsc(e2e_res_table())
  let r = @main.cli_run(
    ["axml-cli", "dump", "x.axml", "--resolve", "--arsc", "r.arsc"],
    input,
    Some(arsc),
  )
  assert_eq(r.code, 0, msg="resolve with table exit 0 (err=\{join_err(r)})")
  assert_eq(
    r.out,
    ["EL|0||manifest", "AT|0|manifest||label|MyApp"],
    msg="reference attribute resolved to MyApp",
  )
}

///|
/// L4：--config + --resolve + 表 -> lookup_with 路径接通，退出码 0。
test "L4 config with resolve wired" {
  let input = @axml.encode(e2e_ref_doc())
  let arsc = @axml.encode_arsc(e2e_res_table())
  let r = @main.cli_run(
    [
      "axml-cli", "dump", "x.axml", "--resolve", "--arsc", "r.arsc", "--config",
      "zh-rCN",
    ],
    input,
    Some(arsc),
  )
  assert_eq(r.code, 0, msg="config+resolve exit 0 (err=\{join_err(r)})")
  assert_true(
    r.out.at(1).contains("label"),
    msg="config resolve renders label attr",
  )
}

///|
/// L4：无新选项冻结——未知选项被拒为退出码 2。
test "L4 unknown option rejected (no-new-option freeze)" {
  let input = @axml.encode(e2e_simple_doc())
  let r = @main.cli_run(["axml-cli", "dump", "x.axml", "--bogus"], input, None)
  assert_eq(r.code, 2, msg="unknown option exit 2")
  assert_true(
    r.err.at(0).contains("未知选项"),
    msg="stderr says unknown option",
  )
}

///|
/// L4：非法 --config 限定符 -> 退出码 1（解析错误，而非用法错误）。
test "L4 invalid config qualifier exit 1" {
  let input = @axml.encode(e2e_ref_doc())
  let arsc = @axml.encode_arsc(e2e_res_table())
  let r = @main.cli_run(
    [
      "axml-cli", "dump", "x.axml", "--resolve", "--arsc", "r.arsc", "--config",
      "watch-xylophone",
    ],
    input,
    Some(arsc),
  )
  assert_eq(r.code, 1, msg="invalid qualifier exit 1 (err=\{join_err(r)})")
  assert_true(r.err.length() >= 1, msg="invalid qualifier writes stderr")
}

///|
/// L4：截断的 ZIP -> 退出码 1（zip 结构错误经汇输出）。
test "L4 truncated zip exit 1" {
  let bad = b"PK\x03\x04short"
  let r = @main.cli_run(["axml-cli", "dump", "bad.apk"], bad, None)
  assert_eq(r.code, 1, msg="truncated zip exit 1")
  assert_true(r.err.length() >= 1, msg="truncated zip writes stderr")
}
