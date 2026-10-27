// Fixed-point linear equation distilled from the trained integer SNN.
module distilled_congestion_predictor #(
    parameter int NUM_PORTS = noc_pkg::NUM_PORTS,
    parameter logic signed [55:0] COEFFICIENTS =
        distilled_congestion_model_pkg::EQUATION_COEFFICIENTS,
    parameter logic signed [11:0] BIAS =
        distilled_congestion_model_pkg::EQUATION_BIAS,
    parameter logic signed [11:0] THRESHOLD =
        distilled_congestion_model_pkg::EQUATION_THRESHOLD
) (
    input logic [NUM_PORTS*7-1:0] feature_events,
    input logic [NUM_PORTS-1:0] feature_valid,
    output logic [NUM_PORTS-1:0] congestion_risk,
    output logic signed [NUM_PORTS-1:0][11:0] equation_score
);

    always @* begin : p_equation
        logic signed [7:0] coefficient;
        logic signed [12:0] accumulator;
        congestion_risk = '0;
        equation_score = '0;
        for (int output_port = 0; output_port < NUM_PORTS; output_port++) begin
            accumulator = {{1{BIAS[11]}}, BIAS};
            for (int feature_index = 0; feature_index < 7; feature_index++) begin
                coefficient = COEFFICIENTS[feature_index*8 +: 8];
                if (feature_events[output_port*7 + feature_index])
                    accumulator = accumulator + {{5{coefficient[7]}}, coefficient};
            end
            if (accumulator > 13'sd2047)
                equation_score[output_port] = 12'sd2047;
            else if (accumulator < -13'sd2048)
                equation_score[output_port] = -12'sd2048;
            else
                equation_score[output_port] = accumulator[11:0];
            congestion_risk[output_port] = feature_valid[output_port] &&
                ($signed(equation_score[output_port]) >= $signed(THRESHOLD));
        end
    end
endmodule
