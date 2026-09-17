#!/usr/bin/env bash
# 把工程的最低系统版本提到 iOS 26.0，从而启用真实的 AlarmKit 响铃。
#
# 前提：装好 Xcode 26 及以上（提供 iOS 26+ SDK）。
#   macOS Sequoia 15.6+ 能装到的最高版本是 Xcode 26.3（自带 iOS 26.2 SDK）——
#   也就是说，不需要升级 macOS。
#
# 用法：
#   DINGCLOCK_XCODE=/Applications/Xcode-26.3.app ./scripts/upgrade-to-ios26.sh
#
# 业务代码不需要改动 —— 响铃层是用 #if canImport(AlarmKit) 隔离的。
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/lib-toolchain.sh

if ! resolve_toolchain; then
  echo
  echo "❌ 当前选中的工具链没有 iOS 26+ SDK，无法启用 AlarmKit。"
  echo "   跑 ./scripts/check-toolchain.sh 看看这台机器上有哪些 Xcode。"
  echo
  echo "   如果还没装：Xcode 26.3 是停留在 macOS Sequoia 上能装的最高版本，"
  echo "   自带 iOS 26.2 SDK，完全够用，且不需要升级系统。"
  exit 1
fi

echo
echo "==> 把最低系统版本提升到 iOS 26.0"
# 必须用 -0（slurp 整个文件）：deploymentTarget: 和 iOS: 不在同一行，
# 逐行处理时换行匹配不到，会导致 options.deploymentTarget 漏改
perl -0pi -e 's/(deploymentTarget:\s*\n\s*iOS:\s*)"[\d.]+"/$1"26.0"/' project.yml
perl -pi  -e 's/(IPHONEOS_DEPLOYMENT_TARGET:\s*)"[\d.]+"/$1"26.0"/' project.yml
grep -nE 'deploymentTarget:|iOS:|DEPLOYMENT_TARGET' project.yml | sed 's/^/    /'

echo
echo "==> 重新生成工程"
xcodegen generate

echo
echo "✅ 完成。现在编译即可切到真实系统闹钟："
echo "   DINGCLOCK_XCODE=${DINGCLOCK_XCODE:-\$DEVELOPER_DIR 对应的 .app} ./scripts/build.sh"
echo
echo "验证 AlarmKit 是否生效："
echo "   1. 设置页「后端」应显示「AlarmKit（系统级闹钟）」"
echo "   2. 首次使用会弹出闹钟权限请求（文案来自 NSAlarmKitUsageDescription）"
echo "   3. ⚠️ 响铃是否真突破静音模式，必须在真机上验，模拟器验不出来"
echo
echo "注意：最低系统提到 26.0 后就不能再装在 iOS 18 的模拟器上了。"
echo "     需要先用 Xcode 下载一个 iOS 26 模拟器运行时（Settings → Components），"
echo "     或者直接跑你的 iPhone 13 真机。"
