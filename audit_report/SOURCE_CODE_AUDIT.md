# Source-code and architecture audit

**Evidence basis:** source files as present on 2026-10-24. Line references are repository-relative and 1-based.

## 1. Inventory and project structure

The project root is `C:\Users\legen\Desktop\Capstone research\Temporal and Freq`. It contains one root README and four documented folders:

| Area | Contents |
|---|---|
| `rtl/common/` | `noc_pkg.sv` |
| `rtl/router/` | `router_5port.sv`, `input_buffer.sv`, `fifo.sv`, `switch_allocator.sv`, `round_robin_arbiter.sv`, `crossbar.sv` |
| `rtl/congestion/` | `congestion_monitor.sv`, `congestion_estimator.sv` |
| `rtl/mesh/` | `noc_mesh_4x4.sv`, `noc_router_wrapper.sv`, `mesh_route_compute.sv`, `mesh_link_fifo.sv` |
| `sim/` | router, congestion and mesh testbenches; included `.svh` helpers/checkers/scenarios |
| `validation/` | four PowerShell scripts, saved run logs, executables, VCDs, and results |
| `docs/` | README and TF-PCR/mesh validation report |

The package defines `FLIT_WIDTH=48`, `FIFO_DEPTH=4`, `NUM_PORTS=5`, `ADDR_WIDTH=4`, and port encodings Local=0, North=1, South=2, East=3, West=4 (`rtl/common/noc_pkg.sv:9-29`). `ADDR_WIDTH` has no apparent role in the inspected RTL. No SystemVerilog macros were found. Key compile parameters include router `ENABLE_TF_PCR=0` by default, but mesh wrapper/mesh `ENABLE_TF_PCR=1` by default; mesh routing mode defaults to XY (`router_5port.sv:18-29`, `noc_router_wrapper.sv:6-19`, `noc_mesh_4x4.sv:5-17`).

### Module hierarchy

```text
noc_mesh_4x4
  16 x noc_router_wrapper (coordinates x=node%4, y=node/4)
    5 x mesh_route_compute
    1 x router_5port
      5 x input_buffer / fifo
      1 x switch_allocator
        5 x round_robin_arbiter (one per output)
        optional congestion_monitor + congestion_estimator
      1 x crossbar
  registered mesh_link_fifo on each directed neighbor link
```

The mesh instantiates wrappers with `node=0..15`, deriving X/Y coordinates at `rtl/mesh/noc_mesh_4x4.sv:48-77`. Link generation and boundaries are at `:89-186`.

## 2. Original five-port router

The default original flit is 48 bits: `[47:45]` is one of five output-port codes; `[44:0]` is payload. This is a single-flit packet router, not a packet reassembly/framing layer (`router_5port.sv:10-16`; `noc_pkg.sv:9-29`). The output code alone addresses only a local port, not 16 mesh nodes.

Each input has a FIFO (`router_5port.sv:90-115`, `input_buffer.sv:6-52`, `fifo.sv:3-79`). The allocator decodes each FIFO head's top three bits, asserts one request for a valid destination, and flags codes 5-7 as invalid (`switch_allocator.sv:77-100`). Invalid heads are popped to avoid blocking later flits (`router_5port.sv:115-117`).

There is an independent round-robin arbiter for each output. The arbiter holds its selected input while `grant_valid && !ready` and advances its fairness pointer only on `grant_valid && ready` (`round_robin_arbiter.sv:35-91`). Thus a grant/offered output is not itself service. The actual transfer is `out_valid && out_ready`; the crossbar exposes `output_valid=grant_valid`, copies the granted FIFO head, and pops only if the corresponding output is ready (`crossbar.sv:25-45`).

The router's ready/valid input accepts a flit on an edge when `in_valid && in_ready`; the output transfers when `out_valid && out_ready` (`router_5port.sv:34-46`). FIFOs reset pointers/counts asynchronously when `rst_n` is low; the router clears the invalid-drop pulse asynchronously (`fifo.sv:35-69`, `router_5port.sv:178-185`). Default router FIFO depth is four (`noc_pkg.sv:12`).

### Example flit journey through one router

Suppose a flit has destination code East (`3'b011`) and enters the Local input:

1. On an edge with Local `in_valid && in_ready`, the Local input FIFO writes the whole flit.
2. The FIFO head becomes valid; the allocator decodes the top three bits and asserts Local-to-East request.
3. East's round-robin arbiter picks one requester. If East is not ready, the arbiter locks that input and the crossbar keeps valid/data stable.
4. When East `out_valid && out_ready`, the crossbar pops the source FIFO and the arbiter advances its pointer.

Independent outputs can transfer concurrently; a given output has at most one granted input, and an input's single destination code requests at most one output (`switch_allocator.sv:77-100`, `router_5port_tb_checks.svh:1-94`).

## 3. TF-PCR measurements and estimator

### What is counted

The switch allocator exports its decoded request matrix. It defines successful output service as `grant_valid & output_ready`, equivalent to public `out_valid && out_ready` because the crossbar drives `out_valid=grant_valid` (`switch_allocator.sv:73-103`, `crossbar.sv:27-40`).

For each output `o` and requester/input `i`:

- **Request-cycle count:** increments by the number of active requester bits each clock. This is eligible requester-cycles, not unique packet arrivals.
- **Requester wait:** while a request remains active, increments unless that exact requester wins a successful output transfer; clears on service or withdrawal; saturates at all ones.
- **Output blocked cycles:** increments once per clock if any requester exists and no transfer succeeds; clears on no request or a successful transfer; saturates.
- **Window demand/service:** request-cycle and transfer-cycle counts accumulate over `WINDOW_CYCLES`; at the final cycle the output snapshot includes that current cycle's values. Deficit is `max(demand - service, 0)`. The accumulators reset at that boundary, while the last completed snapshot remains available to the estimator until the next boundary.

Evidence: `congestion_monitor.sv:42-112`. With defaults, window=16; demand counter width is `ceil(log2(16*5+1))=7`, service width `ceil(log2(16+1))=5`; the temporal counters are 8-bit saturating. Demand may reach 80 request-cycles in a 16-cycle window, service at most 16. No counter rollover is expected within the configured bounds; temporal counters saturate rather than wrap.

### Score equation and worked example

The RTL computes:

```text
time_score = max(normalize(max_i requester_wait[o,i]),
                 normalize(output_blocked[o]))
frequency_score = normalize(last_window_service_deficit[o])
score = floor((TIME_WEIGHT*time_score + FREQ_WEIGHT*frequency_score)
              / (TIME_WEIGHT + FREQ_WEIGHT))
predicted = score >= SCORE_THRESHOLD
```

The normalization scales to 0..255 with integer division, saturating at 16 temporal cycles and 8 deficit units by default (`congestion_estimator.sv:28-50`, `:52-88`). Default weights are 3 and 1; threshold is 128 (`:5-14`). The implementation is consistent with `floor((3*time_score + deficit_score)/4)` for defaults (`:82-87`). Integer division truncates toward zero; all score values are nonnegative.

Standalone test example: the test uses a four-cycle window. Two requesters ask for output 0 on each of four cycles; one is transferred each cycle. Demand=8, service=4, deficit=4. The unsatisfied requester's wait reaches 4; output blocked cycles remain 0 because a transfer occurred each cycle. Normalized time=`floor(255*4/16)=63`; deficit score=`floor(255*4/8)=127`; final score=`floor((3*63+127)/4)=79`, below threshold 128. This exact result is checked in `sim/congestion/tfpcr_monitor_tb.sv:73-113`.

High request frequency alone is not sufficient for a positive deficit score: the aggregate request-cycles are compared with successful service. Still, this is a particular demand/service heuristic: request-cycle totals and transfer-cycle totals are not packet-arrival counters and should be named/documented accordingly.

### Is it a predictor?

The RTL output `congestion_predicted` is a thresholded score built from present consecutive waits/blocking and the most recently completed 16-cycle service-deficit window. There is no configurable prediction horizon or future-event model in the estimator RTL. The independent “four blocked cycles in the next eight” event is defined in the mesh testbench, not generated by the hardware estimator (`mesh_noc_tb.sv:26-27`; `mesh_noc_tb_detector_eval.svh:2-143`). It is therefore more precise to call the RTL output a congestion-risk/prediction flag and call the future-event labels a testbench evaluation target.

The evaluation uses later cycles to label the target; no future blocked value is fed into the score. The target nevertheless measures persistence of the same ready/valid blockage phenomenon that contributes to current monitor history. The event windows overlap substantially, so per-cycle confusion samples are correlated and are not independent observations.

## 4. Feature-enable behavior and routing dataflow

`router_5port.ENABLE_TF_PCR` defaults to disabled. In the allocator, enabling it instantiates monitor and estimator; disabling it ties diagnostic counters, scores, and predictions to zero (`switch_allocator.sv:105-155`). Destination decoding, arbiters, crossbar, requests, grants, and transfer conditions are outside that generate and are unchanged. This supports baseline datapath preservation at RTL; the enabled configuration does add logic/resource cost not measured here.

The mesh wrapper defaults `ENABLE_TF_PCR=1`. It sets route-compute `score_valid` equal to that parameter (`noc_router_wrapper.sv:50-63`) and passes its score/prediction arrays into route selection. This is a configuration enable, **not a runtime score-valid/warm-up signal**. Before the first completed window, deficit is reset/zero; no explicit warm-up validity is supplied. The route-compute module supports `score_valid=0` deterministic fallback, but the wrapper does not dynamically detect invalid/unknown score data (`mesh_route_compute.sv:73-87`; `noc_router_wrapper.sv:50-63`).

### Signal dependency table

| Signal/state | Source and update | Consumer | Affects routing? | Affects prediction? |
|---|---|---|---:|---:|
| `buffer_valid`, `buffer_flit` | Input FIFO head | Allocator decode/request | Yes, destination route request | Yes, via request matrix |
| `request_matrix[o*5+i]` | Allocator, when valid FIFO head destination is `o` | Arbiter, monitor, wrapper occupancy baseline | No direct score-based choice in router; supplies fixed output request | Yes, demand/wait and occupancy comparator |
| `grant_valid`, `grant_index` | Output arbiters | Crossbar and monitor | Arbitration only; not selected by TF-PCR | Yes, identifies service requester |
| `output_ready`, `out_valid` | Downstream and crossbar | Arbiter, crossbar, monitor | Backpressure / grant lock, not congestion route | Yes, service and blockage |
| `output_transfer` | `grant_valid & output_ready` | Monitor | No, not in router arbiter selection | Yes, successful-service counts |
| `requester_wait_cycles`, `output_blocked_cycles` | Monitor state | Estimator | Indirectly, through wrapper route compute | Yes, time score |
| `last_window_service_deficit` | Monitor's most recent completed window | Estimator | Indirectly, through wrapper | Yes, frequency score |
| `congestion_score`, `congestion_predicted` | Estimator; zero when disabled | Router output ports; wrapper route compute | **Yes in mesh West-First only** | Predictor outputs |
| `input_occupancy` + `request_matrix` | FIFO counts and decoded head requests | Wrapper occupancy detector | No; diagnostic comparator only | Occupancy-only prediction only |
| `computed_route` / `[63:61]` | Wrapper route compute and flit rewrite | Existing router destination decode | **Yes: actual mesh output request** | No |

Signal wiring evidence: `router_5port.sv:117-174`; `switch_allocator.sv:73-155`; `noc_router_wrapper.sv:50-145`; `mesh_route_compute.sv:22-87`. The occupancy detector is not a routing input; it is reported as a comparator.

## 5. Mesh topology, packet and routing

### Mesh format and links

The mesh uses 64-bit flits. The wrapper reads destination X from `[60:59]`, Y from `[58:57]`, and rewrites only `[63:61]`. The remaining `[56:0]` is opaque to RTL (`noc_router_wrapper.sv:1-4`, `:50-78`). The testbench conventionally sets `[56:32]=0` and stores its tag in `[31:0]` (`mesh_noc_tb_helpers.svh:2-14`); those 25 upper payload bits are not enforced as “reserved” by the RTL.

Each directed inter-router link has a depth-2 registered FIFO. `source_ready` depends on local registered occupancy (`count < DEPTH`), while destination valid reflects local occupancy; downstream ready does not feed combinationally around a mesh cycle (`mesh_link_fifo.sv:25-64`). A 4x4 orthogonal mesh therefore has 24 bidirectional neighbor pairs/48 directed link FIFOs. East output connects to the neighbor's West input; West to East; South to North; North to South (`noc_mesh_4x4.sv:111-184`).

Boundary inputs are tied invalid/zero and boundary outputs not-ready (`noc_mesh_4x4.sv:89-108`). The testbench asserts that a boundary output never asserts valid (`mesh_noc_tb_observers.svh:88-113`). Every node has a Local injection/ejection interface (`noc_mesh_4x4.sv:82-87`).

### XY and West-First

`mesh_route_compute` first selects the XY-preferred direction: East/West until X matches, then North/South until Y matches; local destination selects Local (`mesh_route_compute.sv:31-55`). XY mode allows only that preferred output. Every selected non-local hop reduces Manhattan distance by one.

West-First mode restricts alternatives:

- Destination west: West is the only legal hop; remaining westward progress must occur before any non-West turn.
- Destination east and vertically displaced: East and the required vertical hop are legal minimal alternatives.
- Same X: only the required vertical direction is legal.

When `score_valid` is true and the preferred hop's prediction bit is set, the selector scans legal choices and picks a strictly lower raw score. Ties retain the initialized preferred hop. If all legal choices are predicted congested, it still selects the legal choice with the lowest score; no legal hop is removed just because it is congested. Otherwise it keeps the XY-preferred legal hop (`mesh_route_compute.sv:54-87`). Tests cover a legal North detour and an equal-score tie, but do not explicitly assert the “all legal choices congested” case.

The wrapper locks a computed hop if an ingress flit is valid but the router FIFO is not ready, then uses it until acceptance (`noc_router_wrapper.sv:67-97`). After the flit enters the router FIFO, the router's arbiter holds an output grant during output backpressure. These are distinct stability points.

West-First is a known deadlock-avoidance turn model, not a new theorem of this project. The restriction removes turns **to West after a non-West turn**, which is the basis of the channel-dependency acyclicity argument in the turn-model literature. The project has exhaustive finite route enumeration, not a formal channel-dependency proof or model checking. Cite Glass and Ni; do not present simulation as proof.

## 6. Parameters and implementation limits

Relevant defaults: router FIFO 4; link FIFO 2; monitor window 16; temporal score saturation 16; deficit saturation 8; time/frequency weights 3/1; prediction score threshold 128; occupancy comparator threshold 3. See `noc_pkg.sv`, `router_5port.sv:18-29`, `noc_mesh_4x4.sv:5-17`, `noc_router_wrapper.sv:6-19`, and `congestion_estimator.sv:5-14`.

Icarus Verilog is present (12.0 development build). Verilator, Yosys, Quartus, Vivado, Verible lint, SymbiYosys and common SMT tools were not found on PATH during this audit. Thus no synthesis, area/power/frequency estimate, lint result, or formal deadlock proof is reported. The project has no build system beyond its PowerShell/Icarus scripts.
