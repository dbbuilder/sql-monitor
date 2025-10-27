namespace SqlMonitor.Api.Models;

/// <summary>
/// User MFA settings model
/// Phase 2.0 Week 3 Days 11-12: Multi-Factor Authentication
/// </summary>
public class UserMFA
{
    public int UserMFAID { get; set; }
    public int UserID { get; set; }
    public bool MFAEnabled { get; set; }
    public string MFAType { get; set; } = "TOTP";
    public byte[]? TOTPSecret { get; set; }
    public string? TOTPSecretPlain { get; set; }
    public string? PhoneNumber { get; set; }
    public bool PhoneNumberVerified { get; set; }
    public bool EmailVerified { get; set; }
    public int BackupCodesUsed { get; set; }
    public DateTime EnrolledDate { get; set; }
    public DateTime? LastUsedDate { get; set; }
}

/// <summary>
/// MFA enrollment request
/// </summary>
public class MFAEnrollmentRequest
{
    public string MFAType { get; set; } = "TOTP";
    public string? PhoneNumber { get; set; }
}

/// <summary>
/// MFA enrollment response
/// </summary>
public class MFAEnrollmentResponse
{
    public string Secret { get; set; } = string.Empty;
    public string QrCodeUri { get; set; } = string.Empty;
    public string QrCodeImage { get; set; } = string.Empty; // Base64 PNG
    public List<string> BackupCodes { get; set; } = new List<string>();
}

/// <summary>
/// MFA verification request
/// </summary>
public class MFAVerificationRequest
{
    public string Code { get; set; } = string.Empty;
    public bool IsBackupCode { get; set; } = false;
}

/// <summary>
/// MFA status response
/// </summary>
public class MFAStatusResponse
{
    public bool MFAEnabled { get; set; }
    public string? MFAType { get; set; }
    public int RemainingBackupCodes { get; set; }
    public DateTime? EnrolledDate { get; set; }
    public DateTime? LastUsedDate { get; set; }
}
