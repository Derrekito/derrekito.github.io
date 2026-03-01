---
title: "Naive Weibull Curve Fitting for SEU Cross-Section Data"
date: 2027-01-10 10:00:00 -0700
categories: [Radiation Effects, Statistical Modeling]
tags: [weibull, seu, see, cross-section, mle, bootstrap, poisson, radiation-testing, series]
series: "SEU/SEE Statistical Modeling"
series_order: 1
math: true
---

Single Event Effects (SEE) characterization requires fitting cross-section versus energy curves to sparse radiation test data. The Weibull function provides a standard parametric model for this relationship, capturing the threshold, turn-on, and saturation behavior observed in real devices. This post presents a naive but educational approach to Weibull curve fitting using Poisson Maximum Likelihood Estimation with bootstrap confidence intervals.

This post serves as an educational introduction to Weibull curve fitting. For production analysis requiring reproducible, defensible results, see the companion series: [Rigorous SEU Cross-Section Analysis: A Methodological Manifesto Against Vibe Fitting](/radiation%20effects/statistical%20methods/2027/05/16/seu-cross-section-manifesto-vibe-fitting.html).

## Series Context

This post provides the foundational concepts. The rigorous methodology series builds upon these fundamentals with:

- **Automated method selection** based on data characteristics (N ≥ 50 threshold, zero handling)
- **Literature-grounded thresholds** from Quinn 2014, Quinn & Tompkins 2024, Efron & Tibshirani 1993
- **Decision tree workflows** eliminating subjective "vibe fitting"
- **Comprehensive validation pipelines** with pass/fail criteria

The naive approach presented here intentionally simplifies several aspects for pedagogical clarity. The rigorous series addresses these limitations systematically.

## Problem Statement

Radiation effects testing quantifies device susceptibility to Single Event Effects by exposing devices to controlled particle beams and counting induced errors. The fundamental measurement is the cross-section: the effective area over which an incident particle causes an upset.

Cross-section varies with particle energy (or Linear Energy Transfer for heavy ions). At low energies, insufficient charge deposits in sensitive volumes to cause upsets. Above a threshold energy, cross-section increases through a "turn-on" region before saturating at high energies where all sensitive volumes respond.

The engineering challenge lies in characterizing this energy-dependent behavior from limited test data. Beam time at particle accelerator facilities costs thousands of dollars per hour. A typical test campaign may yield only 5-10 data points spanning the energy range of interest. From these sparse observations, analysts must:

- Estimate the threshold energy below which the device is immune
- Characterize the saturation cross-section representing maximum vulnerability
- Quantify uncertainty in these parameters for mission risk assessment
- Enable rate predictions for specific radiation environments

The Weibull cumulative distribution function provides a flexible parametric model for fitting these cross-section curves.

## Technical Background

### The Weibull Cross-Section Model

The 4-parameter Weibull function models cross-section as a function of Linear Energy Transfer (LET):

$$\sigma(E) = \begin{cases}
0 & \text{if } E \leq E_{th} \\
\sigma_{sat} \left[1 - \exp\left(-\left(\frac{E - E_{th}}{W}\right)^S\right)\right] & \text{if } E > E_{th}
\end{cases}$$

where:

| Parameter | Symbol | Units | Physical Meaning |
|-----------|--------|-------|------------------|
| Saturation cross-section | $\sigma_{sat}$ | cm$^2$/device | Maximum cross-section at high energy |
| Threshold energy | $E_{th}$ | MeV-cm$^2$/mg (LET) | Minimum energy to cause an event |
| Width parameter | $W$ | MeV-cm$^2$/mg | Controls energy range of transition |
| Shape parameter | $S$ | dimensionless | Controls steepness of turn-on |

This functional form originates from the cumulative Weibull distribution and was established as the community standard by Petersen et al. in the early 1990s. The CREME96 and CREME-MC space environment tools use this parametrization for rate predictions.

### Physical Interpretation

The Weibull function captures the physics of charge collection in microelectronic devices:

**Below threshold** ($E < E_{th}$): Incident particles deposit insufficient charge to flip memory cells or trigger logic upsets. The sensitive volumes remain unaffected.

**Turn-on region** ($E \approx E_{th}$): As energy increases, the deposited charge begins exceeding critical charge thresholds in some sensitive volumes. The shape parameter $S$ controls how abruptly this transition occurs. Sharp turn-ons ($S > 2$) indicate tight critical charge distributions; gradual turn-ons ($S < 1$) suggest significant variation in sensitive volume characteristics.

**Saturation region** ($E \gg E_{th}$): All sensitive volumes respond to incident particles. The cross-section plateaus at $\sigma_{sat}$, representing the total effective sensitive area.

### Python Implementation

```python
import numpy as np

def weibull_cross_section(energy, sigma_sat, e_th, s, w):
    """
    Four-parameter Weibull cross-section model.

    Parameters
    ----------
    energy : array-like
        Energy values (LET in MeV-cm^2/mg or proton energy in MeV)
    sigma_sat : float
        Saturation cross-section (cm^2/device)
    e_th : float
        Threshold energy
    s : float
        Shape parameter (dimensionless)
    w : float
        Width parameter (same units as energy)

    Returns
    -------
    sigma : ndarray
        Cross-section values (cm^2/device)
    """
    sigma = np.zeros_like(energy, dtype=float)
    mask = energy > e_th
    sigma[mask] = sigma_sat * (1 - np.exp(-((energy[mask] - e_th) / w) ** s))
    return sigma
```

## Naive Approach Disclaimer

This post presents a simplified, educational treatment of Weibull fitting. The approach makes several assumptions that may not hold for real test data:

**Assumptions made:**
- Counts follow a Poisson distribution (no overdispersion or zero-inflation)
- The Weibull functional form is correct (no model misspecification)
- Data points are independent (no correlation between measurements)
- Fluence measurements are exact (no systematic uncertainties)
- All LET values are above threshold (no zero-event handling)

**When this approach breaks down:**
- Fewer than 5 data points (insufficient constraints for 4 parameters)
- Zero-event observations requiring upper limit treatment
- Evidence of overdispersion (variance exceeding mean)
- Device behavior not matching Weibull shape
- Systematic fluence uncertainties dominating statistical uncertainty

Future posts in this series will address these limitations systematically. The naive approach presented here serves as a pedagogical foundation for understanding the statistical machinery before adding complexity.

## Poisson Maximum Likelihood Estimation

### Why Poisson, Not Least Squares

Radiation test data consists of counts: the number of Single Event Upsets observed during exposure to a known particle fluence. These counts are inherently discrete and non-negative, following Poisson statistics.

Weighted least squares fitting assumes Gaussian errors and symmetric confidence intervals. For small counts (N < 50), this assumption fails:

| Observed Count | Least Squares SE | Poisson 95% CI |
|----------------|-----------------|----------------|
| 3 | $\pm 1.73$ | [0.62, 8.77] |
| 10 | $\pm 3.16$ | [4.8, 18.4] |
| 50 | $\pm 7.07$ | [37.1, 66.0] |

The Poisson confidence intervals are asymmetric and wider than symmetric Gaussian intervals would suggest. For counts below 50, Poisson MLE provides correct statistical inference while least squares underestimates uncertainty.

### MLE Formulation

The observed count $N_i$ at energy $E_i$ with fluence $\Phi_i$ follows:

$$N_i \sim \text{Poisson}(\lambda_i)$$

where the expected count is:

$$\lambda_i = \sigma(E_i; \theta) \cdot \Phi_i$$

The cross-section $\sigma(E_i; \theta)$ depends on the Weibull parameters $\theta = [\sigma_{sat}, E_{th}, S, W]$.

Assuming independence, the log-likelihood for all observations is:

$$\ell(\theta) = \sum_{i=1}^{n} \left[ N_i \log(\lambda_i) - \lambda_i \right] + \text{const}$$

Maximum Likelihood Estimation finds the parameters $\hat{\theta}$ that maximize this likelihood:

$$\hat{\theta}_{MLE} = \arg\max_\theta \ell(\theta)$$

In practice, optimization minimizes the negative log-likelihood:

$$\hat{\theta}_{MLE} = \arg\min_\theta \left\{ -\sum_{i=1}^{n} \left[ N_i \log(\sigma(E_i; \theta) \cdot \Phi_i) - \sigma(E_i; \theta) \cdot \Phi_i \right] \right\}$$

### Implementation

```python
from scipy.optimize import minimize

def poisson_neg_log_likelihood(params, energy, counts, fluence):
    """
    Negative log-likelihood for Poisson-Weibull model.

    Parameters
    ----------
    params : array-like
        Weibull parameters [sigma_sat, e_th, s, w]
    energy : array-like
        Energy values
    counts : array-like
        Observed event counts
    fluence : array-like
        Particle fluence for each observation

    Returns
    -------
    nll : float
        Negative log-likelihood
    """
    sigma_sat, e_th, s, w = params

    # Compute expected cross-sections
    sigma = weibull_cross_section(energy, sigma_sat, e_th, s, w)

    # Expected counts
    lambda_exp = sigma * fluence

    # Avoid log(0) for numerical stability
    lambda_exp = np.maximum(lambda_exp, 1e-10)

    # Poisson log-likelihood (negative for minimization)
    log_lik = np.sum(counts * np.log(lambda_exp) - lambda_exp)

    return -log_lik


def fit_weibull_mle(energy, counts, fluence, initial_guess=None, bounds=None):
    """
    Fit Weibull cross-section model using Poisson MLE.

    Parameters
    ----------
    energy : array-like
        Energy values
    counts : array-like
        Observed event counts
    fluence : array-like
        Particle fluence for each observation
    initial_guess : array-like, optional
        Starting point [sigma_sat, e_th, s, w]
    bounds : list of tuples, optional
        Parameter bounds [(low, high), ...]

    Returns
    -------
    params : ndarray
        Fitted parameters [sigma_sat, e_th, s, w]
    result : OptimizeResult
        Full optimization result
    """
    energy = np.asarray(energy)
    counts = np.asarray(counts)
    fluence = np.asarray(fluence)

    # Default initial guess based on data
    if initial_guess is None:
        sigma_max = np.max(counts / fluence)
        e_min = np.min(energy)
        e_range = np.max(energy) - e_min
        initial_guess = [
            sigma_max * 1.2,      # sigma_sat
            max(0, e_min - 1.0),  # e_th
            2.0,                   # s
            e_range / 3            # w
        ]

    # Default bounds
    if bounds is None:
        sigma_max = np.max(counts / fluence)
        e_min = np.min(energy)
        e_range = np.max(energy) - e_min
        bounds = [
            (sigma_max * 0.1, sigma_max * 10),  # sigma_sat
            (0, e_min),                          # e_th
            (0.1, 10),                           # s
            (0.1, e_range * 2)                   # w
        ]

    # Optimize
    result = minimize(
        poisson_neg_log_likelihood,
        initial_guess,
        args=(energy, counts, fluence),
        method='L-BFGS-B',
        bounds=bounds,
        options={'maxiter': 10000, 'ftol': 1e-9}
    )

    if not result.success:
        raise RuntimeError(f"MLE optimization failed: {result.message}")

    return result.x, result
```

## Bootstrap Confidence Intervals

### Why Bootstrap for Small Samples

Maximum likelihood theory provides analytical formulas for parameter uncertainty via the Hessian (observed Fisher information). These asymptotic results assume large samples where the MLE is approximately Gaussian.

For SEE test data with 5-10 observations, asymptotic theory fails:

- The Gaussian approximation is poor for highly non-linear models
- Hessian-based confidence intervals can underestimate uncertainty by 30-50%
- Boundary constraints (all parameters positive) are not respected
- Parameter correlations are inadequately captured

Bootstrap resampling provides reliable uncertainty quantification without distributional assumptions. The procedure:

1. Fit the model to original data, obtaining $\hat{\theta}$
2. Generate synthetic datasets by resampling
3. Refit the model to each synthetic dataset
4. Compute confidence intervals from the empirical distribution of fitted parameters

### Parametric vs Non-Parametric Bootstrap

**Non-parametric bootstrap** resamples directly from observed data with replacement. For sparse count data, this can produce degenerate samples (e.g., all zeros) that prevent model fitting.

**Parametric bootstrap** resamples from the fitted model:

$$N_i^* \sim \text{Poisson}(\hat{\lambda}_i)$$

where $\hat{\lambda}_i = \sigma(E_i; \hat{\theta}) \cdot \Phi_i$ uses the fitted cross-section.

For small-sample count data, parametric bootstrap provides better coverage because:
- Synthetic counts can differ from observed values
- Zero observations can generate non-zero resamples if the fitted model predicts $\hat{\lambda} > 0$
- Model smoothing reduces degenerate sample probability

The choice of parametric bootstrap assumes the Poisson-Weibull model is correct. Goodness-of-fit testing (covered in Part 2) validates this assumption.

### Implementation

```python
from joblib import Parallel, delayed

def bootstrap_single_iteration(b, energy, fluence, theta_hat, seed):
    """
    Single bootstrap iteration.

    Parameters
    ----------
    b : int
        Bootstrap iteration index
    energy : ndarray
        Energy values
    fluence : ndarray
        Fluence values
    theta_hat : ndarray
        Fitted parameters from original data
    seed : int
        Base random seed

    Returns
    -------
    params : ndarray or None
        Fitted parameters from resampled data
    """
    np.random.seed(seed + b)

    # Compute expected counts from fitted model
    sigma_hat = weibull_cross_section(energy, *theta_hat)
    lambda_hat = sigma_hat * fluence

    # Parametric bootstrap: resample from Poisson
    counts_star = np.random.poisson(lambda_hat)

    # Skip if degenerate (all zeros or insufficient non-zero)
    if np.sum(counts_star > 0) < 3:
        return None

    # Refit model
    try:
        params_star, _ = fit_weibull_mle(
            energy, counts_star, fluence,
            initial_guess=theta_hat  # Warm start
        )
        return params_star
    except:
        return None


def bootstrap_confidence_intervals(energy, counts, fluence, theta_hat,
                                    n_bootstrap=1000, confidence=0.95,
                                    n_jobs=-1, seed=42):
    """
    Compute bootstrap confidence intervals for Weibull parameters.

    Parameters
    ----------
    energy : ndarray
        Energy values
    counts : ndarray
        Observed counts
    fluence : ndarray
        Fluence values
    theta_hat : ndarray
        MLE fitted parameters
    n_bootstrap : int
        Number of bootstrap iterations
    confidence : float
        Confidence level (e.g., 0.95 for 95% CI)
    n_jobs : int
        Number of parallel jobs (-1 for all cores)
    seed : int
        Random seed for reproducibility

    Returns
    -------
    ci_lower : ndarray
        Lower bounds for each parameter
    ci_upper : ndarray
        Upper bounds for each parameter
    theta_bootstrap : ndarray
        All successful bootstrap parameter estimates
    """
    # Parallel bootstrap
    theta_bootstrap = Parallel(n_jobs=n_jobs, verbose=0)(
        delayed(bootstrap_single_iteration)(
            b, energy, fluence, theta_hat, seed
        )
        for b in range(n_bootstrap)
    )

    # Filter out failed iterations
    theta_bootstrap = np.array([t for t in theta_bootstrap if t is not None])

    # Check success rate
    success_rate = len(theta_bootstrap) / n_bootstrap
    if success_rate < 0.90:
        print(f"Warning: Bootstrap success rate {success_rate:.1%} is low")

    # Percentile confidence intervals
    alpha = 1 - confidence
    ci_lower = np.percentile(theta_bootstrap, 100 * alpha / 2, axis=0)
    ci_upper = np.percentile(theta_bootstrap, 100 * (1 - alpha / 2), axis=0)

    return ci_lower, ci_upper, theta_bootstrap
```

### Percentile Method

The percentile method constructs confidence intervals directly from the empirical bootstrap distribution:

- Sort the bootstrap estimates: $\hat{\theta}^*_{(1)} \leq \cdots \leq \hat{\theta}^*_{(B)}$
- For a 95% confidence interval: lower = 2.5th percentile, upper = 97.5th percentile

This method:
- Produces asymmetric intervals when the bootstrap distribution is skewed
- Requires no distributional assumptions
- Naturally respects parameter bounds

More sophisticated methods (BCa, bootstrap-t) can improve coverage but require additional computation. For the naive approach presented here, percentile intervals are sufficient.

## Goodness-of-Fit Assessment

### Deviance Test

The deviance statistic quantifies how well the fitted model describes the data:

$$D = 2 \sum_{i=1}^{n} \left[ N_i \log\left(\frac{N_i}{\hat{\lambda}_i}\right) - (N_i - \hat{\lambda}_i) \right]$$

Under the null hypothesis that the Poisson-Weibull model is correct:

$$D \sim \chi^2_{n-p}$$

where $n$ is the number of observations and $p = 4$ is the number of fitted parameters.

The deviance test requires $n - p \geq 3$ degrees of freedom for reasonable power. With only 5 data points and 4 parameters, the test has limited discriminatory ability. This limitation motivates collecting more test data when feasible.

### Implementation

```python
from scipy.stats import chi2

def deviance_test(counts, lambda_hat, n_params=4):
    """
    Deviance goodness-of-fit test for Poisson model.

    Parameters
    ----------
    counts : ndarray
        Observed counts
    lambda_hat : ndarray
        Fitted expected counts
    n_params : int
        Number of model parameters

    Returns
    -------
    deviance : float
        Deviance statistic
    p_value : float
        P-value from chi-squared distribution
    df : int
        Degrees of freedom
    """
    # Handle N=0 cases (0 * log(0/x) = 0 by convention)
    mask = counts > 0

    deviance = 2 * np.sum(
        counts[mask] * np.log(counts[mask] / lambda_hat[mask])
        - (counts[mask] - lambda_hat[mask])
    )

    # Add contribution from zero counts
    deviance += 2 * np.sum(lambda_hat[~mask])

    df = len(counts) - n_params

    if df < 1:
        return deviance, np.nan, df

    p_value = 1 - chi2.cdf(deviance, df)

    return deviance, p_value, df
```

### Interpretation

| P-value | Interpretation |
|---------|---------------|
| p > 0.10 | Model fits adequately |
| 0.05 < p < 0.10 | Marginal fit, inspect residuals |
| p < 0.05 | Model fit questionable |
| p < 0.01 | Model likely misspecified |

A small p-value suggests either:
- The Weibull functional form is incorrect
- Overdispersion (variance exceeds Poisson expectation)
- Zero-inflation (excess zero observations)
- Outliers or data quality issues

Part 2 of this series covers diagnostic procedures for distinguishing these cases.

## Visualization

Effective visualization communicates both the fitted curve and uncertainty in the fit.

### Cross-Section Curve with Confidence Bands

```python
import matplotlib.pyplot as plt

def plot_weibull_fit(energy, counts, fluence, theta_hat, theta_bootstrap,
                     confidence=0.95, figsize=(10, 6)):
    """
    Plot fitted Weibull curve with confidence bands.

    Parameters
    ----------
    energy : ndarray
        Energy values from test data
    counts : ndarray
        Observed counts
    fluence : ndarray
        Fluence values
    theta_hat : ndarray
        MLE fitted parameters
    theta_bootstrap : ndarray
        Bootstrap parameter samples (n_bootstrap x 4)
    confidence : float
        Confidence level for bands
    figsize : tuple
        Figure size
    """
    fig, ax = plt.subplots(figsize=figsize)

    # Dense energy grid for smooth curve
    e_plot = np.linspace(0, np.max(energy) * 1.2, 200)

    # MLE fitted curve
    sigma_fit = weibull_cross_section(e_plot, *theta_hat)

    # Bootstrap curves for confidence band
    alpha = 1 - confidence
    sigma_curves = np.array([
        weibull_cross_section(e_plot, *theta_b)
        for theta_b in theta_bootstrap
    ])
    sigma_lower = np.percentile(sigma_curves, 100 * alpha / 2, axis=0)
    sigma_upper = np.percentile(sigma_curves, 100 * (1 - alpha / 2), axis=0)

    # Observed cross-sections with Poisson error bars
    sigma_obs = counts / fluence

    # Poisson confidence intervals for individual points
    from scipy.stats import poisson
    count_lower = poisson.ppf(alpha / 2, counts)
    count_upper = poisson.ppf(1 - alpha / 2, counts)
    sigma_err_lower = sigma_obs - count_lower / fluence
    sigma_err_upper = count_upper / fluence - sigma_obs

    # Plot
    ax.fill_between(e_plot, sigma_lower * 1e6, sigma_upper * 1e6,
                     alpha=0.3, color='blue', label=f'{int(confidence*100)}% CI')
    ax.plot(e_plot, sigma_fit * 1e6, 'b-', linewidth=2, label='MLE Fit')
    ax.errorbar(energy, sigma_obs * 1e6,
                yerr=[sigma_err_lower * 1e6, sigma_err_upper * 1e6],
                fmt='ko', markersize=8, capsize=5, label='Observed')

    # Reference lines
    ax.axhline(y=theta_hat[0] * 1e6, color='gray', linestyle='--',
               alpha=0.5, label=r'$\sigma_{sat}$')
    ax.axvline(x=theta_hat[1], color='red', linestyle='--',
               alpha=0.5, label=r'$E_{th}$')

    ax.set_xlabel('LET (MeV-cm$^2$/mg)', fontsize=12)
    ax.set_ylabel('Cross-Section ($\\times 10^{-6}$ cm$^2$/device)', fontsize=12)
    ax.set_title('Weibull Cross-Section Fit with Bootstrap Uncertainty', fontsize=14)
    ax.legend(loc='lower right', fontsize=10)
    ax.grid(True, alpha=0.3)
    ax.set_xlim(left=0)
    ax.set_ylim(bottom=0)

    plt.tight_layout()
    return fig, ax
```

### Parameter Distributions

Histograms of bootstrap parameter distributions reveal:
- Whether the distribution is approximately Gaussian (well-behaved)
- Evidence of skewness (may need asymmetric intervals)
- Bimodality (parameter identification issues)

```python
def plot_parameter_distributions(theta_bootstrap, theta_hat, param_names=None):
    """
    Plot bootstrap distributions for each parameter.
    """
    if param_names is None:
        param_names = [r'$\sigma_{sat}$', r'$E_{th}$', r'$S$', r'$W$']

    fig, axes = plt.subplots(2, 2, figsize=(12, 10))

    for i, (ax, name) in enumerate(zip(axes.flat, param_names)):
        values = theta_bootstrap[:, i]

        ax.hist(values, bins=50, density=True, alpha=0.7,
                edgecolor='black', linewidth=0.5)
        ax.axvline(theta_hat[i], color='red', linestyle='--',
                   linewidth=2, label='MLE')
        ax.axvline(np.percentile(values, 2.5), color='orange',
                   linestyle=':', linewidth=1.5, label='95% CI')
        ax.axvline(np.percentile(values, 97.5), color='orange',
                   linestyle=':', linewidth=1.5)

        ax.set_xlabel(name, fontsize=12)
        ax.set_ylabel('Density', fontsize=12)
        ax.legend(fontsize=9)
        ax.grid(True, alpha=0.3)

    plt.suptitle('Bootstrap Parameter Distributions', fontsize=14)
    plt.tight_layout()
    return fig, axes
```

## Limitations and Future Work

### Limitations of the Naive Approach

This educational treatment intentionally omits several practical considerations:

**Zero-event handling**: Real test data often includes LET values where no upsets were observed. These observations provide upper-limit constraints but cannot be handled by standard MLE (the likelihood involves log(0)). The rigorous series covers the Quinn 3.7/Φ upper limit rule in [Part 4: Zero-Event Treatment](/radiation%20effects/statistical%20methods/2027/06/13/seu-cross-section-zero-events.html).

**Model validation**: The deviance test provides limited discriminatory power with 5 data points. Overdispersion tests, residual analysis, and validation pipelines are covered in [Part 5: Deviance Testing](/radiation%20effects/statistical%20methods/2027/06/20/seu-cross-section-deviance-test.html) and [Part 7: Validation Pipelines](/radiation%20effects/statistical%20methods/2027/07/04/seu-cross-section-validation-pipeline.html).

**Method selection**: The choice between MLE variants (Standard, SmallSample, WithZeros) and bootstrap configurations (Full vs Conservative) should follow automated decision rules based on data characteristics, not analyst judgment. The [Manifesto](/radiation%20effects/statistical%20methods/2027/05/16/seu-cross-section-manifesto-vibe-fitting.html) presents the complete decision tree.

**Systematic uncertainties**: Fluence measurements typically carry 5-10% systematic uncertainty. This analysis treats fluence as exact, underestimating total parameter uncertainty.

**Correlated data**: Multiple measurements on the same device or during the same beam run may violate independence assumptions.

### The Rigorous Alternative

The companion series eliminates subjective judgment from curve fitting:

- **Automated method selection**: Decision tree based on N ≥ 50 threshold (Quinn 2014), zero presence, and sample adequacy
- **Literature-grounded thresholds**: Every decision point cites peer-reviewed sources
- **Reproducible workflows**: Given identical inputs and random seeds, any analyst produces identical outputs
- **Comprehensive validation**: Pre-analysis checks (overdispersion, zero-inflation, sample size) and post-fit validation (deviance test, residual analysis, parameter bounds)

Start with the [Manifesto](/radiation%20effects/statistical%20methods/2027/05/16/seu-cross-section-manifesto-vibe-fitting.html) for the complete framework.

## Summary

This post presented a naive but pedagogically useful approach to fitting Weibull cross-section curves to SEE test data:

1. **Weibull model** captures threshold, turn-on, and saturation physics with four parameters
2. **Poisson MLE** provides statistically correct inference for count data
3. **Parametric bootstrap** quantifies parameter uncertainty for small samples
4. **Deviance testing** assesses goodness-of-fit (with limitations)
5. **Visualization** communicates results with confidence bands

The approach assumes no zero events, correct model specification, and independent Poisson observations. Real test data frequently violates these assumptions, motivating the more sophisticated methods to be covered in subsequent posts.

For readers implementing these methods, the key practical guidance is:
- Always use Poisson MLE, not least squares, for count data
- Use bootstrap (not Hessian) for uncertainty with fewer than 50 total events
- Report confidence intervals, not just point estimates
- Validate the model before trusting the fit

---

## Series Index

### Introductory Post

1. **Naive Weibull Curve Fitting** (this post) - Educational foundation

### Rigorous Methodology Series

For production-quality analysis, the following series provides automated, reproducible methods:

0. [Rigorous SEU Cross-Section Analysis: A Methodological Manifesto Against Vibe Fitting](/radiation%20effects/statistical%20methods/2027/05/16/seu-cross-section-manifesto-vibe-fitting.html) - Decision tree overview
1. [MLE for Weibull Cross-Sections](/radiation%20effects/statistical%20methods/2027/05/23/seu-cross-section-mle-weibull.html) - When normal approximations hold
2. [Parametric Bootstrap for SEU Data](/radiation%20effects/statistical%20methods/2027/05/30/seu-cross-section-bootstrap-uncertainty.html) - When MLE covariance fails
3. [Choosing Confidence Intervals](/radiation%20effects/statistical%20methods/2027/06/06/seu-cross-section-confidence-intervals.html) - BCA vs Percentile methods
4. [When N=0: Zero-Event Treatment](/radiation%20effects/statistical%20methods/2027/06/13/seu-cross-section-zero-events.html) - Upper limits done right
5. [Deviance Testing for Model Adequacy](/radiation%20effects/statistical%20methods/2027/06/20/seu-cross-section-deviance-test.html) - Goodness-of-fit assessment
6. [Derived Parameter Validation](/radiation%20effects/statistical%20methods/2027/06/27/seu-cross-section-parameter-validation.html) - Physical constraints
7. [Automated Validation Pipelines](/radiation%20effects/statistical%20methods/2027/07/04/seu-cross-section-validation-pipeline.html) - From data to defensible results

## References

The methods presented here draw from established literature in radiation effects testing and statistical modeling:

- Petersen, E. L., et al. (1992). "Rate Prediction for Single Event Effects - A Critique." IEEE Trans. Nucl. Sci.
- Quinn, H. M. (2014). "Challenges in Testing Complex Systems." IEEE Trans. Nucl. Sci.
- Cameron, A. C., & Trivedi, P. K. (2013). *Regression Analysis of Count Data*. Cambridge University Press.
- Efron, B., & Tibshirani, R. J. (1993). *An Introduction to the Bootstrap*. Chapman & Hall/CRC.

## Computational Environment

The code examples in this post use:
- Python 3.10+
- NumPy, SciPy for numerical computation
- Matplotlib for visualization
- joblib for parallel bootstrap execution
