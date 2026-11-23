#!/usr/bin/env python3
"""A fake Spotify (accounts + Web API) on 127.0.0.1 for the tests.

  fake_spotify.py <port-file>     listens on a free port, writes it to <port-file>

Control: POST /test/state merges JSON into the state, GET /test/state reads
it, GET /test/log lists the requests seen. state.force maps "METHOD /path"
to a list of canned answers ({"status", "headers", "body"}, or {"delay": s}
alone to answer normally but late) used up in order.
Tokens are fake ("acc-N", "ref-N"); nothing here talks to the real Spotify.
"""
import base64, hashlib, json, sys, threading, time, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

lock = threading.Lock()
S = {
    "devices": [],          # [{"id","name","type","is_active","is_restricted"}]
    "playing": False,
    "access": "acc-0",      # the access token the API accepts
    "refresh": "ref-0",     # the refresh token /api/token accepts
    "rotate": True,         # hand out a new refresh token on each refresh
    "n": 0,
    "challenge": "",
    "code": "good-code",
    "force": {},
}
LOG = []


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, status, body=None, headers=None):
        raw = b"" if body is None else json.dumps(body).encode()
        self.send_response(status)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        if raw:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def handle_any(self, method):
        u = urllib.parse.urlparse(self.path)
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        if u.path.startswith("/test/"):
            with lock:
                if u.path == "/test/state" and method == "POST":
                    S.update(json.loads(raw or b"{}"))
                if u.path == "/test/log":
                    return self.reply(200, LOG)
                return self.reply(200, S)
        key = method + " " + u.path
        with lock:
            LOG.append({"req": key, "auth": self.headers.get("Authorization") or "",
                        "body": raw.decode(errors="replace")})
            forced = S["force"].get(key) or []
            f = forced.pop(0) if forced else None
        if f is not None:
            time.sleep(f.get("delay", 0))
            if f.get("status"):
                return self.reply(f["status"], f.get("body"), f.get("headers"))
        with lock:
            return self.route(method, u, raw)

    def route(self, method, u, raw):
        if u.path == "/authorize":
            q = urllib.parse.parse_qs(u.query)
            S["challenge"] = q["code_challenge"][0]
            S["authorize"] = {k: v[0] for k, v in q.items()}
            loc = q["redirect_uri"][0] + "?" + urllib.parse.urlencode({"code": S["code"], "state": q["state"][0]})
            return self.reply(302, None, {"Location": loc})
        if u.path == "/api/token":
            f = {k: v[0] for k, v in urllib.parse.parse_qs(raw.decode()).items()}
            if f.get("grant_type") == "authorization_code":
                want = base64.urlsafe_b64encode(hashlib.sha256(f.get("code_verifier", "").encode()).digest()).rstrip(b"=").decode()
                if f.get("code") != S["code"] or want != S["challenge"] or not f.get("client_id"):
                    return self.reply(400, {"error": "invalid_grant"})
            elif f.get("grant_type") == "refresh_token":
                if f.get("refresh_token") != S["refresh"] or not f.get("client_id"):
                    return self.reply(400, {"error": "invalid_grant", "error_description": "Refresh token revoked"})
            else:
                return self.reply(400, {"error": "unsupported_grant_type"})
            S["n"] += 1
            S["access"] = "acc-%d" % S["n"]
            body = {"access_token": S["access"], "token_type": "Bearer", "expires_in": 3600,
                    "scope": "user-read-playback-state user-modify-playback-state"}
            if S["rotate"] or f.get("grant_type") == "authorization_code":
                S["refresh"] = "ref-%d" % S["n"]
                body["refresh_token"] = S["refresh"]
            return self.reply(200, body)
        if self.headers.get("Authorization") != "Bearer " + S["access"]:
            return self.reply(401, {"error": {"status": 401, "message": "The access token expired"}})
        if u.path == "/v1/me/player/devices" and method == "GET":
            return self.reply(200, {"devices": S["devices"]})
        if u.path == "/v1/me/player" and method == "GET":
            act = [d for d in S["devices"] if d.get("is_active")]
            if not act:
                return self.reply(204)
            return self.reply(200, {"is_playing": S["playing"], "device": act[0]})
        if u.path == "/v1/me/player" and method == "PUT":
            b = json.loads(raw or b"{}")
            ids = b.get("device_ids") or []
            if not ids or ids[0] not in [d["id"] for d in S["devices"]]:
                return self.reply(404, {"error": {"status": 404, "message": "Device not found", "reason": "NO_ACTIVE_DEVICE"}})
            for d in S["devices"]:
                d["is_active"] = d["id"] == ids[0]
            S["playing"] = bool(b.get("play"))
            return self.reply(204)
        return self.reply(404, {"error": {"status": 404, "message": "no such fake endpoint"}})

    def do_GET(self):
        self.handle_any("GET")

    def do_POST(self):
        self.handle_any("POST")

    def do_PUT(self):
        self.handle_any("PUT")


srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
with open(sys.argv[1] + ".tmp", "w") as f:
    f.write(str(srv.server_address[1]))
import os
os.replace(sys.argv[1] + ".tmp", sys.argv[1])
srv.serve_forever()
