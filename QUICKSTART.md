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

# Update these values for the NEW API profile (dbt_template):
# - DBT_TEMPLATE_USER (defaults to 'dune')
# - DBT_TEMPLATE_API_KEY (your Dune API key from team settings)
# - DBT_TEMPLATE_HOST (dune-api-trino.dune.com for prod)
# - DBT_TEMPLATE_CATALOG (defaults to 'delta_prod')
# - DBT_TEMPLATE_SCHEMA (your Dune team name)
# - DEV_SCHEMA_SUFFIX (your name or identifier for dev schemas)
#
# Also update legacy profile values (dbt_template_old) if needed:
# - DBT_TEMPLATE_OLD_USER
# - DBT_TEMPLATE_OLD_PASSWORD
# - DBT_TEMPLATE_OLD_HOST
# - DBT_TEMPLATE_OLD_SCHEMA
# - DBT_TEMPLATE_OLD_ROUTING_GROUP
# - DBT_TEMPLATE_OLD_EXTRA_CREDENTIAL

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

The repository includes a `profiles.yml` file with two profile configurations:
- **`dbt_template_old`**: Legacy direct access (currently active in `dbt_project.yml`)
- **`dbt_template`**: New Dune API access

**For local development**, the included `profiles.yml` uses environment variables from your `.envrc` file. You can also create a personal `~/.dbt/profiles.yml` to override if needed.

**Required settings for the API profile (`dbt_template`):**
- `host`: `dune-api-trino.dune.com` (prod) or `dune-api-trino.dev.dune.com` (dev)
- `port`: `443`
- `method`: `ldap`
- `catalog`: `delta_prod`
- `schema`: Your team name (e.g., `dune`)
- `user`: Your team name
- `password`: Your Dune API key
- `session_properties.transformations`: `true` (required!)
- `http_scheme`: `https`

See `profiles.yml` and `.envrc.example` for complete configuration details.

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

The template includes example models in two directories:

**Template Models** (`models/templates/`):
- **View Model** (`dbt_template_view_model.sql`): Lightweight, always fresh
- **Table Model** (`dbt_template_table_model.sql`): Uses `on_table_exists='replace'` for Dune compatibility
- **Incremental Model** (`dbt_template_incremental_model.sql`): Efficient updates with merge strategy

**Interview Models** (`models/interviews/`):
- **Uniswap V3 Trades** (`uniswap_v3_trades.sql`): Example analysis model

All models demonstrate different materializations and best practices for Dune Analytics.

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
# Create a new model file in your desired directory
# For example, in the interviews directory:
cat > models/interviews/my_ethereum_model.sql << 'EOF'
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
5. ✅ Runs full refresh on `interviews.**` models
6. ✅ Tests `interviews.**` models
7. ✅ Runs incremental update on `interviews.**` models
8. ✅ Tests again to verify incremental logic

> **Note:** The CI pipeline currently only runs models in the `interviews/` directory. To test other models, update the `--select` flag in `.github/workflows/dbt_run.yml`.

The workflow uses the `dunesql` profile from the self-hosted runner's configuration.

## Troubleshooting

### "Profile not found" error
- The repository includes `profiles.yml` that uses environment variables
- If using direnv, make sure `.envrc` is configured and allowed
- Verify the profile name is `dbt_template_old` (as currently set in `dbt_project.yml`)
- You can also create `~/.dbt/profiles.yml` to override the repo profile

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

