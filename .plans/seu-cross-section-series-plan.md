# Rigorous SEU Cross-Section Analysis: Blog Series Plan

## Series Overview

This 8-post blog series presents a methodological framework for reproducible SEU (Single Event Upset) cross-section analysis using the 4-parameter Weibull model. The series serves as a counter to "vibe fitting" - the common practice of manually adjusting curve parameters until they "look right" - advocating instead for automated, literature-grounded methods with explicit convergence criteria and fallback hierarchies.

**Target Audience**: Radiation effects engineers, reliability physicists, and test engineers who perform SEE characterization. Familiarity with basic statistics and radiation testing concepts assumed.

**Series Tagline**: "Science should be reproducible. Curve fitting shouldn't require intuition."

**Naming Convention**: Generic references to "the analysis framework" or "the methodology" - no proprietary tool names.

---

## Main Post: The Manifesto

**Title**: Rigorous SEU Cross-Section Analysis: A Methodological Manifesto Against Vibe Fitting

**Key Topics**:
- The reproducibility crisis in radiation test data analysis
- What "vibe fitting" is and why it persists
- Data sanity principles (generalizable, not schema-specific)
- The decision tree concept: automated method selection
- Literature foundations and why thresholds exist
- Series roadmap

**Prerequisites**: None (series introduction)

**Technical Depth**: Medium - conceptual with decision tree overview

**Estimated Length**: 2,500-3,000 words

**Key Elements**:
- Decision tree flowchart (ASCII or diagram description)
- Summary table of key thresholds with citations
- Links to all method posts

**Citations**:
- Quinn 2014 (IEEE TNS 61:2) - statistical foundations
- Quinn & Tompkins 2024 (IEEE TNS 71:4) - zero handling
- Petersen et al. 1992 (IEEE TNS 39:6) - Weibull model heritage

---

## Post 1: Maximum Likelihood Estimation for Weibull Fitting

**Title**: MLE for Weibull Cross-Sections: When Normal Approximations Hold

**Key Topics**:
- Poisson likelihood for count data
- The 4-parameter Weibull model (σ_sat, LET_th, S, W)
- L-BFGS-B constrained optimization
- Standard MLE (N ≥ 50): Hessian-based covariance valid
- Small-sample MLE (N < 50): defer covariance to bootstrap
- MLE with zeros: fit only non-zero data
- Convergence criteria and failure modes

**Prerequisites**: Main post

**Technical Depth**: High - mathematical foundations with implementation

**Estimated Length**: 3,000-3,500 words

**Key Elements**:
- Negative log-likelihood formulation
- Parameter bounds from physics
- Convergence diagnostics
- Code patterns (Python/SciPy)

**Citations**:
- Quinn 2014 (IEEE TNS 61:2, pp. 778-779) - N=50 threshold
- Petersen et al. 1992 - Weibull model definition
- CREME96 documentation - practical fitting guidance

---

## Post 2: Bootstrap Methods for Small-Sample Uncertainty

**Title**: Parametric Bootstrap for SEU Data: When MLE Covariance Fails

**Key Topics**:
- Why Hessian covariance fails for small samples
- Parametric Poisson resampling methodology
- Full bootstrap (N ≥ 50, min_count ≥ 5): 10,000 iterations
- Conservative bootstrap (N < 50 or sparse): 20,000 iterations
- Bootstrap covariance estimation
- Convergence diagnostics (success rate, distribution shape)
- Parallelization for computational efficiency

**Prerequisites**: Post 1 (MLE foundations)

**Technical Depth**: High - algorithm details with implementation

**Estimated Length**: 2,800-3,200 words

**Key Elements**:
- Resampling algorithm pseudocode
- Skewness checks for distribution validity
- Warm-start optimization pattern
- Parallel execution with joblib

**Citations**:
- Efron & Tibshirani 1993 - bootstrap methodology (Chapters 6, 13, 14)
- Quinn 2014 - small-sample considerations

---

## Post 3: Confidence Interval Selection: BCA vs Percentile

**Title**: Choosing Confidence Intervals: Second-Order Accuracy vs Robustness

**Key Topics**:
- Percentile method: simple, robust, works with zeros
- BCA (Bias-Corrected Accelerated): second-order accurate
- When to use each (decision threshold: N ≥ 50 and no zeros)
- Bias correction (z₀) computation and interpretation
- Acceleration (a) from jackknife
- Adjusted percentile calculation
- Coverage properties and validation

**Prerequisites**: Post 2 (bootstrap foundations)

**Technical Depth**: Medium-High - mathematical concepts with practical guidance

**Estimated Length**: 2,500-2,800 words

**Key Elements**:
- BCA formula breakdown
- Decision flowchart for CI method selection
- Interpretation of bias correction magnitude
- When BCA fails and percentile saves the day

**Citations**:
- Efron & Tibshirani 1993 (Chapter 14) - BCA intervals
- DiCiccio & Efron 1996 - bootstrap confidence intervals review

---

## Post 4: Zero-Event Data: Upper Limits Done Right

**Title**: When N=0: Proper Treatment of Zero-Event Observations

**Key Topics**:
- Why zeros cannot constrain Weibull parameters
- The 3.7/Φ upper limit rule (95% confidence)
- Derivation from Poisson statistics
- Excluding zeros from curve fitting
- Reporting upper limits alongside fitted curve
- Common mistakes: fitting zeros as data points
- Bayesian interpretation

**Prerequisites**: Main post

**Technical Depth**: Medium - conceptual with clear formulas

**Estimated Length**: 2,000-2,400 words

**Key Elements**:
- Upper limit calculation example
- Visualization: fitted curve with upper limit arrows
- Comparison: including vs excluding zeros
- Alternative confidence levels (90%, 99%)

**Citations**:
- Quinn & Tompkins 2024 (IEEE TNS 71:4, pp. 670-679) - "Measuring Zero"
- Gehrels 1986 - Poisson confidence limits
- Feldman & Cousins 1998 - unified approach to limits

---

## Post 5: Goodness-of-Fit: The Deviance Test

**Title**: Does the Weibull Fit? Deviance Testing for Model Adequacy

**Key Topics**:
- Deviance statistic for Poisson regression
- Degrees of freedom: n_points - 4
- When to run the test (DoF ≥ 3)
- Interpreting p-values (> 0.05 = adequate fit)
- Pearson residuals and residual analysis
- What to do when the test fails
- Limitations and caveats

**Prerequisites**: Post 1 (MLE foundations)

**Technical Depth**: Medium-High - statistical test with interpretation

**Estimated Length**: 2,400-2,800 words

**Key Elements**:
- Deviance formula and computation
- Residual plot interpretation
- Decision tree for test applicability
- Alternative: visual residual assessment when DoF < 3

**Citations**:
- McCullagh & Nelder 1989 - deviance in GLMs
- Agresti 2013 - categorical data analysis

---

## Post 6: Threshold LET and Saturation Cross-Section

**Title**: Derived Parameters: Physical Validation of Fitted Results

**Key Topics**:
- Threshold LET (LET_th): physical interpretation
- Saturation cross-section (σ_sat): asymptotic behavior
- Shape parameter (S): onset sharpness
- Width parameter (W): transition breadth
- Physical validity checks for each parameter
- Uncertainty propagation from bootstrap
- Typical ranges by technology node
- When parameters indicate fitting problems

**Prerequisites**: Posts 1-2 (fitting and uncertainty)

**Technical Depth**: Medium - physical interpretation with validation criteria

**Estimated Length**: 2,600-3,000 words

**Key Elements**:
- Parameter interpretation table
- Validation checklist with pass/fail criteria
- Typical ranges by technology (advanced, mid-range, hardened)
- Red flags indicating poor fits

**Citations**:
- Petersen et al. 1992, 2005 - Weibull parameter interpretation
- JEDEC JESD89A - test method standards

---

## Post 7: Automated Validation and Reproducible Reporting

**Title**: From Data to Defensible Results: Automated Validation Pipelines

**Key Topics**:
- Pre-analysis validation checks (5 checks)
  - Overdispersion (φ ≤ 1.5)
  - Zero-inflation (< 20% excess)
  - Sample size adequacy (n/p ≥ 10)
  - Count threshold (λ̄ ≥ 0.1)
  - Independence assumption
- Post-fit validation checks
- Status indicators: PASS / WARNING / FAIL
- What makes results defensible in peer review
- Reproducibility requirements
- Report generation patterns

**Prerequisites**: All previous posts

**Technical Depth**: Medium - practical implementation focus

**Estimated Length**: 2,800-3,200 words

**Key Elements**:
- Validation summary template
- Status indicator decision logic
- Checklist for publication-ready results
- Example validation report output

**Citations**:
- Harrell 2015, Peduzzi 1996 - sample size requirements
- Cameron & Trivedi 2013 - overdispersion diagnostics

---

## Series Cross-References

| Post | Links To | Links From |
|------|----------|------------|
| Main | 1-7 | All |
| 1 (MLE) | 2, 5, 6 | Main |
| 2 (Bootstrap) | 3, 6 | 1 |
| 3 (CI Methods) | 6 | 2 |
| 4 (Zeros) | 1, 6 | Main |
| 5 (Deviance) | 6, 7 | 1 |
| 6 (Parameters) | 7 | 1, 2, 3, 4, 5 |
| 7 (Validation) | - | All |

---

## Key Thresholds Summary Table

| Decision | Threshold | Source |
|----------|-----------|--------|
| MLE covariance validity | N ≥ 50 | Quinn 2014 |
| Bootstrap variant | N ≥ 50 AND min_count ≥ 5 | Efron & Tibshirani |
| CI method (BCA vs Percentile) | N ≥ 50 AND no zeros | Efron & Tibshirani |
| Zero handling | 3.7/Φ upper limit | Quinn & Tompkins 2024 |
| Deviance test applicability | DoF ≥ 3 | McCullagh & Nelder |
| Overdispersion | φ ≤ 1.5 | Cameron & Trivedi |
| Zero-inflation | < 20% excess | ZIP literature |
| Sample size | n/p ≥ 10 | Harrell, Peduzzi |
| Count threshold | λ̄ ≥ 0.1 | Poisson theory |

---

## Content Guidelines

### What to Include
- Decision criteria with explicit thresholds
- Literature citations (IEEE TNS preferred)
- Algorithm descriptions and pseudocode
- Validation criteria and pass/fail logic
- Physical interpretation of parameters
- Common pitfalls and how to avoid them

### What to Exclude
- Proprietary tool names or branding
- Specific device test data
- Internal process details
- Schema-specific implementation details

### Code Examples
- Use Python with NumPy/SciPy
- Generic variable names
- Include error handling patterns
- Show key algorithmic steps

### Citation Style
- Inline: Author Year format (e.g., "Quinn 2014")
- Full reference at post end
- Link to DOI where available

---

## Publishing Schedule (Suggested)

| Post | Suggested Publish Week |
|------|----------------------|
| Main (Manifesto) | Week 1 |
| 1 (MLE) | Week 2 |
| 2 (Bootstrap) | Week 3 |
| 3 (CI Methods) | Week 4 |
| 4 (Zeros) | Week 5 |
| 5 (Deviance) | Week 6 |
| 6 (Parameters) | Week 7 |
| 7 (Validation) | Week 8 |

---

## Relationship to Existing Content

This series builds upon and references:
- **Naive Weibull Curve Fit** (2027-01-10): Introductory post, serves as Part 1 of SEU series
- **Cache March Test** (pending PA): Complements with detection methodology

The manifesto post should reference the naive Weibull post as "an introduction to the model itself" while this series focuses on "rigorous methodology for applying it."

---

## Notes

- Each post should stand alone but link to related posts
- Decision trees should be consistent across all posts
- Threshold values must match exactly across series
- Citations should use consistent formatting (not LaTeX)
- Code examples should be runnable snippets
