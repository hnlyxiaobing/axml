///|
/// T-W2-3 门禁工具单测：解析器与 SHA-256（不依赖文件系统）。

///|
test "check_fixtures: parse_registered 提取 §1 登记行" {
  let text =
    #|# axml 测试资产登记
    #|## 1. 入库 fixture
    #|| 文件 | SHA-256 | 来源 | 许可 |
    #||---|---|---|---|
    #|| base.resources.arsc | `1fa3cb291285348ec1b33c85e7317d989467707f4791c4e5302f2d312d1e18c8` | 受控自建 | Apache-2.0 |
    #|| fx-config.resources.arsc | `add60ee1b4e14c5d1adef2ab9c5cbdca7fbc836270976b5dcb043fe80d509c43` | 受控自产 | Apache-2.0 |
    #|## 4. SKIPPED 清单
    #|| 用例 | 原因 |
    #||---|---|
    #|| axml L3 device | 真机测试本轮不执行 |
  let got = parse_registered(text)
  assert_eq(got.length(), 2, msg="仅提取带 64hex 反引号哈希的行")
  assert_eq(got[0].0, "base.resources.arsc", msg="文件名")
  assert_eq(
    got[0].1,
    "1fa3cb291285348ec1b33c85e7317d989467707f4791c4e5302f2d312d1e18c8",
    msg="哈希",
  )
  assert_eq(got[1].0, "fx-config.resources.arsc", msg="第二行文件名")
}

///|
test "check_fixtures: parse_embedded 解码 FIXTURE 块字节" {
  let text =
    #|// FIXTURE-BEGIN axml/tests/fixtures/demo.arsc
    #|fn fixture_demo() -> Bytes {
    #|  b"\x02\x00\x0c\x00\xff\x00\"\n"
    #|  b"\x5c\x41\x42"
    #|}
    #|// FIXTURE-END axml/tests/fixtures/demo.arsc
  let got = parse_embedded(text)
  assert_eq(got.length(), 1, msg="一个内嵌块")
  match got.get("demo.arsc") {
    None => fail("demo.arsc 块应存在")
    Some(bytes) => {
      assert_eq(bytes.length(), 11, msg="两行字面量合并 11 字节")
      assert_eq(bytes[0], b'\x02', msg="首字节")
      assert_eq(bytes[4], b'\xff', msg="高位字节")
      assert_eq(bytes[5], b'\x00', msg="零字节")
      assert_eq(bytes[6], b'"', msg="转义引号")
      assert_eq(bytes[7], b'\n', msg="转义换行")
      assert_eq(bytes[8], b'\\', msg="\\x5c 反斜杠字节")
      assert_eq(bytes[9], b'A', msg="第二行首字节")
      assert_eq(bytes[10], b'B', msg="第二行次字节")
    }
  }
}

///|
test "check_fixtures: begin_marker 只认 FIXTURE-BEGIN 标记" {
  assert_eq(
    begin_marker("// FIXTURE-BEGIN axml/tests/fixtures/a.bin"),
    "a.bin",
    msg="标记行取文件名",
  )
  assert_eq(begin_marker("fn main { }"), "", msg="非标记行返回空")
  assert_eq(
    begin_marker("// FIXTURE-BEGIN other/path/a.bin"),
    "",
    msg="非 tests/fixtures 路径返回空",
  )
}

///|
test "check_fixtures: sha256 已知向量" {
  assert_eq(
    sha256_hex(@utf8.encode("")),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    msg="空串",
  )
  assert_eq(
    sha256_hex(@utf8.encode("abc")),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    msg="abc",
  )
  // 多块输入（1000 × "a"，期望值经 PowerShell Get-FileHash 独立实测）
  let long_input = StringBuilder(capacity=1000)
  for _ in 0..<1000 {
    long_input.write_string("a")
  }
  assert_eq(
    sha256_hex(@utf8.encode(long_input.to_string())),
    "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3",
    msg="1000×a（跨 16 块）",
  )
}
