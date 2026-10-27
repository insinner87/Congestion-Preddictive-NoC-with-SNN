# Predictive routing integration

## Decision path

For each incoming flit, the wrapper computes the legal XY or West-First
candidate outputs from its source coordinate and destination. Per-output local
time, request/service-frequency, input-buffer pressure, and actual outgoing
link FIFO features feed either the trained SNN or its distilled equation. The
predictor gives each candidate a risk decision. The route selector applies risk
only when the normal preferred legal output is risky, and changes to an
available legal candidate with lower risk. It keeps deterministic preference
on ties and when the predictor is invalid or no ready lower-risk alternative
exists. The selected hop then enters the existing allocator, crossbar, and
registered link FIFO.

`ENABLE_SNN_ROUTING` and `ENABLE_EQUATION_ROUTING` select the predictor policy.
The feature path can be enabled independently for trace capture. The final
equation configuration uses the same seven bits and the fixed-point constants
in `distilled_congestion_model_pkg.sv`. The packet's current-hop field is
rewritten as before; the 57-bit opaque payload is untouched. The two-bit
priority sideband remains attached through every input, link, and ejection FIFO.

## Directed test

`sim/mesh/equation_routing_tb.sv` drives the actual wrapper feature extractor
with a two-entry East link occupancy and a head flit blocked on East. After
the temporal window is valid, the test checks the observed East feature vector
and a positive equation risk. For a destination where East and North are both
legal West-First choices, a second tagged flit is selected for the available
North output and observed intact on that output. The test then makes North
unavailable and checks fallback to preferred East. The test passes with the
trained equation package.

`mesh-west-first-equation` enables the distilled equation in the full-mesh
packet scoreboard with priority and adaptive-buffer pressure active. The full
regression checks packet/priority conservation, route legality, and the
directed equation-route case. A simulation pass is not a formal proof of
deadlock or starvation freedom.

## Route stability and unavailable paths

West-First turn restrictions are computed independently from risk; the model
cannot create an illegal turn. A chosen ingress next hop is held while that
input transfer is stalled. The route selector also filters alternative
candidates using the current `out_ready` for that physical link. If the
alternative is unavailable, the policy retains the preferred legal route and
lets ordinary ready/valid backpressure hold the flit. If there is no legal
alternative, the preferred route is retained. There is no predictor pipeline,
so risk is sampled from the currently valid feature state rather than a
delayed prediction.

## Limits

The SNN and equation are local candidate-link predictors. The equation has
98.997% agreement with the trained SNN and 96.70% test accuracy on the recorded
traffic set; the SNN has 96.28% test accuracy. These results do not prove a
latency or throughput improvement. Existing fixed-seed mesh regressions report
delivery and latency, while statistically powered multi-seed baseline versus
equation performance comparisons are not complete. Cyclone IV timing/resource
fit and deadlock freedom also remain unverified.
