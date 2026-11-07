# hnlyxiaobing/axml

> R2 冻结前整改轮（2026-11-07，同日 WP-1 加法性新增 resources.arsc 解析链）。本包为**完整实现**：AXML 字节流 → 文档树，以及 resources.arsc → 资源表（查询 + 属性引用解析）的解析器，全部导出函数均为真实实现，包内无 `declare` 存根。`moon check --deny-warn`：0 error / 0 warning；`moon test`：87/87；`moon fmt --check`：通过。

Android Binary XML 解析结果的契约层：字符串池、resource map、XML 节点树与属性访问接口；以及 Android 二进制资源表（resources.arsc）的解析与查询接口（`parse_arsc` / `lookup` / `resolve_attr_value`）。错误模型：AXML 侧 `pub suberror AxmlError`（8 个带偏移/索引的变体），资源表侧 `pub suberror ArscError`（6 个变体）；无外部句柄、无释放函数，本包不导出任何 trait（`DocumentView` 已在 R2 删除）。

完整文档见同目录 `README.md`（定位 / 非目标 / 依赖 / 平台与许可风险 / 测试验收 / 冻结前状态）、`DESIGN.md`（设计契约，§14 为 resources.arsc 的 D1 范围与降级项）、`API.md`（公开签名与渲染规则）；总体架构与决策见 `../docs/architecture.md`、`../docs/adr/`。

**当前状态：实现完成并通过门禁，等待 API 冻结评审。**
