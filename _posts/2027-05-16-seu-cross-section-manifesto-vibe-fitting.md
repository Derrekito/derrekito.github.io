---
title: "Rigorous SEU Cross-Section Analysis: A Methodological Manifesto Against Vibe Fitting"
date: 2027-05-16
categories: [Radiation Effects, Statistical Methods]
tags: [seu, weibull, curve-fitting, statistics, reproducibility, radiation-testing, methodology]
series: seu-cross-section-analysis
series_order: 0
---

The radiation effects community has a reproducibility problem. When two engineers analyze the same SEU test data, they often produce different Weibull fits. Not because the mathematics differs, but because the fitting process relies on manual parameter adjustment - tweaking values until the curve "looks right." This practice, colloquially known as "vibe fitting," produces results that cannot be independently verified, defended in peer review, or compared meaningfully across studies.

This post introduces a methodological framework that eliminates subjective judgment from cross-section analysis. The approach employs automated method selection based on data characteristics, explicit convergence criteria, and fallback hierarchies grounded in statistical literature. Science should be reproducible. Curve fitting should not require intuition.

## The Problem: Manual Parameter Adjustment

The 4-parameter Weibull model has served the radiation effects community since Petersen et al. established it as the standard in 1992. The model describes SEU cross-section as a function of LET:

```
σ(LET) = 0                                    for LET ≤ LET_th
σ(LET) = σ_sat × [1 - exp(-((LET - LET_th)/W)^S)]   for LET > LET_th
```

Four parameters require estimation: saturation cross-section (σ_sat), threshold LET (LET_th), shape (S), and width (W). The challenge lies not in the model itself but in how parameters are determined.

Common practice involves:

1. Loading data into a spreadsheet or plotting tool
2. Guessing initial parameter values
3. Adjusting parameters manually until the curve passes through most data points
4. Declaring the fit "good enough" based on visual inspection

This workflow produces several failure modes:

**Irreproducibility**: Two analysts examining identical data arrive at different parameter sets. Neither can explain why their values are "correct."

**No uncertainty quantification**: Manual fitting provides point estimates without confidence intervals. Downstream rate predictions inherit unknown error.

**Inconsistent methodology**: Each analysis applies different judgment criteria. Cross-study comparisons become meaningless.

**Publication bias**: Results that "look wrong" get adjusted until they "look right," potentially masking genuine physical effects.

## Data Sanity: What Must Be True Before Fitting

Before any curve fitting begins, the data must satisfy fundamental statistical assumptions. These checks apply universally, regardless of specific data formats or collection methods.

### Overdispersion Check

Poisson statistics assume variance equals mean. The dispersion ratio φ = s²/λ̄ quantifies deviation from this assumption.

| Dispersion Ratio | Interpretation | Action |
|------------------|----------------|--------|
| φ < 0.5 | Underdispersed | Unusual but acceptable |
| 0.5 ≤ φ ≤ 1.5 | Compatible with Poisson | Proceed normally |
| 1.5 < φ ≤ 2.0 | Borderline overdispersion | Note caveat, monitor quality |
| φ > 2.0 | Significant overdispersion | Consider negative binomial model |

Overdispersion often indicates experimental issues: inconsistent beam conditions, device-to-device variation, or systematic errors in fluence measurement.

### Zero-Inflation Check

Excess zeros beyond Poisson expectations suggest the standard model may be inadequate. The expected number of zeros under Poisson is n × exp(-λ̄). Excess zeros exceeding 20-30% indicate potential zero-inflation requiring specialized models.

### Sample Size Adequacy

The ratio of observations to parameters (n/p) determines estimation reliability. For the 4-parameter Weibull:

| n/p Ratio | Interpretation |
|-----------|----------------|
| n/p ≥ 10 | Adequate to excellent statistical power |
| 5 ≤ n/p < 10 | Marginal power; bootstrap essential |
| n/p < 5 | Severely underpowered; wide confidence intervals expected |

This threshold derives from regression diagnostics literature (Harrell 2015, Peduzzi 1996). With fewer than 10 observations per parameter, standard asymptotic theory begins to fail.

### Count Threshold

Mean count λ̄ below 0.1 indicates very rare events where Poisson approximations may struggle. Such data often require upper-limit reporting rather than curve fitting.

## The Decision Tree: Automated Method Selection

Rather than relying on analyst judgment, method selection follows explicit decision rules based on data characteristics. Five key decisions determine which algorithms execute:

```
DATA CHARACTERIZATION
        │
        ├── Total events (N_total)
        ├── Zero observations present?
        ├── Minimum count per LET point
        ├── Number of data points
        └── Degrees of freedom (n - 4)
        │
        ▼
METHOD SELECTION
        │
        ├── Decision 1: MLE Variant
        │       has_zeros? ──────► MLE-WithZeros
        │       N ≥ 50? ─────────► MLE-Standard (Hessian covariance)
        │       N < 50? ─────────► MLE-SmallSample (defer to bootstrap)
        │
        ├── Decision 2: Bootstrap Variant
        │       N ≥ 50 AND min_count ≥ 5? ──► Full (10,000 iterations)
        │       Otherwise ──────────────────► Conservative (20,000 iterations)
        │
        ├── Decision 3: Confidence Interval Method
        │       N ≥ 50 AND no zeros? ──► BCA (second-order accurate)
        │       Otherwise ─────────────► Percentile (robust)
        │
        ├── Decision 4: Zero Event Handler
        │       has_zeros? ──► Apply 3.7/Φ upper limit rule
        │
        └── Decision 5: Goodness-of-Fit Test
                DoF ≥ 3? ──► Run deviance test
                Otherwise ─► Skip (insufficient degrees of freedom)
```

Each decision point has a literature-grounded threshold. No judgment required.

## The N=50 Threshold: Why It Matters

The number 50 appears repeatedly in the decision tree. This threshold originates from Quinn's 2014 analysis of statistical considerations in radiation testing (IEEE TNS Vol. 61, No. 2).

For Poisson-distributed count data, normal approximation validity requires sufficient sample size. Below N=50 total events:

- Hessian-based covariance estimates become unreliable
- Symmetric confidence intervals misrepresent true uncertainty
- Standard errors may underestimate actual parameter uncertainty

Above N=50, asymptotic theory holds and computationally efficient methods apply. Below this threshold, non-parametric approaches (bootstrap resampling) provide more reliable uncertainty estimates despite increased computational cost.

The threshold is not arbitrary - it reflects where mathematical approximations begin to fail detectably.

## Zero Events: Upper Limits, Not Data Points

When a LET point produces zero observed events, the natural inclination is to plot σ = 0 and fit the curve through it. This approach is statistically incorrect.

Zero events constrain the cross-section from above, not at zero. The observation indicates σ < some_value, not σ = 0. Quinn and Tompkins formalized this in their 2024 paper "Measuring Zero" (IEEE TNS Vol. 71, No. 4):

```
σ_upper_limit = 3.7 / Φ    (95% confidence)
```

where Φ is the fluence at that LET point. This upper limit represents the largest cross-section consistent with observing zero events at that fluence.

Proper treatment:
1. Exclude zero-event points from curve fitting
2. Fit Weibull to non-zero observations only
3. Report upper limits separately as constraints
4. Verify fitted curve lies below upper limits

Including zeros in the fit biases parameters toward artificially low thresholds and steep onset shapes.

## Bootstrap: When Standard Errors Fail

For small samples (N < 50) or data with zeros, the parametric bootstrap provides uncertainty estimates without relying on asymptotic approximations.

The algorithm:

1. Compute expected counts from fitted parameters: λ_i = σ(LET_i) × Φ_i
2. Generate bootstrap sample: N*_i ~ Poisson(λ_i)
3. Refit Weibull to bootstrap sample
4. Repeat 10,000-20,000 times
5. Estimate covariance from bootstrap distribution

This approach makes no distributional assumptions about parameter estimators. Confidence intervals emerge directly from the empirical distribution of bootstrap estimates.

Two variants apply:

**Full Bootstrap** (N ≥ 50, adequate counts): 10,000 iterations with standard convergence tolerance

**Conservative Bootstrap** (N < 50 or sparse counts): 20,000 iterations with tighter convergence criteria, accommodating higher expected failure rates

## Confidence Intervals: BCA vs Percentile

Two methods construct confidence intervals from bootstrap distributions:

**Percentile Method**: Take the 2.5th and 97.5th percentiles directly. Simple, robust, makes no distributional assumptions. Appropriate when data contains zeros or N < 50.

**BCA (Bias-Corrected Accelerated)**: Adjusts percentiles for bias and skewness in the bootstrap distribution. Second-order accurate, providing better coverage properties. Requires N ≥ 50 and no zeros to compute stably.

The choice follows automatically from data characteristics. When in doubt, percentile intervals sacrifice some efficiency for guaranteed robustness.

## Goodness-of-Fit: Does the Model Work?

After fitting, the deviance test assesses whether the Weibull model adequately describes the data. The test statistic follows a chi-squared distribution with (n - 4) degrees of freedom under the null hypothesis that the model is adequate.

Applicability requires at least 3 degrees of freedom (7+ data points). With fewer points, formal testing lacks power and residual plots provide the only diagnostic.

Interpretation:
- p-value > 0.05: Fail to reject adequacy; model is acceptable
- 0.01 < p ≤ 0.05: Marginal fit; inspect residuals carefully
- p ≤ 0.01: Strong evidence of lack of fit; reconsider model or data quality

A failing deviance test does not invalidate the analysis - it flags results requiring additional scrutiny.

## Parameter Validation: Physical Constraints

Fitted parameters must satisfy physical constraints:

**Saturation Cross-Section (σ_sat)**:
- Must be positive
- Should exceed maximum measured cross-section
- Typical range: 10⁻¹⁰ to 10⁻³ cm²/device

**Threshold LET (LET_th)**:
- Must be non-negative
- Must be less than minimum tested LET
- Typical ranges vary by technology node

**Shape Parameter (S)**:
- Typical range: 0.5 to 5
- S < 1 indicates gradual onset (multiple mechanisms)
- S > 3 indicates sharp onset (possible overfitting)

**Width Parameter (W)**:
- Should be comparable to tested LET range
- W >> LET range indicates poor constraint

Parameters outside expected ranges trigger warnings, not automatic rejection. Physical understanding informs interpretation.

## The Complete Validation Pipeline

Combining all elements, the automated pipeline executes:

```
1. LOAD DATA
        │
        ▼
2. PRE-ANALYSIS VALIDATION
        ├── Overdispersion check
        ├── Zero-inflation check
        ├── Sample size check
        ├── Count threshold check
        └── Independence verification
        │
        ▼
3. METHOD SELECTION (decision tree)
        │
        ▼
4. EXECUTE FITTING
        ├── MLE variant (Standard/SmallSample/WithZeros)
        ├── Bootstrap variant (Full/Conservative)
        ├── CI method (BCA/Percentile)
        └── Zero handler (if applicable)
        │
        ▼
5. POST-FIT VALIDATION
        ├── Parameter physical checks
        ├── Residual analysis
        ├── Deviance test (if DoF sufficient)
        └── CI width assessment
        │
        ▼
6. GENERATE REPORT
        ├── Validation summary with status indicators
        ├── Fitted parameters with uncertainties
        ├── Publication-ready figures
        └── Reproducibility documentation
```

Every step produces auditable output. No manual intervention required.

## Reproducibility Requirements

For results to be independently verifiable:

1. **Random seed documentation**: Bootstrap resampling must use recorded seeds
2. **Software version pinning**: NumPy, SciPy, and analysis code versions recorded
3. **Complete parameter logging**: Initial guesses, bounds, convergence criteria
4. **Validation status recording**: All check results preserved
5. **Raw data archival**: Original counts, fluences, LETs available for re-analysis

Given identical inputs and recorded seeds, any analyst must reproduce identical outputs.

## Series Roadmap

This post introduces the framework. Subsequent posts detail each component:

1. **MLE for Weibull Cross-Sections** - Likelihood formulation, optimization, convergence criteria
2. **Bootstrap Methods for Small-Sample Uncertainty** - Resampling algorithms, iteration selection, diagnostics
3. **Confidence Interval Selection** - BCA vs percentile, when each applies
4. **Zero-Event Data Treatment** - Upper limits, exclusion criteria, proper reporting
5. **Goodness-of-Fit Testing** - Deviance statistic, residual analysis, interpretation
6. **Derived Parameter Validation** - Physical constraints, typical ranges, red flags
7. **Automated Validation Pipelines** - Implementation patterns, status indicators, reporting

Each post provides sufficient detail for implementation while maintaining focus on the specific topic.

## Conclusion

Vibe fitting persists because it appears to work. Curves pass through data points. Reports get published. The failure mode is invisible: results that cannot be reproduced, compared, or defended.

The alternative requires more initial effort - implementing decision trees, bootstrap algorithms, and validation checks. But the investment pays dividends in every subsequent analysis. Method selection becomes automatic. Uncertainty quantification becomes rigorous. Results become defensible.

The radiation effects community deserves better than "it looked right to me." Science demands reproducibility. This series provides the tools to achieve it.

## References

- Efron, B., & Tibshirani, R. J. (1993). *An Introduction to the Bootstrap*. Chapman and Hall/CRC.

- Harrell, F. E. (2015). *Regression Modeling Strategies* (2nd ed.). Springer.

- McCullagh, P., & Nelder, J. A. (1989). *Generalized Linear Models* (2nd ed.). Chapman and Hall/CRC.

- Peduzzi, P., Concato, J., Kemper, E., Holford, T. R., & Feinstein, A. R. (1996). A simulation study of the number of events per variable in logistic regression analysis. *Journal of Clinical Epidemiology*, 49(12), 1373-1379.

- Petersen, E. L., Pickel, J. C., Adams, J. H., & Smith, E. C. (1992). Rate prediction for single event effects - A critique. *IEEE Transactions on Nuclear Science*, 39(6), 1577-1599.

- Quinn, H. (2014). Challenges in testing complex systems. *IEEE Transactions on Nuclear Science*, 61(2), 766-786.

- Quinn, H., & Tompkins, P. (2024). Measuring zero: Neutron testing of modern digital electronics. *IEEE Transactions on Nuclear Science*, 71(4), 670-679.

---

*This post is Part 0 of the SEU Cross-Section Analysis series. Next: [MLE for Weibull Cross-Sections](/seu-cross-section-mle-weibull)*
