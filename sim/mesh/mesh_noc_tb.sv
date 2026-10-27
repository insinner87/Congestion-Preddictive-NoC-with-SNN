// Self-checking traffic, routing, and backpressure test for noc_mesh_4x4.
//
// Mesh packet layout:
//   [63:61] current-hop output code (rewritten by each router wrapper)
//   [60:59] destination X
//   [58:57] destination Y
//   [56:0]  opaque payload (the testbench stores its tag in [31:0])
//   [31:0]  unique test tag
module mesh_noc_tb #(
    parameter int ROUTING_MODE = 0,
    parameter bit ENABLE_TF_PCR = 1'b1,
    parameter bit ENABLE_PRIORITY = 1'b0,
    parameter bit ENABLE_SNN = 1'b0,
    parameter bit ENABLE_SNN_ROUTING = ENABLE_SNN,
    parameter bit ENABLE_EQUATION_ROUTING = 1'b0,
    parameter bit ENABLE_ADAPTIVE_PREDICTOR = 1'b0,
    parameter int SNN_VALIDATION_ACCURACY_PERCENT = 0,
    parameter int SNN_VALIDATION_CORRECT_SAMPLES = 0,
    parameter int SNN_VALIDATION_TOTAL_SAMPLES = 0,
    parameter bit ENABLE_ADAPTIVE_BUFFER = 1'b0,
    parameter bit ENABLE_OFFLOAD = 1'b0
);

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [15:0] local_in_valid = '0;
    logic [15:0] local_in_ready;
    logic [15:0][63:0] local_in_flit = '0;
    logic [15:0][1:0] local_in_priority = '0;
    logic [15:0] local_out_valid;
    logic [15:0] local_out_ready = '1;
    logic [15:0][63:0] local_out_flit;
    logic [15:0][1:0] local_out_priority;

    localparam int MAX_TAGS = 4096;
    localparam int MAX_TRACE_CYCLES = 6000;
    localparam int NUM_OUTPUTS = 80;
    localparam int EVENT_HORIZON = 8;
    localparam int EVENT_BLOCKED_CYCLES = 4;
    logic [63:0] expected_flit [0:MAX_TAGS-1];
    integer expected_node [0:MAX_TAGS-1];
    logic expected_valid [0:MAX_TAGS-1];
    logic expected_injected [0:MAX_TAGS-1];
    logic [1:0] expected_priority [0:MAX_TAGS-1];
    logic received [0:MAX_TAGS-1];
    integer injection_cycle [0:MAX_TAGS-1];
    logic [15:0] accepted_previous = '0;
    logic [15:0] input_was_stalled = '0;
    logic [15:0] output_was_stalled = '0;
    logic [63:0] held_input_flit [0:15];
    logic [63:0] held_output_flit [0:15];
    logic [1:0] held_input_priority [0:15];
    logic [1:0] held_output_priority [0:15];
    logic pcr_prediction_trace [0:NUM_OUTPUTS-1][0:MAX_TRACE_CYCLES-1];
    logic occupancy_prediction_trace [0:NUM_OUTPUTS-1][0:MAX_TRACE_CYCLES-1];
    logic blocked_trace [0:NUM_OUTPUTS-1][0:MAX_TRACE_CYCLES-1];
    integer expected_packets = 0;
    integer delivered_packets = 0;
    integer accepted_packets = 0;
    integer cumulative_latency = 0;
    integer first_injection_cycle = -1;
    integer final_delivery_cycle = 0;
    integer next_tag = 1;
    integer random_state = 32'h4f1b_c2d7;
    integer seed_value = 1327219415;
    integer alternate_route_count = 0;
    integer adaptive_snn_cycles = 0;
    integer adaptive_equation_cycles = 0;
    integer adaptive_initial_snn_selections = 0;
    integer adaptive_initial_equation_selections = 0;
    integer adaptive_to_snn_switches = 0;
    integer adaptive_to_equation_switches = 0;
    integer occupancy_sum = 0;
    integer occupancy_samples = 0;
    integer maximum_buffer_occupancy = 0;
    logic count_random_phase_routes = 1'b0;
    integer latency_histogram [0:MAX_TRACE_CYCLES-1];
    integer random_value;

    always #5 clk = ~clk;

    noc_mesh_4x4 #(
        .FLIT_WIDTH(64),
        .ROUTING_MODE(ROUTING_MODE),
        .ENABLE_TF_PCR(ENABLE_TF_PCR),
        .ENABLE_PRIORITY(ENABLE_PRIORITY),
        .ENABLE_SNN(ENABLE_SNN),
        .ENABLE_SNN_ROUTING(ENABLE_SNN_ROUTING),
        .ENABLE_EQUATION_ROUTING(ENABLE_EQUATION_ROUTING),
        .ENABLE_ADAPTIVE_PREDICTOR(ENABLE_ADAPTIVE_PREDICTOR),
        .SNN_VALIDATION_ACCURACY_PERCENT(SNN_VALIDATION_ACCURACY_PERCENT),
        .SNN_VALIDATION_CORRECT_SAMPLES(SNN_VALIDATION_CORRECT_SAMPLES),
        .SNN_VALIDATION_TOTAL_SAMPLES(SNN_VALIDATION_TOTAL_SAMPLES),
        .ENABLE_ADAPTIVE_BUFFER(ENABLE_ADAPTIVE_BUFFER),
        .ENABLE_OFFLOAD(ENABLE_OFFLOAD),
        .LINK_FIFO_DEPTH(2)
    ) dut (.*);

    wire [79:0] route_probe_valid;
    wire [79:0] route_probe_ready;
    wire [5119:0] route_probe_flit;
    wire [239:0] accepted_next_hop;
    for (genvar probe_node = 0; probe_node < 16; probe_node++) begin : g_route_probe_node
        for (genvar probe_port = 0; probe_port < 5; probe_port++) begin : g_route_probe_port
            localparam int PROBE_INDEX = probe_node * 5 + probe_port;
            assign route_probe_valid[PROBE_INDEX] =
                dut.router_in_valid[probe_node][probe_port];
            assign route_probe_ready[PROBE_INDEX] =
                dut.router_in_ready[probe_node][probe_port];
            assign route_probe_flit[PROBE_INDEX*64 +: 64] =
                dut.router_in_flit[probe_node][probe_port];
            assign accepted_next_hop[PROBE_INDEX*3 +: 3] =
                dut.g_routers[probe_node].router_wrapper.
                    routed_in_flit[probe_port][63:61];
        end
    end

    // Trace capture, packet scoreboarding, and boundary checks.
`include "mesh_noc_tb_observers.svh"

    // Packet construction, driver helpers, and detector evaluation.
`include "mesh_noc_tb_helpers.svh"
`include "mesh_noc_tb_detector_eval.svh"

    // Complete directed and deterministic-random traffic scenarios.
`include "mesh_noc_tb_scenarios.svh"

    // Simulation timeout guard.
`include "mesh_noc_tb_watchdog.svh"
endmodule
