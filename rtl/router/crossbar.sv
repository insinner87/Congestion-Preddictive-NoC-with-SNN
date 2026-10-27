// Five-input, five-output flit crossbar.
//
// The switch allocator grants at most one input to each output. This module
// uses those grants to select the actual flit data. It also generates the pop
// signals that remove flits from the input FIFOs when an output accepts them.
//
// For example, if grant[East][Local] is 1, Local's FIFO head is copied to the
// East output. It leaves Local's FIFO only on a clock edge when East is ready.
module crossbar #(
    parameter int NUM_PORTS = noc_pkg::NUM_PORTS,
    parameter int FLIT_WIDTH = noc_pkg::FLIT_WIDTH
) (
    // One FIFO head flit and one grant row per input/output port.
    input  logic [NUM_PORTS-1:0][FLIT_WIDTH-1:0] input_flit,
    input  logic [NUM_PORTS-1:0][1:0] input_priority,
    input  logic [NUM_PORTS*NUM_PORTS-1:0] grant,
    input  logic [NUM_PORTS-1:0] grant_valid,

    // Downstream ready and the corresponding public ready/valid data outputs.
    input  logic [NUM_PORTS-1:0] output_ready,
    output logic [NUM_PORTS-1:0] output_valid,
    output logic [NUM_PORTS-1:0][FLIT_WIDTH-1:0] output_flit,
    output logic [NUM_PORTS-1:0][1:0] output_priority,

    // One pop signal per input FIFO. This is asserted only for a real
    // downstream transfer: grant is present AND that destination is ready.
    output logic [NUM_PORTS-1:0] input_pop
);

    // Build each output's data mux independently. The allocator gives no more
    // than one selected input per output, so only one input should match.
    always_comb begin : p_route_flits
        output_valid = grant_valid;
        output_flit = '0;
        output_priority = '0;
        input_pop = '0;

        for (int output_port = 0; output_port < NUM_PORTS; output_port++) begin
            for (int input_port = 0; input_port < NUM_PORTS; input_port++) begin
                if (grant[output_port * NUM_PORTS + input_port]) begin
                    output_flit[output_port] = input_flit[input_port];
                    output_priority[output_port] = input_priority[input_port];

                    // Ready/valid transfer rule:
                    //   output_valid && output_ready means accepted now.
                    // Only then is it safe to remove the input's FIFO head.
                    if (output_ready[output_port])
                        input_pop[input_port] = 1'b1;
                end
            end
        end
    end

    initial begin
        if (NUM_PORTS != 5)
            $fatal(1, "crossbar currently supports exactly five ports");
    end

endmodule
