# SNN-to-equation distillation

## Method

After version 1 of the integer SNN passed validation, a seven-input logistic
regression was fit to its binary congestion decisions. The inputs are the same
seven event bits supplied to the SNN. Candidate regularization values were
selected on validation; coefficients and bias were then quantized at scale 4
to signed integer values for an inexpensive fixed-point implementation. The
decision threshold is zero. The final test split was evaluated after this
choice and was not used to fit or select the equation.

## Derived expression

For binary event inputs `x0` through `x6` in the feature order specified in
[feature_specification.md](feature_specification.md):

```text
R = -15 + 3*x0 + 1*x1 + 2*x2 + 4*x3 + 2*x4 + 16*x5 + 3*x6
predict congestion when R >= 0
```

The fitted logistic coefficients were multiplied by four and rounded to
integers. `R` is a scaled decision score, not a calibrated probability. Since
each input is binary, hardware evaluates each coefficient as a conditional
add. The maximum/minimum score for these coefficients is +16/−15.

The equation is stored in `models/distilled_equation.json`; its generated RTL
parameters are in `rtl/congestion/distilled_congestion_model_pkg.sv`.

## Held-out result

On 15,552 untouched test samples, the equation agrees with the trained SNN on
98.997% of decisions and has 96.70% ground-truth accuracy. It achieves 91.35%
precision, 85.84% recall, F1 88.51%, 1.41% false-positive rate, 14.16%
false-negative rate, ROC-AUC 0.9743, and PR average precision 0.9205. Its test
confusion matrix is `[[13,063, 187], [326, 1,976]]`. It passes the configured
95% agreement, 90% accuracy, 70% recall, and 15% FPR gates.

| Offered load | Accuracy | Precision | Recall | FPR |
|---:|---:|---:|---:|---:|
| 30% | 99.29% | 96.59% | 96.02% | 0.36% |
| 60% | 96.64% | 90.85% | 86.43% | 1.54% |
| 85% | 94.17% | 88.93% | 80.37% | 2.45% |

Equation results by workload, candidate port, and congestion episode duration,
plus the validation metrics and SNN agreement, are in
`validation/snn_experiment/distillation_results.json`. At the per-port level,
North recall is 60.00% and West recall is 38.95%; those paths need separate
review even though overall and per-load accuracy gates pass.

## Limits

The equation loses about one SNN decision in one hundred on the held-out data.
It also uses the same correlated per-cycle examples and one held-out traffic
seed as the SNN report. It is a compact approximation for the tested feature
and traffic domain, not a universal routing law.
