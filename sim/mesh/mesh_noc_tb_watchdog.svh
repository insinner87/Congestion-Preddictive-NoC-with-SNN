// Fails a stalled regression instead of hanging indefinitely.
    initial begin
        repeat (20000) @(posedge clk);
        $fatal(1, "mesh test timed out");
    end
