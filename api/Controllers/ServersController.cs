using Microsoft.AspNetCore.Mvc;
using SqlServerMonitor.Api.Models;
using SqlServerMonitor.Api.Services;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace SqlServerMonitor.Api.Controllers
{
    /// <summary>
    /// API controller for server management and health monitoring
    /// Phase 1.9: Multi-server support
    /// </summary>
    [ApiController]
    [Route("api/[controller]")]
    [Produces("application/json")]
    public class ServersController : ControllerBase
    {
        private readonly IServerService _serverService;
        private readonly ILogger<ServersController> _logger;

        public ServersController(IServerService serverService, ILogger<ServersController> logger)
        {
            _serverService = serverService ?? throw new ArgumentNullException(nameof(serverService));
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        /// <summary>
        /// Get all registered servers
        /// </summary>
        /// <param name="environment">Filter by environment (Production, Development, Test)</param>
        /// <param name="includeInactive">Include inactive servers</param>
        /// <returns>List of registered servers</returns>
        /// <response code="200">Returns the list of servers</response>
        /// <response code="500">Internal server error</response>
        [HttpGet]
        [ProducesResponseType(typeof(IEnumerable<ServerModel>), StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status500InternalServerError)]
        public async Task<ActionResult<IEnumerable<ServerModel>>> GetServers(
            [FromQuery] string? environment = null,
            [FromQuery] bool includeInactive = false)
        {
            try
            {
                _logger.LogInformation(
                    "Getting servers list (Environment: {Environment}, IncludeInactive: {IncludeInactive})",
                    environment ?? "All",
                    includeInactive);

                var servers = await _serverService.GetServersAsync(environment, includeInactive);

                return Ok(servers);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving servers");
                return StatusCode(500, new { error = "Failed to retrieve servers", details = ex.Message });
            }
        }

        /// <summary>
        /// Get server by ID
        /// </summary>
        /// <param name="id">Server ID</param>
        /// <returns>Server details</returns>
        /// <response code="200">Returns the server</response>
        /// <response code="404">Server not found</response>
        /// <response code="500">Internal server error</response>
        [HttpGet("{id}")]
        [ProducesResponseType(typeof(ServerModel), StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        [ProducesResponseType(StatusCodes.Status500InternalServerError)]
        public async Task<ActionResult<ServerModel>> GetServer(int id)
        {
            try
            {
                _logger.LogInformation("Getting server with ID: {ServerId}", id);

                var server = await _serverService.GetServerByIdAsync(id);

                if (server == null)
                {
                    return NotFound(new { error = $"Server with ID {id} not found" });
                }

                return Ok(server);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving server {ServerId}", id);
                return StatusCode(500, new { error = "Failed to retrieve server", details = ex.Message });
            }
        }

        /// <summary>
        /// Get health status for all servers
        /// </summary>
        /// <param name="environment">Filter by environment</param>
        /// <param name="includeInactive">Include inactive servers</param>
        /// <returns>Health status for all servers with 24-hour averages</returns>
        /// <response code="200">Returns health status for all servers</response>
        /// <response code="500">Internal server error</response>
        [HttpGet("health")]
        [ProducesResponseType(typeof(IEnumerable<ServerHealthModel>), StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status500InternalServerError)]
        public async Task<ActionResult<IEnumerable<ServerHealthModel>>> GetServersHealth(
            [FromQuery] string? environment = null,
            [FromQuery] bool includeInactive = false)
        {
            try
            {
                _logger.LogInformation(
                    "Getting server health status (Environment: {Environment}, IncludeInactive: {IncludeInactive})",
                    environment ?? "All",
                    includeInactive);

                var healthStatus = await _serverService.GetServerHealthStatusAsync(environment, includeInactive);

                return Ok(healthStatus);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving server health status");
                return StatusCode(500, new { error = "Failed to retrieve server health", details = ex.Message });
            }
        }

        /// <summary>
        /// Get health status for a specific server
        /// </summary>
        /// <param name="id">Server ID</param>
        /// <returns>Health status with 24-hour averages</returns>
        /// <response code="200">Returns health status</response>
        /// <response code="404">Server not found</response>
        /// <response code="500">Internal server error</response>
        [HttpGet("{id}/health")]
        [ProducesResponseType(typeof(ServerHealthModel), StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        [ProducesResponseType(StatusCodes.Status500InternalServerError)]
        public async Task<ActionResult<ServerHealthModel>> GetServerHealth(int id)
        {
            try
            {
                _logger.LogInformation("Getting health status for server ID: {ServerId}", id);

                var healthStatus = await _serverService.GetServerHealthStatusAsync(id);

                if (healthStatus == null)
                {
                    return NotFound(new { error = $"Server with ID {id} not found" });
                }

                return Ok(healthStatus);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving health status for server {ServerId}", id);
                return StatusCode(500, new { error = "Failed to retrieve server health", details = ex.Message });
            }
        }

        /// <summary>
        /// Get resource utilization trends for a server
        /// </summary>
        /// <param name="id">Server ID</param>
        /// <param name="days">Number of days of history (default: 7)</param>
        /// <returns>Daily resource trends (CPU, sessions, blocking)</returns>
        /// <response code="200">Returns resource trends</response>
        /// <response code="404">Server not found</response>
        /// <response code="500">Internal server error</response>
        [HttpGet("{id}/trends")]
        [ProducesResponseType(typeof(IEnumerable<ResourceTrendModel>), StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        [ProducesResponseType(StatusCodes.Status500InternalServerError)]
        public async Task<ActionResult<IEnumerable<ResourceTrendModel>>> GetServerTrends(
            int id,
            [FromQuery] int days = 7)
        {
            try
            {
                _logger.LogInformation("Getting resource trends for server {ServerId} (last {Days} days)", id, days);

                if (days < 1 || days > 365)
                {
                    return BadRequest(new { error = "Days parameter must be between 1 and 365" });
                }

                var trends = await _serverService.GetResourceTrendsAsync(id, days);

                if (trends == null || !trends.Any())
                {
                    return NotFound(new { error = $"No trend data found for server ID {id}" });
                }

                return Ok(trends);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving resource trends for server {ServerId}", id);
                return StatusCode(500, new { error = "Failed to retrieve resource trends", details = ex.Message });
            }
        }

        /// <summary>
        /// Get database summary for a server
        /// </summary>
        /// <param name="id">Server ID</param>
        /// <param name="databaseName">Optional: Filter by database name</param>
        /// <returns>Database size and backup status</returns>
        /// <response code="200">Returns database summary</response>
        /// <response code="404">Server not found</response>
        /// <response code="500">Internal server error</response>
        [HttpGet("{id}/databases")]
        [ProducesResponseType(typeof(IEnumerable<DatabaseSummaryModel>), StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        [ProducesResponseType(StatusCodes.Status500InternalServerError)]
        public async Task<ActionResult<IEnumerable<DatabaseSummaryModel>>> GetServerDatabases(
            int id,
            [FromQuery] string? databaseName = null)
        {
            try
            {
                _logger.LogInformation(
                    "Getting database summary for server {ServerId} (Database: {DatabaseName})",
                    id,
                    databaseName ?? "All");

                var databases = await _serverService.GetDatabaseSummaryAsync(id, databaseName);

                if (databases == null || !databases.Any())
                {
                    return NotFound(new { error = $"No databases found for server ID {id}" });
                }

                return Ok(databases);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving database summary for server {ServerId}", id);
                return StatusCode(500, new { error = "Failed to retrieve database summary", details = ex.Message });
            }
        }

        /// <summary>
        /// Register a new server
        /// </summary>
        /// <param name="request">Server registration details</param>
        /// <returns>Created server</returns>
        /// <response code="201">Server created successfully</response>
        /// <response code="400">Invalid request</response>
        /// <response code="409">Server already exists</response>
        /// <response code="500">Internal server error</response>
        [HttpPost]
        [ProducesResponseType(typeof(ServerModel), StatusCodes.Status201Created)]
        [ProducesResponseType(StatusCodes.Status400BadRequest)]
        [ProducesResponseType(StatusCodes.Status409Conflict)]
        [ProducesResponseType(StatusCodes.Status500InternalServerError)]
        public async Task<ActionResult<ServerModel>> RegisterServer([FromBody] ServerRegistrationRequest request)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(request.ServerName))
                {
                    return BadRequest(new { error = "ServerName is required" });
                }

                _logger.LogInformation("Registering new server: {ServerName}", request.ServerName);

                // Check if server already exists
                var existingServer = await _serverService.GetServerByNameAsync(request.ServerName);
                if (existingServer != null)
                {
                    return Conflict(new { error = $"Server '{request.ServerName}' already exists" });
                }

                var server = await _serverService.RegisterServerAsync(
                    request.ServerName,
                    request.Environment ?? "Production",
                    request.IsActive ?? true);

                return CreatedAtAction(
                    nameof(GetServer),
                    new { id = server.ServerID },
                    server);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error registering server {ServerName}", request.ServerName);
                return StatusCode(500, new { error = "Failed to register server", details = ex.Message });
            }
        }

        /// <summary>
        /// Update server details
        /// </summary>
        /// <param name="id">Server ID</param>
        /// <param name="request">Updated server details</param>
        /// <returns>Updated server</returns>
        /// <response code="200">Server updated successfully</response>
        /// <response code="400">Invalid request</response>
        /// <response code="404">Server not found</response>
        /// <response code="500">Internal server error</response>
        [HttpPut("{id}")]
        [ProducesResponseType(typeof(ServerModel), StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status400BadRequest)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        [ProducesResponseType(StatusCodes.Status500InternalServerError)]
        public async Task<ActionResult<ServerModel>> UpdateServer(int id, [FromBody] ServerUpdateRequest request)
        {
            try
            {
                _logger.LogInformation("Updating server ID: {ServerId}", id);

                var existingServer = await _serverService.GetServerByIdAsync(id);
                if (existingServer == null)
                {
                    return NotFound(new { error = $"Server with ID {id} not found" });
                }

                var updatedServer = await _serverService.UpdateServerAsync(
                    id,
                    request.Environment,
                    request.IsActive);

                return Ok(updatedServer);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating server {ServerId}", id);
                return StatusCode(500, new { error = "Failed to update server", details = ex.Message });
            }
        }
    }
}
