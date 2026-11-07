///|
/// Internal byte-level decoding layer for the AXML parser (not exported).
///
/// Error mapping contract (mirrored by whitebox tests):
/// - `UnexpectedEof(offset)`：以 `offset` 开头的读取项被截断（输入结束或超出
///   所在 chunk 的边界）；
/// - `BadStringPool(offset, detail)`：字符串池结构或字符串内容在 `offset` 处
///   非法（偏移表越界、缺 NUL 终止符、非法 UTF-8/UTF-16 序列等）；
/// - `UnsupportedEncoding(detail)`：字符串池 flags 指示既非 UTF-8 也非
///   UTF-16 的编码（未知标志位）。
///
/// 所有偏移均为输入缓冲区中的绝对字节偏移。

///|
/// Little-endian 定宽读取器。`limit` 是可读区域的开区间上界（输入末尾或
/// 所在 chunk 的末尾），任何越界读取都以 `UnexpectedEof(offset)` 报告
/// 被截断项的起始偏移。
fn read_u8(data : Bytes, off : Int32, limit : Int32) -> Int32 raise AxmlError {
  if off < 0 || off + 1 > limit || off + 1 > data.length() {
    raise UnexpectedEof(off)
  }
  data.at(off).to_int()
}

///|
fn read_u16(data : Bytes, off : Int32, limit : Int32) -> Int32 raise AxmlError {
  if off < 0 || off + 2 > limit || off + 2 > data.length() {
    raise UnexpectedEof(off)
  }
  let b0 = data.at(off).to_int()
  let b1 = data.at(off + 1).to_int()
  b0 | (b1 << 8)
}

///|
fn read_u32(data : Bytes, off : Int32, limit : Int32) -> Int32 raise AxmlError {
  if off < 0 || off + 4 > limit || off + 4 > data.length() {
    raise UnexpectedEof(off)
  }
  let b0 = data.at(off).to_int()
  let b1 = data.at(off + 1).to_int()
  let b2 = data.at(off + 2).to_int()
  let b3 = data.at(off + 3).to_int()
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
fn read_u32u(
  data : Bytes,
  off : Int32,
  limit : Int32,
) -> UInt32 raise AxmlError {
  if off < 0 || off + 4 > limit || off + 4 > data.length() {
    raise UnexpectedEof(off)
  }
  data.at(off).to_uint() |
  (data.at(off + 1).to_uint() << 8) |
  (data.at(off + 2).to_uint() << 16) |
  (data.at(off + 3).to_uint() << 24)
}

///|
/// 字符串池长度前缀（8 位形式）：高位置位时由两字节组成。
/// 返回 (长度值, 后续位置)。
fn read_len8(
  data : Bytes,
  pos : Int32,
  limit : Int32,
) -> (Int32, Int32) raise AxmlError {
  let b = read_u8(data, pos, limit)
  if (b & 0x80) == 0 {
    return (b, pos + 1)
  }
  let b2 = read_u8(data, pos + 1, limit)
  (((b & 0x7F) << 8) | b2, pos + 2)
}

///|
/// 字符串池长度前缀（16 位形式）：高位置位时由两个 16 位字组成。
/// 返回 (长度值, 后续位置)。
fn read_len16(
  data : Bytes,
  pos : Int32,
  limit : Int32,
) -> (Int32, Int32) raise AxmlError {
  let u = read_u16(data, pos, limit)
  if (u & 0x8000) == 0 {
    return (u, pos + 2)
  }
  let u2 = read_u16(data, pos + 2, limit)
  (((u & 0x7FFF) << 16) | u2, pos + 4)
}

///|
/// 校验后的 Unicode 标量值转 `Char`；防御性兜底，正常路径在校验后不会触发。
fn scalar_to_char(cp : Int32, at : Int32) -> Char raise AxmlError {
  match cp.to_char() {
    Some(c) => c
    None => raise BadStringPool(at, "invalid Unicode scalar value \{cp}")
  }
}

///|
/// 严格 UTF-8 解码：`off` 起 `len` 字节。拒绝过长编码、代理项码点与超出
/// U+10FFFF 的码点；非法字节以 `BadStringPool(非法字节偏移, detail)` 报告。
fn decode_utf8(
  data : Bytes,
  off : Int32,
  len : Int32,
) -> String raise AxmlError {
  if off < 0 || len < 0 || off + len > data.length() {
    raise UnexpectedEof(off)
  }
  let builder = StringBuilder(size_hint=len)
  let end = off + len
  let mut i = off
  while i < end {
    let b0 = data.at(i).to_int()
    if b0 < 0x80 {
      builder.write_char(scalar_to_char(b0, i))
      i = i + 1
    } else if b0 >= 0xC2 && b0 < 0xE0 {
      if i + 2 > end {
        raise BadStringPool(i, "truncated UTF-8 sequence")
      }
      let b1 = data.at(i + 1).to_int()
      if b1 < 0x80 || b1 > 0xBF {
        raise BadStringPool(i + 1, "invalid UTF-8 continuation byte")
      }
      builder.write_char(scalar_to_char(((b0 & 0x1F) << 6) | (b1 & 0x3F), i))
      i = i + 2
    } else if b0 >= 0xE0 && b0 < 0xF0 {
      if i + 3 > end {
        raise BadStringPool(i, "truncated UTF-8 sequence")
      }
      let b1 = data.at(i + 1).to_int()
      let b2 = data.at(i + 2).to_int()
      if b1 < 0x80 || b1 > 0xBF {
        raise BadStringPool(i + 1, "invalid UTF-8 continuation byte")
      }
      if b2 < 0x80 || b2 > 0xBF {
        raise BadStringPool(i + 2, "invalid UTF-8 continuation byte")
      }
      let cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
      if cp < 0x800 {
        raise BadStringPool(i, "overlong UTF-8 encoding")
      }
      if cp >= 0xD800 && cp <= 0xDFFF {
        raise BadStringPool(i, "UTF-8 encoding of surrogate code point")
      }
      builder.write_char(scalar_to_char(cp, i))
      i = i + 3
    } else if b0 >= 0xF0 && b0 < 0xF5 {
      if i + 4 > end {
        raise BadStringPool(i, "truncated UTF-8 sequence")
      }
      let b1 = data.at(i + 1).to_int()
      let b2 = data.at(i + 2).to_int()
      let b3 = data.at(i + 3).to_int()
      if b1 < 0x80 || b1 > 0xBF {
        raise BadStringPool(i + 1, "invalid UTF-8 continuation byte")
      }
      if b2 < 0x80 || b2 > 0xBF {
        raise BadStringPool(i + 2, "invalid UTF-8 continuation byte")
      }
      if b3 < 0x80 || b3 > 0xBF {
        raise BadStringPool(i + 3, "invalid UTF-8 continuation byte")
      }
      let cp = ((b0 & 0x07) << 18) |
        ((b1 & 0x3F) << 12) |
        ((b2 & 0x3F) << 6) |
        (b3 & 0x3F)
      if cp < 0x10000 {
        raise BadStringPool(i, "overlong UTF-8 encoding")
      }
      if cp > 0x10FFFF {
        raise BadStringPool(i, "UTF-8 code point out of range")
      }
      builder.write_char(scalar_to_char(cp, i))
      i = i + 4
    } else {
      raise BadStringPool(i, "invalid UTF-8 lead byte")
    }
  }
  builder.to_string()
}

///|
/// UTF-16LE 解码：`off` 起 `units` 个 code unit。合并代理对；孤立代理以
/// `BadStringPool(代理位置, detail)` 报告。
fn decode_utf16(
  data : Bytes,
  off : Int32,
  units : Int32,
) -> String raise AxmlError {
  if off < 0 ||
    units < 0 ||
    off > data.length() ||
    units > (data.length() - off) / 2 {
    raise UnexpectedEof(off)
  }
  let builder = StringBuilder(size_hint=units)
  let mut i = 0
  while i < units {
    let base = off + 2 * i
    let u = data.at(base).to_int() | (data.at(base + 1).to_int() << 8)
    if u >= 0xD800 && u <= 0xDBFF {
      if i + 1 >= units {
        raise BadStringPool(base, "unpaired UTF-16 high surrogate")
      }
      let next = off + 2 * (i + 1)
      let lo = data.at(next).to_int() | (data.at(next + 1).to_int() << 8)
      if lo < 0xDC00 || lo > 0xDFFF {
        raise BadStringPool(next, "unpaired UTF-16 high surrogate")
      }
      let cp = 0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00)
      builder.write_char(scalar_to_char(cp, base))
      i = i + 2
    } else if u >= 0xDC00 && u <= 0xDFFF {
      raise BadStringPool(base, "unpaired UTF-16 low surrogate")
    } else {
      builder.write_char(scalar_to_char(u, base))
      i = i + 1
    }
  }
  builder.to_string()
}

///|
/// 解码一个 UTF-8 字符串池条目：字符数前缀 + 字节数前缀 + 载荷 + NUL 终止符。
/// `chunk_end` 为所在字符串池 chunk 的开区间末尾。
fn decode_utf8_entry(
  data : Bytes,
  entry : Int32,
  chunk_end : Int32,
) -> String raise AxmlError {
  let (_, p1) = read_len8(data, entry, chunk_end)
  let (byte_len, p2) = read_len8(data, p1, chunk_end)
  if p2 + byte_len + 1 > chunk_end {
    raise BadStringPool(entry, "string entry exceeds string-pool chunk")
  }
  let s = decode_utf8(data, p2, byte_len)
  if data.at(p2 + byte_len).to_int() != 0 {
    raise BadStringPool(p2 + byte_len, "string entry lacks NUL terminator")
  }
  s
}

///|
/// 解码一个 UTF-16 字符串池条目：unit 数前缀 + 载荷 + 16 位 NUL 终止符。
fn decode_utf16_entry(
  data : Bytes,
  entry : Int32,
  chunk_end : Int32,
) -> String raise AxmlError {
  let (units, p1) = read_len16(data, entry, chunk_end)
  if p1 + 2 > chunk_end || units > (chunk_end - p1 - 2) / 2 {
    raise BadStringPool(entry, "string entry exceeds string-pool chunk")
  }
  let s = decode_utf16(data, p1, units)
  if data.at(p1 + 2 * units).to_int() != 0 ||
    data.at(p1 + 2 * units + 1).to_int() != 0 {
    raise BadStringPool(p1 + 2 * units, "string entry lacks NUL terminator")
  }
  s
}

///|
/// 解析 RES_STRING_POOL_TYPE chunk（chunk 起始于 `off`，长度 `csize`）。
/// 校验：headerSize==28、flags 仅含 SORTED/UTF8 位、count 与 offset 表、
/// stringsStart/stylesStart 一致性、每个条目完整且带 NUL 终止符。
fn parse_string_pool(
  data : Bytes,
  off : Int32,
  csize : Int32,
) -> StringPool raise AxmlError {
  let limit = off + csize
  let string_count = read_u32(data, off + 8, limit)
  let style_count = read_u32(data, off + 12, limit)
  let flags = read_u32(data, off + 16, limit)
  let strings_start = read_u32(data, off + 20, limit)
  let styles_start = read_u32(data, off + 24, limit)
  // 已知标志位：SORTED_FLAG(1) 与 UTF8_FLAG(0x100)；其余位意味着未知编码。
  if flags < 0 || flags > 0x101 || (flags & 0x101) != flags {
    raise UnsupportedEncoding(
      "string pool at offset \{off} has unknown flags \{flags}",
    )
  }
  let encoding = if (flags & 0x100) == 0 { Utf16 } else { Utf8 }
  if string_count < 0 || style_count < 0 || string_count > (csize - 28) / 4 {
    raise BadStringPool(off, "string count \{string_count} exceeds chunk")
  }
  if style_count > (csize - 28 - 4 * string_count) / 4 {
    raise BadStringPool(off, "style count \{style_count} exceeds chunk")
  }
  let table_end = 28 + 4 * (string_count + style_count)
  if strings_start < table_end || strings_start > csize {
    raise BadStringPool(
      off,
      "stringsStart \{strings_start} is outside the string-pool chunk",
    )
  }
  if style_count == 0 {
    if styles_start != 0 {
      raise BadStringPool(
        off,
        "stylesStart \{styles_start} is set without style entries",
      )
    }
  } else if styles_start < strings_start || styles_start > csize {
    raise BadStringPool(
      off,
      "stylesStart \{styles_start} is outside the string-pool chunk",
    )
  }
  let strings : Array[String] = []
  let mut i = 0
  while i < string_count {
    let table_off = off + 28 + 4 * i
    let rel = read_u32(data, table_off, limit)
    if rel < 0 || rel >= csize - strings_start {
      raise BadStringPool(table_off, "string offset \{rel} is out of range")
    }
    let entry = off + strings_start + rel
    let s = if encoding is Utf8 {
      decode_utf8_entry(data, entry, limit)
    } else {
      decode_utf16_entry(data, entry, limit)
    }
    strings.push(s)
    i = i + 1
  }
  let styles : Bytes = if style_count == 0 {
    b""
  } else {
    Bytes::from_array(data[off + styles_start:limit].to_array())
  }
  { encoding, strings, styles, }
}

///|
/// `Res_value.dataType` 的支持子集映射；未知编码原样保留在 `Unknown` 中，
/// 便于上层降级而不丢失信息。
fn value_type_of(data_type : Int32) -> ValueType {
  match data_type {
    0x00 => Null
    0x01 => Reference
    0x02 => Attribute
    0x03 => String
    0x04 => Float
    0x05 => Dimension
    0x06 => Fraction
    0x10 => IntDec
    0x11 => IntHex
    0x12 => IntBoolean
    _ => Unknown(data_type)
  }
}

///|
/// 解析必须存在的字符串池引用；越界（含 -1）返回 `InvalidStringIndex`。
fn string_req(pool : StringPool, index : Int32) -> String raise AxmlError {
  if index < 0 || index >= pool.strings.length() {
    raise InvalidStringIndex(index)
  }
  pool.strings.at(index)
}

///|
/// 解析可选字符串池引用；`0xFFFFFFFF`（-1）表示不存在，其余越界值返回
/// `InvalidStringIndex`。
fn string_opt(pool : StringPool, index : Int32) -> String? raise AxmlError {
  if index == -1 {
    return None
  }
  if index < 0 || index >= pool.strings.length() {
    raise InvalidStringIndex(index)
  }
  Some(pool.strings.at(index))
}
