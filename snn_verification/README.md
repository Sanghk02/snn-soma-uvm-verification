# SNN LIF Neuron UVM Verification Environment

![UVM Version](https://img.shields.io/badge/UVM-1.2-blue.svg)
![Coverage](https://img.shields.io/badge/Coverage-100%25-brightgreen.svg)
![Status](https://img.shields.io/badge/Status-Verified-success.svg)

## Overview
This project verifies a behavioral **Leaky Integrate-and-Fire (LIF) neuron model** for Spiking Neural Networks (SNN), using the **Universal Verification Methodology (UVM)**.

The verification environment focuses on:
* Functional correctness of LIF dynamics
* Correct timing alignment with 1-cycle SRAM read latency
* Strict handshake protocol validation
* Coverage-driven stimulus generation

## DUT (Device Under Test) Architecture
The DUT is a behavioral model of an SNN Soma (LIF Neuron) array.
* **Neuron Capacity**: 256 Neurons (4 Banks × 16 Words × 4 Neurons/Word).
* **Data Width**: 16-bit signed membrane potentials.
* **Configurable parameters**: 
  * `threshold`
  * `leakage_factor`

## LIF Behavior
Spike condition:
```text
V > threshold
```
Leakage behavior (arithmetic shift):
```text
V_new = V - (V >>> leakage_factor)
```
If a spike occurs:
```text
V_new = 0
```

## UVM Testbench Architecture
The testbench follows standard layered UVM architecture:

```text
Test (soma_test)
 └── Environment (soma_env)
      ├── Agent (soma_agent)
      │    ├── Driver (soma_driver)
      │    ├── Monitor (soma_monitor)
      │    └── Sequencer (uvm_sequencer)
      ├── Scoreboard (soma_scoreboard)
      └── Coverage (soma_coverage)
```
      
* **Sequence (`soma_base_seq`)**: Generates configuration, directed corner cases, and constrained-random stimulus.
* **Driver (`soma_driver`)**:
Drives transactions through clocking blocks and enforces handshake protocol (`busy`, `done`). Includes timeout protection   to prevent simulation deadlock.
* **Monitor (`soma_monitor`)**: Captures DUT behavior with cycle alignment. Implements a 1-cycle delayed pipeline model to match SRAM read latency.
* **Scoreboard (`soma_scoreboard`)**: Implements a predictive LIF reference model and compares:
  * Spike vectors
  * Updated membrane potentials
Reports mismatches with exact neuron index and expected/actual values and performs orphan transaction checks in the `check_phase` to prevent false positive results.
* **Coverage (`soma_coverage`)**: Contains comprehensive `covergroup` and `cross` coverage models aligned with the Verification Plan (V-Plan).

## Verification Strategy
A hybrid stimulus strategy is applied:
1. **Configuration Sweep**: Systematic variation of:
   * `threshold`
   * `leakage_factor`
2. **Directed Tests (Corner Cases)**:
   * All-spike condition (`32767`)
   * All-negative potentials (`-32768`) 
3. **Constrained Random Verification (CRV)**: Randomized membrane potentials with weighted distribution near threshold boundaries ($V = Thresh-1, Thresh, Thresh+1$) and leakage extremes (`0` to `15`).

This approach ensures both deterministic edge-case validation and broad state-space exploration.

## Key Verification Techniques
1. **Clocking Blocks**:
Prevent race conditions between DUT and testbench.

3. **Cycle-Aligned Pipeline Monitoring**: Accurately captures 1-cycle delayed SRAM read data.
5. **Handshake Timeout Protection**: Detects DUT hangs during busy/done protocol.
6. **Orphan Transaction Check**: Scoreboard check_phase ensures no expected transactions remain unverified.
7. **Cross Coverage per Neuron**: Ensures each neuron experiences:
   * Spike and No-Spike states
   * Positive and Negative potentials

## Coverage Model
Functional coverage includes:
## Verification Results
* **Functional Coverage**: `100.00%`
  * Successfully covered all 256 neurons experiencing both Spike/No-Spike states, and positive/negative potentials across varied thresholds and leakage factors.
* **Test Status**: PASSED (100% Functional Match, Zero dropped transactions).

## Repository Structure
```text
├── rtl/
│   └── soma_hw_module.sv    # DUT: LIF Neuron Behavioral Model
├── tb/
│   └── testbench.sv         # UVM Testbench (Env, Agent, Sequencer, etc.)
├── README.md                
└── Soma_Vplan.md                 # Verification Plan 
```
## How to Run
1. Include the UVM 1.2 library in your simulator (VCS, Xcelium, Questa, or EDA Playground).
2. Ensure rtl/soma_hw_module.sv is included in the compile path.
3. Compile and run `tb/testbench.sv`.
4. Run the simulation with the argument: `+UVM_TESTNAME=soma_test`.










