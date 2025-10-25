using FluentAssertions;
using Microsoft.AspNetCore.Mvc;
using Moq;
using SqlMonitor.Api.Controllers;
using SqlMonitor.Api.Models;
using SqlMonitor.Api.Services;
using Xunit;

namespace SqlMonitor.Api.Tests.Controllers;

/// <summary>
/// TDD tests for MetricsController
/// Phase: RED (Write tests FIRST, expect failures)
/// </summary>
public class MetricsControllerTests
{
    private readonly Mock<ISqlService> _mockSqlService;
    private readonly MetricsController _controller;

    public MetricsControllerTests()
    {
        _mockSqlService = new Mock<ISqlService>();
        _controller = new MetricsController(_mockSqlService.Object);
    }

    [Fact]
    public async Task GetMetrics_ShouldReturnOkResult_WithListOfMetrics()
    {
        // Arrange
        var expectedMetrics = new List<PerformanceMetric>
        {
            new PerformanceMetric
            {
                MetricID = 1,
                ServerID = 1,
                ServerName = "SQL-PROD-01",
                CollectionTime = DateTime.UtcNow,
                MetricCategory = "CPU",
                MetricName = "Percent",
                MetricValue = 45.5m
            }
        };

        _mockSqlService
            .Setup(s => s.GetMetricsAsync(1, null, null, null, null))
            .ReturnsAsync(expectedMetrics);

        // Act
        var result = await _controller.GetMetrics(serverID: 1);

        // Assert
        var okResult = result.Result.Should().BeOfType<OkObjectResult>().Subject;
        var metrics = okResult.Value.Should().BeAssignableTo<IEnumerable<PerformanceMetric>>().Subject;
        metrics.Should().HaveCount(1);
        metrics.First().MetricCategory.Should().Be("CPU");
    }

    [Fact]
    public async Task GetMetrics_ShouldFilterByTimeRange_WhenProvided()
    {
        // Arrange
        var startTime = DateTime.UtcNow.AddHours(-1);
        var endTime = DateTime.UtcNow;

        _mockSqlService
            .Setup(s => s.GetMetricsAsync(1, startTime, endTime, null, null))
            .ReturnsAsync(new List<PerformanceMetric>());

        // Act
        await _controller.GetMetrics(serverID: 1, startTime: startTime, endTime: endTime);

        // Assert
        _mockSqlService.Verify(
            s => s.GetMetricsAsync(1, startTime, endTime, null, null),
            Times.Once);
    }

    [Fact]
    public async Task GetMetrics_ShouldFilterByCategory_WhenProvided()
    {
        // Arrange
        var cpuMetrics = new List<PerformanceMetric>
        {
            new PerformanceMetric { MetricCategory = "CPU", MetricName = "Percent", MetricValue = 45.5m }
        };

        _mockSqlService
            .Setup(s => s.GetMetricsAsync(1, null, null, "CPU", null))
            .ReturnsAsync(cpuMetrics);

        // Act
        var result = await _controller.GetMetrics(serverID: 1, metricCategory: "CPU");

        // Assert
        var okResult = result.Result.Should().BeOfType<OkObjectResult>().Subject;
        var metrics = okResult.Value.Should().BeAssignableTo<IEnumerable<PerformanceMetric>>().Subject;
        metrics.Should().OnlyContain(m => m.MetricCategory == "CPU");
    }

    [Fact]
    public async Task GetMetrics_ShouldReturn400_WhenServerIDIsZero()
    {
        // Act
        var result = await _controller.GetMetrics(serverID: 0);

        // Assert
        result.Result.Should().BeOfType<BadRequestObjectResult>();
    }

    [Fact]
    public async Task GetMetrics_ShouldReturn500_WhenExceptionOccurs()
    {
        // Arrange
        _mockSqlService
            .Setup(s => s.GetMetricsAsync(1, null, null, null, null))
            .ThrowsAsync(new Exception("Database error"));

        // Act
        var result = await _controller.GetMetrics(serverID: 1);

        // Assert
        var statusResult = result.Result.Should().BeOfType<ObjectResult>().Subject;
        statusResult.StatusCode.Should().Be(500);
    }

    [Fact]
    public async Task InsertMetric_ShouldReturnCreated_WhenSuccessful()
    {
        // Arrange
        var request = new InsertMetricRequest
        {
            ServerID = 1,
            CollectionTime = DateTime.UtcNow,
            MetricCategory = "CPU",
            MetricName = "Percent",
            MetricValue = 45.5m
        };

        _mockSqlService
            .Setup(s => s.InsertMetricAsync(It.IsAny<InsertMetricRequest>()))
            .Returns(Task.CompletedTask);

        // Act
        var result = await _controller.InsertMetric(request);

        // Assert
        var createdResult = result.Should().BeOfType<CreatedAtActionResult>().Subject;
        createdResult.ActionName.Should().Be(nameof(MetricsController.GetMetrics));
    }

    [Fact]
    public async Task InsertMetric_ShouldReturn400_WhenRequestIsNull()
    {
        // Act
        var result = await _controller.InsertMetric(null!);

        // Assert
        result.Should().BeOfType<BadRequestObjectResult>();
    }

    [Fact]
    public async Task InsertMetric_ShouldReturn400_WhenServerIDIsZero()
    {
        // Arrange
        var request = new InsertMetricRequest
        {
            ServerID = 0,
            CollectionTime = DateTime.UtcNow,
            MetricCategory = "CPU",
            MetricName = "Percent"
        };

        // Act
        var result = await _controller.InsertMetric(request);

        // Assert
        result.Should().BeOfType<BadRequestObjectResult>();
    }

    [Fact]
    public async Task InsertMetric_ShouldReturn500_WhenExceptionOccurs()
    {
        // Arrange
        var request = new InsertMetricRequest
        {
            ServerID = 1,
            CollectionTime = DateTime.UtcNow,
            MetricCategory = "CPU",
            MetricName = "Percent"
        };

        _mockSqlService
            .Setup(s => s.InsertMetricAsync(It.IsAny<InsertMetricRequest>()))
            .ThrowsAsync(new Exception("Database error"));

        // Act
        var result = await _controller.InsertMetric(request);

        // Assert
        var statusResult = result.Should().BeOfType<ObjectResult>().Subject;
        statusResult.StatusCode.Should().Be(500);
    }

    [Fact]
    public async Task InsertMetric_ShouldCallService_WithCorrectRequest()
    {
        // Arrange
        var request = new InsertMetricRequest
        {
            ServerID = 1,
            CollectionTime = DateTime.UtcNow,
            MetricCategory = "CPU",
            MetricName = "Percent",
            MetricValue = 45.5m
        };

        _mockSqlService
            .Setup(s => s.InsertMetricAsync(It.IsAny<InsertMetricRequest>()))
            .Returns(Task.CompletedTask);

        // Act
        await _controller.InsertMetric(request);

        // Assert
        _mockSqlService.Verify(
            s => s.InsertMetricAsync(It.Is<InsertMetricRequest>(r =>
                r.ServerID == request.ServerID &&
                r.MetricCategory == request.MetricCategory &&
                r.MetricName == request.MetricName)),
            Times.Once);
    }
}
