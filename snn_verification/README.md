# SNN LIF Neuron UVM Verification Environment

![UVM Version](https://img.shields.io/badge/UVM-1.2-blue.svg)
![Coverage](https://img.shields.io/badge/Coverage-100%25-brightgreen.svg)
![Status](https://img.shields.io/badge/Status-Verified-success.svg)

## Overview
This project demonstrates a cycle-accurate behavioral **Leaky Integrate-and-Fire (LIF) neuron model** for Spiking Neural Networks (SNN), rigorously verified using the **Universal Verification Methodology (UVM)** with functional coverage-driven testing. 

The verification environment is specifically designed to handle hardware timing behaviors such as SRAM read latency, clocking synchronization, and strict protocol handshaking.

## DUT (Device Under Test) Architecture
The DUT is a behavioral model of an SNN Soma (LIF Neuron) array.
* **Neuron Capacity**: 256 Neurons (4 Banks × 16 Words × 4 Neurons/Word).
* **Data Width**: 16-bit signed potentials.
* **Core Logic**: Updates membrane potentials based on programmable `threshold` and `leakage_factor`. Emits spikes when potentials exceed the threshold.

## UVM Testbench Architecture
The UVM testbench follows standard layered architecture:

Test
 └── Environment
      ├── Agent
      │    ├── Driver
      │    ├── Monitor
      │    └── Sequencer
      ├── Scoreboard
      └── Coverage
      
* **Sequence (`soma_base_seq`)**: A hybrid stimulus generator executing:
  * **Configuration**: Initial setup of registers.
  * **Directed Tests**: Corner case targeting (All-Spike, All-Negative potentials).
  * **CRV (Constrained Random Verification)**: Randomized valid parameters for broad state-space exploration.
* **Driver (`soma_driver`)**: Implements strict hardware handshake protocols (`busy`, `done`). Includes a **Watchdog (Timeout) mechanism** to prevent simulation deadlocks during hardware hangs.
* **Monitor (`soma_monitor`)**: Utilizes **Pipeline Capture Logic** to accurately sample delayed memory read data (1-cycle SRAM latency), perfectly synchronized with the clocking block.
* **Scoreboard (`soma_scoreboard`)**: Features cycle-accurate predictive modeling.
  * Independent error tracking for `Spike` pattern mismatches and `Potential` value mismatches.
  * Captures the exact `neuron_idx`, `expected_value`, and `actual_value` for rapid debugging.
  * Orphan transaction checks in the `check_phase` to detect data loss.
* **Coverage (`soma_coverage`)**: 100% Functional Coverage achieved via targeted `covergroup` and `cross` coverage matching the V-Plan.

## Advanced UVM Techniques Applied
1. **Clocking Blocks & Race Condition Prevention**: Eliminated delta-cycle race conditions between the DUT and TB by strictly driving and sampling through `clocking blocks` (`vif.cb`) with explicit setup/hold times.
2. **Deep Copy Object Management**: Prevented object reference overwriting in the Scoreboard by utilizing UVM `create` for independent expected data queues.
3. **Drain Time Utilization**: Clean simulation termination utilizing UVM's native `set_drain_time` instead of hardcoded `#` delays.
4. **Automated Waveform Dumping**: Configured to automatically generate `dump.vcd` for post-simulation timing analysis.

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

