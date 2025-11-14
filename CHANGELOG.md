# Changelog

All notable changes to this template will be documented in this file.

## [v1.2.0] - 2025-11-14

### Changed
- **Table Materialization Strategy**: Removed project-level `on_table_exists: replace` config (#46)
  - Now uses dbt-trino default strategy (temp table → rename sequence)
  - Allows proper schema change handling during full refreshes
  - Updated documentation to reflect this change (#48)

### Added
- **Table Maintenance Automation**: Global post-hooks for Delta Lake table optimization (#45)
  - Automatic `OPTIMIZE` command after table/incremental materializations
  - Automatic `VACUUM` command to clean up old files
  - Improves query performance and reduces storage costs
- **Table/View Drop Script**: Python utility script for manual table/view cleanup (#43)
  - Supports dropping tables and views across dev/prod environments
  - Uses Dune API key for authentication
  - Helpful for schema migrations and cleanup tasks
- **Source Read Recommendations**: Documentation for efficient source filtering (#44)
  - Best practices for lookback periods on blockchain data
  - Guidance on date-based filtering strategies

### Fixed
- **Troubleshooting Documentation**: Added guidance for `DELTA_LAKE_BAD_WRITE` errors when using `on_table_exists: replace` with schema changes

## [1.1.1] - 2025-10-30

### Changed
- **API Endpoint Update**: Updated Dune Trino API host from `dune-api-trino.dune.com` to `trino.api.dune.com` in profiles.yml (#40)

### Added
- **Security Documentation**: Added guidance for public repositories to require workflow approval for outside contributors (#41)
  - New section in SETUP_FOR_NEW_TEAMS.md explaining fork pull request workflow permissions
  - Protects secrets (DUNE_API_KEY) and prevents unauthorized workflow runs
  - Brief reference added to README.md GitHub Setup section

## [1.1.0] - 2025-10-23

### Changed
- **Environment Variable Configuration**: Standardized on environment variables instead of `.env` file approach
  - Removed `.env.example` file
  - Updated documentation with multiple setup methods (shell profile, session export, inline)
  - Simplified getting started guide with link to detailed setup options

### Added
- **GitHub Actions Workflow Enhancements**:
  - New `dbt_ci.yml` workflow (renamed from `dbt_run.yml`) for PR validation
  - New `dbt_deploy.yml` workflow for deploying modified models on push to main
  - Monthly schedule trigger on `dbt_deploy.yml` to prevent manifest artifact expiration (90-day limit)
  - Concurrency controls across production workflows to prevent concurrent writes
  - Automated manifest generation on first PR if none exists (with clear error handling)
  - State comparison logic using manifest artifacts for efficient modified-only runs

### Improved
- **Simplified `dbt_prod.yml`**: Streamlined to focus only on scheduled incremental model runs
- **Workflow naming consistency**: Job names now match workflow file names for clarity
- **Artifact management**: Proper cross-workflow artifact sharing with `dawidd6/action-download-artifact`
- **Documentation**: Updated all workflow references and setup instructions

### Fixed
- Artifact download configuration to properly reference workflow names for manifest retrieval

## [1.0.0] - 2025-10-21

### Added
- Initial dbt template structure for Dune data transformations
- Custom schema naming macro (dev vs prod targets)
- Custom source macro with `delta_prod` database default
- GitHub Actions workflows for CI/CD (PR validation and production runs)
- Complete documentation in `docs/` directory
- Setup guide for new teams
- Python dependency management with `uv`
- Model templates for all materialization types
- Cursor AI rules for dbt best practices
- Production schedule disabled by default for new template users
- Upstream tracking documentation for template updates
