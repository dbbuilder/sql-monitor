# SQL HTTP Bridge (Dual-Platform: Linux & Windows)

This package delivers a minimal, localhost-only HTTP service that:
- Accepts proc / user / pass
- Calls SQL Server via `sqlcmd`
- Returns JSON
- Works on BOTH Linux (systemd) and Windows Server (NSSM service)
- Uses least-privilege SQL auth

## Components

- `service/sql_http_service.py`  
  Cross-platform Python HTTP server that:
  - Listens on 127.0.0.1:8080
  - Parses GET/POST params
  - Maps `proc` to an allowlisted stored procedure
  - Calls `sqlcmd` / `sqlcmd.exe`
  - Emits JSON
  - Returns 401 if SQL auth fails
  - Logs to stdout/stderr for auditing

- `config/sql-http-service.conf.sample`  
  INI-format config consumed by the Python service.

- `linux/sql-http-service.service`  
  systemd unit definition for Linux.

- `windows/INSTALL_WINDOWS.md`  
  Instructions to install as a Windows Service using NSSM.

- `sql/DBA_setup.sql`  
  SQL Server script to:
  - Create DBATools (if not exists)
  - Create Api_AccessLog
  - Create dbo.Api_GetInventory (sample safe proc)
  - Create restricted login `svc_api_readonly`
  - Grant EXEC ONLY on approved procs
  - Document security posture

## Endpoint

`GET/POST http://127.0.0.1:8080/api?proc=Inventory&user=svc_api_readonly&pass=<url-encoded-password>`

## Security Model (Summary)

1. Localhost bind only (127.0.0.1:8080)
2. SQL auth required on every call
3. Least-privilege SQL login with EXECUTE-only permissions
4. Allowlist of stored procedures (no dynamic SQL)
5. Auditing in DBATools.dbo.Api_AccessLog and service logs
6. Easy revocation: stop service, rotate password, revoke EXEC
