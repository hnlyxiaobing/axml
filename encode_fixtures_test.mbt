// M8-3：真实入库 AXML fixture 的 encode 语义往返（T-W8-2 / T-W8-3）。
//
// 样本来自 fixtures_test.mbt 内嵌常量（与 tests/fixtures/ 同源，SHA-256 见
// tests/ASSETS.md）。往返律口径：`parse(encode(doc))` 与 `doc` 逐字段等价，
// 且 CLI 规范化输出（tree / pool）逐行一致；不要求与 aapt2 字节级一致。

///|
fn assert_manifest_roundtrip(name : String, src : Bytes) -> Unit raise {
  let doc = @axml.parse(src)
  let back = @axml.parse(@axml.encode(doc))
  assert_true(same_doc(doc, back), msg="\{name}: document fields preserved")
  assert_true(
    fx_canon_tree(back) == fx_canon_tree(doc),
    msg="\{name}: canonical tree preserved",
  )
  assert_true(
    fx_canon_pool(back) == fx_canon_pool(doc),
    msg="\{name}: canonical pool preserved",
  )
}

///|
test "T-W8-2 real manifest base round-trips" {
  assert_manifest_roundtrip("base", fixture_base_manifest())
}

///|
test "T-W8-2 real manifest tvshell-debug round-trips" {
  assert_manifest_roundtrip("tvshell-debug", fixture_tvshell_manifest())
}

///|
test "T-W8-2 real manifest fx-multidex round-trips" {
  assert_manifest_roundtrip("fx-multidex", fixture_fx_multidex_manifest())
}

///|
test "T-W8-2 real manifest framework-res round-trips" {
  assert_manifest_roundtrip("framework-res", fixture_framework_res_manifest())
}

///|
test "T-W8-3 encode output of real manifests re-parses and is stable" {
  let samples = [
    fixture_base_manifest(),
    fixture_tvshell_manifest(),
    fixture_fx_multidex_manifest(),
    fixture_framework_res_manifest(),
  ]
  for src in samples {
    let once = @axml.encode(@axml.parse(src))
    // 再次 parse 不 panic（失败会以 AxmlError 传播并使用例失败）。
    let doc = @axml.parse(once)
    assert_true(doc.nodes.length() > 0, msg="round-trip output has nodes")
    let twice = @axml.encode(doc)
    assert_true(once == twice, msg="second encode equals the first")
  }
}
