using System;
using System.Collections.Generic;

namespace SqlMonitor.Api.Models;

/// <summary>
/// Request model for executing SQL queries
/// </summary>
public class ExecuteQueryRequest
{
    /// <summary>
    /// Server ID to execute query against
    /// </summary>
    public int ServerId { get; set; }

    /// <summary>
    /// Database name
    /// </summary>
    public string Database { get; set; } = string.Empty;

    /// <summary>
    /// SQL query to execute
    /// </summary>
    public string Query { get; set; } = string.Empty;

    /// <summary>
    /// Timeout in seconds (default: 60)
    /// </summary>
    public int TimeoutSeconds { get; set; } = 60;

    /// <summary>
    /// Maximum rows to return per result set (default: 5000)
    /// </summary>
    public int MaxRows { get; set; } = 5000;
}

/// <summary>
/// Response model for query execution
/// </summary>
public class ExecuteQueryResponse
{
    /// <summary>
    /// Whether execution was successful
    /// </summary>
    public bool Success { get; set; }

    /// <summary>
    /// Error message if execution failed
    /// </summary>
    public string? Error { get; set; }

    /// <summary>
    /// Result sets returned by the query
    /// </summary>
    public List<QueryResultSet> ResultSets { get; set; } = new();

    /// <summary>
    /// Execution time in milliseconds
    /// </summary>
    public long ExecutionTimeMs { get; set; }

    /// <summary>
    /// Total rows affected (for INSERT/UPDATE/DELETE)
    /// </summary>
    public int RowsAffected { get; set; }

    /// <summary>
    /// Messages returned by SQL Server (PRINT statements, etc.)
    /// </summary>
    public List<string> Messages { get; set; } = new();
}

/// <summary>
/// Single result set from a query
/// </summary>
public class QueryResultSet
{
    /// <summary>
    /// Column definitions
    /// </summary>
    public List<QueryColumn> Columns { get; set; } = new();

    /// <summary>
    /// Row data
    /// </summary>
    public List<Dictionary<string, object?>> Rows { get; set; } = new();

    /// <summary>
    /// Row count
    /// </summary>
    public int RowCount => Rows.Count;
}

/// <summary>
/// Column definition
/// </summary>
public class QueryColumn
{
    /// <summary>
    /// Column name
    /// </summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// Data type (SQL Server type)
    /// </summary>
    public string DataType { get; set; } = string.Empty;

    /// <summary>
    /// Whether column allows NULLs
    /// </summary>
    public bool IsNullable { get; set; }

    /// <summary>
    /// Maximum length (for string types)
    /// </summary>
    public int? MaxLength { get; set; }
}

/// <summary>
/// Request model for analyzing query rewrites
/// </summary>
public class AnalyzeQueryRewriteRequest
{
    /// <summary>
    /// SQL query text to analyze
    /// </summary>
    public string QueryText { get; set; } = string.Empty;

    /// <summary>
    /// Optional server ID for context
    /// </summary>
    public int? ServerId { get; set; }

    /// <summary>
    /// Optional database name for context
    /// </summary>
    public string? DatabaseName { get; set; }
}

/// <summary>
/// Response model for query rewrite analysis
/// </summary>
public class AnalyzeQueryRewriteResponse
{
    /// <summary>
    /// List of rewrite suggestions
    /// </summary>
    public List<QueryRewriteSuggestion> Suggestions { get; set; } = new();

    /// <summary>
    /// Total number of suggestions
    /// </summary>
    public int TotalSuggestions => Suggestions.Count;
}

/// <summary>
/// Query rewrite suggestion
/// </summary>
public class QueryRewriteSuggestion
{
    /// <summary>
    /// Rule ID (e.g., P001, P002)
    /// </summary>
    public string RuleId { get; set; } = string.Empty;

    /// <summary>
    /// Rule description
    /// </summary>
    public string Description { get; set; } = string.Empty;

    /// <summary>
    /// Severity (Critical, Warning, Info)
    /// </summary>
    public string Severity { get; set; } = string.Empty;

    /// <summary>
    /// Line number in query (0 if not applicable)
    /// </summary>
    public int LineNumber { get; set; }

    /// <summary>
    /// Column number in query (0 if not applicable)
    /// </summary>
    public int ColumnNumber { get; set; }

    /// <summary>
    /// Original code pattern
    /// </summary>
    public string? OriginalCode { get; set; }

    /// <summary>
    /// Suggested rewrite
    /// </summary>
    public string? SuggestedCode { get; set; }

    /// <summary>
    /// Detailed explanation
    /// </summary>
    public string? Explanation { get; set; }

    /// <summary>
    /// Impact level (High, Medium, Low)
    /// </summary>
    public string? Impact { get; set; }
}

/// <summary>
/// Response model for query percentiles
/// </summary>
public class QueryPercentilesResponse
{
    /// <summary>
    /// List of queries with percentile data
    /// </summary>
    public List<QueryPercentileData> Queries { get; set; } = new();

    /// <summary>
    /// Time window used for calculation
    /// </summary>
    public int TimeWindowMinutes { get; set; }
}

/// <summary>
/// Query percentile data
/// </summary>
public class QueryPercentileData
{
    /// <summary>
    /// Query Store Query ID
    /// </summary>
    public long QueryId { get; set; }

    /// <summary>
    /// Plan ID
    /// </summary>
    public long PlanId { get; set; }

    /// <summary>
    /// Query text (first 200 characters)
    /// </summary>
    public string? QueryText { get; set; }

    /// <summary>
    /// 50th percentile (median) duration in milliseconds
    /// </summary>
    public decimal P50DurationMs { get; set; }

    /// <summary>
    /// 95th percentile duration in milliseconds
    /// </summary>
    public decimal P95DurationMs { get; set; }

    /// <summary>
    /// 99th percentile duration in milliseconds
    /// </summary>
    public decimal P99DurationMs { get; set; }

    /// <summary>
    /// Average duration in milliseconds
    /// </summary>
    public decimal AvgDurationMs { get; set; }

    /// <summary>
    /// Execution count
    /// </summary>
    public int ExecutionCount { get; set; }
}

/// <summary>
/// Response model for wait statistics by category
/// </summary>
public class WaitStatsByCategoryResponse
{
    /// <summary>
    /// List of wait categories with statistics
    /// </summary>
    public List<WaitCategoryData> Categories { get; set; } = new();

    /// <summary>
    /// Time window used for calculation
    /// </summary>
    public int TimeWindowMinutes { get; set; }

    /// <summary>
    /// Total wait time across all categories (ms)
    /// </summary>
    public decimal TotalWaitTimeMs { get; set; }
}

/// <summary>
/// Wait category data
/// </summary>
public class WaitCategoryData
{
    /// <summary>
    /// Wait category (CPU, I/O, Lock, etc.)
    /// </summary>
    public string Category { get; set; } = string.Empty;

    /// <summary>
    /// Wait type
    /// </summary>
    public string WaitType { get; set; } = string.Empty;

    /// <summary>
    /// Total wait time in milliseconds
    /// </summary>
    public decimal TotalWaitTimeMs { get; set; }

    /// <summary>
    /// Total wait count
    /// </summary>
    public long TotalWaitCount { get; set; }

    /// <summary>
    /// Average wait time in milliseconds
    /// </summary>
    public decimal? AvgWaitTimeMs { get; set; }

    /// <summary>
    /// Maximum wait time in milliseconds
    /// </summary>
    public decimal? MaxWaitTimeMs { get; set; }

    /// <summary>
    /// Percentage of total wait time
    /// </summary>
    public decimal PercentageOfTotal { get; set; }
}
