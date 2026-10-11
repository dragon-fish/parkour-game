# 反编译工具链

[15-原版逻辑反编译](../15-原版逻辑反编译.md) 的结论都由这些工具产生。所有输出写到
`_local/me-re/`（gitignore，可随时重生成）。

## 脚本层：UnrealScript 字节码

1. 解压：`ue3_decompress.py <src.u> <dst.u>`，再用 `flatten_header.py <src.u> <dst.u>` 把文件头改成
   未压缩包（压缩包展开后，逻辑上的文件头是 0 个 chunk，比磁盘上的短 16 字节/chunk）。
   安装目录里的 `TdGame.u`、`Engine.u` 已被 Mirror's Edge Tweaks 存成未压缩包，可以直接用。
2. 反编译：`uedump/`（.NET 10，Eliot.UELib 1.13.7）。
   `dotnet uedump.dll [--raw] <out> Core.u Engine.u GameFramework.u TdGame.u`。
   所有包一起加载，原生运算符的名字才能解析出来。
   **美化输出会丢括号**：`a && (b || c)` 会被印成 `a && b || c`。用 `--raw` 输出（运算符保留为 `__NFUN_n__` 调用），
   再用 `paren_operators.py <raw_root> <out_root>` 改写成**每个运算符都带括号**的中缀形式。读脚本时只读这一份。

## 原生层：MirrorsEdge.exe

- 32 位 PE，SteamStub 2.1 壳（Steamless 3.1.0.5 脱壳失败，但 `.text` 未加密，不影响静态分析），基址 0x400000。
- Ghidra 12.1.4，先用 `analyzeHeadless` 建好持久化工程，之后用 `ghidra/run_script.ps1` 以 `-noanalysis -readOnly` 跑脚本：
  - `DecompileTree.java <out> <depth> <addr>[~label] ...`：反编译函数，并往下展开 depth 层调用。
  - `StringRefs.java <out> <depth> <text> ...`：按 UTF-16 字符串反查引用它的函数（找类注册、找虚表）。
  - `FindDisp.java <out> 0 <hex> ...`：列出同时用到这些偏移的函数（找消费某几个属性的代码）。
  - `Disasm.java <out> 0 <addr> ...`：反汇编，看 x87 栈传参和 `this` 指针。
  - `EmuCall.java <out> 0 <spec>`：在模拟器里执行原版函数。已补上 `rsqrtss`、`_CIpow`、`floor`，
    支持填充 UE3 的 `GSinTable`。
- 原生函数注册表：UTF-16 名字 `int<Class>exec<Func>`，`.data` 段里是 `{名字指针, 函数指针}`。
  exec 外壳解析参数后调用虚函数，例如 `ATdPawn` 的虚表在 `0x01d05268`。
- 字段偏移：`ue3_layout.py <script_root> <Class> [--grep RE] [--at HEX ...]`，按 UE3 链接规则（声明顺序、
  各自对齐、连续 bool 共用一个 32 位字）算出类布局。

## 验证

`verify/accel_ref.py` 是第 15.2 节公式的 Python 实现，并能生成模拟器用例：
`gen <spec> <n> <seed>` 生成随机输入，`EmuCall.java` 在原版机器码上执行，`check <spec> <emu_out>` 逐例比对。
300 个随机用例全部吻合（误差 ≤ 0.1，即原版自己的取整精度）。
