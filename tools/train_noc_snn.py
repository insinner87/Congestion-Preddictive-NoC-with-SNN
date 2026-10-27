#!/usr/bin/env python3
"""Train and evaluate the quantized LIF used by the mesh RTL.

Training uses reproducible simulated annealing/coordinate mutations over the
small integer parameter space. Every candidate is evaluated by the exact
integer RTL recurrence, avoiding a floating-point-to-hardware mismatch.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import random
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
FEATURE_NAMES = [
    "blocked_streak_ge_2", "blocked_streak_ge_5", "request_cycles_ge_16",
    "low_service_during_demand", "downstream_occupancy_ge_depth_minus_1",
    "recent_max_occupancy_ge_depth", "occupancy_rising_or_requester_buffer_pressure",
]


@dataclass
class SplitData:
    features: np.ndarray
    valid: np.ndarray
    targets: np.ndarray
    target_valid: np.ndarray
    events: np.ndarray
    seeds: np.ndarray
    loads: np.ndarray
    workloads: np.ndarray
    ports: np.ndarray


def load_dataset(path: Path) -> dict[str, SplitData]:
    # Keep each physical candidate output as a recurrent sequence. Metadata is
    # identical within each (run,node,port) key and the seeds stay disjoint.
    groups: dict[tuple[str, str, int, int], list[dict[str, str]]] = defaultdict(list)
    with path.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            key = (row["split"], row["run_id"], int(row["node"]), int(row["port"]))
            groups[key].append(row)

    split_groups: dict[str, list[tuple[tuple[str, str, int, int], list[dict[str, str]]]]] = defaultdict(list)
    max_length = 0
    for key, rows in groups.items():
        rows.sort(key=lambda row: int(row["cycle"]))
        split_groups[key[0]].append((key, rows))
        max_length = max(max_length, len(rows))

    result: dict[str, SplitData] = {}
    for split, items in split_groups.items():
        count = len(items)
        features = np.zeros((count, max_length, 7), dtype=np.uint8)
        valid = np.zeros((count, max_length), dtype=np.uint8)
        targets = np.zeros((count, max_length), dtype=np.uint8)
        target_valid = np.zeros((count, max_length), dtype=np.uint8)
        events = np.zeros((count, max_length), dtype=np.uint8)
        seeds = np.zeros(count, dtype=np.int32)
        loads = np.zeros(count, dtype=np.int16)
        workloads = np.empty(count, dtype=object)
        ports = np.zeros(count, dtype=np.int8)
        for sequence_index, (key, rows) in enumerate(items):
            for sample_index, row in enumerate(rows):
                feature_mask = int(row["features"])
                features[sequence_index, sample_index, :] = [
                    (feature_mask >> bit) & 1 for bit in range(7)
                ]
                valid[sequence_index, sample_index] = int(row["feature_valid"])
                targets[sequence_index, sample_index] = int(row["target_congestion_within_h8"])
                target_valid[sequence_index, sample_index] = int(row["target_valid"])
                events[sequence_index, sample_index] = int(row["future_event"])
            seeds[sequence_index] = int(rows[0]["seed"])
            loads[sequence_index] = int(rows[0]["load_percent"])
            workloads[sequence_index] = rows[0]["workload"]
            ports[sequence_index] = key[3]
        result[split] = SplitData(
            features=features, valid=valid, targets=targets,
            target_valid=target_valid, events=events, seeds=seeds,
            loads=loads, workloads=workloads, ports=ports,
        )
    return result


def lif_leak(potential: np.ndarray) -> np.ndarray:
    amount = potential >> 2
    amount = np.where((potential > 0) & (amount == 0), 1, amount)
    return potential - amount


def infer(data: SplitData, model: dict[str, Any]) -> tuple[np.ndarray, np.ndarray]:
    weights = np.asarray(model["hidden_weights"], dtype=np.int16)
    output_weights = np.asarray(model["output_weights"], dtype=np.int16)
    count, time_steps, _ = data.features.shape
    hidden = np.zeros((count, 4), dtype=np.int16)
    output = np.zeros(count, dtype=np.int16)
    predictions = np.zeros((count, time_steps), dtype=np.uint8)
    risk_scores = np.zeros((count, time_steps), dtype=np.uint8)
    hidden_threshold = int(model["hidden_threshold"])
    output_threshold = int(model["output_threshold"])
    potential_max = int(model.get("potential_max", 63))

    for time_index in range(time_steps):
        is_valid = data.valid[:, time_index].astype(bool)
        invalid = ~is_valid
        if np.any(invalid):
            hidden[invalid, :] = 0
            output[invalid] = 0

        x = data.features[:, time_index, :].astype(np.int16)
        integrated = np.minimum(potential_max, lif_leak(hidden) + x @ weights.T)
        hidden_spikes = integrated >= hidden_threshold
        next_hidden = np.where(hidden_spikes, integrated - hidden_threshold, integrated)
        output_integrated = np.minimum(
            potential_max,
            lif_leak(output) + hidden_spikes.astype(np.int16) @ output_weights,
        )
        risk_scores[:, time_index] = np.select(
            [output_integrated >= 6, output_integrated >= 4, output_integrated >= 2],
            [3, 2, 1], default=0,
        )
        predictions[:, time_index] = (output_integrated >= 4).astype(np.uint8)
        output_next = np.where(
            output_integrated >= output_threshold,
            output_integrated - output_threshold,
            output_integrated,
        )
        hidden_next = np.where(is_valid[:, None], next_hidden, 0)
        output_next = np.where(is_valid, output_next, 0)
        hidden = hidden_next.astype(np.int16)
        output = output_next.astype(np.int16)
    return predictions, risk_scores


def safe_ratio(numerator: int, denominator: int) -> float:
    return float(numerator / denominator) if denominator else 0.0


def binary_metrics(y: np.ndarray, pred: np.ndarray, score: np.ndarray | None = None) -> dict[str, Any]:
    y = y.astype(bool)
    pred = pred.astype(bool)
    tp = int(np.count_nonzero(y & pred))
    tn = int(np.count_nonzero(~y & ~pred))
    fp = int(np.count_nonzero(~y & pred))
    fn = int(np.count_nonzero(y & ~pred))
    precision = safe_ratio(tp, tp + fp)
    recall = safe_ratio(tp, tp + fn)
    fpr = safe_ratio(fp, fp + tn)
    fnr = safe_ratio(fn, fn + tp)
    f1 = safe_ratio(2 * precision * recall, precision + recall)
    metrics: dict[str, Any] = {
        "samples": int(y.size), "positive_samples": int(np.count_nonzero(y)),
        "positive_prevalence": safe_ratio(int(np.count_nonzero(y)), int(y.size)),
        "accuracy": safe_ratio(tp + tn, int(y.size)), "precision": precision,
        "recall": recall, "f1": f1, "false_positive_rate": fpr,
        "false_negative_rate": fnr, "confusion_matrix": [[tn, fp], [fn, tp]],
        "balanced_accuracy": (recall + safe_ratio(tn, tn + fp)) / 2,
    }
    if score is not None and np.unique(y).size == 2:
        metrics["roc_auc"] = rank_auc(y, score)
        metrics["pr_auc_average_precision"] = average_precision(y, score)
    else:
        metrics["roc_auc"] = None
        metrics["pr_auc_average_precision"] = None
    return metrics


def rank_auc(y: np.ndarray, scores: np.ndarray) -> float:
    order = np.argsort(scores, kind="mergesort")
    sorted_scores = scores[order]
    ranks = np.empty(scores.size, dtype=np.float64)
    left = 0
    while left < scores.size:
        right = left + 1
        while right < scores.size and sorted_scores[right] == sorted_scores[left]:
            right += 1
        ranks[order[left:right]] = (left + 1 + right) / 2
        left = right
    positive_count = int(np.count_nonzero(y))
    negative_count = int(y.size - positive_count)
    return float((ranks[y].sum() - positive_count * (positive_count + 1) / 2) /
                 (positive_count * negative_count))


def average_precision(y: np.ndarray, scores: np.ndarray) -> float:
    order = np.argsort(-scores, kind="mergesort")
    sorted_y = y[order].astype(np.float64)
    cumulative_tp = np.cumsum(sorted_y)
    precision_at_k = cumulative_tp / np.arange(1, y.size + 1)
    return float((precision_at_k * sorted_y).sum() / sorted_y.sum())


def evaluate(data: SplitData, model: dict[str, Any]) -> dict[str, Any]:
    predictions, risk_scores = infer(data, model)
    mask = data.valid.astype(bool) & data.target_valid.astype(bool)
    y = data.targets[mask].astype(bool)
    pred = predictions[mask].astype(bool)
    score = risk_scores[mask].astype(np.float64)
    metrics: dict[str, Any] = binary_metrics(y, pred, score)

    # Evaluate subgroups without changing the frozen decision threshold.
    group_results: dict[str, Any] = {}
    for field, values in (("load_percent", data.loads), ("workload", data.workloads),
                          ("candidate_port", data.ports)):
        group_results[field] = {}
        for value in sorted(set(values.tolist()), key=str):
            sequence_mask = values == value
            cell_mask = mask[sequence_mask]
            group_y = data.targets[sequence_mask][cell_mask].astype(bool)
            group_pred = predictions[sequence_mask][cell_mask].astype(bool)
            group_score = risk_scores[sequence_mask][cell_mask].astype(np.float64)
            group_results[field][str(value)] = binary_metrics(group_y, group_pred, group_score)
    metrics["subgroups"] = group_results

    # Episode-level lead time and duration strata avoid counting a sustained
    # blocked run once per cycle as if it were many independent events.
    leads: list[int] = []
    episode_buckets: dict[str, dict[str, Any]] = {
        "1-4": {"episodes": 0, "detected": 0, "leads": []},
        "5-8": {"episodes": 0, "detected": 0, "leads": []},
        "9+": {"episodes": 0, "detected": 0, "leads": []},
    }
    for sequence_index in range(data.features.shape[0]):
        event_row = data.events[sequence_index].astype(bool)
        event_starts: list[tuple[int, int]] = []
        cursor = 0
        while cursor < event_row.size:
            if not event_row[cursor]:
                cursor += 1
                continue
            start = cursor
            while cursor < event_row.size and event_row[cursor]:
                cursor += 1
            if not data.valid[sequence_index, start] or cursor > event_row.size - 8:
                continue
            event_starts.append((start, cursor - start))
        for event_time, duration in event_starts:
            bucket_name = "1-4" if duration <= 4 else "5-8" if duration <= 8 else "9+"
            bucket = episode_buckets[bucket_name]
            bucket["episodes"] += 1
            start = max(0, event_time - 8)
            prior = np.flatnonzero(predictions[sequence_index, start:event_time])
            if prior.size:
                lead = event_time - (start + int(prior[0]))
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
            "episodes": values["episodes"],
            "detected": values["detected"],
            "recall": safe_ratio(values["detected"], values["episodes"]),
            "mean_lead_time_cycles": float(np.mean(values["leads"])) if values["leads"] else None,
        }
        for name, values in episode_buckets.items()
    }
    return metrics


def quick_metrics(data: SplitData, model: dict[str, Any]) -> dict[str, Any]:
    predictions, risk_scores = infer(data, model)
    mask = data.valid.astype(bool) & data.target_valid.astype(bool)
    return binary_metrics(
        data.targets[mask].astype(bool), predictions[mask].astype(bool),
        risk_scores[mask].astype(np.float64),
    )


def training_objective(metrics: dict[str, Any]) -> float:
    # Favor both discrimination and useful event detection, with explicit
    # penalties for missing congestion or flooding the router with alarms.
    score = (0.25 * metrics["accuracy"] + 0.45 * metrics["recall"] +
             0.30 * metrics["precision"])
    if metrics["recall"] < 0.70:
        score -= 0.75 * (0.70 - metrics["recall"])
    if metrics["false_positive_rate"] > 0.15:
        score -= 0.75 * (metrics["false_positive_rate"] - 0.15)
    return score


def random_model(rng: random.Random) -> dict[str, Any]:
    return {
        "hidden_weights": [[rng.randrange(4) for _ in range(7)] for _ in range(4)],
        "output_weights": [rng.randrange(4) for _ in range(4)],
        "hidden_threshold": rng.randint(2, 18),
        "output_threshold": rng.randint(2, 18),
        "potential_max": 63,
    }


def mutate(model: dict[str, Any], rng: random.Random) -> dict[str, Any]:
    candidate = json.loads(json.dumps(model))
    changes = 1 if rng.random() < 0.78 else 2
    for _ in range(changes):
        kind = rng.randrange(3)
        if kind == 0:
            neuron, feature = rng.randrange(4), rng.randrange(7)
            old = candidate["hidden_weights"][neuron][feature]
            candidate["hidden_weights"][neuron][feature] = rng.choice(
                [value for value in range(4) if value != old]
            )
        elif kind == 1:
            neuron = rng.randrange(4)
            old = candidate["output_weights"][neuron]
            candidate["output_weights"][neuron] = rng.choice(
                [value for value in range(4) if value != old]
            )
        else:
            threshold_key = rng.choice(["hidden_threshold", "output_threshold"])
            candidate[threshold_key] = rng.randint(1, 24)
    return candidate


def parameter_key(model: dict[str, Any]) -> str:
    return json.dumps(model, sort_keys=True, separators=(",", ":"))


def train(train_data: SplitData, validation_data: SplitData, *, seed: int,
          max_experiments: int, restarts: int) -> tuple[dict[str, Any], dict[str, Any]]:
    rng = random.Random(seed)
    archive: dict[str, tuple[float, dict[str, Any], dict[str, Any]]] = {}
    trials = max(1, max_experiments)
    per_restart = math.ceil(trials / max(1, restarts))
    for restart in range(restarts):
        current = random_model(rng)
        current_metrics = quick_metrics(train_data, current)
        current_score = training_objective(current_metrics)
        for step in range(per_restart):
            if restart * per_restart + step >= trials:
                break
            candidate = mutate(current, rng)
            candidate_metrics = quick_metrics(train_data, candidate)
            candidate_score = training_objective(candidate_metrics)
            key = parameter_key(candidate)
            previous = archive.get(key)
            if previous is None or candidate_score > previous[0]:
                archive[key] = (candidate_score, candidate, candidate_metrics)

            progress = step / max(1, per_restart - 1)
            temperature = 0.025 * (1.0 - progress) + 0.002
            if candidate_score >= current_score or rng.random() < math.exp(
                max(-50.0, (candidate_score - current_score) / temperature)
            ):
                current, current_metrics, current_score = candidate, candidate_metrics, candidate_score

            if len(archive) > 100:
                keep = sorted(archive.values(), key=lambda item: item[0], reverse=True)[:75]
                archive = {parameter_key(item[1]): item for item in keep}

    candidates = sorted(archive.values(), key=lambda item: item[0], reverse=True)[:50]
    selected: tuple[float, float, dict[str, Any], dict[str, Any], dict[str, Any]] | None = None
    for train_score, model, train_metrics in candidates:
        validation_metrics = evaluate(validation_data, model)
        validation_score = training_objective(validation_metrics)
        # Validation selection prefers meeting the primary accuracy target,
        # then the congestion recall and false-alarm requirements.
        gate_penalty = 0.0
        if validation_metrics["accuracy"] < 0.90:
            gate_penalty += 2.0 * (0.90 - validation_metrics["accuracy"])
        if validation_metrics["recall"] < 0.70:
            gate_penalty += 1.0 * (0.70 - validation_metrics["recall"])
        if validation_metrics["false_positive_rate"] > 0.15:
            gate_penalty += validation_metrics["false_positive_rate"] - 0.15
        selection = validation_score - gate_penalty
        if selected is None or selection > selected[0]:
            selected = (selection, train_score, model, train_metrics, validation_metrics)
    assert selected is not None
    info = {
        "method": "reproducible simulated annealing over quantized integer LIF parameters",
        "objective": "0.25*accuracy + 0.45*recall + 0.30*precision, with penalties for recall < 0.70 and FPR > 0.15",
        "training_seed": seed, "experiments": trials, "restarts": restarts,
        "candidate_models_selected_on_validation": len(candidates),
        "train_objective": selected[1], "train_metrics": selected[3],
        "validation_metrics": selected[4],
    }
    return selected[2], info


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", type=Path, default=ROOT / "validation/snn_experiment/dataset.csv")
    parser.add_argument("--model", type=Path, default=ROOT / "models/snn_trained.json")
    parser.add_argument("--results", type=Path, default=ROOT / "validation/snn_experiment/accuracy_results.json")
    parser.add_argument("--seed", type=int, default=72631)
    parser.add_argument("--max-experiments", type=int, default=1000)
    parser.add_argument("--restarts", type=int, default=10)
    parser.add_argument("--max-retries", type=int, default=2,
                        help="additional validation-driven retraining rounds (bounded)")
    args = parser.parse_args()
    splits = load_dataset(args.dataset)
    if not {"train", "validation", "test"}.issubset(splits):
        parser.error("dataset must contain train, validation, and test splits")
    if set(splits["train"].seeds) & set(splits["validation"].seeds) or \
       set(splits["train"].seeds) & set(splits["test"].seeds) or \
       set(splits["validation"].seeds) & set(splits["test"].seeds):
        parser.error("traffic seeds overlap across splits")
    attempts: list[tuple[float, dict[str, Any], dict[str, Any]]] = []
    selected_attempt: tuple[float, dict[str, Any], dict[str, Any]] | None = None
    for retry in range(args.max_retries + 1):
        budget = args.max_experiments * (2 ** retry)
        model_candidate, training_candidate = train(
            splits["train"], splits["validation"], seed=args.seed + retry * 1009,
            max_experiments=budget, restarts=args.restarts * (retry + 1),
        )
        validation_candidate = training_candidate["validation_metrics"]
        gate_ok = (validation_candidate["accuracy"] >= 0.90 and
                   validation_candidate["recall"] >= 0.70 and
                   validation_candidate["false_positive_rate"] <= 0.15)
        validation_score = training_objective(validation_candidate)
        gate_penalty = 0.0 if gate_ok else 1.0
        attempt = (validation_score + gate_penalty, model_candidate, training_candidate)
        attempts.append(attempt)
        if selected_attempt is None or attempt[0] > selected_attempt[0]:
            selected_attempt = attempt
        if gate_ok:
            selected_attempt = attempt
            break
        print(f"Validation gate missed on retraining round {retry + 1}; "
              f"retrying with {budget * 2} bounded candidate evaluations.")
    assert selected_attempt is not None
    model, training = selected_attempt[1], selected_attempt[2]
    training["retraining_rounds"] = len(attempts)
    training["retraining_attempts"] = [
        {
            "round": index + 1,
            "seed": args.seed + index * 1009,
            "experiments": attempt[2]["experiments"],
            "validation_metrics": attempt[2]["validation_metrics"],
        }
        for index, attempt in enumerate(attempts)
    ]
    # The untouched test split is evaluated once, after validation selection.
    test_metrics = evaluate(splits["test"], model)
    results: dict[str, Any] = {
        "model_version": 1, "horizon_cycles": 8,
        "label_event": "blocked_streak >= 4 OR (downstream link FIFO occupancy >= 2 and a request is present)",
        "feature_order_lsb_first": FEATURE_NAMES,
        "decision": "congestion risk when RTL output_integrated >= 4 (risk_class >= 2)",
        "acceptance": {"accuracy_minimum": 0.90, "recall_minimum": 0.70,
                       "false_positive_rate_maximum": 0.15},
        "training": training, "held_out_test_metrics": test_metrics,
        "test_gate_passed": bool(test_metrics["accuracy"] >= 0.90 and
                                  test_metrics["recall"] >= 0.70 and
                                  test_metrics["false_positive_rate"] <= 0.15),
        "dataset": str(args.dataset.resolve()),
    }
    args.model.parent.mkdir(parents=True, exist_ok=True)
    args.results.parent.mkdir(parents=True, exist_ok=True)
    args.model.write_text(json.dumps(model, indent=2), encoding="utf-8")
    args.results.write_text(json.dumps(results, indent=2), encoding="utf-8")
    print("Selected integer LIF model:")
    print(json.dumps(model, indent=2))
    print("Validation metrics:")
    print(json.dumps(training["validation_metrics"], indent=2))
    print("Untouched held-out test metrics:")
    print(json.dumps(test_metrics, indent=2))
    print(f"ACCEPTANCE GATE: {'PASS' if results['test_gate_passed'] else 'FAIL'}")


if __name__ == "__main__":
    main()
