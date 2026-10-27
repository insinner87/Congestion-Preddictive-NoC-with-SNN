module distilled_predictor_tb;
    localparam int NUM_PORTS = 2;

    logic [NUM_PORTS*7-1:0] feature_events;
    logic [NUM_PORTS-1:0] feature_valid;
    logic [NUM_PORTS-1:0] congestion_risk;
    logic signed [NUM_PORTS-1:0][11:0] equation_score;
    integer expected_score;
    integer trial;
    integer port;
    integer bit_index;

    distilled_congestion_predictor #(.NUM_PORTS(NUM_PORTS)) dut (.*);

    initial begin
        feature_events = '0;
        feature_valid = '0;
        for (trial = 0; trial < 1000; trial = trial + 1) begin
            for (port = 0; port < NUM_PORTS; port = port + 1) begin
                feature_valid[port] = $urandom_range(0, 1);
                for (bit_index = 0; bit_index < 7; bit_index = bit_index + 1)
                    feature_events[port*7 + bit_index] = $urandom_range(0, 1);
            end
            #1;
            for (port = 0; port < NUM_PORTS; port = port + 1) begin
                expected_score = $signed(distilled_congestion_model_pkg::EQUATION_BIAS);
                for (bit_index = 0; bit_index < 7; bit_index = bit_index + 1)
                    if (feature_events[port*7 + bit_index])
                        expected_score += $signed(
                            distilled_congestion_model_pkg::EQUATION_COEFFICIENTS[
                                bit_index*8 +: 8]);
                if (expected_score > 2047) expected_score = 2047;
                if (expected_score < -2048) expected_score = -2048;
                if ($signed(equation_score[port]) != expected_score)
                    $fatal(1, "score mismatch on port %0d: got %0d expected %0d",
                        port, $signed(equation_score[port]), expected_score);
                if (congestion_risk[port] !==
                    (feature_valid[port] && expected_score >=
                        $signed(distilled_congestion_model_pkg::EQUATION_THRESHOLD)))
                    $fatal(1, "risk mismatch on port %0d", port);
            end
        end
        $display("DISTILLED EQUATION RANDOMIZED TEST PASSED (2000 package-coefficient vectors)");
        $finish;
    end
endmodule
