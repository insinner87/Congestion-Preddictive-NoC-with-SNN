// Directed all-pairs, contention, backpressure, hotspot, and seeded traffic.
    initial begin : run_mesh_tests
        integer tag;
        integer destination;
        integer source;
        integer timeout_cycles;
        logic [15:0] random_accepted;
        integer plusarg_status;
        integer percentile_target_95;
        integer percentile_target_99;
        integer percentile_95;
        integer percentile_99;
        integer latency_cumulative;
        integer maximum_latency;
        logic percentile_95_found;
        logic percentile_99_found;

        plusarg_status = $value$plusargs("SEED=%d", seed_value);
        random_state = seed_value;
        for (int latency = 0; latency < MAX_TRACE_CYCLES; latency++)
            latency_histogram[latency] = 0;
        for (int index = 0; index < MAX_TAGS; index++) begin
            expected_valid[index] = 1'b0;
            expected_injected[index] = 1'b0;
            received[index] = 1'b0;
            expected_flit[index] = '0;
            expected_node[index] = 0;
        end

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        $display("4x4 mesh test: routing %0d, TF-PCR %0b, priority %0b, SNN %0b, buffer %0b, offload %0b, seed 0x%08x",
                 ROUTING_MODE, ENABLE_TF_PCR, ENABLE_PRIORITY, ENABLE_SNN,
                 ENABLE_ADAPTIVE_BUFFER, ENABLE_OFFLOAD, seed_value);

        $display("TEST A: all 256 source/destination pairs, including all local ejections");
        for (source = 0; source < 16; source++) begin
            for (destination = 0; destination < 16; destination++) begin
                tag = next_tag++;
                prepare_packet(destination, tag);
                send_packet(source, destination, tag);
                wait_for_tag(tag);
            end
        end

        $display("TEST B: simultaneous independent transfers");
        @(negedge clk);
        for (int endpoint = 0; endpoint < 4; endpoint++) begin
            case (endpoint)
                0: begin source = 0; destination = 1; end
                1: begin source = 3; destination = 2; end
                2: begin source = 12; destination = 13; end
                default: begin source = 15; destination = 14; end
            endcase
            tag = next_tag++;
            prepare_packet(destination, tag);
            local_in_flit[source] = make_packet(destination, tag);
            local_in_priority[source] = expected_priority[tag];
            local_in_valid[source] = 1'b1;
        end
        @(posedge clk);
        for (int endpoint = 0; endpoint < 4; endpoint++) begin
            case (endpoint)
                0: source = 0;
                1: source = 3;
                2: source = 12;
                default: source = 15;
            endcase
            if (!local_in_ready[source])
                $fatal(1, "fresh source %0d was unexpectedly backpressured", source);
        end
        @(negedge clk);
        local_in_valid = '0;
        timeout_cycles = 0;
        while (delivered_packets < expected_packets && timeout_cycles < 2000) begin
            @(negedge clk);
            timeout_cycles++;
        end
        if (delivered_packets != expected_packets)
            $fatal(1, "simultaneous transfer batch did not drain");

        $display("TEST C: repeated 16-source hotspot bursts to node 5");
        for (int burst = 0; burst < 4; burst++) begin
            @(negedge clk);
            local_in_valid = '0;
            for (source = 0; source < 16; source++) begin
                tag = next_tag++;
                prepare_packet(5, tag);
                local_in_flit[source] = make_packet(5, tag);
                local_in_priority[source] = expected_priority[tag];
                local_in_valid[source] = 1'b1;
            end
            @(posedge clk);
            for (source = 0; source < 16; source++)
                if (!local_in_ready[source])
                    $fatal(1, "hotspot burst source %0d was unexpectedly backpressured",
                           source);
        end
        @(negedge clk);
        local_in_valid = '0;
        timeout_cycles = 0;
        while (delivered_packets < expected_packets && timeout_cycles < 5000) begin
            @(negedge clk);
            timeout_cycles++;
        end
        if (delivered_packets != expected_packets)
            $fatal(1, "sustained hotspot traffic did not drain");

        $display("TEST D: sustained multi-packet destination backpressure and recovery");
        destination = 10;
        local_out_ready[destination] = 1'b0;
        for (int source_index = 0; source_index < 4; source_index++) begin
            case (source_index)
                0: source = 0;
                1: source = 4;
                2: source = 8;
                default: source = 12;
            endcase
            tag = next_tag++;
            prepare_packet(destination, tag);
            send_packet(source, destination, tag);
        end
        timeout_cycles = 0;
        while (!local_out_valid[destination] && timeout_cycles < 1000) begin
            @(negedge clk);
            timeout_cycles++;
        end
        if (!local_out_valid[destination])
            $fatal(1, "packet did not reach the backpressured destination");
        repeat (8) begin
            @(posedge clk);
            if (!local_out_valid[destination])
                $fatal(1, "stalled destination valid deasserted under backpressure");
        end
        @(negedge clk);
        local_out_ready[destination] = 1'b1;
        for (int packet_index = 0; packet_index < 4; packet_index++)
            wait_for_tag(next_tag - 4 + packet_index);

        $display("TEST E: legal alternate selection under TF-PCR/SNN/equation and deterministic fallback");
        if (ROUTING_MODE == 1 && (ENABLE_TF_PCR || ENABLE_SNN || ENABLE_EQUATION_ROUTING)) begin
            if (ENABLE_SNN) begin
                force dut.g_routers[4].router_wrapper.g_route_computers[0].
                    route_compute.snn_congestion_score[noc_pkg::PORT_EAST] = 8'd200;
                force dut.g_routers[4].router_wrapper.g_route_computers[0].
                    route_compute.snn_congestion_score[noc_pkg::PORT_NORTH] = 8'd10;
                force dut.g_routers[4].router_wrapper.g_route_computers[0].
                    route_compute.snn_congestion_predicted[noc_pkg::PORT_EAST] = 1'b1;
            end else if (ENABLE_EQUATION_ROUTING) begin
                force dut.g_routers[4].router_wrapper.g_route_computers[0].
                    route_compute.snn_congestion_score[noc_pkg::PORT_EAST] = 8'd255;
                force dut.g_routers[4].router_wrapper.g_route_computers[0].
                    route_compute.snn_congestion_score[noc_pkg::PORT_NORTH] = 8'd0;
                force dut.g_routers[4].router_wrapper.g_route_computers[0].
                    route_compute.snn_congestion_predicted[noc_pkg::PORT_EAST] = 1'b1;
            end else begin
                force dut.g_routers[4].router_wrapper.g_route_computers[0].
                    route_compute.congestion_score[noc_pkg::PORT_EAST] = 8'd200;
                force dut.g_routers[4].router_wrapper.g_route_computers[0].
                    route_compute.congestion_score[noc_pkg::PORT_NORTH] = 8'd10;
                force dut.g_routers[4].router_wrapper.g_route_computers[0].
                    route_compute.congestion_predicted[noc_pkg::PORT_EAST] = 1'b1;
            end
        end
        destination = 1;
        tag = next_tag++;
        prepare_packet(destination, tag);
        send_packet(4, destination, tag);
        timeout_cycles = 0;
        if (ROUTING_MODE == 1 && (ENABLE_TF_PCR || ENABLE_SNN || ENABLE_EQUATION_ROUTING)) begin
            while (!dut.router_out_valid[4][noc_pkg::PORT_NORTH] &&
                   timeout_cycles < 100) begin
                @(negedge clk);
                timeout_cycles++;
            end
            if (!dut.router_out_valid[4][noc_pkg::PORT_NORTH])
                $fatal(1, "adaptive router did not select the lower-score legal North output");
        end else begin
            while (!dut.router_out_valid[4][noc_pkg::PORT_EAST] &&
                   timeout_cycles < 100) begin
                @(negedge clk);
                timeout_cycles++;
            end
            if (!dut.router_out_valid[4][noc_pkg::PORT_EAST])
                $fatal(1, "deterministic XY fallback did not choose East");
        end
        wait_for_tag(tag);
        if (ROUTING_MODE == 1 && (ENABLE_TF_PCR || ENABLE_SNN || ENABLE_EQUATION_ROUTING)) begin
            if (ENABLE_SNN) begin
                release dut.g_routers[4].router_wrapper.g_route_computers[0].
                    route_compute.snn_congestion_score[noc_pkg::PORT_EAST];
                release dut.g_routers[4].router_wrapper.g_route_computers[0].
                    route_compute.snn_congestion_score[noc_pkg::PORT_NORTH];
                release dut.g_routers[4].router_wrapper.g_route_computers[0].
                    route_compute.snn_congestion_predicted[noc_pkg::PORT_EAST];
            end else if (ENABLE_EQUATION_ROUTING) begin
                release dut.g_routers[4].router_wrapper.g_route_computers[0].
                    route_compute.snn_congestion_score[noc_pkg::PORT_EAST];
                release dut.g_routers[4].router_wrapper.g_route_computers[0].
                    route_compute.snn_congestion_score[noc_pkg::PORT_NORTH];
                release dut.g_routers[4].router_wrapper.g_route_computers[0].
                    route_compute.snn_congestion_predicted[noc_pkg::PORT_EAST];
            end else begin
                release dut.g_routers[4].router_wrapper.g_route_computers[0].
                    route_compute.congestion_score[noc_pkg::PORT_EAST];
                release dut.g_routers[4].router_wrapper.g_route_computers[0].
                    route_compute.congestion_score[noc_pkg::PORT_NORTH];
                release dut.g_routers[4].router_wrapper.g_route_computers[0].
                    route_compute.congestion_predicted[noc_pkg::PORT_EAST];
            end
        end

        $display("TEST F: deterministic uniform random load with bounded drain");
        count_random_phase_routes = 1'b1;
        for (int cycle = 0; cycle < 240; cycle++) begin
            @(negedge clk);
            for (source = 0; source < 16; source++) begin
                if (accepted_previous[source])
                    local_in_valid[source] = 1'b0;
                if (!local_in_valid[source]) begin
                    random_value = $urandom(random_state);
                    if ((random_value & 7) == 0) begin
                        destination = $urandom(random_state) % 16;
                        tag = next_tag++;
                        prepare_packet(destination, tag);
                        local_in_flit[source] = make_packet(destination, tag);
                        local_in_priority[source] = expected_priority[tag];
                        local_in_valid[source] = 1'b1;
                    end
                end
            end

            @(posedge clk);
            random_accepted = '0;
            for (source = 0; source < 16; source++)
                random_accepted[source] =
                    local_in_valid[source] && local_in_ready[source];
            accepted_previous = random_accepted;
        end

        for (int cycle = 0; cycle < 200; cycle++) begin
            @(negedge clk);
            for (source = 0; source < 16; source++)
                if (accepted_previous[source])
                    local_in_valid[source] = 1'b0;
            @(posedge clk);
            random_accepted = '0;
            for (source = 0; source < 16; source++)
                random_accepted[source] =
                    local_in_valid[source] && local_in_ready[source];
            accepted_previous = random_accepted;
        end
        @(negedge clk);
        if (local_in_valid != 0)
            $fatal(1, "random traffic drivers did not finish handshakes");

        timeout_cycles = 0;
        while (delivered_packets < expected_packets && timeout_cycles < 4000) begin
            @(negedge clk);
            timeout_cycles++;
        end
        if (delivered_packets != expected_packets)
            $fatal(1, "random load lost packets: accepted scoreboard %0d, delivered %0d",
                   expected_packets, delivered_packets);
        if (accepted_packets != expected_packets)
            $fatal(1, "injection handshakes %0d do not match generated packets %0d",
                   accepted_packets, expected_packets);

        count_random_phase_routes = 1'b0;
        evaluate_detectors($time / 10);
        percentile_target_95 = (delivered_packets * 95 + 99) / 100;
        percentile_target_99 = (delivered_packets * 99 + 99) / 100;
        percentile_95 = 0;
        percentile_99 = 0;
        percentile_95_found = 1'b0;
        percentile_99_found = 1'b0;
        latency_cumulative = 0;
        maximum_latency = 0;
        for (int latency = 0; latency < MAX_TRACE_CYCLES; latency++) begin
            latency_cumulative += latency_histogram[latency];
            if (latency_histogram[latency] > 0)
                maximum_latency = latency;
            if (!percentile_95_found && latency_cumulative >= percentile_target_95) begin
                percentile_95 = latency;
                percentile_95_found = 1'b1;
            end
            if (!percentile_99_found && latency_cumulative >= percentile_target_99) begin
                percentile_99 = latency;
                percentile_99_found = 1'b1;
            end
        end
        $display("PERFORMANCE mode=%0d seed=%0d offered=%0d injected=%0d delivered=%0d avg-latency=%0.3f max-latency=%0d p95-latency=%0d p99-latency=%0d cycles throughput=%0.4f packets/cycle avg-link-occupancy=%0.4f max-link-occupancy=%0d random-phase-alternate-hops=%0d",
                 ROUTING_MODE, seed_value, expected_packets, accepted_packets,
                 delivered_packets,
                 real'(cumulative_latency) / real'(delivered_packets),
                 maximum_latency, percentile_95, percentile_99,
                 real'(delivered_packets) /
                    real'(final_delivery_cycle - first_injection_cycle),
                 occupancy_samples == 0 ? 0.0 :
                    real'(occupancy_sum) / real'(occupancy_samples),
                 maximum_buffer_occupancy,
                 alternate_route_count);
        $display("INTEGRITY injected=%0d delivered=%0d missing=%0d duplicates=0 corrupted=0 unexpected=0 final=PASS",
                 accepted_packets, delivered_packets,
                 accepted_packets - delivered_packets);
        if (ENABLE_ADAPTIVE_PREDICTOR)
            $display("ADAPTIVE POLICY offline-validation=%0d%% offline-correct=%0d offline-total=%0d threshold=90%% min-samples=32 online-window=64 initial-SNN-selections=%0d initial-equation-selections=%0d SNN-selected-samples=%0d equation-selected-samples=%0d to-SNN-switches=%0d to-equation-switches=%0d",
                     SNN_VALIDATION_ACCURACY_PERCENT,
                     SNN_VALIDATION_CORRECT_SAMPLES,
                     SNN_VALIDATION_TOTAL_SAMPLES,
                     adaptive_initial_snn_selections,
                     adaptive_initial_equation_selections, adaptive_snn_cycles,
                     adaptive_equation_cycles, adaptive_to_snn_switches,
                     adaptive_to_equation_switches);
        $display("ALL MESH TESTS PASSED: mode=%0d packets=%0d, no drops/duplicates/corruption",
                 ROUTING_MODE, delivered_packets);
        $finish;
    end
