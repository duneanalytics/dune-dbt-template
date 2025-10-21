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

## Staying Updated with Template Changes

If this repo was created from the dune-dbt-template, you can pull in updates:

**Set up upstream (one-time):**
```bash
git remote add upstream https://github.com/YOUR_ORG/dune-dbt-template.git
git fetch upstream
```

**Pull in template updates:**
```bash
git fetch upstream
git checkout main
git merge upstream/main  # Review and resolve conflicts as needed
git push origin main
```

**Best practices:**
- Review changes before merging to ensure they align with your project
- Test thoroughly after merging template updates
- Consider selective merging if only certain updates are needed

## Next Steps

- Read [Development Workflow](development-workflow.md) to learn the recommended process
- Review [dbt Best Practices](dbt-best-practices.md) for repo-specific patterns
- Check [SQL Style Guide](sql-style-guide.md) for formatting standards

