#!/usr/bin/env bash
# 脚本自检：拦住「$VAR 后面紧跟中文标点」这个坑。
#
# 为什么需要它：
#   bash 在非 UTF-8 locale 下解析 `"当前是 $OS_VERSION。"` 时，
#   会把全角句号的多字节字节当成变量名的一部分，
#   于是报 `OS_VERSION: unbound variable`，而且报错位置和真实原因看着毫无关系。
#   这个坑在本项目的脚本里出现过三次，每次都花时间排查，所以固化成检查。
#
# 用法：
#   ./scripts/lint-scripts.sh          # 只报告
#   ./scripts/lint-scripts.sh --fix    # 自动加花括号
set -euo pipefail

cd "$(dirname "$0")/.."

PY="$(command -v python3)"
FIX=0
[[ "${1:-}" == "--fix" ]] && FIX=1

"$PY" - "$FIX" <<'PY'
import os
import re
import sys
import glob

fix = sys.argv[1] == "1"

# 规则一：$VAR 后面紧跟非 ASCII 字符 —— bash 会把多字节字节吞进变量名
#         报「VAR: unbound variable」，且报错位置和真实原因毫无关系
rule_var = re.compile(r'\$([A-Za-z_][A-Za-z0-9_]*)(?=[^\x00-\x7F])')
# 规则二：$ 后跟两位以上数字 —— $99 其实是 $9 + 字面量 9，$10 是 $1 + "0"；
#         想引用第 10 个位置参数必须写 ${10}。这类 bug 在 heredoc 里最常见
#         （比如把「$99 会员」写进提示文案里）
rule_pos = re.compile(r'\$([0-9]{2,})')

total = 0
changed_files = []

for path in sorted(glob.glob("scripts/*.sh")):
    # 跳过自己：本文件的说明文字里就带着 `$99`/`$10` 这类示例，
    # 而且那段是嵌在 bash 里的 Python 代码，用 shell 规则去扫必然误报。
    if os.path.basename(path) == "lint-scripts.sh":
        continue
    with open(path, encoding="utf-8") as fh:
        lines = fh.readlines()

    hits = []
    for lineno, line in enumerate(lines, 1):
        # 纯注释行跳过：注释里出现 `$VAR。` 是无害的（本条规则自己的说明就是个例子）
        if line.lstrip().startswith("#"):
            continue
        for m in rule_var.finditer(line):
            hits.append((lineno, m.group(1), line[m.end():m.end() + 1]))
        for m in rule_pos.finditer(line):
            hits.append((lineno, "$" + m.group(1), line[m.end():m.end() + 1]))

    if not hits:
        continue

    total += len(hits)
    print(f"\n{path}")
    for lineno, name, nxt in hits:
        mark = "  已自动修复" if fix else ""
        print(f"  {lineno:>4}:  {name}  后面是 {nxt!r}{mark}")
        print(f"        {lines[lineno - 1].rstrip()}")

    if fix:
        # 只自动修规则一：$VAR 粘上多字节字符时，${VAR} 永远是对的。
        # 规则二不能自动修 —— $99 多半是字面美元符号而不是位置参数，
        # 改成 ${99} 反而会坏（空值或 unbound），得人来判断是转义还是改写文案。
        for i, line in enumerate(lines):
            lines[i] = rule_var.sub(lambda m: "${%s}" % m.group(1), line)
        with open(path, "w", encoding="utf-8") as fh:
            fh.writelines(lines)
        changed_files.append(path)

print()
if total == 0:
    print("✅ 没有发现变量名粘连问题")
    sys.exit(0)

if fix:
    print(f"✅ 已自动修复 {len(changed_files)} 个文件里的多字节粘连问题：{', '.join(changed_files)}")
    print("   （位置参数类的问题要手动改，见上面列表。）")
    sys.exit(1)

print(f"❌ 发现 {total} 处变量引用问题。")
print("   · 多字节粘连：跑 ./scripts/lint-scripts.sh --fix 自动加花括号")
print("   · 位置参数（$99/$10 这种）：要么转义成 \\$99，要么改写文案去掉美元符号")
sys.exit(1)
PY
