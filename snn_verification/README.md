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
* **Monitor (`soma_monitor`)**: Utilizes **Pipeline Capture Logic** to accurately sample delayed memory read data (1-cycle SRAM latency), perfectly synchronized with the clocking block.
* **Scoreboard (`soma_scoreboard`)**: Features cycle-accurate predictive modeling.
  * Independent error tracking for `Spike` pattern mismatches and `Potential` value mismatches.
  * Captures the exact `neuron_idx`, `expected_value`, and `actual_value` for rapid debugging.
  * Orphan transaction checks in the `check_phase` to detect data loss.
* **Coverage (`soma_coverage`)**: 100% Functional Coverage achieved via targeted `covergroup` and `cross` coverage matching the V-Plan.

## Verification Strategy & Scenarios
A comprehensive hybrid sequence (`soma_base_seq`) is utilized to drive the stimulus, executing the following phases consecutively to achieve 100% functional coverage:
1. **Configuration Sweep**: Initializes threshold and leakage factor.
2. **Directed Tests (Corner Cases)**: Generates maximum positive potentials (`32767`) to force 256 simultaneous spikes.
   * Generates negative potentials (`-32768`) to verify signed arithmetic extension.
3. **CRV (Constrained Random Verification)**: Randomly injects potentials specifically weighted around the edge of the threshold ($V = Thresh-1, Thresh, Thresh+1$) and tests leakage extremes (`0` to `15`).

## Advanced UVM Techniques Applied
1. **Clocking Blocks & Race Condition Prevention**: Eliminated delta-cycle race conditions between the DUT and TB by strictly driving and sampling through `clocking blocks` (`vif.cb`) with explicit setup/hold times.
2. **Pipeline Capture Monitor**: Implements a 1-clock delayed pipeline register array in the Monitor to accurately sample delayed memory read data, mirroring 1-cycle SRAM read latency.
3. **Deep Copy Object Management**: Prevented object reference overwriting in the Scoreboard by utilizing UVM `create` for independent expected data queues.
4. **Precise Error Tracking**: The Scoreboard features independent error tracking for `Spike` pattern mismatches and `Potential` value mismatches, capturing the exact `neuron_idx`, `expected_value`, and `actual_value`.
5. **Hardware Timeout**: The Driver features a 2,000-cycle timeout limit during protocol handshakes (`busy`, `done`) to prevent simulation deadlocks in case of DUT hangs.
6. **Orphan Transaction Check**: Utilizes the UVM `check_phase` in the Scoreboard to detect any remaining expected items in the queue, ensuring no data loss occurs at the end of the simulation.
7. **Drain Time Utilization**: Clean simulation termination utilizing UVM's native `set_drain_time` instead of hardcoded `#` delays.
8. **Automated Waveform Dumping**: Configured to automatically generate `dump.vcd` for post-simulation timing analysis.

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
├── Vplan.md                # Verification Plan
└── README.md
```
## How to Run
1. Include the UVM 1.2 library in your simulator (VCS, Xcelium, Questa, or EDA Playground).
2. Ensure rtl/soma_hw_module.sv is included in the compile path.
3. Compile and run `tb/testbench.sv`.
4. Run the simulation with the argument: `+UVM_TESTNAME=soma_test`.




