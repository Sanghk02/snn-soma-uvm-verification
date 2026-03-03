`timescale 1ns / 1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

`include "../rtl/soma_hw_module.sv"

// ============================================================================
// 1. Interface
// ============================================================================
interface soma_if(input logic clk);
  logic         n_rst;
  logic         start;
  logic         config_en;
  logic  [15:0] threshold;
  logic  [15:0] leakage_factor;
  logic         busy;
  logic         done;
  
  logic  [3:0]  bank_rd_addr [4];
  logic         bank_rd_en   [4];
  logic  [63:0] bank_rd_data [4]; 
  
  logic  [3:0]  bank_wr_addr [4];
  logic         bank_wr_en   [4];
  logic  [63:0] bank_wr_data [4];
  
  logic [255:0] spike_out;
  logic         spike_valid;
  
  // Clocking block for UVM testbench synchronization to prevent delta-cycle race conditions
  clocking cb @(posedge clk);
    default input #1ns output #1ns;
    input  n_rst, busy, done;
    input  bank_rd_addr, bank_rd_en, bank_wr_addr, bank_wr_en, bank_wr_data;
    input  spike_out, spike_valid;
    
    inout  start, config_en, threshold, leakage_factor;
    output bank_rd_data;
  endclocking
endinterface

// ============================================================================
// 2. Data Item (Transaction)
// ============================================================================
typedef enum { SET_CONFIG, SEND_DATA } soma_pkt_e;

class snn_item extends uvm_sequence_item;
  `uvm_object_utils(snn_item)
  
  rand soma_pkt_e         pkt_type;
  rand int                threshold;
  rand int                leakage_factor;
  rand bit signed [15:0]  potentials [256]; 
       bit signed [15:0]  updated_potentials [256];
       bit        [255:0] spikes;
  
  // Solve-before constraint to ensure threshold is evaluated before potentials
  constraint c_order { solve threshold before potentials; }
      
  constraint c_ranges {
    threshold inside {[0:1000]};
    leakage_factor inside {[0:15]}; 
  }
  
  function new(string name = "snn_item");
    super.new(name); 
  endfunction
endclass

// ============================================================================
// 3. Driver
// ============================================================================
class soma_driver extends uvm_driver #(snn_item);
  `uvm_component_utils(soma_driver)
  virtual soma_if vif;
  uvm_analysis_port #(snn_item) ap; 
  
  function new(string name, uvm_component parent); 
    super.new(name, parent); 
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual soma_if)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "Could not find VIF")
  endfunction
      
  virtual task run_phase(uvm_phase phase);
    snn_item item;
    
    wait(vif.n_rst == 1);
    @(vif.cb); // Use clocking block instead of raw posedge clock
    
    forever begin
      seq_item_port.get_next_item(item);
      ap.write(item); 
      
      if (item.pkt_type == SET_CONFIG) drive_config(item);
      else                             drive_data(item);
      
      seq_item_port.item_done();
    end
  endtask
  
  task drive_data(snn_item item);
    int timeout = 0;
    
    // Wait for DUT to clear previous state and return to IDLE
    while (vif.cb.done === 1'b1 || vif.cb.busy === 1'b1) begin
      @(vif.cb);
    end
      
    vif.cb.start <= 1;
    @(vif.cb);
    vif.cb.start <= 0;
    
    // Serve as SRAM backend while DUT is busy computing
    while (!vif.cb.done) begin
      @(vif.cb);
      timeout++;
      
      if(timeout > 2000) begin
        `uvm_error("DRV_TIMEOUT", "Timeout waiting for done signal")
        break;
      end
        
      for (int b = 0; b < 4; b++) begin
        if (vif.cb.bank_rd_en[b]) begin
          // Pack 4 x 16-bit potentials into a 64-bit word
          int word_idx = vif.cb.bank_rd_addr[b];
          int base = (b * 64) + (word_idx * 4);
          
          vif.cb.bank_rd_data[b][15:0]  <= item.potentials[base];
          vif.cb.bank_rd_data[b][31:16] <= item.potentials[base+1];
          vif.cb.bank_rd_data[b][47:32] <= item.potentials[base+2];
          vif.cb.bank_rd_data[b][63:48] <= item.potentials[base+3];
        end
      end
    end
  endtask
    
  task drive_config(snn_item item);
    while (vif.cb.done === 1'b1 || vif.cb.busy === 1'b1) begin
      @(vif.cb);
    end
    
    vif.cb.config_en      <= 1;
    vif.cb.threshold      <= item.threshold;
    vif.cb.leakage_factor <= item.leakage_factor;
    @(vif.cb);
    vif.cb.config_en      <= 0;
  endtask
endclass

// ============================================================================
// 4. Monitor
// ============================================================================
class soma_monitor extends uvm_monitor;
  `uvm_component_utils(soma_monitor)
  virtual soma_if vif;
  uvm_analysis_port #(snn_item) ap;
  
  int current_thresh;
  int current_leak;
  
  bit signed [15:0] pot_buf [256];
  bit signed [15:0] in_pot_buf [256];
  
  bit       rd_en_d [4];
  bit [3:0] rd_addr_d [4];
  
  function new(string name, uvm_component parent); 
    super.new(name, parent); 
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual soma_if)::get(this, "", "vif", vif))
      `uvm_fatal("MON", "Could not find VIF")
  endfunction
      
  virtual task run_phase(uvm_phase phase);
    snn_item item;
    
    // Initialize pipeline registers for 1-cycle delayed capture
    for(int b = 0; b < 4; b++) begin
      rd_en_d[b]   = 0;
      rd_addr_d[b] = 0;
    end
    
    forever begin
      @(vif.cb); // Synchronize with clocking block
      
      // 1. Capture data using 1-cycle delayed signals (Previous clock's request)
      for (int b = 0; b < 4; b++) begin
        if (rd_en_d[b]) begin
          int word_idx = rd_addr_d[b];
          int base = (b * 64) + (word_idx * 4);
          
          in_pot_buf[base]   = vif.cb.bank_rd_data[b][15:0];
          in_pot_buf[base+1] = vif.cb.bank_rd_data[b][31:16];
          in_pot_buf[base+2] = vif.cb.bank_rd_data[b][47:32];
          in_pot_buf[base+3] = vif.cb.bank_rd_data[b][63:48];
        end
      end
      
      // 2. Store current clock's request for the next clock cycle
      for (int b = 0; b < 4; b++) begin
        rd_en_d[b]   = vif.cb.bank_rd_en[b];
        rd_addr_d[b] = vif.cb.bank_rd_addr[b];
      end
      
      // Capture configuration settings
      if (vif.cb.config_en) begin
        current_thresh = vif.cb.threshold;
        current_leak   = vif.cb.leakage_factor;
      end
            
      // Capture hardware write data
      for (int b = 0; b < 4; b++) begin
        if (vif.cb.bank_wr_en[b]) begin
          int word_idx = vif.cb.bank_wr_addr[b];
          int base = (b * 64) + (word_idx * 4);
          
          pot_buf[base]   = vif.cb.bank_wr_data[b][15:0];
          pot_buf[base+1] = vif.cb.bank_wr_data[b][31:16];
          pot_buf[base+2] = vif.cb.bank_wr_data[b][47:32];
          pot_buf[base+3] = vif.cb.bank_wr_data[b][63:48];
        end
      end
      
      // Complete transaction upon spike_valid assertion
      if (vif.cb.spike_valid) begin 
        item = snn_item::type_id::create("item");
        item.spikes             = vif.cb.spike_out;
        item.updated_potentials = pot_buf;
        item.potentials         = in_pot_buf;
        item.threshold          = current_thresh;
        item.leakage_factor     = current_leak;
        ap.write(item);
      end
    end
  endtask
endclass

// ============================================================================
// 5. Scoreboard
// ============================================================================
class soma_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(soma_scoreboard)
  `uvm_analysis_imp_decl(_drv)
  `uvm_analysis_imp_decl(_mon)
  
  uvm_analysis_imp_drv #(snn_item, soma_scoreboard) drv_imp;
  uvm_analysis_imp_mon #(snn_item, soma_scoreboard) mon_imp;
  
  int threshold_ref = 100;
  int leak_ref      = 1;
  
  int pass_count    = 0;
  int fail_count    = 0; 
  
  snn_item item_queue[$];
 
  function new(string name, uvm_component parent); 
    super.new(name, parent); 
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    drv_imp = new("drv_imp", this);
    mon_imp = new("mon_imp", this);
  endfunction
  
  virtual function void write_drv(snn_item item);
    if (item.pkt_type == SET_CONFIG) begin
      threshold_ref = item.threshold;
      leak_ref      = item.leakage_factor;
    end else begin
      bit        [255:0] exp_spikes = 0;
      bit signed [15:0]  exp_pots [256];
      
      snn_item exp_item = snn_item::type_id::create("exp_item");
      
      // Calculate expected spikes and membrane potentials
      for (int i = 0; i < 256; i++) begin
        if (item.potentials[i] > threshold_ref) begin
          exp_spikes[i] = 1;
          exp_pots[i]   = 0; 
        end else begin
          exp_spikes[i] = 0;
          // Apply arithmetic right shift with sign extension
          exp_pots[i]   = item.potentials[i] - ($signed(item.potentials[i]) >>> leak_ref);
        end
      end
      
      exp_item.spikes             = exp_spikes; 
      exp_item.updated_potentials = exp_pots; 
      item_queue.push_back(exp_item);
    end
  endfunction
  
  virtual function void write_mon(snn_item actual);
    snn_item expected;
    if (item_queue.size() > 0) begin
      expected = item_queue.pop_front();
      
      // 1. Verify Spike Pattern
      if (actual.spikes == expected.spikes) begin
        bit match = 1;
        int first_fail_idx = -1; // Store index for debugging 
        
        // 2. Verify Updated Potentials
        for (int i = 0; i < 256; i++) begin
          if (actual.updated_potentials[i] != expected.updated_potentials[i]) begin
            match = 0;
            if (first_fail_idx == -1) first_fail_idx = i;
          end          
        end
          
        if (match) begin
          pass_count++;
          `uvm_info("SCB", $sformatf("Item #%0d Checked: 256 Neurons MATCHED perfectly!", pass_count), UVM_LOW)
        end else begin
          fail_count++;
          `uvm_error("SCB_FAIL_POT", $sformatf("Potential Mismatch! Neuron[%0d] | Exp: %0d, Act: %0d", 
                      first_fail_idx, expected.updated_potentials[first_fail_idx], actual.updated_potentials[first_fail_idx]))
        end
      end else begin
        fail_count++;
        `uvm_error("SCB_FAIL_SPIKE", $sformatf("Spike Vector Mismatch! | Exp: %64X, Act: %64X", expected.spikes, actual.spikes))
      end
    end else begin
      // Synchronization error: Monitor sent data, but Scoreboard queue is empty
      `uvm_error("SCB_FATAL", "Monitor sent data, but Scoreboard queue is empty!")
    end
  endfunction
  
  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (item_queue.size() > 0) begin
      fail_count++;
      `uvm_error("SCB_ORPHAN", $sformatf("Simulation finished, but %0d expected items are still stuck in Scoreboard queue (Missing DUT Output)", item_queue.size()))
    end
  endfunction
  
  // Report final simulation results
  virtual function void report_phase(uvm_phase phase);
    `uvm_info("SCB_SUM", "==============================", UVM_LOW)
    `uvm_info("SCB_SUM", " FINAL SCOREBOARD REPORT", UVM_LOW)
    `uvm_info("SCB_SUM", $sformatf(" -TOTAL PASSED : %0d", pass_count), UVM_LOW)
    `uvm_info("SCB_SUM", $sformatf(" -TOTAL FAILED : %0d", fail_count), UVM_LOW)
    
    if (fail_count == 0 && pass_count > 0) begin
      `uvm_info("SCB_SUM", " SYSTEM STATUS: 100% FUNCTIONAL MATCH", UVM_LOW)
    end else begin
      `uvm_error("SCB_SUM", $sformatf(" SYSTEM STATUS: [FAIL] Found %0d Mismatches", fail_count))
    end
    `uvm_info("SCB_SUM","===============================", UVM_LOW)
  endfunction
endclass            
     
// ============================================================================
// 6. Coverage
// ============================================================================
class soma_coverage extends uvm_subscriber #(snn_item);
  `uvm_component_utils(soma_coverage)
  snn_item item;
  
  // Covergroup with arguments for independent, per-neuron evaluation
  covergroup soma_cg with function sample(int neuron_idx, bit is_spike, int thresh, int leak, int is_neg);
    cp_id:     coverpoint neuron_idx { bins ids[] = {[0:255]}; }
    cp_spike:  coverpoint is_spike   { bins no_spike = {0}; bins spike = {1}; }
    
    cp_thresh: coverpoint thresh { 
      bins range_0_250    = {[0:250]}; 
      bins range_251_500  = {[251:500]}; 
      bins range_501_750  = {[501:750]}; 
      bins range_751_1000 = {[751:1000]}; 
    }
    
    cp_leak: coverpoint leak { 
      bins min_leak = {0};        
      bins mid_leak = {[1:14]}; 
      bins max_leak = {15};      
    }
    
    cp_sign: coverpoint is_neg {
      bins positive = {0};
      bins negative = {1};
    }
    
    // Cross coverage: Ensure every neuron experiences both Spike and No-Spike (V-Plan Key Criteria)
    cross_id_spike: cross cp_id, cp_spike;
    cross_id_sign:  cross cp_id, cp_sign;
  endgroup
  
  function new(string name, uvm_component parent);
    super.new(name, parent);
    soma_cg = new();
  endfunction
  
  virtual function void write(snn_item t);
    this.item = t;
    // Iterate over the 256-bit vector and sample each neuron individually
    for (int i = 0; i < 256; i++) begin
      soma_cg.sample(i, t.spikes[i], t.threshold, t.leakage_factor, (t.potentials[i] < 0));
    end
  endfunction
  
  virtual function void report_phase(uvm_phase phase);
    // Output the current functional coverage percentage
    real curr_cov = soma_cg.get_inst_coverage();
    `uvm_info("COV_REP", $sformatf("Current Functional Coverage: %0.2f%%", curr_cov), UVM_LOW)
    
    if (curr_cov >= 100.0)
      `uvm_info("COV_REP", "ALL Neurons & Configs Covered!", UVM_LOW)
  endfunction
endclass
    
// ============================================================================
// 7. Agent
// ============================================================================
class soma_agent extends uvm_agent;
  `uvm_component_utils(soma_agent)
  soma_driver    drv;
  soma_monitor   mon;
  uvm_sequencer #(snn_item) sqr;
  uvm_analysis_port #(snn_item) ap;
  
  function new(string name, uvm_component parent); 
    super.new(name, parent); 
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    ap  = new("ap", this);
    mon = soma_monitor::type_id::create("mon", this);
    sqr = uvm_sequencer#(snn_item)::type_id::create("sqr", this);
    drv = soma_driver::type_id::create("drv", this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
    mon.ap.connect(this.ap);
  endfunction
endclass
    
// ============================================================================
// 8. Environment
// ============================================================================
class soma_env extends uvm_env;
  `uvm_component_utils(soma_env)
  soma_agent      agent;
  soma_scoreboard scb;
  soma_coverage   cov;
  
  function new(string name, uvm_component parent); 
    super.new(name, parent); 
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    agent = soma_agent::type_id::create("agent", this);
    scb   = soma_scoreboard::type_id::create("scb", this);
    cov   = soma_coverage::type_id::create("cov", this);
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
    agent.ap.connect(scb.mon_imp);
    agent.ap.connect(cov.analysis_export);
    agent.drv.ap.connect(scb.drv_imp);
  endfunction
endclass

// ============================================================================
// 9. Sequence
// ============================================================================
class soma_base_seq extends uvm_sequence #(snn_item);
  `uvm_object_utils(soma_base_seq)
  function new(string name = "soma_base_seq"); 
    super.new(name); 
  endfunction
  
  int current_threshold;
  int current_leak;

  virtual task body();
    snn_item item;
    
    // [Directed Sweep] Initial Configuration
    item = snn_item::type_id::create("item");
    start_item(item);
    item.pkt_type = SET_CONFIG;
    if(!item.randomize() with { threshold == 1000; leakage_factor == 1; })
      `uvm_error("SEQ", "Initial Config Fail")
    finish_item(item);
      
    // Directed Test: Max Positive
    `uvm_info("SEQ", "Starting Directed: All-Neuron Spike Case", UVM_LOW)
    item = snn_item::type_id::create("item");
    start_item(item);
    item.pkt_type = SEND_DATA;
    // Fill the spike bins (force all neurons to spike)
    if(!item.randomize() with { foreach(potentials[i]) potentials[i] == 32767; })
      `uvm_error("SEQ", "Directed Random Fail")
    finish_item(item);
    
    // Directed Test: Max Negative
    `uvm_info("SEQ", "Starting Directed: All-Neuron Negative Case", UVM_LOW)
    item = snn_item::type_id::create("item");
    start_item(item);
    item.pkt_type = SEND_DATA;
    // Fill the negative and no-spike bins (force all neurons to stay below threshold)
    if(!item.randomize() with { foreach(potentials[i]) potentials[i] == -32768; })
      `uvm_error("SEQ", "Directed Random Fail")
    finish_item(item);
    
    // Constrained Random Verification (CRV)
    `uvm_info("SEQ", "Starting CRV: Constrained Random Verification", UVM_LOW)
    repeat(50) begin
      // 1. Set new configuration (target various coverage bins)
      item = snn_item::type_id::create("item");
      start_item(item);
      item.pkt_type = SET_CONFIG;
      
      if(!item.randomize() with {
        leakage_factor dist { 0 := 10, [1:14] :/ 10, 15 := 10 };
        
        threshold dist {
          [0:250]    :/ 10,
          [251:500]  :/ 10,
          [501:750]  :/ 10,
          [751:1000] :/ 10
        };
      }) `uvm_error("SEQ", "Config Randomization Failed!")
      
      current_threshold = item.threshold;
      current_leak      = item.leakage_factor;
      finish_item(item);
      
      // 2. Send 10 data packets with the current configuration
      repeat(10) begin
        item = snn_item::type_id::create("item");
        start_item(item);
        item.pkt_type = SEND_DATA;
        
        if(!item.randomize() with {
          foreach (potentials[i]) {
            potentials[i] dist {
              current_threshold     := 10,
              current_threshold + 1 := 10,
              current_threshold - 1 := 10,
              [-32768 : - 1]        :/ 30,
              32767                 := 10,
              [0 : 32767]           :/ 30
            };
          }
        }) `uvm_error("SEQ", "Data Randomization Failed!")
        finish_item(item);
      end
    end
  endtask
endclass
          
// ============================================================================
// 10. Test
// ============================================================================
class soma_test extends uvm_test;
  `uvm_component_utils(soma_test)
  soma_env env;
  
  function new(string name, uvm_component parent); 
    super.new(name, parent); 
  endfunction
  
  virtual function void build_phase(uvm_phase phase);
    env = soma_env::type_id::create("env", this);
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    soma_base_seq seq = soma_base_seq::type_id::create("seq");
    
    phase.phase_done.set_drain_time(this, 100ns);
    
    phase.raise_objection(this);
    seq.start(env.agent.sqr);
    phase.drop_objection(this);
  endtask
endclass

// ============================================================================
// 11. Top Module
// ============================================================================
module top;
  logic clk = 0;
  always #5 clk = ~clk;
  
  soma_if _if(clk);
  
  // Generate reset signal
  initial begin
    _if.n_rst = 0;
    #20 _if.n_rst = 1;
  end
  
  // Instantiate the DUT (Device Under Test)
  // Ensure that 'soma_hw_module.sv' is compiled along with this testbench
  soma_hw_module DUT(_if);
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, top);
    
    uvm_config_db#(virtual soma_if)::set(null, "*", "vif", _if);
    run_test("soma_test");
  end
endmodule