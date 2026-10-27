// Self-checking testbench for router_5port.
//
// Compile and run both feature configurations with validation/run-all.ps1.
// The regression records router_5port_tb.vcd and router_5port_results.txt in
// the configuration's output directory.
//
// The testbench drives the same ready/valid signals a neighboring router
// would use and checks that accepted flits emerge from the correct output.
module router_5port_tb #(
    parameter bit ENABLE_TF_PCR = 1'b1
);
    localparam int NUMPORTS = 5;
    localparam int FLITWIDTH = 48;
    localparam int WINDOW_CYCLES = 16;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [NUMPORTS-1:0] in_valid = '0;
    logic [NUMPORTS-1:0] in_ready;
    logic [NUMPORTS-1:0][FLITWIDTH-1:0] in_flit = '0;
    logic [NUMPORTS-1:0][1:0] in_priority = '0;
    logic [NUMPORTS-1:0] out_valid;
    logic [NUMPORTS-1:0] out_ready = '1;
    logic [NUMPORTS-1:0][FLITWIDTH-1:0] out_flit;
    logic [NUMPORTS-1:0][1:0] out_priority;
    logic [NUMPORTS-1:0] invalid_flit_dropped;
    logic [NUMPORTS-1:0][($clog2(noc_pkg::FIFO_DEPTH)+1)-1:0] input_occupancy;
    logic [NUMPORTS-1:0][7:0] congestion_score_out;
    logic [NUMPORTS-1:0] congestion_predicted_out;
    logic [NUMPORTS*NUMPORTS-1:0] output_request_matrix;

    int checks_passed = 0;
    integer results_file;
    localparam int MAX_TRACKED_FLITS = 1024;
    logic [FLITWIDTH-1:0] expected_flits [0:NUMPORTS-1][0:MAX_TRACKED_FLITS-1];
    int queue_read [0:NUMPORTS-1];
    int queue_write [0:NUMPORTS-1];
    int queue_count [0:NUMPORTS-1];
    logic [NUMPORTS-1:0] previous_invalid = '0;
    logic [NUMPORTS-1:0] input_stalled = '0;
    logic [NUMPORTS-1:0] output_stalled = '0;
    logic [FLITWIDTH-1:0] held_input_flit [0:NUMPORTS-1];
    logic [FLITWIDTH-1:0] held_output_flit [0:NUMPORTS-1];

    always #5 clk = ~clk;

    router_5port #(
        .ENABLE_TF_PCR(ENABLE_TF_PCR)
    ) dut (.*);


    // Assertions and reference-model scoreboard.
`include "router_5port_tb_checks.svh"

    // Ready/valid stimulus helpers.
`include "router_5port_tb_drivers.svh"

    // Directed test cases and watchdog.
`include "router_5port_tb_scenarios.svh"
endmodule
