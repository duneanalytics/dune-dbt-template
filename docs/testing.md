# Testing

Testing strategy and requirements for dbt models.

## Schema Configuration (Required)

**All models highly recommended to be declared in a `schema.yml` file.**

Minimum requirement:
```yaml
version: 2

models:
  - name: my_model_name
```

Optional metadata (recommended):
```yaml
version: 2

models:
  - name: my_model_name
    description: "What this model does"
    tags: ['daily']
    columns:
      - name: column_name
        description: "Column description"
```

## Required Tests for Incremental Models

**If your model uses unique keys, you should add tests:**

1. `dbt_utils.unique_combination_of_columns` for the unique key
2. `not_null` for each column in the unique key

### Example: Composite Unique Key

Model (`ethereum_transactions.sql`):
```sql
{{ config(
    alias = 'ethereum_transactions'
    , materialized = 'incremental'
    , incremental_strategy = 'merge'
    , unique_key = ['block_date', 'transaction_hash']
) }}
```

Schema (`schema.yml`):
```yaml
version: 2

models:
  - name: ethereum_transactions
    data_tests:
      - dbt_utils.unique_combination_of_columns:
          combination_of_columns:
            - block_date
            - transaction_hash
    columns:
      - name: block_date
        tests:
          - not_null
      - name: transaction_hash
        tests:
          - not_null
```

### Example: Single Unique Key

Model (`user_balances.sql`):
```sql
{{ config(
    alias = 'user_balances'
    , materialized = 'incremental'
    , incremental_strategy = 'merge'
    , unique_key = 'user_address'
) }}
```

Schema (`schema.yml`):
```yaml
version: 2

models:
  - name: user_balances
    data_tests:
      - dbt_utils.unique_combination_of_columns:
          combination_of_columns:
            - user_address
    columns:
      - name: user_address
        tests:
          - not_null
```

## Optional Tests

Use based on your data quality requirements:

- `unique` - Single-column unique constraints
- `accepted_values` - Enum/categorical validation
- `relationships` - Foreign key checks
- Custom tests in `tests/` directory

Example:
```yaml
columns:
  - name: status
    tests:
      - accepted_values:
          values: ['active', 'inactive', 'pending']
  - name: user_id
    tests:
      - relationships:
          to: ref('users')
          field: id
```

## Running Tests

```bash
# Test all models
dbt test

# Test specific model
dbt test --select my_model

# Test specific model and downstream
dbt test --select my_model+

# Run and test in sequence
dbt run --select my_model && dbt test --select my_model
```

## Why These Tests?

**For incremental models:**
- `unique_combination_of_columns` - Catches duplicates from failed merges
- `not_null` - Prevents NULL key values that cause merge failures

NULL values in unique keys → merge lookups fail → duplicates inserted → data quality issues.

## Test Failures in CI

Pull requests run tests automatically. Failed tests block merging.

To fix test failures:
1. Check test output for specific failures
2. Query the model to investigate data
3. Fix the underlying issue (not the test)
4. Re-run tests locally before pushing

## See Also

- [dbt Best Practices](dbt-best-practices.md) - NULL handling in unique keys
- [CI/CD](cicd.md) - How tests run in GitHub Actions

