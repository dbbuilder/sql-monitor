using System.Security.Claims;

namespace SqlMonitor.Api.Services;

/// <summary>
/// Service for JWT token generation and validation
/// Phase 2.0 Week 2 Day 6-7: Authentication Integration
/// SOC 2 Controls: CC6.1, CC6.2
/// </summary>
public interface IJwtService
{
    /// <summary>
    /// Generates a JWT token for an authenticated user
    /// </summary>
    /// <param name="userId">User ID</param>
    /// <param name="userName">Username</param>
    /// <param name="email">User email</param>
    /// <param name="roles">User roles (optional)</param>
    /// <returns>JWT token string</returns>
    string GenerateToken(int userId, string userName, string email, IEnumerable<string>? roles = null);

    /// <summary>
    /// Validates a JWT token and extracts claims
    /// </summary>
    /// <param name="token">JWT token to validate</param>
    /// <returns>ClaimsPrincipal if valid, null if invalid</returns>
    ClaimsPrincipal? ValidateToken(string token);

    /// <summary>
    /// Extracts user ID from a validated token
    /// </summary>
    /// <param name="principal">ClaimsPrincipal from validated token</param>
    /// <returns>User ID if found, null otherwise</returns>
    int? GetUserIdFromToken(ClaimsPrincipal principal);

    /// <summary>
    /// Extracts username from a validated token
    /// </summary>
    /// <param name="principal">ClaimsPrincipal from validated token</param>
    /// <returns>Username if found, null otherwise</returns>
    string? GetUserNameFromToken(ClaimsPrincipal principal);
}
