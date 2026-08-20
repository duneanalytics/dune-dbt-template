#!/usr/bin/env python3
"""
Example script: drop one table through the Dune Trino API endpoint.

This is an example use case, not a supported Dune tool. It uses the same API
endpoint and session configuration as this dbt project's profiles.yml file.

The example intentionally starts with the simplest safe scope: one exact table
per invocation, a dry-run preview by default, and an interactive Y/N confirmation
before execution. You can adapt it to be more flexible for your own environment,
but any broader cleanup workflow needs its own review and safety controls.

Usage:
    # Print the exact statement without executing it
    uv run python scripts/drop_tables.py --schema my_schema --table my_table

    # Print the same preview, then prompt before executing it
    uv run python scripts/drop_tables.py \
        --schema my_schema \
        --table my_table \
        --execute

Set DUNE_API_KEY in your environment before using --execute.
"""

import argparse
import os
import sys

import trino


TRINO_HOST = "trino.api.dune.com"
TRINO_PORT = 443
CATALOG = "dune"


def exact_identifier(value: str) -> str:
    """Validate an exact schema or table name."""
    if not value or value != value.strip():
        raise argparse.ArgumentTypeError(
            "must be a non-empty name without surrounding whitespace"
        )
    if any(character in value for character in ('"', "%", "*")):
        raise argparse.ArgumentTypeError(
            "must be an exact name without quotes or wildcard characters"
        )
    return value


def quote_identifier(identifier: str) -> str:
    """Quote a validated Trino identifier."""
    return f'"{identifier}"'


def build_drop_statement(schema: str, table: str) -> str:
    """Build one exact DROP TABLE statement."""
    qualified_table = ".".join(
        (
            quote_identifier(CATALOG),
            quote_identifier(schema),
            quote_identifier(table),
        )
    )
    return f"drop table {qualified_table}"


def confirm_drop() -> bool:
    """Require an explicit Y or N response before execution."""
    while True:
        try:
            response = input("Continue to drop the above? [Y/N]: ").strip()
        except (EOFError, KeyboardInterrupt):
            return False

        if response == "Y":
            return True
        if response == "N":
            return False
        print("Enter Y or N only.")


def execute_drop(statement: str, api_key: str) -> None:
    """Execute the confirmed DROP using the settings from profiles.yml."""
    connection = trino.dbapi.connect(
        host=TRINO_HOST,
        port=TRINO_PORT,
        user="dune",
        catalog=CATALOG,
        http_scheme="https",
        auth=trino.auth.BasicAuthentication("dune", api_key),
        session_properties={"transformations": "true"},
    )
    try:
        cursor = connection.cursor()
        try:
            cursor.execute(statement)
            cursor.fetchall()
        finally:
            cursor.close()
    finally:
        connection.close()


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Example script that previews and optionally drops one exact table "
            "through the Dune Trino API endpoint."
        )
    )
    parser.add_argument(
        "--schema",
        required=True,
        type=exact_identifier,
        help="Exact schema name. Required; wildcards are not supported.",
    )
    parser.add_argument(
        "--table",
        required=True,
        type=exact_identifier,
        help="Exact table name. Required; wildcards are not supported.",
    )
    parser.add_argument(
        "--execute",
        action="store_true",
        help="After the preview and confirmation, execute the DROP statement.",
    )
    args = parser.parse_args()

    statement = build_drop_statement(args.schema, args.table)
    print("DRY RUN PREVIEW")
    print(f"Endpoint: {TRINO_HOST}")
    print("The script would execute exactly one statement:")
    print(statement)

    if not args.execute:
        print("Nothing was dropped. Add --execute to continue after this preview.")
        return 0

    if not sys.stdin.isatty():
        print(
            "--execute requires an interactive terminal. Nothing was dropped.",
            file=sys.stderr,
        )
        return 1

    if not confirm_drop():
        print("Cancelled. Nothing was dropped.")
        return 0

    api_key = os.getenv("DUNE_API_KEY")
    if not api_key:
        print("DUNE_API_KEY is not set. Nothing was dropped.", file=sys.stderr)
        return 1

    try:
        execute_drop(statement, api_key)
    except Exception as exc:
        print(f"Drop failed: {exc}", file=sys.stderr)
        return 1

    print(f"Dropped {CATALOG}.{args.schema}.{args.table}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
