#!/usr/bin/env python3
"""Generate deterministic TF feature traces, tune a tiny integer LIF SNN, and evaluate it.

This is a signal-level workload model, not a full mesh simulator. Use its held-out
results to check the parameter-search path; final research numbers must come from
separate full-NoC traces with the same feature schema.
"""

from __future__ import annotations

import argparse
import csv
import json
import random
from pathlib import Path
from typing import Any


HORIZON = 8
BLOCK_RUN = 4
HIDDEN_NEURONS = 4
FEATURES = 5
DEFAULT_MODEL = {
    "hidden_weights": [
        [2, 2, 1, 1, 1],
        [0, 2, 2, 1, 2],
        [2, 1, 2, 2, 1],
        [1, 2, 1, 2, 2],
    ],
    "output_weights": [1, 2, 2, 2],
    "hidden_threshold": 8,
    "output_threshold": 6,
    "potential_max": 63,
}


def parse_seeds(value: str) -> list[int]:
    return [int(item.strip(), 0) for item in value.split(",") if item.strip()]


def workload_sample(rng: random.Random, cycle: int, cycles: int) -> tuple[int, int, str]:
    phase = min(5, (cycle * 6) // cycles)
    modes = ["low", "bursty", "ramp_up", "hotspot", "recovery", "mixed"]
    mode = modes[phase]
    local_cycle = cycle - (phase * cycles // 6)

    if mode == "low":
        requester_count = rng.choices([0, 1, 2], weights=[55, 40, 5])[0]
        ready_probability = 0.98
    elif mode == "bursty":
        in_burst = (local_cycle % 32) < 12
        requester_count = rng.randint(2, 5) if in_burst else rng.randint(0, 1)
        ready_probability = 0.72
    elif mode == "ramp_up":
        ramp = min(5, 1 + (local_cycle * 5 // max(1, cycles // 6)))
        requester_count = max(0, min(5, ramp + rng.choice([-1, 0, 0, 1])))
        ready_probability = 0.68
    elif mode == "hotspot":
        requester_count = rng.choices([1, 2, 3, 4, 5], weights=[5, 10, 25, 35, 25])[0]
        ready_probability = 0.48
    elif mode == "recovery":
        recovery = max(0, 5 - (local_cycle * 6 // max(1, cycles // 6)))
        requester_count = max(0, min(5, recovery + rng.choice([-1, 0, 0, 1])))
        ready_probability = 0.88
    else:
        requester_count = rng.randint(0, 5)
        ready_probability = rng.uniform(0.45, 0.95)

    transfer = int(requester_count > 0 and rng.random() < ready_probability)
    return requester_count, transfer, mode


def simulate_signal_stream(seed: int, output_port: int, cycles: int) -> dict[str, Any]:
    rng = random.Random(seed * 65537 + output_port * 7919)
    requester_counts: list[int] = []
    transfers: list[int] = []
    blocked: list[int] = []
    modes: list[str] = []

    for cycle in range(cycles):
        requesters, transfer, mode = workload_sample(rng, cycle, cycles)
        requester_counts.append(requesters)
        transfers.append(transfer)
        blocked.append(int(requesters > 0 and not transfer))
        modes.append(mode)

    features_by_cycle: list[list[int]] = []
    valid_by_cycle: list[bool] = []
    metadata_by_cycle: list[dict[str, int | str]] = []
    history: list[int] = []
    blocked_streak = 0
    request_accumulator = 0
    active_accumulator = 0
    service_accumulator = 0
    request_snapshot = 0
    active_snapshot = 0
    service_snapshot = 0
    window_valid = False

    for cycle in range(cycles):
        requesters = requester_counts[cycle]
        transfer = transfers[cycle]
        is_blocked = blocked[cycle]
        blocked_streak = min(15, blocked_streak + 1) if is_blocked else 0

        request_accumulator = min(40, request_accumulator + requesters)
        active_accumulator = min(8, active_accumulator + int(requesters > 0))
        service_accumulator = min(8, service_accumulator + transfer)

        if cycle % 8 == 7:
            request_snapshot = request_accumulator
            active_snapshot = active_accumulator
            service_snapshot = service_accumulator
            request_accumulator = 0
            active_accumulator = 0
            service_accumulator = 0
            window_valid = True

        history.append(requesters)
        if len(history) > 4:
            history.pop(0)
        trend = 0
        if len(history) == 4:
            if requesters > history[0]:
                trend = 1
            elif requesters < history[0]:
                trend = 2

        feature_valid = window_valid and len(history) == 4
        bits = [
            int(requesters >= 2),
            int(blocked_streak >= 2),
            int(trend == 1 and requesters > 0),
            int(request_snapshot >= 16),
            int(max(request_snapshot - service_snapshot, 0) >= 4),
        ]
        features_by_cycle.append(bits if feature_valid else [0] * FEATURES)
        valid_by_cycle.append(feature_valid)
        metadata_by_cycle.append(
            {
                "requester_count": requesters,
                "blocked_streak": blocked_streak,
                "pressure_trend": trend,
                "requester_cycles_8": request_snapshot,
                "demand_active_cycles_8": active_snapshot,
                "service_cycles_8": service_snapshot,
                "service_deficit_8": max(request_snapshot - service_snapshot, 0),
                "mode": modes[cycle],
            }
        )

    labels = [0] * cycles
    for cycle in range(cycles):
        future = blocked[cycle + 1 : cycle + HORIZON + 1]
        labels[cycle] = int(any(
            all(future[start : start + BLOCK_RUN])
            for start in range(max(0, len(future) - BLOCK_RUN + 1))
        ))

    return {
        "seed": seed,
        "output": output_port,
        "cycles": cycles,
        "requester_counts": requester_counts,
        "transfers": transfers,
        "blocked": blocked,
        "features": features_by_cycle,
        "valid": valid_by_cycle,
        "metadata": metadata_by_cycle,
        "labels": labels,
    }


def trace_rows(streams: list[dict[str, Any]], split: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for stream in streams:
        stream_key = f"{stream['seed']}:{stream['output']}"
        for cycle in range(stream["cycles"] - HORIZON):
            if not stream["valid"][cycle]:
                continue
            features = stream["features"][cycle]
            row = {
                "split": split,
                "seed": stream["seed"],
                "output": stream["output"],
                "stream": stream_key,
                "cycle": cycle,
                **stream["metadata"][cycle],
                "feature_0_high_pressure": features[0],
                "feature_1_persistent_block": features[1],
                "feature_2_rising_pressure": features[2],
                "feature_3_high_demand_rate": features[3],
                "feature_4_high_service_deficit": features[4],
                "target_blocked_within_h8": stream["labels"][cycle],
            }
            rows.append(row)
    return rows


def leak(potential: int) -> int:
    amount = max(1, potential >> 2) if potential else 0
    return potential - amount


def run_snn(stream: dict[str, Any], model: dict[str, Any]) -> list[int]:
    hidden_potential = [0] * HIDDEN_NEURONS
    output_potential = 0
    classes = [0] * stream["cycles"]
    for cycle in range(stream["cycles"]):
        if not stream["valid"][cycle]:
            hidden_potential = [0] * HIDDEN_NEURONS
            output_potential = 0
            continue

        features = stream["features"][cycle]
        spikes: list[int] = []
        next_hidden: list[int] = []
        for neuron in range(HIDDEN_NEURONS):
            weighted = sum(
                model["hidden_weights"][neuron][feature] * features[feature]
                for feature in range(FEATURES)
            )
            integrated = min(model["potential_max"], leak(hidden_potential[neuron]) + weighted)
            spike = int(integrated >= model["hidden_threshold"])
            spikes.append(spike)
            next_hidden.append(
                integrated - model["hidden_threshold"] if spike else integrated
            )

        output_weighted = sum(
            model["output_weights"][neuron] * spikes[neuron]
            for neuron in range(HIDDEN_NEURONS)
        )
        output_integrated = min(
            model["potential_max"], leak(output_potential) + output_weighted
        )
        classes[cycle] = (
            3 if output_integrated >= 6 else
            2 if output_integrated >= 4 else
            1 if output_integrated >= 2 else 0
        )
        output_spike = output_integrated >= model["output_threshold"]
        output_potential = (
            output_integrated - model["output_threshold"]
            if output_spike else output_integrated
        )
        hidden_potential = next_hidden
    return classes


def binary_metrics(rows: list[dict[str, Any]], predictions: dict[str, list[int]]) -> dict[str, Any]:
    tp = fp = tn = fn = 0
    for row in rows:
        prediction = predictions[row["stream"]][row["cycle"]]
        label = int(row["target_blocked_within_h8"])
        if prediction and label:
            tp += 1
        elif prediction:
            fp += 1
        elif label:
            fn += 1
        else:
            tn += 1

    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    fpr = fp / (fp + tn) if fp + tn else 0.0
    fnr = fn / (fn + tp) if fn + tp else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0

    detected_leads: list[int] = []
    event_count = detected_count = 0
    for stream_key, class_values in predictions.items():
        stream = next(stream for stream in _CURRENT_STREAMS if
                      f"{stream['seed']}:{stream['output']}" == stream_key)
        blocked = stream["blocked"]
        for onset in range(len(blocked) - BLOCK_RUN + 1):
            if not all(blocked[onset : onset + BLOCK_RUN]):
                continue
            if onset > 0 and blocked[onset - 1]:
                continue
            event_count += 1
            candidates = [
                cycle for cycle in range(max(0, onset - HORIZON), onset)
                if cycle < len(class_values) and class_values[cycle] >= 2
            ]
            if candidates:
                detected_count += 1
                detected_leads.append(onset - max(candidates))

    return {
        "samples": len(rows),
        "TP": tp,
        "FP": fp,
        "TN": tn,
        "FN": fn,
        "precision": precision,
        "recall": recall,
        "F1": f1,
        "false_positive_rate": fpr,
        "false_negative_rate": fnr,
        "events": event_count,
        "events_detected_in_advance": detected_count,
        "mean_lead_cycles": (
            sum(detected_leads) / len(detected_leads) if detected_leads else 0.0
        ),
    }


_CURRENT_STREAMS: list[dict[str, Any]] = []


def evaluate_model(
    streams: list[dict[str, Any]], rows: list[dict[str, Any]], model: dict[str, Any]
) -> dict[str, Any]:
    global _CURRENT_STREAMS
    _CURRENT_STREAMS = streams
    predictions = {
        f"{stream['seed']}:{stream['output']}": [
            int(risk_class >= 2) for risk_class in run_snn(stream, model)
        ]
        for stream in streams
    }
    return binary_metrics(rows, predictions)


def evaluate_heuristic(
    streams: list[dict[str, Any]], rows: list[dict[str, Any]], name: str
) -> dict[str, Any]:
    global _CURRENT_STREAMS
    _CURRENT_STREAMS = streams
    predictions: dict[str, list[int]] = {}
    for stream in streams:
        key = f"{stream['seed']}:{stream['output']}"
        values = [0] * stream["cycles"]
        for cycle in range(stream["cycles"]):
            meta = stream["metadata"][cycle]
            requester_count = int(meta["requester_count"])
            blocked_streak = int(meta["blocked_streak"])
            trend = int(meta["pressure_trend"])
            demand = int(meta["requester_cycles_8"])
            deficit = int(meta["service_deficit_8"])
            if name == "current_requester_threshold":
                values[cycle] = int(requester_count >= 3)
            elif name == "time_history_only":
                values[cycle] = int(blocked_streak >= 2 or (trend == 1 and requester_count > 0))
            elif name == "event_rate_only":
                values[cycle] = int(demand >= 16 or deficit >= 4)
            else:
                pressure = int(requester_count >= 2)
                persistence = int(blocked_streak >= 2)
                rising = int(trend == 1 and requester_count > 0)
                demand_rate = int(demand >= 16)
                deficit_high = int(deficit >= 4)
                values[cycle] = int(
                    2 * pressure + 2 * persistence + 2 * rising +
                    demand_rate + deficit_high >= 4
                )
        predictions[key] = values
    return binary_metrics(rows, predictions)


def random_model(rng: random.Random) -> dict[str, Any]:
    return {
        "hidden_weights": [
            [rng.randrange(4) for _ in range(FEATURES)]
            for _ in range(HIDDEN_NEURONS)
        ],
        "output_weights": [rng.randrange(4) for _ in range(HIDDEN_NEURONS)],
        "hidden_threshold": rng.randrange(4, 13),
        "output_threshold": rng.randrange(4, 11),
        "potential_max": 63,
    }


def pack_weights(weights: list[int]) -> int:
    return sum(weight << (2 * index) for index, weight in enumerate(weights))


def emit_rtl_package(path: Path, model: dict[str, Any], version: int) -> None:
    lines = [
        "// Generated by tools/predictor_eval.py; do not edit weights by hand.",
        f"// Model version {version}; integer parameter search on the training split.",
        "package snn_model_parameters_pkg;",
        f"    localparam int MODEL_VERSION = {version};",
    ]
    for neuron, weights in enumerate(model["hidden_weights"]):
        lines.append(
            f"    localparam logic [9:0] W_HIDDEN_{neuron} = 10'h{pack_weights(weights):03x};"
        )
    lines.extend([
        f"    localparam logic [7:0] W_OUTPUT = 8'h{pack_weights(model['output_weights']):02x};",
        f"    localparam logic [7:0] HIDDEN_THRESHOLD = 8'd{model['hidden_threshold']};",
        f"    localparam logic [7:0] OUTPUT_THRESHOLD = 8'd{model['output_threshold']};",
        f"    localparam logic [7:0] POTENTIAL_MAX = 8'd{model['potential_max']};",
        "endpackage",
        "",
    ])
    path.write_text("\n".join(lines), encoding="utf-8")


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        raise ValueError(f"no samples generated for {path}")
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=Path("validation/run/predictor-eval"))
    parser.add_argument("--train-seeds", default="101,202,303,404,505,606,707,808")
    parser.add_argument("--test-seeds", default="1001,1002,1003,1004")
    parser.add_argument("--cycles", type=int, default=512)
    parser.add_argument("--outputs", type=int, default=5)
    parser.add_argument("--trials", type=int, default=160)
    parser.add_argument("--search-seed", type=int, default=0x534E4E)
    parser.add_argument("--write-rtl", action="store_true")
    parser.add_argument(
        "--rtl-package", type=Path,
        default=Path("rtl/congestion/snn_model_parameters_pkg.sv"),
    )
    args = parser.parse_args()
    if args.cycles <= 16 or args.outputs < 1 or args.trials < 1:
        parser.error("cycles must exceed 16; outputs and trials must be positive")

    train_seeds = parse_seeds(args.train_seeds)
    test_seeds = parse_seeds(args.test_seeds)
    if set(train_seeds) & set(test_seeds):
        parser.error("training and held-out seeds must be disjoint")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    train_streams = [
        simulate_signal_stream(seed, output_port, args.cycles)
        for seed in train_seeds for output_port in range(args.outputs)
    ]
    test_streams = [
        simulate_signal_stream(seed, output_port, args.cycles)
        for seed in test_seeds for output_port in range(args.outputs)
    ]
    train_rows = trace_rows(train_streams, "train")
    test_rows = trace_rows(test_streams, "heldout")
    write_csv(args.output_dir / "training_trace.csv", train_rows)
    write_csv(args.output_dir / "heldout_trace.csv", test_rows)

    rng = random.Random(args.search_seed)
    best_model = DEFAULT_MODEL
    best_metrics = evaluate_model(train_streams, train_rows, best_model)
    for _ in range(args.trials):
        candidate = random_model(rng)
        metrics = evaluate_model(train_streams, train_rows, candidate)
        candidate_key = (metrics["F1"], metrics["recall"], metrics["precision"])
        best_key = (best_metrics["F1"], best_metrics["recall"], best_metrics["precision"])
        if candidate_key > best_key:
            best_model = candidate
            best_metrics = metrics

    if args.write_rtl:
        package_path = args.rtl_package
        if not package_path.is_absolute():
            package_path = Path.cwd() / package_path
        emit_rtl_package(package_path, best_model, version=1)

    result_rows: list[dict[str, Any]] = []
    for split, streams, rows in [
        ("train", train_streams, train_rows),
        ("heldout", test_streams, test_rows),
    ]:
        for name in [
            "current_requester_threshold",
            "time_history_only",
            "event_rate_only",
            "combined_features_no_snn",
        ]:
            result_rows.append({"split": split, "model": name,
                                **evaluate_heuristic(streams, rows, name)})
        result_rows.append({"split": split, "model": "combined_features_snn",
                            **evaluate_model(streams, rows, best_model)})
    write_csv(args.output_dir / "evaluation_results.csv", result_rows)

    metadata = {
        "schema_version": 1,
        "model_version": 1 if args.write_rtl else 0,
        "generator": "synthetic per-output request/service signal model",
        "target": f"at least {BLOCK_RUN} consecutive blocked cycles in t+1..t+{HORIZON}",
        "horizon_cycles": HORIZON,
        "block_run_cycles": BLOCK_RUN,
        "training_seeds": train_seeds,
        "heldout_seeds": test_seeds,
        "cycles_per_output": args.cycles,
        "outputs_per_seed": args.outputs,
        "parameter_search_trials": args.trials,
        "parameter_search_seed": args.search_seed,
        "model_parameters": best_model,
        "training_metrics": best_metrics,
        "limitations": [
            "The generator is a signal-level workload model, not noc_mesh_4x4 simulation.",
            "Held-out results validate the dataset/search code, not full-NoC prediction quality.",
            "Current requester count is used as a pressure baseline because downstream link occupancy is not exposed to the routing wrapper.",
            "No FPGA synthesis, area, timing, or power tool is part of this run.",
        ],
    }
    (args.output_dir / "experiment.json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
    )

    print(f"training rows: {len(train_rows)}; held-out rows: {len(test_rows)}")
    print(f"selected model F1 on training rows: {best_metrics['F1']:.4f}")
    for row in result_rows:
        if row["split"] == "heldout":
            print(
                f"heldout {row['model']}: TP={row['TP']} FP={row['FP']} "
                f"TN={row['TN']} FN={row['FN']} precision={row['precision']:.3f} "
                f"recall={row['recall']:.3f} events="
                f"{row['events_detected_in_advance']}/{row['events']} "
                f"mean_lead={row['mean_lead_cycles']:.2f}"
            )
    print(f"results: {args.output_dir.resolve()}")
    if args.write_rtl:
        print(f"RTL parameter package: {package_path.resolve()}")


if __name__ == "__main__":
    main()
