// Whitebox tests for the resources.arsc internal decoder (WP-1).
// 包内可见：字符串池/配置/locale 解包等内部实现逐项断言。
//
// 真实样本（永久内嵌，逐字节来自 framework-res.apk -> resources.arsc 的类型池
// chunk @298688，长度 488；SHA-256(整文件) =
// AA8BDA9CACF640E4BB7BD552AF4BF025D38EAEAF0C07CD04C5FBC15B3B8587B4；
// aapt2 dump resources 的 22 个 type 行与其 23 串类型名逐项一致，含占位名 "?22"）。

///|
/// 真实样本：framework-res.resources.arsc 的类型字符串池 chunk（UTF-16，23 串）。
// FIXTURE-BEGIN arsc/framework-res.type-pool.chunk
fn aw_fixture_fw_type_pool() -> Bytes {
  b"\x01\x00\x1c\x00\xe8\x01\x00\x00\x17\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x78\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x0c\x00\x00\x00\x14\x00\x00\x00\x22\x00\x00\x00\x32\x00\x00\x00\x40\x00\x00\x00\x4e\x00\x00\x00\x5c\x00\x00\x00\x70\x00\x00\x00\x80\x00\x00\x00\x8c\x00\x00\x00\xa0\x00\x00\x00\xbc\x00\x00\x00\xcc\x00\x00\x00\xde\x00\x00\x00\xf6\x00\x00\x00\x00\x01\x00\x00\x1e\x01\x00\x00\x2a\x01\x00\x00\x3e\x01\x00\x00\x4a\x01\x00\x00\x5c\x01\x00\x00\x66\x01\x00\x00\x04\x00\x61\x00\x74\x00\x74\x00\x72\x00\x00\x00\x02\x00\x69\x00\x64\x00\x00\x00\x05\x00\x73\x00\x74\x00\x79\x00\x6c\x00\x65\x00\x00\x00\x06\x00\x73\x00\x74\x00\x72\x00\x69\x00\x6e\x00\x67\x00\x00\x00\x05\x00\x64\x00\x69\x00\x6d\x00\x65\x00\x6e\x00\x00\x00\x05\x00\x63\x00\x6f\x00\x6c\x00\x6f\x00\x72\x00\x00\x00\x05\x00\x61\x00\x72\x00\x72\x00\x61\x00\x79\x00\x00\x00\x08\x00\x64\x00\x72\x00\x61\x00\x77\x00\x61\x00\x62\x00\x6c\x00\x65\x00\x00\x00\x06\x00\x6c\x00\x61\x00\x79\x00\x6f\x00\x75\x00\x74\x00\x00\x00\x04\x00\x61\x00\x6e\x00\x69\x00\x6d\x00\x00\x00\x08\x00\x61\x00\x6e\x00\x69\x00\x6d\x00\x61\x00\x74\x00\x6f\x00\x72\x00\x00\x00\x0c\x00\x69\x00\x6e\x00\x74\x00\x65\x00\x72\x00\x70\x00\x6f\x00\x6c\x00\x61\x00\x74\x00\x6f\x00\x72\x00\x00\x00\x06\x00\x6d\x00\x69\x00\x70\x00\x6d\x00\x61\x00\x70\x00\x00\x00\x07\x00\x69\x00\x6e\x00\x74\x00\x65\x00\x67\x00\x65\x00\x72\x00\x00\x00\x0a\x00\x74\x00\x72\x00\x61\x00\x6e\x00\x73\x00\x69\x00\x74\x00\x69\x00\x6f\x00\x6e\x00\x00\x00\x03\x00\x72\x00\x61\x00\x77\x00\x00\x00\x0d\x00\x5e\x00\x61\x00\x74\x00\x74\x00\x72\x00\x2d\x00\x70\x00\x72\x00\x69\x00\x76\x00\x61\x00\x74\x00\x65\x00\x00\x00\x04\x00\x62\x00\x6f\x00\x6f\x00\x6c\x00\x00\x00\x08\x00\x66\x00\x72\x00\x61\x00\x63\x00\x74\x00\x69\x00\x6f\x00\x6e\x00\x00\x00\x04\x00\x6d\x00\x65\x00\x6e\x00\x75\x00\x00\x00\x07\x00\x70\x00\x6c\x00\x75\x00\x72\x00\x61\x00\x6c\x00\x73\x00\x00\x00\x03\x00\x3f\x00\x32\x00\x32\x00\x00\x00\x03\x00\x78\x00\x6d\x00\x6c\x00\x00\x00"
}
// FIXTURE-END arsc/framework-res.type-pool.chunk

///|
/// 小端 16 位字。
fn aw_w2(n : Int32) -> Bytes {
  Bytes::from_array([(n & 255).to_byte(), ((n >> 8) & 255).to_byte()])
}

///|
/// 小端 32 位字。
fn aw_w4(n : Int32) -> Bytes {
  Bytes::from_array([
    (n & 255).to_byte(),
    ((n >> 8) & 255).to_byte(),
    ((n >> 16) & 255).to_byte(),
    ((n >> 24) & 255).to_byte(),
  ])
}

///|
/// 字节串拼接。
fn aw_cat(parts : Array[Bytes]) -> Bytes {
  let mut acc = b""
  for p in parts {
    acc = acc + p
  }
  acc
}

///|
/// 真实样本：framework-res 类型池（UTF-16，23 串）解码逐项断言。
test "arsc wb: framework-res 类型池真实字节" {
  let data = aw_fixture_fw_type_pool()
  assert_eq(data.length(), 488, msg="类型池 chunk 488 字节")
  let pool = arsc_pool(data, 0, data.length())
  assert_true(pool.encoding is Utf16, msg="UTF-16 池")
  assert_eq(pool.strings.length(), 23, msg="23 串")
  assert_eq(pool.strings.at(0), "attr", msg="idx0")
  assert_eq(pool.strings.at(3), "string", msg="idx3")
  assert_eq(pool.strings.at(10), "animator", msg="idx10")
  assert_eq(
    pool.strings.at(16),
    "^attr-private",
    msg="idx16 私有 attr 类型名",
  )
  assert_eq(pool.strings.at(20), "plurals", msg="idx20")
  assert_eq(
    pool.strings.at(21),
    "?22",
    msg="idx21 占位类型名（真实字节）",
  )
  assert_eq(pool.strings.at(22), "xml", msg="idx22")
}

///|
/// `AxmlError` → `ArscError` 映射契约。
test "arsc wb: axml_err 映射" {
  assert_true(axml_err(UnexpectedEof(5)) is Eof(5), msg="Eof")
  assert_true(axml_err(BadChunkType(6, 7U)) is BadChunk(6, 7), msg="BadChunk")
  assert_true(axml_err(BadHeaderSize(8, 9)) is BadHeader(8, 9), msg="BadHeader")
  assert_true(
    axml_err(BadStringPool(10, "x")) is BadPool(10, "x"),
    msg="BadPool",
  )
  assert_true(axml_err(InvalidStringIndex(11)) is BadIndex(11), msg="BadIndex")
}

///|
/// locale 解包（AOSP unpackLanguageOrRegion）：两位 ASCII 与 15 位压缩码。
test "arsc wb: locale 解包" {
  assert_eq(unpack_locale(b"\x65\x6e", 0, 2, false), "en", msg="ASCII 语言")
  assert_eq(unpack_locale(b"\x43\x4e", 0, 2, true), "CN", msg="ASCII 地区")
  assert_eq(
    unpack_locale(b"\x9d\xc5", 0, 2, false),
    "eng",
    msg="压缩三字母语言",
  )
  assert_eq(
    unpack_locale(b"\xa8\x45", 0, 2, true),
    "419",
    msg="压缩 UN M.49 地区",
  )
  assert_eq(unpack_locale(b"\x00\x00", 0, 2, false), "", msg="any")
  assert_eq(
    unpack_locale(b"\x00\x65", 0, 2, false),
    "",
    msg="高字节为零不输出",
  )
}

///|
/// `ResTable_config` 字段解码（64 字节新式 + 28 字节旧式 + 压缩 locale）。
test "arsc wb: config 字段解码" {
  let cfg64 = aw_cat([
    aw_w4(64),
    aw_w2(310),
    aw_w2(26),
    b"\x9d\xc5\x43\x4e",
    b"\x02\x00",
    aw_w2(480),
    b"\x00\x00\x00\x00",
    aw_w2(0),
    aw_w2(0),
    aw_w2(35),
    aw_w2(0),
    b"\x00\x00",
    aw_w2(600),
    aw_w2(0),
    aw_w2(0),
    b"\x00\x00\x00\x00",
    b"\x00\x00\x00\x00",
    b"\x00\x00\x00\x00",
    b"\x00\x00\x00\x00",
    b"\x00\x00\x00\x00",
    b"\x00\x00\x00\x00",
    b"\x00\x00\x00\x00",
  ])
  assert_eq(cfg64.length(), 64, msg="64 字节")
  let cfg = parse_config(cfg64, 0, 64)
  assert_eq(cfg.size, 64, msg="size")
  assert_eq(cfg.mcc, 310, msg="mcc")
  assert_eq(cfg.mnc, 26, msg="mnc")
  assert_eq(cfg.language, "eng", msg="压缩语言")
  assert_eq(cfg.country, "CN", msg="地区")
  assert_eq(cfg.orientation, 2, msg="orientation")
  assert_eq(cfg.density, 480, msg="density")
  assert_eq(cfg.sdk_version, 35, msg="sdk")
  assert_eq(cfg.smallest_screen_width_dp, 600, msg="swdp")
  assert_true(!cfg.is_default(), msg="非默认配置")
  // 28 字节旧式 config（Android 1.6 时代布局）。
  let cfg28 = aw_cat([
    aw_w4(28),
    aw_w2(0),
    aw_w2(0),
    b"\x00\x00\x00\x00",
    b"\x00\x00\x00\x00",
    b"\x00\x00\x00\x00",
    aw_w2(0),
    aw_w2(0),
    aw_w2(21),
    aw_w2(0),
  ])
  assert_eq(cfg28.length(), 28, msg="28 字节")
  let old = parse_config(cfg28, 0, 28)
  assert_eq(old.size, 28, msg="旧式 size")
  assert_eq(old.sdk_version, 21, msg="旧式 sdk")
  assert_eq(old.smallest_screen_width_dp, 0, msg="旧式无 swdp 字段")
  assert_true(!old.is_default(), msg="sdk=21 非默认配置")
}

///|
/// `Res_value.dataType` 全映射。
test "arsc wb: res_data_type_of 全映射" {
  assert_true(res_data_type_of(0x00) is Null, msg="0x00")
  assert_true(res_data_type_of(0x01) is Reference, msg="0x01")
  assert_true(res_data_type_of(0x02) is Attribute, msg="0x02")
  assert_true(res_data_type_of(0x03) is String, msg="0x03")
  assert_true(res_data_type_of(0x04) is Float, msg="0x04")
  assert_true(res_data_type_of(0x05) is Dimension, msg="0x05")
  assert_true(res_data_type_of(0x06) is Fraction, msg="0x06")
  assert_true(res_data_type_of(0x07) is DynamicReference, msg="0x07")
  assert_true(res_data_type_of(0x08) is DynamicAttribute, msg="0x08")
  assert_true(res_data_type_of(0x10) is IntDec, msg="0x10")
  assert_true(res_data_type_of(0x11) is IntHex, msg="0x11")
  assert_true(res_data_type_of(0x12) is IntBoolean, msg="0x12")
  assert_true(res_data_type_of(0x1c) is IntColorArgb8, msg="0x1c")
  assert_true(res_data_type_of(0x1d) is IntColorRgb8, msg="0x1d")
  assert_true(res_data_type_of(0x1e) is IntColorArgb4, msg="0x1e")
  assert_true(res_data_type_of(0x1f) is IntColorRgb4, msg="0x1f")
  assert_true(res_data_type_of(0x2a) is Unknown(42), msg="未知类型保留")
}

///|
/// 6 位定点小数（aapt2 `%f` 风格）边界。
test "arsc wb: fixed6 渲染" {
  assert_eq(fixed6(1.5), "1.500000", msg="1.5")
  assert_eq(fixed6(0.0 - 2.25), "-2.250000", msg="负数")
  assert_eq(fixed6(0.0), "0.000000", msg="零")
  assert_eq(fixed6(48.0), "48.000000", msg="整数")
}
