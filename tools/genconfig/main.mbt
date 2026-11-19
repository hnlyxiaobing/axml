///|
/// fx-config fixture 生成器（受控自产，T-W2-3 证据链溯源工具）。
///
/// 程序化构造一对 manifest + resources.arsc：
/// - AXML：manifest > application，`android:label` 为 Reference 型属性
///   （raw_data = 0x7f010000 = string/app_name），经 `@axml.encode` 回编；
/// - ARSC：包 0x7f "com.fx.config"，string/app_name 双配置——
///   默认 "Fx Multidex" + zh "Fx 多维"（与真实样本 fx-multidex.resources.arsc
///   的取值同构），经 `@axml.encode_arsc` 回编（构造型配置零填充路径）。
///
/// 用途：真实 fx-multidex manifest 的 label 为内嵌字面量（池串 "Fx Multidex"，
/// 不含 `@string/app_name` 引用），无法演示 `--config` 选值；本 fixture 补齐
/// 该演示能力。生成产物写入 `tests/fixtures/`，并把可内嵌的
/// `FIXTURE-BEGIN/END` 块打印到 stdout（供 `fixtures_test.mbt` 内嵌）。
///
/// 运行：`moon run tools/genconfig`（在仓库根目录）。
async fn main {
  let doc : @axml.AxmlDoc = gen_doc()
  let axml_bytes = @axml.encode(doc)
  let arsc_bytes = @axml.encode_arsc(gen_table())
  let axml_path = "tests/fixtures/fx-config.AndroidManifest.xml"
  let arsc_path = "tests/fixtures/fx-config.resources.arsc"
  @fs.write_binary(axml_path, axml_bytes[:])
  @fs.write_binary(arsc_path, arsc_bytes[:])
  println("written: \{axml_path} (\{axml_bytes.length()} bytes)")
  println("written: \{arsc_path} (\{arsc_bytes.length()} bytes)")
  println("")
  println("// FIXTURE-BEGIN axml/tests/fixtures/fx-config.AndroidManifest.xml")
  print_fn_block("fixture_fx_config_manifest", axml_bytes)
  println("// FIXTURE-END axml/tests/fixtures/fx-config.AndroidManifest.xml")
  println("")
  println("// FIXTURE-BEGIN axml/tests/fixtures/fx-config.resources.arsc")
  print_fn_block("fixture_fx_config_arsc", arsc_bytes)
  println("// FIXTURE-END axml/tests/fixtures/fx-config.resources.arsc")
}

///|
/// manifest > application，`android:label` 为 Reference 型（0x7f010000）。
fn gen_doc() -> @axml.AxmlDoc {
  let android_ns = "http://schemas.android.com/apk/res/android"
  {
    pool: {
      encoding: @axml.StringEncoding::Utf8,
      strings: ["manifest", "application", android_ns, "label"],
      styles: Bytes::make(0, b'\x00'),
    },
    nodes: [
      {
        line: 1,
        ns: None,
        name: "manifest",
        attributes: [],
        children: [1],
        parent: None,
        chunk: @axml.ChunkType::StartElement,
      },
      {
        line: 1,
        ns: None,
        name: "application",
        attributes: [
          {
            ns: Some(android_ns),
            name: "label",
            raw_value: None,
            value_type: @axml.ValueType::Reference,
            res0: b'\x00',
            raw_data: 0x7f010000U,
            line: 1,
          },
        ],
        children: [],
        parent: Some(0),
        chunk: @axml.ChunkType::StartElement,
      },
    ],
    roots: [0],
    resource_map: [],
  }
}

///|
/// 双配置资源表：string/app_name 默认 "Fx Multidex" + zh "Fx 多维"。
fn gen_table() -> @axml.ResTable {
  fn pool(strings : Array[String]) -> @axml.StringPool {
    {
      encoding: @axml.StringEncoding::Utf8,
      strings,
      styles: Bytes::make(0, b'\x00'),
    }
  }

  let def = @axml.ResConfig::from_qualifiers("") catch { _ => abort("def") }
  let zh = @axml.ResConfig::from_qualifiers("zh") catch { _ => abort("zh") }
  let entry_def : @axml.ResEntry = {
    key: 0,
    key_name: "app_name",
    flags: 0,
    value: @axml.ResEntryValue::Simple({
      data_type: @axml.ResDataType::String,
      data: 0U,
    }),
  }
  let entry_zh : @axml.ResEntry = {
    key: 0,
    key_name: "app_name",
    flags: 0,
    value: @axml.ResEntryValue::Simple({
      data_type: @axml.ResDataType::String,
      data: 1U,
    }),
  }
  let spec : @axml.ResTypeSpec = {
    id: 1,
    types_count: 2,
    entry_count: 1,
    spec_flags: [0x40000000U],
    configs: [
      { id: 1, flags: 0, config: def, entries: [Some(entry_def)], },
      { id: 1, flags: 0, config: zh, entries: [Some(entry_zh)], },
    ],
  }
  let pkg : @axml.ResPackage = {
    id: 0x7f,
    name: "com.fx.config",
    type_id_offset: 0,
    type_pool: pool(["string"]),
    key_pool: pool(["app_name"]),
    types: [spec],
    libraries: [],
  }
  {
    global_pool: pool(["Fx Multidex", "Fx 多维"]),
    packages: [pkg],
    package_count: 1,
  }
}

///|
/// 把字节渲染为 `fn <name>() -> Bytes { b"..."... }` 形态（每行 4096 字节，
/// 与 fixtures_test.mbt 既有内嵌块口径一致）。
fn print_fn_block(name : String, data : Bytes) -> Unit {
  println("fn \{name}() -> Bytes {")
  let digits : Array[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let total = data.length()
  let chunk = 4096
  let mut off = 0
  while off < total {
    let end = if off + chunk < total { off + chunk } else { total }
    let line : StringBuilder = StringBuilder(capacity=chunk * 4 + 16)
    line.write_string("  b\"")
    for i in off..<end {
      let b = data[i].to_int()
      line.write_string("\\x")
      line.write_char(digits[(b >> 4) & 0xF])
      line.write_char(digits[b & 0xF])
    }
    line.write_string("\"")
    println(line.to_string())
    off = end
  }
  println("}")
}
