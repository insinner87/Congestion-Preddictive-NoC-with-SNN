module mesh_route_compute_tb;

    logic [1:0] current_x = '0;
    logic [1:0] current_y = '0;
    logic [1:0] destination_x = '0;
    logic [1:0] destination_y = '0;
    logic [4:0][7:0] congestion_score = '0;
    logic [4:0] congestion_predicted = '0;
    logic [4:0] candidate_available = '1;
    logic score_valid = 1'b0;
    logic [2:0] xy_port;
    logic [4:0] xy_legal;
    logic xy_valid;
    logic [2:0] west_first_port;
    logic [4:0] west_first_legal;
    logic west_first_valid;

    int tested_pairs = 0;

    mesh_route_compute #(.ROUTING_MODE(0)) xy (
        .current_x(current_x),
        .current_y(current_y),
        .destination_x(destination_x),
        .destination_y(destination_y),
        .congestion_score(congestion_score),
        .congestion_predicted(congestion_predicted),
        .snn_congestion_score({5{8'b0}}),
        .snn_congestion_predicted(5'b0),
        .candidate_available(candidate_available),
        .score_valid(score_valid),
        .selected_port(xy_port),
        .legal_ports(xy_legal),
        .route_valid(xy_valid)
    );

    mesh_route_compute #(.ROUTING_MODE(1)) west_first (
        .current_x(current_x),
        .current_y(current_y),
        .destination_x(destination_x),
        .destination_y(destination_y),
        .congestion_score(congestion_score),
        .congestion_predicted(congestion_predicted),
        .snn_congestion_score({5{8'b0}}),
        .snn_congestion_predicted(5'b0),
        .candidate_available(candidate_available),
        .score_valid(score_valid),
        .selected_port(west_first_port),
        .legal_ports(west_first_legal),
        .route_valid(west_first_valid)
    );

    task automatic verify_path(
        input integer source,
        input integer destination,
        input logic adaptive
    );
        integer x;
        integer y;
        integer previous_distance;
        integer distance;
        integer steps;
        logic west_started;
        logic [2:0] selected;
        logic [4:0] legal;
        logic route_ok;

        x = source % 4;
        y = source / 4;
        west_started = 1'b0;
        steps = 0;

        while ((x != destination % 4 || y != destination / 4) && steps < 6) begin
            current_x = 2'(x);
            current_y = 2'(y);
            destination_x = 2'(destination % 4);
            destination_y = 2'(destination / 4);
            #1;

            if (adaptive) begin
                selected = west_first_port;
                legal = west_first_legal;
                route_ok = west_first_valid;
            end else begin
                selected = xy_port;
                legal = xy_legal;
                route_ok = xy_valid;
            end

            if (!route_ok || !legal[selected])
                $fatal(1, "route invalid for %0d -> %0d at (%0d,%0d)",
                       source, destination, x, y);

            previous_distance =
                (x > destination % 4 ? x - destination % 4 : destination % 4 - x) +
                (y > destination / 4 ? y - destination / 4 : destination / 4 - y);
            case (selected)
                noc_pkg::PORT_NORTH: y--;
                noc_pkg::PORT_SOUTH: y++;
                noc_pkg::PORT_EAST: x++;
                noc_pkg::PORT_WEST: x--;
                default: $fatal(1, "nonlocal route selected Local for %0d -> %0d",
                                source, destination);
            endcase
            distance =
                (x > destination % 4 ? x - destination % 4 : destination % 4 - x) +
                (y > destination / 4 ? y - destination / 4 : destination / 4 - y);
            if (distance != previous_distance - 1)
                $fatal(1, "route does not make minimal progress for %0d -> %0d",
                       source, destination);

            if (adaptive) begin
                if (selected == noc_pkg::PORT_WEST) begin
                    if (west_started)
                        $fatal(1, "duplicate West-first phase");
                end else begin
                    west_started = 1'b1;
                end
                if (west_started && selected == noc_pkg::PORT_WEST)
                    $fatal(1, "West-First turn restriction violated for %0d -> %0d",
                           source, destination);
            end

            steps++;
        end
        if (x != destination % 4 || y != destination / 4)
            $fatal(1, "route failed to reach destination for %0d -> %0d",
                   source, destination);
    endtask

    initial begin
        for (int source = 0; source < 16; source++) begin
            for (int destination = 0; destination < 16; destination++) begin
                verify_path(source, destination, 1'b0);
                verify_path(source, destination, 1'b1);
                tested_pairs++;
            end
        end

        // When the XY-preferred East output predicts congestion, the
        // West-First selector must choose a lower-score legal North option.
        current_x = 2'd0;
        current_y = 2'd1;
        destination_x = 2'd1;
        destination_y = 2'd0;
        congestion_score = '0;
        congestion_score[noc_pkg::PORT_EAST] = 8'd200;
        congestion_score[noc_pkg::PORT_NORTH] = 8'd10;
        congestion_predicted = '0;
        congestion_predicted[noc_pkg::PORT_EAST] = 1'b1;
        score_valid = 1'b1;
        #1;
        if (west_first_port != noc_pkg::PORT_NORTH ||
            !west_first_legal[west_first_port])
            $fatal(1, "adaptive selector did not take the lower-score legal route");

        // A predicted safer alternate that cannot accept a flit must not be
        // selected; retain the deterministic preferred legal route.
        candidate_available[noc_pkg::PORT_NORTH] = 1'b0;
        #1;
        if (west_first_port != noc_pkg::PORT_EAST)
            $fatal(1, "unavailable alternate route was selected");
        candidate_available[noc_pkg::PORT_NORTH] = 1'b1;

        congestion_score[noc_pkg::PORT_EAST] = 8'd20;
        congestion_score[noc_pkg::PORT_NORTH] = 8'd20;
        congestion_predicted[noc_pkg::PORT_NORTH] = 1'b1;
        congestion_predicted[noc_pkg::PORT_EAST] = 1'b1;
        #1;
        if (west_first_port != noc_pkg::PORT_EAST)
            $fatal(1, "equal-score tie must retain deterministic XY preference");

        // When West is the only West-First candidate, a lower score on an
        // illegal direction must not permit a turn that violates the model.
        current_x = 2'd2;
        current_y = 2'd1;
        destination_x = 2'd1;
        destination_y = 2'd0;
        congestion_score = '0;
        congestion_score[noc_pkg::PORT_WEST] = 8'd200;
        congestion_predicted = '0;
        congestion_predicted[noc_pkg::PORT_WEST] = 1'b1;
        #1;
        if (west_first_port != noc_pkg::PORT_WEST ||
            west_first_legal != 5'b10000)
            $fatal(1, "risk score selected an illegal alternate route");

        $display("ROUTE TESTS PASSED: %0d XY + %0d West-First pairs and adaptive legality cases",
                 tested_pairs, tested_pairs);
        $finish;
    end

endmodule
