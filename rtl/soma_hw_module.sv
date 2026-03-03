`timescale 1ns / 1ps

// ============================================================================
// Module: soma_hw_module
// Description: Behavioral Reference Model of the SNN Soma Unit.
//              Handles 256 LIF neurons across 4 parallel SRAM banks with 
//              1-cycle read latency and signed fixed-point arithmetic.
// ============================================================================
module soma_hw_module(soma_if vif);
  logic signed [15:0] thresh_q = 100;
  logic        [15:0] leak_q   = 1;
  
  initial begin
    // Initialize hardware state
    vif.done        <= 0;
    vif.busy        <= 0;
    vif.spike_valid <= 0;
    vif.spike_out   <= 0;
    for (int i = 0; i < 4; i++) begin
      vif.bank_rd_en[i] <= 0;
      vif.bank_wr_en[i] <= 0;
    end
    
    // Infinite loop representing hardware clock-by-clock behavior
    forever begin
      @(posedge vif.clk); // Evaluate state at every positive clock edge
      
      // Asynchronous reset handling
      if (!vif.n_rst) begin
        vif.done        <= 0;
        vif.busy        <= 0;
        vif.spike_valid <= 0;
        vif.spike_out   <= 0;
        for (int i = 0; i < 4; i++) begin
          vif.bank_rd_en[i] <= 0;
          vif.bank_wr_en[i] <= 0;
        end
        continue; // Skip logic and move to next clock if reset is active
      end
      
      // Capture configuration settings
      if (vif.config_en) begin
        thresh_q <= vif.threshold;
        leak_q   <= vif.leakage_factor;
      end
      
      // Start LIF parallel computation
      if (vif.start) begin
        vif.busy <= 1;
        
        // Process 16 words sequentially (16 words * 4 banks * 4 neurons = 256 neurons)
        for (int w = 0; w < 16; w++) begin
          
          // SRAM Read Request Phase
          for (int b = 0; b < 4; b++) begin
            vif.bank_rd_addr[b] <= w;
            vif.bank_rd_en[b]   <= 1;
          end
          
          @(posedge vif.clk); // Wait for SRAM address setup
          @(posedge vif.clk); // 1-cycle SRAM read latency synchronization
          
          // LIF Computation Phase
          for (int b = 0; b < 4; b++) begin
            logic [63:0] w_data;
            
            for (int s = 0; s < 4; s++) begin
              logic signed [15:0] v_old;
              logic signed [15:0] v_new;
              int n_idx;
              
              n_idx = (b * 64) + (w * 4) + s;
              v_old = vif.bank_rd_data[b][s*16 +: 16];
              
              // LIF computation logic: Threshold crossing and leakage
              if (v_old > thresh_q) begin
                v_new = 0;
                vif.spike_out[n_idx] <= 1;
              end else begin
                v_new = v_old - (v_old >>> leak_q);
                vif.spike_out[n_idx] <= 0;
              end
              w_data[s*16 +: 16] = v_new;
            end
            
            // SRAM Write Phase Setup
            vif.bank_wr_addr[b] <= w;
            vif.bank_wr_data[b] <= w_data;
            vif.bank_wr_en[b]   <= 1;
            vif.bank_rd_en[b]   <= 0; // Deassert read enable
          end
          
          @(posedge vif.clk); // Wait for SRAM write completion
          
          // Deassert write enable
          for (int b = 0; b < 4; b++) begin
            vif.bank_wr_en[b] <= 0;
          end
        end 
        
        // Finalize computation and output results
        vif.spike_valid <= 1;
        vif.done        <= 1;
        vif.busy        <= 0;
        
        @(posedge vif.clk); // Hold valid signal for 1 clock cycle
        vif.spike_valid <= 0;
        vif.done        <= 0;
      end
    end
  end
endmodule