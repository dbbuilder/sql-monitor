namespace SqlMonitor.Api.Middleware;

/// <summary>
/// Attribute to specify required permissions for an API endpoint
/// Phase 2.0 Week 1 Day 5: RBAC Foundation (API)
/// SOC 2 Controls: CC6.1, CC6.2, CC6.3
/// </summary>
[AttributeUsage(AttributeTargets.Method | AttributeTargets.Class, AllowMultiple = true)]
public class RequirePermissionAttribute : Attribute
{
    /// <summary>
    /// Resource type (e.g., "Servers", "Metrics", "Alerts")
    /// </summary>
    public string ResourceType { get; }

    /// <summary>
    /// Action type (e.g., "Read", "Write", "Delete", "Execute", "Admin")
    /// </summary>
    public string ActionType { get; }

    /// <summary>
    /// Initialize a new permission requirement
    /// </summary>
    /// <param name="resourceType">Resource type (e.g., "Servers")</param>
    /// <param name="actionType">Action type (e.g., "Read")</param>
    public RequirePermissionAttribute(string resourceType, string actionType)
    {
        ResourceType = resourceType ?? throw new ArgumentNullException(nameof(resourceType));
        ActionType = actionType ?? throw new ArgumentNullException(nameof(actionType));
    }
}
