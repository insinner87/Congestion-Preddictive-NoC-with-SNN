// Registered ready/valid link buffer for a flit and its priority sideband.
// Source readiness depends only on local registered occupancy, preventing
// ready-path loops around the mesh.
module mesh_link_fifo #(
    parameter int DATA_WIDTH = 64,
    parameter int DEPTH = 2,
    parameter int COUNT_WIDTH = $clog2(DEPTH) + 1,
    parameter int POINTER_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    parameter int PRIORITY_WIDTH = 2
) (
    input  logic clk,
    input  logic rst_n,
    input  logic source_valid,
    output logic source_ready,
    input  logic [DATA_WIDTH-1:0] source_data,
    input  logic [PRIORITY_WIDTH-1:0] source_priority,
    output logic destination_valid,
    input  logic destination_ready,
    output logic [DATA_WIDTH-1:0] destination_data,
    output logic [PRIORITY_WIDTH-1:0] destination_priority,
    output logic [COUNT_WIDTH-1:0] occupancy
);

    logic [DATA_WIDTH+PRIORITY_WIDTH-1:0] storage [0:DEPTH-1];
    logic [POINTER_WIDTH-1:0] write_pointer;
    logic [POINTER_WIDTH-1:0] read_pointer;
    logic [COUNT_WIDTH-1:0] count;
    logic write_enable;
    logic read_enable;

    assign source_ready = count < DEPTH;
    assign destination_valid = count != 0;
    assign destination_data = destination_valid ?
        storage[read_pointer][DATA_WIDTH-1:0] : '0;
    assign destination_priority = destination_valid ?
        storage[read_pointer][DATA_WIDTH+PRIORITY_WIDTH-1:DATA_WIDTH] : '0;
    assign occupancy = count;
    assign write_enable = source_valid && source_ready;
    assign read_enable = destination_valid && destination_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_pointer <= '0;
            read_pointer <= '0;
            count <= '0;
        end else begin
            if (write_enable) begin
                storage[write_pointer] <= {source_priority, source_data};
                if (write_pointer == DEPTH - 1)
                    write_pointer <= '0;
                else
                    write_pointer <= write_pointer + 1'b1;
            end

            if (read_enable) begin
                if (read_pointer == DEPTH - 1)
                    read_pointer <= '0;
                else
                    read_pointer <= read_pointer + 1'b1;
            end

            case ({write_enable, read_enable})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

    initial begin
        if (DEPTH < 1)
            $fatal(1, "mesh_link_fifo DEPTH must be positive");
    end

endmodule
