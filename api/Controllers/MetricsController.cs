using Microsoft.AspNetCore.Mvc;
using SqlMonitor.Api.Models;
using SqlMonitor.Api.Services;

namespace SqlMonitor.Api.Controllers;

/// <summary>
/// Controller for managing performance metrics
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class MetricsController : ControllerBase
{
    private readonly ISqlService _sqlService;
    private readonly ILogger<MetricsController> _logger;

    public MetricsController(ISqlService sqlService, ILogger<MetricsController>? logger = null)
    {
        _sqlService = sqlService;
        _logger = logger ?? new LoggerFactory().CreateLogger<MetricsController>();
    }

    /// <summary>
    /// Gets performance metrics for a specific server
    /// </summary>
    /// <param name="serverID">Server ID (required)</param>
    /// <param name="startTime">Start of time range (optional)</param>
    /// <param name="endTime">End of time range (optional)</param>
    /// <param name="metricCategory">Metric category filter (optional)</param>
    /// <param name="metricName">Metric name filter (optional)</param>
    /// <returns>List of performance metrics</returns>
    [HttpGet]
    [ProducesResponseType(typeof(IEnumerable<PerformanceMetric>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<ActionResult<IEnumerable<PerformanceMetric>>> GetMetrics(
        [FromQuery] int serverID,
        [FromQuery] DateTime? startTime = null,
        [FromQuery] DateTime? endTime = null,
        [FromQuery] string? metricCategory = null,
        [FromQuery] string? metricName = null)
    {
        if (serverID <= 0)
        {
            return BadRequest(new { error = "ServerID must be greater than 0" });
        }

        try
        {
            var metrics = await _sqlService.GetMetricsAsync(
                serverID,
                startTime,
                endTime,
                metricCategory,
                metricName);

            return Ok(metrics);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving metrics for ServerID {ServerID}", serverID);
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Inserts a new performance metric
    /// </summary>
    /// <param name="request">Metric data</param>
    /// <returns>Created result</returns>
    [HttpPost]
    [ProducesResponseType(StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> InsertMetric([FromBody] InsertMetricRequest request)
    {
        if (request == null)
        {
            return BadRequest(new { error = "Request body is required" });
        }

        if (request.ServerID <= 0)
        {
            return BadRequest(new { error = "ServerID must be greater than 0" });
        }

        try
        {
            await _sqlService.InsertMetricAsync(request);

            return CreatedAtAction(
                nameof(GetMetrics),
                new { serverID = request.ServerID },
                new { message = "Metric inserted successfully" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error inserting metric for ServerID {ServerID}", request.ServerID);
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Trigger on-demand metrics collection (for Grafana 30-second refresh)
    /// </summary>
    /// <param name="serverId">Server ID to collect metrics for (default: 1)</param>
    /// <param name="includeAdvanced">Include advanced metrics (blocking, index analysis, etc.) - slower</param>
    /// <returns>Collection status</returns>
    [HttpPost("collect")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<ActionResult> TriggerCollection(
        [FromQuery] int serverId = 1,
        [FromQuery] bool includeAdvanced = false)
    {
        try
        {
            var startTime = DateTime.UtcNow;

            _logger.LogInformation(
                "Triggering metrics collection for server {ServerId}, includeAdvanced: {IncludeAdvanced}",
                serverId, includeAdvanced);

            // Call the main collection procedure
            await _sqlService.CollectMetricsAsync(serverId, includeAdvanced);

            var duration = (DateTime.UtcNow - startTime).TotalMilliseconds;

            _logger.LogInformation(
                "Metrics collection completed in {Duration}ms for server {ServerId}",
                duration, serverId);

            return Ok(new
            {
                success = true,
                serverId = serverId,
                includeAdvanced = includeAdvanced,
                durationMs = duration,
                collectedAt = DateTime.UtcNow,
                message = includeAdvanced
                    ? "Complete metrics collection (server + drill-down + advanced) completed successfully"
                    : "Fast metrics collection (server + drill-down) completed successfully"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error collecting metrics for server {ServerId}", serverId);
            return StatusCode(500, new
            {
                success = false,
                error = ex.Message,
                serverId = serverId
            });
        }
    }

    /// <summary>
    /// Get last collection time for a server
    /// </summary>
    /// <param name="serverId">Server ID</param>
    /// <returns>Last collection timestamp</returns>
    [HttpGet("last-collection/{serverId}")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<ActionResult> GetLastCollectionTime(int serverId)
    {
        try
        {
            var lastCollection = await _sqlService.GetLastCollectionTimeAsync(serverId);

            if (lastCollection == null)
            {
                return NotFound(new
                {
                    serverId = serverId,
                    message = "No collections found for this server"
                });
            }

            var timeSinceCollection = DateTime.UtcNow - lastCollection.Value;

            return Ok(new
            {
                serverId = serverId,
                lastCollectionTime = lastCollection.Value,
                secondsSinceCollection = timeSinceCollection.TotalSeconds,
                isStale = timeSinceCollection.TotalMinutes > 10 // Flag if no collection in 10 minutes
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving last collection time for server {ServerId}", serverId);
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Health check endpoint to verify metrics collection is working
    /// </summary>
    [HttpGet("health")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status503ServiceUnavailable)]
    public async Task<ActionResult> GetHealthStatus()
    {
        try
        {
            var lastCollection = await _sqlService.GetLastCollectionTimeAsync(1);

            if (lastCollection == null)
            {
                return StatusCode(503, new
                {
                    status = "Unhealthy",
                    reason = "No metrics have been collected yet",
                    recommendation = "Run: POST /api/metrics/collect to start collection"
                });
            }

            var timeSinceCollection = DateTime.UtcNow - lastCollection.Value;
            var isHealthy = timeSinceCollection.TotalMinutes < 10;

            if (!isHealthy)
            {
                return StatusCode(503, new
                {
                    status = "Degraded",
                    lastCollectionTime = lastCollection.Value,
                    minutesSinceCollection = timeSinceCollection.TotalMinutes,
                    reason = "No recent collections (expected every 5 minutes)",
                    recommendation = "Check SQL Agent job status"
                });
            }

            return Ok(new
            {
                status = "Healthy",
                lastCollectionTime = lastCollection.Value,
                secondsSinceCollection = timeSinceCollection.TotalSeconds,
                nextExpectedCollection = lastCollection.Value.AddMinutes(5)
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error checking metrics health");
            return StatusCode(503, new
            {
                status = "Error",
                error = ex.Message
            });
        }
    }
}
