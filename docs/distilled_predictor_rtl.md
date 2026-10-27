# Distilled predictor RTL

`rtl/congestion/distilled_congestion_predictor.sv` evaluates the learned
integer equation on each seven-bit candidate-output event vector. Coefficients
are signed 8-bit constants, bias and threshold are signed 12-bit constants,
and an explicit signed 13-bit accumulator is saturated to signed 12-bit output.
The generated model uses scale 4, bias −15, threshold 0, and coefficients
`[3, 1, 2, 4, 2, 16, 3]`. No floating-point operator, multiplier, runtime
software, or extra prediction cycle is required.

The output is valid only when the feature extractor has initialized. Invalid
predictions yield no congestion risk, so route selection uses its legal
preferred-hop fallback. `ENABLE_EQUATION_ROUTING` enables this path in
`noc_router_wrapper` and the 4x4 mesh. When enabled, a risky preferred hop is
replaced by a lower-risk legal output only if that output's ready signal is
asserted. If no available lower-risk legal output exists, the preferred route
remains selected.

`sim/congestion/distilled_predictor_tb.sv` drives 2,000 randomized vectors and
compares the RTL score/risk against a signed arithmetic reference using the
generated package constants. It passed with the trained equation. Its compile
is registered as the `distilled-predictor` regression.

The arithmetic can be evaluated in one combinational cycle, but no Cyclone IV
synthesis or timing analysis is available. The absence of a registered stage
is not evidence that the route path meets the EP4CE10 clock target. Resource
use, Fmax, and physical power remain unmeasured.
