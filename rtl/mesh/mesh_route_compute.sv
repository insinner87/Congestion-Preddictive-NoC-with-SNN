// Minimal next-hop selection for XY or West-First mesh routing.
//
// West-First mode forbids taking a West turn after any non-West hop. For a
// packet that still needs to move West, West is its only legal choice. When
// the destination is East and vertically displaced, East and the required
// vertical direction are both minimal and legal. All choices reduce
// Manhattan distance by exactly one.
module mesh_route_compute #(
    parameter int ROUTING_MODE = 0,
    parameter int GRID_SIZE = 4,
    parameter bit USE_SNN_SCORE = 1'b0
) (
    input  logic [1:0] current_x,
    input  logic [1:0] current_y,
    input  logic [1:0] destination_x,
    input  logic [1:0] destination_y,
    input  logic [4:0][7:0] congestion_score,
    input  logic [4:0] congestion_predicted,
    input  logic [4:0][7:0] snn_congestion_score,
    input  logic [4:0] snn_congestion_predicted,
    input  logic [4:0] candidate_available,
    input  logic score_valid,
    output logic [2:0] selected_port,
    output logic [4:0] legal_ports,
    output logic route_valid
);

    import noc_pkg::*;

    always @* begin : p_select_route
        logic [2:0] preferred_port;
        logic [7:0] best_score;
        logic [2:0] candidate_port;
        logic [4:0][7:0] route_costs;
        logic [4:0] route_risk_flags;

        legal_ports = '0;
        selected_port = PORT_LOCAL;
        preferred_port = PORT_LOCAL;
        best_score = 8'hff;
        candidate_port = PORT_LOCAL;
        route_costs = USE_SNN_SCORE ? snn_congestion_score : congestion_score;
        route_risk_flags = USE_SNN_SCORE ? snn_congestion_predicted : congestion_predicted;
        route_valid = 1'b1;

        if (current_x >= GRID_SIZE || current_y >= GRID_SIZE ||
            destination_x >= GRID_SIZE || destination_y >= GRID_SIZE) begin
            route_valid = 1'b0;
        end else if (current_x == destination_x &&
                     current_y == destination_y) begin
            legal_ports[PORT_LOCAL] = 1'b1;
        end else begin
            if (destination_x > current_x)
                preferred_port = PORT_EAST;
            else if (destination_x < current_x)
                preferred_port = PORT_WEST;
            else if (destination_y < current_y)
                preferred_port = PORT_NORTH;
            else
                preferred_port = PORT_SOUTH;

            legal_ports[preferred_port] = 1'b1;

            if (ROUTING_MODE == 1) begin
                if (destination_x < current_x) begin
                    legal_ports = 5'b10000;
                end else if (destination_x > current_x) begin
                    legal_ports[PORT_EAST] = 1'b1;
                    if (destination_y < current_y)
                        legal_ports[PORT_NORTH] = 1'b1;
                    else if (destination_y > current_y)
                        legal_ports[PORT_SOUTH] = 1'b1;
                end else if (destination_y < current_y) begin
                    legal_ports = 5'b00010;
                end else begin
                    legal_ports = 5'b00100;
                end
            end

            selected_port = preferred_port;
            if (ROUTING_MODE == 1 && score_valid &&
                route_risk_flags[preferred_port]) begin
                best_score = route_costs[preferred_port];
                for (int port = 0; port < 5; port++) begin
                    if (legal_ports[port] && candidate_available[port]) begin
                        candidate_port = port[2:0];
                        if (route_costs[candidate_port] < best_score) begin
                            selected_port = candidate_port;
                            best_score = route_costs[candidate_port];
                        end
                    end
                end
            end
        end
    end

    initial begin
        if (GRID_SIZE < 2 || GRID_SIZE > 4)
            $fatal(1, "mesh_route_compute supports grid sizes from 2 through 4");
        if (ROUTING_MODE < 0 || ROUTING_MODE > 1)
            $fatal(1, "ROUTING_MODE must be 0 (XY) or 1 (West-First adaptive)");
    end

endmodule
