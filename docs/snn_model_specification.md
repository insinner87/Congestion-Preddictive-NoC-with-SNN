# Trained integer SNN specification

## Network

Each candidate router output uses a feed-forward population of four hidden
leaky integrate-and-fire neurons and one output LIF neuron. Seven binary event
features are shared conceptually across candidate outputs. Weights are
unsigned two-bit integers (0 through 3), and membrane state is eight-bit
storage clamped to 0 through 63. Inference uses no floating-point arithmetic,
Python runtime, or online training.

For a nonzero potential `v`, the leak is `max(1, floor(v/4))`; zero remains
zero. The integer recurrence is:

```text
v_leaked = v - (v == 0 ? 0 : max(1, v >> 2))
v_sum = min(63, v_leaked + sum(weight[i] * spike[i]))
spike = (v_sum >= threshold)
v_next = spike ? (v_sum - threshold) : v_sum
```

The four hidden spikes feed the output neuron in that same combinational
evaluation. The output risk class is 0 below 2, 1 from 2, 2 from 4, and 3 from
6. Routing treats class 2 or 3 as predicted congestion. Invalid feature
windows suppress risk and reset membrane state. Idle zero state does not
update, using `state_update_enable` rather than a gated clock.

## Trained parameters

The selected version 1 parameters are in
`rtl/congestion/snn_model_parameters_pkg.sv` and the machine-readable checkpoint
is `models/snn_trained.json`:

```text
hidden_weights = [[2,1,1,0,3,2,2], [0,0,0,2,1,2,0],
                  [0,2,2,2,1,0,0], [1,3,3,3,0,3,2]]
output_weights = [1,3,0,0]
hidden_threshold = 3; output_threshold = 1; potential_max = 63
```

The feature order from least-significant bit to most-significant bit is
`blocked_streak_ge_2`, `blocked_streak_ge_5`, `request_cycles_ge_16`,
`low_service_during_demand`, `downstream_occupancy_ge_depth_minus_1`,
`recent_max_occupancy_ge_depth`, and
`occupancy_rising_or_requester_buffer_pressure`. Full signal source and scale
definitions are in [feature_specification.md](feature_specification.md).

The model was selected by a bounded, reproducible integer-parameter search on
actual full-mesh RTL traces. It is not the original hand-picked parameter set.
Training details, held-out metrics, seed groups, and limits are documented in
[snn_training_and_accuracy.md](snn_training_and_accuracy.md).

## Route integration and known limits

`ENABLE_SNN` captures features and enables the network; `ENABLE_SNN_ROUTING`
separately controls whether its risk can change route selection. This allowed
trace collection with SNN observation enabled and policy feedback disabled.
West-First legal turns are generated independently. A predicted-risk primary
is replaced only by a lower-risk legal output that is currently ready. The
existing route lock preserves a selected next hop while an ingress transfer
is stalled. If the prediction is invalid or no available lower-risk candidate
exists, the preferred legal output remains selected.

Held-out aggregate SNN accuracy is 96.28%, with 87.79% recall and 2.25% false
positive rate. Direction-specific recall is lower for North and West outputs
(61.48% and 60.00%), so the aggregate gate does not imply equal performance on
every candidate direction. The model predicts local candidate-link blockage;
it does not estimate end-to-end path latency.

Cyclone IV EP4CE10 synthesis, resource use, critical path, and maximum clock
frequency have not been measured. No physical power estimate is available.
