namespace SqlMonitor.Api.Models;

/// <summary>
/// User authentication information retrieved from database
/// Phase 2.0 Week 2 Day 6-7: Authentication Integration
/// </summary>
public class UserAuthInfo
{
    public int UserID { get; set; }
    public string UserName { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string? FullName { get; set; }
    public bool IsActive { get; set; }
    public bool IsLocked { get; set; }
    public int FailedLoginAttempts { get; set; }
    public DateTime? LastLoginTime { get; set; }
    public string? LastLoginIP { get; set; }
    public byte[] PasswordHash { get; set; } = Array.Empty<byte>();
    public byte[] PasswordSalt { get; set; } = Array.Empty<byte>();
    public bool MustChangePassword { get; set; }
}
