# dbt Project with Trino

A simple dbt project template using dbt-core, dbt-trino, and uv for Python dependency management.

## Prerequisites

- Python 3.12+
- [uv](https://github.com/astral-sh/uv) (install with: `curl -LsSf https://astral.sh/uv/install.sh | sh`)
- Access to a Trino/Starburst cluster

## Quick Start

### 1. Install Dependencies

```bash
# Install dependencies into virtual environment
uv sync

# Activate the virtual environment (recommended for interactive use)
source .venv/bin/activate
```

> **Note:** After activating the virtual environment, you can run `dbt` commands directly without the `uv run` prefix. If you prefer not to activate, you can use `uv run dbt <command>` instead.

### 2. Configure dbt Profile

Create your dbt profile at `~/.dbt/profiles.yml`:

```bash
# Copy the example file
mkdir -p ~/.dbt
cp profiles.yml.example ~/.dbt/profiles.yml
```

Edit `~/.dbt/profiles.yml` with your Trino connection details. See the [dbt-trino setup docs](https://docs.getdbt.com/docs/core/connect-data-platform/trino-setup) for authentication options.

### 3. Test Connection

```bash
# With activated venv:
dbt debug

# Or without activation:
uv run dbt debug
```

### 4. Run dbt

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
├── models/               # SQL models
├── macros/               # Jinja macros
├── seeds/                # CSV seed files
├── snapshots/            # Snapshot definitions
├── tests/                # Custom tests
├── dbt_project.yml       # dbt project configuration
├── pyproject.toml        # uv/Python dependencies
├── uv.lock              # Locked dependencies
└── profiles.yml.example  # Example dbt profile configuration
```

## Common dbt Commands

> **Tip:** Activate the virtual environment first with `source .venv/bin/activate` to run these commands without the `uv run` prefix.

```bash
# Compile SQL without running
dbt compile

# Run specific model
dbt run --select my_model

# Run models downstream of a specific model
dbt run --select my_model+

# Full refresh (rebuild incremental models)
dbt run --full-refresh

# Clean project (remove compiled files)
dbt clean
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

## Adding Python Dependencies

```bash
# Add a new Python package
uv add package-name

# Add a development dependency
uv add --dev package-name

# Update dependencies
uv sync
```

## Authentication Methods

The example profile uses LDAP authentication. For other methods (OAuth, JWT, Kerberos, etc.), refer to:
- [dbt-trino setup documentation](https://docs.getdbt.com/docs/core/connect-data-platform/trino-setup)

## Resources

- [dbt Documentation](https://docs.getdbt.com/)
- [dbt-trino Adapter](https://github.com/starburstdata/dbt-trino)
- [uv Documentation](https://github.com/astral-sh/uv)
- [Trino Documentation](https://trino.io/docs/)

