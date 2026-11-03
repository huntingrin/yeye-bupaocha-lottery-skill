"""Background driver for macOS iPhone Mirroring — no focus stealing.

Why this exists: phone-harness posts mouse events with
CGEventPost(kCGHIDEventTap), which lands on whatever window is frontmost. On
this Mac the mirroring window sits behind other apps, so every "tap" went to
the wrong window and the only workaround was raising it — which grabs the
user's screen.

CGEventPostToPid delivers the same event straight to the mirroring process, so
none of this touches the foreground app. Verified: a click posted this way
changed the mirrored screen while Preview stayed frontmost.
"""
import subprocess
import tempfile
import time

import Quartz
import Vision
from AppKit import NSRunningApplication
from Foundation import NSURL

BUNDLE = "com.apple.ScreenContinuity"
LANGS = ["zh-Hans", "en-US"]

KEYCODES = {
    "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "esc": 53,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "v": 9, "a": 0, "c": 8, "x": 7, "z": 6,
    "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
    "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
}


def pid():
    apps = NSRunningApplication.runningApplicationsWithBundleIdentifier_(BUNDLE)
    return apps[0].processIdentifier() if apps else None


_LAST_WIN = None


def window(retries=6):
    """The phone window: owner pid + layer 0, preferring name == owner name."""
    global _LAST_WIN
    p = pid()
    if p is None:
        return None
    # CGWindowListCopyWindowInfo can come back empty for a moment while the
    # WindowServer is busy (space switch, display wake). Retry, then fall back
    # to the last window we saw rather than reporting "no window".
    for _ in range(retries):
        wins = Quartz.CGWindowListCopyWindowInfo(
            Quartz.kCGWindowListOptionAll, Quartz.kCGNullWindowID) or []
        cands = [w for w in wins
                 if w.get("kCGWindowOwnerPID") == p and w.get("kCGWindowLayer", 1) == 0]
        named = [w for w in cands
                 if w.get("kCGWindowName") == w.get("kCGWindowOwnerName")]
        pick = named or cands
        if pick:
            b = pick[0]["kCGWindowBounds"]
            _LAST_WIN = {"id": int(pick[0]["kCGWindowNumber"]),
                         "x": b["X"], "y": b["Y"],
                         "w": b["Width"], "h": b["Height"]}
            return _LAST_WIN
        time.sleep(0.25)
    return _LAST_WIN


def shot(path=None):
    """Capture the phone window by id — works while it is behind other apps."""
    path = path or tempfile.mktemp(prefix="phone-", suffix=".png")
    try:
        got_path, w = _bg().capture(path)
        return got_path, w
    except Exception:
        w = window()
        if w is None:
            raise RuntimeError("no mirroring window")
        subprocess.run(["screencapture", "-x", "-o", "-l", str(w["id"]), path],
                       check=True)
        return path, w


def ocr(path, win, langs=None):
    """Text boxes in screen points: [{text, x, y, w, h, conf}]."""
    handler = Vision.VNImageRequestHandler.alloc().initWithURL_options_(
        NSURL.fileURLWithPath_(path), None)
    req = Vision.VNRecognizeTextRequest.alloc().init()
    req.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelAccurate)
    req.setRecognitionLanguages_(langs or LANGS)
    ok, err = handler.performRequests_error_([req], None)
    if not ok:
        raise RuntimeError(f"Vision OCR failed: {err}")

    src = Quartz.CGImageSourceCreateWithURL(NSURL.fileURLWithPath_(path), None)
    props = Quartz.CGImageSourceCopyPropertiesAtIndex(src, 0, None)
    iw, ih = int(props["PixelWidth"]), int(props["PixelHeight"])
    sx, sy = win["w"] / iw, win["h"] / ih

    out = []
    for obs in req.results() or []:
        cand = obs.topCandidates_(1)
        if not cand:
            continue
        t = cand[0].string()
        bb = obs.boundingBox()
        px = bb.origin.x * iw
        py = (1.0 - bb.origin.y - bb.size.height) * ih
        out.append({
            "text": t,
            "conf": float(cand[0].confidence()),
            "x": win["x"] + (px + bb.size.width * iw / 2) * sx,
            "y": win["y"] + (py + bb.size.height * ih / 2) * sy,
            "w": bb.size.width * iw * sx,
            "h": bb.size.height * ih * sy,
        })
    return out


def screen():
    path, win = shot()
    return ocr(path, win)


def find(text, exact=False, elements=None):
    els = elements if elements is not None else screen()
    if exact:
        return [e for e in els if e["text"].strip() == text]
    return [e for e in els if text in e["text"]]


def _bg():
    """phone-harness's SkyLight backend: posts event records straight to the
    mirroring window, so the frontmost app never changes."""
    from phone_harness import background
    return background


def tap(x, y, settle=0.4):
    _bg().tap(x, y)
    time.sleep(settle)


def _key_window():
    """Mark the mirroring window as key without raising it.

    Without this the phone window is not the key window, and every synthesized
    touch is dropped on the floor — the screen keeps updating, taps do nothing.
    Needed after the app is (re)launched or another app takes focus.
    """
    b = _bg()
    pid, win = b._ctx()
    b._make_key(pid, win["id"])
    time.sleep(0.15)


def long_press(x, y, duration=0.9):
    _key_window()
    _bg().long_press(x, y, duration=duration)
    time.sleep(0.4)


def key(combo, settle=0.4):
    """combo: 'return', 'cmd+1', 'delete', ..."""
    _bg().press(combo)
    time.sleep(settle)


def type_text(text, settle=0.8):
    """Paste into the focused field without taking focus."""
    _bg().type_text(text)
    time.sleep(settle)


def tap_text(text, index=0, exact=False, elements=None):
    hits = find(text, exact=exact, elements=elements)
    if not hits:
        raise RuntimeError(f"text not found: {text!r}")
    h = hits[index]
    tap(h["x"], h["y"])
    return h


def back_home():
    key("cmd+1")


def dump(limit=40):
    for e in screen()[:limit]:
        print(f"  {e['text']!r:38} ({round(e['x'])},{round(e['y'])})")
