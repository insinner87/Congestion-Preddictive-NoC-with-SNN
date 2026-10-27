# Standalone simulation outputs

`run-router.ps1` and `run-mesh.ps1` each create a timestamped child directory
here, keeping separate router and mesh runs without overwriting prior output.
Each run stores the Icarus executable, compiler transcript, simulation log,
and any result/waveform files produced by its testbench.
