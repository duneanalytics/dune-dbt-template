#!/usr/bin/env python3
"""
Example script: drop a single table or view in a Dune schema via the Trino API.

This is an EXAMPLE, not a supported Dune tool. It is here to show one way to clean
up objects your dbt project created. You are free to delete it, or to replace it
with something that fits your own environment.

Managing storage is your responsibility. dbt projects accumulate tables in dev, CI
and production schemas, and those tables occupy storage until you remove them.
Dune's SQL interface supports DROP TABLE and DROP VIEW directly, so this script is
a convenience wrapper rather than the only route.

Scope, deliberately narrow:
    - Exactly one object per invocation. --target, --schema and --table are all
      required, so there is no bulk mode and no pattern matching.
    - No wildcards. Schema and table names are matched exactly.
    - Dry run unless --execute is passed.
    - --execute requires interactive confirmation and refuses to run without a TTY.

NOTE: Trino's DROP TABLE removes the metastore entry. It does not by itself
guarantee the underlying storage is reclaimed immediately.

Usage:
    # Show what would be dropped (no changes)
    python scripts/drop_tables.py --target dev --schema my_team__tmp_ --table my_model

    # Actually drop it, after confirming interactively
    python scripts/drop_tables.py --target dev --schema my_team__tmp_ --table my_model --execute

Set DUNE_API_KEY in your environment before running.
"""

import argparse
import logging
import os
import sys
from typing import Optional

import trino


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

TRINO_HOST = "trino.api.dune.com"
TRINO_PORT = 443
CATALOG = "dune"


def connect(api_key: str) -> trino.dbapi.Connection:
    """Open a connection to the Dune Trino endpoint."""
    logger.info(f"Connecting to {TRINO_HOST} (catalog={CATALOG})")
    return trino.dbapi.connect(
        host=TRINO_HOST,
        port=TRINO_PORT,
        user="dune",
        auth=trino.auth.BasicAuthentication("dune", api_key),
        catalog=CATALOG,
        http_scheme="https",
        session_properties={"transformations": "true"},
    )


def validate_name(kind: str, value: str) -> None:
    """
    Reject names this script will not accept.

    Wildcards are refused outright: this script matches exact names only, and
    accepting '%' would invite the assumption that patterns are supported.
    """
    if "%" in value:
        raise ValueError(
            f"{kind} '{value}' contains '%'. Wildcards are not supported: "
            f"this script drops one named object at a time."
        )
    if '"' in value:
        raise ValueError(f"{kind} '{value}' contains a double quote.")
    if value.strip() != value or not value:
        raise ValueError(f"{kind} must be a non-empty name without surrounding whitespace.")


def quote_identifier(identifier: str) -> str:
    """Double-quote an identifier for safe use in a DDL statement."""
    if '"' in identifier:
        raise ValueError(f"Invalid identifier: {identifier}")
    return f'"{identifier}"'


def find_object(
    connection: trino.dbapi.Connection,
    schema: str,
    table: str,
) -> Optional[str]:
    """
    Look up one object by exact schema and table name.

    Returns the object's table_type ('BASE TABLE' or 'VIEW'), or None if it does
    not exist. Looking it up first means a typo reports "not found" rather than
    silently succeeding against DROP ... IF EXISTS.
    """
    query = """
        select
            table_type
        from
            dune.information_schema.tables
        where
            table_catalog = ?
            and table_schema = ?
            and table_name = ?
    """
    cursor = connection.cursor()
    try:
        cursor.execute(query, (CATALOG, schema, table))
        rows = cursor.fetchall()
    finally:
        cursor.close()

    if not rows:
        return None
    return rows[0][0]


def build_drop_statement(schema: str, table: str, table_type: str) -> str:
    """Build the DROP statement for a single object."""
    target = ".".join(
        (quote_identifier(CATALOG), quote_identifier(schema), quote_identifier(table))
    )
    keyword = "view" if table_type == "VIEW" else "table"
    return f"drop {keyword} {target}"


def confirm(target: str, schema: str, table: str) -> bool:
    """
    Ask for interactive confirmation.

    On the prod target the full schema.table must be retyped, so that dropping a
    production object cannot be a reflexive 'yes'.
    """
    if not sys.stdin.isatty():
        logger.error(
            "--execute requires an interactive terminal. This is an ad-hoc tool and "
            "is not intended to run unattended."
        )
        return False

    qualified = f"{schema}.{table}"
    if target == "prod":
        prompt = f"Type '{qualified}' to confirm dropping this PROD object: "
        expected = qualified
    else:
        prompt = "Type 'yes' to confirm: "
        expected = "yes"

    try:
        response = input(prompt).strip()
    except (EOFError, KeyboardInterrupt):
        logger.warning("Cancelled.")
        return False

    if response != expected:
        logger.warning("Input did not match. Cancelled, nothing was dropped.")
        return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Drop a single table or view in a Dune schema. Example script, not a "
            "supported Dune tool."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
This script drops ONE named object per run. --target, --schema and --table are all
required. There is no bulk mode and no wildcard support.

--target records which environment you intend to act on and controls how the
confirmation prompt behaves. It is a declaration of intent, not a safety boundary:
the object dropped is always the one you name in --schema and --table.

Examples:
  # Show what would be dropped, change nothing
  python scripts/drop_tables.py --target dev --schema my_team__tmp_ --table my_model

  # Drop it (asks for confirmation first)
  python scripts/drop_tables.py --target dev --schema my_team__tmp_ --table my_model --execute

  # Production object (confirmation requires retyping schema.table)
  python scripts/drop_tables.py --target prod --schema my_team --table my_model --execute

Requires DUNE_API_KEY in the environment.
        """,
    )

    parser.add_argument(
        "--target",
        required=True,
        choices=["dev", "prod"],
        help="Environment you intend to act on. Required.",
    )
    parser.add_argument(
        "--schema",
        required=True,
        help="Exact schema name. Required. No wildcards.",
    )
    parser.add_argument(
        "--table",
        required=True,
        help="Exact table or view name. Required. No wildcards.",
    )
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Perform the drop. Without this flag the statement is only printed.",
    )

    args = parser.parse_args()

    api_key = os.getenv("DUNE_API_KEY")
    if not api_key:
        logger.error("DUNE_API_KEY is not set.")
        return 1

    try:
        validate_name("Schema", args.schema)
        validate_name("Table", args.table)
    except ValueError as exc:
        logger.error(str(exc))
        return 1

    dry_run = not args.execute
    if dry_run:
        logger.info("DRY RUN. Nothing will be dropped. Add --execute to apply.")

    logger.info(
        f"Target [{args.target.upper()}]: {CATALOG}.{args.schema}.{args.table}"
    )

    connection = connect(api_key)
    try:
        table_type = find_object(connection, args.schema, args.table)
        if table_type is None:
            logger.error(
                f"Not found: {CATALOG}.{args.schema}.{args.table}. "
                f"Nothing was dropped. Check the schema and table names."
            )
            return 1

        statement = build_drop_statement(args.schema, args.table, table_type)
        logger.info(f"Statement: {statement}")

        if dry_run:
            logger.info("DRY RUN complete. Re-run with --execute to apply.")
            return 0

        if not confirm(args.target, args.schema, args.table):
            return 1

        cursor = connection.cursor()
        try:
            cursor.execute(statement)
            cursor.fetchall()
        finally:
            cursor.close()

        logger.info(f"Dropped {CATALOG}.{args.schema}.{args.table}")
        return 0
    except Exception as exc:
        logger.error(f"Failed: {exc}")
        return 1
    finally:
        connection.close()
        logger.info("Connection closed")


if __name__ == "__main__":
    sys.exit(main())
