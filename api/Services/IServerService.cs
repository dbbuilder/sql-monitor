using SqlServerMonitor.Api.Models;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace SqlServerMonitor.Api.Services
{
    /// <summary>
    /// Service interface for server management and monitoring
    /// Phase 1.9: Multi-server support
    /// </summary>
    public interface IServerService
    {
        /// <summary>
        /// Get all servers
        /// </summary>
        Task<IEnumerable<ServerModel>> GetServersAsync(string? environment = null, bool includeInactive = false);

        /// <summary>
        /// Get server by ID
        /// </summary>
        Task<ServerModel?> GetServerByIdAsync(int serverId);

        /// <summary>
        /// Get server by name
        /// </summary>
        Task<ServerModel?> GetServerByNameAsync(string serverName);

        /// <summary>
        /// Get health status for all servers
        /// </summary>
        Task<IEnumerable<ServerHealthModel>> GetServerHealthStatusAsync(string? environment = null, bool includeInactive = false);

        /// <summary>
        /// Get health status for specific server
        /// </summary>
        Task<ServerHealthModel?> GetServerHealthStatusAsync(int serverId);

        /// <summary>
        /// Get resource trends for server
        /// </summary>
        Task<IEnumerable<ResourceTrendModel>> GetResourceTrendsAsync(int? serverId = null, int days = 7);

        /// <summary>
        /// Get database summary for server
        /// </summary>
        Task<IEnumerable<DatabaseSummaryModel>> GetDatabaseSummaryAsync(int? serverId = null, string? databaseName = null);

        /// <summary>
        /// Register new server
        /// </summary>
        Task<ServerModel> RegisterServerAsync(string serverName, string environment, bool isActive);

        /// <summary>
        /// Update server details
        /// </summary>
        Task<ServerModel> UpdateServerAsync(int serverId, string? environment, bool? isActive);
    }
}
