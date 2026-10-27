// Bounded per-output temporal and event-rate features for predictive routing.
// Requester-cycles count eligible FIFO-head requests, not packet arrivals.
module tf_feature_extractor #(
    parameter int NUM_PORTS = noc_pkg::NUM_PORTS,
    parameter int WINDOW_CYCLES = 8,
    parameter int REQUESTER_COUNT_WIDTH = 3,
    parameter int HISTORY_DEPTH = 4,
    parameter int BUFFER_OCCUPANCY_WIDTH = 2
) (
    input  logic clk,
    input  logic rst_n,
    input  logic [NUM_PORTS*NUM_PORTS-1:0] request,
    input  logic [NUM_PORTS-1:0] output_transfer,
    input  logic [NUM_PORTS-1:0][BUFFER_OCCUPANCY_WIDTH-1:0]
        downstream_occupancy,

    output logic [NUM_PORTS-1:0][REQUESTER_COUNT_WIDTH-1:0]
        requester_count,
    output logic [NUM_PORTS-1:0][3:0] blocked_streak,
    output logic [NUM_PORTS-1:0][1:0] pressure_trend,
    output logic [NUM_PORTS-1:0][$clog2(WINDOW_CYCLES*NUM_PORTS+1)-1:0]
        requester_cycles,
    output logic [NUM_PORTS-1:0][$clog2(WINDOW_CYCLES+1)-1:0]
        demand_active_cycles,
    output logic [NUM_PORTS-1:0][$clog2(WINDOW_CYCLES+1)-1:0]
        service_cycles,
    output logic [NUM_PORTS-1:0][$clog2(WINDOW_CYCLES*NUM_PORTS+1)-1:0]
        service_deficit,
    output logic [NUM_PORTS-1:0][BUFFER_OCCUPANCY_WIDTH-1:0]
        downstream_occupancy_current,
    output logic [NUM_PORTS-1:0][BUFFER_OCCUPANCY_WIDTH-1:0]
        downstream_occupancy_max,
    output logic [NUM_PORTS-1:0] downstream_occupancy_rising,
    output logic [NUM_PORTS-1:0] feature_valid
);

    localparam int REQUESTER_CYCLE_WIDTH =
        (WINDOW_CYCLES * NUM_PORTS > 1) ?
        $clog2(WINDOW_CYCLES * NUM_PORTS + 1) : 1;
    localparam int WINDOW_COUNT_WIDTH =
        (WINDOW_CYCLES > 1) ? $clog2(WINDOW_CYCLES + 1) : 1;
    localparam int WINDOW_INDEX_WIDTH =
        (WINDOW_CYCLES > 1) ? $clog2(WINDOW_CYCLES) : 1;
    localparam int HISTORY_COUNT_WIDTH =
        (HISTORY_DEPTH > 1) ? $clog2(HISTORY_DEPTH + 1) : 1;

    logic [WINDOW_INDEX_WIDTH-1:0] window_cycle;
    logic [NUM_PORTS-1:0][REQUESTER_CYCLE_WIDTH-1:0] requester_accumulator;
    logic [NUM_PORTS-1:0][WINDOW_COUNT_WIDTH-1:0] demand_accumulator;
    logic [NUM_PORTS-1:0][WINDOW_COUNT_WIDTH-1:0] service_accumulator;
    logic [NUM_PORTS-1:0][REQUESTER_CYCLE_WIDTH-1:0] requester_cycle_snapshot;
    logic [NUM_PORTS-1:0][WINDOW_COUNT_WIDTH-1:0] demand_cycle_snapshot;
    logic [NUM_PORTS-1:0][WINDOW_COUNT_WIDTH-1:0] service_cycle_snapshot;
    logic [NUM_PORTS-1:0][3:0] blocked_streak_state;
    logic [NUM_PORTS-1:0][REQUESTER_COUNT_WIDTH-1:0]
        pressure_history [0:HISTORY_DEPTH-1];
    logic [NUM_PORTS-1:0][BUFFER_OCCUPANCY_WIDTH-1:0]
        occupancy_history [0:HISTORY_DEPTH-1];
    logic [NUM_PORTS-1:0][HISTORY_COUNT_WIDTH-1:0] history_sample_count;
    logic window_valid;

    always_comb begin : p_current_features
        requester_count = '0;
        blocked_streak = blocked_streak_state;
        pressure_trend = '0;
        requester_cycles = requester_cycle_snapshot;
        demand_active_cycles = demand_cycle_snapshot;
        service_cycles = service_cycle_snapshot;
        service_deficit = '0;
        downstream_occupancy_current = downstream_occupancy;
        downstream_occupancy_max = downstream_occupancy;
        downstream_occupancy_rising = '0;
        feature_valid = '0;

        for (int output_port = 0; output_port < NUM_PORTS; output_port++) begin
            for (int input_port = 0; input_port < NUM_PORTS; input_port++) begin
                requester_count[output_port] = requester_count[output_port] +
                    request[output_port * NUM_PORTS + input_port];
            end

            if (window_valid && history_sample_count[output_port] >= HISTORY_DEPTH)
                feature_valid[output_port] = 1'b1;

            if (history_sample_count[output_port] >= HISTORY_DEPTH) begin
                if (requester_count[output_port] >
                    pressure_history[HISTORY_DEPTH-1][output_port])
                    pressure_trend[output_port] = 2'd1;
                else if (requester_count[output_port] <
                    pressure_history[HISTORY_DEPTH-1][output_port])
                    pressure_trend[output_port] = 2'd2;
            end

            if (requester_cycle_snapshot[output_port] > service_cycle_snapshot[output_port])
                service_deficit[output_port] =
                    requester_cycle_snapshot[output_port] - service_cycle_snapshot[output_port];

            if (history_sample_count[output_port] != 0 &&
                downstream_occupancy[output_port] > occupancy_history[0][output_port])
                downstream_occupancy_rising[output_port] = 1'b1;

            for (int sample = 0; sample < HISTORY_DEPTH; sample++) begin
                if (occupancy_history[sample][output_port] >
                    downstream_occupancy_max[output_port])
                    downstream_occupancy_max[output_port] =
                        occupancy_history[sample][output_port];
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin : p_feature_history
        logic [REQUESTER_CYCLE_WIDTH-1:0] next_requester_count;
        logic [WINDOW_COUNT_WIDTH-1:0] next_demand_count;
        logic [WINDOW_COUNT_WIDTH-1:0] next_service_count;
        logic any_request;

        if (!rst_n) begin
            window_cycle <= '0;
            requester_accumulator <= '0;
            demand_accumulator <= '0;
            service_accumulator <= '0;
            requester_cycle_snapshot <= '0;
            demand_cycle_snapshot <= '0;
            service_cycle_snapshot <= '0;
            blocked_streak_state <= '0;
            history_sample_count <= '0;
            window_valid <= 1'b0;
            for (int sample = 0; sample < HISTORY_DEPTH; sample++)
                begin
                    pressure_history[sample] <= '0;
                    occupancy_history[sample] <= '0;
                end
        end else begin
            if (window_cycle == WINDOW_CYCLES - 1)
                window_cycle <= '0;
            else
                window_cycle <= window_cycle + 1'b1;

            for (int output_port = 0; output_port < NUM_PORTS; output_port++) begin
                any_request = |request[output_port * NUM_PORTS +: NUM_PORTS];

                if (any_request && !output_transfer[output_port]) begin
                    if (&blocked_streak_state[output_port])
                        blocked_streak_state[output_port] <= blocked_streak_state[output_port];
                    else
                        blocked_streak_state[output_port] <=
                            blocked_streak_state[output_port] + 1'b1;
                end else begin
                    blocked_streak_state[output_port] <= '0;
                end

                for (int sample = HISTORY_DEPTH-1; sample > 0; sample--)
                    pressure_history[sample][output_port] <=
                        pressure_history[sample-1][output_port];
                pressure_history[0][output_port] <= requester_count[output_port];
                occupancy_history[0][output_port] <= downstream_occupancy[output_port];
                for (int sample = HISTORY_DEPTH-1; sample > 0; sample--)
                    occupancy_history[sample][output_port] <=
                        occupancy_history[sample-1][output_port];
                if (history_sample_count[output_port] < HISTORY_DEPTH)
                    history_sample_count[output_port] <=
                        history_sample_count[output_port] + 1'b1;

                next_requester_count = requester_accumulator[output_port] +
                    requester_count[output_port];
                next_demand_count = demand_accumulator[output_port] + any_request;
                next_service_count = service_accumulator[output_port] +
                    output_transfer[output_port];

                if (window_cycle == WINDOW_CYCLES - 1) begin
                    requester_cycle_snapshot[output_port] <= next_requester_count;
                    demand_cycle_snapshot[output_port] <= next_demand_count;
                    service_cycle_snapshot[output_port] <= next_service_count;
                    requester_accumulator[output_port] <= '0;
                    demand_accumulator[output_port] <= '0;
                    service_accumulator[output_port] <= '0;
                    window_valid <= 1'b1;
                end else begin
                    requester_accumulator[output_port] <= next_requester_count;
                    demand_accumulator[output_port] <= next_demand_count;
                    service_accumulator[output_port] <= next_service_count;
                end
            end
        end
    end

    initial begin
        if (NUM_PORTS < 1)
            $fatal(1, "tf_feature_extractor requires at least one port");
        if (WINDOW_CYCLES < 1)
            $fatal(1, "tf_feature_extractor WINDOW_CYCLES must be positive");
        if (HISTORY_DEPTH < 1)
            $fatal(1, "tf_feature_extractor HISTORY_DEPTH must be positive");
        if ((1 << REQUESTER_COUNT_WIDTH) <= NUM_PORTS)
            $fatal(1, "REQUESTER_COUNT_WIDTH cannot represent NUM_PORTS");
    end

endmodule
