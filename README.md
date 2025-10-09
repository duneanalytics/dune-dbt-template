# dune-dbt-template

A dbt project template for Dune using Trino and uv for Python package management.

## Quick Setup

```bash
# One time
cp .env.example .env
# Edit .env with your credentials

# Every session
uv sync                        # Only needed first time or after dependency changes
source .venv/bin/activate
source .env
```

## Common Commands

```bash
dbt deps                       # Install dbt packages
dbt debug                      # Test connection
dbt run                        # Run all models
dbt run --select my_model      # Run specific model
dbt test                       # Run tests
dbt docs generate && dbt docs serve  # View documentation
```

## Configuration

### Environment Variables

Required variables in `.env`:
- `DBT_TEMPLATE_USER` - user is always 'dune'
- `DBT_TEMPLATE_API_KEY` - Your Dune API key
- `DBT_TEMPLATE_HOST` - `dune-api-trino.dune.com` (prod) or `dune-api-trino.dev.dune.com` (dev)
- `DBT_TEMPLATE_CATALOG` - catalog is always 'dune'
- `DBT_TEMPLATE_SCHEMA` - Your Dune team name
- `DEV_SCHEMA_SUFFIX` - Optional suffix for development schemas

### DEV_SCHEMA_SUFFIX Toggle

To enable/disable the schema suffix, edit `.env` and uncomment one option:

```bash
# Option 1: Use suffix
export DEV_SCHEMA_SUFFIX=jeff
# unset DEV_SCHEMA_SUFFIX

# Option 2: No suffix
# export DEV_SCHEMA_SUFFIX=jeff
unset DEV_SCHEMA_SUFFIX
```

Then reload: `source .env`

> **Why `unset`?** Commenting out a variable doesn't remove it. `unset` explicitly clears it.

## Model Types

Example models in `models/templates/`:

| Type | File | Use Case |
|------|------|----------|
| View | `dbt_template_view_model.sql` | Lightweight, always fresh data |
| Table | `dbt_template_table_model.sql` | Static snapshots, uses `on_table_exists='replace'` |
| Incremental | `dbt_template_incremental_model.sql` | Large datasets, efficient updates |

**Working with incremental models:**
```bash
dbt run --select model_name --full-refresh  # First run or rebuild
dbt run --select model_name                 # Subsequent incremental runs
```

## Project Structure

```
models/          # dbt models and templates
macros/          # Custom Dune macros (schema overrides, sources)
profiles.yml     # Connection profile (uses .env variables)
dbt_project.yml  # Project configuration
.env             # Your credentials (gitignored)
.env.example     # Template for .env
```

## Troubleshooting

**Environment variables not set:**
```bash
source .env                    # Load variables
env | grep DBT_TEMPLATE        # Verify they're set
```

**Connection errors:**
```bash
dbt debug                      # Test connection
# Check .env has correct credentials
# Verify host ends with .dune.com (not .dev.dune.com for prod)
```

**dbt_utils not found:**
```bash
dbt deps                       # Install packages
```

**Virtual environment issues:**
```bash
uv sync --reinstall            # Recreate venv
source .venv/bin/activate
```

## Dependencies

**Python packages:**
```bash
uv add package-name            # Add package
uv sync                        # Sync dependencies
```

**dbt packages:**
```bash
# Edit packages.yml
dbt deps                       # Install
```

## Documentation

- [dbt-trino Setup](https://docs.getdbt.com/docs/core/connect-data-platform/trino-setup)
- [dbt Documentation](https://docs.getdbt.com/)
- [uv Documentation](https://github.com/astral-sh/uv)
