#!/usr/bin/env python3
"""
Script to drop tables and views in a Dune schema via Trino API.

This script connects to the Dune Trino API endpoint using the same configuration
as dbt and drops tables and views based on schema pattern or specific table name.

NOTE: Trino's DROP TABLE command only removes the metastore entry, leaving orphaned
data in S3. S3 cleanup should be handled separately via scheduled cleanup jobs.

Usage:
    # Dry run - drop all tables matching DUNE_TEAM_NAME__tmp_* pattern
    python scripts/drop_tables.py

    # Dry run - drop all tables in specific schema
    python scripts/drop_tables.py --schema my_custom_schema

    # Dry run - drop specific table
    python scripts/drop_tables.py --table my_table_name --schema my_schema

    # Actually execute drops
    python scripts/drop_tables.py --execute

    # Execute drop for specific schema
    python scripts/drop_tables.py --schema my_schema --execute
"""

import argparse
import logging
import os
import sys
from typing import Optional

import trino


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)


class DuneTrinoConnection:
    """Manages connection to Dune Trino API endpoint."""

    def __init__(
        self,
        api_key: Optional[str] = None,
        host: str = "trino.api.dune.com",
        port: int = 443,
        catalog: str = "dune",
    ):
        """
        Initialize Dune Trino connection.

        Args:
            api_key: Dune API key (defaults to DUNE_API_KEY env var)
            host: Trino host endpoint
            port: Trino port
            catalog: Trino catalog
        """
        self.api_key = api_key or os.getenv("DUNE_API_KEY")
        if not self.api_key:
            raise ValueError(
                "DUNE_API_KEY environment variable is required or pass api_key parameter"
            )

        self.host = host
        self.port = port
        self.catalog = catalog
        self.connection = None

        logger.info(f"Initialized Dune Trino connection config (host={host}, catalog={catalog})")

    def connect(self) -> trino.dbapi.Connection:
        """
        Establish connection to Dune Trino API.

        Returns:
            trino.dbapi.Connection: Active Trino connection
        """
        logger.info("Connecting to Dune Trino API...")

        self.connection = trino.dbapi.connect(
            host=self.host,
            port=self.port,
            user="dune",  # Always 'dune' for Dune API
            catalog=self.catalog,
            http_scheme="https",
            auth=trino.auth.BasicAuthentication("dune", self.api_key),
            session_properties={"transformations": "true"},
        )

        logger.info("Successfully connected to Dune Trino API")
        return self.connection

    def close(self):
        """Close the Trino connection."""
        if self.connection:
            self.connection.close()
            logger.info("Connection closed")


def list_tables_by_pattern(
    connection: trino.dbapi.Connection,
    schema_pattern: str,
    catalog: str = "dune",
) -> list:
    """
    List all tables matching a schema pattern.

    Args:
        connection: Active Trino connection
        schema_pattern: Schema pattern to match (e.g., 'my_team__tmp_%' for LIKE matching)
        catalog: Catalog name (default: 'dune')

    Returns:
        list: List of dicts with schema, table name, and type
    """
    cursor = connection.cursor()

    # Use parameterized query to prevent SQL injection
    query = """
        select
            table_schema
            , table_name
            , table_type
        from
            dune.information_schema.tables
        where
            table_catalog = ?
            and table_schema like ?
        order by
            table_schema
            , table_name
    """

    logger.info(f"Querying tables matching schema pattern: {schema_pattern}")
    logger.debug(f"Query: {query}")
    logger.debug(f"Parameters: catalog={catalog}, schema_pattern={schema_pattern}")

    try:
        cursor.execute(query, (catalog, schema_pattern))
        results = cursor.fetchall()

        tables = []
        for row in results:
            schema_name, table_name, table_type = row
            tables.append({
                "schema": schema_name,
                "name": table_name,
                "type": table_type,
            })

        return tables
    except Exception as e:
        logger.error(f"Error querying tables: {e}")
        raise
    finally:
        cursor.close()


def list_tables_by_schema(
    connection: trino.dbapi.Connection,
    schema: str,
    catalog: str = "dune",
) -> list:
    """
    List all tables in a specific schema using exact equality match.

    Args:
        connection: Active Trino connection
        schema: Exact schema name (no pattern matching)
        catalog: Catalog name (default: 'dune')

    Returns:
        list: List of dicts with schema, table name, and type
    """
    cursor = connection.cursor()

    # Use parameterized query with exact equality (not LIKE)
    query = """
        select
            table_schema
            , table_name
            , table_type
        from
            dune.information_schema.tables
        where
            table_catalog = ?
            and table_schema = ?
        order by
            table_schema
            , table_name
    """

    logger.info(f"Querying tables in schema: {schema}")
    logger.debug(f"Query: {query}")
    logger.debug(f"Parameters: catalog={catalog}, schema={schema}")

    try:
        cursor.execute(query, (catalog, schema))
        results = cursor.fetchall()

        tables = []
        for row in results:
            schema_name, table_name, table_type = row
            tables.append({
                "schema": schema_name,
                "name": table_name,
                "type": table_type,
            })

        return tables
    except Exception as e:
        logger.error(f"Error querying tables: {e}")
        raise
    finally:
        cursor.close()


def list_specific_table(
    connection: trino.dbapi.Connection,
    schema: str,
    table_name: str,
    catalog: str = "dune",
) -> list:
    """
    List a specific table in a schema.

    Args:
        connection: Active Trino connection
        schema: Schema name
        table_name: Table name
        catalog: Catalog name (default: 'dune')

    Returns:
        list: List with single dict containing table info, or empty list if not found
    """
    cursor = connection.cursor()

    # Use parameterized query to prevent SQL injection
    query = """
        select
            table_schema
            , table_name
            , table_type
        from
            dune.information_schema.tables
        where
            table_catalog = ?
            and table_schema = ?
            and table_name = ?
    """

    logger.info(f"Querying table: {catalog}.{schema}.{table_name}")
    logger.debug(f"Query: {query}")
    logger.debug(f"Parameters: catalog={catalog}, schema={schema}, table_name={table_name}")

    try:
        cursor.execute(query, (catalog, schema, table_name))
        results = cursor.fetchall()

        tables = []
        for row in results:
            schema_name, table_name_result, table_type = row
            tables.append({
                "schema": schema_name,
                "name": table_name_result,
                "type": table_type,
            })

        return tables
    except Exception as e:
        logger.error(f"Error querying table: {e}")
        raise
    finally:
        cursor.close()


def quote_identifier(identifier: str) -> str:
    """
    Quote a SQL identifier to prevent SQL injection in DDL statements.
    
    In Trino, identifiers can be quoted with double quotes.
    This function validates and quotes identifiers safely.
    
    Args:
        identifier: SQL identifier to quote
        
    Returns:
        str: Quoted identifier
        
    Raises:
        ValueError: If identifier contains quotes or is invalid
    """
    # Validate: no double quotes allowed (would break quoting)
    if '"' in identifier:
        raise ValueError(f"Invalid identifier: contains double quotes: {identifier}")
    
    # Quote the identifier
    return f'"{identifier}"'


def drop_table_or_view(
    connection: trino.dbapi.Connection,
    schema: str,
    table_name: str,
    table_type: str,
    catalog: str = "dune",
    dry_run: bool = True,
) -> bool:
    """
    Drop a table or view from the specified schema.

    Args:
        connection: Active Trino connection
        schema: Schema name
        table_name: Name of the table/view to drop
        table_type: Type of object ('BASE TABLE' or 'VIEW')
        catalog: Catalog name (default: 'dune')
        dry_run: If True, only log the command without executing

    Returns:
        bool: True if successful (or dry run), False otherwise
    """
    try:
        # Quote identifiers to prevent SQL injection in DDL statements
        quoted_catalog = quote_identifier(catalog)
        quoted_schema = quote_identifier(schema)
        quoted_table = quote_identifier(table_name)
        
        # Determine if this is a table or view
        if table_type == "VIEW":
            drop_statement = f"drop view if exists {quoted_catalog}.{quoted_schema}.{quoted_table}"
        else:  # BASE TABLE or other types
            drop_statement = f"drop table if exists {quoted_catalog}.{quoted_schema}.{quoted_table}"
    except ValueError as e:
        logger.error(f"✗ Invalid identifier for {schema}.{table_name}: {e}")
        return False

    # Always log the drop command
    logger.info(f"DROP: {drop_statement}")

    if dry_run:
        logger.debug("Dry run mode - command not executed")
        return True

    # Execute the drop command
    cursor = connection.cursor()
    try:
        cursor.execute(drop_statement)
        logger.info(f"✓ Successfully dropped: {schema}.{table_name}")
        return True
    except Exception as e:
        logger.error(f"✗ Error dropping {schema}.{table_name}: {e}")
        return False
    finally:
        cursor.close()


def drop_tables(
    connection: trino.dbapi.Connection,
    tables: list,
    catalog: str = "dune",
    dry_run: bool = True,
) -> dict:
    """
    Drop tables and views from the list.

    Args:
        connection: Active Trino connection
        tables: List of table dicts with 'schema', 'name', and 'type'
        catalog: Catalog name (default: 'dune')
        dry_run: If True, only log the commands without executing

    Returns:
        dict: Summary with counts of successful and failed drops
    """
    if not tables:
        logger.info("No tables found to drop.")
        return {"total": 0, "success": 0, "failed": 0}

    logger.info("=" * 80)
    logger.info(f"Preparing to drop {len(tables)} table(s)/view(s)")
    logger.info("=" * 80)

    success_count = 0
    failed_count = 0

    for table in tables:
        success = drop_table_or_view(
            connection,
            table["schema"],
            table["name"],
            table["type"],
            catalog,
            dry_run,
        )
        if success:
            success_count += 1
        else:
            failed_count += 1

    logger.info("=" * 80)
    logger.info(f"Drop summary: {success_count} successful, {failed_count} failed")
    logger.info("=" * 80)

    return {
        "total": len(tables),
        "success": success_count,
        "failed": failed_count,
    }


def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(
        description="Drop tables and views in a Dune schema via Trino API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Dry run - drop all dev tables (DUNE_TEAM_NAME__tmp_* pattern)
  python scripts/drop_tables.py

  # Execute drop for dev tables
  python scripts/drop_tables.py --execute

  # Drop specific dev table (dry run)
  python scripts/drop_tables.py --table my_table --schema dune__tmp_jeff

  # Drop specific dev table (execute)
  python scripts/drop_tables.py --table my_table --schema dune__tmp_jeff --execute

  # Drop specific prod table (dry run - REQUIRES --schema AND --table)
  python scripts/drop_tables.py --target prod --schema dune --table my_table

  # Drop specific prod table (execute - REQUIRES CONFIRMATION)
  python scripts/drop_tables.py --target prod --schema dune --table my_table --execute
        """,
    )

    # Get default schema pattern from environment
    dune_team_name = os.getenv("DUNE_TEAM_NAME", "dune")
    default_dev_pattern = f"{dune_team_name}__tmp_%"
    default_prod_schema = dune_team_name

    parser.add_argument(
        "--target",
        type=str,
        choices=["dev", "prod"],
        default="dev",
        help="Target environment: 'dev' (default, uses __tmp_ pattern) or 'prod' (production schema)",
    )

    parser.add_argument(
        "--schema",
        type=str,
        default=None,
        help="Schema name or pattern (overrides --target default)",
    )

    parser.add_argument(
        "--table",
        type=str,
        default=None,
        help="Specific table or view name to drop (requires --schema to be exact schema name)",
    )

    parser.add_argument(
        "--execute",
        action="store_true",
        help="Execute the drop operations (default is dry-run mode)",
    )

    parser.add_argument(
        "--api-key",
        type=str,
        default=None,
        help="Dune API key (defaults to DUNE_API_KEY env var)",
    )

    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Enable verbose (debug) logging",
    )

    args = parser.parse_args()

    # Set logging level based on verbose flag
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
        logger.setLevel(logging.DEBUG)

    # Determine dry run mode
    dry_run = not args.execute

    # Determine schema/pattern to use and prod status
    is_prod = args.target == "prod"
    
    if args.schema:
        schema_or_pattern = args.schema
        use_pattern = not args.table  # If specific table, don't use pattern matching
    else:
        # Use target to determine schema
        if args.target == "prod":
            schema_or_pattern = default_prod_schema
            use_pattern = False  # Prod is exact schema, not a pattern
        else:  # dev
            schema_or_pattern = default_dev_pattern
            use_pattern = True

    # Validation
    if args.table and not args.schema:
        logger.error("Error: --table requires --schema to be specified")
        return 1
    
    # Production safety: require specific table/view
    if is_prod and (not args.schema or not args.table):
        logger.error("=" * 80)
        logger.error("Error: Production drops require BOTH --schema AND --table")
        logger.error("=" * 80)
        logger.error("For safety, you can only drop one specific table/view at a time in prod.")
        logger.error("You must specify:")
        logger.error("  --schema SCHEMA_NAME")
        logger.error("  --table TABLE_NAME")
        logger.error("")
        logger.error("Example:")
        logger.error(f"  python scripts/drop_tables.py --target prod --schema {default_prod_schema} --table my_table --execute")
        logger.error("=" * 80)
        return 1

    # Display mode
    if dry_run:
        logger.warning("=" * 80)
        logger.warning("DRY RUN MODE - No operations will be executed")
        logger.warning("To execute operations, add the --execute flag")
        logger.warning("=" * 80)

    # Display target info
    target_label = f"{'PROD' if is_prod else 'DEV'}"
    if args.table:
        logger.info(f"Target [{target_label}]: Specific table '{args.table}' in schema '{args.schema}'")
    elif use_pattern:
        logger.info(f"Target [{target_label}]: All tables matching schema pattern '{schema_or_pattern}'")
    else:
        logger.info(f"Target [{target_label}]: All tables in schema '{schema_or_pattern}'")

    # Execute
    dune_conn = None
    try:
        # Create connection
        dune_conn = DuneTrinoConnection(api_key=args.api_key)
        connection = dune_conn.connect()

        # Get tables to drop
        if args.table:
            # Drop specific table
            tables = list_specific_table(
                connection,
                args.schema,
                args.table,
                catalog="dune",
            )
            if not tables:
                logger.warning(f"Table '{args.table}' not found in schema '{args.schema}'")
                return 0
        elif use_pattern:
            # Drop by pattern (uses SQL LIKE with wildcards)
            tables = list_tables_by_pattern(
                connection,
                schema_or_pattern,
                catalog="dune",
            )
        else:
            # Drop all in specific schema (uses exact equality match)
            tables = list_tables_by_schema(
                connection,
                schema_or_pattern,
                catalog="dune",
            )

        # Production safety check: require confirmation before dropping
        if is_prod and not dry_run and tables:
            logger.warning("")
            logger.warning("=" * 80)
            logger.warning("⚠️  PRODUCTION DROP WARNING ⚠️")
            logger.warning("=" * 80)
            logger.warning(f"You are about to DROP {len(tables)} table(s)/view(s) from PRODUCTION schema(s)!")
            logger.warning(f"Schema: {schema_or_pattern}")
            logger.warning("=" * 80)
            logger.warning("")
            
            # Show first 10 tables as preview
            preview_count = min(10, len(tables))
            logger.warning(f"Preview of tables to be dropped (showing {preview_count} of {len(tables)}):")
            for i, table in enumerate(tables[:preview_count]):
                logger.warning(f"  {i+1}. {table['schema']}.{table['name']} ({table['type']})")
            if len(tables) > preview_count:
                logger.warning(f"  ... and {len(tables) - preview_count} more table(s)")
            logger.warning("")
            
            # Get user confirmation
            try:
                response = input("Are you sure you want to proceed? Type 'yes' to confirm: ").strip().lower()
                if response != "yes":
                    logger.info("Operation cancelled by user.")
                    return 0
                logger.info("Confirmed. Proceeding with drop operations...")
            except (KeyboardInterrupt, EOFError):
                logger.info("\nOperation cancelled by user.")
                return 0

        # Drop the tables
        summary = drop_tables(
            connection,
            tables,
            catalog="dune",
            dry_run=dry_run,
        )

        if dry_run:
            logger.info("")
            logger.info("=" * 80)
            logger.info("DRY RUN COMPLETE")
            logger.info("Above are the DROP commands that would be executed.")
            logger.info("Use --execute flag to actually drop the tables/views.")
            logger.info("=" * 80)

        return 0

    except Exception as e:
        logger.error(f"Failed to complete operation: {e}")
        return 1
    finally:
        # Ensure connection is always closed, even if an exception occurs
        if dune_conn is not None:
            dune_conn.close()


if __name__ == "__main__":
    sys.exit(main())

