# Scripts

This directory contains utility scripts for managing your Dune dbt project.

## drop_tables.py

Drops tables and views in a Dune schema via the Trino API endpoint.

### Purpose

This script connects to the Dune Trino API using the same configuration as dbt and drops tables and views based on:
- **Target environment** (dev or prod)
  - `dev` (default): Drops all tables matching `{DUNE_TEAM_NAME}__tmp_%` pattern (bulk drops allowed)
  - `prod`: **Only allows dropping ONE specific table/view at a time** (requires `--schema` and `--table`)
- **Schema pattern matching** (bulk drops are restricted to `{DUNE_TEAM_NAME}__tmp_` schemas)
- **Specific table/view** (drop a single table or view from any schema)

The script uses `INFORMATION_SCHEMA.TABLES` to find tables and generates appropriate `DROP TABLE` or `DROP VIEW` commands based on the object type.

**⚠️ Important Note on Storage**: 
- Trino's `DROP TABLE` command only removes the metastore entry, **leaving orphaned data in S3**
- S3 cleanup should be handled separately via scheduled cleanup jobs
- This script does not clean up S3 data (requires separate AWS access)

**Safety model**:
- Bulk drops (no `--table`) are only permitted against disposable dev schemas, meaning those starting with `{DUNE_TEAM_NAME}__tmp_`
- The production schema can **never** be bulk-dropped. Production objects must be dropped one at a time with `--table`
- Any drop touching a schema outside the dev namespace requires interactive confirmation
- Bulk-dropping some other non-production schema is possible, but requires the explicit `--allow-bulk-outside-dev` flag
- These rules are enforced against the schema being targeted, **not** against the `--target` flag, so they cannot be bypassed by omitting `--target prod`

### Prerequisites

- Ensure you have set the `DUNE_API_KEY` environment variable
- Optionally set `DUNE_TEAM_NAME` environment variable (defaults to 'dune')
- Install dependencies: `uv sync`

### Usage

#### Drop Dev Tables (Default)

By default, the script uses `dev` target and matches all schemas starting with `{DUNE_TEAM_NAME}__tmp_`:

```bash
# Dry run - drops all tables in dev schemas matching dune__tmp_*
# This includes dune__tmp_, dune__tmp_pr123, dune__tmp_jeff, etc.
python scripts/drop_tables.py

# Execute - actually drop dev tables
python scripts/drop_tables.py --execute
```

**Dev pattern matching uses SQL LIKE**: The pattern `dune__tmp_%` will match:
- `dune__tmp_` (exact match)
- `dune__tmp_pr123` (with PR number suffix)
- `dune__tmp_alice` (with user suffix)
- Any other schema starting with `dune__tmp_`

#### Drop Prod Tables

⚠️ **Production Restriction**: For safety, prod drops require BOTH `--schema` AND `--table`.

You can only drop **one specific table/view at a time** in prod. Bulk drops are not allowed.

```bash
# Dry run - drop specific prod table
python scripts/drop_tables.py --target prod --schema dune --table my_table

# Execute - drop specific prod table (REQUIRES CONFIRMATION)
python scripts/drop_tables.py --target prod --schema dune --table my_table --execute
```

**⚠️ Production Safety**: When using `--target prod` with `--execute`:
1. You MUST specify both `--schema` and `--table` (no pattern matching)
2. Script confirms the specific table that will be dropped
3. Requires you to type `yes` to confirm
4. Operation is cancelled if you type anything else or press Ctrl+C

**This restriction ensures prod drops are deliberate, specific, and rare.**

#### Drop Specific Schema

Drop all tables in a specific dev schema:

```bash
# Dry run - show what would be dropped
python scripts/drop_tables.py --schema dune__tmp_pr123

# Execute - actually drop the tables
python scripts/drop_tables.py --schema dune__tmp_pr123 --execute
```

⚠️ **`--schema` is a SQL LIKE pattern, not a literal name.** A value such as `%` would match every
schema the API key can see. Because of this, bulk drops are refused unless every schema the pattern
resolves to sits inside the `{DUNE_TEAM_NAME}__tmp_` dev namespace.

To bulk-drop a non-production schema outside that namespace, opt in explicitly. This still requires
interactive confirmation, and still refuses to touch the production schema:

```bash
python scripts/drop_tables.py --schema scratch_area --allow-bulk-outside-dev --execute
```

#### Drop Specific Table/View

Drop a single table or view:

```bash
# Dry run - show what would be dropped
python scripts/drop_tables.py --table my_table_name --schema my_schema

# Execute - actually drop the table
python scripts/drop_tables.py --table my_table_name --schema my_schema --execute
```

**Note**: When dropping a specific table, you must provide the exact schema name (not a pattern).

#### Additional Options

```bash
# Verbose logging for debugging
python scripts/drop_tables.py --verbose

# Specify API key directly (instead of using env var)
python scripts/drop_tables.py --execute --api-key YOUR_API_KEY_HERE
```

### Command-Line Arguments

| Argument | Description | Default |
|----------|-------------|---------|
| `--target` | Target environment: `dev` or `prod` | `dev` |
| `--schema` | Schema name or pattern (overrides `--target`) | None (uses target default) |
| `--table` | Specific table/view name (requires `--schema`) | None (drops all) |
| `--execute` | Execute the drop operations (default is dry-run) | False |
| `--allow-bulk-outside-dev` | Permit a bulk drop outside the `__tmp_` dev namespace. Never permits bulk-dropping the production schema | False |
| `--api-key` | Dune API key | `DUNE_API_KEY` env var |
| `--verbose`, `-v` | Enable verbose (debug) logging | False |

**Target Defaults**:
- `dev`: Uses schema pattern `{DUNE_TEAM_NAME}__tmp_%` (matches all dev schemas)
- `prod`: Uses schema `{DUNE_TEAM_NAME}` (exact production schema)

### Examples

```bash
# Drop all dev tables (dry run - default target)
python scripts/drop_tables.py

# Drop all dev tables (execute)
python scripts/drop_tables.py --execute

# Drop all tables in specific dev schema (dry run)
python scripts/drop_tables.py --schema dune__tmp_pr123

# Drop all tables in specific dev schema (execute)
python scripts/drop_tables.py --schema dune__tmp_pr123 --execute

# Drop specific dev table (dry run)
python scripts/drop_tables.py --table my_model --schema dune__tmp_jeff

# Drop specific dev table (execute)
python scripts/drop_tables.py --table my_model --schema dune__tmp_jeff --execute

# Drop specific PROD table (dry run - REQUIRES --schema AND --table)
python scripts/drop_tables.py --target prod --schema dune --table my_model

# Drop specific PROD table (execute - REQUIRES CONFIRMATION)
python scripts/drop_tables.py --target prod --schema dune --table my_model --execute

# Bulk drop outside the dev namespace (refused without the opt-in flag)
python scripts/drop_tables.py --schema test_% --allow-bulk-outside-dev --execute

# Verbose output for debugging
python scripts/drop_tables.py --verbose
```

### Output

#### Dry Run Mode (Default)

Shows all DROP commands that would be executed:

```
2025-11-09 15:12:47 - __main__ - WARNING - ================================================================================
2025-11-09 15:12:47 - __main__ - WARNING - DRY RUN MODE - No operations will be executed
2025-11-09 15:12:47 - __main__ - WARNING - To execute operations, add the --execute flag
2025-11-09 15:12:47 - __main__ - WARNING - ================================================================================
2025-11-09 15:12:47 - __main__ - INFO - Target: All tables matching schema pattern 'dune__tmp_%'
2025-11-09 15:12:47 - __main__ - INFO - Initialized Dune Trino connection config (host=trino.api.dune.com, catalog=dune)
2025-11-09 15:12:47 - __main__ - INFO - Connecting to Dune Trino API...
2025-11-09 15:12:47 - __main__ - INFO - Successfully connected to Dune Trino API
2025-11-09 15:12:47 - __main__ - INFO - Querying tables matching schema pattern: dune__tmp_%
2025-11-09 15:12:49 - __main__ - INFO - ================================================================================
2025-11-09 15:12:49 - __main__ - INFO - Preparing to drop 305 table(s)/view(s)
2025-11-09 15:12:49 - __main__ - INFO - ================================================================================
2025-11-09 15:12:49 - __main__ - INFO - DROP: drop table if exists dune.dune__tmp_jeff.my_table
2025-11-09 15:12:49 - __main__ - INFO - DROP: drop view if exists dune.dune__tmp_jeff.my_view
2025-11-09 15:12:49 - __main__ - INFO - DROP: drop table if exists dune.dune__tmp_pr123.another_table
...
2025-11-09 15:12:49 - __main__ - INFO - ================================================================================
2025-11-09 15:12:49 - __main__ - INFO - Drop summary: 305 successful, 0 failed
2025-11-09 15:12:49 - __main__ - INFO - ================================================================================
2025-11-09 15:12:49 - __main__ - INFO - 
2025-11-09 15:12:49 - __main__ - INFO - ================================================================================
2025-11-09 15:12:49 - __main__ - INFO - DRY RUN COMPLETE
2025-11-09 15:12:49 - __main__ - INFO - Above are the DROP commands that would be executed.
2025-11-09 15:12:49 - __main__ - INFO - Use --execute flag to actually drop the tables/views.
2025-11-09 15:12:49 - __main__ - INFO - ================================================================================
2025-11-09 15:12:49 - __main__ - INFO - Connection closed
```

#### Execute Mode

When executing with `--execute`, each drop is confirmed with ✓ or ✗:

```
2025-11-09 15:15:00 - __main__ - INFO - DROP: drop table if exists dune.dune__tmp_jeff.my_table
2025-11-09 15:15:01 - __main__ - INFO - ✓ Successfully dropped: dune__tmp_jeff.my_table
2025-11-09 15:15:01 - __main__ - INFO - DROP: drop view if exists dune.dune__tmp_jeff.my_view
2025-11-09 15:15:02 - __main__ - INFO - ✓ Successfully dropped: dune__tmp_jeff.my_view
...
2025-11-09 15:15:10 - __main__ - INFO - ================================================================================
2025-11-09 15:15:10 - __main__ - INFO - Drop summary: 305 successful, 0 failed
2025-11-09 15:15:10 - __main__ - INFO - ================================================================================
```

### Connection Details

The script uses the following connection configuration (matching `profiles.yml`):

- **Host**: `trino.api.dune.com`
- **Port**: `443`
- **User**: `dune` (fixed)
- **Catalog**: `dune` (fixed)
- **Authentication**: Basic auth with DUNE_API_KEY
- **HTTP Scheme**: HTTPS
- **Session Properties**: `transformations: true`

### How It Works

1. Reads `DUNE_API_KEY` and `DUNE_TEAM_NAME` from environment variables
2. Establishes a connection to Dune's Trino API endpoint
3. Queries `INFORMATION_SCHEMA.TABLES` based on the target:
   - **Pattern mode**: Uses `LIKE` to match schema names (e.g., `dune__tmp_%`)
   - **Specific schema**: Queries exact schema name
   - **Specific table**: Queries for exact schema and table name
4. For each table/view found:
   - Generates appropriate `DROP TABLE` or `DROP VIEW` command based on type
   - Logs the DROP command (visible in both dry run and execute modes)
   - If `--execute` flag is set, executes the DROP command
5. Displays a summary of successful and failed drops
6. Closes the connection

**Pattern Matching Behavior:**
- Default pattern `{DUNE_TEAM_NAME}__tmp_%` matches all dev schemas
- The `%` wildcard matches any characters (including none), and `_` matches any single character
- You can provide custom patterns with `--schema` (e.g., `test_%`, `staging_%`), but a bulk drop is refused unless every schema the pattern resolves to is a `__tmp_` dev schema, or `--allow-bulk-outside-dev` is passed
- Validation happens against the schemas the pattern actually resolved to, so wildcard behaviour cannot widen the blast radius unnoticed

This approach is particularly useful for:
- Cleaning up all dev schemas at once (including PR schemas)
- Cleaning up after CI/CD test runs
- Removing temporary tables from pattern-matched schemas

### Safety Features

- **Dry run by default**: Prevents accidental deletions
- **Bulk drops scoped to the dev namespace**: Enforced against the resolved schema rather than the `--target` flag, so it cannot be bypassed by omitting `--target prod`
- **Production schema can never be bulk-dropped**: Even with `--allow-bulk-outside-dev`
- **Confirmation outside the dev namespace**: Any drop touching a non-`__tmp_` schema requires typing `yes`
- **Clear logging**: All DROP commands are displayed before execution
- **Pattern visibility**: Shows which schemas are matched before dropping
- **Summary reporting**: Confirms what was dropped and if any failures occurred
- **Uses `IF EXISTS`**: DROP commands won't fail if table doesn't exist

### Tests

The guards above are covered by regression tests that stub the Trino driver, so they never connect to
Dune or touch real data. They use only the standard library, so no extra dependencies are needed:

```bash
uv run python -m unittest discover tests
```
