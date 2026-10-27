# Routing and offloading policy

## Existing route contract

The 4x4 mesh accepts destination coordinates in `[60:57]`, rewrites the current hop in `[63:61]`, and passes `[56:0]` untouched. XY mode has one minimal candidate. West-First generates the legal candidate mask first; the preferred direction remains the deterministic tie break. Adaptive scores may rank only the set bits in that mask. No invalid score, reset, or missing predictor state may select an arbitrary output.

## Prediction-driven selection

For each legal candidate output, use a bounded integer cost. The baseline comparison keeps the existing 3:1 time-to-service-deficit score unchanged. The new feature path produces an explicit future-risk class. In an SNN-enabled run, the predictor cost replaces the old diagnostic threshold as the future-risk input; the baseline estimator remains available for ablation and fallback. The route selector scans legal candidates in a fixed port order and changes from the preferred output only on a strict cost decrease. Equal costs retain the preferred hop. When the preferred output is not predicted high risk, the existing preferred choice remains.

The wrapper continues to lock the route while an offered ingress flit is stalled, then stores the chosen next hop in the accepted flit. The output arbiter separately holds its grant while downstream `ready` is low. Feature snapshots are one cycle old at most; the same-cycle predictor path uses the latest combinational request/handshake view and stored history. If an output score is not valid after reset, the preferred legal route is selected.

## Offloading policy

“Offloading” means congestion-triggered alternate-next-hop selection for an ingress flit, within existing West-First candidates. It does not migrate an already queued packet, create an external port, duplicate a packet, or split a packet. A controller should assert only after a configurable persistence condition or high future-risk class; it should release below a separate lower threshold. When no alternate candidate exists, the legal preferred hop remains selected. Predictor invalid/reset state also falls back to the preferred legal hop. The held route while ingress is stalled prevents score fluctuations from changing an offered flit.

The initial implementation asserts after two consecutive valid risk classes at or above class 2 and recovers after two valid samples at or below class 1. Invalid/reset prediction clears the controller and falls back to the preferred legal route. These are starting values, not experimentally optimal settings. No offload-frequency or performance benefit is claimed until held-out full-mesh traces evaluate trigger and recovery cases.

## Priority sideband and arbitration

Neither the 48-bit standalone router format nor the 64-bit mesh format defines priority. In the mesh format, all 57 payload bits are opaque to the RTL. Reusing payload bits would reduce application payload and break compatibility.

The approved interface keeps the 64-bit flit unchanged and adds a two-bit priority sideband to router input/output and mesh injection/ejection ports. The sideband is stored with every router FIFO entry and each link FIFO entry, selected with the data in the crossbar, and preserved across each ready/valid transfer. Class 0 is lowest and class 3 highest. The sideband remains present and aligned even when priority arbitration is disabled.

Priority arbitration is optional and disabled by default to preserve the previous arbitration policy. When enabled, each output first considers requests that have waited at least `PRIORITY_AGE_LIMIT` cycles (16 by default), choosing the first aged requester from the rotating round-robin start. Otherwise it chooses the highest class, breaking ties by round robin. A stalled grant stays locked until transfer. Aging provides a bounded opportunity under the assumption that downstream `ready` eventually stays high; no unconditional liveness guarantee is claimed.

For the 4x4 mesh with router FIFO depth 4 and link FIFO depth 2, the sideband adds 2 bits to each of 320 router FIFO entries and 96 directed-link FIFO entries, for 832 data-storage bits. With priority enabled and the default age limit, the declared per-requester age state is another 2,000 bits (80 output arbiters × 5 requesters × 5 age bits), before synthesis optimization, plus priority comparison and selection logic. These are RTL-derived counts, not Cyclone IV synthesis results. Public mesh and router ready/valid interfaces gain aligned priority signals; external code must drive priority for each offered flit and sample it with the matching output flit.

`priority_arbiter_tb` checks class precedence, equal-class rotation, age promotion, and grant stability under backpressure. `mesh-west-first-priority` and `mesh-west-first-snn` check end-to-end priority/flit alignment with priority enabled. The latter also enables SNN routing, adaptive buffer notification, and offload control. These simulations do not prove a formal starvation bound or measure hardware cost.
