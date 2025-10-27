using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using SqlMonitor.Api.Services;
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace SqlMonitor.Api.Middleware;

/// <summary>
/// Middleware to log all HTTP requests to the audit trail (Phase 2.0 - SOC 2 compliance)
/// Controls: CC6.1, CC6.2, CC7.2
/// </summary>
public class AuditMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<AuditMiddleware> _logger;
    private readonly ISqlService _sqlService;

    // Endpoints to exclude from audit logging (too noisy)
    private static readonly string[] ExcludedPaths = new[] { "/health", "/swagger", "/favicon.ico" };

    public AuditMiddleware(
        RequestDelegate next,
        ILogger<AuditMiddleware> logger,
        ISqlService sqlService)
    {
        _next = next;
        _logger = logger;
        _sqlService = sqlService;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        // Skip audit logging for excluded paths
        if (ExcludedPaths.Any(path => context.Request.Path.StartsWithSegments(path)))
        {
            await _next(context);
            return;
        }

        var stopwatch = Stopwatch.StartNew();
        Exception? requestException = null;

        // Capture request body (for POST/PUT)
        string? requestBody = null;
        if (context.Request.Method == "POST" || context.Request.Method == "PUT")
        {
            context.Request.EnableBuffering();
            requestBody = await ReadRequestBodyAsync(context.Request);
            context.Request.Body.Position = 0; // Reset stream for next middleware
        }

        try
        {
            // Execute next middleware
            await _next(context);
        }
        catch (Exception ex)
        {
            requestException = ex;
            throw; // Re-throw to preserve original exception
        }
        finally
        {
            stopwatch.Stop();

            // Log to audit trail
            await LogAuditEventAsync(context, stopwatch.ElapsedMilliseconds, requestBody, requestException);
        }
    }

    private async Task<string?> ReadRequestBodyAsync(HttpRequest request)
    {
        try
        {
            using var reader = new StreamReader(request.Body, Encoding.UTF8, leaveOpen: true);
            return await reader.ReadToEndAsync();
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to read request body for audit logging");
            return null;
        }
    }

    private async Task LogAuditEventAsync(
        HttpContext context,
        long durationMs,
        string? requestBody,
        Exception? exception)
    {
        try
        {
            var userName = context.User?.Identity?.Name ?? "Anonymous";
            var ipAddress = context.Connection.RemoteIpAddress?.ToString();
            var method = context.Request.Method;
            var path = context.Request.Path;
            var queryString = context.Request.QueryString.ToString();
            var statusCode = context.Response.StatusCode;

            // Build SQL text (request details)
            var sqlText = new StringBuilder();
            sqlText.AppendLine($"{method} {path}{queryString}");
            sqlText.AppendLine($"Status: {statusCode}");
            sqlText.AppendLine($"Duration: {durationMs}ms");

            if (!string.IsNullOrEmpty(requestBody))
            {
                sqlText.AppendLine($"Request Body: {requestBody}");
            }

            // Determine event type and severity
            var eventType = exception != null ? "HttpRequestError" : "HttpRequest";
            var severity = exception != null ? "Error" : "Information";

            // Call stored procedure
            await _sqlService.LogAuditEventAsync(
                eventType: eventType,
                userName: userName,
                applicationName: "SqlServerMonitor.Api",
                hostName: null,
                ipAddress: ipAddress,
                databaseName: null,
                schemaName: null,
                objectName: null,
                objectType: null,
                actionType: null,
                oldValue: null,
                newValue: null,
                affectedRows: null,
                sqlText: sqlText.ToString(),
                errorNumber: exception != null ? 1 : null,
                errorMessage: exception?.Message,
                severity: severity,
                dataClassification: "Internal",
                complianceFlag: "SOC2",
                retentionDays: 2555
            );

            _logger.LogDebug("Audit event logged: {Method} {Path} ({Duration}ms)", method, path, durationMs);
        }
        catch (Exception ex)
        {
            // Don't fail the request if audit logging fails
            _logger.LogError(ex, "Failed to log audit event");
        }
    }
}
