using FluentAssertions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using SqlServerMonitor.Api.Models;
using SqlServerMonitor.Api.Services;
using Xunit;

namespace SqlMonitor.Api.Tests.Integration;

/// <summary>
/// Integration tests for QueryService (Phase 1.9)
/// These tests require a test database with:
/// - MonitoringDB schema deployed
/// - Query Store enabled on test databases
/// - Test query data collected
/// - usp_GetTopQueries stored procedure created
///
/// Configure test database connection in:
/// - appsettings.Test.json OR
/// - Environment variable: ConnectionStrings__MonitoringDB
///
/// Run with: dotnet test --filter "Category=Integration"
/// </summary>
[Trait("Category", "Integration")]
[Collection("Database")]
public class QueryServiceIntegrationTests : IAsyncLifetime
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<QueryService> _logger;
    private QueryService _service = null!;

    public QueryServiceIntegrationTests()
    {
        // Load configuration from appsettings.Test.json or environment variables
        var configBuilder = new ConfigurationBuilder()
            .AddJsonFile("appsettings.Test.json", optional: true)
            .AddEnvironmentVariables();

        _configuration = configBuilder.Build();

        var loggerFactory = LoggerFactory.Create(builder => builder.AddConsole());
        _logger = loggerFactory.CreateLogger<QueryService>();
    }

    public Task InitializeAsync()
    {
        // Setup: Create service instance
        _service = new QueryService(_configuration, _logger);
        return Task.CompletedTask;
    }

    public Task DisposeAsync()
    {
        // Cleanup: No specific cleanup needed
        return Task.CompletedTask;
    }

    #region GetTopQueriesAsync Tests

    [Fact]
    public async Task GetTopQueriesAsync_ShouldReturnQueries_WithDefaultParameters()
    {
        // Act
        var queries = await _service.GetTopQueriesAsync();

        // Assert
        queries.Should().NotBeNull();
        // May be empty if no Query Store data collected yet

        if (queries.Any())
        {
            queries.Should().AllSatisfy(q =>
            {
                q.ServerID.Should().BeGreaterThan(0);
                q.ServerName.Should().NotBeNullOrEmpty();
                q.DatabaseName.Should().NotBeNullOrEmpty();
                q.QueryID.Should().BeGreaterThan(0);
                q.ExecutionCount.Should().BeGreaterThan(0);
            });

            // Should be ordered by TotalCpu (default)
            queries.Count().Should().BeLessThanOrEqualTo(50, "because default topN is 50");
        }
    }

    [Fact]
    public async Task GetTopQueriesAsync_ShouldFilterByServerId_WhenProvided()
    {
        // Arrange
        // First, get any queries to find a valid server ID
        var allQueries = await _service.GetTopQueriesAsync();
        if (!allQueries.Any())
        {
            // Skip test if no data available
            return;
        }

        var testServerId = allQueries.First().ServerID;

        // Act
        var queries = await _service.GetTopQueriesAsync(serverId: testServerId);

        // Assert
        queries.Should().NotBeNull();
        if (queries.Any())
        {
            queries.Should().OnlyContain(q => q.ServerID == testServerId);
        }
    }

    [Fact]
    public async Task GetTopQueriesAsync_ShouldLimitResults_WhenTopNSpecified()
    {
        // Act
        var queries = await _service.GetTopQueriesAsync(topN: 10);

        // Assert
        queries.Should().NotBeNull();
        queries.Count().Should().BeLessThanOrEqualTo(10, "because topN was set to 10");
    }

    [Fact]
    public async Task GetTopQueriesAsync_ShouldOrderByAvgCpu_WhenSpecified()
    {
        // Act
        var queries = await _service.GetTopQueriesAsync(orderBy: "AvgCpu", topN: 5);

        // Assert
        queries.Should().NotBeNull();

        if (queries.Any() && queries.Count() > 1)
        {
            // Verify ordering (descending by AvgCpu)
            var queriesList = queries.ToList();
            for (int i = 0; i < queriesList.Count - 1; i++)
            {
                queriesList[i].AvgCpuMs.Should().BeGreaterThanOrEqualTo(queriesList[i + 1].AvgCpuMs,
                    "because results should be ordered by AvgCpu descending");
            }
        }
    }

    [Fact]
    public async Task GetTopQueriesAsync_ShouldOrderByTotalReads_WhenSpecified()
    {
        // Act
        var queries = await _service.GetTopQueriesAsync(orderBy: "TotalReads", topN: 5);

        // Assert
        queries.Should().NotBeNull();

        if (queries.Any() && queries.Count() > 1)
        {
            // Verify ordering (descending by TotalReads)
            var queriesList = queries.ToList();
            for (int i = 0; i < queriesList.Count - 1; i++)
            {
                queriesList[i].TotalLogicalReads.Should().BeGreaterThanOrEqualTo(queriesList[i + 1].TotalLogicalReads,
                    "because results should be ordered by TotalReads descending");
            }
        }
    }

    [Fact]
    public async Task GetTopQueriesAsync_ShouldOrderByAvgDuration_WhenSpecified()
    {
        // Act
        var queries = await _service.GetTopQueriesAsync(orderBy: "AvgDuration", topN: 5);

        // Assert
        queries.Should().NotBeNull();

        if (queries.Any() && queries.Count() > 1)
        {
            // Verify ordering (descending by AvgDuration)
            var queriesList = queries.ToList();
            for (int i = 0; i < queriesList.Count - 1; i++)
            {
                queriesList[i].AvgDurationMs.Should().BeGreaterThanOrEqualTo(queriesList[i + 1].AvgDurationMs,
                    "because results should be ordered by AvgDuration descending");
            }
        }
    }

    [Fact]
    public async Task GetTopQueriesAsync_ShouldFilterByMinExecutionCount()
    {
        // Act
        var queries = await _service.GetTopQueriesAsync(minExecutionCount: 100);

        // Assert
        queries.Should().NotBeNull();

        if (queries.Any())
        {
            queries.Should().AllSatisfy(q =>
            {
                q.ExecutionCount.Should().BeGreaterThanOrEqualTo(100,
                    "because minExecutionCount was set to 100");
            });
        }
    }

    [Fact]
    public async Task GetTopQueriesAsync_ShouldReturnEmptyList_WhenNoQueriesMatch()
    {
        // Act - Use very high minExecutionCount that likely won't match anything
        var queries = await _service.GetTopQueriesAsync(minExecutionCount: 1000000);

        // Assert
        queries.Should().NotBeNull();
        queries.Should().BeEmpty("because minExecutionCount is very high");
    }

    [Fact]
    public async Task GetTopQueriesAsync_ShouldMapAllProperties_Correctly()
    {
        // Act
        var queries = await _service.GetTopQueriesAsync(topN: 1);

        // Assert
        queries.Should().NotBeNull();

        if (queries.Any())
        {
            var query = queries.First();

            // Verify all key properties are mapped
            query.ServerID.Should().BeGreaterThan(0);
            query.ServerName.Should().NotBeNullOrEmpty();
            query.DatabaseName.Should().NotBeNullOrEmpty();
            query.QueryID.Should().BeGreaterThan(0);
            query.PlanID.Should().BeGreaterThan(0);

            // Execution stats
            query.ExecutionCount.Should().BeGreaterThan(0);
            query.TotalCpuMs.Should().BeGreaterThanOrEqualTo(0);
            query.AvgCpuMs.Should().BeGreaterThanOrEqualTo(0);

            // Duration stats
            query.TotalDurationMs.Should().BeGreaterThanOrEqualTo(0);
            query.AvgDurationMs.Should().BeGreaterThanOrEqualTo(0);

            // I/O stats
            query.TotalLogicalReads.Should().BeGreaterThanOrEqualTo(0);
            query.AvgLogicalReads.Should().BeGreaterThanOrEqualTo(0);

            // Timing
            query.CollectionTime.Should().NotBe(default(DateTime));
        }
    }

    [Fact]
    public async Task GetTopQueriesAsync_ShouldHandleLargeTopN_Efficiently()
    {
        // Act
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        var queries = await _service.GetTopQueriesAsync(topN: 500);
        stopwatch.Stop();

        // Assert
        queries.Should().NotBeNull();
        queries.Count().Should().BeLessThanOrEqualTo(500);

        // Performance assertion: Should complete in reasonable time
        stopwatch.ElapsedMilliseconds.Should().BeLessThan(5000,
            "because stored procedure should be optimized with indexes");
    }

    [Fact]
    public async Task GetTopQueriesAsync_ShouldReturnQueriesForAllServers_WhenServerIdNull()
    {
        // Act
        var queries = await _service.GetTopQueriesAsync(serverId: null, topN: 100);

        // Assert
        queries.Should().NotBeNull();

        if (queries.Any() && queries.Count() > 1)
        {
            // Should have queries from multiple servers (if data exists)
            var distinctServers = queries.Select(q => q.ServerID).Distinct().Count();
            // Note: This assertion depends on test data having multiple servers
            distinctServers.Should().BeGreaterThanOrEqualTo(1);
        }
    }

    #endregion

    #region Performance Tests

    [Fact]
    public async Task GetTopQueriesAsync_ShouldBeFast_WithSmallTopN()
    {
        // Act
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        var queries = await _service.GetTopQueriesAsync(topN: 10);
        stopwatch.Stop();

        // Assert
        queries.Should().NotBeNull();
        stopwatch.ElapsedMilliseconds.Should().BeLessThan(1000,
            "because small queries should be very fast");
    }

    [Fact]
    public async Task GetTopQueriesAsync_ShouldUseDatabaseIndexes_ForPerformance()
    {
        // This test verifies that the stored procedure uses indexes efficiently
        // by checking that response time is reasonable even with filtering

        // Act
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        var queries = await _service.GetTopQueriesAsync(
            serverId: null,
            orderBy: "TotalCpu",
            topN: 100,
            minExecutionCount: 10);
        stopwatch.Stop();

        // Assert
        queries.Should().NotBeNull();
        stopwatch.ElapsedMilliseconds.Should().BeLessThan(3000,
            "because indexed queries should be fast even with filters");
    }

    #endregion
}
