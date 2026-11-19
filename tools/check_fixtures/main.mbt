///|
/// fixture 双通道一致性门禁（T-W2-3，fail-closed）。
///
/// 校验三条链（任一失败即退出码 1，缺失文件不静默跳过）：
/// 1. `tests/ASSETS.md` §1 登记的每个文件在 `tests/fixtures/` 下存在，
///    且实测 SHA-256 与登记值一致（SHA-256 为本包内置最小实现，
///    启动时先过标准向量自测）；
/// 2. `fixtures_test.mbt` 中 `FIXTURE-BEGIN/END` 内嵌字节块与对应文件
///    逐字节一致（首个差异打印 文件/偏移/期望/实际）；
/// 3. 反向完备：每个内嵌块都必须在 ASSETS §1 有登记（防止未登记资产入库）。
///
/// 无内嵌块的样本（畸形派生物）输出「仅哈希」状态，仍受 SHA-256 门禁约束。
///
/// 运行：`moon run tools/check_fixtures`（仓库根目录；CI 于 moon test 后执行）。
async fn main {
  sha256_selftest()
  // —— 读取 ASSETS §1 登记 ——
  let assets_bytes = @fs.read_binary("tests/ASSETS.md")
  let registered = parse_registered(@utf8.decode(assets_bytes))
  if registered.is_empty() {
    println("FAIL|未从 tests/ASSETS.md §1 解析到任何登记行")
    @env.exit(1)
  }
  // —— 读取 fixtures_test.mbt 内嵌块 ——
  let ft_bytes = @fs.read_binary("fixtures_test.mbt")
  let embedded = parse_embedded(@utf8.decode(ft_bytes))
  let mut failures = 0
  let mut embedded_count = 0
  for entry in registered {
    let (name, want_hash) = entry
    let path = "tests/fixtures/" + name
    if !@fs.exists(path) {
      println("FAIL|\{name}|文件缺失（不得静默跳过）")
      failures = failures + 1
      continue
    }
    let data = @fs.read_binary(path)
    let got_hash = sha256_hex(data)
    if got_hash != want_hash {
      println(
        "FAIL|\{name}|SHA-256 不一致|期望 \{want_hash}|实际 \{got_hash}",
      )
      failures = failures + 1
      continue
    }
    match embedded.get(name) {
      Some(block) => {
        if block.length() != data.length() {
          println(
            "FAIL|\{name}|内嵌块长度不一致|期望 \{data.length()}|实际 \{block.length()}",
          )
          failures = failures + 1
          continue
        }
        let mut diff_at = -1
        let mut got_byte = b'\x00'
        for i in 0..<data.length() {
          if block[i] != data[i] {
            diff_at = i
            got_byte = block[i]
            break
          }
        }
        if diff_at >= 0 {
          println(
            "FAIL|\{name}|逐字节不一致|偏移 \{diff_at}|期望 0x\{hex2(data[diff_at])}|实际 0x\{hex2(got_byte)}",
          )
          failures = failures + 1
        } else {
          println("OK|\{name}|哈希+内嵌逐字节一致")
          embedded_count = embedded_count + 1
        }
      }
      None => println("OK|\{name}|仅哈希（无内嵌块）")
    }
  }
  // —— 反向完备：内嵌块必须已登记 ——
  for name in embedded.keys() {
    let mut found = false
    for entry in registered {
      if entry.0 == name {
        found = true
        break
      }
    }
    if !found {
      println("FAIL|\{name}|内嵌块存在但 ASSETS §1 未登记")
      failures = failures + 1
    }
  }
  println(
    "check_fixtures: registered=\{registered.length()} embedded=\{embedded_count} failures=\{failures}",
  )
  if failures > 0 {
    @env.exit(1)
  }
}

///|
/// 去除两端空白与 CR。
fn strip(s : StringView) -> StringView {
  s.trim(chars=" \t\r")
}

///|
/// 解析 ASSETS §1 表行：`| <file> | \`<64hex>\` | ...` -> (file, hash)。
fn parse_registered(text : String) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for line in text.split("\n") {
    let l = strip(line)
    if l.length() < 2 || l[0] != '|' {
      continue
    }
    let cells : Array[StringView] = l.split("|").collect()
    if cells.length() < 4 {
      continue
    }
    // cells[0] 为首 | 前的空串，cells[1]=文件名，cells[2]=哈希
    let name = strip(cells[1])
    let hash = strip(cells[2])
    // 哈希列须为反引号包裹的 64 位十六进制
    if hash.length() == 66 && hash[0] == '`' && hash[65] == '`' {
      let h = hash[1:65].to_owned()
      if is_hex64(h) && name.length() > 0 && !name.contains("/") {
        out.push((name.to_owned(), h))
      }
    }
  }
  out
}

///|
/// 解析 fixtures_test.mbt 的 `FIXTURE-BEGIN/END` 内嵌块：
/// 块内逐行收集 `b"..."` 字节字面量并解码 \xNN / \\ / \" / \n / \r / \t / \0。
fn parse_embedded(text : String) -> Map[String, Bytes] {
  let out : Map[String, Bytes] = Map([])
  let mut cur_name = ""
  let mut cur : Array[Byte] = []
  for line in text.split("\n") {
    let l = line.trim(chars="\r")
    if cur_name == "" {
      let name = begin_marker(l)
      if name != "" {
        cur_name = name
        cur = []
      }
    } else if l.contains("// FIXTURE-END") {
      out[cur_name] = Bytes::from_array(cur)
      cur_name = ""
      cur = []
    } else {
      collect_literal(l, cur)
    }
  }
  out
}

///|
/// `// FIXTURE-BEGIN <path>` -> `tests/fixtures/` 之后的文件名；非标记行返回 ""。
fn begin_marker(line : StringView) -> String {
  let prefix = "// FIXTURE-BEGIN "
  if !line.has_prefix(prefix) {
    return ""
  }
  let path = line[prefix.length():].to_owned()
  guard path.find("tests/fixtures/") is Some(idx) else { return "" }
  let start = idx + "tests/fixtures/".length()
  path[start:].to_owned()
}

///|
/// 从一行中收集全部 `b"..."` 字面量的解码字节（忽略行内其余内容）。
fn collect_literal(line : StringView, out : Array[Byte]) -> Unit {
  let n = line.length()
  let mut i = 0
  while i < n {
    if line[i] == 'b' && i + 1 < n && line[i + 1] == '"' {
      i = i + 2
      while i < n {
        let c = line[i]
        if c == '"' {
          i = i + 1
          break
        }
        if c == '\\' {
          if i + 3 < n && line[i + 1] == 'x' {
            let hi = hex_val(line[i + 2].to_int())
            let lo = hex_val(line[i + 3].to_int())
            if hi >= 0 && lo >= 0 {
              out.push((hi * 16 + lo).to_byte())
              i = i + 4
              continue
            }
          }
          // 简单转义
          if i + 1 < n {
            let e = line[i + 1]
            let b : Int32 = match e {
              '\\' => 0x5C
              '"' => 0x22
              'n' => 0x0A
              'r' => 0x0D
              't' => 0x09
              '0' => 0x00
              _ => -1
            }
            if b >= 0 {
              out.push(b.to_byte())
              i = i + 2
              continue
            }
          }
          break
        }
        // 普通字符（内嵌块口径为纯 \xNN，出现裸字符按原样收编）
        out.push(line[i].to_int().to_byte())
        i = i + 1
      }
      continue
    }
    i = i + 1
  }
}

///|
fn hex_val(v : Int32) -> Int32 {
  if v >= 0x30 && v <= 0x39 {
    return v - 0x30
  }
  if v >= 0x61 && v <= 0x66 {
    return v - 0x61 + 10
  }
  if v >= 0x41 && v <= 0x46 {
    return v - 0x41 + 10
  }
  -1
}

///|
fn is_hex64(s : String) -> Bool {
  if s.length() != 64 {
    return false
  }
  for c in s {
    if hex_val(c.to_int()) < 0 {
      return false
    }
  }
  true
}

///|
fn hex2(b : Byte) -> String {
  let v = b.to_int()
  let digits : Array[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let out = StringBuilder(capacity=2)
  out.write_char(digits[(v >> 4) & 0xF])
  out.write_char(digits[v & 0xF])
  out.to_string()
}
