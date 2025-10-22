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
```

### 2. Set Environment Variables

Choose one method:

**Method A: Add to shell profile (persistent)**

```bash
# For zsh (default on macOS)
echo 'export DUNE_API_KEY=your_api_key_here' >> ~/.zshrc
echo 'export DUNE_TEAM_NAME=your_team_name' >> ~/.zshrc
echo 'export DEV_SCHEMA_SUFFIX=your_name' >> ~/.zshrc  # Optional
source ~/.zshrc

# For bash
echo 'export DUNE_API_KEY=your_api_key_here' >> ~/.bashrc
echo 'export DUNE_TEAM_NAME=your_team_name' >> ~/.bashrc
echo 'export DEV_SCHEMA_SUFFIX=your_name' >> ~/.bashrc  # Optional
source ~/.bashrc

# For fish
echo 'set -x DUNE_API_KEY your_api_key_here' >> ~/.config/fish/config.fish
echo 'set -x DUNE_TEAM_NAME your_team_name' >> ~/.config/fish/config.fish
echo 'set -x DEV_SCHEMA_SUFFIX your_name' >> ~/.config/fish/config.fish  # Optional
source ~/.config/fish/config.fish
```

**Method B: Export for current session (temporary)**

```bash
# bash/zsh
export DUNE_API_KEY=your_api_key_here
export DUNE_TEAM_NAME=your_team_name
export DEV_SCHEMA_SUFFIX=your_name  # Optional

# fish
set -x DUNE_API_KEY your_api_key_here
set -x DUNE_TEAM_NAME your_team_name
set -x DEV_SCHEMA_SUFFIX your_name  # Optional
```

**Method C: Inline with commands (one-off)**

```bash
DUNE_API_KEY=your_api_key_here DUNE_TEAM_NAME=your_team_name uv run dbt debug
```

### 3. Install dbt Packages and Test Connection

```bash
# Install dbt packages
uv run dbt deps

# Test connection
uv run dbt debug
```

You should see: `All checks passed!`

## Your First Run

```bash
# Run all models (writes to dev schema)
uv run dbt run

# Run tests
uv run dbt test

# View documentation
uv run dbt docs generate && uv run dbt docs serve
```

## Development Targets

- **`dev` (default)**: Writes to `{team}__tmp_{suffix}` schemas - safe for development
- **`prod`**: Writes to `{team}` schemas - production tables (use with caution)

To use prod target:
```bash
uv run dbt run --target prod
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

