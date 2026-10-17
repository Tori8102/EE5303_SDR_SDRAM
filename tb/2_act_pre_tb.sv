// -----------------------------------------------------------------------
// #2 act_pre_tb.sv
// Directed, module-level (non-UVM) testbench 
// Power-up -> Init -> (ACT -> WRA -> RDA, repeated across several banks). 
// -----------------------------------------------------------------------
 
`timescale 1ns/1ps
 
import sdr_bfm_pkg::*;
 
module act_pre_tb;
 
  localparam int ADDR_W = 23; // +1 top bit: AP (virtual A10)
  localparam int DATA_W = 16;
  localparam int BANK_W = 2;
  localparam int ROW_W  = 12;
  localparam int COL_W  = 8;
  localparam int ID_W   = 4;
  localparam int APB_ADDR_W = 8;
 
  logic clk;
  logic rst_n;
 
  initial clk = 0;
  always #5 clk = ~clk;
 
  initial begin
    rst_n = 0;
    repeat (5) @(posedge clk);
    rst_n = 1;
  end
 
  axi_if   #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W)) aif (.clk(clk), .rst_n(rst_n));
  apb_if   #(.ADDR_W(APB_ADDR_W), .DATA_W(DATA_W))          apbif (.clk(clk), .rst_n(rst_n));
  sdram_if #(.BANK_W(BANK_W), .ROW_W(ROW_W), .DATA_W(DATA_W)) sif (.clk(clk), .rst_n(rst_n));
 
  wire [DATA_W-1:0] dq_wire;
  assign sif.dq = dq_wire;
 
  sdr_ctrl #(
    .DATA_W(DATA_W), .BANK_W(BANK_W), .ROW_W(ROW_W), .COL_W(COL_W), .ID_W(ID_W)
  ) dut (
    .clk        (clk),
    .rst_n      (rst_n),
 
    .axi_s_awvalid (aif.awvalid), .axi_s_awready (aif.awready), .axi_s_awaddr (aif.awaddr),
    .axi_s_awid    (aif.awid),    .axi_s_awlen   (aif.awlen),   .axi_s_awsize (aif.awsize),
    .axi_s_awburst (aif.awburst),
 
    .axi_s_wvalid  (aif.wvalid),  .axi_s_wready  (aif.wready),  .axi_s_wdata  (aif.wdata),
    .axi_s_wstrb   (aif.wstrb),   .axi_s_wlast   (aif.wlast),
 
    .axi_s_bvalid  (aif.bvalid),  .axi_s_bready  (aif.bready),  .axi_s_bresp  (aif.bresp),
    .axi_s_bid     (aif.bid),
 
    .axi_s_arvalid (aif.arvalid), .axi_s_arready (aif.arready), .axi_s_araddr (aif.araddr),
    .axi_s_arid    (aif.arid),    .axi_s_arlen   (aif.arlen),   .axi_s_arsize (aif.arsize),
    .axi_s_arburst (aif.arburst),
 
    .axi_s_rvalid  (aif.rvalid),  .axi_s_rready  (aif.rready),  .axi_s_rdata  (aif.rdata),
    .axi_s_rresp   (aif.rresp),   .axi_s_rlast   (aif.rlast),   .axi_s_rid    (aif.rid),
 
    .apb_s_psel    (apbif.psel),    .apb_s_penable (apbif.penable), .apb_s_pwrite (apbif.pwrite),
    .apb_s_paddr   (apbif.paddr),   .apb_s_pwdata  (apbif.pwdata),  .apb_s_prdata (apbif.prdata),
    .apb_s_pready  (apbif.pready),  .apb_s_pslverr (apbif.pslverr),
 
    .sdr_cs_n  (sif.cs_n),  .sdr_ras_n (sif.ras_n), .sdr_cas_n (sif.cas_n),
    .sdr_we_n  (sif.we_n),  .sdr_cke_n (sif.cke_n),   .sdr_ba    (sif.ba),
    .sdr_addr  (sif.addr),  .sdr_dqm   (sif.dqm),   .sdr_dq    (dq_wire)
  );
 
  sdr_sdram_model #(
    .DATA_W(DATA_W), .BANK_W(BANK_W), .ROW_W(ROW_W), .COL_W(COL_W)
  ) sdram (
    .clk   (clk),   .rst_n (rst_n),
    .cs_n  (sif.cs_n), .ras_n (sif.ras_n), .cas_n (sif.cas_n), .we_n (sif.we_n),
    .cke_n   (sif.cke_n),  .ba    (sif.ba),    .addr  (sif.addr),  .dqm  (sif.dqm),
    .dq    (dq_wire)
  );

  int unsigned act_cnt, rd_cnt, wr_cnt, pre_cnt, prea_cnt, ref_cnt, MRS_cnt;
  int unsigned pde_cnt, pdx_cnt, sre_cnt, srx_cnt;
  bit cke_prev_mon, in_self_refresh_mon;
 
  initial begin
    cke_prev_mon        = 1'b1;
    in_self_refresh_mon = 1'b0;
  end
 
  always @(posedge clk) begin
    sdr_cmd_e c;
    c = decode_sdr_cmd(sif.cs_n, sif.ras_n, sif.cas_n, sif.we_n, sif.addr[AP_BIT],
                        cke_prev_mon, sif.cke_n, in_self_refresh_mon);
    case (c)
      CMD_ACT         : act_cnt++;
      CMD_RD, CMD_RDA : rd_cnt++;
      CMD_WR, CMD_WRA : wr_cnt++;
      CMD_PRE         : pre_cnt++;
      CMD_PREA        : prea_cnt++;
      CMD_REF         : ref_cnt++;
      CMD_MRS         : MRS_cnt++;
      CMD_PDE         : pde_cnt++;
      CMD_PDX         : pdx_cnt++;
      CMD_SRE : begin sre_cnt++; in_self_refresh_mon = 1'b1; end
      CMD_SRX : begin srx_cnt++; in_self_refresh_mon = 1'b0; end
      CMD_DES, CMD_NOP : ;
      default : ;
    endcase
    cke_prev_mon = sif.cke_n;
  end
 
  int unsigned errors;
  bit [21:0] test_addrs [4] = '{22'h000100, 22'h100100, 22'h200300, 22'h3FFF00};
  bit [15:0] test_data  [4] = '{16'hA5A5, 16'h1234, 16'h5A5A, 16'hFFFF};
 
  initial begin
    axi_if_init(aif);
    apb_if_init(apbif);
    errors = 0;
 
    @(posedge rst_n);
    repeat (10) @(posedge clk);
 
    for (int i = 0; i < 4; i++) begin
      bit [15:0] rdata;
      int unsigned act_before;
 
      act_before = act_cnt;
      $display("[act_pre_tb] iter=%0d WR addr=0x%0h, col=0x%0h, row=0x%0h, bank=0x%0h, data=0x%0h", i, test_addrs[i], test_addrs[i][7:0], test_addrs[i][19:8], test_addrs[i][21:20], test_data[i]);
      axi_write(aif, test_addrs[i], test_data[i]);
 
      if (act_cnt == act_before) begin
        errors++;
        $error("[act_pre_tb] iter=%0d expected an ACT for this access but none observed", i);
      end
 
      $display("[act_pre_tb] iter=%0d RD addr=0x%0h, col=0x%0h, row=0x%0h, bank=0x%0h", i, test_addrs[i], test_addrs[i][7:0], test_addrs[i][19:8], test_addrs[i][21:20]);
      axi_read(aif, test_addrs[i], rdata);
 
      if (rdata !== test_data[i]) begin
        errors++;
        $error("[act_pre_tb] iter=%0d MISMATCH addr=0x%0h exp=0x%0h act=0x%0h",
               i, test_addrs[i], test_data[i], rdata);
      end else begin
        $display("[act_pre_tb] iter=%0d MATCH addr=0x%0h data=0x%0h", i, test_addrs[i], rdata);
      end
    end
 
    repeat (20) @(posedge clk);
 
    if (prea_cnt == 0) begin
      errors++;
      $error("[act_pre_tb] expected the S_INIT precharge-all (PREA) but none observed");
    end
    if (pre_cnt != 0) begin
      errors++;
      $error("[act_pre_tb] expected 0 single-bank PRE (every access uses AP=1), got %0d", pre_cnt);
    end
    if (act_cnt < 8) begin
      errors++;
      $error("[act_pre_tb] expected >=8 ACTs (one per WR + one per RD), got %0d", act_cnt);
    end
 
    if (errors == 0) $display("[act_pre_tb] PASS (act_cnt=%0d pre_cnt=%0d prea_cnt=%0d)", act_cnt, pre_cnt, prea_cnt);
    else              $display("[act_pre_tb] FAIL (%0d error(s))", errors);
 
    $finish;
  end
 
endmodule

