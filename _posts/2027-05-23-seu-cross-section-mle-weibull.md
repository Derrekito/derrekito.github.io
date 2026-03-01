---
title: "MLE for Weibull Cross-Sections: When Normal Approximations Hold"
date: 2027-05-23
categories: [Radiation Effects, Statistical Methods]
tags: [seu, weibull, mle, maximum-likelihood, curve-fitting, python, scipy]
series: seu-cross-section-analysis
series_order: 1
---

Maximum Likelihood Estimation provides the statistical foundation for rigorous SEU cross-section analysis. When applied correctly, MLE extracts optimal parameter estimates from sparse radiation test data while enabling principled uncertainty quantification. When applied incorrectly, MLE produces misleading confidence intervals that understate true parameter uncertainty. The distinction lies in understanding when asymptotic normal approximations hold versus when they fail.

This post details the Poisson likelihood formulation for Weibull cross-section fitting, the L-BFGS-B optimization approach, physically-motivated parameter bounds, and three MLE variants tailored to different data characteristics. The framework builds directly on the methodological principles established in the series manifesto, replacing vibe fitting with reproducible, defensible analysis.

## Poisson Likelihood for Count Data

Radiation effects testing produces count data: the number of Single Event Upsets observed during exposure to a known particle fluence. These counts follow Poisson statistics, making the Poisson likelihood the correct foundation for inference.

### The Statistical Model

At each LET value E_i, an observed count N_i results from exposing a device to fluence Phi_i. The expected count depends on the cross-section:

```
lambda_i = sigma(E_i; theta) * Phi_i
```

where sigma(E_i; theta) is the Weibull cross-section function evaluated at energy E_i with parameter vector theta.

The probability of observing exactly N_i events under Poisson statistics is:

```
P(N_i | lambda_i) = lambda_i^N_i * exp(-lambda_i) / N_i!
```

Assuming independence across measurements, the joint probability (likelihood) for all observations is the product:

```
L(theta) = Product over i of [ lambda_i^N_i * exp(-lambda_i) / N_i! ]
```

Taking the logarithm converts products to sums and eliminates the factorial term (which does not depend on theta):

```
log L(theta) = Sum over i of [ N_i * log(lambda_i) - lambda_i ] + constant
```

### Why Poisson, Not Gaussian

Gaussian (least squares) fitting assumes symmetric, normally-distributed errors. For count data, this assumption fails in three ways.

First, counts are discrete and non-negative. A Gaussian model can predict negative counts or fractional counts, both physically impossible.

Second, Poisson variance equals the mean. Low counts have proportionally larger uncertainty than high counts. Least squares assigns equal weight to all residuals, overweighting low-count observations.

Third, Poisson confidence intervals are asymmetric. Observing 3 events yields a 95% Poisson interval of approximately [0.6, 8.8], not [3 - 1.73, 3 + 1.73] as Gaussian theory suggests. The table below illustrates this divergence.

| Observed Count | Gaussian SE | Poisson 95% CI |
|----------------|-------------|----------------|
| 3 | +/- 1.73 | [0.6, 8.8] |
| 10 | +/- 3.16 | [4.8, 18.4] |
| 25 | +/- 5.00 | [16.2, 36.8] |
| 50 | +/- 7.07 | [37.1, 66.0] |
| 100 | +/- 10.0 | [81.4, 121.6] |

Above approximately 50 counts, the Poisson distribution converges toward Gaussian and symmetric intervals become acceptable. Below this threshold, Poisson inference remains essential.

## The 4-Parameter Weibull Model

The Weibull function has served as the community standard for SEU cross-section modeling since Petersen et al. 1992. The 4-parameter form captures threshold behavior, turn-on characteristics, and saturation physics:

```
sigma(E) = 0                                          for E <= E_th
sigma(E) = sigma_sat * [1 - exp(-((E - E_th)/W)^S)]   for E > E_th
```

Each parameter carries physical meaning grounded in device physics and charge collection mechanisms.

### Saturation Cross-Section (sigma_sat)

The saturation cross-section represents the maximum cross-section achieved at high LET, where all sensitive volumes respond to incident particles. This parameter corresponds to the total effective sensitive area of the device.

Physical interpretation: At sufficiently high LET, every particle traversing a sensitive volume deposits enough charge to cause an upset. The cross-section saturates at the geometric sum of all sensitive regions.

Typical values: Range from 10^-10 cm^2/device for hardened technologies to 10^-3 cm^2/device for large commercial memories. Values depend on technology node, cell architecture, and hardening approaches.

### Threshold LET (E_th or LET_th)

The threshold LET represents the minimum energy deposition required to cause an upset in any sensitive volume. Below this threshold, deposited charge is insufficient to flip cell states.

Physical interpretation: The threshold corresponds to the critical charge divided by sensitive volume path length. Devices with smaller feature sizes typically exhibit lower thresholds due to reduced critical charge requirements.

Typical values: Range from near-zero for advanced CMOS nodes to 20+ MeV-cm^2/mg for hardened SOI technologies.

### Shape Parameter (S)

The shape parameter controls the steepness of the cross-section turn-on region. It describes how uniformly the sensitive volumes respond as LET increases.

Physical interpretation:
- S < 1: Gradual onset indicating significant variation in critical charge among sensitive volumes, or multiple upset mechanisms with different thresholds
- S approximately 1-2: Moderate transition typical of commercial devices
- S > 3: Sharp onset suggesting tight critical charge distribution, potentially indicating overfitting

### Width Parameter (W)

The width parameter controls the LET range over which the cross-section transitions from threshold to saturation.

Physical interpretation: Larger W values indicate a broader distribution of sensitive volume characteristics. Smaller W values indicate more uniform response across the device.

Typical values: Generally comparable to the tested LET range. Values much larger than the data range indicate poor parameter constraint.

## Negative Log-Likelihood Formulation

Maximum likelihood estimation finds parameters that maximize the likelihood function. Equivalently, minimization routines find parameters that minimize the negative log-likelihood (NLL):

```
NLL(theta) = -log L(theta)
           = Sum over i of [ lambda_i - N_i * log(lambda_i) ]
           = Sum over i of [ sigma(E_i; theta) * Phi_i - N_i * log(sigma(E_i; theta) * Phi_i) ]
```

### Numerical Stability

Direct implementation of the NLL requires careful handling of edge cases.

Zero cross-section: When E_i <= E_th, the Weibull function returns zero. Computing log(0) produces negative infinity, contaminating the objective function. The solution is to replace zero with a small positive value (typically 10^-10 to 10^-15) before taking the logarithm.

Zero counts: When N_i = 0, the term N_i * log(lambda_i) equals zero regardless of lambda_i. This is mathematically correct (0 * log(x) = 0), but numerical issues can arise from 0 * inf in floating point. Explicit handling prevents propagation of NaN values.

Overflow: Very large expected counts can cause exp(-lambda) to underflow. Working entirely in log space (log-likelihood rather than likelihood) prevents this issue.

### Python Implementation

```python
import numpy as np

def weibull_cross_section(energy, sigma_sat, e_th, s, w):
    """4-parameter Weibull cross-section model."""
    sigma = np.zeros_like(energy, dtype=np.float64)
    mask = energy > e_th
    if np.any(mask):
        arg = ((energy[mask] - e_th) / w) ** s
        sigma[mask] = sigma_sat * (1.0 - np.exp(-arg))
    return sigma


def poisson_neg_log_likelihood(params, energy, counts, fluence, eps=1e-12):
    """Negative log-likelihood for Poisson-Weibull model."""
    sigma_sat, e_th, s, w = params
    sigma = weibull_cross_section(energy, sigma_sat, e_th, s, w)
    lambda_exp = sigma * fluence
    lambda_safe = np.maximum(lambda_exp, eps)
    nll = np.sum(lambda_exp - counts * np.log(lambda_safe))
    return nll
```

## L-BFGS-B Constrained Optimization

The Limited-memory Broyden-Fletcher-Goldfarb-Shanno with Box constraints (L-BFGS-B) algorithm provides an efficient approach for optimizing the Weibull likelihood subject to parameter bounds.

### Why L-BFGS-B

Several characteristics make L-BFGS-B well-suited for Weibull fitting.

Box constraints: Physical parameters require bounds. Cross-section must be positive. Threshold must fall below the minimum tested LET. L-BFGS-B handles simple bound constraints directly without penalty function reformulation.

Memory efficiency: The algorithm approximates the Hessian using limited history (typically 10 past iterations), reducing memory requirements compared to full Newton methods.

Gradient-based: L-BFGS-B uses gradient information for efficient search direction computation. SciPy can compute gradients numerically when analytical gradients are unavailable.

Convergence properties: For smooth, bounded optimization problems like the Weibull likelihood, L-BFGS-B typically converges reliably to local optima.

### SciPy Implementation

```python
from scipy.optimize import minimize

def fit_weibull_mle(energy, counts, fluence, initial_guess=None, bounds=None):
    """Fit Weibull cross-section model using Poisson MLE with L-BFGS-B."""
    energy = np.asarray(energy, dtype=np.float64)
    counts = np.asarray(counts, dtype=np.float64)
    fluence = np.asarray(fluence, dtype=np.float64)

    if bounds is None:
        bounds = compute_parameter_bounds(energy, counts, fluence)
    if initial_guess is None:
        initial_guess = compute_initial_guess(energy, counts, fluence, bounds)

    result = minimize(
        poisson_neg_log_likelihood,
        initial_guess,
        args=(energy, counts, fluence),
        method='L-BFGS-B',
        bounds=bounds,
        options={'maxiter': 10000, 'ftol': 1e-10, 'gtol': 1e-8}
    )
    return result.x, result
```

## Parameter Bounds from Physics

Physically-motivated bounds serve two purposes: they constrain optimization to meaningful parameter regions and prevent the optimizer from exploring pathological corners of parameter space.

### Saturation Cross-Section Bounds

Lower bound: The saturation cross-section must exceed the maximum observed cross-section. A device cannot have fewer sensitive volumes than the data indicates. A factor of 0.5 below the maximum observed sigma provides margin for measurement noise.

Upper bound: Physical device areas constrain the maximum plausible cross-section. A factor of 10 above the maximum observed sigma allows for saturation well above measured points while remaining physically reasonable.

```
sigma_sat bounds: [0.5 * max(sigma_obs), 10 * max(sigma_obs)]
```

### Threshold LET Bounds

Lower bound: Threshold must be non-negative. Negative threshold lacks physical meaning.

Upper bound: Threshold must fall below the minimum tested LET where events were observed. Setting the upper bound at the minimum tested LET ensures the fitted threshold lies within the testable regime.

```
LET_th bounds: [0, min(LET)]
```

### Shape Parameter Bounds

Lower bound: Shape values below 0.1 produce extremely gradual turn-on, approaching a step function at threshold. Such behavior rarely matches physical device response.

Upper bound: Shape values above 10 produce extremely sharp turn-on, approximating a step function at threshold plus a small offset. This typically indicates overfitting to noise in sparse data.

```
S bounds: [0.1, 10]
```

### Width Parameter Bounds

Lower bound: Width values near zero cause numerical instability in the exponential term and imply implausibly sharp transitions.

Upper bound: Width much larger than twice the LET range indicates the transition extends far beyond measured data, suggesting poor parameter constraint.

```
W bounds: [0.1, 2 * (max_LET - min_LET)]
```

### Implementation

```python
def compute_parameter_bounds(energy, counts, fluence):
    """Compute physically-motivated parameter bounds."""
    sigma_obs = counts / fluence
    sigma_max = np.max(sigma_obs[sigma_obs > 0])
    let_min, let_max = np.min(energy), np.max(energy)
    let_range = let_max - let_min

    return [
        (0.5 * sigma_max, 10.0 * sigma_max),  # sigma_sat
        (0.0, let_min),                        # e_th
        (0.1, 10.0),                           # s
        (0.1, 2.0 * let_range)                 # w
    ]

def compute_initial_guess(energy, counts, fluence, bounds):
    """Compute reasonable initial parameter guess."""
    sigma_max = np.max((counts / fluence)[counts > 0])
    let_min = np.min(energy)
    let_range = np.max(energy) - let_min

    initial = np.array([sigma_max * 1.2, max(0, let_min - 1.0), 2.0, let_range / 3.0])
    for i, (low, high) in enumerate(bounds):
        initial[i] = np.clip(initial[i], low, high)
    return initial
```

## Three MLE Variants

Data characteristics determine which MLE variant produces reliable results. The decision tree from the series manifesto provides explicit selection criteria.

### Standard MLE (N >= 50)

When total event count exceeds 50, asymptotic normal theory provides valid Hessian-based uncertainty estimates. This threshold derives from Quinn 2014, which demonstrated that Poisson likelihoods require approximately 50 events for the Central Limit Theorem to ensure adequate normal approximation.

Standard MLE proceeds as:
1. Optimize the negative log-likelihood
2. Compute the Hessian matrix at the optimum
3. Invert the Hessian to obtain the covariance matrix
4. Extract standard errors as square roots of diagonal elements
5. Construct symmetric confidence intervals

The Hessian-based covariance is computationally efficient, requiring only a single optimization run plus Hessian evaluation.

### Small-Sample MLE (N < 50)

Below 50 total events, Hessian-based covariance estimates become unreliable. The normal approximation fails, and symmetric confidence intervals misrepresent true uncertainty.

Small-sample MLE modifies the approach:
1. Optimize the negative log-likelihood (same procedure)
2. Do not compute Hessian-based covariance
3. Defer uncertainty quantification to bootstrap methods

Point estimates remain valid from MLE. Only the covariance estimation changes.

The manifesto specifies the N=50 threshold as a hard boundary. Borderline cases (N = 48 vs N = 52) should not trigger analyst judgment about which method to apply.

### MLE With Zeros

When zero-event observations appear in the data, the likelihood formulation requires modification. Zero events provide upper-limit constraints rather than point measurements, as established by Quinn and Tompkins 2024.

The MLE-WithZeros variant:
1. Identify zero-event observations
2. Exclude zero-event points from the likelihood
3. Fit Weibull to non-zero observations only
4. Report upper limits separately using the 3.7/Phi rule
5. Verify fitted curve lies below upper limits

Including zeros in the standard likelihood biases the fit toward artificially low thresholds, as the optimizer attempts to reduce expected counts at zero-event LET values.

### Implementation

```python
from enum import Enum

class MLEVariant(Enum):
    STANDARD = "standard"
    SMALL_SAMPLE = "small_sample"
    WITH_ZEROS = "with_zeros"

def select_mle_variant(counts):
    """Select appropriate MLE variant based on data characteristics."""
    total_events = np.sum(counts)
    has_zeros = np.any(counts == 0)

    if has_zeros:
        return MLEVariant.WITH_ZEROS
    elif total_events >= 50:
        return MLEVariant.STANDARD
    else:
        return MLEVariant.SMALL_SAMPLE

def fit_weibull_with_variant(energy, counts, fluence):
    """Fit Weibull model using appropriate MLE variant."""
    variant = select_mle_variant(counts)

    if variant == MLEVariant.WITH_ZEROS:
        # Fit only to non-zero observations
        mask = counts > 0
        energy_fit, counts_fit, fluence_fit = energy[mask], counts[mask], fluence[mask]
        # Compute upper limits for zero observations (3.7/Phi rule)
        upper_limits = {float(energy[i]): 3.7/fluence[i]
                        for i in np.where(counts == 0)[0]}
    else:
        energy_fit, counts_fit, fluence_fit = energy, counts, fluence
        upper_limits = None

    params, opt_result = fit_weibull_mle(energy_fit, counts_fit, fluence_fit)

    # Compute covariance for standard variant only
    if variant == MLEVariant.STANDARD:
        covariance = compute_hessian_covariance(params, energy_fit, counts_fit, fluence_fit)
        standard_errors = np.sqrt(np.diag(covariance))
    else:
        covariance, standard_errors = None, None

    return params, variant, covariance, standard_errors, upper_limits
```

## Convergence Criteria and Failure Modes

Reliable MLE requires both successful optimization and verification that convergence criteria have been satisfied.

### Convergence Criteria

L-BFGS-B uses two convergence tests.

Function tolerance (ftol): The optimizer terminates when the relative change in objective function falls below ftol between iterations. A value of 1e-10 ensures high precision in the final objective value.

Gradient tolerance (gtol): The optimizer terminates when the maximum absolute gradient component falls below gtol. A value of 1e-8 ensures the optimum is a true stationary point.

Both criteria must be satisfied for reliable convergence. Setting overly loose tolerances (ftol = 1e-4) can terminate optimization prematurely at suboptimal points.

### Failure Modes

Several failure modes require detection and handling.

Maximum iterations reached: The optimizer exhausts its iteration budget without satisfying convergence criteria. This indicates either overly tight tolerances or a poorly-scaled problem. Increasing maxiter or rescaling parameters may resolve the issue.

Bound violations: Parameters may converge to bound values, indicating the optimal solution lies outside the feasible region. This suggests incorrect bounds or misspecified model.

Numerical issues: NaN or infinity values in the objective function indicate numerical instability. Common causes include log(0), division by zero, or exponential overflow.

Multiple local optima: The Weibull likelihood can have multiple local minima, particularly when threshold and saturation are poorly constrained. Multi-start optimization from different initial points can identify the global optimum.

### Detection Implementation

```python
def check_convergence(result, bounds):
    """Check optimization convergence and detect failure modes."""
    warnings = []
    converged = result.success

    # Check gradient norm
    if hasattr(result, 'jac') and result.jac is not None:
        grad_norm = np.max(np.abs(result.jac))
        if grad_norm > 1e-6:
            warnings.append(f"Large gradient: {grad_norm:.2e}")

    # Check for parameters at bounds
    param_names = ['sigma_sat', 'e_th', 's', 'w']
    for val, (low, high), name in zip(result.x, bounds, param_names):
        if np.isclose(val, low, rtol=1e-6) or np.isclose(val, high, rtol=1e-6):
            warnings.append(f"{name} at bound")

    return converged, result.nit, warnings
```

## Hessian-Based Covariance

When the normal approximation holds (N >= 50), the inverse of the Hessian matrix provides the parameter covariance matrix.

### Theoretical Foundation

At the maximum likelihood estimate, the observed Fisher information equals the negative Hessian of the log-likelihood:

```
I(theta_hat) = -H(theta_hat) = -d^2 log L / d theta d theta^T
```

Under regularity conditions satisfied by the Poisson-Weibull model, the MLE is asymptotically normal:

```
theta_hat ~ Normal(theta_true, I(theta_hat)^-1)
```

The covariance matrix is thus:

```
Cov(theta_hat) = I(theta_hat)^-1 = -H(theta_hat)^-1
```

Standard errors are square roots of diagonal elements.

### When Hessian Covariance Fails

The asymptotic approximation fails under several conditions.

Small sample size: Below N=50 total events, the Poisson likelihood curvature does not adequately represent parameter uncertainty. Hessian-based standard errors typically underestimate true uncertainty by 20-50%.

Parameters at bounds: When optimal parameters lie at constraint boundaries, the standard Hessian interpretation breaks down. Profiled or bootstrap confidence intervals are required.

Near-singular Hessian: When parameters are poorly identified (e.g., threshold near the minimum LET), the Hessian becomes ill-conditioned. Matrix inversion amplifies numerical errors, producing unreliable covariance estimates.

Non-quadratic likelihood: The normal approximation assumes the log-likelihood is approximately quadratic near the maximum. Strongly skewed likelihoods violate this assumption.

### Implementation

```python
from scipy.optimize import approx_fprime
from scipy.stats import norm

def compute_hessian_covariance(params, energy, counts, fluence, eps=1e-5):
    """Compute covariance matrix from Hessian inverse."""
    n_params = len(params)
    hessian = np.zeros((n_params, n_params))

    def nll(p):
        return poisson_neg_log_likelihood(p, energy, counts, fluence)

    for i in range(n_params):
        def grad_i(p):
            return approx_fprime(p, nll, eps)[i]
        hessian[i, :] = approx_fprime(params, grad_i, eps)

    hessian = 0.5 * (hessian + hessian.T)  # Symmetrize

    try:
        covariance = np.linalg.inv(hessian)
    except np.linalg.LinAlgError:
        covariance = np.linalg.pinv(hessian)

    if np.any(np.diag(covariance) < 0):
        raise ValueError("Hessian not positive definite; use bootstrap instead.")

    return covariance

def compute_confidence_intervals(params, standard_errors, confidence=0.95):
    """Compute symmetric confidence intervals from standard errors."""
    z = norm.ppf(1 - (1 - confidence) / 2)
    ci = np.column_stack([params - z * standard_errors,
                          params + z * standard_errors])
    return ci
```

## Complete Workflow Example

The following example demonstrates the complete MLE workflow.

```python
# Example test data
let_values = np.array([5.0, 10.0, 15.0, 20.0, 30.0, 40.0, 60.0, 80.0])
counts = np.array([3, 12, 28, 45, 62, 71, 78, 82])
fluence = np.array([1e7, 1e7, 1e7, 1e7, 1e7, 1e7, 1e7, 1e7])

# Select variant (N=381 > 50, so standard MLE applies)
variant = select_mle_variant(counts)  # Returns STANDARD

# Fit model with automatic bounds
params, opt_result = fit_weibull_mle(let_values, counts, fluence)
# params = [sigma_sat, LET_th, S, W]

# Compute covariance from Hessian (valid for N >= 50)
covariance = compute_hessian_covariance(params, let_values, counts, fluence)
standard_errors = np.sqrt(np.diag(covariance))

# 95% confidence intervals
ci = compute_confidence_intervals(params, standard_errors)
```

## Summary

Maximum likelihood estimation provides the correct statistical foundation for Weibull cross-section fitting. The Poisson likelihood properly handles count data, respecting its discrete, non-negative nature and asymmetric uncertainty.

Key implementation principles:

1. **Use Poisson, not Gaussian**: Least squares underestimates uncertainty for counts below 50.

2. **Constrain parameters physically**: Bounds prevent optimization from exploring unphysical regions.

3. **Select variant by data characteristics**: N >= 50 enables Hessian covariance; N < 50 requires bootstrap; zeros require exclusion.

4. **Verify convergence**: Check optimizer status, gradient norms, and boundary proximity.

5. **Know when Hessian fails**: Small samples, boundary solutions, and ill-conditioned Hessians require bootstrap alternatives.

The MLE point estimates remain valid regardless of sample size. Only the uncertainty quantification method changes based on the N=50 threshold established by Quinn 2014.

When Hessian-based covariance fails or N falls below 50, bootstrap methods provide reliable uncertainty estimates without asymptotic assumptions. The next post in this series details bootstrap implementation, iteration selection, and confidence interval construction.

## References

- Petersen, E. L., Pickel, J. C., Adams, J. H., & Smith, E. C. (1992). Rate prediction for single event effects - A critique. IEEE Transactions on Nuclear Science, 39(6), 1577-1599.

- Quinn, H. (2014). Challenges in testing complex systems. IEEE Transactions on Nuclear Science, 61(2), 766-786.

- Quinn, H., & Tompkins, P. (2024). Measuring zero: Neutron testing of modern digital electronics. IEEE Transactions on Nuclear Science, 71(4), 670-679.

- Adams, J. H. (1986). Cosmic ray effects on microelectronics, Part IV. Naval Research Laboratory Memorandum Report 5901.

- Zhu, C., Byrd, R. H., Lu, P., & Nocedal, J. (1997). Algorithm 778: L-BFGS-B: Fortran subroutines for large-scale bound-constrained optimization. ACM Transactions on Mathematical Software, 23(4), 550-560.

---

*This post is Part 1 of the SEU Cross-Section Analysis series.*

**Series Navigation:**
- Previous: [Rigorous SEU Cross-Section Analysis: A Methodological Manifesto](/seu-cross-section-manifesto-vibe-fitting)
- Next: [Bootstrap Methods for Small-Sample Uncertainty](/seu-cross-section-bootstrap) (Part 2)
