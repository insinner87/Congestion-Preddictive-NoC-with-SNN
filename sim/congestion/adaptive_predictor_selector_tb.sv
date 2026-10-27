module adaptive_predictor_selector_tb;
    localparam int NUM_PORTS = 1;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [NUM_PORTS-1:0] prediction_valid = '0;
    logic [NUM_PORTS-1:0] snn_prediction = '0;
    logic [NUM_PORTS-1:0] equation_prediction = '0;
    logic [NUM_PORTS-1:0] actual_congestion_event = '0;
    logic [NUM_PORTS-1:0] selected_prediction;
    logic [NUM_PORTS-1:0] select_snn;
    logic [NUM_PORTS-1:0][3:0] online_sample_count;
    logic [NUM_PORTS-1:0][6:0] online_accuracy_percent;
    logic [NUM_PORTS-1:0] model_selection_pulse;
    logic [NUM_PORTS-1:0] model_switch_pulse;
    logic [NUM_PORTS-1:0][2:0] model_switch_reason;
    logic [NUM_PORTS-1:0] validation_gate_select_snn;
    logic [NUM_PORTS-1:0][3:0] validation_gate_sample_count;
    logic [NUM_PORTS-1:0][6:0] validation_gate_accuracy;
    logic [NUM_PORTS-1:0] validation_gate_selection_pulse;
    logic [NUM_PORTS-1:0] validation_gate_switch_pulse;
    logic [NUM_PORTS-1:0][2:0] validation_gate_switch_reason;
    integer switch_to_snn_count = 0;
    integer switch_to_equation_count = 0;
    integer initial_equation_selections = 0;
    integer offline_gate_selections = 0;

    always #5 clk = ~clk;

    adaptive_predictor_selector #(
        .NUM_PORTS(NUM_PORTS),
        .PREDICTION_HORIZON(8),
        .ONLINE_WINDOW_SIZE(8),
        .MIN_ONLINE_SAMPLES(4),
        .VALIDATION_ACCURACY_PERCENT(0),
        .VALIDATION_CORRECT_SAMPLES(95),
        .VALIDATION_TOTAL_SAMPLES(100)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .prediction_valid(prediction_valid),
        .snn_prediction(snn_prediction),
        .equation_prediction(equation_prediction),
        .actual_congestion_event(actual_congestion_event),
        .selected_prediction(selected_prediction),
        .select_snn(select_snn),
        .online_sample_count(online_sample_count),
        .online_accuracy_percent(online_accuracy_percent),
        .model_selection_pulse(model_selection_pulse),
        .model_switch_pulse(model_switch_pulse),
        .model_switch_reason(model_switch_reason)
    );

    adaptive_predictor_selector #(
        .NUM_PORTS(NUM_PORTS),
        .PREDICTION_HORIZON(8),
        .ONLINE_WINDOW_SIZE(8),
        .MIN_ONLINE_SAMPLES(4),
        .VALIDATION_ACCURACY_PERCENT(0),
        .VALIDATION_CORRECT_SAMPLES(900),
        .VALIDATION_TOTAL_SAMPLES(1000)
    ) validation_gate_dut (
        .clk(clk),
        .rst_n(rst_n),
        .prediction_valid(prediction_valid),
        .snn_prediction(snn_prediction),
        .equation_prediction(equation_prediction),
        .actual_congestion_event(actual_congestion_event),
        .selected_prediction(),
        .select_snn(validation_gate_select_snn),
        .online_sample_count(validation_gate_sample_count),
        .online_accuracy_percent(validation_gate_accuracy),
        .model_selection_pulse(validation_gate_selection_pulse),
        .model_switch_pulse(validation_gate_switch_pulse),
        .model_switch_reason(validation_gate_switch_reason)
    );

    task automatic drive_cycle(
        input logic snn_value,
        input logic equation_value,
        input logic actual_event
    );
        begin
            @(negedge clk);
            prediction_valid[0] = 1'b1;
            snn_prediction[0] = snn_value;
            equation_prediction[0] = equation_value;
            actual_congestion_event[0] = actual_event;
            @(posedge clk);
            #1;
            if (model_switch_pulse[0]) begin
                if (model_switch_reason[0] == 3'd1)
                    switch_to_snn_count++;
                else if (model_switch_reason[0] == 3'd2 ||
                         model_switch_reason[0] == 3'd3 ||
                         model_switch_reason[0] == 3'd4)
                    switch_to_equation_count++;
            end
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;
        if (!model_selection_pulse[0] || model_switch_reason[0] != 3'd3 ||
            !validation_gate_selection_pulse[0] ||
            validation_gate_switch_reason[0] != 3'd2)
            $fatal(1, "initial model selections did not report their fallback reasons");
        initial_equation_selections++;
        offline_gate_selections++;

        $display("ADAPTIVE TEST 1: wait for completed labels and minimum samples");
        repeat (12) drive_cycle(1'b0, 1'b1, 1'b0);
        if (!select_snn[0] || online_sample_count[0] < 4 ||
            online_accuracy_percent[0] != 100)
            $fatal(1, "validated SNN was not selected after sufficient accurate samples");
        if (selected_prediction[0] !== snn_prediction[0])
            $fatal(1, "selected prediction did not follow the SNN");
        if (validation_gate_select_snn[0] ||
            validation_gate_switch_pulse[0])
            $fatal(1, "90-percent offline validation gate incorrectly enabled SNN");
        if (initial_equation_selections != 1 || offline_gate_selections != 1)
            $fatal(1, "initial selection event counts were SNN-gate=%0d offline-gate=%0d",
                   initial_equation_selections, offline_gate_selections);

        $display("ADAPTIVE TEST 2: do not consume future labels before the horizon");
        drive_cycle(1'b1, 1'b0, 1'b0);
        if (!select_snn[0])
            $fatal(1, "SNN selection changed before the prediction label matured");
        repeat (7) drive_cycle(1'b0, 1'b0, 1'b0);
        if (!select_snn[0])
            $fatal(1, "SNN selection changed before the eight-cycle horizon elapsed");
        drive_cycle(1'b0, 1'b0, 1'b0);
        if (select_snn[0] || model_switch_reason[0] != 3'd4)
            $fatal(1, "online accuracy <=90%% did not switch back to equation mode");
        if (online_sample_count[0] != 8 ||
            online_accuracy_percent[0] > 90)
            $fatal(1, "rolling-window accuracy/count did not include the matured error");
        drive_cycle(1'b1, 1'b0, 1'b0);
        if (selected_prediction[0] !== equation_prediction[0])
            $fatal(1, "fallback selection did not use the equation prediction");
        if (switch_to_snn_count != 1 || switch_to_equation_count != 1)
            $fatal(1, "expected one SNN and one equation switch event, got %0d and %0d",
                   switch_to_snn_count, switch_to_equation_count);

        $display("ADAPTIVE PREDICTOR SELECTOR TESTS PASSED: eight-cycle delayed labels, 90%% gate, online fallback");
        $finish;
    end

    initial begin
        #2000;
        $fatal(1, "adaptive predictor selector test timed out");
    end
endmodule
