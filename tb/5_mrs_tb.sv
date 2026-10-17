// -----------------------------------------------------------------------
// #5 mrs_tb.sv
// Directed, module-level (non-UVM) testbench "MRS test".
// Power-up -> Init (includes the mandatory initial MRS) -> WR -> RD -> PREA -> MRS (re-issue via APB CTRL.mrs_req, write-1-to-pulse, see rtl/sdr_ctrl.sv register map) -> WR -> RD -> PREA. 
// -----------------------------------------------------------------------
 
`timescale 1ns/1ps
 
import sdr_bfm_pkg::*;
 
module mrs_tb;
 
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
    .cke_n (sif.cke_n),  .ba    (sif.ba),    .addr  (sif.addr),  .dqm  (sif.dqm),
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
 
  localparam bit [7:0] APB_ADDR_STATUS = 8'h00;
 
  task automatic wait_ctrl_idle();
    bit [15:0] status;
    do begin
      apb_read(apbif, APB_ADDR_STATUS, status);
    end while (status[1]); // ctrl_busy
  endtask
 
  int unsigned errors;
 
  initial begin
    bit [21:0] addr;
    bit [15:0] wdata, rdata;
    int unsigned MRS_cnt_before;
 
    axi_if_init(aif);
    apb_if_init(apbif);
    errors = 0;
 
    @(posedge rst_n);
    repeat (20) @(posedge clk);
 
    // S_INIT issues the mandatory initial MRS.
    if (MRS_cnt < 1) begin
      errors++;
      $error("[mrs_tb] expected >=1 MRS from S_INIT, got %0d", MRS_cnt);
    end
 
    addr  = 22'h000C00;
    wdata = 16'hC0DE;
    $display("[mrs_tb] WR addr=0x%0h, col=0x%0h, row=0x%0h, bank=0x%0h, data=0x%0h", addr, addr[7:0], addr[19:8], addr[21:20], wdata);
    axi_write(aif, addr, wdata);
 
    axi_read(aif, addr, rdata);
    if (rdata !== wdata) begin
      errors++;
      $error("[mrs_tb] pre-MRS MISMATCH exp=0x%0h act=0x%0h", wdata, rdata);
    end
 
    repeat (10) @(posedge clk); // let the WR/RD auto-precharge settle (PREA)
 
    wait_ctrl_idle();
    MRS_cnt_before = MRS_cnt;
    $display("[mrs_tb] pulsing mrs_req to re-issue LOAD_MODE");
    apb_mrs_pulse(apbif);
    repeat (10) @(posedge clk);
 
    if (MRS_cnt <= MRS_cnt_before) begin
      errors++;
      $error("[mrs_tb] expected a second MRS after mrs_req pulse, MRS_cnt unchanged at %0d", MRS_cnt);
    end else begin
      $display("[mrs_tb] observed re-issued MRS (MRS_cnt=%0d)", MRS_cnt);
    end
 
    addr  = 22'h000D00;
    wdata = 16'hBEAD;
    $display("[mrs_tb] post-MRS WR addr=0x%0h, col=0x%0h, row=0x%0h, bank=0x%0h, data=0x%0h", addr, addr[7:0], addr[19:8], addr[21:20], wdata);
    axi_write(aif, addr, wdata);
 
    axi_read(aif, addr, rdata);
    if (rdata !== wdata) begin
      errors++;
      $error("[mrs_tb] post-MRS MISMATCH exp=0x%0h act=0x%0h", wdata, rdata);
    end else begin
      $display("[mrs_tb] post-MRS RD MATCH data=0x%0h", rdata);
    end

    begin
      bit [21:0] open_addr;
      bit [15:0] open_wdata, open_rdata;
      int unsigned prea_before, MRS_cnt_before2;
 
      open_addr  = 22'h000E00;
      open_wdata = 16'hFEED;
      $display("[mrs_tb] WR addr=0x%0h, col=0x%0h, row=0x%0h, bank=0x%0h, data=0x%0h (AP=0, row stays open)", open_addr, open_addr[7:0], open_addr[19:8], open_addr[21:20], open_wdata);
      axi_write_noap(aif, open_addr, open_wdata);
 
      // wait_ctrl_idle();
      prea_before     = prea_cnt;
      MRS_cnt_before2 = MRS_cnt;
      $display("[mrs_tb] pulsing mrs_req with a row open to force an auto-PREA before LOAD_MODE");
      apb_mrs_pulse(apbif);
      repeat (10) @(posedge clk);
 
      if (prea_cnt <= prea_before) begin
        errors++;
        $error("[mrs_tb] expected an automatic all-bank PREA before MRS while a row was open, prea_cnt unchanged at %0d",
               prea_cnt);
      end else begin
        $display("[mrs_tb] observed %0d automatic all-bank PREA(s) ahead of MRS", prea_cnt - prea_before);
      end
      if (MRS_cnt <= MRS_cnt_before2) begin
        errors++;
        $error("[mrs_tb] expected a third MRS after the auto-PREA, MRS_cnt unchanged at %0d", MRS_cnt);
      end
 
      // The row closed by the auto-PREA is gone; a fresh AP=1 access
      // confirms normal operation still works afterward.
      axi_read(aif, open_addr, open_rdata);
      if (open_rdata !== open_wdata) begin
        errors++;
        $error("[mrs_tb] post-auto-PREA MISMATCH exp=0x%0h act=0x%0h", open_wdata, open_rdata);
      end else begin
        $display("[mrs_tb] post-auto-PREA RD MATCH data=0x%0h", open_rdata);
      end
    end
 
    repeat (20) @(posedge clk);
 
    if (errors == 0) $display("[mrs_tb] PASS (MRS_cnt=%0d prea_cnt=%0d)", MRS_cnt, prea_cnt);
    else              $display("[mrs_tb] FAIL (%0d error(s))", errors);
 
    $finish;
  end
 
endmodule

