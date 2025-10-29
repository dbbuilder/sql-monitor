# Blog Article Deployment Guide

**Last Updated**: 2025-10-29
**Status**: Automated

---

## Overview

The SQL Server Optimization Blog is **automatically deployed** with every SQL Monitor installation. All 12 articles are embedded in the Dashboard Browser's blog panel and require no manual setup.

---

## How It Works

### 1. Articles Are Pre-Embedded in Dashboard JSON

All 12 articles exist in a single location:
```
dashboards/grafana/dashboards/00-dashboard-browser.json
```

Specifically in **panel id: 10** (the markdown text panel at the bottom of the page).

### 2. Deployment Process

When you deploy SQL Monitor:

```bash
# Standard deployment
./deploy.sh \
  --sql-server "server,port" \
  --sql-user "username" \
  --sql-password "password"
```

**What happens**:
1. ✅ Docker Compose starts Grafana container
2. ✅ Grafana reads `dashboards/grafana/provisioning/dashboards/dashboards.yaml`
3. ✅ Provisioning config points to `dashboards/grafana/dashboards/` directory
4. ✅ `00-dashboard-browser.json` loads automatically
5. ✅ Blog panel (panel 10) displays all 12 articles
6. ✅ **Done!** No additional steps needed

### 3. Verification

```bash
# After deployment, verify blog is visible
open http://localhost:9002  # or http://your-server:9002

# Login: admin / Admin123!
# Scroll to bottom of Dashboard Browser
# See "📚 SQL Server Optimization Blog" with all 12 articles
```

---

## Current State

### Articles Embedded in Dashboard

All 12 articles are currently in the blog panel markdown content:

**Location**: `00-dashboard-browser.json` → panels → id: 10 → options → content

**Format**: Single markdown string containing:
- Article titles with emoji icons
- Problem statements
- Code examples (SQL)
- Performance comparisons
- Decision matrices
- Common mistakes
- Summary checklists

**Size**: ~15,000 characters (well under Grafana 65KB markdown limit)

### Standalone Article Files

Additionally, for documentation and reference, we have created **complete standalone articles**:

```
docs/blog/
├── README.md (index of all 12 articles)
├── DEPLOYMENT.md (this file)
├── 01-indexes-based-on-statistics.md (COMPLETE - 400+ lines)
├── 02-temp-tables-vs-table-variables.md (COMPLETE - 450+ lines)
└── 03-when-cte-is-not-best.md (COMPLETE - 400+ lines)
```

**Purpose**:
- External documentation
- Training materials
- Print/PDF reference guides
- Future expansion (separate blog page)

**Note**: Articles 4-12 summaries are in the dashboard JSON but don't need standalone files yet (content is embedded).

---

## Updating Articles

### Method 1: Edit Dashboard JSON Directly (Fastest)

```bash
# 1. Edit dashboard browser
vi dashboards/grafana/dashboards/00-dashboard-browser.json

# 2. Find panel id: 10 (around line 643)
# 3. Locate "content": "# 📚 SQL Server Optimization Blog..."
# 4. Update markdown content (preserve JSON escaping)
# 5. Save

# 6. Restart Grafana
docker compose restart grafana

# 7. Verify changes (wait 10 seconds for restart)
open http://localhost:9002
```

**Example edit** (updating Article 1 title):
```json
{
  "content": "# 📚 SQL Server Optimization Blog\n\n## Best Practices and Performance Tuning Techniques\n\n---\n\n### 1️⃣ How to Add Indexes Based on Statistics (UPDATED 2025-11)\n\n**Problem**: Missing indexes are the #1 cause..."
}
```

### Method 2: Programmatic Update (For Bulk Changes)

```bash
# Use jq to update dashboard JSON
jq '.panels[] |= if .id == 10 then .options.content = $newcontent else . end' \
  --arg newcontent "$(cat updated-blog-content.md)" \
  00-dashboard-browser.json > temp.json

mv temp.json 00-dashboard-browser.json

docker compose restart grafana
```

### Method 3: Grafana UI (Manual, Not Recommended)

1. Open Dashboard Browser in Grafana
2. Click "Edit" (top right)
3. Click blog panel (bottom)
4. Edit → Panel → Options → Content (markdown editor)
5. Make changes
6. Save dashboard
7. **Warning**: Changes lost if dashboard.json redeployed!

---

## Article Content Guidelines

### Markdown Formatting

**Supported**:
- ✅ Headers (H1-H6): `#` to `######`
- ✅ Bold: `**text**`
- ✅ Italic: `*text*`
- ✅ Code blocks: ` ```sql ... ``` `
- ✅ Inline code: `` `code` ``
- ✅ Lists (ordered/unordered)
- ✅ Tables
- ✅ Links: `[text](url)`
- ✅ Horizontal rules: `---`
- ✅ Blockquotes: `>`
- ✅ Emojis: `📚 🔍 ✅ ❌`

**Not Supported** (Grafana limitations):
- ❌ HTML (stripped, except safe tags)
- ❌ JavaScript
- ❌ Images (but links to external images work)
- ❌ Embedded videos

### JSON Escaping

When embedding markdown in JSON, escape:
- Newlines: `\n`
- Quotes: `\"`
- Backslashes: `\\`

**Example**:
```json
{
  "content": "# Article Title\n\nParagraph with \"quoted text\" and backslash: \\\\"
}
```

---

## Best Practices

### 1. Keep Articles Concise

- Target: 5-10 minute read time
- Use collapsible sections if needed
- Link to external resources for deep dives

### 2. Test Code Examples

All SQL code must:
- Run on SQL Server 2019+
- Include complete context (table schemas)
- Show actual execution plans
- Include performance metrics

### 3. Use Consistent Formatting

```markdown
### Article Title

**Problem**: One-sentence problem statement

**Solution**: One-sentence solution

**Example**:
` ``sql
-- Code here
` ``

**Why**: Explanation

---
```

### 4. Version Control

Update version in article when making changes:
```markdown
**Last Updated**: 2025-11-15
**Version**: 1.1 (minor update)
```

---

## Automated Deployment Script

Create this script for easy blog updates:

```bash
#!/bin/bash
# update-blog.sh

DASHBOARD_FILE="dashboards/grafana/dashboards/00-dashboard-browser.json"
BLOG_CONTENT_FILE="docs/blog/compiled-blog.md"

echo "Compiling blog articles..."

# Compile all markdown files into single blog content
cat docs/blog/01-*.md docs/blog/02-*.md docs/blog/03-*.md > "$BLOG_CONTENT_FILE"

# Escape for JSON
ESCAPED_CONTENT=$(cat "$BLOG_CONTENT_FILE" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}')

# Update dashboard JSON
jq --arg content "$ESCAPED_CONTENT" \
  '.panels[] |= if .id == 10 then .options.content = $content else . end' \
  "$DASHBOARD_FILE" > temp.json

mv temp.json "$DASHBOARD_FILE"

echo "Blog updated in dashboard JSON"

# Restart Grafana
echo "Restarting Grafana..."
docker compose restart grafana

echo "Done! Blog updated."
```

**Usage**:
```bash
chmod +x update-blog.sh
./update-blog.sh
```

---

## Monitoring Blog Usage

### Dashboard Analytics (Future Enhancement)

Track blog panel usage with Grafana analytics:

```sql
-- Create tracking table
CREATE TABLE dbo.BlogArticleViews (
    ViewID INT IDENTITY PRIMARY KEY,
    UserID INT,
    ArticleNumber INT,  -- 1-12
    ViewTime DATETIME2 DEFAULT GETUTCDATE(),
    TimeSpentSeconds INT
);

-- Dashboard query to show most popular articles
SELECT
    ArticleNumber,
    COUNT(*) AS ViewCount,
    AVG(TimeSpentSeconds) AS AvgTimeSpent
FROM dbo.BlogArticleViews
WHERE ViewTime >= DATEADD(DAY, -30, GETUTCDATE())
GROUP BY ArticleNumber
ORDER BY ViewCount DESC;
```

---

## Troubleshooting

### Issue: Blog Panel Not Showing

**Symptoms**: Dashboard Browser loads but blog panel empty

**Solutions**:
1. Check panel ID: `jq '.panels[] | select(.id == 10)' 00-dashboard-browser.json`
2. Check content length: `jq '.panels[] | select(.id == 10) | .options.content | length' 00-dashboard-browser.json`
3. Check JSON validity: `jq . 00-dashboard-browser.json > /dev/null`
4. Restart Grafana: `docker compose restart grafana`

### Issue: Markdown Not Rendering

**Symptoms**: Blog shows raw markdown instead of formatted text

**Solutions**:
1. Check mode is "markdown": `jq '.panels[] | select(.id == 10) | .options.mode' 00-dashboard-browser.json`
2. Should return: `"markdown"` (not `"html"` or `"plaintext"`)
3. Fix: `jq '.panels[] |= if .id == 10 then .options.mode = "markdown" else . end' 00-dashboard-browser.json > temp.json`

### Issue: JSON Escaping Broken

**Symptoms**: Dashboard won't load, JSON syntax error

**Solutions**:
1. Validate JSON: `jq . 00-dashboard-browser.json`
2. Check for unescaped quotes/newlines in content
3. Re-escape content:
   ```bash
   cat article.md | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}'
   ```
4. Restore from git: `git checkout 00-dashboard-browser.json`

---

## Backup and Restore

### Backup Current Blog

```bash
# Backup entire dashboards directory
tar -czf dashboards-backup-$(date +%Y%m%d).tar.gz dashboards/

# Extract blog content only
jq '.panels[] | select(.id == 10) | .options.content' \
  dashboards/grafana/dashboards/00-dashboard-browser.json \
  > blog-backup-$(date +%Y%m%d).md
```

### Restore Blog from Backup

```bash
# Restore blog content from backup
jq --arg content "$(cat blog-backup-20251029.md)" \
  '.panels[] |= if .id == 10 then .options.content = $content else . end' \
  00-dashboard-browser.json > temp.json

mv temp.json 00-dashboard-browser.json
docker compose restart grafana
```

---

## Future Enhancements

### Planned Features

1. **Separate Blog Dashboard** (Phase 3)
   - Dedicated dashboard with one panel per article
   - Sidebar navigation
   - Search functionality
   - Print/PDF export

2. **Interactive Code Playground** (Phase 3)
   - Execute SQL examples directly in Grafana
   - SQL fiddle integration
   - Query result visualization

3. **User Comments** (Phase 3)
   - PostgreSQL or MongoDB backend
   - Article feedback and questions
   - Upvote/downvote system

4. **Article Recommendations** (AI Layer)
   - Analyze user's slow queries
   - Recommend relevant articles
   - Automated performance tips

---

## Summary

### Current Deployment: Fully Automated ✅

- ✅ All 12 articles embedded in dashboard JSON
- ✅ Deployed automatically with `docker compose up`
- ✅ No manual installation steps needed
- ✅ Available immediately on Dashboard Browser home page
- ✅ Survives Grafana restarts
- ✅ Version controlled in Git

### Article Files: Documentation Reference

- ✅ 3 complete standalone articles (01-03)
- ✅ 9 article summaries in README (04-12)
- ✅ All content embedded in dashboard JSON
- ✅ Future: Expand standalone articles as needed

### Maintenance: Simple

- Edit `00-dashboard-browser.json` panel 10
- Run `docker compose restart grafana`
- Verify at http://localhost:9002

---

**Last Updated**: 2025-10-29
**Deployment Status**: Production Ready ✅
**Auto-Deployed**: Yes (with every `docker compose up`)
