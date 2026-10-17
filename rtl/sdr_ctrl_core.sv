// ----------------------------------------------------------------------- 
// sdr_ctrl_core.sv 
// 
// SDR SDRAM command/timing core FSM (internal block, instantiated by sdr_ctrl.sv, which exposes the real AXI4 + APB ports). 
// 
// This design always uses RDA/WRA (A10=1, auto-precharge) instead of a separate explicit PRECHARGE command per access, since every access here 
// closes its row immediately (no page-mode/row-reuse optimization). 
// ----------------------------------------------------------------------- 
module sdr_ctrl_core #( 
    // SDR SDRAM controller parameter ------------------------------------------- 
    parameter int                           DATA_W = 16, 
    parameter int                           BANK_W = 2, 
    parameter int                           ROW_W  = 12, 
    parameter int                           COL_W  = 8, 
    parameter int                           T_RCD  = 2,             // Timing param ACTIVE -> READ/WRITE 
    parameter int                           T_RP   = 2,             // Timing param internal auto-precharge settle time before next ACTIVE 
    parameter int                           T_RAS  = 4,             // min ACT -> auto-precharge row-active time (tRAS); the effective row-active hold used is max(T_RCD+T_CL, T_RAS), 
                                                                    // so tRC (= tRAS+tRP minimum) is automatically satisfied too 
    parameter int                           T_RFC  = 3,             // REF -> next command, init sequence (tRFC) 
    parameter int                           T_MRD  = 2,             // Timing param LOAD MODE REGISTER -> next command 
    parameter int                           T_XSR  = 3,             // Timing param SRE -> First valid command 
    parameter int                           T_REFI = 64,            // Cycles between periodic AUTO REFRESH commands while idle (tREFI; demo-scaled like the other T_* timing parameters -- 
                                                                    // real SDR SDRAM is ~7.8us between refreshes, not 32 clocks) 
    parameter int                           T_REF_MARGIN = T_RP+1,  // How many cycles before the nominal tREFI deadline an open bank's auto-precharge-all must be started before reaching tREFI
    parameter int                           T_POR  = 4,             // Power-up delay after reset, held in S_INIT issuing NOP before, the init PRECHARGE/REFRESH/LOAD_MODE sequence is allowed to 
                                                                    // start (tPOR; demo-scaled -- real SDR SDRAM requires >=100us of stable clock/CKE-high before the first command) 
    parameter int                           T_CL   = 2,             // CAS latency (READ -> data valid), also coded into MRS 
    parameter int                           BL_ENC = 3'b000         // Burst Length field for MRS (000 = BL1, this design is single-word) 
) 
( 
    // Clock & Reset ------------------------------------------------------------ 
    input  logic                            clk, 
    input  logic                            rst_n, 

    // Host (front-end) interface ----------------------------------------------- 
    input  logic                            req_valid, 
    output logic                            req_ready, 
    input  logic                            req_wr,                 // 1 = write, 0 = read 
    input  logic                            req_ap,                 // 1 = auto-precharge or PREA, 0 = normal or PRE 
    input  logic [BANK_W+ROW_W+COL_W-1:0]   req_addr, 
    input  logic [DATA_W-1:0]               req_wdata, 
    output logic                            resp_valid, 
    input  logic                            resp_ready, 
    output logic [DATA_W-1:0]               resp_rdata, 
    output logic                            init_done, 
    output logic                            ctrl_busy, 

    // Low power control 
    input  logic                            pd_req,                 // 1 = request power-down (PDE), 0 = request exit (PDX) 
    input  logic                            sr_req,                 // 1 = request self-refresh (SRE), 0 = request exit (SRX) 
    output logic                            pd_active,              // 1 while in power-down 
    output logic                            sr_active,              // 1 while in self-refresh (incl. tXSR exit wait) 
    input  logic                            mrs_req, 
    input  logic                            row_act_req, 
    input  logic [BANK_W-1:0]               row_act_bank, 
    input  logic [ROW_W-1:0]                row_act_row, 
    output logic                            row_open, 

    // SDR SDRAM (back-end) interface ------------------------------------------- 
    // Active-low command pins 
    output logic                            sdr_cke_n, 
    output logic                            sdr_cs_n, 
    output logic                            sdr_ras_n, 
    output logic                            sdr_cas_n, 
    output logic                            sdr_we_n, 
    output logic [BANK_W-1:0]               sdr_ba, 
    output logic [ROW_W-1:0]                sdr_addr,               // muxed row/column/MRS-value (col/A10 zero-extended) 
    output logic                            sdr_dqm,                // active-high (1 = mask) 
    inout  wire  [DATA_W-1:0]               sdr_dq 
); 
    // -------------------------------------------------------------------------- 
    // Localparam 
    // -------------------------------------------------------------------------- 
    localparam int AP_BIT = COL_W;                                  // Auto-precharge / precharge-all bit position within sdram_addr                     
    localparam int BANK_NUM = 1 << BANK_W;                          // Num of bank 
    localparam int RAS_HOLD = (T_RCD + T_CL > T_RAS) ? (T_RCD + T_CL) : T_RAS; 
                                                                    // Local param RAS timing hold (depends on T_RCD and T_CL) 
    // -------------------------------------------------------------------------- 
    // Define commands 
    // -------------------------------------------------------------------------- 
    // Active-LOW command encoding: {cmd_cs_n, cmd_ras_n, cmd_cas_n, cmd_we_n} (0 = asserted) 
    typedef struct packed { 
        logic cmd_cke_n; 
        logic cmd_cs_n; 
        logic cmd_ras_n; 
        logic cmd_cas_n; 
        logic cmd_we_n; 
    } cmd_s; 

    localparam cmd_s CMD_DES    = '{cmd_cke_n:1'b0, cmd_cs_n:1'b1, cmd_ras_n:1'b1, cmd_cas_n:1'b1, cmd_we_n:1'b1}; 
    localparam cmd_s CMD_NOP    = '{cmd_cke_n:1'b0, cmd_cs_n:1'b0, cmd_ras_n:1'b1, cmd_cas_n:1'b1, cmd_we_n:1'b1}; 
    localparam cmd_s CMD_ACT    = '{cmd_cke_n:1'b0, cmd_cs_n:1'b0, cmd_ras_n:1'b0, cmd_cas_n:1'b1, cmd_we_n:1'b1}; 
    localparam cmd_s CMD_RD     = '{cmd_cke_n:1'b0, cmd_cs_n:1'b0, cmd_ras_n:1'b1, cmd_cas_n:1'b0, cmd_we_n:1'b1};  // (A10=0) 
    localparam cmd_s CMD_RDA    = '{cmd_cke_n:1'b0, cmd_cs_n:1'b0, cmd_ras_n:1'b1, cmd_cas_n:1'b0, cmd_we_n:1'b1}; // (A10=1 - auto precharge) 
    localparam cmd_s CMD_WR     = '{cmd_cke_n:1'b0, cmd_cs_n:1'b0, cmd_ras_n:1'b1, cmd_cas_n:1'b0, cmd_we_n:1'b0}; // (A10=0) 
    localparam cmd_s CMD_WRA    = '{cmd_cke_n:1'b0, cmd_cs_n:1'b0, cmd_ras_n:1'b1, cmd_cas_n:1'b0, cmd_we_n:1'b0}; // (A10=1 - auto precharge) 
    localparam cmd_s CMD_PRE    = '{cmd_cke_n:1'b0, cmd_cs_n:1'b0, cmd_ras_n:1'b0, cmd_cas_n:1'b1, cmd_we_n:1'b0}; // (A10=0 - single bank) 
    localparam cmd_s CMD_PREA   = '{cmd_cke_n:1'b0, cmd_cs_n:1'b0, cmd_ras_n:1'b0, cmd_cas_n:1'b1, cmd_we_n:1'b0}; // (A10=1 - all bank) 
    localparam cmd_s CMD_REF    = '{cmd_cke_n:1'b0, cmd_cs_n:1'b0, cmd_ras_n:1'b0, cmd_cas_n:1'b0, cmd_we_n:1'b1}; // Refresh all bank 
    localparam cmd_s CMD_MRS    = '{cmd_cke_n:1'b0, cmd_cs_n:1'b0, cmd_ras_n:1'b0, cmd_cas_n:1'b0, cmd_we_n:1'b0}; 
    localparam cmd_s CMD_PDE    = '{cmd_cke_n:1'b1, cmd_cs_n:1'b0, cmd_ras_n:1'b1, cmd_cas_n:1'b1, cmd_we_n:1'b1}; 
    localparam cmd_s CMD_PDX    = '{cmd_cke_n:1'b0, cmd_cs_n:1'b0, cmd_ras_n:1'b1, cmd_cas_n:1'b1, cmd_we_n:1'b1}; 
    localparam cmd_s CMD_SRE    = '{cmd_cke_n:1'b1, cmd_cs_n:1'b0, cmd_ras_n:1'b0, cmd_cas_n:1'b0, cmd_we_n:1'b1}; 
    localparam cmd_s CMD_SRX    = '{cmd_cke_n:1'b0, cmd_cs_n:1'b0, cmd_ras_n:1'b1, cmd_cas_n:1'b1, cmd_we_n:1'b1}; 

    // -------------------------------------------------------------------------- 
    // Mode register value 
    // -------------------------------------------------------------------------- 
    // ------------------------------------------------------------------------------------------------------------- 
    //       A11       A10       A9       A8       A7       A6       A5       A4       A3       A2       A1       A0 
    //        0         0        0        0        0         
    //                                   WBM                 ------ T_CL ------    Burst type   ------ BL_ENC ------  
    //                                       
    // ------------------------------------------------------------------------------------------------------------- 
    // Set MRS depends on parameter or set default 
    localparam int T_CL_ENC = (T_CL == 3) ? 3'b011 : 3'b010;  
    localparam logic [ROW_W-1:0] MRS_VALUE = {{(ROW_W-8){1'b0}}, 1'b0, T_CL_ENC, 1'b0, BL_ENC[2:0]}; 

    // ----------------------------------------------------------------- 
    // Define finite state machine 
    // ----------------------------------------------------------------- 
    typedef enum logic [3:0] { 
        S_INIT,     // reset entry: runs the entire one-time power-up sequence internally, then -> S_IDLE once 
        S_IDLE,     // bus-idle dispatch hub (REF/MRS/PPDE/SRE/ACT/COL/PRE, decided per-bank), also absorbs the post-self-refresh tXSR settle wait (`xsr_settled`) 
        S_REF,      // REF (periodic post-init refresh) + tRFC wait -> S_IDLE 
        S_MRS,      // MRS (runtime re-issue) + tMRD wait -> S_IDLE 
        S_PPDE,     // Precharge Power-Down hold (PDE); -> S_IDLE (PDX "for free") 
        S_SRE,      // Self-Refresh entry+hold (SRE then PDE framing); -> S_IDLE (SRX "for free"; tXSR settle handled in S_IDLE afterward) 
        S_ACT,      // ACT (one bank, `cur_bank`) + tRCD wait; then dispatches a pending access or returns to S_IDLE 
        S_APDE,     // Active Power-Down hold (PDE); -> S_ACT (PDX "for free", rcd_cnt resumes exactly where it was frozen) 
        S_WR_RD,    // Column access: RD/WR (`cur_wr`) with or without auto-precharge (`cur_ap`) + CAS-latency (and, if `cur_ap`,settle) wait, -> S_IDLE (if `cur_ap`, that bank's row closes; otherwise it stays open) 
        S_PRE       // explicit close: single-bank PRE (`cur_bank`) or, when `pre_all`, an all-bank PREA + tRP wait, -> S_IDLE 
    } state_e; 
    state_e                 state; 
    state_e                 next_state; 
    state_e                 prev_state; 

    always_ff @(posedge clk or negedge rst_n)  
    begin 
        if (!rst_n)  
        begin 
            prev_state <= S_INIT; 
        end 
        else 
        begin         
            prev_state <= state; 
        end 
    end 

    always_ff @(posedge clk or negedge rst_n)  
    begin 
        if (!rst_n)  
        begin 
            state <= S_INIT; 
        end 
        else      
        begin 
            state <= next_state; 
        end 
    end 

    // ----------------------------------------------------------------- 
    // Capture entering commands with FSM 
    // This will use to assign command (drive signal), calculate counters and update activating bank row 
    // ----------------------------------------------------------------- 
    bit act_entering; 
    bit ref_entering; 
    bit mrs_entering; 
    bit sre_entering; 
    bit col_entering; 
    bit pre_entering; 
    assign act_entering  = (state == S_ACT) && (prev_state == S_IDLE); 
    assign ref_entering  = (state == S_REF) && (prev_state != S_REF); 
    assign mrs_entering  = (state == S_MRS) && (prev_state != S_MRS); 
    assign sre_entering  = (state == S_SRE) && (prev_state != S_SRE); 
    assign col_entering  = (state == S_WR_RD) && (prev_state != S_WR_RD); 
    assign pre_entering  = (state == S_PRE) && (prev_state != S_PRE); 

    // ----------------------------------------------------------------- 
    // Timing counters  
    // ----------------------------------------------------------------- 
    int unsigned rcd_cnt; 
    int unsigned col_cnt; 
    int unsigned rfc_cnt; 
    int unsigned mrd_cnt; 
    int unsigned ras_cnt[BANK_NUM]; 
    int unsigned por_cnt;                               // S_INIT holds NOP for T_POR cycles before starting PREA 
    int unsigned xsr_cnt; 
    int unsigned refi_cnt; 

    // ----------------------------------------------------------------- 
    // Event command signals  
    // ----------------------------------------------------------------- 
    bit por_done; 
    bit xsr_settled; 
    bit ref_due;
    bit ref_approaching; 
    bit mrs_pending;                                  // Check pending MRS command 
	
    assign ref_due = (refi_cnt >= unsigned'(T_REFI-2)); 
    assign ref_approaching = (refi_cnt >= unsigned'(((T_REFI-2) > (T_REF_MARGIN+1)) ? (T_REFI-2-T_REF_MARGIN-1) : 0));

    // ----------------------------------------------------------------- 
    // Internal variables check ACT command conditions 
    // ----------------------------------------------------------------- 
    logic               row_open_bank [BANK_NUM];       // Per-bank row-activated state (activated - 1, not - 0) 
    logic [ROW_W-1:0]   open_row_bank [BANK_NUM];       // Per-bank per-row state (activated - 1, not - 0) 
    bit               	held_by_act_req;                // Is there any activated request bank or not 
    logic [BANK_W-1:0]  act_req_bank;                   // Last (or current) target activated bank  
    bit               	pending_access;                 // Pending column access attached to a freshly-opened row 
    logic [BANK_W-1:0]  req_bank_f;                     // Decoded bank address 
    logic [ROW_W-1:0]   req_row_f;                      // Decoded row address 
    logic [COL_W-1:0]   req_col_f;                      // Decoded column address 
    bit                 req_bank_open;                  // Status target bank - row 
    bit                 req_row_match;                  // Logic bit set target row at one bank is still activated before or not 
    bit               	need_precharge_all;             // Bit require need to set precharge all (check conditions of other commands) 

    assign req_bank_f    = req_addr[BANK_W+ROW_W+COL_W-1 -: BANK_W]; 
    assign req_row_f     = req_addr[ROW_W+COL_W-1 -: ROW_W]; 
    assign req_col_f     = req_addr[COL_W-1:0]; 
    assign req_bank_open = row_open_bank[req_bank_f]; 
    assign req_row_match = req_bank_open && (open_row_bank[req_bank_f] == req_row_f); 

    // ----------------------------------------------------------------- 
    // Internal variables check PRE command conditions 
    // ----------------------------------------------------------------- 
    logic [BANK_W-1:0]  close_bank;                     // Target precharge bank 
    bit               	pre_all_sel;                    // Select precharge all or not 
    bit               	pre_all; 
    bit               	any_bank_open;                  // Bit check any bank open before sending REF/SRE/PPDE/MRS 
    bit               	banks_precharge_ready;          // Bit check precharge wait timing RAS before submit 
    assign need_precharge_all = any_bank_open && (sr_req || pd_req || mrs_pending || ref_approaching); 
    always_comb  
    begin 
        any_bank_open         = 1'b0; 
        banks_precharge_ready = 1'b1; 
        for (int b = 0; b < BANK_NUM; b++)  
        begin 
            if (row_open_bank[b])  
            begin 
                any_bank_open = 1'b1; 
                if (ras_cnt[b] < unsigned'(RAS_HOLD))  
                begin 
                    banks_precharge_ready = 1'b0; 
                end 
            end 
        end 
    end 

    // ----------------------------------------------------------------- 
    // Internal variables check MRS command conditions 
    // ----------------------------------------------------------------- 
    always_ff @(posedge clk or negedge rst_n)  
    begin 
        if (!rst_n)               
        begin 
            mrs_pending <= 1'b0; 
        end 
        else if (mrs_entering) 
        begin 
            mrs_pending <= 1'b0; 
        end 
        else if (mrs_req && (state == S_IDLE))  
        begin 
            mrs_pending <= 1'b1; 
        end 
    end 

    // ----------------------------------------------------------------- 
    // Power-up init microsequence, run entirely within S_INIT:  
    // tPOR hold, PREA, two REFRESH passes, MRS, tMRD wait.  
    // `rfc_cnt`/`mrd_cnt` above are reused for the init REF/MRS phases (disjoint in time from their post-init S_REF/S_MRS reuse). 
    // ----------------------------------------------------------------- 
    typedef enum logic [2:0] {  
        IST_POR,  
        IST_PREA,  
        IST_REF0,  
        IST_REF1,  
        IST_MRS 
    } init_step_e; 
    init_step_e init_step; 
    init_step_e prev_init_step; 

    always_ff @(posedge clk or negedge rst_n)  
    begin 
        if (!rst_n)  
        begin 
            prev_init_step <= IST_POR; 
        end 
        else 
        begin         
            prev_init_step <= init_step; 
        end 
    end 

    // Capture entering commands with power-up init microsequence 
    bit ist_ref0_entering; 
    bit ist_ref1_entering; 
    bit ist_MRS_entering; 
    bit doing_ref; 
    bit ref_phase_entering; 
    assign ist_ref0_entering    = (init_step == IST_REF0) && (prev_init_step != IST_REF0); 
    assign ist_ref1_entering    = (init_step == IST_REF1) && (prev_init_step != IST_REF1); 
    assign ist_MRS_entering     = (init_step == IST_MRS)  && (prev_init_step != IST_MRS); 
    assign doing_ref            = (state == S_REF) || (state == S_INIT && (init_step == IST_REF0 || init_step == IST_REF1)); 
    assign ref_phase_entering   = ref_entering || ist_ref0_entering || ist_ref1_entering; 

    // ----------------------------------------------------------------- 
    // Drive output SDR SDRAM signals 
    // ----------------------------------------------------------------- 
    logic [BANK_W-1:0] 	cur_bank; 
    logic [ROW_W-1:0]  	cur_row; 
    logic [COL_W-1:0]  	cur_col; 
    bit              	cur_wr; 
    bit              	cur_ap; 
    logic [DATA_W-1:0] 	cur_wdata; 
    cmd_s 				cmd; 
    bit 				dq_drive; 
    logic [DATA_W-1:0] 	dq_out; 
//	string				cmd_name_dbg;
    assign sdr_cs_n  	= cmd.cmd_cs_n; 
    assign sdr_ras_n 	= cmd.cmd_ras_n; 
    assign sdr_cas_n 	= cmd.cmd_cas_n; 
    assign sdr_we_n  	= cmd.cmd_we_n; 
    assign sdr_cke_n 	= cmd.cmd_cke_n; 
    assign sdr_dqm   	= 1'b0; 
    assign sdr_ba    	= cur_bank; 
    assign sdr_dq    	= dq_drive ? dq_out : {DATA_W{1'bz}}; 

    // Row/Column/A10/MRS-value mux onto sdr_addr. Which state no meaningful, address will be 0 (default) 
    always_comb  
    begin 
        sdr_addr = '0; 
        unique case (state) 
            S_ACT   : sdr_addr = cur_row; 
            S_WR_RD : sdr_addr = cur_ap ? {{(ROW_W-AP_BIT-1){1'b0}}, 1'b1, cur_col}: 
                                            {{(ROW_W-AP_BIT){1'b0}}        , cur_col}; 
            S_PRE   : sdr_addr = pre_all ?{{(ROW_W-AP_BIT-1){1'b0}}, 1'b1, {AP_BIT{1'b0}}} : '0; 
            S_MRS   : sdr_addr = MRS_VALUE; 
            S_INIT  :  
            begin 
                unique case (init_step) 
                    IST_POR  : sdr_addr = '0; 
                    IST_PREA : sdr_addr = {{(ROW_W-AP_BIT-1){1'b0}}, 1'b1, {AP_BIT{1'b0}}}; 
                    IST_REF0 : sdr_addr = '0; 
                    IST_REF1 : sdr_addr = '0; 
                    IST_MRS  : sdr_addr = MRS_VALUE; 
                endcase 
            end 
            S_IDLE, S_REF, S_PPDE, S_SRE, S_APDE : sdr_addr = '0; 
        endcase 
    end 

    assign row_open = held_by_act_req && row_open_bank[act_req_bank]; 
    assign init_done  = (state != S_INIT); 
    assign req_ready  = (state == S_IDLE) && xsr_settled && !sr_req && !pd_req && !mrs_pending && !ref_due && !(req_bank_open && !req_row_match); 
    assign ctrl_busy  = !req_ready; 
    assign pd_active  = (state == S_PPDE) || (state == S_APDE); 
    assign sr_active  = (state == S_SRE) || !xsr_settled; 

    // Latch request/bookkeeping state. All transitions below only ever fire from S_IDLE. 
    always_ff @(posedge clk or negedge rst_n)  
    begin 
		if (!rst_n)  
		begin 
			cur_bank        <= '0; 
			cur_row         <= '0; 
			cur_col         <= '0; 
			cur_wr          <= 1'b0; 
			cur_wdata       <= '0; 
			cur_ap          <= 1'b0; 
			held_by_act_req <= 1'b0; 
			act_req_bank    <= '0; 
			pending_access  <= 1'b0; 
			pre_all         <= 1'b0; 
		end  
		else  
		begin 
			if (state == S_IDLE && next_state == S_PRE)  
			begin 
				cur_bank <= close_bank; 
				pre_all  <= pre_all_sel; 
			end  
			else if (req_valid && req_ready)  
			begin 
				cur_bank  <= req_bank_f; 
				cur_col   <= req_col_f; 
				cur_wr    <= req_wr; 
				cur_wdata <= req_wdata; 
				cur_ap    <= req_ap; 
				if (!req_bank_open)  
				begin 
					cur_row        <= req_row_f; 
					pending_access <= 1'b1; // this access is attached to the fresh ACT 
				end  
				else  
				begin 
					pending_access <= 1'b0; // direct dispatch, no ACT involved 
				end 
			end  
			else if (state == S_IDLE && !req_valid && row_act_req && 
					!(row_open_bank[row_act_bank] && (open_row_bank[row_act_bank] != row_act_row)))  
			begin 
				held_by_act_req <= 1'b1; 
				act_req_bank    <= row_act_bank; 
				if (!row_open_bank[row_act_bank])  
				begin 
					cur_bank       <= row_act_bank; 
					cur_row        <= row_act_row; 
					pending_access <= 1'b0; 
				end 
			end 
			if (pending_access && (next_state == S_WR_RD))  
			begin 
				pending_access <= 1'b0; // the pending access is being dispatched this cycle 
			end 
			if (held_by_act_req && (((state == S_PRE) && (next_state == S_IDLE) && (pre_all || (cur_bank == act_req_bank))) || 
									((state == S_WR_RD) && cur_ap && (next_state == S_IDLE) && (cur_bank == act_req_bank))))  
			begin 
				held_by_act_req <= 1'b0; 
			end 
		end 
    end 

    // Per-bank row-open bookkeeping - the sole source of truth for which banks currently have an open row 
    always_ff @(posedge clk or negedge rst_n)  
    begin 
        if (!rst_n)  
        begin 
            for (int b = 0; b < BANK_NUM; b++)  
            begin 
                row_open_bank[b] <= 1'b0; 
                open_row_bank[b] <= '0; 
            end 
        end  
        else  
        begin 
            if (act_entering)  
            begin 
                row_open_bank[cur_bank] <= 1'b1; 
                open_row_bank[cur_bank] <= cur_row; 
            end 
            if ((state == S_PRE) && (next_state == S_IDLE))  
            begin 
                if (pre_all) 
                begin 
                    for (int b = 0; b < BANK_NUM; b++)  
                    begin 
                        row_open_bank[b] <= 1'b0; // auto PREA 
                    end 
                end  
                else 
                begin 
                    row_open_bank[cur_bank] <= 1'b0; // Close single-bank 
                end 
            end 
            if ((state == S_WR_RD) && cur_ap && (next_state == S_IDLE))  
            begin 
                row_open_bank[cur_bank] <= 1'b0; // auto-precharge closes this bank only 
            end 
            if ((state == S_INIT) && (init_step == IST_PREA))  
            begin 
                for (int b = 0; b < BANK_NUM; b++)  
                begin 
                    row_open_bank[b] <= 1'b0; // PREA: all banks 
                end 
            end 
        end 
    end 

    // Counters 
    always_ff @(posedge clk or negedge rst_n)  
    begin 
        if (!rst_n)  
        begin 
            rcd_cnt  <= '0; 
            for (int b = 0; b < BANK_NUM; b++)  
            begin 
                ras_cnt[b] <= '0; 
            end 
            col_cnt  <= '0; 
            rfc_cnt  <= '0; 
            mrd_cnt  <= '0; 
            por_cnt  <= '0; 
            refi_cnt <= '0; 
        end  
        else  
        begin 
            if (!por_done)  
            begin 
                por_cnt <= por_cnt + 1'b1; 
            end 
            else 
            begin 
                por_cnt <= por_cnt; 
            end 

            if (doing_ref && ref_phase_entering) 
            begin 
                refi_cnt <= '0; 
            end 
            else if (!pd_active && !sr_active) 
            begin 
                refi_cnt <= refi_cnt + 1'b1; 
            end 
            else 
            begin 
                refi_cnt <= refi_cnt; 
            end 

            if (state == S_ACT)  
            begin 
                if (act_entering)  
                begin 
                    rcd_cnt <= '0; 
                end 
                else 
                begin 
                    rcd_cnt <= rcd_cnt + 1'b1; 
                end 
            end  
            else if (state == S_PRE)  
            begin 
                if (pre_entering)  
                begin 
                    rcd_cnt <= '0; 
                end 
                else 
                begin 
                    rcd_cnt <= rcd_cnt + 1'b1; 
                end 
            end 
            else 
            begin 
                rcd_cnt <= rcd_cnt; 
            end 
            for (int b = 0; b < BANK_NUM; b++)  
            begin 
                if (act_entering && (cur_bank == b[BANK_W-1:0]))  
                begin 
                    ras_cnt[b] <= '0; 
                end 
                else if (row_open_bank[b])  
                begin 
                    ras_cnt[b] <= ras_cnt[b] + 1'b1; 
                end 
            end 
            if (state == S_WR_RD)  
            begin 
                if (col_entering)  
                begin 
                    col_cnt <= '0; 
                end 
                else       
                begin 
                    col_cnt <= col_cnt + 1'b1; 
                end 
            end 
            if (doing_ref)  
            begin 
                if (ref_phase_entering)  
                begin 
                    rfc_cnt <= '0; 
                end 
                else                     
                begin 
                    rfc_cnt <= rfc_cnt + 1'b1; 
                end 
            end 
            if (state == S_MRS)  
            begin 
                if (mrs_entering)  
                begin 
                    mrd_cnt <= '0; 
                end 
                else               
                begin 
                    mrd_cnt <= mrd_cnt + 1'b1; 
                end 
            end  
            else if (state == S_INIT && init_step == IST_MRS)  
            begin 
                if (ist_MRS_entering)  
                begin 
                    mrd_cnt <= '0; 
                end 
                else                    
                begin 
                    mrd_cnt <= mrd_cnt + 1'b1; 
                end 
            end 
        end 
    end 

    // tXSR settle and counter: becomes unsettled the cycle self-refresh is left (S_SRE -> S_IDLE), then counts T_XSR further NOP cycles in S_IDLE before `req_ready`/dispatch is allowed again 
    always_ff @(posedge clk or negedge rst_n)  
    begin 
        if (!rst_n)  
        begin 
            xsr_settled <= 1'b1; 
            xsr_cnt     <= '0; 
        end  
        else if (state == S_SRE && next_state == S_IDLE)  
        begin 
            xsr_settled <= 1'b0; 
            xsr_cnt     <= '0; 
        end  
        else if (!xsr_settled)  
        begin 
            if (xsr_cnt >= unsigned'(T_XSR-1))  
                xsr_settled <= 1'b1; 
            else                                
                xsr_cnt <= xsr_cnt + 1'b1; 
        end 
        else 
        begin 
            xsr_settled <= xsr_settled; 
            xsr_cnt <= xsr_cnt; 
        end 
    end 

    // Counter check power-up initialization done or not 
    always_ff @(posedge clk or negedge rst_n)  
    begin 
        if (!rst_n) 
        begin 
            por_done <= 1'b0; 
        end 
        else if (!por_done && por_cnt >= unsigned'(T_POR-1))  
        begin    
            por_done <= 1'b1; 
        end 
        else 
        begin 
            por_done <= por_done; 
        end 
    end 

    // Init sub-phase sequence, run only while state==S_INIT (see init_step_e declaration above for what each phase does). 
    always_ff @(posedge clk or negedge rst_n)  
    begin 
        if (!rst_n)  
        begin 
            init_step <= IST_POR; 
        end 
        else if (state == S_INIT) 
        begin 
            case (init_step) 
            IST_POR  :  
            begin 
                if (por_done)  
                begin 
                    init_step <= IST_PREA; 
                end 
                else 
                begin 
                    init_step <= IST_POR; 
                end 
            end 
            IST_PREA :  
            begin    
                init_step <= IST_REF0; // PREA is always exactly 1 cycle 
            end 
            IST_REF0 :  
            begin 
                if (!ist_ref0_entering && rfc_cnt >= unsigned'(T_RFC-1))  
                begin 
                    init_step <= IST_REF1; 
                end 
                else 
                begin 
                    init_step <= IST_REF0; 
                end 
            end 
            IST_REF1 :  
            begin 
                if (!ist_ref1_entering && rfc_cnt >= unsigned'(T_RFC-1))  
                begin 
                    init_step <= IST_MRS; 
                end 
                else 
                begin 
                    init_step <= IST_REF1; 
                end 
            end 
            IST_MRS  : ; // stays; S_INIT itself exits to S_IDLE once tMRD elapses (see next-state logic) 
            default  : ; 
            endcase 
        end 
    end 

    // Calculate Next-state logic 
    always_comb  
    begin 
        next_state  = state; 
        close_bank  = '0;   // default; only meaningful on cycles next_state becomes S_PRE from S_IDLE 
        pre_all_sel = 1'b0; // default; only meaningful on cycles next_state becomes S_PRE from S_IDLE 
        case (state) 
            S_INIT:  
            begin 
                if (init_step == IST_MRS && !ist_MRS_entering && mrd_cnt >= unsigned'(T_MRD-1)) 
                    next_state = S_IDLE; 
            end 
            S_IDLE :  
            begin 
                if (xsr_settled)  
                begin 
                    if (need_precharge_all)  
                    begin 
                        if (banks_precharge_ready)  
                        begin 
                            next_state   = S_PRE; 
                            pre_all_sel  = 1'b1; 
                        end 
                    end 
                    else if (sr_req)        
                        next_state = S_SRE; 
                    else if (pd_req)        
                        next_state = S_PPDE; 
                    else if (mrs_pending)   
                        next_state = S_MRS; 
                    else if (ref_due)       
                        next_state = S_REF; 
                    else if (req_valid)  
                    begin 
                        if (req_bank_open && !req_row_match)  
                        begin 
                            if (ras_cnt[req_bank_f] >= unsigned'(RAS_HOLD))  
                            begin 
                                next_state = S_PRE; 
                                close_bank = req_bank_f; 
                            end 
                        end  
                        else if (req_bank_open)  
                        begin 
                            next_state = S_WR_RD; 
                        end  
                        else  
                        begin 
                            next_state = S_ACT; 
                        end 
                    end  
                    else if (held_by_act_req && !row_act_req && row_open_bank[act_req_bank] && (ras_cnt[act_req_bank] >= unsigned'(RAS_HOLD)))  
                    begin 
                        next_state = S_PRE; 
                        close_bank = act_req_bank; 
                    end  
                    else if (row_act_req)  
                    begin 
                        if (row_open_bank[row_act_bank] && (open_row_bank[row_act_bank] == row_act_row))  
                        begin 
                            // Already open (from any origin) with the matching row: adopt it (latch block above), no command issued. 
                        end  
                        else if (!row_open_bank[row_act_bank])  
                        begin 
                            next_state = S_ACT;  
                        end 
                        else if (ras_cnt[row_act_bank] >= unsigned'(RAS_HOLD)) 
                        begin 
                            next_state = S_PRE; 
                            close_bank = row_act_bank; 
                        end 
                    end 
                end 
            end 
            S_REF :  
            begin 
                if (!ref_entering && rfc_cnt >= unsigned'(T_RFC-1))  
                    next_state = S_IDLE; 
            end 
            S_MRS :  
            begin 
                if (!mrs_entering && mrd_cnt >= unsigned'(T_MRD-1))  
                    next_state = S_IDLE; 
            end 
            S_PPDE :  
            begin 
                if (!pd_req)  
                    next_state = S_IDLE; 
            end 
            S_SRE  :  
            begin 
                if (!sr_req)  
                    next_state = S_IDLE; 
            end 
            S_ACT :  
            begin 
                if (!act_entering && pd_req)  
                begin 
                    next_state = S_APDE; 
                end  
                else if (!act_entering && rcd_cnt >= unsigned'(T_RCD-1))  
                begin 
                    if (pending_access) 
                        next_state = S_WR_RD; 
                    else 
                        next_state = S_IDLE; 
                end 
            end 
            S_APDE :  
            begin 
                if (!pd_req)  
                    next_state = S_ACT; 
            end 
            S_WR_RD :  
            begin 
                if (!col_entering)  
                begin 
                    if (cur_ap)  
                    begin 
                        if (ras_cnt[cur_bank] >= unsigned'(RAS_HOLD + T_RP))  
                            next_state = S_IDLE; 
                    end  
                    else  
                    begin
                        if (cur_wr) 
                        begin
                        if (col_cnt >= unsigned'(T_CL-1))  
                            next_state = S_IDLE; 
                        end
                        else
                        begin
                        if (col_cnt >= unsigned'(T_CL))  
                            next_state = S_IDLE; 
                        end 
                    end 
                end 
            end 
            S_PRE :  
            begin 
                if (!pre_entering && rcd_cnt >= unsigned'(T_RP-1))  
                    next_state = S_IDLE; 
            end 
            default : next_state = S_IDLE; 
        endcase 
    end 

    // Command / data-bus drive per state 
    always_comb  
    begin 
        cmd      = CMD_NOP; 
        dq_drive = 1'b0; 
        dq_out   = '0; 
        unique case (state) 
            S_INIT :  
            begin 
                unique case (init_step) 
                    IST_POR  : cmd = CMD_NOP; 
                    IST_PREA : cmd = CMD_PREA; 
                    IST_REF0 : cmd = ist_ref0_entering ? CMD_REF : CMD_NOP; 
                    IST_REF1 : cmd = ist_ref1_entering ? CMD_REF : CMD_NOP; 
                    IST_MRS  : cmd = ist_MRS_entering  ? CMD_MRS : CMD_NOP; 
                endcase 
            end 
            S_IDLE : cmd = CMD_NOP; 
            S_REF  : cmd = ref_entering ? CMD_REF : CMD_NOP; 
            S_MRS  : cmd = mrs_entering ? CMD_MRS : CMD_NOP; 
            S_PPDE : cmd = CMD_PDE; 
            S_SRE  : cmd = sre_entering ? CMD_SRE : CMD_PDE; 
            S_ACT  : cmd = act_entering ? CMD_ACT : CMD_NOP; 
            S_APDE : cmd = CMD_PDE; 
            S_WR_RD :  
            begin 
                if (col_entering) 
                begin 
                    if (cur_wr)  
                    begin 
                        cmd      = cur_ap ? CMD_WRA : CMD_WR; 
                        dq_drive = 1'b1; 
                        dq_out   = cur_wdata; 
                    end  
                else  
                    begin 
                        cmd = cur_ap ? CMD_RDA : CMD_RD; 
                    end 
                end 
                else  
                begin 
                    cmd = CMD_NOP; 
                end 
            end 
            S_PRE   : cmd = pre_entering ? (pre_all ? CMD_PREA : CMD_PRE) : CMD_NOP; 
        endcase 
    end 
	
//	always_comb begin
//		case (cmd)
//			CMD_NOP : cmd_name_dbg = "NOP";
//			CMD_ACT : cmd_name_dbg = "ACT";
//			CMD_REF : cmd_name_dbg = "REF";
//			CMD_MRS : cmd_name_dbg = "MRS";
//			CMD_PDE : cmd_name_dbg = "PDE";
//			CMD_SRE : cmd_name_dbg = "SRE";
//			CMD_RD  : cmd_name_dbg = cur_ap ? "RDA" : "RD";
//			CMD_WR  : cmd_name_dbg = cur_ap ? "WRA" : "WR";
//			CMD_PRE : cmd_name_dbg = pre_all ? "PREA" : "PRE";
//			default : cmd_name_dbg = "NOP";
//		endcase
//	end

//	always @(cmd_name_dbg) begin
//		$display("[TIME: %0t] Send command: %0s", $realtime, cmd_name_dbg);
//	end
	
    // Read data capture (tCL cycles after RDA) & response handshake. The auto-precharge (RDA/WRA) closes the row internally while `col_cnt` runs out within S_RDA/S_WRA; no explicit PRE command is issued by the controller. 
    logic [DATA_W-1:0] 	rdata_capture; 
    bit                	resp_pending; 
    always_ff @(posedge clk or negedge rst_n)  
    begin 
        if (!rst_n)  
        begin 
            rdata_capture <= '0; 
            resp_pending  <= 1'b0; 
        end  
        else  
        begin 
            if ((state == S_WR_RD) && !cur_wr && !col_entering && col_cnt == unsigned'(T_CL)) 
            begin 
                rdata_capture <= sdr_dq; 
            end 
            if ((state == S_WR_RD) && (next_state == S_IDLE)) 
            begin 
                resp_pending <= 1'b1; 
            end 
            else if (resp_valid && resp_ready) 
            begin 
                resp_pending <= 1'b0; 
            end 
            else 
            begin 
                resp_pending <= resp_pending; 
            end 
        end 
    end 
    assign resp_valid = resp_pending; 
    assign resp_rdata = rdata_capture; 
endmodule 

