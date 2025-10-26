using Microsoft.AspNetCore.Mvc;
using SqlMonitor.Api.Models;
using SqlMonitor.Api.Services;
using System.Text;

namespace SqlMonitor.Api.Controllers;

/// <summary>
/// Controller for database object code preview and SSMS integration
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class CodeController : ControllerBase
{
    private readonly ISqlService _sqlService;
    private readonly ILogger<CodeController> _logger;

    public CodeController(ISqlService sqlService, ILogger<CodeController>? logger = null)
    {
        _sqlService = sqlService;
        _logger = logger ?? new LoggerFactory().CreateLogger<CodeController>();
    }

    /// <summary>
    /// Get object code (cached or live retrieval)
    /// </summary>
    /// <param name="serverId">Server ID</param>
    /// <param name="database">Database name</param>
    /// <param name="schema">Schema name</param>
    /// <param name="objectName">Object name</param>
    /// <returns>Object code and metadata</returns>
    [HttpGet("{serverId}/{database}/{schema}/{objectName}")]
    [ProducesResponseType(typeof(ObjectCode), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<ActionResult<ObjectCode>> GetObjectCode(
        int serverId,
        string database,
        string schema,
        string objectName)
    {
        try
        {
            _logger.LogInformation(
                "Retrieving code for {Schema}.{Object} in {Database} on server {ServerId}",
                schema, objectName, database, serverId);

            var code = await _sqlService.GetObjectCodeAsync(serverId, database, schema, objectName);

            if (code == null)
            {
                return NotFound(new {
                    error = $"Object {schema}.{objectName} not found in database {database}"
                });
            }

            return Ok(code);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving object code");
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Download object code as .sql file with connection info embedded
    /// </summary>
    /// <param name="serverId">Server ID</param>
    /// <param name="database">Database name</param>
    /// <param name="schema">Schema name</param>
    /// <param name="objectName">Object name</param>
    /// <returns>SQL file download</returns>
    [HttpGet("{serverId}/{database}/{schema}/{objectName}/download")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> DownloadObjectCode(
        int serverId,
        string database,
        string schema,
        string objectName)
    {
        try
        {
            // Get server info
            var server = await _sqlService.GetServerByIdAsync(serverId);
            if (server == null)
            {
                return NotFound(new { error = $"Server {serverId} not found" });
            }

            // Get object code
            var code = await _sqlService.GetObjectCodeAsync(serverId, database, schema, objectName);
            if (code == null)
            {
                return NotFound(new {
                    error = $"Object {schema}.{objectName} not found in database {database}"
                });
            }

            // Build SQL file with connection info header
            var sqlFile = new StringBuilder();
            sqlFile.AppendLine("/*");
            sqlFile.AppendLine("==============================================================================");
            sqlFile.AppendLine($"  Object: {schema}.{objectName}");
            sqlFile.AppendLine($"  Database: {database}");
            sqlFile.AppendLine($"  Server: {server.ServerName}");
            sqlFile.AppendLine($"  Type: {code.ObjectType}");
            sqlFile.AppendLine($"  Retrieved: {DateTime.UtcNow:yyyy-MM-dd HH:mm:ss} UTC");
            sqlFile.AppendLine("==============================================================================");
            sqlFile.AppendLine();
            sqlFile.AppendLine("CONNECTION INFO:");
            sqlFile.AppendLine($"  Server: {server.ServerName}");
            sqlFile.AppendLine($"  Database: {database}");
            sqlFile.AppendLine($"  Authentication: SQL Server Authentication or Windows Authentication");
            sqlFile.AppendLine();
            sqlFile.AppendLine("INSTRUCTIONS:");
            sqlFile.AppendLine("  1. Open this file in SQL Server Management Studio (SSMS)");
            sqlFile.AppendLine($"  2. Connect to server: {server.ServerName}");
            sqlFile.AppendLine($"  3. Switch to database: {database}");
            sqlFile.AppendLine("  4. Review and execute as needed");
            sqlFile.AppendLine("==============================================================================");
            sqlFile.AppendLine("*/");
            sqlFile.AppendLine();
            sqlFile.AppendLine($"USE [{database}];");
            sqlFile.AppendLine("GO");
            sqlFile.AppendLine();
            sqlFile.AppendLine(code.Definition);

            var fileContent = Encoding.UTF8.GetBytes(sqlFile.ToString());
            var fileName = $"{schema}.{objectName}.sql";

            return File(fileContent, "text/plain", fileName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error downloading object code");
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Download batch file to open object in SSMS (Windows only)
    /// </summary>
    /// <param name="serverId">Server ID</param>
    /// <param name="database">Database name</param>
    /// <param name="schema">Schema name</param>
    /// <param name="objectName">Object name</param>
    /// <returns>Batch file download</returns>
    [HttpGet("{serverId}/{database}/{schema}/{objectName}/ssms-launcher")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> DownloadSsmsLauncher(
        int serverId,
        string database,
        string schema,
        string objectName)
    {
        try
        {
            // Get server info
            var server = await _sqlService.GetServerByIdAsync(serverId);
            if (server == null)
            {
                return NotFound(new { error = $"Server {serverId} not found" });
            }

            // Get object code
            var code = await _sqlService.GetObjectCodeAsync(serverId, database, schema, objectName);
            if (code == null)
            {
                return NotFound(new {
                    error = $"Object {schema}.{objectName} not found in database {database}"
                });
            }

            // Create temporary SQL file path
            var tempFileName = $"{schema}.{objectName}.sql";
            var tempFilePath = $"%TEMP%\\{tempFileName}";

            // Build batch file that:
            // 1. Creates SQL file in temp directory
            // 2. Launches SSMS with connection parameters
            // 3. Opens the SQL file
            var batchFile = new StringBuilder();
            batchFile.AppendLine("@echo off");
            batchFile.AppendLine($"REM ===================================================================");
            batchFile.AppendLine($"REM   SSMS Launcher for {schema}.{objectName}");
            batchFile.AppendLine($"REM   Server: {server.ServerName}");
            batchFile.AppendLine($"REM   Database: {database}");
            batchFile.AppendLine($"REM ===================================================================");
            batchFile.AppendLine();
            batchFile.AppendLine("echo Creating SQL file...");
            batchFile.AppendLine($"echo USE [{database}]; > {tempFilePath}");
            batchFile.AppendLine($"echo GO >> {tempFilePath}");

            // Escape the code definition for batch file
            var escapedCode = code.Definition?.Replace("\"", "\"\"") ?? "";
            var codeLines = escapedCode.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
            foreach (var line in codeLines)
            {
                batchFile.AppendLine($"echo {line} >> {tempFilePath}");
            }

            batchFile.AppendLine();
            batchFile.AppendLine("echo Launching SSMS...");
            batchFile.AppendLine($"start \"\" \"C:\\Program Files (x86)\\Microsoft SQL Server Management Studio 19\\Common7\\IDE\\Ssms.exe\" -S \"{server.ServerName}\" -d \"{database}\" {tempFilePath}");
            batchFile.AppendLine();
            batchFile.AppendLine("REM Alternative SSMS 18 path:");
            batchFile.AppendLine($"REM start \"\" \"C:\\Program Files (x86)\\Microsoft SQL Server Management Studio 18\\Common7\\IDE\\Ssms.exe\" -S \"{server.ServerName}\" -d \"{database}\" {tempFilePath}");
            batchFile.AppendLine();
            batchFile.AppendLine("echo.");
            batchFile.AppendLine("echo If SSMS did not open, you may need to adjust the SSMS installation path in this batch file.");
            batchFile.AppendLine("pause");

            var fileContent = Encoding.UTF8.GetBytes(batchFile.ToString());
            var fileName = $"Open-{schema}.{objectName}-in-SSMS.bat";

            return File(fileContent, "application/x-bat", fileName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error generating SSMS launcher");
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Generate SSMS connection string for manual use
    /// </summary>
    /// <param name="serverId">Server ID</param>
    /// <param name="database">Database name</param>
    /// <returns>Connection information</returns>
    [HttpGet("connection-info/{serverId}/{database}")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<ActionResult> GetConnectionInfo(int serverId, string database)
    {
        try
        {
            var server = await _sqlService.GetServerByIdAsync(serverId);
            if (server == null)
            {
                return NotFound(new { error = $"Server {serverId} not found" });
            }

            return Ok(new
            {
                server = server.ServerName,
                database = database,
                ssmsCommandLine = $"Ssms.exe -S \"{server.ServerName}\" -d \"{database}\"",
                sqlcmdCommandLine = $"sqlcmd -S \"{server.ServerName}\" -d \"{database}\" -E",
                connectionString = $"Server={server.ServerName};Database={database};Integrated Security=true;"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving connection info");
            return StatusCode(500, new { error = ex.Message });
        }
    }
}
