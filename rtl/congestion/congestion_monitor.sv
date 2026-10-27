// Per-output congestion measurements for the five-port switch allocator.
//
// Request counters measure eligible requester-cycles, not unique packet
// arrivals. Transfer counters use the allocator's real ready/valid handshake.
module congestion_monitor #(
    parameter int NUM_PORTS = noc_pkg::NUM_PORTS,
    parameter int INDEX_WIDTH = (NUM_PORTS > 1) ? $clog2(NUM_PORTS) : 1,
    parameter int WAIT_COUNTER_WIDTH = 8,
    parameter int BLOCKED_COUNTER_WIDTH = 8,
    parameter int WINDOW_CYCLES = 16,
    parameter int REQUEST_COUNT_WIDTH =
        (WINDOW_CYCLES * NUM_PORTS > 1) ?
        $clog2(WINDOW_CYCLES * NUM_PORTS + 1) : 1,
    parameter int TRANSFER_COUNT_WIDTH =
        (WINDOW_CYCLES > 1) ? $clog2(WINDOW_CYCLES + 1) : 1
) (
    input  logic clk,
    input  logic rst_n,
    input  logic [NUM_PORTS*NUM_PORTS-1:0] request,
    input  logic [NUM_PORTS-1:0] output_transfer,
    input  logic [NUM_PORTS-1:0][INDEX_WIDTH-1:0] grant_index,

    output logic [NUM_PORTS*NUM_PORTS-1:0][WAIT_COUNTER_WIDTH-1:0]
        requester_wait_cycles,
    output logic [NUM_PORTS-1:0][BLOCKED_COUNTER_WIDTH-1:0]
        output_blocked_cycles,
    output logic [NUM_PORTS-1:0][REQUEST_COUNT_WIDTH-1:0]
        last_window_request_count,
    output logic [NUM_PORTS-1:0][TRANSFER_COUNT_WIDTH-1:0]
        last_window_transfer_count,
    output logic [NUM_PORTS-1:0][REQUEST_COUNT_WIDTH-1:0]
        last_window_service_deficit
);

    localparam int WINDOW_COUNTER_WIDTH =
        (WINDOW_CYCLES > 1) ? $clog2(WINDOW_CYCLES) : 1;

    logic [WINDOW_COUNTER_WIDTH-1:0] window_cycle;
    logic [NUM_PORTS-1:0][REQUEST_COUNT_WIDTH-1:0] window_request_count;
    logic [NUM_PORTS-1:0][TRANSFER_COUNT_WIDTH-1:0] window_transfer_count;

    always_ff @(posedge clk or negedge rst_n) begin : p_update_metrics
        int unsigned active_requesters;
        logic [REQUEST_COUNT_WIDTH-1:0] request_count_next;
        logic [TRANSFER_COUNT_WIDTH-1:0] transfer_count_next;

        if (!rst_n) begin
            window_cycle <= '0;
            window_request_count <= '0;
            window_transfer_count <= '0;
            requester_wait_cycles <= '0;
            output_blocked_cycles <= '0;
            last_window_request_count <= '0;
            last_window_transfer_count <= '0;
            last_window_service_deficit <= '0;
        end else begin
            if (window_cycle == WINDOW_CYCLES - 1)
                window_cycle <= '0;
            else
                window_cycle <= window_cycle + 1'b1;

            for (int output_port = 0; output_port < NUM_PORTS; output_port++) begin
                active_requesters = 0;

                for (int input_port = 0; input_port < NUM_PORTS; input_port++) begin
                    if (request[output_port * NUM_PORTS + input_port]) begin
                        active_requesters++;

                        if (output_transfer[output_port] &&
                            grant_index[output_port] == input_port) begin
                            requester_wait_cycles[output_port * NUM_PORTS + input_port] <= '0;
                        end else if (&requester_wait_cycles[output_port * NUM_PORTS + input_port]) begin
                            requester_wait_cycles[output_port * NUM_PORTS + input_port] <=
                                requester_wait_cycles[output_port * NUM_PORTS + input_port];
                        end else begin
                            requester_wait_cycles[output_port * NUM_PORTS + input_port] <=
                                requester_wait_cycles[output_port * NUM_PORTS + input_port] + 1'b1;
                        end
                    end else begin
                        requester_wait_cycles[output_port * NUM_PORTS + input_port] <= '0;
                    end
                end

                if (|request[output_port * NUM_PORTS +: NUM_PORTS] &&
                    !output_transfer[output_port]) begin
                    if (&output_blocked_cycles[output_port])
                        output_blocked_cycles[output_port] <=
                            output_blocked_cycles[output_port];
                    else
                        output_blocked_cycles[output_port] <=
                            output_blocked_cycles[output_port] + 1'b1;
                end else begin
                    output_blocked_cycles[output_port] <= '0;
                end

                request_count_next =
                    window_request_count[output_port] + active_requesters;
                transfer_count_next =
                    window_transfer_count[output_port] + output_transfer[output_port];

                if (window_cycle == WINDOW_CYCLES - 1) begin
                    last_window_request_count[output_port] <= request_count_next;
                    last_window_transfer_count[output_port] <= transfer_count_next;
                    if (request_count_next > transfer_count_next)
                        last_window_service_deficit[output_port] <=
                            request_count_next - transfer_count_next;
                    else
                        last_window_service_deficit[output_port] <= '0;
                    window_request_count[output_port] <= '0;
                    window_transfer_count[output_port] <= '0;
                end else begin
                    window_request_count[output_port] <= request_count_next;
                    window_transfer_count[output_port] <= transfer_count_next;
                end
            end
        end
    end

    initial begin
        if (NUM_PORTS < 1)
            $fatal(1, "congestion_monitor requires at least one port");
        if (WINDOW_CYCLES < 1)
            $fatal(1, "WINDOW_CYCLES must be at least one");
        if (WAIT_COUNTER_WIDTH < 1 || BLOCKED_COUNTER_WIDTH < 1)
            $fatal(1, "congestion counter widths must be at least one");
    end

endmodule
