// Blackbox tests run against the package's public API. Use `@axml` to import.
// Prefer high-level behaviors over implementation details.
// Run `moon test` to execute and `moon test --update` to refresh snapshots.
//
// 工作区没有真实 APK 资产（docs/open-questions.md Q1），全部样本在测试代码中
// 以编程方式构造：合法样本覆盖 UTF-8 / UTF-16 字符串池，畸形样本覆盖截断、
// 非法 chunk 头、非法字符串索引与厂商变体布局。

///|
/// 8 位字面量助手。
fn b(n : Int32) -> Byte {
  (n & 0xFF).to_byte()
}

///|
/// 单字节 Bytes。
fn one(x : Int32) -> Bytes {
  Bytes::from_array([b(x)])
}

///|
/// 小端 16 位字。
fn w2(n : Int32) -> Bytes {
  Bytes::from_array([b(n), b(n >> 8)])
}

///|
/// 小端 32 位字。
fn w4(n : Int32) -> Bytes {
  Bytes::from_array([b(n), b(n >> 8), b(n >> 16), b(n >> 24)])
}

///|
/// 字节串拼接。
fn cat(parts : Array[Bytes]) -> Bytes {
  let mut acc = b""
  for p in parts {
    acc = acc + p
  }
  acc
}

///|
/// UTF-8 字符串池条目长度前缀。
fn len8(n : Int32) -> Bytes {
  if n < 0x80 {
    Bytes::from_array([b(n)])
  } else {
    Bytes::from_array([b(0x80 | (n >> 8)), b(n)])
  }
}

///|
/// UTF-16 字符串池条目长度前缀。
fn len16(n : Int32) -> Bytes {
  if n < 0x8000 {
    w2(n)
  } else {
    cat([w2(0x8000 | (n >> 16)), w2(n)])
  }
}

///|
/// 构造 UTF-8 字符串池条目（字符数 + 字节数 + 载荷 + NUL）。
fn utf8_entry(chars : Int32, payload : Bytes) -> Bytes {
  cat([len8(chars), len8(payload.length()), payload, b"\x00"])
}

///|
/// 构造 UTF-16 字符串池条目（unit 数 + 载荷 + NUL）。
fn utf16_entry(units : Int32, payload : Bytes) -> Bytes {
  cat([len16(units), payload, b"\x00\x00"])
}

///|
/// 由 code unit 数组构造 UTF-16LE 载荷。
fn utf16_str(units : Array[Int32]) -> Bytes {
  let out : Array[Byte] = []
  for u in units {
    out.push(b(u))
    out.push(b(u >> 8))
  }
  Bytes::from_array(out)
}

///|
/// 字符串池 chunk（headerSize 可注入以便畸形测试）。
fn pool_raw(
  flags : Int32,
  header_size : Int32,
  table : Bytes,
  str_data : Bytes,
) -> Bytes {
  let count = table.length() / 4
  let body = cat([
    w4(count),
    w4(0),
    w4(flags),
    w4(28 + table.length()),
    w4(0),
    table,
    str_data,
  ])
  cat([w2(0x0001), w2(header_size), w4(8 + body.length()), body])
}

///|
/// 合法字符串池 chunk。
fn pool(entries : Array[Bytes], flags : Int32) -> Bytes {
  let mut table = b""
  let mut str_data = b""
  for e in entries {
    table = table + w4(str_data.length())
    str_data = str_data + e
  }
  pool_raw(flags, 28, table, str_data)
}

///|
/// RES_XML_* 节点 chunk（node 头 16 字节：line=1，comment=无）。
fn node_head(typ : Int32, payload : Bytes) -> Bytes {
  cat([w2(typ), w2(16), w4(16 + payload.length()), w4(1), w4(-1), payload])
}

///|
fn start_ns(prefix : Int32, uri : Int32) -> Bytes {
  node_head(0x0100, cat([w4(prefix), w4(uri)]))
}

///|
fn end_ns(prefix : Int32, uri : Int32) -> Bytes {
  node_head(0x0101, cat([w4(prefix), w4(uri)]))
}

///|
/// typed attribute（20 字节：ns/name/rawValue + Res_value{size=8}）。
fn attr(
  ns : Int32,
  name : Int32,
  raw : Int32,
  data_type : Int32,
  data_val : Int32,
) -> Bytes {
  cat([w4(ns), w4(name), w4(raw), w2(8), b"\x00", one(data_type), w4(data_val)])
}

///|
/// 带可变 Res_value.size 的 attribute（畸形注入用）。
fn attr_value_size(
  ns : Int32,
  name : Int32,
  raw : Int32,
  value_size : Int32,
  data_type : Int32,
  data_val : Int32,
) -> Bytes {
  cat([
    w4(ns),
    w4(name),
    w4(raw),
    w2(value_size),
    b"\x00",
    one(data_type),
    w4(data_val),
  ])
}

///|
/// START_ELEMENT chunk（attributeStart/attributeSize 可注入）。
fn start_elem_layout(
  ns : Int32,
  name : Int32,
  attr_start : Int32,
  attr_size : Int32,
  attrs : Array[Bytes],
) -> Bytes {
  let ext = cat([
    w4(ns),
    w4(name),
    w2(attr_start),
    w2(attr_size),
    w2(attrs.length()),
    w2(0),
    w2(0),
    w2(0),
  ])
  node_head(0x0102, cat([ext, cat(attrs)]))
}

///|
/// 标准 START_ELEMENT（attributeStart=20，attributeSize=20）。
fn start_elem(ns : Int32, name : Int32, attrs : Array[Bytes]) -> Bytes {
  start_elem_layout(ns, name, 20, 20, attrs)
}

///|
fn end_elem(ns : Int32, name : Int32) -> Bytes {
  node_head(0x0103, cat([w4(ns), w4(name)]))
}

///|
fn cdata(text : Int32) -> Bytes {
  node_head(0x0104, cat([w4(text), w2(8), b"\x00", b"\x03", w4(text)]))
}

///|
fn res_map(ids : Array[Int32]) -> Bytes {
  let mut body = b""
  for id in ids {
    body = body + w4(id)
  }
  cat([w2(0x0180), w2(8), w4(8 + body.length()), body])
}

///|
/// RES_XML_TYPE 外层文档。
fn xml_doc(parts : Array[Bytes]) -> Bytes {
  let body = cat(parts)
  cat([w2(0x0003), w2(8), w4(8 + body.length()), body])
}

///|
/// 截取前缀（畸形样本构造）。
fn cut(data : Bytes, n : Int32) -> Bytes {
  data[0:n].to_owned()
}

///|
/// UTF-8 黄金样本（编程方式构造的小型 manifest 形态文档）：
/// 字符串池 13 项 + 命名空间 + resource map + 3 个元素 + 1 个 CDATA。
fn golden_utf8() -> Bytes {
  let strings = [
    utf8_entry(8, b"manifest"),
    utf8_entry(7, b"package"),
    utf8_entry(15, b"com.example.app"),
    utf8_entry(11, b"application"),
    utf8_entry(8, b"activity"),
    utf8_entry(13, b".MainActivity"),
    utf8_entry(7, b"android"),
    utf8_entry(42, b"http://schemas.android.com/apk/res/android"),
    utf8_entry(11, b"versionName"),
    utf8_entry(3, b"1.0"),
    utf8_entry(11, b"hello cdata"),
    utf8_entry(10, b"debuggable"),
    utf8_entry(8, b"exported"),
  ]
  xml_doc([
    pool(strings, 0x100),
    start_ns(6, 7),
    res_map([0x01010003, 0x0101000F]),
    start_elem(-1, 0, [
      attr(-1, 1, 2, 3, 2),
      attr(7, 8, 9, 3, 9),
      attr(7, 11, -1, 0x12, 1),
    ]),
    start_elem(-1, 3, []),
    start_elem(-1, 4, [attr(7, 12, -1, 0x11, 0x2A)]),
    end_elem(-1, 4),
    cdata(10),
    end_elem(-1, 3),
    end_elem(-1, 0),
    end_ns(6, 7),
  ])
}

///|
/// UTF-16 黄金样本：含 BMP（héllo）与代理对（😀）字符串。
fn golden_utf16() -> Bytes {
  let entry0 = utf16_entry(5, utf16_str([0x68, 0xE9, 0x6C, 0x6C, 0x6F]))
  let entry1 = utf16_entry(2, utf16_str([0xD83D, 0xDE00]))
  let entry2 = utf16_entry(4, utf16_str([0x6E, 0x61, 0x6D, 0x65]))
  let entry3 = utf16_entry(4, utf16_str([0x72, 0x6F, 0x6F, 0x74]))
  xml_doc([
    pool([entry0, entry1, entry2, entry3], 0),
    start_elem(-1, 3, [attr(-1, 2, 0, 3, 0)]),
    end_elem(-1, 3),
  ])
}

///|
fn parse_err(data : Bytes) -> @axml.AxmlError raise {
  let result = Ok(@axml.parse(data)) catch { err => Err(err) }
  match result {
    Ok(_) => fail("expected parse to raise AxmlError")
    Err(e) => e
  }
}

///|
fn string_at_err(doc : @axml.AxmlDoc, index : Int32) -> @axml.AxmlError raise {
  let result = Ok(doc.string_at(index)) catch { err => Err(err) }
  match result {
    Ok(_) => fail("expected string_at to raise AxmlError")
    Err(e) => e
  }
}

///|
fn node_at_err(doc : @axml.AxmlDoc, index : Int32) -> @axml.AxmlError raise {
  let result = Ok(doc.node_at(index)) catch { err => Err(err) }
  match result {
    Ok(_) => fail("expected node_at to raise AxmlError")
    Err(e) => e
  }
}

///|
fn elements_err(doc : @axml.AxmlDoc) -> @axml.AxmlError raise {
  let result = Ok(doc.elements()) catch { err => Err(err) }
  match result {
    Ok(_) => fail("expected elements to raise AxmlError")
    Err(e) => e
  }
}

///|
test "parse decodes the UTF-8 golden document" {
  let doc = @axml.parse(golden_utf8())
  assert_true(doc.pool.encoding is Utf8, msg="pool encoding")
  assert_true(doc.pool.strings.length() == 13, msg="pool size")
  assert_true(doc.string_at(0) == "manifest", msg="string 0")
  assert_true(doc.string_at(2) == "com.example.app", msg="string 2")
  assert_true(
    doc.string_at(7) == "http://schemas.android.com/apk/res/android",
    msg="string 7",
  )
  assert_true(doc.string_at(12) == "exported", msg="string 12")
  assert_true(doc.pool.styles.length() == 0, msg="no styles")
  assert_true(doc.resource_map.length() == 2, msg="resource map size")
  assert_true(doc.resource_map.at(0) == 0x01010003U, msg="resource id 0")
  assert_true(doc.resource_map.at(1) == 0x0101000FU, msg="resource id 1")
  assert_true(doc.nodes.length() == 4, msg="node table size")
  assert_true(doc.roots.length() == 1, msg="single root")
  assert_true(doc.roots.at(0) == 0, msg="root index")
}

///|
test "parse builds the node tree with parents and children" {
  let doc = @axml.parse(golden_utf8())
  let root = doc.node_at(0)
  assert_true(root.name == "manifest", msg="root name")
  assert_true(root.ns is None, msg="root has no namespace")
  assert_true(root.parent is None, msg="root has no parent")
  assert_true(root.line == 1, msg="line number preserved")
  assert_true(root.chunk is StartElement, msg="root chunk kind")
  assert_true(root.children.length() == 1, msg="root children")
  assert_true(root.children.at(0) == 1, msg="root child index")
  let app = doc.node_at(1)
  assert_true(app.name == "application", msg="child name")
  assert_true(app.parent is Some(0), msg="child parent")
  assert_true(app.children.length() == 2, msg="child children count")
  assert_true(app.children.at(0) == 2, msg="child child 0")
  assert_true(app.children.at(1) == 3, msg="child child 1")
  let activity = doc.node_at(2)
  assert_true(activity.name == "activity", msg="grandchild name")
  assert_true(activity.parent is Some(1), msg="grandchild parent")
  assert_true(activity.children.length() == 0, msg="grandchild has no children")
  let text = doc.node_at(3)
  assert_true(text.chunk is CData, msg="cdata node kind")
  assert_true(text.name == "hello cdata", msg="cdata text")
  assert_true(text.parent is Some(1), msg="cdata parent")
}

///|
test "elements returns element nodes in chunk order and filters CData" {
  let doc = @axml.parse(golden_utf8())
  let elements = doc.elements()
  assert_true(elements.length() == 3, msg="element count")
  assert_true(elements.at(0).name == "manifest", msg="element 0")
  assert_true(elements.at(1).name == "application", msg="element 1")
  assert_true(elements.at(2).name == "activity", msg="element 2")
  for e in elements {
    assert_true(e.chunk is StartElement, msg="only element nodes")
  }
}

///|
test "attributes keep raw order and typed values" {
  let doc = @axml.parse(golden_utf8())
  let root = doc.node_at(0)
  let attrs = root.attrs()
  assert_true(attrs.length() == 3, msg="attribute count")
  assert_true(attrs.at(0).name == "package", msg="attr order 0")
  assert_true(attrs.at(1).name == "versionName", msg="attr order 1")
  assert_true(attrs.at(2).name == "debuggable", msg="attr order 2")
  let pkg = attrs.at(0)
  assert_true(pkg.ns is None, msg="package has no namespace")
  assert_true(pkg.raw_value is Some("com.example.app"), msg="package raw value")
  assert_true(pkg.value_type is String, msg="package value type")
  assert_true(pkg.res0 == b'\x00', msg="res0 preserved")
  assert_true(pkg.raw_data == 2U, msg="raw data preserved")
  assert_true(pkg.line == 1, msg="attribute line")
  let version = attrs.at(1)
  assert_true(
    version.ns is Some("http://schemas.android.com/apk/res/android"),
    msg="android namespace preserved",
  )
  assert_true(version.raw_value is Some("1.0"), msg="version raw value")
  let debuggable = attrs.at(2)
  assert_true(debuggable.raw_value is None, msg="no raw value")
  assert_true(debuggable.value_type is IntBoolean, msg="boolean value type")
  assert_true(debuggable.raw_data == 1U, msg="boolean raw data")
  let activity_attr = doc.node_at(2).attrs().at(0)
  assert_true(
    activity_attr.ns is Some("http://schemas.android.com/apk/res/android"),
    msg="activity attr ns",
  )
  assert_true(activity_attr.value_type is IntHex, msg="hex value type")
  assert_true(activity_attr.raw_data == 0x2AU, msg="hex raw data")
}

///|
test "parse decodes the UTF-16 golden document with non-ASCII strings" {
  let doc = @axml.parse(golden_utf16())
  assert_true(doc.pool.encoding is Utf16, msg="pool encoding")
  assert_true(doc.pool.strings.length() == 4, msg="pool size")
  assert_true(doc.string_at(0) == "héllo", msg="BMP string")
  assert_true(doc.string_at(1) == "😀", msg="surrogate pair string")
  let elements = doc.elements()
  assert_true(elements.length() == 1, msg="element count")
  assert_true(elements.at(0).name == "root", msg="element name")
  let attr0 = elements.at(0).attrs().at(0)
  assert_true(attr0.name == "name", msg="attr name")
  assert_true(attr0.raw_value is Some("héllo"), msg="attr raw value")
}

///|
test "namespace chunks create no nodes" {
  let doc = @axml.parse(golden_utf8())
  // StartNamespace / EndNamespace 只校验不建节点：节点表只含元素与 CDATA。
  for node in doc.nodes {
    assert_true(
      node.chunk is StartElement || node.chunk is CData,
      msg="namespace chunks produce no nodes",
    )
  }
}

///|
test "unknown chunk types are skipped" {
  let unknown = cat([w2(0x0200), w2(8), w4(12), b"\x01\x02\x03\x04"])
  let doc = @axml.parse(
    xml_doc([
      pool([utf8_entry(1, b"a")], 0x100),
      unknown,
      start_elem(-1, 0, []),
      end_elem(-1, 0),
    ]),
  )
  assert_true(doc.elements().length() == 1, msg="unknown chunk skipped")
  assert_true(doc.elements().at(0).name == "a", msg="element still parsed")
}

///|
test "vendor-extended attribute layout is degraded" {
  // attributeSize=24 > 20：每条属性后多 4 字节，按步长跳过多余字节。
  let pad = b"\x00\x00\x00\x00"
  let doc = @axml.parse(
    xml_doc([
      pool(
        [utf8_entry(1, b"e"), utf8_entry(1, b"a"), utf8_entry(1, b"b")],
        0x100,
      ),
      start_elem_layout(-1, 0, 20, 24, [
        cat([attr(-1, 1, -1, 0x10, 7), pad]),
        cat([attr(-1, 2, -1, 0x10, 8), pad]),
      ]),
      end_elem(-1, 0),
    ]),
  )
  let attrs = doc.elements().at(0).attrs()
  assert_true(attrs.length() == 2, msg="both attributes recovered")
  assert_true(attrs.at(0).name == "a", msg="attr 0 name")
  assert_true(attrs.at(1).name == "b", msg="attr 1 name")
  assert_true(attrs.at(0).raw_data == 7U, msg="attr 0 data")
  assert_true(attrs.at(1).raw_data == 8U, msg="attr 1 data")
}

///|
test "string_at raises InvalidStringIndex for out-of-range indices" {
  let doc = @axml.parse(golden_utf8())
  let e1 = string_at_err(doc, 99)
  guard e1 is InvalidStringIndex(99) else {
    fail("expected InvalidStringIndex(99)")
  }
  let e2 = string_at_err(doc, -1)
  guard e2 is InvalidStringIndex(-1) else {
    fail("expected InvalidStringIndex(-1)")
  }
  let e3 = string_at_err(doc, 13)
  guard e3 is InvalidStringIndex(13) else {
    fail("expected InvalidStringIndex(13)")
  }
}

///|
test "node_at raises InvalidNodeIndex for out-of-range indices" {
  let doc = @axml.parse(golden_utf8())
  let e1 = node_at_err(doc, 4)
  guard e1 is InvalidNodeIndex(4) else { fail("expected InvalidNodeIndex(4)") }
  let e2 = node_at_err(doc, -1)
  guard e2 is InvalidNodeIndex(-1) else {
    fail("expected InvalidNodeIndex(-1)")
  }
}

///|
test "elements raises InvalidNodeIndex for a corrupt node table" {
  let doc : @axml.AxmlDoc = {
    pool: { encoding: Utf8, strings: [], styles: b"", },
    nodes: [],
    roots: [5],
    resource_map: [],
  }
  let e = elements_err(doc)
  guard e is InvalidNodeIndex(5) else { fail("expected InvalidNodeIndex(5)") }
}

///|
test "truncated input raises UnexpectedEof at the cut point" {
  let full = golden_utf8()
  // 外层头可读，首个 chunk 头读到一半：截断项起始于 12。
  let e1 = parse_err(cut(full, 12))
  guard e1 is UnexpectedEof(12) else { fail("expected UnexpectedEof(12)") }
  // chunk 类型可读、headerSize 读取越界：截断项起始于 10。
  let e2 = parse_err(cut(full, 10))
  guard e2 is UnexpectedEof(10) else { fail("expected UnexpectedEof(10)") }
  // 任意中段截断都必须带偏移报错而不是 panic。
  let e3 = parse_err(cut(full, full.length() / 2))
  guard e3 is UnexpectedEof(_) else {
    fail("expected UnexpectedEof for mid-document truncation")
  }
}

///|
test "bad outer chunk type raises BadChunkType" {
  let e = parse_err(cat([w2(0x0002), w2(8), w4(8)]))
  guard e is BadChunkType(0, found) else {
    fail("expected BadChunkType for non-RES_XML_TYPE magic")
  }
  assert_true(found == 2U, msg="found chunk type preserved")
}

///|
test "bad outer headerSize raises BadHeaderSize" {
  let e = parse_err(cat([w2(0x0003), w2(7), w4(8)]))
  guard e is BadHeaderSize(0, 7) else { fail("expected BadHeaderSize(0, 7)") }
}

///|
test "trailing bytes after the document raise BadHeaderSize" {
  let e = parse_err(cat([golden_utf8(), b"\x00"]))
  guard e is BadHeaderSize(4, _) else {
    fail("expected BadHeaderSize for trailing bytes")
  }
}

///|
test "bad string pool headerSize raises BadHeaderSize" {
  let bad_pool = pool_raw(0x100, 27, w4(0), utf8_entry(1, b"a"))
  let e = parse_err(xml_doc([bad_pool]))
  guard e is BadHeaderSize(8, 27) else {
    fail("expected BadHeaderSize(8, 27) for the string pool")
  }
}

///|
test "corrupt string pool raises BadStringPool" {
  // offset 表条目指向池外：错误定位于 offset 表（文档内偏移 36）。
  let bad_pool = pool_raw(0x100, 28, w4(100), utf8_entry(1, b"a"))
  let e = parse_err(xml_doc([bad_pool]))
  guard e is BadStringPool(36, _) else {
    fail("expected BadStringPool(36, _) for out-of-range string offset")
  }
}

///|
test "unknown string pool flags raise UnsupportedEncoding" {
  let bad_pool = pool_raw(0x200, 28, w4(0), utf8_entry(1, b"a"))
  let e = parse_err(xml_doc([bad_pool]))
  guard e is UnsupportedEncoding(_) else {
    fail("expected UnsupportedEncoding for unknown pool flags")
  }
}

///|
test "invalid string indices raise InvalidStringIndex" {
  // 元素名引用越界字符串。
  let e1 = parse_err(
    xml_doc([pool([utf8_entry(1, b"a")], 0x100), start_elem(-1, 99, [])]),
  )
  guard e1 is InvalidStringIndex(99) else {
    fail("expected InvalidStringIndex(99)")
  }
  // 元素名引用 -1（缺省值）不允许用于必需引用。
  let e2 = parse_err(
    xml_doc([pool([utf8_entry(1, b"a")], 0x100), start_elem(-1, -1, [])]),
  )
  guard e2 is InvalidStringIndex(-1) else {
    fail("expected InvalidStringIndex(-1)")
  }
  // 属性名引用越界字符串。
  let e3 = parse_err(
    xml_doc([
      pool([utf8_entry(1, b"a")], 0x100),
      start_elem(-1, 0, [attr(-1, 55, -1, 0x10, 1)]),
    ]),
  )
  guard e3 is InvalidStringIndex(55) else {
    fail("expected InvalidStringIndex(55)")
  }
}

///|
test "unbalanced element chunks raise BadChunkType" {
  // 没有开始标签的结束标签。
  let pool_chunk = pool([utf8_entry(1, b"a")], 0x100)
  let e1 = parse_err(xml_doc([pool_chunk, end_elem(-1, 0)]))
  guard e1 is BadChunkType(44, found) else {
    fail("expected BadChunkType at the stray end element")
  }
  assert_true(found == 0x0103U, msg="end-element chunk type reported")
  // 结束标签与栈顶元素名称不匹配。
  let e2 = parse_err(
    xml_doc([
      pool([utf8_entry(1, b"a"), utf8_entry(1, b"b")], 0x100),
      start_elem(-1, 0, []),
      end_elem(-1, 1),
    ]),
  )
  guard e2 is BadChunkType(_, 0x0103U) else {
    fail("expected BadChunkType for a mismatched end element")
  }
}

///|
test "unclosed elements raise UnexpectedEof at the end of input" {
  let data = xml_doc([pool([utf8_entry(1, b"a")], 0x100), start_elem(-1, 0, [])])
  let e = parse_err(data)
  guard e is UnexpectedEof(off) else {
    fail("expected UnexpectedEof for unclosed elements")
  }
  assert_true(off == data.length(), msg="EOF offset is the end of input")
}

///|
test "vendor variant attribute layout raises VendorVariant" {
  // attributeSize=12 < 20：无法安全定位 Res_value，按厂商变体报错。
  let e1 = parse_err(
    xml_doc([
      pool([utf8_entry(1, b"a")], 0x100),
      start_elem_layout(-1, 0, 20, 12, [attr(-1, 0, -1, 0x10, 1)]),
    ]),
  )
  guard e1 is VendorVariant(_) else {
    fail("expected VendorVariant for attributeSize < 20")
  }
  // attributeStart=16 < 20：属性区域侵入 attrExt 头。
  let e2 = parse_err(
    xml_doc([
      pool([utf8_entry(1, b"a")], 0x100),
      start_elem_layout(-1, 0, 16, 20, [attr(-1, 0, -1, 0x10, 1)]),
    ]),
  )
  guard e2 is VendorVariant(_) else {
    fail("expected VendorVariant for attributeStart < 20")
  }
}

///|
test "Res_value size other than 8 raises BadHeaderSize" {
  let e = parse_err(
    xml_doc([
      pool([utf8_entry(1, b"a")], 0x100),
      start_elem(-1, 0, [attr_value_size(-1, 0, -1, 7, 0x10, 1)]),
    ]),
  )
  guard e is BadHeaderSize(_, 7) else {
    fail("expected BadHeaderSize for Res_value.size != 8")
  }
}

///|
test "missing string pool raises BadStringPool" {
  let e = parse_err(xml_doc([]))
  guard e is BadStringPool(8, _) else {
    fail("expected BadStringPool for a document without a pool")
  }
}

///|
test "XML chunks before the string pool raise BadChunkType" {
  let e = parse_err(xml_doc([start_ns(0, 1)]))
  guard e is BadChunkType(8, found) else {
    fail("expected BadChunkType for XML chunks before the pool")
  }
  assert_true(found == 0x0100U, msg="start-namespace chunk type reported")
}

///|
test "a second string pool raises BadChunkType" {
  let e = parse_err(
    xml_doc([
      pool([utf8_entry(1, b"a")], 0x100),
      pool([utf8_entry(1, b"b")], 0x100),
    ]),
  )
  guard e is BadChunkType(_, 0x0001U) else {
    fail("expected BadChunkType for a duplicate string pool")
  }
}
