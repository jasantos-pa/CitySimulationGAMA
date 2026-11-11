"""Prepare isolated, auditable GAMA runs without changing the source project."""

import argparse
import csv
import hashlib
import json
import math
import re
import shutil
import subprocess
import sys
import uuid
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path, value):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, allow_nan=False)
        stream.write("\n")


def project_file(project, path):
    resolved = path.resolve()
    if not resolved.is_relative_to(project):
        raise ValueError(f"Dependency outside project: {path}")
    relative = resolved.relative_to(project)
    cursor = project
    for part in path.absolute().relative_to(project).parts:
        cursor = cursor / part
        if cursor.is_symlink():
            raise ValueError(f"Symbolic links are not supported: {cursor}")
    if not resolved.is_file():
        raise ValueError(f"Missing dependency: {relative}")
    return resolved


def discover(project, model, extra_inputs=()):
    sources = set()
    inputs = set()
    pending = [project_file(project, project / model)]
    while pending:
        source = pending.pop()
        if source in sources:
            continue
        sources.add(source)
        text = source.read_text(encoding="utf-8-sig")
        for imported in re.findall(r'(?m)^\s*import\s+["\']([^"\']+)["\']', text):
            pending.append(project_file(project, source.parent / imported))
        for literal in re.findall(r'["\'](\.\./includes/[^"\']+)["\']', text):
            inputs.add(project_file(project, source.parent / literal))
    for relative in extra_inputs:
        inputs.add(project_file(project, project / relative))
    for path in list(inputs):
        if path.suffix.lower() == ".shp":
            for suffix in (".shx", ".dbf", ".prj"):
                inputs.add(project_file(project, path.with_suffix(suffix)))
            inputs.update(sibling for sibling in path.parent.glob(path.stem + ".*") if sibling.is_file())
        if path.suffix.lower() in (".db", ".sqlite", ".sqlite3"):
            for suffix in ("-wal", "-journal"):
                journal = Path(str(path) + suffix)
                if journal.exists() and journal.stat().st_size:
                    raise ValueError(f"Database has an active journal; obtain a consistent offline copy: {path.name}")
    for path in inputs:
        project_file(project, path)
    return sorted(sources), sorted(inputs - sources)


def git(project, *arguments):
    result = subprocess.run(
        ["git", "--no-optional-locks", "-C", str(project), *arguments],
        capture_output=True,
        check=True,
    )
    return result.stdout


def git_record(project, sources, allow_no_git=False):
    relative = [path.relative_to(project).as_posix() for path in sources]
    try:
        status = git(project, "status", "--porcelain=v1", "--untracked-files=all")
        tracked = git(project, "ls-files", "-z", "--", *relative).decode("utf-8", errors="replace").split("\0")
        record = {
            "commit": git(project, "rev-parse", "HEAD").decode().strip(),
            "branch": git(project, "branch", "--show-current").decode().strip(),
            "working_tree_dirty": bool(status),
            "source_files_not_tracked": sorted(set(relative) - set(tracked)),
            "scope": "Dirty status excludes ignored files; exact source snapshots are authoritative.",
        }
        patch = git(project, "diff", "--binary", "--no-ext-diff", "HEAD", "--", *relative)
        return record, patch
    except (OSError, subprocess.CalledProcessError) as error:
        if not allow_no_git:
            raise ValueError("Cannot capture Git provenance. Run as the repository owner or explicitly use --allow-no-git for an unversioned source.") from error
        return {"available": False, "reason": type(error).__name__}, b""


def copy_verified(project, path, destination):
    expected = sha256(path)
    relative = path.relative_to(project)
    target = destination / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    with path.open("rb") as source, target.open("xb") as output:
        shutil.copyfileobj(source, output)
    if sha256(path) != expected or sha256(target) != expected:
        raise ValueError(f"File changed while taking snapshot: {relative}")
    return {"path": relative.as_posix(), "sha256": expected, "bytes": target.stat().st_size}


def parameter_values(path, model_text):
    values = json.loads(path.read_text(encoding="utf-8-sig")) if path else {}
    if not isinstance(values, dict):
        raise ValueError("Parameters must be a JSON object keyed by GAML variable.")
    exposed = set(re.findall(r'\bparameter\s+[^\n]*?\bvar:\s*(\w+)', model_text))
    resolved = {}
    for variable, value in values.items():
        if variable not in exposed:
            raise ValueError(f"Parameter is not exposed by the model: {variable}")
        if isinstance(value, bool):
            kind, encoded = "BOOLEAN", str(value).lower()
        elif isinstance(value, int):
            kind, encoded = "INT", str(value)
        elif isinstance(value, float) and math.isfinite(value):
            kind, encoded = "FLOAT", str(value)
        elif isinstance(value, str):
            kind, encoded = "STRING", value
        else:
            raise ValueError(f"Unsupported parameter value: {variable}")
        resolved[variable] = {"type": kind, "value": encoded}
    return values, resolved


def prepare(args):
    project = args.project.resolve()
    source = project_file(project, project / args.model)
    text = source.read_text(encoding="utf-8-sig")
    if not re.search(r'(?m)^experiment\s+' + re.escape(args.experiment) + r'\b', text):
        raise ValueError("Experiment does not exist in selected model.")
    if not math.isfinite(args.seed) or args.seed == 0:
        raise ValueError("Use an explicit finite, nonzero seed.")
    if args.steps < 1:
        raise ValueError("Steps must be positive.")
    requested, parameters = parameter_values(args.parameters, text)
    sources, inputs = discover(project, args.model, args.input)
    revision, patch = git_record(project, sources, args.allow_no_git)
    gama_home = args.gama_home.resolve()
    configuration = gama_home / "configuration" / "config.ini"
    launcher = gama_home / "headless" / "gama-headless.bat"
    if not configuration.is_file() or not launcher.is_file():
        raise ValueError("GAMA installation must contain configuration/config.ini and headless/gama-headless.bat.")
    config_text = configuration.read_text(encoding="utf-8", errors="replace")
    match = re.search(r'(?m)^gama.branch=(.+)$', config_text)
    run_id = args.run_id or (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8])
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,100}', run_id) or run_id.endswith("."):
        raise ValueError("Run ID must be a simple unique directory name.")
    output_root = args.output_root.resolve()
    if output_root == project or output_root.is_relative_to(source.parent) or output_root.is_relative_to(project / "includes"):
        raise ValueError("Output root must be separate from model and input directories.")
    run_dir = output_root / run_id
    output_root.mkdir(parents=True, exist_ok=True)
    run_dir.mkdir(exist_ok=False)
    snapshot = run_dir / "project"
    snapshot.mkdir()
    source_records = [copy_verified(project, path, snapshot) for path in sources]
    input_records = [copy_verified(project, path, snapshot) for path in inputs]
    for record in source_records + input_records:
        if sha256(project / record["path"]) != record["sha256"]:
            raise ValueError(f"Source project changed during preparation: {record['path']}")
    (run_dir / "source.patch").write_bytes(patch)
    tool_copy = run_dir / "run_archive.py"
    shutil.copyfile(Path(__file__), tool_copy)
    model_relative = source.relative_to(project).as_posix()
    plan = ET.Element("Experiment_plan")
    simulation = ET.SubElement(plan, "Simulation", {
        "experiment": args.experiment,
        "finalStep": str(args.steps),
        "id": "0",
        "seed": str(args.seed),
        "sourcePath": (snapshot / model_relative).as_posix(),
    })
    xml_parameters = ET.SubElement(simulation, "Parameters")
    for variable, value in parameters.items():
        ET.SubElement(xml_parameters, "Parameter", {"var": variable, "name": variable, **value})
    ET.SubElement(simulation, "Outputs")
    ET.ElementTree(plan).write(run_dir / "plan.xml", encoding="utf-8", xml_declaration=True)
    warnings = [
        "Prepared only: no simulation executed and effective runtime parameters/seed not observed.",
        "Automatic dependency discovery covers literal ../includes/ paths and imports only; declare other dependencies with --input.",
        "CSV file paths remain unchanged inside the isolated project; finalize after GAMA has stopped.",
    ]
    if "RANDOM()" in text.upper():
        warnings.append("SQL RANDOM() is independent of the requested GAMA seed; bit-for-bit replay is not guaranteed.")
    if "create simulation with:" in text:
        warnings.append("Experiment initialization sets values explicitly; requested XML parameters can differ from effective values.")
    if "sync_electric_taxi_fleet_runtime" in text:
        warnings.append("Interactive parameter changes are possible; record interventions or avoid them in comparable runs.")
    manifest = {
        "schema_version": 1,
        "run_id": run_id,
        "created_utc": utc_now(),
        "status": "prepared",
        "source_project": str(project),
        "model": model_relative,
        "experiment": args.experiment,
        "git": revision,
        "sources": source_records,
        "inputs": input_records,
        "requested": {"seed": args.seed, "final_step": args.steps, "parameters": requested},
        "effective_runtime": None,
        "gama": {"home": str(gama_home), "declared_branch": match.group(1).strip() if match else None,
                 "config_sha256": sha256(configuration), "launcher_sha256": sha256(launcher)},
        "host": {"platform": sys.platform, "python": sys.version.split()[0]},
        "tool_sha256": sha256(tool_copy),
        "plan_sha256": sha256(run_dir / "plan.xml"),
        "launch": {"argv": [str(launcher), "-ws", str(run_dir / "gama-workspace"), str(run_dir / "plan.xml"), str(run_dir / "headless")],
                   "cwd": str((snapshot / model_relative).parent)},
        "warnings": warnings,
    }
    write_json(run_dir / "manifest.json", manifest)
    return {"run_dir": str(run_dir), "manifest": str(run_dir / "manifest.json"), "status": "prepared", "warnings": warnings}


def finalize(args):
    run_dir = args.run_dir.resolve()
    manifest = json.loads((run_dir / "manifest.json").read_text(encoding="utf-8"))
    if (run_dir / "results.json").exists():
        raise ValueError("Run is already finalized; existing records are never overwritten.")
    snapshot = run_dir / "project"
    for record in manifest["sources"] + manifest["inputs"]:
        path = project_file(snapshot, snapshot / record["path"])
        if sha256(path) != record["sha256"]:
            raise ValueError(f"Snapshot changed: {record['path']}")
    if sha256(run_dir / "plan.xml") != manifest["plan_sha256"]:
        raise ValueError("Execution plan changed after preparation.")
    if sha256(run_dir / "run_archive.py") != manifest["tool_sha256"]:
        raise ValueError("Archived tool changed after preparation.")
    outputs = []
    captured_inputs = {"project/" + record["path"] for record in manifest["inputs"]}
    for path in sorted(run_dir.rglob("*.csv")):
        relative = path.relative_to(run_dir).as_posix()
        if relative.startswith("gama-workspace/") or relative in captured_inputs:
            continue
        project_file(run_dir, path)
        with path.open(encoding="utf-8-sig", errors="replace", newline="") as stream:
            header = next(csv.reader(stream), [])
        outputs.append({"path": relative, "sha256": sha256(path), "bytes": path.stat().st_size, "header": header})
    if not outputs:
        raise ValueError("No CSV results found; a prepared plan is not a completed run.")
    result = {
        "schema_version": 1, "run_id": manifest["run_id"], "finalized_utc": utc_now(),
        "status": "outputs_archived_unvalidated", "reported_exit_code": args.exit_code,
        "manifest_sha256": sha256(run_dir / "manifest.json"), "outputs": outputs,
        "limitations": "CSV presence and hashes do not prove completion, correct parameters, or scientific validity. Logs may contain buffered or partial runs.",
    }
    write_json(run_dir / "results.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    preparation = commands.add_parser("prepare", help="Snapshot code/inputs and write a plan; does not launch GAMA.")
    preparation.add_argument("--project", type=Path, required=True)
    preparation.add_argument("--model", required=True)
    preparation.add_argument("--experiment", default="Leganes")
    preparation.add_argument("--seed", type=float, required=True)
    preparation.add_argument("--steps", type=int, required=True)
    preparation.add_argument("--gama-home", type=Path, required=True)
    preparation.add_argument("--output-root", type=Path, required=True)
    preparation.add_argument("--parameters", type=Path)
    preparation.add_argument("--input", action="append", default=[])
    preparation.add_argument("--run-id")
    preparation.add_argument("--allow-no-git", action="store_true", help="Explicitly allow an unversioned archive if Git provenance is unavailable.")
    preparation.set_defaults(operation=prepare)
    completion = commands.add_parser("finalize", help="Hash isolated CSV outputs after GAMA has stopped.")
    completion.add_argument("--run-dir", type=Path, required=True)
    completion.add_argument("--exit-code", type=int)
    completion.set_defaults(operation=finalize)
    args = parser.parse_args()
    try:
        print(json.dumps(args.operation(args), ensure_ascii=False, indent=2))
    except (ValueError, OSError, subprocess.CalledProcessError, ET.ParseError) as error:
        parser.exit(1, f"{type(error).__name__}: {error}\n")


if __name__ == "__main__":
    main()
