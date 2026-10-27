// Persistent predicted-risk trigger for alternate legal next-hop selection.
// This controller does not move, copy, or split a packet already in a FIFO.
module congestion_offload_controller #(
    parameter int NUM_PORTS = noc_pkg::NUM_PORTS,
    parameter int COUNTER_WIDTH = 3,
    parameter int TRIGGER_CLASS = 2,
    parameter int RECOVERY_CLASS = 1,
    parameter int TRIGGER_CYCLES = 2,
    parameter int RECOVERY_CYCLES = 2
) (
    input  logic clk,
    input  logic rst_n,
    input  logic [NUM_PORTS-1:0][1:0] risk_class,
    input  logic [NUM_PORTS-1:0] risk_valid,
    output logic [NUM_PORTS-1:0] offload_active,
    output logic [NUM_PORTS-1:0] offload_start_pulse
);

    logic [NUM_PORTS-1:0][COUNTER_WIDTH-1:0] trigger_count;
    logic [NUM_PORTS-1:0][COUNTER_WIDTH-1:0] recovery_count;

    always_ff @(posedge clk or negedge rst_n) begin : p_offload_hysteresis
        if (!rst_n) begin
            trigger_count <= '0;
            recovery_count <= '0;
            offload_active <= '0;
            offload_start_pulse <= '0;
        end else begin
            offload_start_pulse <= '0;
            for (int output_port = 0; output_port < NUM_PORTS; output_port++) begin
                if (!risk_valid[output_port]) begin
                    trigger_count[output_port] <= '0;
                    recovery_count[output_port] <= '0;
                    offload_active[output_port] <= 1'b0;
                end else if (!offload_active[output_port]) begin
                    recovery_count[output_port] <= '0;
                    if (risk_class[output_port] >= TRIGGER_CLASS) begin
                        if (trigger_count[output_port] < TRIGGER_CYCLES)
                            trigger_count[output_port] <= trigger_count[output_port] + 1'b1;
                        if (trigger_count[output_port] >= TRIGGER_CYCLES - 1) begin
                            offload_active[output_port] <= 1'b1;
                            offload_start_pulse[output_port] <= 1'b1;
                            trigger_count[output_port] <= '0;
                        end
                    end else begin
                        trigger_count[output_port] <= '0;
                    end
                end else begin
                    trigger_count[output_port] <= '0;
                    if (risk_class[output_port] <= RECOVERY_CLASS) begin
                        if (recovery_count[output_port] < RECOVERY_CYCLES - 1)
                            recovery_count[output_port] <= recovery_count[output_port] + 1'b1;
                        else begin
                            recovery_count[output_port] <= '0;
                            offload_active[output_port] <= 1'b0;
                        end
                    end else begin
                        recovery_count[output_port] <= '0;
                    end
                end
            end
        end
    end

    initial begin
        if (NUM_PORTS < 1 || COUNTER_WIDTH < 1)
            $fatal(1, "congestion_offload_controller dimensions must be positive");
        if (TRIGGER_CLASS < 1 || TRIGGER_CLASS > 3 ||
            RECOVERY_CLASS < 0 || RECOVERY_CLASS >= TRIGGER_CLASS)
            $fatal(1, "offload trigger/recovery classes are invalid");
        if (TRIGGER_CYCLES < 1 || RECOVERY_CYCLES < 1)
            $fatal(1, "offload persistence values must be positive");
    end
endmodule
