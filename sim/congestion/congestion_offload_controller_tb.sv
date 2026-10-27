module congestion_offload_controller_tb;
    localparam int NUM_PORTS = 2;

    logic clk;
    logic rst_n;
    logic [NUM_PORTS-1:0][1:0] risk_class;
    logic [NUM_PORTS-1:0] risk_valid;
    logic [NUM_PORTS-1:0] offload_active;
    logic [NUM_PORTS-1:0] offload_start_pulse;

    congestion_offload_controller #(
        .NUM_PORTS(NUM_PORTS),
        .TRIGGER_CYCLES(2),
        .RECOVERY_CYCLES(2)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .risk_class(risk_class),
        .risk_valid(risk_valid),
        .offload_active(offload_active),
        .offload_start_pulse(offload_start_pulse)
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
        risk_class = '0;
        risk_valid = '0;
        repeat (2) tick();
        rst_n = 1'b1;

        $display("OFFLOAD TEST 1: short risk spike does not trigger");
        risk_valid[0] = 1'b1;
        risk_class[0] = 2'd3;
        tick();
        risk_class[0] = 2'd0;
        tick();
        if (offload_active[0] || offload_start_pulse[0])
            $fatal(1, "transient prediction triggered offloading");

        $display("OFFLOAD TEST 2: persistent risk triggers and low risk recovers");
        risk_class[0] = 2'd2;
        repeat (2) tick();
        if (!offload_active[0] || !offload_start_pulse[0])
            $fatal(1, "persistent risk did not assert offloading");
        risk_class[0] = 2'd1;
        tick();
        if (!offload_active[0])
            $fatal(1, "offloading released before the recovery window");
        tick();
        if (offload_active[0])
            $fatal(1, "offloading did not release below recovery class");

        $display("OFFLOAD TEST 3: invalid/reset predictor safely clears trigger");
        risk_class[0] = 2'd3;
        repeat (2) tick();
        if (!offload_active[0])
            $fatal(1, "second persistent trigger did not assert");
        risk_valid[0] = 1'b0;
        tick();
        if (offload_active[0] || offload_start_pulse[0])
            $fatal(1, "invalid predictor state did not fall back safely");
        rst_n = 1'b0;
        #1;
        if (offload_active != '0)
            $fatal(1, "offload state did not clear on reset");

        $display("CONGESTION OFFLOAD CONTROLLER TESTS PASSED");
        $finish;
    end
endmodule
