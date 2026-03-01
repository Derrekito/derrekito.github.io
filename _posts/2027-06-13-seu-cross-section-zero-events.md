---
title: "When N=0: Proper Treatment of Zero-Event Observations"
date: 2027-06-13
categories: [Radiation Effects, Statistical Methods]
tags: [seu, zero-events, upper-limits, poisson, statistics, radiation-testing]
series: seu-cross-section-analysis
series_order: 4
---

Radiation effects testing frequently produces zero-event observations. At low LET values, exposing a device to substantial fluence without observing a single upset is common and informative. These zeros contain real information about device susceptibility, yet improper treatment remains one of the most pervasive errors in cross-section analysis. This post establishes correct statistical treatment of zero-event data, derives the standard upper limit formulas, and demonstrates practical implementation.

## The Problem with Zeros

Consider a typical heavy-ion SEU test campaign. The test plan targets LETs from 2 to 60 MeV-cm2/mg, with fluences of 10^7 ions/cm2 at each LET point. At LET = 2, no upsets occur. At LET = 5, still nothing. At LET = 10, two upsets appear. Higher LETs produce increasing counts.

The temptation is to include the LET = 2 and LET = 5 points in curve fitting with cross-section sigma = 0. This approach seems intuitive: zero events observed, zero cross-section measured.

This reasoning is statistically incorrect.

A zero observation does not constrain the cross-section at zero. It constrains the cross-section from above. The observation indicates sigma is small enough that the expected number of events lambda = sigma times Phi was insufficient to produce even one count with high probability. The correct interpretation: sigma < upper_limit, not sigma = 0.

Including zeros as sigma = 0 data points produces systematic bias:

**Artificially low threshold estimates**: The fitting algorithm attempts to pass through sigma = 0 at low LETs, pulling the threshold estimate downward even when the true threshold lies above the tested LET range.

**Overconfident uncertainty bounds**: Zero observations treated as exact measurements reduce apparent uncertainty, masking the true constraint that zeros provide.

**Steep shape parameters**: To reconcile near-zero values at low LET with non-zero values at higher LET, fits compensate with unnaturally steep turn-on shapes.

The fitted curve may visually pass through data points while systematically misrepresenting the underlying physics.

## Upper Limits from Poisson Statistics

When zero events are observed at fluence Phi, the goal is determining the largest cross-section consistent with this observation at a specified confidence level.

The Poisson probability of observing exactly k events when lambda events are expected is:

```
P(k | lambda) = (lambda^k * exp(-lambda)) / k!
```

For k = 0:

```
P(0 | lambda) = exp(-lambda)
```

This probability decreases as lambda increases. Setting a confidence level CL (typically 0.95), the upper limit lambda_upper satisfies:

```
P(0 | lambda_upper) = 1 - CL
exp(-lambda_upper) = 1 - CL
lambda_upper = -ln(1 - CL)
```

For common confidence levels:

| Confidence Level | -ln(1 - CL) | Interpretation |
|------------------|-------------|----------------|
| 90% | 2.303 | 10% chance of zero if lambda = 2.30 |
| 95% | 2.996 | 5% chance of zero if lambda = 3.00 |
| 99% | 4.605 | 1% chance of zero if lambda = 4.61 |

Since lambda = sigma times Phi, the cross-section upper limit becomes:

```
sigma_upper = lambda_upper / Phi = -ln(1 - CL) / Phi
```

## The 3.7/Phi Rule

The radiation effects community commonly cites the "3.7/Phi rule" for 95% confidence upper limits. This formulation deserves clarification.

The value 3.7 derives from chi-squared quantiles, not directly from -ln(0.05). The connection arises through the relationship between Poisson distributions and chi-squared distributions.

For a Poisson-distributed count N, the upper limit at confidence level CL relates to chi-squared quantiles:

```
lambda_upper = (1/2) * chi2_inverse(CL, 2(N+1))
```

For N = 0 at 95% confidence:

```
lambda_upper = (1/2) * chi2_inverse(0.95, 2)
             = (1/2) * 5.991
             = 2.996
```

However, some formulations use a slightly different convention, leading to the value 3.0 or rounding effects that produce 3.7. Quinn and Tompkins (2024) provide authoritative treatment in "Measuring Zero," establishing the conventions used in IEEE radiation effects publications.

The practical difference between 3.0 and 3.7 amounts to roughly 23% in the upper limit. For mission-critical applications, the precise formulation should be specified. The standard 95% confidence upper limit is:

```
sigma_upper_95 = 2.996 / Phi  (exact Poisson)
sigma_upper_95 = 3.0 / Phi    (commonly rounded)
```

The 3.7/Phi formula sometimes cited corresponds to a one-sided 97.5% confidence bound or includes additional conservatism factors.

## Alternative Confidence Levels

Different applications require different confidence levels:

**90% Confidence (2.30/Phi)**

Appropriate for preliminary screening or when slightly optimistic bounds are acceptable. Provides narrower limits while maintaining reasonable conservatism.

```
sigma_upper_90 = 2.303 / Phi
```

**95% Confidence (3.0/Phi)**

The community standard for most applications. Balances conservatism against over-constraint.

```
sigma_upper_95 = 2.996 / Phi
```

**99% Confidence (4.61/Phi)**

Required for safety-critical systems or when regulatory standards demand higher assurance.

```
sigma_upper_99 = 4.605 / Phi
```

## Implementation

The following Python code implements upper limit calculations:

```python
import numpy as np
from scipy.stats import chi2

def poisson_upper_limit(n_observed, confidence=0.95):
    """Calculate Poisson upper limit on expected count."""
    return 0.5 * chi2.ppf(confidence, 2 * (n_observed + 1))

def cross_section_upper_limit(fluence, n_observed=0, confidence=0.95):
    """Calculate cross-section upper limit for observed count."""
    lambda_upper = poisson_upper_limit(n_observed, confidence)
    return lambda_upper / fluence

# Example: fluence = 1e7 particles/cm^2, zero events
ul_95 = cross_section_upper_limit(1e7, 0, 0.95)
# Result: 3.00e-07 cm^2
```

## Proper Treatment Workflow

The correct procedure for handling mixed data (zeros and non-zeros) follows this sequence:

**Step 1: Separate Zero and Non-Zero Observations**

```python
def separate_zero_nonzero(let_values, counts, fluences):
    """Separate zero-event and non-zero-event observations."""
    zero_mask = counts == 0
    return {
        'nonzero': {'let': let_values[~zero_mask],
                    'counts': counts[~zero_mask],
                    'fluence': fluences[~zero_mask]},
        'zero': {'let': let_values[zero_mask],
                 'fluence': fluences[zero_mask]}
    }
```

**Step 2: Fit Weibull to Non-Zero Data Only**

Zero-event points provide no positive information about cross-section shape, only constraints.

```python
data = separate_zero_nonzero(let_values, counts, fluences)
params_fit, result = fit_weibull_mle(
    data['nonzero']['let'], data['nonzero']['counts'], data['nonzero']['fluence'])
```

**Step 3: Compute Upper Limits for Zero-Event Points**

```python
upper_limits = np.array([cross_section_upper_limit(phi, 0, 0.95)
                         for phi in data['zero']['fluence']])
```

**Step 4: Verify Fit Respects Upper Limits**

The fitted curve must lie below all upper limits. This verification serves as a consistency check.

```python
def verify_fit_respects_limits(params, zero_lets, upper_limits):
    """Verify fitted Weibull lies below all upper limits."""
    fitted_sigma = weibull_cross_section(zero_lets, *params)
    violations = fitted_sigma > upper_limits
    return {'all_valid': not np.any(violations),
            'violation_lets': zero_lets[violations] if np.any(violations) else []}
```

When violations occur, the fitted curve predicts cross-sections inconsistent with zero observations. This situation indicates insufficient fluence at zero-event points, model misspecification, or data quality issues.

## Common Mistakes

Several errors appear repeatedly in published analyses:

**Mistake 1: Fitting Zeros as sigma = 0**

Including zero-event points in least squares or MLE fits with sigma = 0 biases all parameters. The fitting algorithm minimizes residuals to zero values that carry infinite weight relative to their actual information content.

**Mistake 2: Using Arbitrary Small Values**

Substituting sigma = 10^-15 or similar small values for zeros attempts to avoid numerical issues while still including these points in fitting. This approach provides no statistical justification and introduces arbitrary bias. The specific small value chosen affects results in unpredictable ways.

**Mistake 3: Ignoring Zeros Without Reporting Limits**

Excluding zero-event points from analysis without documenting upper limits discards real information. These limits constrain the fitted curve and should appear in technical reports and publications.

**Mistake 4: Misapplying Confidence Levels**

Mixing 90%, 95%, and 99% confidence levels within the same analysis or applying formulas without understanding their derivation leads to inconsistent results. The confidence level should be stated explicitly and applied consistently.

**Mistake 5: Incorrect Fluence Units**

The upper limit formula requires consistent units. Cross-section in cm^2 requires fluence in particles/cm^2. Mixing cm^2 cross-sections with particles/device fluences produces incorrect limits by factors corresponding to device area.

## Visualization

Proper visualization distinguishes between measured cross-sections and upper limits:

```python
import matplotlib.pyplot as plt

def plot_fit_with_limits(let_data, sigma_data, let_zero, upper_limits, params_fit):
    """Plot Weibull fit with upper limit arrows for zero-event points."""
    fig, ax = plt.subplots(figsize=(10, 7))

    # Fitted curve
    let_curve = np.linspace(0, max(np.max(let_data), np.max(let_zero)) * 1.2, 200)
    ax.plot(let_curve, weibull_cross_section(let_curve, *params_fit) * 1e6,
            'b-', linewidth=2, label='Weibull Fit')

    # Non-zero measurements
    ax.plot(let_data, sigma_data * 1e6, 'ko', markersize=10, label='Measured')

    # Upper limits as downward arrows
    for let, ul in zip(let_zero, upper_limits):
        ax.annotate('', xy=(let, 0), xytext=(let, ul * 1e6),
                    arrowprops=dict(arrowstyle='->', color='red', lw=2))
        ax.plot(let, ul * 1e6, 'rv', markersize=10)

    ax.set_xlabel('LET (MeV-cm$^2$/mg)')
    ax.set_ylabel('Cross-Section ($\\times 10^{-6}$ cm$^2$/device)')
    ax.legend()
    return fig, ax
```

The visualization distinguishes measured values (circles) from upper limits (downward arrows with inverted triangles). The fitted curve should lie below all upper limit markers.

## Bayesian Interpretation

The frequentist upper limit admits a Bayesian interpretation that provides additional insight.

With a uniform (flat) prior on cross-section from 0 to some maximum sigma_max, Bayes' theorem updates the prior based on the zero-event observation:

```
P(sigma | N=0, Phi) proportional to P(N=0 | sigma, Phi) * P(sigma)
                                  = exp(-sigma * Phi) * constant
```

The posterior is exponential, decreasing with sigma. The 95% credible interval upper bound coincides with the frequentist 95% confidence upper limit when using a uniform prior.

This correspondence provides intuition: the upper limit represents the cross-section value above which 95% of the posterior probability mass lies (in the Bayesian view) or the value that would produce zero events with only 5% probability (in the frequentist view).

Informative priors based on similar device families or technology nodes can sharpen these bounds. If prior testing of similar devices establishes typical cross-section ranges, incorporating this information produces tighter posterior bounds while remaining consistent with observed data.

The Bayesian framework also naturally handles combining zero-event observations with non-zero observations through likelihood multiplication, though implementation requires care with model specification.

## When All Points Are Zeros

A special case arises when every tested LET produces zero events. This situation indicates one of several possibilities:

**Insufficient Fluence**

The fluence at each LET was too low to produce observable events given the device's actual cross-section. Upper limits at each LET constrain the cross-section but provide no information about shape.

Resolution: Report upper limits at each LET. No Weibull fit is possible or meaningful. Additional testing at higher fluences is required.

**Device Immunity**

The device may be genuinely immune to SEU at all tested LETs. This conclusion requires careful consideration of whether the tested LET range spans the expected threshold.

Resolution: If the maximum tested LET exceeds expected thresholds by a significant margin (e.g., LET_max > 40 MeV-cm^2/mg for many technologies), upper limits at the highest LET provide meaningful bounds on saturation cross-section.

**Threshold Above Test Range**

The device threshold may exceed the maximum tested LET. All zero observations are then expected and informative about threshold location.

Resolution: Report that threshold exceeds maximum tested LET. The tightest constraint comes from the highest-fluence zero observation.

In all cases, report upper limits rather than claiming sigma = 0 across the board.

## Validation Example

A complete example applying proper zero-event treatment:

```python
# Test data: 3 zeros at low LET, 5 non-zero at higher LET
let_values = np.array([2, 5, 10, 15, 20, 30, 40, 60])  # MeV-cm^2/mg
counts = np.array([0, 0, 0, 3, 8, 15, 22, 25])         # observed events
fluences = np.array([1e7, 1e7, 1e7, 1e7, 1e7, 1e7, 1e7, 1e7])

# Separate, fit to non-zeros, compute limits, verify
data = separate_zero_nonzero(let_values, counts, fluences)
params_fit, _ = fit_weibull_mle(data['nonzero']['let'],
                                 data['nonzero']['counts'],
                                 data['nonzero']['fluence'])
upper_limits = np.array([cross_section_upper_limit(phi) for phi in data['zero']['fluence']])
verification = verify_fit_respects_limits(params_fit, data['zero']['let'], upper_limits)
print(f"All upper limits respected: {verification['all_valid']}")
```

## Integration with Series Methods

The zero-event handling described here integrates with methods from earlier posts in this series.

The validation pipeline from Post 0 includes zero-event handling as a decision point:

```
DATA CHARACTERIZATION
        |
        +-- Zero observations present?
        |       |
        |       +-- Yes --> Apply 3.7/Phi upper limit rule
        |       |           Exclude from curve fitting
        |       |           Verify fit respects limits
        |       |
        |       +-- No --> Proceed with standard MLE
```

Bootstrap confidence intervals (Post 1) apply to the non-zero data subset. Zero-event points do not participate in resampling since they provide only one-sided constraints.

The deviance goodness-of-fit test (Post 2) uses only non-zero observations for computing the test statistic. Degrees of freedom are n_nonzero minus number of parameters.

## Summary

Zero-event observations in radiation effects testing provide real information that must be treated correctly:

1. **Zeros constrain from above**: The observation N = 0 indicates sigma < upper_limit, not sigma = 0

2. **Upper limit formula**: sigma_upper = -ln(1 - CL) / Phi, commonly approximated as 3.0/Phi for 95% confidence

3. **Proper workflow**: Separate zeros from non-zeros, fit to non-zeros only, compute upper limits for zeros, verify fit respects all limits

4. **Common errors**: Fitting sigma = 0, using arbitrary small values, ignoring zeros without reporting limits

5. **All-zeros case**: Report upper limits at each LET; no Weibull fit is meaningful

Correct treatment of zero events prevents systematic bias in threshold and shape parameter estimates while maintaining full use of available information.

## References

- Feldman, G. J., & Cousins, R. D. (1998). Unified approach to the classical statistical analysis of small signals. *Physical Review D*, 57(7), 3873-3889.

- Gehrels, N. (1986). Confidence limits for small numbers of events in astrophysical data. *The Astrophysical Journal*, 303, 336-346.

- Quinn, H., & Tompkins, P. (2024). Measuring zero: Neutron testing of modern digital electronics. *IEEE Transactions on Nuclear Science*, 71(4), 670-679.

---

## Series Navigation

This post is Part 4 of the SEU Cross-Section Analysis series.

| Post | Title | Status |
|------|-------|--------|
| 0 | [Rigorous SEU Cross-Section Analysis: A Methodological Manifesto](/seu-cross-section-manifesto-vibe-fitting) | Published |
| 1 | [Naive Weibull Curve Fitting](/naive-weibull-curve-fit-seu-cross-section) | Published |
| 2 | Model Validation and Goodness-of-Fit | Planned |
| 3 | Bootstrap Methods for Small-Sample Uncertainty | Planned |
| 4 | **When N=0: Proper Treatment of Zero-Event Observations** (this post) | Current |
| 5 | Goodness-of-Fit Testing | Planned |
| 6 | Derived Parameter Validation | Planned |
| 7 | Automated Validation Pipelines | Planned |

*Previous: [Naive Weibull Curve Fitting](/naive-weibull-curve-fit-seu-cross-section)*
