#!/usr/bin/env python3
"""iPhone Mirroring driver CLI for the 爷爷不泡茶 skill.

Runs inside the phone-harness Python (pyobjc + Vision). Uses bgphone's
background SkyLight backend so taps do not steal the user's focus.

Examples:
  python iphone.py state
  python iphone.py screen --json
  python iphone.py find --text 百万奖池
  python iphone.py tap-text --text 百万奖池
  python iphone.py long-press --x 1500 --y 900 --duration 0.5
  python iphone.py type --text yeye
  python iphone.py key --key return
  python iphone.py home
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bgphone as P  # noqa: E402


def _window_or_fail():
    w = P.window()
    if not w:
        print(json.dumps({
            "ok": False,
            "error": "no_mirroring_window",
            "next": "打开 iPhone Mirroring、解锁手机，保持窗口可见后重试"
        }, ensure_ascii=False))
        raise SystemExit(2)
    return w


def _elements():
    return P.screen()


def cmd_state(_args):
    w = _window_or_fail()
    print(json.dumps({
        "ok": True,
        "window": w,
        "backend": "phone-harness background (SkyLight)",
    }, ensure_ascii=False, indent=2))


def cmd_screen(args):
    w = _window_or_fail()
    els = _elements()
    out = {"ok": True, "window": w, "count": len(els), "elements": els}
    if args.out:
        path, _ = P.shot(args.out)
        out["screenshot"] = path
    print(json.dumps(out, ensure_ascii=False, indent=2))


def cmd_find(args):
    _window_or_fail()
    els = _elements()
    if args.exact:
        hits = [e for e in els if e["text"].strip() == args.text]
    else:
        hits = [e for e in els if args.text in e["text"]]
    print(json.dumps({"ok": True, "query": args.text, "count": len(hits),
                      "matches": hits}, ensure_ascii=False, indent=2))


def cmd_tap(args):
    _window_or_fail()
    P._key_window()
    P.tap(args.x, args.y)
    print(json.dumps({"ok": True, "action": "tap", "x": args.x, "y": args.y},
                     ensure_ascii=False))


def cmd_tap_text(args):
    _window_or_fail()
    els = _elements()
    if args.exact:
        hits = [e for e in els if e["text"].strip() == args.text]
    else:
        hits = [e for e in els if args.text in e["text"]]
    if not hits:
        print(json.dumps({"ok": False, "error": "text_not_found",
                          "query": args.text}, ensure_ascii=False))
        raise SystemExit(1)
    h = hits[min(args.index, len(hits) - 1)]
    P._key_window()
    P.tap(h["x"], h["y"])
    print(json.dumps({"ok": True, "action": "tap_text", "query": args.text,
                      "hit": h}, ensure_ascii=False, indent=2))


def cmd_long_press(args):
    _window_or_fail()
    P.long_press(args.x, args.y, duration=args.duration)
    print(json.dumps({"ok": True, "action": "long_press", "x": args.x,
                      "y": args.y, "duration": args.duration},
                     ensure_ascii=False))


def cmd_type(args):
    _window_or_fail()
    P._key_window()
    P.type_text(args.text)
    print(json.dumps({"ok": True, "action": "type", "text": args.text},
                     ensure_ascii=False))


def cmd_key(args):
    _window_or_fail()
    P._key_window()
    P.key(args.key)
    print(json.dumps({"ok": True, "action": "key", "key": args.key},
                     ensure_ascii=False))


def cmd_home(_args):
    _window_or_fail()
    P._key_window()
    P.back_home()
    print(json.dumps({"ok": True, "action": "home"}, ensure_ascii=False))


def cmd_scroll(args):
    _window_or_fail()
    P._key_window()
    P._bg().scroll_wheel(args.dy, args.x, args.y, steps=args.steps)
    print(json.dumps({"ok": True, "action": "scroll", "dy": args.dy,
                      "x": args.x, "y": args.y}, ensure_ascii=False))


def cmd_shot(args):
    _window_or_fail()
    path, w = P.shot(args.out)
    print(json.dumps({"ok": True, "screenshot": path, "window": w},
                     ensure_ascii=False, indent=2))


def cmd_wait_text(args):
    _window_or_fail()
    deadline = time.time() + args.timeout
    last = []
    while time.time() < deadline:
        last = _elements()
        if args.exact:
            hits = [e for e in last if e["text"].strip() == args.text]
        else:
            hits = [e for e in last if args.text in e["text"]]
        if hits:
            print(json.dumps({"ok": True, "query": args.text, "matches": hits},
                             ensure_ascii=False, indent=2))
            return
        time.sleep(args.interval)
    print(json.dumps({"ok": False, "error": "timeout", "query": args.text,
                      "last_count": len(last)}, ensure_ascii=False))
    raise SystemExit(1)


def main():
    ap = argparse.ArgumentParser(description="iPhone Mirroring driver")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("state")
    p.set_defaults(func=cmd_state)

    p = sub.add_parser("screen")
    p.add_argument("--out", help="also save a PNG here")
    p.set_defaults(func=cmd_screen)

    p = sub.add_parser("find")
    p.add_argument("--text", required=True)
    p.add_argument("--exact", action="store_true")
    p.set_defaults(func=cmd_find)

    p = sub.add_parser("tap")
    p.add_argument("--x", type=float, required=True)
    p.add_argument("--y", type=float, required=True)
    p.set_defaults(func=cmd_tap)

    p = sub.add_parser("tap-text")
    p.add_argument("--text", required=True)
    p.add_argument("--exact", action="store_true")
    p.add_argument("--index", type=int, default=0)
    p.set_defaults(func=cmd_tap_text)

    p = sub.add_parser("long-press")
    p.add_argument("--x", type=float, required=True)
    p.add_argument("--y", type=float, required=True)
    p.add_argument("--duration", type=float, default=0.5)
    p.set_defaults(func=cmd_long_press)

    p = sub.add_parser("type")
    p.add_argument("--text", required=True)
    p.set_defaults(func=cmd_type)

    p = sub.add_parser("key")
    p.add_argument("--key", required=True)
    p.set_defaults(func=cmd_key)

    p = sub.add_parser("home")
    p.set_defaults(func=cmd_home)

    p = sub.add_parser("scroll")
    p.add_argument("--dy", type=float, required=True,
                   help="negative = scroll down/content up")
    p.add_argument("--x", type=float, default=1500)
    p.add_argument("--y", type=float, default=800)
    p.add_argument("--steps", type=int, default=10)
    p.set_defaults(func=cmd_scroll)

    p = sub.add_parser("shot")
    p.add_argument("--out", required=True)
    p.set_defaults(func=cmd_shot)

    p = sub.add_parser("wait-text")
    p.add_argument("--text", required=True)
    p.add_argument("--exact", action="store_true")
    p.add_argument("--timeout", type=float, default=8.0)
    p.add_argument("--interval", type=float, default=0.5)
    p.set_defaults(func=cmd_wait_text)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
