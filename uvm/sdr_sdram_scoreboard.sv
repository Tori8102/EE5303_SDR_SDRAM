// ---------------------------------------------------------------
// Scoreboard:
//  - Reference model (assoc array) + AXI write-vs-read-back compare
//  - Independent cross-check of AXI-expected data against the SDR
//    back-end's actually-observed writes (addr-mapped to bank/row/col)
//  - Low-power protocol cross-check: APB CTRL-register writes (pd_req/
//    sr_req) are tracked to build an expected PDE/PDX/SRE/SRX event
//    queue (same arbitration priority as the RTL: sr_req > pd_req),
//    which is compared in-order against the sdr_monitor's independently
//    observed low-power events on the SDR command/CKE bus.
// ---------------------------------------------------------------
class sdr_scoreboard extends uvm_component;
    `uvm_component_utils(sdr_scoreboard)

    uvm_analysis_imp #(axi_txn, sdr_scoreboard)            axi_imp;
    uvm_analysis_imp_bfm #(sdram_cmd_txn, sdr_scoreboard)  bfm_imp;
    uvm_analysis_imp_pwr #(sdr_pwr_evt_txn, sdr_scoreboard) pwr_imp;
    uvm_analysis_imp_apb #(apb_txn, sdr_scoreboard)        apb_imp;
    uvm_analysis_imp_cmdevt #(sdr_cmd_evt_txn, sdr_scoreboard) cmdevt_imp;

    bit [DATA_W-1:0] expected_mem[bit [ADDR_W-1:0]];          // addr -> data (AXI-side model)
    bit [DATA_W-1:0] actual_mem[bit [BANK_W+ROW_W+COL_W-1:0]]; // {bank,row,col} -> data (back-end observed)

    int unsigned match_cnt, mismatch_cnt, xcheck_cnt, xcheck_fail;

    // Low-power protocol cross-check state
    bit pd_req_prev, sr_req_prev;
    pwr_evt_e expected_pwr_evt_q[$];
    int unsigned pwr_match_cnt, pwr_mismatch_cnt;


    int unsigned act_cnt, rd_cnt, rda_cnt, wr_cnt, wra_cnt, pre_cnt, prea_cnt, ref_cnt, MRS_cnt;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        axi_imp    = new("axi_imp", this);
        bfm_imp    = new("bfm_imp", this);
        pwr_imp    = new("pwr_imp", this);
        apb_imp    = new("apb_imp", this);
        cmdevt_imp = new("cmdevt_imp", this);
    endfunction

    // From sdr_monitor: per-command observed counters
    function void write_cmdevt(sdr_cmd_evt_txn t);
    case (t.cmd)
        CMD_ACT  : act_cnt++;
        CMD_RD   : rd_cnt++;
        CMD_RDA  : rda_cnt++;
        CMD_WR   : wr_cnt++;
        CMD_WRA  : wra_cnt++;
        CMD_PRE  : pre_cnt++;
        CMD_PREA : prea_cnt++;
        CMD_REF  : ref_cnt++;
        CMD_MRS  : MRS_cnt++;
        default  : ;
    endcase
    endfunction

    // From AXI monitor: write-reference-model update / read-back compare
    function void write(axi_txn tx);
    if (tx.wr) begin
        expected_mem[tx.addr] = tx.wdata;
    end else begin
        if (expected_mem.exists(tx.addr)) begin
        if (tx.rdata !== expected_mem[tx.addr]) begin
            mismatch_cnt++;
            `uvm_error("DATA_MISMATCH",
            $sformatf("addr=0x%0h exp=0x%0h act=0x%0h", tx.addr, expected_mem[tx.addr], tx.rdata))
        end else begin
            match_cnt++;
        end
        end else begin
        `uvm_warning("UNINIT_READ", $sformatf("Read from unwritten addr 0x%0h", tx.addr))
        end
    end
    endfunction

    // From sdr_monitor: independent cross-check of back-end writes
    function void write_bfm(sdram_cmd_txn t);
    bit [BANK_W+ROW_W+COL_W-1:0] key = {t.bank, t.row, t.col};
    actual_mem[key] = t.data;
    endfunction

    // From sdr_monitor: observed low-power event -> compare against
    // expected queue built from APB CTRL writes
    function void write_pwr(sdr_pwr_evt_txn e);
    pwr_evt_e exp_evt;
    if (expected_pwr_evt_q.size() == 0) begin
        pwr_mismatch_cnt++;
        `uvm_error("PWR_EVT_UNEXPECTED",
        $sformatf("Observed power event %s with no corresponding APB CTRL request queued", e.evt.name()))
        return;
    end
    exp_evt = expected_pwr_evt_q.pop_front();
    if (exp_evt != e.evt) begin
        pwr_mismatch_cnt++;
        `uvm_error("PWR_EVT_MISMATCH",
        $sformatf("Expected power event %s but observed %s", exp_evt.name(), e.evt.name()))
    end else begin
        pwr_match_cnt++;
        `uvm_info("PWR_EVT_MATCH", $sformatf("Observed expected power event %s", e.evt.name()), UVM_LOW)
    end
    endfunction

    // From APB monitor: decode CTRL-register writes into expected PDE/PDX/
    // SRE/SRX events, using the same sr_req-over-pd_req priority as the RTL
    function void write_apb(apb_txn tx);
    bit pd_req_new, sr_req_new;
    if (!(tx.wr && tx.addr == APB_ADDR_CTRL)) return;

    pd_req_new = tx.wdata[0];
    sr_req_new = tx.wdata[1];

    if (sr_req_new && !sr_req_prev)
        expected_pwr_evt_q.push_back(PWR_EVT_SRE);
    else if (!sr_req_new && sr_req_prev)
        expected_pwr_evt_q.push_back(PWR_EVT_SRX);
    else if (pd_req_new && !pd_req_prev && !sr_req_new)
        expected_pwr_evt_q.push_back(PWR_EVT_PDE);
    else if (!pd_req_new && pd_req_prev && !sr_req_prev)
        expected_pwr_evt_q.push_back(PWR_EVT_PDX);

    pd_req_prev = pd_req_new;
    sr_req_prev = sr_req_new;
    endfunction

    function void check_phase(uvm_phase phase);
    foreach (expected_mem[a]) begin
        // a[ADDR_W-1] is the AP bit, not part of the bank/row/col mapping.
        bit [BANK_W-1:0] bank = a[MEM_ADDR_W-1 -: BANK_W];
        bit [ROW_W-1:0]  row  = a[ROW_W+COL_W-1 -: ROW_W];
        bit [COL_W-1:0]  col  = a[COL_W-1:0];
        bit [BANK_W+ROW_W+COL_W-1:0] key = {bank, row, col};

        xcheck_cnt++;
        if (!actual_mem.exists(key)) begin
        xcheck_fail++;
        `uvm_error("XCHECK_MISSING",
            $sformatf("addr=0x%0h bank=%0d row=0x%0h col=0x%0h never observed on back-end",
                    a, bank, row, col))
        end else if (actual_mem[key] !== expected_mem[a]) begin
        xcheck_fail++;
        `uvm_error("XCHECK_MISMATCH",
            $sformatf("addr=0x%0h exp=0x%0h dut_backend=0x%0h", a, expected_mem[a], actual_mem[key]))
        end
    end

    if (expected_pwr_evt_q.size() != 0)
        `uvm_error("PWR_EVT_MISSING",
        $sformatf("%0d expected power event(s) were never observed: %p",
                    expected_pwr_evt_q.size(), expected_pwr_evt_q))

    `uvm_info("SCOREBOARD",
        $sformatf("AXI compare: match=%0d mismatch=%0d | Cross-check: total=%0d fail=%0d | PwrEvt: match=%0d mismatch=%0d | CmdCnt: ACT=%0d RD=%0d RDA=%0d WR=%0d WRA=%0d PRE=%0d PREA=%0d REF=%0d MRS=%0d",
                match_cnt, mismatch_cnt, xcheck_cnt, xcheck_fail, pwr_match_cnt, pwr_mismatch_cnt,
                act_cnt, rd_cnt, rda_cnt, wr_cnt, wra_cnt, pre_cnt, prea_cnt, ref_cnt, MRS_cnt), UVM_LOW)
    endfunction
endclass