# Router regression

`router_5port_tb.sv` is the top-level testbench. Its `.svh` fragments separate
the assertions/reference scoreboard, ready/valid drivers, and directed
scenarios. They are included by that top-level file and should not be compiled
as independent compilation units. Run `validation\run-all.ps1` to test with
TF-PCR enabled and disabled. `priority_arbiter_tb.sv` verifies class ordering,
round-robin tie handling, age promotion, and stable grants under backpressure.
