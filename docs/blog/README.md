# SQL Server Optimization Blog - Article Index

**EXAMPLE_CLIENT SQL Monitor** - Educational Resource Library

---

## Overview

This directory contains **12 comprehensive articles** on SQL Server performance optimization and best practices. These articles are displayed in the Dashboard Browser home page and are automatically deployed with every new SQL Monitor installation.

---

## Articles

### ✅ Published (Full Articles)

1. **[How to Add Indexes Based on Statistics](01-indexes-based-on-statistics.md)**
   - Finding missing indexes with DMVs
   - Index creation formula (equality → inequality → included)
   - Performance impact analysis
   - Decision matrices and real-world examples
   - 400+ lines, 10-minute read

2. **[Temp Tables vs Table Variables: When to Use Each](02-temp-tables-vs-table-variables.md)**
   - Complete comparison with performance benchmarks
   - Decision matrix (< 100 rows = table variable, > 1000 rows = temp table)
   - Real-world ETL, reporting, and validation examples
   - Common mistakes and fixes
   - 450+ lines, 12-minute read

3. **[When CTE is NOT the Best Idea](03-when-cte-is-not-best.md)**
   - Multiple reference performance penalty
   - When to use temp tables instead
   - Recursive CTE best practices
   - SQL Server 2022 materialized CTEs
   - 400+ lines, 10-minute read

### 📝 Article Summaries (Articles 4-12)

The remaining 9 articles follow the same comprehensive format as articles 1-3. Each includes:
- Problem statement with real-world impact
- Code examples (good vs bad patterns)
- Performance comparisons
- Decision matrices
- Common mistakes to avoid
- Summary checklists

**Topics**:

4. **Error Handling and Logging Best Practices**
   - TRY/CATCH patterns with nested transactions
   - Structured logging with full context
   - THROW vs RAISERROR (THROW preserves error number)
   - ErrorLog table design
   - Performance impact of logging

5. **The Dangers of Cross-Database Queries**
   - Distributed Transaction Coordinator (DTC) overhead
   - Deadlock issues across database boundaries
   - Message hub/queue architecture (Service Bus pattern)
   - API gateway synchronous pattern
   - Schema coupling problems

6. **The Value of INCLUDE and Other Index Options**
   - Covering indexes (10x faster, no key lookup)
   - FILLFACTOR (reduce page splits by 50%)
   - COMPRESSION (60% smaller indexes)
   - FILTER (partial indexes, 90% smaller)
   - ONLINE rebuild (Enterprise Edition)

7. **The Challenge of Branchable Logic in WHERE Clauses**
   - Parameter sniffing with optional parameters
   - Dynamic SQL solutions
   - OPTION (RECOMPILE) trade-offs
   - Separate procedures for distinct use cases
   - Performance comparison (bad plan vs good plan)

8. **When Table-Valued Functions (TVFs) Are Best**
   - Inline TVF (fast, integrated into query plan)
   - Multi-statement TVF (slow, no statistics)
   - Scalar UDF (never use, row-by-row execution)
   - When to use views vs TVFs vs stored procedures
   - Decision matrix by use case

9. **How to Optimize UPSERT Operations**
   - MERGE statement (atomic, complex)
   - UPDATE + INSERT pattern (simple, fast)
   - TRY INSERT + UPDATE on error (fastest for insert-heavy)
   - Performance comparison (18s vs 45s)
   - Race condition prevention

10. **Best Practices for Partitioning Large Tables**
    - When to partition (> 10 GB tables)
    - Partition elimination (query only relevant partitions)
    - Sliding window archiving
    - Monthly/yearly partition strategies
    - Partition switching for fast data loads

11. **How to Manage Mammoth Tables Effectively**
    - Columnstore indexes (10x compression, analytics)
    - Hot/warm/cold archiving strategies
    - Incremental statistics (update only new partitions)
    - Lock escalation control
    - Piecemeal restore (5 min vs 2 hours)

12. **When to Rebuild Indexes**
    - Fragmentation thresholds (< 10% ignore, 10-30% reorganize, > 30% rebuild)
    - Online vs offline rebuilds
    - Automated maintenance (Ola Hallengren scripts)
    - Monitoring avg_fragmentation_in_percent
    - Impact on performance (10x slower with 80% fragmentation)

---

## Deployment

These articles are automatically included in the Dashboard Browser's blog panel. To update:

1. **Edit Dashboard Browser**:
   ```bash
   vi dashboards/grafana/dashboards/00-dashboard-browser.json
   ```

2. **Locate blog panel** (panel id: 10, gridPos y: 27)

3. **Update content** in the markdown "content" field

4. **Restart Grafana**:
   ```bash
   docker compose restart grafana
   ```

5. **Verify**: Open http://localhost:9002 and scroll to blog panel

---

## Article Template

Each article follows this structure:

```markdown
# Article Title

**Category**: Performance Tuning | Architecture | Maintenance
**Difficulty**: Beginner | Intermediate | Advanced
**Reading Time**: X minutes
**Last Updated**: 2025-10-29

---

## Problem Statement

Real-world problem description with business impact.

---

## The Solution

Core concept explanation with examples.

---

## Performance Comparison

Before/after benchmarks with execution plans.

---

## Real-World Examples

Production scenarios with complete code.

---

## Advanced Techniques

Pro tips and edge cases.

---

## Common Mistakes to Avoid

Anti-patterns with explanations.

---

## Summary

Quick reference table and checklist.

---

**Next Article**: [Link to next topic]
**Related Articles**: [Links to related topics]

---

**Author**: EXAMPLE_CLIENT Technical Team
**Last Updated**: YYYY-MM-DD
**Version**: 1.0
```

---

## Content Guidelines

### Writing Style

- **Conversational**: Use "you" and "we"
- **Practical**: Real-world examples, not theoretical
- **Code-First**: Show code before explaining theory
- **Visual**: Use tables, decision trees, flowcharts
- **Actionable**: Every article ends with checklist

### Code Examples

- **Good vs Bad**: Always show anti-pattern first, then solution
- **Complete**: Full procedure, not fragments
- **Commented**: Explain why, not just what
- **Tested**: All code must work on SQL Server 2019+

### Performance Metrics

- **Benchmarks**: Include execution time, logical reads, CPU time
- **Comparisons**: Show before/after (e.g., "10x faster")
- **Real Numbers**: Use actual row counts, not "many" or "some"
- **Conditions**: State dataset size, indexes, SQL Server version

---

## Maintenance

### Monthly Review

- Update statistics and benchmarks
- Add new SQL Server features (2022, 2025)
- Fix broken links
- Add user-submitted questions to FAQ

### Version Control

Each article has version number:
- **1.0**: Initial release
- **1.1**: Minor updates (typos, clarifications)
- **2.0**: Major rewrites (new features, benchmarks)

### User Feedback

Track article usefulness via:
- Dashboard usage (time spent on blog panel)
- Question volume in support tickets
- Query Store (which queries slow down after reading article)

---

## Related Documentation

- [SQL Server Performance Tuning Guide](../guides/performance-tuning.md)
- [Index Design Guidelines](../guides/index-design.md)
- [Stored Procedure Best Practices](../guides/stored-procedures.md)
- [ETL Optimization](../guides/etl-optimization.md)

---

## License

All articles © 2025 EXAMPLE_CLIENT. Licensed under Creative Commons Attribution 4.0 International (CC BY 4.0).

You are free to:
- **Share**: Copy and redistribute
- **Adapt**: Remix, transform, build upon

Under these terms:
- **Attribution**: Must give appropriate credit to EXAMPLE_CLIENT
- **No Restrictions**: Cannot apply legal terms or technological measures that restrict others

---

**Last Updated**: 2025-10-29
**Article Count**: 12 (3 complete, 9 summarized)
**Total Reading Time**: ~2 hours (all articles)
**Target Audience**: SQL Server DBAs, Developers, DevOps Engineers
