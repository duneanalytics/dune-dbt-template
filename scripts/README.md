# Example scripts

The scripts in this directory are **examples, not supported Dune tooling**. They
show narrowly scoped ways to work with objects created by this dbt project. Review
and adapt them for your own environment.

## `drop_tables.py`

This example drops one exact table per invocation through the same Dune Trino API
endpoint that dbt uses: `trino.api.dune.com`. Table maintenance statements cannot
be run from the Dune app. You can use any Trino client configured with the
equivalent settings in `profiles.yml`; this script demonstrates one approach.

The script deliberately has no bulk mode, schema sweep, or pattern matching.
`--schema` and `--table` are both required, and `%` and `*` are rejected.

### Preview one table

Dry run is the default. This prints the endpoint and exact `drop table` statement,
then exits without connecting or changing anything:

```bash
uv run python scripts/drop_tables.py \
  --schema my_team__tmp_ \
  --table my_model
```

### Drop one table

`--execute` prints the same preview first. It then pauses and accepts only `Y` or
`N`. The script connects and submits the statement only after an explicit `Y`:

```bash
uv run python scripts/drop_tables.py \
  --schema my_team__tmp_ \
  --table my_model \
  --execute
```

```text
DRY RUN PREVIEW
Endpoint: trino.api.dune.com
The script would execute exactly one statement:
drop table "dune"."my_team__tmp_"."my_model"
Continue to drop the above? [Y/N]:
```

Execution requires:

- `DUNE_API_KEY` in the environment
- An interactive terminal
- Dependencies installed with `uv sync`

The script uses the connection settings in `profiles.yml`, including the
`transformations` session property. Its module docstring explains how to use it as
a starting point if your environment requires a more flexible maintenance process.

### Tests

```bash
python3 -m unittest discover tests --verbose
```

The Trino driver is stubbed, so the tests issue no queries and consume no credits.
