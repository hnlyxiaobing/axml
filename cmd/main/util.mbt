///|
/// CLI 公共辅助（axml-cli）：JSON 转义、hex/十进制渲染、属性值规范化、
/// 资源引用解析辅助。仅使用 moonbitlang/core 与本模块公开 API。

///|
/// JSON 字符串转义（RFC 8259 最小充分子集：引号、反斜杠、控制字符）。
fn json_escape(s : String) -> String {
  let out : Array[String] = []
  out.push("\"")
  for c in s.iter() {
    let v = c.to_int()
    if c == '"' {
      out.push("\\\"")
    } else if c == '\\' {
      out.push("\\\\")
    } else if c == '\n' {
      out.push("\\n")
    } else if c == '\r' {
      out.push("\\r")
    } else if c == '\t' {
      out.push("\\t")
    } else if v < 0x20 {
      out.push("\\u" + json_hex4(v))
    } else {
      out.push(c.to_string())
    }
  }
  out.push("\"")
  str_join(out)
}

///|
/// 四位小写十六进制（JSON \uXXXX 用）。
fn json_hex4(v : Int32) -> String {
  let digits = "0123456789abcdef"
  let mut s = ""
  let mut x = v
  let mut n = 0
  while n < 4 {
    let d = x & 0xF
    s = digits[d:d + 1].to_owned() + s
    x = x >> 4
    n = n + 1
  }
  s
}

///|
/// 片段拼接为字符串（无分隔符；JSON 构造用）。
fn str_join(parts : Array[String]) -> String {
  let mut s = ""
  for l in parts {
    s = s + l
  }
  s
}

///|
/// 文本行拼接（`\n` 分隔；帮助文本用）。
fn join_lines(lines : Array[String]) -> String {
  let mut s = ""
  let mut first = true
  for l in lines {
    if first {
      first = false
    } else {
      s = s + "\n"
    }
    s = s + l
  }
  s
}

///|
/// 无符号 32 位小写十六进制（至少 8 位；aapt2 `0x%08x` 渲染一致）。
fn hex8(v : UInt32) -> String {
  let digits = "0123456789abcdef"
  let mut s = ""
  let mut x = v
  let mut n = 0
  while x != 0U {
    let d = (x & 15U).to_byte().to_int()
    s = digits[d:d + 1].to_owned() + s
    x = x >> 4
    n = n + 1
  }
  while n < 8 {
    s = "0" + s
    n = n + 1
  }
  s
}

///|
/// 有符号十进制（aapt2 对 TYPE_INT_DEC 按有符号渲染）。
fn int_dec(v : UInt32) -> String {
  "\{v.reinterpret_as_int()}"
}

///|
/// 资源引用解析上下文：`--resolve` 开启时把 Reference/Attribute 属性解析为人类可读值。
struct RefCtx {
  doc : @axml.AxmlDoc
  table : @axml.ResTable?
  resolve : Bool
}

///|
/// 资源引用名字级解析（resources.arsc 链；`@type/name`，如 `@string/app_name`）。
/// 命中 -> `@type/name`；未命中/无表 -> `@0x%08x`。作为 resolve_attr 的降级回退。
fn resolve_res_ref(table : @axml.ResTable?, res_id : UInt32) -> String {
  match table {
    Some(t) =>
      match t.lookup(res_id) {
        Some(hit) => "@" + hit.type_name + "/" + hit.entry_name
        None => "@0x" + hex8(res_id)
      }
    None => "@0x" + hex8(res_id)
  }
}

///|
/// `--resolve` 属性值渲染：`@axml.resolve_attr_value`
/// （AXML 文档 + 资源表联合解析）的 `ResolvedAttr.text`（解析后的人类可读值，
/// 如 `@string/app_name` → `MyApp`）。
/// 降级链（保持既有回退与退出码约定）：
/// 1. 解析成功（Literal/FromId/FromName）-> `ResolvedAttr.text`；
/// 2. Unresolved 且文本仍为 `@0x…` 原值 -> 名字级回退 `resolve_res_ref`
///    （命中 `@type/name`，再退 `@0x%08x`）；
/// 3. Unresolved 但文本带说明（如 `… (dynamic)`、`(invalid string index …)`）-> 原样保留；
/// 4. 无表（防御路径，正常被 `--resolve` 的退出码 2 拦截）-> `@0x%08x`。
/// 框架引用（0x01…）不在应用资源表内 -> `@0x%08x`（README 口径不变）。
fn resolve_attr(ctx : RefCtx, a : @axml.XmlAttribute) -> String {
  match ctx.table {
    Some(t) => {
      let r = @axml.resolve_attr_value(ctx.doc, t, a)
      match r.origin {
        Unresolved(_) =>
          if r.text.has_prefix("@0x") {
            match r.id {
              Some(id) => resolve_res_ref(ctx.table, id)
              None => r.text
            }
          } else {
            r.text
          }
        _ => r.text
      }
    }
    None => "@0x" + hex8(a.raw_data)
  }
}

///|
/// 属性值规范化渲染（无 --resolve 时与 aapt2 dump xmltree 渲染逐字段对齐、
/// 与 tests/ASSETS.md §4 黄金口径逐字节一致；--resolve 时 Reference/Attribute 走
/// `resolve_attr` 解析为人类可读值）。
fn attr_value(ctx : RefCtx, a : @axml.XmlAttribute) -> String {
  if ctx.resolve && (a.value_type is Reference || a.value_type is Attribute) {
    return resolve_attr(ctx, a)
  }
  match a.raw_value {
    Some(v) => v
    None =>
      match a.value_type {
        Null => "@null"
        Reference => "@0x" + hex8(a.raw_data)
        Attribute => "?0x" + hex8(a.raw_data)
        String => ""
        Float => "?float"
        Dimension => "?dim"
        Fraction => "?frac"
        IntDec => int_dec(a.raw_data)
        IntHex => "0x" + hex8(a.raw_data)
        IntBoolean => if a.raw_data == 0U { "false" } else { "true" }
        Unknown(_) => "?unknown"
      }
  }
}

///|
/// 值类型枚举名（--json 输出用）。
fn value_type_name(t : @axml.ValueType) -> String {
  match t {
    Null => "Null"
    Reference => "Reference"
    Attribute => "Attribute"
    String => "String"
    Float => "Float"
    Dimension => "Dimension"
    Fraction => "Fraction"
    IntDec => "IntDec"
    IntHex => "IntHex"
    IntBoolean => "IntBoolean"
    Unknown(v) => "Unknown(\{v})"
  }
}

///|
/// `String?` 渲染（None -> 空串）。
fn opt_str(v : String?) -> String {
  match v {
    Some(s) => s
    None => ""
  }
}
