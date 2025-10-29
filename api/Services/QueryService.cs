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
    /// Service implementation for query performance analysis
    /// Uses Dapper for lightweight data access (stored procedure only pattern)
    /// Phase 1.9: Cross-server query monitoring
    /// </summary>
    public class QueryService : IQueryService
    {
        private readonly string _connectionString;
        private readonly ILogger<QueryService> _logger;

        public QueryService(IConfiguration configuration, ILogger<QueryService> logger)
        {
            _connectionString = configuration.GetConnectionString("MonitoringDB")
                ?? throw new ArgumentNullException(nameof(configuration), "MonitoringDB connection string not found");
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        public async Task<IEnumerable<TopQueryModel>> GetTopQueriesAsync(
            int? serverId = null,
            string orderBy = "TotalCpu",
            int topN = 50,
            int minExecutionCount = 10)
        {
            try
            {
                using var connection = new SqlConnection(_connectionString);

                // Call stored procedure from Days 4-5
                var queries = await connection.QueryAsync<TopQueryModel>(
                    "dbo.usp_GetTopQueries",
                    new
                    {
                        ServerID = serverId,
                        OrderBy = orderBy,
                        TopN = topN,
                        MinExecutionCount = minExecutionCount
                    },
                    commandType: CommandType.StoredProcedure);

                _logger.LogInformation(
                    "Retrieved top {TopN} queries (OrderBy: {OrderBy}, ServerID: {ServerId}, MinExecCount: {MinExecCount})",
                    topN,
                    orderBy,
                    serverId?.ToString() ?? "All",
                    minExecutionCount);

                return queries;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving top queries");
                throw;
            }
        }
    }
}
