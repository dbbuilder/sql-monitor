using Microsoft.AspNetCore.Mvc;
using SqlServerMonitor.Api.Models;
using SqlServerMonitor.Api.Services;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace SqlServerMonitor.Api.Controllers
{
    /// <summary>
    /// API controller for query performance analysis
    /// Phase 1.9: Cross-server query monitoring
    /// </summary>
    [ApiController]
    [Route("api/[controller]")]
    [Produces("application/json")]
    public class QueriesController : ControllerBase
    {
        private readonly IQueryService _queryService;
        private readonly ILogger<QueriesController> _logger;

        public QueriesController(IQueryService queryService, ILogger<QueriesController> logger)
        {
            _queryService = queryService ?? throw new ArgumentNullException(nameof(queryService));
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        /// <summary>
        /// Get top N queries across all servers
        /// </summary>
        /// <param name="serverId">Optional: Filter by server ID</param>
        /// <param name="orderBy">Order by: TotalCpu, AvgCpu, TotalReads, AvgDuration (default: TotalCpu)</param>
        /// <param name="topN">Number of queries to return (default: 50, max: 500)</param>
        /// <param name="minExecutionCount">Minimum execution count to include (default: 10)</param>
        /// <returns>Top N queries with performance metrics</returns>
        /// <response code="200">Returns the top queries</response>
        /// <response code="400">Invalid parameters</response>
        /// <response code="500">Internal server error</response>
        [HttpGet("top")]
        [ProducesResponseType(typeof(IEnumerable<TopQueryModel>), StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status400BadRequest)]
        [ProducesResponseType(StatusCodes.Status500InternalServerError)]
        public async Task<ActionResult<IEnumerable<TopQueryModel>>> GetTopQueries(
            [FromQuery] int? serverId = null,
            [FromQuery] string orderBy = "TotalCpu",
            [FromQuery] int topN = 50,
            [FromQuery] int minExecutionCount = 10)
        {
            try
            {
                // Validate parameters
                if (topN < 1 || topN > 500)
                {
                    return BadRequest(new { error = "topN parameter must be between 1 and 500" });
                }

                if (minExecutionCount < 0)
                {
                    return BadRequest(new { error = "minExecutionCount must be >= 0" });
                }

                var validOrderByValues = new[] { "TotalCpu", "AvgCpu", "TotalReads", "AvgDuration" };
                if (!validOrderByValues.Contains(orderBy, StringComparer.OrdinalIgnoreCase))
                {
                    return BadRequest(new
                    {
                        error = $"Invalid orderBy value. Valid values: {string.Join(", ", validOrderByValues)}"
                    });
                }

                _logger.LogInformation(
                    "Getting top {TopN} queries (OrderBy: {OrderBy}, ServerID: {ServerId}, MinExecCount: {MinExecCount})",
                    topN,
                    orderBy,
                    serverId?.ToString() ?? "All",
                    minExecutionCount);

                var queries = await _queryService.GetTopQueriesAsync(serverId, orderBy, topN, minExecutionCount);

                return Ok(queries);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving top queries");
                return StatusCode(500, new { error = "Failed to retrieve top queries", details = ex.Message });
            }
        }
    }
}
