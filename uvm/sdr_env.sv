 // ---------------------------------------------------------------
// Environment
// ---------------------------------------------------------------
class sdr_env extends uvm_env;
    `uvm_component_utils(sdr_env)

    axi_agent             axi_agt;
    apb_agent             apb_agt;
    sdr_monitor           sdr_mon;
    sdr_scoreboard        sb;
    sdr_virtual_sequencer vseqr;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        axi_agt = axi_agent::type_id::create("axi_agt", this);
        apb_agt = apb_agent::type_id::create("apb_agt", this);
        sdr_mon = sdr_monitor::type_id::create("sdr_mon", this);
        sb      = sdr_scoreboard::type_id::create("sb", this);
        vseqr   = sdr_virtual_sequencer::type_id::create("vseqr", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        axi_agt.mon.ap.connect(sb.axi_imp);
        sdr_mon.cmd_ap.connect(sb.bfm_imp);
        sdr_mon.pwr_ap.connect(sb.pwr_imp);
        sdr_mon.cmd_evt_ap.connect(sb.cmdevt_imp);
        apb_agt.mon.ap.connect(sb.apb_imp);
        vseqr.axi_seqr = axi_agt.seqr;
        vseqr.apb_seqr = apb_agt.seqr;
    endfunction
endclass