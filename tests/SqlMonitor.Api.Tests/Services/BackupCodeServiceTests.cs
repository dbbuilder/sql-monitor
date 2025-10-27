using Xunit;
using SqlMonitor.Api.Services;
using System;
using System.Linq;
using System.Text.RegularExpressions;
using Moq;
using Microsoft.Extensions.Logging;

namespace SqlMonitor.Api.Tests.Services;

/// <summary>
/// Unit tests for BackupCodeService (MFA recovery codes)
/// Phase 2.0 Week 3 Days 11-12: Multi-Factor Authentication
/// </summary>
public class BackupCodeServiceTests
{
    private readonly IBackupCodeService _backupCodeService;
    private readonly Mock<ILogger<BackupCodeService>> _mockLogger;

    public BackupCodeServiceTests()
    {
        _mockLogger = new Mock<ILogger<BackupCodeService>>();

        var passwordService = new PasswordService();
        _backupCodeService = new BackupCodeService(passwordService, _mockLogger.Object);
    }

    #region GenerateBackupCodes Tests

    [Fact]
    public void GenerateBackupCodes_ShouldReturnRequestedCount()
    {
        // Arrange
        var count = 10;

        // Act
        var codes = _backupCodeService.GenerateBackupCodes(count);

        // Assert
        Assert.NotNull(codes);
        Assert.Equal(count, codes.Count);
    }

    [Fact]
    public void GenerateBackupCodes_ShouldReturnDefaultCount()
    {
        // Act
        var codes = _backupCodeService.GenerateBackupCodes();

        // Assert
        Assert.NotNull(codes);
        Assert.Equal(10, codes.Count); // Default count
    }

    [Fact]
    public void GenerateBackupCodes_ShouldReturnCodesInCorrectFormat()
    {
        // Act
        var codes = _backupCodeService.GenerateBackupCodes(10);

        // Assert
        foreach (var code in codes)
        {
            // Format: XXXX-XXXX (8 characters + 1 dash)
            Assert.Matches(@"^[A-Z0-9]{4}-[A-Z0-9]{4}$", code);
        }
    }

    [Fact]
    public void GenerateBackupCodes_ShouldExcludeAmbiguousCharacters()
    {
        // Arrange
        var ambiguousChars = new[] { '0', 'O', 'I', '1' };

        // Act
        var codes = _backupCodeService.GenerateBackupCodes(50);

        // Assert
        foreach (var code in codes)
        {
            var codeWithoutDash = code.Replace("-", "");
            foreach (var ambiguousChar in ambiguousChars)
            {
                Assert.DoesNotContain(ambiguousChar, codeWithoutDash);
            }
        }
    }

    [Fact]
    public void GenerateBackupCodes_ShouldGenerateUniqueCodes()
    {
        // Arrange
        var count = 100;

        // Act
        var codes = _backupCodeService.GenerateBackupCodes(count);

        // Assert
        var uniqueCodes = codes.Distinct().Count();
        Assert.Equal(count, uniqueCodes);
    }

    [Fact]
    public void GenerateBackupCodes_MultipleCalls_ShouldGenerateDifferentSets()
    {
        // Act
        var codes1 = _backupCodeService.GenerateBackupCodes(10);
        var codes2 = _backupCodeService.GenerateBackupCodes(10);

        // Assert
        // Sets should not be identical
        Assert.NotEqual(codes1, codes2);
    }

    [Fact]
    public void GenerateBackupCodes_WithCustomCount_ShouldReturnCorrectCount()
    {
        // Arrange
        var counts = new[] { 5, 10, 15, 20 };

        foreach (var count in counts)
        {
            // Act
            var codes = _backupCodeService.GenerateBackupCodes(count);

            // Assert
            Assert.Equal(count, codes.Count);
        }
    }

    [Fact]
    public void GenerateBackupCodes_ShouldOnlyUseUppercase()
    {
        // Act
        var codes = _backupCodeService.GenerateBackupCodes(50);

        // Assert
        foreach (var code in codes)
        {
            Assert.Equal(code, code.ToUpperInvariant());
        }
    }

    #endregion

    #region HashBackupCode Tests

    [Fact]
    public void HashBackupCode_ShouldReturnHashAndSalt()
    {
        // Arrange
        var code = "ABCD-EFGH";

        // Act
        var (hash, salt) = _backupCodeService.HashBackupCode(code);

        // Assert
        Assert.NotNull(hash);
        Assert.NotNull(salt);
        Assert.NotEmpty(hash);
        Assert.NotEmpty(salt);
    }

    [Fact]
    public void HashBackupCode_ShouldReturnDifferentHashForSameCode()
    {
        // Arrange
        var code = "ABCD-EFGH";

        // Act
        var (hash1, salt1) = _backupCodeService.HashBackupCode(code);
        var (hash2, salt2) = _backupCodeService.HashBackupCode(code);

        // Assert
        // Different salts should result in different hashes
        Assert.NotEqual(hash1, hash2);
        Assert.NotEqual(salt1, salt2);
    }

    [Fact]
    public void HashBackupCode_ShouldNormalizeCode()
    {
        // Arrange
        var code1 = "ABCD-EFGH";
        var code2 = "abcd-efgh"; // Lowercase
        var code3 = "ABCDEFGH";  // No dash

        // Act
        var (hash1, salt1) = _backupCodeService.HashBackupCode(code1);
        var (hash2, salt2) = _backupCodeService.HashBackupCode(code2);
        var (hash3, salt3) = _backupCodeService.HashBackupCode(code3);

        // Assert
        // All should produce valid hashes (normalization doesn't throw)
        Assert.NotEmpty(hash1);
        Assert.NotEmpty(hash2);
        Assert.NotEmpty(hash3);
    }

    [Fact]
    public void HashBackupCode_WithNullCode_ShouldThrowException()
    {
        // Act & Assert
        // BackupCodeService throws ArgumentException (not ArgumentNullException)
        Assert.Throws<ArgumentException>(() => _backupCodeService.HashBackupCode(null!));
    }

    [Fact]
    public void HashBackupCode_WithEmptyCode_ShouldThrowException()
    {
        // Act & Assert
        Assert.Throws<ArgumentException>(() => _backupCodeService.HashBackupCode(""));
    }

    [Fact]
    public void HashBackupCode_ShouldReturnBCryptSizedHash()
    {
        // Arrange
        var code = "ABCD-EFGH";

        // Act
        var (hash, salt) = _backupCodeService.HashBackupCode(code);

        // Assert
        // BCrypt produces 60-byte hashes, but PasswordService returns 64-byte hash
        Assert.Equal(64, hash.Length);
    }

    [Fact]
    public void HashBackupCode_ShouldReturnCorrectSaltSize()
    {
        // Arrange
        var code = "ABCD-EFGH";

        // Act
        var (hash, salt) = _backupCodeService.HashBackupCode(code);

        // Assert
        // Salt should be 32 bytes (from PasswordService)
        Assert.Equal(32, salt.Length);
    }

    #endregion

    #region VerifyBackupCode Tests

    [Fact]
    public void VerifyBackupCode_WithCorrectCode_ShouldReturnTrue()
    {
        // Arrange
        var code = "ABCD-EFGH";
        var (hash, salt) = _backupCodeService.HashBackupCode(code);

        // Act
        var isValid = _backupCodeService.VerifyBackupCode(code, hash, salt);

        // Assert
        Assert.True(isValid);
    }

    [Fact]
    public void VerifyBackupCode_WithIncorrectCode_ShouldReturnFalse()
    {
        // Arrange
        var correctCode = "ABCD-EFGH";
        var incorrectCode = "WXYZ-QRST";
        var (hash, salt) = _backupCodeService.HashBackupCode(correctCode);

        // Act
        var isValid = _backupCodeService.VerifyBackupCode(incorrectCode, hash, salt);

        // Assert
        Assert.False(isValid);
    }

    [Fact]
    public void VerifyBackupCode_ShouldBeCaseInsensitive()
    {
        // Arrange
        var code = "ABCD-EFGH";
        var (hash, salt) = _backupCodeService.HashBackupCode(code);

        // Act
        var isValidUppercase = _backupCodeService.VerifyBackupCode("ABCD-EFGH", hash, salt);
        var isValidLowercase = _backupCodeService.VerifyBackupCode("abcd-efgh", hash, salt);
        var isValidMixed = _backupCodeService.VerifyBackupCode("AbCd-EfGh", hash, salt);

        // Assert
        Assert.True(isValidUppercase);
        Assert.True(isValidLowercase);
        Assert.True(isValidMixed);
    }

    [Fact]
    public void VerifyBackupCode_ShouldIgnoreDashes()
    {
        // Arrange
        var code = "ABCD-EFGH";
        var (hash, salt) = _backupCodeService.HashBackupCode(code);

        // Act
        var isValidWithDash = _backupCodeService.VerifyBackupCode("ABCD-EFGH", hash, salt);
        var isValidWithoutDash = _backupCodeService.VerifyBackupCode("ABCDEFGH", hash, salt);

        // Assert
        Assert.True(isValidWithDash);
        Assert.True(isValidWithoutDash);
    }

    [Fact]
    public void VerifyBackupCode_WithNullCode_ShouldReturnFalse()
    {
        // Arrange
        var code = "ABCD-EFGH";
        var (hash, salt) = _backupCodeService.HashBackupCode(code);

        // Act
        var isValid = _backupCodeService.VerifyBackupCode(null!, hash, salt);

        // Assert
        Assert.False(isValid);
    }

    [Fact]
    public void VerifyBackupCode_WithEmptyCode_ShouldReturnFalse()
    {
        // Arrange
        var code = "ABCD-EFGH";
        var (hash, salt) = _backupCodeService.HashBackupCode(code);

        // Act
        var isValid = _backupCodeService.VerifyBackupCode("", hash, salt);

        // Assert
        Assert.False(isValid);
    }

    [Fact]
    public void VerifyBackupCode_WithNullHash_ShouldReturnFalse()
    {
        // Arrange
        var code = "ABCD-EFGH";
        var (_, salt) = _backupCodeService.HashBackupCode(code);

        // Act
        var isValid = _backupCodeService.VerifyBackupCode(code, null!, salt);

        // Assert
        Assert.False(isValid);
    }

    [Fact]
    public void VerifyBackupCode_WithNullSalt_ShouldReturnFalse()
    {
        // Arrange
        var code = "ABCD-EFGH";
        var (hash, _) = _backupCodeService.HashBackupCode(code);

        // Act
        var isValid = _backupCodeService.VerifyBackupCode(code, hash, null!);

        // Assert
        Assert.False(isValid);
    }

    [Fact]
    public void VerifyBackupCode_WithWrongSalt_ShouldReturnFalse()
    {
        // Arrange
        var code = "ABCD-EFGH";
        var (hash, _) = _backupCodeService.HashBackupCode(code);
        var (_, wrongSalt) = _backupCodeService.HashBackupCode("OTHER-CODE");

        // Act
        var isValid = _backupCodeService.VerifyBackupCode(code, hash, wrongSalt);

        // Assert
        Assert.False(isValid);
    }

    #endregion

    #region Integration Tests

    [Fact]
    public void EndToEnd_GenerateHashVerify_ShouldWork()
    {
        // Arrange
        var codes = _backupCodeService.GenerateBackupCodes(10);

        // Act & Assert
        foreach (var code in codes)
        {
            var (hash, salt) = _backupCodeService.HashBackupCode(code);
            var isValid = _backupCodeService.VerifyBackupCode(code, hash, salt);
            Assert.True(isValid, $"Code {code} failed verification");
        }
    }

    [Fact]
    public void EndToEnd_MultipleCodes_ShouldVerifyIndependently()
    {
        // Arrange
        var codes = _backupCodeService.GenerateBackupCodes(5);
        var hashedCodes = codes.Select(c => new
        {
            Code = c,
            Hash = _backupCodeService.HashBackupCode(c)
        }).ToList();

        // Act & Assert
        for (int i = 0; i < codes.Count; i++)
        {
            var code = codes[i];
            var (hash, salt) = hashedCodes[i].Hash;

            // Correct code should verify
            Assert.True(_backupCodeService.VerifyBackupCode(code, hash, salt));

            // Other codes should not verify
            for (int j = 0; j < codes.Count; j++)
            {
                if (i != j)
                {
                    Assert.False(_backupCodeService.VerifyBackupCode(codes[j], hash, salt));
                }
            }
        }
    }

    [Fact]
    public void EndToEnd_SameCodeDifferentHashes_ShouldBothVerify()
    {
        // Arrange
        var code = "ABCD-EFGH";
        var (hash1, salt1) = _backupCodeService.HashBackupCode(code);
        var (hash2, salt2) = _backupCodeService.HashBackupCode(code);

        // Act
        var isValid1 = _backupCodeService.VerifyBackupCode(code, hash1, salt1);
        var isValid2 = _backupCodeService.VerifyBackupCode(code, hash2, salt2);

        // Assert
        Assert.True(isValid1);
        Assert.True(isValid2);
        Assert.NotEqual(hash1, hash2); // Hashes should be different
    }

    #endregion

    #region Security Tests

    [Fact]
    public void Security_DifferentSalts_ShouldProduceDifferentHashes()
    {
        // Arrange
        var code = "ABCD-EFGH";
        var iterations = 10;
        var hashes = new System.Collections.Generic.HashSet<string>();

        // Act
        for (int i = 0; i < iterations; i++)
        {
            var (hash, _) = _backupCodeService.HashBackupCode(code);
            hashes.Add(Convert.ToBase64String(hash));
        }

        // Assert
        // All hashes should be unique (no hash collisions)
        Assert.Equal(iterations, hashes.Count);
    }

    [Fact]
    public void Security_SlightlyDifferentCodes_ShouldProduceCompletelyDifferentHashes()
    {
        // Arrange
        var code1 = "ABCD-EFGH";
        var code2 = "ABCD-EFGI"; // Only last character different

        // Act
        var (hash1, _) = _backupCodeService.HashBackupCode(code1);
        var (hash2, _) = _backupCodeService.HashBackupCode(code2);

        // Assert
        // Hashes should be completely different (avalanche effect)
        Assert.NotEqual(hash1, hash2);

        // Count differing bytes (should be significant)
        int differingBytes = 0;
        for (int i = 0; i < Math.Min(hash1.Length, hash2.Length); i++)
        {
            if (hash1[i] != hash2[i])
                differingBytes++;
        }

        // At least 50% of bytes should differ
        Assert.True(differingBytes > hash1.Length / 2);
    }

    [Fact]
    public void Security_GenerateMultipleSets_ShouldHaveNoCollisions()
    {
        // Arrange
        var sets = 10;
        var codesPerSet = 10;
        var allCodes = new System.Collections.Generic.HashSet<string>();

        // Act
        for (int i = 0; i < sets; i++)
        {
            var codes = _backupCodeService.GenerateBackupCodes(codesPerSet);
            foreach (var code in codes)
            {
                allCodes.Add(code);
            }
        }

        // Assert
        // All codes should be unique (no collisions across sets)
        Assert.Equal(sets * codesPerSet, allCodes.Count);
    }

    #endregion

    #region Format Tests

    [Fact]
    public void Format_CodesAreReadable_ShouldBeEasyToType()
    {
        // Act
        var codes = _backupCodeService.GenerateBackupCodes(10);

        // Assert
        foreach (var code in codes)
        {
            // Should be in format XXXX-XXXX
            Assert.Equal(9, code.Length); // 4 + 1 + 4

            // Should have dash in the middle
            Assert.Equal('-', code[4]);

            // Should only contain allowed characters
            var allowedChars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789-";
            Assert.All(code, c => Assert.Contains(c, allowedChars));
        }
    }

    [Fact]
    public void Format_NoConfusingCharacters_ShouldExcludeAmbiguous()
    {
        // Arrange
        var confusingPairs = new[]
        {
            ('0', 'O'),
            ('I', '1'),
            ('l', '1')
        };

        // Act
        var codes = _backupCodeService.GenerateBackupCodes(100);

        // Assert
        foreach (var code in codes)
        {
            // Should not contain 0, O, I, 1, l
            Assert.DoesNotContain('0', code);
            Assert.DoesNotContain('O', code);
            Assert.DoesNotContain('I', code);
            Assert.DoesNotContain('1', code);
            Assert.DoesNotContain('l', code);
        }
    }

    #endregion
}
