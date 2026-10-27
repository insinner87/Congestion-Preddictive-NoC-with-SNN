#!/usr/bin/env python3
"""Generate labeled predictive-congestion data from the actual 4x4 mesh RTL."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RTL_AND_TB = [
    "rtl/common/noc_pkg.sv",
    "rtl/congestion/snn_model_parameters_pkg.sv",
    "rtl/congestion/distilled_congestion_model_pkg.sv",
    "rtl/congestion/distilled_congestion_predictor.sv",
    "rtl/router/fifo.sv",
    "rtl/router/input_buffer.sv",
    "rtl/router/round_robin_arbiter.sv",
    "rtl/congestion/congestion_monitor.sv",
    "rtl/congestion/congestion_estimator.sv",
    "rtl/congestion/tf_feature_extractor.sv",
    "rtl/congestion/snn_predictor.sv",
    "rtl/congestion/adaptive_predictor_selector.sv",
    "rtl/congestion/adaptive_buffer_controller.sv",
    "rtl/congestion/congestion_offload_controller.sv",
    "rtl/router/switch_allocator.sv",
    "rtl/router/crossbar.sv",
    "rtl/router/router_5port.sv",
    "rtl/mesh/mesh_route_compute.sv",
    "rtl/mesh/mesh_link_fifo.sv",
    "rtl/mesh/noc_router_wrapper.sv",
    "rtl/mesh/noc_mesh_4x4.sv",
    "sim/mesh/mesh_trace_tb.sv",
]
RAW_COLUMNS = [
    "cycle", "node", "port", "feature_valid", "features", "blocked_streak",
    "requester_count", "requester_cycles_8", "demand_active_cycles_8",
    "service_cycles_8", "service_deficit_8", "pressure_trend", "occupancy",
    "occupancy_max", "occupancy_rising", "request_nonempty", "output_transfer",
    "congestion_score", "congestion_prediction", "snn_risk_class",
]
DATA_COLUMNS = [
    "split", "run_id", "seed", "load_percent", "workload", "cycle", "node",
    "port", "feature_valid", "features", "blocked_streak", "requester_count",
    "requester_cycles_8", "demand_active_cycles_8", "service_cycles_8",
    "service_deficit_8", "pressure_trend", "occupancy", "occupancy_max",
    "occupancy_rising", "request_nonempty", "output_transfer",
    "congestion_score", "congestion_prediction", "snn_risk_class",
    "future_event", "target_valid", "target_congestion_within_h8",
]
WORKLOAD_IDS = {
    "uniform": 0,
    "hotspot": 1,
    "transpose": 2,
    "bursty": 3,
    "no_congestion": 4,
    "random": 5,
    "moderate": 6,
    "severe": 7,
    "mixed": 8,
}


def parse_int_list(value: str) -> list[int]:
    return [int(part.strip(), 0) for part in value.split(",") if part.strip()]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def build_simulator(build_dir: Path) -> tuple[Path, str, str]:
    compiler = shutil.which("iverilog")
    simulator = shutil.which("vvp")
    if not compiler or not simulator:
        raise RuntimeError("Icarus Verilog commands iverilog and vvp must be on PATH")
    executable = build_dir / "mesh_trace.vvp"
    command = [compiler, "-g2012", "-Wall", "-s", "mesh_trace_tb", "-o", str(executable)]
    command.extend(str(ROOT / path) for path in RTL_AND_TB)
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    (build_dir / "compile.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    if result.returncode:
        raise RuntimeError(f"Icarus compile failed; see {build_dir / 'compile.log'}")
    compiler_version = subprocess.run([compiler, "-V"], cwd=ROOT, text=True,
                                       capture_output=True).stdout.splitlines()[0]
    runtime_result = subprocess.run([simulator, "-V"], cwd=ROOT, text=True,
                                    capture_output=True)
    runtime_text = (runtime_result.stdout + runtime_result.stderr).splitlines()
    runtime_version = next((line for line in runtime_text if "Icarus Verilog runtime" in line),
                           "VVP version unavailable")
    return executable, compiler_version, runtime_version


def write_dataset(raw_runs: list[dict[str, object]], output_path: Path, horizon: int) -> int:
    total = 0
    with output_path.open("w", newline="", encoding="utf-8") as output_handle:
        writer = csv.DictWriter(output_handle, fieldnames=DATA_COLUMNS)
        writer.writeheader()
        for run in raw_runs:
            raw_path = Path(str(run["raw_file"]))
            by_stream: dict[tuple[int, int], list[dict[str, int]]] = {}
            with raw_path.open(newline="", encoding="utf-8") as raw_handle:
                for raw in csv.DictReader(raw_handle):
                    row = {key: int(raw[key]) for key in RAW_COLUMNS}
                    by_stream.setdefault((row["node"], row["port"]), []).append(row)
            for (node, port), rows in sorted(by_stream.items()):
                rows.sort(key=lambda row: row["cycle"])
                events = [
                    int(row["blocked_streak"] >= 4 or
                        (row["occupancy"] >= 2 and row["request_nonempty"] == 1))
                    for row in rows
                ]
                for index, row in enumerate(rows):
                    target_valid = int(index + horizon < len(rows))
                    future_event = events[index]
                    target = 0
                    if target_valid:
                        future = events[index + 1:index + horizon + 1]
                        target = int(any(future))
                    writer.writerow({
                        "split": run["split"], "run_id": run["run_id"], "seed": run["seed"],
                        "load_percent": run["load_percent"], "workload": run["workload"],
                        **row, "future_event": future_event,
                        "target_valid": target_valid,
                        "target_congestion_within_h8": target,
                    })
                    total += 1
    return total


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=ROOT / "validation/snn_experiment")
    parser.add_argument("--cycles", type=int, default=256)
    parser.add_argument("--horizon", type=int, default=8)
    parser.add_argument("--train-seeds", default="1001,1002")
    parser.add_argument("--validation-seeds", default="2001")
    parser.add_argument("--test-seeds", default="3001,3002,3003,3004,3005")
    parser.add_argument("--loads", default="5,50,95")
    parser.add_argument(
        "--workloads",
        default="no_congestion,random,moderate,severe,mixed",
    )
    args = parser.parse_args()
    if args.cycles <= args.horizon or args.horizon != 8:
        parser.error("cycles must exceed the RTL's documented eight-cycle prediction horizon")
    simulator = shutil.which("vvp")
    if not simulator:
        parser.error("vvp was not found on PATH")

    data_dir = args.data_dir.resolve()
    build_dir = data_dir / "build"
    raw_dir = data_dir / "raw"
    build_dir.mkdir(parents=True, exist_ok=True)
    raw_dir.mkdir(parents=True, exist_ok=True)
    executable, compiler_version, runtime_version = build_simulator(build_dir)
    seed_splits = {
        "train": parse_int_list(args.train_seeds),
        "validation": parse_int_list(args.validation_seeds),
        "test": parse_int_list(args.test_seeds),
    }
    all_seeds = [seed for values in seed_splits.values() for seed in values]
    if len(all_seeds) != len(set(all_seeds)):
        parser.error("train, validation, and test seed lists must be disjoint")
    loads = parse_int_list(args.loads)
    workloads = [item.strip().lower() for item in args.workloads.split(",") if item.strip()]
    unknown = sorted(set(workloads) - set(WORKLOAD_IDS))
    if unknown:
        parser.error(f"unknown workloads: {unknown}")

    manifest: dict[str, object] = {
        "schema_version": 1, "label_horizon_cycles": args.horizon,
        "congestion_event": "blocked_streak >= 4 OR (downstream link FIFO occupancy >= 2 and a request is present)",
        "scenario_definitions": {
            "no_congestion": "5% independent injection probability with random destinations",
            "random": "seeded random destinations with intermittent hotspot selection",
            "moderate": "30% injection with repeating 32-cycle 55% bursts",
            "severe": "95% sustained injection toward a central hotspot",
            "mixed": "alternating 64-cycle sparse (5%) and severe (95%) periods",
        },
        "workload_ids": WORKLOAD_IDS, "trace_cycles": args.cycles,
        "simulator_executable": executable.name,
        "simulator_versions": {"iverilog": compiler_version, "vvp": runtime_version},
        "compile_flags": ["-g2012", "-Wall", "-s", "mesh_trace_tb"],
        "trace_configuration": {
            "routing": "West-First", "tf_pcr_enabled": True,
            "snn_feature_capture": True, "snn_route_feedback": False,
            "equation_route_feedback": False, "adaptive_buffer_pressure": True,
            "priority_enabled": False, "trace_router_nodes": [5, 6, 9, 10],
            "link_fifo_depth": 2, "sample_period_cycles": 1,
        },
        "rtl_testbench": "sim/mesh/mesh_trace_tb.sv",
        "seed_splits": seed_splits, "loads": loads, "workloads": workloads,
        "runs": [],
    }
    runs: list[dict[str, object]] = []
    for split, seeds in seed_splits.items():
        for seed in seeds:
            for load in loads:
                if not 0 <= load <= 100:
                    parser.error("load levels must be percentages from 0 through 100")
                for workload_name in workloads:
                    run_id = f"{split}_s{seed}_l{load}_{workload_name}"
                    raw_file = raw_dir / f"{run_id}.csv"
                    route_file = raw_dir / f"{run_id}_routes.csv"
                    command = [
                        simulator, str(executable), f"+TRACE_FILE={raw_file}",
                        f"+TRACE_ROUTE_FILE={route_file}",
                        f"+CYCLES={args.cycles}", f"+SEED={seed}",
                        f"+LOAD={load}", f"+WORKLOAD={WORKLOAD_IDS[workload_name]}",
                    ]
                    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
                    if result.returncode:
                        raise RuntimeError(
                            f"Trace run {run_id} failed (exit {result.returncode}):\n"
                            f"{result.stdout}\n{result.stderr}"
                        )
                    summary = re.search(
                        r"MESH TRACE SUMMARY: offered=(\d+) accepted=(\d+) "
                        r"delivered=(\d+) missing=(\d+) duplicates=(\d+) "
                        r"corrupted=(\d+) max_link_occupancy=(\d+)",
                        result.stdout,
                    )
                    if summary is None:
                        raise RuntimeError(
                            f"Trace run {run_id} omitted its integrity/traffic summary"
                        )
                    offered, accepted, delivered, missing, duplicates, corrupted, max_occupancy = (
                        int(value) for value in summary.groups()
                    )
                    if (accepted != offered or delivered != accepted or missing != 0 or
                            duplicates != 0 or corrupted != 0):
                        raise RuntimeError(
                            f"Trace integrity failed for {run_id}: "
                            f"offered={offered}, accepted={accepted}, delivered={delivered}, "
                            f"missing={missing}, duplicates={duplicates}, corrupted={corrupted}"
                        )
                    if not route_file.exists() or route_file.stat().st_size == 0:
                        raise RuntimeError(f"Trace run {run_id} produced no route log")
                    run_record: dict[str, object] = {
                        "run_id": run_id, "split": split, "seed": seed,
                        "load_percent": load, "workload": workload_name,
                        "workload_id": WORKLOAD_IDS[workload_name], "cycles": args.cycles,
                        "raw_file": str(raw_file),
                        "raw_sha256": sha256(raw_file),
                        "route_file": str(route_file),
                        "route_sha256": sha256(route_file),
                        "traffic": {
                            "offered_flits": offered,
                            "accepted_flits": accepted,
                            "delivered_flits": delivered,
                            "missing_flits": missing,
                            "duplicate_flits": duplicates,
                            "corrupted_flits": corrupted,
                            "throughput_flits_per_cycle": delivered / args.cycles,
                            "maximum_link_occupancy": max_occupancy,
                        },
                    }
                    runs.append(run_record)
                    print(f"Generated {run_id}: {raw_file.stat().st_size:,} bytes")
    manifest["runs"] = runs
    manifest_path = data_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    dataset_path = data_dir / "dataset.csv"
    row_count = write_dataset(runs, dataset_path, args.horizon)
    manifest["dataset_file"] = str(dataset_path)
    manifest["dataset_sha256"] = sha256(dataset_path)
    manifest["dataset_rows"] = row_count
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Wrote {row_count:,} rows to {dataset_path}")
    print(f"Manifest: {manifest_path}")
    print("Raw traces retained and checksummed in the manifest.")


if __name__ == "__main__":
    main()
