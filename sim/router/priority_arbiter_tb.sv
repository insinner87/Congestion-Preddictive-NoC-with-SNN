module priority_arbiter_tb;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [2:0] request = '0;
    logic [2:0][1:0] request_priority = '0;
    logic ready = 1'b1;
    logic [2:0] grant_onehot;
    logic grant_valid;
    logic [1:0] grant_index;

    round_robin_arbiter #(
        .NUM_REQUESTERS(3),
        .INDEX_WIDTH(2),
        .ENABLE_PRIORITY(1'b1),
        .AGE_LIMIT(4)
    ) dut (.*);

    always #5 clk = ~clk;

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic expect_winner(input integer requester);
        begin
            #1;
            if (!grant_valid || grant_index != requester ||
                grant_onehot != (3'b001 << requester))
                $fatal(1, "expected requester %0d; valid=%b index=%0d onehot=%b",
                       requester, grant_valid, grant_index, grant_onehot);
        end
    endtask

    task automatic reset_dut;
        begin
            rst_n = 1'b0;
            request = '0;
            request_priority = '0;
            ready = 1'b1;
            repeat (2) tick();
            rst_n = 1'b1;
            #1;
        end
    endtask

    initial begin
        $display("PRIORITY TEST 1: highest class wins first");
        reset_dut();
        request = 3'b111;
        request_priority[0] = 2'd0;
        request_priority[1] = 2'd1;
        request_priority[2] = 2'd3;
        expect_winner(2);

        $display("PRIORITY TEST 2: waiting lower classes age into service");
        for (int cycle = 0; cycle < 4; cycle++) begin
            expect_winner(2);
            tick();
        end
        expect_winner(0);
        tick();
        expect_winner(1);

        $display("PRIORITY TEST 3: equal classes rotate round-robin");
        reset_dut();
        request = 3'b011;
        request_priority[0] = 2'd2;
        request_priority[1] = 2'd2;
        expect_winner(0);
        tick();
        expect_winner(1);
        tick();
        expect_winner(0);

        $display("PRIORITY TEST 4: stalled grants remain stable through priority changes");
        reset_dut();
        request = 3'b111;
        request_priority[0] = 2'd0;
        request_priority[1] = 2'd1;
        request_priority[2] = 2'd3;
        ready = 1'b0;
        expect_winner(2);
        tick();
        request_priority[0] = 2'd3;
        expect_winner(2);
        ready = 1'b1;
        tick();

        $display("PRIORITY ARBITER TESTS PASSED");
        $finish;
    end
endmodule
