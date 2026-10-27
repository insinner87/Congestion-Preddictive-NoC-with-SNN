// Reusable flit construction and ready/valid driver tasks.
    // Pack a port number into [47:45] and a recognizable value into payload.
    function automatic logic [FLITWIDTH-1:0] make_flit(
        input logic [2:0] destination,
        input logic [44:0] payload
    );
        return {destination, payload};
    endfunction

    // Drive an input until a rising edge accepts its valid flit. The upstream
    // must keep valid/data stable until ready is also high.
    task automatic send_flit(
        input int source,
        input logic [FLITWIDTH-1:0] flit
    );
        @(negedge clk);
        in_flit[source] = flit;
        in_valid[source] = 1'b1;

        do begin
            @(posedge clk);
        end while (!in_ready[source]);

        // Deassert valid away from the active clock edge to avoid a testbench
        // race with the router's sequential FIFO logic.
        @(negedge clk);
        in_valid[source] = 1'b0;
    endtask

    // With the output ready, check the head flit and let the next rising edge
    // transfer it. The destination is an output port index, not an input index.
    task automatic expect_transfer(
        input int destination,
        input logic [FLITWIDTH-1:0] expected_flit
    );
        // Call after a sender task returns on a falling edge, or just after a
        // previous transfer's rising edge. Check before the next transfer edge.
        #1;
        if (!out_valid[destination])
            $fatal(1, "FAIL: expected valid flit on output %0d", destination);
        if (out_flit[destination] !== expected_flit)
            $fatal(1, "FAIL: output %0d expected %h, got %h",
                   destination, expected_flit, out_flit[destination]);
        if (!out_ready[destination])
            $fatal(1, "FAIL: test expected output %0d to be ready", destination);

        @(posedge clk);
        #1;
        checks_passed++;
    endtask

