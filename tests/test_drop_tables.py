"""
Regression tests for the safety guards in scripts/drop_tables.py.

Uses only the standard library, so it needs no additional dependencies and no
change to uv.lock. Run with:

    uv run python -m unittest discover tests
    # or
    python3 -m unittest discover tests

The Trino driver is stubbed, so these tests never open a connection or touch
real data. Every DROP statement the script would issue is captured instead.

Covers the bypass reported against the original guards, where both the prod
check and the confirmation prompt keyed off the --target flag rather than the
schema actually being targeted, so supplying --schema skipped both.
"""

import importlib.util
import logging
import os
import re
import sys
import types
import unittest
from pathlib import Path
from unittest import mock


TEAM_NAME = "my_team"

# Simulated contents of dune.information_schema.tables.
CATALOG_FIXTURE = [
    ("my_team", "positions_daily", "BASE TABLE"),
    ("my_team", "trades_enriched", "BASE TABLE"),
    ("my_team", "reporting_view", "VIEW"),
    ("my_team__tmp_", "scratch_model", "BASE TABLE"),
    ("my_team__tmp_pr42", "scratch_model", "BASE TABLE"),
    ("scratch_area", "junk", "BASE TABLE"),
    ("other_team", "their_table", "BASE TABLE"),
]

SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "drop_tables.py"


def setUpModule():
    """Silence the script's own logging so test output stays readable."""
    logging.disable(logging.CRITICAL)


def tearDownModule():
    logging.disable(logging.NOTSET)


def like_to_regex(pattern):
    """Mirror SQL LIKE semantics: % matches any run, _ matches one character."""
    out = ""
    for char in pattern:
        if char == "%":
            out += ".*"
        elif char == "_":
            out += "."
        else:
            out += re.escape(char)
    return re.compile("^" + out + "$")


class FakeCursor:
    def __init__(self, recorder):
        self._recorder = recorder
        self._rows = []

    def execute(self, query, params=None):
        normalized = " ".join(query.lower().split())
        if "information_schema.tables" in normalized:
            if "table_schema like" in normalized:
                matcher = like_to_regex(params[1])
                self._rows = [r for r in CATALOG_FIXTURE if matcher.match(r[0])]
            elif "table_name = ?" in normalized:
                self._rows = [
                    r for r in CATALOG_FIXTURE if r[0] == params[1] and r[1] == params[2]
                ]
            else:
                self._rows = [r for r in CATALOG_FIXTURE if r[0] == params[1]]
        elif normalized.startswith("drop "):
            self._recorder.append(query)
            self._rows = []

    def fetchall(self):
        return self._rows

    def close(self):
        pass


class FakeConnection:
    def __init__(self, recorder):
        self._recorder = recorder

    def cursor(self):
        return FakeCursor(self._recorder)

    def close(self):
        pass


class DropTablesTestCase(unittest.TestCase):
    """Base class providing an isolated, offline invocation of the script."""

    def run_script(self, argv, confirm_response="yes"):
        """
        Run drop_tables.main() with the given argv.

        Returns:
            tuple: (exit_code, dropped_statements, was_prompted)
        """
        recorded_drops = []
        prompted = {"value": False}

        trino_stub = types.ModuleType("trino")
        dbapi = types.ModuleType("trino.dbapi")
        auth = types.ModuleType("trino.auth")
        dbapi.connect = lambda **kwargs: FakeConnection(recorded_drops)
        dbapi.Connection = FakeConnection
        auth.BasicAuthentication = lambda *args, **kwargs: None
        trino_stub.dbapi = dbapi
        trino_stub.auth = auth

        stub_modules = {
            "trino": trino_stub,
            "trino.dbapi": dbapi,
            "trino.auth": auth,
        }
        env = {
            "DUNE_API_KEY": "fake-key-not-real",
            "DUNE_TEAM_NAME": TEAM_NAME,
        }

        def fake_input(prompt=""):
            prompted["value"] = True
            return confirm_response

        with mock.patch.dict(sys.modules, stub_modules), mock.patch.dict(
            os.environ, env
        ), mock.patch("builtins.input", fake_input), mock.patch.object(
            sys, "argv", ["drop_tables.py"] + argv
        ):
            spec = importlib.util.spec_from_file_location(
                "drop_tables_under_test", SCRIPT_PATH
            )
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            exit_code = module.main()

        return exit_code, recorded_drops, prompted["value"]

    @staticmethod
    def schemas_touched(drops):
        """Extract the schema from each captured DROP statement."""
        return sorted({stmt.split(".")[1].strip('"') for stmt in drops})


class TestBulkDropIsScopedToDevSchemas(DropTablesTestCase):
    def test_prod_schema_bulk_drop_is_refused_without_target_flag(self):
        """The reported bypass: --schema <prod> --execute must not drop anything."""
        exit_code, drops, prompted = self.run_script(["--schema", TEAM_NAME, "--execute"])

        self.assertEqual(exit_code, 1)
        self.assertEqual(drops, [])
        self.assertFalse(prompted)

    def test_bare_wildcard_is_refused(self):
        """--schema % must never fan out across every schema in the catalog."""
        exit_code, drops, _ = self.run_script(["--schema", "%", "--execute"])

        self.assertEqual(exit_code, 1)
        self.assertEqual(drops, [])

    def test_prefix_wildcard_spanning_prod_is_refused(self):
        """A pattern reaching both prod and dev schemas must be refused."""
        exit_code, drops, _ = self.run_script(["--schema", f"{TEAM_NAME}%", "--execute"])

        self.assertEqual(exit_code, 1)
        self.assertEqual(drops, [])

    def test_unrelated_schema_bulk_drop_is_refused(self):
        exit_code, drops, _ = self.run_script(["--schema", "other_team", "--execute"])

        self.assertEqual(exit_code, 1)
        self.assertEqual(drops, [])


class TestIntendedWorkflowsStillFunction(DropTablesTestCase):
    def test_default_dev_bulk_drop_targets_only_tmp_schemas(self):
        exit_code, drops, prompted = self.run_script(["--execute"])

        self.assertEqual(exit_code, 0)
        self.assertEqual(self.schemas_touched(drops), ["my_team__tmp_", "my_team__tmp_pr42"])
        self.assertFalse(prompted, "dev schemas are disposable and should not prompt")

    def test_single_dev_schema_bulk_drop_is_allowed(self):
        exit_code, drops, _ = self.run_script(["--schema", "my_team__tmp_pr42", "--execute"])

        self.assertEqual(exit_code, 0)
        self.assertEqual(self.schemas_touched(drops), ["my_team__tmp_pr42"])

    def test_dry_run_is_the_default(self):
        exit_code, drops, _ = self.run_script([])

        self.assertEqual(exit_code, 0)
        self.assertEqual(drops, [], "no DDL should execute without --execute")

    def test_single_prod_table_drop_is_allowed_with_confirmation(self):
        exit_code, drops, prompted = self.run_script(
            [
                "--target",
                "prod",
                "--schema",
                TEAM_NAME,
                "--table",
                "positions_daily",
                "--execute",
            ]
        )

        self.assertEqual(exit_code, 0)
        self.assertTrue(prompted, "dropping a prod object must be confirmed")
        self.assertEqual(len(drops), 1)
        self.assertIn("positions_daily", drops[0])

    def test_prod_bulk_drop_via_target_flag_still_refused(self):
        exit_code, drops, _ = self.run_script(["--target", "prod", "--execute"])

        self.assertEqual(exit_code, 1)
        self.assertEqual(drops, [])


class TestConfirmationBehaviour(DropTablesTestCase):
    def test_single_non_dev_drop_prompts_even_without_target_prod(self):
        """Previously this path skipped the prompt entirely."""
        exit_code, drops, prompted = self.run_script(
            ["--schema", TEAM_NAME, "--table", "positions_daily", "--execute"]
        )

        self.assertEqual(exit_code, 0)
        self.assertTrue(prompted)
        self.assertEqual(len(drops), 1)

    def test_declining_confirmation_drops_nothing(self):
        exit_code, drops, prompted = self.run_script(
            ["--schema", TEAM_NAME, "--table", "positions_daily", "--execute"],
            confirm_response="no",
        )

        self.assertEqual(exit_code, 0)
        self.assertTrue(prompted)
        self.assertEqual(drops, [])

    def test_view_uses_drop_view(self):
        exit_code, drops, _ = self.run_script(
            ["--schema", TEAM_NAME, "--table", "reporting_view", "--execute"]
        )

        self.assertEqual(exit_code, 0)
        self.assertTrue(drops[0].lower().startswith("drop view"))


class TestExplicitOptIn(DropTablesTestCase):
    def test_opt_in_allows_bulk_drop_of_non_dev_schema(self):
        exit_code, drops, prompted = self.run_script(
            ["--schema", "scratch_area", "--allow-bulk-outside-dev", "--execute"]
        )

        self.assertEqual(exit_code, 0)
        self.assertTrue(prompted, "opting in still requires confirmation")
        self.assertEqual(self.schemas_touched(drops), ["scratch_area"])

    def test_opt_in_cannot_bulk_drop_the_production_schema(self):
        exit_code, drops, _ = self.run_script(
            ["--schema", TEAM_NAME, "--allow-bulk-outside-dev", "--execute"]
        )

        self.assertEqual(exit_code, 1)
        self.assertEqual(drops, [])

    def test_opt_in_cannot_bulk_drop_prod_via_wildcard(self):
        exit_code, drops, _ = self.run_script(
            ["--schema", "%", "--allow-bulk-outside-dev", "--execute"]
        )

        self.assertEqual(exit_code, 1)
        self.assertEqual(drops, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
