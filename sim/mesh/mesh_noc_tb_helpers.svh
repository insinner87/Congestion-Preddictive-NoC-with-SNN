// Packet construction, injection, and delivery helper tasks.
    function automatic logic [63:0] make_packet(
        input integer destination,
        input integer tag
    );
        return {
            3'b000,
            2'(destination % 4),
            2'(destination / 4),
            25'b0,
            32'(tag)
        };
    endfunction

    task automatic prepare_packet(input integer destination, input integer tag);
        if (tag <= 0 || tag >= MAX_TAGS)
            $fatal(1, "test tag %0d is outside scoreboard capacity", tag);
        expected_flit[tag] = make_packet(destination, tag);
        expected_priority[tag] = 2'(tag % 4);
        expected_node[tag] = destination;
        expected_valid[tag] = 1'b1;
        expected_injected[tag] = 1'b0;
        injection_cycle[tag] = 0;
        expected_packets++;
    endtask

    task automatic send_packet(
        input integer source,
        input integer destination,
        input integer tag
    );
        @(negedge clk);
        local_in_flit[source] = make_packet(destination, tag);
        local_in_priority[source] = expected_priority[tag];
        local_in_valid[source] = 1'b1;

        do begin
            @(posedge clk);
        end while (!local_in_ready[source]);

        @(negedge clk);
        local_in_valid[source] = 1'b0;
    endtask

    task automatic wait_for_tag(input integer tag);
        integer timeout_cycles;
        timeout_cycles = 0;
        while (!received[tag] && timeout_cycles < 2000) begin
            @(negedge clk);
            timeout_cycles++;
        end
        if (!received[tag])
            $fatal(1, "timeout waiting for packet tag %0d", tag);
    endtask

