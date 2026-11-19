#!/bin/bash
# Installs (or removes with --uninstall) the LaunchAgent com.user.aiusage, which runs the collector
# every 300 s and at load.
#
# The job runs a copy of the collector in ~/Library/Application Support/AIUsage/bin, never the file
# in the repo: a launchd job that runs a script from ~/Desktop, ~/Documents or ~/Downloads hangs on
# the macOS privacy (TCC) check. Each install overwrites that copy, so run install.sh again after
# every change to the collector.
set -euo pipefail

LABEL="com.user.aiusage"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="$HERE/ai_usage_collect.py"
TEMPLATE="$HERE/com.user.aiusage.plist.template"
AGENT_DIR="$HOME/Library/LaunchAgents"
PLIST="$AGENT_DIR/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/AIUsage"
APP_DIR="$HOME/Library/Application Support/AIUsage"
BIN_DIR="$APP_DIR/bin"
INSTALLED_SCRIPT="$BIN_DIR/ai_usage_collect.py"
UID_NUM="$(id -u)"

# tests/test_install.py takes install_copy, launchd_path, render_plist and remove_copy out of this file by name.

install_copy() {
    mkdir -p "$BIN_DIR"
    cp "$SOURCE_SCRIPT" "$INSTALLED_SCRIPT.tmp"
    chmod 644 "$INSTALLED_SCRIPT.tmp"
    mv "$INSTALLED_SCRIPT.tmp" "$INSTALLED_SCRIPT"
    cmp -s "$SOURCE_SCRIPT" "$INSTALLED_SCRIPT" || { echo "คัดลอก collector ไม่สำเร็จ" >&2; return 1; }
}

launchd_path() {
    # The PATH of the job. launchd gives a job only /usr/bin:/bin:/usr/sbin:/sbin, so the job gets Homebrew,
    # ~/.local/bin and the folder of each of node, claude, codex and agy as it is installed now (the folder
    # of the command as found, not a resolved symlink). The folders are fixed at install time: run
    # install.sh again after an install, upgrade or move of one of these tools.
    local dirs="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin" name found dir
    for name in node claude codex agy; do
        found="$(command -v "$name" 2>/dev/null || true)"
        case "$found" in
            /*) dir="$(dirname "$found")" ;;
            *) continue ;;
        esac
        case ":$dirs:" in
            *":$dir:"*) ;;
            *) dirs="$dirs:$dir" ;;
        esac
    done
    echo "$dirs:/usr/bin:/bin:/usr/sbin:/sbin"
}

render_plist() {
    # $1 template, $2 output, $3 python3, $4 installed script, $5 log folder, $6 app folder, $7 PATH of the job
    sed -e "s|__PYTHON3__|$3|g" -e "s|__SCRIPT__|$4|g" -e "s|__LOG_DIR__|$5|g" -e "s|__APP_DIR__|$6|g" \
        -e "s|__PATH__|$7|g" "$1" > "$2"
}

remove_copy() {
    # Only the copied script goes. usage.json, cache.json, notify-state.json and the lock files stay.
    rm -rf -- "$BIN_DIR"
}

if [ "${1:-}" = "--uninstall" ]; then
    launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    remove_copy
    echo "ถอนการติดตั้ง $LABEL แล้ว ข้อมูลใน $APP_DIR ยังอยู่"
    exit 0
fi

PYTHON3="$(command -v python3 || true)"
case "$PYTHON3" in
    /*) ;;
    *) echo "ไม่พบ python3 ที่เป็น absolute path" >&2; exit 1 ;;
esac
[ -f "$SOURCE_SCRIPT" ] || { echo "ไม่พบ $SOURCE_SCRIPT" >&2; exit 1; }
[ -f "$TEMPLATE" ] || { echo "ไม่พบ $TEMPLATE" >&2; exit 1; }
LAUNCH_PATH="$(launchd_path)"
for value in "$PYTHON3" "$INSTALLED_SCRIPT" "$LOG_DIR" "$APP_DIR" "$LAUNCH_PATH"; do
    case "$value" in
        *[\&\|\<\>]*) echo "พาธมีอักขระที่ใส่ใน plist ไม่ได้: $value" >&2; exit 1 ;;
    esac
done

mkdir -p "$LOG_DIR" "$APP_DIR" "$AGENT_DIR"
install_copy
render_plist "$TEMPLATE" "$PLIST.tmp" "$PYTHON3" "$INSTALLED_SCRIPT" "$LOG_DIR" "$APP_DIR" "$LAUNCH_PATH"
if ! plutil -lint "$PLIST.tmp" >/dev/null; then
    rm -f "$PLIST.tmp"
    echo "plist ที่สร้างไม่ถูกต้อง ยังไม่ได้ติดตั้ง" >&2
    exit 1
fi
mv "$PLIST.tmp" "$PLIST"

launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST"
echo "ติดตั้ง $LABEL แล้ว ใช้สำเนาที่ $INSTALLED_SCRIPT รันทุก 300 วินาที บันทึกล็อกที่ $LOG_DIR"
