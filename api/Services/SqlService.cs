using Dapper;
using Microsoft.Data.SqlClient;
using SqlMonitor.Api.Models;
using System.Data;

namespace SqlMonitor.Api.Services;

/// <summary>
/// SQL database service using Dapper and stored procedures
/// </summary>
public class SqlService : ISqlService
{
    private readonly SqlConnectionFactory _connectionFactory;

    public SqlService(SqlConnectionFactory connectionFactory)
    {
        _connectionFactory = connectionFactory;
    }

    public async Task<IEnumerable<Server>> GetServersAsync(bool? isActive = null, string? environment = null)
    {
        using var connection = _connectionFactory.CreateConnection();

        return await connection.QueryAsync<Server>(
            "dbo.usp_GetServers",
            new { IsActive = isActive, Environment = environment },
            commandType: CommandType.StoredProcedure);
    }

    public async Task InsertMetricAsync(InsertMetricRequest request)
    {
        using var connection = _connectionFactory.CreateConnection();

        await connection.ExecuteAsync(
            "dbo.usp_InsertMetrics",
            new
            {
                ServerID = request.ServerID,
                CollectionTime = request.CollectionTime,
                MetricCategory = request.MetricCategory,
                MetricName = request.MetricName,
                MetricValue = request.MetricValue
            },
            commandType: CommandType.StoredProcedure);
    }

    public async Task<IEnumerable<PerformanceMetric>> GetMetricsAsync(
        int serverID,
        DateTime? startTime = null,
        DateTime? endTime = null,
        string? metricCategory = null,
        string? metricName = null)
    {
        using var connection = _connectionFactory.CreateConnection();

        return await connection.QueryAsync<PerformanceMetric>(
            "dbo.usp_GetMetrics",
            new
            {
                ServerID = serverID,
                StartTime = startTime,
                EndTime = endTime,
                MetricCategory = metricCategory,
                MetricName = metricName
            },
            commandType: CommandType.StoredProcedure);
    }

    public async Task<Server?> GetServerByIdAsync(int serverId)
    {
        using var connection = _connectionFactory.CreateConnection();

        var servers = await connection.QueryAsync<Server>(
            "SELECT ServerID, ServerName, Environment, IsActive, CreatedDate, ModifiedDate FROM dbo.Servers WHERE ServerID = @ServerId",
            new { ServerId = serverId });

        return servers.FirstOrDefault();
    }

    public async Task<ObjectCode?> GetObjectCodeAsync(int serverId, string database, string schema, string objectName)
    {
        using var connection = _connectionFactory.CreateConnection();

        var result = await connection.QueryAsync<ObjectCode>(
            "dbo.usp_GetObjectCode",
            new
            {
                ServerID = serverId,
                DatabaseName = database,
                SchemaName = schema,
                ObjectName = objectName
            },
            commandType: CommandType.StoredProcedure);

        return result.FirstOrDefault();
    }

    public async Task CollectMetricsAsync(int serverId, bool includeAdvanced = false)
    {
        using var connection = _connectionFactory.CreateConnection();

        if (includeAdvanced)
        {
            // Call usp_CollectAllAdvancedMetrics (includes server + drill-down + advanced)
            await connection.ExecuteAsync(
                "dbo.usp_CollectAllAdvancedMetrics",
                new { ServerID = serverId },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 300); // 5 minute timeout for advanced metrics
        }
        else
        {
            // Call usp_CollectAllMetrics (server + drill-down only, fast)
            await connection.ExecuteAsync(
                "dbo.usp_CollectAllMetrics",
                new { ServerID = serverId },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 60); // 1 minute timeout for fast collection
        }
    }

    public async Task<DateTime?> GetLastCollectionTimeAsync(int serverId)
    {
        using var connection = _connectionFactory.CreateConnection();

        var result = await connection.QueryFirstOrDefaultAsync<DateTime?>(
            @"SELECT MAX(CollectionTime)
              FROM dbo.PerformanceMetrics
              WHERE ServerID = @ServerId",
            new { ServerId = serverId });

        return result;
    }

    public async Task LogAuditEventAsync(
        string eventType,
        string userName,
        string? applicationName = null,
        string? hostName = null,
        string? ipAddress = null,
        string? databaseName = null,
        string? schemaName = null,
        string? objectName = null,
        string? objectType = null,
        string? actionType = null,
        string? oldValue = null,
        string? newValue = null,
        int? affectedRows = null,
        string? sqlText = null,
        int? errorNumber = null,
        string? errorMessage = null,
        string? severity = "Information",
        string? dataClassification = "Internal",
        string? complianceFlag = "SOC2",
        int retentionDays = 2555)
    {
        using var connection = _connectionFactory.CreateConnection();

        await connection.ExecuteAsync(
            "dbo.usp_LogAuditEvent",
            new
            {
                EventType = eventType,
                UserName = userName,
                ApplicationName = applicationName,
                HostName = hostName,
                IPAddress = ipAddress,
                DatabaseName = databaseName,
                SchemaName = schemaName,
                ObjectName = objectName,
                ObjectType = objectType,
                ActionType = actionType,
                OldValue = oldValue,
                NewValue = newValue,
                AffectedRows = affectedRows,
                SqlText = sqlText,
                ErrorNumber = errorNumber,
                ErrorMessage = errorMessage,
                Severity = severity,
                DataClassification = dataClassification,
                ComplianceFlag = complianceFlag,
                RetentionDays = retentionDays
            },
            commandType: CommandType.StoredProcedure,
            commandTimeout: 5); // Short timeout for audit logging
    }
}

/// <summary>
/// Factory for creating SQL connections
/// </summary>
public class SqlConnectionFactory
{
    private readonly string _connectionString;

    public SqlConnectionFactory(string connectionString)
    {
        _connectionString = connectionString;
    }

    public SqlConnection CreateConnection()
    {
        return new SqlConnection(_connectionString);
    }
}
