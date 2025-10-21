# Getting Started

Quick setup guide for new developers cloning this dbt project.

## Prerequisites

- Python 3.12+
- Git
- [uv](https://github.com/astral-sh/uv) (Python package manager)
- Dune API key

## Initial Setup

### 1. Clone and Install

```bash
git clone <repo-url>
cd dune-dbt-template
uv sync
source .venv/bin/activate
```

### 2. Configure Credentials

```bash
cp .env.example .env
```

Edit `.env` and set:
```bash
DUNE_API_KEY=your_api_key_here
DUNE_TEAM_NAME=your_team_name
DEV_SCHEMA_SUFFIX=your_name  # Optional: your personal dev space
```

### 3. Load Environment and Test Connection

```bash
# Load environment variables
set -a && source .env && set +a

# Install dbt packages
dbt deps

# Test connection
dbt debug
```

You should see: `All checks passed!`

## Your First Run

```bash
# Run all models (writes to dev schema)
dbt run

# Run tests
dbt test

# View documentation
dbt docs generate && dbt docs serve
```

## Development Targets

- **`dev` (default)**: Writes to `{team}__tmp_{suffix}` schemas - safe for development
- **`prod`**: Writes to `{team}` schemas - production tables (use with caution)

To use prod target:
```bash
dbt run --target prod
```

## Next Steps

- Read [Development Workflow](development-workflow.md) to learn the recommended process
- Review [dbt Best Practices](dbt-best-practices.md) for repo-specific patterns
- Check [SQL Style Guide](sql-style-guide.md) for formatting standards

