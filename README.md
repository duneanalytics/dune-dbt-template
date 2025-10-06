# Dune DBT Template

A dbt project template for Dune Analytics using dbt-core, dbt-trino, and uv for Python dependency management. This template includes pre-configured GitHub Actions CI/CD pipeline, custom Dune-specific macros, and example models demonstrating views, tables, and incremental materialization.

## Prerequisites

- Python 3.12+
- [uv](https://github.com/astral-sh/uv) (install with: `curl -LsSf https://astral.sh/uv/install.sh | sh`)
- [direnv](https://direnv.net/) (optional but recommended, install with: `brew install direnv` on macOS)
- Access to Dune Trino cluster via API

## Quick Start

### 1. Set Up Environment (Choose One)

**Option A: Using direnv (Recommended)**

```bash
# Clone the repository
git clone <repo-url>
cd dune-dbt-template

# Copy and configure environment file
cp .envrc.example .envrc
# Edit .envrc with your credentials (API keys, passwords, etc.)

# Allow direnv to load the environment
direnv allow

# That's it! The .envrc file will automatically:
# - Create and activate the virtual environment with uv sync
# - Set all required environment variables
# - Activate whenever you cd into the directory
```

**Option B: Manual Setup**

```bash
# Install dependencies into virtual environment
uv sync

# Activate the virtual environment (recommended for interactive use)
source .venv/bin/activate
```

> **Note:** After activating the virtual environment, you can run `dbt` commands directly without the `uv run` prefix. If you prefer not to activate, you can use `uv run dbt <command>` instead.

### 2. Configure dbt Profile

The repository includes a `profiles.yml` file with two profile configurations:
- **`dbt_template_old`**: Legacy direct access (currently active in `dbt_project.yml`)
- **`dbt_template`**: New Dune API access

**For local development**, you can either:
1. Use the included `profiles.yml` with environment variables (set in `.envrc`)
2. Create a personal `~/.dbt/profiles.yml` to override

**Key configuration settings:**
- **Host**: `dune-api-trino.dune.com` (for API access)
- **User**: Your team name
- **Password**: Your Dune API key
- **Catalog**: `delta_prod` (for API access)
- **Session properties**: Must include `transformations: true`

See `profiles.yml` for the complete configuration and `.envrc.example` for required environment variables.

### 3. Install dbt Packages

```bash
# Install dbt_utils and other packages
uv run dbt deps
```

### 4. Test Connection

```bash
# With activated venv:
dbt debug

# Or without activation:
uv run dbt debug
```

### 5. Run dbt

```bash
# With activated venv:
dbt run
dbt test
dbt docs generate
dbt docs serve

# Or without activation (prefix each with 'uv run'):
uv run dbt run
```

## Project Structure

```
.
├── .github/
│   └── workflows/
│       └── dbt_run.yml           # PR checks CI pipeline
├── models/
│   ├── interviews/               # Interview example models
│   │   ├── uniswap_v3_trades.sql
│   │   └── _schema.yml
│   └── templates/                # Template example models
│       ├── dbt_template_view_model.sql          # Example view model
│       ├── dbt_template_table_model.sql         # Example table model
│       ├── dbt_template_incremental_model.sql   # Example incremental model
│       ├── _schema.yml                          # Model documentation & tests
│       └── _sources.yml                         # Source definitions
├── macros/
│   └── dune_dbt_overrides/
│       ├── schema.sql             # S3 bucket configuration
│       └── source.sql             # Source database resolution
├── scripts/
│   └── activate-trino-cluster.sh  # Cluster connectivity check script
├── seeds/                # CSV seed files
├── snapshots/            # Snapshot definitions
├── tests/                # Custom tests
├── dbt_project.yml       # dbt project configuration
├── packages.yml          # dbt packages (dbt_utils)
├── profiles.yml          # dbt profile configuration with env vars
├── .envrc.example        # Example environment variables
├── pyproject.toml        # uv/Python dependencies
└── uv.lock              # Locked dependencies
```

## Example Models

This template includes three example models that query Ethereum transaction data:

### 1. View Model (`dbt_template_view_model`)
- **Materialization**: View
- **Use case**: Fast-refreshing, lightweight aggregations
- **Query**: Transaction count per block for the last day

### 2. Table Model (`dbt_template_table_model`)
- **Materialization**: Table
- **Use case**: Static snapshots of data
- **Configuration**: Uses `on_table_exists='replace'` for Dune Hive metastore compatibility

### 3. Incremental Model (`dbt_template_incremental_model`)
- **Materialization**: Incremental
- **Strategy**: Merge with unique key on `[block_number, block_date]`
- **Use case**: Efficient updates with large datasets
- **Incremental logic**: Processes last 1 day on incremental runs, last 7 days on full refresh
- **Tests**: Includes `dbt_utils.unique_combination_of_columns` test

## Custom Macros

The `macros/dune_dbt_overrides/` directory contains Dune-specific macro overrides:

### S3 Bucket Configuration (`trino__create_schema`)
Configures S3 storage locations for schemas based on target environment.

### Source Database Resolution (`source`)
Automatically resolves source tables to the `delta_prod` database.

> **Note:** Additional custom macros may be present for development purposes.

## CI/CD Pipeline

The project includes a GitHub Actions workflow (`.github/workflows/dbt_run.yml`) that runs on pull requests:

### Workflow Steps:
1. **Checkout**: Pulls repository code
2. **Setup**: Installs Python 3.12 and uv package manager
3. **Dependencies**: Installs project dependencies with `uv sync`
4. **Variables**: Configures `PROFILE` environment variable for dunesql profile
5. **dbt deps**: Installs dbt packages (dbt_utils)
6. **Activate Cluster**: Runs connectivity check with retry logic (up to 10 minutes)
7. **Compile**: Validates SQL compilation (all models)
8. **Full Refresh**: Runs `interviews.**` models with `--full-refresh`
9. **Test**: Runs tests for `interviews.**` models after full refresh
10. **Incremental Run**: Runs `interviews.**` models again to test incremental logic
11. **Test Again**: Validates incremental updates for `interviews.**` models

> **Note:** Currently, the CI workflow only runs models in the `interviews/` directory. To test template models or other directories, update the `--select` flag in `.github/workflows/dbt_run.yml`.

### Runner Configuration:
- Uses self-hosted runners with label `spellbook-trino-ci`
- Requires `dunesql` profile configured at `/home/github/.dbt/profiles.yml`
- 90-minute timeout for long-running jobs

## Cluster Activation Script

The `scripts/activate-trino-cluster.sh` script ensures the Trino cluster is available before running dbt commands:
- Retries `dbt debug` up to 40 times (10 minutes total)
- 15-second wait between retries
- Fails the workflow if cluster is not available within timeout

## Common dbt Commands

> **Tip:** Activate the virtual environment first with `source .venv/bin/activate` to run these commands without the `uv run` prefix.

```bash
# Install dbt packages
dbt deps

# Compile SQL without running
dbt compile

# Run specific model
dbt run --select my_model

# Run models downstream of a specific model
dbt run --select my_model+

# Full refresh (rebuild incremental models)
dbt run --full-refresh

# Run tests
dbt test

# Run specific test
dbt test --select dbt_template_incremental_model

# Clean project (remove compiled files)
dbt clean

# Generate and serve documentation
dbt docs generate
dbt docs serve
```

### Virtual Environment Management

```bash
# Activate virtual environment (for interactive sessions)
source .venv/bin/activate

# Deactivate when done
deactivate

# Alternative: use 'uv run' without activation (good for scripts/CI)
uv run dbt run
```

## Adding Dependencies

### Python Dependencies

```bash
# Add a new Python package
uv add package-name

# Add a development dependency
uv add --dev package-name

# Update dependencies
uv sync
```

### dbt Packages

Edit `packages.yml` to add dbt packages:

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.0.0", "<2.0.0"]
  - package: calogica/dbt_expectations
    version: [">=0.8.0", "<0.9.0"]
```

Then run:
```bash
dbt deps
```

## Environment-Specific Behavior

The project uses different profiles and configurations based on the environment:

| Environment | Profile | Target | Configuration Source | Use Case |
|-------------|---------|--------|---------------------|----------|
| **Production** | `dbt_template` or `dbt_template_old` | `prod` | `profiles.yml` + env vars | Production deployments |
| **CI/Test** | `dunesql` | (runner config) | `/home/github/.dbt/profiles.yml` | GitHub Actions PR checks |
| **Development** | `dbt_template` or `dbt_template_old` | `dev` (default) | `profiles.yml` + `.envrc` | Local development |

Configure different schemas and connection details via environment variables (`.envrc`) or in your dbt profiles.

## Troubleshooting

### Cluster Connection Issues
- The activation script retries for up to 10 minutes
- Check your API key and team name in profiles.yml
- Verify `transformations: true` is set in session properties

### Schema Already Exists Errors
- Table models use `on_table_exists='replace'` to handle existing tables
- This is required for Dune Hive metastore compatibility

### Incremental Model Not Updating
- Check that `is_incremental()` logic is working: `dbt compile --select model_name`
- Verify `unique_key` configuration matches your data
- Use `--full-refresh` to rebuild from scratch

## Resources

- [dbt Documentation](https://docs.getdbt.com/)
- [dbt-trino Adapter](https://github.com/starburstdata/dbt-trino)
- [dbt_utils Package](https://github.com/dbt-labs/dbt-utils)
- [uv Documentation](https://github.com/astral-sh/uv)
- [Dune Analytics](https://dune.com/)

