// Per-output round-robin arbiter with optional four-class priority and aging.
//
// There is one copy of this module per output port. Its request vector has one
// bit for each input FIFO that wants this output. If several inputs request at
// once, the arbiter grants one input and remembers where the next search starts.
//
// Example with five requesters:
//   request = 5'b01010 means inputs 1 and 3 both want this output.
//   If the search starts at input 0, input 1 wins first.
//   After input 1 transfers, the next search starts at input 2, so input 3 can
//   win the next time both inputs are requesting.
//
// The arbiter also locks a grant if the output is not ready. This is necessary
// for ready/valid protocols: while valid=1 and ready=0, the selected flit must
// remain the same until it is accepted.
// In priority mode, class 3 is highest; round-robin selects among equal
// classes. A request waiting AGE_LIMIT unsuccessful cycles is promoted ahead
// of priority peers, with aged requesters also served round-robin.
module round_robin_arbiter #(
    parameter int NUM_REQUESTERS = 5,
    parameter int INDEX_WIDTH = (NUM_REQUESTERS > 1) ? $clog2(NUM_REQUESTERS) : 1,
    parameter bit ENABLE_PRIORITY = 1'b0,
    parameter int AGE_LIMIT = 16,
    parameter int AGE_WIDTH = (AGE_LIMIT > 1) ? $clog2(AGE_LIMIT + 1) : 1
) (
    input  logic                         clk,
    input  logic                         rst_n,

    // One request bit from each input FIFO for this particular output.
    input  logic [NUM_REQUESTERS-1:0]    request,
    // Two-bit class for each requester, paired with its FIFO head flit.
    input  logic [NUM_REQUESTERS-1:0][1:0] request_priority,

    // ready is the downstream output's ready signal.
    input  logic                         ready,

    // One-hot grant is convenient for controlling the crossbar.
    output logic [NUM_REQUESTERS-1:0]    grant_onehot,
    output logic                         grant_valid,

    // Binary input number is useful for status/debug and arbitration state.
    output logic [INDEX_WIDTH-1:0]       grant_index
);

    // Search begins here after reset and moves past each successfully served
    // requester. It is state: unlike a combinational priority encoder, its
    // changing value makes the choice fair over time.
    logic [INDEX_WIDTH-1:0] next_start;

    // A stalled output holds its original input selection. The requester keeps
    // its FIFO head until ready, so that saved index continues to refer to the
    // same unconsumed flit.
    logic                   grant_locked;
    logic [INDEX_WIDTH-1:0] locked_index;
    logic [AGE_WIDTH-1:0]   wait_age [0:NUM_REQUESTERS-1];

    always_comb begin : p_choose_grant
        integer offset;
        integer candidate;
        integer best_priority;
        logic aged_request_found;

        // Safe defaults represent "no requester selected".
        grant_onehot = '0;
        grant_valid = 1'b0;
        grant_index = '0;
        best_priority = -1;
        aged_request_found = 1'b0;

        if (grant_locked) begin
            // Do not change the output's offered flit during backpressure.
            grant_index = locked_index;
            if (request[locked_index]) begin
                grant_onehot[locked_index] = 1'b1;
                grant_valid = 1'b1;
            end
        end else if (ENABLE_PRIORITY) begin
            // Once a request has waited AGE_LIMIT unsuccessful cycles, serve
            // an aged requester before considering priority. The rotating
            // start position preserves round-robin fairness among aged peers.
            for (offset = 0; offset < NUM_REQUESTERS; offset++) begin
                candidate = (next_start + offset) % NUM_REQUESTERS;
                if (!aged_request_found && request[candidate] &&
                    wait_age[candidate] >= AGE_LIMIT) begin
                    grant_onehot[candidate] = 1'b1;
                    grant_valid = 1'b1;
                    grant_index = candidate;
                    aged_request_found = 1'b1;
                end
            end

            // Otherwise choose the highest class. Because candidates are
            // visited in round-robin order and equal classes do not replace
            // the current winner, ties rotate fairly.
            if (!aged_request_found) begin
                for (offset = 0; offset < NUM_REQUESTERS; offset++) begin
                    candidate = (next_start + offset) % NUM_REQUESTERS;
                    if (request[candidate] &&
                        int'(request_priority[candidate]) > best_priority) begin
                        grant_onehot = '0;
                        grant_onehot[candidate] = 1'b1;
                        grant_valid = 1'b1;
                        grant_index = candidate;
                        best_priority = request_priority[candidate];
                    end
                end
            end
        end else begin
            // Scan all requester positions, starting at next_start and
            // wrapping around. The first active request becomes the winner.
            for (offset = 0; offset < NUM_REQUESTERS; offset++) begin
                candidate = (next_start + offset) % NUM_REQUESTERS;

                if (!grant_valid && request[candidate]) begin
                    grant_onehot[candidate] = 1'b1;
                    grant_valid = 1'b1;
                    grant_index = candidate;
                end
            end
        end
    end

    // Update fairness and lock state only on a clock edge.
    always_ff @(posedge clk or negedge rst_n) begin : p_update_arbiter_state
        if (!rst_n) begin
            next_start <= '0;
            grant_locked <= 1'b0;
            locked_index <= '0;
            for (int requester = 0; requester < NUM_REQUESTERS; requester++)
                wait_age[requester] <= '0;
        end else if (grant_valid && !ready) begin
            // The output is showing a flit, but its receiver has not taken it.
            // Save the winning input so a new request cannot replace that flit.
            grant_locked <= 1'b1;
            locked_index <= grant_index;

            for (int requester = 0; requester < NUM_REQUESTERS; requester++) begin
                if (!ENABLE_PRIORITY || !request[requester])
                    wait_age[requester] <= '0;
                else if (wait_age[requester] < AGE_LIMIT)
                    wait_age[requester] <= wait_age[requester] + 1'b1;
            end
        end else if (grant_valid && ready) begin
            // A transfer happened (valid and ready). Let the requester after
            // this winner have first chance in the next arbitration.
            if (grant_index == NUM_REQUESTERS - 1)
                next_start <= '0;
            else
                next_start <= grant_index + 1'b1;

            grant_locked <= 1'b0;

            for (int requester = 0; requester < NUM_REQUESTERS; requester++) begin
                if (!ENABLE_PRIORITY || !request[requester] ||
                    requester == grant_index)
                    wait_age[requester] <= '0;
                else if (wait_age[requester] < AGE_LIMIT)
                    wait_age[requester] <= wait_age[requester] + 1'b1;
            end
        end else begin
            for (int requester = 0; requester < NUM_REQUESTERS; requester++)
                if (!ENABLE_PRIORITY || !request[requester])
                    wait_age[requester] <= '0;
        end
    end

    initial begin
        if (NUM_REQUESTERS < 1)
            $fatal(1, "NUM_REQUESTERS must be at least one");
        if (AGE_LIMIT < 1)
            $fatal(1, "AGE_LIMIT must be positive");
    end

endmodule
