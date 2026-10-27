// Directed router tests and simulation watchdog.
    // Watchdog prevents a broken handshake from hanging the simulation.
    initial begin
        $dumpfile("router_5port_tb.vcd");
        $dumpvars(0, router_5port_tb);
        repeat (500) @(posedge clk);
        $fatal(1, "FAIL: simulation timed out");
    end

    initial begin : run_tests
        logic [FLITWIDTH-1:0] flit_a;
        logic [FLITWIDTH-1:0] flit_b;

        results_file = $fopen("router_5port_results.txt", "w");
        if (results_file == 0)
            $fatal(1, "FAIL: unable to open router_5port_results.txt");
        report_line("Five-port router test results");
        report_line("");

        // Keep reset asserted for two clocks, then release it between edges.
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // TEST 1: Several sources contend for Local. Source 1 wins first and
        // becomes locked while Local is stalled. Higher-priority source 0 then
        // arrives, but it must not replace source 1's already-offered flit.
        // After source 1 transfers, round-robin order serves source 3 then 0.
        report_line("TEST 1: FIFO, round-robin arbitration, and stable stalled grant");
        flit_a = make_flit(3'd0, 45'd101);
        flit_b = make_flit(3'd0, 45'd103);
        out_ready[0] = 1'b0;
        send_flit(1, flit_a);
        send_flit(3, flit_b);
        send_flit(0, make_flit(3'd0, 45'd100));
        #1;
        if (!out_valid[0] || out_flit[0] !== flit_a)
            $fatal(1, "FAIL: first Local grant should be source 1's flit");
        @(negedge clk);
        out_ready[0] = 1'b1;
        expect_transfer(0, flit_a);
        expect_transfer(0, flit_b);
        expect_transfer(0, make_flit(3'd0, 45'd100));
        record_test_pass();

        // TEST 2: Send packets to every destination and check they leave the
        // matching output. This confirms destination decoding and switch paths.
        report_line("TEST 2: all five destination routes");
        for (int destination = 0; destination < NUMPORTS; destination++) begin
            logic [FLITWIDTH-1:0] expected;
            int source;

            expected = make_flit(destination[2:0], 45'(200 + destination));
            // Make the East example especially clear: a flit enters Local
            // (input 0), but its destination bits send it out through East
            // (output 3). Other destinations use a different source input.
            source = (destination == 3) ? 0 : (destination + 1) % NUMPORTS;
            send_flit(source, expected);
            expect_transfer(destination, expected);
        end
        record_test_pass();

        // TEST 3: Two different outputs can transfer in parallel on one clock.
        report_line("TEST 3: simultaneous transfers on separate outputs");
        flit_a = make_flit(3'd2, 45'd302);
        flit_b = make_flit(3'd4, 45'd504);
        out_ready[2] = 1'b0;
        out_ready[4] = 1'b0;
        send_flit(0, flit_a);
        send_flit(2, flit_b);
        #1;
        if (!out_valid[2] || out_flit[2] !== flit_a ||
            !out_valid[4] || out_flit[4] !== flit_b)
            $fatal(1, "FAIL: expected simultaneous South and West flits");
        out_ready[2] = 1'b1;
        out_ready[4] = 1'b1;
        @(posedge clk);
        #1;
        checks_passed++;
        record_test_pass();

        // TEST 4: Fill one input FIFO while its destination is blocked. The
        // first flit must remain stable at the output and the fifth write must
        // be backpressured until the receiver starts accepting flits.
        report_line("TEST 4: output backpressure and input FIFO capacity");
        out_ready[1] = 1'b0;
        for (int item = 0; item < 4; item++)
            send_flit(2, make_flit(3'd1, 45'(400 + item)));

        @(negedge clk);
        if (in_ready[2])
            $fatal(1, "FAIL: full input FIFO should deassert in_ready");
        if (!out_valid[1] || out_flit[1] !== make_flit(3'd1, 45'd400))
            $fatal(1, "FAIL: blocked output should hold the oldest flit");
        repeat (2) begin
            @(negedge clk);
            if (!out_valid[1] || out_flit[1] !== make_flit(3'd1, 45'd400))
                $fatal(1, "FAIL: output flit changed under backpressure");
        end

        // On this edge the old head is removed and the fifth flit is written;
        // the FIFO supports both operations together without losing data.
        in_flit[2] = make_flit(3'd1, 45'd404);
        in_valid[2] = 1'b1;
        out_ready[1] = 1'b1;
        #1;
        if (!in_ready[2])
            $fatal(1, "FAIL: full FIFO should accept write when read frees a slot");
        @(posedge clk);
        #1;
        in_valid[2] = 1'b0;
        checks_passed++;

        for (int item = 1; item <= 4; item++)
            expect_transfer(1, make_flit(3'd1, 45'(400 + item)));
        record_test_pass();

        // TEST 5: Invalid destination codes (5, 6, or 7) are discarded and
        // reported rather than permanently blocking their source FIFO.
        report_line("TEST 5: invalid destination is discarded and reported");
        send_flit(4, make_flit(3'd7, 45'd707));
        @(posedge clk);
        #1;
        if (!invalid_flit_dropped[4])
            $fatal(1, "FAIL: invalid destination should pulse drop status");
        checks_passed++;
        @(posedge clk);
        #1;
        if (invalid_flit_dropped[4])
            $fatal(1, "FAIL: invalid destination status should last one cycle");
        record_test_pass();

        // TEST 6: Per-requester wait time and per-output blocked time are
        // distinct measurements. The selected request is locked during
        // backpressure, but each simultaneous requester retains its own wait.
        report_line("TEST 6: requester wait and output blocked-cycle measurements");
        out_ready[0] = 1'b0;
        flit_a = make_flit(3'd0, 45'd800);
        flit_b = make_flit(3'd0, 45'd801);
        send_flit(0, flit_a);
        send_flit(1, flit_b);
        repeat (3) @(posedge clk);
        #1;

        if (ENABLE_TF_PCR) begin
            if (dut.requester_wait_cycles[0] <=
                dut.requester_wait_cycles[1])
                $fatal(1, "FAIL: per-requester wait counters did not distinguish contention age");
            if (dut.output_blocked_cycles[0] < 3)
                $fatal(1, "FAIL: output blocked-cycle counter did not advance");
            if (dut.out_valid[0] !== 1'b1 ||
                dut.out_flit[0] !== flit_a)
                $fatal(1, "FAIL: metric tracking changed the locked output flit");
        end

        @(negedge clk);
        out_ready[0] = 1'b1;
        @(posedge clk);
        #1;
        if (ENABLE_TF_PCR &&
            (dut.requester_wait_cycles[0] != 0 ||
             dut.output_blocked_cycles[0] != 0))
            $fatal(1, "FAIL: successful service did not reset requester/output wait counters");
        if (!out_valid[0] || out_flit[0] !== flit_b)
            $fatal(1, "FAIL: second contending input was not selected after first transfer");
        @(posedge clk);
        #1;
        if (ENABLE_TF_PCR &&
            (dut.requester_wait_cycles[1] != 0 ||
             dut.output_blocked_cycles[0] != 0))
            $fatal(1, "FAIL: completed request did not clear its wait metrics");
        repeat (2 * WINDOW_CYCLES) @(posedge clk);
        #1;
        if (ENABLE_TF_PCR &&
            (dut.allocator.last_window_request_count[0] != 0 ||
             dut.allocator.last_window_transfer_count[0] != 0 ||
             dut.allocator.last_window_service_deficit[0] != 0))
            $fatal(1, "FAIL: idle observation window should contain no demand, service, or deficit");
        record_test_pass();

        // TEST 7: A sustained service deficit saturates the counters and
        // raises the time-dominant score. Service recovers the temporal score.
        report_line("TEST 7: score normalization, counter saturation, and recovery");
        @(negedge clk);
        out_ready[0] = 1'b0;
        flit_a = make_flit(3'd0, 45'd900);
        send_flit(0, flit_a);
        repeat (260) @(posedge clk);
        #1;

        if (ENABLE_TF_PCR) begin
            if (dut.requester_wait_cycles[0] != 8'hff ||
                dut.output_blocked_cycles[0] != 8'hff)
                $fatal(1, "FAIL: wait and blocked counters should saturate at their maximum");
            if (dut.allocator.last_window_request_count[0] != WINDOW_CYCLES ||
                dut.allocator.last_window_transfer_count[0] != 0 ||
                dut.allocator.last_window_service_deficit[0] != WINDOW_CYCLES)
                $fatal(1, "FAIL: fixed-window demand/service counts or deficit are incorrect");
            if (dut.time_score[0] != 8'hff ||
                dut.frequency_score[0] != 8'hff ||
                dut.congestion_score[0] != 8'hff ||
                dut.congestion_predicted[0] !== 1'b1)
                $fatal(1, "FAIL: sustained deficit should saturate the score and assert prediction");
        end else if (dut.requester_wait_cycles != '0 ||
                     dut.output_blocked_cycles != '0 ||
                     dut.congestion_score != '0 ||
                     dut.congestion_predicted != '0) begin
            $fatal(1, "FAIL: disabled metrics must remain inactive");
        end

        @(negedge clk);
        out_ready[0] = 1'b1;
        expect_transfer(0, flit_a);
        if (ENABLE_TF_PCR &&
            (dut.requester_wait_cycles[0] != 0 ||
             dut.output_blocked_cycles[0] != 0 ||
             dut.time_score[0] != 0 ||
             dut.congestion_score[0] != 8'd63 ||
             dut.congestion_predicted[0] !== 1'b0))
            $fatal(1, "FAIL: successful service did not recover the temporal congestion score");
        record_test_pass();

        @(negedge clk);
        rst_n = 1'b0;
        #1;
        if (ENABLE_TF_PCR &&
            (dut.requester_wait_cycles != '0 ||
             dut.output_blocked_cycles != '0 ||
             dut.allocator.last_window_request_count != '0 ||
             dut.allocator.last_window_transfer_count != '0 ||
             dut.allocator.last_window_service_deficit != '0 ||
             dut.congestion_score != '0 ||
             dut.congestion_predicted != '0))
            $fatal(1, "FAIL: reset did not clear estimator and measurement state");
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        report_line($sformatf("ALL TESTS PASSED (%0d stage/transfer check points)",
                              checks_passed));
        $fclose(results_file);
        $finish;
    end