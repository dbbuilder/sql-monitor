"""
Pytest configuration and fixtures for dashboard validation tests
"""

import pytest
import pymssql
import yaml
import json
from pathlib import Path
from typing import Dict, List, Tuple

# Load configuration
def load_config():
    config_path = Path(__file__).parent / "config.yaml"
    with open(config_path) as f:
        return yaml.safe_load(f)

CONFIG = load_config()

@pytest.fixture(scope="session")
def db_config():
    """Database configuration"""
    return CONFIG['database']

@pytest.fixture(scope="session")
def db_connection(db_config):
    """Shared database connection for all tests"""
    # Format server:port for pymssql
    server = db_config['server']
    if 'port' in db_config:
        server = f"{db_config['server']}:{db_config['port']}"

    conn = pymssql.connect(
        server=server,
        database=db_config['database'],
        user=db_config['user'],
        password=db_config['password'],
        timeout=db_config['timeout'],
        tds_version='7.0'
    )
    yield conn
    conn.close()

@pytest.fixture(scope="session")
def test_config():
    """Test configuration"""
    return CONFIG['tests']

@pytest.fixture(scope="session")
def dashboards(test_config):
    """Load all dashboard files"""
    dashboards_dir = Path(test_config['dashboards_dir'])
    skip_patterns = test_config['skip_patterns']

    dashboard_files = []
    for file in sorted(dashboards_dir.glob('*.json')):
        # Skip backup files
        if any(pattern in str(file) for pattern in skip_patterns):
            continue
        dashboard_files.append(file)

    return dashboard_files

def extract_queries_from_dashboard(dashboard_path: Path) -> Dict:
    """Extract all SQL queries from a dashboard"""
    with open(dashboard_path) as f:
        dashboard = json.load(f)

    queries = []

    def extract_from_panels(panels):
        if not panels:
            return

        for panel in panels:
            if not panel:
                continue

            # Handle nested panels (rows)
            if 'panels' in panel:
                extract_from_panels(panel['panels'])

            # Extract SQL from targets
            if 'targets' in panel:
                panel_title = panel.get('title', 'Unknown Panel')
                panel_id = panel.get('id', 0)

                for idx, target in enumerate(panel['targets']):
                    if not target:
                        continue

                    # Try different query field names
                    query = target.get('rawSql') or target.get('rawQuery') or target.get('query', '')

                    if query and isinstance(query, str) and query.strip():
                        queries.append({
                            'panel_id': panel_id,
                            'panel_title': panel_title,
                            'target_index': idx,
                            'query': query.strip()
                        })

    if 'panels' in dashboard:
        extract_from_panels(dashboard['panels'])

    return {
        'name': dashboard_path.stem,
        'title': dashboard.get('title', 'Unknown'),
        'queries': queries
    }

@pytest.fixture(scope="session")
def dashboard_queries(dashboards):
    """Extract queries from all dashboards"""
    all_queries = {}
    for dashboard_file in dashboards:
        dashboard_data = extract_queries_from_dashboard(dashboard_file)
        all_queries[dashboard_data['name']] = dashboard_data

    return all_queries

def pytest_generate_tests(metafunc):
    """Generate parameterized tests for each dashboard query"""
    if "dashboard_query" in metafunc.fixturenames:
        # Load dashboards and extract queries
        test_config = CONFIG['tests']
        dashboards_dir = Path(test_config['dashboards_dir'])
        skip_patterns = test_config['skip_patterns']

        test_cases = []

        for dashboard_file in sorted(dashboards_dir.glob('*.json')):
            if any(pattern in str(dashboard_file) for pattern in skip_patterns):
                continue

            dashboard_data = extract_queries_from_dashboard(dashboard_file)

            for query_info in dashboard_data['queries']:
                test_id = f"{dashboard_data['name']}::{query_info['panel_title']}"
                test_cases.append((
                    dashboard_data['name'],
                    dashboard_data['title'],
                    query_info['panel_title'],
                    query_info['query'],
                    test_id
                ))

        # Parameterize the test
        metafunc.parametrize(
            "dashboard_query",
            test_cases,
            ids=[tc[4] for tc in test_cases]
        )

@pytest.fixture
def query_executor(db_connection, test_config):
    """Execute SQL queries with retry logic"""
    class QueryExecutor:
        def __init__(self, connection, config):
            self.connection = connection
            self.retry_enabled = config['retry']['enabled']
            self.max_attempts = config['retry']['max_attempts']
            self.delay = config['retry']['delay_seconds']
            self.timeout = config['query_timeout']

        def execute(self, query: str) -> Tuple[bool, int, str]:
            """Execute query and return (success, row_count, error)"""
            import time
            import re
            from datetime import datetime, timedelta, timezone

            # Replace Grafana macros with actual SQL
            query = self._replace_grafana_macros(query)

            attempts = 0
            last_error = None

            while attempts < self.max_attempts:
                attempts += 1

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
                    return (True, row_count, None)

                except Exception as e:
                    last_error = str(e)

                    if not self.retry_enabled or attempts >= self.max_attempts:
                        break

                    # Wait before retry
                    time.sleep(self.delay)

            return (False, 0, last_error)

        def _replace_grafana_macros(self, query: str) -> str:
            """Replace Grafana-specific macros with actual SQL"""
            import re
            from datetime import datetime, timedelta, timezone

            # Default time range: last 6 hours
            time_from = datetime.now(timezone.utc) - timedelta(hours=6)
            time_to = datetime.now(timezone.utc)

            # Replace $__timeFrom() and $__timeTo()
            query = query.replace('$__timeFrom()', f"'{time_from.strftime('%Y-%m-%d %H:%M:%S')}'")
            query = query.replace('$__timeTo()', f"'{time_to.strftime('%Y-%m-%d %H:%M:%S')}'")

            # Replace $__timeFilter(column) with a simple true condition
            # Using actual time ranges can cause slow scans on empty/large tables
            query = re.sub(r'\$__timeFilter\([^)]+\)', '1=1', query)

            # Replace $__timeGroup(column, interval) with DATEADD time bucketing
            # Example: $__timeGroup(CheckStartTime, '1d') -> DATEADD(DAY, DATEDIFF(DAY, 0, CheckStartTime), 0)
            query = re.sub(
                r"\$__timeGroup\(([^,]+),\s*'([^']+)'\)",
                lambda m: f"DATEADD(DAY, DATEDIFF(DAY, 0, {m.group(1).strip()}), 0)",
                query
            )

            # Replace Grafana time range variables with numeric values
            # $__range_s, $__range_ms, $__range_m, $__range_h, $__range
            query = re.sub(r'\$__range_s\b', '21600', query)   # 6 hours in seconds
            query = re.sub(r'\$__range_ms\b', '21600000', query)  # 6 hours in milliseconds
            query = re.sub(r'\$__range_m\b', '360', query)   # 6 hours in minutes
            query = re.sub(r'\$__range_h\b', '6', query)     # 6 hours
            query = re.sub(r'\$__range\b', '21600000', query)  # Default to milliseconds

            # Replace numeric ID variables with integer value (not string)
            # This must happen BEFORE general variable replacement
            query = re.sub(r'\$\{ServerID[^}]*\}', '1', query)
            query = re.sub(r'\$ServerID\b', '1', query)

            # Replace Grafana template variables
            # ${ServerName:singlequote} or similar -> '%' for wildcard matching
            query = re.sub(r'\$\{[^}]+\}', "'%'", query)

            # Replace simple $variable references (not in ${})
            query = re.sub(r"\$\w+", "'%'", query)

            # Fix string patterns created by variable replacement
            # Apply repeatedly until no more changes (handles nested patterns)
            max_iterations = 10
            for _ in range(max_iterations):
                old_query = query

                # Fix concatenation: '%' + '%' → '%%'
                query = query.replace("'%' + '%'", "'%%'")
                query = query.replace("'%%' + '%'", "'%%%'")
                query = query.replace("'%' + '%%'", "'%%%'")

                # Fix adjacent literals: '%'%' → '%%'
                query = query.replace("'%'%'", "'%%'")
                query = query.replace("'%%'%'", "'%%%'")
                query = query.replace("'%'%%'", "'%%%'")

                # Fix empty quotes: ''%'' → '%'
                query = query.replace("''%''", "'%'")

                # No more changes, we're done
                if query == old_query:
                    break

            # Replace $__all checks (used in WHERE clauses)
            query = re.sub(r"'\$__all' IN \([^)]+\) OR ", "", query)
            query = re.sub(r" AND '\$__all' IN \([^)]+\)", "", query)

            return query

    return QueryExecutor(db_connection, test_config)
