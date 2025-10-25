using FluentAssertions;
using Microsoft.AspNetCore.Mvc;
using Moq;
using SqlMonitor.Api.Controllers;
using SqlMonitor.Api.Models;
using SqlMonitor.Api.Services;
using Xunit;

namespace SqlMonitor.Api.Tests.Controllers;

/// <summary>
/// TDD tests for ServerController
/// Phase: RED (Write tests FIRST, expect failures)
/// </summary>
public class ServerControllerTests
{
    private readonly Mock<ISqlService> _mockSqlService;
    private readonly ServerController _controller;

    public ServerControllerTests()
    {
        _mockSqlService = new Mock<ISqlService>();
        _controller = new ServerController(_mockSqlService.Object);
    }

    [Fact]
    public async Task GetServers_ShouldReturnOkResult_WithListOfServers()
    {
        // Arrange
        var expectedServers = new List<Server>
        {
            new Server { ServerID = 1, ServerName = "SQL-PROD-01", Environment = "Production", IsActive = true },
            new Server { ServerID = 2, ServerName = "SQL-PROD-02", Environment = "Production", IsActive = true }
        };

        _mockSqlService
            .Setup(s => s.GetServersAsync(null, null))
            .ReturnsAsync(expectedServers);

        // Act
        var result = await _controller.GetServers();

        // Assert
        var okResult = result.Result.Should().BeOfType<OkObjectResult>().Subject;
        var servers = okResult.Value.Should().BeAssignableTo<IEnumerable<Server>>().Subject;
        servers.Should().HaveCount(2);
        servers.Should().Contain(s => s.ServerName == "SQL-PROD-01");
    }

    [Fact]
    public async Task GetServers_ShouldFilterByIsActive_WhenProvided()
    {
        // Arrange
        var activeServers = new List<Server>
        {
            new Server { ServerID = 1, ServerName = "SQL-PROD-01", IsActive = true }
        };

        _mockSqlService
            .Setup(s => s.GetServersAsync(true, null))
            .ReturnsAsync(activeServers);

        // Act
        var result = await _controller.GetServers(isActive: true);

        // Assert
        var okResult = result.Result.Should().BeOfType<OkObjectResult>().Subject;
        var servers = okResult.Value.Should().BeAssignableTo<IEnumerable<Server>>().Subject;
        servers.Should().HaveCount(1);
        servers.Should().OnlyContain(s => s.IsActive == true);
    }

    [Fact]
    public async Task GetServers_ShouldFilterByEnvironment_WhenProvided()
    {
        // Arrange
        var prodServers = new List<Server>
        {
            new Server { ServerID = 1, ServerName = "SQL-PROD-01", Environment = "Production", IsActive = true }
        };

        _mockSqlService
            .Setup(s => s.GetServersAsync(null, "Production"))
            .ReturnsAsync(prodServers);

        // Act
        var result = await _controller.GetServers(environment: "Production");

        // Assert
        var okResult = result.Result.Should().BeOfType<OkObjectResult>().Subject;
        var servers = okResult.Value.Should().BeAssignableTo<IEnumerable<Server>>().Subject;
        servers.Should().OnlyContain(s => s.Environment == "Production");
    }

    [Fact]
    public async Task GetServers_ShouldReturnEmptyList_WhenNoServersExist()
    {
        // Arrange
        _mockSqlService
            .Setup(s => s.GetServersAsync(null, null))
            .ReturnsAsync(new List<Server>());

        // Act
        var result = await _controller.GetServers();

        // Assert
        var okResult = result.Result.Should().BeOfType<OkObjectResult>().Subject;
        var servers = okResult.Value.Should().BeAssignableTo<IEnumerable<Server>>().Subject;
        servers.Should().BeEmpty();
    }

    [Fact]
    public async Task GetServers_ShouldReturn500_WhenExceptionOccurs()
    {
        // Arrange
        _mockSqlService
            .Setup(s => s.GetServersAsync(null, null))
            .ThrowsAsync(new Exception("Database error"));

        // Act
        var result = await _controller.GetServers();

        // Assert
        var statusResult = result.Result.Should().BeOfType<ObjectResult>().Subject;
        statusResult.StatusCode.Should().Be(500);
    }

    [Fact]
    public async Task GetServers_ShouldCallServiceWithCorrectParameters()
    {
        // Arrange
        _mockSqlService
            .Setup(s => s.GetServersAsync(true, "Production"))
            .ReturnsAsync(new List<Server>());

        // Act
        await _controller.GetServers(isActive: true, environment: "Production");

        // Assert
        _mockSqlService.Verify(
            s => s.GetServersAsync(true, "Production"),
            Times.Once);
    }
}
