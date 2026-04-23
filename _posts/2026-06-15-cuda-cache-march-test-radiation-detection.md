---
title: "Cache March Test: A CUDA/CPU Framework for Radiation-Induced Memory Error Detection"
date: 2026-06-15
categories: [Embedded Systems, Radiation Testing]
tags: [cuda, radiation, seu, set, gpu, arm, hpc, reliability, aerospace]
---

Space-grade and high-performance computing systems face a fundamental reliability challenge: energetic particles passing through silicon can corrupt data stored in memory cells. The Cache March Test framework provides systematic detection and classification of these Single Event Effects (SEE) through repeated read/write verification cycles on both CPU and GPU architectures.

## Problem Statement

Modern processors operate at voltage levels where a single ionizing particle can deposit sufficient charge to flip a bit in an SRAM cell. In terrestrial environments, this radiation originates primarily from secondary neutrons produced by cosmic ray interactions in the atmosphere. In space, direct exposure to solar protons, galactic cosmic rays, and trapped radiation belts dramatically increases the event rate.

The consequences of undetected memory corruption range from silent data corruption (SDC) to system crashes. For safety-critical applications in aerospace, automotive, and high-performance computing, quantifying and characterizing these error rates under controlled radiation exposure enables:

- Selection of appropriate error mitigation strategies (ECC, TMR, scrubbing)
- Qualification of COTS (commercial off-the-shelf) components for radiation environments
- Validation of fault-tolerant software architectures
- Development of cross-section data for radiation transport simulations

Beam testing at particle accelerator facilities provides the controlled radiation environment necessary for systematic characterization. The Cache March Test framework instruments CPU and GPU memory to detect, classify, and localize errors during these exposures.

## Technical Background

### Single Event Effects Taxonomy

Radiation-induced memory errors fall into two primary categories based on their persistence:

**Single Event Upset (SEU)**: A stable bit flip caused by charge collection in an SRAM cell. The corrupted value persists until explicitly overwritten. SEUs represent actual memory cell corruption and are the primary concern for data integrity.

**Single Event Transient (SET)**: A momentary voltage glitch on combinational logic or sense amplifier circuitry that can cause an incorrect value to be latched during a read operation. The underlying memory cell remains uncorrupted; subsequent reads return the correct value.

Distinguishing between SEU and SET is essential for accurate cross-section measurements. An SET incorrectly classified as an SEU would overestimate the actual memory cell vulnerability while underestimating timing-sensitive combinational logic susceptibility.

### March Test Algorithms

March tests constitute a class of memory test algorithms that traverse memory in a specific pattern while writing and reading predetermined data patterns. The "march" refers to the sequential addressing from address 0 to n (ascending) or n to 0 (descending).

A classical March C- algorithm consists of:

```
M0: ↑ (w0)         Write 0 to all locations, ascending
M1: ↑ (r0, w1)     Read 0, write 1, ascending
M2: ↑ (r1, w0)     Read 1, write 0, ascending
M3: ↓ (r0, w1)     Read 0, write 1, descending
M4: ↓ (r1, w0)     Read 1, write 0, descending
M5: ↑ (r0)         Read 0, ascending
```

The alternating traversal directions and complementary patterns provide detection coverage for stuck-at faults, transition faults, coupling faults, and address decoder faults.

The Cache March Test framework implements a four-pattern march sequence:

| Pass | Pattern | Hex Value (64-bit) | Purpose |
|------|---------|-------------------|---------|
| 1 | All zeros | `0x0000000000000000` | Baseline, detects stuck-at-1 |
| 2 | All ones | `0xFFFFFFFFFFFFFFFF` | Detects stuck-at-0 |
| 3 | Alternating 10 | `0xAAAAAAAAAAAAAAAA` | Exercises bit transitions |
| 4 | Alternating 01 | `0x5555555555555555` | Complementary transitions |

This pattern set ensures every bit position experiences both 0-to-1 and 1-to-0 transitions while providing distinguishable expected values for error detection.

### Cache Hierarchy and Test Array Sizing

The test array size is calibrated to exercise specific cache levels. For GPU testing, the array is sized to match the L2 cache capacity:

```c
ctx->numArrayElements = dp.l2CacheSize / ctx->typeSize;
```

This sizing strategy ensures:
- Working set exceeds L1 cache, forcing L2 utilization
- Full L2 capacity is exercised, maximizing coverage
- Memory access patterns stress cache controller logic

For CPU testing, similar sizing targets the L2 cache (typically 1 MB per core for modern ARM Cortex-A series):

```c
#define L2_SIZE (1024 * 1024)
```

## Architecture Overview

The framework comprises three primary components: a CPU test module, CUDA kernels for GPU testing, and a verification framework for validating detection logic.

### CPU Module

The CPU implementation (`cpu_cache_test.c`) provides single-threaded and OpenMP-parallelized testing modes. Each thread maintains a private test array allocated on the stack to ensure cache residency:

```c
#ifdef _OPENMP
#pragma omp parallel
{
#endif
    uint64_t local_array[num_elements];
    for (long unsigned int i = 0; i < num_elements; i++) {
        local_array[i] = INITIAL;
    }

    while (keep_running) {
        executeTestPass(local_array, num_elements);
    }
#ifdef _OPENMP
}
#endif
```

Stack allocation provides two advantages over heap allocation:
- Guaranteed cache-line alignment on most platforms
- Automatic deallocation on thread exit without explicit free

The core verification function performs bidirectional traversal with direction-dependent march addressing:

```c
void checkAndSetArray(uint64_t *array, unsigned long numElements,
                      uint64_t setValue, uint64_t matchValue,
                      LocalCounters *local, bool direction)
{
    for (unsigned long i = direction ? 0 : numElements - 1;
         direction ? (i < numElements) : 1;
         i += direction ? 1 : -1)
    {
        volatile uint64_t *src = &array[i];
        read.val1 = *src;
        read.val2 = *src;

        if (read.val1 != matchValue || read.val2 != matchValue) {
            // Error classification logic
        }
        array[i] = setValue;
        if (!direction && i == 0) break;
    }
}
```

### CUDA Kernels

<div id="cuda-grid-container" style="float: right; margin: 0 0 15px 20px; width: 180px; height: 180px; position: relative;">
<canvas id="cuda-pulsing-grid" width="180" height="180" style="background: transparent;"></canvas>
</div>
<script src="/assets/js/pulsing-grid.js"></script>

GPU testing requires distinct write and verify kernels to accommodate the SIMT execution model. The check kernel (`checkArrayKernel`) implements the double-read detection strategy:

```cuda
__global__ void checkArrayKernel(cudaTestContext *ctx, TEST_TYPE matchValue)
{
    __shared__ unsigned int smid;
    __shared__ bool processBlock;
    __shared__ TEST_TYPE s_test_errors;
    __shared__ TEST_TYPE s_seu_errors;
    __shared__ TEST_TYPE s_set_errors;

    if (threadIdx.x == 0) {
        asm("mov.u32 %0, %smid;" : "=r"(smid));
        // SM work distribution logic
    }
    __syncthreads();

    for (unsigned int idx = threadIdx.x;
         idx < ctx->numArrayElements;
         idx += ctx->threadsPerBlock)
    {
        volatile TEST_TYPE *src = &ctx->array[idx];
        TEST_TYPE val1 = *src;
        TEST_TYPE val2 = *src;

        TEST_TYPE bits = val1 ^ matchValue;
        TEST_TYPE bits0 = val2 ^ matchValue;

        // Classification and counting
    }
}
```

Key design decisions include:

**Volatile pointers**: The `volatile` qualifier on the source pointer forces the compiler to issue two distinct memory load instructions rather than reusing a cached register value. This is essential for SET detection.

**Shared memory counters**: Error counts accumulate in shared memory first, then flush to global memory once per block. This reduces global atomic contention during high-error events.

**Block-stride loop**: Each block processes the entire array rather than a partitioned subset. Combined with the SM work map, this ensures uniform coverage regardless of block scheduling order.

### Verification Framework

The verification module (`cuda_verify.cu`) provides deterministic fault injection to validate detection logic before beam testing:

```c
VerifyTestResult testSingleBitSEU(cudaTestContext* ctx,
                                  size_t position,
                                  unsigned int bit_position)
{
    resetTestArray(ctx, INITIAL);
    resetErrorCounters(ctx);

    // Inject single-bit fault
    TEST_TYPE fault_mask = (TEST_TYPE)1 << bit_position;
    ctx->array[position] ^= fault_mask;

    checkArrayKernel<<<VERIFY_NUM_BLOCKS, ctx->threadsPerBlock>>>(ctx, INITIAL);
    cudaDeviceSynchronize();

    readErrorCounters(ctx, &result.actual_seu, &result.actual_set, &result.actual_total);

    // Validate expected: 1 error location, 1 SEU bit, 0 SET bits
}
```

The test suite includes:
- Single-bit SEU detection at various positions
- Multi-bit SEU detection (consecutive and distributed bits)
- Boundary condition testing (first element, last element, warp boundaries)
- Pattern verification (each march pass pattern)
- False positive verification (clean memory should produce zero errors)

## Double-Read Detection Algorithm

The double-read mechanism provides temporal discrimination between persistent and transient errors:

```
┌─────────────────────────────────────────────────────────────┐
│                  Double-Read Detection Flow                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│    Write Pattern P to Memory Location L                     │
│                    │                                        │
│                    ▼                                        │
│    ┌──────────────────────────────┐                        │
│    │  First Read: val1 = *L       │                        │
│    └──────────────────────────────┘                        │
│                    │                                        │
│                    ▼                                        │
│    ┌──────────────────────────────┐                        │
│    │  Second Read: val2 = *L      │                        │
│    └──────────────────────────────┘                        │
│                    │                                        │
│                    ▼                                        │
│    ┌──────────────────────────────┐                        │
│    │  Compute: bits1 = val1 XOR P │                        │
│    │  Compute: bits2 = val2 XOR P │                        │
│    └──────────────────────────────┘                        │
│                    │                                        │
│         ┌─────────┴─────────┐                              │
│         ▼                   ▼                              │
│  ┌─────────────┐    ┌─────────────┐                        │
│  │ bits1 == 0  │    │ bits1 != 0  │                        │
│  │ AND         │    │ OR          │                        │
│  │ bits2 == 0  │    │ bits2 != 0  │                        │
│  └──────┬──────┘    └──────┬──────┘                        │
│         │                  │                               │
│         ▼                  ▼                               │
│   ┌──────────┐    ┌───────────────────┐                    │
│   │ No Error │    │ Error Detected    │                    │
│   └──────────┘    └─────────┬─────────┘                    │
│                             │                               │
│                  ┌──────────┴──────────┐                   │
│                  ▼                     ▼                   │
│           ┌───────────┐         ┌───────────┐              │
│           │bits1==bits2│        │bits1!=bits2│              │
│           └─────┬─────┘         └─────┬─────┘              │
│                 │                     │                    │
│                 ▼                     ▼                    │
│        ┌────────────────┐   ┌────────────────┐             │
│        │     SEU        │   │     SET        │             │
│        │ Persistent     │   │ Transient      │             │
│        │ Memory Error   │   │ Read Glitch    │             │
│        └────────────────┘   └────────────────┘             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

The classification logic:

```c
TEST_TYPE bits = val1 ^ matchValue;   // Corruption pattern, read 1
TEST_TYPE bits0 = val2 ^ matchValue;  // Corruption pattern, read 2

if (diff || diff2) {
    atomicAdd(&s_test_errors, (TEST_TYPE)1);

    if (bits == bits0) {
        // SEU: Same corruption in both reads = persistent cell flip
        atomicAdd(&s_seu_errors, (TEST_TYPE)diff);
    } else {
        // SET: Different corruption patterns = transient disturbance
        atomicAdd(&s_set_errors, (TEST_TYPE)diff2);
    }
}
```

Critical implementation details:

1. **XOR comparison**: The XOR operation produces a bitmask where each set bit indicates a position that differs from the expected value.

2. **Pattern comparison, not count comparison**: SEU vs SET classification compares the actual bit patterns (`bits == bits0`), not just the population counts. Two different corruptions could have the same hamming weight.

3. **Bit-level counting**: The error counters accumulate corrupted bit counts, not just event counts. This provides severity information for cross-section calculations.

## Per-SM Error Attribution

GPU architectures partition compute resources into Streaming Multiprocessors (SMs). Radiation events exhibit spatial locality; a particle strike affects transistors in a localized region. Attributing errors to specific SMs enables:

- Identification of faulty SMs for selective disable
- Spatial correlation analysis for multi-bit upset (MBU) detection
- Validation that all SMs are exercised during testing

### SM Identification

CUDA does not provide a runtime API for SM identification, but PTX inline assembly exposes the `%smid` special register:

```cuda
__shared__ unsigned int smid;

if (threadIdx.x == 0) {
    asm("mov.u32 %0, %smid;" : "=r"(smid));
}
__syncthreads();
```

The SM ID is queried once per block (by thread 0) and broadcast via shared memory to all threads in the block.

### Work Distribution

A naive approach where every block processes all data results in redundant work and conflated error attribution. The framework implements a bitmap-based work claiming mechanism:

```cuda
if (threadIdx.x == 0) {
    int entry = smid / ctx->numBits;
    int bit = smid % ctx->numBits;
    TEST_TYPE mask = (TEST_TYPE)1 << bit;

    // Atomically set bit and check if we were first
    TEST_TYPE prevVal = atomicOr(&ctx->sm_work_map[entry], mask);
    processBlock = ((prevVal & mask) == 0);
}
__syncthreads();

if (!processBlock) return;
```

This ensures:
- Exactly one block per SM processes the array
- All SMs participate regardless of scheduler nondeterminism
- Error counts are attributable to specific SMs

### Per-SM Counters

Errors detected by each SM are atomically accumulated into SM-indexed arrays:

```cuda
if (s_seu_errors > 0) {
    atomicAdd(ctx->d_seu_errors, (unsigned long long)s_seu_errors);
    if (smid < ctx->numSMs)
        atomicAdd(&ctx->sm_seu_errors[smid], (unsigned long long)s_seu_errors);
}
```

Post-test analysis can identify SMs with anomalous error rates or correlated multi-bit events.

## Build System Design

The build system uses GNU Make with platform-specific configuration files. The modular structure separates architecture definitions from feature flags.

### Directory Structure

```
cache_march_test/
├── Makefile              # Primary build orchestration
├── mk/
│   ├── h100.mk          # NVIDIA H100 configuration
│   ├── orin.mk          # NVIDIA Orin configuration
│   ├── zcu102.mk        # Xilinx ZCU102 configuration
│   ├── cuda.mk          # CUDA feature flags
│   ├── omp.mk           # OpenMP configuration
│   ├── arm.mk           # ARM architecture flags
│   └── helper.mk        # Utility functions
├── src/                  # Implementation files
└── include/              # Header files
```

### Platform Configuration

Each platform file defines architecture-specific settings:

```make
# mk/h100.mk
ifeq ($(h100),1)
    GCC_VERSION     := 13
    CUDA_VERSION    := 12.9
    TARGET_ARCH     := x86_64
    GPU_VIRT_ARCH   := compute_90
    GPU_REAL_ARCH   := sm_90

    gpu  := 1
    cuda := 1

    FACILITY        := NSRL_2025
    CPU             := "$(set_cpu)"
    GPU             := "$(set_gpu)"

    THREADS_PER_BLOCK := 1024
endif
```

```make
# mk/orin.mk
ifeq ($(orin),1)
    TARGET_ARCH     := aarch64
    GPU_VIRT_ARCH   := compute_87
    GPU_REAL_ARCH   := sm_87

    MACHINE_DEP_FLAGS += -mtune=cortex-a78ae -march=armv8.2-a+fp+simd

    FACILITY        := LBNL2025
    CPU             := Arm_Cortex-A78AE
endif
```

### Cross-Compilation

The build system auto-detects cross-compilation requirements:

```make
ifneq ($(HOST_ARCH),$(TARGET_ARCH))
    use_cross := 1
endif

ifeq ($(use_cross),1)
    TOOLCHAIN_PREFIX ?= $(TARGET_ARCH)-linux-gnu
    CC  := $(TOOLCHAIN_PREFIX)-gcc-$(GCC_VERSION)
    CXX := $(TOOLCHAIN_PREFIX)-g++-$(GCC_VERSION)
endif
```

Docker containers provide cross-compilation environments for Jetson platforms (Orin, Xavier) when building from x86_64 development machines.

### Build Targets

```bash
# CPU-only build
make cpu=1

# CPU with OpenMP parallelization
make cpu=1 omp=1

# NVIDIA Orin (cross-compile from x86_64)
make orin=1

# NVIDIA H100
make h100=1

# Xilinx ZCU102 (CPU only, aarch64)
make zcu102=1
```

The build produces multiple executables with distinct optimization levels:

| Executable | Description |
|------------|-------------|
| `cpu_cache_test_O2` | CPU test, optimized |
| `cpu_cache_test_O0` | CPU test, unoptimized (debugging) |
| `cpu_cache_sleep_test_O2` | CPU test with inter-iteration sleep |
| `cuda_cache_test` | GPU test |
| `cuda_cache_sleep_test` | GPU test with inter-iteration sleep |

The sleep variants insert delays between test passes, useful for long-duration exposures where continuous execution would generate excessive data rates.

## Telemetry Output Format

The framework supports both JSON and YAML output formats for machine parsing and real-time monitoring.

### JSON Format

```json
{"t":"meta","facility":"NSRL_2025","test_name":"Cache_March_Test","version":"2.5.1","os":"Ubuntu 22.04","kernel":"5.15.0","cpu":"AMD EPYC","gpu":"H100","num_elements":8388608}
{"t":"conf","arr_size_bytes":67108864,"thread_cnt":4,"iter_limit":4294967295,"element_size":8}
{"t":"dbg","i":10000,"core":0}
{"t":"error","cnt":42,"tid":0,"addr":0x7f4a8c001040,"exp":0,"act":281474976710656,"ctx":"SEU"}
```

Record types:
- `meta`: Test configuration and environment metadata
- `conf`: Runtime configuration parameters
- `dbg`: Periodic heartbeat with iteration count
- `error`: Individual error detection event

### YAML Format

```yaml
metadata:
  facility: NSRL_2025
  test_name: Cache_March_Test
  version: 2.5.1
  os: Ubuntu 22.04
  kernel: 5.15.0
  cpu: AMD EPYC
  gpu: H100
  num_elements: 8388608

config:
  arr_size_bytes: 67108864
  thread_cnt: 4
  iter_limit: 4294967295
  element_size: 8

data:
  - t: dbg
    i: 10000
    core: 0
  - t: error
    cnt: 42
    tid: 0
    addr: 0x7f4a8c001040
    exp: 0
    act: 281474976710656
    ctx: SEU
```

### Resilience Statistics

For GPU testing, the resilience infrastructure tracks retry and recovery statistics:

```yaml
resilience_stats:
  total_retries: 3
  transient_errors: 2
  soft_fatal_errors: 1
  hard_fatal_errors: 0
  kernel_timeouts: 0
  health_check_failures: 0
```

This data enables post-hoc analysis of GPU behavior under radiation stress, distinguishing between test article failures (SEU/SET) and infrastructure failures (kernel hangs, driver errors).

## Application Context: Beam Testing

### Accelerator Facilities

Radiation effects testing uses particle accelerators to deliver controlled radiation exposures:

**NASA Space Radiation Laboratory (NSRL)**: Located at Brookhaven National Laboratory, NSRL provides proton and heavy ion beams simulating the galactic cosmic ray and solar particle environment. Beam energies range from 50 MeV to 2.5 GeV per nucleon.

**TRIUMF Proton Irradiation Facility**: The Canadian facility provides proton beams up to 500 MeV, suitable for single-event effects testing and proton-induced activation studies.

**Lawrence Berkeley National Laboratory (LBNL)**: The 88-Inch Cyclotron provides heavy ion beams with LET (Linear Energy Transfer) values spanning the range of interest for space applications.

### Test Execution Protocol

A typical beam test campaign involves:

1. **Pre-beam verification**: Run the verification suite to confirm detection logic functions correctly before exposure begins.

2. **Functional checkout**: Execute several test iterations without beam to establish baseline error rates (should be zero for functional hardware).

3. **Beam exposure**: Enable beam and collect error events. The test runs continuously, logging all detected errors with timestamps.

4. **Flux monitoring**: Correlate error events with beam flux measurements from facility dosimetry to compute cross-sections.

5. **Post-beam analysis**: Process telemetry logs to extract:
   - SEU cross-section (upsets per bit per unit fluence)
   - SET rate characterization
   - Spatial distribution across SMs
   - Multi-bit upset clustering analysis

### Cross-Section Calculation

The SEU cross-section sigma relates observed upsets to particle fluence:

```
sigma = N_upset / (N_bits * Phi)
```

Where:
- `N_upset`: Number of bit upsets observed
- `N_bits`: Total bits under test
- `Phi`: Particle fluence (particles/cm^2)

The framework provides `N_upset` via the SEU bit counter. Facility instrumentation provides `Phi`. The test configuration determines `N_bits` (array elements * 64 bits/element for 64-bit test types).

## Supported Platforms

| Platform | Architecture | GPU Compute | Test Modes |
|----------|--------------|-------------|------------|
| NVIDIA H100 | x86_64 | SM90 (Hopper) | CPU + GPU |
| NVIDIA Orin AGX | aarch64 | SM87 (Ampere) | CPU + GPU |
| NVIDIA Orin NX | aarch64 | SM87 (Ampere) | CPU + GPU |
| NVIDIA Xavier | aarch64 | SM72 (Volta) | CPU + GPU |
| Xilinx ZCU102 | aarch64 | N/A | CPU only |

The framework architecture supports extension to additional platforms through new `.mk` configuration files without modification to core detection logic.

## Summary

The Cache March Test framework provides systematic detection and classification of radiation-induced memory errors for CPU and GPU architectures. Key capabilities include:

- **Dual-mode operation**: CPU testing via single-threaded or OpenMP-parallelized execution; GPU testing via CUDA kernels
- **SEU/SET discrimination**: Double-read detection algorithm distinguishes persistent cell corruption from transient read glitches
- **Spatial attribution**: Per-SM error counters enable fault localization and multi-bit upset analysis
- **Platform portability**: Modular build system supports x86_64 and aarch64 architectures across multiple NVIDIA compute generations
- **Machine-readable telemetry**: JSON/YAML output formats facilitate automated analysis pipelines

The framework is designed for research-grade radiation effects characterization at particle accelerator facilities, providing the instrumentation necessary for computing device-under-test cross-sections and qualifying hardware for radiation environments.
