#!/bin/bash
# =============================================================================
# R18 manual e2e checklist runner — sandbox scenarios that xcodebuild cannot
# cover (see AGENTS.md "WidgetKit desktop widget — R18 e2e checklist").
#
# The script performs the file/process operations for each scenario and
# prints the EXPECTED desktop result. A human watches the desktop widget and
# confirms. Snapshot is backed up on start and restored on exit (trap).
#
# Prereqs:
#   - Token King.app installed (./scripts/build-and-install.sh) and running
#     at least once so the snapshot file exists.
#   - At least one Token King widget on the desktop.
#
# Widget refresh note: the widget follows a 15-min timeline. After each
# scenario the app usually pushes a reload via WidgetCenter; if it doesn't
# (app killed), either wait for the next refresh or remove/re-add the widget
# to force a fresh timeline.
# =============================================================================
set -euo pipefail

APP_NAME="Token King"
SHARED_DIR="$HOME/Library/Application Support/com.tokenking.app.shared"
SNAPSHOT="$SHARED_DIR/widget-snapshot.json"
BACKUP="$SHARED_DIR/widget-snapshot.json.r18-backup"

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }

cleanup() {
    echo
    bold "== Cleanup: restoring original snapshot =="
    if [ -f "$BACKUP" ]; then
        mv "$BACKUP" "$SNAPSHOT"
        green "snapshot restored"
    fi
    if ! pgrep -x "$APP_NAME" >/dev/null; then
        yellow "relaunching $APP_NAME..."
        open -a "$APP_NAME" || yellow "could not relaunch — open it manually"
    fi
}
trap cleanup EXIT

wait_key() {
    echo
    read -r -p "按回车进入下一个场景 / Press Enter for next scenario..." _
    echo
}

expect() {
    yellow "预期桌面表现 / EXPECTED:"
    echo "  $1"
    echo "  (widget 15 分钟刷新一次；看不到变化就移除再添加 widget 强制刷新)"
}

# --- Preflight ---------------------------------------------------------------
bold "== R18 manual e2e — preflight =="
if [ ! -f "$SNAPSHOT" ]; then
    echo "snapshot not found at: $SNAPSHOT"
    echo "先启动一次 $APP_NAME 让它写出 snapshot，再运行本脚本。"
    exit 1
fi
cp "$SNAPSHOT" "$BACKUP"
green "snapshot backed up"
echo "场景开始。请保持桌面 widget 可见。"
wait_key

# --- Scenario 1: no file -----------------------------------------------------
bold "== 场景 1/5: No file =="
echo "操作: 杀掉主 app，移除 snapshot 文件"
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1
mv "$SNAPSHOT" "$SNAPSHOT.r18-tmp"
expect 'widget 显示空态 "Open Token King to populate"'
wait_key

# --- Scenario 2: corrupt JSON ------------------------------------------------
bold "== 场景 2/5: Corrupt JSON =="
echo "操作: 写入 'not json'"
echo 'not json' > "$SNAPSHOT"
expect 'widget 显示 "Snapshot corrupt"；Console 里 subsystem=com.tokenking category=widget.provider 有 error 日志'
wait_key

# --- Scenario 3: half-written JSON -------------------------------------------
bold "== 场景 3/5: Half-written JSON =="
HALF=$(( $(stat -f%z "$BACKUP") / 2 ))
echo "操作: 截断到前 $HALF 字节"
head -c "$HALF" "$BACKUP" > "$SNAPSHOT"
expect 'widget 显示 "Snapshot corrupt"（与场景 2 相同）'
wait_key

# --- Scenario 4: stale snapshot ----------------------------------------------
bold "== 场景 4/5: Stale snapshot =="
echo "操作: 恢复完好内容，但把 mtime 改到 2020-01-01"
cp "$BACKUP" "$SNAPSHOT"
touch -t 202001010000 "$SNAPSHOT"
expect 'widget 顶部出现 "Stale XXm" 徽标，下方仍显示旧数据'
echo "注意: stale 判定读的是 JSON 内的 snapshotAt 字段，不是 mtime；"
echo "如果没看到徽标，属正常——该场景真正由 WidgetSnapshotReaderTests 覆盖。"
wait_key

# --- Scenario 5: app restart recovery ----------------------------------------
bold "== 场景 5/5: 重启恢复 =="
rm -f "$SNAPSHOT.r18-tmp"
cp "$BACKUP" "$SNAPSHOT"
echo "操作: 重新启动主 app，等待它写出新 snapshot（写盘节流约 30s）"
open -a "$APP_NAME"
echo "等待 40s..."
sleep 40
if [ -f "$SNAPSHOT" ]; then
    green "snapshot 已重写"
else
    yellow "snapshot 尚未出现——再多等一会或检查 app 是否报错"
fi
expect 'widget 恢复新鲜数据渲染，无 Stale 徽标'
wait_key

bold "== 全部场景结束 =="
echo "退出时会自动恢复原始 snapshot 并确保 app 在运行。"
