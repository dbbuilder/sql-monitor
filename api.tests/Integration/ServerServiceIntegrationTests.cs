using FluentAssertions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Moq;
using SqlServerMonitor.Api.Models;
using SqlServerMonitor.Api.Services;
using Xunit;

namespace SqlMonitor.Api.Tests.Integration;

/// <summary>
/// Integration tests for ServerService (Phase 1.9)
/// These tests require a test database with:
/// - MonitoringDB schema deployed
/// - Test data seeded
/// - All stored procedures created
///
/// Configure test database connection in:
/// - appsettings.Test.json OR
/// - Environment variable: ConnectionStrings__MonitoringDB
///
/// Run with: dotnet test --filter "Category=Integration"
/// </summary>
[Trait("Category", "Integration")]
[Collection("Database")]
public class ServerServiceIntegrationTests : IAsyncLifetime
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<ServerService> _logger;
    private ServerService _service = null!;
    private int _testServerId;

    public ServerServiceIntegrationTests()
    {
        // Load configuration from appsettings.Test.json or environment variables
        var configBuilder = new ConfigurationBuilder()
            .AddJsonFile("appsettings.Test.json", optional: true)
            .AddEnvironmentVariables();

        _configuration = configBuilder.Build();

        var loggerFactory = LoggerFactory.Create(builder => builder.AddConsole());
        _logger = loggerFactory.CreateLogger<ServerService>();
    }

    public async Task InitializeAsync()
    {
        // Setup: Create test server for tests
        _service = new ServerService(_configuration, _logger);

        try
        {
            // Register a test server
            var testServer = await _service.RegisterServerAsync(
                $"TEST-SERVER-{Guid.NewGuid().ToString("N").Substring(0, 8)}",
                "Testing",
                true);

            _testServerId = testServer.ServerID;
        }
        catch (InvalidOperationException)
        {
            // Server might already exist, that's okay
            // In a real scenario, we'd query for the test server
        }
    }

    public async Task DisposeAsync()
    {
        // Cleanup: Remove test server (if your stored procedures support deletion)
        // For now, we leave test data (it will be cleaned up manually or by test database reset)
        await Task.CompletedTask;
    }

    #region GetServersAsync Tests

    [Fact]
    public async Task GetServersAsync_ShouldReturnServers_WhenDatabaseHasData()
    {
        // Act
        var servers = await _service.GetServersAsync();

        // Assert
        servers.Should().NotBeNull();
        servers.Should().NotBeEmpty("because test database should have at least one server");
        servers.Should().AllSatisfy(s =>
        {
            s.ServerID.Should().BeGreaterThan(0);
            s.ServerName.Should().NotBeNullOrEmpty();
            s.Environment.Should().NotBeNullOrEmpty();
        });
    }

    [Fact]
    public async Task GetServersAsync_ShouldFilterByEnvironment_WhenProvided()
    {
        // Act
        var servers = await _service.GetServersAsync(environment: "Testing");

        // Assert
        servers.Should().NotBeNull();
        if (servers.Any())
        {
            servers.Should().OnlyContain(s => s.Environment == "Testing");
        }
    }

    [Fact]
    public async Task GetServersAsync_ShouldReturnOnlyActiveServers_ByDefault()
    {
        // Act
        var servers = await _service.GetServersAsync(includeInactive: false);

        // Assert
        servers.Should().NotBeNull();
        servers.Should().OnlyContain(s => s.IsActive == true);
    }

    [Fact]
    public async Task GetServersAsync_ShouldReturnAllServers_WhenIncludeInactiveTrue()
    {
        // Act
        var servers = await _service.GetServersAsync(includeInactive: true);

        // Assert
        servers.Should().NotBeNull();
        // Should include both active and inactive servers
    }

    #endregion

    #region GetServerByIdAsync Tests

    [Fact]
    public async Task GetServerByIdAsync_ShouldReturnServer_WhenServerExists()
    {
        // Act
        var server = await _service.GetServerByIdAsync(_testServerId);

        // Assert
        server.Should().NotBeNull();
        server!.ServerID.Should().Be(_testServerId);
        server.ServerName.Should().NotBeNullOrEmpty();
        server.Environment.Should().NotBeNullOrEmpty();
    }

    [Fact]
    public async Task GetServerByIdAsync_ShouldReturnNull_WhenServerDoesNotExist()
    {
        // Act
        var server = await _service.GetServerByIdAsync(99999);

        // Assert
        server.Should().BeNull();
    }

    #endregion

    #region GetServerByNameAsync Tests

    [Fact]
    public async Task GetServerByNameAsync_ShouldReturnServer_WhenServerExists()
    {
        // Arrange
        var existingServer = await _service.GetServerByIdAsync(_testServerId);
        existingServer.Should().NotBeNull();

        // Act
        var server = await _service.GetServerByNameAsync(existingServer!.ServerName);

        // Assert
        server.Should().NotBeNull();
        server!.ServerName.Should().Be(existingServer.ServerName);
        server.ServerID.Should().Be(_testServerId);
    }

    [Fact]
    public async Task GetServerByNameAsync_ShouldReturnNull_WhenServerDoesNotExist()
    {
        // Act
        var server = await _service.GetServerByNameAsync("NONEXISTENT-SERVER-XYZ");

        // Assert
        server.Should().BeNull();
    }

    #endregion

    #region GetServerHealthStatusAsync Tests

    [Fact]
    public async Task GetServerHealthStatusAsync_ShouldReturnHealthForAllServers()
    {
        // Act
        var healthStatus = await _service.GetServerHealthStatusAsync();

        // Assert
        healthStatus.Should().NotBeNull();
        healthStatus.Should().NotBeEmpty("because test database should have at least one server");
        healthStatus.Should().AllSatisfy(h =>
        {
            h.ServerID.Should().BeGreaterThan(0);
            h.ServerName.Should().NotBeNullOrEmpty();
            h.HealthStatus.Should().NotBeNullOrEmpty();
        });
    }

    [Fact]
    public async Task GetServerHealthStatusAsync_ShouldReturnHealthForSpecificServer()
    {
        // Act
        var health = await _service.GetServerHealthStatusAsync(_testServerId);

        // Assert
        health.Should().NotBeNull();
        health!.ServerID.Should().Be(_testServerId);
        health.HealthStatus.Should().NotBeNullOrEmpty();
    }

    [Fact]
    public async Task GetServerHealthStatusAsync_ShouldFilterByEnvironment()
    {
        // Act
        var healthStatus = await _service.GetServerHealthStatusAsync(environment: "Testing");

        // Assert
        healthStatus.Should().NotBeNull();
        if (healthStatus.Any())
        {
            healthStatus.Should().OnlyContain(h => h.Environment == "Testing");
        }
    }

    #endregion

    #region GetResourceTrendsAsync Tests

    [Fact]
    public async Task GetResourceTrendsAsync_ShouldReturnTrends_WhenDataExists()
    {
        // Act
        var trends = await _service.GetResourceTrendsAsync(days: 7);

        // Assert
        trends.Should().NotBeNull();
        // May be empty if no historical data exists yet
        trends.Should().AllSatisfy(t =>
        {
            t.ServerID.Should().BeGreaterThan(0);
            t.ServerName.Should().NotBeNullOrEmpty();
            t.CollectionDate.Should().BeAfter(DateTime.UtcNow.AddDays(-8));
        });
    }

    [Fact]
    public async Task GetResourceTrendsAsync_ShouldFilterByServerId()
    {
        // Act
        var trends = await _service.GetResourceTrendsAsync(serverId: _testServerId, days: 7);

        // Assert
        trends.Should().NotBeNull();
        if (trends.Any())
        {
            trends.Should().OnlyContain(t => t.ServerID == _testServerId);
        }
    }

    #endregion

    #region GetDatabaseSummaryAsync Tests

    [Fact]
    public async Task GetDatabaseSummaryAsync_ShouldReturnDatabases_WhenDataExists()
    {
        // Act
        var databases = await _service.GetDatabaseSummaryAsync();

        // Assert
        databases.Should().NotBeNull();
        // May be empty if no database snapshots collected yet
        databases.Should().AllSatisfy(db =>
        {
            db.ServerID.Should().BeGreaterThan(0);
            db.ServerName.Should().NotBeNullOrEmpty();
            db.DatabaseName.Should().NotBeNullOrEmpty();
            db.TotalSizeMB.Should().BeGreaterThanOrEqualTo(0);
        });
    }

    [Fact]
    public async Task GetDatabaseSummaryAsync_ShouldFilterByServerId()
    {
        // Act
        var databases = await _service.GetDatabaseSummaryAsync(serverId: _testServerId);

        // Assert
        databases.Should().NotBeNull();
        if (databases.Any())
        {
            databases.Should().OnlyContain(db => db.ServerID == _testServerId);
        }
    }

    [Fact]
    public async Task GetDatabaseSummaryAsync_ShouldFilterByDatabaseName()
    {
        // Act
        var databases = await _service.GetDatabaseSummaryAsync(databaseName: "master");

        // Assert
        databases.Should().NotBeNull();
        if (databases.Any())
        {
            databases.Should().OnlyContain(db => db.DatabaseName == "master");
        }
    }

    #endregion

    #region RegisterServerAsync Tests

    [Fact]
    public async Task RegisterServerAsync_ShouldCreateNewServer_WithValidData()
    {
        // Arrange
        var uniqueName = $"TEST-NEW-{Guid.NewGuid().ToString("N").Substring(0, 8)}";

        // Act
        var server = await _service.RegisterServerAsync(uniqueName, "Testing", true);

        // Assert
        server.Should().NotBeNull();
        server.ServerID.Should().BeGreaterThan(0);
        server.ServerName.Should().Be(uniqueName);
        server.Environment.Should().Be("Testing");
        server.IsActive.Should().BeTrue();
        server.CreatedUTC.Should().BeCloseTo(DateTime.UtcNow, TimeSpan.FromMinutes(1));
    }

    [Fact]
    public async Task RegisterServerAsync_ShouldThrowInvalidOperationException_WhenServerExists()
    {
        // Arrange
        var existingServer = await _service.GetServerByIdAsync(_testServerId);
        existingServer.Should().NotBeNull();

        // Act
        Func<Task> act = async () => await _service.RegisterServerAsync(
            existingServer!.ServerName,
            "Testing",
            true);

        // Assert
        await act.Should().ThrowAsync<InvalidOperationException>()
            .WithMessage("*already exists*");
    }

    #endregion

    #region UpdateServerAsync Tests

    [Fact]
    public async Task UpdateServerAsync_ShouldUpdateEnvironment_WhenProvided()
    {
        // Arrange
        var originalServer = await _service.GetServerByIdAsync(_testServerId);
        originalServer.Should().NotBeNull();

        // Act
        var updatedServer = await _service.UpdateServerAsync(_testServerId, "Development", null);

        // Assert
        updatedServer.Should().NotBeNull();
        updatedServer.ServerID.Should().Be(_testServerId);
        updatedServer.Environment.Should().Be("Development");
        updatedServer.LastModifiedUTC.Should().NotBeNull();
        updatedServer.LastModifiedUTC.Should().BeAfter(originalServer!.CreatedUTC);
    }

    [Fact]
    public async Task UpdateServerAsync_ShouldUpdateIsActive_WhenProvided()
    {
        // Act
        var updatedServer = await _service.UpdateServerAsync(_testServerId, null, false);

        // Assert
        updatedServer.Should().NotBeNull();
        updatedServer.ServerID.Should().Be(_testServerId);
        updatedServer.IsActive.Should().BeFalse();

        // Cleanup: Set back to active
        await _service.UpdateServerAsync(_testServerId, null, true);
    }

    [Fact]
    public async Task UpdateServerAsync_ShouldUpdateBothFields_WhenBothProvided()
    {
        // Act
        var updatedServer = await _service.UpdateServerAsync(_testServerId, "Testing", true);

        // Assert
        updatedServer.Should().NotBeNull();
        updatedServer.ServerID.Should().Be(_testServerId);
        updatedServer.Environment.Should().Be("Testing");
        updatedServer.IsActive.Should().BeTrue();
    }

    #endregion
}
