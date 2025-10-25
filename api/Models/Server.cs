namespace SqlMonitor.Api.Models;

/// <summary>
/// Represents a monitored SQL Server instance
/// </summary>
public class Server
{
    public int ServerID { get; set; }
    public string ServerName { get; set; } = string.Empty;
    public string? Environment { get; set; }
    public bool IsActive { get; set; }
    public DateTime CreatedDate { get; set; }
    public DateTime? ModifiedDate { get; set; }
}
