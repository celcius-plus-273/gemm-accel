# GEMM Accelerator: Weight Stationary Systolic Array

A hardware accelerator for dense matrix multiplication implemented in SystemVerilog. This project implements a systolic array architecture optimized for high-performance, energy-efficient matrix operations commonly used in AI/ML workloads.

**Note:** This project's design & implementation were used as the safety module for the Hive SoC Tapeout (ECE4804: Theory to Tapeout). Only behavioral simulation is supported in this public version; physical design and post-synthesis/post-APR simulations are not included.

## Overview

A systolic array is a specialized parallel computing architecture where multiple processing elements (PEs) work in concert, with each PE communicating only with its neighbors. This design minimizes data movement and maximizes compute density by keeping weights resident in PEs while activations and partial sums flow through the array. This implementation supports configurable array dimensions and multiple data formats.

### Key Capabilities

- **Scalable Architecture**: Configurable systolic array dimensions (4×4 to 16×16 PEs)
- **Multiple Data Formats**: 8-bit, 16-bit, 32-bit integers and floating-point (float16, float32, float8_e4m3)
- **Comprehensive Verification**: Automated test generation and reference model verification
- **EDA Tool Integration**: Synopsys VCS, Design Compiler, and ICC (Place & Route)

## Architecture

### High-Level Design

The systolic array performs matrix multiplication through a state machine with multiple operational phases:

1. **Preload Phase**: Weight matrix is loaded from the buffer into PE weight registers

2. **Streaming Phase**: Input activations flow from the buffer through the array while partial results accumulate in a pipelined manner. The `data_gen.py` script automatically staggers activations to achieve the weight-stationary dataflow pattern.

3. **Drain Phase** (overlapped with streaming): Final results are collected and written to the output buffer as they flow through the array

The IDLE state is entered when no computation is active.

### Core Components

<p align="center">
<img src="./docs/top_level.png" alt="" width="700"/>
</p>

### Module Hierarchy

- **Matrix Multiplication Top Level** (`matrix_mult_wrapper.sv`)
  - Integrates the computation array & controller
  - Scratch buffers used to supply per cycle data during computation

- **Matrix Multiplication Controller** (`sa_control.sv`)
  - Main orchestrator managing data flow between memory and array
  - Handles configuration and state sequencing

- **Systolic Array Compute Block** (`sa_compute.sv`)
  - Grid of processing elements (PEs)
  - Data routing and pipeline control

- **Processing Element** (`sa_pe.sv`)
  - Individual computation unit
  - Multiply-accumulate (MAC) operation
  - Local weight storage

- **Memory Subsystem**
  - Input activation buffer
  - Weight buffer
  - Output/partial sums buffer
  - Multiple implementations: behavioral, realistic emulator, and DesignWare-based

### Implementation Variants

The project supports multiple implementations for different use cases:

- **Memory Implementations**:
  - Behavioral (`mem_simple.sv`) - Simple simulation model
  - Emulator (`mem_emulator.sv`) - Realistic timing model
  - DesignWare (`mem_dw_buffer.sv`) - Synthesis-optimized model

- **MAC Implementations**:
  - Simple (`sa_mac_simple.sv`) - Behavioral multiply-accumulate
  - DesignWare Integer (`sa_mac_dw.sv`) - For integer operations
  - DesignWare Float (`sa_mac_dw_fp.sv`) - For floating-point operations

- **Built-in Self-Test** (`src/rtl/bist/`)
  - LFSR (`lfsr.sv`) - Pattern generation for testing
  - MISR (`misr.sv`) - Test response compression
  - Pseudo-random number generator (`pseudo_rand_num_gen.sv`)
  - Signature analyzer (`signature_analyzer.sv`)
  - Supports design verification and manufacturing test

## Project Structure

```
systolic_public/
├── README.md                       # This file
├── LICENSE                         # MIT License
├── docs/
│   └── PPA_analysis.pdf            # Power, Performance, and Area analysis
└── sim/                            # Simulation output directories
│   ├── behav/                      # Behavioral simulation results
│   ├── syn/                        # Post-synthesis simulation results
│   └── apr/                        # Post-APR simulation results
└── src/
    ├── rtl/                        # Register Transfer Logic
    │   ├── systolic/               # Systolic array core modules
    │   ├── matmul/                 # Matrix multiplication controller
    │   ├── memory/                 # Memory subsystem
    │   ├── bist/                   # Built-in self-test
    │   └── misc/                   # Utilities (clock domain crossing, shift registers)
    ├── verif/                      # Verification infrastructure
    │   ├── testbench/              # Simulation testbenches
    │   │   ├── tb_matrix_mult_mem.sv     # Main testbench (active)
    │   │   └── archive/            # Legacy testbenches for reference
    │   ├── scripts/                # Test generation and verification scripts
    │   └── include/                # VCS include files & SDF configs
    ├── makefiles/                  # Build system
    │   ├── Makefile_behav_sim      # Behavioral simulation
    │   └── ...                     # Additional flow makefiles

```

## Getting Started

### Prerequisites

- **SystemVerilog Simulator**: Synopsys VCS (required; version 2019.06 or later recommended)
- **Synthesis & Place & Route**: Not available in this public version (behavioral simulation only)
- **Python 3.x**: For test generation and verification scripts
  - Required packages: `numpy`, `click`, `ml_dtypes`
  - Install with: `pip install numpy click ml_dtypes`
- **Make**: Build system

### Quick Start/Reference

**Complete Behavioral Simulation Flow**

```bash
cd sim/behav
make link                                  # Initialize simulation directory
make run DATA_WIDTH=16 NUM_TESTS=50        # Generate tests, simulate, and verify
```

**Custom Configuration Example**

```bash
# Run 32-bit floating-point simulation on 16×16 array
make run DATA_WIDTH=32 M=16 K=16 N=16 \
         PE_ROWS=16 PE_COLS=16 FP=1 NUM_TESTS=100
```

**Check Results**

```bash
# View simulation passed/failed summary
tail verif_summary.log
```

## Configuration

Default configuration can be modified through Makefile parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DATA_WIDTH` | 16 | Data width in bits (8, 16, or 32) |
| `M` | 8 | Matrix A rows / output rows |
| `K` | 8 | Matrix A columns / Matrix B rows |
| `N` | 8 | Matrix B columns / output columns |
| `PE_ROWS` | 8 | Systolic array row count |
| `PE_COLS` | 8 | Systolic array column count |
| `TEST_COUNT` | 100 | Number of test vectors |
| `DATA_FORMAT` | INT | Data format (INT, FLOAT) |

### Memory Architecture

| Parameter | Size | Purpose |
|-----------|------|---------|
| Weight Buffer | 2048 bits | Stores weight matrix W |
| Input Activation Buffer | 4096 bits | Supplies activation matrix A |
| Output/Partial Sum Buffer | 4096 bits | Stores result matrix C |

Each buffer can be parameterized via Makefile. Note that physical design considerations are omitted.

## Scripts & Usage

### Test Data Generation

Generate random test vectors for simulation:

```bash
python3 scripts/data_gen.py
  -w 16         # data width (8, 16, or 32 bits)
  -d 8 8 8      # M, K, N dimensions
  -f 0          # 0: Integer | 1: Float
  -n 200        # number of tests
```

Supported formats: `int8`, `int16`, `int32`, `float16`, `float32`, `float8_e4m3`

### Utility Scripts

**Matrix Transformation (`scripts/util.py`)**

Shared utilities used by test generation and verification:
- Format conversion (integer to floating-point and vice versa)
- Matrix transpose and padding operations
- Binary/hex file I/O
- Support for all six data formats (int8, int16, int32, float8_e4m3, float16, float32)

### Running Simulations

```bash
make vcs        # calls VCS and executes simv
```

### Verification

Compare hardware simulation results against golden reference:

```bash
python3 scripts/verify.py
  -w 16         # data width (8, 16, or 32 bits)
  -d 8 8 8      # M, K, N dimensions
  -a 8 8        # physical array dimensions (rows, cols)
  -f 0          # 0: Integer | 1: Float
  -n 200        # number of tests
```

The verification script will generate an output log `verif_summary.log` with the results of each test. The verification summary can be extracted as:

```bash
head -n 4 verif_summary.log
```

### Test Data Organization

Generated test data is organized as follows:

```
sim/behav/bin/
├── test_0/
│   ├── input_A.bin              # Activation matrix (M × K)
│   ├── input_B.bin              # Weight matrix (K × N)
│   └── output_golden.bin        # Golden reference output (M × N)
├── test_1/
│   └── ...
```

Each test is independently generated with configurable dimensions and data format.

## Key Features

### Modularity

- Supports 4x4 to 16x16 physical computation array dimensions
- Parameterized scratch buffer dimensions

### Data Format Support

- **8-bit Integer**: for edge AI inference
- **16-bit Integer**: compact integer format (used on some AI models)
- **32-bit Integer**: traditional integer support
- **8-bit Float (e4m3)**: emerging ultra-low precision format
- **16-bit Float**: efficient ML workloads
- **32-bit Float**: high-precision applications/workloads

The `data_gen.py` script automatically formats input matrices for hardware loading, handling type conversions and memory layout. The diagram below shows the expected memory mapping:

<p align="center">
<img src="./docs/memory_mapping.png" alt="" width="700"/>
</p>

### Verification Infrastructure

- Automated test generation with configurable parameters
- Golden value is computed using Python's `numpy` library alongside data type libraries such as `ml_dtpyes`
- Automated result comparisson between python's golden output and systolic array's output
- Post-synthesis and post-APR simulation capabilities (Not supported on this public version)

## Performance Exploration

This systolic-based GEMM accelerator was used on the following projects to explore and understand the tradeoffs in PPA for different data format and memory configurations.

### Project 1: An Analysis on the Effects of Variable Bit Precision and Dynamic Range on Power, Area, and Accuracy in a 65 nm GEMM Accelerator

Power, Performance, and Area (PPA) analysis & comparison for all supported data formats is provided under the project report `PPA_analysis.pdf`. This report was used as a deliverable for the explorational final project for ECE 6135: Digital Systems at Nanometer Nodes.

- See `docs/PPA_analysis.pdf` for detailed implementation metrics
- Includes area breakdown, power consumption, and performance characterization for post-synthesis netlist results

## Troubleshooting

### Common Issues

**Python import errors (numpy, click, ml_dtypes)**
- Ensure all dependencies are installed: `pip install numpy click ml_dtypes`
- Use Python 3.7 or later
- If using a virtual environment, activate it before installing packages

**VCS compilation errors**
- Verify Synopsys VCS is installed and licensed
- Check that SystemVerilog support is enabled in your VCS installation
- For DesignWare modules, ensure DW license is available

**Simulation takes too long**
- Reduce `NUM_TESTS` in Makefile: `make vcs NUM_TESTS=10`
- Use smaller array dimensions: `make vcs PE_ROWS=4 PE_COLS=4`
- Combine smaller settings: `make vcs PE_ROWS=4 PE_COLS=4 NUM_TESTS=10`

**Verification failures**
- Check that test data was generated: `ls sim/behav/bin/test_*/`
- Verify golden output exists: `ls sim/behav/bin/test_0/output_golden.bin`
- Check simulation output files: `ls sim/behav/*.fsdb` or `ls sim/behav/*.vpd`
- Review detailed results: `cat verif_summary.log`

## References

### IEEE/Industry Standards

- IEEE 754 (Floating-Point) - Technical Standard for Floating-Point arithmetic

### Papers

- Kung, H.T., "Why Systolic Architectures?" IEEE Computer, 1982
- TPU architecture (Google) - Practical systolic deployment in ML accelerators

