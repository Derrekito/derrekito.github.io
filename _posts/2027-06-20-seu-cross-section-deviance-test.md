---
title: "Does the Weibull Fit? Deviance Testing for Model Adequacy"
date: 2027-06-20
categories: [Radiation Effects, Statistical Methods]
tags: [seu, goodness-of-fit, deviance, chi-squared, residuals, statistics]
series: seu-cross-section-analysis
series_order: 5
---

After fitting a Weibull model to SEU cross-section data, a critical question remains: does the model adequately describe the observations? Maximum likelihood estimation finds the best parameters given the assumed model structure, but provides no guarantee that the structure itself is appropriate. The deviance test formalizes this assessment, quantifying whether discrepancies between observed and predicted counts exceed what random sampling variation would produce.

This post presents the deviance goodness-of-fit test for Poisson regression models, including calculation procedures, interpretation guidelines, and diagnostic residual analysis. The methods apply directly to the 4-parameter Weibull cross-section model introduced in earlier posts of this series.

## The Deviance Statistic

### Definition and Derivation

The deviance statistic arises from likelihood ratio theory. For Poisson-distributed count data, the deviance compares the fitted model to a "saturated" model that perfectly predicts each observation.

For n data points with observed counts N_i and fitted expected counts lambda_i, the deviance is:

```
D = 2 * sum[N_i * log(N_i / lambda_i) - (N_i - lambda_i)]
```

This formula requires special handling when N_i = 0. The term N_i * log(N_i / lambda_i) becomes 0 * log(0), which is undefined. By convention (and mathematical limits), this contribution equals zero, but the (N_i - lambda_i) term still applies. For zero-count observations:

```
When N_i = 0: contribution = 2 * lambda_i
```

This makes physical sense: if the model predicts lambda_i expected counts but zero were observed, the discrepancy contributes positively to the deviance proportional to the prediction.

The complete deviance formula handling both cases:

```
D = 2 * sum_{N_i > 0}[N_i * log(N_i / lambda_i) - (N_i - lambda_i)]
    + 2 * sum_{N_i = 0}[lambda_i]
```

### Statistical Properties

Under the null hypothesis that the Poisson-Weibull model correctly describes the data, the deviance follows a chi-squared distribution:

```
D ~ chi-squared(df)
```

where the degrees of freedom equal:

```
df = n_points - n_parameters = n - 4
```

The 4 parameters of the Weibull model (sigma_sat, LET_th, W, S) consume 4 degrees of freedom from the original n observations. The remaining df degrees of freedom quantify information available for testing model adequacy.

This chi-squared approximation holds asymptotically (for large samples). For small samples typical in radiation testing, the approximation remains reasonable but should be interpreted with appropriate caution.

### Degrees of Freedom Requirements

The chi-squared test requires sufficient degrees of freedom to have statistical power. With df = 1 or 2, the test detects only extreme lack of fit. Practical guidelines:

| Data Points | DoF | Recommendation |
|-------------|-----|----------------|
| 4 | 0 | Test undefined; saturated model |
| 5 | 1 | Test possible but very low power |
| 6 | 2 | Minimal power; consider visual assessment |
| 7 | 3 | Adequate for detecting gross misfit |
| 8+ | 4+ | Standard test application appropriate |

The threshold of DoF >= 3 (requiring 7+ data points) provides reasonable discriminatory ability. With fewer points, visual inspection of residual plots becomes the primary diagnostic tool.

## Python Implementation

The following implementation calculates deviance and performs the chi-squared test:

```python
import numpy as np
from scipy.stats import chi2

def calculate_deviance(counts, lambda_fitted):
    """
    Calculate Poisson deviance statistic.

    Parameters
    ----------
    counts : array-like
        Observed event counts N_i
    lambda_fitted : array-like
        Model-predicted expected counts lambda_i

    Returns
    -------
    deviance : float
        The deviance statistic D
    """
    counts = np.asarray(counts, dtype=float)
    lambda_fitted = np.asarray(lambda_fitted, dtype=float)

    # Avoid numerical issues with very small predictions
    lambda_fitted = np.maximum(lambda_fitted, 1e-10)

    deviance = 0.0

    for n_i, lam_i in zip(counts, lambda_fitted):
        if n_i > 0:
            # Standard deviance contribution
            deviance += 2 * (n_i * np.log(n_i / lam_i) - (n_i - lam_i))
        else:
            # Zero-count contribution
            deviance += 2 * lam_i

    return deviance


def deviance_test(counts, lambda_fitted, n_params=4):
    """
    Perform deviance goodness-of-fit test.

    Parameters
    ----------
    counts : array-like
        Observed event counts
    lambda_fitted : array-like
        Model-predicted expected counts
    n_params : int
        Number of model parameters (4 for Weibull)

    Returns
    -------
    result : dict
        Dictionary containing:
        - deviance: the D statistic
        - df: degrees of freedom
        - p_value: p-value from chi-squared distribution
        - test_valid: whether df >= 3 for reliable testing
    """
    counts = np.asarray(counts)
    lambda_fitted = np.asarray(lambda_fitted)

    n_points = len(counts)
    df = n_points - n_params

    deviance = calculate_deviance(counts, lambda_fitted)

    result = {
        'deviance': deviance,
        'df': df,
        'p_value': None,
        'test_valid': df >= 3
    }

    if df >= 1:
        # Compute p-value (probability of observing D this large or larger)
        result['p_value'] = 1 - chi2.cdf(deviance, df)

    return result
```

### Example Application

Consider a dataset with 8 LET points and fitted Weibull parameters:

```python
# Example data
let_values = np.array([5, 10, 15, 20, 30, 40, 50, 60])  # MeV-cm^2/mg
counts = np.array([0, 3, 12, 25, 45, 52, 58, 61])
fluence = np.array([1e7, 1e7, 1e7, 1e7, 1e7, 1e7, 1e7, 1e7])

# Fitted Weibull parameters (from MLE)
sigma_sat = 6.2e-6  # cm^2
let_th = 4.5        # MeV-cm^2/mg
w = 12.0
s = 1.8

# Calculate expected counts
def weibull_cross_section(let_val, sigma_sat, let_th, w, s):
    if let_val <= let_th:
        return 0.0
    return sigma_sat * (1 - np.exp(-((let_val - let_th) / w) ** s))

lambda_fitted = np.array([
    weibull_cross_section(let_val, sigma_sat, let_th, w, s) * phi
    for let_val, phi in zip(let_values, fluence)
])

# Perform deviance test
result = deviance_test(counts, lambda_fitted, n_params=4)

print(f"Deviance: {result['deviance']:.2f}")
print(f"Degrees of freedom: {result['df']}")
print(f"P-value: {result['p_value']:.4f}")
print(f"Test valid (df >= 3): {result['test_valid']}")
```

## Interpreting P-Values

The p-value represents the probability of observing a deviance as large as (or larger than) the calculated value, assuming the model is correct. Standard interpretation thresholds:

| P-value Range | Interpretation | Recommended Action |
|---------------|----------------|-------------------|
| p > 0.05 | Model adequacy not rejected | Accept fit, proceed with analysis |
| 0.01 < p <= 0.05 | Marginal evidence against model | Inspect residuals carefully |
| p <= 0.01 | Strong evidence of lack of fit | Investigate causes, report with caveats |

### What the P-Value Does Not Mean

Several common misinterpretations should be avoided:

**p > 0.05 does not prove the model is correct.** The test may lack power to detect subtle misspecification. Small datasets with df = 3-4 can produce high p-values even when the model is modestly incorrect.

**p < 0.05 does not prove the model is wrong.** Statistical significance indicates the model's predictions differ from observations more than expected by chance, but the practical significance of this difference may be negligible. A model that captures the essential physics may still produce a low p-value due to minor systematic effects.

**The 0.05 threshold is conventional, not fundamental.** Radiation effects analysis should consider the consequences of model inadequacy. For conservative rate predictions, a model with p = 0.03 may still be acceptable if residual patterns suggest no systematic bias.

## Pearson Residuals

When the deviance test indicates potential lack of fit, Pearson residuals localize the problem. These standardized residuals identify which observations contribute most to the discrepancy.

### Definition

The Pearson residual for observation i:

```
r_i = (N_i - lambda_i) / sqrt(lambda_i)
```

This standardization divides the raw residual (N_i - lambda_i) by its expected standard deviation under Poisson assumptions (sqrt(lambda_i)).

### Expected Properties

For a correctly specified model with Poisson data:

| Property | Expected Value | Interpretation |
|----------|---------------|----------------|
| Mean | Approximately 0 | No systematic bias |
| Standard deviation | Approximately 1 | Residuals properly scaled |
| Distribution | Approximately normal (for large lambda_i) | Outliers identifiable |

Departures from these expectations signal specific problems:

- Mean significantly different from 0: Systematic over- or under-prediction
- Standard deviation >> 1: Overdispersion (more variance than Poisson predicts)
- Standard deviation << 1: Underdispersion (rare, possibly aggregated data)

### Implementation

```python
def calculate_pearson_residuals(counts, lambda_fitted):
    """
    Calculate Pearson residuals for Poisson model.

    Parameters
    ----------
    counts : array-like
        Observed event counts
    lambda_fitted : array-like
        Model-predicted expected counts

    Returns
    -------
    residuals : ndarray
        Standardized Pearson residuals
    summary : dict
        Summary statistics (mean, std, range)
    """
    counts = np.asarray(counts, dtype=float)
    lambda_fitted = np.asarray(lambda_fitted, dtype=float)

    # Avoid division by zero for very small predictions
    lambda_safe = np.maximum(lambda_fitted, 0.1)

    residuals = (counts - lambda_fitted) / np.sqrt(lambda_safe)

    summary = {
        'mean': np.mean(residuals),
        'std': np.std(residuals),
        'min': np.min(residuals),
        'max': np.max(residuals),
        'n_large': np.sum(np.abs(residuals) > 2)
    }

    return residuals, summary


```

## Residual Plot Interpretation

Visual inspection of residual plots often reveals patterns invisible in summary statistics. The standard diagnostic plot shows Pearson residuals versus the predictor variable (LET).

### Creating Residual Plots

```python
import matplotlib.pyplot as plt

def plot_residuals(let_values, residuals, summary, figsize=(10, 6)):
    """
    Create diagnostic residual plot.

    Parameters
    ----------
    let_values : array-like
        LET values (predictor variable)
    residuals : array-like
        Pearson residuals
    summary : dict
        Residual summary statistics
    figsize : tuple
        Figure dimensions

    Returns
    -------
    fig, ax : matplotlib figure and axes
    """
    fig, ax = plt.subplots(figsize=figsize)

    # Scatter plot of residuals
    ax.scatter(let_values, residuals, s=80, c='blue', edgecolors='black',
               linewidths=1, alpha=0.7, zorder=3)

    # Reference lines
    ax.axhline(y=0, color='black', linestyle='-', linewidth=1)
    ax.axhline(y=2, color='red', linestyle='--', linewidth=1, alpha=0.7)
    ax.axhline(y=-2, color='red', linestyle='--', linewidth=1, alpha=0.7)

    # Shaded acceptable region
    ax.fill_between(ax.get_xlim(), -2, 2, color='green', alpha=0.1, zorder=1)

    # Annotations
    ax.text(0.02, 0.98, f"Mean: {summary['mean']:.2f}\nStd: {summary['std']:.2f}",
            transform=ax.transAxes, verticalalignment='top',
            fontsize=10, family='monospace',
            bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))

    ax.set_xlabel('LET (MeV-cm$^2$/mg)', fontsize=12)
    ax.set_ylabel('Pearson Residual', fontsize=12)
    ax.set_title('Residual Diagnostic Plot', fontsize=14)
    ax.grid(True, alpha=0.3, zorder=0)

    plt.tight_layout()
    return fig, ax
```

### Pattern Recognition

Different residual patterns indicate specific model problems:

**Random scatter around zero**: The ideal outcome. Residuals show no systematic structure, supporting model adequacy. The Weibull function captures the underlying physics.

**U-shaped or inverted U-shaped pattern**: Indicates the Weibull shape does not match the data's turn-on behavior. The model systematically over-predicts in some LET regions and under-predicts in others. Consider whether the 4-parameter form is appropriate or whether physical effects (e.g., multiple sensitive volume populations) require a different functional form.

**Monotonic trend**: Residuals increase or decrease systematically with LET. This pattern suggests the fitted threshold or saturation parameters are biased. Re-examine parameter bounds and initial values in the optimization.

**One or two large residuals**: Isolated outliers may indicate data quality issues at specific LET points. Investigate beam uniformity, fluence measurement accuracy, or device-to-device variation for those test conditions.

**Consistently positive or negative residuals**: All residuals on one side of zero indicate systematic bias. The model may be constrained by bounds that prevent reaching the true optimum, or the data may have systematic fluence errors.

## What To Do When the Test Fails

A failed deviance test (p <= 0.01) or problematic residual patterns require systematic investigation.

### Step 1: Check Data Quality

Before questioning the model, verify the data:

- Confirm fluence values are correctly recorded (units, decimal places)
- Check for transcription errors in event counts
- Verify device identification (correct part, correct test conditions)
- Review test logs for anomalies (beam trips, dosimetry issues)

Data quality problems are common in radiation testing where measurements occur under time pressure at accelerator facilities.

### Step 2: Examine Specific Points

Identify observations contributing most to the deviance:

```python
def identify_problem_points(let_values, counts, lambda_fitted, threshold=2.0):
    """
    Identify observations with large residuals.

    Parameters
    ----------
    let_values : array-like
        LET values
    counts : array-like
        Observed counts
    lambda_fitted : array-like
        Predicted counts
    threshold : float
        Residual magnitude threshold

    Returns
    -------
    problem_df : list of dicts
        Details for each problematic observation
    """
    residuals, _ = calculate_pearson_residuals(counts, lambda_fitted)

    problem_points = []
    for i, (let_val, n, lam, r) in enumerate(
            zip(let_values, counts, lambda_fitted, residuals)):
        if abs(r) > threshold:
            problem_points.append({
                'index': i,
                'LET': let_val,
                'observed': n,
                'predicted': lam,
                'residual': r
            })

    return problem_points
```

For each problem point, consider:

- Was the test duration unusually short or long?
- Were multiple devices tested at this LET?
- Is this LET near the threshold where model predictions are most sensitive?

### Step 3: Consider Alternative Models

If data quality is verified and systematic patterns persist, the Weibull functional form may be inadequate:

**Multiple sensitive volume populations**: Devices with distinct sensitive volume types may show a two-stage turn-on not captured by single Weibull. A sum of two Weibull functions can model such behavior.

**Energy-dependent saturation**: Some devices exhibit saturation cross-section that varies with LET at very high energies, violating the constant sigma_sat assumption.

**Heavy-ion species effects**: Different ion species at the same LET may produce different cross-sections due to track structure effects. Data pooled across species may not follow a single Weibull curve.

### Step 4: Report with Caveats

When model inadequacy cannot be resolved, report results with appropriate qualifications:

- Document the deviance test result (D, df, p-value)
- Include residual plot in supplementary material
- Describe the nature of the misfit (e.g., "systematic under-prediction at intermediate LET")
- Quantify the practical impact on downstream rate calculations
- Note that parameter uncertainties may be underestimated

Honest reporting of model limitations serves the community better than presenting inadequate fits without qualification.

## Visual Assessment for Small Datasets

When degrees of freedom fall below 3 (fewer than 7 data points), formal testing lacks statistical power. Visual assessment becomes primary:

### Evaluation Criteria

When examining these plots without formal testing:

1. **Does the fitted curve pass through or near all data points?** Perfect agreement is not expected, but systematic deviations are concerning.

2. **Does the observed-vs-predicted plot cluster around the 1:1 line?** Points should scatter symmetrically around the diagonal without systematic curvature.

3. **Are Poisson confidence intervals consistent with the fit?** For count N, the approximate 95% interval is N +/- 2*sqrt(N). Data points should mostly fall within their intervals around the fitted curve.

4. **Does the fitted threshold appear reasonable?** The threshold should fall below the lowest LET with non-zero counts but not implausibly far below.

## Summary

The deviance goodness-of-fit test provides a formal assessment of Weibull model adequacy for SEU cross-section data:

1. **Deviance calculation** compares observed and predicted counts using the formula D = 2 * sum[N_i * log(N_i / lambda_i) - (N_i - lambda_i)], with special handling for zero counts.

2. **Degrees of freedom** equal n - 4 for the 4-parameter Weibull. Testing requires df >= 3 (7+ data points) for adequate statistical power.

3. **P-value interpretation** follows standard thresholds: p > 0.05 suggests adequacy, p <= 0.01 indicates strong evidence of misfit, with intermediate values warranting careful residual inspection.

4. **Pearson residuals** localize model-data discrepancies. Residuals should have mean approximately 0 and standard deviation approximately 1.

5. **Residual plots** reveal systematic patterns (U-shapes, trends, outliers) that suggest specific model problems.

6. **Failed tests** require systematic investigation of data quality before considering alternative models or reporting with caveats.

7. **Small datasets** (fewer than 7 points) require visual assessment when formal testing lacks power.

The deviance test answers a critical question: given these data, is there statistical evidence that the Weibull model is inadequate? A passing test does not prove the model is correct, but a failing test demands investigation before trusting fitted parameters for downstream rate calculations.

## References

- McCullagh, P., & Nelder, J. A. (1989). *Generalized Linear Models* (2nd ed.). Chapman and Hall/CRC.

- Agresti, A. (2013). *Categorical Data Analysis* (3rd ed.). Wiley.

- Petersen, E. L., Pickel, J. C., Adams, J. H., & Smith, E. C. (1992). Rate prediction for single event effects - A critique. *IEEE Transactions on Nuclear Science*, 39(6), 1577-1599.

- Quinn, H. (2014). Challenges in testing complex systems. *IEEE Transactions on Nuclear Science*, 61(2), 766-786.

---

## Series Navigation

This post is Part 5 of the SEU Cross-Section Analysis series.

| Post | Topic |
|------|-------|
| [Part 0](/seu-cross-section-manifesto-vibe-fitting) | Methodological Manifesto Against Vibe Fitting |
| [Part 1](/naive-weibull-curve-fit-seu-cross-section) | Naive Weibull Curve Fitting |
| Part 2 | MLE for Weibull Cross-Sections |
| Part 3 | Bootstrap Methods for Small-Sample Uncertainty |
| Part 4 | Zero-Event Data Treatment |
| **Part 5** | **Deviance Testing for Model Adequacy** (this post) |
| Part 6 | Derived Parameter Validation |
| Part 7 | Automated Validation Pipelines |

*Next: [Derived Parameter Validation](/seu-cross-section-parameter-validation) - Physical constraints and typical parameter ranges.*
