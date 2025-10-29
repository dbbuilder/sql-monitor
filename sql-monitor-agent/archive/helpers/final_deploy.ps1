$Server = "sqltest.schoolvision.net,14333"
$Username = "sv"
$Password = "Gv51076!"

$env:SQLCMDPASSWORD = $Password

Write-Host "Dropping existing procedure..."
sqlcmd -S $Server -U $Username -d DBATools -N -C -i "/mnt/e/Downloads/sql_monitor/fix_quoted_identifier.sql"

Write-Host "`nRecreating procedure with QUOTED_IDENTIFIER ON..."
sqlcmd -S $Server -U $Username -d DBATools -N -C -i "/mnt/e/Downloads/sql_monitor/10_create_master_orchestrator_FIXED.sql"

Write-Host "`nTesting collection..."
sqlcmd -S $Server -U $Username -d DBATools -N -C -Q "EXEC dbo.DBA_CollectPerformanceSnapshot @Debug = 1"

Write-Host "`nChecking results..."
sqlcmd -S $Server -U $Username -d DBATools -N -C -Q "SELECT COUNT(*) AS SnapshotCount FROM DBATools.dbo.PerfSnapshotRun"
