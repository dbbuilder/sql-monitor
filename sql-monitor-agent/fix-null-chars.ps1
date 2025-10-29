#!/usr/bin/env pwsh
param([string]$Server, [string]$User, [string]$Password)

Write-Host "Deploying NULL character fix to $Server..." -ForegroundColor Cyan

$sql = Get-Content "15_create_html_formatter.sql" -Raw -Encoding UTF8
$batches = $sql -split '(?m)^\s*GO\s*$' | Where-Object { $_.Trim() }

$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = "Server=$Server;Database=DBATools;User Id=$User;Password=$Password;TrustServerCertificate=True;Encrypt=False;Connection Timeout=30"
$conn.Open()

foreach ($batch in $batches) {
    if ($batch.Trim()) {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $batch
        $cmd.CommandTimeout = 60
        $cmd.ExecuteNonQuery() | Out-Null
        $cmd.Dispose()
    }
}

$conn.Close()
$conn.Dispose()

Write-Host "✓ HTML formatter updated!" -ForegroundColor Green
Write-Host "Now try generating the report again." -ForegroundColor Cyan
