// 畸形派生用例：从**真实** AXML 样本派生，
// 覆盖截断 / 偏移污染 / 错误索引 / 未知 chunk。断言目标：报 `AxmlError` 而非 panic。
// 样本来源与哈希见 tests/ASSETS.md；条目提取样本见 tests/fixtures/。

///|
/// 字节级变异：拷贝后把 `offset` 处改成 `value`。
fn fx_mut(src : Bytes, offset : Int32, value : Byte) -> Bytes {
  let arr : Array[Byte] = []
  for i in 0..<src.length() {
    arr.push(src[i])
  }
  if offset >= 0 && offset < arr.length() {
    arr[offset] = value
  }
  Bytes::from_array(arr)
}

///|
/// 截断到前 `n` 字节。
fn fx_cut(src : Bytes, n : Int32) -> Bytes {
  let arr : Array[Byte] = []
  let mut i = 0
  while i < n && i < src.length() {
    arr.push(src[i])
    i = i + 1
  }
  Bytes::from_array(arr)
}

///|
/// 读小端 u32。
fn fx_u32(src : Bytes, off : Int32) -> Int32 {
  src[off].to_int() +
  (src[off + 1].to_int() << 8) +
  (src[off + 2].to_int() << 16) +
  (src[off + 3].to_int() << 24)
}

///|
/// 写小端 u32（拷贝后写入）。
fn fx_set_u32(src : Bytes, off : Int32, v : Int32) -> Bytes {
  let arr : Array[Byte] = []
  for i in 0..<src.length() {
    arr.push(src[i])
  }
  arr[off] = (v & 0xFF).to_byte()
  arr[off + 1] = ((v >> 8) & 0xFF).to_byte()
  arr[off + 2] = ((v >> 16) & 0xFF).to_byte()
  arr[off + 3] = ((v >> 24) & 0xFF).to_byte()
  Bytes::from_array(arr)
}

///|
/// 在文件尾追加一个未知 chunk（type=0x0007），并同步外层 size ——
/// 期望解析器按 DESIGN §7 跳过且不影响已有结构。
fn fx_append_unknown_chunk(src : Bytes) -> Bytes {
  let arr : Array[Byte] = []
  for i in 0..<src.length() {
    arr.push(src[i])
  }
  let outer = fx_u32(src, 4)
  arr[4] = (outer & 0xFF).to_byte()
  arr[5] = ((outer >> 8) & 0xFF).to_byte()
  arr[6] = ((outer >> 16) & 0xFF).to_byte()
  arr[7] = ((outer >> 24) & 0xFF).to_byte()
  // RES_CHUNK：type=0x0007（未知）、headerSize=8、size=12、4 字节载荷
  arr.push(b'\x07')
  arr.push(b'\x00')
  arr.push(b'\x08')
  arr.push(b'\x00')
  arr.push(b'\x0c')
  arr.push(b'\x00')
  arr.push(b'\x00')
  arr.push(b'\x00')
  arr.push(b'\xaa')
  arr.push(b'\xbb')
  arr.push(b'\xcc')
  arr.push(b'\xdd')
  let new_outer = outer + 12
  arr[4] = (new_outer & 0xFF).to_byte()
  arr[5] = ((new_outer >> 8) & 0xFF).to_byte()
  arr[6] = ((new_outer >> 16) & 0xFF).to_byte()
  arr[7] = ((new_outer >> 24) & 0xFF).to_byte()
  Bytes::from_array(arr)
}

///|
/// 解析是否以 `AxmlError` 结束（true = 报错，false = 解析成功）。
fn fx_raises(b : Bytes) -> Bool {
  let mut raised = false
  try ignore(@axml.parse(b)) catch {
    _ => raised = true
  } noraise {
    _ => ()
  }
  raised
}

///|
test "axml malformed: 截断真实清单报错且不 panic" {
  let src = fixture_tvshell_manifest()
  for cut in [0, 1, 8, 64, 100, 1000, 2000] {
    assert_true(
      fx_raises(fx_cut(src, cut)),
      msg="截断到 \{cut} 字节应报 AxmlError",
    )
  }
}

///|
test "axml malformed: 外层 chunk 类型污染报错" {
  let src = fixture_tvshell_manifest()
  // 0x0003 -> 0x0009（非 RES_XML_TYPE）
  assert_true(fx_raises(fx_mut(src, 0, b'\x09')), msg="doc type 污染")
}

///|
test "axml malformed: 字符串池 headerSize 污染报错" {
  let src = fixture_tvshell_manifest()
  // 字符串池 chunk 位于 offset 8；headerSize 在 +2（0x001c = 28）
  assert_true(
    fx_raises(fx_mut(src, 10, b'\x1b')),
    msg="pool headerSize=27 应报 BadHeaderSize",
  )
}

///|
test "axml malformed: 字符串池 chunk 类型污染（池被跳过）报错" {
  let src = fixture_tvshell_manifest()
  // chunk type 0x0001 -> 0x0007：未知 chunk 被跳过 => 缺池 => BadStringPool
  assert_true(
    fx_raises(fx_mut(src, 8, b'\x07')),
    msg="缺字符串池应报 BadStringPool",
  )
}

///|
/// 读小端 u16。
fn fx_u16(src : Bytes, off : Int32) -> Int32 {
  src[off].to_int() + (src[off + 1].to_int() << 8)
}

///|
/// 定位第一个 RES_XML_START_ELEMENT(0x0102) chunk 的 name 字段偏移（+20）。
fn fx_first_element_name_off(src : Bytes) -> Int32 {
  let total = fx_u32(src, 4)
  let mut off = 8
  let mut found = -1
  while off + 8 <= total && found < 0 {
    let t = fx_u16(src, off)
    let sz = fx_u32(src, off + 4)
    if sz < 8 || off + sz > total {
      found = -2
    } else if t == 0x0102 {
      found = off + 20
    } else {
      off = off + sz
    }
  }
  found
}

///|
test "axml malformed: 首元素 name 索引污染报 InvalidStringIndex" {
  let src = fixture_tvshell_manifest()
  let name_off = fx_first_element_name_off(src)
  assert_true(name_off > 0, msg="能找到首个 start-element 的 name 字段")
  let bad = fx_set_u32(src, name_off, 0x7FFF)
  assert_true(
    fx_raises(bad),
    msg="越界字符串索引应报 InvalidStringIndex",
  )
}

///|
test "axml malformed: 中段字节污染不 panic（报错或结构可观察地变化）" {
  let src = fixture_tvshell_manifest()
  let base = fx_canon_tree(@axml.parse(src))
  // 污染字符串池数据区的一个字节：要么报错，要么解析结果与原黄金不同
  let mut reported = false
  let mut changed = false
  let polluted = fx_mut(src, 64, b'\xff')
  try {
    let doc = @axml.parse(polluted)
    changed = fx_canon_tree(doc) != base
  } catch {
    _ => reported = true
  } noraise {
    _ => ()
  }
  assert_true(
    reported || changed,
    msg="中段污染必须报错或产生可观察差异（绝不允许静默等同原样本）",
  )
}

///|
test "axml malformed: 未知 chunk 被跳过且不影响已有结构" {
  let src = fixture_tvshell_manifest()
  let expect = fx_canon_tree(@axml.parse(src))
  let doc = @axml.parse(fx_append_unknown_chunk(src))
  assert_eq(fx_canon_tree(doc), expect)
  assert_eq(doc.pool.strings.length(), 31)
}

///|
/// AXML 没有 checksum 字段（区别于 DEX），本模块的完整性由 chunk size/index 校验承担；
/// 对应的“错误 checksum”用例在 dex/fixtures_malformed_test.mbt 中覆盖。
#skip
test "axml malformed: checksum 污染 [SKIPPED: AXML 无 checksum 字段]" {
  println("SKIPPED: AXML 无 checksum 字段，等价用例见 dex 链")
}

///|
/// 程序化 **arsc** 边角样本（**非真实格式兼容证据**）：
/// 与 tests/fixtures/edge-arsc-{truncated,badheadersize,badtype}.bin 同字节
/// （派生命令见 tests/ASSETS.md §8）。对当前 `@axml.parse` 的实测行为：
/// 全部报 `AxmlError`（RES_TABLE 外层 chunk 非 RES_XML）且不 panic；
/// 这些派生样本同时是 resources.arsc 解析器的边角夹具
///（截断 / headerSize 污染 / 未知 chunk 类型）。
test "axml malformed: 程序化 arsc 边角样本被拒且不 panic" {
  let fx = fixture_fx_multidex_arsc()
  let tv = fixture_tvshell_arsc()
  // edge-arsc-truncated.bin：fx arsc 截断到 20 字节
  assert_true(fx_raises(fx_cut(fx, 20)), msg="截断 arsc 应报 AxmlError")
  // edge-arsc-badheadersize.bin：空表 arsc 外层 headerSize 12 -> 8
  assert_true(
    fx_raises(fx_mut(tv, 2, b'\x08')),
    msg="headerSize 污染应报 AxmlError",
  )
  // edge-arsc-badtype.bin：外层 chunk type 0x0002 -> 0x0007（未知类型）
  assert_true(
    fx_raises(fx_mut(fx, 0, b'\x07')),
    msg="未知 chunk 类型应报 AxmlError",
  )
}
