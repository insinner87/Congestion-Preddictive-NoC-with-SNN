# NoC congestion predictor experiment summary

Dataset SHA-256: `470cc840113dc7ce5af86f0a4378d0e82433f559cf763c29bd7254fd6c627150`
Prediction horizon: 8 cycles

## Predictor results

### Validation
- **snn**: n=15552, accuracy=0.9722, precision=0.9166, recall=0.8935, F1=0.9049, FPR=0.0141, FNR=0.1065, confusion=[[13064, 187], [245, 2056]]
- **equation**: n=15552, accuracy=0.9720, precision=0.9413, recall=0.8644, F1=0.9012, FPR=0.0094, FNR=0.1356, confusion=[[13127, 124], [312, 1989]]
- SNN per-seed accuracy: 2001=0.9722

### Test
- **snn**: n=15552, accuracy=0.9628, precision=0.8715, recall=0.8779, F1=0.8747, FPR=0.0225, FNR=0.1221, confusion=[[12952, 298], [281, 2021]]
- **equation**: n=15552, accuracy=0.9670, precision=0.9135, recall=0.8584, F1=0.8851, FPR=0.0141, FNR=0.1416, confusion=[[13063, 187], [326, 1976]]
- SNN per-seed accuracy: 3001=0.9628

## End-to-end routing regressions
- `mesh-xy`: not_run
- `mesh-west-first`: not_run
- `mesh-west-first-baseline`: not_run
- `mesh-west-first-snn`: not_run
- `mesh-west-first-equation`: not_run
- `mesh-west-first-adaptive`: not_run
