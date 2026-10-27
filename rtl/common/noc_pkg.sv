package noc_pkg;

    // ==============================
    // Router Parameters
    // ==============================

    // The simple router uses 48-bit, single-flit packets. Bits [47:45] hold
    // the destination port; the remaining bits are application payload.
    parameter int FLIT_WIDTH = 48;

    // Number of waiting flits each router input can buffer.
    parameter int FIFO_DEPTH = 4;
    parameter int ADDR_WIDTH = 4;
    parameter int NUM_PORTS  = 5;


    // ==============================
    // Port Encoding
    // ==============================

    // These numeric values are also the destination codes in flit[47:45].
    // Codes 3'b101 through 3'b111 are invalid for this five-port router.
    typedef enum logic [2:0] {

        PORT_LOCAL = 3'd0,
        PORT_NORTH = 3'd1,
        PORT_SOUTH = 3'd2,
        PORT_EAST  = 3'd3,
        PORT_WEST  = 3'd4

    } port_t;

endpackage  
