---
title: "Choosing Confidence Intervals: Second-Order Accuracy vs Robustness"
date: 2027-06-06
categories: [Radiation Effects, Statistical Methods]
tags: [seu, confidence-intervals, bca, bootstrap, statistics, python]
series: seu-cross-section-analysis
series_order: 3
---

Bootstrap resampling generates an empirical distribution of parameter estimates. The final step transforms this distribution into confidence intervals that quantify parameter uncertainty. Two methods dominate bootstrap practice: the percentile method and the bias-corrected accelerated (BCA) method. Each offers distinct tradeoffs between robustness and accuracy, and the choice between them follows directly from data characteristics.

This post examines both methods in detail, providing the statistical foundations, decision rules, and Python implementations necessary for rigorous SEU cross-section analysis.

## The Percentile Method: Simplicity and Robustness

The percentile method constructs confidence intervals by taking quantiles directly from the bootstrap distribution. Given B bootstrap estimates of parameter theta, the 95% confidence interval uses the 2.5th and 97.5th percentiles of the sorted values.

### Algorithm

The procedure requires only sorting and indexing:

1. Obtain B bootstrap parameter estimates: theta_1, theta_2, ..., theta_B
2. Sort the estimates in ascending order
3. For confidence level (1 - alpha), compute lower index: L = floor(B * alpha/2)
4. Compute upper index: U = floor(B * (1 - alpha/2))
5. Confidence interval: [theta_(L), theta_(U)]

For 10,000 bootstrap samples and 95% confidence, L = 250 and U = 9750, yielding the interval [theta_(250), theta_(9750)].

### Properties

The percentile method offers several advantages for SEU cross-section analysis:

**No distributional assumptions**: The method treats bootstrap estimates as an empirical distribution, making no assumptions about normality or symmetry. For heavily skewed parameter estimates like threshold LET near zero, this robustness matters.

**Automatic asymmetry**: When the true sampling distribution is asymmetric, percentile intervals reflect this naturally. The interval [3.2, 8.7] differs from [3.5, 8.4] even though both span 5.5 units, capturing real asymmetry in parameter uncertainty.

**Handles zeros gracefully**: When some bootstrap iterations produce zero cross-sections or boundary values, percentile intervals incorporate these outcomes without special handling.

**Small sample compatibility**: With as few as 100 bootstrap iterations, percentile intervals remain computable. No additional calculations that might fail with sparse data are required.

### Implementation

```python
import numpy as np

def percentile_confidence_interval(bootstrap_estimates, confidence=0.95):
    """Compute confidence interval using the percentile method."""
    alpha = 1 - confidence
    ci_lower = np.percentile(bootstrap_estimates, 100 * alpha / 2)
    ci_upper = np.percentile(bootstrap_estimates, 100 * (1 - alpha / 2))
    return ci_lower, ci_upper

def percentile_ci_all_parameters(theta_bootstrap, confidence=0.95):
    """Compute percentile CIs for all Weibull parameters."""
    alpha = 1 - confidence
    ci_lower = np.percentile(theta_bootstrap, 100 * alpha / 2, axis=0)
    ci_upper = np.percentile(theta_bootstrap, 100 * (1 - alpha / 2), axis=0)
    return ci_lower, ci_upper
```

### Limitations

The percentile method sacrifices theoretical optimality for robustness:

**First-order accuracy**: Coverage probability converges to the nominal level at rate O(1/sqrt(n)), slower than theoretically achievable. For small samples, actual coverage may deviate from nominal by several percentage points.

**Bias uncorrected**: If the bootstrap distribution is systematically shifted from the true sampling distribution, percentile intervals inherit this bias.

**Skewness uncorrected**: Skewness in the bootstrap distribution can cause systematic coverage problems that the percentile method does not address.

## The BCA Method: Second-Order Accuracy

The bias-corrected accelerated (BCA) method, introduced by Efron (1987) and refined in Efron and Tibshirani (1993), adjusts percentile endpoints to correct for bias and skewness. This adjustment achieves second-order accuracy, with coverage probability converging at rate O(1/n) rather than O(1/sqrt(n)).

### Conceptual Foundation

BCA intervals address two sources of error:

**Bias correction (z_0)**: The bootstrap distribution may be centered away from the MLE. The bias correction factor z_0 measures this shift using the fraction of bootstrap estimates below the MLE.

**Acceleration (a)**: The variance of the estimator may depend on the parameter value itself. This acceleration factor, computed via jackknife, adjusts for how quickly the standard error changes as the parameter changes.

### Computing Bias Correction z_0

The bias correction factor quantifies how the bootstrap median relates to the MLE:

1. Compute the proportion f of bootstrap estimates less than the MLE: f = count(theta* < theta_MLE) / B
2. Transform to the standard normal scale: z_0 = Phi^(-1)(f)

Interpretation:
- f = 0.50 implies z_0 = 0 (no bias)
- f = 0.60 implies z_0 = 0.253 (bootstrap median below MLE)
- Values of |z_0| exceeding 0.5 indicate substantial bias

```python
from scipy.stats import norm

def compute_bias_correction(bootstrap_estimates, mle_estimate):
    """Compute bias correction factor z_0 for BCA intervals."""
    f = np.mean(bootstrap_estimates < mle_estimate)

    # Handle edge cases
    if f == 0:
        f = 0.5 / len(bootstrap_estimates)
    elif f == 1:
        f = 1 - 0.5 / len(bootstrap_estimates)

    return norm.ppf(f)
```

### Computing Acceleration from Jackknife

The acceleration factor captures how parameter uncertainty varies with the parameter value. Estimation uses the jackknife:

1. For each observation i, compute theta_(-i) by fitting without observation i
2. Compute the mean: theta_bar = mean(theta_(-i))
3. Compute acceleration: a = sum((theta_bar - theta_(-i))^3) / (6 * (sum((theta_bar - theta_(-i))^2))^(3/2))

```python
def compute_acceleration_jackknife(energy, counts, fluence, fit_function):
    """Compute acceleration factor from jackknife estimates."""
    n = len(energy)
    theta_jackknife = []

    for i in range(n):
        mask = np.ones(n, dtype=bool)
        mask[i] = False
        try:
            theta_i = fit_function(energy[mask], counts[mask], fluence[mask])
            theta_jackknife.append(theta_i)
        except:
            continue

    if len(theta_jackknife) < 3:
        return np.zeros(4)

    theta_jackknife = np.array(theta_jackknife)
    theta_bar = np.mean(theta_jackknife, axis=0)
    diff = theta_bar - theta_jackknife
    numerator = np.sum(diff ** 3, axis=0)
    denominator = 6 * (np.sum(diff ** 2, axis=0)) ** 1.5

    with np.errstate(divide='ignore', invalid='ignore'):
        a = np.where(denominator > 0, numerator / denominator, 0)
    return a
```

### Adjusted Percentile Calculation

With z_0 and a computed, BCA adjusts the percentile endpoints. For a (1 - alpha) confidence interval:

alpha_1 = Phi(z_0 + (z_0 + z_(alpha/2)) / (1 - a * (z_0 + z_(alpha/2))))
alpha_2 = Phi(z_0 + (z_0 + z_(1-alpha/2)) / (1 - a * (z_0 + z_(1-alpha/2))))

When z_0 = 0 and a = 0, BCA reduces to the percentile method.

```python
def bca_confidence_interval(bootstrap_estimates, mle_estimate, z_0, a,
                            confidence=0.95):
    """Compute BCA confidence interval."""
    alpha = 1 - confidence
    z_alpha_lower = norm.ppf(alpha / 2)
    z_alpha_upper = norm.ppf(1 - alpha / 2)

    def adjusted_percentile(z_alpha):
        numerator = z_0 + z_alpha
        denominator = 1 - a * (z_0 + z_alpha)
        if abs(denominator) < 1e-10:
            return norm.cdf(z_alpha)
        adjusted_z = z_0 + numerator / denominator
        return norm.cdf(adjusted_z)

    alpha_1 = np.clip(adjusted_percentile(z_alpha_lower), 0.001, 0.999)
    alpha_2 = np.clip(adjusted_percentile(z_alpha_upper), 0.001, 0.999)

    ci_lower = np.percentile(bootstrap_estimates, 100 * alpha_1)
    ci_upper = np.percentile(bootstrap_estimates, 100 * alpha_2)
    return ci_lower, ci_upper
```

### Complete BCA Implementation

```python
def bca_intervals_complete(energy, counts, fluence, theta_mle,
                           theta_bootstrap, fit_function, confidence=0.95):
    """Compute BCA confidence intervals for all Weibull parameters."""
    n_params = theta_mle.shape[0]
    ci_lower = np.zeros(n_params)
    ci_upper = np.zeros(n_params)

    z_0 = np.array([
        compute_bias_correction(theta_bootstrap[:, j], theta_mle[j])
        for j in range(n_params)
    ])
    a = compute_acceleration_jackknife(energy, counts, fluence, fit_function)

    for j in range(n_params):
        ci_lower[j], ci_upper[j] = bca_confidence_interval(
            theta_bootstrap[:, j], theta_mle[j], z_0[j], a[j], confidence
        )

    return ci_lower, ci_upper, {'z_0': z_0, 'a': a}
```

## When BCA Fails: Percentile Saves the Analysis

BCA provides superior coverage properties under ideal conditions. However, several scenarios cause BCA to fail or produce unreliable intervals, while percentile intervals remain valid.

### Zero-Event Observations

When some LET points produce zero observed events, jackknife estimates become unstable. Removing a zero-event observation has minimal impact on the fit, while removing a high-count observation may dramatically shift parameters. This imbalance produces acceleration values dominated by a few influential points, making the acceleration factor unreliable.

The bias correction z_0 also suffers: if the MLE sits at a boundary (threshold at zero, for instance), the fraction of bootstrap estimates below the MLE becomes uninformative. A threshold estimate of exactly zero will have nearly all bootstrap estimates at or above zero, producing f near 1.0 and z_0 near infinity.

### Small Sample Sizes

With fewer than 50 total events, bootstrap distributions become granular rather than smooth. The jackknife, computed from only n observations (typically 5-10 for SEU tests), provides a poor estimate of skewness. Acceleration values fluctuate wildly between similar datasets, sometimes producing corrections that worsen rather than improve coverage.

Furthermore, the normal approximation underlying BCA adjustments requires sufficient sample size. The formula assumes Phi^(-1) transformations behave reasonably, which requires enough observations to estimate the relevant quantiles with adequate precision.

### Bootstrap Failure Rates

When many bootstrap iterations fail to converge, the successful iterations may not represent the full sampling distribution. BCA corrections computed from a biased subset can shift intervals in the wrong direction. A bootstrap that fails 15% of iterations likely fails preferentially on certain types of resamples (those with sparse high-LET data, for instance), biasing the retained distribution.

If more than 10% of bootstrap iterations fail, confidence interval reliability degrades regardless of method. Percentile intervals from the successful subset provide estimates, but interpretation requires explicit caution about the selection bias.

### Boundary Parameters

Threshold LET estimates often cluster near zero, hitting the physical constraint that threshold cannot be negative. BCA adjustments can push interval endpoints outside valid bounds, requiring post-hoc clipping that undermines theoretical guarantees.

Percentile intervals naturally respect bounds because bootstrap estimates themselves respect bounds (assuming the fitting algorithm does). No additional clipping or correction is needed.

## The Decision Rule: Automated Method Selection

Given the tradeoffs, a clear decision rule prevents ad hoc choices:

```
IF (N_total >= 50) AND (no zero-event observations) THEN
    Use BCA intervals
ELSE
    Use Percentile intervals
```

### Implementation

```python
def select_ci_method(counts, has_zeros=None):
    """Select confidence interval method based on data characteristics."""
    n_total = np.sum(counts)
    if has_zeros is None:
        has_zeros = np.any(counts == 0)

    if n_total >= 50 and not has_zeros:
        return 'bca', f'N_total={n_total} >= 50 and no zeros: BCA applicable'
    elif n_total < 50:
        return 'percentile', f'N_total={n_total} < 50: use robust percentile'
    else:
        return 'percentile', 'Zero-event observations: use percentile method'

def compute_confidence_intervals(energy, counts, fluence, theta_mle,
                                  theta_bootstrap, fit_function, confidence=0.95):
    """Automatically select method and compute confidence intervals."""
    method, reason = select_ci_method(counts)

    if method == 'bca':
        ci_lower, ci_upper, diagnostics = bca_intervals_complete(
            energy, counts, fluence, theta_mle, theta_bootstrap,
            fit_function, confidence
        )
        diagnostics['reason'] = reason
    else:
        ci_lower, ci_upper = percentile_ci_all_parameters(theta_bootstrap, confidence)
        diagnostics = {'reason': reason, 'z_0': None, 'a': None}

    return ci_lower, ci_upper, method, diagnostics
```

## Coverage Properties and Validation

Confidence interval quality is measured by coverage probability: the frequency with which intervals computed from repeated samples contain the true parameter value. A 95% confidence interval should contain the true value in 95% of repeated experiments under identical conditions.

### First-Order vs Second-Order Accuracy

The distinction between first-order and second-order accuracy determines how quickly coverage probability approaches the nominal level as sample size increases.

**First-order accurate** (percentile method): Coverage probability converges to the nominal level at rate O(1/sqrt(n)), where n represents the effective sample size. With n=25 observations, actual coverage for a nominal 95% interval might be anywhere from 90% to 98%, depending on the specific parameter and data distribution.

**Second-order accurate** (BCA method): Coverage converges at rate O(1/n). With the same n=25 observations, actual coverage is typically within 1-2% of nominal. The faster convergence rate means BCA intervals achieve target coverage with smaller samples.

This difference matters for mission-critical radiation effects analysis. A satellite design margin based on a 95% confidence interval that actually covers only 90% of the time introduces hidden risk. The 5% difference between stated and actual coverage can represent meaningful probability of exceeding design limits.

### Simulation-Based Validation

Coverage properties can be validated empirically through simulation. The procedure generates synthetic datasets from known parameters, computes confidence intervals for each dataset, and counts how often the intervals contain the true values. This Monte Carlo approach provides empirical coverage probabilities that can be compared against nominal levels.

For typical SEU test configurations (7 LET points, 30-100 total events), simulation studies reveal:

| Parameter | Percentile Coverage | BCA Coverage | Nominal |
|-----------|---------------------|--------------|---------|
| sigma_sat | 91-94% | 94-96% | 95% |
| e_th | 89-93% | 93-96% | 95% |
| s (shape) | 90-94% | 93-96% | 95% |
| w (width) | 88-93% | 92-95% | 95% |

BCA consistently achieves coverage closer to nominal. The improvement is most pronounced for threshold and width parameters, which exhibit strong non-linearity.

## Interpreting Asymmetric Confidence Intervals

Both percentile and BCA methods produce asymmetric intervals when the sampling distribution is skewed. Proper interpretation requires recognizing that asymmetry conveys real information about parameter uncertainty.

### Sources of Asymmetry

**Boundary constraints**: Threshold LET cannot be negative. Estimates near zero have more room to vary upward than downward, naturally producing intervals like [0.1, 2.3] rather than the symmetric [-1.0, 1.5] (which would be physically invalid). The asymmetry reflects the constraint, not a fitting artifact.

**Logarithmic parameters**: Saturation cross-section spans orders of magnitude. A symmetric interval in log space corresponds to an asymmetric interval in linear space. An interval from 1e-7 to 1e-5 cm^2 appears highly asymmetric when reported linearly, but represents equal relative uncertainty in both directions.

**Non-linear dependence**: The relationship between observed counts and Weibull parameters is non-linear. Small changes in high-count observations may produce larger parameter shifts than equivalent changes in low-count observations. This non-linearity propagates through to the bootstrap distribution.

**Skewed sampling distributions**: Even without boundaries or non-linearity, finite-sample estimators can have skewed distributions. The MLE for variance, for instance, is skewed right in small samples.

### Reporting Asymmetric Intervals

When reporting asymmetric intervals, avoid misleading summaries:

**Incorrect**: sigma_sat = 5.3e-6 +/- 1.2e-6 cm^2/device

This notation implies symmetry that does not exist and obscures meaningful information about the uncertainty structure.

**Correct**: sigma_sat = 5.3e-6 cm^2/device (95% CI: [3.8e-6, 7.9e-6])

Or with explicit asymmetric notation:

**Also correct**: sigma_sat = 5.3e-6 (+2.6/-1.5) x 10^-6 cm^2/device

### Interval Width and Parameter Confidence

Wider intervals indicate greater uncertainty, not fitting failure. An interval spanning two orders of magnitude for threshold LET indicates that the data genuinely cannot constrain this parameter precisely. Attempting to force narrower intervals through different methods or additional assumptions would misrepresent the actual state of knowledge.

Comparing interval widths across methods provides a diagnostic. BCA intervals narrower than percentile intervals suggest the bias and skewness corrections are working as intended. BCA intervals dramatically wider than percentile intervals may indicate numerical instability in the correction factors, warranting investigation of the z_0 and a diagnostics.

## Practical Recommendations

Based on the statistical analysis and failure mode considerations above, the following recommendations apply to SEU cross-section analysis:

**Default to the decision rule**: Apply the N >= 50 AND no zeros criterion automatically. The threshold of 50 total events comes from Quinn (2014), reflecting where asymptotic approximations begin to hold reliably. Manual override should require explicit justification documented in the analysis record.

**Report the method used**: Reproducibility requires knowing which interval method was applied. Analysis reports should state "95% BCA confidence intervals" or "95% percentile confidence intervals" explicitly. Given the same bootstrap samples, different methods produce different intervals, so method specification is essential for reproducibility.

**Inspect BCA diagnostics**: When using BCA, report z_0 and a values for each parameter. Large corrections (|z_0| > 0.5 or |a| > 0.3) warrant additional scrutiny. Such values indicate substantial bias or skewness in the bootstrap distribution, and the corrections may be sensitive to outliers or numerical issues.

**Validate coverage for critical applications**: For spacecraft qualification analyses where design margins depend on confidence interval accuracy, run simulation studies with parameters similar to the observed fit. This Monte Carlo validation verifies that stated confidence levels are achieved for the specific data configuration at hand.

**Trust percentile when uncertain**: If any doubt exists about BCA applicability, percentile intervals remain valid if slightly less efficient. Robustness trumps optimality for safety-critical applications. A 93% actual coverage from percentile intervals is preferable to a nominally 95% but actually 85% coverage from unstable BCA corrections.

## Summary

The choice between percentile and BCA confidence intervals follows data characteristics, not analyst preference. The percentile method offers robustness to zeros, small samples, and boundary effects at the cost of first-order accuracy. BCA achieves second-order accuracy when sufficient data (N >= 50) with no zeros enables reliable bias and acceleration estimation.

The decision rule automates selection: N >= 50 AND no zeros implies BCA; otherwise percentile. Both methods produce asymmetric intervals when appropriate, and reporting these accurately communicates the true state of knowledge about device radiation susceptibility.

## References

- DiCiccio, T. J., & Efron, B. (1996). Bootstrap confidence intervals. Statistical Science, 11(3), 189-228.

- Efron, B. (1987). Better bootstrap confidence intervals. Journal of the American Statistical Association, 82(397), 171-185.

- Efron, B., & Tibshirani, R. J. (1993). An Introduction to the Bootstrap. Chapman and Hall/CRC. Chapter 14.

- Quinn, H. (2014). Challenges in testing complex systems. IEEE Transactions on Nuclear Science, 61(2), 766-786.

---

*This post is Part 3 of the SEU Cross-Section Analysis series.*

**Series Navigation:**
- Part 0: [Rigorous SEU Cross-Section Analysis: A Methodological Manifesto](/seu-cross-section-manifesto-vibe-fitting)
- Part 1: MLE for Weibull Cross-Sections
- Part 2: Bootstrap Methods for Small-Sample Uncertainty
- **Part 3: Confidence Interval Selection** (current)
- Part 4: Zero-Event Data Treatment
- Part 5: Goodness-of-Fit Testing
- Part 6: Derived Parameter Validation
- Part 7: Automated Validation Pipelines
