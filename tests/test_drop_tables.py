"""
Tests for scripts/drop_tables.py.

The Trino driver is stubbed, so these tests issue no queries and consume no credits.

Run with:
    python3 -m unittest discover tests --verbose
"""

import importlib.util
import io
import sys
import types
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest import mock


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "drop_tables.py"

TEAM = "my_team"
DEV_SCHEMA = f"{TEAM}__tmp_"
PROD_SCHEMA = TEAM


class FakeCursor:
    """Records every statement executed and answers the lookup query."""

    def __init__(self, recorder, object_type):
        self._recorder = recorder
        self._object_type = object_type
        self._rows = []

    def execute(self, statement, params=None):
        self._recorder.append((statement, params))
        if "information_schema" in statement:
            self._rows = [(self._object_type,)] if self._object_type else []
        else:
            self._rows = []

    def fetchall(self):
        return self._rows

    def close(self):
        pass


class FakeConnection:
    def __init__(self, recorder, object_type):
        self._recorder = recorder
        self._object_type = object_type

    def cursor(self):
        return FakeCursor(self._recorder, self._object_type)

    def close(self):
        pass


def load_script(recorder, object_type):
    """Import the script fresh with a stubbed trino module."""
    trino_stub = types.ModuleType("trino")
    dbapi = types.ModuleType("trino.dbapi")
    auth = types.ModuleType("trino.auth")

    dbapi.connect = lambda **kwargs: FakeConnection(recorder, object_type)
    dbapi.Connection = FakeConnection
    auth.BasicAuthentication = lambda user, password: ("basic", user, password)
    trino_stub.dbapi = dbapi
    trino_stub.auth = auth

    modules = {"trino": trino_stub, "trino.dbapi": dbapi, "trino.auth": auth}
    with mock.patch.dict(sys.modules, modules):
        spec = importlib.util.spec_from_file_location("drop_tables_under_test", SCRIPT_PATH)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    return module


class DropTablesTestCase(unittest.TestCase):
    """Runs the script's main() with a stubbed driver and a scripted stdin."""

    def run_script(
        self,
        argv,
        object_type="BASE TABLE",
        confirm_response="yes",
        api_key="fake-key",
        isatty=True,
    ):
        recorder = []
        module = load_script(recorder, object_type)

        env = {"DUNE_API_KEY": api_key} if api_key else {}
        prompted = {"called": False}

        def fake_input(_prompt=""):
            prompted["called"] = True
            if confirm_response is None:
                raise EOFError
            return confirm_response

        with mock.patch.dict("os.environ", env, clear=True), \
                mock.patch.object(module, "input", fake_input, create=True), \
                mock.patch.object(sys, "argv", ["drop_tables.py"] + argv), \
                mock.patch.object(sys.stdin, "isatty", lambda: isatty):
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                try:
                    exit_code = module.main()
                except SystemExit as exc:  # argparse rejects missing required flags
                    exit_code = exc.code

        drops = [stmt for stmt, _ in recorder if stmt.lower().startswith("drop ")]
        return exit_code, drops, prompted["called"]


class TestAllThreeFlagsAreRequired(DropTablesTestCase):
    """--target, --schema and --table are mandatory, so there is no bulk mode."""

    def test_no_arguments_is_rejected(self):
        exit_code, drops, _ = self.run_script([])
        self.assertNotEqual(exit_code, 0)
        self.assertEqual(drops, [])

    def test_missing_target_is_rejected(self):
        exit_code, drops, _ = self.run_script(
            ["--schema", DEV_SCHEMA, "--table", "my_model", "--execute"]
        )
        self.assertNotEqual(exit_code, 0)
        self.assertEqual(drops, [])

    def test_missing_table_is_rejected(self):
        """The bug this replaces: schema without table used to mean 'drop them all'."""
        exit_code, drops, _ = self.run_script(
            ["--target", "prod", "--schema", PROD_SCHEMA, "--execute"]
        )
        self.assertNotEqual(exit_code, 0)
        self.assertEqual(drops, [])

    def test_missing_schema_is_rejected(self):
        exit_code, drops, _ = self.run_script(
            ["--target", "dev", "--table", "my_model", "--execute"]
        )
        self.assertNotEqual(exit_code, 0)
        self.assertEqual(drops, [])


class TestReportedBypassIsGone(DropTablesTestCase):
    """
    The command originally reported against this script:

        drop_tables.py --schema <prod_schema> --execute

    It used to bulk-drop every object in that schema, because the prod guard and the
    confirmation prompt were both keyed to --target, which defaulted away from prod.
    There is no longer a code path that drops more than the one object named by
    --table, and --target and --table are now both required, so the command cannot
    even be parsed.
    """

    def test_schema_only_execute_is_rejected(self):
        exit_code, drops, prompted = self.run_script(["--schema", PROD_SCHEMA, "--execute"])
        self.assertNotEqual(exit_code, 0)
        self.assertEqual(drops, [])
        self.assertFalse(prompted)

    def test_wildcard_schema_only_execute_is_rejected(self):
        exit_code, drops, _ = self.run_script(["--schema", "%", "--execute"])
        self.assertNotEqual(exit_code, 0)
        self.assertEqual(drops, [])


class TestWildcardsAreRejected(DropTablesTestCase):
    def test_wildcard_schema_is_rejected(self):
        exit_code, drops, _ = self.run_script(
            ["--target", "prod", "--schema", "%", "--table", "my_model", "--execute"]
        )
        self.assertEqual(exit_code, 1)
        self.assertEqual(drops, [])

    def test_partial_wildcard_schema_is_rejected(self):
        exit_code, drops, _ = self.run_script(
            ["--target", "dev", "--schema", f"{TEAM}__tmp_%", "--table", "m", "--execute"]
        )
        self.assertEqual(exit_code, 1)
        self.assertEqual(drops, [])

    def test_wildcard_table_is_rejected(self):
        exit_code, drops, _ = self.run_script(
            ["--target", "dev", "--schema", DEV_SCHEMA, "--table", "%", "--execute"]
        )
        self.assertEqual(exit_code, 1)
        self.assertEqual(drops, [])


class TestDryRunIsTheDefault(DropTablesTestCase):
    def test_without_execute_nothing_is_dropped(self):
        exit_code, drops, prompted = self.run_script(
            ["--target", "prod", "--schema", PROD_SCHEMA, "--table", "my_model"]
        )
        self.assertEqual(exit_code, 0)
        self.assertEqual(drops, [])
        self.assertFalse(prompted, "dry run must not prompt")


class TestExecuteDropsExactlyOneObject(DropTablesTestCase):
    def test_dev_drop_with_confirmation(self):
        exit_code, drops, prompted = self.run_script(
            ["--target", "dev", "--schema", DEV_SCHEMA, "--table", "my_model", "--execute"]
        )
        self.assertEqual(exit_code, 0)
        self.assertTrue(prompted)
        self.assertEqual(len(drops), 1)
        self.assertIn(f'"{DEV_SCHEMA}"."my_model"', drops[0])

    def test_view_uses_drop_view(self):
        _, drops, _ = self.run_script(
            ["--target", "dev", "--schema", DEV_SCHEMA, "--table", "my_view", "--execute"],
            object_type="VIEW",
        )
        self.assertEqual(len(drops), 1)
        self.assertTrue(drops[0].startswith("drop view "))

    def test_table_uses_drop_table(self):
        _, drops, _ = self.run_script(
            ["--target", "dev", "--schema", DEV_SCHEMA, "--table", "my_model", "--execute"]
        )
        self.assertTrue(drops[0].startswith("drop table "))

    def test_missing_object_drops_nothing(self):
        exit_code, drops, prompted = self.run_script(
            ["--target", "dev", "--schema", DEV_SCHEMA, "--table", "nope", "--execute"],
            object_type=None,
        )
        self.assertEqual(exit_code, 1)
        self.assertEqual(drops, [])
        self.assertFalse(prompted)


class TestConfirmation(DropTablesTestCase):
    def test_declining_drops_nothing(self):
        exit_code, drops, prompted = self.run_script(
            ["--target", "dev", "--schema", DEV_SCHEMA, "--table", "my_model", "--execute"],
            confirm_response="no",
        )
        self.assertEqual(exit_code, 1)
        self.assertEqual(drops, [])
        self.assertTrue(prompted)

    def test_prod_requires_qualified_name_not_yes(self):
        exit_code, drops, _ = self.run_script(
            ["--target", "prod", "--schema", PROD_SCHEMA, "--table", "my_model", "--execute"],
            confirm_response="yes",
        )
        self.assertEqual(exit_code, 1, "'yes' must not be enough on prod")
        self.assertEqual(drops, [])

    def test_prod_accepts_qualified_name(self):
        exit_code, drops, _ = self.run_script(
            ["--target", "prod", "--schema", PROD_SCHEMA, "--table", "my_model", "--execute"],
            confirm_response=f"{PROD_SCHEMA}.my_model",
        )
        self.assertEqual(exit_code, 0)
        self.assertEqual(len(drops), 1)

    def test_interrupt_drops_nothing(self):
        exit_code, drops, _ = self.run_script(
            ["--target", "dev", "--schema", DEV_SCHEMA, "--table", "my_model", "--execute"],
            confirm_response=None,
        )
        self.assertEqual(exit_code, 1)
        self.assertEqual(drops, [])

    def test_non_interactive_execute_is_refused(self):
        """Prevents the script being wired into automation as-is."""
        exit_code, drops, _ = self.run_script(
            ["--target", "dev", "--schema", DEV_SCHEMA, "--table", "my_model", "--execute"],
            isatty=False,
        )
        self.assertEqual(exit_code, 1)
        self.assertEqual(drops, [])


class TestEnvironment(DropTablesTestCase):
    def test_missing_api_key_fails_before_connecting(self):
        exit_code, drops, _ = self.run_script(
            ["--target", "dev", "--schema", DEV_SCHEMA, "--table", "my_model", "--execute"],
            api_key=None,
        )
        self.assertEqual(exit_code, 1)
        self.assertEqual(drops, [])


if __name__ == "__main__":
    unittest.main()
