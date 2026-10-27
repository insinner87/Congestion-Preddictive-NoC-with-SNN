# Five-port router RTL

This folder contains the five-port router and its FIFO, input-buffer,
round-robin/priority arbiter, switch allocator, and crossbar modules. The
48-bit data flit format is unchanged. A two-bit priority sideband is stored
and forwarded alongside each flit; priority arbitration is optional and off
by default. Mesh nodes use this router through `rtl\mesh\`.
