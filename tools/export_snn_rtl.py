#!/usr/bin/env python3
"""Export trained integer LIF parameters into the synthesizable SV package."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def packed(weights: list[int]) -> str:
    return "{" + ", ".join(f"2'd{weight}" for weight in reversed(weights)) + "}"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, default=ROOT / "models/snn_trained.json")
    parser.add_argument("--output", type=Path, default=ROOT / "rtl/congestion/snn_model_parameters_pkg.sv")
    parser.add_argument("--version", type=int, default=1)
    args = parser.parse_args()
    model = json.loads(args.model.read_text(encoding="utf-8"))
    hidden = model["hidden_weights"]
    if len(hidden) != 4 or any(len(row) != 7 for row in hidden):
        parser.error("the RTL expects exactly four hidden neurons with seven weights each")
    if len(model["output_weights"]) != 4:
        parser.error("the RTL expects four output weights")
    for weight in [value for row in hidden for value in row] + model["output_weights"]:
        if not 0 <= int(weight) <= 3:
            parser.error("all exported weights must fit the two-bit unsigned RTL encoding")
    output = "\n".join([
        "// Generated from the quantized integer LIF training checkpoint.",
        "package snn_model_parameters_pkg;",
        f"    localparam int MODEL_VERSION = {args.version};",
        *[
            f"    localparam logic [13:0] W_HIDDEN_{index} = {packed(row)};"
            for index, row in enumerate(hidden)
        ],
        f"    localparam logic [7:0] W_OUTPUT = {packed(model['output_weights'])};",
        f"    localparam logic [7:0] HIDDEN_THRESHOLD = 8'd{int(model['hidden_threshold'])};",
        f"    localparam logic [7:0] OUTPUT_THRESHOLD = 8'd{int(model['output_threshold'])};",
        f"    localparam logic [7:0] POTENTIAL_MAX = 8'd{int(model.get('potential_max', 63))};",
        "endpackage",
        "",
    ])
    args.output.write_text(output, encoding="utf-8")
    print(f"Exported model version {args.version} to {args.output}")


if __name__ == "__main__":
    main()
