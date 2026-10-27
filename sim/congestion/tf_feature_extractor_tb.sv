module tf_feature_extractor_tb;
    localparam int NUM_PORTS = 2;

    logic clk;
    logic rst_n;
    logic [NUM_PORTS*NUM_PORTS-1:0] request;
    logic [NUM_PORTS-1:0] output_transfer;
    logic [NUM_PORTS-1:0][1:0] downstream_occupancy;
    logic [NUM_PORTS-1:0][2:0] requester_count;
    logic [NUM_PORTS-1:0][3:0] blocked_streak;
    logic [NUM_PORTS-1:0][1:0] pressure_trend;
    logic [NUM_PORTS-1:0][3:0] requester_cycles;
    logic [NUM_PORTS-1:0][2:0] demand_active_cycles;
    logic [NUM_PORTS-1:0][2:0] service_cycles;
    logic [NUM_PORTS-1:0][3:0] service_deficit;
    logic [NUM_PORTS-1:0][1:0] downstream_occupancy_current;
    logic [NUM_PORTS-1:0][1:0] downstream_occupancy_max;
    logic [NUM_PORTS-1:0] downstream_occupancy_rising;
    logic [NUM_PORTS-1:0] feature_valid;

    tf_feature_extractor #(
        .NUM_PORTS(NUM_PORTS),
        .WINDOW_CYCLES(4),
        .HISTORY_DEPTH(2)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .request(request),
        .output_transfer(output_transfer),
        .downstream_occupancy(downstream_occupancy),
        .requester_count(requester_count),
        .blocked_streak(blocked_streak),
        .pressure_trend(pressure_trend),
        .requester_cycles(requester_cycles),
        .demand_active_cycles(demand_active_cycles),
        .service_cycles(service_cycles),
        .service_deficit(service_deficit),
        .downstream_occupancy_current(downstream_occupancy_current),
        .downstream_occupancy_max(downstream_occupancy_max),
        .downstream_occupancy_rising(downstream_occupancy_rising),
        .feature_valid(feature_valid)
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
        request = '0;
        output_transfer = '0;
        downstream_occupancy = '0;
        repeat (2) tick();
        rst_n = 1'b1;

        $display("FEATURE TEST 1: reset, pressure, persistence, and window snapshot");
        request[1:0] = 2'b11;
        repeat (4) tick();
        if (requester_count[0] != 2 || blocked_streak[0] != 4 ||
            requester_cycles[0] != 8 || demand_active_cycles[0] != 4 ||
            service_cycles[0] != 0 || service_deficit[0] != 8 ||
            !feature_valid[0] || pressure_trend[0] != 2'd0)
            $fatal(1, "feature window/persistence mismatch: count=%0d blocked=%0d req=%0d active=%0d svc=%0d deficit=%0d trend=%0d valid=%b",
                requester_count[0], blocked_streak[0], requester_cycles[0],
                demand_active_cycles[0], service_cycles[0], service_deficit[0],
                pressure_trend[0], feature_valid[0]);

        $display("FEATURE TEST 2: recovery, service accounting, and falling pressure");
        request[1:0] = 2'b01;
        tick();
        if (pressure_trend[0] != 2'd2 || blocked_streak[0] != 5)
            $fatal(1, "falling pressure or blocked streak mismatch: trend=%0d blocked=%0d count=%0d oldest=%0d",
                pressure_trend[0], blocked_streak[0], requester_count[0],
                dut.pressure_history[1][0]);
        repeat (2) tick();
        if (blocked_streak[0] != 7)
            $fatal(1, "blocked persistence count did not advance");
        output_transfer[0] = 1'b1;
        tick();
        output_transfer[0] = 1'b0;
        if (blocked_streak[0] != 0 || requester_cycles[0] != 4 ||
            demand_active_cycles[0] != 4 || service_cycles[0] != 1 ||
            service_deficit[0] != 3)
            $fatal(1, "service/recovery snapshot mismatch");

        $display("FEATURE TEST 3: rising trend and asynchronous reset");
        request[1:0] = 2'b11;
        @(negedge clk);
        downstream_occupancy[0] = 2'd1;
        #1;
        if (!downstream_occupancy_rising[0] ||
            downstream_occupancy_current[0] != 1 ||
            downstream_occupancy_max[0] != 1)
            $fatal(1, "downstream occupancy growth was not exposed as a feature");
        tick();
        if (pressure_trend[0] != 2'd1)
            $fatal(1, "rising pressure was not detected");
        rst_n = 1'b0;
        #1;
        if (blocked_streak[0] != 0 || requester_cycles[0] != 0 ||
            demand_active_cycles[0] != 0 || service_cycles[0] != 0 ||
            service_deficit[0] != 0 || feature_valid[0])
            $fatal(1, "feature state did not reset cleanly");

        $display("TF FEATURE EXTRACTOR TESTS PASSED");
        $finish;
    end
endmodule
