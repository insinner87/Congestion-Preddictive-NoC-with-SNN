module adaptive_buffer_controller_tb;
    localparam int NUM_INPUTS = 2;

    logic clk;
    logic rst_n;
    logic [NUM_INPUTS-1:0][2:0] occupancy;
    logic [NUM_INPUTS-1:0] early_pressure;
    logic [NUM_INPUTS-1:0] persistence_pressure;

    adaptive_buffer_controller #(
        .NUM_INPUTS(NUM_INPUTS),
        .FIFO_DEPTH(4),
        .OCCUPANCY_WIDTH(3)
    ) early_dut (
        .clk(clk),
        .rst_n(rst_n),
        .occupancy(occupancy),
        .buffer_pressure(early_pressure)
    );

    adaptive_buffer_controller #(
        .NUM_INPUTS(NUM_INPUTS),
        .FIFO_DEPTH(4),
        .OCCUPANCY_WIDTH(3),
        .EARLY_OCCUPANCY_THRESHOLD(5)
    ) persistence_dut (
        .clk(clk),
        .rst_n(rst_n),
        .occupancy(occupancy),
        .buffer_pressure(persistence_pressure)
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
        occupancy = '0;
        repeat (2) tick();
        rst_n = 1'b1;

        $display("BUFFER TEST 1: rising occupancy asserts early pressure");
        occupancy[0] = 2;
        tick();
        if (!early_pressure[0])
            $fatal(1, "rising occupancy did not assert early notification");
        if (persistence_pressure[0])
            $fatal(1, "persistence-only controller asserted below its high threshold");

        $display("BUFFER TEST 2: sustained high occupancy and recovery hysteresis");
        occupancy[0] = 3;
        occupancy[1] = 3;
        tick();
        if (persistence_pressure[0])
            $fatal(1, "persistence-only controller asserted after one high cycle");
        tick();
        if (!persistence_pressure[0])
            $fatal(1, "sustained high occupancy did not assert pressure");
        occupancy = 2;
        tick();
        if (!early_pressure[0] || !persistence_pressure[0])
            $fatal(1, "pressure released before the recovery persistence window");
        tick();
        if (early_pressure[0] || persistence_pressure[0])
            $fatal(1, "pressure did not recover below the lower threshold");

        $display("BUFFER TEST 3: asynchronous reset");
        occupancy[0] = 3;
        tick();
        rst_n = 1'b0;
        #1;
        if (early_pressure != '0 || persistence_pressure != '0)
            $fatal(1, "buffer pressure did not clear on reset");

        $display("ADAPTIVE BUFFER CONTROLLER TESTS PASSED");
        $finish;
    end
endmodule
