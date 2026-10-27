# Congestion diagnostics RTL

`congestion_monitor.sv` tracks requester wait, output blocking, and
windowed demand/service. `congestion_estimator.sv` preserves the original
TF-PCR diagnostic score. `tf_feature_extractor.sv` adds bounded request/service
windows and trend features. `snn_predictor.sv` implements a small integer LIF
risk model using `snn_model_parameters_pkg.sv`. `adaptive_buffer_controller.sv`
emits hysteretic early pressure without changing FIFO admission, and
`congestion_offload_controller.sv` supplies a persistent risk trigger. Compile
`rtl\common\noc_pkg.sv` and the SNN parameter package before these modules.
