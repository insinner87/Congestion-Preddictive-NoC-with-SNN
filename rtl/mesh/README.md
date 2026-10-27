# Mesh RTL

`noc_mesh_4x4.sv` connects 16 existing routers. `noc_router_wrapper.sv`
decodes coordinate destinations and selects legal hops;
`mesh_route_compute.sv` implements XY and West-First choices with an optional
SNN-risk score input; `mesh_link_fifo.sv` registers inter-router links.
The two-bit priority sideband is preserved across router and link FIFOs;
priority arbitration is optional and disabled by default. Optional SNN,
adaptive buffer-pressure, and persistent offload controls are disabled by
default. See
`docs\TF-PCR-VALIDATION.md` for packet layout, boundary handling, and routing
constraints.
