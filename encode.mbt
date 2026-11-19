///|
/// AXML 格式级回编（M8-2）：字符串池 + resource map + 元素/属性/CDATA 节点。
///
/// 往返律定义为 `parse(encode(doc))` 与规范化后的 `doc` 语义等价，不要求与
/// aapt2 产物逐字节一致。命名空间声明 chunk 不做重建：`AxmlDoc` 只保留解析后
/// 的 ns URI，不保留前缀与声明位置，解析侧本就跳过这两类 chunk。
///
/// - 参数：`doc` 来自 `parse` 或上层构造，`pool.strings` 为已解码字符串。
/// - 返回：完整 AXML 字节流（含 RES_XML_TYPE 外层头），编码为独立拷贝。
/// - 错误：样式块非空、非元素/非 CDATA 节点 → `VendorVariant`；节点引用的
///   字符串不在池中或节点索引非法 → `BadStringPool` / `InvalidNodeIndex`；
///   字符串长度超过 UTF-8 池前缀上限（0x7FFF 字节）→ `BadStringPool`。
pub fn encode(doc : AxmlDoc) -> Bytes raise AxmlError {
  if doc.pool.styles.length() > 0 {
    raise VendorVariant("encode: string pool styles are not supported")
  }
  let visited : Array[Bool] = []
  for _ in 0..<doc.nodes.length() {
    visited.push(false)
  }
  let body : Array[Byte] = []
  for root in doc.roots {
    encode_node(doc, root, visited, body)
  }
  let mut i = 0
  while i < visited.length() {
    if !visited.at(i) {
      // 节点未被任何根/父节点引用：回编会静默丢信息，按非法节点表拒绝。
      raise InvalidNodeIndex(i)
    }
    i = i + 1
  }
  let pool = encode_string_pool(doc.pool)
  let map = encode_resource_map(doc.resource_map)
  let header : Array[Byte] = []
  enc_u16(header, 0x0003)
  enc_u16(header, 8)
  enc_u32(header, 8 + pool.length() + map.length() + body.length())
  enc_cat([Bytes::from_array(header), pool, map, Bytes::from_array(body)])
}

///|
/// 按解析顺序回编单个节点：元素先写 START_ELEMENT，递归子节点后写
/// END_ELEMENT；CDATA 直接写文本 chunk。重复访问（多父/环）按非法节点表拒绝。
fn encode_node(
  doc : AxmlDoc,
  index : Int32,
  visited : Array[Bool],
  out : Array[Byte],
) -> Unit raise AxmlError {
  if index < 0 || index >= doc.nodes.length() {
    raise InvalidNodeIndex(index)
  }
  if visited.at(index) {
    raise InvalidNodeIndex(index)
  }
  visited.set(index, true)
  let node = doc.nodes.at(index)
  match node.chunk {
    CData => encode_cdata(node, doc.pool, out)
    StartElement => {
      encode_start_element(node, doc.pool, out)
      for child in node.children {
        encode_node(doc, child, visited, out)
      }
      encode_end_element(node, doc.pool, out)
    }
    _ =>
      raise VendorVariant(
        "encode: node \{index} has unsupported chunk \{node.name}",
      )
  }
}

///|
/// RES_XML_START_ELEMENT_TYPE：node 头 + attributeExt(20) + 20 字节/属性。
fn encode_start_element(
  node : XmlNode,
  pool : StringPool,
  out : Array[Byte],
) -> Unit raise AxmlError {
  let attr_count = node.attributes.length()
  enc_u16(out, 0x0102)
  enc_u16(out, 16)
  enc_u32(out, 16 + 20 + 20 * attr_count)
  enc_u32(out, node.line)
  enc_u32(out, -1)
  enc_u32(out, enc_string_index(pool, node.ns))
  enc_u32(out, enc_string_index_required(pool, node.name))
  enc_u16(out, 20)
  enc_u16(out, 20)
  enc_u16(out, attr_count)
  enc_u16(out, 0)
  enc_u16(out, 0)
  enc_u16(out, 0)
  for a in node.attributes {
    enc_u32(out, enc_string_index(pool, a.ns))
    enc_u32(out, enc_string_index_required(pool, a.name))
    enc_u32(out, enc_string_index(pool, a.raw_value))
    enc_u16(out, 8)
    enc_u8(out, a.res0.to_int())
    enc_u8(out, enc_value_type(a.value_type))
    enc_u32(out, a.raw_data.reinterpret_as_int())
  }
}

///|
/// RES_XML_END_ELEMENT_TYPE：node 头 + ns/name 索引。
fn encode_end_element(
  node : XmlNode,
  pool : StringPool,
  out : Array[Byte],
) -> Unit raise AxmlError {
  enc_u16(out, 0x0103)
  enc_u16(out, 16)
  enc_u32(out, 24)
  enc_u32(out, node.line)
  enc_u32(out, -1)
  enc_u32(out, enc_string_index(pool, node.ns))
  enc_u32(out, enc_string_index_required(pool, node.name))
}

///|
/// RES_XML_CDATA_TYPE：node 头 + 文本字符串索引 + Res_value{String, data=索引}。
fn encode_cdata(
  node : XmlNode,
  pool : StringPool,
  out : Array[Byte],
) -> Unit raise AxmlError {
  let text = enc_string_index_required(pool, node.name)
  enc_u16(out, 0x0104)
  enc_u16(out, 16)
  enc_u32(out, 28)
  enc_u32(out, node.line)
  enc_u32(out, -1)
  enc_u32(out, text)
  enc_u16(out, 8)
  enc_u8(out, 0)
  enc_u8(out, 0x03)
  enc_u32(out, text)
}

///|
/// 可选字符串引用转池索引；`None` 写 -1（与解析侧 `0xFFFFFFFF` 约定一致）。
fn enc_string_index(pool : StringPool, s : String?) -> Int32 raise AxmlError {
  match s {
    None => -1
    Some(text) => enc_string_index_required(pool, text)
  }
}

///|
/// 在池中查找字符串的首个索引；缺失时拒绝回编，避免产生悬空引用。
fn enc_string_index_required(
  pool : StringPool,
  text : String,
) -> Int32 raise AxmlError {
  let mut i = 0
  while i < pool.strings.length() {
    if pool.strings.at(i) == text {
      return i
    }
    i = i + 1
  }
  raise BadStringPool(0, "encode: string \"\{text}\" is missing from the pool")
}

///|
/// `ValueType` 到 `Res_value.dataType` 字节的逆映射。
fn enc_value_type(v : ValueType) -> Int32 {
  match v {
    Null => 0x00
    Reference => 0x01
    Attribute => 0x02
    String => 0x03
    Float => 0x04
    Dimension => 0x05
    Fraction => 0x06
    IntDec => 0x10
    IntHex => 0x11
    IntBoolean => 0x12
    Unknown(n) => n
  }
}

///|
/// 重建 RES_STRING_POOL_TYPE chunk：保留原编码（UTF-8/UTF-16）与字符串顺序，
/// 不设置 SORTED 标志（本库不做排序）。
fn encode_string_pool(pool : StringPool) -> Bytes raise AxmlError {
  let offsets : Array[Int32] = []
  let data : Array[Byte] = []
  for s in pool.strings {
    offsets.push(data.length())
    if pool.encoding is Utf8 {
      enc_utf8_entry(s, data)
    } else {
      enc_utf16_entry(s, data)
    }
  }
  let count = pool.strings.length()
  let strings_start = 28 + 4 * count
  let out : Array[Byte] = []
  enc_u16(out, 0x0001)
  enc_u16(out, 28)
  enc_u32(out, strings_start + data.length())
  enc_u32(out, count)
  enc_u32(out, 0)
  enc_u32(out, if pool.encoding is Utf8 { 0x100 } else { 0 })
  enc_u32(out, strings_start)
  enc_u32(out, 0)
  for rel in offsets {
    enc_u32(out, rel)
  }
  for b in data {
    out.push(b)
  }
  Bytes::from_array(out)
}

///|
/// 重建 RES_XML_RESOURCE_MAP_TYPE chunk；空表直接省略该 chunk（与 aapt2 一致）。
fn encode_resource_map(ids : Array[UInt32]) -> Bytes {
  if ids.is_empty() {
    return b""
  }
  let out : Array[Byte] = []
  enc_u16(out, 0x0180)
  enc_u16(out, 8)
  enc_u32(out, 8 + 4 * ids.length())
  for id in ids {
    enc_u32(out, id.reinterpret_as_int())
  }
  Bytes::from_array(out)
}

///|
/// UTF-8 字符串池条目：UTF-16 unit 数前缀 + 字节数前缀 + 载荷 + NUL。
fn enc_utf8_entry(s : String, out : Array[Byte]) -> Unit raise AxmlError {
  let payload = enc_utf8_bytes(s)
  enc_len8(out, enc_utf16_unit_len(s))
  enc_len8(out, payload.length())
  for b in payload {
    out.push(b)
  }
  out.push((0x00).to_byte())
}

///|
/// UTF-16 字符串池条目：unit 数前缀 + UTF-16LE 载荷 + 16 位 NUL。
fn enc_utf16_entry(s : String, out : Array[Byte]) -> Unit {
  enc_len16(out, enc_utf16_unit_len(s))
  for c in s {
    let cp = c.to_int()
    if cp <= 0xFFFF {
      enc_u16(out, cp)
    } else {
      let v = cp - 0x10000
      enc_u16(out, 0xD800 + (v >> 10))
      enc_u16(out, 0xDC00 + (v & 0x3FF))
    }
  }
  enc_u16(out, 0)
}

///|
/// 字符串的 UTF-16 code unit 数（BMP 外码点计 2），即池条目前缀的计数值。
fn enc_utf16_unit_len(s : String) -> Int32 {
  let mut n = 0
  for c in s {
    if c.to_int() > 0xFFFF {
      n = n + 2
    } else {
      n = n + 1
    }
  }
  n
}

///|
/// 严格 UTF-8 编码（输入为合法 `Char`，不会产生代理项或过长编码）。
fn enc_utf8_bytes(s : String) -> Array[Byte] {
  let out : Array[Byte] = []
  for c in s {
    let cp = c.to_int()
    if cp < 0x80 {
      out.push(cp.to_byte())
    } else if cp < 0x800 {
      out.push((0xC0 | (cp >> 6)).to_byte())
      out.push((0x80 | (cp & 0x3F)).to_byte())
    } else if cp < 0x10000 {
      out.push((0xE0 | (cp >> 12)).to_byte())
      out.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      out.push((0x80 | (cp & 0x3F)).to_byte())
    } else {
      out.push((0xF0 | (cp >> 18)).to_byte())
      out.push((0x80 | ((cp >> 12) & 0x3F)).to_byte())
      out.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      out.push((0x80 | (cp & 0x3F)).to_byte())
    }
  }
  out
}

///|
/// UTF-8 池长度前缀：小于 0x80 单字节，否则两字节（上限 0x7FFF）。
fn enc_len8(out : Array[Byte], n : Int32) -> Unit raise AxmlError {
  if n < 0 || n > 0x7FFF {
    raise BadStringPool(
      0,
      "string length \{n} exceeds the UTF-8 pool prefix limit",
    )
  }
  if n < 0x80 {
    out.push(n.to_byte())
  } else {
    out.push((0x80 | (n >> 8)).to_byte())
    out.push((n & 0xFF).to_byte())
  }
}

///|
/// UTF-16 池长度前缀：小于 0x8000 单字，否则两字。
fn enc_len16(out : Array[Byte], n : Int32) -> Unit {
  if n < 0x8000 {
    enc_u16(out, n)
  } else {
    enc_u16(out, 0x8000 | (n >> 16))
    enc_u16(out, n & 0xFFFF)
  }
}

///|
fn enc_u8(out : Array[Byte], n : Int32) -> Unit {
  out.push((n & 0xFF).to_byte())
}

///|
fn enc_u16(out : Array[Byte], n : Int32) -> Unit {
  enc_u8(out, n)
  enc_u8(out, n >> 8)
}

///|
fn enc_u32(out : Array[Byte], n : Int32) -> Unit {
  enc_u8(out, n)
  enc_u8(out, n >> 8)
  enc_u8(out, n >> 16)
  enc_u8(out, n >> 24)
}

///|
/// 顺序拼接字节片段。
fn enc_cat(parts : Array[Bytes]) -> Bytes {
  let out : Array[Byte] = []
  for p in parts {
    for i in 0..<p.length() {
      out.push(p.at(i))
    }
  }
  Bytes::from_array(out)
}
