namespace SqlMonitor.Api.Services;

/// <summary>
/// Service for TOTP (Time-based One-Time Password) operations
/// Phase 2.0 Week 3 Days 11-12: Multi-Factor Authentication
/// SOC 2 Controls: CC6.1, CC6.2, CC6.8
/// </summary>
public interface ITotpService
{
    /// <summary>
    /// Generates a new TOTP secret for a user
    /// </summary>
    /// <returns>Base32-encoded secret string</returns>
    string GenerateSecret();

    /// <summary>
    /// Generates a QR code URI for authenticator app enrollment
    /// </summary>
    /// <param name="email">User's email</param>
    /// <param name="secret">TOTP secret (Base32)</param>
    /// <param name="issuer">Application name (e.g., "SQL Monitor")</param>
    /// <returns>otpauth:// URI for QR code</returns>
    string GenerateQrCodeUri(string email, string secret, string issuer = "SQL Monitor");

    /// <summary>
    /// Generates a QR code image as Base64 string
    /// </summary>
    /// <param name="qrCodeUri">otpauth:// URI</param>
    /// <returns>Base64-encoded PNG image</returns>
    string GenerateQrCodeImage(string qrCodeUri);

    /// <summary>
    /// Validates a TOTP code against a secret
    /// </summary>
    /// <param name="secret">TOTP secret (Base32)</param>
    /// <param name="code">6-digit code from user</param>
    /// <param name="timeToleranceSeconds">Time window tolerance (default 30 seconds)</param>
    /// <returns>True if code is valid, false otherwise</returns>
    bool ValidateCode(string secret, string code, int timeToleranceSeconds = 30);

    /// <summary>
    /// Gets the current TOTP code for a secret (for testing/display purposes)
    /// </summary>
    /// <param name="secret">TOTP secret (Base32)</param>
    /// <returns>Current 6-digit code</returns>
    string GetCurrentCode(string secret);
}
