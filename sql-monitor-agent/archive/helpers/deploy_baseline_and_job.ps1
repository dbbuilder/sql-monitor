$Server = "sqltest.schoolvision.net,14333"
$Username = "sv"
$Password = "Gv51076!"

$env:SQLCMDPASSWORD = $Password

Write-Host "Deploying original baseline procedure with QUOTED_IDENTIFIER fix..."
sqlcmd -S $Server -U $Username -d DBATools -N -C -i "/mnt/e/Downloads/sql_monitor/03_create_DBA_CollectPerformanceSnapshot.sql"

Write-Host "`nRedeploying master orchestrator..."
sqlcmd -S $Server -U $Username -d DBATools -N -C -i "/mnt/e/Downloads/sql_monitor/10_create_master_orchestrator_FIXED.sql"

Write-Host "`nCreating SQL Agent job for every 5 minutes..."
sqlcmd -S $Server -U $Username -d msdb -N -C -i "/mnt/e/Downloads/sql_monitor/04_create_agent_job_linux.sql"

Write-Host "`nDone!"
