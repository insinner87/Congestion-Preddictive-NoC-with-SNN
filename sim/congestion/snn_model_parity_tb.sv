module snn_model_parity_tb;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [6:0] feature_spikes = '0;
    logic feature_valid = 1'b0;
    logic [1:0] risk_class;
    logic output_spike;
    logic risk_valid;
    logic state_update_enable;
    integer ref_hidden [0:3];
    integer ref_output;
    integer random_seed = 32'h16c0ffee;

    always #5 clk = ~clk;

    snn_predictor #(.NUM_PORTS(1)) dut (
        .clk(clk), .rst_n(rst_n), .feature_spikes(feature_spikes),
        .feature_valid(feature_valid), .risk_class(risk_class),
        .output_spike(output_spike), .risk_valid(risk_valid),
        .state_update_enable(state_update_enable)
    );

    function automatic logic [13:0] packed_hidden_weights(input integer neuron);
        case (neuron)
            0: packed_hidden_weights = snn_model_parameters_pkg::W_HIDDEN_0;
            1: packed_hidden_weights = snn_model_parameters_pkg::W_HIDDEN_1;
            2: packed_hidden_weights = snn_model_parameters_pkg::W_HIDDEN_2;
            default: packed_hidden_weights = snn_model_parameters_pkg::W_HIDDEN_3;
        endcase
    endfunction

    function automatic integer leak(input integer potential);
        integer amount;
        begin
            if (potential == 0) leak = 0;
            else begin
                amount = potential >> 2;
                if (amount == 0) amount = 1;
                leak = potential - amount;
            end
        end
    endfunction

    task automatic random_step(input logic [6:0] events, input logic is_valid);
        integer next_hidden [0:3];
        integer weighted;
        integer integrated;
        integer output_weighted;
        integer output_integrated;
        integer predicted_class;
        integer predicted_spike;
        integer any_state;
        logic [3:0] spikes;
        logic [13:0] weights;
        begin
            feature_spikes = events;
            feature_valid = is_valid;
            #1;
            any_state = (ref_output != 0);
            output_weighted = 0;
            for (int neuron = 0; neuron < 4; neuron++) begin
                weights = packed_hidden_weights(neuron);
                weighted = 0;
                for (int feature_index = 0; feature_index < 7; feature_index++)
                    if (events[feature_index])
                        weighted += weights[feature_index*2 +: 2];
                integrated = leak(ref_hidden[neuron]) + weighted;
                if (integrated > snn_model_parameters_pkg::POTENTIAL_MAX)
                    integrated = snn_model_parameters_pkg::POTENTIAL_MAX;
                spikes[neuron] = integrated >= snn_model_parameters_pkg::HIDDEN_THRESHOLD;
                next_hidden[neuron] = spikes[neuron] ?
                    integrated - snn_model_parameters_pkg::HIDDEN_THRESHOLD : integrated;
                if (ref_hidden[neuron] != 0) any_state = 1;
                if (spikes[neuron])
                    output_weighted += snn_model_parameters_pkg::W_OUTPUT[neuron*2 +: 2];
            end
            output_integrated = leak(ref_output) + output_weighted;
            if (output_integrated > snn_model_parameters_pkg::POTENTIAL_MAX)
                output_integrated = snn_model_parameters_pkg::POTENTIAL_MAX;
            predicted_class = output_integrated >= 6 ? 3 :
                              output_integrated >= 4 ? 2 :
                              output_integrated >= 2 ? 1 : 0;
            predicted_spike = output_integrated >= snn_model_parameters_pkg::OUTPUT_THRESHOLD;
            if (risk_valid !== is_valid ||
                (is_valid && (risk_class != predicted_class ||
                              output_spike != predicted_spike ||
                              state_update_enable !=
                                (any_state || (|events)))))
                $fatal(1, "Python/RTL LIF-equivalent recurrence mismatch");

            @(posedge clk);
            #1;
            if (is_valid) begin
                if (any_state || (|events)) begin
                    ref_output = predicted_spike ?
                        output_integrated - snn_model_parameters_pkg::OUTPUT_THRESHOLD :
                        output_integrated;
                    for (int neuron = 0; neuron < 4; neuron++)
                        ref_hidden[neuron] = next_hidden[neuron];
                end
            end else begin
                ref_output = 0;
                for (int neuron = 0; neuron < 4; neuron++) ref_hidden[neuron] = 0;
            end
            @(negedge clk);
        end
    endtask

    initial begin
        ref_output = 0;
        for (int neuron = 0; neuron < 4; neuron++) ref_hidden[neuron] = 0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        for (int trial = 0; trial < 1000; trial++) begin
            random_step(7'($urandom(random_seed)), $urandom(random_seed) % 5 != 0);
        end
        $display("TRAINED INTEGER SNN REFERENCE PARITY PASSED (1000 recurrent samples)");
        $finish;
    end
endmodule
