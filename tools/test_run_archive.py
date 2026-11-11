import argparse
import json
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

import run_archive


class RunArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.project = self.root / "project"
        (self.project / "models").mkdir(parents=True)
        (self.project / "includes").mkdir()
        self.model = self.project / "models" / "candidate copy.gaml"
        self.model.write_text(
            'model test\nimport "helper.gaml"\n'
            'global { file roads <- file("../includes/roads.shp"); }\n'
            'experiment Leganes type: gui {\n'
            'parameter "Count" var: count <- 10;\n}\n', encoding="utf-8")
        (self.project / "models" / "helper.gaml").write_text("model helper\n", encoding="utf-8")
        for suffix in (".shp", ".shx", ".dbf", ".prj", ".cpg"):
            (self.project / "includes" / ("roads" + suffix)).write_bytes(b"fixture")
        self.gama = self.root / "gama"
        (self.gama / "configuration").mkdir(parents=True)
        (self.gama / "headless").mkdir()
        (self.gama / "configuration" / "config.ini").write_text("gama.branch=2025-06-4\n")
        (self.gama / "headless" / "gama-headless.bat").write_text("fixture, never executed")
        self.args = argparse.Namespace(
            project=self.project, model="models/candidate copy.gaml", experiment="Leganes",
            seed=42.0, steps=100, gama_home=self.gama, output_root=self.root / "runs",
            parameters=None, input=[], run_id="test-run", allow_no_git=True)

    def prepare(self):
        result = run_archive.prepare(self.args)
        run_dir = Path(result["run_dir"])
        return run_dir, json.loads((run_dir / "manifest.json").read_text(encoding="utf-8"))

    def test_exact_snapshot_includes_imports_and_shapefile_companions(self):
        original = self.model.read_bytes()
        run_dir, manifest = self.prepare()
        self.assertEqual(original, (run_dir / "project" / self.args.model).read_bytes())
        self.assertEqual(original, self.model.read_bytes())
        self.assertEqual(2, len(manifest["sources"]))
        self.assertEqual(5, len(manifest["inputs"]))
        self.assertEqual("prepared", manifest["status"])
        self.assertIsNone(manifest["effective_runtime"])
        self.assertEqual("2025-06-4", manifest["gama"]["declared_branch"])
        self.assertEqual("42.0", ET.parse(run_dir / "plan.xml").find("Simulation").get("seed"))
        self.assertEqual(str((self.gama / "headless").resolve()), manifest["launch"]["cwd"])

    def test_existing_run_is_not_overwritten(self):
        run_dir, _ = self.prepare()
        before = (run_dir / "manifest.json").read_bytes()
        with self.assertRaises(FileExistsError):
            self.prepare()
        self.assertEqual(before, (run_dir / "manifest.json").read_bytes())

    def test_outside_project_dependency_rejected(self):
        (self.root / "external.gaml").write_text("model external")
        self.model.write_text('model test\nimport "../../external.gaml"\nexperiment Leganes type: gui {}')
        with self.assertRaisesRegex(ValueError, "outside project"):
            self.prepare()

    def test_missing_shapefile_companion_rejected(self):
        (self.project / "includes" / "roads.shx").unlink()
        with self.assertRaisesRegex(ValueError, "Missing dependency"):
            self.prepare()
        self.assertFalse(self.args.output_root.exists())

    def test_zero_seed_and_path_traversal_run_id_rejected(self):
        self.args.seed = 0
        with self.assertRaisesRegex(ValueError, "nonzero seed"):
            self.prepare()
        self.args.seed = 42
        self.args.run_id = "../escape"
        with self.assertRaisesRegex(ValueError, "Run ID"):
            self.prepare()

    def test_parameter_types_and_unknown_parameter(self):
        self.args.parameters = self.root / "parameters.json"
        self.args.parameters.write_text('{"count": 20}', encoding="utf-8")
        run_dir, manifest = self.prepare()
        parameter = ET.parse(run_dir / "plan.xml").find("Simulation/Parameters/Parameter")
        self.assertEqual("INT", parameter.get("type"))
        self.assertEqual(20, manifest["requested"]["parameters"]["count"])
        self.args.parameters.write_text('{"numPeople": 500}', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "not exposed"):
            run_archive.parameter_values(self.args.parameters, self.model.read_text())

    def test_sqlite_active_wal_rejected(self):
        (self.project / "includes" / "source.db").write_bytes(b"fixture")
        (self.project / "includes" / "source.db-wal").write_bytes(b"pending transaction")
        self.args.input = ["includes/source.db"]
        with self.assertRaisesRegex(ValueError, "active journal"):
            self.prepare()

    def test_finalize_hashes_csv_without_claiming_completion(self):
        run_dir, _ = self.prepare()
        csv_path = run_dir / "project" / "models" / "trips.csv"
        csv_path.write_text("trip_id,status\n1,COMPLETED\n", encoding="utf-8")
        args = argparse.Namespace(run_dir=run_dir, exit_code=0)
        result = run_archive.finalize(args)
        self.assertEqual("outputs_archived_unvalidated", result["status"])
        self.assertEqual(run_archive.sha256(csv_path), result["outputs"][0]["sha256"])
        self.assertEqual(["trip_id", "status"], result["outputs"][0]["header"])
        with self.assertRaisesRegex(ValueError, "already finalized"):
            run_archive.finalize(args)
        self.assertFalse((self.project / "models" / "trips.csv").exists())

    def test_finalize_rejects_mutated_snapshot_or_missing_outputs(self):
        run_dir, _ = self.prepare()
        args = argparse.Namespace(run_dir=run_dir, exit_code=None)
        with self.assertRaisesRegex(ValueError, "No CSV"):
            run_archive.finalize(args)
        (run_dir / "project" / self.args.model).write_text("model changed")
        with self.assertRaisesRegex(ValueError, "Snapshot changed"):
            run_archive.finalize(args)

    def test_dirty_and_ignored_sources_are_preserved(self):
        subprocess.run(["git", "init", str(self.project)], check=True, capture_output=True)
        (self.project / ".gitignore").write_text("models/*\n!models/helper.gaml\n")
        subprocess.run(["git", "-C", str(self.project), "add", ".gitignore", "models/helper.gaml"], check=True, capture_output=True)
        subprocess.run(["git", "-C", str(self.project), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-m", "fixture"], check=True, capture_output=True)
        helper = self.project / "models" / "helper.gaml"
        helper.write_text("model helper\n\n")
        run_dir, manifest = self.prepare()
        self.assertTrue(manifest["git"]["working_tree_dirty"])
        self.assertIn(self.args.model, manifest["git"]["source_files_not_tracked"])
        self.assertIn(b"helper.gaml", (run_dir / "source.patch").read_bytes())
        self.assertEqual(helper.read_bytes(), (run_dir / "project/models/helper.gaml").read_bytes())

    def test_finalize_rejects_changed_execution_plan(self):
        run_dir, _ = self.prepare()
        (run_dir / "plan.xml").write_text("changed")
        with self.assertRaisesRegex(ValueError, "Execution plan changed"):
            run_archive.finalize(argparse.Namespace(run_dir=run_dir, exit_code=None))

    def test_input_csv_is_not_misidentified_as_a_result(self):
        (self.project / "includes" / "schedule.csv").write_text("hour,count\n7,20\n")
        self.args.input = ["includes/schedule.csv"]
        run_dir, _ = self.prepare()
        with self.assertRaisesRegex(ValueError, "No CSV"):
            run_archive.finalize(argparse.Namespace(run_dir=run_dir, exit_code=None))

    def test_missing_git_provenance_requires_explicit_opt_out(self):
        self.args.allow_no_git = False
        with self.assertRaisesRegex(ValueError, "Cannot capture Git provenance"):
            self.prepare()
        self.assertFalse(self.args.output_root.exists())


if __name__ == "__main__":
    unittest.main()
