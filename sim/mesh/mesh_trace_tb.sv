// Full-mesh trace source for supervised future-congestion prediction.
// Rows sample real wrapper features and link FIFO occupancy at each clock.
module mesh_trace_tb;
    localparam int PORTS = noc_pkg::NUM_PORTS;
    localparam int HORIZON = 8;
    localparam int MAX_TAGS = 65536;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [15:0] local_in_valid = '0;
    logic [15:0] local_in_ready;
    logic [15:0][63:0] local_in_flit = '0;
    logic [15:0][1:0] local_in_priority = '0;
    logic [15:0] local_out_valid;
    logic [15:0] local_out_ready = '0;
    logic [15:0][63:0] local_out_flit;
    logic [15:0][1:0] local_out_priority;

    integer trace_fd;
    integer total_cycles = 2048;
    integer seed_value = 1001;
    integer load_percent = 50;
    integer workload = 0;
    integer cycle_number = 0;
    integer random_value;
    integer offered_percent;
    integer destination;
    integer x_coord;
    integer y_coord;
    integer packet_tag = 1;
    integer node;
    integer plusarg_status;
    integer drain_cycles = 0;
    integer offered_flits = 0;
    integer accepted_flits = 0;
    integer delivered_flits = 0;
    integer missing_flits = 0;
    integer duplicate_flits = 0;
    integer corrupted_flits = 0;
    integer maximum_link_occupancy = 0;
    integer route_trace_fd;
    logic [63:0] expected_flit [0:MAX_TAGS-1];
    integer expected_destination [0:MAX_TAGS-1];
    logic offered_tag [0:MAX_TAGS-1];
    logic accepted_tag [0:MAX_TAGS-1];
    logic delivered_tag [0:MAX_TAGS-1];
    logic [31:0] rng_state;
    string trace_path;
    string route_trace_path;

    always #5 clk = ~clk;

    noc_mesh_4x4 #(
        .FLIT_WIDTH(64),
        .ROUTING_MODE(1),
        .ENABLE_TF_PCR(1'b1),
        .ENABLE_PRIORITY(1'b0),
        .ENABLE_SNN(1'b1),
        .ENABLE_SNN_ROUTING(1'b0),
        .TRACE_CENTER_ONLY(1'b1),
        .ENABLE_ADAPTIVE_BUFFER(1'b1),
        .LINK_FIFO_DEPTH(2)
    ) dut (.*);

    initial begin
        trace_path = "noc_trace.csv";
        route_trace_path = "noc_routes.csv";
        plusarg_status = $value$plusargs("TRACE_FILE=%s", trace_path);
        plusarg_status = $value$plusargs("TRACE_ROUTE_FILE=%s", route_trace_path);
        plusarg_status = $value$plusargs("CYCLES=%d", total_cycles);
        plusarg_status = $value$plusargs("SEED=%d", seed_value);
        plusarg_status = $value$plusargs("LOAD=%d", load_percent);
        plusarg_status = $value$plusargs("WORKLOAD=%d", workload);
        rng_state = 32'(seed_value);
        for (int tag = 0; tag < MAX_TAGS; tag++) begin
            expected_flit[tag] = '0;
            expected_destination[tag] = 0;
            offered_tag[tag] = 1'b0;
            accepted_tag[tag] = 1'b0;
            delivered_tag[tag] = 1'b0;
        end
        trace_fd = $fopen(trace_path, "w");
        if (trace_fd == 0) $fatal(1, "Cannot open trace file %s", trace_path);
        route_trace_fd = $fopen(route_trace_path, "w");
        if (route_trace_fd == 0)
            $fatal(1, "Cannot open route trace file %s", route_trace_path);
        $fwrite(trace_fd,
            "cycle,node,port,feature_valid,features,blocked_streak,requester_count,requester_cycles_8,demand_active_cycles_8,service_cycles_8,service_deficit_8,pressure_trend,occupancy,occupancy_max,occupancy_rising,request_nonempty,output_transfer,congestion_score,congestion_prediction,snn_risk_class\n");
        $fwrite(route_trace_fd,
            "cycle,node,input_port,destination_x,destination_y,selected_port,score_vector,prediction_vector\n");
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
    end

    // Hold an offered flit stable until its ready/valid transfer occurs.
    always @(negedge clk) begin
        if (rst_n) begin
            if (cycle_number < total_cycles) begin
                cycle_number = cycle_number + 1;
                for (node = 0; node < 16; node = node + 1) begin
                    if (local_in_valid[node] && local_in_ready[node])
                        local_in_valid[node] = 1'b0;
                    if (!local_in_valid[node]) begin
                        random_value = $urandom(rng_state) % 100;
                        offered_percent = load_percent;
                        case (workload)
                            3: begin
                                if ((cycle_number % 96) < 24)
                                    offered_percent = (load_percent * 3) / 2;
                                else
                                    offered_percent = load_percent / 3;
                                if (offered_percent > 95) offered_percent = 95;
                            end
                            4: offered_percent = 5;
                            6: begin
                                if ((cycle_number % 128) < 32)
                                    offered_percent = 55;
                                else
                                    offered_percent = 30;
                            end
                            7: offered_percent = 95;
                            8: begin
                                if ((cycle_number % 128) < 64)
                                    offered_percent = 5;
                                else
                                    offered_percent = 95;
                            end
                            default: begin end
                        endcase
                        if (random_value < offered_percent) begin
                            if (packet_tag >= MAX_TAGS)
                                $fatal(1, "Trace exceeded the supported unique-tag count");
                            case (workload)
                                1, 3, 7: destination = (node == 10) ? 5 : 10;
                                5: begin
                                    if (($urandom(rng_state) % 4) == 0)
                                        destination =
                                            ($urandom(rng_state) % 2) == 0 ? 5 : 10;
                                    else begin
                                        destination = $urandom(rng_state) % 16;
                                        if (destination == node)
                                            destination = (destination + 7) % 16;
                                    end
                                end
                                2: begin
                                    x_coord = node % 4;
                                    y_coord = node / 4;
                                    destination = x_coord * 4 + y_coord;
                                    if (destination == node)
                                        destination = (destination + 1) % 16;
                                end
                                default: begin
                                    destination = $urandom(rng_state) % 16;
                                    if (destination == node)
                                        destination = (destination + 7) % 16;
                                end
                            endcase
                            local_in_flit[node] = {
                                3'b000, 2'(destination % 4), 2'(destination / 4),
                                25'b0, 32'(packet_tag)
                            };
                            expected_flit[packet_tag] = local_in_flit[node];
                            expected_destination[packet_tag] = destination;
                            offered_tag[packet_tag] = 1'b1;
                            offered_flits++;
                            local_in_priority[node] = 2'b00;
                            local_in_valid[node] = 1'b1;
                            packet_tag = packet_tag + 1;
                        end
                    end
                    local_out_ready[node] = ($urandom(rng_state) % 100) < 92;
                end
            end else begin
                local_out_ready = '1;
                for (node = 0; node < 16; node = node + 1)
                    if (local_in_valid[node] && local_in_ready[node])
                        local_in_valid[node] = 1'b0;
            end
        end
    end

    for (genvar source = 0; source < 16; source++) begin : g_trace_endpoint_scoreboard
        always @(posedge clk) begin : p_check_endpoint_handshakes
            integer tag;
            logic [63:0] observed_flit;
            if (rst_n) begin
                if (local_in_valid[source] && local_in_ready[source]) begin
                    tag = local_in_flit[source][31:0];
                    if (tag <= 0 || tag >= MAX_TAGS ||
                        !offered_tag[tag] || accepted_tag[tag] ||
                        local_in_flit[source] !== expected_flit[tag])
                        $fatal(1, "Trace accepted-flit scoreboard failed for tag %0d", tag);
                    accepted_tag[tag] = 1'b1;
                    accepted_flits++;
                end
                if (local_out_valid[source] && local_out_ready[source]) begin
                    observed_flit = local_out_flit[source];
                    tag = observed_flit[31:0];
                    if (tag <= 0 || tag >= MAX_TAGS ||
                        !accepted_tag[tag] || delivered_tag[tag]) begin
                        duplicate_flits++;
                        $fatal(1, "Trace unexpected or duplicate output tag %0d", tag);
                    end
                    if (source != expected_destination[tag] ||
                        observed_flit !== expected_flit[tag]) begin
                        corrupted_flits++;
                        $fatal(1, "Trace output flit %0d was corrupted or misrouted", tag);
                    end
                    delivered_tag[tag] = 1'b1;
                    delivered_flits++;
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
                always @(posedge clk) begin : p_record_maximum_occupancy
                    if (rst_n &&
                        dut.router_output_buffer_occupancy[occupancy_node][occupancy_port] >
                            maximum_link_occupancy)
                        maximum_link_occupancy =
                            dut.router_output_buffer_occupancy[
                                occupancy_node][occupancy_port];
                end
            end
        end
    end

    // The center routers have all four physical links. Generate static
    // hierarchy references so Icarus records the exact DUT signals.
    for (genvar g_node = 0; g_node < 16; g_node++) begin : g_trace_node
        if (g_node == 5 || g_node == 6 || g_node == 9 || g_node == 10) begin : g_center
            for (genvar g_port = 1; g_port <= 4; g_port++) begin : g_trace_port
                always @(posedge clk) begin
                    #1;
                    if (rst_n && cycle_number <= total_cycles) begin
                        $fwrite(trace_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                            cycle_number,
                            g_node,
                            g_port,
                            dut.g_routers[g_node].router_wrapper.tf_feature_valid[g_port],
                            dut.g_routers[g_node].router_wrapper.tf_encoded_features[g_port*7 +: 7],
                            dut.g_routers[g_node].router_wrapper.tf_blocked_streak[g_port],
                            dut.g_routers[g_node].router_wrapper.tf_requester_count[g_port],
                            dut.g_routers[g_node].router_wrapper.tf_requester_cycles[g_port],
                            dut.g_routers[g_node].router_wrapper.tf_demand_active_cycles[g_port],
                            dut.g_routers[g_node].router_wrapper.tf_service_cycles[g_port],
                            dut.g_routers[g_node].router_wrapper.tf_service_deficit[g_port],
                            dut.g_routers[g_node].router_wrapper.tf_pressure_trend[g_port],
                            dut.router_output_buffer_occupancy[g_node][g_port],
                            dut.g_routers[g_node].router_wrapper.tf_output_buffer_occupancy_max[g_port],
                            dut.g_routers[g_node].router_wrapper.tf_output_buffer_rising[g_port],
                            (|dut.g_routers[g_node].router_wrapper.output_request_matrix[g_port*PORTS +: PORTS]),
                            dut.g_routers[g_node].router_wrapper.output_transfer[g_port],
                            dut.router_congestion_score[g_node][g_port],
                            dut.router_congestion_predicted[g_node][g_port],
                            dut.g_routers[g_node].router_wrapper.snn_risk_class[g_port]);
                    end
                end
            end
        end
    end

    for (genvar route_node = 0; route_node < 16; route_node++) begin : g_route_trace_node
        for (genvar input_port = 0; input_port < PORTS; input_port++) begin : g_route_trace_input
            always @(posedge clk) begin
                #1;
                if (rst_n && cycle_number <= total_cycles &&
                    dut.router_in_valid[route_node][input_port] &&
                    dut.router_in_ready[route_node][input_port]) begin
                    $fwrite(route_trace_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%h,%b\n",
                        cycle_number, route_node, input_port,
                        dut.router_in_flit[route_node][input_port][60:59],
                        dut.router_in_flit[route_node][input_port][58:57],
                        dut.g_routers[route_node].router_wrapper.ingress_route[input_port],
                        dut.g_routers[route_node].router_wrapper.route_score,
                        dut.g_routers[route_node].router_wrapper.route_risk);
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n && cycle_number >= total_cycles) begin
            #1;
            drain_cycles++;
            if (local_in_valid == 0 && accepted_flits == delivered_flits) begin
                missing_flits = accepted_flits - delivered_flits;
                #1;
                $fclose(trace_fd);
                $fclose(route_trace_fd);
                $display("MESH TRACE SUMMARY: offered=%0d accepted=%0d delivered=%0d missing=%0d duplicates=%0d corrupted=%0d max_link_occupancy=%0d",
                    offered_flits, accepted_flits, delivered_flits, missing_flits,
                    duplicate_flits, corrupted_flits, maximum_link_occupancy);
                $display("MESH TRACE COMPLETE: seed=%0d load=%0d workload=%0d cycles=%0d file=%s",
                    seed_value, load_percent, workload, total_cycles, trace_path);
                $finish;
            end
            if (drain_cycles > 20000)
                $fatal(1, "Trace traffic did not drain; accepted=%0d delivered=%0d",
                       accepted_flits, delivered_flits);
        end
    end

    initial begin
        if (total_cycles <= HORIZON || load_percent < 0 || load_percent > 100 ||
            workload < 0 || workload > 8)
            $fatal(1, "Invalid trace parameters");
    end
endmodule
