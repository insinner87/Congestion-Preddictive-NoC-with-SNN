// Occupancy-based early pressure notification with hysteresis.
// This block never changes FIFO capacity or its ready/full semantics.
module adaptive_buffer_controller #(
    parameter int NUM_INPUTS = noc_pkg::NUM_PORTS,
    parameter int FIFO_DEPTH = noc_pkg::FIFO_DEPTH,
    parameter int OCCUPANCY_WIDTH = $clog2(FIFO_DEPTH + 1),
    parameter int COUNTER_WIDTH = 3,
    parameter int ASSERT_CYCLES = 2,
    parameter int RECOVERY_CYCLES = 2,
    parameter int EARLY_OCCUPANCY_THRESHOLD = (FIFO_DEPTH > 2) ? FIFO_DEPTH - 2 : 1,
    parameter int ASSERT_OCCUPANCY_THRESHOLD = (FIFO_DEPTH > 1) ? FIFO_DEPTH - 1 : 1,
    parameter int RECOVERY_OCCUPANCY_THRESHOLD = FIFO_DEPTH / 2
) (
    input  logic clk,
    input  logic rst_n,
    input  logic [NUM_INPUTS-1:0][OCCUPANCY_WIDTH-1:0] occupancy,
    output logic [NUM_INPUTS-1:0] buffer_pressure
);

    logic [NUM_INPUTS-1:0][OCCUPANCY_WIDTH-1:0] previous_occupancy;
    logic [NUM_INPUTS-1:0][COUNTER_WIDTH-1:0] high_occupancy_cycles;
    logic [NUM_INPUTS-1:0][COUNTER_WIDTH-1:0] recovery_cycles;

    always_ff @(posedge clk or negedge rst_n) begin : p_pressure_hysteresis
        if (!rst_n) begin
            previous_occupancy <= '0;
            high_occupancy_cycles <= '0;
            recovery_cycles <= '0;
            buffer_pressure <= '0;
        end else begin
            for (int input_port = 0; input_port < NUM_INPUTS; input_port++) begin
                previous_occupancy[input_port] <= occupancy[input_port];

                if (occupancy[input_port] >= ASSERT_OCCUPANCY_THRESHOLD) begin
                    if (high_occupancy_cycles[input_port] < ASSERT_CYCLES)
                        high_occupancy_cycles[input_port] <=
                            high_occupancy_cycles[input_port] + 1'b1;
                end else begin
                    high_occupancy_cycles[input_port] <= '0;
                end

                if (!buffer_pressure[input_port]) begin
                    recovery_cycles[input_port] <= '0;
                    if (occupancy[input_port] >= ASSERT_OCCUPANCY_THRESHOLD &&
                        high_occupancy_cycles[input_port] >= ASSERT_CYCLES - 1)
                        buffer_pressure[input_port] <= 1'b1;
                    else if (occupancy[input_port] >= EARLY_OCCUPANCY_THRESHOLD &&
                             occupancy[input_port] > previous_occupancy[input_port])
                        buffer_pressure[input_port] <= 1'b1;
                end else if (occupancy[input_port] <= RECOVERY_OCCUPANCY_THRESHOLD) begin
                    if (recovery_cycles[input_port] < RECOVERY_CYCLES - 1) begin
                        recovery_cycles[input_port] <= recovery_cycles[input_port] + 1'b1;
                    end else begin
                        recovery_cycles[input_port] <= '0;
                        buffer_pressure[input_port] <= 1'b0;
                    end
                end else begin
                    recovery_cycles[input_port] <= '0;
                end
            end
        end
    end

    initial begin
        if (NUM_INPUTS < 1 || FIFO_DEPTH < 1)
            $fatal(1, "adaptive_buffer_controller dimensions must be positive");
        if (ASSERT_CYCLES < 1 || RECOVERY_CYCLES < 1 || COUNTER_WIDTH < 1)
            $fatal(1, "adaptive buffer persistence parameters must be positive");
        if (ASSERT_OCCUPANCY_THRESHOLD < 1 ||
            RECOVERY_OCCUPANCY_THRESHOLD >= ASSERT_OCCUPANCY_THRESHOLD)
            $fatal(1, "adaptive buffer hysteresis thresholds are invalid");
    end
endmodule
