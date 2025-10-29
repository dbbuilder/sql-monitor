using SqlServerMonitor.Api.Models;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace SqlServerMonitor.Api.Services
{
    /// <summary>
    /// Service interface for query performance analysis
    /// Phase 1.9: Cross-server query monitoring
    /// </summary>
    public interface IQueryService
    {
        /// <summary>
        /// Get top N queries across servers
        /// </summary>
        Task<IEnumerable<TopQueryModel>> GetTopQueriesAsync(
            int? serverId = null,
            string orderBy = "TotalCpu",
            int topN = 50,
            int minExecutionCount = 10);
    }
}
