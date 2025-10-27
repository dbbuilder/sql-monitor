using System.Security.Cryptography;
using System.Text;
using BCrypt.Net;

namespace SqlMonitor.Api.Services;

/// <summary>
/// BCrypt-based password hashing service with secure salt generation
/// Phase 2.0 Week 2 Day 6: Authentication Integration
/// SOC 2 Controls: CC6.1, CC6.2
/// </summary>
public class PasswordService : IPasswordService
{
    private const int SaltSize = 32; // 32 bytes for salt (matches database schema)
    private const int HashSize = 64; // 64 bytes for hash (matches database schema)
    private const int BCryptWorkFactor = 12; // BCrypt work factor (cost)

    /// <summary>
    /// Hashes a password using BCrypt with automatic salt generation
    /// Returns 64-byte hash and 32-byte salt compatible with database schema
    /// </summary>
    public (byte[] Hash, byte[] Salt) HashPassword(string password)
    {
        if (string.IsNullOrWhiteSpace(password))
        {
            throw new ArgumentException("Password cannot be null or empty", nameof(password));
        }

        // Generate cryptographically secure salt
        var salt = GenerateSalt();

        // Combine password and salt for BCrypt hashing
        var saltedPassword = CombinePasswordAndSalt(password, salt);

        // Hash using BCrypt
        var bcryptHash = BCrypt.Net.BCrypt.HashPassword(saltedPassword, BCryptWorkFactor);

        // Convert BCrypt hash to 64-byte array (pad if necessary)
        var hash = ConvertBCryptHashToBytes(bcryptHash);

        return (hash, salt);
    }

    /// <summary>
    /// Verifies a password against stored hash and salt
    /// </summary>
    public bool VerifyPassword(string password, byte[] storedHash, byte[] storedSalt)
    {
        if (string.IsNullOrWhiteSpace(password))
        {
            return false;
        }

        if (storedHash == null || storedHash.Length != HashSize)
        {
            throw new ArgumentException($"Stored hash must be {HashSize} bytes", nameof(storedHash));
        }

        if (storedSalt == null || storedSalt.Length != SaltSize)
        {
            throw new ArgumentException($"Stored salt must be {SaltSize} bytes", nameof(storedSalt));
        }

        try
        {
            // Combine password and stored salt
            var saltedPassword = CombinePasswordAndSalt(password, storedSalt);

            // Convert stored hash back to BCrypt string format
            var bcryptHashString = ConvertBytesToBCryptHash(storedHash);

            // Verify using BCrypt
            return BCrypt.Net.BCrypt.Verify(saltedPassword, bcryptHashString);
        }
        catch
        {
            // Any exception during verification means password doesn't match
            return false;
        }
    }

    /// <summary>
    /// Generates a cryptographically secure 32-byte random salt
    /// </summary>
    public byte[] GenerateSalt()
    {
        var salt = new byte[SaltSize];
        using (var rng = RandomNumberGenerator.Create())
        {
            rng.GetBytes(salt);
        }
        return salt;
    }

    /// <summary>
    /// Combines password and salt for hashing
    /// </summary>
    private string CombinePasswordAndSalt(string password, byte[] salt)
    {
        // Convert salt to base64 for consistent string representation
        var saltString = Convert.ToBase64String(salt);
        return $"{password}{saltString}";
    }

    /// <summary>
    /// Converts BCrypt hash string to 64-byte array (pads with zeros if needed)
    /// </summary>
    private byte[] ConvertBCryptHashToBytes(string bcryptHash)
    {
        var hashBytes = Encoding.UTF8.GetBytes(bcryptHash);
        var result = new byte[HashSize];

        // Copy hash bytes to result (truncate or pad as needed)
        Array.Copy(hashBytes, result, Math.Min(hashBytes.Length, HashSize));

        return result;
    }

    /// <summary>
    /// Converts 64-byte hash array back to BCrypt string format
    /// </summary>
    private string ConvertBytesToBCryptHash(byte[] hashBytes)
    {
        // Find the actual end of the hash (first zero byte)
        var actualLength = Array.IndexOf(hashBytes, (byte)0);
        if (actualLength == -1)
        {
            actualLength = hashBytes.Length;
        }

        return Encoding.UTF8.GetString(hashBytes, 0, actualLength);
    }
}
