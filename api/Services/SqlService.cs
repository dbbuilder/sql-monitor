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
