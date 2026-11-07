// Whitebox tests run within the package scope.
// Use them to validate internal helpers or invariants.
// Keep them focused; public behavior belongs in `_test.mbt`.

///|
/// 8 位字面量助手。
fn b(n : Int32) -> Byte {
  (n & 0xFF).to_byte()
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
/// UTF-8 字符串条目长度前缀（8 位形式，含两字节扩展形）。
fn len8(n : Int32) -> Bytes {
  if n < 0x80 {
    Bytes::from_array([b(n)])
  } else {
    Bytes::from_array([b(0x80 | (n >> 8)), b(n)])
  }
}

///|
/// UTF-16 字符串条目长度前缀（16 位形式，含两字扩展形）。
fn len16(n : Int32) -> Bytes {
  if n < 0x8000 {
    w2(n)
  } else {
    cat([w2(0x8000 | (n >> 16)), w2(n)])
  }
}

///|
/// 构造 UTF-8 字符串池条目。
fn utf8_entry(chars : Int32, payload : Bytes) -> Bytes {
  cat([len8(chars), len8(payload.length()), payload, b"\x00"])
}

///|
/// 构造 UTF-16 字符串池条目。
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
/// 原始字符串池 chunk 构造器（便于注入畸形字段）。
fn pool_chunk(
  string_count : Int32,
  style_count : Int32,
  flags : Int32,
  strings_start : Int32,
  styles_start : Int32,
  table : Bytes,
  str_data : Bytes,
  style_data : Bytes,
) -> Bytes {
  let body = cat([
    w4(string_count),
    w4(style_count),
    w4(flags),
    w4(strings_start),
    w4(styles_start),
    table,
    str_data,
    style_data,
  ])
  cat([w2(0x0001), w2(28), w4(8 + body.length()), body])
}

///|
/// 合法 UTF-8 字符串池 chunk。
fn utf8_pool(entries : Array[Bytes]) -> Bytes {
  let count = entries.length()
  let mut table = b""
  let mut str_data = b""
  for e in entries {
    table = table + w4(str_data.length())
    str_data = str_data + e
  }
  pool_chunk(count, 0, 0x100, 28 + 4 * count, 0, table, str_data, b"")
}

///|
fn read_u16_err(data : Bytes, off : Int32, limit : Int32) -> AxmlError raise {
  let result = Ok(read_u16(data, off, limit)) catch { err => Err(err) }
  match result {
    Ok(_) => fail("expected read_u16 to raise")
    Err(e) => e
  }
}

///|
fn read_u32_err(data : Bytes, off : Int32, limit : Int32) -> AxmlError raise {
  let result = Ok(read_u32(data, off, limit)) catch { err => Err(err) }
  match result {
    Ok(_) => fail("expected read_u32 to raise")
    Err(e) => e
  }
}

///|
fn decode_utf8_err(data : Bytes, off : Int32, len : Int32) -> AxmlError raise {
  let result = Ok(decode_utf8(data, off, len)) catch { err => Err(err) }
  match result {
    Ok(_) => fail("expected decode_utf8 to raise")
    Err(e) => e
  }
}

///|
fn decode_utf16_err(
  data : Bytes,
  off : Int32,
  units : Int32,
) -> AxmlError raise {
  let result = Ok(decode_utf16(data, off, units)) catch { err => Err(err) }
  match result {
    Ok(_) => fail("expected decode_utf16 to raise")
    Err(e) => e
  }
}

///|
fn decode_utf8_entry_err(
  data : Bytes,
  entry : Int32,
  chunk_end : Int32,
) -> AxmlError raise {
  let result = Ok(decode_utf8_entry(data, entry, chunk_end)) catch {
    err => Err(err)
  }
  match result {
    Ok(_) => fail("expected decode_utf8_entry to raise")
    Err(e) => e
  }
}

///|
fn decode_utf16_entry_err(
  data : Bytes,
  entry : Int32,
  chunk_end : Int32,
) -> AxmlError raise {
  let result = Ok(decode_utf16_entry(data, entry, chunk_end)) catch {
    err => Err(err)
  }
  match result {
    Ok(_) => fail("expected decode_utf16_entry to raise")
    Err(e) => e
  }
}

///|
fn parse_string_pool_err(
  data : Bytes,
  off : Int32,
  csize : Int32,
) -> AxmlError raise {
  let result = Ok(parse_string_pool(data, off, csize)) catch { err => Err(err) }
  match result {
    Ok(_) => fail("expected parse_string_pool to raise")
    Err(e) => e
  }
}

///|
test "readers report the offset of truncated fields" {
  let data = b"\x01\x02\x03\x04"
  assert_true(read_u16(data, 0, 4) == 0x0201, msg="read_u16 little-endian")
  assert_true(read_u32(data, 0, 4) == 0x04030201, msg="read_u32 little-endian")
  let e16 = read_u16_err(data, 3, 4)
  guard e16 is UnexpectedEof(off) else {
    fail("expected UnexpectedEof from read_u16")
  }
  assert_true(off == 3, msg="read_u16 truncation offset")
  let e32 = read_u32_err(data, 1, 4)
  guard e32 is UnexpectedEof(off2) else {
    fail("expected UnexpectedEof from read_u32")
  }
  assert_true(off2 == 1, msg="read_u32 truncation offset")
  let elim = read_u16_err(data, 0, 1)
  guard elim is UnexpectedEof(off3) else {
    fail("expected UnexpectedEof from limit bound")
  }
  assert_true(off3 == 0, msg="limit-bound offset")
}

///|
test "decode_utf8 decodes 1-4 byte sequences" {
  assert_true(
    decode_utf8(Bytes::from_array([b(0x41)]), 0, 1) == "A",
    msg="ASCII",
  )
  assert_true(
    decode_utf8(Bytes::from_array([b(0xC3), b(0xA9)]), 0, 2) == "é",
    msg="2-byte",
  )
  assert_true(
    decode_utf8(Bytes::from_array([b(0xE4), b(0xB8), b(0xAD)]), 0, 3) == "中",
    msg="3-byte",
  )
  assert_true(
    decode_utf8(Bytes::from_array([b(0xF0), b(0x9F), b(0x98), b(0x80)]), 0, 4) ==
    "😀",
    msg="4-byte",
  )
}

///|
test "decode_utf8 rejects overlong surrogate and out-of-range sequences" {
  // 过长 2 字节形（C0 80）。
  let e1 = decode_utf8_err(Bytes::from_array([b(0xC0), b(0x80)]), 0, 2)
  guard e1 is BadStringPool(0, _) else {
    fail("expected BadStringPool for overlong 2-byte form")
  }
  // 过长 3 字节形（E0 80 80）。
  let e2 = decode_utf8_err(Bytes::from_array([b(0xE0), b(0x80), b(0x80)]), 0, 3)
  guard e2 is BadStringPool(0, _) else {
    fail("expected BadStringPool for overlong 3-byte form")
  }
  // 代理项码点 U+D800 的 UTF-8 编码（ED A0 80）。
  let e3 = decode_utf8_err(Bytes::from_array([b(0xED), b(0xA0), b(0x80)]), 0, 3)
  guard e3 is BadStringPool(0, _) else {
    fail("expected BadStringPool for surrogate code point")
  }
  // U+110000 超出 Unicode 上限（F4 90 80 80）。
  let e4 = decode_utf8_err(
    Bytes::from_array([b(0xF4), b(0x90), b(0x80), b(0x80)]),
    0,
    4,
  )
  guard e4 is BadStringPool(0, _) else {
    fail("expected BadStringPool for out-of-range code point")
  }
  // 非法 lead（F5）。
  let e5 = decode_utf8_err(
    Bytes::from_array([b(0xF5), b(0x80), b(0x80), b(0x80)]),
    0,
    4,
  )
  guard e5 is BadStringPool(0, _) else {
    fail("expected BadStringPool for invalid lead byte")
  }
  // 孤立 continuation 字节（80）。
  let e6 = decode_utf8_err(Bytes::from_array([b(0x80)]), 0, 1)
  guard e6 is BadStringPool(0, _) else {
    fail("expected BadStringPool for lone continuation byte")
  }
}

///|
test "decode_utf8 rejects truncated sequences and bad continuations" {
  let e1 = decode_utf8_err(Bytes::from_array([b(0xE4), b(0xB8)]), 0, 2)
  guard e1 is BadStringPool(0, _) else {
    fail("expected BadStringPool for truncated 3-byte sequence")
  }
  let e2 = decode_utf8_err(Bytes::from_array([b(0xC3), b(0x41)]), 0, 2)
  guard e2 is BadStringPool(off, _) else {
    fail("expected BadStringPool for bad continuation byte")
  }
  assert_true(off == 1, msg="bad continuation offset")
  let e3 = decode_utf8_err(Bytes::from_array([b(0xF0), b(0x9F), b(0x98)]), 0, 3)
  guard e3 is BadStringPool(0, _) else {
    fail("expected BadStringPool for truncated 4-byte sequence")
  }
  // 请求长度越过输入末尾。
  let e4 = decode_utf8_err(Bytes::from_array([b(0x41)]), 0, 2)
  guard e4 is UnexpectedEof(0) else {
    fail("expected UnexpectedEof for length past input end")
  }
}

///|
test "decode_utf16 decodes BMP and surrogate pairs" {
  assert_true(
    decode_utf16(utf16_str([0x68, 0xE9]), 0, 2) == "hé",
    msg="BMP text",
  )
  assert_true(
    decode_utf16(utf16_str([0xD83D, 0xDE00]), 0, 2) == "😀",
    msg="surrogate pair",
  )
}

///|
test "decode_utf16 rejects unpaired surrogates" {
  // 高位代理后跟非低位代理：错误指向下一项。
  let e1 = decode_utf16_err(utf16_str([0xD83D, 0x0041]), 0, 2)
  guard e1 is BadStringPool(off, _) else {
    fail("expected BadStringPool for unpaired high surrogate")
  }
  assert_true(off == 2, msg="unpaired high surrogate offset")
  // 高位代理后无后续 unit。
  let e2 = decode_utf16_err(utf16_str([0xD83D]), 0, 1)
  guard e2 is BadStringPool(0, _) else {
    fail("expected BadStringPool for high surrogate at end")
  }
  // 孤立低位代理。
  let e3 = decode_utf16_err(utf16_str([0xDE00]), 0, 1)
  guard e3 is BadStringPool(0, _) else {
    fail("expected BadStringPool for lone low surrogate")
  }
}

///|
test "string entries accept extended length prefixes" {
  // 非规范两字节长度形：0x80 0x05 表示 char_len=5。
  let utf8_ext = b"\x80\x05\x02\x68\x69\x00"
  assert_true(
    decode_utf8_entry(utf8_ext, 0, utf8_ext.length()) == "hi",
    msg="UTF-8 extended length prefix",
  )
  // 两 unit 长度形：0x8000 0x0002 表示 units=2。
  let utf16_ext = cat([w2(0x8000), w2(0x0002), utf16_str([0x68, 0x69]), w2(0)])
  assert_true(
    decode_utf16_entry(utf16_ext, 0, utf16_ext.length()) == "hi",
    msg="UTF-16 extended length prefix",
  )
}

///|
test "string entries require NUL terminators" {
  // UTF-8：把终止符置为 0x01。
  let bad8 = b"\x02\x02\x68\x69\x01"
  let e8 = decode_utf8_entry_err(bad8, 0, bad8.length())
  guard e8 is BadStringPool(off, _) else {
    fail("expected BadStringPool for missing UTF-8 terminator")
  }
  assert_true(off == 4, msg="UTF-8 terminator offset")
  // UTF-16：把终止符置为 0x0001。
  let bad16 = cat([w2(0x0002), utf16_str([0x68, 0x69]), w2(0x0001)])
  let e16 = decode_utf16_entry_err(bad16, 0, bad16.length())
  guard e16 is BadStringPool(off2, _) else {
    fail("expected BadStringPool for missing UTF-16 terminator")
  }
  assert_true(off2 == 6, msg="UTF-16 terminator offset")
  // 条目载荷越过 chunk 末尾。
  let over = b"\x02\x10\x68\x69\x00"
  let eo = decode_utf8_entry_err(over, 0, over.length())
  guard eo is BadStringPool(0, _) else {
    fail("expected BadStringPool for entry past chunk end")
  }
}

///|
test "parse_string_pool decodes UTF-8 and UTF-16 pools" {
  let pool8_data = utf8_pool([
    utf8_entry(8, b"manifest"),
    utf8_entry(5, Bytes::from_array([b(0x68), b(0xC3), b(0xA9)])),
  ])
  let pool8 = parse_string_pool(pool8_data, 0, pool8_data.length())
  assert_true(pool8.encoding is Utf8, msg="UTF-8 encoding flag")
  assert_true(pool8.strings.length() == 2, msg="UTF-8 string count")
  assert_true(pool8.strings.at(0) == "manifest", msg="UTF-8 string 0")
  assert_true(pool8.strings.at(1) == "hé", msg="UTF-8 string 1")
  assert_true(pool8.styles.length() == 0, msg="no styles")
  let mut table = b""
  let mut str_data = b""
  let entry0 = utf16_entry(
    8,
    utf16_str([0x6D, 0x61, 0x6E, 0x69, 0x66, 0x65, 0x73, 0x74]),
  )
  let entry1 = utf16_entry(2, utf16_str([0xD83D, 0xDE00]))
  for e in [entry0, entry1] {
    table = table + w4(str_data.length())
    str_data = str_data + e
  }
  let pool16_data = pool_chunk(2, 0, 0, 36, 0, table, str_data, b"")
  let pool16 = parse_string_pool(pool16_data, 0, pool16_data.length())
  assert_true(pool16.encoding is Utf16, msg="UTF-16 default encoding")
  assert_true(pool16.strings.at(0) == "manifest", msg="UTF-16 string 0")
  assert_true(pool16.strings.at(1) == "😀", msg="UTF-16 string 1")
}

///|
test "parse_string_pool validates stringsStart" {
  // stringsStart 落在 offset 表之内。
  let entry = utf8_entry(1, b"a")
  let data = pool_chunk(1, 0, 0x100, 20, 0, w4(0), entry, b"")
  let e1 = parse_string_pool_err(data, 0, data.length())
  guard e1 is BadStringPool(0, _) else {
    fail("expected BadStringPool for stringsStart inside the offset table")
  }
  // stringsStart 超出 chunk。
  let data2 = pool_chunk(1, 0, 0x100, 1024, 0, w4(0), entry, b"")
  let e2 = parse_string_pool_err(data2, 0, data2.length())
  guard e2 is BadStringPool(0, _) else {
    fail("expected BadStringPool for stringsStart past the chunk")
  }
  // offset 表条目越界。
  let data3 = pool_chunk(1, 0, 0x100, 32, 0, w4(100), entry, b"")
  let e3 = parse_string_pool_err(data3, 0, data3.length())
  guard e3 is BadStringPool(off, _) else {
    fail("expected BadStringPool for out-of-range string offset")
  }
  assert_true(off == 28, msg="offset table entry position")
}

///|
test "parse_string_pool rejects unknown encoding flags" {
  let entry = utf8_entry(1, b"a")
  let mut table = b""
  let mut str_data = b""
  table = table + w4(0)
  str_data = str_data + entry
  let data = pool_chunk(1, 0, 0x200, 32, 0, table, str_data, b"")
  let e = parse_string_pool_err(data, 0, data.length())
  guard e is UnsupportedEncoding(_) else {
    fail("expected UnsupportedEncoding for unknown pool flags")
  }
}

///|
test "parse_string_pool validates stylesStart" {
  let entry = utf8_entry(1, b"a")
  let table = w4(0)
  // style_count=0 但 stylesStart 非 0。
  let data = pool_chunk(1, 0, 0x100, 32, 4, table, entry, b"")
  let e1 = parse_string_pool_err(data, 0, data.length())
  guard e1 is BadStringPool(0, _) else {
    fail("expected BadStringPool for stylesStart without styles")
  }
  // style_count>0 但 stylesStart 早于 stringsStart。
  let data2 = pool_chunk(1, 1, 0x100, 36, 28, cat([w4(0), w4(0)]), entry, b"")
  let e2 = parse_string_pool_err(data2, 0, data2.length())
  guard e2 is BadStringPool(0, _) else {
    fail("expected BadStringPool for stylesStart before stringsStart")
  }
}

///|
test "parse_string_pool preserves raw style bytes" {
  let entry = utf8_entry(1, b"a")
  let table = cat([w4(0), w4(0)])
  let style_data = b"\x01\x02\x03\x00"
  let data = pool_chunk(
    1,
    1,
    0x100,
    36,
    36 + entry.length(),
    table,
    entry,
    style_data,
  )
  let pool = parse_string_pool(data, 0, data.length())
  assert_true(pool.styles == style_data, msg="styles raw bytes preserved")
  assert_true(pool.strings.at(0) == "a", msg="string entry decoded")
}

///|
test "value_type_of maps known types and preserves unknown" {
  assert_true(value_type_of(0x00) is Null, msg="Null")
  assert_true(value_type_of(0x01) is Reference, msg="Reference")
  assert_true(value_type_of(0x03) is String, msg="String")
  assert_true(value_type_of(0x10) is IntDec, msg="IntDec")
  assert_true(value_type_of(0x12) is IntBoolean, msg="IntBoolean")
  assert_true(value_type_of(0x30) is Unknown(48), msg="Unknown preserved")
}
