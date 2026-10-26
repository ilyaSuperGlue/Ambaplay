#!/usr/bin/env python3
"""Regression coverage for multi-ID Steam compatibility entries (offline)."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "compat-reported.py"
spec = importlib.util.spec_from_file_location("ambaplay_compat_reported", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReportedCompatTests(unittest.TestCase):
    def test_multiple_appids_from_one_compatible_page(self):
        pages = [
            {"title": "Two Editions", "revisions": [{"slots": {"main": {"content":
                "| crossover = Perfect\n| steam appid = 42, 43, invalid\n"}}}]},
            {"title": "Not Compatible", "revisions": [{"slots": {"main": {"content":
                "| crossover = Broken\n| steam appid = 44\n"}}}]},
        ]
        with tempfile.TemporaryDirectory() as tmp, \
                patch.object(module, "OUT", str(Path(tmp) / "reported.json")), \
                patch.object(module, "pages", return_value=[p["title"] for p in pages]), \
                patch.object(module, "api", return_value={"query": {"pages": pages}}):
            module.main()
            result = json.loads(Path(module.OUT).read_text())
        self.assertEqual([42, 43], sorted(g["appid"] for g in result["games"]))
        self.assertTrue(all(g["crossover"] == "perfect" for g in result["games"]))


if __name__ == "__main__":
    unittest.main()
