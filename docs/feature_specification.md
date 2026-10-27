# Predictive congestion feature specification

## Sampling and candidate path

Each feature row describes one physical output link of an interior 4x4 mesh
router at one clock sample. The trace bench records ports North through West at
routers 5, 6, 9, and 10. Those routers have all four physical links. The
candidate is the outgoing link from that router; it is not an end-to-end path
latency estimate. West-First route legality remains computed separately by
`mesh_route_compute`.

The sampled downstream occupancy is the count in the actual two-flit
`mesh_link_fifo` sourced by that output. Occupancy is measured before it is
encoded, then compared with that FIFO's configured depth. The link FIFO now
exports its count to the router wrapper. Boundary and local ports are not used
in the training rows.

## Seven SNN input events

The event vector is `tf_encoded_features[output_port*7 +: 7]`. The least
significant bit is feature 0. An asserted bit is one input spike for that
candidate and sample. All counters reset asynchronously with `rst_n`.

| Bit | Name | Source and encoding | Time scale / meaning |
|---:|---|---|---|
| 0 | `blocked_streak_ge_2` | `tf_blocked_streak >= 2` | At least two consecutive sampled cycles with a request and no successful output transfer. This is local blocked time. |
| 1 | `blocked_streak_ge_5` | `tf_blocked_streak >= 5` | At least five consecutive locally blocked cycles; the four-bit counter saturates at 15. |
| 2 | `request_cycles_ge_16` | `tf_requester_cycles >= 16` | In the eight-cycle window, sum of eligible FIFO-head requests across the five input ports is at least 16 request-cycles (maximum 40). This is request frequency, not FFT frequency. |
| 3 | `low_service_during_demand` | `demand_active_cycles >= 4 && service_cycles <= 2` | At least four demand-active cycles and no more than two successful transfers in the same eight-cycle window. Request frequency and successful service frequency remain distinct. |
| 4 | `downstream_occupancy_ge_depth_minus_1` | `current_occupancy >= max(depth-1,1)` | Current outgoing link FIFO occupancy normalized by the actual configured depth. For depth 2, one or more entries sets the event. |
| 5 | `recent_max_occupancy_ge_depth` | `max(current, previous four samples) >= depth` | The outgoing link FIFO reached full occupancy in the current/recent four-sample history. |
| 6 | `occupancy_rising_or_requester_buffer_pressure` | occupancy greater than the prior sample OR a currently requesting input is in adaptive buffer-pressure state | One-cycle occupancy gradient OR correlated input-buffer pressure. Input FIFO occupancy is not attributed to unrelated head-of-line destinations. |

The extractor samples every clock. The event-rate counters cover eight
cycles. The occupancy history covers the current sample and four prior clock
samples. `feature_valid` stays low until the eight-cycle window and four-sample
history are initialized; the SNN state resets while invalid. Membrane voltage
is six-bit bounded (stored in eight-bit registers), weights are unsigned
two-bit values, and thresholds/reset-by-subtraction are exported parameters.

## Label and incomplete observations

For a candidate sample at cycle `t`, define the observed severe-congestion
event as:

```text
event(t) = blocked_streak(t) >= 4
           OR (downstream_link_occupancy(t) >= 2 AND request_nonempty(t))
```

The label is one when `event(t+1)` through `event(t+8)` contains an event. The
last eight rows of each run have `target_valid=0`; they are retained in raw
traces but omitted from supervised metrics and training. Startup samples with
`feature_valid=0` likewise do not enter the score. The dataset is split by
traffic seed before training, so no time windows from one run appear in more
than one split.

The generator writes `feature_valid`, the raw feature mask, all constituent
counter values, current/max occupancy, occupancy rise, request presence, and
successful transfer. This allows labels and model scores to be audited back to
measured mesh signals.
