// Records per-output prediction/blockage and checks packet protocol integrity.
    for (genvar node = 0; node < 16; node++) begin : g_detector_trace
        for (genvar port = 0; port < 5; port++) begin : g_output
            localparam int OUTPUT_INDEX = node * 5 + port;
            always @(posedge clk) begin : p_record_cycle
                integer trace_index;
                trace_index = $time / 10;
                if (rst_n && trace_index < MAX_TRACE_CYCLES) begin
                    pcr_prediction_trace[OUTPUT_INDEX][trace_index] =
                        dut.router_congestion_predicted[node][port];
                    occupancy_prediction_trace[OUTPUT_INDEX][trace_index] =
                        dut.router_occupancy_predicted[node][port];
                    blocked_trace[OUTPUT_INDEX][trace_index] =
                        dut.router_out_valid[node][port] &&
                        !dut.router_out_ready[node][port];
                end
            end
        end
    end

    always @(posedge clk) begin : p_mesh_scoreboard
        integer tag;
        integer cycle_sample;
        integer packet_latency;
        logic [63:0] observed_flit;
        logic [63:0] input_flit_sample;

        if (!rst_n) begin
            input_was_stalled = '0;
            output_was_stalled = '0;
        end else begin
            cycle_sample = $time / 10;
            for (int node = 0; node < 16; node++) begin
                if (input_was_stalled[node] &&
                    (!local_in_valid[node] ||
                     local_in_flit[node] !== held_input_flit[node] ||
                     local_in_priority[node] !== held_input_priority[node]))
                    $fatal(1, "source %0d changed data while valid was backpressured", node);
                input_was_stalled[node] =
                    local_in_valid[node] && !local_in_ready[node];
                held_input_flit[node] = local_in_flit[node];
                held_input_priority[node] = local_in_priority[node];
                if (local_in_valid[node] && local_in_ready[node]) begin
                    input_flit_sample = local_in_flit[node];
                    tag = input_flit_sample[31:0];
                    if (tag <= 0 || tag >= MAX_TAGS ||
                        !expected_valid[tag] || expected_injected[tag])
                        $fatal(1, "unexpected or duplicate injection tag %0d", tag);
                    if (input_flit_sample !== expected_flit[tag])
                        $fatal(1, "source packet %0d changed before FIFO acceptance", tag);
                    if (local_in_priority[node] !== expected_priority[tag])
                        $fatal(1, "source packet %0d priority changed before FIFO acceptance", tag);
                    expected_injected[tag] = 1'b1;
                    injection_cycle[tag] = cycle_sample;
                    accepted_packets++;
                    if (first_injection_cycle < 0)
                        first_injection_cycle = cycle_sample;
                end

                if (output_was_stalled[node] &&
                    (!local_out_valid[node] ||
                     local_out_flit[node] !== held_output_flit[node] ||
                     local_out_priority[node] !== held_output_priority[node]))
                    $fatal(1, "destination %0d changed a stalled output packet", node);
                output_was_stalled[node] =
                    local_out_valid[node] && !local_out_ready[node];
                held_output_flit[node] = local_out_flit[node];
                held_output_priority[node] = local_out_priority[node];

                if (local_out_valid[node] && local_out_ready[node]) begin
                    observed_flit = local_out_flit[node];
                    tag = observed_flit[31:0];
                    if (tag <= 0 || tag >= MAX_TAGS ||
                        !expected_valid[tag])
                        $fatal(1, "unexpected or malformed packet tag %0d at node %0d",
                               tag, node);
                    if (expected_node[tag] != node ||
                        observed_flit !== expected_flit[tag])
                        $fatal(1, "packet %0d corrupted or misrouted; at node %0d expected node %0d",
                               tag, node, expected_node[tag]);
                    if (local_out_priority[node] !== expected_priority[tag])
                        $fatal(1, "packet %0d priority corrupted: got %0d expected %0d",
                               tag, local_out_priority[node], expected_priority[tag]);
                    if (received[tag])
                        $fatal(1, "duplicate packet tag %0d", tag);
                    if (!expected_injected[tag])
                        $fatal(1, "packet %0d ejected before its injection handshake", tag);
                    received[tag] = 1'b1;
                    delivered_packets++;
                    packet_latency = cycle_sample - injection_cycle[tag];
                    cumulative_latency += packet_latency;
                    if (packet_latency >= 0 && packet_latency < MAX_TRACE_CYCLES)
                        latency_histogram[packet_latency]++;
                    final_delivery_cycle = cycle_sample;
                end

            end
        end
    end

    for (genvar occupancy_node = 0; occupancy_node < 16; occupancy_node++) begin : g_occupancy_node
        for (genvar occupancy_port = 1; occupancy_port < 5; occupancy_port++) begin : g_occupancy_port
            if ((occupancy_port == noc_pkg::PORT_NORTH && occupancy_node >= 4) ||
                (occupancy_port == noc_pkg::PORT_SOUTH && occupancy_node < 12) ||
                (occupancy_port == noc_pkg::PORT_EAST && occupancy_node % 4 < 3) ||
                (occupancy_port == noc_pkg::PORT_WEST && occupancy_node % 4 > 0)) begin : g_physical_link
                always @(posedge clk) begin : p_sample_occupancy
                    if (rst_n) begin
                        occupancy_sum += dut.router_output_buffer_occupancy[
                            occupancy_node][occupancy_port];
                        occupancy_samples++;
                        if (dut.router_output_buffer_occupancy[
                                occupancy_node][occupancy_port] >
                            maximum_buffer_occupancy)
                            maximum_buffer_occupancy =
                                dut.router_output_buffer_occupancy[
                                    occupancy_node][occupancy_port];
                    end
                end
            end
        end
    end

    if (ENABLE_ADAPTIVE_PREDICTOR) begin : g_adaptive_model_observers
        for (genvar node = 0; node < 16; node++) begin : g_node
            always @(posedge clk) begin : p_record_adaptive_selection
                #1;
                if (rst_n) begin
                    for (int port = 0; port < 5; port++) begin
                        if (dut.g_routers[node].router_wrapper.tf_feature_valid[port]) begin
                            if (dut.g_routers[node].router_wrapper.adaptive_select_snn[port])
                                adaptive_snn_cycles++;
                            else
                                adaptive_equation_cycles++;
                        end
                        if (dut.g_routers[node].router_wrapper.
                            adaptive_model_selection_pulse[port] &&
                            !dut.g_routers[node].router_wrapper.
                                adaptive_model_switch_pulse[port]) begin
                            $display("MODEL_SELECTION cycle=%0d node=%0d output=%0d model=%0d kind=0 reason=%0d online_accuracy=%0d online_samples=%0d",
                                $time / 10, node, port,
                                dut.g_routers[node].router_wrapper.
                                    adaptive_select_snn[port],
                                dut.g_routers[node].router_wrapper.
                                    adaptive_model_switch_reason[port],
                                dut.g_routers[node].router_wrapper.
                                    adaptive_online_accuracy[port],
                                dut.g_routers[node].router_wrapper.
                                    adaptive_online_samples[port]);
                            if (dut.g_routers[node].router_wrapper.
                                adaptive_select_snn[port])
                                adaptive_initial_snn_selections++;
                            else
                                adaptive_initial_equation_selections++;
                        end
                        if (dut.g_routers[node].router_wrapper.
                            adaptive_model_switch_pulse[port]) begin
                            $display("MODEL_SELECTION cycle=%0d node=%0d output=%0d model=%0d kind=1 reason=%0d online_accuracy=%0d online_samples=%0d",
                                $time / 10, node, port,
                                dut.g_routers[node].router_wrapper.
                                    adaptive_select_snn[port],
                                dut.g_routers[node].router_wrapper.
                                    adaptive_model_switch_reason[port],
                                dut.g_routers[node].router_wrapper.
                                    adaptive_online_accuracy[port],
                                dut.g_routers[node].router_wrapper.
                                    adaptive_online_samples[port]);
                            if (dut.g_routers[node].router_wrapper.
                                adaptive_model_switch_reason[port] == 3'd1)
                                adaptive_to_snn_switches++;
                            else
                                adaptive_to_equation_switches++;
                        end
                    end
                end
            end
        end
    end

    always @(posedge clk) begin : p_count_adaptive_routes
        integer destination_x;
        integer destination_y;
        integer current_x;
        integer current_y;
        integer probe_index;
        logic [2:0] preferred_port;
        logic [2:0] accepted_port;

        if (rst_n && ROUTING_MODE == 1 && count_random_phase_routes) begin
            for (int node = 0; node < 16; node++) begin
                current_x = node % 4;
                current_y = node / 4;
                for (int input_port = 0; input_port < 5; input_port++) begin
                    probe_index = node * 5 + input_port;
                    if (route_probe_valid[probe_index] &&
                        route_probe_ready[probe_index]) begin
                        destination_x = route_probe_flit[probe_index*64+59 +: 2];
                        destination_y = route_probe_flit[probe_index*64+57 +: 2];
                        if (destination_x > current_x)
                            preferred_port = noc_pkg::PORT_EAST;
                        else if (destination_x < current_x)
                            preferred_port = noc_pkg::PORT_WEST;
                        else if (destination_y < current_y)
                            preferred_port = noc_pkg::PORT_NORTH;
                        else if (destination_y > current_y)
                            preferred_port = noc_pkg::PORT_SOUTH;
                        else
                            preferred_port = noc_pkg::PORT_LOCAL;

                        accepted_port = accepted_next_hop[probe_index*3 +: 3];
                        if (accepted_port != preferred_port)
                            alternate_route_count++;
                    end
                end
            end
        end
    end

    for (genvar node = 0; node < 16; node++) begin : g_boundary_checks
        localparam int X = node % 4;
        localparam int Y = node / 4;

        if (Y == 0) begin : g_no_north
            always @(posedge clk)
                if (rst_n && dut.router_out_valid[node][noc_pkg::PORT_NORTH])
                    $fatal(1, "router %0d asserted a nonexistent North output", node);
        end
        if (Y == 3) begin : g_no_south
            always @(posedge clk)
                if (rst_n && dut.router_out_valid[node][noc_pkg::PORT_SOUTH])
                    $fatal(1, "router %0d asserted a nonexistent South output", node);
        end
        if (X == 0) begin : g_no_west
            always @(posedge clk)
                if (rst_n && dut.router_out_valid[node][noc_pkg::PORT_WEST])
                    $fatal(1, "router %0d asserted a nonexistent West output", node);
        end
        if (X == 3) begin : g_no_east
            always @(posedge clk)
                if (rst_n && dut.router_out_valid[node][noc_pkg::PORT_EAST])
                    $fatal(1, "router %0d asserted a nonexistent East output", node);
        end
    end
