using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SqlMonitor.Api.Models;
using SqlMonitor.Api.Services;

namespace SqlMonitor.Api.Controllers;

/// <summary>
/// Session management controller
/// Phase 2.0 Week 3 Days 13-14: Session Management
/// SOC 2 Controls: CC6.1, CC6.6, CC6.7
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class SessionController : ControllerBase
{
    private readonly ISqlService _sqlService;
    private readonly ILogger<SessionController> _logger;

    public SessionController(ISqlService sqlService, ILogger<SessionController> logger)
    {
        _sqlService = sqlService;
        _logger = logger;
    }

    /// <summary>
    /// Get all sessions for current user
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetMySessions()
    {
        try
        {
            var userId = GetCurrentUserId();
            if (userId == null)
                return Unauthorized(new { error = "User not authenticated" });

            var sessions = await _sqlService.GetUserSessionsAsync(userId.Value, includeInactive: false);

            // Convert to summary format
            var currentSessionId = GetCurrentSessionId();
            var summaries = sessions.Select(s => new UserSessionSummary
            {
                SessionID = s.SessionID,
                IPAddress = s.IPAddress,
                DeviceType = s.DeviceType,
                LocationCity = s.LocationCity,
                LocationCountry = s.LocationCountry,
                LoginTime = s.LoginTime,
                LastActivityTime = s.LastActivityTime,
                ExpiresAt = s.ExpiresAt,
                IsActive = s.IsActive,
                IsCurrentSession = s.SessionID == currentSessionId
            }).ToList();

            return Ok(summaries);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting user sessions");
            return StatusCode(500, new { error = "An error occurred" });
        }
    }

    /// <summary>
    /// Logout current session
    /// </summary>
    [HttpPost("logout")]
    public async Task<IActionResult> Logout()
    {
        try
        {
            var sessionId = GetCurrentSessionId();
            var userId = GetCurrentUserId();
            var userName = GetCurrentUserName();

            if (sessionId == null || userId == null)
                return Unauthorized(new { error = "User not authenticated" });

            await _sqlService.LogoutSessionAsync(sessionId.Value, "Manual", GetClientIPAddress());

            // Audit log
            await _sqlService.LogAuditEventAsync(
                eventType: "SessionLogout",
                userName: userName ?? "Unknown",
                ipAddress: GetClientIPAddress(),
                severity: "Information",
                complianceFlag: "SOC2",
                retentionDays: 2555
            );

            _logger.LogInformation("User {UserId} logged out session {SessionId}", userId, sessionId);

            return Ok(new { message = "Logged out successfully" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error logging out session");
            return StatusCode(500, new { error = "An error occurred" });
        }
    }

    /// <summary>
    /// Logout a specific session (for managing multiple sessions)
    /// </summary>
    [HttpDelete("{sessionId}")]
    public async Task<IActionResult> LogoutSession(Guid sessionId)
    {
        try
        {
            var userId = GetCurrentUserId();
            var userName = GetCurrentUserName();

            if (userId == null)
                return Unauthorized(new { error = "User not authenticated" });

            // Verify session belongs to user
            var sessions = await _sqlService.GetUserSessionsAsync(userId.Value, includeInactive: false);
            var session = sessions.FirstOrDefault(s => s.SessionID == sessionId);

            if (session == null)
                return NotFound(new { error = "Session not found or not owned by user" });

            await _sqlService.LogoutSessionAsync(sessionId, "Manual", GetClientIPAddress());

            // Audit log
            await _sqlService.LogAuditEventAsync(
                eventType: "SessionLogout",
                userName: userName ?? "Unknown",
                ipAddress: GetClientIPAddress(),
                severity: "Information",
                complianceFlag: "SOC2",
                retentionDays: 2555,
                actionType: "LogoutOtherSession"
            );

            _logger.LogInformation("User {UserId} logged out session {SessionId}", userId, sessionId);

            return Ok(new { message = "Session logged out successfully" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error logging out specific session");
            return StatusCode(500, new { error = "An error occurred" });
        }
    }

    /// <summary>
    /// Logout all other sessions (keep current session active)
    /// </summary>
    [HttpPost("logout-all-others")]
    public async Task<IActionResult> LogoutAllOtherSessions()
    {
        try
        {
            var userId = GetCurrentUserId();
            var userName = GetCurrentUserName();
            var currentSessionId = GetCurrentSessionId();

            if (userId == null || currentSessionId == null)
                return Unauthorized(new { error = "User not authenticated" });

            var loggedOutCount = await _sqlService.ForceLogoutUserAsync(
                userId.Value,
                excludeSessionId: currentSessionId.Value,
                adminUserName: userName
            );

            // Audit log
            await _sqlService.LogAuditEventAsync(
                eventType: "LogoutAllOtherSessions",
                userName: userName ?? "Unknown",
                ipAddress: GetClientIPAddress(),
                severity: "Information",
                complianceFlag: "SOC2",
                retentionDays: 2555,
                affectedRows: loggedOutCount
            );

            _logger.LogInformation("User {UserId} logged out {Count} other sessions", userId, loggedOutCount);

            return Ok(new { message = $"Logged out {loggedOutCount} other session(s)", count = loggedOutCount });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error logging out all other sessions");
            return StatusCode(500, new { error = "An error occurred" });
        }
    }

    /// <summary>
    /// Get session statistics (admin only)
    /// </summary>
    [HttpGet("statistics")]
    public async Task<IActionResult> GetStatistics([FromQuery] int timeRangeHours = 24)
    {
        try
        {
            // Note: In production, add role-based authorization check for admin
            var userId = GetCurrentUserId();
            if (userId == null)
                return Unauthorized(new { error = "User not authenticated" });

            var stats = await _sqlService.GetSessionStatisticsAsync(timeRangeHours);

            if (stats == null)
                return NotFound(new { error = "No statistics available" });

            return Ok(stats);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting session statistics");
            return StatusCode(500, new { error = "An error occurred" });
        }
    }

    /// <summary>
    /// Cleanup expired sessions (admin/system only)
    /// </summary>
    [HttpPost("cleanup-expired")]
    public async Task<IActionResult> CleanupExpiredSessions()
    {
        try
        {
            // Note: In production, add role-based authorization check for admin/system
            var userId = GetCurrentUserId();
            var userName = GetCurrentUserName();

            if (userId == null)
                return Unauthorized(new { error = "User not authenticated" });

            var cleanedCount = await _sqlService.CleanupExpiredSessionsAsync();

            // Audit log
            await _sqlService.LogAuditEventAsync(
                eventType: "SessionCleanup",
                userName: userName ?? "System",
                ipAddress: GetClientIPAddress(),
                severity: "Information",
                complianceFlag: "SOC2",
                retentionDays: 2555,
                affectedRows: cleanedCount
            );

            _logger.LogInformation("Cleaned up {Count} expired sessions", cleanedCount);

            return Ok(new { message = $"Cleaned up {cleanedCount} expired session(s)", count = cleanedCount });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error cleaning up expired sessions");
            return StatusCode(500, new { error = "An error occurred" });
        }
    }

    /// <summary>
    /// Helper method to get current user ID from claims
    /// </summary>
    private int? GetCurrentUserId()
    {
        var userIdClaim = User.FindFirst("UserId")?.Value;
        return userIdClaim != null && int.TryParse(userIdClaim, out var userId) ? userId : null;
    }

    /// <summary>
    /// Helper method to get current username from claims
    /// </summary>
    private string? GetCurrentUserName()
    {
        return User.Identity?.Name;
    }

    /// <summary>
    /// Helper method to get current session ID from claims
    /// </summary>
    private Guid? GetCurrentSessionId()
    {
        var sessionIdClaim = User.FindFirst("SessionId")?.Value;
        return sessionIdClaim != null && Guid.TryParse(sessionIdClaim, out var sessionId) ? sessionId : null;
    }

    /// <summary>
    /// Helper method to get client IP address
    /// </summary>
    private string GetClientIPAddress()
    {
        return HttpContext.Connection.RemoteIpAddress?.ToString() ?? "Unknown";
    }
}
