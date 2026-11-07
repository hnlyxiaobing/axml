///|
/// WP-3 axml-cli 视图渲染：tree / sem / pool（文本记录行与 --json 两种形态）。
/// 记录行口径与 fixtures/golden/axml/*.norm.txt 一致（EL/AT、SEM、POOL/STR）。
/// `ctx` 为资源引用解析上下文（`--resolve` 接线点，见 util.mbt）。

///|
/// manifest 语义字段集合（sem 视图）。
struct SemInfo {
  pkg_name : String
  version_code : String
  version_name : String
  min_sdk : String
  target_sdk : String
  label : String
  has_label : Bool
  activity : String
  permissions : Array[String]
}

///|
/// 取节点上第一个同名属性的渲染值。
fn attr_str(ctx : RefCtx, n : @axml.XmlNode, name : String) -> String? {
  let mut res : String? = None
  let mut found = false
  for a in n.attrs() {
    if a.name == name && !found {
      found = true
      res = Some(attr_value(ctx, a))
    }
  }
  res
}

///|
/// 只取字符串字面量原值（raw_value）。
fn attr_raw(n : @axml.XmlNode, name : String) -> String? {
  let mut res : String? = None
  let mut found = false
  for a in n.attrs() {
    if a.name == name && !found {
      found = true
      res = a.raw_value
    }
  }
  res
}

///|
/// 该 activity 是否含 MAIN + LAUNCHER intent-filter（badging 的 launchable-activity）。
fn is_launcher(ctx : RefCtx, doc : @axml.AxmlDoc, act : @axml.XmlNode) -> Bool {
  let mut main = false
  let mut launcher = false
  for ci in act.children {
    let n = doc.nodes.at(ci)
    if n.name == "intent-filter" {
      for ai in n.children {
        let m = doc.nodes.at(ai)
        let v = attr_str(ctx, m, "name")
        if m.name == "action" && v == Some("android.intent.action.MAIN") {
          main = true
        }
        if m.name == "category" && v == Some("android.intent.category.LAUNCHER") {
          launcher = true
        }
      }
    }
  }
  main && launcher
}

///|
/// activity 名解析（badging 同构）：`.Main` -> `pkg.Main`；`a.b.C` 原样；`Main` -> `pkg.Main`。
fn resolve_activity(pkg : String, raw : String) -> String {
  if raw.has_prefix(".") {
    pkg + raw
  } else if raw.contains(".") {
    raw
  } else {
    pkg + "." + raw
  }
}

///|
/// 语义字段提取（golden sem.norm.txt 口径；label 仅取字符串字面量）。
fn sem_info(ctx : RefCtx, doc : @axml.AxmlDoc) -> SemInfo raise @axml.AxmlError {
  let mut pkg = ""
  let mut vc = ""
  let mut vn = ""
  let mut min_sdk = ""
  let mut tgt_sdk = ""
  let mut label = ""
  let mut has_label = false
  let mut act = ""
  let perms : Array[String] = []
  for e in doc.elements() {
    if e.name == "manifest" && pkg == "" {
      pkg = opt_str(attr_str(ctx, e, "package"))
      vc = opt_str(attr_str(ctx, e, "versionCode"))
      vn = opt_str(attr_str(ctx, e, "versionName"))
    } else if e.name == "uses-sdk" && min_sdk == "" {
      min_sdk = opt_str(attr_str(ctx, e, "minSdkVersion"))
      tgt_sdk = opt_str(attr_str(ctx, e, "targetSdkVersion"))
    } else if e.name == "application" && !has_label {
      match attr_raw(e, "label") {
        Some(v) => {
          label = v
          has_label = true
        }
        None => ()
      }
    } else if e.name == "uses-permission" {
      match attr_str(ctx, e, "name") {
        Some(v) => perms.push(v)
        None => ()
      }
    } else if e.name == "activity" && act == "" {
      if is_launcher(ctx, doc, e) {
        act = resolve_activity(pkg, opt_str(attr_str(ctx, e, "name")))
      }
    }
  }
  SemInfo::{
    pkg_name: pkg,
    version_code: vc,
    version_name: vn,
    min_sdk,
    target_sdk: tgt_sdk,
    label,
    has_label,
    activity: act,
    permissions: perms,
  }
}

///|
/// sem 视图文本记录行。
fn sem_lines(s : SemInfo) -> Array[String] {
  let out : Array[String] = []
  out.push("SEM|package|\{s.pkg_name}")
  out.push("SEM|versionCode|\{s.version_code}")
  out.push("SEM|versionName|\{s.version_name}")
  out.push("SEM|minSdk|\{s.min_sdk}")
  out.push("SEM|targetSdk|\{s.target_sdk}")
  if s.has_label {
    out.push("SEM|label|\{s.label}")
  }
  if s.activity != "" {
    out.push("SEM|activity|\{s.activity}")
  }
  for p in s.permissions {
    out.push("SEM|permission|\{p}")
  }
  out
}

///|
/// 递归输出 `EL|depth|ns|name` 与 `AT|depth|elem|ns|name|value`。
fn tree_walk(
  ctx : RefCtx,
  doc : @axml.AxmlDoc,
  idx : Int32,
  depth : Int32,
  out : Array[String],
) -> Unit {
  let n = doc.nodes.at(idx)
  if n.chunk is StartElement {
    out.push("EL|\{depth}|\{opt_str(n.ns)}|\{n.name}")
    for a in n.attrs() {
      out.push(
        "AT|\{depth}|\{n.name}|\{opt_str(a.ns)}|\{a.name}|\{attr_value(ctx, a)}",
      )
    }
    for c in n.children {
      tree_walk(ctx, doc, c, depth + 1, out)
    }
  }
}

///|
/// 树视图文本记录行（roots 全量深度优先）。
fn tree_lines(ctx : RefCtx, doc : @axml.AxmlDoc) -> Array[String] {
  let out : Array[String] = []
  for r in doc.roots {
    tree_walk(ctx, doc, r, 0, out)
  }
  out
}

///|
/// 字符串池视图文本记录行。
fn pool_lines(doc : @axml.AxmlDoc) -> Array[String] {
  let out : Array[String] = []
  let n = doc.pool.strings.length()
  out.push("POOL|\{n}")
  let mut i = 0
  while i < n {
    out.push("STR|\{i}|\{doc.pool.strings.at(i)}")
    i = i + 1
  }
  out
}

///|
/// 树视图 --json（嵌套节点树）。
fn tree_json(ctx : RefCtx, doc : @axml.AxmlDoc, idx : Int32) -> String {
  let n = doc.nodes.at(idx)
  let parts : Array[String] = []
  parts.push(
    "{\"ns\":\{json_escape(opt_str(n.ns))},\"name\":\{json_escape(n.name)},\"attributes\":[",
  )
  let mut first = true
  for a in n.attrs() {
    if !first {
      parts.push(",")
    }
    first = false
    parts.push(
      "{\"ns\":\{json_escape(opt_str(a.ns))},\"name\":\{json_escape(a.name)},\"value\":\{json_escape(attr_value(ctx, a))},\"value_type\":\{json_escape(value_type_name(a.value_type))}}",
    )
  }
  parts.push("],\"children\":[")
  first = true
  for c in n.children {
    let child = doc.nodes.at(c)
    if child.chunk is StartElement {
      if !first {
        parts.push(",")
      }
      first = false
      parts.push(tree_json(ctx, doc, c))
    }
  }
  parts.push("]}")
  str_join(parts)
}
