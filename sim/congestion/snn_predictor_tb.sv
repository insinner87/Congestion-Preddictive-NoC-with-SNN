module snn_predictor_tb;
    localparam int NUM_PORTS = 1;

    logic clk;
    logic rst_n;
    logic [NUM_PORTS*7-1:0] feature_spikes;
    logic [NUM_PORTS-1:0] feature_valid;
    logic [NUM_PORTS-1:0][1:0] risk_class;
    logic [NUM_PORTS-1:0] output_spike;
    logic [NUM_PORTS-1:0] risk_valid;
    logic [NUM_PORTS-1:0] state_update_enable;

    // Unit-test parameters are deliberately spike-friendly so this test checks
    // LIF reset/leak mechanics independently of whichever trained package is exported.
    snn_predictor #(
        .NUM_PORTS(NUM_PORTS),
        .W_HIDDEN_0(14'h3fff),
        .W_HIDDEN_1(14'h3fff),
        .W_HIDDEN_2(14'h3fff),
        .W_HIDDEN_3(14'h3fff),
        .W_OUTPUT(8'hff),
        .HIDDEN_THRESHOLD(8'd8),
        .OUTPUT_THRESHOLD(8'd6),
        .POTENTIAL_MAX(8'd63)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .feature_spikes(feature_spikes),
        .feature_valid(feature_valid),
        .risk_class(risk_class),
        .output_spike(output_spike),
        .risk_valid(risk_valid),
        .state_update_enable(state_update_enable)
    );

    always #5 clk = ~clk;

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        feature_spikes = '0;
        feature_valid = '0;
        repeat (2) tick();
        rst_n = 1'b1;

        $display("SNN TEST 1: deterministic reset and valid gating");
        #1;
        if (risk_valid[0] || output_spike[0] || risk_class[0] != 0)
            $fatal(1, "invalid feature window did not use safe output");

        $display("SNN TEST 2: encoded events integrate and produce LIF spikes");
        feature_valid[0] = 1'b1;
        feature_spikes[6:0] = 7'b1111111;
        #1;
        if (!risk_valid[0] || risk_class[0] < 2 || !state_update_enable[0])
            $fatal(1, "strong feature events did not raise the risk class");
        repeat (4) tick();
        if (!output_spike[0] || risk_class[0] != 3)
            $fatal(1, "LIF output did not reach its spike threshold");

        $display("SNN TEST 3: leak and deterministic recovery");
        feature_spikes[6:0] = '0;
        repeat (16) tick();
        if (risk_class[0] != 0 || output_spike[0] || state_update_enable[0])
            $fatal(1, "membrane potential did not decay after input events");

        feature_valid[0] = 1'b0;
        rst_n = 1'b0;
        #1;
        if (risk_valid[0] || risk_class[0] != 0 || output_spike[0])
            $fatal(1, "asynchronous reset did not clear predictor output");

        $display("SNN PREDICTOR TESTS PASSED");
        $finish;
    end
endmodule
