#!/usr/bin/env python3
"""
Thin wrapper around bin/serve.py that adds an Access-Control-Allow-Origin
header to every response.

The web frontend (port 8080) and the API (port 3000) are different origins
from the browser's point of view, so without this header the frontend's
XMLHttpRequest/$.getJSON calls in web/js/keygen.js get blocked by CORS.

This avoids patching the upstream bin/serve.py: it imports it as a module
(which does NOT start the server, since serve.py only does that under
`if __name__ == "__main__"`), monkey-patches BaseHTTPRequestHandler.end_headers
to inject the header, then starts the server itself using serve.py's own
classes/constants.
"""
import os
import sys
from http.server import BaseHTTPRequestHandler

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(BASE_DIR, "..", "bin"))
import serve  # noqa: E402  (bin/serve.py)

_real_end_headers = BaseHTTPRequestHandler.end_headers


def _end_headers_with_cors(self):
    self.send_header("Access-Control-Allow-Origin", os.environ.get("CORS_ALLOW_ORIGIN", "*"))
    _real_end_headers(self)


BaseHTTPRequestHandler.end_headers = _end_headers_with_cors

if __name__ == "__main__":
    httpd = serve.ForkingSimpleServer(("", serve.PORT_NUMBER), serve.MyHandler)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    httpd.server_close()
