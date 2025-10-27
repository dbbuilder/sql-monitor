using Microsoft.Extensions.Caching.Memory;
using SqlMonitor.Api.Services;
using System.Security.Claims;
using System.Text.Json;

namespace SqlMonitor.Api.Middleware;

/// <summary>
/// Middleware for permission-based authorization
/// Phase 2.0 Week 1 Day 5: RBAC Foundation (API)
/// SOC 2 Controls: CC6.1, CC6.2, CC6.3
/// </summary>
public class AuthorizationMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<AuthorizationMiddleware> _logger;
    private readonly IMemoryCache _cache;
    private static readonly TimeSpan CacheDuration = TimeSpan.FromMinutes(5);

    public AuthorizationMiddleware(
        RequestDelegate next,
        ILogger<AuthorizationMiddleware> logger,
        IMemoryCache cache)
    {
        _next = next ?? throw new ArgumentNullException(nameof(next));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        _cache = cache ?? throw new ArgumentNullException(nameof(cache));
    }

    public async Task InvokeAsync(HttpContext context, ISqlService sqlService)
    {
        // Get endpoint metadata
        var endpoint = context.GetEndpoint();
        if (endpoint == null)
        {
            await _next(context);
            return;
        }

        // Get required permissions from endpoint metadata
        var requiredPermissions = endpoint.Metadata.GetOrderedMetadata<RequirePermissionAttribute>();
        if (!requiredPermissions.Any())
        {
            // No permission required - allow access
            await _next(context);
            return;
        }

        // Check if user is authenticated
        if (!context.User.Identity?.IsAuthenticated ?? true)
        {
            _logger.LogWarning("Unauthenticated user attempted to access {Path}", context.Request.Path);
            await WriteUnauthorizedResponse(context);
            return;
        }

        // Extract user ID from claims
        var userIdClaim = context.User.FindFirst("UserId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !int.TryParse(userIdClaim, out int userId))
        {
            _logger.LogWarning("User {UserName} has no valid UserId claim", context.User.Identity.Name);
            await WriteUnauthorizedResponse(context);
            return;
        }

        try
        {
            // Check if user has ANY of the required permissions (OR logic)
            bool hasPermission = false;
            foreach (var permission in requiredPermissions)
            {
                if (await CheckPermissionWithCacheAsync(sqlService, userId, permission.ResourceType, permission.ActionType))
                {
                    hasPermission = true;
                    break;
                }
            }

            if (!hasPermission)
            {
                var userName = context.User.Identity.Name ?? "Unknown";
                var permissionList = string.Join(" OR ", requiredPermissions.Select(p => $"{p.ResourceType}.{p.ActionType}"));

                _logger.LogWarning(
                    "Access denied for user {UserName} (ID: {UserId}) to {Method} {Path}. Required: {Permissions}",
                    userName, userId, context.Request.Method, context.Request.Path, permissionList);

                await WriteForbiddenResponse(context, permissionList);
                return;
            }

            // User has permission - continue
            await _next(context);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error checking permissions for user {UserId}", userId);
            await WriteInternalErrorResponse(context);
        }
    }

    private async Task<bool> CheckPermissionWithCacheAsync(
        ISqlService sqlService,
        int userId,
        string resourceType,
        string actionType)
    {
        var cacheKey = $"Permission:{userId}:{resourceType}:{actionType}";

        // Try to get from cache
        if (_cache.TryGetValue(cacheKey, out bool cachedResult))
        {
            return cachedResult;
        }

        // Not in cache - check database
        var hasPermission = await sqlService.CheckPermissionAsync(userId, resourceType, actionType);

        // Cache the result
        _cache.Set(cacheKey, hasPermission, CacheDuration);

        return hasPermission;
    }

    private static async Task WriteUnauthorizedResponse(HttpContext context)
    {
        context.Response.StatusCode = 401;
        context.Response.ContentType = "application/json";

        var response = new
        {
            error = "Unauthorized",
            message = "Authentication required"
        };

        await context.Response.WriteAsync(JsonSerializer.Serialize(response));
    }

    private static async Task WriteForbiddenResponse(HttpContext context, string requiredPermissions)
    {
        context.Response.StatusCode = 403;
        context.Response.ContentType = "application/json";

        var response = new
        {
            error = "Forbidden",
            message = "Access denied. Required permissions: " + requiredPermissions
        };

        await context.Response.WriteAsync(JsonSerializer.Serialize(response));
    }

    private static async Task WriteInternalErrorResponse(HttpContext context)
    {
        context.Response.StatusCode = 500;
        context.Response.ContentType = "application/json";

        var response = new
        {
            error = "Internal Server Error",
            message = "An error occurred while checking permissions"
        };

        await context.Response.WriteAsync(JsonSerializer.Serialize(response));
    }
}
