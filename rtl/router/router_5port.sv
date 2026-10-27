// Top-level five-port router.
//
// This module connects the independently commented building blocks:
//   1. input_buffer.sv: stores incoming flits, one FIFO per input;
//   2. switch_allocator.sv: decodes destinations and arbitrates requests;
//   3. crossbar.sv: moves the granted flits to output ports;
//   4. round_robin_arbiter.sv: provides fair, stable grants per output.
//
// Port numbers come from noc_pkg:
//   0 = Local, 1 = North, 2 = South, 3 = East, 4 = West
//
// Packet format for the default 48-bit flit:
//   flit[47:45] = destination port number
//   flit[44:0]  = payload (passed through unchanged)
// A separate two-bit priority sideband is stored and forwarded with each
// flit. Priority arbitration is optional and disabled by default.
//
// The router only routes one-flit packets in this first version. It does not
// create a network, calculate coordinates, or assemble multi-flit packets.
module router_5port #(
    parameter int FLIT_WIDTH = noc_pkg::FLIT_WIDTH,
    parameter int FIFO_DEPTH = noc_pkg::FIFO_DEPTH,
    parameter bit ENABLE_TF_PCR = 1'b0,
    parameter bit ENABLE_PRIORITY = 1'b0,
    parameter int PRIORITY_AGE_LIMIT = 16,
    parameter int WAIT_COUNTER_WIDTH = 8,
    parameter int BLOCKED_COUNTER_WIDTH = 8,
    parameter int WINDOW_CYCLES = 16,
    parameter int TIME_SCORE_SATURATION = 16,
    parameter int FREQ_SCORE_SATURATION = 8,
    parameter int TIME_WEIGHT = 3,
    parameter int FREQ_WEIGHT = 1,
    parameter logic [7:0] SCORE_THRESHOLD = 8'd128
) (
    input  logic clk,
    input  logic rst_n,

    // Upstream ready/valid interface for all five input ports.
    // Input i accepts a flit on a rising edge when in_valid[i] and
    // in_ready[i] are both high.
    input  logic [noc_pkg::NUM_PORTS-1:0] in_valid,
    output logic [noc_pkg::NUM_PORTS-1:0] in_ready,
    input  logic [noc_pkg::NUM_PORTS-1:0][FLIT_WIDTH-1:0] in_flit,
    input  logic [noc_pkg::NUM_PORTS-1:0][1:0] in_priority,

    // Downstream ready/valid interface for all five output ports.
    // Output o transfers its flit on a rising edge when out_valid[o] and
    // out_ready[o] are both high.
    output logic [noc_pkg::NUM_PORTS-1:0] out_valid,
    input  logic [noc_pkg::NUM_PORTS-1:0] out_ready,
    output logic [noc_pkg::NUM_PORTS-1:0][FLIT_WIDTH-1:0] out_flit,
    output logic [noc_pkg::NUM_PORTS-1:0][1:0] out_priority,

    // One-cycle status pulse for each input whose invalid destination was
    // removed. Legal destinations are 0 through 4; codes 5 through 7 are bad.
    output logic [noc_pkg::NUM_PORTS-1:0] invalid_flit_dropped,

    // Optional observations used by mesh-level routing and detector studies.
    output logic [noc_pkg::NUM_PORTS-1:0][($clog2(FIFO_DEPTH)+1)-1:0]
        input_occupancy,
    output logic [noc_pkg::NUM_PORTS-1:0][7:0] congestion_score_out,
    output logic [noc_pkg::NUM_PORTS-1:0] congestion_predicted_out,
    output logic [noc_pkg::NUM_PORTS*noc_pkg::NUM_PORTS-1:0]
        output_request_matrix
);

    localparam int NUMPORTS = noc_pkg::NUM_PORTS;
    localparam int INDEXWIDTH = (NUMPORTS > 1) ? $clog2(NUMPORTS) : 1;
    localparam int COUNTWIDTH = $clog2(FIFO_DEPTH) + 1;

    // Signals between the five input FIFOs and the allocator/crossbar.
    logic [NUMPORTS-1:0] buffer_valid;
    logic [NUMPORTS-1:0] buffer_pop;
    logic [NUMPORTS-1:0][FLIT_WIDTH-1:0] buffer_flit;
    logic [NUMPORTS-1:0][1:0] buffer_priority;
    logic [NUMPORTS-1:0][FLIT_WIDTH+1:0] buffer_word;
    logic [NUMPORTS-1:0] invalid_head;

    // The allocator produces a grant for every output. Grant bit
    // (o * NUM_PORTS + i) means input FIFO i has permission to drive output o.
    logic [NUMPORTS*NUMPORTS-1:0] grant;
    logic [NUMPORTS-1:0] grant_valid;
    logic [NUMPORTS-1:0][INDEXWIDTH-1:0] grant_index;
    logic [NUMPORTS*NUMPORTS-1:0][WAIT_COUNTER_WIDTH-1:0]
        requester_wait_cycles;
    logic [NUMPORTS-1:0][BLOCKED_COUNTER_WIDTH-1:0] output_blocked_cycles;
    logic [NUMPORTS-1:0][7:0] time_score;
    logic [NUMPORTS-1:0][7:0] frequency_score;
    logic [NUMPORTS-1:0][7:0] congestion_score;
    logic [NUMPORTS-1:0] congestion_predicted;

    // Transfer and removal signals from the crossbar.
    logic [NUMPORTS-1:0] crossbar_pop;

    // ---------------------------------------------------------------------
    // Input buffers
    // ---------------------------------------------------------------------
    // Generate the same small FIFO wrapper once for each router input.
    for (genvar input_port = 0; input_port < NUMPORTS; input_port++) begin : g_input_buffers
        input_buffer #(
            .DATA_WIDTH(FLIT_WIDTH + 2),
            .FIFO_DEPTH(FIFO_DEPTH),
            .COUNT_WIDTH(COUNTWIDTH)
        ) buffer (
            .clk       (clk),
            .rst_n     (rst_n),

            // External traffic writes this input's FIFO.
            .in_valid  (in_valid[input_port]),
            .in_ready  (in_ready[input_port]),
            .in_data   ({in_priority[input_port], in_flit[input_port]}),

            // The allocator sees the oldest buffered flit. The combined pop
            // removes it after a successful transfer or an invalid drop.
            .out_valid (buffer_valid[input_port]),
            .pop       (buffer_pop[input_port]),
            .out_data  (buffer_word[input_port]),
            .occupancy (input_occupancy[input_port])
        );

        assign buffer_flit[input_port] =
            buffer_word[input_port][FLIT_WIDTH-1:0];
        assign buffer_priority[input_port] =
            buffer_word[input_port][FLIT_WIDTH+1:FLIT_WIDTH];
    end

    // A normal flit is popped only after an output handshake. An invalid
    // destination is popped immediately, otherwise it would block all later
    // flits in that input FIFO. These two cases are mutually exclusive.
    assign buffer_pop = crossbar_pop | invalid_head;

    // ---------------------------------------------------------------------
    // Switch allocator
    // ---------------------------------------------------------------------
    // The allocator reads FIFO head destinations, builds requests, and asks
    // one round-robin arbiter per output to pick a requesting input.
    switch_allocator #(
        .NUM_PORTS  (NUMPORTS),
        .FLIT_WIDTH (FLIT_WIDTH),
        .INDEX_WIDTH(INDEXWIDTH),
        .ENABLE_TF_PCR(ENABLE_TF_PCR),
        .ENABLE_PRIORITY(ENABLE_PRIORITY),
        .PRIORITY_AGE_LIMIT(PRIORITY_AGE_LIMIT),
        .WAIT_COUNTER_WIDTH(WAIT_COUNTER_WIDTH),
        .BLOCKED_COUNTER_WIDTH(BLOCKED_COUNTER_WIDTH),
        .WINDOW_CYCLES(WINDOW_CYCLES),
        .TIME_SCORE_SATURATION(TIME_SCORE_SATURATION),
        .FREQ_SCORE_SATURATION(FREQ_SCORE_SATURATION),
        .TIME_WEIGHT(TIME_WEIGHT),
        .FREQ_WEIGHT(FREQ_WEIGHT),
        .SCORE_THRESHOLD(SCORE_THRESHOLD)
    ) allocator (
        .clk          (clk),
        .rst_n        (rst_n),
        .input_valid  (buffer_valid),
        .input_flit   (buffer_flit),
        .input_priority(buffer_priority),
        .output_ready (out_ready),
        .grant        (grant),
        .grant_valid  (grant_valid),
        .grant_index  (grant_index),
        .invalid_input(invalid_head),
        .requester_wait_cycles(requester_wait_cycles),
        .output_blocked_cycles(output_blocked_cycles),
        .time_score(time_score),
        .frequency_score(frequency_score),
        .congestion_score(congestion_score),
        .congestion_predicted(congestion_predicted),
        .request_matrix(output_request_matrix)
    );
    assign congestion_score_out = congestion_score;
    assign congestion_predicted_out = congestion_predicted;

    // ---------------------------------------------------------------------
    // Crossbar
    // ---------------------------------------------------------------------
    // The crossbar uses the grant matrix to copy selected FIFO heads to the
    // public outputs, and pops a FIFO only when that output is ready.
    crossbar #(
        .NUM_PORTS (NUMPORTS),
        .FLIT_WIDTH(FLIT_WIDTH)
    ) data_switch (
        .input_flit (buffer_flit),
        .input_priority(buffer_priority),
        .grant      (grant),
        .grant_valid(grant_valid),
        .output_ready(out_ready),
        .output_valid(out_valid),
        .output_flit(out_flit),
        .output_priority(out_priority),
        .input_pop  (crossbar_pop)
    );

    // Convert the allocator's combinational invalid-head indication into a
    // clean one-clock status pulse for the router's outside world.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            invalid_flit_dropped <= '0;
        else
            invalid_flit_dropped <= invalid_head;
    end

    initial begin
        if (NUMPORTS != 5)
            $fatal(1, "router_5port requires exactly five ports");
        if (FLIT_WIDTH < 3)
            $fatal(1, "FLIT_WIDTH must be at least three bits");
        if (FIFO_DEPTH < 1)
            $fatal(1, "FIFO_DEPTH must be at least one");
    end

endmodule
