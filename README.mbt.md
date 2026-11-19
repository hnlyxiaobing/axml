# hnlyxiaobing/axml

把 Android 二进制 XML（AXML）与 `resources.arsc` 解析成可读的节点树、属性、字符串池与资源引用值，并提供格式级回编（AXML / ARSC 值级）。

- 解析：AXML chunk、字符串池、resource map、命名空间、元素与属性，支持 tree / sem / pool 三种视图
- 资源表：`resources.arsc` 的 package / typeSpec / type entry / 字符串池，bag 压平，`?attr` 主题求值
- 解析辅助：qualifier 最优匹配、`ResTableSet` 多表联合解析、`--config` 设备限定符取值
- 回编：`encode` 生成 AXML、`encode_arsc` 生成 `resources.arsc`（值级语义往返）
- 零第三方依赖；`preferred_target = wasm`，wasm/native 双目标通过同一套测试

## 安装

```bash
moon add hnlyxiaobing/axml
```

## 快速开始

```mbt nocheck
///|
fn dump_names(raw : Bytes) -> Unit raise {
  let doc = @axml.parse(raw)
  for node in doc.elements() {
    guard node.chunk is StartElement else { continue }
    println(node.name)
    for attr in node.attrs() {
      println("\{attr.name} = \{attr.raw_value.unwrap_or("")}")
    }
  }
}

///|
fn resolve_label(raw_axml : Bytes, raw_arsc : Bytes) -> Unit raise {
  let doc = @axml.parse(raw_axml)
  let table = @axml.parse_arsc(raw_arsc)
  for node in doc.elements() {
    for attr in node.attrs() {
      let resolved = @axml.resolve_attr_value(doc, table, attr)
      println("\{attr.name} -> \{resolved}")
    }
  }
}
```

## 命令行

```bash
axml-cli dump --view sem --resolve --arsc resources.arsc AndroidManifest.xml
axml-cli dump --json --config zh-rCN-sw600dp AndroidManifest.xml
```

## 链接

- 完整说明（能力边界、公开 API、验证、风险）：仓库 `README.md`
- 公开签名以 `pkg.generated.mbti` 为准
- 许可：Apache-2.0
