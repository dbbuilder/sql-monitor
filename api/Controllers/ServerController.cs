using Microsoft.AspNetCore.Mvc;
using SqlMonitor.Api.Models;
using SqlMonitor.Api.Services;

namespace SqlMonitor.Api.Controllers;

/// <summary>
/// Controller for managing monitored SQL Server instances
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class ServerController : ControllerBase
{
    private readonly ISqlService _sqlService;
    private readonly ILogger<ServerController> _logger;

    public ServerController(ISqlService sqlService, ILogger<ServerController>? logger = null)
    {
        _sqlService = sqlService;
        _logger = logger ?? new LoggerFactory().CreateLogger<ServerController>();
    }

    /// <summary>
    /// Gets list of monitored SQL Server instances
    /// </summary>
    /// <param name="isActive">Filter by active status (optional)</param>
    /// <param name="environment">Filter by environment (optional)</param>
    /// <returns>List of servers</returns>
    [HttpGet]
    [ProducesResponseType(typeof(IEnumerable<Server>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<ActionResult<IEnumerable<Server>>> GetServers(
        [FromQuery] bool? isActive = null,
        [FromQuery] string? environment = null)
    {
        try
        {
            var servers = await _sqlService.GetServersAsync(isActive, environment);
            return Ok(servers);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving servers");
            return StatusCode(500, new { error = ex.Message });
        }
    }
}
