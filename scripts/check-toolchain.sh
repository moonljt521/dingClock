#!/usr/bin/env bash
# 报告当前机器能用的 Xcode、各自的 iOS SDK、以及是否满足 AlarmKit 的要求。
#
#   ./scripts/check-toolchain.sh
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== 当前系统 ==="
sw_vers | sed 's/^/    /'
echo "    芯片：$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 未知)"
echo

echo "=== 已安装的 Xcode ==="
found=0
for app in /Applications/Xcode*.app; do
  [[ -d "$app" ]] || continue
  found=1
  dir="$app/Contents/Developer"
  version="$(DEVELOPER_DIR="$dir" xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}')"
  sdk="$(DEVELOPER_DIR="$dir" xcodebuild -showsdks 2>/dev/null \
    | grep -oE 'iphoneos[0-9]+(\.[0-9]+)?' | sed 's/^iphoneos//' \
    | sort -t. -k1,1n -k2,2n | tail -1)"
  major="${sdk%%.*}"
  if [[ -n "$major" ]] && (( major >= 26 )); then
    alarm="✅ 可排真实系统闹钟"
  else
    alarm="❌ 只能走调试排期"
  fi
  printf "    %-28s Xcode %-8s iOS SDK %-6s %s\n" "$(basename "$app")" "${version:-?}" "${sdk:-?}" "$alarm"
done
[[ $found -eq 1 ]] || echo "    （/Applications 下没找到 Xcode）"
echo

echo "=== xcode-select 当前指向 ==="
echo "    $(xcode-select -p)"
echo

echo "=== 结论 ==="
cat <<'EOF'
    AlarmKit 需要 iOS 26+ SDK，也就是 Xcode 26 及以上。
    但 Xcode 26.4 起把最低系统提到了 macOS Tahoe 26.2。

        Xcode 16.2           最低 macOS 14.5 Sonoma   iOS 18.2 SDK   ❌
        Xcode 26 – 26.3      最低 macOS 15.6 Sequoia  iOS 26.0–26.2  ✅
        Xcode 26.4 – 26.6    最低 macOS 26.2 Tahoe    iOS 26.4–26.5  ✅ 需升系统
        Xcode 27.0           最低 macOS 26.6 Tahoe    iOS 27.0 SDK   ✅ 需升系统

    → 停在 macOS Sequoia 的话，能装到的最高版本是 Xcode 26.3（自带 iOS 26.2 SDK）。
      不需要升级 macOS。

    去哪下（App Store 只能拿到最新版，过季版本必须走开发者下载页）：
        https://developer.apple.com/download/all/?q=Xcode
        用任意**免费** Apple ID 登录，搜索 26.3，下载 Xcode_26.3_Apple_silicon.xip
        （别下 Universal —— 体积大一倍，Apple 芯片用不上）

    或者用开源 CLI 一条命令搞定登录 + 下载 + 安装：
        brew install xcodes && xcodes install 26.3

    下载完成后在 Finder 双击解压，再把解出的 Xcode.app 改名搬进 /Applications：
        mv ~/Downloads/Xcode.app /Applications/Xcode-26.3.app
    （改名必须在进入 /Applications 之前，否则会撞上现有的 Xcode.app）
        DINGCLOCK_XCODE=/Applications/Xcode-26.3.app ./scripts/upgrade-to-ios26.sh
EOF
