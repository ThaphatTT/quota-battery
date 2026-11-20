#!/bin/bash
# Builds AIUsage.app (Release, signed with your own Apple Team id) and installs it into ~/Applications.
# An existing ~/Applications/AIUsage.app is replaced. A running AIUsage is quit first and opened again.
#
# Usage:
#   scripts/build-mac.sh               build and install into ~/Applications
#   scripts/build-mac.sh --no-install  build only; the app is copied to mac/build/AIUsage.app
#
# The Team id comes from DEVELOPMENT_TEAM in the environment, or else from mac/Local.xcconfig
# (copy mac/Local.xcconfig.example and fill it in). AGENTS.md explains how to find the Team id.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC_DIR="$ROOT/mac"
LOCAL_XCCONFIG="$MAC_DIR/Local.xcconfig"
PLACEHOLDER="YOURTEAMID"
APP_NAME="AIUsage.app"
INSTALL_DIR="$HOME/Applications"
INSTALL=1
DERIVED=""
APP_BUNDLE_ID="local.aiusage.AIUsage"
APP_PROCESS="AIUsage"
# The widget extension runs as its own process. The [A] keeps pkill from matching the shell that runs this
# pattern, because the pattern would otherwise appear in that shell's own command line.
WIDGET_PATTERN="[A]IUsage.app/Contents/PlugIns/AIUsageWidget.appex"

cleanup() {
    # Removes the temp DerivedData, if one was made. This runs on every exit, after main has returned,
    # so the variable must be global.
    if [ -n "$DERIVED" ]; then
        rm -rf "$DERIVED"
    fi
}
trap cleanup EXIT

fail() {
    echo "build-mac.sh: $*" >&2
    exit 1
}

usage() {
    sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Prints the last DEVELOPMENT_TEAM value in an xcconfig file, or nothing when there is none.
team_from_xcconfig() {
    local file="$1"
    [ -f "$file" ] || return 0
    sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*\([A-Za-z0-9]*\).*$/\1/p' "$file" \
        | tail -n 1
}

# Prints the Team id to build with. Returns 1 when there is none, or when it is still the placeholder.
resolve_team() {
    local team="${DEVELOPMENT_TEAM:-}"
    if [ -z "$team" ]; then
        team="$(team_from_xcconfig "$LOCAL_XCCONFIG")"
    fi
    if [ -z "$team" ] || [ "$team" = "$PLACEHOLDER" ]; then
        return 1
    fi
    printf '%s\n' "$team"
}

# Quits the running AIUsage app before its bundle is replaced. Returns 0 only when an app was running.
# The app is asked to quit first, and it is terminated only if it is still running after 10 seconds.
quit_running_app() {
    pgrep -x "$APP_PROCESS" >/dev/null 2>&1 || return 1
    echo "ปิดแอป AIUsage ที่กำลังทำงานก่อนติดตั้งทับ"
    osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    local _
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x "$APP_PROCESS" >/dev/null 2>&1 || return 0
        sleep 1
    done
    echo "แอป AIUsage ยังไม่ปิด จึงบังคับปิด" >&2
    pkill -x "$APP_PROCESS" >/dev/null 2>&1 || true
    sleep 1
    return 0
}

# Stops the widget extension of the installed app. The old extension keeps running the old code until it is
# stopped; macOS then starts it again from the new copy. pkill exits with 1 when nothing matches, which is fine.
stop_widget_extension() {
    echo "หยุดกระบวนการวิดเจ็ตเก่า (ถ้ามี) เพื่อให้ macOS โหลดโค้ดใหม่"
    pkill -f "$WIDGET_PATTERN" >/dev/null 2>&1 || true
}

main() {
    local arg team product dest was_running
    for arg in "$@"; do
        case "$arg" in
            --no-install) INSTALL=0 ;;
            -h|--help) usage; exit 0 ;;
            *) fail "ไม่รู้จักตัวเลือก $arg (ใช้ --no-install หรือ --help)" ;;
        esac
    done

    [ "$(uname -s)" = "Darwin" ] || fail "สคริปต์นี้ใช้ได้บน macOS เท่านั้น"
    command -v xcodegen >/dev/null 2>&1 || fail "ไม่พบ xcodegen ติดตั้งด้วย: brew install xcodegen"
    xcodebuild -version >/dev/null 2>&1 \
        || fail "xcodebuild ใช้ไม่ได้ ติดตั้ง Xcode และเลือกด้วย xcode-select ก่อน"

    if ! team="$(resolve_team)"; then
        fail "ไม่พบ Team id ของ Apple
  1. คัดลอก mac/Local.xcconfig.example เป็น mac/Local.xcconfig
  2. ใส่ Team id ของคุณแทน YOURTEAMID (วิธีหาดูใน AGENTS.md)
  หรือกำหนดตัวแปร DEVELOPMENT_TEAM ก่อนรันสคริปต์ก็ได้"
    fi

    echo "สร้างโปรเจกต์ด้วย xcodegen"
    (cd "$MAC_DIR" && xcodegen generate)

    # The build output goes to a temp folder that cleanup removes on exit. The app is copied out first.
    DERIVED="$(mktemp -d "${TMPDIR:-/tmp}/aiusage-derived.XXXXXX")"

    echo "สร้าง AIUsage แบบ Release"
    xcodebuild -project "$MAC_DIR/AIUsage.xcodeproj" -scheme AIUsage -configuration Release \
        -derivedDataPath "$DERIVED" "DEVELOPMENT_TEAM=$team" -allowProvisioningUpdates build

    product="$DERIVED/Build/Products/Release/$APP_NAME"
    [ -d "$product" ] || fail "สร้างเสร็จแต่ไม่พบ $APP_NAME ที่คาดไว้"

    if [ "$INSTALL" = 1 ]; then
        dest="$INSTALL_DIR/$APP_NAME"
    else
        dest="$MAC_DIR/build/$APP_NAME"
    fi
    mkdir -p "$(dirname "$dest")"
    rm -rf "$dest.new"
    ditto "$product" "$dest.new"

    # A running app must be quit before its bundle is replaced, and it is opened again afterwards.
    # Only the install path does this, so --no-install never touches a running app.
    was_running=0
    if [ "$INSTALL" = 1 ] && quit_running_app; then
        was_running=1
    fi
    rm -rf "$dest"
    mv "$dest.new" "$dest"

    if [ "$INSTALL" = 1 ]; then
        echo "ติดตั้งแล้วที่ $dest"
        stop_widget_extension
        if [ "$was_running" = 1 ]; then
            echo "เปิดแอป AIUsage อีกครั้ง"
            open "$dest" || echo "เปิดแอป AIUsage ไม่สำเร็จ เปิดเองได้จาก $dest" >&2
        fi
        echo "เปิดแอป AIUsage หนึ่งครั้ง แล้วเพิ่มวิดเจ็ต Quota Battery จากหน้าวิดเจ็ตของ macOS"
    else
        echo "สร้างแล้วที่ $dest (ยังไม่ได้ติดตั้ง)"
    fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
