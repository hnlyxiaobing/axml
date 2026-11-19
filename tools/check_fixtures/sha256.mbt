///|
/// 最小 SHA-256（FIPS 180-4）实现：仅依赖 moonbitlang/core，
/// 供 T-W2-3 门禁在不依赖 OS 命令（certutil/sha256sum）的前提下校验登记哈希。

///|
/// SHA-256 初始哈希值（FIPS 180-4 §5.3.3）。
let h0_init : Array[UInt32] = [
  0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU, 0x510e527fU, 0x9b05688cU, 0x1f83d9abU,
  0x5be0cd19U,
]

///|
/// 轮常数 K（前 64 个素数的立方根小数部分前 32 位）。
let k_const : Array[UInt32] = [
  0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU, 0x59f111f1U, 0x923f82a4U,
  0xab1c5ed5U, 0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U, 0x72be5d74U, 0x80deb1feU,
  0x9bdc06a7U, 0xc19bf174U, 0xe49b69c1U, 0xefbe4786U, 0x0fc19dc6U, 0x240ca1ccU, 0x2de92c6fU,
  0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU, 0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U,
  0xc6e00bf3U, 0xd5a79147U, 0x06ca6351U, 0x14292967U, 0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU,
  0x53380d13U, 0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U, 0xa2bfe8a1U, 0xa81a664bU,
  0xc24b8b70U, 0xc76c51a3U, 0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U, 0x19a4c116U,
  0x1e376c08U, 0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU, 0x5b9cca4fU, 0x682e6ff3U,
  0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U, 0x90befffaU, 0xa4506cebU, 0xbef9a3f7U,
  0xc67178f2U,
]

///|
/// UInt32 循环右移。
fn rotr(x : UInt32, n : Int32) -> UInt32 {
  (x >> n) | (x << (32 - n))
}

///|
/// SHA-256 单块压缩（64 轮）。
fn sha256_block(h : Array[UInt32], block : Bytes, base : Int32) -> Unit {
  let w : Array[UInt32] = []
  for t in 0..<16 {
    let i = base + t * 4
    let v = (block[i].to_int().reinterpret_as_uint() << 24) |
      (block[i + 1].to_int().reinterpret_as_uint() << 16) |
      (block[i + 2].to_int().reinterpret_as_uint() << 8) |
      block[i + 3].to_int().reinterpret_as_uint()
    w.push(v)
  }
  for t in 16..<64 {
    let s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >> 3)
    let s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >> 10)
    w.push(w[t - 16] + s0 + w[t - 7] + s1)
  }
  let mut a = h[0]
  let mut b = h[1]
  let mut c = h[2]
  let mut d = h[3]
  let mut e = h[4]
  let mut f = h[5]
  let mut g = h[6]
  let mut hh = h[7]
  for t in 0..<64 {
    let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
    let ch = (e & f) ^ (e.reinterpret_as_int().lnot().reinterpret_as_uint() & g)
    let temp1 = hh + s1 + ch + k_const[t] + w[t]
    let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
    let maj = (a & b) ^ (a & c) ^ (b & c)
    let temp2 = s0 + maj
    hh = g
    g = f
    f = e
    e = d + temp1
    d = c
    c = b
    b = a
    a = temp1 + temp2
  }
  h[0] = h[0] + a
  h[1] = h[1] + b
  h[2] = h[2] + c
  h[3] = h[3] + d
  h[4] = h[4] + e
  h[5] = h[5] + f
  h[6] = h[6] + g
  h[7] = h[7] + hh
}

///|
/// SHA-256 摘要（64 位十六进制小写）。
fn sha256_hex(data : Bytes) -> String {
  let h : Array[UInt32] = []
  for v in h0_init {
    h.push(v)
  }
  let padded = sha256_padded(data)
  for off in 0..<(padded.length() / 64) {
    sha256_block(h, padded, off * 64)
  }
  let digits : Array[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let out = StringBuilder(capacity=64)
  for v in h {
    for shift in [28, 24, 20, 16, 12, 8, 4, 0] {
      let d = (v >> shift).reinterpret_as_int() & 0xF
      out.write_char(digits[d])
    }
  }
  out.to_string()
}

///|
/// SHA-256 消息填充：0x80 + 0x00... + 8 字节大端位长（总长 ≡ 0 mod 64）。
/// 位长按显式字节写出——UInt32 移位量按 mod 32 掩码，不能对 32 位值移 ≥32 位。
/// 门禁样本上限远小于 512MB，位长高 32 位恒为 0（超出即 fail-closed 拒绝）。
fn sha256_padded(data : Bytes) -> Bytes {
  let len = data.length()
  if len >= 0x20000000 {
    abort("sha256_padded: input too large")
  }
  let bit_len : UInt32 = (len * 8).reinterpret_as_uint()
  let padded_len = ((len + 8) / 64 + 1) * 64
  let buf : Array[Byte] = []
  for i in 0..<len {
    buf.push(data[i])
  }
  buf.push(b'\x80')
  for _ in 0..<(padded_len - len - 8 - 1) {
    buf.push(b'\x00')
  }
  // 大端 64 位位长：高 32 位为 0，低 32 位按字节拆出
  buf.push(b'\x00')
  buf.push(b'\x00')
  buf.push(b'\x00')
  buf.push(b'\x00')
  buf.push(((bit_len >> 24).reinterpret_as_int() & 0xFF).to_byte())
  buf.push(((bit_len >> 16).reinterpret_as_int() & 0xFF).to_byte())
  buf.push(((bit_len >> 8).reinterpret_as_int() & 0xFF).to_byte())
  buf.push((bit_len.reinterpret_as_int() & 0xFF).to_byte())
  Bytes::from_array(buf)
}

///|
/// 启动自测：FIPS 180-4 / NIST CAVP 已知向量，失败即中止（fail-closed）。
fn sha256_selftest() -> Unit {
  let vectors : Array[(String, String)] = [
    ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
    ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
    (
      "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
    ),
    (
      "The quick brown fox jumps over the lazy dog", "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592",
    ),
  ]
  for v in vectors {
    let (input, want) = v
    let got = sha256_hex(bytes_of_string(input))
    if got != want {
      println(
        "FAIL|SHA-256 自测失败|输入 \"\{input}\"|期望 \{want}|实际 \{got}",
      )
      @env.exit(1)
    }
  }
  // 多块输入（1000 × "a"，跨 16 个块）：期望值以 OS 独立实现
  // （PowerShell Get-FileHash）离线实测后登记于此
  let long_input : StringBuilder = StringBuilder(capacity=1000)
  for _ in 0..<1000 {
    long_input.write_string("a")
  }
  let got = sha256_hex(bytes_of_string(long_input.to_string()))
  if got != "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3" {
    println("FAIL|SHA-256 自测失败|输入 1000×'a'|实际 \{got}")
    @env.exit(1)
  }
}

///|
fn bytes_of_string(s : String) -> Bytes {
  // 门禁输入为 ASCII 结构行 + 文件名；统一按 UTF-8 编码
  @utf8.encode(s)
}
