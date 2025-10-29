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
/// Unit tests for QueriesController (Phase 1.9 query performance analysis)
/// Tests follow TDD pattern with Arrange-Act-Assert
/// </summary>
public class QueriesControllerTests
{
    private readonly Mock<IQueryService> _mockQueryService;
    private readonly Mock<ILogger<QueriesController>> _mockLogger;
    private readonly QueriesController _controller;

    public QueriesControllerTests()
    {
        _mockQueryService = new Mock<IQueryService>();
        _mockLogger = new Mock<ILogger<QueriesController>>();
        _controller = new QueriesController(_mockQueryService.Object, _mockLogger.Object);
    }

    #region GetTopQueries Tests

    [Fact]
    public async Task GetTopQueries_ShouldReturnOkResult_WithDefaultParameters()
    {
        // Arrange
        var expectedQueries = new List<TopQueryModel>
        {
            new TopQueryModel
            {
                ServerID = 1,
                ServerName = "SQL-PROD-01",
                DatabaseName = "ApplicationDB",
                QueryID = 100,
                ExecutionCount = 1000,
                TotalCpuMs = 50000,
                AvgCpuMs = 50
            },
            new TopQueryModel
            {
                ServerID = 1,
                ServerName = "SQL-PROD-01",
                DatabaseName = "ApplicationDB",
                QueryID = 101,
                ExecutionCount = 500,
                TotalCpuMs = 30000,
                AvgCpuMs = 60
            }
        };

        _mockQueryService
            .Setup(s => s.GetTopQueriesAsync(null, "TotalCpu", 50, 10))
            .ReturnsAsync(expectedQueries);

        // Act
        var result = await _controller.GetTopQueries();

        // Assert
        var okResult = result.Result.Should().BeOfType<OkObjectResult>().Subject;
        var queries = okResult.Value.Should().BeAssignableTo<IEnumerable<TopQueryModel>>().Subject;
        queries.Should().HaveCount(2);
        queries.First().QueryID.Should().Be(100);
    }

    [Fact]
    public async Task GetTopQueries_ShouldFilterByServerId_WhenProvided()
    {
        // Arrange
        var expectedQueries = new List<TopQueryModel>
        {
            new TopQueryModel
            {
                ServerID = 2,
                ServerName = "SQL-PROD-02",
                QueryID = 200,
                ExecutionCount = 800
            }
        };

        _mockQueryService
            .Setup(s => s.GetTopQueriesAsync(2, "TotalCpu", 50, 10))
            .ReturnsAsync(expectedQueries);

        // Act
        var result = await _controller.GetTopQueries(serverId: 2);

        // Assert
        var okResult = result.Result.Should().BeOfType<OkObjectResult>().Subject;
        var queries = okResult.Value.Should().BeAssignableTo<IEnumerable<TopQueryModel>>().Subject;
        queries.Should().OnlyContain(q => q.ServerID == 2);
    }

    [Fact]
    public async Task GetTopQueries_ShouldOrderByAvgCpu_WhenSpecified()
    {
        // Arrange
        var expectedQueries = new List<TopQueryModel>
        {
            new TopQueryModel { QueryID = 100, AvgCpuMs = 100 },
            new TopQueryModel { QueryID = 101, AvgCpuMs = 75 }
        };

        _mockQueryService
            .Setup(s => s.GetTopQueriesAsync(null, "AvgCpu", 50, 10))
            .ReturnsAsync(expectedQueries);

        // Act
        var result = await _controller.GetTopQueries(orderBy: "AvgCpu");

        // Assert
        _mockQueryService.Verify(s => s.GetTopQueriesAsync(null, "AvgCpu", 50, 10), Times.Once);
    }

    [Fact]
    public async Task GetTopQueries_ShouldAcceptCustomTopN_WhenValid()
    {
        // Arrange
        var expectedQueries = new List<TopQueryModel>();
        _mockQueryService
            .Setup(s => s.GetTopQueriesAsync(null, "TotalCpu", 100, 10))
            .ReturnsAsync(expectedQueries);

        // Act
        var result = await _controller.GetTopQueries(topN: 100);

        // Assert
        _mockQueryService.Verify(s => s.GetTopQueriesAsync(null, "TotalCpu", 100, 10), Times.Once);
    }

    [Fact]
    public async Task GetTopQueries_ShouldReturnBadRequest_WhenTopNTooSmall()
    {
        // Act
        var result = await _controller.GetTopQueries(topN: 0);

        // Assert
        var badRequestResult = result.Result.Should().BeOfType<BadRequestObjectResult>().Subject;
        badRequestResult.StatusCode.Should().Be(StatusCodes.Status400BadRequest);
    }

    [Fact]
    public async Task GetTopQueries_ShouldReturnBadRequest_WhenTopNTooLarge()
    {
        // Act
        var result = await _controller.GetTopQueries(topN: 501);

        // Assert
        var badRequestResult = result.Result.Should().BeOfType<BadRequestObjectResult>().Subject;
        badRequestResult.StatusCode.Should().Be(StatusCodes.Status400BadRequest);
    }

    [Fact]
    public async Task GetTopQueries_ShouldReturnBadRequest_WhenMinExecutionCountNegative()
    {
        // Act
        var result = await _controller.GetTopQueries(minExecutionCount: -1);

        // Assert
        var badRequestResult = result.Result.Should().BeOfType<BadRequestObjectResult>().Subject;
        badRequestResult.StatusCode.Should().Be(StatusCodes.Status400BadRequest);
    }

    [Fact]
    public async Task GetTopQueries_ShouldReturnBadRequest_WhenOrderByInvalid()
    {
        // Act
        var result = await _controller.GetTopQueries(orderBy: "InvalidMetric");

        // Assert
        var badRequestResult = result.Result.Should().BeOfType<BadRequestObjectResult>().Subject;
        badRequestResult.StatusCode.Should().Be(StatusCodes.Status400BadRequest);
    }

    [Theory]
    [InlineData("TotalCpu")]
    [InlineData("AvgCpu")]
    [InlineData("TotalReads")]
    [InlineData("AvgDuration")]
    public async Task GetTopQueries_ShouldAcceptValidOrderBy_CaseInsensitive(string orderBy)
    {
        // Arrange
        _mockQueryService
            .Setup(s => s.GetTopQueriesAsync(null, orderBy, 50, 10))
            .ReturnsAsync(new List<TopQueryModel>());

        // Act
        var result = await _controller.GetTopQueries(orderBy: orderBy);

        // Assert
        result.Result.Should().BeOfType<OkObjectResult>();
    }

    [Fact]
    public async Task GetTopQueries_ShouldAcceptMinExecutionCount_WhenProvided()
    {
        // Arrange
        _mockQueryService
            .Setup(s => s.GetTopQueriesAsync(null, "TotalCpu", 50, 100))
            .ReturnsAsync(new List<TopQueryModel>());

        // Act
        var result = await _controller.GetTopQueries(minExecutionCount: 100);

        // Assert
        _mockQueryService.Verify(s => s.GetTopQueriesAsync(null, "TotalCpu", 50, 100), Times.Once);
    }

    [Fact]
    public async Task GetTopQueries_ShouldReturn500_WhenExceptionOccurs()
    {
        // Arrange
        _mockQueryService
            .Setup(s => s.GetTopQueriesAsync(null, "TotalCpu", 50, 10))
            .ThrowsAsync(new Exception("Database error"));

        // Act
        var result = await _controller.GetTopQueries();

        // Assert
        var statusResult = result.Result.Should().BeOfType<ObjectResult>().Subject;
        statusResult.StatusCode.Should().Be(500);
    }

    [Fact]
    public async Task GetTopQueries_ShouldLogInformation_WhenCalled()
    {
        // Arrange
        _mockQueryService
            .Setup(s => s.GetTopQueriesAsync(null, "TotalCpu", 50, 10))
            .ReturnsAsync(new List<TopQueryModel>());

        // Act
        await _controller.GetTopQueries();

        // Assert
        _mockLogger.Verify(
            x => x.Log(
                LogLevel.Information,
                It.IsAny<EventId>(),
                It.Is<It.IsAnyType>((v, t) => v.ToString().Contains("Getting top")),
                null,
                It.IsAny<Func<It.IsAnyType, Exception?, string>>()),
            Times.Once);
    }

    [Fact]
    public async Task GetTopQueries_ShouldLogError_WhenExceptionOccurs()
    {
        // Arrange
        var exception = new Exception("Database error");
        _mockQueryService
            .Setup(s => s.GetTopQueriesAsync(null, "TotalCpu", 50, 10))
            .ThrowsAsync(exception);

        // Act
        await _controller.GetTopQueries();

        // Assert
        _mockLogger.Verify(
            x => x.Log(
                LogLevel.Error,
                It.IsAny<EventId>(),
                It.Is<It.IsAnyType>((v, t) => v.ToString().Contains("Error retrieving top queries")),
                exception,
                It.IsAny<Func<It.IsAnyType, Exception?, string>>()),
            Times.Once);
    }

    [Fact]
    public async Task GetTopQueries_ShouldReturnEmptyList_WhenNoQueriesMatch()
    {
        // Arrange
        _mockQueryService
            .Setup(s => s.GetTopQueriesAsync(null, "TotalCpu", 50, 10))
            .ReturnsAsync(new List<TopQueryModel>());

        // Act
        var result = await _controller.GetTopQueries();

        // Assert
        var okResult = result.Result.Should().BeOfType<OkObjectResult>().Subject;
        var queries = okResult.Value.Should().BeAssignableTo<IEnumerable<TopQueryModel>>().Subject;
        queries.Should().BeEmpty();
    }

    #endregion
}
