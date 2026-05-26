# CI/CD

Continuous integration and deployment via GitHub Actions.

## GitHub-Hosted Runners

This template uses **GitHub-hosted runners** (`ubuntu-latest`) to execute CI/CD workflows.

GitHub provides and manages these runners - no infrastructure setup required on your end.

## Pull Request Workflow (CI)

**Trigger:** Every pull request
**File:** `.github/workflows/dbt_run.yml`

### What It Does

1. Enforces branch is up-to-date with main
2. Installs dependencies and dbt packages
3. Runs modified models with `--full-refresh`
4. Tests modified models
5. Runs modified incremental models (incremental run)
6. Tests modified incremental models again

### PR Schema Isolation

Each PR gets its own isolated schema:

```
{team}__tmp_pr{number}
```

Example: `dune__tmp_pr123`

This is set via `DEV_SCHEMA_SUFFIX=pr{number}` environment variable.

### How to Pass CI

✅ **Keep branch updated:**

```bash
git fetch origin
git merge origin/main
git push
```

✅ **Test locally before pushing:**

```bash
uv run dbt run --select modified_model --full-refresh
uv run dbt test --select modified_model
```

✅ **Fix failing tests** - Don't skip tests or disable checks

## Production Workflow

**Trigger:** Manual (schedule disabled by default)
**File:** `.github/workflows/dbt_prod.yml`
**Branch:** `main` only

⚠️ **Note:** The schedule is **disabled by default** in the template. Teams must uncomment the cron line in the workflow file when ready to enable scheduled runs.

The workflow file offers two cron options:

- **Daily** (`0 6 * * *`) — the safe default. Pairs with the included date-granularity datashare example.
- **Hourly** (`0 * * * *`) — only safe if every datashare model uses a timestamp `time_column` with an hour-sized incremental window. A date `time_column` with hourly cadence re-reads the full day's partition from the destination on every MERGE, which is 24x the cross-region transfer cost on S3 Export targets. See [Cadence and sync windows](dune-datashares.md#cadence-and-sync-windows).

### What It Does

1. Downloads previous manifest (if exists)
2. **If state exists**: Runs modified models with `--full-refresh` and tests
3. Runs all models (handles incremental logic automatically)
4. Tests all models
5. Uploads manifest for next run
6. Sends email notification on failure

### State Comparison

The workflow saves `manifest.json` after each run and downloads it next time to detect changes.

- Modified models get full refresh
- Unchanged incremental models run incrementally
- Manifest expires after 90 days

### Target Configuration

Production runs use `DBT_TARGET=prod`:

- Writes to `{team}` schemas (production)
- No suffix applied

## GitHub Setup Required

### Secrets (Settings → Secrets and Variables → Actions → Secrets)

```
DUNE_API_KEY=your_api_key
```

### Variables (Settings → Secrets and Variables → Actions → Variables)

```
DUNE_TEAM_NAME=your_team_name
```

Optional - defaults to `'dune'` if not set.

## Email Notifications

To receive failure alerts:

1. **Enable notifications:**
   Profile → Settings → Notifications → Actions → "Notify me for failed workflows only"

2. **Verify email address** in GitHub settings

3. **Watch repository:**
   Click "Watch" button (any level works, even "Participating and @mentions")

## Workflow Triggers

### Pull Request Workflow

Runs when:

- PR opened, synchronized, or reopened
- Changes to: `models/`, `macros/`, `dbt_project.yml`, `profiles.yml`, `packages.yml`, workflow file

### Production Workflow

Runs when:

- Scheduled cron - **disabled by default, must be uncommented**. The workflow ships with a daily option (`'0 6 * * *'`) and a commented hourly option; see the cost note above before choosing hourly.
- Manual trigger via GitHub Actions UI

## Troubleshooting CI Failures

### Branch Not Up-to-Date

```bash
git fetch origin
git merge origin/main
git push
```

### Test Failures

Check test output in GitHub Actions logs:

```
dbt test output → specific test name → error message
```

Query the model in Dune to investigate.

### Connection Errors

- Verify `DUNE_API_KEY` secret is set correctly
- Check Dune API status

### Timeout

Workflows timeout after 30 minutes. If hitting this:

- Optimize query performance
- Add date filters during development
- Consider breaking large models into smaller pieces

## Manual Production Run

Go to Actions tab → "dbt prod orchestration" → "Run workflow"

Use this for:

- Testing deployment changes
- Forcing a full refresh
- Running outside normal schedule

## See Also

- [Development Workflow](development-workflow.md) - Local development process
- [Testing](testing.md) - Test requirements
- [Troubleshooting](troubleshooting.md) - Common issues
