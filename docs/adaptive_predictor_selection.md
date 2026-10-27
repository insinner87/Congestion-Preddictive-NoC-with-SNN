# Adaptive SNN/equation selection

The optional `ENABLE_ADAPTIVE_PREDICTOR` route mode evaluates the existing SNN
and distilled equation from the same seven binary hardware features. Both
predictors describe the same target: a local output experiences a congestion
event within the next eight cycles, where an event is either four consecutive
blocked cycles or a full downstream link FIFO while a requester is present.

The selector does not see future events as predictor inputs. It retains the
SNN prediction and feature-valid bit, and only evaluates that prediction after
the eight-cycle horizon has elapsed. The label is formed from the measured
event signals in the eight subsequent cycles. The equation prediction is used
as the fallback route-risk signal.

## Policy

- Offline validation is supplied as the exact correct-sample count and total
  sample count. `SNN_VALIDATION_ACCURACY_PERCENT` remains a compatibility
  fallback when the sample total is zero; its default is `0`, which safely
  disables SNN selection when a caller has not supplied validation evidence.
- An offline accuracy of exactly 90% or below always selects the equation
  predictor. When counts are supplied, the strict threshold comparison uses
  integer cross-multiplication and does not depend on rounded percentages.
- After at least 32 matured SNN labels, the selector uses the SNN only while
  its accuracy over the most recent 64 completed predictions is strictly
  greater than 90%. Before 32 labels, it uses the equation fallback.
- The accuracy comparison is integer-exact (`correct * 100 > samples * 90`);
  displayed integer percentages are truncated.
- Both predictions are evaluated when the offline validation gate is above
  90%. If rolling online SNN accuracy becomes 90% or lower, selection returns
  to the equation model. If it later recovers above 90%, selection returns to
  the SNN.
- Each output has its own completed-sample window. `model_switch_pulse` and
  `model_switch_reason` report actual state changes. `model_selection_pulse`
  also reports the initial equation/SNN choice, with the same reason code.
  Reason codes are `1`: SNN selected, `2`: offline accuracy at/below
  threshold, `3`: insufficient online samples, and `4`: online accuracy
  at/below threshold.

The live policy is a runtime fault/generalization guard, not a substitute for
held-out validation. `run-complete.ps1` generates validation traces and
evaluates the frozen SNN first, then passes its exact correct/total counts into
the adaptive RTL regression. Standalone callers may provide those counts (or
use the percentage compatibility parameter) for the exact model under test.
No model accuracy is inferred before its delayed labels arrive.

## Routing boundary

The selected risk and score feed `mesh_route_compute` through
`noc_router_wrapper`. They can choose a lower-score, ready, destination-directed
minimal West-First alternative. The five-port router's allocator and its
ready/valid flow control are unchanged. XY mode remains deterministic, and a
stalled ingress keeps its computed route locked until the input handshake.

The Icarus selector regression uses an eight-cycle label horizon, verifies the
90% offline gate and initial sample fallback, then injects a prediction error
and checks that the mature label—not future information—causes the online
fallback. The full-mesh adaptive regression also logs selected sample counts
and model-switch events.
