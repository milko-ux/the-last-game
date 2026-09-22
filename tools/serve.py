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
"""
import http.server, ssl, os, sys, socket, subprocess

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
BUILD = os.path.join(ROOT, "..", "the-last-game-build", "phase-r")
CERT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".certs")


class NoCache(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        super().end_headers()

    def log_message(self, *a):
        pass


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
    print("Ctrl-C to stop.", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
