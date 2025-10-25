namespace SqlMonitor.Api.Models;

/// <summary>
/// Represents a performance metric collected from a SQL Server instance
/// </summary>
public class PerformanceMetric
{
    public long MetricID { get; set; }
    public int ServerID { get; set; }
    public string ServerName { get; set; } = string.Empty;
    public DateTime CollectionTime { get; set; }
    public string MetricCategory { get; set; } = string.Empty;
    public string MetricName { get; set; } = string.Empty;
    public decimal? MetricValue { get; set; }
}

/// <summary>
/// Request model for inserting a new performance metric
/// </summary>
public class InsertMetricRequest
{
    public int ServerID { get; set; }
    public DateTime CollectionTime { get; set; }
    public string MetricCategory { get; set; } = string.Empty;
    public string MetricName { get; set; } = string.Empty;
    public decimal? MetricValue { get; set; }
}
