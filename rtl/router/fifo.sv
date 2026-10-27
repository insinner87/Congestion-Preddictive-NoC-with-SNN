// A synchronous FIFO (first in, first out) for buffering router flits.
// The oldest accepted write is the next item returned by a read.
module fifo #(
    parameter int DATA_WIDTH = 48,
    parameter int FIFO_DEPTH = 4
)(
    input logic                     clk,
    input logic                     rst_n,
    input logic                     wr_en,
    input logic                     rd_en,
    input logic [DATA_WIDTH-1:0]    wr_data,
    output logic [DATA_WIDTH-1:0]   rd_data,
    output logic                    full,
    output logic                    empty,
    output logic [$clog2(FIFO_DEPTH):0] count
);

    // For a depth of 4, two bits are enough to address entries 0 through 3.
    // Keep at least one bit so the pointer is also valid when depth is 1.
    localparam int PTRWIDTH = (FIFO_DEPTH > 1) ? $clog2(FIFO_DEPTH) : 1;

    logic [DATA_WIDTH-1:0] storage [0:FIFO_DEPTH-1];
    logic [PTRWIDTH-1:0]  write_ptr;
    logic [PTRWIDTH-1:0]  read_ptr;
    logic                  do_write;
    logic                  do_read;

    // count is the number of stored items; its extra bit represents FIFO_DEPTH.
    assign empty = (count == 0);
    assign full  = (count == FIFO_DEPTH);

    // Present the oldest item at the output. The output is zero when empty;
    // consumers should use empty to determine whether rd_data is meaningful.
    assign rd_data = empty ? '0 : storage[read_ptr];

    // Do not read an empty FIFO. When full, accept a write only if a read on
    // this same clock edge frees a slot.
    assign do_read  = rd_en && !empty;
    assign do_write = wr_en && (!full || do_read);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= '0;
            read_ptr  <= '0;
            count     <= '0;
        end else begin
            // Store new data at the write pointer, then advance it circularly.
            if (do_write) begin
                storage[write_ptr] <= wr_data;
                if (write_ptr == FIFO_DEPTH - 1)
                    write_ptr <= '0;
                else
                    write_ptr <= write_ptr + 1'b1;
            end

            // A read advances the pointer to the next-oldest item.
            if (do_read) begin
                if (read_ptr == FIFO_DEPTH - 1)
                    read_ptr <= '0;
                else
                    read_ptr <= read_ptr + 1'b1;
            end

            // A simultaneous accepted read and write replaces one item with
            // another, so the number of stored items does not change.
            case ({do_write, do_read})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

    initial begin
        if (FIFO_DEPTH < 1)
            $fatal(1, "FIFO_DEPTH must be at least 1");
    end

endmodule
