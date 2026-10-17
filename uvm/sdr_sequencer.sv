// ---------------------------------------------------------------
// Virtual sequencer: coordinates AXI and APB sequences from a single
// top-level test sequence (e.g. issue AXI traffic, then drive an APB
// low-power sequence, then resume AXI traffic).
// ---------------------------------------------------------------
class sdr_virtual_sequencer extends uvm_sequencer;
    `uvm_component_utils(sdr_virtual_sequencer)
    axi_sequencer axi_seqr;
    apb_sequencer apb_seqr;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass