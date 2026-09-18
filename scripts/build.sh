#!/usr/bin/env bash
# 编译 + 测试 + 装进模拟器运行
#
# 用法：
#   ./scripts/build.sh              # 测试 + 编译 + 运行 + 截图
#   ./scripts/build.sh test         # 只生成工程并跑测试
#   ./scripts/build.sh run          # 只编译 + 运行
#
# 工具链（想让 AlarmKit 真正生效时必须指定带 iOS 26 SDK 的 Xcode）：
#   DINGCLOCK_XCODE=/Applications/Xcode-26.3.app ./scripts/build.sh
#
# 其他可选环境变量：
#   TAB=1        初始标签页（0=闹钟 1=响铃日历 2=设置）
#   SHOT=/tmp/x.png  截图输出路径
#   DEVICE="iPhone 16 Pro"  模拟器机型
set -euo pipefail

# Homebrew 在 Apple Silicon 上装在 /opt/homebrew/bin，部分环境（CI、被改过的 PATH）
# 不带这一条，会导致 xcodegen 找不到。加上是无害的兜底。
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

cd "$(dirname "$0")/.."
source scripts/lib-toolchain.sh

SCHEME="DingClock"
PROJECT="DingClock.xcodeproj"
BUNDLE_ID="com.moonding.dingclock"
DERIVED="./build"

MODE="${1:-all}"

# 工具链解析失败（退出码 2 = 没有 AlarmKit）不算致命，仍然可以验证界面
resolve_toolchain || true

# 选模拟器设备：优先用环境变量 DEVICE，否则按偏好顺序挑，最后兜底随便一台。
# 注意设备名跟着运行时走 —— iOS 26 里是 iPhone 17 系列，没有 iPhone 16 Pro。
DEVICE="${DEVICE:-}"
ALL_DEVICES="$(xcrun simctl list devices available 2>/dev/null)"
if [[ -z "$DEVICE" ]]; then
  for candidate in "iPhone 17 Pro" "iPhone 16 Pro"; do
    if grep -qF "$candidate (" <<<"$ALL_DEVICES"; then
      DEVICE="$candidate"
      break
    fi
  done
fi
if [[ -z "$DEVICE" ]]; then
  # 兜底：simctl 按运行时从旧到新列出，取最后一个就是最新的
  DEVICE="$(printf '%s\n' "$ALL_DEVICES" | grep -oE 'iPhone [^(]+' | sed 's/^ *//' | tail -1)"
fi
if [[ -z "$DEVICE" ]]; then
  echo "❌ 没找到任何可用的 iPhone 模拟器。先在 Xcode → Settings → Components 装一个 iOS 运行时。" >&2
  exit 1
fi

DESTINATION="platform=iOS Simulator,name=$DEVICE"
echo "==> 模拟器   : $DEVICE"

if [ "$MODE" = "test" ] || [ "$MODE" = "all" ]; then
  echo "==> 生成工程"
  xcodegen generate

  echo "==> 跑测试"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -destination "$DESTINATION" -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO test 2>&1 \
    | grep -E "error:|TEST (SUCCEEDED|FAILED)|Executed .* tests" | sort -u
fi

if [ "$MODE" = "run" ] || [ "$MODE" = "all" ]; then
  echo "==> 编译"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -destination "$DESTINATION" -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO build 2>&1 \
    | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u

  APP="$DERIVED/Build/Products/Debug-iphonesimulator/DingClock.app"

  echo "==> 安装并启动"
  xcrun simctl bootstatus booted -b >/dev/null 2>&1 || true
  xcrun simctl install booted "$APP"
  xcrun simctl terminate booted "$BUNDLE_ID" >/dev/null 2>&1 || true
  SIMCTL_CHILD_DINGCLOCK_TAB="${TAB:-0}" xcrun simctl launch booted "$BUNDLE_ID"

  sleep 3
  OUT="${SHOT:-/tmp/dingclock.png}"
  xcrun simctl io booted screenshot "$OUT" >/dev/null 2>&1 && echo "==> 截图：$OUT"
fi
