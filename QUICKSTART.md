# Quick Start Guide

## Setup Checklist

- [x] ✅ uv project initialized
- [x] ✅ dbt-core and dbt-trino installed
- [x] ✅ dbt project created
- [ ] ⏳ Activate virtual environment with `source .venv/bin/activate`
- [ ] ⏳ Configure your Trino connection in `~/.dbt/profiles.yml`
- [ ] ⏳ Test connection with `dbt debug`

## Next Steps

### 1. Activate Virtual Environment (Recommended)

```bash
# Activate the virtual environment
source .venv/bin/activate

# Your prompt should now show (.venv) prefix
# Now you can run dbt commands directly without 'uv run'
```

> **Alternative:** Skip activation and prefix all commands with `uv run` (e.g., `uv run dbt debug`)

### 2. Configure Your Connection

```bash
# Create dbt config directory
mkdir -p ~/.dbt

# Copy example profile
cp profiles.yml.example ~/.dbt/profiles.yml

# Edit with your Trino connection details
nano ~/.dbt/profiles.yml  # or use your preferred editor
```

**Required settings in `profiles.yml`:**
- `host`: Your Trino/Starburst server hostname
- `port`: Usually 443 for TLS-enabled clusters
- `database`: Catalog name in Trino
- `schema`: Schema within the catalog
- `user`: Your username
- `password`: Your password (for LDAP auth)

### 3. Test Your Connection

```bash
# With activated venv (recommended):
dbt debug

# Or without activation:
uv run dbt debug
```

You should see:
```
All checks passed!
```

### 4. Run Your First Models

```bash
# Run the example models (venv activated)
dbt run

# Expected output:
# - 2 models will be created as views in your Trino schema
```

### 5. Explore the Example Models

Look at these files to understand the structure:
- `models/example/my_first_dbt_model.sql`
- `models/example/my_second_dbt_model.sql`
- `models/example/schema.yml`

### 6. Create Your Own Models

```bash
# Create a new model file
cat > models/my_model.sql << 'EOF'
{{ config(materialized='table') }}

select
    1 as id,
    'example' as name
EOF

# Run just your new model (venv activated)
dbt run --select my_model
```

## Common Commands

> **Tip:** These commands assume you've activated the virtual environment with `source .venv/bin/activate`

```bash
# Compile without running
dbt compile

# Run specific model
dbt run --select my_model

# Run tests
dbt test

# Generate docs
dbt docs generate
dbt docs serve
```

## Virtual Environment Tips

```bash
# Activate for the session (do this once per terminal session)
source .venv/bin/activate

# You'll see (.venv) in your prompt
# Now all 'dbt' commands work directly

# When done, deactivate
deactivate

# Alternative: run without activation (each command)
uv run dbt <command>
```

## Troubleshooting

### "Profile not found" error
- Make sure `~/.dbt/profiles.yml` exists
- Verify the profile name matches `dbt_template` (as set in `dbt_project.yml`)

### Connection errors
- Check your Trino host, port, and credentials
- Test connectivity: `curl https://your-trino-host:443`
- Verify catalog and schema exist and you have access

### "keyring module not found" warning
This is just a warning. OAuth tokens won't be cached, but LDAP/JWT/other auth methods work fine. To fix:
```bash
uv add 'trino[external-authentication-token-cache]'
```

## Documentation

- [dbt-trino Setup](https://docs.getdbt.com/docs/core/connect-data-platform/trino-setup)
- [dbt Documentation](https://docs.getdbt.com/)
- [uv Documentation](https://github.com/astral-sh/uv)

