# Windows Installation (sql-http-service)

## 1. Prereqs
- Windows Server (on-prem, AWS EC2, Azure VM)
- Python 3.x installed and in PATH
- `sqlcmd.exe` in PATH (SQL Server tools / ODBC client tools)
- NSSM (Non-Sucking Service Manager) to wrap python as a Windows Service

## 2. Directory Layout
Create:
`C:\sql-http-service\`

Copy in:
- `C:\sql-http-service\sql_http_service.py`
- `C:\sql-http-service\sql-http-service.conf`

Example `sql-http-service.conf`:
```ini
[service]
sql_server=localhost
database=YourAppDB
port=8080
allowed_procs=Inventory:dbo.Api_GetInventory
```

## 3. Test Manually
Open PowerShell (Run as Administrator):

```powershell
python C:\sql-http-service\sql_http_service.py C:\sql-http-service\sql-http-service.conf
```

In another window:
```powershell
curl "http://127.0.0.1:8080/api?proc=Inventory&user=svc_api_readonly&pass=N3%26yq9dV%234uWgZr%21L0p%5ECH1tR7%40xFm2K"
```

You should get JSON.

Ctrl+C to stop the server.

## 4. Install as a Windows Service using NSSM
Download `nssm.exe` (place at e.g. `C:\nssm\nssm.exe`).

Then run:
```powershell
C:\nssm\nssm.exe install sql-http-service `
  "C:\Python39\python.exe" `
  "C:\sql-http-service\sql_http_service.py" `
  "C:\sql-http-service\sql-http-service.conf"
```

Adjust python path if different.

Then:
```powershell
Start-Service sql-http-service
Get-Service sql-http-service
```

## 5. Verify Binding
```powershell
netstat -ano | findstr 8080
```
Expect to see `127.0.0.1:8080` in LISTENING.

## 6. Security Notes
- Service binds ONLY to 127.0.0.1, so it's not remotely accessible.
- Caller MUST present valid SQL credentials.
- The SQL login `svc_api_readonly` only has EXECUTE on approved procs.
- Every call is logged in DBATools.dbo.Api_AccessLog.

## 7. Revocation
- `Stop-Service sql-http-service`
- Rotate SQL password for `svc_api_readonly`
- Revoke EXECUTE from exposed proc
