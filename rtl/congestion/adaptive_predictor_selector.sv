// Selects the SNN only when offline validation and delayed online evidence
// both exceed the configured accuracy threshold.
module adaptive_predictor_selector #(
    parameter int NUM_PORTS = noc_pkg::NUM_PORTS,
    parameter int PREDICTION_HORIZON = 8,
    parameter int ONLINE_WINDOW_SIZE = 64,
    parameter int MIN_ONLINE_SAMPLES = 32,
    parameter int VALIDATION_ACCURACY_PERCENT = 0,
    parameter int VALIDATION_CORRECT_SAMPLES = 0,
    parameter int VALIDATION_TOTAL_SAMPLES = 0,
    parameter int ACCURACY_THRESHOLD_PERCENT = 90,
    parameter int SAMPLE_COUNT_WIDTH = $clog2(ONLINE_WINDOW_SIZE + 1),
    parameter int POINTER_WIDTH = (ONLINE_WINDOW_SIZE > 1) ?
        $clog2(ONLINE_WINDOW_SIZE) : 1
) (
    input logic clk,
    input logic rst_n,
    input logic [NUM_PORTS-1:0] prediction_valid,
    input logic [NUM_PORTS-1:0] snn_prediction,
    input logic [NUM_PORTS-1:0] equation_prediction,
    input logic [NUM_PORTS-1:0] actual_congestion_event,
    output logic [NUM_PORTS-1:0] selected_prediction,
    output logic [NUM_PORTS-1:0] select_snn,
    output logic [NUM_PORTS-1:0][SAMPLE_COUNT_WIDTH-1:0] online_sample_count,
    output logic [NUM_PORTS-1:0][6:0] online_accuracy_percent,
    output logic [NUM_PORTS-1:0] model_selection_pulse,
    output logic [NUM_PORTS-1:0] model_switch_pulse,
    output logic [NUM_PORTS-1:0][2:0] model_switch_reason
);

    localparam logic [2:0] SWITCH_NONE = 3'd0;
    localparam logic [2:0] SWITCH_TO_SNN = 3'd1;
    localparam logic [2:0] SWITCH_OFFLINE_ACCURACY = 3'd2;
    localparam logic [2:0] SWITCH_INSUFFICIENT_SAMPLES = 3'd3;
    localparam logic [2:0] SWITCH_ONLINE_ACCURACY = 3'd4;
    localparam bit OFFLINE_VALIDATION_PASSES =
        (VALIDATION_TOTAL_SAMPLES > 0) ?
            (VALIDATION_CORRECT_SAMPLES * 100 >
                VALIDATION_TOTAL_SAMPLES * ACCURACY_THRESHOLD_PERCENT) :
            (VALIDATION_ACCURACY_PERCENT > ACCURACY_THRESHOLD_PERCENT);

    logic [NUM_PORTS-1:0] snn_prediction_history [0:PREDICTION_HORIZON-1];
    logic [NUM_PORTS-1:0] valid_history [0:PREDICTION_HORIZON-1];
    logic [NUM_PORTS-1:0] event_history [0:PREDICTION_HORIZON-1];
    logic [NUM_PORTS-1:0] snn_correct_history [0:ONLINE_WINDOW_SIZE-1];
    logic [NUM_PORTS-1:0][POINTER_WIDTH-1:0] write_pointer;
    logic [NUM_PORTS-1:0][SAMPLE_COUNT_WIDTH-1:0] correct_sample_count;
    logic [NUM_PORTS-1:0] selection_initialized;

    always_comb begin : p_selected_prediction
        selected_prediction = '0;
        for (int port = 0; port < NUM_PORTS; port++) begin
            selected_prediction[port] = select_snn[port] ?
                snn_prediction[port] : equation_prediction[port];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin : p_accuracy_and_selection
        integer target;
        integer correct;
        integer sample_count;
        integer next_accuracy;
        logic target_congested;
        logic snn_correct;
        logic desired_snn;
        logic [2:0] reason;

        if (!rst_n) begin
            select_snn <= '0;
            online_sample_count <= '0;
            correct_sample_count <= '0;
            online_accuracy_percent <= '0;
            model_switch_pulse <= '0;
            model_selection_pulse <= '0;
            model_switch_reason <= '0;
            write_pointer <= '0;
            selection_initialized <= '0;
            for (int delay = 0; delay < PREDICTION_HORIZON; delay++) begin
                snn_prediction_history[delay] <= '0;
                valid_history[delay] <= '0;
                event_history[delay] <= '0;
            end
            for (int sample = 0; sample < ONLINE_WINDOW_SIZE; sample++)
                snn_correct_history[sample] <= '0;
        end else begin
            for (int port = 0; port < NUM_PORTS; port++) begin
                model_switch_pulse[port] <= 1'b0;
                model_selection_pulse[port] <= 1'b0;
                model_switch_reason[port] <= SWITCH_NONE;
                target_congested = actual_congestion_event[port];
                for (int delay = 0; delay < PREDICTION_HORIZON - 1; delay++)
                    target_congested |= event_history[delay][port];

                sample_count = int'(online_sample_count[port]);
                correct = int'(correct_sample_count[port]);
                desired_snn = 1'b0;
                reason = SWITCH_NONE;

                if (!OFFLINE_VALIDATION_PASSES) begin
                    reason = SWITCH_OFFLINE_ACCURACY;
                end else if (sample_count < MIN_ONLINE_SAMPLES &&
                             !valid_history[PREDICTION_HORIZON-1][port]) begin
                    reason = SWITCH_INSUFFICIENT_SAMPLES;
                end else begin
                    if (valid_history[PREDICTION_HORIZON-1][port]) begin
                        snn_correct =
                            snn_prediction_history[PREDICTION_HORIZON-1][port] ==
                            target_congested;
                        if (sample_count == ONLINE_WINDOW_SIZE) begin
                            correct = correct -
                                int'(snn_correct_history[write_pointer[port]][port]);
                        end else begin
                            sample_count = sample_count + 1;
                        end
                        correct = correct + int'(snn_correct);
                        snn_correct_history[write_pointer[port]][port] <= snn_correct;
                        if (write_pointer[port] == ONLINE_WINDOW_SIZE - 1)
                            write_pointer[port] <= '0;
                        else
                            write_pointer[port] <= write_pointer[port] + 1'b1;
                        correct_sample_count[port] <= SAMPLE_COUNT_WIDTH'(correct);
                        online_sample_count[port] <= SAMPLE_COUNT_WIDTH'(sample_count);
                    end

                    if (sample_count < MIN_ONLINE_SAMPLES) begin
                        reason = SWITCH_INSUFFICIENT_SAMPLES;
                    end else if (correct * 100 >
                                 sample_count * ACCURACY_THRESHOLD_PERCENT) begin
                        desired_snn = 1'b1;
                        reason = SWITCH_TO_SNN;
                    end else begin
                        reason = SWITCH_ONLINE_ACCURACY;
                    end
                end

                if (!OFFLINE_VALIDATION_PASSES) begin
                    desired_snn = 1'b0;
                    reason = SWITCH_OFFLINE_ACCURACY;
                end

                if (sample_count != 0)
                    next_accuracy = (correct * 100) / sample_count;
                else
                    next_accuracy = 0;
                online_accuracy_percent[port] <= 7'(next_accuracy);

                if (!selection_initialized[port]) begin
                    selection_initialized[port] <= 1'b1;
                    model_selection_pulse[port] <= 1'b1;
                    model_switch_reason[port] <= reason;
                end

                if (select_snn[port] != desired_snn) begin
                    select_snn[port] <= desired_snn;
                    model_switch_pulse[port] <= 1'b1;
                    model_selection_pulse[port] <= 1'b1;
                    model_switch_reason[port] <= reason;
                end
            end

            for (int delay = PREDICTION_HORIZON - 1; delay > 0; delay--) begin
                snn_prediction_history[delay] <= snn_prediction_history[delay-1];
                valid_history[delay] <= valid_history[delay-1];
                event_history[delay] <= event_history[delay-1];
            end
            snn_prediction_history[0] <= snn_prediction;
            valid_history[0] <= prediction_valid;
            event_history[0] <= actual_congestion_event;
        end
    end

    initial begin
        if (NUM_PORTS < 1)
            $fatal(1, "adaptive_predictor_selector requires at least one port");
        if (PREDICTION_HORIZON < 1)
            $fatal(1, "PREDICTION_HORIZON must be positive");
        if (ONLINE_WINDOW_SIZE < 1 ||
            MIN_ONLINE_SAMPLES < 1 ||
            MIN_ONLINE_SAMPLES > ONLINE_WINDOW_SIZE)
            $fatal(1, "Invalid online accuracy window/sample configuration");
        if (VALIDATION_ACCURACY_PERCENT < 0 ||
            VALIDATION_ACCURACY_PERCENT > 100 ||
            ACCURACY_THRESHOLD_PERCENT < 0 ||
            ACCURACY_THRESHOLD_PERCENT > 100)
            $fatal(1, "Accuracy percentages must be in the range 0 through 100");
        if (VALIDATION_CORRECT_SAMPLES < 0 ||
            VALIDATION_TOTAL_SAMPLES < 0 ||
            VALIDATION_CORRECT_SAMPLES > VALIDATION_TOTAL_SAMPLES)
            $fatal(1, "Invalid offline validation sample counts");
    end

endmodule
