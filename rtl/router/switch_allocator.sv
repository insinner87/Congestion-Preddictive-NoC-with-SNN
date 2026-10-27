// Switch allocator for a five-port router.
//
// Inputs to the allocator are the five FIFO head flits. The allocator looks
// at each flit's destination and creates one request for the matching output.
// It then uses one arbiter per output to choose which input gets that output
// in the current cycle. Optional priority mode prefers higher classes while
// retaining round-robin ties and aging for waiting requesters.
//
// This block does not move the flit data. It only decides who is allowed to
// use each output. crossbar.sv uses the resulting one-hot grant matrix to move
// data from the selected input FIFO to the selected output.
module switch_allocator #(
    parameter int NUM_PORTS = noc_pkg::NUM_PORTS,
    parameter int FLIT_WIDTH = noc_pkg::FLIT_WIDTH,
    parameter int DEST_WIDTH = 3,
    parameter int INDEX_WIDTH = (NUM_PORTS > 1) ? $clog2(NUM_PORTS) : 1,
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
    input  logic                              clk,
    input  logic                              rst_n,

    // Head flit and valid bit from each input FIFO.
    input  logic [NUM_PORTS-1:0]              input_valid,
    input  logic [NUM_PORTS-1:0][FLIT_WIDTH-1:0] input_flit,
    // Priority sideband remains aligned with the head flit in each FIFO.
    input  logic [NUM_PORTS-1:0][1:0]          input_priority,

    // Downstream readiness is used by each arbiter to know when its grant
    // actually transferred, and whether it must keep a grant locked.
    input  logic [NUM_PORTS-1:0]              output_ready,

    // A flattened grant bit at (o * NUM_PORTS + i) is high when input i has
    // been selected to drive output o.
    output logic [NUM_PORTS*NUM_PORTS-1:0]     grant,
    output logic [NUM_PORTS-1:0]              grant_valid,
    output logic [NUM_PORTS-1:0][INDEX_WIDTH-1:0] grant_index,

    // A destination value 5, 6, or 7 is not a port in this five-port router.
    // Those FIFO heads are flagged so the top-level router can discard them.
    output logic [NUM_PORTS-1:0]              invalid_input,

    // Diagnostic congestion state; routing remains destination-fixed.
    output logic [NUM_PORTS*NUM_PORTS-1:0][WAIT_COUNTER_WIDTH-1:0]
        requester_wait_cycles,
    output logic [NUM_PORTS-1:0][BLOCKED_COUNTER_WIDTH-1:0]
        output_blocked_cycles,
    output logic [NUM_PORTS-1:0][7:0] time_score,
    output logic [NUM_PORTS-1:0][7:0] frequency_score,
    output logic [NUM_PORTS-1:0][7:0] congestion_score,
    output logic [NUM_PORTS-1:0] congestion_predicted,
    output logic [NUM_PORTS*NUM_PORTS-1:0] request_matrix
);

    // Requests are organized by output in one flat vector:
    //   request[output_port * NUM_PORTS + input_port]
    // A bit is asserted only when that input has a valid flit for that output.
    logic [NUM_PORTS*NUM_PORTS-1:0] request;
    logic [NUM_PORTS-1:0] output_transfer;
    logic [NUM_PORTS-1:0][(WINDOW_CYCLES * NUM_PORTS > 1 ?
        $clog2(WINDOW_CYCLES * NUM_PORTS + 1) : 1)-1:0]
        last_window_request_count;
    logic [NUM_PORTS-1:0][(WINDOW_CYCLES > 1 ?
        $clog2(WINDOW_CYCLES + 1) : 1)-1:0]
        last_window_transfer_count;
    logic [NUM_PORTS-1:0][(WINDOW_CYCLES * NUM_PORTS > 1 ?
        $clog2(WINDOW_CYCLES * NUM_PORTS + 1) : 1)-1:0]
        last_window_service_deficit;
    assign request_matrix = request;

    // Decode each input head once. The flit is passed through without
    // modification; only these top bits are used for route selection.
    always_comb begin : p_decode_destinations
        logic [DEST_WIDTH-1:0] destination;

        request = '0;
        invalid_input = '0;

        for (int input_port = 0; input_port < NUM_PORTS; input_port++) begin
            destination = input_flit[input_port] >> (FLIT_WIDTH - DEST_WIDTH);

            if (input_valid[input_port]) begin
                if (destination < NUM_PORTS) begin
                    // One flit has one destination, therefore one input can
                    // request at most one output at a time.
                    request[destination * NUM_PORTS + input_port] = 1'b1;
                end else begin
                    // Let the router pop and report bad routing codes. If the
                    // invalid flit stayed in front, it would block that FIFO.
                    invalid_input[input_port] = 1'b1;
                end

            end
        end
    end

    // A grant is counted as service only when the public ready/valid
    // handshake can complete on the current edge.
    assign output_transfer = grant_valid & output_ready;

    generate
        if (ENABLE_TF_PCR) begin : g_congestion_monitor
            congestion_monitor #(
                .NUM_PORTS(NUM_PORTS),
                .INDEX_WIDTH(INDEX_WIDTH),
                .WAIT_COUNTER_WIDTH(WAIT_COUNTER_WIDTH),
                .BLOCKED_COUNTER_WIDTH(BLOCKED_COUNTER_WIDTH),
                .WINDOW_CYCLES(WINDOW_CYCLES)
            ) monitor (
                .clk                         (clk),
                .rst_n                       (rst_n),
                .request                     (request),
                .output_transfer             (output_transfer),
                .grant_index                 (grant_index),
                .requester_wait_cycles       (requester_wait_cycles),
                .output_blocked_cycles       (output_blocked_cycles),
                .last_window_request_count   (last_window_request_count),
                .last_window_transfer_count  (last_window_transfer_count),
                .last_window_service_deficit (last_window_service_deficit)
            );

            congestion_estimator #(
                .NUM_PORTS(NUM_PORTS),
                .WAIT_COUNTER_WIDTH(WAIT_COUNTER_WIDTH),
                .BLOCKED_COUNTER_WIDTH(BLOCKED_COUNTER_WIDTH),
                .REQUEST_COUNT_WIDTH(WINDOW_CYCLES * NUM_PORTS > 1 ?
                    $clog2(WINDOW_CYCLES * NUM_PORTS + 1) : 1),
                .TIME_SCORE_SATURATION(TIME_SCORE_SATURATION),
                .FREQ_SCORE_SATURATION(FREQ_SCORE_SATURATION),
                .TIME_WEIGHT(TIME_WEIGHT),
                .FREQ_WEIGHT(FREQ_WEIGHT),
                .SCORE_THRESHOLD(SCORE_THRESHOLD)
            ) estimator (
                .requester_wait_cycles (requester_wait_cycles),
                .output_blocked_cycles (output_blocked_cycles),
                .service_deficit       (last_window_service_deficit),
                .time_score            (time_score),
                .frequency_score       (frequency_score),
                .congestion_score      (congestion_score),
                .congestion_predicted  (congestion_predicted)
            );
        end else begin : g_congestion_disabled
            assign last_window_request_count = '0;
            assign last_window_transfer_count = '0;
            assign last_window_service_deficit = '0;
            assign requester_wait_cycles = '0;
            assign output_blocked_cycles = '0;
            assign time_score = '0;
            assign frequency_score = '0;
            assign congestion_score = '0;
            assign congestion_predicted = '0;
        end
    endgenerate

    // Every output arbitrates independently. This permits parallel transfers
    // between different input/output pairs during the same clock cycle.
    for (genvar output_port = 0; output_port < NUM_PORTS; output_port++) begin : g_output_arbiters
        round_robin_arbiter #(
            .NUM_REQUESTERS(NUM_PORTS),
            .INDEX_WIDTH(INDEX_WIDTH),
            .ENABLE_PRIORITY(ENABLE_PRIORITY),
            .AGE_LIMIT(PRIORITY_AGE_LIMIT)
        ) arbiter (
            .clk          (clk),
            .rst_n        (rst_n),
            .request      (request[output_port * NUM_PORTS +: NUM_PORTS]),
            .request_priority(input_priority),
            .ready        (output_ready[output_port]),
            .grant_onehot (grant[output_port * NUM_PORTS +: NUM_PORTS]),
            .grant_valid  (grant_valid[output_port]),
            .grant_index  (grant_index[output_port])
        );
    end

    initial begin
        if (NUM_PORTS != 5)
            $fatal(1, "switch_allocator currently supports exactly five ports");
        if (FLIT_WIDTH < DEST_WIDTH)
            $fatal(1, "FLIT_WIDTH must contain the destination field");
    end

endmodule
