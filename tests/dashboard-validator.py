#!/usr/bin/env python3
"""
Dashboard E2E Validator
Tests all Grafana dashboards by executing their SQL queries and reporting missing data/stored procedures
"""

import json
import os
import sys
import re
from pathlib import Path
from typing import Dict, List, Tuple
import pymssql
from dataclasses import dataclass
from collections import defaultdict

@dataclass
class QueryResult:
    """Result of a query test"""
    panel_title: str
    query: str
    success: bool
    error: str = None
    row_count: int = 0
    missing_objects: List[str] = None

@dataclass
class DashboardReport:
    """Report for a single dashboard"""
    dashboard_name: str
    dashboard_title: str
    total_panels: int
    successful_queries: int
    failed_queries: int
    missing_tables: List[str]
    missing_procedures: List[str]
    query_results: List[QueryResult]

class DashboardValidator:
    """Validates Grafana dashboards against SQL Server"""

    def __init__(self, server: str, database: str, user: str, password: str):
        self.server = server
        self.database = database
        self.user = user
        self.password = password
        self.connection = None

    def connect(self):
        """Connect to SQL Server"""
        try:
            self.connection = pymssql.connect(
                server=self.server,
                database=self.database,
                user=self.user,
                password=self.password,
                timeout=30
            )
            print(f"✅ Connected to {self.server}/{self.database}")
            return True
        except Exception as e:
            print(f"❌ Failed to connect to database: {e}")
            return False

    def close(self):
        """Close database connection"""
        if self.connection:
            self.connection.close()

    def extract_queries_from_dashboard(self, dashboard_path: str) -> Tuple[str, str, List[Tuple[str, str]]]:
        """Extract all SQL queries from a dashboard JSON file"""
        with open(dashboard_path, 'r') as f:
            dashboard = json.load(f)

        dashboard_name = os.path.basename(dashboard_path).replace('.json', '')
        dashboard_title = dashboard.get('title', 'Unknown')
        queries = []

        def extract_from_panels(panels):
            for panel in panels:
                if not panel:
                    continue

                # Handle nested panels (rows)
                if 'panels' in panel:
                    extract_from_panels(panel['panels'])

                # Extract SQL from targets
                if 'targets' in panel:
                    panel_title = panel.get('title', 'Unknown Panel')
                    for target in panel['targets']:
                        if not target:
                            continue
                        # Try different query field names
                        query = target.get('rawSql') or target.get('rawQuery') or target.get('query', '')
                        if query and isinstance(query, str) and query.strip():
                            queries.append((panel_title, query.strip()))

        if 'panels' in dashboard:
            extract_from_panels(dashboard['panels'])

        return dashboard_name, dashboard_title, queries

    def identify_missing_objects(self, error_message: str) -> List[str]:
        """Identify missing tables/procedures from error message"""
        missing = []

        # Pattern for "Invalid object name 'dbo.TableName'"
        match = re.search(r"Invalid object name '([^']+)'", error_message)
        if match:
            missing.append(match.group(1))

        # Pattern for "Could not find stored procedure 'ProcName'"
        match = re.search(r"Could not find stored procedure '([^']+)'", error_message)
        if match:
            missing.append(match.group(1))

        return missing

    def test_query(self, panel_title: str, query: str) -> QueryResult:
        """Test a single SQL query"""
        try:
            cursor = self.connection.cursor()
            cursor.execute(query)

            # Try to fetch results
            try:
                rows = cursor.fetchall()
                row_count = len(rows)
            except:
                row_count = cursor.rowcount if cursor.rowcount >= 0 else 0

            cursor.close()

            return QueryResult(
                panel_title=panel_title,
                query=query[:200],  # Truncate for readability
                success=True,
                row_count=row_count
            )

        except Exception as e:
            error_str = str(e)
            missing_objects = self.identify_missing_objects(error_str)

            return QueryResult(
                panel_title=panel_title,
                query=query[:200],
                success=False,
                error=error_str,
                missing_objects=missing_objects
            )

    def validate_dashboard(self, dashboard_path: str) -> DashboardReport:
        """Validate all queries in a dashboard"""
        dashboard_name, dashboard_title, queries = self.extract_queries_from_dashboard(dashboard_path)

        print(f"\n📊 Testing: {dashboard_title} ({len(queries)} queries)")
        print(f"   File: {dashboard_name}.json")

        query_results = []
        missing_tables = set()
        missing_procedures = set()

        for panel_title, query in queries:
            result = self.test_query(panel_title, query)
            query_results.append(result)

            if not result.success:
                if result.missing_objects:
                    for obj in result.missing_objects:
                        if obj.startswith('dbo.usp_') or 'procedure' in result.error.lower():
                            missing_procedures.add(obj)
                        else:
                            missing_tables.add(obj)

        successful = sum(1 for r in query_results if r.success)
        failed = sum(1 for r in query_results if not r.success)

        # Print summary
        status = "✅" if failed == 0 else "⚠️" if successful > 0 else "❌"
        print(f"   {status} {successful}/{len(queries)} queries successful")

        if missing_tables:
            print(f"   ❌ Missing tables: {', '.join(sorted(missing_tables))}")
        if missing_procedures:
            print(f"   ❌ Missing procedures: {', '.join(sorted(missing_procedures))}")

        return DashboardReport(
            dashboard_name=dashboard_name,
            dashboard_title=dashboard_title,
            total_panels=len(queries),
            successful_queries=successful,
            failed_queries=failed,
            missing_tables=sorted(missing_tables),
            missing_procedures=sorted(missing_procedures),
            query_results=query_results
        )

    def validate_all_dashboards(self, dashboards_dir: str) -> List[DashboardReport]:
        """Validate all dashboards in a directory"""
        dashboard_files = sorted(Path(dashboards_dir).glob('*.json'))

        # Skip certain files
        skip_files = ['-backup.json', '.backup']
        dashboard_files = [f for f in dashboard_files if not any(skip in str(f) for skip in skip_files)]

        print(f"\n{'='*80}")
        print(f"🔍 Dashboard Validation Report")
        print(f"{'='*80}")
        print(f"Found {len(dashboard_files)} dashboards to validate")

        reports = []
        for dashboard_file in dashboard_files:
            report = self.validate_dashboard(str(dashboard_file))
            reports.append(report)

        return reports

    def print_summary(self, reports: List[DashboardReport]):
        """Print comprehensive summary"""
        total_panels = sum(r.total_panels for r in reports)
        total_success = sum(r.successful_queries for r in reports)
        total_failed = sum(r.failed_queries for r in reports)

        all_missing_tables = set()
        all_missing_procedures = set()

        for report in reports:
            all_missing_tables.update(report.missing_tables)
            all_missing_procedures.update(report.missing_procedures)

        print(f"\n{'='*80}")
        print(f"📈 SUMMARY")
        print(f"{'='*80}")
        print(f"Total Dashboards: {len(reports)}")
        print(f"Total Panels: {total_panels}")
        print(f"Successful Queries: {total_success} ({total_success/total_panels*100:.1f}%)")
        print(f"Failed Queries: {total_failed} ({total_failed/total_panels*100:.1f}%)")
        print()

        if all_missing_tables:
            print(f"🔴 MISSING TABLES ({len(all_missing_tables)}):")
            for table in sorted(all_missing_tables):
                count = sum(1 for r in reports if table in r.missing_tables)
                print(f"   - {table} (used in {count} dashboard{'s' if count > 1 else ''})")
            print()

        if all_missing_procedures:
            print(f"🔴 MISSING STORED PROCEDURES ({len(all_missing_procedures)}):")
            for proc in sorted(all_missing_procedures):
                count = sum(1 for r in reports if proc in r.missing_procedures)
                print(f"   - {proc} (used in {count} dashboard{'s' if count > 1 else ''})")
            print()

        # Dashboards fully working
        fully_working = [r for r in reports if r.failed_queries == 0 and r.total_panels > 0]
        if fully_working:
            print(f"✅ FULLY WORKING DASHBOARDS ({len(fully_working)}):")
            for report in fully_working:
                print(f"   - {report.dashboard_title} ({report.total_panels} panels)")
            print()

        # Dashboards needing attention
        needs_attention = [r for r in reports if r.failed_queries > 0]
        if needs_attention:
            print(f"⚠️  DASHBOARDS NEEDING ATTENTION ({len(needs_attention)}):")
            for report in sorted(needs_attention, key=lambda r: r.failed_queries, reverse=True):
                pct = (report.failed_queries / report.total_panels * 100) if report.total_panels > 0 else 0
                print(f"   - {report.dashboard_title}: {report.failed_queries}/{report.total_panels} failed ({pct:.0f}%)")
            print()

    def write_detailed_report(self, reports: List[DashboardReport], output_file: str):
        """Write detailed markdown report"""
        with open(output_file, 'w') as f:
            f.write("# Dashboard Validation Report\n\n")
            f.write(f"**Generated**: {os.popen('date').read().strip()}\n\n")

            # Summary
            total_panels = sum(r.total_panels for r in reports)
            total_success = sum(r.successful_queries for r in reports)
            total_failed = sum(r.failed_queries for r in reports)

            f.write("## Summary\n\n")
            f.write(f"- **Total Dashboards**: {len(reports)}\n")
            f.write(f"- **Total Panels**: {total_panels}\n")
            f.write(f"- **Successful Queries**: {total_success} ({total_success/total_panels*100:.1f}%)\n")
            f.write(f"- **Failed Queries**: {total_failed} ({total_failed/total_panels*100:.1f}%)\n\n")

            # Missing objects
            all_missing_tables = set()
            all_missing_procedures = set()
            for report in reports:
                all_missing_tables.update(report.missing_tables)
                all_missing_procedures.update(report.missing_procedures)

            if all_missing_tables:
                f.write("## Missing Tables\n\n")
                for table in sorted(all_missing_tables):
                    dashboards = [r.dashboard_title for r in reports if table in r.missing_tables]
                    f.write(f"- `{table}` - Used in: {', '.join(dashboards)}\n")
                f.write("\n")

            if all_missing_procedures:
                f.write("## Missing Stored Procedures\n\n")
                for proc in sorted(all_missing_procedures):
                    dashboards = [r.dashboard_title for r in reports if proc in r.missing_procedures]
                    f.write(f"- `{proc}` - Used in: {', '.join(dashboards)}\n")
                f.write("\n")

            # Dashboard details
            f.write("## Dashboard Details\n\n")
            for report in sorted(reports, key=lambda r: r.dashboard_title):
                status = "✅" if report.failed_queries == 0 else "⚠️"
                f.write(f"### {status} {report.dashboard_title}\n\n")
                f.write(f"- **File**: `{report.dashboard_name}.json`\n")
                f.write(f"- **Total Panels**: {report.total_panels}\n")
                f.write(f"- **Successful**: {report.successful_queries}\n")
                f.write(f"- **Failed**: {report.failed_queries}\n")

                if report.missing_tables:
                    f.write(f"- **Missing Tables**: {', '.join(report.missing_tables)}\n")
                if report.missing_procedures:
                    f.write(f"- **Missing Procedures**: {', '.join(report.missing_procedures)}\n")

                # Failed queries
                failed_results = [r for r in report.query_results if not r.success]
                if failed_results:
                    f.write("\n**Failed Queries**:\n\n")
                    for result in failed_results:
                        f.write(f"- **{result.panel_title}**: {result.error[:100]}\n")

                f.write("\n")

        print(f"\n📝 Detailed report written to: {output_file}")

def main():
    # Configuration
    SERVER = "172.31.208.1,14333"  # WSL host IP
    DATABASE = "MonitoringDB"
    USER = "sv"
    PASSWORD = "Gv51076!"
    DASHBOARDS_DIR = "/mnt/d/Dev2/sql-monitor/dashboards/grafana/dashboards"
    REPORT_FILE = "/mnt/d/Dev2/sql-monitor/tests/dashboard-validation-report.md"

    # Validate
    validator = DashboardValidator(SERVER, DATABASE, USER, PASSWORD)

    if not validator.connect():
        sys.exit(1)

    try:
        reports = validator.validate_all_dashboards(DASHBOARDS_DIR)
        validator.print_summary(reports)
        validator.write_detailed_report(reports, REPORT_FILE)
    finally:
        validator.close()

if __name__ == "__main__":
    main()
