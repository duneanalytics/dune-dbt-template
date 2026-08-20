"""Unit tests for the single-table drop example."""

import importlib.util
import io
import os
import sys
import types
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "drop_tables.py"
SCHEMA = "my_team__tmp_"
TABLE = "my_model"


class FakeCursor:
    def __init__(self, statements):
        self.statements = statements

    def execute(self, statement):
        self.statements.append(statement)

    def fetchall(self):
        return []

    def close(self):
        pass


class FakeConnection:
    def __init__(self, statements):
        self.statements = statements

    def cursor(self):
        return FakeCursor(self.statements)

    def close(self):
        pass


def load_script(statements, connections):
    """Load the script with a stubbed Trino module."""
    trino_stub = types.ModuleType("trino")
    dbapi = types.ModuleType("trino.dbapi")
    auth = types.ModuleType("trino.auth")

    def fake_connect(**kwargs):
        connections.append(kwargs)
        return FakeConnection(statements)

    dbapi.connect = fake_connect
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
    def run_script(
        self,
        arguments,
        responses=None,
        api_key="fake-key",
        isatty=True,
    ):
        statements = []
        connections = []
        prompts = []
        output_before_prompts = []
        module = load_script(statements, connections)
        remaining_responses = list(responses or [])
        stdout = io.StringIO()
        stderr = io.StringIO()

        def fake_input(prompt):
            prompts.append(prompt)
            output_before_prompts.append(stdout.getvalue())
            if not remaining_responses:
                raise EOFError
            return remaining_responses.pop(0)

        environment = {"DUNE_API_KEY": api_key} if api_key else {}
        with (
            mock.patch.dict(os.environ, environment, clear=True),
            mock.patch.object(module, "input", fake_input, create=True),
            mock.patch.object(sys, "argv", ["drop_tables.py", *arguments]),
            mock.patch.object(sys.stdin, "isatty", return_value=isatty),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            try:
                exit_code = module.main()
            except SystemExit as exc:
                exit_code = exc.code

        return {
            "exit_code": exit_code,
            "statements": statements,
            "connections": connections,
            "prompts": prompts,
            "output_before_prompts": output_before_prompts,
            "stdout": stdout.getvalue(),
            "stderr": stderr.getvalue(),
        }


class TestSingleTableScope(DropTablesTestCase):
    def test_schema_and_table_are_required(self):
        for arguments in ([], ["--schema", SCHEMA], ["--table", TABLE]):
            with self.subTest(arguments=arguments):
                result = self.run_script(arguments)
                self.assertNotEqual(result["exit_code"], 0)
                self.assertEqual(result["statements"], [])
                self.assertEqual(result["connections"], [])

    def test_wildcards_are_rejected(self):
        for option, value in (("--schema", "%"), ("--schema", "team*"), ("--table", "model%")):
            with self.subTest(option=option, value=value):
                arguments = ["--schema", SCHEMA, "--table", TABLE]
                arguments[arguments.index(option) + 1] = value
                result = self.run_script(arguments)
                self.assertNotEqual(result["exit_code"], 0)
                self.assertEqual(result["statements"], [])
                self.assertEqual(result["connections"], [])


class TestDryRun(DropTablesTestCase):
    def test_default_prints_preview_without_connecting(self):
        result = self.run_script(
            ["--schema", SCHEMA, "--table", TABLE],
            api_key=None,
        )

        self.assertEqual(result["exit_code"], 0)
        self.assertEqual(result["statements"], [])
        self.assertEqual(result["connections"], [])
        self.assertEqual(result["prompts"], [])
        self.assertIn("DRY RUN PREVIEW", result["stdout"])
        self.assertIn(
            'drop table "dune"."my_team__tmp_"."my_model"',
            result["stdout"],
        )


class TestExecuteConfirmation(DropTablesTestCase):
    def test_execute_reprints_preview_before_prompt_and_drops_after_y(self):
        result = self.run_script(
            ["--schema", SCHEMA, "--table", TABLE, "--execute"],
            responses=["Y"],
        )

        self.assertEqual(result["exit_code"], 0)
        self.assertEqual(len(result["prompts"]), 1)
        self.assertIn("Continue to drop the above? [Y/N]", result["prompts"][0])
        self.assertIn("DRY RUN PREVIEW", result["output_before_prompts"][0])
        self.assertIn(
            'drop table "dune"."my_team__tmp_"."my_model"',
            result["output_before_prompts"][0],
        )
        self.assertEqual(
            result["statements"],
            ['drop table "dune"."my_team__tmp_"."my_model"'],
        )
        self.assertEqual(len(result["connections"]), 1)

    def test_n_cancels_without_connecting(self):
        result = self.run_script(
            ["--schema", SCHEMA, "--table", TABLE, "--execute"],
            responses=["N"],
        )

        self.assertEqual(result["exit_code"], 0)
        self.assertEqual(result["statements"], [])
        self.assertEqual(result["connections"], [])
        self.assertIn("Cancelled. Nothing was dropped.", result["stdout"])

    def test_end_of_input_cancels_without_connecting(self):
        result = self.run_script(
            ["--schema", SCHEMA, "--table", TABLE, "--execute"],
        )

        self.assertEqual(result["exit_code"], 0)
        self.assertEqual(result["statements"], [])
        self.assertEqual(result["connections"], [])
        self.assertIn("Cancelled. Nothing was dropped.", result["stdout"])

    def test_only_exact_y_or_n_is_accepted(self):
        result = self.run_script(
            ["--schema", SCHEMA, "--table", TABLE, "--execute"],
            responses=["yes", "y", "Y"],
        )

        self.assertEqual(result["exit_code"], 0)
        self.assertEqual(len(result["prompts"]), 3)
        self.assertEqual(result["stdout"].count("Enter Y or N only."), 2)
        self.assertEqual(len(result["statements"]), 1)

    def test_non_interactive_execute_is_refused_after_preview(self):
        result = self.run_script(
            ["--schema", SCHEMA, "--table", TABLE, "--execute"],
            isatty=False,
        )

        self.assertEqual(result["exit_code"], 1)
        self.assertIn("DRY RUN PREVIEW", result["stdout"])
        self.assertEqual(result["prompts"], [])
        self.assertEqual(result["statements"], [])
        self.assertEqual(result["connections"], [])

    def test_missing_api_key_stops_after_confirmation(self):
        result = self.run_script(
            ["--schema", SCHEMA, "--table", TABLE, "--execute"],
            responses=["Y"],
            api_key=None,
        )

        self.assertEqual(result["exit_code"], 1)
        self.assertIn("DRY RUN PREVIEW", result["stdout"])
        self.assertEqual(len(result["prompts"]), 1)
        self.assertEqual(result["statements"], [])
        self.assertEqual(result["connections"], [])

    def test_connection_matches_dbt_profile(self):
        result = self.run_script(
            ["--schema", SCHEMA, "--table", TABLE, "--execute"],
            responses=["Y"],
        )

        connection = result["connections"][0]
        self.assertEqual(connection["host"], "trino.api.dune.com")
        self.assertEqual(connection["catalog"], "dune")
        self.assertEqual(connection["session_properties"], {"transformations": "true"})


if __name__ == "__main__":
    unittest.main()
