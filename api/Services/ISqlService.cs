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

    /// <summary>
    /// Gets server by ID
    /// </summary>
    Task<Server?> GetServerByIdAsync(int serverId);

    /// <summary>
    /// Gets database object code (cached or retrieves and caches)
    /// </summary>
    Task<ObjectCode?> GetObjectCodeAsync(int serverId, string database, string schema, string objectName);

    /// <summary>
    /// Triggers metrics collection for a server
    /// </summary>
    Task CollectMetricsAsync(int serverId, bool includeAdvanced = false);

    /// <summary>
    /// Gets the last collection time for a server
    /// </summary>
    Task<DateTime?> GetLastCollectionTimeAsync(int serverId);

    /// <summary>
    /// Logs an audit event (Phase 2.0 - SOC 2 compliance)
    /// </summary>
    Task LogAuditEventAsync(
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
        int retentionDays = 2555);

    /// <summary>
    /// Checks if a user has a specific permission (Phase 2.0 - RBAC)
    /// </summary>
    /// <param name="userId">User ID</param>
    /// <param name="resourceType">Resource type (e.g., "Servers", "Metrics")</param>
    /// <param name="actionType">Action type (e.g., "Read", "Write", "Delete")</param>
    /// <returns>True if user has permission, false otherwise</returns>
    Task<bool> CheckPermissionAsync(int userId, string resourceType, string actionType);

    /// <summary>
    /// Gets user by username or email (Phase 2.0 Week 2 - Authentication)
    /// </summary>
    /// <param name="userNameOrEmail">Username or email</param>
    /// <returns>User information including password hash and salt</returns>
    Task<UserAuthInfo?> GetUserByUserNameOrEmailAsync(string userNameOrEmail);

    /// <summary>
    /// Updates user last login time and IP (Phase 2.0 Week 2 - Authentication)
    /// </summary>
    Task UpdateUserLastLoginAsync(int userId, string ipAddress);

    /// <summary>
    /// Gets MFA settings for a user (Phase 2.0 Week 3 - MFA)
    /// </summary>
    Task<UserMFA?> GetUserMFAAsync(int userId);

    /// <summary>
    /// Enables MFA for a user (Phase 2.0 Week 3 - MFA)
    /// </summary>
    Task EnableMFAAsync(int userId, string mfaType, byte[]? totpSecret, string? totpSecretPlain, string? phoneNumber, string modifiedBy);

    /// <summary>
    /// Disables MFA for a user (Phase 2.0 Week 3 - MFA)
    /// </summary>
    Task DisableMFAAsync(int userId, string modifiedBy);

    /// <summary>
    /// Inserts a hashed backup code (Phase 2.0 Week 3 - MFA)
    /// </summary>
    Task InsertBackupCodeAsync(int userId, byte[] codeHash, byte[] codeSalt);

    /// <summary>
    /// Gets remaining backup codes count (Phase 2.0 Week 3 - MFA)
    /// </summary>
    Task<int> GetRemainingBackupCodesAsync(int userId);

    /// <summary>
    /// Logs MFA verification attempt (Phase 2.0 Week 3 - MFA)
    /// </summary>
    Task LogMFAAttemptAsync(int userId, string mfaType, bool isSuccess, string? failureReason, string? ipAddress, string? userAgent);
}
