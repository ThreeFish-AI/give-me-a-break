#!/usr/bin/env bash
# Give me a break — 一键安装/升级（macOS）
# 下载 Release zip → 防御性去隔离 → 替换 /Applications/GiveMeABreak.app → 启动。
# 用法：bash install.sh [vX.Y.Z]    # 缺省安装最新正式版
# 用法示例：bash install.sh          # 最新正式版
#           bash install.sh v0.1.8   # 指定版本（含升级替换）
# 环境变量：GIVEMEABREAK_INSTALL_DIR 覆盖安装目录（测试/自定义；不退出运行中实例、不自动启动）
set -euo pipefail

REPO="ThreeFish-AI/give-me-a-break"
APP_NAME="GiveMeABreak"

log() { printf '==> %s\n' "$*"; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "本脚本仅支持 macOS。"
command -v curl  >/dev/null || die "未找到 curl。"
command -v ditto >/dev/null || die "未找到 ditto（macOS 自带）。"

# 版本参数严格校验（防拼 URL 注入）；缺省取最新正式版（API 限流时兜底走 releases/latest 302）
VER="${1:-}"
if [ -z "$VER" ]; then
  log "查询最新正式版本…"
  VER=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | sed -n 's/.*"tag_name": *"\(v[0-9][^"]*\)".*/\1/p' | head -n1 || true)
  if [ -z "$VER" ]; then
    log "API 不可用（限流/网络），走 releases/latest 302 兜底…"
    VER=$(curl -fsS --connect-timeout 15 -o /dev/null -w '%{redirect_url}' "https://github.com/$REPO/releases/latest" \
      | sed -n 's|.*/tag/\(v[0-9][^/?]*\).*|\1|p' || true)
  fi
  [ -n "$VER" ] || die "无法获取最新版本号（网络异常？），请显式指定：bash install.sh v0.1.8"
fi
echo "$VER" | grep -Eq '^v?[0-9]+\.[0-9]+\.[0-9]+$' || die "版本号格式非法：${VER}（应为 vX.Y.Z）"
case "$VER" in v*) ;; *) VER="v$VER" ;; esac

URL="https://github.com/$REPO/releases/download/$VER/give-me-a-break-${VER#v}-macos.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log "下载 $URL"
curl -fsSL "$URL" -o "$TMP/app.zip" || die "下载失败（版本不存在？）：$VER"

log "解压…"
unzip -q "$TMP/app.zip" -d "$TMP/out"
SRC="$(find "$TMP/out" -maxdepth 2 -name "$APP_NAME.app" -type d | head -n1)"
[ -n "$SRC" ] || die "zip 中未找到 $APP_NAME.app"

# 防御性去隔离：curl 下载本身不产生 quarantine，此处覆盖「浏览器下载 zip 再投喂本脚本」的场景
xattr -dr com.apple.quarantine "$SRC" 2>/dev/null || true

# 安装目标：GIVEMEABREAK_INSTALL_DIR 覆盖（测试/自定义，不退出运行中实例、不自动启动）
# → /Applications 可写直用 → sudo → ~/Applications
QUIT() {
  osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 1
}
OVERRIDE_DIR="${GIVEMEABREAK_INSTALL_DIR:-}"
if [ -n "$OVERRIDE_DIR" ]; then
  mkdir -p "$OVERRIDE_DIR"
  DEST="$OVERRIDE_DIR/$APP_NAME.app"
  log "安装到 ${DEST}（GIVEMEABREAK_INSTALL_DIR 覆盖）…"
  rm -rf "$DEST"
  ditto "$SRC" "$DEST"
elif [ -w "/Applications" ]; then
  log "安装到 /Applications（正在运行则先退出）…"
  QUIT
  rm -rf "/Applications/$APP_NAME.app"
  ditto "$SRC" "/Applications/$APP_NAME.app"
  DEST="/Applications/$APP_NAME.app"
elif sudo -v 2>/dev/null; then
  log "写入 /Applications 需要管理员权限（正在运行则先退出）…"
  QUIT
  sudo rm -rf "/Applications/$APP_NAME.app"
  sudo ditto "$SRC" "/Applications/$APP_NAME.app"
  DEST="/Applications/$APP_NAME.app"
else
  DEST="$HOME/Applications/$APP_NAME.app"
  mkdir -p "$HOME/Applications"
  log "无法写入 /Applications（且 sudo 不可用），改用 ~/Applications…"
  QUIT
  rm -rf "$DEST"
  ditto "$SRC" "$DEST"
fi

if [ -n "$OVERRIDE_DIR" ]; then
  log "覆盖目录安装完成（不自动启动）：$DEST"
  exit 0
fi

log "启动 $DEST"
open "$DEST"

cat <<'EOF'

✅ 安装完成。首次启动请在「系统设置 → 隐私与安全性」按需授予：
   • 辅助功能（控制音乐）
   • 完全日历访问（会议感知，可选）
   • 输入监控（⌃⌘Q 屏幕遮罩；授权后需重启 App 生效）
TCC 权限授权一次即可——升级替换二进制后不再重复（稳定签名）。
EOF
