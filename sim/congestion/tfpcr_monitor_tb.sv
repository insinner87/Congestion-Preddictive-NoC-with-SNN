module tfpcr_monitor_tb;

    localparam int NUM_PORTS = noc_pkg::NUM_PORTS;
    localparam int WINDOW_CYCLES = 4;
    localparam int WAIT_WIDTH = 8;
    localparam int BLOCKED_WIDTH = 8;
    localparam int REQUEST_COUNT_WIDTH = $clog2(WINDOW_CYCLES * NUM_PORTS + 1);
    localparam int TRANSFER_COUNT_WIDTH = $clog2(WINDOW_CYCLES + 1);

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [NUM_PORTS*NUM_PORTS-1:0] request = '0;
    logic [NUM_PORTS-1:0] output_transfer = '0;
    logic [NUM_PORTS-1:0][2:0] grant_index = '0;
    logic [NUM_PORTS*NUM_PORTS-1:0][WAIT_WIDTH-1:0] requester_wait_cycles;
    logic [NUM_PORTS-1:0][BLOCKED_WIDTH-1:0] output_blocked_cycles;
    logic [NUM_PORTS-1:0][REQUEST_COUNT_WIDTH-1:0] last_window_request_count;
    logic [NUM_PORTS-1:0][TRANSFER_COUNT_WIDTH-1:0] last_window_transfer_count;
    logic [NUM_PORTS-1:0][REQUEST_COUNT_WIDTH-1:0] last_window_service_deficit;
    logic [NUM_PORTS-1:0][7:0] time_score;
    logic [NUM_PORTS-1:0][7:0] frequency_score;
    logic [NUM_PORTS-1:0][7:0] congestion_score;
    logic [NUM_PORTS-1:0] congestion_predicted;

    always #5 clk = ~clk;

    congestion_monitor #(
        .NUM_PORTS(NUM_PORTS),
        .INDEX_WIDTH(3),
        .WAIT_COUNTER_WIDTH(WAIT_WIDTH),
        .BLOCKED_COUNTER_WIDTH(BLOCKED_WIDTH),
        .WINDOW_CYCLES(WINDOW_CYCLES)
    ) monitor (.*);

    congestion_estimator #(
        .NUM_PORTS(NUM_PORTS),
        .WAIT_COUNTER_WIDTH(WAIT_WIDTH),
        .BLOCKED_COUNTER_WIDTH(BLOCKED_WIDTH),
        .REQUEST_COUNT_WIDTH(REQUEST_COUNT_WIDTH)
    ) estimator (
        .requester_wait_cycles(requester_wait_cycles),
        .output_blocked_cycles(output_blocked_cycles),
        .service_deficit(last_window_service_deficit),
        .time_score(time_score),
        .frequency_score(frequency_score),
        .congestion_score(congestion_score),
        .congestion_predicted(congestion_predicted)
    );

    initial begin : run_monitor_checks
        request[2] = 1'b0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        $display("TEST 1: withdrawn request clears only its wait state");
        @(negedge clk);
        request[2] = 1'b1;
        repeat (3) @(posedge clk);
        #1;
        if (requester_wait_cycles[2] != 3 ||
            output_blocked_cycles[0] != 3)
            $fatal(1, "wait or blocked-cycle counter did not count exactly once per cycle");

        @(negedge clk);
        request[2] = 1'b0;
        @(posedge clk);
        #1;
        if (requester_wait_cycles[2] != 0 ||
            output_blocked_cycles[0] != 0)
            $fatal(1, "withdrawn request did not clear its temporal measurements");

        $display("TEST 2: same-window demand/service, contention, and boundary snapshot");
        @(negedge clk);
        rst_n = 1'b0;
        request = '0;
        output_transfer = '0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        request[0] = 1'b1;
        request[1] = 1'b1;
        request[NUM_PORTS] = 1'b1;
        output_transfer[0] = 1'b1;
        output_transfer[1] = 1'b1;
        grant_index[0] = 3'd0;
        grant_index[1] = 3'd0;

        for (int cycle = 1; cycle <= WINDOW_CYCLES; cycle++) begin
            @(posedge clk);
            #1;
            if (requester_wait_cycles[0] != 0 ||
                requester_wait_cycles[1] != cycle ||
                output_blocked_cycles[0] != 0)
                $fatal(1, "simultaneous transfer/requester wait update failed at cycle %0d",
                       cycle);
        end

        if (last_window_request_count[0] != 8 ||
            last_window_transfer_count[0] != 4 ||
            last_window_service_deficit[0] != 4)
            $fatal(1, "window boundary demand/service/deficit snapshot is incorrect");
        if (last_window_request_count[1] != 4 ||
            last_window_transfer_count[1] != 4 ||
            last_window_service_deficit[1] != 0)
            $fatal(1, "successfully serviced high-rate output was misclassified as deficient");
        if (time_score[0] != 8'd63 ||
            frequency_score[0] != 8'd127 ||
            congestion_score[0] != 8'd79 ||
            congestion_predicted[0])
            $fatal(1, "normalization or default 3:1 score weighting is incorrect");
        if (frequency_score[1] != 0 || congestion_score[1] != 0)
            $fatal(1, "service matching demand should produce no frequency score");

        $display("TEST 3: saturation and asynchronous reset");
        @(negedge clk);
        rst_n = 1'b0;
        request = '0;
        output_transfer = '0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        request[3] = 1'b1;
        repeat (260) @(posedge clk);
        #1;
        if (requester_wait_cycles[3] != 8'hff ||
            output_blocked_cycles[0] != 8'hff)
            $fatal(1, "temporal counters did not saturate at 8'hff");

        @(negedge clk);
        rst_n = 1'b0;
        #1;
        if (requester_wait_cycles != '0 ||
            output_blocked_cycles != '0 ||
            last_window_request_count != '0 ||
            last_window_transfer_count != '0 ||
            last_window_service_deficit != '0 ||
            time_score != '0 ||
            frequency_score != '0 ||
            congestion_score != '0 ||
            congestion_predicted != '0)
            $fatal(1, "reset did not clear measurement and estimator state");

        $display("TF-PCR MONITOR TESTS PASSED");
        $finish;
    end

    initial begin
        repeat (400) @(posedge clk);
        $fatal(1, "monitor test timed out");
    end

endmodule
