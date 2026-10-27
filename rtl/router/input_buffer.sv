// One input queue for one router port.
//
// The router instantiates five copies of this module: Local, North, South,
// East, and West. Each queue preserves the order of flits arriving on its
// input, even when another input is selected for an output.
module input_buffer #(
    parameter int DATA_WIDTH = 48,
    parameter int FIFO_DEPTH = 4,
    parameter int COUNT_WIDTH = $clog2(FIFO_DEPTH) + 1
) (
    input  logic                  clk,
    input  logic                  rst_n,

    // Upstream ready/valid interface.
    input  logic                  in_valid,
    output logic                  in_ready,
    input  logic [DATA_WIDTH-1:0] in_data,

    // Head-of-queue ready/valid interface to the router switch.
    output logic                  out_valid,
    input  logic                  pop,
    output logic [DATA_WIDTH-1:0] out_data,
    output logic [COUNT_WIDTH-1:0] occupancy
);

    logic full;
    logic empty;

    // When full, accept a new flit on the same cycle that the router removes
    // the current head. This allows continuous traffic without a bubble.
    assign in_ready = !full || pop;

    // `out_valid` says the FIFO has a flit available. The router asserts pop
    // only when that flit is actually consumed (or deliberately discarded).
    assign out_valid = !empty;

    fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) queue (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (in_valid && in_ready),
        .rd_en   (pop),
        .wr_data (in_data),
        .rd_data (out_data),
        .full    (full),
        .empty   (empty),
        .count   (occupancy)
    );

endmodule
