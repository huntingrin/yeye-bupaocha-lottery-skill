#!/bin/sh
# Re-apply the two local fixes to phone-harness after `uv tool upgrade`
# (or a reinstall) wipes site-packages. Idempotent: safe to run every time.
set -e
F="$(uv tool dir)/phone-harness/lib/python3.12/site-packages/phone_harness/ocr.py"
[ -f "$F" ] || { echo "ocr.py not found: $F" >&2; exit 1; }

python3 - "$F" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
orig = s

# 1) pyobjc 12 rejects an empty dict as VNImageRequestHandler options.
s = s.replace(
    "NSURL.fileURLWithPath_(path), {})",
    "NSURL.fileURLWithPath_(path), None)")

# 2) Vision defaults to English; Chinese UI text degrades badly.
if "setRecognitionLanguages_" not in s:
    s = s.replace(
        "    request.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelAccurate)\n",
        "    request.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelAccurate)\n"
        "    langs = [x.strip() for x in\n"
        "             os.environ.get(\"PH_OCR_LANGS\", \"zh-Hans,en-US\").split(\",\") if x.strip()]\n"
        "    if langs:\n"
        "        request.setRecognitionLanguages_(langs)\n")
if "import os" not in s[:600]:
    s = s.replace("import Quartz\nimport Vision",
                  "import os\n\nimport Quartz\nimport Vision", 1)

open(p, "w", encoding="utf-8").write(s)
print("patched" if s != orig else "already patched")
PY

# 3) open_app() with a Chinese name raises "cannot type '设' via keycodes".
F2="$(uv tool dir)/phone-harness/lib/python3.12/site-packages/phone_harness/ios.py"
python3 - "$F2" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
if "except ValueError:" in s and "CJK" in s:
    print("ios.py already patched")
else:
    s = s.replace(
        "        self.mirror.type_text(name, keystrokes=True)\n",
        "        try:\n"
        "            self.mirror.type_text(name, keystrokes=True)\n"
        "        except ValueError:\n"
        "            # ASCII-only keycodes: CJK names fall back to the clipboard path.\n"
        "            self.mirror.type_text(name)\n", 1)
    open(p, "w", encoding="utf-8").write(s)
    print("ios.py patched")
PY
