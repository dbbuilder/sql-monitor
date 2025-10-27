namespace SqlMonitor.Api.Services;

/// <summary>
/// Service for secure password hashing and verification using BCrypt
/// Phase 2.0 Week 2 Day 6: Authentication Integration
/// SOC 2 Controls: CC6.1, CC6.2
/// </summary>
public interface IPasswordService
{
    /// <summary>
    /// Hashes a password using BCrypt with automatic salt generation
    /// </summary>
    /// <param name="password">Plain text password to hash</param>
    /// <returns>Tuple containing password hash and salt as byte arrays</returns>
    (byte[] Hash, byte[] Salt) HashPassword(string password);

    /// <summary>
    /// Verifies a password against a stored hash and salt
    /// </summary>
    /// <param name="password">Plain text password to verify</param>
    /// <param name="storedHash">Stored password hash (64 bytes)</param>
    /// <param name="storedSalt">Stored password salt (32 bytes)</param>
    /// <returns>True if password matches, false otherwise</returns>
    bool VerifyPassword(string password, byte[] storedHash, byte[] storedSalt);

    /// <summary>
    /// Generates a cryptographically secure random salt
    /// </summary>
    /// <returns>32-byte random salt</returns>
    byte[] GenerateSalt();
}
