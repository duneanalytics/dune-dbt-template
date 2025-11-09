# dune-dbt-template

A dbt project template for Dune using Trino and uv for Python package management.

> **Using this as a template?** See [SETUP_FOR_NEW_TEAMS.md](SETUP_FOR_NEW_TEAMS.md) for first-time setup instructions.

[![Latest Release](https://img.shields.io/github/v/release/duneanalytics/dune-dbt-template?label=latest%20release)](https://github.com/duneanalytics/dune-dbt-template/releases) | [CHANGELOG](CHANGELOG.md)

## 📚 Documentation

**New to this repo?** See the [docs/](docs/) directory for complete guides:

- **[Getting Started](docs/getting-started.md)** - Initial setup for new developers
- **[Development Workflow](docs/development-workflow.md)** - How to develop models
- **[dbt Best Practices](docs/dbt-best-practices.md)** - Patterns and configurations
- **[Testing](docs/testing.md)** - Test requirements
- **[CI/CD](docs/cicd.md)** - GitHub Actions workflows
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues

## Quick Setup

### 1. Install Dependencies

```bash
uv sync
```

### 2. Set Environment Variables

**Required variables:**

| Variable | Description | Where to Get |
|----------|-------------|--------------|
| `DUNE_API_KEY` | Your Dune API key for authentication | [dune.com/settings/api](https://dune.com/settings/api) |
| `DUNE_TEAM_NAME` | Your team name (determines schema where models are written) | Your Dune team name |

**Optional variables:**

| Variable | Description | Default |
|----------|-------------|---------|
| `DEV_SCHEMA_SUFFIX` | Personal dev schema suffix (creates `{team}__tmp_{suffix}`) | None (uses `{team}__tmp_`) |

See [Getting Started](docs/getting-started.md#2-set-environment-variables) for multiple options to set these variables (shell profile, session export, or inline).

### 3. Install dbt Packages and Run

```bash
uv run dbt deps      # Install dbt packages
uv run dbt debug     # Test connection
uv run dbt run       # Run models (uses dev target by default)
uv run dbt test      # Run tests
```

### Target Configuration

This project uses dbt targets to control **schema naming**, not API endpoints:
- Both `dev` and `prod` targets connect to the **same production API** (`trino.api.dune.com`)
- Target names control where models are written:
  - **`dev` target** (default): Writes to `{team}__tmp_` schemas (safe for development)
  - **`prod` target**: Writes to `{team}` schemas (production tables)

**Local development** uses `dev` target by default. To test with prod target locally:
```bash
uv run dbt run --target prod  # Use prod schema naming
```

### Optional: Schema Suffix

Set `DEV_SCHEMA_SUFFIX=your_name` environment variable to use schema `{team}__tmp_{your_name}` instead of `{team}__tmp_`.

```bash
# Add to shell profile for persistence
echo 'export DEV_SCHEMA_SUFFIX=your_name' >> ~/.zshrc
source ~/.zshrc

# Or export for current session
export DEV_SCHEMA_SUFFIX=your_name

# Or inline with command
DEV_SCHEMA_SUFFIX=your_name uv run dbt run
```

To disable suffix after using it:
```bash
unset DEV_SCHEMA_SUFFIX
```

## Common Commands

```bash
uv run dbt run                             # Run all models
uv run dbt run --select model_name         # Run specific model
uv run dbt run --select model_name --full-refresh  # Full refresh incremental model
uv run dbt test                            # Run all tests
uv run dbt test --select model_name        # Test specific model
uv run dbt docs generate && uv run dbt docs serve # View documentation
```

## Cursor AI Rules

This repo includes **optional** Cursor AI guidelines in `.cursor/rules/`:

- **`dbt-best-practices.mdc`** - dbt patterns and best practices
  - Repository configs, development workflow, incremental models
  - Model organization, DuneSQL optimization, data quality

These are basic guidelines, not requirements. Cursor AI applies them automatically when available.

**Note:** SQL formatting preferences (sql-style-guide.mdc) are kept local and not committed to the repo.

## Querying Models on Dune App/API

⚠️ **Important:** Models must be queried with the `dune` catalog prefix on Dune app/API.

**Pattern:** `dune.{team_name}.{table}` (where `{team_name}` = `DUNE_TEAM_NAME` environment variable)

```sql
-- ❌ Won't work
select * from dune__tmp_.dbt_template_view_model

-- ✅ Correct (with DUNE_TEAM_NAME=dune)
select * from dune.dune.dbt_template_view_model
select * from dune.dune__tmp_.dbt_template_view_model
```

**Note:** dbt logs omit the catalog name, so copy-pasting queries from dbt output won't work directly—you must prepend `dune.` to the schema.

## Model Templates

| Type | File | Use Case |
|------|------|----------|
| View | `dbt_template_view_model.sql` | Lightweight, always fresh |
| Table | `dbt_template_table_model.sql` | Static snapshots |
| Incremental (Merge) | `dbt_template_merge_incremental_model.sql` | Efficient updates via merge |
| Incremental (Delete+Insert) | `dbt_template_delete_insert_incremental_model.sql` | Efficient updates via delete+insert |
| Incremental (Append) | `dbt_template_append_incremental_model.sql` | Append-only with deduplication |

All templates are in `models/templates/`.

## GitHub Actions

### CI Workflow (Pull Requests)

Runs on every PR. Enforces branch is up-to-date with main, then runs and tests modified models.

**Target:** Uses `dev` target with `DEV_SCHEMA_SUFFIX=pr{number}` for isolated testing

**Steps:**
1. Enforces branch is up-to-date with main
2. Runs modified models with full refresh
3. Tests modified models
4. Runs modified incremental models (incremental run)
5. Tests modified incremental models

**PR schema:** `{team}__tmp_pr{number}` (e.g., `dune__tmp_pr123`)

### Production Workflow (Scheduled)

Runs hourly on main branch. Uses state comparison to only full refresh modified models, then runs normal cadence runs.

**Target:** Sets `DBT_TARGET: prod` to write to production schemas (`{team}`)

**Steps:**
1. Downloads previous manifest (if exists)
2. **If state exists:** Runs modified models with full refresh and tests
3. Runs all models (handles incremental logic)
4. Tests all models
5. Uploads manifest for next run
6. Sends email on failure

**State comparison:** Saves `manifest.json` after each run. Next run downloads it to detect changes. Manifest expires after 90 days.

### GitHub Setup

**Required:**
1. Add Secret: `DUNE_API_KEY` (Settings → Secrets and variables → Actions → Secrets)
2. Add Variable: `DUNE_TEAM_NAME` (Settings → Secrets and variables → Actions → Variables)
   - Optional, defaults to `'dune'` if not set

**Recommended:**
1. **Public repos:** Require approval for outside contributor workflows (Settings → Actions → General → Fork pull request workflows)
   - Protects secrets from unauthorized access
   - See [SETUP_FOR_NEW_TEAMS.md](SETUP_FOR_NEW_TEAMS.md#fork-pull-request-workflow-permissions-required-for-public-repos) for details

**Email notifications:**
1. Enable workflow notifications: Profile → Settings → Notifications → Actions → "Notify me for failed workflows only"
2. Verify email address is set
3. Watch repository: Click "Watch" (any level works, even "Participating and @mentions")

## Troubleshooting

**Environment variables not set:**
```bash
# Verify variables are set
env | grep DUNE_API_KEY
env | grep DUNE_TEAM_NAME

# If not set, export them
export DUNE_API_KEY=your_api_key
export DUNE_TEAM_NAME=your_team_name
```

**Connection errors:**
```bash
uv run dbt debug  # Test connection and check for errors
```

**dbt_utils not found:**
```bash
uv run dbt deps
```

**Dependency issues:**
```bash
uv sync --reinstall
```

## Project Structure

```
models/          # dbt models and templates
macros/          # Custom Dune macros (schema overrides, sources)
  └── dune_dbt_overrides/
      └── get_custom_schema.sql  # Controls schema naming based on target
scripts/         # Utility scripts for managing your Dune dbt project
  └── drop_tables.py  # Drop tables/views by schema pattern or specific table
.cursor/         # Cursor AI rules (dbt-best-practices.mdc)
  └── rules/
      └── dbt-best-practices.mdc  # dbt patterns and configurations
profiles.yml     # Connection profile (uses env_var() to read environment variables)
dbt_project.yml  # Project configuration
```

### Schema Naming Logic

The `get_custom_schema.sql` macro determines where models are written based on the dbt target:

| Target | DEV_SCHEMA_SUFFIX | Schema Name | Use Case |
|--------|-------------------|-------------|----------|
| `prod` | (any) | `{team}` | Production tables |
| `dev` | Not set | `{team}__tmp_` | Local development |
| `dev` | Set to `pr123` | `{team}__tmp_pr123` | CI/CD per PR |
| `dev` | Set to `alice` | `{team}__tmp_alice` | Personal dev space |

This ensures safe isolation between development and production environments.

## Utility Scripts

The `scripts/` directory contains utility scripts for managing tables and schemas. See [scripts/README.md](scripts/README.md) for details.

## Links

- [dbt-trino Setup](https://docs.getdbt.com/docs/core/connect-data-platform/trino-setup)
- [dbt Documentation](https://docs.getdbt.com/)
- [uv Documentation](https://github.com/astral-sh/uv)
