namespace SqlMonitor.Api.Models;

/// <summary>
/// User session model
/// Phase 2.0 Week 3 Days 13-14: Session Management
/// </summary>
public class UserSession
{
    public Guid SessionID { get; set; }
    public int UserID { get; set; }
    public string SessionToken { get; set; } = string.Empty;
    public string? RefreshToken { get; set; }
    public byte[]? RefreshTokenHash { get; set; }
    public string IPAddress { get; set; } = string.Empty;
    public string? UserAgent { get; set; }
    public string? DeviceType { get; set; }
    public string? DeviceFingerprint { get; set; }
    public string? LocationCity { get; set; }
    public string? LocationCountry { get; set; }
    public DateTime LoginTime { get; set; }
    public DateTime LastActivityTime { get; set; }
    public DateTime ExpiresAt { get; set; }
    public bool IsActive { get; set; }
    public DateTime? LogoutTime { get; set; }
    public string? LogoutReason { get; set; }
    public bool RememberMe { get; set; }
    public DateTime CreatedDate { get; set; }
    public DateTime ModifiedDate { get; set; }
}

/// <summary>
/// Session activity audit record
/// </summary>
public class SessionActivity
{
    public long ActivityID { get; set; }
    public Guid SessionID { get; set; }
    public int UserID { get; set; }
    public string ActivityType { get; set; } = string.Empty;
    public DateTime ActivityTime { get; set; }
    public string? IPAddress { get; set; }
    public string? UserAgent { get; set; }
    public string? Endpoint { get; set; }
    public string? HttpMethod { get; set; }
    public int? ResponseStatus { get; set; }
    public string? Details { get; set; }
    public DateTime RetentionDate { get; set; }
}

/// <summary>
/// Request to create new session
/// </summary>
public class CreateSessionRequest
{
    public int UserID { get; set; }
    public string SessionToken { get; set; } = string.Empty;
    public string? RefreshToken { get; set; }
    public byte[]? RefreshTokenHash { get; set; }
    public string IPAddress { get; set; } = string.Empty;
    public string? UserAgent { get; set; }
    public string? DeviceType { get; set; }
    public string? DeviceFingerprint { get; set; }
    public string? LocationCity { get; set; }
    public string? LocationCountry { get; set; }
    public bool RememberMe { get; set; }
}

/// <summary>
/// Response after session creation
/// </summary>
public class CreateSessionResponse
{
    public Guid SessionID { get; set; }
    public DateTime ExpiresAt { get; set; }
    public bool RememberMe { get; set; }
}

/// <summary>
/// Request to refresh session
/// </summary>
public class RefreshSessionRequest
{
    public string RefreshToken { get; set; } = string.Empty;
    public string IPAddress { get; set; } = string.Empty;
}

/// <summary>
/// Response after session refresh
/// </summary>
public class RefreshSessionResponse
{
    public string SessionToken { get; set; } = string.Empty;
    public string? RefreshToken { get; set; }
    public DateTime ExpiresAt { get; set; }
}

/// <summary>
/// Session statistics for monitoring
/// </summary>
public class SessionStatistics
{
    public int ActiveSessions { get; set; }
    public int TotalSessionsCreated { get; set; }
    public int ExpiredSessions { get; set; }
    public int ForceLogouts { get; set; }
    public int ManualLogouts { get; set; }
    public double? AvgSessionDurationMinutes { get; set; }
    public int? PeakConcurrentSessions { get; set; }
}

/// <summary>
/// User session summary for display
/// </summary>
public class UserSessionSummary
{
    public Guid SessionID { get; set; }
    public string IPAddress { get; set; } = string.Empty;
    public string? DeviceType { get; set; }
    public string? LocationCity { get; set; }
    public string? LocationCountry { get; set; }
    public DateTime LoginTime { get; set; }
    public DateTime LastActivityTime { get; set; }
    public DateTime ExpiresAt { get; set; }
    public bool IsActive { get; set; }
    public bool IsCurrentSession { get; set; }
}
