# hnlyxiaobing/axml

> R2 冻结前整改轮（2026-11-07）。本包为**完整实现**：AXML 字节流 → 文档树的解析器（字符串池 UTF-8 / UTF-16、节点树、typed attribute），全部导出函数均为真实实现，包内无 `declare` 存根。`moon check --deny-warn`：0 error / 0 warning；`moon test`：40/40；`moon fmt --check`：通过。

Android Binary XML 解析结果的契约层：字符串池、resource map、XML 节点树与属性访问接口。错误模型为 `pub suberror AxmlError`（8 个带偏移/索引的变体）；无外部句柄、无释放函数，本包不导出任何 trait（`DocumentView` 已在 R2 删除）。

完整文档见同目录 `README.md`（定位 / 非目标 / 依赖 / 平台与许可风险 / 测试验收 / 冻结前状态）、`DESIGN.md`（设计契约）、`API.md`（公开签名）；总体架构与决策见 `../docs/architecture.md`、`../docs/adr/`。

**当前状态：实现完成并通过门禁，等待 API 冻结评审。**
