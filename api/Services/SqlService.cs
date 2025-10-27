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

    public async Task<bool> CheckPermissionAsync(int userId, string resourceType, string actionType)
    {
        using var connection = _connectionFactory.CreateConnection();

        var parameters = new DynamicParameters();
        parameters.Add("@UserID", userId);
        parameters.Add("@ResourceType", resourceType);
        parameters.Add("@ActionType", actionType);
        parameters.Add("@HasPermission", dbType: DbType.Boolean, direction: ParameterDirection.Output);

        await connection.ExecuteAsync(
            "dbo.usp_CheckPermission",
            parameters,
            commandType: CommandType.StoredProcedure);

        return parameters.Get<bool>("@HasPermission");
    }

    public async Task<UserAuthInfo?> GetUserByUserNameOrEmailAsync(string userNameOrEmail)
    {
        using var connection = _connectionFactory.CreateConnection();

        // Try username first
        var users = await connection.QueryAsync<UserAuthInfo>(
            "dbo.usp_GetUserByUserName",
            new { UserName = userNameOrEmail },
            commandType: CommandType.StoredProcedure);

        var user = users.FirstOrDefault();

        // If not found by username, try email
        if (user == null)
        {
            var usersByEmail = await connection.QueryAsync<UserAuthInfo>(
                "dbo.usp_GetUserByEmail",
                new { Email = userNameOrEmail },
                commandType: CommandType.StoredProcedure);

            user = usersByEmail.FirstOrDefault();
        }

        return user;
    }

    public async Task UpdateUserLastLoginAsync(int userId, string ipAddress)
    {
        using var connection = _connectionFactory.CreateConnection();

        await connection.ExecuteAsync(
            "dbo.usp_UpdateUserLastLogin",
            new { UserID = userId, IPAddress = ipAddress },
            commandType: CommandType.StoredProcedure);
    }

    public async Task<UserMFA?> GetUserMFAAsync(int userId)
    {
        using var connection = _connectionFactory.CreateConnection();

        var result = await connection.QueryAsync<UserMFA>(
            "dbo.usp_GetUserMFA",
            new { UserID = userId },
            commandType: CommandType.StoredProcedure);

        return result.FirstOrDefault();
    }

    public async Task EnableMFAAsync(int userId, string mfaType, byte[]? totpSecret, string? totpSecretPlain, string? phoneNumber, string modifiedBy)
    {
        using var connection = _connectionFactory.CreateConnection();

        await connection.ExecuteAsync(
            "dbo.usp_EnableMFA",
            new
            {
                UserID = userId,
                MFAType = mfaType,
                TOTPSecret = totpSecret,
                TOTPSecretPlain = totpSecretPlain,
                PhoneNumber = phoneNumber,
                ModifiedBy = modifiedBy
            },
            commandType: CommandType.StoredProcedure);
    }

    public async Task DisableMFAAsync(int userId, string modifiedBy)
    {
        using var connection = _connectionFactory.CreateConnection();

        await connection.ExecuteAsync(
            "dbo.usp_DisableMFA",
            new { UserID = userId, ModifiedBy = modifiedBy },
            commandType: CommandType.StoredProcedure);
    }

    public async Task InsertBackupCodeAsync(int userId, byte[] codeHash, byte[] codeSalt)
    {
        using var connection = _connectionFactory.CreateConnection();

        await connection.ExecuteAsync(
            "dbo.usp_InsertBackupCode",
            new { UserID = userId, CodeHash = codeHash, CodeSalt = codeSalt },
            commandType: CommandType.StoredProcedure);
    }

    public async Task<int> GetRemainingBackupCodesAsync(int userId)
    {
        using var connection = _connectionFactory.CreateConnection();

        var parameters = new DynamicParameters();
        parameters.Add("@UserID", userId);
        parameters.Add("@RemainingCount", dbType: DbType.Int32, direction: ParameterDirection.Output);

        await connection.ExecuteAsync(
            "dbo.usp_GetRemainingBackupCodes",
            parameters,
            commandType: CommandType.StoredProcedure);

        return parameters.Get<int>("@RemainingCount");
    }

    public async Task LogMFAAttemptAsync(int userId, string mfaType, bool isSuccess, string? failureReason, string? ipAddress, string? userAgent)
    {
        using var connection = _connectionFactory.CreateConnection();

        await connection.ExecuteAsync(
            "dbo.usp_LogMFAAttempt",
            new
            {
                UserID = userId,
                MFAType = mfaType,
                IsSuccess = isSuccess,
                FailureReason = failureReason,
                IPAddress = ipAddress,
                UserAgent = userAgent
            },
            commandType: CommandType.StoredProcedure);
    }

    // =============================================
    // Session Management Methods (Phase 2.0 Week 3 Days 13-14)
    // =============================================

    public async Task<Guid> CreateSessionAsync(CreateSessionRequest request)
    {
        using var connection = _connectionFactory.CreateConnection();

        var parameters = new DynamicParameters();
        parameters.Add("@UserID", request.UserID);
        parameters.Add("@SessionToken", request.SessionToken);
        parameters.Add("@RefreshToken", request.RefreshToken);
        parameters.Add("@RefreshTokenHash", request.RefreshTokenHash);
        parameters.Add("@IPAddress", request.IPAddress);
        parameters.Add("@UserAgent", request.UserAgent);
        parameters.Add("@DeviceType", request.DeviceType);
        parameters.Add("@DeviceFingerprint", request.DeviceFingerprint);
        parameters.Add("@LocationCity", request.LocationCity);
        parameters.Add("@LocationCountry", request.LocationCountry);
        parameters.Add("@RememberMe", request.RememberMe);
        parameters.Add("@SessionID", dbType: DbType.Guid, direction: ParameterDirection.Output);

        await connection.ExecuteAsync(
            "dbo.usp_CreateSession",
            parameters,
            commandType: CommandType.StoredProcedure);

        return parameters.Get<Guid>("@SessionID");
    }

    public async Task<IEnumerable<UserSession>> GetUserSessionsAsync(int userId, bool includeInactive = false)
    {
        using var connection = _connectionFactory.CreateConnection();

        return await connection.QueryAsync<UserSession>(
            "dbo.usp_GetUserSessions",
            new { UserID = userId, IncludeInactive = includeInactive },
            commandType: CommandType.StoredProcedure);
    }

    public async Task<UserSession?> GetSessionByTokenAsync(string sessionToken)
    {
        using var connection = _connectionFactory.CreateConnection();

        var result = await connection.QueryAsync<UserSession>(
            "dbo.usp_GetSessionByToken",
            new { SessionToken = sessionToken },
            commandType: CommandType.StoredProcedure);

        return result.FirstOrDefault();
    }

    public async Task UpdateSessionActivityAsync(Guid sessionId, string? ipAddress, string? userAgent, string? endpoint, string? httpMethod, int? responseStatus)
    {
        using var connection = _connectionFactory.CreateConnection();

        await connection.ExecuteAsync(
            "dbo.usp_UpdateSessionActivity",
            new
            {
                SessionID = sessionId,
                IPAddress = ipAddress,
                UserAgent = userAgent,
                Endpoint = endpoint,
                HttpMethod = httpMethod,
                ResponseStatus = responseStatus
            },
            commandType: CommandType.StoredProcedure);
    }

    public async Task<Guid> RefreshSessionAsync(byte[] refreshTokenHash, string newSessionToken, string? newRefreshToken, byte[]? newRefreshTokenHash, string ipAddress)
    {
        using var connection = _connectionFactory.CreateConnection();

        var parameters = new DynamicParameters();
        parameters.Add("@RefreshTokenHash", refreshTokenHash);
        parameters.Add("@NewSessionToken", newSessionToken);
        parameters.Add("@NewRefreshToken", newRefreshToken);
        parameters.Add("@NewRefreshTokenHash", newRefreshTokenHash);
        parameters.Add("@IPAddress", ipAddress);
        parameters.Add("@SessionID", dbType: DbType.Guid, direction: ParameterDirection.Output);

        await connection.ExecuteAsync(
            "dbo.usp_RefreshSession",
            parameters,
            commandType: CommandType.StoredProcedure);

        return parameters.Get<Guid>("@SessionID");
    }

    public async Task LogoutSessionAsync(Guid sessionId, string logoutReason = "Manual", string? ipAddress = null)
    {
        using var connection = _connectionFactory.CreateConnection();

        await connection.ExecuteAsync(
            "dbo.usp_LogoutSession",
            new
            {
                SessionID = sessionId,
                LogoutReason = logoutReason,
                IPAddress = ipAddress
            },
            commandType: CommandType.StoredProcedure);
    }

    public async Task<int> ForceLogoutUserAsync(int userId, Guid? excludeSessionId = null, string? adminUserName = null)
    {
        using var connection = _connectionFactory.CreateConnection();

        var result = await connection.QueryAsync<int>(
            "dbo.usp_ForceLogoutUser",
            new
            {
                UserID = userId,
                ExcludeSessionID = excludeSessionId,
                AdminUserName = adminUserName
            },
            commandType: CommandType.StoredProcedure);

        return result.FirstOrDefault();
    }

    public async Task EnforceConcurrentSessionLimitAsync(int userId, int maxSessions = 3, Guid? currentSessionId = null)
    {
        using var connection = _connectionFactory.CreateConnection();

        await connection.ExecuteAsync(
            "dbo.usp_EnforceConcurrentSessionLimit",
            new
            {
                UserID = userId,
                MaxSessions = maxSessions,
                CurrentSessionID = currentSessionId
            },
            commandType: CommandType.StoredProcedure);
    }

    public async Task<int> CleanupExpiredSessionsAsync()
    {
        using var connection = _connectionFactory.CreateConnection();

        var result = await connection.QueryAsync<int>(
            "dbo.usp_CleanupExpiredSessions",
            commandType: CommandType.StoredProcedure);

        return result.FirstOrDefault();
    }

    public async Task<SessionStatistics?> GetSessionStatisticsAsync(int timeRangeHours = 24)
    {
        using var connection = _connectionFactory.CreateConnection();

        var result = await connection.QueryAsync<SessionStatistics>(
            "dbo.usp_GetSessionStatistics",
            new { TimeRangeHours = timeRangeHours },
            commandType: CommandType.StoredProcedure);

        return result.FirstOrDefault();
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
