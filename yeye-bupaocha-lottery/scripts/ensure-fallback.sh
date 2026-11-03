#!/usr/bin/env bash
# ensure-fallback.sh — 取「android-device-operator」的 GitHub 版本（兜底用）
#
# 用法:
#   bash ensure-fallback.sh [--install] [--latest] [--json]
#
# 默认 pin 到 cola-skills 的 c975a22（2026-11-03 的 main）。
# --latest 则跟随 main（不推荐，命令可能变）。
#
# 退出码:
#   0  已就绪
#   21 没有 git
#   22 克隆/拉取失败
#   23 目标目录冲突（存在但不是 git 仓库）

set -euo pipefail

REPO_URL="https://github.com/marswaveai/cola-skills.git"
PINNED="c975a22cf1a5341c85030fa642a007c3f015fa6d"
DEST="${YEYE_COLA_SKILLS_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/yeye-bupaocha-lottery/cola-skills}"

INSTALL=0
LATEST=0
JSON=0

usage() {
  cat <<'EOF'
用法: bash ensure-fallback.sh [--install] [--latest] [--json]

  --install  不存在时克隆 GitHub 仓库（稀疏检出 android-device-operator）
  --latest   跟随 main，而不是 pin 到 c975a22
  --json     输出 JSON
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --install) INSTALL=1; shift ;;
    --latest) LATEST=1; shift ;;
    --json) JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage; exit 2 ;;
  esac
done

if ! command -v git >/dev/null 2>&1; then
  echo "未找到 git；请先安装 git，或手动下载：" >&2
  echo "  https://github.com/marswaveai/cola-skills/tree/main/android-device-operator" >&2
  exit 21
fi

target="$DEST/android-device-operator"

is_git_repo() {
  [ -d "$DEST/.git" ]
}

commit_of() {
  git -C "$DEST" rev-parse HEAD 2>/dev/null || true
}

check_ok() {
  [ -f "$target/SKILL.md" ] || return 1
  if [ "$LATEST" = "1" ]; then
    return 0
  fi
  local c
  c="$(commit_of)"
  [ "$c" = "$PINNED" ]
}

if [ -d "$DEST" ] && ! is_git_repo; then
  echo "目录已存在但不是 git 仓库: $DEST" >&2
  echo "移走它或设置 YEYE_COLA_SKILLS_DIR 到别的路径。" >&2
  exit 23
fi

if ! check_ok; then
  if [ "$INSTALL" != "1" ]; then
    echo "兜底技能未就绪: $target" >&2
    echo "运行: bash \"$0\" --install" >&2
    exit 22
  fi
  if ! is_git_repo; then
    mkdir -p "$(dirname "$DEST")"
    git clone --depth 1 --filter=blob:none --sparse "$REPO_URL" "$DEST"
    git -C "$DEST" sparse-checkout set android-device-operator
  fi
  if [ "$LATEST" = "1" ]; then
    git -C "$DEST" fetch --depth 1 origin main
    git -C "$DEST" checkout --detach FETCH_HEAD
  else
    if git -C "$DEST" cat-file -e "${PINNED}^{commit}" 2>/dev/null; then
      git -C "$DEST" checkout --detach "$PINNED"
    else
      git -C "$DEST" fetch --depth 1 origin "$PINNED"
      git -C "$DEST" checkout --detach "$PINNED"
    fi
  fi
fi

if ! check_ok; then
  echo "兜底技能校验失败: $target" >&2
  exit 22
fi

C="$(commit_of)"
if [ "$JSON" = "1" ]; then
  DEST="$DEST" TARGET="$target" COMMIT="$C" PINNED="$PINNED" \
  node -e '
    console.log(JSON.stringify({
      ok: true,
      source: "github",
      path: process.env.TARGET,
      repo: process.env.DEST,
      commit: process.env.COMMIT,
      pinned: process.env.PINNED,
      url: "https://github.com/marswaveai/cola-skills/tree/main/android-device-operator"
    }, null, 2));
  '
else
  echo "GitHub 兜底技能就绪"
  echo "Path:   $target"
  echo "Commit: $C"
  echo "Pin:    $PINNED"
fi
