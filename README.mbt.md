# hnlyxiaobing/axml

> Round-1 · 架构与声明可评审（2026-11-06）。本包只有数据结构、错误模型与 `declare` 函数签名，**无 AXML 解析逻辑**。`moon check`：0 error，5 × `[0068]`（预期）。

Android Binary XML 解析结果的契约层：字符串池、resource map、XML 节点树与属性访问接口。

完整文档见同目录 `README.md`（定位 / 非目标 / 依赖 / 平台与许可风险 / 测试验收 / 状态）、`DESIGN.md`（设计契约）、`API.md`（公开签名）；总体架构与决策见 `../docs/architecture.md`、`../docs/adr/`。

**当前状态：等待评审，不进入实现。**
