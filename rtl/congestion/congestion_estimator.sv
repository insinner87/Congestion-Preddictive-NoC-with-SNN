// Integer-only congestion score for measured wait time and service deficit.
//
// Time and frequency are independently normalized to 0..255. The default
// 3:1 weighting makes temporal persistence the primary signal.
module congestion_estimator #(
    parameter int NUM_PORTS = noc_pkg::NUM_PORTS,
    parameter int WAIT_COUNTER_WIDTH = 8,
    parameter int BLOCKED_COUNTER_WIDTH = 8,
    parameter int REQUEST_COUNT_WIDTH = 8,
    parameter int TIME_SCORE_SATURATION = 16,
    parameter int FREQ_SCORE_SATURATION = 8,
    parameter int TIME_WEIGHT = 3,
    parameter int FREQ_WEIGHT = 1,
    parameter logic [7:0] SCORE_THRESHOLD = 8'd128
) (
    input logic [NUM_PORTS*NUM_PORTS-1:0][WAIT_COUNTER_WIDTH-1:0]
        requester_wait_cycles,
    input logic [NUM_PORTS-1:0][BLOCKED_COUNTER_WIDTH-1:0]
        output_blocked_cycles,
    input logic [NUM_PORTS-1:0][REQUEST_COUNT_WIDTH-1:0] service_deficit,

    output logic [NUM_PORTS-1:0][7:0] time_score,
    output logic [NUM_PORTS-1:0][7:0] frequency_score,
    output logic [NUM_PORTS-1:0][7:0] congestion_score,
    output logic [NUM_PORTS-1:0] congestion_predicted
);

    function automatic logic [7:0] normalize_time(input longint unsigned cycles);
        longint unsigned scaled_value;

        if (cycles >= TIME_SCORE_SATURATION) begin
            normalize_time = 8'hff;
        end else begin
            scaled_value = cycles * 64'd255;
            normalize_time = scaled_value / TIME_SCORE_SATURATION;
        end
    endfunction

    function automatic logic [7:0] normalize_frequency(
        input logic [REQUEST_COUNT_WIDTH-1:0] deficit
    );
        longint unsigned scaled_value;

        if (deficit >= FREQ_SCORE_SATURATION) begin
            normalize_frequency = 8'hff;
        end else begin
            scaled_value = deficit * 64'd255;
            normalize_frequency = scaled_value / FREQ_SCORE_SATURATION;
        end
    endfunction

    always_comb begin : p_score_outputs
        logic [WAIT_COUNTER_WIDTH-1:0] largest_wait;
        logic [7:0] blocked_score;
        logic [15:0] weighted_sum;

        time_score = '0;
        frequency_score = '0;
        congestion_score = '0;
        congestion_predicted = '0;
        largest_wait = '0;
        blocked_score = '0;
        weighted_sum = '0;

        for (int output_port = 0; output_port < NUM_PORTS; output_port++) begin
            largest_wait = '0;
            for (int input_port = 0; input_port < NUM_PORTS; input_port++) begin
                if (requester_wait_cycles[output_port * NUM_PORTS + input_port] >
                    largest_wait)
                    largest_wait =
                        requester_wait_cycles[output_port * NUM_PORTS + input_port];
            end

            time_score[output_port] = normalize_time(largest_wait);
            blocked_score = normalize_time(output_blocked_cycles[output_port]);
            if (blocked_score > time_score[output_port])
                time_score[output_port] = blocked_score;

            frequency_score[output_port] =
                normalize_frequency(service_deficit[output_port]);
            weighted_sum =
                TIME_WEIGHT * time_score[output_port] +
                FREQ_WEIGHT * frequency_score[output_port];
            congestion_score[output_port] =
                weighted_sum / (TIME_WEIGHT + FREQ_WEIGHT);
            congestion_predicted[output_port] =
                congestion_score[output_port] >= SCORE_THRESHOLD;
        end
    end

    initial begin
        if (TIME_SCORE_SATURATION < 1 || FREQ_SCORE_SATURATION < 1)
            $fatal(1, "score normalization thresholds must be at least one");
        if (TIME_WEIGHT < 1 || FREQ_WEIGHT < 1 ||
            TIME_WEIGHT + FREQ_WEIGHT > 255)
            $fatal(1, "score weights must be positive and sum to at most 255");
    end

endmodule
