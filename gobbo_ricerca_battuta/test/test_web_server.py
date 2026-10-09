#!/usr/bin/env python3
"""Server mock di REAPER per collaudare zp_solo.html fuori da REAPER.

Simula gli endpoint web di REAPER:
  GET /zp_solo.html
  GET /_/GET/EXTSTATE/ZP_SOLO_WEB/state
  GET /_/GET/EXTSTATE/ZP_SOLO_WEB/nav
  GET /_/SET/EXTSTATE/ZP_SOLO_WEB/cmd/<payload>
"""

from __future__ import annotations

import http.server
import json
import socketserver
import sys
import threading
import time
import urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
WEB_DIR = ROOT / "ZP Studio Suite" / "web"
HTML_FILE = WEB_DIR / "zp_solo.html"

STATE = {
    "v": 1,
    "t": time.time(),
    "ack": "",
    "msg": "Motore web acceso",
    "transport": "STOP",
    "pos": 15.250,
    "tc": "00:00:15:06",
    "track": "Voce Speaker",
    "armed": 1,
    "input": "In 1",
    "in_db": -18.4,
    "rit_db": -22.1,
    "region": "Take 001",
    "preroll": True,
    "preroll_s": 3,
    "sws": True,
    "dirty": False,
    "can_undo": True,
    "can_redo": False,
    "share": ["http://192.168.1.50:8080/zp_solo.html"],
    "navv": 1,
    "lang": "it",
}

NAV = {
    "len": 90.0,
    "regions": [{"s": 10.0, "e": 45.0, "n": "Take 001", "c": "#5b6b8a"}],
    "markers": [{"p": 20.0, "n": "Mark 1", "c": "#e0b040"}],
    "items": [{"s": 12.0, "e": 42.0}],
}


class MockReaperHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB_DIR), **kwargs)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path.startswith("/_/GET/EXTSTATE/ZP_SOLO_WEB/state"):
            STATE["t"] = time.time()
            data = "EXTSTATE\tZP_SOLO_WEB\tstate\t" + json.dumps(STATE) + "\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data.encode("utf-8"))
            return

        if path.startswith("/_/GET/EXTSTATE/ZP_SOLO_WEB/nav"):
            data = "EXTSTATE\tZP_SOLO_WEB\tnav\t" + json.dumps(NAV) + "\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data.encode("utf-8"))
            return

        if path.startswith("/_/SET/EXTSTATE/ZP_SOLO_WEB/cmd/"):
            raw_cmd = path[len("/_/SET/EXTSTATE/ZP_SOLO_WEB/cmd/") :]
            unquoted = urllib.parse.unquote(raw_cmd)
            parts = unquoted.split("|", 2)
            if len(parts) >= 2:
                cmd_id = parts[0]
                verb = parts[1]
                arg = parts[2] if len(parts) > 2 else ""
                STATE["ack"] = cmd_id
                if verb == "rec":
                    STATE["transport"] = "REC"
                    STATE["msg"] = f"REC su {STATE['track']}"
                elif verb == "play":
                    STATE["transport"] = "PLAY"
                    STATE["msg"] = "PLAY"
                elif verb == "stop":
                    STATE["transport"] = "STOP"
                    STATE["msg"] = "STOP"
                elif verb == "pause":
                    STATE["transport"] = "PAUSE"
                    STATE["msg"] = "PAUSA"
                elif verb == "preroll":
                    STATE["preroll"] = not STATE["preroll"]
                    STATE["msg"] = f"Pre-roll {'acceso' if STATE['preroll'] else 'spento'}"
                elif verb == "goto":
                    try:
                        STATE["pos"] = float(arg)
                        STATE["msg"] = f"Vai a {STATE['pos']:.1f} s"
                    except ValueError:
                        pass
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"OK\n")
            return

        # Fallback sui file statici
        super().do_GET()

    def log_message(self, format, *args):
        # Silenzioso nei test automatici
        pass


def test_client(port: int) -> bool:
    import urllib.request

    url = f"http://127.0.0.1:{port}/zp_solo.html"
    with urllib.request.urlopen(url) as resp:
        html = resp.read().decode("utf-8")

    assert "<!doctype html>" in html
    assert "ZP_EN" in html
    assert "b-lang-it" in html and "b-lang-en" in html
    assert "lc-firma" in html
    assert "Lato Cardioide" in html

    # Test endpoint stato
    st_url = f"http://127.0.0.1:{port}/_/GET/EXTSTATE/ZP_SOLO_WEB/state"
    with urllib.request.urlopen(st_url) as resp:
        st_data = resp.read().decode("utf-8")
    assert "EXTSTATE\tZP_SOLO_WEB\tstate\t" in st_data

    # Test comando
    cmd_url = f"http://127.0.0.1:{port}/_/SET/EXTSTATE/ZP_SOLO_WEB/cmd/test-1%7Cplay%7C"
    with urllib.request.urlopen(cmd_url) as resp:
        assert resp.read() == b"OK\n"

    # Test stato aggiornato
    with urllib.request.urlopen(st_url) as resp:
        st_data = resp.read().decode("utf-8")
    val = json.loads(st_data.split("\t", 3)[3])
    assert val["transport"] == "PLAY"
    assert val["ack"] == "test-1"

    print("Test client mock server: TUTTO OK")
    return True


def main():
    socketserver.TCPServer.allow_reuse_address = True
    server = socketserver.TCPServer(("127.0.0.1", 0), MockReaperHandler)
    port = server.server_address[1]
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()
    print(f"Mock REAPER server avviato su http://127.0.0.1:{port}/zp_solo.html")

    try:
        ok = test_client(port)
        if not ok:
            sys.exit(1)
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
