using Dapper;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using SqlServerMonitor.Api.Models;
using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Threading.Tasks;

namespace SqlServerMonitor.Api.Services
{
    /// <summary>
    /// Service implementation for server management and monitoring
    /// Uses Dapper for lightweight data access (stored procedure only pattern)
    /// Phase 1.9: Multi-server support
    /// </summary>
    public class ServerService : IServerService
    {
        private readonly string _connectionString;
        private readonly ILogger<ServerService> _logger;

        public ServerService(IConfiguration configuration, ILogger<ServerService> logger)
        {
            _connectionString = configuration.GetConnectionString("MonitoringDB")
                ?? throw new ArgumentNullException(nameof(configuration), "MonitoringDB connection string not found");
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        public async Task<IEnumerable<ServerModel>> GetServersAsync(string? environment = null, bool includeInactive = false)
        {
            try
            {
                using var connection = new SqlConnection(_connectionString);

                // Direct table query (simple enough not to need SP)
                var sql = @"
                    SELECT ServerID, ServerName, Environment, IsActive, CreatedUTC, LastModifiedUTC
                    FROM dbo.Servers
                    WHERE (@Environment IS NULL OR Environment = @Environment)
                      AND (@IncludeInactive = 1 OR IsActive = 1)
                    ORDER BY ServerName";

                var servers = await connection.QueryAsync<ServerModel>(sql, new
                {
                    Environment = environment,
                    IncludeInactive = includeInactive
                });

                _logger.LogInformation("Retrieved {Count} servers", servers.Count());
                return servers;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving servers");
                throw;
            }
        }

        public async Task<ServerModel?> GetServerByIdAsync(int serverId)
        {
            try
            {
                using var connection = new SqlConnection(_connectionString);

                var sql = @"
                    SELECT ServerID, ServerName, Environment, IsActive, CreatedUTC, LastModifiedUTC
                    FROM dbo.Servers
                    WHERE ServerID = @ServerId";

                var server = await connection.QuerySingleOrDefaultAsync<ServerModel>(sql, new { ServerId = serverId });

                if (server != null)
                {
                    _logger.LogInformation("Retrieved server {ServerId}: {ServerName}", serverId, server.ServerName);
                }

                return server;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving server {ServerId}", serverId);
                throw;
            }
        }

        public async Task<ServerModel?> GetServerByNameAsync(string serverName)
        {
            try
            {
                using var connection = new SqlConnection(_connectionString);

                var sql = @"
                    SELECT ServerID, ServerName, Environment, IsActive, CreatedUTC, LastModifiedUTC
                    FROM dbo.Servers
                    WHERE ServerName = @ServerName";

                var server = await connection.QuerySingleOrDefaultAsync<ServerModel>(sql, new { ServerName = serverName });

                return server;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving server by name: {ServerName}", serverName);
                throw;
            }
        }

        public async Task<IEnumerable<ServerHealthModel>> GetServerHealthStatusAsync(
            string? environment = null,
            bool includeInactive = false)
        {
            try
            {
                using var connection = new SqlConnection(_connectionString);

                // Call stored procedure from Days 4-5
                var healthStatus = await connection.QueryAsync<ServerHealthModel>(
                    "dbo.usp_GetServerHealthStatus",
                    new
                    {
                        ServerID = (int?)null,  // NULL = all servers
                        Environment = environment,
                        IncludeInactive = includeInactive
                    },
                    commandType: CommandType.StoredProcedure);

                _logger.LogInformation(
                    "Retrieved health status for {Count} servers (Environment: {Environment})",
                    healthStatus.Count(),
                    environment ?? "All");

                return healthStatus;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving server health status");
                throw;
            }
        }

        public async Task<ServerHealthModel?> GetServerHealthStatusAsync(int serverId)
        {
            try
            {
                using var connection = new SqlConnection(_connectionString);

                // Call stored procedure with specific ServerID
                var healthStatus = await connection.QueryAsync<ServerHealthModel>(
                    "dbo.usp_GetServerHealthStatus",
                    new
                    {
                        ServerID = serverId,
                        Environment = (string?)null,
                        IncludeInactive = true  // Include even if inactive
                    },
                    commandType: CommandType.StoredProcedure);

                var result = healthStatus.FirstOrDefault();

                if (result != null)
                {
                    _logger.LogInformation(
                        "Retrieved health status for server {ServerId}: {HealthStatus}",
                        serverId,
                        result.HealthStatus);
                }

                return result;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving health status for server {ServerId}", serverId);
                throw;
            }
        }

        public async Task<IEnumerable<ResourceTrendModel>> GetResourceTrendsAsync(int? serverId = null, int days = 7)
        {
            try
            {
                using var connection = new SqlConnection(_connectionString);

                // Call stored procedure from Days 4-5
                var trends = await connection.QueryAsync<ResourceTrendModel>(
                    "dbo.usp_GetResourceTrends",
                    new
                    {
                        ServerID = serverId,
                        Days = days
                    },
                    commandType: CommandType.StoredProcedure);

                _logger.LogInformation(
                    "Retrieved resource trends for {Count} days (ServerID: {ServerId})",
                    days,
                    serverId?.ToString() ?? "All");

                return trends;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving resource trends");
                throw;
            }
        }

        public async Task<IEnumerable<DatabaseSummaryModel>> GetDatabaseSummaryAsync(
            int? serverId = null,
            string? databaseName = null)
        {
            try
            {
                using var connection = new SqlConnection(_connectionString);

                // Call stored procedure from Days 4-5
                var databases = await connection.QueryAsync<DatabaseSummaryModel>(
                    "dbo.usp_GetDatabaseSummary",
                    new
                    {
                        ServerID = serverId,
                        DatabaseName = databaseName
                    },
                    commandType: CommandType.StoredProcedure);

                _logger.LogInformation(
                    "Retrieved database summary: {Count} databases (ServerID: {ServerId}, Database: {DatabaseName})",
                    databases.Count(),
                    serverId?.ToString() ?? "All",
                    databaseName ?? "All");

                return databases;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving database summary");
                throw;
            }
        }

        public async Task<ServerModel> RegisterServerAsync(string serverName, string environment, bool isActive)
        {
            try
            {
                using var connection = new SqlConnection(_connectionString);

                var sql = @"
                    INSERT INTO dbo.Servers (ServerName, Environment, IsActive)
                    VALUES (@ServerName, @Environment, @IsActive);

                    SELECT ServerID, ServerName, Environment, IsActive, CreatedUTC, LastModifiedUTC
                    FROM dbo.Servers
                    WHERE ServerID = SCOPE_IDENTITY();";

                var server = await connection.QuerySingleAsync<ServerModel>(sql, new
                {
                    ServerName = serverName,
                    Environment = environment,
                    IsActive = isActive
                });

                _logger.LogInformation(
                    "Registered new server {ServerName} (ServerID: {ServerId}, Environment: {Environment})",
                    serverName,
                    server.ServerID,
                    environment);

                return server;
            }
            catch (SqlException ex) when (ex.Number == 2627) // Unique constraint violation
            {
                _logger.LogWarning("Server {ServerName} already exists", serverName);
                throw new InvalidOperationException($"Server '{serverName}' already exists", ex);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error registering server {ServerName}", serverName);
                throw;
            }
        }

        public async Task<ServerModel> UpdateServerAsync(int serverId, string? environment, bool? isActive)
        {
            try
            {
                using var connection = new SqlConnection(_connectionString);

                var sql = @"
                    UPDATE dbo.Servers
                    SET
                        Environment = COALESCE(@Environment, Environment),
                        IsActive = COALESCE(@IsActive, IsActive),
                        LastModifiedUTC = SYSUTCDATETIME()
                    WHERE ServerID = @ServerId;

                    SELECT ServerID, ServerName, Environment, IsActive, CreatedUTC, LastModifiedUTC
                    FROM dbo.Servers
                    WHERE ServerID = @ServerId;";

                var server = await connection.QuerySingleAsync<ServerModel>(sql, new
                {
                    ServerId = serverId,
                    Environment = environment,
                    IsActive = isActive
                });

                _logger.LogInformation("Updated server {ServerId}: {ServerName}", serverId, server.ServerName);

                return server;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating server {ServerId}", serverId);
                throw;
            }
        }
    }
}
