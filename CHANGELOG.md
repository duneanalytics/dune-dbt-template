# Changelog

All notable changes to this template will be documented in this file.

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
