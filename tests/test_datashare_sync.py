"""Offline tests using dbt's macro runtime; no Trino connection is made."""

import re
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

from dbt.clients.jinja import MacroGenerator
from dbt.context.exceptions_jinja import raise_compiler_error
from dbt.contracts.graph.nodes import Macro
from dbt.include.global_project import PACKAGE_PATH as DBT_GLOBAL_PROJECT_PATH
from dbt_common.exceptions import CompilationError
from dbt_common.exceptions.macros import MacroReturn

MACRO_PATH = Path("macros/dune_dbt_overrides/datashare_sync_post_hook.sql")
ROOT = Path(__file__).resolve().parents[1]


def macro_return(value):
    raise MacroReturn(value)


class TestDatashareSync(unittest.TestCase):
    def setUp(self):
        self.config = {
            "materialized": "incremental",
            "unique_key": ["id", "block_date"],
            "meta": {"datashare_sync": {"enabled": True}},
            "properties": {"change_data_feed_enabled": "true"},
        }
        self.node = SimpleNamespace(
            resource_type="model",
            name="example",
            alias="delivered",
            unique_id="model.dbt_template.example",
            fqn=["dbt_template", "example"],
            schema="my_team",
            database="dune",
            config=self.config,
        )
        self.context = {
            "return": macro_return,
            "exceptions": SimpleNamespace(raise_compiler_error=raise_compiler_error),
            "log": Mock(spec=[], return_value=""),
            "run_query": Mock(spec=[]),
            "target": SimpleNamespace(name="prod", database="dune"),
            "this": SimpleNamespace(schema="my_team", identifier="delivered"),
            "model": SimpleNamespace(
                config=SimpleNamespace(
                    materialized="incremental",
                    get=self.config.get,
                )
            ),
            "is_incremental": Mock(spec=[], return_value=True),
            "config": SimpleNamespace(get=self.config.get),
            "flags": SimpleNamespace(FULL_REFRESH=False),
            "graph": SimpleNamespace(nodes={self.node.unique_id: self.node}),
        }
        for path in (
            ROOT / MACRO_PATH,
            Path(DBT_GLOBAL_PROJECT_PATH) / "macros/materializations/configs.sql",
        ):
            source = path.read_text()
            for name in re.findall(r"{%\s*macro\s+(\w+)\(", source):
                macro = Macro(
                    name=name,
                    resource_type="macro",
                    package_name="dbt_template",
                    path=str(path),
                    original_file_path=str(path),
                    unique_id=f"macro.dbt_template.{name}",
                    macro_sql=source,
                )
                self.context[name] = MacroGenerator(macro, self.context)

    def hook(self):
        return self.context["datashare_trigger_sync"]()

    def operation(self, selector="example", **kwargs):
        return self.context["datashare_trigger_sync_operation"](selector, **kwargs)

    def test_incremental_hook_generates_only_changefeed_sql_without_queries(self):
        self.assertEqual(
            " ".join(self.hook().split()),
            "ALTER TABLE dune.my_team.delivered EXECUTE sync_datashare( "
            "unique_key_columns => ARRAY['id', 'block_date'], full_refresh => false)",
        )
        self.context["run_query"].assert_not_called()

    def test_first_run_hook_does_not_force_full_refresh(self):
        self.context["is_incremental"].return_value = False
        self.assertIn("full_refresh => false", self.hook())
        self.context["is_incremental"].assert_not_called()

    def test_table_materialization_hook_does_not_force_full_refresh(self):
        self.context["model"].config.materialized = "table"
        self.context["is_incremental"].return_value = False
        self.assertIn("full_refresh => false", self.hook())
        self.context["is_incremental"].assert_not_called()

    def test_hook_propagates_dbt_full_refresh_for_both_materializations(self):
        self.context["flags"].FULL_REFRESH = True
        for materialized in ("incremental", "table"):
            with self.subTest(materialized=materialized):
                self.context["model"].config.materialized = materialized
                self.assertIn("full_refresh => true", self.hook())
        self.context["run_query"].assert_not_called()

    def test_hook_respects_model_full_refresh_config_over_cli_flag(self):
        for configured, requested in ((True, False), (False, True)):
            with self.subTest(configured=configured, requested=requested):
                self.config["full_refresh"] = configured
                self.context["flags"].FULL_REFRESH = requested
                expected = "true" if configured else "false"
                self.assertIn(f"full_refresh => {expected}", self.hook())
        self.context["run_query"].assert_not_called()

    def test_hook_skips_dev_views_and_disabled_or_absent_metadata(self):
        for field, value in (
            ("target", SimpleNamespace(name="dev")),
            (
                "model",
                SimpleNamespace(
                    config=SimpleNamespace(materialized="view", get=self.config.get)
                ),
            ),
        ):
            with self.subTest(field=field):
                previous = self.context[field]
                self.context[field] = value
                self.assertEqual(self.hook(), "")
                self.context[field] = previous
        for meta in (
            {},
            None,
            {"datashare_sync": {"enabled": False}},
            {"datashare_sync": {"enabled": "true"}},
        ):
            with self.subTest(meta=meta):
                self.config["meta"] = meta
                self.assertEqual(self.hook(), "")
        self.context["run_query"].assert_not_called()

    def test_cdf_is_required_through_both_entrypoints(self):
        for value in (None, False, "false", "", 1):
            with self.subTest(value=value):
                self.config["properties"] = {"change_data_feed_enabled": value}
                for call in (self.hook, self.operation):
                    with self.assertRaisesRegex(
                        CompilationError, "change_data_feed_enabled"
                    ):
                        call()
        self.context["run_query"].assert_not_called()

    def test_cdf_accepts_sql_literal_and_boolean(self):
        for value in ("true", " TRUE ", True):
            with self.subTest(value=value):
                self.config["properties"]["change_data_feed_enabled"] = value
                self.assertIn("EXECUTE sync_datashare", self.hook())

    def test_unique_key_is_required(self):
        for value in (None, [], {}, "", " ", [""], [1], 1):
            with self.subTest(value=value):
                self.config["unique_key"] = value
                with self.assertRaisesRegex(CompilationError, "unique_key"):
                    self.hook()
        self.context["run_query"].assert_not_called()

    def test_single_key_and_partitioning_escape_sql_strings(self):
        self.config["unique_key"] = "owner's_id"
        self.config["meta"]["datashare_sync"]["partitioning"] = "day's_date"
        sql = self.hook()
        self.assertIn("ARRAY['owner''s_id']", sql)
        self.assertIn("partitioning => 'day''s_date'", sql)

    def test_empty_partitioning_is_omitted(self):
        for value in (None, "", " "):
            with self.subTest(value=value):
                self.config["meta"]["datashare_sync"]["partitioning"] = value
                self.assertNotIn("partitioning =>", self.hook())

    def test_unknown_sync_keys_fail(self):
        self.config["meta"]["datashare_sync"]["unexpected"] = True
        with self.assertRaisesRegex(CompilationError, "unsupported.*unexpected"):
            self.operation()
        self.context["run_query"].assert_not_called()

    def test_manual_sync_does_not_force_full_refresh_for_both_materializations(self):
        for materialized in ("incremental", "table"):
            with self.subTest(materialized=materialized):
                self.config["materialized"] = materialized
                self.context["run_query"].reset_mock()
                sql = self.operation()
                self.assertIn("full_refresh => false", sql)
                self.context["run_query"].assert_called_once_with(sql)

    def test_manual_full_refresh_is_explicit_for_both_materializations(self):
        for materialized in ("incremental", "table"):
            for requested in (False, True):
                with self.subTest(materialized=materialized, requested=requested):
                    self.config["materialized"] = materialized
                    expected = "true" if requested else "false"
                    self.assertIn(
                        f"full_refresh => {expected}",
                        self.operation(full_refresh=requested, dry_run=True),
                    )
        self.context["run_query"].assert_not_called()

    def test_manual_sync_guards_dev_execution_but_allows_preview_and_override(self):
        self.context["target"].name = "dev"
        with self.assertRaisesRegex(CompilationError, "Refusing datashare sync.*dev"):
            self.operation()
        self.operation(dry_run=True)
        self.context["run_query"].assert_not_called()
        self.operation(allow_prod_only=False)
        self.context["run_query"].assert_called_once()

    def test_selectors_resolve_model_name_alias_fqn_and_unique_id(self):
        for selector in (
            self.node.name,
            self.node.alias,
            ".".join(self.node.fqn),
            self.node.unique_id,
        ):
            with self.subTest(selector=selector):
                self.assertIn(
                    "dune.my_team.delivered", self.operation(selector, dry_run=True)
                )
        self.context["run_query"].assert_not_called()

    def test_missing_and_ambiguous_selectors_fail_without_queries(self):
        with self.assertRaisesRegex(CompilationError, "No model found"):
            self.operation("missing")
        self.context["graph"].nodes["duplicate"] = self.node
        with self.assertRaisesRegex(CompilationError, "ambiguous"):
            self.operation()
        self.context["run_query"].assert_not_called()

    def test_manual_sync_rejects_models_without_enabled_sync_or_table_materialization(
        self,
    ):
        for key, value in (("meta", {}), ("materialized", "view")):
            with self.subTest(key=key):
                previous = self.config[key]
                self.config[key] = value
                with self.assertRaisesRegex(CompilationError, "Cannot sync"):
                    self.operation()
                self.config[key] = previous
        self.context["run_query"].assert_not_called()


if __name__ == "__main__":
    unittest.main()
