using System;
using System.ComponentModel.DataAnnotations;

namespace SqlServerMonitor.Api.Models
{
    /// <summary>
    /// Server model (basic information)
    /// </summary>
    public class ServerModel
    {
        public int ServerID { get; set; }
        public string ServerName { get; set; } = string.Empty;
        public string Environment { get; set; } = string.Empty;
        public bool IsActive { get; set; }
        public DateTime CreatedUTC { get; set; }
        public DateTime? LastModifiedUTC { get; set; }
    }

    /// <summary>
    /// Server health status model (with real-time metrics)
    /// </summary>
    public class ServerHealthModel
    {
        public int ServerID { get; set; }
        public string ServerName { get; set; } = string.Empty;
        public string Environment { get; set; } = string.Empty;
        public bool IsActive { get; set; }

        // Latest collection metrics
        public DateTime? LastCollectionTime { get; set; }
        public decimal? LatestCpuPct { get; set; }
        public string? LatestTopWaitType { get; set; }
        public decimal? LatestTopWaitMsPerSec { get; set; }
        public int? LatestSessionsCount { get; set; }
        public int? LatestRequestsCount { get; set; }
        public int? LatestBlockingCount { get; set; }

        // Snapshot counts
        public long? TotalSnapshots { get; set; }
        public long? SnapshotsLast24Hours { get; set; }

        // 24-hour averages
        public decimal? Avg24HrCpuPct { get; set; }
        public decimal? Avg24HrSessionsCount { get; set; }
        public decimal? Avg24HrBlockingCount { get; set; }

        // Health status
        public string HealthStatus { get; set; } = string.Empty;
        public int? MinutesSinceLastCollection { get; set; }
    }

    /// <summary>
    /// Resource trend model (daily aggregates)
    /// </summary>
    public class ResourceTrendModel
    {
        public int ServerID { get; set; }
        public string ServerName { get; set; } = string.Empty;
        public string Environment { get; set; } = string.Empty;
        public DateTime CollectionDate { get; set; }

        // CPU metrics
        public decimal? AvgCpuPct { get; set; }
        public decimal? MaxCpuPct { get; set; }
        public decimal? P95CpuPct { get; set; }

        // Session metrics
        public decimal? AvgSessionsCount { get; set; }
        public int? MaxSessionsCount { get; set; }

        // Blocking metrics
        public decimal? AvgBlockingCount { get; set; }
        public int? MaxBlockingCount { get; set; }

        // Data points
        public int DataPoints { get; set; }
    }

    /// <summary>
    /// Database summary model
    /// </summary>
    public class DatabaseSummaryModel
    {
        public int ServerID { get; set; }
        public string ServerName { get; set; } = string.Empty;
        public string DatabaseName { get; set; } = string.Empty;

        // Size metrics
        public decimal DataSizeMB { get; set; }
        public decimal LogSizeMB { get; set; }
        public decimal TotalSizeMB { get; set; }
        public decimal? LogUsedPct { get; set; }

        // Configuration
        public string RecoveryModel { get; set; } = string.Empty;
        public string State { get; set; } = string.Empty;

        // Backup status
        public DateTime? LastFullBackupUTC { get; set; }
        public DateTime? LastLogBackupUTC { get; set; }
        public int? HoursSinceLastFullBackup { get; set; }
        public int? HoursSinceLastLogBackup { get; set; }
        public DateTime LastCollectionTime { get; set; }

        // Health status
        public string BackupHealthStatus { get; set; } = string.Empty;
    }

    /// <summary>
    /// Server registration request
    /// </summary>
    public class ServerRegistrationRequest
    {
        [Required]
        [StringLength(128, MinimumLength = 1)]
        public string ServerName { get; set; } = string.Empty;

        [StringLength(50)]
        public string? Environment { get; set; }

        public bool? IsActive { get; set; }
    }

    /// <summary>
    /// Server update request
    /// </summary>
    public class ServerUpdateRequest
    {
        [StringLength(50)]
        public string? Environment { get; set; }

        public bool? IsActive { get; set; }
    }
}
