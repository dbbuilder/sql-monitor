$Server = "sqltest.schoolvision.net,14333"
$Database = "DBATools"
$Username = "sv"
$Password = "Gv51076!"

$env:SQLCMDPASSWORD = $Password

sqlcmd -S $Server -U $Username -d $Database -N -C -Q "SELECT TOP 1 ErrDescription FROM dbo.LogEntry WHERE ProcedureName = 'DBA_CollectPerformanceSnapshot' AND IsError = 1 ORDER BY LogEntryID DESC"
