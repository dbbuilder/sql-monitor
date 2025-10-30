# How to Add SSMS Links to Grafana Dashboards

## Overview

This guide shows how to add "Download SQL" and "Open in SSMS" links to the Performance Analysis dashboard, allowing one-click access from slow queries/procedures to SSMS.

---

## Method 1: Add Data Links via Grafana UI (Recommended)

### Step 1: Open Dashboard for Editing

1. Navigate to http://localhost:3000
2. Login (admin / Admin123!)
3. Go to "Performance Analysis" dashboard
4. Click the **gear icon** (⚙️) at the top → **Settings**
5. Or click **Edit** button in top-right corner

---

### Step 2: Edit the "Long-Running Queries" Panel

1. Find the "Long-Running Queries (Sorted by Avg Duration)" table panel
2. Click the panel title → **Edit**
3. In the right sidebar, scroll to **Field** section
4. Click **Overrides** tab
5. Click **+ Add field override**

---

### Step 3: Add Override for Query Preview Column

1. **Fields with name matching regex**: `QueryPreview|ProcedureName`
2. Click **+ Add override property**
3. Select **Data links**
4. Click **+ Add link**

---

### Step 4: Add "Download SQL" Link

**Link 1: Download SQL**

- **Title**: `Download SQL`
- **URL**:
  ```
  http://localhost:5000/api/code/1/${__data.fields.DatabaseName}/${__data.fields.SchemaName:raw}/${__data.fields.ObjectName:raw}/download
  ```
- **Open in new tab**: ✅ Checked

**Variables Explained**:
- `${__data.fields.DatabaseName}` - Database from the query result
- `${__data.fields.SchemaName:raw}` - Schema (usually "dbo")
- `${__data.fields.ObjectName:raw}` - Procedure or query object name

---

### Step 5: Add "Open in SSMS" Link

Still in the same override, click **+ Add link** again:

**Link 2: SSMS Launcher**

- **Title**: `Open in SSMS (Windows)`
- **URL**:
  ```
  http://localhost:5000/api/code/1/${__data.fields.DatabaseName}/${__data.fields.SchemaName:raw}/${__data.fields.ObjectName:raw}/ssms-launcher
  ```
- **Open in new tab**: ✅ Checked

---

### Step 6: Save Changes

1. Click **Apply** (top-right)
2. Click **Save dashboard** (disk icon)
3. Add note: "Added SSMS integration links"
4. Click **Save**

---

## Method 2: For Stored Procedures Panel

Repeat the same steps for the **"Stored Procedures by Execution Count"** panel:

1. Edit the "Stored Procedures" panel
2. Add field override for `ProcedureName`
3. Add the same two data links (Download SQL, Open in SSMS)
4. **Important**: The URL should extract procedure name from `ProcedureName` field

**Modified URL for Procedures**:

Assuming `ProcedureName` format is `dbo.usp_MyProcedure`:

```
http://localhost:5000/api/code/1/${__data.fields.DatabaseName}/dbo/${__data.fields.ProcedureName:raw}/download
```

**Note**: This assumes schema is always `dbo`. For dynamic schemas, you'd need to parse the ProcedureName.

---

## Alternative: Hardcode Schema to "dbo"

If your queries don't return a `SchemaName` column, you can hardcode it:

```
http://localhost:5000/api/code/1/${__data.fields.DatabaseName}/dbo/${__data.fields.ProcedureName:raw}/download
```

---

## Verifying It Works

### Test 1: Check Link Appears

1. Go to Performance Analysis dashboard
2. Look at the "Long-Running Queries" table
3. Find a row with data
4. Hover over the `QueryPreview` or `ProcedureName` value
5. You should see clickable link icons appear

---

### Test 2: Click "Download SQL"

1. Click the link
2. A file should download (e.g., `dbo.usp_MyProcedure.sql`)
3. Open the file in a text editor
4. Verify it contains:
   - Connection info in header comments
   - Full procedure definition

---

### Test 3: Click "Open in SSMS" (Windows only)

1. Click the SSMS link
2. A `.bat` file downloads (e.g., `Open-dbo.usp_MyProcedure-in-SSMS.bat`)
3. Double-click the batch file
4. SSMS should launch with:
   - Connected to `sqltest.schoolvision.net,14333`
   - Database switched to the correct database
   - Procedure code loaded in a query window

---

## Troubleshooting

### Issue: Links don't appear

**Cause**: Field override not matching the column name

**Solution**:
1. Edit panel
2. Check the exact column name in the query result
3. Update the field override matcher to match that exact name

---

### Issue: "Object not found" error when clicking link

**Cause**: Object code not cached yet

**Solution**: The API will automatically cache it on first request. If it still fails:

```sql
-- Manually cache the object
EXEC dbo.usp_CacheObjectCode
    @ServerID = 1,
    @DatabaseName = 'YourDatabase',
    @SchemaName = 'dbo',
    @ObjectName = 'YourProcedure';
```

---

### Issue: Wrong URL format

**Cause**: Grafana variables not interpolating correctly

**Solution**: Check that your SQL query returns the required fields:
- `DatabaseName`
- `SchemaName` (or hardcode to "dbo")
- `ObjectName` or `ProcedureName`

**Example SQL Query** (should include these columns):

```sql
SELECT
    DatabaseName,
    'dbo' AS SchemaName,  -- Hardcoded if not available
    ProcedureName AS ObjectName,
    AvgDurationMs,
    ExecutionCount
FROM dbo.ProcedureMetrics
WHERE ServerID = 1
  AND DatabaseName LIKE CASE WHEN '$database' = 'All' THEN '%' ELSE '$database' END
ORDER BY AvgDurationMs DESC;
```

---

## Advanced: Using Transformations to Build Links

If your query doesn't have the right column format, use Grafana transformations:

### Step 1: Add Transformation

1. Edit panel
2. Go to **Transform** tab
3. Click **+ Add transformation**
4. Select **Add field from calculation**

---

### Step 2: Extract Schema from ProcedureName

**Transform**: Extract string before first `.` as SchemaName

1. Mode: **Reduce row**
2. Calculations: **Custom**
3. Expression:
   ```
   ${__field.name:text}.split('.')[0]
   ```

---

### Step 3: Extract Object Name

**Transform**: Extract string after first `.` as ObjectName

1. Mode: **Reduce row**
2. Calculations: **Custom**
3. Expression:
   ```
   ${__field.name:text}.split('.')[1]
   ```

---

## Summary

**Setup Steps**:
1. Edit dashboard → Edit panel
2. Field → Overrides → Add override
3. Match field name (e.g., `ProcedureName`)
4. Add override property → Data links
5. Add "Download SQL" link
6. Add "Open in SSMS" link
7. Save dashboard

**Link URL Format**:
```
http://localhost:5000/api/code/{serverId}/{database}/{schema}/{object}/download
http://localhost:5000/api/code/{serverId}/{database}/{schema}/{object}/ssms-launcher
```

**Variables**:
- `{serverId}` = `1` (hardcoded for now)
- `{database}` = `${__data.fields.DatabaseName}`
- `{schema}` = `${__data.fields.SchemaName:raw}` or hardcode to `dbo`
- `{object}` = `${__data.fields.ObjectName:raw}` or `${__data.fields.ProcedureName:raw}`

---

**Next**: Test the links in Grafana and verify they download the correct files!
