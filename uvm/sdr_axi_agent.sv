// ---------------------------------------------------------------
// AXI agent
// ---------------------------------------------------------------
class axi_agent extends uvm_agent;
    `uvm_component_utils(axi_agent)
    axi_driver    drv;
    axi_monitor   mon;
    axi_sequencer seqr;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        drv  = axi_driver::type_id::create("drv", this);
        mon  = axi_monitor::type_id::create("mon", this);
        seqr = axi_sequencer::type_id::create("seqr", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction
endclass