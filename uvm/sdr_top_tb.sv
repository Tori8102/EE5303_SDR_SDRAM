// -----------------------------------------------------------------------
// top_tb.sv
// Top-level testbench: clock/reset gen, DUT, SDR SDRAM behavioral model,
// interfaces, UVM config_db hookup, run_test()
// -----------------------------------------------------------------------
 
`timescale 1ns/1ps
 
import uvm_pkg::*;
`include "uvm_macros.svh"
import sdr_pkg::*;
 
module top_tb;
 
  localparam int ADDR_W = sdr_pkg::ADDR_W;
  localparam int DATA_W = sdr_pkg::DATA_W;
  localparam int BANK_W = sdr_pkg::BANK_W;
  localparam int ROW_W  = sdr_pkg::ROW_W;
  localparam int COL_W  = sdr_pkg::COL_W;
 
  logic clk;
  logic rst_n;
 
  initial clk = 0;
  always #5 clk = ~clk;
 
  initial begin
    rst_n = 0;
    repeat (5) @(posedge clk);
    rst_n = 1;
  end
 
  localparam int ID_W = 4;
 
  localparam int APB_ADDR_W = sdr_pkg::APB_ADDR_W;
 
  axi_if   #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W)) aif (.clk(clk), .rst_n(rst_n));
  apb_if   #(.ADDR_W(APB_ADDR_W), .DATA_W(DATA_W)) apbif (.clk(clk), .rst_n(rst_n));
  sdram_if #(.BANK_W(BANK_W), .ROW_W(ROW_W), .DATA_W(DATA_W)) sif (.clk(clk), .rst_n(rst_n));
 
  wire [DATA_W-1:0] dq_wire;
  assign sif.dq = dq_wire;
 
  sdr_ctrl #(
    .DATA_W(DATA_W), .BANK_W(BANK_W), .ROW_W(ROW_W), .COL_W(COL_W), .ID_W(ID_W)
  ) dut (
    .clk        (clk),
    .rst_n      (rst_n),
 
    .axi_s_awvalid (aif.awvalid),
    .axi_s_awready (aif.awready),
    .axi_s_awaddr  (aif.awaddr),
    .axi_s_awid    (aif.awid),
    .axi_s_awlen   (aif.awlen),
    .axi_s_awsize  (aif.awsize),
    .axi_s_awburst (aif.awburst),
 
    .axi_s_wvalid  (aif.wvalid),
    .axi_s_wready  (aif.wready),
    .axi_s_wdata   (aif.wdata),
    .axi_s_wstrb   (aif.wstrb),
    .axi_s_wlast   (aif.wlast),
 
    .axi_s_bvalid  (aif.bvalid),
    .axi_s_bready  (aif.bready),
    .axi_s_bresp   (aif.bresp),
    .axi_s_bid     (aif.bid),
 
    .axi_s_arvalid (aif.arvalid),
    .axi_s_arready (aif.arready),
    .axi_s_araddr  (aif.araddr),
    .axi_s_arid    (aif.arid),
    .axi_s_arlen   (aif.arlen),
    .axi_s_arsize  (aif.arsize),
    .axi_s_arburst (aif.arburst),
 
    .axi_s_rvalid  (aif.rvalid),
    .axi_s_rready  (aif.rready),
    .axi_s_rdata   (aif.rdata),
    .axi_s_rresp   (aif.rresp),
    .axi_s_rlast   (aif.rlast),
    .axi_s_rid     (aif.rid),
 
    .apb_s_psel    (apbif.psel),
    .apb_s_penable (apbif.penable),
    .apb_s_pwrite  (apbif.pwrite),
    .apb_s_paddr   (apbif.paddr),
    .apb_s_pwdata  (apbif.pwdata),
    .apb_s_prdata  (apbif.prdata),
    .apb_s_pready  (apbif.pready),
    .apb_s_pslverr (apbif.pslverr),
 
    .sdr_cs_n  (sif.cs_n),
    .sdr_ras_n (sif.ras_n),
    .sdr_cas_n (sif.cas_n),
    .sdr_we_n  (sif.we_n),
    .sdr_cke   (sif.cke),
    .sdr_ba    (sif.ba),
    .sdr_addr  (sif.addr),
    .sdr_dqm   (sif.dqm),
    .sdr_dq    (dq_wire)
  );
 
  sdr_sdram_model #(
    .DATA_W(DATA_W), .BANK_W(BANK_W), .ROW_W(ROW_W), .COL_W(COL_W)
  ) sdram (
    .clk   (clk),
    .rst_n (rst_n),
    .cs_n  (sif.cs_n),
    .ras_n (sif.ras_n),
    .cas_n (sif.cas_n),
    .we_n  (sif.we_n),
    .cke   (sif.cke),
    .ba    (sif.ba),
    .addr  (sif.addr),
    .dqm   (sif.dqm),
    .dq    (dq_wire)
  );
 
  initial begin
    uvm_config_db#(virtual axi_if.drv)::set(null, "uvm_test_top.env.axi_agt.drv", "vif", aif);
    uvm_config_db#(virtual axi_if.mon)::set(null, "uvm_test_top.env.axi_agt.mon", "vif", aif);
    uvm_config_db#(virtual apb_if.drv)::set(null, "uvm_test_top.env.apb_agt.drv", "vif", apbif);
    uvm_config_db#(virtual apb_if.mon)::set(null, "uvm_test_top.env.apb_agt.mon", "vif", apbif);
    uvm_config_db#(virtual sdram_if.mon)::set(null, "uvm_test_top.env.sdr_mon", "vif", sif);
    run_test("sdr_base_test");
  end
 
endmodule



