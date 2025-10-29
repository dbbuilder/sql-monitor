$Server = "sqltest.schoolvision.net,14333"
$Database = "DBATools"
$Username = "sv"
$Password = "Gv51076!"

$env:SQLCMDPASSWORD = $Password

sqlcmd -S $Server -U $Username -d $Database -N -C -i "/mnt/e/Downloads/sql_monitor/check_status.sql"
