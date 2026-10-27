// Stage-level assertions, reference FIFO model, and cycle scoreboard.
    // Validate the signals between every router stage, not only the public
    // input/output behavior. The model also checks per-input FIFO ordering.
    task automatic check_stages(input string phase);
        logic [NUMPORTS-1:0] expected_requests;
        logic [FLITWIDTH-1:0] expected_output_flit;
        logic [2:0] destination;
        int grant_count;

        for (int input_port = 0; input_port < NUMPORTS; input_port++) begin
            if (dut.buffer_valid[input_port] !== (queue_count[input_port] != 0))
                $fatal(1, "FAIL (%s): input %0d FIFO valid=%b, expected %b",
                       phase, input_port, dut.buffer_valid[input_port],
                       queue_count[input_port] != 0);
            if (queue_count[input_port] != 0 &&
                dut.buffer_flit[input_port] !==
                    expected_flits[input_port][queue_read[input_port]])
                $fatal(1, "FAIL (%s): input %0d FIFO head=%h, expected %h",
                       phase, input_port, dut.buffer_flit[input_port],
                       expected_flits[input_port][queue_read[input_port]]);

            if (in_ready[input_port] !==
                ((queue_count[input_port] < noc_pkg::FIFO_DEPTH) ||
                 dut.buffer_pop[input_port]))
                $fatal(1, "FAIL (%s): input %0d ready does not match FIFO capacity/pop",
                       phase, input_port);

            expected_requests = '0;
            destination = dut.buffer_flit[input_port] >> (FLITWIDTH - 3);
            if (dut.buffer_valid[input_port]) begin
                if (destination < NUMPORTS)
                    expected_requests[destination] = 1'b1;
            end

            for (int output_port = 0; output_port < NUMPORTS; output_port++) begin
                if (dut.allocator.request[output_port * NUMPORTS + input_port] !==
                    expected_requests[output_port])
                    $fatal(1, "FAIL (%s): request mismatch input %0d -> output %0d",
                           phase, input_port, output_port);
            end

            if (dut.invalid_head[input_port] !==
                (dut.buffer_valid[input_port] &&
                 (destination >= NUMPORTS)))
                $fatal(1, "FAIL (%s): invalid-head decode mismatch on input %0d",
                       phase, input_port);
        end

        for (int output_port = 0; output_port < NUMPORTS; output_port++) begin
            grant_count = 0;
            expected_output_flit = '0;
            for (int input_port = 0; input_port < NUMPORTS; input_port++) begin
                if (dut.grant[output_port * NUMPORTS + input_port]) begin
                    grant_count++;
                    if (!dut.allocator.request[output_port * NUMPORTS + input_port])
                        $fatal(1, "FAIL (%s): grant is not backed by a request (%0d -> %0d)",
                               phase, input_port, output_port);
                    expected_output_flit = dut.buffer_flit[input_port];
                end
            end

            if (grant_count > 1)
                $fatal(1, "FAIL (%s): output %0d has %0d simultaneous grants",
                       phase, output_port, grant_count);
            if (dut.grant_valid[output_port] !== (grant_count != 0))
                $fatal(1, "FAIL (%s): grant_valid mismatch on output %0d",
                       phase, output_port);
            if (out_valid[output_port] !== dut.grant_valid[output_port])
                $fatal(1, "FAIL (%s): crossbar valid mismatch on output %0d",
                       phase, output_port);
            if (out_flit[output_port] !== expected_output_flit)
                $fatal(1, "FAIL (%s): crossbar data mismatch on output %0d; got %h expected %h",
                       phase, output_port, out_flit[output_port], expected_output_flit);
        end

        for (int input_port = 0; input_port < NUMPORTS; input_port++) begin
            begin : check_input_pop
                logic expected_pop;
                expected_pop = 1'b0;
                for (int output_port = 0; output_port < NUMPORTS; output_port++)
                    if (dut.grant[output_port * NUMPORTS + input_port] &&
                        out_ready[output_port])
                        expected_pop = 1'b1;
                if (dut.crossbar_pop[input_port] !== expected_pop)
                    $fatal(1, "FAIL (%s): crossbar pop mismatch on input %0d",
                           phase, input_port);
            end
            if (dut.buffer_pop[input_port] !==
                (dut.crossbar_pop[input_port] | dut.invalid_head[input_port]))
                $fatal(1, "FAIL (%s): FIFO pop mismatch on input %0d",
                       phase, input_port);
        end
        checks_passed++;
    endtask

    task automatic report_line(input string message);
        $display("%s", message);
        $fdisplay(results_file, "%s", message);
        $fflush(results_file);
    endtask

    task automatic record_test_pass();
        report_line("  PASS");
    endtask

    // At each active edge, compare transfers with the reference queues. A
    // trace line records all boundary handshakes and each active stage.
    always @(posedge clk) begin : p_stage_checker
        logic [NUMPORTS-1:0] popped;
        logic [NUMPORTS-1:0] invalid_this_edge;
        int selected_input;

        if (!rst_n) begin
            for (int input_port = 0; input_port < NUMPORTS; input_port++) begin
                queue_read[input_port] = 0;
                queue_write[input_port] = 0;
                queue_count[input_port] = 0;
            end
            previous_invalid = '0;
            input_stalled = '0;
            output_stalled = '0;
            invalid_this_edge = '0;
        end else begin
            check_stages("before clock edge");
            if (invalid_flit_dropped !== previous_invalid)
                $fatal(1, "FAIL: invalid-drop status does not match the previous cycle");

            for (int port = 0; port < NUMPORTS; port++) begin
                if (input_stalled[port] &&
                    (!in_valid[port] || in_flit[port] !== held_input_flit[port]))
                    $fatal(1, "FAIL: input %0d changed valid/data before ready", port);
                if (output_stalled[port] &&
                    (!out_valid[port] || out_flit[port] !== held_output_flit[port]))
                    $fatal(1, "FAIL: output %0d changed valid/data while stalled", port);
                input_stalled[port] = in_valid[port] && !in_ready[port];
                output_stalled[port] = out_valid[port] && !out_ready[port];
                held_input_flit[port] = in_flit[port];
                held_output_flit[port] = out_flit[port];
            end

            popped = '0;
            invalid_this_edge = dut.invalid_head;
            report_line($sformatf(
                "TRACE t=%0t in=%b ready=%b fifo_valid=%b requests=%b grants=%b out_valid=%b out_ready=%b invalid=%b",
                $time, in_valid, in_ready, dut.buffer_valid,
                dut.allocator.request, dut.grant, out_valid, out_ready,
                dut.invalid_head));

            for (int output_port = 0; output_port < NUMPORTS; output_port++) begin
                if (out_valid[output_port] && out_ready[output_port]) begin
                    selected_input = -1;
                    for (int input_port = 0; input_port < NUMPORTS; input_port++)
                        if (dut.grant[output_port * NUMPORTS + input_port])
                            selected_input = input_port;

                    if (selected_input < 0)
                        $fatal(1, "FAIL: output %0d transferred without a grant",
                               output_port);
                    if (queue_count[selected_input] == 0)
                        $fatal(1, "FAIL: output %0d transferred from empty input %0d",
                               output_port, selected_input);
                    if (out_flit[output_port] !==
                        expected_flits[selected_input][queue_read[selected_input]])
                        $fatal(1, "FAIL: output %0d received %h; input %0d expected head %h",
                               output_port, out_flit[output_port], selected_input,
                               expected_flits[selected_input][queue_read[selected_input]]);

                    report_line($sformatf(
                        "TRACE t=%0t crossbar input=%0d -> output=%0d flit=%h",
                        $time, selected_input, output_port, out_flit[output_port]));
                    popped[selected_input] = 1'b1;
                end
            end

            for (int input_port = 0; input_port < NUMPORTS; input_port++) begin
                if (invalid_this_edge[input_port]) begin
                    if (popped[input_port])
                        $fatal(1, "FAIL: invalid flit and crossbar transfer both popped input %0d",
                               input_port);
                    report_line($sformatf(
                        "TRACE t=%0t invalid flit dropped at input=%0d flit=%h",
                        $time, input_port, dut.buffer_flit[input_port]));
                    popped[input_port] = 1'b1;
                end

                if (popped[input_port]) begin
                    queue_read[input_port] =
                        (queue_read[input_port] + 1) % MAX_TRACKED_FLITS;
                    queue_count[input_port]--;
                end

                if (in_valid[input_port] && in_ready[input_port]) begin
                    if (queue_count[input_port] >= MAX_TRACKED_FLITS)
                        $fatal(1, "FAIL: reference queue overflow on input %0d",
                               input_port);
                    expected_flits[input_port][queue_write[input_port]] =
                        in_flit[input_port];
                    queue_write[input_port] =
                        (queue_write[input_port] + 1) % MAX_TRACKED_FLITS;
                    queue_count[input_port]++;
                    report_line($sformatf(
                        "TRACE t=%0t input accepted at port=%0d flit=%h",
                        $time, input_port, in_flit[input_port]));
                end
            end
            previous_invalid = invalid_this_edge;
        end

        #1;
        check_stages("after clock edge");
        if (invalid_flit_dropped !== invalid_this_edge)
            $fatal(1, "FAIL: invalid-drop pulse does not match this cycle's invalid heads");
    end

