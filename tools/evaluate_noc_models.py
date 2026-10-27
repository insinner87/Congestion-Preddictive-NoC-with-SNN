#!/usr/bin/env python3
"""Evaluate frozen NoC predictors on generated traces without training."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from collections import Counter
from dataclasses import fields
from pathlib import Path
from typing import Any

import numpy as np

from train_noc_snn import (
    SplitData,
    binary_metrics,
    evaluate as evaluate_snn,
    infer,
    load_dataset,
)
from distill_noc_snn import evaluate_equation


ROOT = Path(__file__).resolve().parents[1]
PERFORMANCE_PATTERN = re.compile(
    r"PERFORMANCE mode=(?P<mode>\d+) seed=(?P<seed>\d+) "
    r"offered=(?P<offered>\d+) injected=(?P<injected>\d+) "
    r"delivered=(?P<delivered>\d+) avg-latency=(?P<average_latency>[\d.]+) "
    r"max-latency=(?P<maximum_latency>\d+) p95-latency=(?P<p95_latency>\d+) "
    r"p99-latency=(?P<p99_latency>\d+) cycles throughput="
    r"(?P<throughput>[\d.]+) packets/cycle avg-link-occupancy="
    r"(?P<average_link_occupancy>[\d.]+) max-link-occupancy="
    r"(?P<maximum_link_occupancy>\d+) random-phase-alternate-hops="
    r"(?P<alternate_hops>\d+)"
)
INTEGRITY_PATTERN = re.compile(
    r"INTEGRITY injected=(\d+) delivered=(\d+) missing=(\d+) "
    r"duplicates=(\d+) corrupted=(\d+) unexpected=(\d+) final=(\w+)"
)
ADAPTIVE_PATTERN = re.compile(
    r"ADAPTIVE POLICY offline-validation=(\d+)% offline-correct=(\d+) "
    r"offline-total=(\d+) threshold=(\d+)% "
    r"min-samples=(\d+) online-window=(\d+) initial-SNN-selections=(\d+) "
    r"initial-equation-selections=(\d+) SNN-selected-samples=(\d+) "
    r"equation-selected-samples=(\d+) to-SNN-switches=(\d+) "
    r"to-equation-switches=(\d+)"
)
MODEL_SELECTION_PATTERN = re.compile(
    r"MODEL_SELECTION cycle=(\d+) node=(\d+) output=(\d+) model=(\d+) "
    r"kind=(\d+) reason=(\d+) online_accuracy=(\d+) online_samples=(\d+)"
)


def subset_seed(data: SplitData, seed: int) -> SplitData:
    mask = data.seeds == seed
    return SplitData(**{
        field.name: getattr(data, field.name)[mask]
        for field in fields(SplitData)
    })


def evaluate_equation_agreement(
    data: SplitData, equation: dict[str, Any], snn_predictions: np.ndarray
) -> float:
    coefficients = np.asarray(equation["coefficient_signed_8"], dtype=np.int32)
    scores = data.features.astype(np.int32) @ coefficients
    scores += int(equation["bias_signed_12"])
    predictions = (scores >= int(equation["decision_threshold"])) & data.valid.astype(bool)
    mask = data.valid.astype(bool) & data.target_valid.astype(bool)
    return float(np.mean(predictions[mask] == snn_predictions[mask]))


def validation_threshold_sweep(
    data: SplitData, snn_model: dict[str, Any], equation: dict[str, Any]
) -> dict[str, Any]:
    snn_predictions, risk_classes = infer(data, snn_model)
    mask = data.valid.astype(bool) & data.target_valid.astype(bool)
    targets = data.targets.astype(bool)
    result: dict[str, Any] = {"snn_risk_class_threshold": {}, "equation_score_threshold": {}}

    for threshold in (1, 2, 3):
        predictions = risk_classes >= threshold
        result["snn_risk_class_threshold"][str(threshold)] = {
            "overall": binary_metrics(targets[mask], predictions[mask], risk_classes[mask]),
            "by_port": {},
        }
        for port in sorted(set(data.ports.tolist())):
            group_mask = mask & (data.ports[:, None] == port)
            result["snn_risk_class_threshold"][str(threshold)]["by_port"][str(port)] = (
                binary_metrics(targets[group_mask], predictions[group_mask], risk_classes[group_mask])
            )

    coefficients = np.asarray(equation["coefficient_signed_8"], dtype=np.int32)
    equation_scores = data.features.astype(np.int32) @ coefficients
    equation_scores += int(equation["bias_signed_12"])
    for threshold in (-2, -1, 0, 1, 2):
        predictions = (equation_scores >= threshold) & data.valid.astype(bool)
        result["equation_score_threshold"][str(threshold)] = {
            "overall": binary_metrics(targets[mask], predictions[mask], equation_scores[mask]),
            "by_port": {},
        }
        for port in sorted(set(data.ports.tolist())):
            group_mask = mask & (data.ports[:, None] == port)
            result["equation_score_threshold"][str(threshold)]["by_port"][str(port)] = (
                binary_metrics(targets[group_mask], predictions[group_mask], equation_scores[group_mask])
            )

    return result


def summarize_traffic_manifest(dataset_path: Path) -> dict[str, Any]:
    manifest_path = dataset_path.parent / "manifest.json"
    if not manifest_path.exists():
        return {"available": False}

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    groups: dict[tuple[str, str, int], dict[str, Any]] = {}
    for run in manifest.get("runs", []):
        key = (str(run["split"]), str(run["workload"]), int(run["load_percent"]))
        totals = groups.setdefault(key, {
            "runs": 0,
            "seeds": [],
            "offered_flits": 0,
            "accepted_flits": 0,
            "delivered_flits": 0,
            "missing_flits": 0,
            "duplicate_flits": 0,
            "corrupted_flits": 0,
            "maximum_link_occupancy": 0,
            "route_decisions": 0,
            "selected_port_counts": Counter(),
            "occupancy_sum": 0,
            "occupancy_samples": 0,
            "maximum_sampled_occupancy": 0,
            "blocked_streak_maximum": 0,
            "tfpcr_positive_samples": 0,
            "congestion_score_distribution": Counter(),
            "snn_risk_class_distribution": Counter(),
        })
        totals["runs"] += 1
        totals["seeds"].append(int(run["seed"]))
        traffic = run.get("traffic", {})
        for field in (
            "offered_flits", "accepted_flits", "delivered_flits",
            "missing_flits", "duplicate_flits", "corrupted_flits",
        ):
            totals[field] += int(traffic.get(field, 0))
        totals["maximum_link_occupancy"] = max(
            totals["maximum_link_occupancy"],
            int(traffic.get("maximum_link_occupancy", 0)),
        )
        raw_path = Path(str(run["raw_file"]))
        if raw_path.is_file():
            with raw_path.open(newline="", encoding="utf-8") as raw_handle:
                for raw_row in csv.DictReader(raw_handle):
                    occupancy = int(raw_row["occupancy"])
                    totals["occupancy_sum"] += occupancy
                    totals["occupancy_samples"] += 1
                    totals["maximum_sampled_occupancy"] = max(
                        totals["maximum_sampled_occupancy"], occupancy
                    )
                    totals["blocked_streak_maximum"] = max(
                        totals["blocked_streak_maximum"],
                        int(raw_row["blocked_streak"]),
                    )
                    totals["tfpcr_positive_samples"] += int(
                        raw_row["congestion_prediction"]
                    )
                    totals["congestion_score_distribution"][
                        raw_row["congestion_score"]
                    ] += 1
                    totals["snn_risk_class_distribution"][
                        raw_row["snn_risk_class"]
                    ] += 1
        route_path = Path(str(run.get("route_file", "")))
        if route_path.is_file():
            with route_path.open(newline="", encoding="utf-8") as route_handle:
                for route_row in csv.DictReader(route_handle):
                    totals["route_decisions"] += 1
                    totals["selected_port_counts"][route_row["selected_port"]] += 1

    return {
        "available": True,
        "label_horizon_cycles": manifest.get("label_horizon_cycles"),
        "congestion_event": manifest.get("congestion_event"),
        "scenario_definitions": manifest.get("scenario_definitions", {}),
        "by_split_workload_load": {
            f"{split}/{workload}/{load}": {
                **{
                    key: value for key, value in totals.items()
                    if key not in (
                        "seeds", "selected_port_counts", "occupancy_sum",
                        "occupancy_samples",
                    )
                },
                "seeds": sorted(set(totals["seeds"])),
                "throughput_flits_per_cycle": (
                    totals["delivered_flits"] /
                    (totals["runs"] * int(manifest["trace_cycles"]))
                ),
                "average_link_occupancy": (
                    totals["occupancy_sum"] / totals["occupancy_samples"]
                    if totals["occupancy_samples"] else 0.0
                ),
                "maximum_sampled_occupancy": totals["maximum_sampled_occupancy"],
                "maximum_blocked_streak": totals["blocked_streak_maximum"],
                "tfpcr_positive_samples": totals["tfpcr_positive_samples"],
                "congestion_score_distribution": dict(
                    sorted(totals["congestion_score_distribution"].items(),
                           key=lambda item: int(item[0]))
                ),
                "snn_risk_class_distribution": dict(
                    sorted(totals["snn_risk_class_distribution"].items(),
                           key=lambda item: int(item[0]))
                ),
                "selected_port_counts": dict(totals["selected_port_counts"]),
            }
            for (split, workload, load), totals in sorted(groups.items())
        },
    }


def summarize_regressions(directory: Path | None) -> dict[str, Any]:
    if directory is None:
        return {"available": False}

    names = (
        "mesh-xy", "mesh-west-first", "mesh-west-first-baseline",
        "mesh-west-first-snn", "mesh-west-first-equation",
        "mesh-west-first-adaptive",
    )
    result: dict[str, Any] = {"available": True, "configurations": {}}
    for name in names:
        log_path = directory / name / f"{name}.log"
        if not log_path.is_file():
            result["configurations"][name] = {"status": "not_run"}
            continue
        raw_log = log_path.read_bytes()
        if raw_log.startswith((b"\xff\xfe", b"\xfe\xff")):
            text = raw_log.decode("utf-16")
        else:
            text = raw_log.decode("utf-8-sig", errors="replace")
        performance_match = PERFORMANCE_PATTERN.search(text)
        integrity_match = INTEGRITY_PATTERN.search(text)
        adaptive_match = ADAPTIVE_PATTERN.search(text)
        passed = "ALL MESH TESTS PASSED" in text and integrity_match is not None
        configuration: dict[str, Any] = {
            "status": "passed" if passed else "failed",
            "integrity": None,
            "performance": None,
            "adaptive_policy": None,
        }
        if performance_match:
            configuration["performance"] = {
                key: (float(value) if "." in value else int(value))
                for key, value in performance_match.groupdict().items()
            }
        if integrity_match:
            fields_order = (
                "injected", "delivered", "missing", "duplicates",
                "corrupted", "unexpected", "final",
            )
            configuration["integrity"] = {
                key: (value if key == "final" else int(value))
                for key, value in zip(fields_order, integrity_match.groups())
            }
        if adaptive_match:
            fields_order = (
                "offline_validation_percent", "offline_correct_samples",
                "offline_total_samples", "threshold_percent", "minimum_samples",
                "online_window", "initial_snn_selections",
                "initial_equation_selections", "snn_selected_samples",
                "equation_selected_samples", "switches_to_snn",
                "switches_to_equation",
            )
            configuration["adaptive_policy"] = {
                key: int(value)
                for key, value in zip(fields_order, adaptive_match.groups())
            }
            selection_events = [
                {
                    key: int(value)
                    for key, value in zip(
                        (
                            "cycle", "node", "output", "model",
                            "kind", "reason", "online_accuracy_percent",
                            "online_samples",
                        ),
                        match.groups(),
                    )
                }
                for match in MODEL_SELECTION_PATTERN.finditer(text)
            ]
            configuration["adaptive_policy"]["selection_events"] = selection_events
            configuration["adaptive_policy"]["reason_counts"] = dict(
                Counter(str(event["reason"]) for event in selection_events)
            )
        result["configurations"][name] = configuration
    return result


def write_readable_summary(report: dict[str, Any], path: Path) -> None:
    lines = [
        "# NoC congestion predictor experiment summary",
        "",
        f"Dataset SHA-256: `{report['dataset_sha256']}`",
        f"Prediction horizon: {report.get('label_horizon_cycles', 'unknown')} cycles",
        "",
        "## Predictor results",
    ]
    for split_name in ("validation", "test"):
        split_report = report.get(split_name)
        if not split_report:
            continue
        lines.extend(("", f"### {split_name.title()}"))
        for model_name in ("snn", "equation"):
            metrics = split_report[model_name]
            if model_name == "equation":
                metrics = metrics["ground_truth"]
            lines.append(
                f"- **{model_name}**: n={metrics['samples']}, "
                f"accuracy={metrics['accuracy']:.4f}, precision={metrics['precision']:.4f}, "
                f"recall={metrics['recall']:.4f}, F1={metrics['f1']:.4f}, "
                f"FPR={metrics['false_positive_rate']:.4f}, "
                f"FNR={metrics['false_negative_rate']:.4f}, "
                f"confusion={metrics['confusion_matrix']}"
            )
        lines.append(
            "- SNN per-seed accuracy: " +
            ", ".join(
                f"{seed}={metrics['snn']['accuracy']:.4f}"
                for seed, metrics in split_report["per_seed"].items()
            )
        )

    traffic = report.get("traffic", {})
    if traffic.get("available", False):
        lines.extend(("", "## Traffic, routing, and integrity"))
        for scenario, metrics in traffic["by_split_workload_load"].items():
            lines.append(
                f"- `{scenario}`: runs={metrics['runs']}, seeds={metrics['seeds']}, "
                f"offered={metrics['offered_flits']}, accepted={metrics['accepted_flits']}, "
                f"delivered={metrics['delivered_flits']}, missing={metrics['missing_flits']}, "
                f"duplicates={metrics['duplicate_flits']}, corrupted={metrics['corrupted_flits']}, "
                f"route decisions={metrics['route_decisions']}, "
                f"mean/max link occupancy={metrics['average_link_occupancy']:.3f}/"
                f"{metrics['maximum_link_occupancy']}, "
                f"TF-PCR positive samples={metrics['tfpcr_positive_samples']}"
            )

    regressions = report.get("regressions", {})
    if regressions.get("available", False):
        lines.extend(("", "## End-to-end routing regressions"))
        for name, configuration in regressions["configurations"].items():
            lines.append(f"- `{name}`: {configuration['status']}")
            performance = configuration.get("performance")
            if performance:
                lines.append(
                    f"  - latency mean/max={performance['average_latency']}/"
                    f"{performance['maximum_latency']} cycles; "
                    f"throughput={performance['throughput']} packets/cycle; "
                    f"delivered={performance['delivered']}"
                )
            policy = configuration.get("adaptive_policy")
            if policy:
                lines.append(
                    f"  - initial selections SNN/math="
                    f"{policy['initial_snn_selections']}/"
                    f"{policy['initial_equation_selections']}; model cycles SNN/math="
                    f"{policy['snn_selected_samples']}/"
                    f"{policy['equation_selected_samples']}; switches SNN/math="
                    f"{policy['switches_to_snn']}/{policy['switches_to_equation']}"
                )
                lines.append(
                    f"  - selection-event reason counts: {policy['reason_counts']}"
                )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", type=Path, default=ROOT / "validation/snn_experiment/dataset.csv")
    parser.add_argument("--snn-model", type=Path, default=ROOT / "models/snn_trained.json")
    parser.add_argument("--equation", type=Path, default=ROOT / "models/distilled_equation.json")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--regression-dir", type=Path)
    args = parser.parse_args()

    splits = load_dataset(args.dataset)
    snn_model = json.loads(args.snn_model.read_text(encoding="utf-8"))
    equation = json.loads(args.equation.read_text(encoding="utf-8"))
    report: dict[str, Any] = {
        "dataset": str(args.dataset.resolve()),
        "dataset_sha256": hashlib.sha256(args.dataset.read_bytes()).hexdigest(),
        "seeds_by_split": {
            name: sorted(int(seed) for seed in set(data.seeds.tolist()))
            for name, data in splits.items()
        },
        "models": {
            "snn": str(args.snn_model.resolve()),
            "equation": str(args.equation.resolve()),
        },
        "label_horizon_cycles": 8,
        "traffic": summarize_traffic_manifest(args.dataset),
        "regressions": summarize_regressions(args.regression_dir),
    }

    for split_name in ("validation", "test"):
        if split_name not in splits:
            continue
        data = splits[split_name]
        snn_predictions, _ = infer(data, snn_model)
        report[split_name] = {
            "snn": evaluate_snn(data, snn_model),
            "equation": evaluate_equation(data, equation),
            "equation_snn_agreement": evaluate_equation_agreement(
                data, equation, snn_predictions
            ),
            "per_seed": {},
        }
        for seed in sorted(set(data.seeds.tolist())):
            seed_data = subset_seed(data, int(seed))
            seed_predictions, _ = infer(seed_data, snn_model)
            report[split_name]["per_seed"][str(seed)] = {
                "snn": evaluate_snn(seed_data, snn_model),
                "equation": evaluate_equation(seed_data, equation),
                "equation_snn_agreement": evaluate_equation_agreement(
                    seed_data, equation, seed_predictions
                ),
            }
        for model_name in ("snn", "equation"):
            seed_metrics = [
                (
                    metrics[model_name]["ground_truth"]
                    if model_name == "equation"
                    else metrics[model_name]
                )
                for metrics in report[split_name]["per_seed"].values()
            ]
            report[split_name].setdefault("per_seed_variability", {})[model_name] = {
                metric: {
                    "mean": float(np.mean([item[metric] for item in seed_metrics])),
                    "population_standard_deviation": float(
                        np.std([item[metric] for item in seed_metrics])
                    ),
                    "minimum": min(item[metric] for item in seed_metrics),
                    "maximum": max(item[metric] for item in seed_metrics),
                }
                for metric in ("accuracy", "precision", "recall", "f1")
            }

    if "validation" in splits:
        report["validation_threshold_sweep"] = validation_threshold_sweep(
            splits["validation"], snn_model, equation
        )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    summary_path = args.output.with_suffix(".md")
    write_readable_summary(report, summary_path)
    print(f"Evaluation report: {args.output.resolve()}")
    print(f"Readable summary: {summary_path.resolve()}")


if __name__ == "__main__":
    main()
