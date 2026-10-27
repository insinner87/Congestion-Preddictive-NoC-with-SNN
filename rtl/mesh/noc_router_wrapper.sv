// Mesh adapter around the existing five-port router.
//
// Mesh flits use [63:61] as the current-hop output code, [60:59] as
// destination X, [58:57] as destination Y, and [56:0] as opaque payload.
// The adapter rewrites only the hop code when accepting a flit at each router.
module noc_router_wrapper #(
    parameter int FLIT_WIDTH = 64,
    parameter int FIFO_DEPTH = noc_pkg::FIFO_DEPTH,
    parameter int ROUTING_MODE = 0,
    parameter bit ENABLE_TF_PCR = 1'b1,
    parameter bit ENABLE_PRIORITY = 1'b0,
    parameter int PRIORITY_AGE_LIMIT = 16,
    parameter bit ENABLE_SNN = 1'b0,
    parameter bit ENABLE_SNN_ROUTING = ENABLE_SNN,
    parameter bit ENABLE_EQUATION_ROUTING = 1'b0,
    parameter bit ENABLE_ADAPTIVE_PREDICTOR = 1'b0,
    parameter int SNN_VALIDATION_ACCURACY_PERCENT = 0,
    parameter int SNN_VALIDATION_CORRECT_SAMPLES = 0,
    parameter int SNN_VALIDATION_TOTAL_SAMPLES = 0,
    parameter int ADAPTIVE_ONLINE_WINDOW = 64,
    parameter int ADAPTIVE_MIN_ONLINE_SAMPLES = 32,
    parameter bit ENABLE_ADAPTIVE_BUFFER = 1'b0,
    parameter bit ENABLE_OFFLOAD = 1'b0,
    parameter int WINDOW_CYCLES = 16,
    parameter int WAIT_COUNTER_WIDTH = 8,
    parameter int BLOCKED_COUNTER_WIDTH = 8,
    parameter int OCCUPANCY_THRESHOLD = 3,
    parameter int OUTPUT_BUFFER_DEPTH = 2,
    parameter int OUTPUT_BUFFER_OCCUPANCY_WIDTH = 2,
    parameter int TIME_SCORE_SATURATION = 16,
    parameter int FREQ_SCORE_SATURATION = 8,
    parameter int TIME_WEIGHT = 3,
    parameter int FREQ_WEIGHT = 1,
    parameter logic [7:0] SCORE_THRESHOLD = 8'd128
) (
    input logic clk,
    input logic rst_n,
    input logic [1:0] coordinate_x,
    input logic [1:0] coordinate_y,
    input logic [noc_pkg::NUM_PORTS-1:0] in_valid,
    output logic [noc_pkg::NUM_PORTS-1:0] in_ready,
    input logic [noc_pkg::NUM_PORTS-1:0][FLIT_WIDTH-1:0] in_flit,
    input logic [noc_pkg::NUM_PORTS-1:0][1:0] in_priority,
    output logic [noc_pkg::NUM_PORTS-1:0] out_valid,
    input logic [noc_pkg::NUM_PORTS-1:0] out_ready,
    output logic [noc_pkg::NUM_PORTS-1:0][FLIT_WIDTH-1:0] out_flit,
    output logic [noc_pkg::NUM_PORTS-1:0][1:0] out_priority,
    input logic [noc_pkg::NUM_PORTS-1:0][OUTPUT_BUFFER_OCCUPANCY_WIDTH-1:0]
        output_buffer_occupancy,
    output logic [noc_pkg::NUM_PORTS-1:0][7:0] congestion_score,
    output logic [noc_pkg::NUM_PORTS-1:0] congestion_predicted,
    output logic [noc_pkg::NUM_PORTS-1:0] occupancy_predicted,
    output logic [noc_pkg::NUM_PORTS-1:0][($clog2(FIFO_DEPTH)+1)-1:0]
        input_occupancy
);

    localparam int NUM_PORTS = noc_pkg::NUM_PORTS;
    localparam int ROUTE_WIDTH = 3;

    logic [NUM_PORTS-1:0][FLIT_WIDTH-1:0] routed_in_flit;
    logic [NUM_PORTS-1:0] router_in_ready;
    logic [NUM_PORTS-1:0][ROUTE_WIDTH-1:0] computed_route;
    logic [NUM_PORTS-1:0][ROUTE_WIDTH-1:0] ingress_route;
    logic [NUM_PORTS-1:0] computed_route_valid;
    logic [NUM_PORTS-1:0] route_locked;
    logic [NUM_PORTS-1:0][ROUTE_WIDTH-1:0] locked_route;
    logic [NUM_PORTS*NUM_PORTS-1:0] output_request_matrix;
    logic [NUM_PORTS-1:0][2:0] tf_requester_count;
    logic [NUM_PORTS-1:0][3:0] tf_blocked_streak;
    logic [NUM_PORTS-1:0][1:0] tf_pressure_trend;
    logic [NUM_PORTS-1:0][5:0] tf_requester_cycles;
    logic [NUM_PORTS-1:0][3:0] tf_demand_active_cycles;
    logic [NUM_PORTS-1:0][3:0] tf_service_cycles;
    logic [NUM_PORTS-1:0][5:0] tf_service_deficit;
    logic [NUM_PORTS-1:0][OUTPUT_BUFFER_OCCUPANCY_WIDTH-1:0]
        tf_output_buffer_occupancy;
    logic [NUM_PORTS-1:0][OUTPUT_BUFFER_OCCUPANCY_WIDTH-1:0]
        tf_output_buffer_occupancy_max;
    logic [NUM_PORTS-1:0] tf_output_buffer_rising;
    logic [NUM_PORTS-1:0] tf_feature_valid;
    logic [NUM_PORTS*7-1:0] tf_encoded_features;
    logic [NUM_PORTS-1:0][1:0] snn_risk_class;
    logic [NUM_PORTS-1:0] snn_output_spike;
    logic [NUM_PORTS-1:0] snn_risk_valid;
    logic [NUM_PORTS-1:0] snn_state_update_enable;
    logic [NUM_PORTS-1:0] snn_binary_prediction;
    logic [NUM_PORTS-1:0] equation_risk;
    logic signed [NUM_PORTS-1:0][11:0] equation_score;
    logic [NUM_PORTS-1:0] adaptive_select_snn;
    logic [NUM_PORTS-1:0] adaptive_selected_prediction;
    logic [NUM_PORTS-1:0][6:0] adaptive_online_accuracy;
    logic [NUM_PORTS-1:0][($clog2(ADAPTIVE_ONLINE_WINDOW + 1))-1:0]
        adaptive_online_samples;
    logic [NUM_PORTS-1:0] adaptive_model_selection_pulse;
    logic [NUM_PORTS-1:0] adaptive_model_switch_pulse;
    logic [NUM_PORTS-1:0][2:0] adaptive_model_switch_reason;
    logic [NUM_PORTS-1:0] actual_congestion_event;
    logic [NUM_PORTS-1:0] offload_active;
    logic [NUM_PORTS-1:0] offload_start_pulse;
    logic [NUM_PORTS-1:0][7:0] route_score;
    logic [NUM_PORTS-1:0] route_risk;
    logic [NUM_PORTS-1:0] output_transfer;
    logic [NUM_PORTS-1:0] input_buffer_pressure;
    logic [NUM_PORTS-1:0] request_buffer_pressure;

    generate
        if (ENABLE_ADAPTIVE_BUFFER) begin : g_adaptive_buffer_pressure
            adaptive_buffer_controller #(
                .NUM_INPUTS(NUM_PORTS),
                .FIFO_DEPTH(FIFO_DEPTH),
                .OCCUPANCY_WIDTH($clog2(FIFO_DEPTH) + 1)
            ) buffer_controller (
                .clk(clk),
                .rst_n(rst_n),
                .occupancy(input_occupancy),
                .buffer_pressure(input_buffer_pressure)
            );
        end else begin : g_adaptive_buffer_bypass
            assign input_buffer_pressure = '0;
        end
    endgenerate

    assign output_transfer = out_valid & out_ready;

    generate
        if (ENABLE_SNN || ENABLE_EQUATION_ROUTING ||
            ENABLE_ADAPTIVE_PREDICTOR) begin : g_predictive_features
            tf_feature_extractor #(
                .NUM_PORTS(NUM_PORTS),
                .WINDOW_CYCLES(8),
                .REQUESTER_COUNT_WIDTH(3),
                .HISTORY_DEPTH(4),
                .BUFFER_OCCUPANCY_WIDTH(OUTPUT_BUFFER_OCCUPANCY_WIDTH)
            ) feature_extractor (
                .clk(clk),
                .rst_n(rst_n),
                .request(output_request_matrix),
                .output_transfer(output_transfer),
                .downstream_occupancy(output_buffer_occupancy),
                .requester_count(tf_requester_count),
                .blocked_streak(tf_blocked_streak),
                .pressure_trend(tf_pressure_trend),
                .requester_cycles(tf_requester_cycles),
                .demand_active_cycles(tf_demand_active_cycles),
                .service_cycles(tf_service_cycles),
                .service_deficit(tf_service_deficit),
                .downstream_occupancy_current(tf_output_buffer_occupancy),
                .downstream_occupancy_max(tf_output_buffer_occupancy_max),
                .downstream_occupancy_rising(tf_output_buffer_rising),
                .feature_valid(tf_feature_valid)
            );

            always_comb begin : p_encode_snn_features
                tf_encoded_features = '0;
                request_buffer_pressure = '0;
                for (int output_port = 0; output_port < NUM_PORTS; output_port++) begin
                    for (int input_port = 0; input_port < NUM_PORTS; input_port++) begin
                        if (output_request_matrix[output_port*NUM_PORTS + input_port] &&
                            input_buffer_pressure[input_port])
                            request_buffer_pressure[output_port] = 1'b1;
                    end
                    tf_encoded_features[output_port*7 +: 7] = {
                        (tf_output_buffer_rising[output_port] ||
                            request_buffer_pressure[output_port]),
                        (tf_output_buffer_occupancy_max[output_port] >=
                            OUTPUT_BUFFER_DEPTH),
                        (tf_output_buffer_occupancy[output_port] >=
                            ((OUTPUT_BUFFER_DEPTH > 1) ? OUTPUT_BUFFER_DEPTH - 1 : 1)),
                        ((tf_demand_active_cycles[output_port] >= 4) &&
                            (tf_service_cycles[output_port] <= 2)),
                        (tf_requester_cycles[output_port] >= 16),
                        (tf_blocked_streak[output_port] >= 5),
                        (tf_blocked_streak[output_port] >= 2)
                    };
                end
            end

            if (ENABLE_SNN || ENABLE_ADAPTIVE_PREDICTOR) begin : g_snn_network
                snn_predictor #(.NUM_PORTS(NUM_PORTS)) predictor (
                    .clk(clk),
                    .rst_n(rst_n),
                    .feature_spikes(tf_encoded_features),
                    .feature_valid(tf_feature_valid),
                    .risk_class(snn_risk_class),
                    .output_spike(snn_output_spike),
                    .risk_valid(snn_risk_valid),
                    .state_update_enable(snn_state_update_enable)
                );
            end else begin : g_snn_network_bypass
                assign snn_risk_class = '0;
                assign snn_output_spike = '0;
                assign snn_risk_valid = '0;
                assign snn_state_update_enable = '0;
            end
        end else begin : g_snn_bypass
            assign tf_requester_count = '0;
            assign tf_blocked_streak = '0;
            assign tf_pressure_trend = '0;
            assign tf_requester_cycles = '0;
            assign tf_demand_active_cycles = '0;
            assign tf_service_cycles = '0;
            assign tf_service_deficit = '0;
            assign tf_feature_valid = '0;
            assign tf_encoded_features = '0;
            assign tf_output_buffer_occupancy = '0;
            assign tf_output_buffer_occupancy_max = '0;
            assign tf_output_buffer_rising = '0;
            assign snn_risk_class = '0;
            assign snn_output_spike = '0;
            assign snn_risk_valid = '0;
            assign snn_state_update_enable = '0;
            assign request_buffer_pressure = '0;
        end
    endgenerate

    always_comb begin : p_actual_congestion_event
        actual_congestion_event = '0;
        for (int output_port = 0; output_port < NUM_PORTS; output_port++) begin
            actual_congestion_event[output_port] =
                (tf_blocked_streak[output_port] >= 4) ||
                ((output_buffer_occupancy[output_port] >= OUTPUT_BUFFER_DEPTH) &&
                    (|output_request_matrix[
                        output_port*NUM_PORTS +: NUM_PORTS]));
        end
    end

    always_comb begin : p_snn_binary_prediction
        for (int output_port = 0; output_port < NUM_PORTS; output_port++)
            snn_binary_prediction[output_port] =
                snn_risk_valid[output_port] && snn_risk_class[output_port] >= 2;
    end

    generate
        if (ENABLE_ADAPTIVE_PREDICTOR) begin : g_adaptive_predictor
            adaptive_predictor_selector #(
                .NUM_PORTS(NUM_PORTS),
                .PREDICTION_HORIZON(8),
                .ONLINE_WINDOW_SIZE(ADAPTIVE_ONLINE_WINDOW),
                .MIN_ONLINE_SAMPLES(ADAPTIVE_MIN_ONLINE_SAMPLES),
                .VALIDATION_ACCURACY_PERCENT(SNN_VALIDATION_ACCURACY_PERCENT),
                .VALIDATION_CORRECT_SAMPLES(SNN_VALIDATION_CORRECT_SAMPLES),
                .VALIDATION_TOTAL_SAMPLES(SNN_VALIDATION_TOTAL_SAMPLES)
            ) selector (
                .clk(clk),
                .rst_n(rst_n),
                .prediction_valid(tf_feature_valid),
                .snn_prediction(snn_binary_prediction),
                .equation_prediction(equation_risk),
                .actual_congestion_event(actual_congestion_event),
                .selected_prediction(adaptive_selected_prediction),
                .select_snn(adaptive_select_snn),
                .online_sample_count(adaptive_online_samples),
                .online_accuracy_percent(adaptive_online_accuracy),
                .model_selection_pulse(adaptive_model_selection_pulse),
                .model_switch_pulse(adaptive_model_switch_pulse),
                .model_switch_reason(adaptive_model_switch_reason)
            );
        end else begin : g_adaptive_predictor_bypass
            assign adaptive_select_snn = '0;
            assign adaptive_selected_prediction = '0;
            assign adaptive_online_accuracy = '0;
            assign adaptive_online_samples = '0;
            assign adaptive_model_selection_pulse = '0;
            assign adaptive_model_switch_pulse = '0;
            assign adaptive_model_switch_reason = '0;
        end
    endgenerate

    generate
        if (ENABLE_SNN && ENABLE_OFFLOAD) begin : g_offload_controller
            congestion_offload_controller #(.NUM_PORTS(NUM_PORTS)) controller (
                .clk(clk),
                .rst_n(rst_n),
                .risk_class(snn_risk_class),
                .risk_valid(snn_risk_valid),
                .offload_active(offload_active),
                .offload_start_pulse(offload_start_pulse)
            );
        end else begin : g_offload_bypass
            assign offload_active = '0;
            assign offload_start_pulse = '0;
        end
    endgenerate

    always_comb begin : p_route_score_select
        route_score = congestion_score;
        route_risk = congestion_predicted;
        if (ENABLE_ADAPTIVE_PREDICTOR) begin
            route_risk = adaptive_selected_prediction;
            for (int output_port = 0; output_port < NUM_PORTS; output_port++) begin
                if (adaptive_select_snn[output_port]) begin
                    case (snn_risk_class[output_port])
                        2'd0: route_score[output_port] = 8'd0;
                        2'd1: route_score[output_port] = 8'd85;
                        2'd2: route_score[output_port] = 8'd170;
                        default: route_score[output_port] = 8'd255;
                    endcase
                end else begin
                    route_score[output_port] =
                        equation_risk[output_port] ? 8'd255 : 8'd0;
                end
            end
        end else if (ENABLE_EQUATION_ROUTING) begin
            for (int output_port = 0; output_port < NUM_PORTS; output_port++) begin
                route_score[output_port] = equation_risk[output_port] ? 8'd255 : 8'd0;
                route_risk[output_port] = equation_risk[output_port];
            end
        end else if (ENABLE_SNN_ROUTING) begin
            for (int output_port = 0; output_port < NUM_PORTS; output_port++) begin
                if (snn_risk_valid[output_port]) begin
                    case (snn_risk_class[output_port])
                        2'd0: route_score[output_port] = 8'd0;
                        2'd1: route_score[output_port] = 8'd85;
                        2'd2: route_score[output_port] = 8'd170;
                        default: route_score[output_port] = 8'd255;
                    endcase
                    if (ENABLE_OFFLOAD)
                        route_risk[output_port] = offload_active[output_port];
                    else
                        route_risk[output_port] = snn_risk_class[output_port] >= 2;
                end else begin
                    route_score[output_port] = 8'd0;
                    route_risk[output_port] = 1'b0;
                end
            end
        end
    end

    generate
        if (ENABLE_EQUATION_ROUTING || ENABLE_ADAPTIVE_PREDICTOR) begin : g_equation_predictor
            distilled_congestion_predictor #(.NUM_PORTS(NUM_PORTS)) predictor (
                .feature_events(tf_encoded_features),
                .feature_valid(tf_feature_valid),
                .congestion_risk(equation_risk),
                .equation_score(equation_score)
            );
        end else begin : g_equation_bypass
            assign equation_risk = '0;
            assign equation_score = '0;
        end
    endgenerate

    for (genvar input_port = 0; input_port < NUM_PORTS; input_port++) begin : g_route_computers
        mesh_route_compute #(
            .ROUTING_MODE(ROUTING_MODE),
            .GRID_SIZE(4),
            .USE_SNN_SCORE(ENABLE_SNN_ROUTING || ENABLE_EQUATION_ROUTING ||
                ENABLE_ADAPTIVE_PREDICTOR)
        ) route_compute (
            .current_x(coordinate_x),
            .current_y(coordinate_y),
            .destination_x(in_flit[input_port][60:59]),
            .destination_y(in_flit[input_port][58:57]),
            .congestion_score(congestion_score),
            .congestion_predicted(congestion_predicted),
            .snn_congestion_score(route_score),
            .snn_congestion_predicted(route_risk),
            .candidate_available(out_ready),
            .score_valid(ENABLE_TF_PCR || ENABLE_SNN_ROUTING ||
                ENABLE_EQUATION_ROUTING || ENABLE_ADAPTIVE_PREDICTOR),
            .selected_port(computed_route[input_port]),
            .legal_ports(),
            .route_valid(computed_route_valid[input_port])
        );
    end

    for (genvar input_port = 0; input_port < NUM_PORTS; input_port++) begin : g_rewrite_next_hop
        always @* begin
            routed_in_flit[input_port] = in_flit[input_port];
            if (route_locked[input_port])
                ingress_route[input_port] = locked_route[input_port];
            else if (computed_route_valid[input_port])
                ingress_route[input_port] = computed_route[input_port];
            else
                ingress_route[input_port] = 3'b111;
            routed_in_flit[input_port][63:61] = ingress_route[input_port];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin : p_lock_route_during_stall
        if (!rst_n) begin
            route_locked <= '0;
            locked_route <= '0;
        end else begin
            for (int input_port = 0; input_port < NUM_PORTS; input_port++) begin
                if (!in_valid[input_port]) begin
                    route_locked[input_port] <= 1'b0;
                end else if (route_locked[input_port]) begin
                    if (router_in_ready[input_port])
                        route_locked[input_port] <= 1'b0;
                end else if (!router_in_ready[input_port]) begin
                    route_locked[input_port] <= 1'b1;
                    locked_route[input_port] <= computed_route_valid[input_port] ?
                        computed_route[input_port] : 3'b111;
                end
            end
        end
    end

    router_5port #(
        .FLIT_WIDTH(FLIT_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH),
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
    ) router (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(router_in_ready),
        .in_flit(routed_in_flit),
        .in_priority(in_priority),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_flit(out_flit),
        .out_priority(out_priority),
        .invalid_flit_dropped(),
        .input_occupancy(input_occupancy),
        .congestion_score_out(congestion_score),
        .congestion_predicted_out(congestion_predicted),
        .output_request_matrix(output_request_matrix)
    );

    assign in_ready = router_in_ready;

    always @* begin : p_occupancy_detector
        integer occupied_flits;

        occupancy_predicted = '0;
        for (int output_port = 0; output_port < NUM_PORTS; output_port++) begin
            occupied_flits = 0;
            for (int input_port = 0; input_port < NUM_PORTS; input_port++) begin
                if (output_request_matrix[output_port * NUM_PORTS + input_port])
                    occupied_flits += input_occupancy[input_port];
            end
            occupancy_predicted[output_port] =
                occupied_flits >= OCCUPANCY_THRESHOLD;
        end
    end

    initial begin
        if (FLIT_WIDTH < 64)
            $fatal(1, "mesh flits must be at least 64 bits wide");
        if (OCCUPANCY_THRESHOLD < 1)
            $fatal(1, "OCCUPANCY_THRESHOLD must be positive");
    end

endmodule
