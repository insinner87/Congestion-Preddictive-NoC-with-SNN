# Research architecture

## Objective

Extend the existing 4x4 mesh without replacing its five-port router, preserving the original XY and West-First configurations as baselines. The primary research path is a per-output feature pipeline that combines local request pressure, short-term trend, and fixed-window request/service activity with a small integer LIF spiking network. The predictor supplies a future-risk class to the existing West-First legal-candidate selector. The predictor does not decide route legality.

## Existing and proposed path

```text
64-bit mesh flit + local coordinates
  -> existing legal XY / West-First candidate generation
  -> existing router request / transfer signals
  -> bounded TF feature history per output
  -> binary event encoder
  -> 4 hidden LIF neurons + 1 output LIF neuron per output
  -> quantized future-risk class
  -> score among legal candidates, preferred-hop tie break
  -> existing input FIFO, round-robin allocator, crossbar, link FIFO
```

The future target is a sustained blockage event: at least four consecutive cycles with a nonempty request row and no successful transfer during the next eight cycles (`t+1` through `t+8`). The horizon and event definition are experimental parameters; eight cycles is a starting point because the existing mesh test already records an eight-cycle window. It is not claimed optimal until held-out horizon sweeps are run.

The synthesizable LIF path and route influence are implemented and directed-tested. Its checked-in weights are hand selected, however, and have not been evaluated against this future-event target. Treat the current output as an unvalidated risk class until the offline search and held-out full-mesh evaluation run.

## Workstream boundaries

1. **TF-PCR/SNN routing:** separate current baseline measurements from the new feature history. Provide fixed-window requester-cycle/service-cycle counts, a short pressure gradient, a persistence state, and the SNN risk class. Keep predictor bypass and use deterministic preferred-hop fallback during reset/invalid state.
2. **Adaptive buffer and activity control:** implemented as a separate occupancy-pressure controller with an early rising-occupancy threshold and lower recovery threshold. It only supplies a notification/feature; FIFO capacity and full/empty semantics remain fixed. The LIF state holds when all input events and potentials are zero. This is an activity proxy policy, not measured power.
3. **Offloading and priority:** persistent predicted-risk trigger and recovery logic are implemented separately. It selects an alternate, still-legal next hop for a new flit; there is no packet migration. Four priority classes travel on a two-bit sideband aligned with each flit. Per-output arbitration prefers higher classes, rotates ties, and promotes requests after a 16-cycle age threshold.

## Resource and timing approach

The initial predictor has five binary input events, four hidden neurons, and one output neuron for each of five outputs. Potentials are small unsigned integers with fixed leak and threshold behavior; weights are small integer constants. The expected state is on the order of 200 membrane bits per router, plus feature counters and history. This is an RTL structural estimate only. No Cyclone IV synthesis tool is available in the current environment, so area, Fmax, and fit remain unverified.

Feature history is clocked; the small LIF layer evaluates a candidate risk combinationally from the current encoded features and stored potential, with its membrane state committed on the next active edge. This avoids adding a register stage to ingress route acceptance. It may lengthen the route-computation path; the final design needs Quartus timing analysis before FPGA claims.

## Research comparisons

The implementation must compare the original XY baseline, existing West-First/TF-PCR, time/history features, event-rate features, combined features without SNN, and combined features with SNN. Adaptive pressure, predictor update enable, and offload/priority policies are separate switches. Every run uses matched topology, load, seeds, warm-up, and measurement windows. The benchmark methodology defines the labels and metrics. No accuracy or performance benefit is assumed in advance.
