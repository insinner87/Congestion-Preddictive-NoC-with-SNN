// Four-by-four mesh built from the repository's existing five-port router.
//
// Each inter-router direction has a registered two-flit link FIFO. This
// breaks combinational ready paths around mesh cycles and isolates backpressure.
// A two-bit priority sideband accompanies the unchanged mesh flit through all
// router and link FIFOs. Priority arbitration can be enabled by parameter.
module noc_mesh_4x4 #(
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
    parameter bit TRACE_CENTER_ONLY = 1'b0,
    parameter bit ENABLE_ADAPTIVE_BUFFER = 1'b0,
    parameter bit ENABLE_OFFLOAD = 1'b0,
    parameter int LINK_FIFO_DEPTH = 2,
    parameter int WINDOW_CYCLES = 16,
    parameter int OCCUPANCY_THRESHOLD = 3,
    parameter int TIME_SCORE_SATURATION = 16,
    parameter int FREQ_SCORE_SATURATION = 8,
    parameter int TIME_WEIGHT = 3,
    parameter int FREQ_WEIGHT = 1,
    parameter logic [7:0] SCORE_THRESHOLD = 8'd128
) (
    input logic clk,
    input logic rst_n,
    input logic [15:0] local_in_valid,
    output logic [15:0] local_in_ready,
    input logic [15:0][FLIT_WIDTH-1:0] local_in_flit,
    input logic [15:0][1:0] local_in_priority,
    output logic [15:0] local_out_valid,
    input logic [15:0] local_out_ready,
    output logic [15:0][FLIT_WIDTH-1:0] local_out_flit,
    output logic [15:0][1:0] local_out_priority
);

    localparam int NUM_PORTS = noc_pkg::NUM_PORTS;
    localparam int LOCAL = noc_pkg::PORT_LOCAL;
    localparam int NORTH = noc_pkg::PORT_NORTH;
    localparam int SOUTH = noc_pkg::PORT_SOUTH;
    localparam int EAST = noc_pkg::PORT_EAST;
    localparam int WEST = noc_pkg::PORT_WEST;
    localparam int COUNT_WIDTH = $clog2(LINK_FIFO_DEPTH) + 1;
    localparam int LINK_OCCUPANCY_WIDTH = COUNT_WIDTH;

    wire [15:0][NUM_PORTS-1:0] router_in_valid;
    logic [15:0][NUM_PORTS-1:0] router_in_ready;
    wire [15:0][NUM_PORTS-1:0][FLIT_WIDTH-1:0] router_in_flit;
    logic [15:0][NUM_PORTS-1:0][1:0] router_in_priority;
    logic [15:0][NUM_PORTS-1:0] router_out_valid;
    wire [15:0][NUM_PORTS-1:0] router_out_ready;
    logic [15:0][NUM_PORTS-1:0][FLIT_WIDTH-1:0] router_out_flit;
    logic [15:0][NUM_PORTS-1:0][1:0] router_out_priority;
    logic [15:0][NUM_PORTS-1:0][LINK_OCCUPANCY_WIDTH-1:0]
        router_output_buffer_occupancy;
    logic [15:0][NUM_PORTS-1:0][7:0] router_congestion_score;
    logic [15:0][NUM_PORTS-1:0] router_congestion_predicted;
    logic [15:0][NUM_PORTS-1:0] router_occupancy_predicted;
    logic [15:0][NUM_PORTS-1:0][($clog2(FIFO_DEPTH)+1)-1:0]
        router_input_occupancy;

    for (genvar node = 0; node < 16; node++) begin : g_routers
        localparam int X = node % 4;
        localparam int Y = node / 4;

        noc_router_wrapper #(
            .FLIT_WIDTH(FLIT_WIDTH),
            .FIFO_DEPTH(FIFO_DEPTH),
            .ROUTING_MODE(ROUTING_MODE),
            .ENABLE_TF_PCR(ENABLE_TF_PCR),
            .ENABLE_PRIORITY(ENABLE_PRIORITY),
            .PRIORITY_AGE_LIMIT(PRIORITY_AGE_LIMIT),
            .ENABLE_SNN(ENABLE_SNN &&
                (!TRACE_CENTER_ONLY || node == 5 || node == 6 || node == 9 || node == 10)),
            .ENABLE_SNN_ROUTING(ENABLE_SNN_ROUTING),
            .ENABLE_EQUATION_ROUTING(ENABLE_EQUATION_ROUTING),
            .ENABLE_ADAPTIVE_PREDICTOR(ENABLE_ADAPTIVE_PREDICTOR),
            .SNN_VALIDATION_ACCURACY_PERCENT(SNN_VALIDATION_ACCURACY_PERCENT),
            .SNN_VALIDATION_CORRECT_SAMPLES(SNN_VALIDATION_CORRECT_SAMPLES),
            .SNN_VALIDATION_TOTAL_SAMPLES(SNN_VALIDATION_TOTAL_SAMPLES),
            .ADAPTIVE_ONLINE_WINDOW(ADAPTIVE_ONLINE_WINDOW),
            .ADAPTIVE_MIN_ONLINE_SAMPLES(ADAPTIVE_MIN_ONLINE_SAMPLES),
            .ENABLE_ADAPTIVE_BUFFER(ENABLE_ADAPTIVE_BUFFER),
            .ENABLE_OFFLOAD(ENABLE_OFFLOAD),
            .OUTPUT_BUFFER_DEPTH(LINK_FIFO_DEPTH),
            .OUTPUT_BUFFER_OCCUPANCY_WIDTH(LINK_OCCUPANCY_WIDTH),
            .WINDOW_CYCLES(WINDOW_CYCLES),
            .OCCUPANCY_THRESHOLD(OCCUPANCY_THRESHOLD),
            .TIME_SCORE_SATURATION(TIME_SCORE_SATURATION),
            .FREQ_SCORE_SATURATION(FREQ_SCORE_SATURATION),
            .TIME_WEIGHT(TIME_WEIGHT),
            .FREQ_WEIGHT(FREQ_WEIGHT),
            .SCORE_THRESHOLD(SCORE_THRESHOLD)
        ) router_wrapper (
            .clk(clk),
            .rst_n(rst_n),
            .coordinate_x(2'(X)),
            .coordinate_y(2'(Y)),
            .in_valid(router_in_valid[node]),
            .in_ready(router_in_ready[node]),
            .in_flit(router_in_flit[node]),
            .in_priority(router_in_priority[node]),
            .out_valid(router_out_valid[node]),
            .out_ready(router_out_ready[node]),
            .out_flit(router_out_flit[node]),
            .out_priority(router_out_priority[node]),
            .output_buffer_occupancy(router_output_buffer_occupancy[node]),
            .congestion_score(router_congestion_score[node]),
            .congestion_predicted(router_congestion_predicted[node]),
            .occupancy_predicted(router_occupancy_predicted[node]),
            .input_occupancy(router_input_occupancy[node])
        );

        assign router_in_valid[node][LOCAL] = local_in_valid[node];
        assign router_in_flit[node][LOCAL] = local_in_flit[node];
        assign router_in_priority[node][LOCAL] = local_in_priority[node];
        assign local_in_ready[node] = router_in_ready[node][LOCAL];
        assign local_out_valid[node] = router_out_valid[node][LOCAL];
        assign local_out_flit[node] = router_out_flit[node][LOCAL];
        assign local_out_priority[node] = router_out_priority[node][LOCAL];
        assign router_output_buffer_occupancy[node][LOCAL] = '0;
        assign router_out_ready[node][LOCAL] = local_out_ready[node];

        if (Y == 0) begin : g_north_boundary
            assign router_in_valid[node][NORTH] = 1'b0;
            assign router_in_flit[node][NORTH] = '0;
            assign router_in_priority[node][NORTH] = '0;
            assign router_output_buffer_occupancy[node][NORTH] = '0;
            assign router_out_ready[node][NORTH] = 1'b0;
        end
        if (Y == 3) begin : g_south_boundary
            assign router_in_valid[node][SOUTH] = 1'b0;
            assign router_in_flit[node][SOUTH] = '0;
            assign router_in_priority[node][SOUTH] = '0;
            assign router_output_buffer_occupancy[node][SOUTH] = '0;
            assign router_out_ready[node][SOUTH] = 1'b0;
        end
        if (X == 3) begin : g_east_boundary
            assign router_in_valid[node][EAST] = 1'b0;
            assign router_in_flit[node][EAST] = '0;
            assign router_in_priority[node][EAST] = '0;
            assign router_output_buffer_occupancy[node][EAST] = '0;
            assign router_out_ready[node][EAST] = 1'b0;
        end
        if (X == 0) begin : g_west_boundary
            assign router_in_valid[node][WEST] = 1'b0;
            assign router_in_flit[node][WEST] = '0;
            assign router_in_priority[node][WEST] = '0;
            assign router_output_buffer_occupancy[node][WEST] = '0;
            assign router_out_ready[node][WEST] = 1'b0;
        end
    end

    for (genvar y = 0; y < 4; y++) begin : g_rows
        for (genvar x = 0; x < 4; x++) begin : g_columns
            localparam int NODE = y * 4 + x;

            if (x < 3) begin : g_east_link
                localparam int NEIGHBOR = NODE + 1;
                mesh_link_fifo #(
                    .DATA_WIDTH(FLIT_WIDTH),
                    .DEPTH(LINK_FIFO_DEPTH),
                    .COUNT_WIDTH(COUNT_WIDTH)
                ) link (
                    .clk(clk), .rst_n(rst_n),
                    .source_valid(router_out_valid[NODE][EAST]),
                    .source_ready(router_out_ready[NODE][EAST]),
                    .source_data(router_out_flit[NODE][EAST]),
                    .source_priority(router_out_priority[NODE][EAST]),
                    .destination_valid(router_in_valid[NEIGHBOR][WEST]),
                    .destination_ready(router_in_ready[NEIGHBOR][WEST]),
                    .destination_data(router_in_flit[NEIGHBOR][WEST]),
                    .destination_priority(router_in_priority[NEIGHBOR][WEST]),
                    .occupancy(router_output_buffer_occupancy[NODE][EAST])
                );
            end

            if (x > 0) begin : g_west_link
                localparam int NEIGHBOR = NODE - 1;
                mesh_link_fifo #(
                    .DATA_WIDTH(FLIT_WIDTH),
                    .DEPTH(LINK_FIFO_DEPTH),
                    .COUNT_WIDTH(COUNT_WIDTH)
                ) link (
                    .clk(clk), .rst_n(rst_n),
                    .source_valid(router_out_valid[NODE][WEST]),
                    .source_ready(router_out_ready[NODE][WEST]),
                    .source_data(router_out_flit[NODE][WEST]),
                    .source_priority(router_out_priority[NODE][WEST]),
                    .destination_valid(router_in_valid[NEIGHBOR][EAST]),
                    .destination_ready(router_in_ready[NEIGHBOR][EAST]),
                    .destination_data(router_in_flit[NEIGHBOR][EAST]),
                    .destination_priority(router_in_priority[NEIGHBOR][EAST]),
                    .occupancy(router_output_buffer_occupancy[NODE][WEST])
                );
            end

            if (y < 3) begin : g_south_link
                localparam int NEIGHBOR = NODE + 4;
                mesh_link_fifo #(
                    .DATA_WIDTH(FLIT_WIDTH),
                    .DEPTH(LINK_FIFO_DEPTH),
                    .COUNT_WIDTH(COUNT_WIDTH)
                ) link (
                    .clk(clk), .rst_n(rst_n),
                    .source_valid(router_out_valid[NODE][SOUTH]),
                    .source_ready(router_out_ready[NODE][SOUTH]),
                    .source_data(router_out_flit[NODE][SOUTH]),
                    .source_priority(router_out_priority[NODE][SOUTH]),
                    .destination_valid(router_in_valid[NEIGHBOR][NORTH]),
                    .destination_ready(router_in_ready[NEIGHBOR][NORTH]),
                    .destination_data(router_in_flit[NEIGHBOR][NORTH]),
                    .destination_priority(router_in_priority[NEIGHBOR][NORTH]),
                    .occupancy(router_output_buffer_occupancy[NODE][SOUTH])
                );
            end

            if (y > 0) begin : g_north_link
                localparam int NEIGHBOR = NODE - 4;
                mesh_link_fifo #(
                    .DATA_WIDTH(FLIT_WIDTH),
                    .DEPTH(LINK_FIFO_DEPTH),
                    .COUNT_WIDTH(COUNT_WIDTH)
                ) link (
                    .clk(clk), .rst_n(rst_n),
                    .source_valid(router_out_valid[NODE][NORTH]),
                    .source_ready(router_out_ready[NODE][NORTH]),
                    .source_data(router_out_flit[NODE][NORTH]),
                    .source_priority(router_out_priority[NODE][NORTH]),
                    .destination_valid(router_in_valid[NEIGHBOR][SOUTH]),
                    .destination_ready(router_in_ready[NEIGHBOR][SOUTH]),
                    .destination_data(router_in_flit[NEIGHBOR][SOUTH]),
                    .destination_priority(router_in_priority[NEIGHBOR][SOUTH]),
                    .occupancy(router_output_buffer_occupancy[NODE][NORTH])
                );
            end
        end
    end

    initial begin
        if (FLIT_WIDTH < 64)
            $fatal(1, "noc_mesh_4x4 requires FLIT_WIDTH >= 64");
        if (LINK_FIFO_DEPTH < 1)
            $fatal(1, "LINK_FIFO_DEPTH must be positive");
        if (ROUTING_MODE < 0 || ROUTING_MODE > 1)
            $fatal(1, "ROUTING_MODE must be 0 (XY) or 1 (West-First adaptive)");
    end

endmodule
