using System.Security.Cryptography;
using System.Text;

namespace SqlMonitor.Api.Services;

/// <summary>
/// Backup code service for MFA recovery
/// Generates and verifies one-time use backup codes
/// Phase 2.0 Week 3 Days 11-12: Multi-Factor Authentication
/// SOC 2 Controls: CC6.1, CC6.2
/// </summary>
public class BackupCodeService : IBackupCodeService
{
    private readonly IPasswordService _passwordService;
    private readonly ILogger<BackupCodeService> _logger;

    // Backup code format: XXXX-XXXX (8 alphanumeric characters with dash)
    private const int CodeLength = 8;
    private const string CodeCharacters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // Excludes ambiguous characters (0,O,I,1)

    public BackupCodeService(IPasswordService passwordService, ILogger<BackupCodeService> logger)
    {
        _passwordService = passwordService;
        _logger = logger;
    }

    /// <summary>
    /// Generates a set of backup codes
    /// Format: XXXX-XXXX (e.g., "A3K7-9M2P")
    /// </summary>
    public List<string> GenerateBackupCodes(int count = 10)
    {
        if (count < 1 || count > 100)
            throw new ArgumentException("Count must be between 1 and 100", nameof(count));

        var codes = new List<string>();

        for (int i = 0; i < count; i++)
        {
            var code = GenerateSingleCode();
            codes.Add(code);
        }

        _logger.LogInformation("Generated {Count} backup codes", count);

        return codes;
    }

    /// <summary>
    /// Generates a single backup code using cryptographically secure random
    /// </summary>
    private string GenerateSingleCode()
    {
        var codeBytes = new byte[CodeLength];

        using (var rng = RandomNumberGenerator.Create())
        {
            rng.GetBytes(codeBytes);
        }

        var sb = new StringBuilder(CodeLength + 1); // +1 for dash

        for (int i = 0; i < CodeLength; i++)
        {
            // Map byte value to character set
            var charIndex = codeBytes[i] % CodeCharacters.Length;
            sb.Append(CodeCharacters[charIndex]);

            // Add dash after 4th character
            if (i == 3)
                sb.Append('-');
        }

        return sb.ToString();
    }

    /// <summary>
    /// Hashes a backup code for secure storage
    /// Uses same password hashing service (BCrypt-based)
    /// </summary>
    public (byte[] Hash, byte[] Salt) HashBackupCode(string code)
    {
        if (string.IsNullOrWhiteSpace(code))
            throw new ArgumentException("Backup code cannot be empty", nameof(code));

        // Normalize code (uppercase, remove whitespace/dashes)
        var normalizedCode = NormalizeCode(code);

        // Use password service for consistent hashing
        var (hash, salt) = _passwordService.HashPassword(normalizedCode);

        _logger.LogDebug("Hashed backup code (length: {Length})", normalizedCode.Length);

        return (hash, salt);
    }

    /// <summary>
    /// Verifies a backup code against stored hash and salt
    /// </summary>
    public bool VerifyBackupCode(string code, byte[] storedHash, byte[] storedSalt)
    {
        if (string.IsNullOrWhiteSpace(code))
        {
            _logger.LogWarning("Backup code verification failed: Code is empty");
            return false;
        }

        if (storedHash == null || storedHash.Length != 64)
        {
            _logger.LogWarning("Backup code verification failed: Invalid hash length");
            return false;
        }

        if (storedSalt == null || storedSalt.Length != 32)
        {
            _logger.LogWarning("Backup code verification failed: Invalid salt length");
            return false;
        }

        try
        {
            // Normalize code
            var normalizedCode = NormalizeCode(code);

            // Verify using password service
            var isValid = _passwordService.VerifyPassword(normalizedCode, storedHash, storedSalt);

            if (isValid)
            {
                _logger.LogInformation("Backup code verification succeeded");
            }
            else
            {
                _logger.LogWarning("Backup code verification failed: Code does not match");
            }

            return isValid;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Backup code verification error: {Message}", ex.Message);
            return false;
        }
    }

    /// <summary>
    /// Normalizes backup code for comparison
    /// Removes dashes, whitespace, and converts to uppercase
    /// </summary>
    private string NormalizeCode(string code)
    {
        return code
            .Replace("-", "")
            .Replace(" ", "")
            .ToUpperInvariant()
            .Trim();
    }
}
