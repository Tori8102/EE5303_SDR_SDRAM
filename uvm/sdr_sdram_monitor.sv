
class sdr_monitor extends uvm_monitor;
    `uvm_component_utils(sdr_monitor)
    virtual sdram_if.mon vif;
    uvm_analysis_port #(sdram_cmd_txn)   cmd_ap;
    uvm_analysis_port #(sdr_pwr_evt_txn) pwr_ap;
    uvm_analysis_port #(sdr_cmd_evt_txn) cmd_evt_ap;

    bit [ROW_W-1:0] open_row[int unsigned]; // indexed by bank
    bit             cke_prev;
    // Remembered context (mirrors the RTL's own state register) needed to
    // disambiguate PDX vs SRX, since both decode identically otherwise.
    bit             in_self_refresh;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cmd_ap     = new("cmd_ap", this);
        pwr_ap     = new("pwr_ap", this);
        cmd_evt_ap = new("cmd_evt_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual sdram_if.mon)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "sdr_monitor: virtual interface not set")
    endfunction

    task run_phase(uvm_phase phase);
    cke_prev        = 1'b1;
    in_self_refresh = 1'b0;

    forever 
    begin
        sdr_cmd_e c;
        @(posedge vif.clk);

        c = decode_sdr_cmd(vif.cs_n, vif.ras_n, vif.cas_n, vif.we_n, vif.addr[AP_BIT],
                            cke_prev, vif.cke, in_self_refresh);

        if (c != CMD_NOP && c != CMD_DES) begin
        sdr_cmd_evt_txn ce = sdr_cmd_evt_txn::type_id::create("ce");
        ce.cmd  = c;
        ce.bank = vif.ba;
        ce.addr = vif.addr;
        cmd_evt_ap.write(ce);
        end

        case (c)
        CMD_ACT : open_row[vif.ba] = vif.addr;

        CMD_WR, CMD_WRA : 
        begin
            sdram_cmd_txn t = sdram_cmd_txn::type_id::create("t");
            t.bank     = vif.ba;
            t.row      = open_row[vif.ba];
            t.col      = vif.addr[COL_W-1:0];
            t.is_write = 1'b1;
            t.data     = vif.dq;
            cmd_ap.write(t);
        end

        CMD_SRE : 
        begin
            sdr_pwr_evt_txn e = sdr_pwr_evt_txn::type_id::create("e");
            e.evt = PWR_EVT_SRE;
            in_self_refresh = 1'b1;
            pwr_ap.write(e);
        end

        CMD_PDE : 
        begin
            sdr_pwr_evt_txn e = sdr_pwr_evt_txn::type_id::create("e");
            e.evt = PWR_EVT_PDE;
            pwr_ap.write(e);
        end

        CMD_PDX : 
        begin
            sdr_pwr_evt_txn e = sdr_pwr_evt_txn::type_id::create("e");
            e.evt = PWR_EVT_PDX;
            pwr_ap.write(e);
        end

        CMD_SRX : 
        begin
            sdr_pwr_evt_txn e = sdr_pwr_evt_txn::type_id::create("e");
            e.evt = PWR_EVT_SRX;
            in_self_refresh = 1'b0;
            pwr_ap.write(e);
        end

        CMD_DES, CMD_NOP, CMD_RD, CMD_RDA, CMD_PRE, CMD_PREA, CMD_REF, CMD_MRS : ; // no action needed
        default : ;
        endcase

        cke_prev = vif.cke;
    end
    endtask
endclass