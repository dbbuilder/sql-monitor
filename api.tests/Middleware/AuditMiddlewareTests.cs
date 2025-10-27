using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Moq;
using SqlMonitor.Api.Middleware;
using SqlMonitor.Api.Services;
using System.IO;
using System.Security.Claims;
using System.Text;
using Xunit;

namespace SqlMonitor.Api.Tests.Middleware;

/// <summary>
/// Unit tests for AuditMiddleware (Phase 2.0 Feature 1 - SOC 2 CC6.1, CC7.2)
/// TDD: RED Phase - Tests written before implementation
/// </summary>
public class AuditMiddlewareTests
{
    private readonly Mock<ILogger<AuditMiddleware>> _mockLogger;
    private readonly Mock<ISqlService> _mockSqlService;
    private readonly Mock<RequestDelegate> _mockNext;

    public AuditMiddlewareTests()
    {
        _mockLogger = new Mock<ILogger<AuditMiddleware>>();
        _mockSqlService = new Mock<ISqlService>();
        _mockNext = new Mock<RequestDelegate>();
    }

    private AuditMiddleware CreateMiddleware()
    {
        return new AuditMiddleware(
            _mockNext.Object,
            _mockLogger.Object,
            _mockSqlService.Object
        );
    }

    private DefaultHttpContext CreateHttpContext(
        string method = "GET",
        string path = "/api/servers",
        string? username = null,
        string? ipAddress = null)
    {
        var context = new DefaultHttpContext();
        context.Request.Method = method;
        context.Request.Path = path;
        context.Request.Scheme = "https";
        context.Request.Host = new HostString("localhost:9000");

        if (ipAddress != null)
        {
            context.Connection.RemoteIpAddress = System.Net.IPAddress.Parse(ipAddress);
        }

        if (username != null)
        {
            var claims = new[] { new Claim(ClaimTypes.Name, username) };
            var identity = new ClaimsIdentity(claims, "TestAuth");
            context.User = new ClaimsPrincipal(identity);
        }

        return context;
    }

    [Fact]
    public async Task InvokeAsync_ShouldCallNextMiddleware()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext();
        var nextCalled = false;

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Callback(() => nextCalled = true)
            .Returns(Task.CompletedTask);

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        nextCalled.Should().BeTrue("middleware should call next in pipeline");
        _mockNext.Verify(next => next(context), Times.Once);
    }

    [Fact]
    public async Task InvokeAsync_ShouldLogHttpRequest_WithCorrectEventType()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("GET", "/api/servers", "testuser", "192.168.1.100");

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        _mockSqlService.Verify(s => s.LogAuditEventAsync(
            It.Is<string>(eventType => eventType == "HttpRequest"),
            It.Is<string>(userName => userName == "testuser"),
            It.IsAny<string>(), // applicationName
            It.IsAny<string>(), // hostName
            It.Is<string>(ip => ip == "192.168.1.100"),
            It.IsAny<string>(), // databaseName
            It.IsAny<string>(), // schemaName
            It.IsAny<string>(), // objectName
            It.IsAny<string>(), // objectType
            It.IsAny<string>(), // actionType
            It.IsAny<string>(), // oldValue
            It.IsAny<string>(), // newValue
            It.IsAny<int?>(),   // affectedRows
            It.IsAny<string>(), // sqlText
            It.IsAny<int?>(),   // errorNumber
            It.IsAny<string>(), // errorMessage
            It.IsAny<string>(), // severity
            It.IsAny<string>(), // dataClassification
            It.IsAny<string>(), // complianceFlag
            It.IsAny<int>()     // retentionDays
        ), Times.Once, "should log HTTP request to audit trail");
    }

    [Fact]
    public async Task InvokeAsync_ShouldLogUserName_FromClaimsPrincipal()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("GET", "/api/servers", "john.doe", "192.168.1.100");

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        _mockSqlService.Verify(s => s.LogAuditEventAsync(
            It.IsAny<string>(),
            It.Is<string>(userName => userName == "john.doe"),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<int?>(), It.IsAny<string>(),
            It.IsAny<int?>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<int>()
        ), Times.Once);
    }

    [Fact]
    public async Task InvokeAsync_ShouldLogAnonymous_WhenNoUserAuthenticated()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("GET", "/api/servers"); // No username

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        _mockSqlService.Verify(s => s.LogAuditEventAsync(
            It.IsAny<string>(),
            It.Is<string>(userName => userName == "Anonymous"),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<int?>(), It.IsAny<string>(),
            It.IsAny<int?>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<int>()
        ), Times.Once);
    }

    [Fact]
    public async Task InvokeAsync_ShouldLogIPAddress_WhenAvailable()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("GET", "/api/servers", "testuser", "10.0.0.42");

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        _mockSqlService.Verify(s => s.LogAuditEventAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.Is<string>(ip => ip == "10.0.0.42"),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<int?>(),
            It.IsAny<string>(), It.IsAny<int?>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<int>()
        ), Times.Once);
    }

    [Fact]
    public async Task InvokeAsync_ShouldIncludeRequestDetails_InSqlText()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("POST", "/api/servers/1/metrics", "testuser");

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        _mockSqlService.Verify(s => s.LogAuditEventAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<int?>(),
            It.Is<string>(sqlText =>
                sqlText.Contains("POST") &&
                sqlText.Contains("/api/servers/1/metrics") &&
                sqlText.Contains("Duration:")),
            It.IsAny<int?>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<int>()
        ), Times.Once, "SqlText should contain request method, path, and duration");
    }

    [Fact]
    public async Task InvokeAsync_ShouldNotLog_HealthCheckEndpoint()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("GET", "/health");

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        _mockSqlService.Verify(s => s.LogAuditEventAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<int?>(), It.IsAny<string>(), It.IsAny<int?>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<int>()
        ), Times.Never, "/health endpoint should be excluded from audit logging");
    }

    [Fact]
    public async Task InvokeAsync_ShouldNotLog_SwaggerEndpoint()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("GET", "/swagger/v1/swagger.json");

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        _mockSqlService.Verify(s => s.LogAuditEventAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<int?>(), It.IsAny<string>(), It.IsAny<int?>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<int>()
        ), Times.Never, "/swagger endpoints should be excluded from audit logging");
    }

    [Fact]
    public async Task InvokeAsync_ShouldLogException_WhenNextMiddlewareThrows()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("GET", "/api/servers");
        var expectedException = new InvalidOperationException("Database connection failed");

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .ThrowsAsync(expectedException);

        // Act & Assert
        var exception = await Assert.ThrowsAsync<InvalidOperationException>(
            async () => await middleware.InvokeAsync(context));

        exception.Message.Should().Be("Database connection failed");

        // Assert audit log was called with error details
        _mockSqlService.Verify(s => s.LogAuditEventAsync(
            It.Is<string>(eventType => eventType == "HttpRequestError"),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<int?>(),
            It.IsAny<string>(),
            It.Is<int?>(errorNumber => errorNumber == 1),
            It.Is<string>(errorMsg => errorMsg.Contains("Database connection failed")),
            It.Is<string>(severity => severity == "Error"),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<int>()
        ), Times.Once, "should log exception details to audit trail");
    }

    [Fact]
    public async Task InvokeAsync_ShouldCaptureRequestBody_ForPostRequests()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("POST", "/api/servers");

        var requestBody = "{\"serverName\":\"SQL-PROD-01\",\"environment\":\"Production\"}";
        context.Request.Body = new MemoryStream(Encoding.UTF8.GetBytes(requestBody));
        context.Request.ContentType = "application/json";

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        _mockSqlService.Verify(s => s.LogAuditEventAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<int?>(),
            It.Is<string>(sqlText => sqlText.Contains("SQL-PROD-01")),
            It.IsAny<int?>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<int>()
        ), Times.Once, "POST request body should be captured in audit log");
    }

    [Fact]
    public async Task InvokeAsync_ShouldCaptureRequestBody_ForPutRequests()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("PUT", "/api/servers/1");

        var requestBody = "{\"isActive\":false}";
        context.Request.Body = new MemoryStream(Encoding.UTF8.GetBytes(requestBody));
        context.Request.ContentType = "application/json";

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        _mockSqlService.Verify(s => s.LogAuditEventAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<int?>(),
            It.Is<string>(sqlText => sqlText.Contains("isActive")),
            It.IsAny<int?>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<int>()
        ), Times.Once, "PUT request body should be captured in audit log");
    }

    [Fact]
    public async Task InvokeAsync_ShouldNotCaptureRequestBody_ForGetRequests()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("GET", "/api/servers");

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        // Act
        await middleware.InvokeAsync(context);

        // Assert - SqlText should NOT contain request body marker
        _mockSqlService.Verify(s => s.LogAuditEventAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<int?>(),
            It.Is<string>(sqlText => !sqlText.Contains("Request Body:")),
            It.IsAny<int?>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<int>()
        ), Times.Once, "GET requests should not log request body");
    }

    [Fact]
    public async Task InvokeAsync_ShouldNotFailRequest_WhenAuditLoggingFails()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("GET", "/api/servers");
        var nextCalled = false;

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Callback(() => nextCalled = true)
            .Returns(Task.CompletedTask);

        _mockSqlService.Setup(s => s.LogAuditEventAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<int?>(), It.IsAny<string>(), It.IsAny<int?>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<int>()
        )).ThrowsAsync(new Exception("Audit database unavailable"));

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        nextCalled.Should().BeTrue("request should complete even if audit logging fails");
    }

    [Fact]
    public async Task InvokeAsync_ShouldLogWarning_WhenAuditLoggingFails()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext("GET", "/api/servers");

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        _mockSqlService.Setup(s => s.LogAuditEventAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<int?>(), It.IsAny<string>(), It.IsAny<int?>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<int>()
        )).ThrowsAsync(new Exception("Audit database unavailable"));

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        _mockLogger.Verify(
            x => x.Log(
                LogLevel.Error,
                It.IsAny<EventId>(),
                It.Is<It.IsAnyType>((v, t) => v.ToString()!.Contains("Failed to log audit event")),
                It.IsAny<Exception>(),
                It.IsAny<Func<It.IsAnyType, Exception?, string>>()!),
            Times.Once,
            "should log error when audit logging fails");
    }

    [Fact]
    public async Task InvokeAsync_ShouldSetComplianceFlag_ToSOC2()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext();

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        _mockSqlService.Verify(s => s.LogAuditEventAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<int?>(), It.IsAny<string>(), It.IsAny<int?>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(),
            It.Is<string>(complianceFlag => complianceFlag == "SOC2"),
            It.IsAny<int>()
        ), Times.Once, "ComplianceFlag should be set to SOC2");
    }

    [Fact]
    public async Task InvokeAsync_ShouldSetDataClassification_ToInternal()
    {
        // Arrange
        var middleware = CreateMiddleware();
        var context = CreateHttpContext();

        _mockNext.Setup(next => next(It.IsAny<HttpContext>()))
            .Returns(Task.CompletedTask);

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        _mockSqlService.Verify(s => s.LogAuditEventAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<int?>(), It.IsAny<string>(), It.IsAny<int?>(), It.IsAny<string>(),
            It.IsAny<string>(),
            It.Is<string>(dataClass => dataClass == "Internal"),
            It.IsAny<string>(), It.IsAny<int>()
        ), Times.Once, "DataClassification should be set to Internal");
    }
}
