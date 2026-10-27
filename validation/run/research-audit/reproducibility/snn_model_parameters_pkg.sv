// Generated from the quantized integer LIF training checkpoint.
package snn_model_parameters_pkg;
    localparam int MODEL_VERSION = 1;
    localparam logic [13:0] W_HIDDEN_0 = {2'd2, 2'd2, 2'd3, 2'd0, 2'd1, 2'd1, 2'd2};
    localparam logic [13:0] W_HIDDEN_1 = {2'd0, 2'd2, 2'd1, 2'd2, 2'd0, 2'd0, 2'd0};
    localparam logic [13:0] W_HIDDEN_2 = {2'd0, 2'd0, 2'd1, 2'd2, 2'd2, 2'd2, 2'd0};
    localparam logic [13:0] W_HIDDEN_3 = {2'd2, 2'd3, 2'd0, 2'd3, 2'd3, 2'd3, 2'd1};
    localparam logic [7:0] W_OUTPUT = {2'd0, 2'd0, 2'd3, 2'd1};
    localparam logic [7:0] HIDDEN_THRESHOLD = 8'd3;
    localparam logic [7:0] OUTPUT_THRESHOLD = 8'd1;
    localparam logic [7:0] POTENTIAL_MAX = 8'd63;
endpackage
