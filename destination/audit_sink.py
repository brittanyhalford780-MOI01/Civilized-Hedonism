#!/usr/bin/env python3
"""
MOI01.VIP — Independent Destination Audit Sink & Live Monitor

An independent audit endpoint hosted on a destination server (Oracle Cloud, AWS, GCP, etc.)
that receives forwarded payloads from the Vault and displays them on a live HTML dashboard.

PURPOSE:
  This server proves to stakeholders that the Vault is correctly relaying
  payloads WITHOUT relying on any logging within the Vault itself.
  It is a completely independent verification system.

USAGE (on Destination Server):
  1. sudo firewall-cmd --permanent --add-port=8080/tcp
  2. sudo firewall-cmd --reload
  3. python3 destination/audit_sink.py --port 8080 --token audit2026

ZERO EXTERNAL DEPENDENCIES — uses standard Python 3 libraries.
"""

import argparse
import json
import secrets
import threading
import time
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse
from datetime import datetime, timezone

# ─── Configuration ────────────────────────────────────────────────────────────

LISTEN_PORT = 8080
DEFAULT_TOKEN = "audit2026"
MAX_LOG_ENTRIES = 1000
PREVIEW_BYTES = 500
MAX_POST_BYTES = 2 * 1024 * 1024  # 2MB limit to prevent memory exhaustion DoS

LOG = deque(maxlen=MAX_LOG_ENTRIES)
LOG_LOCK = threading.Lock()
STATS = {"total_received": 0, "total_bytes": 0, "errors": 0, "start_time": time.time()}

# ─── Dashboard HTML ───────────────────────────────────────────────────────────

DASHBOARD_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Destination Audit Sink — Live Dashboard</title>
    <!-- Prevent Theme Flashing (FOUC) -->
    <script>
        (function() {
            const theme = localStorage.getItem('audit-theme') || 'system';
            let active = theme;
            if (theme === 'system') {
                active = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
            }
            document.documentElement.setAttribute('data-theme', active);
        })();
    </script>
    <style>
        :root {
            /* Dark Mode (Default) */
            --bg: #0a0e14;
            --card-bg: #111820;
            --border: #1e2a3a;
            --text: #c5d0dc;
            --muted: #5c6d7e;
            --green: #22c55e;
            --green-dim: rgba(34,197,94,0.12);
            --red: #ef4444;
            --red-dim: rgba(239,68,68,0.12);
            --blue: #3b82f6;
            --amber: #f59e0b;
            --mono: 'Courier New', monospace;
        }

        /* Light Mode */
        [data-theme="light"] {
            --bg: #f1f5f9;
            --card-bg: #ffffff;
            --border: #e2e8f0;
            --text: #0f172a;
            --muted: #64748b;
            --green: #16a34a;
            --green-dim: rgba(22, 163, 74, 0.1);
            --red: #dc2626;
            --red-dim: rgba(220, 38, 38, 0.1);
            --blue: #2563eb;
            --amber: #d97706;
        }

        * { margin:0; padding:0; box-sizing:border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background:var(--bg); color:var(--text); padding:24px; transition: background-color 0.3s ease, color 0.3s ease; }
        h1 { font-size:20px; font-weight:600; margin-bottom:4px; display:flex; align-items:center; gap:8px; }
        .pulse-dot { width:10px; height:10px; border-radius:50%; background:var(--green); animation:pulse 1.5s infinite; }
        @keyframes pulse { 0%,100%{opacity:1;} 50%{opacity:0.3;} }
        .subtitle { font-size:12px; color:var(--muted); margin-bottom:24px; }
        .stats { display:grid; grid-template-columns:repeat(auto-fit, minmax(150px, 1fr)); gap:12px; margin-bottom:24px; }
        .stat-card { background:var(--card-bg); border:1px solid var(--border); border-radius:8px; padding:16px; transition: background-color 0.3s ease, border-color 0.3s ease; }
        .stat-label { font-size:11px; color:var(--muted); text-transform:uppercase; letter-spacing:1px; }
        .stat-value { font-size:24px; font-weight:700; margin-top:4px; font-family:var(--mono); }
        .stat-value.green { color:var(--green); }
        .stat-value.blue { color:var(--blue); }
        .stat-value.amber { color:var(--amber); }
        .log-header { display:flex; justify-content:space-between; align-items:center; margin-bottom:12px; }
        .log-header h2 { font-size:14px; }
        .refresh-note { font-size:11px; color:var(--muted); }
        .log-entry { background:var(--card-bg); border:1px solid var(--border); border-radius:8px; padding:14px 16px; margin-bottom:8px; transition:border-color 0.2s, background-color 0.3s ease; }
        .log-entry:hover { border-color:var(--green); }
        .log-meta { display:flex; gap:16px; flex-wrap:wrap; font-size:12px; color:var(--muted); margin-bottom:8px; }
        .log-meta span { display:inline-flex; align-items:center; gap:4px; }
        .log-meta .auth-bearer { color:var(--green); font-family:var(--mono); }
        .log-meta .auth-none { color:var(--red); font-family:var(--mono); }
        .log-preview { font-family:var(--mono); font-size:11px; color:var(--text); background:var(--bg); border-radius:6px; padding:10px 12px; white-space:pre-wrap; word-break:break-all; max-height:120px; overflow-y:auto; border:1px solid var(--border); }
        .badge { display:inline-block; padding:2px 8px; border-radius:4px; font-size:10px; font-weight:600; text-transform:uppercase; }
        .badge-ok { background:var(--green-dim); color:var(--green); }
        .badge-error { background:var(--red-dim); color:var(--red); }
        .empty { text-align:center; padding:40px; color:var(--muted); font-size:14px; }

        /* ─── Theme Switcher ─── */
        .theme-switcher {
            position: fixed; top: 20px; right: 20px;
            display: flex; gap: 4px; background: var(--card-bg);
            border: 1px solid var(--border); padding: 6px; border-radius: 12px;
            backdrop-filter: blur(20px); z-index: 100;
            transition: background-color 0.3s ease, border-color 0.3s ease;
        }
        .theme-switcher input[type="radio"] { display: none; }
        .theme-switcher label {
            cursor: pointer; padding: 8px; border-radius: 8px;
            display: flex; align-items: center; justify-content: center;
            color: var(--muted); transition: all 0.2s ease;
        }
        .theme-switcher label:hover { background: var(--bg); color: var(--text); }
        .theme-switcher input[type="radio"]:checked + label {
            background: var(--green-dim); color: var(--green);
        }
        .theme-switcher svg { width: 16px; height: 16px; }
    </style>
</head>
<body>
    <!-- Theme Switcher (Top Right) -->
    <div class="theme-switcher">
        <input type="radio" id="theme-system" name="theme" value="system" checked>
        <label for="theme-system" title="Follow System Theme">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="3" width="20" height="14" rx="2" ry="2"></rect><line x1="8" y1="21" x2="16" y2="21"></line><line x1="12" y1="17" x2="12" y2="21"></line></svg>
        </label>

        <input type="radio" id="theme-dark" name="theme" value="dark">
        <label for="theme-dark" title="Dark Mode">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"></path></svg>
        </label>

        <input type="radio" id="theme-light" name="theme" value="light">
        <label for="theme-light" title="Light Mode">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="5"></circle><line x1="12" y1="1" x2="12" y2="3"></line><line x1="12" y1="21" x2="12" y2="23"></line><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"></line><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"></line><line x1="1" y1="12" x2="3" y2="12"></line><line x1="21" y1="12" x2="23" y2="12"></line><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"></line><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"></line></svg>
        </label>
    </div>

    <h1><span class="pulse-dot"></span> Destination Audit Sink</h1>
    <p class="subtitle">Independent destination endpoint — listening for Vault relays</p>

    <div class="stats">
        <div class="stat-card">
            <div class="stat-label">Total Received</div>
            <div class="stat-value green" id="statTotal">{{TOTAL}}</div>
        </div>
        <div class="stat-card">
            <div class="stat-label">Total Bytes</div>
            <div class="stat-value blue" id="statBytes">{{BYTES}}</div>
        </div>
        <div class="stat-card">
            <div class="stat-label">Uptime</div>
            <div class="stat-value amber" id="statUptime">{{UPTIME}}</div>
        </div>
    </div>

    <div class="log-header">
        <h2>📡 Live Audit Log (Last {{COUNT}} entries)</h2>
        <span class="refresh-note">Auto-refresh: 5s</span>
    </div>

    <div id="logEntries">
        {{ENTRIES}}
    </div>

    <script>
        // Theme Switching Logic
        (function() {
            const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
            const savedTheme = localStorage.getItem('audit-theme') || 'system';
            const radioToCheck = document.querySelector(`input[name="theme"][value="${savedTheme}"]`);
            if (radioToCheck) radioToCheck.checked = true;

            function applyTheme(theme) {
                let active = theme;
                if (theme === 'system') {
                    active = mediaQuery.matches ? 'dark' : 'light';
                }
                document.documentElement.setAttribute('data-theme', active);
            }
            applyTheme(savedTheme);

            mediaQuery.addEventListener('change', (e) => {
                if (document.querySelector('input[name="theme"]:checked').value === 'system') {
                    applyTheme('system');
                }
            });

            document.querySelectorAll('input[name="theme"]').forEach(input => {
                input.addEventListener('change', (e) => {
                    localStorage.setItem('audit-theme', e.target.value);
                    applyTheme(e.target.value);
                });
            });
        })();

        // Auto refresh
        setTimeout(() => location.reload(), 5000);
    </script>
</body>
</html>"""


def format_bytes(n):
    for unit in ["B", "KB", "MB", "GB"]:
        if abs(n) < 1024:
            return f"{n:.1f} {unit}" if unit != "B" else f"{n} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def format_uptime(seconds):
    hours, remainder = divmod(int(seconds), 3600)
    minutes, secs = divmod(remainder, 60)
    if hours > 0:
        return f"{hours}h {minutes}m"
    return f"{minutes}m {secs}s"


def render_log_entry(entry):
    ts = datetime.fromtimestamp(entry["ts"], tz=timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    auth = entry.get("auth", "none")
    auth_class = "auth-bearer" if auth.startswith("Bearer") else "auth-none"
    auth_display = "Bearer ••••" + auth[-8:] if auth.startswith("Bearer ") and len(auth) > 15 else auth
    size_str = format_bytes(entry.get("size", 0))
    preview = entry.get("preview", "")
    badge = '<span class="badge badge-ok">OK</span>'

    return f"""<div class="log-entry">
        <div class="log-meta">
            <span>{badge}</span>
            <span>🕐 {ts}</span>
            <span>📦 {size_str}</span>
            <span class="{auth_class}">🔑 {auth_display}</span>
        </div>
        <div class="log-preview">{preview}</div>
    </div>"""


class AuditHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def handle_one_request(self):
        try:
            super().handle_one_request()
        except ConnectionError:
            pass

    def _parse_path(self):
        return [p for p in urlparse(self.path).path.split("/") if p]

    def _send_json(self, status, data):
        try:
            body = json.dumps(data).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except ConnectionError:
            pass

    def _send_html(self, status, html):
        try:
            body = html.encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except ConnectionError:
            pass

    def do_POST(self):
        parts = self._parse_path()

        if len(parts) != 2 or parts[1] != "submit":
            self._send_json(404, {"error": "not_found"})
            return

        if not secrets.compare_digest(parts[0], self.server.token):
            self._send_json(403, {"error": "forbidden"})
            return

        try:
            length = int(self.headers.get("Content-Length", 0))
            
            # Prevent Memory Exhaustion DoS
            if length > MAX_POST_BYTES:
                self._send_json(413, {"error": "payload_too_large"})
                return

            body = self.rfile.read(length) if length > 0 else b""

            entry = {
                "ts": time.time(),
                "size": length,
                "auth": self.headers.get("Authorization", "none"),
                "ip": self.client_address[0],
                "preview": body[:PREVIEW_BYTES].decode("utf-8", "replace"),
            }

            with LOG_LOCK:
                LOG.append(entry)
                STATS["total_received"] += 1
                STATS["total_bytes"] += length

            self._send_json(200, {"status": "ok", "logged": True})

        except ConnectionError:
            pass
        except Exception:
            with LOG_LOCK:
                STATS["errors"] += 1
            self._send_json(500, {"error": "internal_error"})

    def do_GET(self):
        parts = self._parse_path()

        if len(parts) == 1 and parts[0] == "health":
            self._send_json(200, {"status": "ok"})
            return

        if len(parts) == 1 and secrets.compare_digest(parts[0], self.server.token):
            self._serve_dashboard()
            return

        if len(parts) == 2 and secrets.compare_digest(parts[0], self.server.token) and parts[1] == "entries":
            with LOG_LOCK:
                entries = list(LOG)
            self._send_json(200, {"entries": entries, "stats": dict(STATS)})
            return

        self._send_json(404, {"error": "not_found"})

    def _serve_dashboard(self):
        with LOG_LOCK:
            entries = list(reversed(LOG))
            total = STATS["total_received"]
            total_bytes = STATS["total_bytes"]
            uptime = time.time() - STATS["start_time"]

        if entries:
            entries_html = "\n".join(render_log_entry(e) for e in entries[:50])
        else:
            entries_html = '<div class="empty">Waiting for payloads from Vault...</div>'

        html = DASHBOARD_HTML
        html = html.replace("{{TOTAL}}", str(total))
        html = html.replace("{{BYTES}}", format_bytes(total_bytes))
        html = html.replace("{{UPTIME}}", format_uptime(uptime))
        html = html.replace("{{COUNT}}", str(len(entries)))
        html = html.replace("{{ENTRIES}}", entries_html)

        self._send_html(200, html)


def main():
    parser = argparse.ArgumentParser(description="Destination Audit Sink Server")
    parser.add_argument("--port", type=int, default=LISTEN_PORT, help="Port to listen on")
    parser.add_argument("--token", type=str, default=DEFAULT_TOKEN, help="Auth token path prefix")
    args = parser.parse_args()

    server = ThreadingHTTPServer(("0.0.0.0", args.port), AuditHandler)
    server.token = args.token

    print("=" * 60)
    print("  Destination Audit Sink — Independent Verification Server")
    print("=" * 60)
    print(f"  Dashboard:  http://<DESTINATION_IP>:{args.port}/{args.token}/")
    print(f"  Submit URL: http://<DESTINATION_IP>:{args.port}/{args.token}/submit")
    print("=" * 60)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down audit sink...")
        server.shutdown()


if __name__ == "__main__":
    main()