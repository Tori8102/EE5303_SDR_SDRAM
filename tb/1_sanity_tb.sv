// ----------------------------------------------------------------------- 
// #1 sanity_tb.sv 
// Directed, module-level (non-UVM) testbench: "Sanity test". 
// Power-up -> Init -> WRA -> RDA -> PREA. 
// ----------------------------------------------------------------------- 
`timescale 1ns/1ps 
import sdr_bfm_pkg::*; 
module sanity_tb; 
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
    initial  
    begin 
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
    )  
    dut 
    ( 
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
    sdr_sdram_model  
    #( 
        .DATA_W(DATA_W), .BANK_W(BANK_W), .ROW_W(ROW_W), .COL_W(COL_W) 
    )  
    sdram  
    ( 
        .clk   (clk),   .rst_n (rst_n), 
        .cs_n  (sif.cs_n), .ras_n (sif.ras_n), .cas_n (sif.cas_n), .we_n (sif.we_n), 
        .cke_n (sif.cke_n),  .ba    (sif.ba),    .addr  (sif.addr),  .dqm  (sif.dqm), 
        .dq    (dq_wire) 
    ); 
    int unsigned act_cnt, rd_cnt, wr_cnt, pre_cnt, ref_cnt, MRS_cnt; 
    int unsigned pde_cnt, pdx_cnt, sre_cnt, srx_cnt; 
    bit cke_prev_mon, in_self_refresh_mon; 
    initial  
    begin 
        cke_prev_mon        = 1'b1; 
        in_self_refresh_mon = 1'b0; 
    end 
    always @(posedge clk)  
    begin 
        sdr_cmd_e c; 
        c = decode_sdr_cmd(sif.cs_n, sif.ras_n, sif.cas_n, sif.we_n, sif.addr[AP_BIT], cke_prev_mon, sif.cke_n, in_self_refresh_mon); 
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
    int unsigned errors; 
    initial  
    begin 
        bit [21:0] addr; 
        bit [15:0] wdata, rdata; 
        axi_if_init(aif); 
        apb_if_init(apbif); 
        errors = 0; 
        @(posedge rst_n); 
        repeat (10) @(posedge clk); 
        addr  = 22'h001234; 
        wdata = 16'hBEEF; 
        $display("[sanity_tb] WR addr=0x%0h, col=0x%0h, row=0x%0h, bank=0x%0h, data=0x%0h", addr, addr[7:0], addr[19:8], addr[21:20], wdata); 
        axi_write(aif, addr, wdata); 
        $display("[sanity_tb] RD addr=0x%0h", addr); 
        axi_read(aif, addr, rdata); 
        if (rdata !== wdata) begin 
        errors++; 
        $error("[sanity_tb] MISMATCH addr=0x%0h exp=0x%0h act=0x%0h", addr, wdata, rdata); 
        end else begin 
        $display("[sanity_tb] MATCH addr=0x%0h data=0x%0h", addr, rdata); 
        end 
        repeat (20) @(posedge clk); 
        if (errors == 0)  $display("[sanity_tb] PASS"); 
        else              $display("[sanity_tb] FAIL (%0d error(s))", errors); 
        $finish; 
    end 
endmodule 

