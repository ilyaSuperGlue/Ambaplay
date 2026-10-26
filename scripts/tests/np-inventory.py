#!/usr/bin/env python3
"""Offline regression for Steam libraries outside the default install."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "np-inventory.py"
spec = importlib.util.spec_from_file_location("ambaplay_np_inventory", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class InventoryTests(unittest.TestCase):
    def test_external_library_manifests_and_executables(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            primary = root / "Steam" / "steamapps"
            other = root / "Library with spaces" / "steamapps"
            for directory in (primary, other):
                (directory / "common" / "Game").mkdir(parents=True)
            (primary / "libraryfolders.vdf").write_text(
                '"libraryfolders"\n{\n "1"\n {\n "path" "' + str(other.parent) + '"\n }\n}\n')
            for folder, appid in ((primary, 101), (other, 102), (other, 101)):
                (folder / f"appmanifest_{appid}.acf").write_text(
                    '"AppState"\n{\n "appid" "' + str(appid) +
                    '"\n "name" "Game"\n "installdir" "Game"\n}\n')
            (other / "common" / "Game" / "game.exe").write_text("")
            with patch.object(module, "STEAMAPPS", str(primary)), \
                    patch.object(module, "ROOT", str(root)), \
                    patch.object(module.L, "store", return_value={"mac": False, "windows": True}), \
                    patch.object(module.L, "pcgw", return_value=None), \
                    patch.object(module.L, "awacy", return_value=(None, [])):
                module.main()
            rows = json.loads((root / "compat" / "installed.json").read_text())
            self.assertEqual([101, 102], sorted(r["appid"] for r in rows))
            external = next(r for r in rows if r["appid"] == 102)
            self.assertEqual(["game.exe"], external["exes"])


    def test_invalid_manifest_does_not_hide_valid_copy_in_other_library(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            primary = root / "Steam" / "steamapps"
            external = root / "External Library" / "steamapps"
            primary.mkdir(parents=True)
            (external / "common" / "Valid Game").mkdir(parents=True)
            (primary / "libraryfolders.vdf").write_text(
                '"libraryfolders"\n{\n "1"\n {\n "path" "' +
                str(external.parent) + '"\n }\n}\n')
            (primary / "appmanifest_101.acf").write_text(
                '"AppState"\n{\n "name" "Incomplete"\n}\n')
            (external / "appmanifest_101.acf").write_text(
                '"AppState"\n{\n "appid" "101"\n "name" "Valid Game"\n'
                ' "installdir" "Valid Game"\n}\n')
            (external / "common" / "Valid Game" / "game.exe").write_text("")
            with patch.object(module, "STEAMAPPS", str(primary)), \
                    patch.object(module, "ROOT", str(root)), \
                    patch.object(module.L, "store", return_value={"mac": False, "windows": True}), \
                    patch.object(module.L, "pcgw", return_value=None), \
                    patch.object(module.L, "awacy", return_value=(None, [])):
                module.main()
            rows = json.loads((root / "compat" / "installed.json").read_text())
            self.assertEqual([101], [r["appid"] for r in rows])
            self.assertEqual(["game.exe"], rows[0]["exes"])


    def test_legacy_config_index(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            steam = root / "Steam"
            primary = steam / "steamapps"
            legacy = root / "Older Library" / "steamapps"
            primary.mkdir(parents=True)
            legacy.mkdir(parents=True)
            config = steam / "config"
            config.mkdir()
            (config / "libraryfolders.vdf").write_text(
                '"libraryfolders"\n{\n "1"\n {\n "path" "' +
                str(legacy.parent) + '"\n }\n}\n')
            (legacy / "appmanifest_201.acf").write_text('"AppState"\n{}\n')
            with patch.object(module, "STEAMAPPS", str(primary)):
                found = list(module.installed_manifests())
            self.assertEqual(
                [(legacy / "appmanifest_201.acf").resolve()],
                [Path(manifest).resolve() for manifest in found],
            )

    def test_modern_and_legacy_indexes_are_combined(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            steam = root / "Steam"
            primary = steam / "steamapps"
            modern = root / "Modern Library" / "steamapps"
            legacy = root / "Older Library" / "steamapps"
            for folder in (primary, modern, legacy):
                folder.mkdir(parents=True)
            (primary / "libraryfolders.vdf").write_text(
                '"libraryfolders"\n{\n "1"\n {\n "path" "' +
                str(modern.parent) + '"\n }\n}\n')
            (steam / "config").mkdir()
            (steam / "config" / "libraryfolders.vdf").write_text(
                '"libraryfolders"\n{\n "2"\n {\n "path" "' +
                str(legacy.parent) + '"\n }\n}\n')
            (modern / "appmanifest_301.acf").write_text('"AppState"\n{}\n')
            (legacy / "appmanifest_302.acf").write_text('"AppState"\n{}\n')
            with patch.object(module, "STEAMAPPS", str(primary)):
                found = sorted(Path(p).name for p in module.installed_manifests())
            self.assertEqual(["appmanifest_301.acf", "appmanifest_302.acf"], found)


if __name__ == "__main__":
    unittest.main()
