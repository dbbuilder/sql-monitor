$Server = "sqltest.schoolvision.net,14333"
$Username = "sv"
$Password = "Gv51076!"

$env:SQLCMDPASSWORD = $Password

Write-Host "Creating SQL Agent job..."
sqlcmd -S $Server -U $Username -d msdb -N -C -i "/mnt/e/Downloads/sql_monitor/04_create_agent_job_FIXED.sql"

Write-Host "`nVerifying job was created..."
sqlcmd -S $Server -U $Username -d msdb -N -C -Q "SELECT name, enabled, date_created FROM msdb.dbo.sysjobs WHERE name = 'DBA Collect Perf Snapshot'"
