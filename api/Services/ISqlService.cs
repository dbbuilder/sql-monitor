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

    /// <summary>
    /// Creates a new user session (Phase 2.0 Week 3 Days 13-14 - Session Management)
    /// </summary>
    Task<Guid> CreateSessionAsync(CreateSessionRequest request);

    /// <summary>
    /// Gets all sessions for a user (Phase 2.0 Week 3 Days 13-14 - Session Management)
    /// </summary>
    Task<IEnumerable<UserSession>> GetUserSessionsAsync(int userId, bool includeInactive = false);

    /// <summary>
    /// Gets session by token (Phase 2.0 Week 3 Days 13-14 - Session Management)
    /// </summary>
    Task<UserSession?> GetSessionByTokenAsync(string sessionToken);

    /// <summary>
    /// Updates session last activity time (Phase 2.0 Week 3 Days 13-14 - Session Management)
    /// </summary>
    Task UpdateSessionActivityAsync(Guid sessionId, string? ipAddress, string? userAgent, string? endpoint, string? httpMethod, int? responseStatus);

    /// <summary>
    /// Refreshes session with new tokens (Phase 2.0 Week 3 Days 13-14 - Session Management)
    /// </summary>
    Task<Guid> RefreshSessionAsync(byte[] refreshTokenHash, string newSessionToken, string? newRefreshToken, byte[]? newRefreshTokenHash, string ipAddress);

    /// <summary>
    /// Logs out a session (Phase 2.0 Week 3 Days 13-14 - Session Management)
    /// </summary>
    Task LogoutSessionAsync(Guid sessionId, string logoutReason = "Manual", string? ipAddress = null);

    /// <summary>
    /// Force logout all sessions for a user (Phase 2.0 Week 3 Days 13-14 - Session Management)
    /// </summary>
    Task<int> ForceLogoutUserAsync(int userId, Guid? excludeSessionId = null, string? adminUserName = null);

    /// <summary>
    /// Enforces concurrent session limit for a user (Phase 2.0 Week 3 Days 13-14 - Session Management)
    /// </summary>
    Task EnforceConcurrentSessionLimitAsync(int userId, int maxSessions = 3, Guid? currentSessionId = null);

    /// <summary>
    /// Cleans up expired sessions (Phase 2.0 Week 3 Days 13-14 - Session Management)
    /// </summary>
    Task<int> CleanupExpiredSessionsAsync();

    /// <summary>
    /// Gets session statistics (Phase 2.0 Week 3 Days 13-14 - Session Management)
    /// </summary>
    Task<SessionStatistics?> GetSessionStatisticsAsync(int timeRangeHours = 24);

    /// <summary>
    /// Executes a stored procedure and returns results mapped to type T
    /// </summary>
    /// <typeparam name="T">Type to map results to</typeparam>
    /// <param name="procedureName">Stored procedure name</param>
    /// <param name="parameters">Stored procedure parameters</param>
    /// <returns>Collection of mapped results</returns>
    Task<IEnumerable<T>> ExecuteStoredProcedureAsync<T>(string procedureName, Dictionary<string, object?>? parameters = null);
}
