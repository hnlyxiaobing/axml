///|
/// CLI 输出汇（axml-cli）。真实模式直接写 stdout/stderr（保持既有流式行为与外部契约
/// 逐字节不变）；捕获模式把行缓冲进内存，供 `moon test` 原生承载 L4 场景断言。
/// 字段 `out_lines`/`err_lines` 为数组（引用类型），`out_line`/`err_line` 的 push
/// 跨结构体按值传递仍共享同一底层数组，故捕获模式可跨调用累积。

///|
priv struct Sink {
  capture : Bool
  out_lines : Array[String]
  err_lines : Array[String]
}

///|
/// 真实汇：`out_line`/`err_line` 转发到真实 stdout/stderr。
fn real_sink() -> Sink {
  Sink::{ capture: false, out_lines: [], err_lines: [], }
}

///|
/// 捕获汇：`out_line`/`err_line` 缓冲到 `out_lines`/`err_lines`。
fn capture_sink() -> Sink {
  Sink::{ capture: true, out_lines: [], err_lines: [], }
}

///|
/// 经汇写 stdout 一行。
fn out_line(sink : Sink, s : String) -> Unit {
  if sink.capture {
    sink.out_lines.push(s)
  } else {
    println(s)
  }
}

///|
/// 经汇写 stderr 一行。
fn err_line(sink : Sink, s : String) -> Unit {
  if sink.capture {
    sink.err_lines.push(s)
  } else {
    eprintln(s)
  }
}
