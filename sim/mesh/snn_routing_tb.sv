module snn_routing_tb;
    import noc_pkg::*;

    logic clk;
    logic rst_n;
    logic [4:0] in_valid;
    logic [4:0] in_ready;
    logic [4:0][63:0] in_flit;
    logic [4:0][1:0] in_priority;
    logic [4:0] out_valid;
    logic [4:0] out_ready;
    logic [4:0][63:0] out_flit;
    logic [4:0][1:0] out_priority;
    logic [4:0][1:0] output_buffer_occupancy;
    logic [4:0][7:0] congestion_score;
    logic [4:0] congestion_predicted;
    logic [4:0] occupancy_predicted;
    logic [4:0][2:0] input_occupancy;
    integer wait_cycles;

    noc_router_wrapper #(
        .ROUTING_MODE(1),
        .ENABLE_TF_PCR(1'b0),
        .ENABLE_SNN(1'b1),
        .ENABLE_OFFLOAD(1'b1),
        .FIFO_DEPTH(4)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .coordinate_x(2'd0),
        .coordinate_y(2'd1),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_flit(in_flit),
        .in_priority(in_priority),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_flit(out_flit),
        .out_priority(out_priority),
        .output_buffer_occupancy(output_buffer_occupancy),
        .congestion_score(congestion_score),
        .congestion_predicted(congestion_predicted),
        .occupancy_predicted(occupancy_predicted),
        .input_occupancy(input_occupancy)
    );

    always #5 clk = ~clk;

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    function automatic logic [63:0] make_flit(input logic [31:0] tag);
        logic [63:0] flit;
        begin
            flit = '0;
            flit[60:59] = 2'd1;
            flit[58:57] = 2'd0;
            flit[31:0] = tag;
            make_flit = flit;
        end
    endfunction

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        in_valid = '0;
        in_flit = '0;
        in_priority = '0;
        output_buffer_occupancy = '0;
        out_ready = 5'b10111; // East is blocked; North can accept.
        repeat (2) tick();
        rst_n = 1'b1;

        $display("SNN ROUTE TEST 1: no valid prediction uses preferred legal hop");
        in_valid[PORT_NORTH] = 1'b1;
        in_flit[PORT_NORTH] = make_flit(32'h0000_0001);
        #1;
        if (dut.computed_route[PORT_NORTH] != PORT_EAST ||
            !in_ready[PORT_NORTH])
            $fatal(1, "initial preferred route was not East");
        tick();
        in_valid[PORT_NORTH] = 1'b0;

        $display("SNN ROUTE TEST 2: future risk changes the selected legal route");
        wait_cycles = 0;
        while (wait_cycles < 40 && !dut.offload_active[PORT_EAST]) begin
            tick();
            wait_cycles = wait_cycles + 1;
        end
        if (!dut.snn_risk_valid[PORT_EAST] ||
            dut.snn_risk_class[PORT_EAST] < 2'd2 ||
            !dut.offload_active[PORT_EAST])
            $fatal(1, "persistent SNN risk did not trigger alternate-route control");

        in_valid[PORT_LOCAL] = 1'b1;
        in_flit[PORT_LOCAL] = make_flit(32'h0000_0002);
        #1;
        if (!in_ready[PORT_LOCAL] || dut.computed_route[PORT_LOCAL] != PORT_NORTH)
            $fatal(1, "SNN risk did not select the lower-risk legal North candidate");
        tick();
        in_valid[PORT_LOCAL] = 1'b0;
        #1;

        if (!out_valid[PORT_NORTH] || out_flit[PORT_NORTH][31:0] != 32'h0000_0002 ||
            !out_valid[PORT_EAST] || out_flit[PORT_EAST][31:0] != 32'h0000_0001)
            $fatal(1, "route/data mismatch: valid=%b north=%h east=%h route=%0d occ=%0d",
                out_valid, out_flit[PORT_NORTH][31:0], out_flit[PORT_EAST][31:0],
                dut.computed_route[PORT_LOCAL], input_occupancy[PORT_LOCAL]);
        tick();
        if (out_valid[PORT_NORTH])
            $fatal(1, "North flit was not consumed on its ready handshake");

        $display("SNN ROUTING INTEGRATION TESTS PASSED");
        $finish;
    end
endmodule
