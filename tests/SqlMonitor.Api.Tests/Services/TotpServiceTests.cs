using Xunit;
using SqlMonitor.Api.Services;
using System;
using System.Text.RegularExpressions;
using Moq;
using Microsoft.Extensions.Logging;

namespace SqlMonitor.Api.Tests.Services;

/// <summary>
/// Unit tests for TotpService (Time-based One-Time Password)
/// Phase 2.0 Week 3 Days 11-12: Multi-Factor Authentication
/// </summary>
public class TotpServiceTests
{
    private readonly ITotpService _totpService;
    private readonly Mock<ILogger<TotpService>> _mockLogger;

    public TotpServiceTests()
    {
        _mockLogger = new Mock<ILogger<TotpService>>();
        _totpService = new TotpService(_mockLogger.Object);
    }

    #region GenerateSecret Tests

    [Fact]
    public void GenerateSecret_ShouldReturnNonEmptyString()
    {
        // Act
        var secret = _totpService.GenerateSecret();

        // Assert
        Assert.NotNull(secret);
        Assert.NotEmpty(secret);
    }

    [Fact]
    public void GenerateSecret_ShouldReturnBase32EncodedString()
    {
        // Act
        var secret = _totpService.GenerateSecret();

        // Assert
        // Base32 alphabet: A-Z, 2-7, padding with =
        var base32Pattern = new Regex(@"^[A-Z2-7]+=*$");
        Assert.Matches(base32Pattern, secret);
    }

    [Fact]
    public void GenerateSecret_ShouldReturnDifferentSecretsOnEachCall()
    {
        // Act
        var secret1 = _totpService.GenerateSecret();
        var secret2 = _totpService.GenerateSecret();
        var secret3 = _totpService.GenerateSecret();

        // Assert
        Assert.NotEqual(secret1, secret2);
        Assert.NotEqual(secret2, secret3);
        Assert.NotEqual(secret1, secret3);
    }

    [Fact]
    public void GenerateSecret_ShouldReturnSecretWithSufficientLength()
    {
        // Act
        var secret = _totpService.GenerateSecret();

        // Assert
        // RFC 6238 recommends at least 128 bits (20 bytes = 160 bits)
        // Base32 encoding: 5 bits per character
        // 160 bits / 5 bits = 32 characters (without padding)
        Assert.True(secret.Length >= 32, $"Secret length {secret.Length} is too short");
    }

    #endregion

    #region GenerateQrCodeUri Tests

    [Fact]
    public void GenerateQrCodeUri_ShouldReturnValidOtpauthUri()
    {
        // Arrange
        var email = "test@example.com";
        var secret = _totpService.GenerateSecret();

        // Act
        var uri = _totpService.GenerateQrCodeUri(email, secret);

        // Assert
        Assert.NotNull(uri);
        Assert.StartsWith("otpauth://totp/", uri);
    }

    [Fact]
    public void GenerateQrCodeUri_ShouldIncludeEmailInUri()
    {
        // Arrange
        var email = "test@example.com";
        var secret = _totpService.GenerateSecret();

        // Act
        var uri = _totpService.GenerateQrCodeUri(email, secret);

        // Assert
        Assert.Contains(Uri.EscapeDataString(email), uri);
    }

    [Fact]
    public void GenerateQrCodeUri_ShouldIncludeSecretInUri()
    {
        // Arrange
        var email = "test@example.com";
        var secret = _totpService.GenerateSecret();

        // Act
        var uri = _totpService.GenerateQrCodeUri(email, secret);

        // Assert
        Assert.Contains($"secret={Uri.EscapeDataString(secret)}", uri);
    }

    [Fact]
    public void GenerateQrCodeUri_ShouldIncludeIssuerInUri()
    {
        // Arrange
        var email = "test@example.com";
        var secret = _totpService.GenerateSecret();
        var issuer = "SQL Monitor";

        // Act
        var uri = _totpService.GenerateQrCodeUri(email, secret, issuer);

        // Assert
        Assert.Contains($"issuer={Uri.EscapeDataString(issuer)}", uri);
        Assert.Contains($"{Uri.EscapeDataString(issuer)}:", uri);
    }

    [Fact]
    public void GenerateQrCodeUri_ShouldHandleSpecialCharactersInEmail()
    {
        // Arrange
        var email = "test+user@example.com";
        var secret = _totpService.GenerateSecret();

        // Act
        var uri = _totpService.GenerateQrCodeUri(email, secret);

        // Assert
        Assert.NotNull(uri);
        Assert.Contains(Uri.EscapeDataString(email), uri);
    }

    [Fact]
    public void GenerateQrCodeUri_ShouldUseDefaultIssuerWhenNotProvided()
    {
        // Arrange
        var email = "test@example.com";
        var secret = _totpService.GenerateSecret();

        // Act
        var uri = _totpService.GenerateQrCodeUri(email, secret);

        // Assert
        Assert.Contains("SQL%20Monitor", uri);
    }

    #endregion

    #region GenerateQrCodeImage Tests

    [Fact]
    public void GenerateQrCodeImage_ShouldReturnBase64String()
    {
        // Arrange
        var email = "test@example.com";
        var secret = _totpService.GenerateSecret();
        var uri = _totpService.GenerateQrCodeUri(email, secret);

        // Act
        var qrCodeImage = _totpService.GenerateQrCodeImage(uri);

        // Assert
        Assert.NotNull(qrCodeImage);
        Assert.NotEmpty(qrCodeImage);
    }

    [Fact]
    public void GenerateQrCodeImage_ShouldReturnValidBase64()
    {
        // Arrange
        var email = "test@example.com";
        var secret = _totpService.GenerateSecret();
        var uri = _totpService.GenerateQrCodeUri(email, secret);

        // Act
        var qrCodeImage = _totpService.GenerateQrCodeImage(uri);

        // Assert
        // Should be able to convert from base64 without exception
        var bytes = Convert.FromBase64String(qrCodeImage);
        Assert.NotEmpty(bytes);
    }

    [Fact]
    public void GenerateQrCodeImage_WithInvalidUri_ShouldThrowException()
    {
        // Arrange
        var invalidUri = "";

        // Act & Assert
        Assert.Throws<ArgumentException>(() => _totpService.GenerateQrCodeImage(invalidUri));
    }

    #endregion

    #region ValidateCode Tests

    [Fact]
    public void ValidateCode_WithValidCode_ShouldReturnTrue()
    {
        // Arrange
        var secret = _totpService.GenerateSecret();
        var currentCode = _totpService.GetCurrentCode(secret);

        // Act
        var isValid = _totpService.ValidateCode(secret, currentCode);

        // Assert
        Assert.True(isValid);
    }

    [Fact]
    public void ValidateCode_WithInvalidCode_ShouldReturnFalse()
    {
        // Arrange
        var secret = _totpService.GenerateSecret();
        var invalidCode = "000000";

        // Act
        var isValid = _totpService.ValidateCode(secret, invalidCode);

        // Assert
        Assert.False(isValid);
    }

    [Fact]
    public void ValidateCode_WithEmptyCode_ShouldReturnFalse()
    {
        // Arrange
        var secret = _totpService.GenerateSecret();
        var emptyCode = "";

        // Act
        var isValid = _totpService.ValidateCode(secret, emptyCode);

        // Assert
        Assert.False(isValid);
    }

    [Fact]
    public void ValidateCode_WithNullCode_ShouldReturnFalse()
    {
        // Arrange
        var secret = _totpService.GenerateSecret();

        // Act
        var isValid = _totpService.ValidateCode(secret, null!);

        // Assert
        Assert.False(isValid);
    }

    [Fact]
    public void ValidateCode_WithIncorrectLength_ShouldReturnFalse()
    {
        // Arrange
        var secret = _totpService.GenerateSecret();
        var tooShortCode = "12345"; // TOTP codes are 6 digits
        var tooLongCode = "1234567";

        // Act
        var isValidShort = _totpService.ValidateCode(secret, tooShortCode);
        var isValidLong = _totpService.ValidateCode(secret, tooLongCode);

        // Assert
        Assert.False(isValidShort);
        Assert.False(isValidLong);
    }

    [Fact]
    public void ValidateCode_SameSecretDifferentCodes_ShouldHaveOnlyOneValidCode()
    {
        // Arrange
        var secret = _totpService.GenerateSecret();
        var currentCode = _totpService.GetCurrentCode(secret);

        // Generate a different code by using different digits
        var differentCode = currentCode == "123456" ? "654321" : "123456";

        // Act
        var isCurrentValid = _totpService.ValidateCode(secret, currentCode);
        var isDifferentValid = _totpService.ValidateCode(secret, differentCode);

        // Assert
        Assert.True(isCurrentValid);
        Assert.False(isDifferentValid);
    }

    #endregion

    #region GetCurrentCode Tests

    [Fact]
    public void GetCurrentCode_ShouldReturnSixDigitCode()
    {
        // Arrange
        var secret = _totpService.GenerateSecret();

        // Act
        var code = _totpService.GetCurrentCode(secret);

        // Assert
        Assert.NotNull(code);
        Assert.Equal(6, code.Length);
        Assert.Matches(@"^\d{6}$", code);
    }

    [Fact]
    public void GetCurrentCode_ShouldReturnSameCodeWithinTimeWindow()
    {
        // Arrange
        var secret = _totpService.GenerateSecret();

        // Act
        var code1 = _totpService.GetCurrentCode(secret);
        System.Threading.Thread.Sleep(1000); // Wait 1 second
        var code2 = _totpService.GetCurrentCode(secret);

        // Assert
        // Codes should be the same within 30-second window
        Assert.Equal(code1, code2);
    }

    [Fact]
    public void GetCurrentCode_DifferentSecrets_ShouldReturnDifferentCodes()
    {
        // Arrange
        var secret1 = _totpService.GenerateSecret();
        var secret2 = _totpService.GenerateSecret();

        // Act
        var code1 = _totpService.GetCurrentCode(secret1);
        var code2 = _totpService.GetCurrentCode(secret2);

        // Assert
        Assert.NotEqual(code1, code2);
    }

    #endregion

    #region Integration Tests

    [Fact]
    public void EndToEnd_GenerateSecretAndValidateCode_ShouldWork()
    {
        // Arrange
        var secret = _totpService.GenerateSecret();

        // Act
        var code = _totpService.GetCurrentCode(secret);
        var isValid = _totpService.ValidateCode(secret, code);

        // Assert
        Assert.True(isValid);
    }

    [Fact]
    public void EndToEnd_GenerateQrCodeAndValidateCode_ShouldWork()
    {
        // Arrange
        var email = "test@example.com";
        var secret = _totpService.GenerateSecret();
        var qrUri = _totpService.GenerateQrCodeUri(email, secret);
        var qrImage = _totpService.GenerateQrCodeImage(qrUri);

        // Act
        var code = _totpService.GetCurrentCode(secret);
        var isValid = _totpService.ValidateCode(secret, code);

        // Assert
        Assert.NotEmpty(qrUri);
        Assert.NotEmpty(qrImage);
        Assert.True(isValid);
    }

    #endregion

    #region Time Tolerance Tests

    [Fact]
    public void ValidateCode_WithCustomTimeTolerance_ShouldRespectTolerance()
    {
        // Arrange
        var secret = _totpService.GenerateSecret();
        var currentCode = _totpService.GetCurrentCode(secret);

        // Act
        var isValidWithDefaultTolerance = _totpService.ValidateCode(secret, currentCode, 30);
        var isValidWithZeroTolerance = _totpService.ValidateCode(secret, currentCode, 0);

        // Assert
        Assert.True(isValidWithDefaultTolerance);
        Assert.True(isValidWithZeroTolerance); // Should still be valid for current time window
    }

    #endregion

    #region Security Tests

    [Fact]
    public void GenerateSecret_ShouldGenerateHighEntropySecrets()
    {
        // Arrange
        var secrets = new System.Collections.Generic.HashSet<string>();
        var count = 100;

        // Act
        for (int i = 0; i < count; i++)
        {
            secrets.Add(_totpService.GenerateSecret());
        }

        // Assert
        // All secrets should be unique (no collisions)
        Assert.Equal(count, secrets.Count);
    }

    [Fact]
    public void ValidateCode_WithReusedCode_ShouldStillValidateWithinWindow()
    {
        // Arrange
        var secret = _totpService.GenerateSecret();
        var code = _totpService.GetCurrentCode(secret);

        // Act
        var isValid1 = _totpService.ValidateCode(secret, code);
        var isValid2 = _totpService.ValidateCode(secret, code); // Reuse same code

        // Assert
        // Note: This test shows that TOTP codes can be reused within the time window
        // For production, you should implement replay attack prevention (store used codes)
        Assert.True(isValid1);
        Assert.True(isValid2);
    }

    #endregion
}
