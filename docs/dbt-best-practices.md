# dbt Best Practices

Key patterns and configurations for this Dune dbt repository.

## Repository-Specific Rules

### Schema Configuration

**NEVER declare `schema` property in model configs.**

Schema names are controlled automatically by `macros/dune_dbt_overrides/get_custom_schema.sql` based on:
- Target (`dev` or `prod`)
- `DUNE_TEAM_NAME` environment variable
- `DEV_SCHEMA_SUFFIX` (optional)

### Alias Configuration

**ALWAYS provide an `alias` config for every model.**

```sql
{{ config(
    alias = 'my_model_name'
    , materialized = 'view'
) }}
```

Alias is how we differentiate models since schema names are auto-managed.

### Source Configuration

The `source()` macro automatically uses `database='delta_prod'`.

To override:
```sql
{{ source('source_name', 'table_name', database='custom_db') }}
```

## Incremental Models

### Required Configuration

```sql
{{ config(
    alias = 'my_incremental_model'
    , materialized = 'incremental'
    , incremental_strategy = 'merge'           -- ALWAYS specify strategy
    , unique_key = ['date', 'id']              -- ALWAYS specify for merge/delete+insert
) }}
```

Strategies:
- `merge` - Update/insert based on unique key
- `delete+insert` - Delete matching rows, then insert
- `append` - Append-only (use with deduplication)

### NULL Handling (Critical)

**Unique key columns MUST NOT contain NULL values.**

In Trino, NULLs cause lookups to fail → duplicates inserted.

**Solutions:**
1. Filter out NULLs: `where key_column is not null`
2. Generate surrogate key: `{{ dbt_utils.generate_surrogate_key(['col1', 'col2']) }}`

### Using incremental_predicates (Caution)

Only use for time-series data where you ONLY need recent target records.

**Use when:**
- Daily aggregations, rolling metrics
- Data naturally partitioned by time

**DO NOT use when:**
- Need to check full history (e.g., DEX pool creation events)
- Reference/dimension tables

When in doubt, leave it out.

## Partitioning

### When to Partition

**Only partition if each partition will have ~1M+ rows.**

Common use cases:
- `partition_by = ['block_month']` for large event tables
- Monthly transfers, swaps, liquidity events

Small tables: partitioning hurts more than helps.

### Partition Columns in Unique Keys

**If partitioned, ALWAYS include partition column in `unique_key`.**

```sql
{{ config(
    unique_key = ['block_month', 'tx_hash', 'evt_index']  -- ✅ includes partition column
    , partition_by = ['block_month']
) }}
```

Why: Enables partition pruning during merge lookups. Dramatically faster.

## Model Organization

### Recommended Patterns

**One Model Per Protocol/Version/Blockchain**
- Separate Uniswap V2, Uniswap V3
- Separate Ethereum, Arbitrum, Polygon
- Benefits: Clear lineage, easy to debug, flexible

**Simple Union Models**
- Union across versions: add `version` column
- Union across chains: add `blockchain` column
- Keep unions simple, no complex logic

**Save Enrichments for Downstream**
- Keep staging models simple (select, rename, basic filters)
- Add metadata, lookups, calculations downstream
- Easier to iterate without rebuilding upstream

### When to Use Macros

- Logic repeats across many blockchains
- Protocols commonly forked (Uniswap V2, Compound, ERC20)

Benefits: Single source of truth, easier maintenance.

## DuneSQL Optimization

### Data Types

- Use `UINT256` and `INT256` for large numbers
- Use `VARBINARY` for binary data
- Hex without quotes: `0x039e2fb...` not `'0x039e2fb...'`
- `DATE '2025-10-08'` for block_date, `TIMESTAMP '2025-10-08'` for block_time

### Query Performance

1. **Filter by partition columns** - `block_date`, `block_time`, `evt_block_time`
2. **Never SELECT \*** - Specify columns needed
3. **Filter cross-chain tables** - Both `blockchain` AND time
4. **Use CTEs** - Break complex queries into readable parts
5. **Avoid correlated subqueries** - Use window functions instead
6. **Use LIMIT during development** - Test with small result sets
7. **Never ORDER BY without LIMIT** - Expensive on large datasets
8. **Use curated tables** - `dex.trades`, `tokens.transfers` vs raw logs

### Join Optimization

Put time filters in both ON and WHERE:
```sql
inner join ethereum.logs as l
	on t.hash = l.tx_hash
	and t.block_date = l.block_date              -- In ON clause
	and l.block_date >= timestamp '2024-10-01'   -- In ON clause
where
	t.block_date >= timestamp '2024-10-01'       -- In WHERE clause
```

## Configuration Defaults

Set globally in `dbt_project.yml`, do not override:
- `view_security: invoker` - Required for Dune views
- `on_table_exists: replace` - Required due to Hive metastore limitations
- `require_certificate_validation: true` - Security requirement

## See Also

- [Development Workflow](development-workflow.md) - Step-by-step process
- [Testing](testing.md) - Test requirements
- [SQL Style Guide](sql-style-guide.md) - Formatting standards

