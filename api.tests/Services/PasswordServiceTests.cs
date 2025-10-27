using SqlMonitor.Api.Services;
using Xunit;

namespace SqlMonitor.Api.Tests.Services;

/// <summary>
/// Tests for PasswordService - BCrypt password hashing and verification
/// Phase 2.0 Week 2 Day 6: Authentication Integration
/// SOC 2 Controls: CC6.1, CC6.2
/// </summary>
public class PasswordServiceTests
{
    private readonly PasswordService _passwordService;

    public PasswordServiceTests()
    {
        _passwordService = new PasswordService();
    }

    [Fact]
    public void HashPassword_ShouldReturnHashAndSalt_WithCorrectLengths()
    {
        // Arrange
        var password = "MySecurePassword123!";

        // Act
        var (hash, salt) = _passwordService.HashPassword(password);

        // Assert
        Assert.NotNull(hash);
        Assert.NotNull(salt);
        Assert.Equal(64, hash.Length); // Database schema expects 64 bytes
        Assert.Equal(32, salt.Length); // Database schema expects 32 bytes
    }

    [Fact]
    public void HashPassword_ShouldGenerateDifferentSalts_ForSamePassword()
    {
        // Arrange
        var password = "SamePassword123!";

        // Act
        var (hash1, salt1) = _passwordService.HashPassword(password);
        var (hash2, salt2) = _passwordService.HashPassword(password);

        // Assert
        Assert.NotEqual(salt1, salt2); // Salts should be different
        Assert.NotEqual(hash1, hash2); // Hashes should be different due to different salts
    }

    [Fact]
    public void VerifyPassword_ShouldReturnTrue_WhenPasswordMatches()
    {
        // Arrange
        var password = "CorrectPassword123!";
        var (hash, salt) = _passwordService.HashPassword(password);

        // Act
        var result = _passwordService.VerifyPassword(password, hash, salt);

        // Assert
        Assert.True(result);
    }

    [Fact]
    public void VerifyPassword_ShouldReturnFalse_WhenPasswordDoesNotMatch()
    {
        // Arrange
        var correctPassword = "CorrectPassword123!";
        var wrongPassword = "WrongPassword456!";
        var (hash, salt) = _passwordService.HashPassword(correctPassword);

        // Act
        var result = _passwordService.VerifyPassword(wrongPassword, hash, salt);

        // Assert
        Assert.False(result);
    }

    [Fact]
    public void VerifyPassword_ShouldReturnFalse_WhenPasswordIsEmpty()
    {
        // Arrange
        var password = "ValidPassword123!";
        var (hash, salt) = _passwordService.HashPassword(password);

        // Act
        var result = _passwordService.VerifyPassword("", hash, salt);

        // Assert
        Assert.False(result);
    }

    [Fact]
    public void VerifyPassword_ShouldReturnFalse_WhenPasswordIsNull()
    {
        // Arrange
        var password = "ValidPassword123!";
        var (hash, salt) = _passwordService.HashPassword(password);

        // Act
        var result = _passwordService.VerifyPassword(null, hash, salt);

        // Assert
        Assert.False(result);
    }

    [Fact]
    public void HashPassword_ShouldThrowArgumentException_WhenPasswordIsEmpty()
    {
        // Arrange
        var emptyPassword = "";

        // Act & Assert
        Assert.Throws<ArgumentException>(() => _passwordService.HashPassword(emptyPassword));
    }

    [Fact]
    public void HashPassword_ShouldThrowArgumentException_WhenPasswordIsNull()
    {
        // Arrange
        string nullPassword = null;

        // Act & Assert
        Assert.Throws<ArgumentException>(() => _passwordService.HashPassword(nullPassword));
    }

    [Fact]
    public void VerifyPassword_ShouldThrowArgumentException_WhenHashIsWrongLength()
    {
        // Arrange
        var password = "ValidPassword123!";
        var (_, salt) = _passwordService.HashPassword(password);
        var wrongLengthHash = new byte[32]; // Wrong length (should be 64)

        // Act & Assert
        Assert.Throws<ArgumentException>(() => _passwordService.VerifyPassword(password, wrongLengthHash, salt));
    }

    [Fact]
    public void VerifyPassword_ShouldThrowArgumentException_WhenSaltIsWrongLength()
    {
        // Arrange
        var password = "ValidPassword123!";
        var (hash, _) = _passwordService.HashPassword(password);
        var wrongLengthSalt = new byte[16]; // Wrong length (should be 32)

        // Act & Assert
        Assert.Throws<ArgumentException>(() => _passwordService.VerifyPassword(password, hash, wrongLengthSalt));
    }

    [Fact]
    public void GenerateSalt_ShouldReturn32Bytes()
    {
        // Act
        var salt = _passwordService.GenerateSalt();

        // Assert
        Assert.NotNull(salt);
        Assert.Equal(32, salt.Length);
    }

    [Fact]
    public void GenerateSalt_ShouldGenerateDifferentSalts()
    {
        // Act
        var salt1 = _passwordService.GenerateSalt();
        var salt2 = _passwordService.GenerateSalt();

        // Assert
        Assert.NotEqual(salt1, salt2);
    }

    [Theory]
    [InlineData("SimplePassword")]
    [InlineData("Complex!Password123@#$")]
    [InlineData("VeryLongPasswordWithManyCharactersAndSpecialSymbols!@#$%^&*()_+{}[]|:;<>?,./")]
    [InlineData("短密码")] // Unicode password
    public void HashPassword_ShouldHandleDifferentPasswordComplexities(string password)
    {
        // Act
        var (hash, salt) = _passwordService.HashPassword(password);
        var verified = _passwordService.VerifyPassword(password, hash, salt);

        // Assert
        Assert.NotNull(hash);
        Assert.NotNull(salt);
        Assert.True(verified);
    }

    [Fact]
    public void VerifyPassword_ShouldBeCaseSensitive()
    {
        // Arrange
        var password = "CaseSensitivePassword";
        var (hash, salt) = _passwordService.HashPassword(password);

        // Act
        var resultLowercase = _passwordService.VerifyPassword("casesensitivepassword", hash, salt);
        var resultUppercase = _passwordService.VerifyPassword("CASESENSITIVEPASSWORD", hash, salt);
        var resultCorrect = _passwordService.VerifyPassword(password, hash, salt);

        // Assert
        Assert.False(resultLowercase);
        Assert.False(resultUppercase);
        Assert.True(resultCorrect);
    }

    [Fact]
    public void HashPassword_ShouldHandleWhitespacePasswords()
    {
        // Arrange
        var password = "  password with spaces  ";

        // Act
        var (hash, salt) = _passwordService.HashPassword(password);
        var verified = _passwordService.VerifyPassword(password, hash, salt);

        // Assert
        Assert.True(verified);
    }

    [Fact]
    public void VerifyPassword_ShouldNotMatch_WhenSaltIsDifferent()
    {
        // Arrange
        var password = "TestPassword123!";
        var (hash, _) = _passwordService.HashPassword(password);
        var differentSalt = _passwordService.GenerateSalt();

        // Act
        var result = _passwordService.VerifyPassword(password, hash, differentSalt);

        // Assert
        Assert.False(result);
    }
}
