#!/usr/bin/env python3

import http.server
import socketserver
import urllib.parse
import subprocess
import json
import configparser
import logging
import sys
import os
import platform

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

class SQLHttpHandler(http.server.BaseHTTPRequestHandler):
    # populated at runtime from config
    allowed_map = {}
    sql_server = "localhost"
    database = "YourAppDB"

    def _send_json(self, status_code, payload_obj):
        """Send back JSON HTTP response."""
        body = json.dumps(payload_obj, indent=2)
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body.encode("utf-8"))

    def _parse_params(self):
        """Parse GET query string and POST form body (application/x-www-form-urlencoded)."""
        params = {}

        # GET
        if self.command == "GET":
            parsed = urllib.parse.urlparse(self.path)
            qs = urllib.parse.parse_qs(parsed.query)
            for k, v in qs.items():
                if v:
                    params[k] = v[0]

        # POST
        if self.command == "POST":
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length).decode("utf-8")
            post_qs = urllib.parse.parse_qs(raw)
            for k, v in post_qs.items():
                if v:
                    params[k] = v[0]

        return params

    def do_GET(self):
        self.handle_request()

    def do_POST(self):
        self.handle_request()

    def handle_request(self):
        try:
            path_only = self.path.split("?")[0]
            if path_only not in ["/api", "/api/"]:
                self._send_json(404, {"error": "not found"})
                return

            params = self._parse_params()
            req_proc_key = params.get("proc")
            req_user     = params.get("user")
            req_pass     = params.get("pass")

            if not req_proc_key or not req_user or not req_pass:
                self._send_json(400, {"error": "missing required params: proc, user, pass"})
                return

            # Map proc key -> actual stored procedure, from allowlist
            sp_name = self.allowed_map.get(req_proc_key)
            if not sp_name:
                self._send_json(400, {"error": "invalid proc"})
                return

            tsql = f"SET NOCOUNT ON; EXEC {sp_name}"

            # Resolve sqlcmd path for Linux or Windows
            sqlcmd_candidates = ["sqlcmd"]
            if platform.system().lower().startswith("win"):
                sqlcmd_candidates.insert(0, "sqlcmd.exe")

            sqlcmd_path = None
            for cand in sqlcmd_candidates:
                for p in os.environ.get("PATH", "").split(os.pathsep):
                    full = os.path.join(p, cand)
                    if os.path.isfile(full):
                        sqlcmd_path = full
                        break
                if sqlcmd_path:
                    break

            if sqlcmd_path is None:
                logging.error("sqlcmd not found in PATH")
                self._send_json(500, {"error": "internal server error"})
                return

            cmd = [
                sqlcmd_path,
                "-S", self.sql_server,
                "-d", self.database,
                "-U", req_user,
                "-P", req_pass,
                "-Q", tsql,
                "-W",      # trim trailing spaces
                "-s", "|"  # pipe delimiter
            ]

            logging.info("Executing stored proc '%s' as login '%s'", sp_name, req_user)

            completed = subprocess.run(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )

            if completed.returncode != 0:
                logging.warning(
                    "sqlcmd error rc=%s stderr=%s",
                    completed.returncode,
                    completed.stderr.strip()
                )
                self._send_json(401, {"error": "auth or exec failed"})
                return

            lines = completed.stdout.strip().splitlines()

            if len(lines) < 3:
                rows_json = []
            else:
                header_line = lines[0]
                data_lines = []
                for line in lines[2:]:
                    if "rows affected" in line:
                        break
                    if line.strip() == "":
                        continue
                    data_lines.append(line)

                cols = [h.strip() for h in header_line.split("|")]

                rows_json = []
                for dl in data_lines:
                    vals = [v.strip() for v in dl.split("|")]
                    row_obj = {}
                    for idx, col_name in enumerate(cols):
                        row_obj[col_name] = vals[idx] if idx < len(vals) else None
                    rows_json.append(row_obj)

            self._send_json(200, {
                "proc": req_proc_key,
                "sp_name": sp_name,
                "row_count": len(rows_json),
                "rows": rows_json
            })

        except Exception as ex:
            logging.exception("Unhandled server error: %s", str(ex))
            self._send_json(500, {"error": "internal server error"})

def load_config(conf_path):
    cfg = configparser.ConfigParser()
    with open(conf_path, "r") as f:
        cfg.read_file(f)

    sql_server = cfg.get("service", "sql_server", fallback="localhost")
    database   = cfg.get("service", "database", fallback="master")
    port       = cfg.getint("service", "port", fallback=8080)

    raw_map    = cfg.get("service", "allowed_procs", fallback="")
    allowed_map = {}
    if raw_map.strip():
        pairs = [p.strip() for p in raw_map.split(",")]
        for pair in pairs:
            if ":" in pair:
                k, v = pair.split(":", 1)
                allowed_map[k.strip()] = v.strip()

    return sql_server, database, port, allowed_map

def run_server(conf_path):
    sql_server, database, port, allowed_map = load_config(conf_path)

    SQLHttpHandler.sql_server  = sql_server
    SQLHttpHandler.database    = database
    SQLHttpHandler.allowed_map = allowed_map

    bind_addr = ("127.0.0.1", port)

    with socketserver.TCPServer(bind_addr, SQLHttpHandler) as httpd:
        logging.info(
            "Starting SQL HTTP service on %s:%d for DB %s (server %s)",
            bind_addr[0], bind_addr[1], database, sql_server
        )
        httpd.serve_forever()

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: sql_http_service.py <path to sql-http-service.conf>", file=sys.stderr)
        sys.exit(1)
    conf_path = sys.argv[1]
    run_server(conf_path)
