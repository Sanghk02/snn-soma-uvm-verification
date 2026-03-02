# [Verification Plan] SNN Soma Unit: Parallel LIF Dynamics

## 1. Introduction
This document outlines the verification strategy for the Soma Unit, a core component of the SNN hardware accelerator. The Soma unit processes 256 neurons across 4 parallel banks, implementing Leaky Integrate-and-Fire (LIF) dynamics. The goal is to ensure functional correctness, timing accuracy, and architectural reliability using the UVM methodology.

## 2. Target Features (Features under Test)

### 2.1 LIF Dynamics Verification
The primary goal is to verify the mathematical accuracy of the LIF model implemented in the Soma Hardware Module:
* **Threshold Crossing:** Ensure a spike is generated when the membrane potential (V) is strictly greater than the registered threshold_q.
* **Potential Reset:** Verify that V is reset to 0 immediately after a spike event.
* **Leaky Integration:** Confirm the arithmetic right shift operation for leakage: 
  * $V_{new} = V - (V >>> leakage_factor)$

### 2.2 Architectural Parallelism
* **4-Bank Parallel Processing:** Verify that all 4 memory banks are accessed simultaneously within the 16-cycle word processing window (per bank).
* **Word-to-Neuron Mapping:** Ensure the 64-bit word is correctly deserialized into four 16-bit neuron potentials and reserialized for writing.
* **Address Sequencing:** Validate that the bank addresses (0 to 15) are generated in the correct sequence without collisions.

### 2.3 Configuration and Control
* **Config Latching:** Verify that 'threshold' and 'leakage_factor' are correctly updated only when the 'config_en' signal is asserted.
* **Handshake Protocol:** Verify that the module correctly asserts busy during calculation and issues spike_valid and done for 1 clock cycle upon completion.

## 3. Test Scenarios
* **Scenario 1 (General LIF Logic):** Inject random 16-bit signed membrane potentials to verify basic integration, leakage, and spiking behavior under normal conditions.
* **Scenario 2 (Edge Case, Threshold):** Apply membrane potentials exactly at $V = Threshold$, $V = Threshold + 1$, and $V = Threshold - 1$ to verify the precision of the spiking comparator. (Implemented via CRV weighting in soma_base_seq)
* **Scenario 3 (Edge Case, Leakage):** Test with leakage_factor at its minimum (no leak) and maximum (full leak) values to ensure the arithmetic right-shift logic operates within bounds.
* **Scenario 4 (Signed Arithmetic):** Inject negative membrane potentials to confirm that the arithmetic right-shift correctly maintains the sign bit (sign extension) during the leakage process. (Implemented via Directed Test: All-Negative Neuron Case)
* **Scenario 5 (All-Spike Stress Test):** Inject maximum positive potentials (32767) to force all 256 neurons to spike simultaneously, verifying bus capacity and reset logic.

## 4. Success Criteria
* **Self-checking:** 100% match between the Hardware (DUT) output and the UVM Scoreboard (Reference Model), including independent verification of both Spike Vectors and Updated Potentials.
* **Functional Coverage:**
  * Neuron_ID: All 256 neuron IDs must be sampled at least once.
  * Spike_Activity: Must observe both 'Spike' (1) and 'No-Spike' (0) conditions for every single neuron (Cross Coverage).
  * Sign_Activity: Must observe both positive and negative potentials for every single neuron (Cross Coverage).
  * Config_Values: Cover a sweep of threshold ranges (0-250, 251-500, 501-750, 751-1000) and leakage_factor edges (0, mid, 15).