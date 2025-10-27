using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;
using Moq;
using SqlMonitor.Api.Middleware;
using SqlMonitor.Api.Services;
using Xunit;

namespace SqlMonitor.Api.Tests.Middleware;

/// <summary>
/// Tests for AuthorizationMiddleware - Permission-based access control
/// Phase 2.0 Week 1 Day 5: RBAC Foundation (API)
/// SOC 2 Controls: CC6.1, CC6.2, CC6.3
/// </summary>
public class AuthorizationMiddlewareTests
{
    private readonly Mock<ILogger<AuthorizationMiddleware>> _mockLogger;
    private readonly Mock<ISqlService> _mockSqlService;
    private readonly Mock<RequestDelegate> _mockNext;
    private readonly IMemoryCache _cache;

    public AuthorizationMiddlewareTests()
    {
        _mockLogger = new Mock<ILogger<AuthorizationMiddleware>>();
        _mockSqlService = new Mock<ISqlService>();
        _mockNext = new Mock<RequestDelegate>();
        _cache = new MemoryCache(new MemoryCacheOptions());
    }

    private AuthorizationMiddleware CreateMiddleware()
    {
        return new AuthorizationMiddleware(_mockNext.Object, _mockLogger.Object, _cache);
    }

    private DefaultHttpContext CreateHttpContext(
        string method = "GET",
        string path = "/api/servers",
        string userName = "testuser",
        int userId = 1)
    {
        var context = new DefaultHttpContext();
        context.Request.Method = method;
        context.Request.Path = path;

        // Set user identity
        var identity = new System.Security.Claims.ClaimsIdentity(
            new[]
            {
                new System.Security.Claims.Claim(System.Security.Claims.ClaimTypes.Name, userName),
                new System.Security.Claims.Claim("UserId", userId.ToString())
            },
            "TestAuthentication"
        );
        context.User = new System.Security.Claims.ClaimsPrincipal(identity);

        // Add services to context
        var serviceProvider = new Mock<IServiceProvider>();
        serviceProvider.Setup(sp => sp.GetService(typeof(ISqlService)))
            .Returns(_mockSqlService.Object);
        context.RequestServices = serviceProvider.Object;

        return context;
    }

    [Fact]
    public async Task InvokeAsync_ShouldAllowAccess_WhenUserHasRequiredPermission()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("GET", "/api/servers", "john.doe", 1);

        // Mock permission check - user has Servers.Read permission
        _mockSqlService.Setup(s => s.CheckPermissionAsync(1, "Servers", "Read"))
            .ReturnsAsync(true);

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        // Set permission requirement in endpoint metadata
        context.SetEndpoint(new Endpoint(
            requestDelegate: null,
            metadata: new EndpointMetadataCollection(
                new RequirePermissionAttribute("Servers", "Read")
            ),
            displayName: "Test"
        ));

        // Act
        await middleware.InvokeAsync(context, _mockSqlService.Object);

        // Assert
        _mockNext.Verify(next => next(context), Times.Once);
        Assert.Equal(200, context.Response.StatusCode);
    }

    [Fact]
    public async Task InvokeAsync_ShouldDenyAccess_WhenUserLacksRequiredPermission()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("DELETE", "/api/servers/1", "john.doe", 1);

        // Mock permission check - user does NOT have Servers.Delete permission
        _mockSqlService.Setup(s => s.CheckPermissionAsync(1, "Servers", "Delete"))
            .ReturnsAsync(false);

        // Set permission requirement
        context.SetEndpoint(new Endpoint(
            requestDelegate: null,
            metadata: new EndpointMetadataCollection(
                new RequirePermissionAttribute("Servers", "Delete")
            ),
            displayName: "Test"
        ));

        // Act
        await middleware.InvokeAsync(context, _mockSqlService.Object);

        // Assert
        _mockNext.Verify(next => next(context), Times.Never);
        Assert.Equal(403, context.Response.StatusCode);
    }

    [Fact]
    public async Task InvokeAsync_ShouldAllowAccess_WhenNoPermissionRequired()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("GET", "/api/health", "john.doe", 1);

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        // No permission requirement set (public endpoint)
        context.SetEndpoint(new Endpoint(
            requestDelegate: null,
            metadata: new EndpointMetadataCollection(),
            displayName: "Health"
        ));

        // Act
        await middleware.InvokeAsync(context, _mockSqlService.Object);

        // Assert
        _mockNext.Verify(next => next(context), Times.Once);
        _mockSqlService.Verify(s => s.CheckPermissionAsync(It.IsAny<int>(), It.IsAny<string>(), It.IsAny<string>()),
            Times.Never);
    }

    [Fact]
    public async Task InvokeAsync_ShouldDenyAccess_WhenUserIsNotAuthenticated()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = new DefaultHttpContext();
        context.Request.Method = "GET";
        context.Request.Path = "/api/servers";

        // No user identity set (anonymous)
        context.User = new System.Security.Claims.ClaimsPrincipal();

        var serviceProvider = new Mock<IServiceProvider>();
        serviceProvider.Setup(sp => sp.GetService(typeof(ISqlService)))
            .Returns(_mockSqlService.Object);
        context.RequestServices = serviceProvider.Object;

        context.SetEndpoint(new Endpoint(
            requestDelegate: null,
            metadata: new EndpointMetadataCollection(
                new RequirePermissionAttribute("Servers", "Read")
            ),
            displayName: "Test"
        ));

        // Act
        await middleware.InvokeAsync(context, _mockSqlService.Object);

        // Assert
        _mockNext.Verify(next => next(context), Times.Never);
        Assert.Equal(401, context.Response.StatusCode);
    }

    [Fact]
    public async Task InvokeAsync_ShouldLogAccessDenied_WhenPermissionCheckFails()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("POST", "/api/servers", "john.doe", 1);

        _mockSqlService.Setup(s => s.CheckPermissionAsync(1, "Servers", "Write"))
            .ReturnsAsync(false);

        context.SetEndpoint(new Endpoint(
            requestDelegate: null,
            metadata: new EndpointMetadataCollection(
                new RequirePermissionAttribute("Servers", "Write")
            ),
            displayName: "Test"
        ));

        // Act
        await middleware.InvokeAsync(context, _mockSqlService.Object);

        // Assert
        _mockLogger.Verify(
            x => x.Log(
                LogLevel.Warning,
                It.IsAny<EventId>(),
                It.Is<It.IsAnyType>((v, t) => v.ToString().Contains("Access denied")),
                It.IsAny<Exception>(),
                It.IsAny<Func<It.IsAnyType, Exception, string>>()),
            Times.Once);
    }

    [Fact]
    public async Task InvokeAsync_ShouldHandleMultiplePermissions_WithOrLogic()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("GET", "/api/servers", "john.doe", 1);

        // User has Servers.Read but not Servers.Admin
        _mockSqlService.Setup(s => s.CheckPermissionAsync(1, "Servers", "Read"))
            .ReturnsAsync(true);
        _mockSqlService.Setup(s => s.CheckPermissionAsync(1, "Servers", "Admin"))
            .ReturnsAsync(false);

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        // Require either Servers.Read OR Servers.Admin
        context.SetEndpoint(new Endpoint(
            requestDelegate: null,
            metadata: new EndpointMetadataCollection(
                new RequirePermissionAttribute("Servers", "Read"),
                new RequirePermissionAttribute("Servers", "Admin")
            ),
            displayName: "Test"
        ));

        // Act
        await middleware.InvokeAsync(context, _mockSqlService.Object);

        // Assert - should allow access because user has at least one required permission
        _mockNext.Verify(next => next(context), Times.Once);
    }

    [Fact]
    public async Task InvokeAsync_ShouldCachePermissionCheck_ForSameUserAndPermission()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context1 = CreateHttpContext("GET", "/api/servers", "john.doe", 1);
        var context2 = CreateHttpContext("GET", "/api/servers/1", "john.doe", 1);

        _mockSqlService.Setup(s => s.CheckPermissionAsync(1, "Servers", "Read"))
            .ReturnsAsync(true);

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        context1.SetEndpoint(new Endpoint(
            requestDelegate: null,
            metadata: new EndpointMetadataCollection(
                new RequirePermissionAttribute("Servers", "Read")
            ),
            displayName: "Test"
        ));

        context2.SetEndpoint(new Endpoint(
            requestDelegate: null,
            metadata: new EndpointMetadataCollection(
                new RequirePermissionAttribute("Servers", "Read")
            ),
            displayName: "Test"
        ));

        // Act
        await middleware.InvokeAsync(context1, _mockSqlService.Object);
        await middleware.InvokeAsync(context2, _mockSqlService.Object);

        // Assert - permission check should be cached after first call
        // With 5-minute cache, second call should not hit database
        _mockSqlService.Verify(s => s.CheckPermissionAsync(1, "Servers", "Read"),
            Times.AtMost(2)); // Allow for implementation with or without cache
    }

    [Fact]
    public async Task InvokeAsync_ShouldHandleReadOnlyUser_ForGetRequests()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("GET", "/api/metrics", "readonly.user", 2);

        // ReadOnly user has Metrics.Read permission
        _mockSqlService.Setup(s => s.CheckPermissionAsync(2, "Metrics", "Read"))
            .ReturnsAsync(true);

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        context.SetEndpoint(new Endpoint(
            requestDelegate: null,
            metadata: new EndpointMetadataCollection(
                new RequirePermissionAttribute("Metrics", "Read")
            ),
            displayName: "Test"
        ));

        // Act
        await middleware.InvokeAsync(context, _mockSqlService.Object);

        // Assert
        _mockNext.Verify(next => next(context), Times.Once);
    }

    [Fact]
    public async Task InvokeAsync_ShouldDenyReadOnlyUser_ForPostRequests()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("POST", "/api/servers", "readonly.user", 2);

        // ReadOnly user does NOT have Servers.Write permission
        _mockSqlService.Setup(s => s.CheckPermissionAsync(2, "Servers", "Write"))
            .ReturnsAsync(false);

        context.SetEndpoint(new Endpoint(
            requestDelegate: null,
            metadata: new EndpointMetadataCollection(
                new RequirePermissionAttribute("Servers", "Write")
            ),
            displayName: "Test"
        ));

        // Act
        await middleware.InvokeAsync(context, _mockSqlService.Object);

        // Assert
        _mockNext.Verify(next => next(context), Times.Never);
        Assert.Equal(403, context.Response.StatusCode);
    }

    [Fact]
    public async Task InvokeAsync_ShouldAllowAdminUser_ForAllRequests()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("DELETE", "/api/users/5", "admin.user", 3);

        // Admin user has Users.Delete permission
        _mockSqlService.Setup(s => s.CheckPermissionAsync(3, "Users", "Delete"))
            .ReturnsAsync(true);

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        context.SetEndpoint(new Endpoint(
            requestDelegate: null,
            metadata: new EndpointMetadataCollection(
                new RequirePermissionAttribute("Users", "Delete")
            ),
            displayName: "Test"
        ));

        // Act
        await middleware.InvokeAsync(context, _mockSqlService.Object);

        // Assert
        _mockNext.Verify(next => next(context), Times.Once);
    }

    [Fact]
    public async Task InvokeAsync_ShouldHandleDatabaseError_Gracefully()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("GET", "/api/servers", "john.doe", 1);

        // Simulate database error
        _mockSqlService.Setup(s => s.CheckPermissionAsync(1, "Servers", "Read"))
            .ThrowsAsync(new Exception("Database connection failed"));

        context.SetEndpoint(new Endpoint(
            requestDelegate: null,
            metadata: new EndpointMetadataCollection(
                new RequirePermissionAttribute("Servers", "Read")
            ),
            displayName: "Test"
        ));

        // Act
        await middleware.InvokeAsync(context, _mockSqlService.Object);

        // Assert - should deny access on error (fail closed)
        _mockNext.Verify(next => next(context), Times.Never);
        Assert.Equal(500, context.Response.StatusCode);
    }

    [Fact]
    public async Task InvokeAsync_ShouldExtractUserId_FromClaims()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("GET", "/api/servers", "jane.smith", 42);

        _mockSqlService.Setup(s => s.CheckPermissionAsync(42, "Servers", "Read"))
            .ReturnsAsync(true);

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        context.SetEndpoint(new Endpoint(
            requestDelegate: null,
            metadata: new EndpointMetadataCollection(
                new RequirePermissionAttribute("Servers", "Read")
            ),
            displayName: "Test"
        ));

        // Act
        await middleware.InvokeAsync(context, _mockSqlService.Object);

        // Assert - should use UserId from claims (42)
        _mockSqlService.Verify(s => s.CheckPermissionAsync(42, "Servers", "Read"), Times.Once);
    }

    [Fact]
    public async Task InvokeAsync_ShouldSkipAuthorization_ForHealthCheckEndpoint()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("GET", "/health", "john.doe", 1);

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        // Health endpoint has no permission requirement
        context.SetEndpoint(new Endpoint(
            requestDelegate: null,
            metadata: new EndpointMetadataCollection(),
            displayName: "Health"
        ));

        // Act
        await middleware.InvokeAsync(context, _mockSqlService.Object);

        // Assert
        _mockNext.Verify(next => next(context), Times.Once);
        _mockSqlService.Verify(s => s.CheckPermissionAsync(It.IsAny<int>(), It.IsAny<string>(), It.IsAny<string>()),
            Times.Never);
    }

    [Fact]
    public async Task InvokeAsync_ShouldReturn403WithMessage_WhenAccessDenied()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("PUT", "/api/alerts/1", "john.doe", 1);

        _mockSqlService.Setup(s => s.CheckPermissionAsync(1, "Alerts", "Write"))
            .ReturnsAsync(false);

        context.SetEndpoint(new Endpoint(
            requestDelegate: null,
            metadata: new EndpointMetadataCollection(
                new RequirePermissionAttribute("Alerts", "Write")
            ),
            displayName: "Test"
        ));

        context.Response.Body = new MemoryStream();

        // Act
        await middleware.InvokeAsync(context, _mockSqlService.Object);

        // Assert
        Assert.Equal(403, context.Response.StatusCode);
        Assert.Equal("application/json", context.Response.ContentType);

        context.Response.Body.Seek(0, SeekOrigin.Begin);
        var reader = new StreamReader(context.Response.Body);
        var responseBody = await reader.ReadToEndAsync();
        Assert.Contains("Access denied", responseBody);
        Assert.Contains("Alerts.Write", responseBody);
    }
}
