namespace SqlMonitor.Api.Services;

/// <summary>
/// Service for MFA backup code generation and verification
/// Phase 2.0 Week 3 Days 11-12: Multi-Factor Authentication
/// SOC 2 Controls: CC6.1, CC6.2
/// </summary>
public interface IBackupCodeService
{
    /// <summary>
    /// Generates a set of backup codes for MFA recovery
    /// </summary>
    /// <param name="count">Number of codes to generate (default 10)</param>
    /// <returns>List of plain text backup codes</returns>
    List<string> GenerateBackupCodes(int count = 10);

    /// <summary>
    /// Hashes a backup code for storage
    /// </summary>
    /// <param name="code">Plain text backup code</param>
    /// <returns>Tuple of (Hash, Salt)</returns>
    (byte[] Hash, byte[] Salt) HashBackupCode(string code);

    /// <summary>
    /// Verifies a backup code against stored hash and salt
    /// </summary>
    /// <param name="code">Plain text backup code from user</param>
    /// <param name="storedHash">Stored hash (64 bytes)</param>
    /// <param name="storedSalt">Stored salt (32 bytes)</param>
    /// <returns>True if code matches, false otherwise</returns>
    bool VerifyBackupCode(string code, byte[] storedHash, byte[] storedSalt);
}
