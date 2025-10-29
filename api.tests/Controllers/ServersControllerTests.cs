using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using Moq;
using SqlServerMonitor.Api.Controllers;
using SqlServerMonitor.Api.Models;
using SqlServerMonitor.Api.Services;
using Xunit;

namespace SqlMonitor.Api.Tests.Controllers;

/// <summary>
/// Unit tests for ServersController (Phase 1.9 multi-server support)
/// Tests follow TDD pattern with Arrange-Act-Assert
/// </summary>
public class ServersControllerTests
{
    private readonly Mock<IServerService> _mockServerService;
    private readonly Mock<ILogger<ServersController>> _mockLogger;
    private readonly ServersController _controller;

    public ServersControllerTests()
    {
        _mockServerService = new Mock<IServerService>();
        _mockLogger = new Mock<ILogger<ServersController>>();
        _controller = new ServersController(_mockServerService.Object, _mockLogger.Object);
    }

    #region GetServers Tests

    [Fact]
    public async Task GetServers_ShouldReturnOkResult_WithListOfServers()
    {
        // Arrange
        var expectedServers = new List<ServerModel>
        {
            new ServerModel { ServerID = 1, ServerName = "SQL-PROD-01", Environment = "Production", IsActive = true },
            new ServerModel { ServerID = 2, ServerName = "SQL-PROD-02", Environment = "Production", IsActive = true }
        };

        _mockServerService
            .Setup(s => s.GetServersAsync(null, false))
            .ReturnsAsync(expectedServers);

        // Act
        var result = await _controller.GetServers();

        // Assert
        var okResult = result.Result.Should().BeOfType<OkObjectResult>().Subject;
        var servers = okResult.Value.Should().BeAssignableTo<IEnumerable<ServerModel>>().Subject;
        servers.Should().HaveCount(2);
        servers.Should().Contain(s => s.ServerName == "SQL-PROD-01");
    }

    [Fact]
    public async Task GetServers_ShouldFilterByEnvironment_WhenProvided()
    {
        // Arrange
        var prodServers = new List<ServerModel>
        {
            new ServerModel { ServerID = 1, ServerName = "SQL-PROD-01", Environment = "Production", IsActive = true }
        };

        _mockServerService
            .Setup(s => s.GetServersAsync("Production", false))
            .ReturnsAsync(prodServers);

        // Act
        var result = await _controller.GetServers(environment: "Production");

        // Assert
        var okResult = result.Result.Should().BeOfType<OkObjectResult>().Subject;
        var servers = okResult.Value.Should().BeAssignableTo<IEnumerable<ServerModel>>().Subject;
        servers.Should().OnlyContain(s => s.Environment == "Production");
    }

    [Fact]
    public async Task GetServers_ShouldIncludeInactive_WhenRequested()
    {
        // Arrange
        var allServers = new List<ServerModel>
        {
            new ServerModel { ServerID = 1, ServerName = "SQL-PROD-01", IsActive = true },
            new ServerModel { ServerID = 2, ServerName = "SQL-OLD-01", IsActive = false }
        };

        _mockServerService
            .Setup(s => s.GetServersAsync(null, true))
            .ReturnsAsync(allServers);

        // Act
        var result = await _controller.GetServers(includeInactive: true);

        // Assert
        var okResult = result.Result.Should().BeOfType<OkObjectResult>().Subject;
        var servers = okResult.Value.Should().BeAssignableTo<IEnumerable<ServerModel>>().Subject;
        servers.Should().HaveCount(2);
        servers.Should().Contain(s => s.IsActive == false);
    }

    [Fact]
    public async Task GetServers_ShouldReturn500_WhenExceptionOccurs()
    {
        // Arrange
        _mockServerService
            .Setup(s => s.GetServersAsync(null, false))
            .ThrowsAsync(new Exception("Database connection failed"));

        // Act
        var result = await _controller.GetServers();

        // Assert
        var statusResult = result.Result.Should().BeOfType<ObjectResult>().Subject;
        statusResult.StatusCode.Should().Be(500);
    }

    #endregion

    #region GetServer Tests

    [Fact]
    public async Task GetServer_ShouldReturnOkResult_WhenServerExists()
    {
        // Arrange
        var server = new ServerModel { ServerID = 1, ServerName = "SQL-PROD-01", IsActive = true };
        _mockServerService.Setup(s => s.GetServerByIdAsync(1)).ReturnsAsync(server);

        // Act
        var result = await _controller.GetServer(1);

        // Assert
        var okResult = result.Result.Should().BeOfType<OkObjectResult>().Subject;
        var returnedServer = okResult.Value.Should().BeOfType<ServerModel>().Subject;
        returnedServer.ServerID.Should().Be(1);
        returnedServer.ServerName.Should().Be("SQL-PROD-01");
    }

    [Fact]
    public async Task GetServer_ShouldReturnNotFound_WhenServerDoesNotExist()
    {
        // Arrange
        _mockServerService.Setup(s => s.GetServerByIdAsync(999)).ReturnsAsync((ServerModel?)null);

        // Act
        var result = await _controller.GetServer(999);

        // Assert
        result.Result.Should().BeOfType<NotFoundObjectResult>();
    }

    [Fact]
    public async Task GetServer_ShouldReturn500_WhenExceptionOccurs()
    {
        // Arrange
        _mockServerService
            .Setup(s => s.GetServerByIdAsync(1))
            .ThrowsAsync(new Exception("Database error"));

        // Act
        var result = await _controller.GetServer(1);

        // Assert
        var statusResult = result.Result.Should().BeOfType<ObjectResult>().Subject;
        statusResult.StatusCode.Should().Be(500);
    }

    #endregion

    #region GetServersHealth Tests

    [Fact]
    public async Task GetServersHealth_ShouldReturnOkResult_WithHealthStatus()
    {
        // Arrange
        var healthStatus = new List<ServerHealthModel>
        {
            new ServerHealthModel
            {
                ServerID = 1,
                ServerName = "SQL-PROD-01",
                HealthStatus = "Healthy",
                LatestCpuPct = 25.5m,
                Avg24HrCpuPct = 30.2m
            }
        };

        _mockServerService
            .Setup(s => s.GetServerHealthStatusAsync(null, false))
            .ReturnsAsync(healthStatus);

        // Act
        var result = await _controller.GetServersHealth();

        // Assert
        var okResult = result.Result.Should().BeOfType<OkObjectResult>().Subject;
        var health = okResult.Value.Should().BeAssignableTo<IEnumerable<ServerHealthModel>>().Subject;
        health.Should().HaveCount(1);
        health.First().HealthStatus.Should().Be("Healthy");
    }

    [Fact]
    public async Task GetServersHealth_ShouldFilterByEnvironment()
    {
        // Arrange
        var healthStatus = new List<ServerHealthModel>
        {
            new ServerHealthModel { ServerID = 1, Environment = "Production" }
        };

        _mockServerService
            .Setup(s => s.GetServerHealthStatusAsync("Production", false))
            .ReturnsAsync(healthStatus);

        // Act
        var result = await _controller.GetServersHealth(environment: "Production");

        // Assert
        _mockServerService.Verify(s => s.GetServerHealthStatusAsync("Production", false), Times.Once);
    }

    #endregion

    #region GetServerHealth Tests

    [Fact]
    public async Task GetServerHealth_ShouldReturnOkResult_WhenServerExists()
    {
        // Arrange
        var health = new ServerHealthModel
        {
            ServerID = 1,
            ServerName = "SQL-PROD-01",
            HealthStatus = "Healthy",
            LatestCpuPct = 25.5m
        };

        _mockServerService.Setup(s => s.GetServerHealthStatusAsync(1)).ReturnsAsync(health);

        // Act
        var result = await _controller.GetServerHealth(1);

        // Assert
        var okResult = result.Result.Should().BeOfType<OkObjectResult>().Subject;
        var returnedHealth = okResult.Value.Should().BeOfType<ServerHealthModel>().Subject;
        returnedHealth.ServerID.Should().Be(1);
        returnedHealth.HealthStatus.Should().Be("Healthy");
    }

    [Fact]
    public async Task GetServerHealth_ShouldReturnNotFound_WhenServerDoesNotExist()
    {
        // Arrange
        _mockServerService.Setup(s => s.GetServerHealthStatusAsync(999)).ReturnsAsync((ServerHealthModel?)null);

        // Act
        var result = await _controller.GetServerHealth(999);

        // Assert
        result.Result.Should().BeOfType<NotFoundObjectResult>();
    }

    #endregion

    #region RegisterServer Tests

    [Fact]
    public async Task RegisterServer_ShouldReturnCreatedResult_WithValidData()
    {
        // Arrange
        var request = new ServerRegistrationRequest
        {
            ServerName = "SQL-NEW-01",
            Environment = "Development",
            IsActive = true
        };

        var createdServer = new ServerModel
        {
            ServerID = 5,
            ServerName = "SQL-NEW-01",
            Environment = "Development",
            IsActive = true
        };

        _mockServerService
            .Setup(s => s.RegisterServerAsync("SQL-NEW-01", "Development", true))
            .ReturnsAsync(createdServer);

        // Act
        var result = await _controller.RegisterServer(request);

        // Assert
        var createdResult = result.Result.Should().BeOfType<CreatedAtActionResult>().Subject;
        createdResult.StatusCode.Should().Be(StatusCodes.Status201Created);
        var server = createdResult.Value.Should().BeOfType<ServerModel>().Subject;
        server.ServerID.Should().Be(5);
        server.ServerName.Should().Be("SQL-NEW-01");
    }

    [Fact]
    public async Task RegisterServer_ShouldReturnBadRequest_WhenModelStateInvalid()
    {
        // Arrange
        _controller.ModelState.AddModelError("ServerName", "Required");
        var request = new ServerRegistrationRequest();

        // Act
        var result = await _controller.RegisterServer(request);

        // Assert
        result.Result.Should().BeOfType<BadRequestObjectResult>();
    }

    [Fact]
    public async Task RegisterServer_ShouldReturnConflict_WhenServerAlreadyExists()
    {
        // Arrange
        var request = new ServerRegistrationRequest { ServerName = "SQL-PROD-01", Environment = "Production" };

        _mockServerService
            .Setup(s => s.RegisterServerAsync("SQL-PROD-01", "Production", null))
            .ThrowsAsync(new InvalidOperationException("Server already exists"));

        // Act
        var result = await _controller.RegisterServer(request);

        // Assert
        var conflictResult = result.Result.Should().BeOfType<ConflictObjectResult>().Subject;
        conflictResult.StatusCode.Should().Be(StatusCodes.Status409Conflict);
    }

    #endregion

    #region UpdateServer Tests

    [Fact]
    public async Task UpdateServer_ShouldReturnOkResult_WithUpdatedServer()
    {
        // Arrange
        var request = new ServerUpdateRequest { Environment = "Production", IsActive = false };
        var updatedServer = new ServerModel
        {
            ServerID = 1,
            ServerName = "SQL-PROD-01",
            Environment = "Production",
            IsActive = false
        };

        _mockServerService
            .Setup(s => s.UpdateServerAsync(1, "Production", false))
            .ReturnsAsync(updatedServer);

        // Act
        var result = await _controller.UpdateServer(1, request);

        // Assert
        var okResult = result.Result.Should().BeOfType<OkObjectResult>().Subject;
        var server = okResult.Value.Should().BeOfType<ServerModel>().Subject;
        server.IsActive.Should().BeFalse();
    }

    [Fact]
    public async Task UpdateServer_ShouldReturnBadRequest_WhenModelStateInvalid()
    {
        // Arrange
        _controller.ModelState.AddModelError("Environment", "Invalid");
        var request = new ServerUpdateRequest();

        // Act
        var result = await _controller.UpdateServer(1, request);

        // Assert
        result.Result.Should().BeOfType<BadRequestObjectResult>();
    }

    [Fact]
    public async Task UpdateServer_ShouldReturn500_WhenExceptionOccurs()
    {
        // Arrange
        var request = new ServerUpdateRequest { IsActive = false };
        _mockServerService
            .Setup(s => s.UpdateServerAsync(1, null, false))
            .ThrowsAsync(new Exception("Database error"));

        // Act
        var result = await _controller.UpdateServer(1, request);

        // Assert
        var statusResult = result.Result.Should().BeOfType<ObjectResult>().Subject;
        statusResult.StatusCode.Should().Be(500);
    }

    #endregion

    #region GetServerTrends Tests

    [Fact]
    public async Task GetServerTrends_ShouldReturnOkResult_WithTrendData()
    {
        // Arrange
        var trends = new List<ResourceTrendModel>
        {
            new ResourceTrendModel
            {
                ServerID = 1,
                ServerName = "SQL-PROD-01",
                CollectionDate = DateTime.UtcNow.AddDays(-1),
                AvgCpuPct = 45.5m,
                MaxCpuPct = 78.2m
            }
        };

        _mockServerService
            .Setup(s => s.GetResourceTrendsAsync(1, 7))
            .ReturnsAsync(trends);

        // Act
        var result = await _controller.GetServerTrends(1);

        // Assert
        var okResult = result.Result.Should().BeOfType<OkObjectResult>().Subject;
        var returnedTrends = okResult.Value.Should().BeAssignableTo<IEnumerable<ResourceTrendModel>>().Subject;
        returnedTrends.Should().HaveCount(1);
    }

    [Fact]
    public async Task GetServerTrends_ShouldAcceptCustomDaysParameter()
    {
        // Arrange
        _mockServerService
            .Setup(s => s.GetResourceTrendsAsync(1, 30))
            .ReturnsAsync(new List<ResourceTrendModel>());

        // Act
        var result = await _controller.GetServerTrends(1, days: 30);

        // Assert
        _mockServerService.Verify(s => s.GetResourceTrendsAsync(1, 30), Times.Once);
    }

    #endregion

    #region GetServerDatabases Tests

    [Fact]
    public async Task GetServerDatabases_ShouldReturnOkResult_WithDatabaseList()
    {
        // Arrange
        var databases = new List<DatabaseSummaryModel>
        {
            new DatabaseSummaryModel
            {
                ServerID = 1,
                ServerName = "SQL-PROD-01",
                DatabaseName = "ApplicationDB",
                TotalSizeMB = 5000,
                BackupHealthStatus = "Healthy"
            }
        };

        _mockServerService
            .Setup(s => s.GetDatabaseSummaryAsync(1, null))
            .ReturnsAsync(databases);

        // Act
        var result = await _controller.GetServerDatabases(1);

        // Assert
        var okResult = result.Result.Should().BeOfType<OkObjectResult>().Subject;
        var returnedDbs = okResult.Value.Should().BeAssignableTo<IEnumerable<DatabaseSummaryModel>>().Subject;
        returnedDbs.Should().HaveCount(1);
        returnedDbs.First().DatabaseName.Should().Be("ApplicationDB");
    }

    [Fact]
    public async Task GetServerDatabases_ShouldFilterByDatabaseName_WhenProvided()
    {
        // Arrange
        _mockServerService
            .Setup(s => s.GetDatabaseSummaryAsync(1, "ApplicationDB"))
            .ReturnsAsync(new List<DatabaseSummaryModel>());

        // Act
        var result = await _controller.GetServerDatabases(1, databaseName: "ApplicationDB");

        // Assert
        _mockServerService.Verify(s => s.GetDatabaseSummaryAsync(1, "ApplicationDB"), Times.Once);
    }

    #endregion
}
