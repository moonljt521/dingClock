#!/usr/bin/env bash
# 工具链解析。
#
# 让同一套源码既能用老 Xcode 编译（走调试排期，不会真响），
# 也能用共存安装的新 Xcode 编译（接上真实 AlarmKit），不需要手工 xcode-select 切换。
#
# 用法：
#   source "$(dirname "$0")/lib-toolchain.sh"
#   resolve_toolchain
#
# 指定方式（任选其一）：
#   DINGCLOCK_XCODE=/Applications/Xcode-26.3.app ./scripts/build.sh
#   export DEVELOPER_DIR=/Applications/Xcode-26.3.app/Contents/Developer
#
# 不指定时自动挑「装了 iOS 26 及以上 SDK」的那个 Xcode；都没有就退回当前 xcode-select。

resolve_toolchain() {
  local candidate=""

  if [[ -n "${DINGCLOCK_XCODE:-}" ]]; then
    candidate="$DINGCLOCK_XCODE/Contents/Developer"
    if [[ ! -d "$candidate" ]]; then
      echo "❌ DINGCLOCK_XCODE 下找不到 Contents/Developer：$DINGCLOCK_XCODE" >&2
      return 1
    fi
  elif [[ -n "${DEVELOPER_DIR:-}" ]]; then
    candidate="$DEVELOPER_DIR"
  else
    # 先按 glob 展开，再看谁带了 iOS 26+ SDK
    local app dir
    for app in /Applications/Xcode*.app; do
      dir="$app/Contents/Developer"
      [[ -d "$dir" ]] || continue
      if DEVELOPER_DIR="$dir" xcodebuild -showsdks 2>/dev/null | grep -qE 'iphoneos(2[6-9]|[3-9][0-9])\.'; then
        candidate="$dir"
        break
      fi
    done
    [[ -z "$candidate" ]] && candidate="$(xcode-select -p)"
  fi

  export DEVELOPER_DIR="$candidate"

  local version sdk major
  version="$(xcodebuild -version 2>/dev/null | head -1)"
  sdk="$(xcodebuild -showsdks 2>/dev/null \
    | grep -oE 'iphoneos[0-9]+(\.[0-9]+)?' \
    | sed 's/^iphoneos//' \
    | sort -t. -k1,1n -k2,2n | tail -1)"
  major="${sdk%%.*}"

  echo "==> 工具链   : $DEVELOPER_DIR"
  echo "==> 版本     : ${version:-未知}"
  echo "==> iOS SDK  : ${sdk:-未知}"

  if [[ -n "$major" ]] && (( major >= 26 )); then
    echo "==> AlarmKit : ✅ 可用，会排真实的系统闹钟"
    return 0
  fi

  echo "==> AlarmKit : ⚠️  不可用（缺 iOS 26+ SDK）"
  echo "              界面与排期照常验证，但不会真响。"
  echo "              装 Xcode 26.3 即可解锁（macOS 15.6+ 就够，不需要升级系统）。"
  return 2
}
