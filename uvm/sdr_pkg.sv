// -----------------------------------------------------------------------
// sdr_pkg.sv
// UVM verification environment for sdr_ctrl.
// -----------------------------------------------------------------------
 
package sdr_pkg;
  
    import uvm_pkg::*;
    `include "uvm_macros.svh"
  
    parameter int MEM_ADDR_W = 22;
    parameter int ADDR_W     = MEM_ADDR_W + 1;
    parameter int DATA_W     = 16;
    parameter int BANK_W     = 2;   // 4 banks
    parameter int ROW_W      = 12;  // 4096 rows
    parameter int COL_W      = 8;   // 256 columns
    parameter int APB_ADDR_W = 8;
  
    // APB register map (see rtl/sdr_ctrl.sv header)
    parameter bit [APB_ADDR_W-1:0] APB_ADDR_STATUS = 8'h00;
    parameter bit [APB_ADDR_W-1:0] APB_ADDR_CTRL   = 8'h04;

	parameter int AP_BIT = COL_W;
	typedef enum {
		CMD_DES, 
		CMD_NOP, 
		CMD_ACT, 
		CMD_RD,
		CMD_RDA, 
		CMD_WR, 
		CMD_WRA,
		CMD_PRE, 
		CMD_PREA, 
		CMD_REF, 
		CMD_MRS, 
		CMD_PDE, 
		CMD_PDX,
		CMD_SRE, 
		CMD_SRX
	} sdr_cmd_e;
 
	function automatic sdr_cmd_e decode_sdr_cmd(
		input bit cs_n, ras_n, cas_n, we_n,
		input bit ap, // address bus's A10/AP_BIT qualifier, same cycle as cs/ras/cas/we
		input bit cke_prev, cke,
		input bit in_self_refresh
	);
		sdr_cmd_e base;
		if (cs_n)                            base = CMD_NOP; // DES not modeled on this monitor's bus: cs_n=1 => NOP
		else if (!ras_n && cas_n && we_n)    base = CMD_ACT;
		else if (ras_n && !cas_n && we_n)    base = ap ? CMD_RDA : CMD_RD;
		else if (ras_n && !cas_n && !we_n)   base = ap ? CMD_WRA : CMD_WR;
		else if (!ras_n && cas_n && !we_n)   base = ap ? CMD_PREA : CMD_PRE;
		else if (!ras_n && !cas_n && we_n)   base = CMD_REF;
		else if (!ras_n && !cas_n && !we_n)  base = CMD_MRS;
		else                                  base = CMD_NOP;
	
		if (cke_prev && !cke) begin
		if (base == CMD_REF) return CMD_SRE;
		if (base == CMD_NOP) return CMD_PDE;
		end else if (!cke_prev && cke) begin
		if (base == CMD_NOP) return in_self_refresh ? CMD_SRX : CMD_PDX;
		end
		return base;
	endfunction

	typedef uvm_sequencer #(axi_txn) axi_sequencer;
	typedef uvm_sequencer #(apb_txn) apb_sequencer;

	`uvm_analysis_imp_decl(_bfm)
	`uvm_analysis_imp_decl(_pwr)
	`uvm_analysis_imp_decl(_apb)
	`uvm_analysis_imp_decl(_cmdevt) 

	`include "sdr_transaction.sv"
	`include "sdr_sequencer.sv"
	`include "sdr_axi_sequence.sv"
	`include "sdr_apb_sequence.sv"
	`include "sdr_axi_driver.sv"
	`include "sdr_axi_monitor.sv"
	`include "sdr_axi_agent.sv"
	`include "sdr_apb_driver.sv"
	`include "sdr_apb_monitor.sv"
	`include "sdr_apb_agent.sv"
	`include "sdr_sdram_monitor.sv"
	`include "sdr_sdram_scoreboard.sv"
	`include "sdr_env.sv"
	`include "sdr_test.sv"
endpackage

