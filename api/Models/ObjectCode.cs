namespace SqlMonitor.Api.Models;

/// <summary>
/// Represents cached database object code (stored procedure, function, view, etc.)
/// </summary>
public class ObjectCode
{
    public long CodeID { get; set; }
    public int ServerID { get; set; }
    public string DatabaseName { get; set; } = string.Empty;
    public string SchemaName { get; set; } = string.Empty;
    public string ObjectName { get; set; } = string.Empty;
    public string ObjectType { get; set; } = string.Empty;
    public string? Definition { get; set; }
    public DateTime LastUpdated { get; set; }
}
