#!/usr/bin/env bash
# 老项目迁移体检：在把工程切到 Xcode 26 之前，先看看会不会炸。
#
# 用法：
#   ./scripts/check-project-compat.sh /path/to/Old.xcodeproj
#   ./scripts/check-project-compat.sh /path/to/Old.xcworkspace [SchemeName]
#
# 想指定用哪个 Xcode 来体检（比如装好的 26.3）：
#   DINGCLOCK_XCODE=/Applications/Xcode-26.3.app ./scripts/check-project-compat.sh ...
set -euo pipefail

source "$(dirname "$0")/lib-toolchain.sh"

CONTAINER_ARG="${1:-}"
SCHEME_ARG="${2:-}"

if [[ -z "$CONTAINER_ARG" ]]; then
  cat <<'EOF'
用法：./scripts/check-project-compat.sh <工程或工作区路径> [Scheme]

例：
  ./scripts/check-project-compat.sh ~/proj/OldApp.xcodeproj
  DINGCLOCK_XCODE=/Applications/Xcode-26.3.app \
    ./scripts/check-project-compat.sh ~/proj/OldApp.xcworkspace OldApp
EOF
  exit 1
fi

if [[ ! -d "$CONTAINER_ARG" ]]; then
  echo "❌ 找不到：$CONTAINER_ARG" >&2
  exit 1
fi

case "$CONTAINER_ARG" in
  *.xcworkspace) CONTAINER=(-workspace "$CONTAINER_ARG") ;;
  *.xcodeproj)   CONTAINER=(-project  "$CONTAINER_ARG") ;;
  *) echo "❌ 路径必须以 .xcodeproj 或 .xcworkspace 结尾" >&2; exit 1 ;;
esac

echo "=== 工具链 ==="
resolve_toolchain || true
echo

# ---------------------------------------------------------------- SDK 声明的范围

SDK_DIR="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)"
SDK_SETTINGS="$SDK_DIR/SDKSettings.plist"
SDK_VERSION="$(basename "${SDK_DIR:-unknown}")"

VDT=""
[[ -f "$SDK_SETTINGS" ]] && VDT="$(/usr/libexec/PlistBuddy -c \
  'Print :SupportedTargets:iphoneos:ValidDeploymentTargets' "$SDK_SETTINGS" 2>/dev/null || true)"

SDK_MIN="$(echo "$VDT" | grep -oE '[0-9]+(\.[0-9]+)?' | sort -t. -k1,1n -k2,2n | head -1 || true)"
SDK_MAX="$(echo "$VDT" | grep -oE '[0-9]+(\.[0-9]+)?' | sort -t. -k1,1n -k2,2n | tail -1 || true)"

echo "=== 这份 SDK 官方支持的部署目标范围 ==="
echo "    SDK      : ${SDK_VERSION}"
echo "    范围     : ${SDK_MIN:-?} ～ ${SDK_MAX:-?}"
echo

# ---------------------------------------------------------------- 工程设置

LIST_OUT="$(xcodebuild -list "${CONTAINER[@]}" 2>/dev/null || true)"
SCHEME="$SCHEME_ARG"
if [[ -z "$SCHEME" ]]; then
  SCHEME="$(printf '%s\n' "$LIST_OUT" \
    | sed -n '/Schemes:/,$p' | tail -n +2 \
    | grep -v '^[[:space:]]*$' | head -1 \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
fi

if [[ -z "$SCHEME" ]]; then
  echo "❌ 没能自动识别 scheme，请把它作为第二个参数传进来。" >&2
  printf '%s\n' "$LIST_OUT" | sed 's/^/    /' >&2
  exit 1
fi

echo "=== 工程设置 ==="
echo "    工程     : $(basename "$CONTAINER_ARG")"
echo "    Scheme   : $SCHEME"

BUILD_SETTINGS="$(xcodebuild "${CONTAINER[@]}" -scheme "$SCHEME" -showBuildSettings 2>/dev/null || true)"
if [[ -z "$BUILD_SETTINGS" ]]; then
  echo "❌ 读不到 build settings。先确认这个 scheme 能正常编译。" >&2
  exit 1
fi

get_setting() {
  # 注意：-showBuildSettings 每行都有缩进，比较前要把行首空白剥掉
  printf '%s\n' "$BUILD_SETTINGS" | awk -F' = ' -v k="$1" '
    { key = $1; sub(/^[ \t]+/, "", key); sub(/[ \t]+$/, "", key)
      if (key == k) { print $2; exit } }'
}

DEP_TARGET="$(get_setting IPHONEOS_DEPLOYMENT_TARGET)"
SWIFT_VERSION="$(get_setting SWIFT_VERSION)"
SRCROOT="$(get_setting SRCROOT)"
INFOPLIST_REL="$(get_setting INFOPLIST_FILE)"
GENERATE_PLIST="$(get_setting GENERATE_INFOPLIST_FILE)"
COMPAT_KEY_SETTING="$(get_setting INFOPLIST_KEY_UIDesignRequiresCompatibility)"

echo "    部署目标 : iOS ${DEP_TARGET:-未知}"
echo "    Swift    : ${SWIFT_VERSION:-未知}"
echo

# ---------------------------------------------------------------- Liquid Glass

echo "=== Liquid Glass 影响 ==="
GLASS_NOTE=""
if [[ -n "$COMPAT_KEY_SETTING" ]]; then
  GLASS_NOTE="INFOPLIST_KEY_UIDesignRequiresCompatibility = $COMPAT_KEY_SETTING"
elif [[ -n "$INFOPLIST_REL" && -f "$SRCROOT/$INFOPLIST_REL" ]]; then
  PLIST="$SRCROOT/$INFOPLIST_REL"
  if /usr/libexec/PlistBuddy -c "Print :UIDesignRequiresCompatibility" "$PLIST" >/dev/null 2>&1; then
    GLASS_NOTE="Info.plist 里 UIDesignRequiresCompatibility = $(/usr/libexec/PlistBuddy -c 'Print :UIDesignRequiresCompatibility' "$PLIST")"
  fi
fi

if [[ -n "$GLASS_NOTE" ]]; then
  echo "    ✅ 已经opt out：$GLASS_NOTE"
  echo "       用 Xcode 26 编译时外观保持不变。"
  echo "       ⚠️ 但 Apple 打算在 Xcode 27 移除这个开关，到时要么重做 UI，要么停在 Xcode 26。"
else
  echo "    ⚠️  没有 UIDesignRequiresCompatibility"
  echo "       用 Xcode 26 编译后，在 iOS 26 设备上界面会自动变成 Liquid Glass 外观。"
  echo "       想先保持不变，就加进 Info.plist："
  echo "           UIDesignRequiresCompatibility = YES  (Boolean)"
  echo "       注意这是**全局**生效的，整个 App 都会回到旧外观。"
fi
echo

# ---------------------------------------------------------------- 部署目标判定

echo "=== 部署目标判定 ==="
echo "    （依据：当前选中的 ${SDK_VERSION}，支持范围 ${SDK_MIN:-?} ～ ${SDK_MAX:-?}）"
echo
if [[ -z "$DEP_TARGET" || -z "$SDK_MIN" ]]; then
  echo "    ⚠️  信息不足，跳过。"
else
  DEP_MAJOR="${DEP_TARGET%%.*}"
  MIN_MAJOR="${SDK_MIN%%.*}"

  if (( DEP_MAJOR >= MIN_MAJOR )); then
    echo "    ✅ iOS ${DEP_TARGET} 在官方支持范围内（${SDK_MIN} ～ ${SDK_MAX}）"
  else
    echo "    ⚠️  iOS ${DEP_TARGET} 低于官方支持范围下限 ${SDK_MIN}"
    echo
    echo "       在 **Xcode 26** 上：这只是一条黄色警告，编译照常进行。"
    echo "       在 **Xcode 27** 上：这会变成红色错误，编译直接中止。"
    echo
    echo "       实测到的警告原文长这样（把部署目标临时改成 11.0 跑出来的）："
    echo "           warning: The iOS Simulator deployment target 'IPHONEOS_DEPLOYMENT_TARGET'"
    echo "           is set to 11.0, but the range of supported deployment target versions"
    echo "           is 12.0 to 18.2.99."
    echo
    if [[ "$DEP_TARGET" == "14"* ]]; then
      echo "       💡 iOS 14 → 15 不会损失任何设备。"
      echo "          iOS 15 支持的全部机型和 iOS 14 完全一致（最低都是 iPhone 6s / SE 一代）。"
      echo "          所以把部署目标抬到 15.0 是零成本的，还能顺手消掉这条警告。"
    fi
  fi

  if [[ "$MIN_MAJOR" -lt 15 ]]; then
    echo
    echo "    ⓘ 注意：上面这个判定用的是当前工具链（${SDK_VERSION}）。"
    echo "      苹果表里 Xcode 26 的部署目标下限是 iOS 15.0 —— 换成 Xcode 26 后判定会变严。"
    echo "      装好之后请用目标 Xcode 再跑一次，那才是迁移后的真实情况："
    echo "          DINGCLOCK_XCODE=/Applications/Xcode-26.3.app $0 $CONTAINER_ARG"
  fi
fi
echo

cat <<'EOF'
=== 结论 ===

  装 Xcode 26.3 不会影响老项目，前提是：
    · 装成独立的 Xcode-26.3.app，不覆盖 /Applications/Xcode.app
    · 不要改 xcode-select（改了的话命令行/CI 才会跟着切过去）

  老项目在 Xcode 26.3 下的表现：
    · 编译 / Archive        可以，低部署目标只报警告
    · 装到 iOS 14 设备上     可以 —— 决定能不能装的是部署目标，不是 Xcode 版本
    · App Store 提交         2026-04-28 起强制 Xcode 26 + iOS 26 SDK 构建，
                            但**不要求**提高部署目标
    · 界面外观               会被 Liquid Glass 改掉，用 UIDesignRequiresCompatibility 先顶住

  想完全不受影响：老项目继续用 Xcode 16.2 编，两个 Xcode 并存互不干扰。
EOF
