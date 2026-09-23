#!/usr/bin/env python3
"""
WEB SHOT — what the phone sees. Opens the SERVED web build in headless
Chromium (Playwright) at the iPhone's landscape size, lets the real run
play itself (?autoplay=1: the validator bot drives) and saves a PNG at a
given bar. Every look screenshot comes from here from 2026-09-23 on: the
Mac's own renderer showed carved monoliths where the phone showed flat
slabs, so a picture from the Mac renderer proves nothing about the phone.

    tools/web_shot.py --bar 11 --out docs/screenshots/w-bar11.png
    tools/web_shot.py --bar 1 --params "light=0" --out /tmp/a.png
    tools/web_shot.py --url https://172.20.10.2:8443/ --wait 4 --out menu.png   (no run: the menu)

The page is 852 x 393 CSS px at device pixel ratio 3 = 2556 x 1179, the
test iPhone's own numbers, so Godot's canvas, its 0.75 render scale and
the 2D layout come out as on the phone. The self-signed certificate is
accepted. The renderer Chromium picked is printed (WEBGL_debug_renderer_info):
if it says SwiftShader or "Software", WebGL2 fell back to software and
the picture is a software render -- say so when reporting.

The run's bar is read from window.pr_bar, which the game publishes four
times a second in dev builds (frame_meter.gd); --wait is the fallback.
"""
import argparse, sys, time
from playwright.sync_api import sync_playwright

ap = argparse.ArgumentParser()
ap.add_argument("--url", default="https://172.20.10.2:8443/?autoplay=1")
ap.add_argument("--params", default="", help="extra query, e.g. 'light=0&glow=0'")
ap.add_argument("--bar", type=int, default=-1, help="shoot when the run reaches this bar")
ap.add_argument("--wait", type=float, default=90.0, help="seconds to wait at most (or exactly, without --bar)")
ap.add_argument("--out", default="/tmp/web_shot.png")
ap.add_argument("--width", type=int, default=852)
ap.add_argument("--height", type=int, default=393)
ap.add_argument("--dpr", type=float, default=3.0)
ap.add_argument("--channel", default="chrome", help="chrome (the installed Google Chrome) or chromium")
ap.add_argument("--browser", default="chromium", help="chromium (Blink, ANGLE/Metal) or webkit (Playwright's WebKit: the phone's engine family, WebGL through ANGLE/Metal like iOS Safari)")
ap.add_argument("--gpu", default="angle", help="angle: real GPU through ANGLE/Metal; swiftshader: software")
args = ap.parse_args()

url = args.url
if args.params:
    url += ("&" if "?" in url else "?") + args.params

chrome_args = ["--ignore-gpu-blocklist", "--ignore-certificate-errors", "--autoplay-policy=no-user-gesture-required"]
if args.gpu == "angle":
    chrome_args += ["--enable-gpu", "--use-angle=metal", "--enable-unsafe-webgpu"]
else:
    chrome_args += ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"]

with sync_playwright() as p:
    if args.browser == "webkit":
        browser = p.webkit.launch(headless=True)
    else:
        browser = p.chromium.launch(channel=args.channel, headless=True, args=chrome_args)
    ctx = browser.new_context(viewport={"width": args.width, "height": args.height},
                              device_scale_factor=args.dpr, ignore_https_errors=True,
                              user_agent="Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1")
    page = ctx.new_page()
    logs = []
    page.on("console", lambda m: logs.append(m.text))
    page.goto(url, wait_until="load")
    renderer = page.evaluate("""() => { const c = document.createElement('canvas');
        const gl = c.getContext('webgl2'); if (!gl) return 'NO WEBGL2';
        const d = gl.getExtension('WEBGL_debug_renderer_info');
        return d ? gl.getParameter(d.UNMASKED_RENDERER_WEBGL) + ' / ' + gl.getParameter(d.UNMASKED_VENDOR_WEBGL) : gl.getParameter(gl.RENDERER); }""")
    print("WEB SHOT renderer:", renderer)
    exts = page.evaluate("""() => { const gl = document.createElement('canvas').getContext('webgl2'); if (!gl) return '';
        return ['WEBGL_compressed_texture_etc', 'WEBGL_compressed_texture_astc', 'WEBGL_compressed_texture_s3tc'].filter(e => gl.getExtension(e)).join(' '); }""")
    print("WEB SHOT compressed textures:", exts or "none")
    t0 = time.time()
    last = None
    while time.time() - t0 < args.wait:
        st = page.evaluate("() => [window.pr_bar, window.pr_state, window.pr_frame_ms]")
        if st != last:
            last = st
        if args.bar >= 0 and st and st[0] is not None and st[0] >= args.bar:
            break
        time.sleep(0.25)
    st = page.evaluate("() => [window.pr_bar, window.pr_state, window.pr_frame_ms]")
    heap = page.evaluate("() => performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) + ' MB used of ' + Math.round(performance.memory.totalJSHeapSize / 1048576) : 'n/a'")
    print("WEB SHOT JS heap:", heap)
    page.screenshot(path=args.out, full_page=False)
    print("WEB SHOT saved=%s bar=%s state=%s frame_ms=%s after %.1f s (%dx%d @%.0fx)" % (
        args.out, st[0], st[1], st[2], time.time() - t0, args.width, args.height, args.dpr))
    probe = page.evaluate("() => window.pr_probe || ''")
    if probe:
        print("WEB SHOT probe table:\n" + probe)
    frames = [l for l in logs if l.startswith("FRAME ") or l.startswith("DEATH ") or l.startswith("REWIND ") or l.startswith("TRACE ") or l.startswith("PROBE") or l.startswith("REWIND COST")]
    for l in frames[:40]:
        print("  " + l[:160])
    errs = [l for l in logs if "error" in l.lower() or "SHADER" in l or "WebGL" in l]
    seen = {}
    for l in errs:
        k = l[:120]
        seen[k] = seen.get(k, 0) + 1
    for k, n in list(seen.items())[:12]:
        print("  console x%d: %s" % (n, k[:200]))
    browser.close()
