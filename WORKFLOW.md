# Development Workflow

This guide covers both local development and the CI/CD pipeline for the Dune DBT Template.

## Local Development

### Option 1: Using direnv (Recommended)

**Set up once:**

```bash
# Install direnv (if not already installed)
# macOS: brew install direnv
# Linux: see https://direnv.net/docs/installation.html

# Configure your shell (add to ~/.bashrc or ~/.zshrc):
eval "$(direnv hook bash)"  # for bash
eval "$(direnv hook zsh)"   # for zsh

# Navigate to project
cd /path/to/dune-dbt-template

# Copy and configure environment file
cp .envrc.example .envrc
# Edit .envrc with your actual credentials

# Allow direnv
direnv allow
```

**Then direnv handles everything automatically:**

```bash
# Just cd into the directory
cd /path/to/dune-dbt-template
# direnv automatically activates the virtual environment and sets env vars

# Run dbt commands directly
dbt deps           # Install packages
dbt debug          # Test connection
dbt compile        # Compile models
dbt run            # Run models
dbt test           # Run tests
dbt docs generate  # Generate docs
dbt docs serve     # View docs

# When you cd out, direnv automatically deactivates
cd ..
```

### Option 2: Manual Virtual Environment Activation

**Do this once per terminal session:**

```bash
# Navigate to project
cd /path/to/dune-dbt-template

# Activate virtual environment
source .venv/bin/activate

# Your prompt will show: (.venv) $
```

**Then run dbt commands directly:**

```bash
dbt deps           # Install packages
dbt debug          # Test connection
dbt compile        # Compile models
dbt run            # Run models
dbt test           # Run tests
dbt docs generate  # Generate docs
dbt docs serve     # View docs
```

**When finished:**

```bash
deactivate
```

### Option 3: Use `uv run` (No activation needed)

**Good for scripts, CI/CD, or one-off commands:**

```bash
uv run dbt deps
uv run dbt debug
uv run dbt run
uv run dbt test
```

## Typical Local Development Session

**With direnv (automatic activation):**

```bash
# 1. Navigate to project (direnv activates automatically)
cd /path/to/dune-dbt-template

# 2. Ensure dependencies are up to date
dbt deps

# 3. Work on your models
# Edit files in models/

# 4. Compile to check for errors
dbt compile --select my_model

# 5. Run specific model
dbt run --select my_model

# 6. Test your changes
dbt test --select my_model

# 7. Run incrementally (for incremental models)
dbt run --select my_incremental_model

# 8. Full refresh when needed
dbt run --select my_incremental_model --full-refresh

# 9. Iterate as needed
# Edit -> Compile -> Run -> Test -> Repeat

# 10. Generate documentation
dbt docs generate
dbt docs serve

# 11. Done! (direnv unloads when you cd out)
```

**Without direnv (manual activation):**

```bash
# 1. Start your session
cd /path/to/dune-dbt-template
source .venv/bin/activate

# 2-10. Same as above...

# 11. End your session
deactivate
```

## Working with Different Model Types

The repository includes example models in `models/templates/` and `models/interviews/`.

### View Models
```bash
# Views are always rebuilt completely
dbt run --select templates.dbt_template_view_model

# Fast to run, always fresh
# Good for: Lightweight transformations, frequently changing data
```

### Table Models
```bash
# Tables replace existing data
dbt run --select templates.dbt_template_table_model

# Uses on_table_exists='replace' for Dune compatibility
# Good for: Static snapshots, moderate-sized datasets
```

### Incremental Models
```bash
# First run (full refresh)
dbt run --select templates.dbt_template_incremental_model --full-refresh

# Subsequent runs (incremental)
dbt run --select templates.dbt_template_incremental_model

# Incremental runs only process new data (last 1 day)
# Good for: Large datasets, append-only data
```

## Managing Dependencies

### Python Dependencies

```bash
# Add a new Python package
uv add package-name

# Add a development dependency
uv add --dev package-name

# Install/sync dependencies after pulling changes
uv sync

# Update all dependencies
uv lock --upgrade
uv sync
```

### dbt Packages

```bash
# Edit packages.yml to add new dbt packages
nano packages.yml

# Install packages
dbt deps

# Example: Add dbt_expectations
# In packages.yml:
# - package: calogica/dbt_expectations
#   version: [">=0.8.0", "<0.9.0"]
```

## CI/CD Pipeline (GitHub Actions)

The project includes an automated CI/CD pipeline that runs on every pull request.

### Workflow Triggers

The workflow runs when:
- A pull request is opened
- New commits are pushed to an open PR
- A closed PR is reopened

### Pipeline Steps

```yaml
1. Check out repository code
2. Set up Python 3.12
3. Install uv package manager
4. Install dependencies (uv sync)
5. Setup environment variables (PROFILE for dunesql)
6. Install dbt packages (dbt deps)
7. Activate Trino cluster (with retry logic)
8. Compile models (dbt compile - all models)
9. Full refresh run (dbt run --full-refresh --select interviews.**)
10. Test after full refresh (dbt test --select interviews.**)
11. Incremental run (dbt run --select interviews.**)
12. Test after incremental (dbt test --select interviews.**)
```

> **Note:** The CI workflow currently only runs and tests models in the `interviews/` directory. To include other models (like those in `templates/`), update the `--select` flag in `.github/workflows/dbt_run.yml`.

### Runner Configuration

- **Runner Type**: Self-hosted Linux runner
- **Runner Label**: `spellbook-trino-ci`
- **Timeout**: 90 minutes
- **Profile**: `dunesql` (from `/home/github/.dbt/profiles.yml`)

### Environment Detection

The pipeline uses the `dunesql` profile which is configured on the self-hosted runner at `/home/github/.dbt/profiles.yml`. This profile determines the schema and connection settings used during CI runs, keeping CI test data isolated from production and development schemas.

### Cluster Activation

The `scripts/activate-trino-cluster.sh` script:
- Retries `dbt debug` up to 40 times
- Waits 15 seconds between retries
- Maximum wait time: 10 minutes
- Fails the workflow if cluster is unavailable

### Viewing Pipeline Results

1. Go to your PR on GitHub
2. Check the "Checks" tab
3. Click on "dbt_run CI pipeline" to see details
4. Review each step's output for errors

## Pull Request Workflow

### 1. Create a Feature Branch

```bash
git checkout -b feature/my-new-model
```

### 2. Develop Locally

```bash
# If using direnv, just cd to the project
cd /path/to/dune-dbt-template
# (environment activates automatically)

# Or manually activate venv
source .venv/bin/activate

# Create your model in the appropriate directory
# For example, in interviews/ or templates/
nano models/interviews/my_new_model.sql

# Test locally
dbt run --select my_new_model
dbt test --select my_new_model
```

### 3. Commit and Push

```bash
git add models/interviews/my_new_model.sql
git commit -m "Add new Ethereum analysis model"
git push origin feature/my-new-model
```

### 4. Open Pull Request

- Go to GitHub and create a PR
- The CI pipeline will automatically start
- Wait for all checks to pass ✅

### 5. Review Pipeline Results

If the pipeline fails:
- Check the GitHub Actions logs
- Fix issues locally
- Push new commits (pipeline reruns automatically)

### 6. Merge

Once all checks pass and you have approvals:
- Merge the PR
- Delete the feature branch

## Schema Naming by Environment

| Environment | Profile | Configuration | Schema Source |
|-------------|---------|---------------|---------------|
| **Production** | `dbt_template` or `dbt_template_old` | Target: `prod` | From `profiles.yml` env vars |
| **CI/Test** | `dunesql` | Self-hosted runner | `/home/github/.dbt/profiles.yml` |
| **Development** | `dbt_template` or `dbt_template_old` | Target: `dev` (default) | From `.envrc` via `profiles.yml` |

This prevents developers and CI runs from overwriting each other's data. Configure different schemas in your environment variables or dbt profiles for each environment.

## Best Practices

### Local Development
- **Use direnv** for automatic environment management (recommended)
- **Or activate the venv** manually for interactive development sessions
- **Use `uv run`** for automated scripts or one-off commands
- **Run tests locally** before pushing to reduce CI failures
- **Use model selection** to run only what you changed: `dbt run --select my_model+`

### Model Development
- **Start with views** for prototyping (fast, no storage)
- **Use tables** for moderate-sized, stable datasets
- **Use incremental** for large datasets with append-only patterns
- **Always include tests** in `_schema.yml`
- **Document your models** with descriptions

### CI/CD
- The `.venv` directory and `.envrc` file are git-ignored for security
- Each developer needs to copy `.envrc.example` to `.envrc` and configure it
- With direnv, `uv sync` runs automatically; otherwise run it manually
- Check your active venv: `which python` (should show `.venv/bin/python`)
- Pipeline uses the `dunesql` profile on the self-hosted runner
- CI currently only runs `interviews.**` models; update workflow to test other directories

### Testing
- Use `dbt_utils.unique_combination_of_columns` for composite key uniqueness
- Add `not_null` tests for critical columns
- Use `relationships` tests to validate foreign keys
- Run `dbt test` before committing

## Troubleshooting

### Local Development Issues

**direnv not loading:**
```bash
# Check if direnv is installed
direnv version

# Make sure your shell hook is configured
# Add to ~/.zshrc or ~/.bashrc:
eval "$(direnv hook zsh)"   # for zsh
eval "$(direnv hook bash)"  # for bash

# Allow the .envrc file
direnv allow
```

**Virtual environment not activating:**
```bash
# With direnv: check if .envrc exists and is allowed
ls -la .envrc
direnv allow

# Without direnv: recreate the environment
uv sync --reinstall
source .venv/bin/activate
```

**dbt_utils not found:**
```bash
# Install packages
dbt deps
```

**Connection timeout:**
```bash
# Check your profiles.yml
dbt debug

# Verify transformations: true in session_properties
```

### CI/CD Issues

**Pipeline stuck on "Waiting for runner":**
- Check that your repo has access to `spellbook-trino-ci` runner
- Contact GitHub org admin to enable runner access

**Cluster activation timeout:**
- The script retries for 10 minutes
- Check Dune API status if this persists
- Verify runner has correct profile at `/home/github/.dbt/profiles.yml`

**Schema already exists errors:**
- Table models use `on_table_exists='replace'`
- This is expected behavior for Dune Hive metastore

**Tests failing in CI but passing locally:**
- Check that your local target matches expected behavior
- Verify incremental logic works on both full refresh and incremental runs
- Use `--full-refresh` locally to match CI behavior

