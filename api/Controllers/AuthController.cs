using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SqlMonitor.Api.Services;

namespace SqlMonitor.Api.Controllers;

/// <summary>
/// Authentication controller - Login, logout, password management
/// Phase 2.0 Week 2 Day 6-7: Authentication Integration
/// SOC 2 Controls: CC6.1, CC6.2, CC6.3
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class AuthController : ControllerBase
{
    private readonly ISqlService _sqlService;
    private readonly IPasswordService _passwordService;
    private readonly IJwtService _jwtService;
    private readonly ILogger<AuthController> _logger;

    public AuthController(
        ISqlService sqlService,
        IPasswordService passwordService,
        IJwtService jwtService,
        ILogger<AuthController> logger)
    {
        _sqlService = sqlService;
        _passwordService = passwordService;
        _jwtService = jwtService;
        _logger = logger;
    }

    /// <summary>
    /// Login endpoint - Authenticates user and returns JWT token
    /// </summary>
    [HttpPost("login")]
    [AllowAnonymous]
    public async Task<IActionResult> Login([FromBody] LoginRequest request)
    {
        try
        {
            // Validate request
            if (string.IsNullOrWhiteSpace(request.UserNameOrEmail) || string.IsNullOrWhiteSpace(request.Password))
            {
                return BadRequest(new { error = "Username/email and password are required" });
            }

            // Get user from database
            var user = await _sqlService.GetUserByUserNameOrEmailAsync(request.UserNameOrEmail);

            if (user == null)
            {
                // Log failed attempt (user not found)
                await _sqlService.LogAuditEventAsync(
                    eventType: "LoginAttemptUserNotFound",
                    userName: request.UserNameOrEmail,
                    ipAddress: GetClientIPAddress(),
                    severity: "Warning",
                    complianceFlag: "SOC2",
                    retentionDays: 2555);

                _logger.LogWarning("Login attempt failed: user {UserName} not found", request.UserNameOrEmail);
                return Unauthorized(new { error = "Invalid username or password" });
            }

            // Check if user is active
            if (!user.IsActive)
            {
                await _sqlService.LogAuditEventAsync(
                    eventType: "LoginAttemptInactiveUser",
                    userName: user.UserName,
                    ipAddress: GetClientIPAddress(),
                    severity: "Warning",
                    complianceFlag: "SOC2",
                    retentionDays: 2555);

                _logger.LogWarning("Login attempt failed: user {UserName} is inactive", user.UserName);
                return Unauthorized(new { error = "Account is inactive" });
            }

            // Check if user is locked
            if (user.IsLocked)
            {
                await _sqlService.LogAuditEventAsync(
                    eventType: "LoginAttemptLockedUser",
                    userName: user.UserName,
                    ipAddress: GetClientIPAddress(),
                    severity: "Critical",
                    complianceFlag: "SOC2",
                    retentionDays: 2555);

                _logger.LogWarning("Login attempt failed: user {UserName} is locked", user.UserName);
                return Unauthorized(new { error = "Account is locked due to multiple failed login attempts" });
            }

            // Verify password
            var passwordValid = _passwordService.VerifyPassword(request.Password, user.PasswordHash, user.PasswordSalt);

            if (!passwordValid)
            {
                await _sqlService.LogAuditEventAsync(
                    eventType: "LoginAttemptInvalidPassword",
                    userName: user.UserName,
                    ipAddress: GetClientIPAddress(),
                    severity: "Warning",
                    complianceFlag: "SOC2",
                    retentionDays: 2555);

                _logger.LogWarning("Login attempt failed: invalid password for user {UserName}", user.UserName);
                return Unauthorized(new { error = "Invalid username or password" });
            }

            // Update last login time
            await _sqlService.UpdateUserLastLoginAsync(user.UserID, GetClientIPAddress());

            // Generate JWT token
            var token = _jwtService.GenerateToken(user.UserID, user.UserName, user.Email);

            // Log successful login
            await _sqlService.LogAuditEventAsync(
                eventType: "LoginSuccess",
                userName: user.UserName,
                ipAddress: GetClientIPAddress(),
                severity: "Information",
                complianceFlag: "SOC2",
                retentionDays: 2555);

            _logger.LogInformation("User {UserName} logged in successfully", user.UserName);

            return Ok(new LoginResponse
            {
                Token = token,
                UserId = user.UserID,
                UserName = user.UserName,
                Email = user.Email,
                FullName = user.FullName,
                MustChangePassword = user.MustChangePassword,
                ExpiresIn = 3600 // 60 minutes in seconds
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during login for user {UserName}", request.UserNameOrEmail);
            return StatusCode(500, new { error = "An error occurred during login" });
        }
    }

    /// <summary>
    /// Logout endpoint - Logs user logout event (token invalidation is client-side for stateless JWT)
    /// </summary>
    [HttpPost("logout")]
    [Authorize]
    public async Task<IActionResult> Logout()
    {
        try
        {
            var userName = User.Identity?.Name ?? "Unknown";
            var userId = User.FindFirst("UserId")?.Value;

            // Log logout event
            await _sqlService.LogAuditEventAsync(
                eventType: "LogoutSuccess",
                userName: userName,
                ipAddress: GetClientIPAddress(),
                severity: "Information",
                complianceFlag: "SOC2",
                retentionDays: 2555);

            _logger.LogInformation("User {UserName} logged out", userName);

            return Ok(new { message = "Logged out successfully" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during logout");
            return StatusCode(500, new { error = "An error occurred during logout" });
        }
    }

    /// <summary>
    /// Get current user info from JWT token
    /// </summary>
    [HttpGet("me")]
    [Authorize]
    public IActionResult GetCurrentUser()
    {
        try
        {
            var userName = User.Identity?.Name;
            var userId = User.FindFirst("UserId")?.Value;
            var email = User.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value;

            if (string.IsNullOrEmpty(userName) || string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { error = "Invalid token" });
            }

            return Ok(new
            {
                userId = int.Parse(userId),
                userName,
                email
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving current user info");
            return StatusCode(500, new { error = "An error occurred" });
        }
    }

    /// <summary>
    /// Helper method to get client IP address
    /// </summary>
    private string GetClientIPAddress()
    {
        return HttpContext.Connection.RemoteIpAddress?.ToString() ?? "Unknown";
    }
}

/// <summary>
/// Login request model
/// </summary>
public class LoginRequest
{
    public string UserNameOrEmail { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
}

/// <summary>
/// Login response model
/// </summary>
public class LoginResponse
{
    public string Token { get; set; } = string.Empty;
    public int UserId { get; set; }
    public string UserName { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string? FullName { get; set; }
    public bool MustChangePassword { get; set; }
    public int ExpiresIn { get; set; } // Token expiration in seconds
}
