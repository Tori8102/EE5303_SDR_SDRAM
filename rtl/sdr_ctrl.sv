// ---------------------------------------------------------------------------------------------------------- 
// sdr_ctrl.sv 
// 
// SDR SDRAM Controller — top-level with AXI4 (data) and APB (config/status) slave ports 
// 
// Config DQ pins: x16 (DQ data width: 16-bit) 
// Address mapping (AXI address -> bank/row/column, same as core): 
//   awaddr/araddr[23]    = AP     (Decide read/write command has auto-precharge or not) 
//   awaddr/araddr[21:20] = bank   (2 bits -> 4 banks) 
//   awaddr/araddr[19:8]  = row    (12 bits -> 4096 rows) 
//   awaddr/araddr[7:0]   = column (8 bits -> 256 columns) 
// Default density = Bank x Row x Column x DQ-width = 64Mb. 
// Page size = 2^Column * Prefetch_size = 2^Column * DQ-width * Burst-Length 
// 
// Address mapping (APB address rdata -> bank/row): 
//   awaddr/araddr[13:12] = bank   (2 bits -> 4 banks) 
//   awaddr/araddr[11:0]  = row    (12 bits -> 4096 rows) 
// 
// APB register map (word-addressed, byte address bit 2 selects word): 
//   0x00 STATUS (RO): bit0 = init_done, bit1 = ctrl_busy 
//   0x04 CTRL   (RW): bit0 = pd_req,    bit1 = sr_req,      bit2 = mrs_req,     bit3 = act_req 
//   0x08 ROW_ACT_ADDR (RW): [BANK_W+ROW_W-1:0] row_act_addr 
// ---------------------------------------------------------------------------------------------------------- 
module sdr_ctrl #( 
    // SDR SDRAM controller parameter ------------------------------------------- 
    parameter int                       DATA_W = 16,                        // Bit      - AXI data width 
    parameter int                       BANK_W = 2,                         // Bit      - SDR SDRAM bank width 
    parameter int                       ROW_W  = 12,                        // Bit      - SDR SDRAM row width 
    parameter int                       COL_W  = 8,                         // Bit      - SDR SDRAM column width 
    parameter int                       ADDR_W = BANK_W + ROW_W + COL_W + 1,// Bit      - AXI address width, depends on option AP, bank, row and column 
    parameter int                       ID_W   = 4,                         // Bit      - AXI ID width 
    parameter int                       T_RCD  = 2,                         // nCK      - Timing param ACTIVE -> READ/WRITE 
    parameter int                       T_RP   = 2,                         // nCK      - Timing param internal auto-precharge settle time before next ACTIVE 
    parameter int                       T_RAS  = 4,                         // nCK      - Timing param ACTIVE to PRECHARGE minimum row active time 
    parameter int                       T_RFC  = 3,                         // nCK      - Timing param AUTO REFRESH -> next command (init sequence) 
    parameter int                       T_MRD  = 2,                         // nCK      - Timing param LOAD MODE REGISTER -> next command 
    parameter int                       T_XSR  = 3,                         // nCK      - Timing param SRE -> First valid command 
    parameter int                       T_REFI = 64,                        // nCK      - Timing param REFRESH commmand period 
    parameter int                       T_POR  = 4,                         // nCK      - Timing param initialization delay 
    parameter int                       T_CL   = 2,                         // nCK      - Timing param CAS latency (READ -> data valid), also coded into MRS 
    parameter int                       BL_ENC = 3'b000                     //          - Burst Length field for MRS (000 = BL1, this design is single-word) 
) 
( 
    // Clock & Reset ------------------------------------------------------------ 
    input  logic                        clk, 
    input  logic                        rst_n, 
    // AXI4 Slave Interface (data path) ----------------------------------------- 
    // Write Address Channel 
    input  logic                        axi_s_awvalid, 
    output logic                        axi_s_awready, 
    input  logic [ADDR_W-1:0]           axi_s_awaddr, 
    input  logic [ID_W-1:0]             axi_s_awid, 
    input  logic [7:0]                  axi_s_awlen, 
    input  logic [2:0]                  axi_s_awsize, 
    input  logic [1:0]                  axi_s_awburst,  
    // Write Data Channel 
    input  logic                        axi_s_wvalid, 
    output logic                        axi_s_wready, 
    input  logic [DATA_W-1:0]           axi_s_wdata, 
    input  logic [(DATA_W/8)-1:0]       axi_s_wstrb, 
    input  logic                        axi_s_wlast, 
    // Write Response Channel 
    output logic                        axi_s_bvalid, 
    input  logic                        axi_s_bready, 
    output logic [1:0]                  axi_s_bresp, 
    output logic [ID_W-1:0]             axi_s_bid,  
    // Read Address Channel 
    input  logic                        axi_s_arvalid, 
    output logic                        axi_s_arready, 
    input  logic [ADDR_W-1:0]           axi_s_araddr, 
    input  logic [ID_W-1:0]             axi_s_arid, 
    input  logic [7:0]                  axi_s_arlen, 
    input  logic [2:0]                  axi_s_arsize, 
    input  logic [1:0]                  axi_s_arburst, 
    // Read Data Channel 
    output logic                        axi_s_rvalid, 
    input  logic                        axi_s_rready, 
    output logic [DATA_W-1:0]           axi_s_rdata, 
    output logic [1:0]                  axi_s_rresp, 
    output logic                        axi_s_rlast, 
    output logic [ID_W-1:0]             axi_s_rid, 
    // APB Slave Interface (config/status) -------------------------------------- 
    input  logic                        apb_s_psel, 
    input  logic                        apb_s_penable, 
    input  logic                        apb_s_pwrite, 
    input  logic [7:0]                  apb_s_paddr, 
    input  logic [DATA_W-1:0]           apb_s_pwdata, 
    output logic [DATA_W-1:0]           apb_s_prdata, 
    output logic                        apb_s_pready, 
    output logic                        apb_s_pslverr, 
    // SDR SDRAM (back-end) interface ------------------------------------------- 
    output logic                        sdr_cke_n, 
    output logic                        sdr_cs_n, 
    output logic                        sdr_ras_n, 
    output logic                        sdr_cas_n, 
    output logic                        sdr_we_n, 
    output logic [BANK_W-1:0]           sdr_ba, 
    output logic [ROW_W-1:0]            sdr_addr, 
    output logic                        sdr_dqm, 
    inout  wire  [DATA_W-1:0]           sdr_dq 
); 
    // AXI OKAY response (no error reporting from the core in this demo) 
    localparam logic [1:0]  AXI_RESP_OKAY = 2'b00; 
    // Format width of address 
    localparam int          MEM_ADDR_W = BANK_W + ROW_W + COL_W; 
    // ----------------------------------------------------------------- 
    // Internal single-outstanding request/response bus to sdr_ctrl_core 
    // ----------------------------------------------------------------- 
    bit                                 core_req_valid; 
    bit                                 core_req_ready; 
    bit                                 core_req_wr; 
    bit                                 core_req_ap; 
    logic        [ADDR_W-2:0]           core_req_addr; 
    logic        [DATA_W-1:0]           core_req_wdata; 
    bit                                 core_resp_valid; 
    bit                                 core_resp_ready; 
    logic        [DATA_W-1:0]           core_resp_rdata; 
    bit                                 init_done; 
    bit                                 ctrl_busy; 
    bit                                 pd_req; 
    bit                                 sr_req; 
    bit                                 mrs_req; 
    bit                                 act_req; 
    logic       [BANK_W+ROW_W-1:0]      row_act_addr; 
    bit                                 row_open;  
    bit                                 pd_active; 
    bit                                 sr_active; 
    sdr_ctrl_core #( 
        .DATA_W                         (DATA_W),  
        .BANK_W                         (BANK_W),  
        .ROW_W                          (ROW_W),  
        .COL_W                          (COL_W), 
        .T_RCD                          (T_RCD),  
        .T_RP                           (T_RP),  
        .T_RAS                          (T_RAS), 
        .T_RFC                          (T_RFC),  
        .T_MRD                          (T_MRD), 
        .T_XSR                          (T_XSR), 
        .T_REFI                         (T_REFI), 
        .T_POR                          (T_POR), 
        .T_CL                           (T_CL),  
        .BL_ENC                         (BL_ENC) 
    ) 
    u_core  
    ( 
        .clk                            (clk), 
        .rst_n                          (rst_n), 
        .req_valid                      (core_req_valid), 
        .req_ready                      (core_req_ready), 
        .req_wr                         (core_req_wr), 
        .req_ap                         (core_req_ap),       
        .req_addr                       (core_req_addr), 
        .req_wdata                      (core_req_wdata), 
        .resp_valid                     (core_resp_valid), 
        .resp_ready                     (core_resp_ready), 
        .resp_rdata                     (core_resp_rdata), 
        .pd_req                         (pd_req), 
        .sr_req                         (sr_req), 
        .mrs_req                        (mrs_req), 
        .row_act_req                    (act_req), 
        .row_act_bank                   (row_act_addr[BANK_W+ROW_W-1 -: BANK_W]), 
        .row_act_row                    (row_act_addr[ROW_W-1:0]), 
        .row_open                       (row_open), 
        .init_done                      (init_done), 
        .ctrl_busy                      (ctrl_busy), 
        .pd_active                      (pd_active), 
        .sr_active                      (sr_active), 
        .sdr_cke_n                      (sdr_cke_n), 
        .sdr_cs_n                       (sdr_cs_n), 
        .sdr_ras_n                      (sdr_ras_n), 
        .sdr_cas_n                      (sdr_cas_n), 
        .sdr_we_n                       (sdr_we_n), 
        .sdr_ba                         (sdr_ba), 
        .sdr_addr                       (sdr_addr), 
        .sdr_dqm                        (sdr_dqm), 
        .sdr_dq                         (sdr_dq) 
    ); 
    // ----------------------------------------------------------------- 
    // AXI4-slave <-> internal-bus adapter 
    // Design only single-outstanding: accepts one AW+W pair or one AR at a time (write transaction has priority when both are pending) 
    // Issues it to the core, then waits for the core's resp_valid pulse before returning B or R and accepting the next transaction. Only single-beat bursts are supported. 
    // ----------------------------------------------------------------- 
    // Generalized multi-beat (INCR) burst support -- AWLEN/ARLEN are now honored instead of assuming single-beat-only transfers. 
	// Each write beat is individually issued to the core as its WDATA arrives; a single BVALID is returned only after the beat tagged WLAST (
	// (the AWLEN'th additional beat) completes. Each read beat individually returns its own RVALID, with RLAST asserted only on the final beat.
    // Auto-precharge (the AP address bit) is applied only on the final beat of a burst, so the row stays open across the intermediate beats -- matching real SDR SDRAM burst semantics.
    typedef enum logic [1:0] {
        AXI_IDLE,
        AXI_WAIT_CORE,
        AXI_RESP_WR,
        AXI_RESP_RD
    } axi_state_e;
    axi_state_e 						axi_state;
    axi_state_e 						axi_next_state;
    bit 								pending_is_wr;
    logic [ID_W-1:0] 					pending_id;
    bit 								cur_beat_is_last; 			// latched at issue time, used once core_resp_valid returns
	logic [DATA_W-1:0]					rdata_hold;
    // -----------------------------------------------------------------
    // AW and W are independent AXI4 channels: a compliant slave must not make AWREADY wait on WVALID, nor WREADY wait on AWVALID (a master is
    // free to present the address and data phases of a write on different cycles, in either order). Each channel is captured into its own
    // one-deep buffer as soon as it individually handshakes; the first beat of the write is issued to the core once both are present.
    // -----------------------------------------------------------------
    bit                 				aw_cap_valid;
    logic [ADDR_W-1:0]    				aw_cap_addr;
    logic [ID_W-1:0]      				aw_cap_id;
    logic [7:0]           				aw_cap_len;   // buffered AWLEN (burst length - 1)
    bit                 				w_cap_valid;
    logic [DATA_W-1:0]    				w_cap_data;

    // AR gets the exact same one-deep capture buffer as AW, so a new read address can be accepted and held even while a write is currently executing through
    // the (single, shared) core -- previously there was no AR buffer at all, so ARREADY could only ever asset on the exact cycle a read was about to be dispatched,
    // which incorrectly tied address-channel acceptance to the core's execution state
    bit                 				ar_cap_valid;
    logic [ADDR_W-1:0]    				ar_cap_addr;
    logic [ID_W-1:0]      				ar_cap_id;
    logic [7:0]           				ar_cap_len;   // buffered ARLEN (burst length - 1)

    // WLAST itself is not latched/used -- "last beat" is tracked authoritatively from the AW channel's AWLEN countdown (eff_wr_len),
    // not re-derived from the W channel's WLAST, so a mismatched WLAST from the master cannot desync the burst's beat accounting.
    // write-burst-in-progress context, valid from the 2nd beatonward (the 1st beat still comes straight off the AW/W channels).
    bit                  				wr_burst_active;
    logic [MEM_ADDR_W-1:0] 				wr_addr_next_r;
    bit                  				wr_ap_bit_r;
    logic [ID_W-1:0]       				wr_id_r;
    logic [7:0]            				wr_len_r;     // beats remaining AFTER the current one

    // read-burst-in-progress context, same shape as the write side.
    bit                  				rd_burst_active;
    logic [MEM_ADDR_W-1:0] 				rd_addr_next_r;
    bit                  				rd_ap_bit_r;
    logic [ID_W-1:0]       				rd_id_r;
    logic [7:0]            				rd_len_r;
    bit                 				aw_have;
    bit                 				w_have;
    bit                 				ar_have;
    bit                 				write_issue;
    bit                 				read_issue;
    logic [ADDR_W-1:0]    				eff_aw_addr;
    logic [ID_W-1:0]      				eff_aw_id;
    logic [DATA_W-1:0]    				eff_w_data;
    logic [7:0]           				eff_aw_len; 
    logic [ADDR_W-1:0]    				eff_ar_addr;
    logic [ID_W-1:0]      				eff_ar_id;
    logic [7:0]           				eff_ar_len; 

    // This beat's effective write address/id/len/ap -- taken from the live AW/W channels (or their one-deep buffers) for the first beat of
    // a burst, or from the registered burst context for later beats.
    logic [MEM_ADDR_W-1:0]				eff_wr_mem_addr;
    bit                 				eff_wr_ap_bit;
    logic [ID_W-1:0]      				eff_wr_id;
    logic [7:0]           				eff_wr_len;
    bit                 				eff_wr_last_beat;
    // For the read side.
    logic [MEM_ADDR_W-1:0]				eff_rd_mem_addr;
    logic                 				eff_rd_ap_bit;
    logic [ID_W-1:0]      				eff_rd_id;
    logic [7:0]           				eff_rd_len;
    logic                 				eff_rd_last_beat;

    // AWREADY/WREADY: each asserted solely based on its own buffer being free -- no dependency on the other channel's VALID. Also held off
    // while a read burst is in progress (single-outstanding ordering). Explicitly qualified with rst_n so READY cannot read as 1 combinationally during reset.
    assign axi_s_awready = rst_n && !aw_cap_valid && !wr_burst_active; 
    assign aw_have = wr_burst_active || aw_cap_valid || (axi_s_awvalid && axi_s_awready);
    assign axi_s_wready  = rst_n && !w_cap_valid && aw_have;
    assign w_have  = w_cap_valid  || (axi_s_wvalid  && axi_s_wready);
    assign eff_aw_addr = aw_cap_valid ? aw_cap_addr : axi_s_awaddr;
    assign eff_aw_id   = aw_cap_valid ? aw_cap_id   : axi_s_awid;
    assign eff_aw_len  = aw_cap_valid ? aw_cap_len  : axi_s_awlen;

    // Mux this beat's write context between "first beat of a new burst" (off the AW/W channels) and "later beat" (off the registered burst context).
    assign eff_wr_mem_addr = wr_burst_active ? wr_addr_next_r        : eff_aw_addr[MEM_ADDR_W-1:0];
    assign eff_wr_ap_bit   = wr_burst_active ? wr_ap_bit_r           : eff_aw_addr[ADDR_W-1];
    assign eff_wr_id       = wr_burst_active ? wr_id_r               : eff_aw_id;
    assign eff_wr_len      = wr_burst_active ? wr_len_r              : eff_aw_len;
    assign eff_wr_last_beat = (eff_wr_len == 8'd0);

    bit req_select_is_wr;
    assign req_select_is_wr = aw_have && w_have; // write priority, decoupled from core_req_ready
    assign write_issue = rst_n && (axi_state == AXI_IDLE) && core_req_ready && req_select_is_wr; //req_select_is_wr (was aw_have && w_have directly)

    // ARREADY/RREADY
    assign axi_s_arready = rst_n && !ar_cap_valid && !rd_burst_active;
    assign ar_have = rd_burst_active || ar_cap_valid || (axi_s_arvalid && axi_s_arready); 
    assign eff_ar_addr = ar_cap_valid ? ar_cap_addr : axi_s_araddr;
    assign eff_ar_id = ar_cap_valid ? ar_cap_id : axi_s_arid;
    assign eff_ar_len = ar_cap_valid ? ar_cap_len : axi_s_arlen;

    assign read_issue = rst_n && (axi_state == AXI_IDLE) && core_req_ready && !req_select_is_wr && ar_have;

    assign eff_rd_mem_addr = rd_burst_active ? rd_addr_next_r : eff_ar_addr[MEM_ADDR_W-1:0];
    assign eff_rd_ap_bit   = rd_burst_active ? rd_ap_bit_r    : eff_ar_addr[ADDR_W-1];
    assign eff_rd_id       = rd_burst_active ? rd_id_r        : eff_ar_id;
    assign eff_rd_len      = rd_burst_active ? rd_len_r       : eff_ar_len;
    assign eff_rd_last_beat = (eff_rd_len == 8'd0);
    assign eff_w_data = w_cap_valid ? w_cap_data : axi_s_wdata;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_cap_valid <= 1'b0;
            aw_cap_addr  <= '0;
            aw_cap_id    <= '0;
            aw_cap_len   <= '0;
        end else if (write_issue) begin
            aw_cap_valid <= 1'b0;
        end else if (axi_s_awvalid && axi_s_awready) begin
            aw_cap_valid <= 1'b1;
            aw_cap_addr  <= axi_s_awaddr;
            aw_cap_id    <= axi_s_awid;
            aw_cap_len   <= axi_s_awlen;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_cap_valid <= 1'b0;
            ar_cap_addr  <= '0;
            ar_cap_id    <= '0;
            ar_cap_len   <= '0;
        end else if (read_issue) begin
            ar_cap_valid <= 1'b0;
        end else if (axi_s_arvalid && axi_s_arready) begin
            ar_cap_valid <= 1'b1;
            ar_cap_addr  <= axi_s_araddr;
            ar_cap_id    <= axi_s_arid;
            ar_cap_len   <= axi_s_arlen;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_cap_valid <= 1'b0;
            w_cap_data  <= '0;
        end else if (write_issue) begin
            w_cap_valid <= 1'b0;
        end else if (axi_s_wvalid && axi_s_wready) begin
            w_cap_valid <= 1'b1;
            w_cap_data  <= axi_s_wdata;
        end
    end

    // Write-burst context -- advances the running address/len on every beat issued, and sets/clears wr_burst_active across beats 2..N
	// of a multi-beat burst (beat 1 is handled by the AW/W buffers above).
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_burst_active <= 1'b0;
            wr_addr_next_r  <= '0;
            wr_ap_bit_r     <= 1'b0;
            wr_id_r         <= '0;
            wr_len_r        <= '0;
        end else if (write_issue) begin
            if (!wr_burst_active) begin
                if (eff_aw_len != 8'd0) begin
                    wr_burst_active <= 1'b1;
                    wr_addr_next_r  <= eff_aw_addr[MEM_ADDR_W-1:0] + 1'b1;
                    wr_ap_bit_r     <= eff_aw_addr[ADDR_W-1];
                    wr_id_r         <= eff_aw_id;
                    wr_len_r        <= eff_aw_len - 8'd1;
                end
            end else if (!eff_wr_last_beat) begin
                wr_addr_next_r <= wr_addr_next_r + 1'b1;
                wr_len_r       <= wr_len_r - 8'd1;
            end else begin
                wr_burst_active <= 1'b0;
            end
        end
    end

    // Read-burst context, mirroring the write side
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_burst_active <= 1'b0;
            rd_addr_next_r  <= '0;
            rd_ap_bit_r     <= 1'b0;
            rd_id_r         <= '0;
            rd_len_r        <= '0;
        end else if (read_issue) begin
            if (!rd_burst_active) begin
                if (eff_ar_len != 8'd0) begin
                    rd_burst_active <= 1'b1;
                    rd_addr_next_r  <= eff_ar_addr[MEM_ADDR_W-1:0] + 1'b1;
                    rd_ap_bit_r     <= eff_ar_addr[ADDR_W-1];
                    rd_id_r         <= eff_ar_id;
                    rd_len_r        <= eff_ar_len - 8'd1;
                end
            end else if (!eff_rd_last_beat) begin
                rd_addr_next_r <= rd_addr_next_r + 1'b1;
                rd_len_r       <= rd_len_r - 8'd1;
            end else begin
                rd_burst_active <= 1'b0;
            end
        end
    end

	always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata_hold <= '0;
        end 
		else if ((axi_state == AXI_WAIT_CORE) && core_resp_valid && !pending_is_wr) begin
            rdata_hold <= core_resp_rdata;
        end
    end

    always_ff @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            pending_is_wr    <= 1'b0;
            pending_id       <= '0;
            cur_beat_is_last <= 1'b0;
        end
        else if (write_issue || read_issue)
        begin
            pending_is_wr    <= write_issue;
            pending_id       <= write_issue ? eff_wr_id : eff_rd_id; //  eff_wr_id/eff_rd_id (burst-aware)
            cur_beat_is_last <= write_issue ? eff_wr_last_beat : eff_rd_last_beat; // 
        end
        else
        begin
            pending_is_wr    <= pending_is_wr;
            pending_id       <= pending_id;
            cur_beat_is_last <= cur_beat_is_last;
        end
    end

    always_ff @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
            axi_state <= AXI_IDLE;
        else
            axi_state <= axi_next_state;
    end

    always_comb
    begin
        axi_next_state = axi_state;
        case (axi_state)
            AXI_IDLE:
            begin
                if (write_issue || read_issue)
                begin
                    axi_next_state = AXI_WAIT_CORE;
                end
                else
                begin
                    axi_next_state = AXI_IDLE;
                end
            end
            AXI_WAIT_CORE:
            begin
                if (core_resp_valid)
                begin
                    if (pending_is_wr)
                        axi_next_state = cur_beat_is_last ? AXI_RESP_WR : AXI_IDLE;
                    else
                        axi_next_state = AXI_RESP_RD;
                end
                else
                begin
                    axi_next_state = AXI_WAIT_CORE;
                end
            end
            AXI_RESP_WR:
            begin
                if (axi_s_bready)
                begin
                    axi_next_state = AXI_IDLE;
                end
                else
                begin
                    axi_next_state = AXI_RESP_WR;
                end
            end
            AXI_RESP_RD:
            begin
                if (axi_s_rready)
                begin
                    axi_next_state = AXI_IDLE;
                end
                else
                begin
                    axi_next_state = AXI_RESP_RD;
                end
            end
            default: axi_next_state = AXI_IDLE;
        endcase
    end

    assign core_req_valid   = write_issue || read_issue;
    assign core_req_wr      = req_select_is_wr;
    // AP/auto-precharge asserted only on the final beat of the burst, so
    // the row stays open across the intermediate beats.
    assign core_req_ap      = req_select_is_wr ? (eff_wr_last_beat && eff_wr_ap_bit)
                                                : (eff_rd_last_beat && eff_rd_ap_bit);
    assign core_req_addr    = req_select_is_wr ? eff_wr_mem_addr : eff_rd_mem_addr; // burst-aware address
    assign core_req_wdata   = eff_w_data;
    assign core_resp_ready  = (axi_state == AXI_WAIT_CORE);
    assign axi_s_bvalid     = (axi_state == AXI_RESP_WR);
    assign axi_s_bresp      = AXI_RESP_OKAY;
    assign axi_s_bid        = pending_id;
    assign axi_s_rvalid     = (axi_state == AXI_RESP_RD);
    assign axi_s_rdata      = rdata_hold;
    assign axi_s_rresp      = AXI_RESP_OKAY;
    assign axi_s_rlast      = axi_s_rvalid && cur_beat_is_last;
    assign axi_s_rid        = pending_id;

    // ----------------------------------------------------------------- 
    // APB slave: status register file (zero wait-state) 
    //  0x00 STATUS (RO): bit0 = init_done, bit1 = ctrl_busy 
    //  0x04 CTRL (RW) 
    //  0x08 ROW_ACT_ADDR (RW) 
    // ----------------------------------------------------------------- 

    assign apb_s_pready  = 1'b1; 
    assign apb_s_pslverr = 1'b0; 
    
	bit    apb_write_fire; 
    assign apb_write_fire = apb_s_psel && apb_s_penable && apb_s_pwrite; 
    assign mrs_req        = apb_write_fire && (apb_s_paddr[7:2] == 6'h1) && apb_s_pwdata[2]; 
    always_ff @(posedge clk or negedge rst_n) 
    begin 
        if (!rst_n) 
        begin 
            pd_req  <= 0; 
            sr_req  <= 0; 
            act_req <= 0; 
        end 
        else if (apb_write_fire && apb_s_paddr[7:2] == 6'h1) 
        begin 
            pd_req  <= apb_s_pwdata[0]; 
            sr_req  <= apb_s_pwdata[1]; 
            act_req <= apb_s_pwdata[3]; 
        end 
        else 
        begin 
            pd_req  <= pd_req; 
            sr_req  <= sr_req; 
            act_req <= act_req; 
        end  
    end 
    always_ff @(posedge clk or negedge rst_n) 
    begin 
        if (!rst_n) 
        begin 
            row_act_addr <= '0; 
        end 
        else if (apb_write_fire && apb_s_paddr[7:2] == 6'h2) 
        begin 
            row_act_addr <= apb_s_pwdata[BANK_W+ROW_W-1:0]; 
        end 
        else 
        begin 
            row_act_addr <= row_act_addr; 
        end 
    end 
    always_comb  
    begin 
        apb_s_prdata = '0; 
        case (apb_s_paddr[7:2]) 
            6'h0    : apb_s_prdata = {{(DATA_W-5){1'b0}}, row_open, sr_active, pd_active, ctrl_busy, init_done}; 
            6'h1    : apb_s_prdata = {{(DATA_W-4){1'b0}}, act_req, 1'b0/*mrs_req*/, sr_req, pd_req}; 
            6'h2    : apb_s_prdata = {{(DATA_W-BANK_W-ROW_W){1'b0}}, row_act_addr}; 
            default : apb_s_prdata = '0; 
        endcase 
    end 
endmodule 