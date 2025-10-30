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
- ✅ **Allow all actions and reusable workflows** (required for workflows to run)
- OR: Allow specific actions (if your org requires it)

**Note:** This template uses GitHub-hosted runners (`ubuntu-latest`). GitHub provides and manages these automatically.

### Fork Pull Request Workflow Permissions (Required for Public Repos)

**Important:** If this is a public repository, protect your secrets and workflows from unauthorized use.

Settings → Actions → General → Fork pull request workflows from outside collaborators:
- ✅ **Require approval for all outside collaborators** (most secure, recommended)
- OR: Require approval for first-time contributors

**Why this matters:**
- Workflows have access to secrets like `DUNE_API_KEY`
- Protect team account from unnecessary workflow runs which consume credits
- This setting requires a maintainer to manually approve workflow runs from non-org members

**Note:** This only affects public repositories. Private repos automatically restrict workflow access to org members.

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

### Set Environment Variables

Add to your shell profile (recommended):

```bash
# For zsh (default on macOS)
echo 'export DUNE_API_KEY=your_actual_api_key' >> ~/.zshrc
echo 'export DUNE_TEAM_NAME=your_team_name' >> ~/.zshrc
echo 'export DEV_SCHEMA_SUFFIX=your_name' >> ~/.zshrc  # Optional
source ~/.zshrc

# For bash
echo 'export DUNE_API_KEY=your_actual_api_key' >> ~/.bashrc
echo 'export DUNE_TEAM_NAME=your_team_name' >> ~/.bashrc
echo 'export DEV_SCHEMA_SUFFIX=your_name' >> ~/.bashrc  # Optional
source ~/.bashrc

# For fish
echo 'set -x DUNE_API_KEY your_actual_api_key' >> ~/.config/fish/config.fish
echo 'set -x DUNE_TEAM_NAME your_team_name' >> ~/.config/fish/config.fish
echo 'set -x DEV_SCHEMA_SUFFIX your_name' >> ~/.config/fish/config.fish  # Optional
source ~/.config/fish/config.fish
```

Or export for current session:
```bash
export DUNE_API_KEY=your_actual_api_key
export DUNE_TEAM_NAME=your_team_name
export DEV_SCHEMA_SUFFIX=your_name  # Optional
```

## 4. First Run

```bash
# Install dependencies
uv sync

# Install dbt packages
uv run dbt deps

# Test connection
uv run dbt debug

# Run template models (optional - you can delete these)
uv run dbt run
uv run dbt test
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

## 6. Enable Production Schedule (Optional)

The production workflow is **disabled by default** to prevent automatic runs on new repos.

**When you're ready for hourly production runs:**

Edit `.github/workflows/dbt_prod.yml`:
```yaml
on:
  schedule:
    - cron: '0 * * * *'  # Uncomment these lines
  workflow_dispatch:
```

**Before enabling:**
- ✅ CI tests are passing
- ✅ You've tested production runs manually (Actions → dbt prod orchestration → Run workflow)
- ✅ You understand this will run every hour and consume GitHub Actions minutes

## Troubleshooting

If CI fails with "Secret not found":
- Double-check secret name matches exactly: `DUNE_API_KEY`
- Secrets are case-sensitive
- Make sure secret is set at repository level (not environment)

If schema errors:
- Verify `DUNE_TEAM_NAME` variable is set
- Check that your Dune team name matches exactly

## 7. Set Up Upstream Tracking (Recommended)

To receive template updates and improvements, set up upstream tracking to the original template repository.

**Add upstream remote:**
```bash
git remote add upstream https://github.com/YOUR_ORG/dune-dbt-template.git
git fetch upstream
```

**To pull in template updates later:**
```bash
git fetch upstream
git checkout main
git merge upstream/main
# Resolve any conflicts
git push origin main
```

**Why do this?**
- ✅ Get bug fixes and improvements from the template
- ✅ Receive new features and optimizations
- ✅ Stay aligned with best practices updates

**Note:** Only merge updates that make sense for your project. Review changes carefully before merging.

## Next Steps

Once setup is complete:
1. Read [Getting Started](docs/getting-started.md)
2. Review [Development Workflow](docs/development-workflow.md)
3. Check [dbt Best Practices](docs/dbt-best-practices.md)
4. Start building your models!

## Support

- See [Troubleshooting](docs/troubleshooting.md) for common issues
- Check [CI/CD](docs/cicd.md) for GitHub Actions details

