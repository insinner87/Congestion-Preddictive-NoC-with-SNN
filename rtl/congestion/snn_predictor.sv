// Small integer leaky-integrate-and-fire predictor.
//
// Seven event-encoded features feed four hidden LIF neurons and one output LIF
// neuron for each router output. The output is a quantized risk class, not a
// probability. Model parameters are integer constants and may be overridden
// by an offline-generated parameter include in a later integration.
module snn_predictor #(
    parameter int NUM_PORTS = noc_pkg::NUM_PORTS,
    parameter logic [13:0] W_HIDDEN_0 = snn_model_parameters_pkg::W_HIDDEN_0,
    parameter logic [13:0] W_HIDDEN_1 = snn_model_parameters_pkg::W_HIDDEN_1,
    parameter logic [13:0] W_HIDDEN_2 = snn_model_parameters_pkg::W_HIDDEN_2,
    parameter logic [13:0] W_HIDDEN_3 = snn_model_parameters_pkg::W_HIDDEN_3,
    parameter logic [7:0] W_OUTPUT = snn_model_parameters_pkg::W_OUTPUT,
    parameter logic [7:0] HIDDEN_THRESHOLD = snn_model_parameters_pkg::HIDDEN_THRESHOLD,
    parameter logic [7:0] OUTPUT_THRESHOLD = snn_model_parameters_pkg::OUTPUT_THRESHOLD,
    parameter logic [7:0] POTENTIAL_MAX = snn_model_parameters_pkg::POTENTIAL_MAX
) (
    input  logic clk,
    input  logic rst_n,
    input  logic [NUM_PORTS*7-1:0] feature_spikes,
    input  logic [NUM_PORTS-1:0] feature_valid,
    output logic [NUM_PORTS-1:0][1:0] risk_class,
    output logic [NUM_PORTS-1:0] output_spike,
    output logic [NUM_PORTS-1:0] risk_valid,
    output logic [NUM_PORTS-1:0] state_update_enable
);

    logic [7:0] hidden_potential [0:NUM_PORTS-1][0:3];
    logic [7:0] hidden_next [0:NUM_PORTS-1][0:3];
    logic [7:0] output_potential [0:NUM_PORTS-1];
    logic [7:0] output_next [0:NUM_PORTS-1];
    logic [3:0] hidden_spikes [0:NUM_PORTS-1];
    logic [7:0] output_integrated [0:NUM_PORTS-1];

    function automatic logic [1:0] get_feature_weight(
        input logic [13:0] packed_weights,
        input integer feature_index
    );
        get_feature_weight = packed_weights[feature_index*2 +: 2];
    endfunction

    function automatic logic [1:0] get_output_weight(
        input logic [7:0] packed_weights,
        input integer neuron_index
    );
        get_output_weight = packed_weights[neuron_index*2 +: 2];
    endfunction

    function automatic logic [7:0] apply_leak(input logic [7:0] potential);
        logic [7:0] leak_amount;
        begin
            leak_amount = potential >> 2;
            if (potential != 0 && leak_amount == 0)
                leak_amount = 1;
            apply_leak = potential - leak_amount;
        end
    endfunction

    always_comb begin : p_lif_inference
        logic [13:0] hidden_weights;
        logic [7:0] weighted_input;
        logic [7:0] leaked_potential;
        logic [7:0] integrated_potential;
        logic [7:0] output_weighted_input;
        logic [7:0] output_leaked_potential;
        logic [7:0] output_integrated_potential;
        logic any_state;

        risk_class = '0;
        output_spike = '0;
        risk_valid = feature_valid;
        state_update_enable = '0;

        for (int output_port = 0; output_port < NUM_PORTS; output_port++) begin
            hidden_spikes[output_port] = '0;
            output_integrated[output_port] = '0;
            output_next[output_port] = '0;
            any_state = (output_potential[output_port] != 0);

            for (int neuron = 0; neuron < 4; neuron++) begin
                case (neuron)
                    0: hidden_weights = W_HIDDEN_0;
                    1: hidden_weights = W_HIDDEN_1;
                    2: hidden_weights = W_HIDDEN_2;
                    default: hidden_weights = W_HIDDEN_3;
                endcase

                weighted_input = '0;
                for (int feature_index = 0; feature_index < 7; feature_index++) begin
                    if (feature_spikes[output_port*7 + feature_index])
                        weighted_input = weighted_input +
                            get_feature_weight(hidden_weights, feature_index);
                end

                leaked_potential = apply_leak(hidden_potential[output_port][neuron]);
                integrated_potential = leaked_potential + weighted_input;
                if (integrated_potential > POTENTIAL_MAX)
                    integrated_potential = POTENTIAL_MAX;

                hidden_spikes[output_port][neuron] =
                    integrated_potential >= HIDDEN_THRESHOLD;
                if (hidden_spikes[output_port][neuron])
                    hidden_next[output_port][neuron] =
                        integrated_potential - HIDDEN_THRESHOLD;
                else
                    hidden_next[output_port][neuron] = integrated_potential;

                if (hidden_potential[output_port][neuron] != 0)
                    any_state = 1'b1;
            end

            output_weighted_input = '0;
            for (int neuron = 0; neuron < 4; neuron++) begin
                if (hidden_spikes[output_port][neuron])
                    output_weighted_input = output_weighted_input +
                        get_output_weight(W_OUTPUT, neuron);
            end

            output_leaked_potential = apply_leak(output_potential[output_port]);
            output_integrated_potential = output_leaked_potential +
                output_weighted_input;
            if (output_integrated_potential > POTENTIAL_MAX)
                output_integrated_potential = POTENTIAL_MAX;
            output_integrated[output_port] = output_integrated_potential;

            output_spike[output_port] =
                output_integrated_potential >= OUTPUT_THRESHOLD;
            if (output_spike[output_port])
                output_next[output_port] =
                    output_integrated_potential - OUTPUT_THRESHOLD;
            else
                output_next[output_port] = output_integrated_potential;

            if (feature_valid[output_port]) begin
                if (output_integrated_potential >= 6)
                    risk_class[output_port] = 2'd3;
                else if (output_integrated_potential >= 4)
                    risk_class[output_port] = 2'd2;
                else if (output_integrated_potential >= 2)
                    risk_class[output_port] = 2'd1;
                else
                    risk_class[output_port] = 2'd0;

                state_update_enable[output_port] = any_state ||
                    (|feature_spikes[output_port*7 +: 7]);
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin : p_lif_state
        if (!rst_n) begin
            for (int output_port = 0; output_port < NUM_PORTS; output_port++) begin
                output_potential[output_port] <= '0;
                for (int neuron = 0; neuron < 4; neuron++)
                    hidden_potential[output_port][neuron] <= '0;
            end
        end else begin
            for (int output_port = 0; output_port < NUM_PORTS; output_port++) begin
                if (!feature_valid[output_port]) begin
                    output_potential[output_port] <= '0;
                    for (int neuron = 0; neuron < 4; neuron++)
                        hidden_potential[output_port][neuron] <= '0;
                end else if (state_update_enable[output_port]) begin
                    output_potential[output_port] <= output_next[output_port];
                    for (int neuron = 0; neuron < 4; neuron++)
                        hidden_potential[output_port][neuron] <=
                            hidden_next[output_port][neuron];
                end
            end
        end
    end

    initial begin
        if (NUM_PORTS < 1)
            $fatal(1, "snn_predictor requires at least one port");
        if (HIDDEN_THRESHOLD < 1 || OUTPUT_THRESHOLD < 1)
            $fatal(1, "SNN thresholds must be positive");
        if (POTENTIAL_MAX < HIDDEN_THRESHOLD || POTENTIAL_MAX < OUTPUT_THRESHOLD)
            $fatal(1, "SNN potential maximum must contain both thresholds");
    end

endmodule
