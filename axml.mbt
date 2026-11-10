///|
/// Android 二进制 XML（AXML）解析库：类型、错误模型与公开接口。
///
/// 本文件包含全部公开类型与 5 个导出函数的真实实现；字节读取、UTF-8/UTF-16
/// 解码与字符串池解析等内部实现在 `decode.mbt`（不导出）。
/// 规范依据：AOSP frameworks/base/include/androidfw/ResourceTypes.h（Apache-2.0）。

///|
/// AXML chunk 类型（AOSP RES_STRING_POOL_TYPE / RES_XML_*_TYPE）。
/// 仅作节点来源标注，暂不参与解析决策。
pub(all) enum ChunkType {
  StringPool
  XmlTree
  StartNamespace
  EndNamespace
  StartElement
  EndElement
  CData
  ResourceMap
}

///|
/// 字符串池编码；UTF8_FLAG(0x100) 置位为 Utf8，否则 Utf16。
pub(all) enum StringEncoding {
  Utf8
  Utf16
}

///|
/// `Res_value.dataType` 的枚举化子集；`Unknown` 保留原始字节以便上层降级。
pub(all) enum ValueType {
  Null
  Reference
  Attribute
  String
  Float
  Dimension
  Fraction
  IntDec
  IntHex
  IntBoolean
  Unknown(Int32)
}

///|
/// 单个 typed attribute。
/// `raw_data` 保留 32 位原始 data；本库不解释 `@ref` / `?attr` 等资源引用语义。
pub(all) struct XmlAttribute {
  ns : String?
  name : String
  raw_value : String?
  value_type : ValueType
  res0 : Byte
  raw_data : UInt32
  line : Int32
}

///|
/// 文档树节点。`children` / `parent` 使用 `AxmlDoc::nodes()` 的索引，
/// 避免递归结构带来的所有权与生命周期歧义。
pub(all) struct XmlNode {
  line : Int32
  ns : String?
  name : String
  attributes : Array[XmlAttribute]
  children : Array[Int32]
  parent : Int32?
  chunk : ChunkType
}

///|
/// 字符串池视图；`strings` 下标与 chunk 内 string index 一一对应。
/// `styles` 保留原始字节，暂不做样式解析。
pub(all) struct StringPool {
  encoding : StringEncoding
  strings : Array[String]
  styles : Bytes
}

///|
/// AXML 解析结果：已解码字符串池 + 线性节点表 + 根索引 + 原始 resource map。
pub(all) struct AxmlDoc {
  pool : StringPool
  nodes : Array[XmlNode]
  roots : Array[Int32]
  resource_map : Array[UInt32]
}

///|
/// AXML 错误模型：全部为可恢复、可定位到字节偏移的显式错误，禁止 panic。
#derive(Debug)
pub suberror AxmlError {
  UnexpectedEof(Int32)
  BadChunkType(Int32, UInt32)
  BadHeaderSize(Int32, Int32)
  BadStringPool(Int32, String)
  InvalidStringIndex(Int32)
  InvalidNodeIndex(Int32)
  UnsupportedEncoding(String)
  VendorVariant(String)
}

///|
pub extend AxmlError with Debug::{to_repr}

///|
/// 字符串池索引。
pub type StringIndex = Int32

///|
/// 节点表索引。
pub type NodeIndex = Int32

///|
/// 解析一段完整 AXML 字节流（含 RES_XML_TYPE 头，不含 ZIP 封装）为文档树。
///
/// - 参数：`data` 为只读字节切片，调用方持有所有权，本函数不转移、不缓存；
///   `styles` 原始字节在返回值中是独立拷贝。
/// - 返回：`AxmlDoc` 纯值，无句柄、无需释放。
/// - 错误：越界 / 非法 headerSize / 非法字符串索引均以 `AxmlError` 传播并带
///   字节偏移。偏移语义：`UnexpectedEof(offset)` 指被截断项的起始偏移；
///   `BadChunkType` / `BadHeaderSize` 的 offset 指 chunk 起始（外层头部为 0）。
/// - 线程：无可变全局状态，可并发调用；返回值为只读，可跨线程共享。
/// - 降级策略（docs/DESIGN.md §7）：未知 chunk 类型按 headerSize/size 跳过；
///   厂商变体布局（attributeStart/attributeSize < 20）以 `VendorVariant` 报告；
///   未知字符串池标志位以 `UnsupportedEncoding` 报告。
/// - 非目标：不解析资源引用、不提供 manifest 语义、不回编、不处理 resources.arsc。
/// - TODO：`res0`/`data` 的语义解释（当前按 docs/API.md 保留原值，语义确定后再实现）。
pub fn parse(data : Bytes) -> AxmlDoc raise AxmlError {
  let limit = data.length()
  let doc_type = read_u16(data, 0, limit)
  if doc_type != 0x0003 {
    raise BadChunkType(0, doc_type.reinterpret_as_uint())
  }
  let header_size = read_u16(data, 2, limit)
  if header_size != 8 {
    raise BadHeaderSize(0, header_size)
  }
  let size = read_u32(data, 4, limit)
  if size < limit {
    // RES_CHUNK_header.size 必须覆盖整个输入；更短意味着尾随垃圾。
    raise BadHeaderSize(4, size)
  }
  if size > limit {
    // 外层 size 超出实际输入：文件在 `limit` 处被截断；必须先拒绝，
    // 否则后续 chunk 的 limit 会越过输入末尾并触发越界读取。
    raise UnexpectedEof(limit)
  }
  let mut pool : StringPool? = None
  let nodes : Array[XmlNode] = []
  let roots : Array[Int32] = []
  let resource_map : Array[UInt32] = []
  let stack : Array[Int32] = []
  let mut off = 8
  while off < size {
    let chunk_type = read_u16(data, off, limit)
    let chunk_header_size = read_u16(data, off + 2, limit)
    let chunk_size = read_u32(data, off + 4, limit)
    if chunk_size < 8 {
      raise BadHeaderSize(off, chunk_size)
    }
    if chunk_header_size < 8 || chunk_header_size > chunk_size {
      raise BadHeaderSize(off, chunk_header_size)
    }
    if off + chunk_size > size {
      raise UnexpectedEof(off)
    }
    if chunk_type == 0x0001 {
      if pool is Some(_) {
        raise BadChunkType(off, 0x0001U)
      }
      if chunk_header_size != 28 {
        raise BadHeaderSize(off, chunk_header_size)
      }
      pool = Some(parse_string_pool(data, off, chunk_size))
    } else if chunk_type == 0x0180 {
      if chunk_header_size != 8 {
        raise BadHeaderSize(off, chunk_header_size)
      }
      if (chunk_size - 8) % 4 != 0 {
        raise BadHeaderSize(off, chunk_size)
      }
      let mut p = off + 8
      while p < off + chunk_size {
        resource_map.push(read_u32u(data, p, off + chunk_size))
        p = p + 4
      }
    } else if chunk_type >= 0x0100 && chunk_type <= 0x0104 {
      // RES_XML_* 节点 chunk：必须位于字符串池之后，node 头固定 16 字节。
      let pool = require_pool(pool, off, chunk_type)
      if chunk_header_size != 16 {
        raise BadHeaderSize(off, chunk_header_size)
      }
      if chunk_type == 0x0102 {
        parse_start_element(data, off, chunk_size, pool, nodes, roots, stack)
      } else if chunk_type == 0x0103 {
        parse_end_element(data, off, chunk_size, pool, nodes, stack)
      } else if chunk_type == 0x0104 {
        parse_cdata(data, off, chunk_size, pool, nodes, roots, stack)
      } else {
        // 0x0100 / 0x0101：命名空间声明仅校验字符串引用后跳过
        // （docs/API.md 非目标：不做命名空间解析）。
        let chunk_end = off + chunk_size
        ignore(string_opt(pool, read_u32(data, off + 16, chunk_end)))
        ignore(string_opt(pool, read_u32(data, off + 20, chunk_end)))
      }
    } else {
      // RES_NULL_TYPE(0x0000) 与未知 chunk 类型按 headerSize/size 跳过。
      ()
    }
    off = off + chunk_size
  }
  if !stack.is_empty() {
    // 文档在元素未闭合处结束。
    raise UnexpectedEof(off)
  }
  let pool = match pool {
    Some(p) => p
    None => raise BadStringPool(8, "missing RES_STRING_POOL_TYPE chunk")
  }
  { pool, nodes, roots, resource_map, }
}

///|
/// 取出已解析的字符串池；XML 节点 chunk 不允许出现在字符串池之前。
fn require_pool(
  pool : StringPool?,
  off : Int32,
  chunk_type : Int32,
) -> StringPool raise AxmlError {
  match pool {
    Some(p) => p
    None => raise BadChunkType(off, chunk_type.reinterpret_as_uint())
  }
}

///|
/// 把节点挂到父节点的 children 或 roots 上。
fn attach(
  nodes : Array[XmlNode],
  roots : Array[Int32],
  parent : Int32?,
  index : Int32,
) -> Unit {
  match parent {
    Some(p) => nodes.at(p).children.push(index)
    None => roots.push(index)
  }
}

///|
/// 解析 RES_XML_START_ELEMENT_TYPE chunk（起始于 `off`，长度 `csize`）。
/// 厂商变体降级：attributeStart/attributeSize 允许大于 20（跳过多余字节），
/// 小于 20 无法安全解析，以 `VendorVariant` 报告。
fn parse_start_element(
  data : Bytes,
  off : Int32,
  csize : Int32,
  pool : StringPool,
  nodes : Array[XmlNode],
  roots : Array[Int32],
  stack : Array[Int32],
) -> Unit raise AxmlError {
  let limit = off + csize
  let line = read_u32(data, off + 8, limit)
  let ns_index = read_u32(data, off + 16, limit)
  let name_index = read_u32(data, off + 20, limit)
  let attribute_start = read_u16(data, off + 24, limit)
  let attribute_size = read_u16(data, off + 26, limit)
  let attribute_count = read_u16(data, off + 28, limit)
  if attribute_start < 20 || attribute_size < 20 {
    raise VendorVariant(
      "start element at offset \{off}: attributeStart=\{attribute_start}, attributeSize=\{attribute_size}",
    )
  }
  let attr_base = off + 16 + attribute_start
  if attribute_count > (csize - 16 - attribute_start) / attribute_size {
    raise UnexpectedEof(attr_base)
  }
  let attributes : Array[XmlAttribute] = []
  let mut i = 0
  while i < attribute_count {
    let a = attr_base + i * attribute_size
    let attr_ns = read_u32(data, a, limit)
    let attr_name = read_u32(data, a + 4, limit)
    let attr_raw = read_u32(data, a + 8, limit)
    let value_size = read_u16(data, a + 12, limit)
    let res0 = read_u8(data, a + 14, limit)
    let data_type = read_u8(data, a + 15, limit)
    let raw_data = read_u32u(data, a + 16, limit)
    if value_size != 8 {
      // Res_value.size 恒为 8；其他取值属于厂商变体布局。
      raise BadHeaderSize(a + 12, value_size)
    }
    attributes.push({
      ns: string_opt(pool, attr_ns),
      name: string_req(pool, attr_name),
      raw_value: string_opt(pool, attr_raw),
      value_type: value_type_of(data_type),
      res0: res0.to_byte(),
      raw_data,
      line,
    })
    i = i + 1
  }
  let parent : Int32? = if stack.is_empty() {
    None
  } else {
    Some(stack.at(stack.length() - 1))
  }
  let index = nodes.length()
  nodes.push({
    line,
    ns: string_opt(pool, ns_index),
    name: string_req(pool, name_index),
    attributes,
    children: [],
    parent,
    chunk: StartElement,
  })
  attach(nodes, roots, parent, index)
  stack.push(index)
}

///|
/// 解析 RES_XML_END_ELEMENT_TYPE chunk：弹出元素栈，并校验结束标签与栈顶
/// 元素的名称/命名空间一致；不匹配以 `BadChunkType` 报告。
fn parse_end_element(
  data : Bytes,
  off : Int32,
  csize : Int32,
  pool : StringPool,
  nodes : Array[XmlNode],
  stack : Array[Int32],
) -> Unit raise AxmlError {
  let limit = off + csize
  let ns_index = read_u32(data, off + 16, limit)
  let name_index = read_u32(data, off + 20, limit)
  if stack.is_empty() {
    raise BadChunkType(off, 0x0103U)
  }
  let top = stack.at(stack.length() - 1)
  let node = nodes.at(top)
  if node.name != string_req(pool, name_index) ||
    node.ns != string_opt(pool, ns_index) {
    raise BadChunkType(off, 0x0103U)
  }
  ignore(stack.pop())
}

///|
/// 解析 RES_XML_CDATA_TYPE chunk：文本作为 `chunk = CData` 的节点进入节点表，
/// 挂在当前打开元素之下；`elements()` 会将其过滤掉。
fn parse_cdata(
  data : Bytes,
  off : Int32,
  csize : Int32,
  pool : StringPool,
  nodes : Array[XmlNode],
  roots : Array[Int32],
  stack : Array[Int32],
) -> Unit raise AxmlError {
  let limit = off + csize
  let line = read_u32(data, off + 8, limit)
  let text_index = read_u32(data, off + 16, limit)
  let value_size = read_u16(data, off + 20, limit)
  ignore(read_u8(data, off + 22, limit))
  ignore(read_u8(data, off + 23, limit))
  ignore(read_u32u(data, off + 24, limit))
  if value_size != 8 {
    raise BadHeaderSize(off + 20, value_size)
  }
  let parent : Int32? = if stack.is_empty() {
    None
  } else {
    Some(stack.at(stack.length() - 1))
  }
  let index = nodes.length()
  nodes.push({
    line,
    ns: None,
    name: string_req(pool, text_index),
    attributes: [],
    children: [],
    parent,
    chunk: CData,
  })
  attach(nodes, roots, parent, index)
}

///|
/// 按 chunk 顺序返回全部元素节点。`XmlTree` / `CData` 等非元素节点不在此列表中。
/// 先校验 roots / parent / children 索引，越界返回 `InvalidNodeIndex`。
pub fn AxmlDoc::elements(self : AxmlDoc) -> Array[XmlNode] raise AxmlError {
  let count = self.nodes.length()
  for root in self.roots {
    if root < 0 || root >= count {
      raise InvalidNodeIndex(root)
    }
  }
  for i in 0..<count {
    let node = self.nodes.at(i)
    match node.parent {
      Some(parent) =>
        if parent < 0 || parent >= count {
          raise InvalidNodeIndex(parent)
        }
      None => ()
    }
    for child in node.children {
      if child < 0 || child >= count {
        raise InvalidNodeIndex(child)
      }
    }
  }
  self.nodes.filter(fn(node) { node.chunk is StartElement })
}

///|
/// 读取字符串池第 `index` 项；越界返回 `InvalidStringIndex`。
pub fn AxmlDoc::string_at(
  self : AxmlDoc,
  index : StringIndex,
) -> String raise AxmlError {
  if index < 0 || index >= self.pool.strings.length() {
    raise InvalidStringIndex(index)
  }
  self.pool.strings.at(index)
}

///|
/// 读取节点表第 `index` 项；越界返回 `InvalidNodeIndex`。
pub fn AxmlDoc::node_at(
  self : AxmlDoc,
  index : NodeIndex,
) -> XmlNode raise AxmlError {
  if index < 0 || index >= self.nodes.length() {
    raise InvalidNodeIndex(index)
  }
  self.nodes.at(index)
}

///|
/// 返回某节点的属性列表（保持 chunk 内原始顺序，不做去重、不做命名空间解析）。
pub fn XmlNode::attrs(self : XmlNode) -> Array[XmlAttribute] {
  self.attributes
}
