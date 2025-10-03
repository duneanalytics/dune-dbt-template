# Quick Start Guide

Get up and running with the Dune DBT Template in minutes.

## Setup Checklist

- [x] ✅ uv project initialized
- [x] ✅ dbt-core and dbt-trino installed
- [x] ✅ dbt project created with example models
- [x] ✅ Custom Dune macros configured
- [x] ✅ GitHub Actions workflow ready
- [ ] ⏳ Set up environment (direnv or manual)
- [ ] ⏳ Install dbt packages with `dbt deps`
- [ ] ⏳ Configure your Dune connection in `~/.dbt/profiles.yml`
- [ ] ⏳ Test connection with `dbt debug`

## Next Steps

### 1. Set Up Your Environment (Choose One)

**Option A: Using direnv (Recommended for Local Development)**

```bash
# Install direnv if you haven't already
# macOS: brew install direnv
# Linux: see https://direnv.net/docs/installation.html

# Copy the example environment file
cp .envrc.example .envrc

# Edit .envrc with your actual credentials
nano .envrc  # or use your preferred editor

# Update these values:
# - DBT_TEMPLATE_PASSWORD (your Trino password)
# - DBT_TEMPLATE_USER (your username)
# - DBT_TEMPLATE_SCHEMA (e.g., dbt_yourname)
# - DBT_TEMPLATE_API_KEY (your Dune API key)
# - DBT_TEMPLATE_API_SCHEMA (your team name)

# Allow direnv to load the environment
direnv allow

# That's it! Your environment is ready.
# direnv will automatically:
# - Run uv sync to create/update the virtual environment
# - Activate the virtual environment
# - Set all environment variables
# - Re-activate whenever you cd into this directory
```

**Option B: Manual Setup (Without direnv)**

```bash
# Install Python dependencies
uv sync

# Activate the virtual environment (recommended)
source .venv/bin/activate

# Your prompt should now show (.venv) prefix
# Now you can run dbt commands directly without 'uv run'
```

> **Alternative:** Skip activation and prefix all commands with `uv run` (e.g., `uv run dbt debug`)

### 2. Install dbt Packages

```bash
# Install dbt_utils and other packages
dbt deps
```

### 3. Configure Your Dune Connection

```bash
# Create dbt config directory
mkdir -p ~/.dbt

# Copy example profile
cp profiles_example_file.yml ~/.dbt/profiles.yml

# Edit with your Dune connection details
nano ~/.dbt/profiles.yml  # or use your preferred editor
```

**Required settings in `profiles.yml`:**

For the `dbt_template_api` profile:
- `host`: `dune-api-trino.dune.com` (prod) or `dune-api-trino.dev.dune.com` (dev)
- `port`: `443`
- `method`: `ldap`
- `catalog`: `delta_prod`
- `schema`: Your team name (e.g., `dune`)
- `user`: Your team name
- `password`: Your Dune API key
- `session_properties.transformations`: `true` (required!)
- `http_scheme`: `https`

### 4. Test Your Connection

```bash
# With activated venv (recommended):
dbt debug

# Or without activation:
uv run dbt debug
```

You should see:
```
All checks passed!
```

### 5. Run the Example Models

```bash
# Run all models (venv activated)
dbt run

# Expected output:
# - dbt_template_view_model (view)
# - dbt_template_table_model (table)
# - dbt_template_incremental_model (incremental)
```

### 6. Run Tests

```bash
# Run all tests
dbt test

# You should see the unique_combination_of_columns test pass
```

### 7. Explore the Example Models

The template includes three example models that demonstrate different materializations:

**View Model** (`models/dbt_template_view_model.sql`):
- Lightweight, always fresh
- Counts transactions per block for last day
- Good for fast-changing data

**Table Model** (`models/dbt_template_table_model.sql`):
- Static snapshot
- Uses `on_table_exists='replace'` for Dune compatibility
- Good for static or slowly changing data

**Incremental Model** (`models/dbt_template_incremental_model.sql`):
- Efficient updates with merge strategy
- Processes last 1 day incrementally, last 7 days on full refresh
- Includes `dbt_utils` test for uniqueness
- Good for large, append-only datasets

### 8. Test Incremental Updates

```bash
# Run with full refresh
dbt run --full-refresh

# Run incrementally (only processes last day)
dbt run

# The incremental model should update efficiently
```

### 9. Create Your Own Models

```bash
# Create a new model file
cat > models/my_ethereum_model.sql << 'EOF'
{{ config(
    schema='test_schema',
    alias='my_ethereum_model',
    materialized='table'
) }}

select
    block_date,
    count(distinct "from") as unique_senders,
    count(*) as tx_count
from {{ source('ethereum', 'transactions') }}
where block_date >= now() - interval '7' day
group by block_date
EOF

# Run just your new model (venv activated)
dbt run --select my_ethereum_model
```

## Common Commands

> **Tip:** These commands assume you've activated the virtual environment with `source .venv/bin/activate`

```bash
# Compile without running
dbt compile

# Run specific model
dbt run --select my_model

# Run tests
dbt test

# Generate docs
dbt docs generate
dbt docs serve
```

## Virtual Environment Tips

**With direnv (automatic):**
```bash
# Just cd into the directory
cd /path/to/dune-dbt-template
# Environment activates automatically!

# Run commands directly
dbt run

# Leave the directory to deactivate
cd ..
```

**Without direnv (manual):**
```bash
# Activate for the session (do this once per terminal session)
source .venv/bin/activate

# You'll see (.venv) in your prompt
# Now all 'dbt' commands work directly

# When done, deactivate
deactivate

# Alternative: run without activation (each command)
uv run dbt <command>
```

## Understanding the CI/CD Pipeline

When you open a pull request, the GitHub Actions workflow automatically:

1. ✅ Checks out your code
2. ✅ Installs dependencies
3. ✅ Waits for Trino cluster (up to 10 minutes)
4. ✅ Compiles all models
5. ✅ Runs full refresh
6. ✅ Tests all models
7. ✅ Runs incremental update
8. ✅ Tests again to verify incremental logic

All models in CI use the `test_schema` (configured in `generate_schema_name` macro).

## Troubleshooting

### "Profile not found" error
- Make sure `~/.dbt/profiles.yml` exists
- Verify the profile name is `dbt_template_api` (as set in `dbt_project.yml`)
- Check that you copied from `profiles_example_file.yml`

### Connection errors
- Check your Dune API key and team name
- Verify `transformations: true` in session properties
- Test with: `dbt debug`
- Check host: `dune-api-trino.dune.com` (not `.dev.dune.com` for prod)

### "dbt_utils not found" error
- Run `dbt deps` to install packages
- Check that `packages.yml` exists

### Incremental model not updating
- Verify `unique_key` is set correctly
- Check incremental logic with: `dbt compile --select dbt_template_incremental_model`
- Use `--full-refresh` to rebuild: `dbt run --full-refresh`

### CI/CD workflow stuck on "Waiting for runner"
- Ensure your repo has access to the `spellbook-trino-ci` self-hosted runner
- Check with your GitHub org admin to enable runner access

## Documentation

- [dbt-trino Setup](https://docs.getdbt.com/docs/core/connect-data-platform/trino-setup)
- [dbt Documentation](https://docs.getdbt.com/)
- [uv Documentation](https://github.com/astral-sh/uv)

