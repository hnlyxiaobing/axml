///|
/// L1：截断 / 位翻转 / 固定种子变异（测试系统设计 §4/§10）。
///
/// 口径（fail-closed）：
/// - 截断扫描：全部入库 fixture（edge-* 派生物本身即截断家族，由 base 样本
///   扫描覆盖）+ W8 `encode` / W9 `encode_arsc` 产物——大样本按素数步长抽样，
///   chunk 头 / 池偏移表 / entry 偏移表 / entriesStart 边界**必采**，尾部 8 字节
///   必采；断言只允许声明错误（AxmlError/ArscError）或解析成功，不允许 panic。
/// - 单 bit 翻转：chunk type/headerSize/size、stringCount、attributeCount、
///   entry offset、`Res_value.size`；断言「报声明错误 或 可观察输出与翻转前不同」。
/// - ≥1000 固定种子变异体（替换/插入/删除，xorshift32 确定性）：断言不 panic
///   且错误属于声明集合。

///|
/// xorshift32：固定种子确定性 PRNG（单元素数组承载可变状态）。
fn fz_xorshift(state : Array[UInt32]) -> UInt32 {
  let mut x = state[0]
  x = x ^ (x << 13)
  x = x ^ (x >> 17)
  x = x ^ (x << 5)
  state[0] = x
  x
}

///|
/// AXML 可观察输出指纹（池字符串 + 资源表 + 节点/属性明细）。
fn fz_axml_fp(doc : @axml.AxmlDoc) -> String {
  let sb = StringBuilder(capacity=128)
  sb.write_string("pool[")
  for s in doc.pool.strings {
    sb.write_string(s)
    sb.write_string(",")
  }
  sb.write_string("]map[")
  for id in doc.resource_map {
    sb.write_string("\{id},")
  }
  sb.write_string("]nodes=")
  sb.write_string("\{doc.nodes.length()}")
  for n in doc.nodes {
    sb.write_string("|\{n.name}<")
    for a in n.attributes {
      sb.write_string("\{a.name}:\{a.raw_data},")
    }
    sb.write_string(">c\{n.children.length()}")
  }
  sb.to_string()
}

///|
/// ARSC 可观察输出指纹（包/类型/条目名/条目值/配置摘要 + 全局池）。
fn fz_arsc_fp(t : @axml.ResTable) -> String {
  let sb = StringBuilder(capacity=128)
  sb.write_string("pkgs=\{t.packages.length()}pool[")
  for s in t.global_pool.strings {
    sb.write_string(s)
    sb.write_string(",")
  }
  sb.write_string("]")
  for p in t.packages {
    sb.write_string("P\{p.id}:\{p.name}:tid\{p.type_id_offset}")
    for spec in p.types {
      sb.write_string("T\{spec.id}n\{spec.entry_count}")
      for cfg in spec.configs {
        sb.write_string(
          "C\{cfg.config.language},\{cfg.config.country},\{cfg.config.density},e\{cfg.entries.length()}",
        )
        for e in cfg.entries {
          match e {
            None => sb.write_string("_")
            Some(en) => {
              sb.write_string("\{en.key_name}")
              match en.value {
                Simple(v) =>
                  sb.write_string("S\{fz_dt_code(v.data_type)}:\{v.data};")
                Complex(bag) =>
                  sb.write_string("B\{bag.parent}:\{bag.maps.length()};")
              }
            }
          }
        }
      }
    }
  }
  sb.to_string()
}

///|
/// `ResDataType` → 稳定短码（指纹用；与线上 dataType 字节同值）。
fn fz_dt_code(dt : @axml.ResDataType) -> Int32 {
  match dt {
    Null => 0x00
    Reference => 0x01
    Attribute => 0x02
    String => 0x03
    Float => 0x04
    Dimension => 0x05
    Fraction => 0x06
    DynamicReference => 0x07
    DynamicAttribute => 0x08
    IntDec => 0x10
    IntHex => 0x11
    IntBoolean => 0x12
    IntColorArgb8 => 0x1c
    IntColorRgb8 => 0x1d
    IntColorArgb4 => 0x1e
    IntColorRgb4 => 0x1f
    Unknown(n) => n
  }
}

///|
/// 解析 AXML：成功返回 Some(指纹)，声明错误返回 None。
/// AXML 解析只可能抛 `AxmlError`（checked error 静态保证），故捕获即声明集合；
/// panic/abort 不经此路径，直接使测试失败。
fn fz_axml_parse(b : Bytes) -> String? {
  Some(fz_axml_fp(@axml.parse(b))) catch {
    _ => None
  }
}

///|
/// 解析 ARSC：成功返回 Some(指纹)，声明错误返回 None。
/// ARSC 解析只可能抛 `ArscError`（checked error 静态保证）。
fn fz_arsc_parse(b : Bytes) -> String? {
  Some(fz_arsc_fp(@axml.parse_arsc(b))) catch {
    _ => None
  }
}

///|
/// 无符号 u16 读取（越界返回 -1，防御式）。
fn fz_u16at(b : Bytes, off : Int32) -> Int32 {
  if off < 0 || off + 2 > b.length() {
    return -1
  }
  b[off].to_int() | (b[off + 1].to_int() << 8)
}

///|
/// 无符号 u32 读取（越界返回 -1，防御式）。
fn fz_u32at(b : Bytes, off : Int32) -> Int32 {
  if off < 0 || off + 4 > b.length() {
    return -1
  }
  b[off].to_int() |
  (b[off + 1].to_int() << 8) |
  (b[off + 2].to_int() << 16) |
  (b[off + 3].to_int() << 24)
}

///|
/// 收集截断扫描采样点：0..16 全采 + 步长抽样 + chunk/池/entry 表边界必采 +
/// 尾部 8 字节必采。`is_arsc` 切换外层头长与 type chunk 解读。
fn fz_samples(b : Bytes, is_arsc : Bool, stride : Int32) -> Array[Int32] {
  let out : Array[Int32] = []
  fn add(off : Int32) -> Unit {
    if off >= 0 && off <= b.length() && !out.contains(off) {
      out.push(off)
    }
  }

  let head = if is_arsc { 12 } else { 8 }
  for i in 0..<16 {
    add(i)
  }
  let mut off = head
  while off + 8 <= b.length() {
    let header_size = fz_u16at(b, off + 2)
    let size = fz_u32at(b, off + 4)
    let ctype = fz_u16at(b, off)
    add(off)
    add(off + header_size)
    add(off + size)
    if ctype == 0x0001 {
      // 字符串池：headerSize / 偏移表尾 / 字符串区起点
      let strings_count = fz_u32at(b, off + 16)
      let strings_start = fz_u32at(b, off + 20)
      add(off + header_size)
      add(off + header_size + 4 * strings_count)
      add(off + strings_start)
    }
    if !is_arsc && ctype == 0x0102 {
      // START_ELEMENT：属性计数与属性区边界
      let attr_count = fz_u16at(b, off + 24)
      add(off + header_size + 20 * attr_count)
    }
    if is_arsc && ctype == 0x0201 {
      // ResTable_type：entry 偏移表尾 + entriesStart
      let entry_count = fz_u32at(b, off + 12)
      let entries_start = fz_u32at(b, off + 16)
      add(off + header_size + 4 * entry_count)
      add(off + entries_start)
    }
    if size <= 0 {
      break
    }
    off = off + size
  }
  // 步长抽样（素数步长，避免只命中对齐位置）
  let mut i = 0
  while i < b.length() {
    add(i)
    i = i + stride
  }
  // 尾部 8 字节必采
  let n = b.length()
  for k in 1..<=8 {
    add(n - k)
  }
  add(n)
  out
}

///|
/// L1-1：全前缀截断扫描（抽样 + 结构边界必采；含全部入库 fixture 与
/// W8/W9 编码产物）。断言：只允许声明错误或成功，不允许 panic。
test "L1: 全前缀截断扫描（抽样 + 边界必采）" {
  let fixtures : Array[(String, Bytes, Bool, Int32)] = [
    ("base.AndroidManifest.xml", fixture_base_manifest(), false, 7),
    ("tvshell-debug.AndroidManifest.xml", fixture_tvshell_manifest(), false, 7),
    (
      "fx-multidex.AndroidManifest.xml",
      fixture_fx_multidex_manifest(),
      false,
      7,
    ),
    (
      "framework-res.AndroidManifest.xml",
      fixture_framework_res_manifest(),
      false,
      97,
    ),
    ("fx-config.AndroidManifest.xml", fixture_fx_config_manifest(), false, 1),
    ("base.resources.arsc", fixture_base_arsc(), true, 1),
    ("tvshell-debug.resources.arsc", fixture_tvshell_arsc(), true, 1),
    ("fx-multidex.resources.arsc", fixture_fx_multidex_arsc(), true, 7),
    ("fx-config.resources.arsc", fixture_fx_config_arsc(), true, 1),
  ]
  let mut cases = 0
  for f in fixtures {
    let (name, bytes, is_arsc, stride) = f
    for off in fz_samples(bytes, is_arsc, stride) {
      let prefix = fx_cut(bytes, off)
      let _ = if is_arsc {
        fz_arsc_parse(prefix)
      } else {
        fz_axml_parse(prefix)
      }
      cases = cases + 1
    }
    println("L1 truncation \{name}: samples so far=\{cases}")
  }
  assert_true(
    cases > 2000,
    msg="截断扫描样本量应 > 2000（实测 \{cases}）",
  )
}

///|
/// L1-4：W8 `encode` / W9 `encode_arsc` 产物纳入截断扫描。
test "L1: W8/W9 编码产物截断扫描" {
  let w8 = @axml.encode(@axml.parse(fixture_fx_multidex_manifest())) catch {
    _ => fail("W8 encode 应成功")
  }
  let w9 = @axml.encode_arsc(@axml.parse_arsc(fixture_fx_multidex_arsc())) catch {
    _ => fail("W9 encode_arsc 应成功")
  }
  let mut cases = 0
  for off in fz_samples(w8, false, 13) {
    let _ = fz_axml_parse(fx_cut(w8, off))
    cases = cases + 1
  }
  for off in fz_samples(w9, true, 13) {
    let _ = fz_arsc_parse(fx_cut(w9, off))
    cases = cases + 1
  }
  println("L1 truncation w8/w9 products: cases=\{cases}")
  assert_true(
    cases > 100,
    msg="W8/W9 产物扫描样本量应 > 100（实测 \{cases}）",
  )
}

///|
/// L1-2：单 bit 翻转（结构关键字段）——断言「报声明错误 或 输出与翻转前不同」。
test "L1: 单 bit 翻转关键字段" {
  let manifest = fixture_fx_multidex_manifest()
  let arsc = fixture_fx_multidex_arsc()
  let base_axml = fz_axml_parse(manifest)
  let base_arsc = fz_arsc_parse(arsc)
  assert_true(base_axml is Some(_), msg="翻转前 manifest 应可解析")
  assert_true(base_arsc is Some(_), msg="翻转前 arsc 应可解析")
  // —— AXML 目标字段（fx-multidex 清单布局防御式读取）——
  let axml_targets : Array[Int32] = [0, 1, 2, 3, 4, 5, 6, 7]
  // 字符串池 stringCount（池 chunk 起于 8，字段在 chunk+8 → 绝对 16）
  for k in 0..<4 {
    axml_targets.push(16 + k)
  }
  // 首个 START_ELEMENT 的 attributeCount
  let mut elem_off = 8
  while elem_off + 8 <= manifest.length() {
    let ctype = fz_u16at(manifest, elem_off)
    let csize = fz_u32at(manifest, elem_off + 4)
    if ctype == 0x0102 {
      for k in 0..<2 {
        axml_targets.push(elem_off + 24 + k)
      }
      break
    }
    if csize <= 0 {
      break
    }
    elem_off = elem_off + csize
  }
  // —— ARSC 目标字段 ——
  let arsc_targets : Array[Int32] = [0, 1, 2, 3, 4, 5, 6, 7]
  // Res_value.size 单列：size=8 时仅 bit3（8→0，触发 BadHeader）可观察
  let value_size_targets : Array[Int32] = []
  // 全局池 stringCount（池 chunk 起于 12，字段在 chunk+8 → 绝对 20）
  for k in 0..<4 {
    arsc_targets.push(20 + k)
  }
  // type chunk 嵌套在 package chunk 内：先入包再遍历其子 chunk
  let mut pkg_off = 12
  while pkg_off + 8 <= arsc.length() {
    let ptype = fz_u16at(arsc, pkg_off)
    let psize = fz_u32at(arsc, pkg_off + 4)
    if ptype == 0x0200 {
      let phsize = fz_u16at(arsc, pkg_off + 2)
      let mut c_off = pkg_off + phsize
      while c_off + 8 <= pkg_off + psize && c_off + 8 <= arsc.length() {
        let ctype = fz_u16at(arsc, c_off)
        let csize2 = fz_u32at(arsc, c_off + 4)
        if ctype == 0x0201 {
          let hsize = fz_u16at(arsc, c_off + 2)
          // type entryCount
          for k in 0..<4 {
            arsc_targets.push(c_off + 12 + k)
          }
          // entry offset 表首槽
          for k in 0..<4 {
            arsc_targets.push(c_off + hsize + k)
          }
          // 首个 Res_value.size（低位字节；解析侧按 AOSP 语义「size>=8 即接受，
          // 多余字节忽略」——size=8 时仅 bit3（8→0）可观察，bit0-2/4-7 为
          // 文档化良性翻转，不纳入断言）
          let entries_start = fz_u32at(arsc, c_off + 16)
          value_size_targets.push(c_off + entries_start + 8)
        }
        if ctype == 0x0202 {
          // typeSpec entryCount
          for k in 0..<4 {
            arsc_targets.push(c_off + 12 + k)
          }
        }
        if csize2 <= 0 {
          break
        }
        c_off = c_off + csize2
      }
      break
    }
    if psize <= 0 {
      break
    }
    pkg_off = pkg_off + psize
  }
  // —— 逐 bit 翻转断言 ——
  let mut flips = 0
  for off in axml_targets {
    if off < 0 || off >= manifest.length() {
      continue
    }
    for bit in 0..<8 {
      let mutated = fx_mut(
        manifest,
        off,
        (manifest[off].to_int() ^ (1 << bit)).to_byte(),
      )
      let got = fz_axml_parse(mutated)
      let changed = match (base_axml, got) {
        (Some(a), Some(b2)) => a != b2
        (Some(_), None) => true
        (None, _) => true
      }
      assert_true(
        changed,
        msg="AXML bit 翻转 off=\{off} bit=\{bit} 后输出应不同或报错",
      )
      flips = flips + 1
    }
  }
  for off in arsc_targets {
    if off < 0 || off >= arsc.length() {
      continue
    }
    for bit in 0..<8 {
      let mutated = fx_mut(
        arsc,
        off,
        (arsc[off].to_int() ^ (1 << bit)).to_byte(),
      )
      let got = fz_arsc_parse(mutated)
      let changed = match (base_arsc, got) {
        (Some(a), Some(b2)) => a != b2
        (Some(_), None) => true
        (None, _) => true
      }
      assert_true(
        changed,
        msg="ARSC bit 翻转 off=\{off} bit=\{bit} 后输出应不同或报错",
      )
      flips = flips + 1
    }
  }
  for off in value_size_targets {
    if off < 0 || off >= arsc.length() {
      continue
    }
    let mutated = fx_mut(arsc, off, (arsc[off].to_int() ^ (1 << 3)).to_byte())
    let got = fz_arsc_parse(mutated)
    let changed = match (base_arsc, got) {
      (Some(_), None) => true
      _ => false
    }
    assert_true(changed, msg="Res_value.size bit3 翻转应报 BadHeader")
    flips = flips + 1
  }
  println("L1 bit flips: cases=\{flips}")
  assert_true(
    flips >= 280,
    msg="bit 翻转用例量应 >= 280（实测 \{flips}）",
  )
}

///|
/// L1-3：≥1000 固定种子变异体（替换/插入/删除）——断言不 panic 且错误属于
/// 声明集合（AxmlError/ArscError）或解析成功。
test "L1: 1000 固定种子变异体不 panic" {
  let pool : Array[(String, Bytes, Bool)] = [
    ("base.AndroidManifest.xml", fixture_base_manifest(), false),
    ("tvshell-debug.AndroidManifest.xml", fixture_tvshell_manifest(), false),
    ("fx-multidex.AndroidManifest.xml", fixture_fx_multidex_manifest(), false),
    ("fx-config.AndroidManifest.xml", fixture_fx_config_manifest(), false),
    ("fx-multidex.resources.arsc", fixture_fx_multidex_arsc(), true),
    ("fx-config.resources.arsc", fixture_fx_config_arsc(), true),
    ("base.resources.arsc", fixture_base_arsc(), true),
  ]
  let state : Array[UInt32] = [0x9E3779B9U]
  let mut variants = 0
  for i in 0..<1050 {
    let pick = (fz_xorshift(state) >> 16) % 7U
    let (name, src, is_arsc) = pool[pick.reinterpret_as_int()]
    let pos = (fz_xorshift(state) >> 8) % src.length().reinterpret_as_uint()
    let byte_val = (fz_xorshift(state) & 0xFFU).reinterpret_as_int().to_byte()
    let mutated : Bytes = match i % 3 {
      0 => fx_mut(src, pos.reinterpret_as_int(), byte_val)
      1 => {
        // 插入：pos 前缀 + 字节 + 后缀
        let p = pos.reinterpret_as_int()
        let head = fx_cut(src, p)
        let tail = fx_cut(src[p:].to_owned(), src.length() - p)
        let joined : Array[Byte] = []
        for k in 0..<head.length() {
          joined.push(head[k])
        }
        joined.push(byte_val)
        for k in 0..<tail.length() {
          joined.push(tail[k])
        }
        Bytes::from_array(joined)
      }
      _ => {
        // 删除：pos 前缀 + pos+1 后缀
        let p = pos.reinterpret_as_int()
        let head = fx_cut(src, p)
        let rest = fx_cut(src[p:].to_owned(), src.length() - p - 1)
        let joined : Array[Byte] = []
        for k in 0..<head.length() {
          joined.push(head[k])
        }
        for k in 0..<rest.length() {
          joined.push(rest[k])
        }
        Bytes::from_array(joined)
      }
    }
    let _ = if is_arsc {
      fz_arsc_parse(mutated)
    } else {
      fz_axml_parse(mutated)
    }
    variants = variants + 1
    ignore(name)
  }
  assert_true(
    variants >= 1000,
    msg="变异体数量应 >= 1000（实测 \{variants}）",
  )
}
