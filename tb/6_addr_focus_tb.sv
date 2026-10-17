// -----------------------------------------------------------------------
// #6 addr_focus_tb.sv
// Directed, module-level (non-UVM) testbench #6: "Focus check write-read: same bank, diff bank, critical address". 
// Covers: 
// (a) two accesses to the same bank/row, different column
// (b) two accesses to different banks, same row/column, 
// (c) the min/max row and column boundary addresses (the "critical" addresses: row=0, row=max, col=0, col=max).
// -----------------------------------------------------------------------
 
`timescale 1ns/1ps
 
import sdr_bfm_pkg::*;
 
module addr_focus_tb;
 
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
      CMD_PRE, CMD_PREA: pre_cnt++;
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
 
  // Address layout: {bank[BANK_W-1:0], row[ROW_W-1:0], col[COL_W-1:0]}
  // (see rtl/sdr_ctrl_core.sv cur_bank/cur_row/cur_col latch).
  function automatic bit [21:0] mk_addr(bit [1:0] bank, bit [11:0] row, bit [7:0] col);
    return {bank, row, col};
  endfunction
 
  int unsigned errors;
 
  task automatic check_wr_rd(input bit [21:0] addr, input bit [15:0] wdata, input string tag);
    bit [15:0] rdata;
    $display("[addr_focus_tb] %s WR addr=0x%0h, col=0x%0h, row=0x%0h, bank=0x%0h, data=0x%0h", tag, addr, addr[7:0], addr[19:8], addr[21:20], wdata);
    axi_write(aif, addr, wdata);
    axi_read(aif, addr, rdata);
    if (rdata !== wdata) begin
      errors++;
      $error("[addr_focus_tb] %s MISMATCH addr=0x%0h exp=0x%0h act=0x%0h", tag, addr, wdata, rdata);
    end else begin
      $display("[addr_focus_tb] %s MATCH addr=0x%0h data=0x%0h", tag, addr, rdata);
    end
  endtask
 
  initial begin
    bit [21:0] a0, a1, a2, a3, a_min, a_max;
 
    axi_if_init(aif);
    apb_if_init(apbif);
    errors = 0;
 
    @(posedge rst_n);
    repeat (10) @(posedge clk);
 
    // (a) Same bank, same row, different column.
    a0 = mk_addr(2'd1, 12'd10, 8'd0);
    a1 = mk_addr(2'd1, 12'd10, 8'd1);
    check_wr_rd(a0, 16'h1111, "same-bank/row col=0");
    check_wr_rd(a1, 16'h2222, "same-bank/row col=1");
    begin
      bit [15:0] rdata;
      axi_read(aif, a0, rdata);
      if (rdata !== 16'h1111) begin
        errors++;
        $error("[addr_focus_tb] same-bank/row addr=0x%0h clobbered: exp=0x1111 act=0x%0h",
               a0, rdata);
      end
    end
 
    // (b) Different banks, same row/column.
    a2 = mk_addr(2'd0, 12'd20, 8'd5);
    a3 = mk_addr(2'd3, 12'd20, 8'd5);
    check_wr_rd(a2, 16'h3333, "diff-bank row/col bank=0");
    check_wr_rd(a3, 16'h4444, "diff-bank row/col bank=3");
    begin
      bit [15:0] rdata;
      axi_read(aif, a2, rdata);
      if (rdata !== 16'h3333) begin
        errors++;
        $error("[addr_focus_tb] diff-bank addr=0x%0h clobbered: exp=0x3333 act=0x%0h",
               a2, rdata);
      end
    end
 
    // (c) Critical boundary addresses: min/max row and column.
    a_min = mk_addr(2'd2, 12'd0,    8'd0);
    a_max = mk_addr(2'd2, 12'hFFF, 8'hFF);
    check_wr_rd(a_min, 16'h5A5A, "critical row=0/col=0");
    check_wr_rd(a_max, 16'hA5A5, "critical row=max/col=max");
 
    repeat (20) @(posedge clk);
 
    if (errors == 0) $display("[addr_focus_tb] PASS");
    else              $display("[addr_focus_tb] FAIL (%0d error(s))", errors);
 
    $finish;
  end
 
endmodule

