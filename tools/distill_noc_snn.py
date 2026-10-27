#!/usr/bin/env python3
"""Fit and evaluate a fixed-point linear equation against the trained SNN."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import numpy as np
from sklearn.linear_model import LogisticRegression

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from train_noc_snn import FEATURE_NAMES, binary_metrics, infer, load_dataset  # noqa: E402


def flat_split(split: Any, snn_model: dict[str, Any]) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    snn_predictions, _ = infer(split, snn_model)
    valid = split.valid.astype(bool) & split.target_valid.astype(bool)
    features = split.features[valid].astype(np.int8)
    targets = split.targets[valid].astype(np.uint8)
    snn = snn_predictions[valid].astype(np.uint8)
    return features, targets, snn


def candidate_metrics(features: np.ndarray, targets: np.ndarray, snn: np.ndarray,
                      coefficients: np.ndarray, bias: int) -> dict[str, Any]:
    scores = features.astype(np.int32) @ coefficients.astype(np.int32) + int(bias)
    predictions = (scores >= 0).astype(np.uint8)
    return {
        "agreement_with_snn": float(np.mean(predictions == snn)),
        "ground_truth": binary_metrics(targets.astype(bool), predictions.astype(bool), scores),
        "feature_samples": int(features.shape[0]),
    }


def evaluate_equation(data: Any, model: dict[str, Any]) -> dict[str, Any]:
    coefficients = np.asarray(model["coefficient_signed_8"], dtype=np.int32)
    scores = data.features.astype(np.int32) @ coefficients + int(model["bias_signed_12"])
    predictions = (scores >= int(model["decision_threshold"])) & data.valid.astype(bool)
    mask = data.valid.astype(bool) & data.target_valid.astype(bool)
    metrics: dict[str, Any] = binary_metrics(
        data.targets[mask].astype(bool), predictions[mask], scores[mask].astype(np.float64),
    )
    subgroups: dict[str, Any] = {}
    for field, values in (("load_percent", data.loads), ("workload", data.workloads),
                          ("candidate_port", data.ports)):
        subgroups[field] = {}
        for value in sorted(set(values.tolist()), key=str):
            sequence_mask = values == value
            group_mask = mask[sequence_mask]
            subgroups[field][str(value)] = binary_metrics(
                data.targets[sequence_mask][group_mask].astype(bool),
                predictions[sequence_mask][group_mask],
                scores[sequence_mask][group_mask].astype(np.float64),
            )
    metrics["subgroups"] = subgroups

    leads: list[int] = []
    duration_groups: dict[str, dict[str, Any]] = {
        "1-4": {"episodes": 0, "detected": 0, "leads": []},
        "5-8": {"episodes": 0, "detected": 0, "leads": []},
        "9+": {"episodes": 0, "detected": 0, "leads": []},
    }
    for sequence_index, raw_events in enumerate(data.events):
        event_row = raw_events.astype(bool)
        index = 0
        while index < event_row.size:
            if not event_row[index]:
                index += 1
                continue
            start = index
            while index < event_row.size and event_row[index]:
                index += 1
            if not data.valid[sequence_index, start] or index > event_row.size - 8:
                continue
            duration = index - start
            bucket_name = "1-4" if duration <= 4 else "5-8" if duration <= 8 else "9+"
            bucket = duration_groups[bucket_name]
            bucket["episodes"] += 1
            history_start = max(0, start - 8)
            prior = np.flatnonzero(predictions[sequence_index, history_start:start])
            if prior.size:
                lead = start - (history_start + int(prior[0]))
                leads.append(lead)
                bucket["detected"] += 1
                bucket["leads"].append(lead)
    metrics["prediction_lead_time_cycles"] = {
        "detected_events": len(leads),
        "mean": float(np.mean(leads)) if leads else None,
        "median": float(np.median(leads)) if leads else None,
    }
    metrics["congestion_episode_duration_cycles"] = {
        name: {
            "episodes": values["episodes"], "detected": values["detected"],
            "recall": values["detected"] / values["episodes"] if values["episodes"] else 0.0,
            "mean_lead_time_cycles": float(np.mean(values["leads"])) if values["leads"] else None,
        }
        for name, values in duration_groups.items()
    }
    return {
        "ground_truth": metrics,
        "feature_samples": metrics["samples"],
    }


def select_equation(train_x: np.ndarray, train_snn: np.ndarray,
                    validation_x: np.ndarray, validation_y: np.ndarray,
                    validation_snn: np.ndarray) -> tuple[dict[str, Any], dict[str, Any]]:
    best: tuple[float, dict[str, Any], dict[str, Any]] | None = None
    for regularization in (0.01, 0.1, 1.0, 10.0, 100.0):
        estimator = LogisticRegression(C=regularization, solver="liblinear", max_iter=2000,
                                        random_state=3049)
        estimator.fit(train_x, train_snn)
        raw_coefficients = estimator.coef_[0]
        raw_bias = float(estimator.intercept_[0])
        for fixed_scale in (4, 8, 16, 32, 64):
            coeffs = np.rint(raw_coefficients * fixed_scale).astype(np.int32)
            bias = int(np.rint(raw_bias * fixed_scale))
            if np.max(np.abs(coeffs), initial=0) > 127 or not -2048 <= bias <= 2047:
                continue
            metric = candidate_metrics(validation_x, validation_y, validation_snn, coeffs, bias)
            truth_metrics = metric["ground_truth"]
            gate_penalty = 0.0
            if truth_metrics["accuracy"] < 0.90:
                gate_penalty += 2.0 * (0.90 - truth_metrics["accuracy"])
            if truth_metrics["recall"] < 0.70:
                gate_penalty += 0.5 * (0.70 - truth_metrics["recall"])
            if truth_metrics["false_positive_rate"] > 0.15:
                gate_penalty += 0.5 * (truth_metrics["false_positive_rate"] - 0.15)
            score = 0.50 * metric["agreement_with_snn"] + 0.50 * truth_metrics["accuracy"] - gate_penalty
            model = {
                "feature_order_lsb_first": FEATURE_NAMES,
                "coefficient_signed_8": [int(value) for value in coeffs],
                "bias_signed_12": bias,
                "decision_threshold": 0,
                "fixed_point_scale": fixed_scale,
                "equation": "R = bias + sum(coefficient[i] * x[i]); predict congestion when R >= 0",
                "arithmetic": "signed 12-bit saturating score, binary features, no floating-point inference",
            }
            if best is None or score > best[0]:
                best = (score, model, metric)
    if best is None:
        raise RuntimeError("no fixed-point logistic candidate fit the signed RTL widths")
    return best[1], {"validation_selection_score": best[0], "validation_metrics": best[2]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", type=Path, default=ROOT / "validation/snn_experiment/dataset.csv")
    parser.add_argument("--snn-model", type=Path, default=ROOT / "models/snn_trained.json")
    parser.add_argument("--equation", type=Path, default=ROOT / "models/distilled_equation.json")
    parser.add_argument("--results", type=Path, default=ROOT / "validation/snn_experiment/distillation_results.json")
    args = parser.parse_args()
    snn_model = json.loads(args.snn_model.read_text(encoding="utf-8"))
    splits = load_dataset(args.dataset)
    train_x, _, train_snn = flat_split(splits["train"], snn_model)
    validation_x, validation_y, validation_snn = flat_split(splits["validation"], snn_model)
    equation, selection = select_equation(
        train_x, train_snn, validation_x, validation_y, validation_snn,
    )
    test_x, test_y, test_snn = flat_split(splits["test"], snn_model)
    test_metrics = evaluate_equation(splits["test"], equation)
    test_equivalence = candidate_metrics(
        test_x, test_y, test_snn,
        np.asarray(equation["coefficient_signed_8"], dtype=np.int32),
        equation["bias_signed_12"],
    )["agreement_with_snn"]
    test_metrics["agreement_with_snn"] = test_equivalence
    report = {
        "method": "logistic-regression distillation of the exact integer SNN decision, selected on validation",
        "feature_order_lsb_first": FEATURE_NAMES,
        "equation": equation,
        "validation": selection["validation_metrics"],
        "untouched_test": test_metrics,
        "acceptance": {"minimum_snn_agreement": 0.95, "minimum_ground_truth_accuracy": 0.90,
                       "minimum_congestion_recall": 0.70, "maximum_false_positive_rate": 0.15},
        "test_gate_passed": bool(
            test_metrics["agreement_with_snn"] >= 0.95 and
            test_metrics["ground_truth"]["accuracy"] >= 0.90 and
            test_metrics["ground_truth"]["recall"] >= 0.70 and
            test_metrics["ground_truth"]["false_positive_rate"] <= 0.15
        ),
    }
    args.equation.parent.mkdir(parents=True, exist_ok=True)
    args.results.parent.mkdir(parents=True, exist_ok=True)
    args.equation.write_text(json.dumps(equation, indent=2), encoding="utf-8")
    args.results.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"Equation: {equation['equation']}")
    print("Coefficients:", equation["coefficient_signed_8"], "bias:", equation["bias_signed_12"])
    print("Validation:", json.dumps(selection["validation_metrics"], indent=2))
    print("Untouched test:", json.dumps(test_metrics, indent=2))
    print("DISTILLATION GATE:", "PASS" if report["test_gate_passed"] else "FAIL")


if __name__ == "__main__":
    main()
