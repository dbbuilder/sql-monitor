#!/usr/bin/env python3
"""
Export SQL Server Health Report as HTML
Handles large NVARCHAR(MAX) output that sqlcmd truncates
"""

import pyodbc
import sys
from datetime import datetime
import os

def export_html_report(server, user, password, output_file=None,
                      top_queries=20, top_indexes=20, hours_back=48):
    """
    Generate and export HTML health report from SQL Server

    Args:
        server: SQL Server address (e.g., 'servername,14333')
        user: SQL username
        password: SQL password
        output_file: Output HTML file path (default: auto-generated)
        top_queries: Number of slow queries to include
        top_indexes: Number of missing indexes to include
        hours_back: Hours to look back for statistics
    """

    # Auto-generate filename if not provided
    if output_file is None:
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_file = f'health_report_{timestamp}.html'

    # Ensure output directory exists
    output_dir = os.path.dirname(output_file)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)

    # Build connection string
    conn_str = (
        f'DRIVER={{ODBC Driver 18 for SQL Server}};'
        f'SERVER={server};'
        f'DATABASE=DBATools;'
        f'UID={user};'
        f'PWD={password};'
        f'TrustServerCertificate=yes;'
        f'Encrypt=Optional'
    )

    print(f"Connecting to {server}...")

    try:
        # Connect to database
        conn = pyodbc.connect(conn_str, timeout=30)
        cursor = conn.cursor()

        # Execute stored procedure
        sql = f"""
        SET NOCOUNT ON
        EXEC DBATools.dbo.DBA_DailyHealthOverview_HTML
            @TopSlowQueries = {top_queries},
            @TopMissingIndexes = {top_indexes},
            @HoursBackForIssues = {hours_back}
        """

        print(f"Generating HTML report...")
        cursor.execute(sql)

        # Fetch result
        row = cursor.fetchone()

        if row is None or row[0] is None:
            print("ERROR: No HTML returned from procedure")
            return False

        html_content = row[0]

        # Write to file
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(html_content)

        # Get file stats
        file_size = os.path.getsize(output_file)

        print(f"\n✅ Report generated successfully")
        print(f"   File: {output_file}")
        print(f"   Size: {file_size:,} bytes ({file_size/1024:.1f} KB)")
        print(f"   HTML Length: {len(html_content):,} characters")

        # Close connection
        cursor.close()
        conn.close()

        return True

    except pyodbc.Error as e:
        print(f"\n❌ Database Error:")
        print(f"   {e}")
        return False
    except Exception as e:
        print(f"\n❌ Error:")
        print(f"   {e}")
        return False


if __name__ == '__main__':
    # Default configuration
    SERVER = 'sqltest.schoolvision.net,14333'
    USER = 'sv'
    PASSWORD = 'Gv51076!'
    OUTPUT_DIR = '/mnt/e/Downloads/sql_monitor/reports'

    # Parse command line arguments
    if len(sys.argv) > 1:
        SERVER = sys.argv[1]
    if len(sys.argv) > 2:
        USER = sys.argv[2]
    if len(sys.argv) > 3:
        PASSWORD = sys.argv[3]

    # Generate timestamp filename
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    output_file = os.path.join(OUTPUT_DIR, f'health_report_{timestamp}.html')

    # Ensure output directory exists
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("=" * 50)
    print("SQL Server Health Report Generator")
    print("=" * 50)
    print(f"Server: {SERVER}")
    print(f"Output: {output_file}")
    print("")

    # Export report
    success = export_html_report(
        server=SERVER,
        user=USER,
        password=PASSWORD,
        output_file=output_file,
        top_queries=20,
        top_indexes=20,
        hours_back=48
    )

    if success:
        print("\nTo view the report:")
        print(f"  1. Open in browser: file://{output_file}")
        print(f"  2. WSL: wslpath -w '{output_file}' | xargs cmd.exe /c start")
        print(f"  3. HTTP server: cd {OUTPUT_DIR} && python3 -m http.server 8000")
        sys.exit(0)
    else:
        print("\nReport generation failed")
        sys.exit(1)
