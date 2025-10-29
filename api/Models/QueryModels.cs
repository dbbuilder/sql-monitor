using System;

namespace SqlServerMonitor.Api.Models
{
    /// <summary>
    /// Top query model (cross-server query performance)
    /// Phase 1.9: Query Store analysis
    /// </summary>
    public class TopQueryModel
    {
        public int ServerID { get; set; }
        public string ServerName { get; set; } = string.Empty;
        public string DatabaseName { get; set; } = string.Empty;
        public long QueryID { get; set; }
        public long PlanID { get; set; }
        public string? QueryText { get; set; }

        // Execution statistics
        public long ExecutionCount { get; set; }
        public decimal TotalCpuMs { get; set; }
        public decimal AvgCpuMs { get; set; }
        public decimal MaxCpuMs { get; set; }

        // Duration statistics
        public decimal TotalDurationMs { get; set; }
        public decimal AvgDurationMs { get; set; }
        public decimal MaxDurationMs { get; set; }

        // I/O statistics
        public long TotalLogicalReads { get; set; }
        public decimal AvgLogicalReads { get; set; }
        public long MaxLogicalReads { get; set; }

        // Memory statistics
        public long? TotalMemoryGrantKB { get; set; }
        public decimal? AvgMemoryGrantKB { get; set; }
        public long? MaxMemoryGrantKB { get; set; }

        // Timing
        public DateTime? LastExecutionTime { get; set; }
        public DateTime? FirstExecutionTime { get; set; }
        public DateTime CollectionTime { get; set; }

        // Ranking
        public int? RankByMetric { get; set; }
    }
}
