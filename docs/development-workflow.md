# Development Workflow

Recommended process for developing dbt models.

## Step-by-Step Process

### 1. Start in Dune App

**Always prototype in Dune's web application first.**

- Write and test your query logic in Dune's query editor
- Validate data output and quality
- Test edge cases
- Iterate quickly with immediate feedback

**Why**: Faster iteration and easier debugging than dbt runs.

### 2. Convert to dbt Model

Once your query works, convert it to a dbt model.

**Choose the right materialization:**

- **`view`** - Quick queries (< 1-2 min). No data stored, runs each query
- **`table`** - Full rebuilds. For snapshots and medium datasets
- **`incremental`** - Large time-series data. Only processes new/updated rows

**Required config:**
```sql
{{ config(
    alias = 'my_model_name'       -- ALWAYS provide alias
    , materialized = 'view'        -- ALWAYS declare materialization
) }}
```

**Always use source() and ref():**
```sql
select
	t.block_time
	, t.hash
from
	{{ source('ethereum', 'transactions') }} as t
left join {{ ref('stg_users') }} as u
	on t.from = u.address
```

### 3. Start with Short Date Filters

**Use restricted date ranges during development to save credits and iterate faster.**

For incremental models:
```sql
where
	blockchain = 'ethereum'
	{%- if is_incremental() %}
	and block_date >= now() - interval '1' day  -- Incremental run
	{%- else %}
	and block_date >= now() - interval '3' day  -- Dev: only 3 days
	{%- endif %}
```

For table models:
```sql
where
	block_date >= now() - interval '7' day  -- Limit during development
```

### 4. Test End-to-End

Before expanding date ranges:

```bash
# Run your model
uv run dbt run --select my_model

# Check data quality
# Query the result in Dune app

# Run tests
uv run dbt test --select my_model

# For incremental: test multiple runs
uv run dbt run --select my_model  # Run twice to test incremental logic
```

### 5. Expand Date Ranges (When Ready)

⚠️ **Only expand when you're confident and ready to consume credits.**

When to expand:
- ✅ Model logic tested and working
- ✅ Data quality verified
- ✅ You understand credit costs
- ✅ You actually need full historical data

Remove dev filters or extend to production range:
```sql
{%- if is_incremental() %}
and block_date >= now() - interval '1' day
{%- else %}
and block_date >= timestamp '2020-01-01'  -- Full history
{%- endif %}
```

## Common Commands

```bash
uv run dbt run --select my_model                    # Run single model
uv run dbt run --select my_model --full-refresh     # Full refresh incremental
uv run dbt run --select my_model+                   # Run model + downstream
uv run dbt run --select +my_model                   # Run upstream + model
uv run dbt test --select my_model                   # Test single model
```

## Schema Naming

Your models write to different schemas based on target and suffix:

| Target | Suffix | Schema | Use |
|--------|--------|--------|-----|
| `dev` | `alice` | `{team}__tmp_alice` | Your personal dev space |
| `dev` | not set | `{team}__tmp_` | Shared dev space |
| `prod` | any | `{team}` | Production |

## Querying Your Models

Models must be queried with `dune.` catalog prefix:

```sql
-- ✅ Correct
select * from dune.{team}__tmp_alice.my_model

-- ❌ Wrong (missing catalog)
select * from {team}__tmp_alice.my_model
```

## Next Steps

- Review [dbt Best Practices](dbt-best-practices.md) for detailed patterns
- Check [Testing](testing.md) for test requirements
- See [SQL Style Guide](sql-style-guide.md) for formatting

