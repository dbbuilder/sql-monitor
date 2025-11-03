using Microsoft.AspNetCore.Mvc;
using SqlMonitor.Api.Models;
using SqlMonitor.Api.Services;
using System.Text;
using System.Data;
using Microsoft.Data.SqlClient;
using System.Diagnostics;

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

    /// <summary>
    /// Execute SQL query and return results
    /// </summary>
    /// <param name="request">Query execution request</param>
    /// <returns>Query results with execution time and row counts</returns>
    [HttpPost("execute")]
    [ProducesResponseType(typeof(ExecuteQueryResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<ActionResult<ExecuteQueryResponse>> ExecuteQuery([FromBody] ExecuteQueryRequest request)
    {
        var response = new ExecuteQueryResponse();
        var stopwatch = Stopwatch.StartNew();

        try
        {
            // Validate request
            if (request.ServerId <= 0)
            {
                return BadRequest(new { error = "Invalid server ID" });
            }

            if (string.IsNullOrWhiteSpace(request.Database))
            {
                return BadRequest(new { error = "Database name is required" });
            }

            if (string.IsNullOrWhiteSpace(request.Query))
            {
                return BadRequest(new { error = "Query is required" });
            }

            if (request.TimeoutSeconds < 1 || request.TimeoutSeconds > 600)
            {
                return BadRequest(new { error = "Timeout must be between 1 and 600 seconds" });
            }

            _logger.LogInformation(
                "Executing query on server {ServerId}, database {Database}",
                request.ServerId, request.Database);

            // Get server connection string
            var server = await _sqlService.GetServerByIdAsync(request.ServerId);
            if (server == null)
            {
                return BadRequest(new { error = $"Server {request.ServerId} not found" });
            }

            // Build connection string
            var connectionString = $"Server={server.ServerName};Database={request.Database};Integrated Security=true;Connection Timeout={request.TimeoutSeconds};TrustServerCertificate=True;";

            using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync();

            using var command = new SqlCommand(request.Query, connection);
            command.CommandTimeout = request.TimeoutSeconds;
            command.CommandType = CommandType.Text;

            // Track messages (PRINT statements, etc.)
            var messages = new List<string>();
            connection.InfoMessage += (sender, args) =>
            {
                messages.Add(args.Message);
            };

            using var reader = await command.ExecuteReaderAsync();

            do
            {
                var resultSet = new QueryResultSet();

                // Get column metadata
                var schemaTable = reader.GetSchemaTable();
                if (schemaTable != null)
                {
                    foreach (DataRow schemaRow in schemaTable.Rows)
                    {
                        var column = new QueryColumn
                        {
                            Name = schemaRow["ColumnName"].ToString() ?? "",
                            DataType = schemaRow["DataTypeName"].ToString() ?? "",
                            IsNullable = (bool)(schemaRow["AllowDBNull"] ?? false),
                            MaxLength = schemaRow["ColumnSize"] != DBNull.Value
                                ? Convert.ToInt32(schemaRow["ColumnSize"])
                                : null
                        };
                        resultSet.Columns.Add(column);
                    }
                }

                // Read rows (limit to MaxRows)
                int rowCount = 0;
                while (await reader.ReadAsync() && rowCount < request.MaxRows)
                {
                    var row = new Dictionary<string, object?>();
                    for (int i = 0; i < reader.FieldCount; i++)
                    {
                        var value = reader.IsDBNull(i) ? null : reader.GetValue(i);
                        row[reader.GetName(i)] = value;
                    }
                    resultSet.Rows.Add(row);
                    rowCount++;
                }

                response.ResultSets.Add(resultSet);

            } while (await reader.NextResultAsync());

            response.RowsAffected = reader.RecordsAffected;
            response.Messages = messages;
            response.Success = true;

            stopwatch.Stop();
            response.ExecutionTimeMs = stopwatch.ElapsedMilliseconds;

            _logger.LogInformation(
                "Query executed successfully in {ElapsedMs}ms, {ResultSetCount} result sets, {RowsAffected} rows affected",
                response.ExecutionTimeMs, response.ResultSets.Count, response.RowsAffected);

            return Ok(response);
        }
        catch (SqlException ex)
        {
            stopwatch.Stop();
            response.ExecutionTimeMs = stopwatch.ElapsedMilliseconds;
            response.Success = false;
            response.Error = $"SQL Error: {ex.Message} (Line {ex.LineNumber})";

            _logger.LogError(ex, "SQL error executing query");
            return Ok(response); // Return 200 with error in response body
        }
        catch (Exception ex)
        {
            stopwatch.Stop();
            response.ExecutionTimeMs = stopwatch.ElapsedMilliseconds;
            response.Success = false;
            response.Error = ex.Message;

            _logger.LogError(ex, "Error executing query");
            return Ok(response); // Return 200 with error in response body
        }
    }

    /// <summary>
    /// Analyze query for rewrite suggestions
    /// </summary>
    /// <param name="request">Query analysis request</param>
    /// <returns>List of rewrite suggestions</returns>
    [HttpPost("analyze-rewrites")]
    [ProducesResponseType(typeof(AnalyzeQueryRewriteResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<ActionResult<AnalyzeQueryRewriteResponse>> AnalyzeQueryRewrites([FromBody] AnalyzeQueryRewriteRequest request)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(request.QueryText))
            {
                return BadRequest(new { error = "Query text is required" });
            }

            _logger.LogInformation("Analyzing query for rewrites");

            // Call stored procedure to analyze query
            var suggestions = await _sqlService.ExecuteStoredProcedureAsync<QueryRewriteSuggestion>(
                "dbo.usp_AnalyzeQueryForRewrites",
                new Dictionary<string, object?>
                {
                    { "@QueryText", request.QueryText },
                    { "@ServerID", request.ServerId },
                    { "@DatabaseName", request.DatabaseName }
                });

            var response = new AnalyzeQueryRewriteResponse
            {
                Suggestions = suggestions.ToList()
            };

            return Ok(response);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error analyzing query for rewrites");
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Get query percentiles for a server
    /// </summary>
    /// <param name="serverId">Server ID</param>
    /// <param name="timeWindowMinutes">Time window in minutes (default: 60)</param>
    /// <returns>Query percentile data</returns>
    [HttpGet("percentiles/{serverId}")]
    [ProducesResponseType(typeof(QueryPercentilesResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<ActionResult<QueryPercentilesResponse>> GetQueryPercentiles(
        int serverId,
        [FromQuery] int timeWindowMinutes = 60)
    {
        try
        {
            _logger.LogInformation(
                "Getting query percentiles for server {ServerId}, time window {TimeWindow} minutes",
                serverId, timeWindowMinutes);

            // First calculate percentiles
            await _sqlService.ExecuteStoredProcedureAsync<object>(
                "dbo.usp_CalculateQueryPercentiles",
                new Dictionary<string, object?>
                {
                    { "@ServerID", serverId },
                    { "@TimeWindowMinutes", timeWindowMinutes }
                });

            // Then get performance insights
            var queries = await _sqlService.ExecuteStoredProcedureAsync<QueryPercentileData>(
                "dbo.usp_GetQueryPerformanceInsights",
                new Dictionary<string, object?>
                {
                    { "@ServerID", serverId },
                    { "@TopN", 50 }
                });

            var response = new QueryPercentilesResponse
            {
                Queries = queries.ToList(),
                TimeWindowMinutes = timeWindowMinutes
            };

            return Ok(response);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting query percentiles");
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Get wait statistics by category for a server
    /// </summary>
    /// <param name="serverId">Server ID</param>
    /// <param name="timeWindowMinutes">Time window in minutes (default: 60)</param>
    /// <returns>Wait statistics by category</returns>
    [HttpGet("wait-categories/{serverId}")]
    [ProducesResponseType(typeof(WaitStatsByCategoryResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<ActionResult<WaitStatsByCategoryResponse>> GetWaitStatsByCategory(
        int serverId,
        [FromQuery] int timeWindowMinutes = 60)
    {
        try
        {
            _logger.LogInformation(
                "Getting wait statistics by category for server {ServerId}, time window {TimeWindow} minutes",
                serverId, timeWindowMinutes);

            var categories = await _sqlService.ExecuteStoredProcedureAsync<WaitCategoryData>(
                "dbo.usp_GetWaitStatsByCategory",
                new Dictionary<string, object?>
                {
                    { "@ServerID", serverId },
                    { "@TimeWindowMinutes", timeWindowMinutes }
                });

            var categoriesList = categories.ToList();
            var totalWaitTime = categoriesList.Sum(c => c.TotalWaitTimeMs);

            var response = new WaitStatsByCategoryResponse
            {
                Categories = categoriesList,
                TimeWindowMinutes = timeWindowMinutes,
                TotalWaitTimeMs = totalWaitTime
            };

            return Ok(response);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting wait statistics by category");
            return StatusCode(500, new { error = ex.Message });
        }
    }
}
