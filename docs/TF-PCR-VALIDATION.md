# TF-PCR and 4x4 mesh validation

## Existing router baseline

The original `router_5port` remains the per-node datapath. Its default packet
format is unchanged: the top three flit bits name one of five output ports.
`ENABLE_TF_PCR` remains disabled by default. The legacy router test now also
checks the optional observation outputs, but the FIFO, ready/valid behavior,
arbitration, crossbar, and baseline destination decoding remain unchanged.

Run the reproducible regression from the project directory:

```powershell
powershell -ExecutionPolicy Bypass -File .\validation\run-all.ps1
```

The script runs enabled and disabled router builds and saves each transcript,
summary, and waveform under `validation\run\reorganized\router-enabled\` and
`validation\run\reorganized\router-disabled\`. See the root README for the
individual pass criteria and complete test list.

## TF-PCR definitions

`congestion_monitor` counts one eligible requester-cycle for each asserted
input-to-output request. This is not a count of unique packet arrivals. An
output transfer is counted only when the allocator grant and downstream
`ready` are both high, i.e. when the router's ready/valid transfer occurs.

For output `o` and window `w`:

```text
request_count[o,w] = sum over cycles and requesters of request[o][i]
transfer_count[o,w] = sum over cycles of (out_valid[o] && out_ready[o])
deficit[o,w] = max(0, request_count[o,w] - transfer_count[o,w])
```

The default window is 16 cycles. All outputs share the same synchronous window
boundary, and the boundary snapshot includes the current cycle's request and
transfer. For five inputs, the request counter width is
`ceil(log2(16*5+1)) = 7` bits; the transfer counter width is
`ceil(log2(16+1)) = 5` bits. The deficit has the request counter width.

Wait time is maintained for each `(output,input requester)` pair. A requester
increments while its request remains asserted and it is not the requester
successfully transferred that cycle. It clears on transfer or request
withdrawal. The blocked-cycle counter is per output and increments once when
at least one requester exists but that output makes no transfer. Both counters
are 8-bit saturating counters by default.

Each score component is normalized independently to 0..255:

```text
time_score = max(
    floor(255 * min(max_requester_wait, 16) / 16),
    floor(255 * min(output_blocked_cycles, 16) / 16)
)
deficit_score = floor(255 * min(deficit, 8) / 8)
score = floor((3 * time_score + deficit_score) / 4)
prediction = score >= 128
```

The weights, normalizers, counter widths, window length, and score threshold
are parameters. The initial configuration weights time 3:1 over service
deficit. High request frequency alone is not a positive congestion signal:
offered request-cycles are compared with successful service over the same
window.

The independent monitor test covers request withdrawal, simultaneous service
and contention, exact window-boundary accounting, no deficit under fully
serviced demand, score scaling, saturation, and reset:

```powershell
powershell -ExecutionPolicy Bypass -File .\validation\run-all.ps1
```

The monitor regression is named `tfpcr-monitor`; its source list and output
directory are defined in `validation\run-all.ps1`.

## Mesh integration

`noc_mesh_4x4` instantiates 16 `noc_router_wrapper`s, each wrapping the existing
five-port router. Mesh packet format is 64 bits:

| Bits | Meaning |
|---|---|
| `[63:61]` | Current-hop output code; rewritten at each router |
| `[60:59]` | Destination X coordinate, 0..3 |
| `[58:57]` | Destination Y coordinate, 0..3 |
| `[56:32]` | Reserved |
| `[31:0]` | Application/test tag in the testbench |

The mesh wrapper preserves destination coordinates and payload while replacing
the top three next-hop bits. A 2-flit registered FIFO is present on each
directed inter-router link. Its source-ready depends only on registered local
occupancy, so downstream ready does not form a combinational path around a
mesh cycle. Boundary input ports are tied invalid/zero and boundary outputs
are held not-ready; the testbench asserts that no boundary output is requested.

Routing modes:

- `ROUTING_MODE=0`: deterministic XY reference; horizontal progress precedes
  vertical progress.
- `ROUTING_MODE=1`: minimal West-First adaptive routing. Any Westward
  progress is completed before a non-West turn. If the destination is West,
  West is the only candidate. For an Eastward destination that is vertically
  displaced, East and the required vertical direction are both legal minimal
  candidates. Every selected hop reduces Manhattan distance by one.

The West-First rule forbids all turns *to West* after a North, South, or East
turn. This is the standard West-First turn restriction; it removes the
channel-dependency turns needed to form a cyclic dependency, rather than
inferring deadlock freedom from simulation alone. See C. J. Glass and L. M. Ni,
"The Turn Model for Adaptive Routing," ISCA, 1992, pp. 278-287. The implementation
does not add virtual channels or change packet ordering within an input FIFO.

At ingress, the wrapper chooses the next hop from the packet destination and
local score. If an ingress ready/valid transaction stalls before entering the
router FIFO, its selected route is latched until acceptance. After acceptance,
the FIFO head's route field is fixed; the existing allocator then holds a
granted output during downstream backpressure. If the XY-preferred output is
not predicted congested, the selector retains it. If it is predicted congested,
the selector chooses a lower-score West-First-legal candidate; equal scores
retain deterministic XY preference. If all legal choices are congested, the
least-score legal choice wins, with XY preference as a tie-break. With TF-PCR
disabled or diagnostic scores invalid, routing falls back to the deterministic
legal XY-preferred choice.

The occupancy-only reference is a separate detector, not a routing input. It
asserts when the sum of FIFO flits whose current head requests an output is at
least 3. With four-flit input FIFOs this is a 75%-of-one-FIFO threshold; it is
fixed before the evaluation trace and was not tuned on that trace.

## Tests and reproduction

The route-compute unit test enumerates all 256 source/destination pairs in XY
and West-First modes, checks minimal Manhattan progress and the West-First
turn restriction, and tests congestion selection and deterministic ties:

```powershell
powershell -ExecutionPolicy Bypass -File .\validation\run-all.ps1
```

The route enumeration regression is named `mesh-routes`; its source list and
output directory are defined in `validation\run-all.ps1`.

The mesh testbench checks all 256 source/destination pairs (including all 240
nonlocal pairs), simultaneous independent traffic, repeated 16-source hotspot
bursts, sustained multi-packet ejection backpressure and recovery, a forced
legal adaptive detour, and deterministic uniform random traffic. The random
seed is `0x4f1bc2d7`. Packet scoreboarding checks injection and ejection
handshakes, destination, intact flit data, no duplicates, and no loss. It also
records end-to-end latency/throughput and compares both detectors against the
same future-event labels.

Compile and run all mesh configurations with
`powershell -ExecutionPolicy Bypass -File .\validation\run-all.ps1`. The
runner preserves the separate XY, West-First TF-PCR, and West-First disabled
logs in per-test directories under `validation\run\reorganized\`.

## Prediction event definition and measured results

The predictor is evaluated against an output-level event independent of either
detector: an output is labeled positive at cycle `t` if, during cycles
`t+1` through `t+8`, it has a run of at least four consecutive cycles with
`out_valid && !out_ready`. This labels future sustained output blocking, not
current buffer occupancy. Confusion counts are per output-cycle; a window is
classified positive when its future horizon contains such a run. Advance
detection is stricter: a prediction must occur before the first blocked cycle
of a run of four. Predictions during or after event onset do not count as
advance detections. Precision/recall/F1 are reported as zero when their
denominator is zero.

All three mesh traces use the same traffic sequence, simulation duration,
event definition, thresholds, and random seed. Results from Icarus simulation:

| Configuration | Packets | Avg latency (cycles) | Throughput (packets/cycle) | TP | FP | TN | FN | Precision | Recall | F1 | False positives/output-cycle |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| XY + TF-PCR diagnostic | 796 | 8.196 | 0.3324 | 23 | 47 | 206302 | 28 | 0.329 | 0.451 | 0.380 | 0.000228 |
| West-First + TF-PCR | 796 | 8.196 | 0.3324 | 23 | 54 | 206295 | 28 | 0.299 | 0.451 | 0.359 | 0.000262 |
| West-First, TF-PCR disabled | 796 | 8.196 | 0.3324 | 0 | 0 | 206349 | 51 | 0.000 | 0.000 | 0.000 | 0.000000 |
| Occupancy-only, same trace | 796 | 8.196 | 0.3324 | 45 | 170 | 206179 | 6 | 0.209 | 0.882 | 0.338 | 0.000824 |

Each detector's confusion totals cover 206,400 output-cycle windows. The trace
contains six qualifying sustained-blocking events. Strict advance detection
found two events with TF-PCR in XY diagnostic mode, two with adaptive
West-First/TF-PCR, and five with occupancy-only; the corresponding missed
event counts were four, four, and one. The mean positive lead was one cycle
for detectors that had advance detections. TF-PCR had higher measured
precision but lower recall than occupancy-only on this trace. TF-PCR disabled
in West-First mode had no predictions and missed all six events. These are
small directed/random regression traces, not evidence that either detector is
generally superior. The forced route-choice test proves that the integrated
West-First wrapper can select a legal lower-score alternative; the measured
traffic did not show an end-to-end latency or throughput advantage over the
XY/fallback case.

The average latency and throughput are workload-level smoke measurements, not
saturated-network capacity measurements. No synthesis tool was available in
the environment; only Icarus Verilog (`iverilog`) and `vvp` were detected, so
hardware resource overhead is not reported.

## Saved run logs

Generated validation transcripts are stored under `validation/results/`.
Existing `router_5port_results.txt` and `router_5port_tb.vcd` are preserved.
