# Development Workflow

## Two Ways to Work with dbt

### Option 1: Activate Virtual Environment (Recommended for interactive work)

**Do this once per terminal session:**

```bash
# Navigate to project
cd /path/to/data-transformations-dbt-template

# Activate virtual environment
source .venv/bin/activate

# Your prompt will show: (.venv) $
```

**Then run dbt commands directly:**

```bash
dbt debug
dbt run
dbt test
dbt docs generate
```

**When finished:**

```bash
deactivate
```

### Option 2: Use `uv run` (No activation needed)

**Good for scripts, CI/CD, or one-off commands:**

```bash
uv run dbt debug
uv run dbt run
uv run dbt test
```

## Typical Development Session

```bash
# 1. Start your session
cd /path/to/data-transformations-dbt-template
source .venv/bin/activate

# 2. Work on your models
# Edit files in models/

# 3. Run your changes
dbt run

# 4. Test your changes
dbt test

# 5. Iterate as needed
# Edit -> Run -> Test -> Repeat

# 6. Generate documentation
dbt docs generate
dbt docs serve

# 7. End your session
deactivate
```

## Managing Dependencies

```bash
# Add a new Python package
uv add package-name

# Install/sync dependencies after pulling changes
uv sync

# Update all dependencies
uv lock --upgrade
uv sync
```

## Tips

- **Always activate the venv** for interactive development sessions
- **Use `uv run`** for automated scripts or CI/CD pipelines
- The `.venv` directory is git-ignored, so each developer needs to run `uv sync`
- Check your active venv: `which python` (should show `.venv/bin/python`)

