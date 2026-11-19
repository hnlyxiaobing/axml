///|
/// P1-2：性质测试补齐（测试系统设计 §4）。
/// - P3 解析确定性：同字节两次 parse/parse_arsc 逐字段相等（≥3 个 fixture）；
/// - P4 配置退化律：`lookup_with(id, 全零 config)` ≡ `lookup(id)`（默认配置存在
///   时；默认配置不存在时按文档化语义断言实际分叉——`lookup_with` 无匹配返回
///   None，`lookup` 回退 chunk 顺序首个命中）；
/// - P6 渲染一致律：简单值 id 的 `resolve_id` 文本 ≡ `format_value` 直渲染；
/// - P10 防火墙律：新增函数（W3 `resolve_attr_value_with_config` / W9 配置序列化）
///   合入后，旧函数既有行为零改动（旧函数 ≡ 新函数在旧口径入参下的结果）。

///|
/// P3：解析确定性——同一字节流两次解析的指纹逐字段相等（覆盖 4 个 fixture）。
test "P3: 同字节两次 parse/parse_arsc 逐字段相等" {
  let cases : Array[(String, Bytes, Bool)] = [
    ("fx-multidex.AndroidManifest.xml", fixture_fx_multidex_manifest(), false),
    (
      "framework-res.AndroidManifest.xml",
      fixture_framework_res_manifest(),
      false,
    ),
    ("fx-multidex.resources.arsc", fixture_fx_multidex_arsc(), true),
    ("fx-config.resources.arsc", fixture_fx_config_arsc(), true),
  ]
  for c in cases {
    let (name, bytes, is_arsc) = c
    let (fp1, fp2) = if is_arsc {
      let a = fz_arsc_parse(bytes)
      let b = fz_arsc_parse(bytes)
      (a, b)
    } else {
      let a = fz_axml_parse(bytes)
      let b = fz_axml_parse(bytes)
      (a, b)
    }
    match (fp1, fp2) {
      (Some(a), Some(b)) =>
        assert_eq(a, b, msg="P3 \{name}: 两次解析指纹一致")
      _ => fail("P3 \{name}: 基线解析应成功")
    }
  }
}

///|
/// P4：配置退化律。默认配置存在 → `lookup_with(id, 全零)` ≡ `lookup(id)`；
/// 仅 zh 配置（无默认）→ 文档化分叉：`lookup_with` 返回 None，`lookup` 回退
/// chunk 顺序首个命中。
test "P4: lookup_with 全零 config 退化律" {
  // —— 默认配置存在（default + zh 双配置表）——
  let dual = mc_table()
  let empty = mr_default()
  for id in [0x7f010000U, 0x7f010099U] {
    let via_with = dual.lookup_with(id, empty)
    let via_plain = dual.lookup(id)
    match (via_with, via_plain) {
      (None, None) => ()
      (Some(a), Some(b)) => {
        assert_eq(a.entry_name, b.entry_name, msg="P4 \{id}: 条目名一致")
        assert_eq(a.type_name, b.type_name, msg="P4 \{id}: 类型名一致")
        assert_true(
          a.config.is_default() == b.config.is_default(),
          msg="P4 \{id}: 命中配置类别一致",
        )
      }
      _ => fail("P4 \{id}: lookup_with 与 lookup 应同命中或同未命中")
    }
  }
  // zh 设备语义不变（对照）：lookup_with 命中 zh 配置
  let zh = @axml.ResConfig::from_qualifiers("zh") catch { _ => abort("zh") }
  match dual.lookup_with(0x7f010000U, zh) {
    None => fail("P4 对照: zh 设备应命中 zh 配置")
    Some(hit) =>
      assert_eq(hit.config.language, "zh", msg="P4 对照: 命中 zh")
  }
  // —— 默认配置不存在（仅 zh 配置表）——
  let zh_only_cfg = @axml.ResConfig::from_qualifiers("zh") catch {
    _ => abort("zh")
  }
  let zh_only_entry : @axml.ResEntry = {
    key: 0,
    key_name: "solo",
    flags: 0,
    value: @axml.ResEntryValue::Simple({
      data_type: @axml.ResDataType::IntDec,
      data: 42U,
    }),
  }
  let spec : @axml.ResTypeSpec = {
    id: 1,
    types_count: 1,
    entry_count: 1,
    spec_flags: [0x40000000U],
    configs: [
      { id: 1, flags: 0, config: zh_only_cfg, entries: [Some(zh_only_entry)], },
    ],
  }
  let pkg : @axml.ResPackage = {
    id: 0x7f,
    name: "solo",
    type_id_offset: 0,
    type_pool: mr_pool(["string"]),
    key_pool: mr_pool(["solo"]),
    types: [spec],
    libraries: [],
  }
  let zh_only : @axml.ResTable = {
    global_pool: mr_pool([]),
    packages: [pkg],
    package_count: 1,
  }
  assert_true(
    zh_only.lookup_with(0x7f010000U, empty) is None,
    msg="P4 无默认: 全零设备不匹配 zh 配置 → None（文档化分叉）",
  )
  assert_true(
    zh_only.lookup(0x7f010000U) is Some(_),
    msg="P4 无默认: lookup 回退 chunk 顺序首个命中",
  )
}

///|
/// P6：渲染一致律——简单值 id 的 `resolve_id` 文本 ≡ `format_value` 直渲染。
/// 口径：`resolve_id` 按 `lookup`（默认配置优先）选中**同一条目**，
/// 故仅与 `lookup(id)` 命中条目的值比较（`lookup_all` 的其他配置不适用）。
/// 覆盖合成表（String）与真实 fixture（string/bool/color 全部非引用简单值）。
test "P6: resolve_id 文本 ≡ format_value 直渲染" {
  // —— 合成双配置表 ——
  let dual = mc_table()
  for id in [0x7f010000U] {
    match dual.lookup(id) {
      None => fail("P6: 条目应命中")
      Some(hit) =>
        match hit.entry.value {
          Simple(v) =>
            assert_eq(
              dual.resolve_id(id),
              dual.format_value(v),
              msg="P6 合成表 \{id}",
            )
          Complex(_) => fail("P6: 应为简单条目")
        }
    }
  }
  // —— 真实 fixture：遍历全部 (包,类型,条目) ——
  let table = @axml.parse_arsc(fixture_fx_multidex_arsc())
  for p in table.packages {
    for spec in p.types {
      let mut idx = 0
      while idx < spec.entry_count {
        let id = (p.id.reinterpret_as_uint() << 24) |
          ((spec.id + p.type_id_offset).reinterpret_as_uint() << 16) |
          idx.reinterpret_as_uint()
        match table.lookup(id) {
          Some(hit) =>
            match hit.entry.value {
              Simple(v) =>
                match v.data_type {
                  // 引用类值 resolve_id 会跟随引用链，不适用 P6 直渲染口径
                  @axml.ResDataType::Reference
                  | @axml.ResDataType::Attribute
                  | @axml.ResDataType::DynamicReference
                  | @axml.ResDataType::DynamicAttribute => ()
                  _ =>
                    assert_eq(
                      table.resolve_id(id),
                      table.format_value(v),
                      msg="P6 fixture \{hit.type_name}/\{hit.entry_name}",
                    )
                }
              Complex(_) => ()
            }
          None => ()
        }
        idx = idx + 1
      }
    }
  }
}

///|
/// P10：防火墙律——新增函数合入后旧函数行为零改动。
/// - W3：`resolve_attr_value`（旧）≡ `resolve_attr_value_with_config` + 全零设备
///   （旧口径入参下逐字段一致），且旧函数对双配置表仍默认优先；
/// - W4/W6：既有 T-W4-3（非 ?attr 与旧函数一致）/T-W6-3（多表不破坏单表行为）
///   零改动仍绿由全量回归承载，此处补 fixture 级交叉核对；
/// - W9：解析产物配置（raw.len == size）回编路径与旧口径一致——
///   `encode_arsc(parse(fx))` 往返指纹不变（raw 原样回写语义未变）。
test "P10: 新增函数防火墙律（旧函数行为零改动）" {
  let dual = mc_table()
  let empty = mr_default()
  let doc = ar_doc()
  // —— W3：旧函数 ≡ 新函数 + 全零设备（id 引用与文本引用两路径）——
  let cases : Array[@axml.XmlAttribute] = [
    ar_attr(Reference, 0x7f010000, None),
    ar_attr(Reference, 0x7f010099, None),
    ar_attr(String, 0U, Some("@string/app_name")),
    ar_attr(IntBoolean, 1U, None),
  ]
  for attr in cases {
    let old = @axml.resolve_attr_value(doc, dual, attr)
    let new = @axml.resolve_attr_value_with_config(doc, dual, attr, empty)
    assert_eq(old.text, new.text, msg="P10 W3: text 一致")
    assert_eq(old.id, new.id, msg="P10 W3: id 一致")
    let old_u = old.origin is Unresolved(_)
    let new_u = new.origin is Unresolved(_)
    assert_eq(old_u, new_u, msg="P10 W3: origin 类别一致")
  }
  // 旧函数默认优先（真实样本同构语义冻结）
  let old_ref = @axml.resolve_attr_value(
    doc,
    dual,
    ar_attr(Reference, 0x7f010000, None),
  )
  assert_eq(
    old_ref.text,
    "Fx Multidex",
    msg="P10 W3: 旧函数默认优先不变",
  )
  // —— W4：非 ?attr 类型与旧函数逐字段一致（真实 arsc + 引用属性）——
  let fx = @axml.parse_arsc(fixture_fx_multidex_arsc())
  let themed = @axml.resolve_attr_value_with_theme(
    doc,
    fx,
    ar_attr(Reference, 0x7f030000, None),
    0x7f030000,
    empty,
  )
  let plain = @axml.resolve_attr_value(
    doc,
    fx,
    ar_attr(Reference, 0x7f030000, None),
  )
  assert_eq(
    themed.text,
    plain.text,
    msg="P10 W4: 非 ?attr 路径与旧函数一致",
  )
  // —— W6：单表集合行为 ≡ 单表直查 ——
  let set : @axml.ResTableSet = { tables: [fx], }
  let via_multi = @axml.resolve_attr_value_multi(
    doc,
    set,
    ar_attr(Reference, 0x7f030000, None),
  )
  assert_eq(
    via_multi.text,
    plain.text,
    msg="P10 W6: 单表集合 ≡ 单表直查",
  )
  // —— W9：解析产物回编往返指纹不变（raw 原样回写语义未变）——
  let out = @axml.encode_arsc(fx) catch {
    _ => fail("P10 W9: encode_arsc 应成功")
  }
  let back = fz_arsc_parse(out)
  let orig = fz_arsc_parse(fixture_fx_multidex_arsc())
  assert_eq(back, orig, msg="P10 W9: 往返指纹与原表一致")
}
