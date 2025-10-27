using OtpNet;
using QRCoder;

namespace SqlMonitor.Api.Services;

/// <summary>
/// TOTP (Time-based One-Time Password) service implementation
/// Uses OtpNet library for RFC 6238 compliance
/// Phase 2.0 Week 3 Days 11-12: Multi-Factor Authentication
/// SOC 2 Controls: CC6.1, CC6.2, CC6.8
/// </summary>
public class TotpService : ITotpService
{
    private readonly ILogger<TotpService> _logger;

    public TotpService(ILogger<TotpService> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Generates a new random TOTP secret (Base32-encoded)
    /// Secret is 160 bits (20 bytes) as recommended by RFC 6238
    /// </summary>
    public string GenerateSecret()
    {
        var key = KeyGeneration.GenerateRandomKey(20); // 160 bits
        var base32Secret = Base32Encoding.ToString(key);

        _logger.LogInformation("Generated new TOTP secret (length: {Length})", base32Secret.Length);

        return base32Secret;
    }

    /// <summary>
    /// Generates otpauth:// URI for QR code
    /// Format: otpauth://totp/{issuer}:{email}?secret={secret}&issuer={issuer}
    /// </summary>
    public string GenerateQrCodeUri(string email, string secret, string issuer = "SQL Monitor")
    {
        if (string.IsNullOrWhiteSpace(email))
            throw new ArgumentException("Email cannot be empty", nameof(email));

        if (string.IsNullOrWhiteSpace(secret))
            throw new ArgumentException("Secret cannot be empty", nameof(secret));

        // URI encode the components
        var encodedIssuer = Uri.EscapeDataString(issuer);
        var encodedEmail = Uri.EscapeDataString(email);
        var encodedSecret = Uri.EscapeDataString(secret);

        // Build otpauth URI
        var uri = $"otpauth://totp/{encodedIssuer}:{encodedEmail}?secret={encodedSecret}&issuer={encodedIssuer}";

        _logger.LogInformation("Generated QR code URI for user {Email}", email);

        return uri;
    }

    /// <summary>
    /// Generates QR code image as Base64-encoded PNG
    /// Uses QRCoder library for image generation
    /// </summary>
    public string GenerateQrCodeImage(string qrCodeUri)
    {
        if (string.IsNullOrWhiteSpace(qrCodeUri))
            throw new ArgumentException("QR code URI cannot be empty", nameof(qrCodeUri));

        try
        {
            using var qrGenerator = new QRCodeGenerator();
            using var qrCodeData = qrGenerator.CreateQrCode(qrCodeUri, QRCodeGenerator.ECCLevel.Q);
            using var qrCode = new PngByteQRCode(qrCodeData);

            var qrCodeBytes = qrCode.GetGraphic(20); // 20 pixels per module
            var base64Image = Convert.ToBase64String(qrCodeBytes);

            _logger.LogInformation("Generated QR code image (size: {Size} bytes)", qrCodeBytes.Length);

            return base64Image;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to generate QR code image");
            throw;
        }
    }

    /// <summary>
    /// Validates a TOTP code against a secret
    /// Uses time window tolerance to account for clock drift
    /// Default tolerance: ±30 seconds (1 window before/after)
    /// </summary>
    public bool ValidateCode(string secret, string code, int timeToleranceSeconds = 30)
    {
        if (string.IsNullOrWhiteSpace(secret))
        {
            _logger.LogWarning("TOTP validation failed: Secret is empty");
            return false;
        }

        if (string.IsNullOrWhiteSpace(code) || code.Length != 6)
        {
            _logger.LogWarning("TOTP validation failed: Code is invalid (length: {Length})", code?.Length ?? 0);
            return false;
        }

        try
        {
            // Decode Base32 secret
            var secretBytes = Base32Encoding.ToBytes(secret);

            // Create TOTP instance
            var totp = new Totp(secretBytes);

            // Validate with time window
            var timeWindow = TimeSpan.FromSeconds(timeToleranceSeconds);
            long timeStepMatched;

            var isValid = totp.VerifyTotp(code, out timeStepMatched, window: VerificationWindow.RfcSpecifiedNetworkDelay);

            if (isValid)
            {
                _logger.LogInformation("TOTP validation succeeded (time step: {TimeStep})", timeStepMatched);
            }
            else
            {
                _logger.LogWarning("TOTP validation failed: Code does not match");
            }

            return isValid;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "TOTP validation error: {Message}", ex.Message);
            return false;
        }
    }

    /// <summary>
    /// Gets the current TOTP code for a secret
    /// Useful for testing and debugging
    /// </summary>
    public string GetCurrentCode(string secret)
    {
        if (string.IsNullOrWhiteSpace(secret))
            throw new ArgumentException("Secret cannot be empty", nameof(secret));

        try
        {
            var secretBytes = Base32Encoding.ToBytes(secret);
            var totp = new Totp(secretBytes);
            var code = totp.ComputeTotp();

            return code;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to compute current TOTP code");
            throw;
        }
    }
}
