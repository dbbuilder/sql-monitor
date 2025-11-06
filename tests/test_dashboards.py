"""
Pytest-based dashboard validation tests
Each SQL query from each dashboard is tested as a separate test case
"""

import pytest
import re
from typing import List

class TestDashboardQueries:
    """Test all dashboard queries execute successfully"""

    def test_dashboard_query(self, dashboard_query, query_executor):
        """Test a single dashboard query"""
        dashboard_name, dashboard_title, panel_title, query, test_id = dashboard_query

        # Execute the query
        success, row_count, error = query_executor.execute(query)

        # Assertions
        assert success, f"Query failed in dashboard '{dashboard_title}' panel '{panel_title}': {error}"

        # Optionally check for data
        # assert row_count > 0, f"Query returned no rows in panel '{panel_title}'"

class TestDatabaseObjects:
    """Test that expected database objects exist"""

    def test_expected_tables_exist(self, db_connection, test_config):
        """Verify all expected tables exist"""
        import yaml

        config_path = "config.yaml"
        with open(config_path) as f:
            config = yaml.safe_load(f)

        expected_tables = config.get('expected_tables', [])

        cursor = db_connection.cursor()

        for table in expected_tables:
            cursor.execute(f"""
                SELECT COUNT(*)
                FROM INFORMATION_SCHEMA.TABLES
                WHERE TABLE_SCHEMA + '.' + TABLE_NAME = '{table}'
            """)

            count = cursor.fetchone()[0]
            assert count > 0, f"Expected table {table} does not exist"

        cursor.close()

    def test_expected_procedures_exist(self, db_connection, test_config):
        """Verify all expected stored procedures exist"""
        import yaml

        config_path = "config.yaml"
        with open(config_path) as f:
            config = yaml.safe_load(f)

        expected_procedures = config.get('expected_procedures', [])

        cursor = db_connection.cursor()

        for procedure in expected_procedures:
            cursor.execute(f"""
                SELECT COUNT(*)
                FROM INFORMATION_SCHEMA.ROUTINES
                WHERE ROUTINE_SCHEMA + '.' + ROUTINE_NAME = '{procedure}'
                AND ROUTINE_TYPE = 'PROCEDURE'
            """)

            count = cursor.fetchone()[0]
            assert count > 0, f"Expected stored procedure {procedure} does not exist"

        cursor.close()

class TestDatabaseConnection:
    """Test database connectivity"""

    def test_can_connect_to_database(self, db_connection):
        """Verify database connection works"""
        cursor = db_connection.cursor()
        cursor.execute("SELECT @@VERSION")
        version = cursor.fetchone()[0]
        cursor.close()

        assert version is not None
        assert "SQL Server" in version

    def test_can_query_servers_table(self, db_connection):
        """Verify Servers table exists and is queryable"""
        cursor = db_connection.cursor()
        cursor.execute("SELECT COUNT(*) FROM dbo.Servers")
        count = cursor.fetchone()[0]
        cursor.close()

        assert count >= 0, "Servers table should exist"

def identify_missing_objects(error_message: str) -> List[str]:
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

@pytest.hookimpl(hookwrapper=True)
def pytest_runtest_makereport(item, call):
    """Add custom information to test reports"""
    outcome = yield
    report = outcome.get_result()

    # Add dashboard information to report
    if hasattr(item, 'callspec') and 'dashboard_query' in item.callspec.params:
        dashboard_name, dashboard_title, panel_title, query, test_id = item.callspec.params['dashboard_query']

        # Add extra information
        report.dashboard_name = dashboard_name
        report.dashboard_title = dashboard_title
        report.panel_title = panel_title

        # If failed, extract missing objects
        if report.failed and hasattr(report, 'longrepr'):
            error_text = str(report.longrepr)
            missing_objects = identify_missing_objects(error_text)
            report.missing_objects = missing_objects
