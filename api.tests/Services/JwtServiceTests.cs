using Microsoft.Extensions.Configuration;
using SqlMonitor.Api.Services;
using System.Security.Claims;
using Xunit;

namespace SqlMonitor.Api.Tests.Services;

/// <summary>
/// Tests for JwtService - JWT token generation and validation
/// Phase 2.0 Week 2 Day 6-7: Authentication Integration
/// SOC 2 Controls: CC6.1, CC6.2
/// </summary>
public class JwtServiceTests
{
    private readonly IJwtService _jwtService;

    public JwtServiceTests()
    {
        // Setup test configuration
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                { "Jwt:SecretKey", "test-secret-key-must-be-at-least-32-characters-long" },
                { "Jwt:Issuer", "SqlMonitor.Api.Test" },
                { "Jwt:Audience", "SqlMonitor.Client.Test" },
                { "Jwt:ExpirationMinutes", "60" }
            })
            .Build();

        _jwtService = new JwtService(configuration);
    }

    [Fact]
    public void GenerateToken_ShouldReturnValidJwtToken()
    {
        // Arrange
        var userId = 1;
        var userName = "john.doe";
        var email = "john.doe@example.com";

        // Act
        var token = _jwtService.GenerateToken(userId, userName, email);

        // Assert
        Assert.NotNull(token);
        Assert.NotEmpty(token);
        Assert.Contains(".", token); // JWT has 3 parts separated by dots
    }

    [Fact]
    public void GenerateToken_ShouldIncludeUserIdInClaims()
    {
        // Arrange
        var userId = 42;
        var userName = "jane.smith";
        var email = "jane.smith@example.com";

        // Act
        var token = _jwtService.GenerateToken(userId, userName, email);
        var principal = _jwtService.ValidateToken(token);

        // Assert
        Assert.NotNull(principal);
        var extractedUserId = _jwtService.GetUserIdFromToken(principal);
        Assert.Equal(userId, extractedUserId);
    }

    [Fact]
    public void GenerateToken_ShouldIncludeUsernameInClaims()
    {
        // Arrange
        var userId = 1;
        var userName = "test.user";
        var email = "test@example.com";

        // Act
        var token = _jwtService.GenerateToken(userId, userName, email);
        var principal = _jwtService.ValidateToken(token);

        // Assert
        Assert.NotNull(principal);
        var extractedUserName = _jwtService.GetUserNameFromToken(principal);
        Assert.Equal(userName, extractedUserName);
    }

    [Fact]
    public void GenerateToken_ShouldIncludeRolesInClaims()
    {
        // Arrange
        var userId = 1;
        var userName = "admin.user";
        var email = "admin@example.com";
        var roles = new[] { "Admin", "Developer" };

        // Act
        var token = _jwtService.GenerateToken(userId, userName, email, roles);
        var principal = _jwtService.ValidateToken(token);

        // Assert
        Assert.NotNull(principal);
        var roleClaims = principal.FindAll(ClaimTypes.Role).Select(c => c.Value).ToArray();
        Assert.Contains("Admin", roleClaims);
        Assert.Contains("Developer", roleClaims);
    }

    [Fact]
    public void ValidateToken_ShouldReturnPrincipal_WhenTokenIsValid()
    {
        // Arrange
        var userId = 1;
        var userName = "test.user";
        var email = "test@example.com";
        var token = _jwtService.GenerateToken(userId, userName, email);

        // Act
        var principal = _jwtService.ValidateToken(token);

        // Assert
        Assert.NotNull(principal);
        Assert.NotNull(principal.Identity);
        Assert.True(principal.Identity.IsAuthenticated);
    }

    [Fact]
    public void ValidateToken_ShouldReturnNull_WhenTokenIsEmpty()
    {
        // Act
        var principal = _jwtService.ValidateToken("");

        // Assert
        Assert.Null(principal);
    }

    [Fact]
    public void ValidateToken_ShouldReturnNull_WhenTokenIsNull()
    {
        // Act
        var principal = _jwtService.ValidateToken(null);

        // Assert
        Assert.Null(principal);
    }

    [Fact]
    public void ValidateToken_ShouldReturnNull_WhenTokenIsInvalid()
    {
        // Arrange
        var invalidToken = "invalid.token.here";

        // Act
        var principal = _jwtService.ValidateToken(invalidToken);

        // Assert
        Assert.Null(principal);
    }

    [Fact]
    public void ValidateToken_ShouldReturnNull_WhenTokenHasInvalidSignature()
    {
        // Arrange - Create token, then modify it (breaks signature)
        var userId = 1;
        var userName = "test.user";
        var email = "test@example.com";
        var token = _jwtService.GenerateToken(userId, userName, email);
        var tamperedToken = token.Substring(0, token.Length - 5) + "XXXXX";

        // Act
        var principal = _jwtService.ValidateToken(tamperedToken);

        // Assert
        Assert.Null(principal);
    }

    [Fact]
    public void GetUserIdFromToken_ShouldReturnUserId_WhenPresent()
    {
        // Arrange
        var userId = 123;
        var userName = "test.user";
        var email = "test@example.com";
        var token = _jwtService.GenerateToken(userId, userName, email);
        var principal = _jwtService.ValidateToken(token);

        // Act
        var extractedUserId = _jwtService.GetUserIdFromToken(principal!);

        // Assert
        Assert.Equal(userId, extractedUserId);
    }

    [Fact]
    public void GetUserIdFromToken_ShouldReturnNull_WhenNotPresent()
    {
        // Arrange - Create principal without UserId claim
        var claims = new[] { new Claim(ClaimTypes.Name, "test.user") };
        var identity = new ClaimsIdentity(claims, "TestAuthentication");
        var principal = new ClaimsPrincipal(identity);

        // Act
        var extractedUserId = _jwtService.GetUserIdFromToken(principal);

        // Assert
        Assert.Null(extractedUserId);
    }

    [Fact]
    public void GetUserNameFromToken_ShouldReturnUsername_WhenPresent()
    {
        // Arrange
        var userId = 1;
        var userName = "test.user";
        var email = "test@example.com";
        var token = _jwtService.GenerateToken(userId, userName, email);
        var principal = _jwtService.ValidateToken(token);

        // Act
        var extractedUserName = _jwtService.GetUserNameFromToken(principal!);

        // Assert
        Assert.Equal(userName, extractedUserName);
    }

    [Fact]
    public void GetUserNameFromToken_ShouldReturnNull_WhenNotPresent()
    {
        // Arrange - Create principal without Name claim
        var claims = new[] { new Claim(ClaimTypes.Email, "test@example.com") };
        var identity = new ClaimsIdentity(claims, "TestAuthentication");
        var principal = new ClaimsPrincipal(identity);

        // Act
        var extractedUserName = _jwtService.GetUserNameFromToken(principal);

        // Assert
        Assert.Null(extractedUserName);
    }

    [Fact]
    public void GenerateToken_ShouldCreateDifferentTokens_ForDifferentUsers()
    {
        // Arrange
        var user1Token = _jwtService.GenerateToken(1, "user1", "user1@example.com");
        var user2Token = _jwtService.GenerateToken(2, "user2", "user2@example.com");

        // Act & Assert
        Assert.NotEqual(user1Token, user2Token);
    }

    [Fact]
    public void GenerateToken_ShouldCreateDifferentTokens_ForSameUserAtDifferentTimes()
    {
        // Arrange
        var userId = 1;
        var userName = "test.user";
        var email = "test@example.com";

        // Act
        var token1 = _jwtService.GenerateToken(userId, userName, email);
        Thread.Sleep(1000); // Wait 1 second to ensure different timestamp
        var token2 = _jwtService.GenerateToken(userId, userName, email);

        // Assert
        Assert.NotEqual(token1, token2); // Different JTI (JWT ID) claim
    }

    [Fact]
    public void JwtService_ShouldThrowException_WhenSecretKeyIsTooShort()
    {
        // Arrange - Configuration with short secret key
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                { "Jwt:SecretKey", "short-key" }, // Less than 32 characters
                { "Jwt:Issuer", "SqlMonitor.Api.Test" },
                { "Jwt:Audience", "SqlMonitor.Client.Test" },
                { "Jwt:ExpirationMinutes", "60" }
            })
            .Build();

        // Act & Assert
        Assert.Throws<InvalidOperationException>(() => new JwtService(configuration));
    }

    [Fact]
    public void JwtService_ShouldThrowException_WhenSecretKeyIsMissing()
    {
        // Arrange - Configuration without secret key
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                { "Jwt:Issuer", "SqlMonitor.Api.Test" },
                { "Jwt:Audience", "SqlMonitor.Client.Test" },
                { "Jwt:ExpirationMinutes", "60" }
            })
            .Build();

        // Act & Assert
        Assert.Throws<InvalidOperationException>(() => new JwtService(configuration));
    }

    [Fact]
    public void GenerateToken_ShouldIncludeEmailInClaims()
    {
        // Arrange
        var userId = 1;
        var userName = "test.user";
        var email = "test@example.com";

        // Act
        var token = _jwtService.GenerateToken(userId, userName, email);
        var principal = _jwtService.ValidateToken(token);

        // Assert
        Assert.NotNull(principal);
        var emailClaim = principal.FindFirst(ClaimTypes.Email);
        Assert.NotNull(emailClaim);
        Assert.Equal(email, emailClaim.Value);
    }
}
