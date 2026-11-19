///|
/// axml-cli 可执行入口（hnlyxiaobing/axml/cmd/main）。
/// CLI 全部公开行为位于库包 `hnlyxiaobing/axml/cmd/cli`（含 L4 E2E 与其公共
/// 入口 `cli_run`）；本包仅保持进程入口：转发 argv、按退出码结束进程。

///|
async fn main {
  let code = @cli.run_main(@env.args())
  if code != 0 {
    @env.exit(code)
  }
}
