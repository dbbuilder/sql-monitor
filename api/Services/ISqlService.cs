using SqlMonitor.Api.Models;

namespace SqlMonitor.Api.Services;

/// <summary>
/// Interface for SQL database operations using stored procedures
/// </summary>
public interface ISqlService
{
    /// <summary>
    /// Gets list of monitored SQL Server instances
    /// </summary>
    Task<IEnumerable<Server>> GetServersAsync(bool? isActive = null, string? environment = null);

    /// <summary>
    /// Inserts a performance metric
    /// </summary>
    Task InsertMetricAsync(InsertMetricRequest request);

    /// <summary>
    /// Gets performance metrics with optional filters
    /// </summary>
    Task<IEnumerable<PerformanceMetric>> GetMetricsAsync(
        int serverID,
        DateTime? startTime = null,
        DateTime? endTime = null,
        string? metricCategory = null,
        string? metricName = null);
}
