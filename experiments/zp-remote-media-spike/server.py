#!/usr/bin/env python3
"""EXPERIMENTAL / FASE 0 / NOT PRODUCT CODE.

Tiny static file server for the ZP Remote media spike — stdlib only, no
dependencies to install. Serves this directory over http://localhost so
getUserMedia()/RTCPeerConnection run in a secure context, and BroadcastChannel
signaling works between /studio/ and /artist/ tabs (same origin).

Usage:
    python3 server.py [port]        # default port 8743

Then open, in Chromium/Chrome:
    http://localhost:8743/studio/
    http://localhost:8743/artist/
(two separate tabs, or two separate devices on the same LAN pointing at the
studio machine's LAN IP instead of localhost).
"""
import http.server
import socketserver
import sys
import os

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8743
DIRECTORY = os.path.dirname(os.path.abspath(__file__))


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def end_headers(self):
        # Not required for localhost (already a secure context), but harmless
        # and useful if this is ever pointed at over a LAN IP for cross-device
        # testing (still http, not https — some browsers may still restrict
        # getUserMedia on a non-localhost http origin; see README "Limiti").
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
    with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
        print(f"ZP Remote media spike — serving {DIRECTORY} on:")
        print(f"  http://localhost:{PORT}/studio/")
        print(f"  http://localhost:{PORT}/artist/")
        print("Ctrl+C per fermare.")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nFermato.")
