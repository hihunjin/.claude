#!/usr/bin/env python3
"""Local proxy for Claude Code: try a custom gateway first, fall back to Anthropic.

Config comes from ~/.claude/.env.local (see .env.local.example):
    CUSTOM_API_BASE_URL, CUSTOM_API_KEY, CUSTOM_API_INSECURE_TLS,
    ANTHROPIC_API_KEY_FALLBACK

Run via scripts/start_proxy.sh, which Claude Code invokes as its apiKeyHelper.
"""
import http.server
import os
import pathlib
import ssl
import sys
import urllib.request

PORT = int(os.environ.get("CLAUDE_PROXY_PORT", "7070"))
ENV_FILE = pathlib.Path.home() / ".claude" / ".env.local"


def load_env():
    if not ENV_FILE.exists():
        return
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


load_env()

BACKENDS = [
    {
        "url": os.environ.get("CUSTOM_API_BASE_URL", ""),
        "token": os.environ.get("CUSTOM_API_KEY", ""),
        "verify_ssl": os.environ.get("CUSTOM_API_INSECURE_TLS", "0") != "1",
    },
    {
        "url": "https://api.anthropic.com",
        "token": os.environ.get("ANTHROPIC_API_KEY_FALLBACK", ""),
        "verify_ssl": True,
    },
]


class FallbackProxy(http.server.BaseHTTPRequestHandler):
    def proxy(self, method):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else None

        for backend in BACKENDS:
            if not backend["url"] or not backend["token"]:
                continue
            try:
                headers = {
                    k: v for k, v in self.headers.items()
                    if k.lower() not in ("host", "authorization", "content-length")
                }
                headers["Authorization"] = f"Bearer {backend['token']}"
                if body:
                    headers["Content-Length"] = str(len(body))

                req = urllib.request.Request(
                    backend["url"] + self.path,
                    data=body, headers=headers, method=method
                )
                ctx = ssl.create_default_context()
                if not backend["verify_ssl"]:
                    ctx.check_hostname = False
                    ctx.verify_mode = ssl.CERT_NONE

                resp = urllib.request.urlopen(req, timeout=30, context=ctx)
                self.send_response(resp.status)
                for k, v in resp.headers.items():
                    if k.lower() != "transfer-encoding":
                        self.send_header(k, v)
                self.end_headers()
                while True:
                    chunk = resp.read(4096)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
                return
            except Exception as exc:
                print(f"[proxy] {backend['url']} failed: {exc}", file=sys.stderr)

        self.send_error(502, "All backends failed")

    def do_GET(self):
        self.proxy("GET")

    def do_POST(self):
        self.proxy("POST")

    def log_message(self, fmt, *args):
        print(f"[proxy] {fmt % args}", file=sys.stderr)


if __name__ == "__main__":
    httpd = http.server.HTTPServer(("127.0.0.1", PORT), FallbackProxy)
    print(f"[proxy] listening on http://127.0.0.1:{PORT}", file=sys.stderr)
    httpd.serve_forever()
