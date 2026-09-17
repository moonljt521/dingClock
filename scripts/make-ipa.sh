#!/usr/bin/env bash
# 打一个可以侧载（拖进手机安装）的 ipa。
#
# 用法：
#   ./scripts/make-ipa.sh                    # 用当前工具链 + Team 签名
#   ./scripts/make-ipa.sh ad-hoc             # Ad Hoc 分发包（同样只发给已登记设备）
#
# ⚠️ 无论 development 还是 ad-hoc，**都只能装进描述文件里登记过的设备**。
#    团队描述文件目前登记了 82 台设备（有效期到 2027-09-07）。
#    对方手机不在名单里的话，先去 developer.apple.com → Devices 把它的 UDID 加进去，
#    再重跑本脚本（automatic signing 会自动把新设备带进描述文件）。
#    想发给任意人且不登记设备，走 TestFlight。
set -euo pipefail

METHOD="${1:-development}"
cd "$(dirname "$0")/.."

ARCHIVE="./build/DingClock.xcarchive"
EXPORT_DIR="./build/ipa"
TEAM="75L84BV98K"

echo "==> 清理旧产物"
rm -rf "$ARCHIVE" "$EXPORT_DIR"

echo "==> Archive（Release / generic iOS）"
xcodebuild -scheme DingClock -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates archive 2>&1 \
  | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)" | sort -u

echo "==> 导出 ipa（method=${METHOD}）"
cat > ./build/exportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>$METHOD</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
    <key>stripSwiftSymbols</key><true/>
    <key>compileBitcode</key><false/>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist ./build/exportOptions.plist -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates 2>&1 | grep -iE "error:|Exported" | sort -u

IPA=$(ls "$EXPORT_DIR"/*.ipa 2>/dev/null | head -1)
[[ -n "$IPA" ]] || { echo "❌ 没找到 ipa"; exit 1; }

echo
echo "==> 校验 ipa 内容"
python3 - "$IPA" <<'PY'
import sys, zipfile, os
ipa = sys.argv[1]
z = zipfile.ZipFile(ipa)
names = z.namelist()
required = [
    "Payload/DingClock.app/DingClock",
    "Payload/DingClock.app/PlugIns/DingClockWidget.appex/DingClockWidget",
    "Payload/DingClock.app/Assets.car",
    "Payload/DingClock.app/embedded.mobileprovision",
]
missing = [p for p in required if p not in names]
for p in required:
    print(("  ✅ " if p in names else "  ❌ 缺少 ") + p.split("Payload/DingClock.app/")[-1])
if missing:
    sys.exit(1)
size = os.path.getsize(ipa)
print(f"\n  {ipa}   {size/1024:.0f} KB")
PY

echo
echo "==> 描述文件允许的设备数（对方手机必须在名单里）"
PROF=$(mktemp /tmp/prof.XXXXXX.mobileprovision)
unzip -p "$IPA" "Payload/DingClock.app/embedded.mobileprovision" > "$PROF"
security cms -D -i "$PROF" > /tmp/make-ipa-profile.plist
python3 - /tmp/make-ipa-profile.plist <<'PY'
import plistlib, sys, datetime
d = plistlib.load(open(sys.argv[1], "rb"), fmt=plistlib.FMT_XML)
print(f"    描述文件: {d.get('Name')}")
print(f"    已登记设备: {len(d.get('ProvisionedDevices', []))}")
exp = d.get("ExpirationDate")
if exp:
    print(f"    有效期至: {exp:%Y-%m-%d}")
PY
rm -f "$PROF" /tmp/make-ipa-profile.plist

echo
echo "✅ 完成：$IPA"
echo "   拖进已登记的手机（爱思助手 / Apple Configurator / iMazing 均可）即可安装。"
