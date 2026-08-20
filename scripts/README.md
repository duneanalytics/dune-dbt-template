# Scripts

Example scripts for use alongside this template. These are **examples, not supported
Dune tooling**. Nothing in the dbt project invokes them, and you are free to delete or
replace them.

## drop_tables.py

Drops a single table or view in a Dune schema via the Trino API.

### Managing storage is your responsibility

A dbt project accumulates tables across dev, CI and production schemas, and those
tables occupy storage until you remove them. Dune's SQL interface supports
`DROP TABLE` and `DROP VIEW` directly, so this script is a convenience wrapper, not
the only route. A one-line `DROP` from any Trino client does the same job:

```sql
DROP TABLE dune.your_schema.your_table;
```

Decide for yourself how to keep your schemas tidy. If you want bulk cleanup, write
something that fits your environment and your review process.

### Scope

This script drops **one named object per run**, deliberately:

- `--target`, `--schema` and `--table` are all required
- No bulk mode, no pattern matching, no wildcards. A `%` in a name is rejected
- Dry run unless `--execute` is passed
- `--execute` asks for interactive confirmation, and refuses to run without a
  terminal, so it cannot be wired into automation as-is

`--target` records which environment you intend to act on and determines how the
confirmation prompt behaves. On `prod` you must retype `schema.table` to proceed. It
is a declaration of intent, **not** a safety boundary: the object dropped is always
the one you name in `--schema` and `--table`.

### Prerequisites

- `DUNE_API_KEY` set in your environment
- Dependencies installed: `uv sync`

### Usage

```bash
# Show the DROP statement, change nothing
uv run python scripts/drop_tables.py --target dev --schema my_team__tmp_ --table my_model

# Apply it, after confirming interactively
uv run python scripts/drop_tables.py --target dev --schema my_team__tmp_ --table my_model --execute

# A production object: confirmation requires retyping schema.table
uv run python scripts/drop_tables.py --target prod --schema my_team --table my_model --execute
```

### Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `--target` | yes | `dev` or `prod`. Intended environment; sets the confirmation style |
| `--schema` | yes | Exact schema name. No wildcards |
| `--table` | yes | Exact table or view name. No wildcards |
| `--execute` | no | Apply the drop. Without it, the statement is printed only |

### Behaviour

1. Validates the schema and table names, rejecting wildcards
2. Looks the object up in `information_schema.tables` by exact name, so a typo
   reports "not found" rather than quietly succeeding against a `DROP ... IF EXISTS`
3. Prints the exact `DROP` statement it would run
4. Without `--execute`, stops there and exits 0
5. With `--execute`, asks for confirmation, then runs the statement

Exit code is 0 on success or a completed dry run, and 1 on a validation failure, a
missing object, a declined confirmation, or an execution error.

### What this script does not do

- It does not drop more than one object per run
- It does not accept patterns, so it cannot sweep a schema
- It does not treat `--target` as an authorization check. Your API key's permissions
  are what actually determine what you can drop
- It does not guarantee the underlying storage is reclaimed immediately. Trino's
  `DROP TABLE` removes the metastore entry

### Tests

```bash
python3 -m unittest discover tests --verbose
```

The tests stub the Trino driver, so they issue no queries and consume no credits.
