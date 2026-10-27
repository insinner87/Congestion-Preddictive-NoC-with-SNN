# Mesh testbenches

`mesh_noc_tb.sv` is the mesh regression top. Its include fragments separate
trace capture/scoreboarding, packet helpers, detector evaluation, scenarios,
and the timeout guard. `mesh_route_compute_tb.sv` exhaustively checks route
selection; `snn_routing_tb.sv` checks that persistent SNN risk changes the
actual West-First next hop without disturbing a stalled packet. The mesh
scoreboard checks priority sideband preservation end to end; the regression
has priority-only and integrated SNN/priority configurations. Run all tests
through `validation\run-all.ps1`.
