#!/usr/bin/env bash
# iphone-bootstrap.sh — iPhone 镜像 + phone-harness 自检
#
# 用法:
#   bash iphone-bootstrap.sh
#
# 退出码:
#   0  就绪
#   10 phone-harness / pyobjc 缺失
#   11 镜像未连接 / 手机被占用 / 锁屏
#   12 没有可用的 iOS driver

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIKA_SKILL="${MIKA_SKILL:-$HOME/.agents/skills/mika-wechat-mini-program}"

UV_DIR=""
if command -v uv >/dev/null 2>&1; then
  UV_DIR="$(uv tool dir 2>/dev/null || true)"
fi

PY="${PHONE_HARNESS_PY:-${UV_DIR:+$UV_DIR/phone-harness/bin/python}}"
if [ -z "$PY" ] || [ ! -x "$PY" ]; then
  PY="$(command -v python3 || true)"
fi

if [ -z "$PY" ] || [ ! -x "$PY" ]; then
  echo '{"ok":false,"reason":"python_missing","next":"安装 Python 3，或 uv tool install phone-harness"}'
  exit 10
fi

if ! "$PY" -c 'import Quartz, Vision, phone_harness' >/dev/null 2>&1; then
  echo '{"ok":false,"reason":"phone_harness_missing","next":"uv tool install phone-harness，然后 bash scripts/repatch.sh"}'
  exit 10
fi

DRIVER=""
if [ -f "$MIKA_SKILL/scripts/ios_bridge.py" ]; then
  DRIVER="$MIKA_SKILL/scripts/ios_bridge.py"
elif [ -f "$SKILL_DIR/scripts/iphone.py" ]; then
  DRIVER="$SKILL_DIR/scripts/iphone.py"
else
  echo '{"ok":false,"reason":"ios_driver_missing","next":"安装 mika-wechat-mini-program，或用本 skill 的 scripts/iphone.py"}'
  exit 12
fi

"$PY" - "$DRIVER" "$PY" <<'PY'
import json
import subprocess
import sys

driver, py = sys.argv[1], sys.argv[2]
p = subprocess.run([py, driver, "state"], capture_output=True, text=True)
try:
    data = json.loads(p.stdout)
except Exception:
    data = {
        "ok": False,
        "reason": "driver_state_failed",
        "stdout": (p.stdout or "")[-500:],
        "stderr": (p.stderr or "")[-500:],
    }
data["driver"] = driver
data["python"] = py
print(json.dumps(data, ensure_ascii=False, indent=2))
sys.exit(0 if data.get("ok") else 11)
PY
