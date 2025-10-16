# dune-dbt-template

A dbt project template for Dune using Trino and uv for Python package management.

## Setup

### 1. Configure Credentials

```bash
cp .env.example .env
# Edit .env and set:
#   DUNE_API_KEY=your_api_key
#   DUNE_TEAM_NAME=your_team_name
```

### 2. Install Dependencies

```bash
uv sync
source .venv/bin/activate
```

### 3. Load Environment and Run

```bash
set -a && source .env && set +a    # Load env vars (do this once per session)
dbt deps                            # Install dbt packages
dbt debug                           # Test connection
dbt run                             # Run models (uses dev target by default)
dbt test                            # Run tests
```

### Target Configuration

This project uses dbt targets to control **schema naming**, not API endpoints:
- Both `dev` and `prod` targets connect to the **same production API** (`dune-api-trino.dune.com`)
- Target names control where models are written:
  - **`dev` target** (default): Writes to `{team}__tmp_` schemas (safe for development)
  - **`prod` target**: Writes to `{team}` schemas (production tables)

**Local development** uses `dev` target by default. To test with prod target locally:
```bash
dbt run --target prod  # Use prod schema naming
```

### Optional: Schema Suffix

Add `DEV_SCHEMA_SUFFIX=your_name` to `.env` to use schema `{team}__tmp_{your_name}` instead of `{team}__tmp_`.

To reload after changing `.env`:
```bash
set -a && source .env && set +a
```

To disable suffix after using it:
```bash
unset DEV_SCHEMA_SUFFIX && set -a && source .env && set +a
```

## Common Commands

```bash
dbt run                             # Run all models
dbt run --select model_name         # Run specific model
dbt run --select model_name --full-refresh  # Full refresh incremental model
dbt test                            # Run all tests
dbt test --select model_name        # Test specific model
dbt docs generate && dbt docs serve # View documentation
```

## Querying Models on Dune App/API

⚠️ **Important:** Models must be queried with the `dune` catalog prefix on Dune app/API.

**Pattern:** `dune.{team_name}.{table}` (where `{team_name}` = `DUNE_TEAM_NAME` from `.env`)

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

**Email notifications:**
1. Enable workflow notifications: Profile → Settings → Notifications → Actions → "Notify me for failed workflows only"
2. Verify email address is set
3. Watch repository: Click "Watch" (any level works, even "Participating and @mentions")

## Troubleshooting

**Environment variables not loading:**
```bash
set -a && source .env && set +a
env | grep DUNE_API_KEY  # Verify it's set
```

**Connection errors:**
```bash
dbt debug  # Test connection and check for errors
```

**dbt_utils not found:**
```bash
dbt deps
```

**Virtual environment issues:**
```bash
uv sync --reinstall
source .venv/bin/activate
```

## Project Structure

```
models/          # dbt models and templates
macros/          # Custom Dune macros (schema overrides, sources)
  └── dune_dbt_overrides/
      └── get_custom_schema.sql  # Controls schema naming based on target
profiles.yml     # Connection profile (uses .env variables)
dbt_project.yml  # Project configuration
.env             # Your credentials (gitignored)
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

## Links

- [dbt-trino Setup](https://docs.getdbt.com/docs/core/connect-data-platform/trino-setup)
- [dbt Documentation](https://docs.getdbt.com/)
- [uv Documentation](https://github.com/astral-sh/uv)
