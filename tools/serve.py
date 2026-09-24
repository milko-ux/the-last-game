#!/usr/bin/env python3
"""Serves the exported web build for local testing.

    tools/serve.py            -> http://localhost:8099   (this Mac only)
    tools/serve.py tls        -> https://<LAN-IP>:8443   (phones / colleagues)
    tools/serve.py tls <dir>  -> serve a different build folder

The default is the Phase R build. Builds are written OUTSIDE the project
(../the-last-game-build/) on purpose: a build folder inside res:// gets
scanned by Godot, and the next export packs the previous export's icons.

Lives in the repo on purpose. It used to live in a scratch directory
that got wiped whenever the session restarted, which meant the test
URL kept dying for no visible reason.

Always sends Cache-Control: no-store. Without it browsers pin Godot's
index.pck and silently run an OLD build while every file on disk looks
correct — that has cost hours twice.

THE BLACK BOX PHONES HOME (2026-09-24, the iOS crash hunt). The game's
black box (prototype/blackbox.gd) sends every line it records to
POST /bb?s=<session id> with navigator.sendBeacon, and this server
appends each line, with the Mac's clock and that session id, to
    ../the-last-game-build/blackbox.log
(next to the build folder, never inside it). When iOS kills the tab,
localStorage may or may not survive; the lines that reached the Mac
are the record. Read it with:  tail -f ../the-last-game-build/blackbox.log
"""
import http.server, ssl, os, sys, socket, subprocess, threading, datetime, urllib.parse

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
BUILD = os.path.join(ROOT, "..", "the-last-game-build", "phase-r")
CERT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".certs")


LOG_PATH = ""            # set in main(): <build folder>/../blackbox.log
_log_lock = threading.Lock()
_sessions_seen = set()


class NoCache(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        super().end_headers()

    def log_message(self, *a):
        pass

    # The black box: POST /bb?s=<session id>, body = one line (or several,
    # newline-separated). Appended as "<Mac time>  <session>  <line>".
    def do_POST(self):
        url = urllib.parse.urlsplit(self.path)
        if url.path != "/bb":
            self.send_response(404)
            self.end_headers()
            return
        sid = urllib.parse.parse_qs(url.query).get("s", ["-"])[0][:24]
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            n = 0
        body = self.rfile.read(min(n, 65536)).decode("utf-8", "replace") if n > 0 else ""
        stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
        lines = [l for l in body.split("\n") if l.strip()]
        with _log_lock:
            try:
                with open(LOG_PATH, "a") as f:
                    if sid not in _sessions_seen:
                        _sessions_seen.add(sid)
                        f.write("%s  %s  --- session from %s\n" % (stamp, sid, self.client_address[0]))
                        print("black box: new session %s from %s" % (sid, self.client_address[0]), flush=True)
                    for l in lines:
                        f.write("%s  %s  %s\n" % (stamp, sid, l[:1000]))
            except OSError as e:
                print("black box: cannot write %s: %s" % (LOG_PATH, e), flush=True)
        self.send_response(204)
        self.end_headers()


def lan_ip() -> str:
    for iface in ("en0", "en1"):
        try:
            out = subprocess.run(["ipconfig", "getifaddr", iface],
                                 capture_output=True, text=True, timeout=3)
            if out.returncode == 0 and out.stdout.strip():
                return out.stdout.strip()
        except Exception:
            pass
    return socket.gethostbyname(socket.gethostname())


def ensure_cert(ip: str):
    os.makedirs(CERT_DIR, exist_ok=True)
    cert = os.path.join(CERT_DIR, "cert.pem")
    key = os.path.join(CERT_DIR, "key.pem")
    # Regenerate if missing or if the machine moved to a different network,
    # since the cert names a specific IP.
    stale = True
    if os.path.exists(cert):
        try:
            txt = subprocess.run(["openssl", "x509", "-in", cert, "-noout", "-text"],
                                 capture_output=True, text=True, timeout=5).stdout
            stale = ip not in txt
        except Exception:
            stale = True
    if stale:
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048",
            "-keyout", key, "-out", cert, "-days", "365", "-nodes",
            "-subj", f"/CN={ip}",
            "-addext", f"subjectAltName=IP:{ip},IP:127.0.0.1,DNS:localhost",
        ], capture_output=True, timeout=30)
        print(f"generated a fresh certificate for {ip}")
    return cert, key


def main() -> None:
    global BUILD
    args = sys.argv[1:]
    tls = "tls" in args
    dirs = [a for a in args if a != "tls"]
    if dirs:
        BUILD = os.path.join(ROOT, dirs[0])
    if not os.path.isdir(BUILD):
        sys.exit(f"No build at {BUILD} — run tools/package_web.sh first.")
    global LOG_PATH
    LOG_PATH = os.path.abspath(os.path.join(BUILD, "..", "blackbox.log"))
    os.chdir(BUILD)

    port = 8443 if tls else 8099
    host = "0.0.0.0" if tls else "127.0.0.1"

    httpd = http.server.ThreadingHTTPServer((host, port), NoCache)
    if tls:
        cert, key = ensure_cert(lan_ip())
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(cert, key)
        httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
        print(f"https://{lan_ip()}:{port}   (accept the certificate warning once)")
    else:
        print(f"http://localhost:{port}")
    print(f"black box log: {LOG_PATH}")
    print("Ctrl-C to stop.", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
