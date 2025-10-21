# Setup for New Teams

Quick setup checklist when creating a new repo from this template.

## 1. Repository Settings

### Branch Protection (Recommended)

Settings → Branches → Add branch protection rule for `main`:
- ✅ Require pull request before merging
- ✅ Require status checks to pass (after first successful CI run)
- ✅ Require branches to be up to date before merging

### Actions Permissions

Settings → Actions → General:
- ✅ Allow all actions and reusable workflows
- OR: Allow specific actions (if your org requires it)

## 2. GitHub Secrets & Variables

### Required Secrets
Settings → Secrets and variables → Actions → Secrets

| Secret Name | Description | How to Get |
|-------------|-------------|------------|
| `DUNE_API_KEY` | Your Dune API key | [dune.com/settings/api](https://dune.com/settings/api) |

### Required Variables
Settings → Secrets and variables → Actions → Variables

| Variable Name | Description | Example |
|---------------|-------------|---------|
| `DUNE_TEAM_NAME` | Your Dune team name | `your_team` |

**Note:** If not set, `DUNE_TEAM_NAME` defaults to `'dune'`.

## 3. Update Project Configuration

### dbt_project.yml
```yaml
name: 'your_project_name'  # Change from 'dbt_template'
profile: 'your_project_name'
```

### profiles.yml
```yaml
your_project_name:  # Match the profile name above
  target: dev
  outputs:
    dev:
      # ... rest stays the same
```

### .env File
```bash
cp .env.example .env

# Edit .env:
DUNE_API_KEY=your_actual_api_key
DUNE_TEAM_NAME=your_team_name
DEV_SCHEMA_SUFFIX=your_name  # Optional
```

## 4. First Run

```bash
# Install dependencies
uv sync
source .venv/bin/activate

# Load environment
set -a && source .env && set +a

# Install dbt packages
dbt deps

# Test connection
dbt debug

# Run template models (optional - you can delete these)
dbt run
dbt test
```

## 5. Remove Template Models (Optional)

The `models/templates/` directory contains example models. You can:

**Option A - Keep as reference:**
Keep the files but don't run them (they're examples)

**Option B - Remove:**
```bash
rm -rf models/templates/
```

Then create your own models in `models/`.

## 6. Email Notifications (Optional)

To receive CI/CD failure emails:

1. Profile → Settings → Notifications → Actions
2. Select: "Notify me for failed workflows only"
3. Verify your email address
4. Watch this repository (any level works)

## 7. Customize Cursor Rules (Optional)

Cursor AI rules in `.cursor/rules/` are optional guidelines:
- `dbt-best-practices.mdc` is committed (team-wide)
- `sql-style-guide.mdc` is gitignored (personal preference)

Modify `dbt-best-practices.mdc` to fit your team's needs, or remove if not using Cursor.

## 8. First Pull Request

Create a test PR to verify CI workflow:

```bash
git checkout -b test-setup
# Make a small change
git commit -am "Test CI setup"
git push origin test-setup
# Create PR on GitHub
```

Verify:
- ✅ CI workflow runs
- ✅ No secret/variable errors
- ✅ Models run successfully
- ✅ Tests pass

## Troubleshooting

If CI fails with "Secret not found":
- Double-check secret name matches exactly: `DUNE_API_KEY`
- Secrets are case-sensitive
- Make sure secret is set at repository level (not environment)

If schema errors:
- Verify `DUNE_TEAM_NAME` variable is set
- Check that your Dune team name matches exactly

## Next Steps

Once setup is complete:
1. Read [Getting Started](docs/getting-started.md)
2. Review [Development Workflow](docs/development-workflow.md)
3. Check [dbt Best Practices](docs/dbt-best-practices.md)
4. Start building your models!

## Support

- See [Troubleshooting](docs/troubleshooting.md) for common issues
- Check [CI/CD](docs/cicd.md) for GitHub Actions details

