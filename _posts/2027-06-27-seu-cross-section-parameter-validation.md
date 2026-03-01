---
title: "Derived Parameters: Physical Validation of Fitted Results"
date: 2027-06-27
categories: [Radiation Effects, Statistical Methods]
tags: [seu, weibull, parameters, validation, threshold-let, cross-section]
series: seu-cross-section-analysis
series_order: 6
---

Curve fitting produces numbers. Physical validation determines whether those numbers represent reality. A mathematically optimal fit can yield parameters that violate physical constraints, exceed reasonable ranges, or indicate numerical pathology. This post establishes systematic validation criteria for the four Weibull parameters, identifies warning signs of fitting problems, and connects parameter quality to rate prediction reliability.

The validation framework applies regardless of fitting methodology. Whether parameters emerge from maximum likelihood estimation, weighted least squares, or manual adjustment, the same physical constraints and typical ranges apply. The goal is catching problems before invalid parameters propagate into mission-critical rate predictions.

## Physical Foundation of the Weibull Model

The 4-parameter Weibull function captures charge collection physics in microelectronic devices:

```
sigma(LET) = 0                                         for LET <= LET_th
sigma(LET) = sigma_sat * [1 - exp(-((LET - LET_th)/W)^S)]   for LET > LET_th
```

Each parameter carries specific physical meaning tied to device characteristics. Understanding this meaning enables validation beyond mere numerical reasonableness.

**Saturation cross-section (sigma_sat)** represents the total sensitive area of the device. When particle LET becomes sufficiently high, every sensitive volume responds to every incident particle. The cross-section saturates at this geometric limit.

**Threshold LET (LET_th)** marks the minimum energy deposition required to upset any sensitive volume in the device. Below this threshold, deposited charge fails to exceed the critical charge of even the most sensitive cell.

**Shape parameter (S)** controls onset sharpness. The shape reflects how tightly the critical charge distribution clusters across sensitive volumes. Homogeneous devices exhibit sharp turn-ons; devices with variable sensitive volumes show gradual transitions.

**Width parameter (W)** determines the LET range over which transition from threshold to saturation occurs. This parameter interacts strongly with shape to define the turn-on characteristic.

## Saturation Cross-Section Validation

### Physical Meaning

The saturation cross-section equals the effective sensitive area of the device when all sensitive volumes respond to incident radiation. For a memory device, this corresponds roughly to the sum of all bit cell sensitive areas. For logic devices, the interpretation becomes more complex but the principle remains: sigma_sat represents maximum possible cross-section.

### Validation Criteria

**Must be positive**: Cross-section cannot be negative. A negative sigma_sat indicates optimization failure or bound violation. This represents a hard failure requiring investigation.

**Must exceed maximum measured cross-section**: The fitted saturation value must be at least as large as the largest observed cross-section in the test data. If any measurement exceeds the fitted sigma_sat, the model fails to describe the data adequately.

The mathematical relationship requires:

```
sigma_sat >= max(N_i / Phi_i) for all i
```

where N_i represents observed counts and Phi_i represents fluence at each LET point.

**Should lie within device-plausible range**: Saturation cross-sections span many orders of magnitude depending on device type, technology node, and sensitive area. Typical ranges by device category:

| Device Type | Typical sigma_sat Range | Notes |
|-------------|-------------------------|-------|
| SRAM, DRAM | 10^-8 to 10^-5 cm^2/device | Scales with bit count |
| Flip-flops, latches | 10^-10 to 10^-7 cm^2/device | Depends on cell count |
| Combinational logic | 10^-10 to 10^-6 cm^2/device | Transient sensitive |
| ADCs, DACs | 10^-9 to 10^-6 cm^2/device | Analog sensitive regions |
| Microprocessors | 10^-6 to 10^-3 cm^2/device | Aggregate of many mechanisms |

Values outside these ranges by more than two orders of magnitude warrant investigation. Extremely large sigma_sat may indicate units confusion or data entry errors. Extremely small values may suggest improper device biasing during testing.

### Red Flags

- sigma_sat at lower optimization bound: The optimizer wants a smaller value than physics allows
- sigma_sat at upper optimization bound: Data suggests larger cross-section than the bound permits
- sigma_sat < max(measured): Mathematical impossibility indicating fit failure
- sigma_sat more than 10x larger than max(measured): Poorly constrained parameter, insufficient high-LET data

## Threshold LET Validation

### Physical Meaning

The threshold LET represents the minimum linear energy transfer required to cause any upset in the device. This threshold emerges from the critical charge requirements of sensitive volumes. Below LET_th, even optimal particle strikes fail to deposit sufficient charge for upset.

For heavy-ion testing, LET_th typically reflects the most sensitive cell in the device. Device hardening efforts specifically target raising this threshold through design techniques such as increased node capacitance, resistive decoupling, or redundancy.

### Validation Criteria

**Must be non-negative**: Negative LET has no physical meaning. A fitted negative threshold indicates either optimization failure or an attempt to model behavior that does not match the Weibull functional form.

**Must be less than minimum tested LET**: If the fitted threshold exceeds the lowest LET tested, the model predicts zero events at all tested conditions, contradicting observations. The constraint requires:

```
LET_th < min(LET_tested)
```

This constraint applies only when events were observed at the minimum LET. If the lowest LET point yielded zero events, the threshold may equal or exceed that LET value.

**Should match technology expectations**: Different technology nodes exhibit characteristic threshold ranges based on feature size and design rules:

| Technology Node | Typical LET_th Range | Comments |
|-----------------|---------------------|----------|
| Advanced (< 28 nm) | 0.1 - 5 MeV-cm^2/mg | Extreme sensitivity at small features |
| Mid-range (28-65 nm) | 5 - 20 MeV-cm^2/mg | Standard commercial parts |
| Mature (90-180 nm) | 10 - 40 MeV-cm^2/mg | Larger features, higher Qcrit |
| Rad-hard (> 65 nm) | 20 - 100+ MeV-cm^2/mg | Deliberate hardening techniques |

These ranges represent typical values from published test data. Individual devices may fall outside these ranges based on specific design choices. However, values dramatically outside expectations warrant scrutiny.

### Red Flags

- LET_th < 0: Physical impossibility
- LET_th = 0 exactly: May indicate parameter at bound rather than true value
- LET_th > min(LET) when events observed at min(LET): Model-data inconsistency
- LET_th inconsistent with technology node: Possible device mislabeling or test error

## Shape Parameter Validation

### Physical Meaning

The shape parameter S controls how abruptly cross-section transitions from threshold to saturation. This sharpness reflects the distribution of critical charges across sensitive volumes in the device.

**S < 1 (gradual onset)**: The device contains sensitive volumes with widely varying critical charges. Some cells upset easily while others require much higher LET. Multiple upset mechanisms may contribute at different thresholds.

**S approximately 1-2 (typical)**: A relatively uniform distribution of sensitive volumes exists. Critical charge varies modestly across the device. This range characterizes most commercial memory devices.

**S > 3 (sharp onset)**: All sensitive volumes have nearly identical critical charge. The device transitions rapidly from immune to saturated. Sharp turn-ons occur in well-controlled, uniform designs.

### Validation Criteria

**Typical range: 0.5 to 5**: Most physically realistic cross-section curves fall within this range. Values outside this range deserve investigation rather than automatic rejection.

**Interpretation by range**:

| S Value | Physical Interpretation | Common Causes |
|---------|------------------------|---------------|
| S < 0.5 | Extremely gradual onset | Multiple mechanisms, possible model mismatch |
| 0.5 - 1.0 | Gradual onset | Variable sensitive volumes, dose enhancement |
| 1.0 - 2.0 | Typical single mechanism | Normal device behavior |
| 2.0 - 3.0 | Sharp onset | Uniform critical charge distribution |
| S > 3.0 | Very sharp onset | Possible overfitting, may indicate W problems |

### S and W Interaction

The shape and width parameters interact strongly. A high S value concentrates the transition in a narrow LET band, while the W value scales that band's width. When S becomes very large (> 5), the model approaches a step function regardless of W. This limiting behavior can cause numerical instability and identifiability problems.

For the combination of parameters:
- If S is large and W is small, the model predicts an extremely sharp step
- If S is large and W is also large, the parameters may be compensating for each other
- Parameter correlation often exceeds 0.8 between S and W, indicating joint rather than individual identifiability

### Red Flags

- S < 0.3: Approaching exponential rather than Weibull behavior
- S > 5: Possible overfitting to noise; step-function limit
- S at optimization bound: Parameter not properly constrained by data
- S uncertainty spanning more than factor of 3: Poorly identified parameter

## Width Parameter Validation

### Physical Meaning

The width parameter W determines the LET range over which cross-section transitions from threshold to saturation. Combined with the shape parameter, W defines the turn-on characteristic's horizontal scale.

Physically, W relates to the spread of critical charges across sensitive volumes. A narrow width indicates uniform critical charge; a wide width suggests substantial variation or multiple mechanisms contributing at different LET values.

### Validation Criteria

**Should be comparable to tested LET range**: The width parameter ought to relate meaningfully to the LET values actually measured. If W dramatically exceeds the tested range, the parameter is poorly constrained by available data.

Define the tested LET range as:

```
LET_range = max(LET) - min(LET)
```

The following criteria apply:

| W / LET_range | Interpretation |
|---------------|----------------|
| 0.1 - 1.0 | Well-constrained, transition occurs within tested range |
| 1.0 - 3.0 | Acceptable, transition extends somewhat beyond data |
| 3.0 - 5.0 | Marginal, width extrapolates significantly beyond data |
| > 5.0 | Poorly constrained, consider fixing W or collecting more data |

**Warning threshold**: W > 5 x (max_LET - min_LET) indicates the fitted transition extends far beyond the measured LET range. Such extrapolation lacks empirical support.

### Red Flags

- W at lower bound: Optimizer pushed toward step function
- W at upper bound: Data does not constrain transition width
- W >> LET_range: Extrapolation beyond data support
- W ~ 0: Numerical instability, step-function collapse

## Uncertainty Propagation from Bootstrap

Bootstrap resampling produces distributions for each parameter rather than point estimates. These distributions enable uncertainty quantification and identification of fitting problems.

### Interpreting Bootstrap Distributions

For well-behaved fits, bootstrap parameter distributions exhibit approximate symmetry, a single mode corresponding to the MLE estimate, and widths consistent with data information content. Problematic distributions indicate fitting issues: bimodal distributions suggest overparameterization or competing mechanisms; extreme skewness indicates parameters near physical boundaries; heavy tails suggest individual data points with excessive leverage.

### Asymmetric Confidence Intervals

Bootstrap percentile intervals naturally accommodate asymmetry. Large lower uncertainty indicates data consistent with smaller parameter values; large upper uncertainty indicates data consistent with larger values. Asymmetry factors exceeding 3:1 warrant flagging as the Gaussian approximation fails.

### Covariance and Correlation

Bootstrap samples enable covariance matrix estimation from the empirical distribution. Parameter correlations reveal identifiability issues:

| Correlation | Interpretation |
|-------------|----------------|
| |rho| < 0.3 | Parameters essentially independent |
| 0.3 <= |rho| < 0.7 | Moderate correlation, acceptable |
| 0.7 <= |rho| < 0.9 | Strong correlation, interpret jointly |
| |rho| >= 0.9 | Near-perfect correlation, identifiability problem |

Common high correlations: S and W (typically 0.6-0.9, both control turn-on shape); LET_th and W (moderate correlation when threshold poorly constrained); sigma_sat and S (correlate when saturation not reached in data).

## Red Flags Summary: Fitting Problems

### Parameters at Bounds

When any parameter equals its optimization bound, the optimizer was constrained from reaching its preferred value. This indicates either physically appropriate behavior (bound prevents non-physical solutions), bounds that are too restrictive, or data-model mismatch. Investigation proceeds by examining whether the bound reflects physics, relaxing bounds by factor of 2 and refitting, and investigating data quality if the parameter moves to the new bound.

### Extreme Values Outside Typical Ranges

| Parameter | Extreme Low | Extreme High |
|-----------|-------------|--------------|
| sigma_sat | < 10^-12 cm^2 | > 10^-2 cm^2 |
| LET_th | < 0 | > 200 MeV-cm^2/mg |
| S | < 0.3 | > 7 |
| W | < 0.01 | > 100 |

Extreme values are not automatically wrong. However, extreme parameters demand independent verification of raw data, confirmation of device identification, check for units conversion errors, and physical explanation consistent with device design.

### Large Asymmetric Uncertainties and High Correlations

Asymmetry factors exceeding 3:1 between lower and upper confidence interval bounds warrant flagging. Such asymmetry indicates the Gaussian approximation fails, possibly due to insufficient data, strong nonlinearity in the likelihood surface, or potential for multimodal solutions.

Correlations exceeding 0.9 in absolute value indicate parameters are not independently identifiable. Response options include reporting correlated parameters jointly, fixing one parameter to a literature value, collecting additional data at LET values that break the degeneracy, or accepting wider combined uncertainty.

## Comprehensive Validation Checklist

The following table provides pass/warning/fail criteria for systematic parameter validation:

| Parameter | Criterion | Pass | Warning | Fail |
|-----------|-----------|------|---------|------|
| sigma_sat | Positivity | > 0 | - | <= 0 |
| sigma_sat | Exceeds max measured | >= max(sigma_obs) | < 1.1 x max(sigma_obs) | < max(sigma_obs) |
| sigma_sat | Plausible range | 10^-10 to 10^-4 cm^2 | Within 2 orders of bounds | Outside by > 2 orders |
| sigma_sat | Not at bound | Interior solution | Within 1% of bound | Exactly at bound |
| LET_th | Non-negative | >= 0 | = 0 exactly | < 0 |
| LET_th | Below min tested | < min(LET) | Within 10% of min(LET) | >= min(LET) with events |
| LET_th | Technology range | Within expected range | Within 2x expected | > 5x expected |
| LET_th | Not at bound | Interior solution | Within 1% of bound | Exactly at bound |
| S | Typical range | 0.5 to 3.0 | 0.3 to 5.0 | < 0.3 or > 7 |
| S | Not at bound | Interior solution | Within 1% of bound | Exactly at bound |
| S | Uncertainty width | < 2x point estimate | 2x to 4x | > 4x |
| W | Proportional to range | 0.1 to 2.0 x LET_range | 2.0 to 5.0 x LET_range | > 5 x LET_range |
| W | Not at bound | Interior solution | Within 1% of bound | Exactly at bound |
| Correlation | S-W correlation | |rho| < 0.7 | 0.7 to 0.9 | > 0.9 |
| Bootstrap | Success rate | > 95% | 90% to 95% | < 90% |
| Bootstrap | Unimodal | Single clear mode | Some bimodality | Clearly bimodal |

## Rate Prediction Implications

Weibull parameters directly determine Single Event Upset rate predictions through numerical integration against the space radiation environment. Parameter quality propagates to rate reliability.

### Rate Sensitivity to Each Parameter

**sigma_sat**: Rate scales linearly with saturation cross-section at high LET. Errors in sigma_sat translate directly to proportional rate errors. A factor-of-2 error in sigma_sat produces a factor-of-2 error in the GCR rate contribution from high-LET particles.

**LET_th**: The threshold determines which portion of the particle spectrum contributes to upset rate. Lowering LET_th by even 1-2 MeV-cm^2/mg can dramatically increase predicted rates due to the steep slope of the GCR integral LET spectrum.

Rate sensitivity approximation for threshold:

```
d(Rate)/d(LET_th) proportional to -Phi_integral(LET_th) * sigma_sat
```

where Phi_integral represents the integral particle flux above threshold. Since flux increases steeply at lower LET, threshold errors dominate rate uncertainty.

**S and W**: Shape and width determine how cross-section transitions across the LET spectrum. Their combined effect influences rate through the turn-on region where flux is substantial but cross-section is not yet saturated.

### Uncertainty Propagation to Rates

Monte Carlo rate calculation using bootstrap parameter samples provides rate uncertainty. Sample parameter sets from the bootstrap distribution, compute rate for each, repeat 1000+ times, and extract percentiles. This approach captures non-Gaussian rate distributions, parameter correlation effects, and nonlinear rate sensitivity.

Mission applications often require bounding rates rather than best estimates. Parameter uncertainty enables best estimate (median parameters), 90% upper bound (95th percentile rate), and 95% upper bound (97.5th percentile rate). Poorly constrained parameters produce large gaps between best estimate and upper bound, reflecting genuine prediction uncertainty.

## Practical Validation Workflow

A systematic validation workflow proceeds through six steps: (1) numerical checks for positivity and bound violations; (2) physical constraint verification ensuring sigma_sat exceeds measured values and LET_th falls below minimum tested LET; (3) reasonableness assessment comparing to technology-typical ranges; (4) uncertainty quality evaluation including bootstrap success rate and correlation magnitudes; (5) rate impact evaluation propagating uncertainty to predictions; and (6) documentation of all validation results for downstream analysts.

This validation framework builds on foundations established earlier in the series. The MLE methods from Posts 1-2 provide parameter estimates requiring validation. Bootstrap methods from Post 3 generate distributions enabling uncertainty assessment. Confidence interval selection from Post 4 determines which intervals apply. Zero-event treatment from Post 5 establishes which data points enter the fit. Validation completes the pipeline by determining whether fitted parameters deserve confidence.

## References

- Petersen, E. L., Pickel, J. C., Adams, J. H., & Smith, E. C. (1992). Rate prediction for single event effects - A critique. IEEE Transactions on Nuclear Science, 39(6), 1577-1599.

- Petersen, E. L. (2005). The relationship of proton and heavy ion upset thresholds. IEEE Transactions on Nuclear Science, 52(6), 2695-2701.

- JEDEC Standard JESD89A. (2006). Measurement and Reporting of Alpha Particle and Terrestrial Cosmic Ray-Induced Soft Errors in Semiconductor Devices. JEDEC Solid State Technology Association.

- Quinn, H. (2014). Challenges in testing complex systems. IEEE Transactions on Nuclear Science, 61(2), 766-786.

- Efron, B., & Tibshirani, R. J. (1993). An Introduction to the Bootstrap. Chapman and Hall/CRC.

---

*This post is Part 6 of the SEU Cross-Section Analysis series.*

**Series Navigation:**

- Part 0: [Rigorous SEU Cross-Section Analysis: A Methodological Manifesto](/2027/05/16/seu-cross-section-manifesto-vibe-fitting)
- Part 1: MLE for Weibull Cross-Sections
- Part 2: Bootstrap Methods for Small-Sample Uncertainty
- Part 3: Confidence Interval Selection
- Part 4: Zero-Event Data Treatment
- Part 5: Goodness-of-Fit Testing
- **Part 6: Derived Parameter Validation** (this post)
- Part 7: Automated Validation Pipelines
