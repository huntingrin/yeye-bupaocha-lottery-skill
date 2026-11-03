#!/usr/bin/env bash
# android-bootstrap.sh — ADB 自检 + 设备选择 + Mika 检测
#
# 用法:
#   bash android-bootstrap.sh [--json] [--install-adb] [--serial <id>]
#
# 退出码:
#   0  就绪
#   10 adb 不存在 / 安装失败
#   11 没有设备
#   12 多台设备，需要 --serial
#   13 设备未授权 / 离线
#   20 缺少 node
#
# 这个脚本只负责「连接」和「探测」，不安装 Mika、不操作微信。

set -euo pipefail

JSON=0
INSTALL=0
SERIAL=""

usage() {
  cat <<'EOF'
用法: bash android-bootstrap.sh [--json] [--install-adb] [--serial <id>]

  --json         输出 JSON
  --install-adb  找不到 adb 时尝试安装（macOS: brew cask；Linux: apt/dnf/pacman）
  --serial <id>  指定设备（多台设备时必填）
  -h, --help     显示帮助
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1; shift ;;
    --install-adb) INSTALL=1; shift ;;
    --serial)
      [ $# -ge 2 ] || { echo "缺少 --serial 的值" >&2; exit 2; }
      SERIAL="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage; exit 2 ;;
  esac
done

OS="$(uname -s)"
FALLBACK_URL="https://github.com/marswaveai/cola-skills/tree/main/android-device-operator"

find_adb() {
  if command -v adb >/dev/null 2>&1; then
    command -v adb
    return 0
  fi
  local p
  for p in \
    "${ANDROID_HOME:-}/platform-tools/adb" \
    "${ANDROID_SDK_ROOT:-}/platform-tools/adb" \
    "$HOME/Library/Android/sdk/platform-tools/adb" \
    "$HOME/Android/Sdk/platform-tools/adb" \
    "${LOCALAPPDATA:-}/Android/Sdk/platform-tools/adb.exe" \
    "$HOME/AppData/Local/Android/Sdk/platform-tools/adb.exe" \
    "C:/Android/platform-tools/adb.exe" \
    "/opt/homebrew/bin/adb" \
    "/usr/local/bin/adb" \
    "/usr/bin/adb"; do
    if [ -n "$p" ] && [ -x "$p" ]; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

install_adb() {
  echo "未找到 adb，尝试安装..." >&2
  case "$OS" in
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        brew install --cask android-platform-tools
      else
        echo "未找到 Homebrew。请安装 Android SDK Platform-Tools:" >&2
        echo "  https://developer.android.com/tools/releases/platform-tools" >&2
        return 1
      fi
      ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y android-tools-adb
      elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y android-tools
      elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm android-tools
      else
        echo "没有可用的包管理器。请手动安装 platform-tools。" >&2
        return 1
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      if command -v winget.exe >/dev/null 2>&1; then
        winget.exe install --id Google.PlatformTools -e \
          --accept-source-agreements --accept-package-agreements
      else
        echo "未找到 winget。请安装 Android SDK Platform-Tools 并加入 PATH:" >&2
        echo "  https://developer.android.com/tools/releases/platform-tools" >&2
        return 1
      fi
      ;;
    *)
      echo "当前系统不支持自动安装: $OS" >&2
      return 1
      ;;
  esac
}

ADB="$(find_adb || true)"
if [ -z "$ADB" ] && [ "$INSTALL" = "1" ]; then
  install_adb || true
  ADB="$(find_adb || true)"
fi
if [ -z "$ADB" ]; then
  echo "未找到 adb。先安装 Android SDK Platform-Tools，或加 --install-adb 重跑。" >&2
  echo "macOS: brew install --cask android-platform-tools" >&2
  echo "下载: https://developer.android.com/tools/releases/platform-tools" >&2
  exit 10
fi

if ! command -v node >/dev/null 2>&1; then
  echo "未找到 node；Mika 和 android-device-operator 都需要 Node.js。" >&2
  exit 20
fi

"$ADB" start-server >/dev/null 2>&1 || true

DEVICES_RAW="$("$ADB" devices -l 2>/dev/null | tr -d '\r' | awk 'NR>1 && NF>=2 && $1 !~ /^\*/ {print $1" "$2}')"

if [ -z "$DEVICES_RAW" ]; then
  echo "没有检测到安卓设备。" >&2
  echo "1) 插上数据线；2) 手机开发者选项里打开 USB 调试；3) 手机上点「允许 USB 调试」。" >&2
  exit 11
fi

if [ -n "$SERIAL" ]; then
  LINE="$(printf '%s\n' "$DEVICES_RAW" | awk -v s="$SERIAL" '$1==s {print; exit}')"
  if [ -z "$LINE" ]; then
    echo "指定的设备不在列表里: $SERIAL" >&2
    echo "当前设备:" >&2
    printf '%s\n' "$DEVICES_RAW" >&2
    exit 11
  fi
  DEVICE_STATE="$(printf '%s\n' "$LINE" | awk '{print $2}')"
else
  COUNT="$(printf '%s\n' "$DEVICES_RAW" | wc -l | tr -d ' ')"
  if [ "$COUNT" -gt 1 ]; then
    echo "检测到多台设备，请用 --serial 指定：" >&2
    printf '%s\n' "$DEVICES_RAW" >&2
    exit 12
  fi
  SERIAL="$(printf '%s\n' "$DEVICES_RAW" | awk '{print $1}')"
  DEVICE_STATE="$(printf '%s\n' "$DEVICES_RAW" | awk '{print $2}')"
fi

if [ "$DEVICE_STATE" != "device" ]; then
  echo "设备 $SERIAL 状态是 $DEVICE_STATE，不是 device。" >&2
  if [ "$DEVICE_STATE" = "unauthorized" ]; then
    echo "请在手机上点「允许 USB 调试」，然后重跑。" >&2
  else
    echo "请重新插线/解锁手机/关闭再打开 USB 调试，然后重跑。" >&2
  fi
  exit 13
fi

MIKA=0
if "$ADB" -s "$SERIAL" shell pm list packages 2>/dev/null \
  | tr -d '\r' | grep -qx 'package:com.wangzan101.mika'; then
  MIKA=1
fi

FALLBACK=""
FALLBACK_SOURCE="none"
GITHUB_FALLBACK="${YEYE_COLA_SKILLS_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/yeye-bupaocha-lottery/cola-skills}/android-device-operator"

for p in \
  "${ANDROID_DEVICE_OPERATOR_SKILL:-}" \
  "$GITHUB_FALLBACK" \
  "$HOME/.agents/skills/android-device-operator" \
  "$HOME/Project/android-device-operator"; do
  if [ -n "$p" ] && [ -d "$p" ]; then
    FALLBACK="$p"
    case "$p" in
      "${ANDROID_DEVICE_OPERATOR_SKILL:-}") FALLBACK_SOURCE="env" ;;
      "$GITHUB_FALLBACK") FALLBACK_SOURCE="github" ;;
      *) FALLBACK_SOURCE="local" ;;
    esac
    break
  fi
done

if [ "$JSON" = "1" ]; then
  OS_NAME="$OS" ADB_PATH="$ADB" SERIAL="$SERIAL" STATE="$DEVICE_STATE" \
  MIKA="$MIKA" FALLBACK="$FALLBACK" FALLBACK_SOURCE="$FALLBACK_SOURCE" \
  FALLBACK_URL="$FALLBACK_URL" \
  node -e '
    const mika = process.env.MIKA === "1";
    const source = process.env.FALLBACK_SOURCE || "none";
    const fallbackNext = source === "github"
      ? ["加载 GitHub 克隆的 android-device-operator，preflight 后用 device 通道兜底"]
      : source === "local"
        ? ["加载本地 android-device-operator（非 GitHub 克隆）；严格使用 GitHub 版先跑 ensure-fallback.sh --install"]
        : ["先跑 ensure-fallback.sh --install，再加载 android-device-operator"];
    const out = {
      ok: true,
      os: process.env.OS_NAME,
      adb: process.env.ADB_PATH,
      serial: process.env.SERIAL,
      state: process.env.STATE,
      mika: mika,
      fallback_skill: process.env.FALLBACK || null,
      fallback_source: source,
      fallback_url: process.env.FALLBACK_URL,
      next: mika
        ? ["加载 mika-wechat-mini-program，跑 mika.mjs sync/state，再执行本 skill 的 flow"]
        : fallbackNext
    };
    console.log(JSON.stringify(out, null, 2));
  '
else
  echo "OS:       $OS"
  echo "ADB:      $ADB"
  echo "Device:   $SERIAL"
  echo "State:    $DEVICE_STATE"
  echo "Mika:     $([ "$MIKA" = "1" ] && echo yes || echo no)"
  echo "Fallback: ${FALLBACK:-未安装} (${FALLBACK_SOURCE})"
  if [ "$MIKA" = "1" ]; then
    echo "Next:     加载 mika-wechat-mini-program，跑 mika.mjs sync/state"
  else
    case "$FALLBACK_SOURCE" in
      github)
        echo "Next:     加载 GitHub 克隆的 android-device-operator，preflight 后用 device 通道" ;;
      local)
        echo "Next:     加载本地 android-device-operator（非 GitHub 克隆）"
        echo "          严格使用 GitHub 版：bash \"$(dirname "$0")/ensure-fallback.sh\" --install" ;;
      *)
        echo "Next:     先跑 ensure-fallback.sh --install，再加载 android-device-operator" ;;
    esac
    echo "URL:      $FALLBACK_URL"
  fi
fi
