///|
/// AXML 格式级回编（M8-1）：字符串池 + resource map + 空文档。
///
/// 往返律定义为 `parse(encode(doc))` 与规范化后的 `doc` 语义等价，不要求与
/// aapt2 产物逐字节一致。里程碑边界：元素/属性节点（M8-2）与字符串池样式块
/// 暂不支持，遇到时以 `VendorVariant` 显式报告，不静默丢信息。
///
/// - 参数：`doc` 来自 `parse` 或上层构造，`pool.strings` 为已解码字符串。
/// - 返回：完整 AXML 字节流（含 RES_XML_TYPE 外层头），编码为独立拷贝。
/// - 错误：节点表/根索引非空或样式块非空 → `VendorVariant`；字符串长度超过
///   UTF-8 池前缀上限（0x7FFF 字节）→ `BadStringPool`。
pub fn encode(doc : AxmlDoc) -> Bytes raise AxmlError {
  if doc.nodes.length() > 0 || doc.roots.length() > 0 {
    raise VendorVariant("encode: element nodes are not supported before M8-2")
  }
  if doc.pool.styles.length() > 0 {
    raise VendorVariant("encode: string pool styles are not supported")
  }
  let pool = encode_string_pool(doc.pool)
  let map = encode_resource_map(doc.resource_map)
  let header : Array[Byte] = []
  enc_u16(header, 0x0003)
  enc_u16(header, 8)
  enc_u32(header, 8 + pool.length() + map.length())
  enc_cat([Bytes::from_array(header), pool, map])
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
