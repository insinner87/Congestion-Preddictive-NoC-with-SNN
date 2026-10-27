module equation_routing_tb;
    import noc_pkg::*;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [1:0] coordinate_x = 2'd0;
    logic [1:0] coordinate_y = 2'd1;
    logic [4:0] in_valid = '0;
    logic [4:0] in_ready;
    logic [4:0][63:0] in_flit = '0;
    logic [4:0][1:0] in_priority = '0;
    logic [4:0] out_valid;
    logic [4:0] out_ready = '1;
    logic [4:0][63:0] out_flit;
    logic [4:0][1:0] out_priority;
    logic [4:0][1:0] output_buffer_occupancy = '0;
    logic [4:0][7:0] congestion_score;
    logic [4:0] congestion_predicted;
    logic [4:0] occupancy_predicted;
    logic [4:0][2:0] input_occupancy;
    integer wait_count;

    always #5 clk = ~clk;

    noc_router_wrapper #(
        .ROUTING_MODE(1), .ENABLE_TF_PCR(1'b0), .ENABLE_SNN(1'b0),
        .ENABLE_SNN_ROUTING(1'b0), .ENABLE_EQUATION_ROUTING(1'b1),
        .ENABLE_ADAPTIVE_BUFFER(1'b0), .FIFO_DEPTH(4),
        .OUTPUT_BUFFER_DEPTH(2), .OUTPUT_BUFFER_OCCUPANCY_WIDTH(2)
    ) dut (.*);

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
        out_ready[PORT_EAST] = 1'b0;
        repeat (2) tick();
        rst_n = 1'b1;

        // Occupy the candidate East link and hold a head flit requesting it.
        output_buffer_occupancy[PORT_EAST] = 2'd2;
        in_valid[PORT_NORTH] = 1'b1;
        in_flit[PORT_NORTH] = make_flit(32'h0000_00a1);
        #1;
        if (dut.computed_route[PORT_NORTH] != PORT_EAST)
            $fatal(1, "test setup failed: first flit should request East");
        tick();
        in_valid[PORT_NORTH] = 1'b0;
        repeat (12) tick();

        if (!dut.tf_feature_valid[PORT_EAST] ||
            !dut.equation_risk[PORT_EAST] ||
            !dut.tf_encoded_features[PORT_EAST*7])
            $fatal(1, "measured congestion did not produce a valid equation risk: features=%b score=%0d",
                dut.tf_encoded_features[PORT_EAST*7 +: 7],
                $signed(dut.equation_score[PORT_EAST]));

        // From (0,1) to (1,0), both East and North are legal West-First hops.
        // The trained equation must send the second flit through the available North link.
        in_valid[PORT_LOCAL] = 1'b1;
        in_flit[PORT_LOCAL] = make_flit(32'h0000_00b2);
        #1;
        if (dut.computed_route[PORT_LOCAL] != PORT_NORTH ||
            !dut.computed_route_valid[PORT_LOCAL])
            $fatal(1, "trained equation did not select the legal lower-risk North hop");
        tick();
        in_valid[PORT_LOCAL] = 1'b0;
        wait_count = 0;
        while (!out_valid[PORT_NORTH] && wait_count < 8) begin
            tick();
            wait_count++;
        end
        if (!out_valid[PORT_NORTH] || out_flit[PORT_NORTH][31:0] != 32'h0000_00b2)
            $fatal(1, "rerouted flit was not delivered intact on North");

        // If North is unavailable, retain the preferred legal East hop rather
        // than selecting an output that cannot currently accept traffic.
        out_ready[PORT_NORTH] = 1'b0;
        in_flit[PORT_LOCAL] = make_flit(32'h0000_00c3);
        in_valid[PORT_LOCAL] = 1'b1;
        #1;
        if (dut.computed_route[PORT_LOCAL] != PORT_EAST)
            $fatal(1, "unavailable alternate did not fall back to the preferred legal hop");
        in_valid[PORT_LOCAL] = 1'b0;

        $display("EQUATION PREDICTIVE ROUTING TEST PASSED: measured East risk -> available legal North; unavailable North -> East fallback");
        $finish;
    end
endmodule
