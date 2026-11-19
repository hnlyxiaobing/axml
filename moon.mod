// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "hnlyxiaobing/axml"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/hnlyxiaobing/axml"

license = "Apache-2.0"

keywords = [ "android", "axml", "arsc", "binary-xml", "parser" ]

preferred_target = "wasm"

description = "Parse Android binary XML (AXML) and resources.arsc into readable node trees, attributes, string pools and resolved resource values, with format-level encoders."
