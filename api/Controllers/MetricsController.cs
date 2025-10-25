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
}
