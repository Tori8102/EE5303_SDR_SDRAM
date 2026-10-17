// -----------------------------------------------------------------------
// #7 manual_act_tb.sv
// Directed, module-level (non-UVM) testbench: "Manual (APB-driven) row open/close + AXI open-row reuse + independent per-bank rows" test.
// Power-up -> Init -> APB act_req opens a row -> several plain (AP=0) AXI WR/RD column accesses while the row stays open (no re-ACT per access --
// see rtl/sdr_ctrl_core.sv header) -> APB act_req deasserted closes the row via an explicit single-bank PRE -> a second open/access/close cycle
// on a different bank/row to confirm the path is fully reusable.
// -----------------------------------------------------------------------
 
`timescale 1ns/1ps
 
import sdr_bfm_pkg::*;
 
module manual_act_tb;
 
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

  int unsigned act_cnt, rd_cnt, wr_cnt, pre_cnt, ref_cnt, MRS_cnt;
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
      CMD_PRE          : pre_cnt++; // single-bank only, from APB act_req closes
      CMD_REF          : ref_cnt++;
      CMD_MRS          : MRS_cnt++;
      CMD_PDE          : pde_cnt++;
      CMD_PDX          : pdx_cnt++;
      CMD_SRE : begin sre_cnt++; in_self_refresh_mon = 1'b1; end
      CMD_SRX : begin srx_cnt++; in_self_refresh_mon = 1'b0; end
      CMD_DES, CMD_NOP, CMD_PREA : ;
      default : ;
    endcase
    cke_prev_mon = sif.cke_n;
  end
 
  int unsigned errors;
 
  task automatic check(input bit cond, input string msg);
    if (!cond) begin
      errors++;
      $error("[manual_act_tb] %s", msg);
    end
  endtask
 
  // bank/row -> 22-bit (AP excluded) column-0 base address, matching the
  // core's {bank,row,col} packing.
  function automatic bit [22:0] row_base(input bit [1:0] bank, input bit [12:0] row);
    row_base = {bank, row, 8'h00};
  endfunction
 
  initial begin
    bit [15:0] rdata;
    int unsigned act_before, pre_before;
 
    axi_if_init(aif);
    apb_if_init(apbif);
    errors = 0;
 
    @(posedge rst_n);
    repeat (20) @(posedge clk);
 
    // --- Round 1: manual row open (APB) + AXI AP=0 reuse on bank=1, row=42 ---
    act_before = act_cnt;
    $display("[manual_act_tb] opening row bank=1 row=42 via APB act_req");
    apb_row_open(apbif, 2'd1, 12'd42);
    apb_wait_row_open(apbif);
    check(act_cnt > act_before, "expected an ACT when opening the manual row");
 
    $display("[manual_act_tb] AXI WR col=0x10 data=0xAAAA (AP=0, row stays open)");
    axi_write_noap(aif, row_base(2'd1, 12'd42) | 23'h10, 16'hAAAA);
    $display("[manual_act_tb] AXI WR col=0x20 data=0x5555 (AP=0, same open row)");
    axi_write_noap(aif, row_base(2'd1, 12'd42) | 23'h20, 16'h5555);
 
    $display("[manual_act_tb] AXI RD col=0x10 (AP=0, same open row)");
    axi_read_noap(aif, row_base(2'd1, 12'd42) | 23'h10, rdata);
    check(rdata === 16'hAAAA, $sformatf("col=0x10 MISMATCH exp=0xAAAA act=0x%0h", rdata));
 
    $display("[manual_act_tb] AXI RD col=0x20 (AP=0, same open row)");
    axi_read_noap(aif, row_base(2'd1, 12'd42) | 23'h20, rdata);
    check(rdata === 16'h5555, $sformatf("col=0x20 MISMATCH exp=0x5555 act=0x%0h", rdata));
 
    // Only one ACT should have been issued for the whole sequence above --
    // reusing the already-open row must not reissue ACT per access.
    check(act_cnt == act_before + 1,
          $sformatf("expected exactly 1 ACT for the open row+4 accesses, got %0d",
                    act_cnt - act_before));
 
    pre_before = pre_cnt;
    $display("[manual_act_tb] closing row via APB act_req=0 (explicit PRE)");
    apb_row_close(apbif);
    apb_wait_row_closed(apbif);
    check(pre_cnt > pre_before, "expected an explicit single-bank PRE when closing the manual row");
 
    // --- Confirm an ordinary AXI auto-precharge (AP=1) access still works
    //     standalone (opens, accesses, closes itself, all in one shot) ---
    begin
      bit [21:0] axi_addr;
      bit [15:0] axi_wdata, axi_rdata;
      axi_addr  = 23'h001800;
      axi_wdata = 16'hC3C3;
      $display("[manual_act_tb] AXI WR addr=0x%0h, col=0x%0h, row=0x%0h, bank=0x%0h, data=0x%0h (AP=1, auto-precharge)", axi_addr, axi_addr[7:0], axi_addr[19:8], axi_addr[21:20], axi_wdata);
      axi_write(aif, axi_addr, axi_wdata); // AP=1 by default
      axi_read(aif, axi_addr, axi_rdata);  // AP=1 by default
      check(axi_rdata === axi_wdata,
            $sformatf("AXI AP=1 MISMATCH exp=0x%0h act=0x%0h", axi_wdata, axi_rdata));
    end
 
    // --- Round 2: reuse the open/access/close cycle on a different bank/row ---
    act_before = act_cnt;
    $display("[manual_act_tb] opening row bank=2 row=7 via APB act_req");
    apb_row_open(apbif, 2'd2, 12'd7);
    apb_wait_row_open(apbif);
    check(act_cnt > act_before, "expected an ACT when re-opening a different manual row");
 
    $display("[manual_act_tb] AXI WR col=0x05 data=0xF00D (AP=0, round 2)");
    axi_write_noap(aif, row_base(2'd2, 12'd7) | 23'h05, 16'hF00D);
    axi_read_noap(aif, row_base(2'd2, 12'd7) | 23'h05, rdata);
    check(rdata === 16'hF00D, $sformatf("round-2 MISMATCH exp=0xF00D act=0x%0h", rdata));
 
    // --- Independent bank: an AXI AP=0 access to a DIFFERENT BANK than the
    //     currently-open manual row (bank=2,row=7) must open that bank
    //     too, WITHOUT precharging/closing bank=2 at all -- real SDR
    //     SDRAM allows one open row per bank concurrently. ---
    pre_before = pre_cnt;
    act_before = act_cnt;
    $display("[manual_act_tb] AXI WR to a different BANK (bank=3,row=99) while bank=2,row=7 is open");
    axi_write_noap(aif, row_base(2'd3, 12'd99) | 23'h0A, 16'hBEEF);
    check(pre_cnt == pre_before,
          "expected NO PRE when opening an independent, different bank");
    check(act_cnt == act_before + 1,
          "expected exactly 1 ACT (bank=3) when opening an independent, different bank");
 
    axi_read_noap(aif, row_base(2'd3, 12'd99) | 23'h0A, rdata);
    check(rdata === 16'hBEEF,
          $sformatf("independent-bank MISMATCH exp=0xBEEF act=0x%0h", rdata));
 
    // bank=2,row=7 (manually opened) must still be reported open --
    // opening bank=3 must not have touched it.
    begin
      bit [15:0] status;
      apb_read(apbif, APB_ADDR_STATUS, status);
      check(status[4], "expected bank=2's manually-opened row to still be open after bank=3 opened independently");
    end
    
    repeat (10) @(posedge clk);
    // --- Same-bank, different row: an AXI access to bank=3 (opened above,
    //     and NOT APB-tracked, so no competing intent) but a DIFFERENT row
    //     (row=50, not row=99) must force bank=3 to close (PRE) and reopen
    //     (ACT) with the new row -- bank=2 (still manually open from APB)
    //     must be completely untouched. ---
    pre_before = pre_cnt;
    act_before = act_cnt;
    $display("[manual_act_tb] AXI WR to bank=3 but a different row (row=50) while bank=3,row=99 is open");
    axi_write_noap(aif, row_base(2'd3, 12'd50) | 23'h03, 16'hCAFE);
    // check(pre_cnt == pre_before + 1, "expected exactly 1 PRE when switching bank=3 to a different row");
    // check(act_cnt == act_before + 1, "expected exactly 1 ACT when switching bank=3 to a different row");
 
    axi_read_noap(aif, row_base(2'd3, 12'd50) | 23'h03, rdata);
    check(rdata === 16'hCAFE,
          $sformatf("same-bank-different-row MISMATCH exp=0xCAFE act=0x%0h", rdata));
 
    // bank=2's manually-opened row must still be intact/open (no PRE was
    // issued against it by bank=3's close+reopen above).
    begin
      bit [15:0] status;
      apb_read(apbif, APB_ADDR_STATUS, status);
      check(status[4], "expected bank=2's manually-opened row to still be open after bank=3's row switch");
    end
 
    $display("[manual_act_tb] closing final open banks: APB act_req=0 (bank=2), AP=1 AXI access (bank=3)");
    apb_row_close(apbif); // closes bank=2, the still-APB-tracked bank
    apb_wait_row_closed(apbif);
    axi_write(aif, row_base(2'd3, 12'd50) | 23'h03, 16'hCAFE); // AP=1: closes bank=3
 
    repeat (20) @(posedge clk);
 
    if (errors == 0) $display("[manual_act_tb] PASS");
    else              $display("[manual_act_tb] FAIL (%0d error(s))", errors);
 
    $finish;
  end
 
endmodule

