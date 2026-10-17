// -----------------------------------------------------------------------
// #4 low_power_tb.sv
// Directed, module-level (non-UVM) testbench "Low-power test".
// Power-up -> Init -> WR -> RD -> (APB pd_req while a row is open, exits via S_APDE back to S_ACT) -> PREA (idle, no row open) -> (APB sr_req,
// enters self-refresh via S_SRE) -> exit self-refresh.
// -----------------------------------------------------------------------
 
`timescale 1ns/1ps
 
import sdr_bfm_pkg::*;
 
module low_power_tb;
 
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
    .cke_n (sif.cke_n),  .ba  (sif.ba),    .addr  (sif.addr),  .dqm  (sif.dqm),
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
      CMD_ACT          : act_cnt++;
      CMD_RD, CMD_RDA  : rd_cnt++;
      CMD_WR, CMD_WRA  : wr_cnt++;
      CMD_PRE          : pre_cnt++;
      CMD_PREA         : prea_cnt++;
      CMD_REF          : ref_cnt++;
      CMD_MRS          : MRS_cnt++;
      CMD_PDE          : pde_cnt++;
      CMD_PDX          : pdx_cnt++;
      CMD_SRE : begin sre_cnt++; in_self_refresh_mon = 1'b1; end
      CMD_SRX : begin srx_cnt++; in_self_refresh_mon = 1'b0; end
      CMD_DES, CMD_NOP : ;
      default : ;
    endcase
    cke_prev_mon = sif.cke_n;
  end
 
  int unsigned errors;
 
  initial begin
    bit [21:0] addr;
    bit [15:0] wdata, rdata;
 
    axi_if_init(aif);
    apb_if_init(apbif);
    errors = 0;
 
    @(posedge rst_n);
    repeat (10) @(posedge clk);
 
    addr  = 22'h000500;
    wdata = 16'h7E57;
    $display("[low_power_tb] WR addr=0x%0h, col=0x%0h, row=0x%0h, bank=0x%0h, data=0x%0h", addr, addr[7:0], addr[19:8], addr[21:20], wdata);
    axi_write(aif, addr, wdata);
 
    $display("[low_power_tb] RD addr=0x%0h", addr);
    axi_read(aif, addr, rdata);
    if (rdata !== wdata) begin
      errors++;
      $error("[low_power_tb] pre-PD MISMATCH exp=0x%0h act=0x%0h", wdata, rdata);
    end
 
    // Active Power-Down: request while a row may still be open (S_APDE), then exit back to S_ACT.
    $display("[low_power_tb] entering active power-down (pd_req=1)");
    apb_set_pd_sr(apbif, 1'b1, 1'b0);
    repeat (10) @(posedge clk);
    $display("[low_power_tb] exiting active power-down (pd_req=0)");
    apb_set_pd_sr(apbif, 1'b0, 1'b0);
    repeat (10) @(posedge clk);
 
    if (pde_cnt < 1 || pdx_cnt < 1) begin
      errors++;
      $error("[low_power_tb] expected >=1 PDE and >=1 PDX, got pde=%0d pdx=%0d",
             pde_cnt, pdx_cnt);
    end
 
    // Confirm normal access still works after PDX.
    axi_read(aif, addr, rdata);
    if (rdata !== wdata) begin
      errors++;
      $error("[low_power_tb] post-PDX MISMATCH exp=0x%0h act=0x%0h", wdata, rdata);
    end
 
    // Idle (post auto-precharge, no row open) -- Precharge Power-Down,
    // then Self-Refresh (sr_req takes priority over pd_req -- see
    // rtl/sdr_ctrl_core.sv -- so these stay mutually exclusive here too).
    $display("[low_power_tb] entering precharge power-down (pd_req=1)");
    apb_set_pd_sr(apbif, 1'b1, 1'b0);
    repeat (10) @(posedge clk);
    $display("[low_power_tb] exiting precharge power-down (pd_req=0)");
    apb_set_pd_sr(apbif, 1'b0, 1'b0);
    repeat (10) @(posedge clk);
 
    $display("[low_power_tb] entering self-refresh (sr_req=1)");
    apb_set_pd_sr(apbif, 1'b0, 1'b1);
    repeat (10) @(posedge clk);
    $display("[low_power_tb] exiting self-refresh (sr_req=0)");
    apb_set_pd_sr(apbif, 1'b0, 1'b0);
    repeat (15) @(posedge clk); // tXSR settle before next access
 
    if (sre_cnt < 1 || srx_cnt < 1) begin
      errors++;
      $error("[low_power_tb] expected >=1 SRE and >=1 SRX, got sre=%0d srx=%0d",
             sre_cnt, srx_cnt);
    end
 
    // Confirm normal access still works after SRX.
    axi_read(aif, addr, rdata);
    if (rdata !== wdata) begin
      errors++;
      $error("[low_power_tb] post-SRX MISMATCH exp=0x%0h act=0x%0h", wdata, rdata);
    end else begin
      $display("[low_power_tb] post-SRX RD MATCH data=0x%0h", rdata);
    end
 
    // --- Auto-PREA-before-PPDE: leave a row open (AP=0) and request
    //     precharge power-down -- PPDE is illegal with any bank active, so
    //     the controller must automatically issue an all-bank PREA (A10=1)
    //     first, then PDE -- see rtl/sdr_ctrl_core.sv "Row lifecycle"
    //     header comment (`need_precharge_all`). ---
    begin
      bit [21:0] open_addr;
      bit [15:0] open_wdata, open_rdata;
      int unsigned prea_before, pde_before;
 
      open_addr  = 22'h000600;
      open_wdata = 16'hD00D;
      $display("[low_power_tb] WR addr=0x%0h, col=0x%0h, row=0x%0h, bank=0x%0h, data=0x%0h (AP=0, row stays open)", open_addr, open_addr[7:0], open_addr[19:8], open_addr[21:20], open_wdata);
      axi_write_noap(aif, open_addr, open_wdata);
 
      prea_before = prea_cnt;
      pde_before  = pde_cnt;
      $display("[low_power_tb] entering precharge power-down (pd_req=1) with a row open");
      apb_set_pd_sr(apbif, 1'b1, 1'b0);
      repeat (10) @(posedge clk);
      $display("[low_power_tb] exiting precharge power-down (pd_req=0)");
      apb_set_pd_sr(apbif, 1'b0, 1'b0);
      repeat (10) @(posedge clk);
 
      if (prea_cnt <= prea_before) begin
        errors++;
        $error("[low_power_tb] expected an automatic all-bank PREA before PDE while a row was open, prea_cnt unchanged at %0d",
               prea_cnt);
      end else begin
        $display("[low_power_tb] observed %0d automatic all-bank PREA(s) ahead of PDE", prea_cnt - prea_before);
      end
      if (pde_cnt <= pde_before) begin
        errors++;
        $error("[low_power_tb] expected >=1 PDE after the auto-PREA, pde_cnt unchanged at %0d", pde_cnt);
      end
 
      // The row closed by the auto-PREA is gone; a fresh AP=1 access
      // confirms normal operation still works afterward.
      axi_read(aif, open_addr, open_rdata);
      if (open_rdata !== open_wdata) begin
        errors++;
        $error("[low_power_tb] post-auto-PREA MISMATCH exp=0x%0h act=0x%0h", open_wdata, open_rdata);
      end else begin
        $display("[low_power_tb] post-auto-PREA RD MATCH data=0x%0h", open_rdata);
      end
    end
 
    repeat (20) @(posedge clk);
 
    if (errors == 0)
      $display("[low_power_tb] PASS (pde=%0d pdx=%0d sre=%0d srx=%0d prea=%0d)",
               pde_cnt, pdx_cnt, sre_cnt, srx_cnt, prea_cnt);
    else
      $display("[low_power_tb] FAIL (%0d error(s))", errors);
 
    $finish;
  end
 
endmodule

