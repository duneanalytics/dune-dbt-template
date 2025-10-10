# dune-dbt-template

A dbt project template for Dune using Trino and uv for Python package management.

## Quick Setup

```bash
# One time setup
cp .env.example .env
# Edit .env and set:
#   - DUNE_API_KEY: Your Dune API key (required)
#   - DUNE_TEAM_NAME: Your team name (required - defaults to 'dune')

# Every session
uv sync                        # Only needed first time or after dependency changes
source .venv/bin/activate
```

**Option A: Load env vars into shell (run multiple commands)**
```bash
set -a && source .env && set +a    # Load once, run many dbt commands
dbt deps
dbt run
dbt test
```

**Option B: Use uv's env file loading (per command)**
```bash
uv run --env-file .env dbt deps
uv run --env-file .env dbt run
uv run --env-file .env dbt test
```

## Common Commands

With **Option A** (after loading env vars into shell):
```bash
dbt deps                       # Install dbt packages
dbt debug                      # Test connection
dbt run                        # Run all models
dbt run --select my_model      # Run specific model
dbt test                       # Run tests
dbt docs generate && dbt docs serve  # View documentation
```

With **Option B** (using uv's env file loading):
```bash
uv run --env-file .env dbt deps
uv run --env-file .env dbt debug
uv run --env-file .env dbt run
uv run --env-file .env dbt run --select my_model
uv run --env-file .env dbt test
uv run --env-file .env dbt docs generate && uv run --env-file .env dbt docs serve
```

## Configuration

### Configuration Files

**`.env`** - Local credentials (never commit):
- `DUNE_API_KEY` - Your Dune API key (**required**)
- `DUNE_TEAM_NAME` - Your Dune team name (**required**, defaults to `'dune'` in profiles.yml)
- `DEV_SCHEMA_SUFFIX` - Optional suffix for dev schemas

**`profiles.yml`** - Connection configuration:
- Uses `DUNE_TEAM_NAME` env var for schema
- Default fallback is `'dune'` if env var not set
- **Alternative:** You can hardcode your team name by changing the default: `env_var('DUNE_TEAM_NAME', 'your_team')`

> **💡 Recommended setup:**
> - **Local dev**: Set `DUNE_TEAM_NAME` in `.env`
> - **CI/CD**: Set as GitHub Variable (visible in logs, defaults to `'dune'` if not set)

### DEV_SCHEMA_SUFFIX Toggle

**To enable schema suffix:**
1. Edit `.env` and set the value: `DEV_SCHEMA_SUFFIX=your_name`
2. Load the change (see below based on your workflow)
3. Run dbt - schema will be `{team}__tmp_{your_name}`

**To disable schema suffix:**
1. Edit `.env` and comment out the line: `# DEV_SCHEMA_SUFFIX=your_name`
2. Load the change (see below based on your workflow)
3. Run dbt - schema will be `{team}__tmp_` (no suffix)

**If using Option A (shell env vars):**
```bash
# To reload after enabling
set -a && source .env && set +a

# To reload after disabling (must unset first!)
unset DEV_SCHEMA_SUFFIX && set -a && source .env && set +a
```
> **⚠️ Critical:** Simply commenting out the line doesn't remove the variable from your current shell session. You **must** run `unset DEV_SCHEMA_SUFFIX` to clear it, or start a fresh terminal session.

**If using Option B (uv --env-file):**
```bash
# No special action needed - changes take effect immediately
uv run --env-file .env dbt run
```
> **✨ Benefit:** With `--env-file`, commented variables are automatically excluded each time you run a command. No manual `unset` needed!

## Model Types

Example models in `models/templates/`:

| Type | File | Use Case |
|------|------|----------|
| View | `dbt_template_view_model.sql` | Lightweight, always fresh data |
| Table | `dbt_template_table_model.sql` | Static snapshots, uses `on_table_exists='replace'` |
| Incremental | `dbt_template_incremental_model.sql` | Large datasets, efficient updates |

**Working with incremental models:**

With **Option A**:
```bash
dbt run --select model_name --full-refresh  # First run or rebuild
dbt run --select model_name                 # Subsequent incremental runs
```

With **Option B**:
```bash
uv run --env-file .env dbt run --select model_name --full-refresh  # First run or rebuild
uv run --env-file .env dbt run --select model_name                 # Subsequent incremental runs
```

## CI/CD

GitHub Actions runs on every pull request using GitHub-hosted runners. Each PR gets an isolated schema: `{team}__tmp_pr{number}` (e.g., `dune__tmp_pr123`).

**Setup:**
1. **Required**: Add GitHub Secret for API key
   - Settings → Secrets and variables → Actions → **Secrets** tab → New repository secret
   - Name: `DUNE_API_KEY`
   - Value: Your Dune API key

2. **Optional**: Set your team name (if not `'dune'`)
   - Settings → Secrets and variables → Actions → **Variables** tab → New repository variable
   - Name: `DUNE_TEAM_NAME`
   - Value: Your team name
   - **If not set, defaults to `'dune'`**

> **💡 Why use Variables instead of Secrets?**
> - Team name isn't sensitive - it's helpful to see in logs for debugging
> - GitHub Secrets mask values in logs as `***`, making troubleshooting harder
> - Variables are visible in logs and perfect for non-sensitive config

**Workflow:**
1. Compiles all models
2. Runs with full refresh
3. Tests models
4. Runs incremental update
5. Tests again

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

If using Option A (shell env vars):
```bash
set -a && source .env && set +a    # Load variables
env | grep DUNE_API_KEY            # Verify they're set
```

If using Option B (uv --env-file):
```bash
# No action needed - variables are loaded automatically per command
# Verify by checking dbt debug output
uv run --env-file .env dbt debug
```

**Schema suffix not updating:**

If using Option A and you commented out `DEV_SCHEMA_SUFFIX` but dbt still uses it:
```bash
unset DEV_SCHEMA_SUFFIX            # Clear the variable
set -a && source .env && set +a    # Reload .env
env | grep DEV_SCHEMA_SUFFIX       # Should show nothing
```
Alternatively, start a fresh terminal session.

If using Option B, changes take effect immediately - no action needed.

**Connection errors:**

With **Option A**:
```bash
dbt debug                      # Test connection
# Check .env has correct credentials
# Verify host ends with .dune.com (not .dev.dune.com for prod)
```

With **Option B**:
```bash
uv run --env-file .env dbt debug  # Test connection
# Check .env has correct credentials
```

**dbt_utils not found:**

With **Option A**: `dbt deps`  
With **Option B**: `uv run --env-file .env dbt deps`

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
