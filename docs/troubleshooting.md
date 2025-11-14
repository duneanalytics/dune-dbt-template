# Troubleshooting

Common issues and solutions.

## Environment Issues

### Environment Variables Not Set

**Symptom:** Connection failures, schema errors

**Solution:**
```bash
# Verify environment variables are set
env | grep DUNE_API_KEY
env | grep DUNE_TEAM_NAME

# If not set, export them (bash/zsh)
export DUNE_API_KEY=your_api_key
export DUNE_TEAM_NAME=your_team_name

# Or for fish
set -x DUNE_API_KEY your_api_key
set -x DUNE_TEAM_NAME your_team_name

# If DEV_SCHEMA_SUFFIX is set and you want to disable it:
unset DEV_SCHEMA_SUFFIX
```

### Dependency Issues

**Symptom:** Package import errors, command not found

**Solution:**
```bash
# Reinstall dependencies
uv sync --reinstall

# Verify installation
uv run dbt --version
```

## Connection Issues

### Connection Timeout / Failure

**Symptom:** `dbt debug` fails, connection errors

**Check:**
```bash
# Run debug to see detailed error
uv run dbt debug

# Verify API key is set
env | grep DUNE_API_KEY

# Check profiles.yml is using correct env vars
cat profiles.yml | grep -A 5 "password:"
```

**Common causes:**
- Missing or incorrect `DUNE_API_KEY`
- Environment variables not exported

### SSL Certificate Errors

**Symptom:** Certificate validation failures

**Check:** `dbt_project.yml` has:
```yaml
flags:
  require_certificate_validation: true
```

And `profiles.yml` has:
```yaml
cert: true
```

These are required and should not be changed.

## dbt Issues

### dbt_utils Not Found

**Symptom:** `dbt_utils` macro errors

**Solution:**
```bash
uv run dbt deps
```

This installs packages from `packages.yml`.

### Model Not Found

**Symptom:** `ref('model_name')` fails

**Causes:**
- Model hasn't been run yet: `uv run dbt run --select model_name`
- Typo in model name

**Check:**
```bash
# List all models
uv run dbt list

# Check specific model exists
uv run dbt list --select model_name
```

### Schema Permission Errors

**Symptom:** Cannot create/drop tables

**Check:**
- Using correct target? (`dev` vs `prod`)
- `DUNE_TEAM_NAME` matches your actual team name
- API key has correct permissions

### Incremental Model Not Updating

**Symptom:** Model runs but data doesn't update

**Causes:**
1. `is_incremental()` condition blocking all data
2. `unique_key` doesn't match any rows
3. NULL values in unique key columns

**Debug:**
```bash
# Force full refresh
uv run dbt run --select model_name --full-refresh

# Check compiled SQL
cat target/compiled/dbt_template/models/path/to/model.sql
```

### Model Full Refresh Fails with DELTA_LAKE_BAD_WRITE

**Symptom:** Full refresh fails when schema changes with error:
- `DELTA_LAKE_BAD_WRITE`
- "Failed to write Delta Lake transaction log entry"
- "Failed accessing transaction log for table: <table_name>"
- "TrinoException: Unsupported Trino column type"

**Cause:**
This occurs when:
1. You set `on_table_exists: replace` config on a table model or project-wide config
2. The model's schema changes (column types, new/removed columns)
3. You trigger a full refresh

The `replace` strategy cannot handle schema changes because of data type mismatches between the existing table schema and the new schema in the Delta Lake transaction log.

**Note:** By default (when `on_table_exists` is not configured), dbt-trino uses a temp table strategy: create temp → rename existing to backup → rename temp to final → drop backup. This default strategy handles schema changes properly.

**Solution:**

You must **manually drop the table** before running the full refresh.

**Option 1: Use the provided Python script**
```bash
# Drop a single table
uv run python scripts/drop_table.py --schema your_schema_name --table your_table_name

# Drop with target specification
uv run python scripts/drop_table.py --schema your_schema_name --table your_table_name --target dev
```

**Option 2: Use any Trino client**
Connect to the Dune Trino API endpoint and run:
```sql
DROP TABLE IF EXISTS dune.your_schema_name.your_table_name;
```

**Then run your full refresh:**
```bash
uv run dbt run --select model_name --full-refresh
```

**Prevention:**

⚠️ **Use `on_table_exists: replace` only for specific use cases.**

The default behavior (temp table strategy) is recommended because:
- It properly handles schema changes
- It avoids Delta Lake transaction log conflicts

## Query Issues

### Query on Dune App Fails

**Symptom:** Cannot query model created by dbt

**Solution:** Must use `dune.` catalog prefix:

```sql
-- ❌ WRONG
select * from team__tmp_.my_model

-- ✅ CORRECT
select * from dune.team__tmp_.my_model
```

### Out of Memory Errors

**Symptom:** Query fails with memory error

**Solutions:**
- Add date filters to limit data scanned
- Remove `ORDER BY` or add `LIMIT`
- Break into smaller CTEs
- Select only needed columns (no `SELECT *`)

## Data Quality Issues

### Duplicate Rows in Incremental Model

**Causes:**
1. NULL values in `unique_key` columns
2. Missing `unique_key` config
3. `incremental_predicates` filtering out target rows

**Solutions:**
1. Filter NULLs: `where key_column is not null`
2. Add `unique_key` config
3. Remove or adjust `incremental_predicates`

**Test:**
```bash
uv run dbt test --select model_name
```

Should catch with `dbt_utils.unique_combination_of_columns` test.

### Wrong Data After Merge

**Symptom:** Incremental updates overwrite with wrong data

**Check:**
- `unique_key` correctly identifies rows
- No NULL values in key columns
- `incremental_strategy` appropriate for use case

## Git Issues

### Merge Conflicts

```bash
# See conflicted files
git status

# Resolve conflicts manually, then:
git add .
git commit
```

### Branch Out of Sync with Main

```bash
git fetch origin
git merge origin/main
# Resolve any conflicts
git push
```

## GitHub Actions Issues

### Workflow Not Triggering

**Check:**
- Files changed are in trigger paths (see `.github/workflows/`)
- Branch is not in draft mode (for PR workflow)

### Workflow Failing

1. Click on failed workflow in Actions tab
2. Expand failed step
3. Read error message
4. Common issues:
   - Missing secrets/variables
   - Test failures (fix tests, don't skip)
   - Connection issues (check API key)

## Still Stuck?

1. Check dbt logs: `logs/dbt.log`
2. Run with verbose flag: `uv run dbt run --select model_name --debug`
3. Check compiled SQL: `target/compiled/dbt_template/models/path/to/model.sql`
4. Query result directly in Dune app to verify data

## See Also

- [Getting Started](getting-started.md) - Initial setup
- [Development Workflow](development-workflow.md) - Development process
- [Testing](testing.md) - Test requirements

