 
// ---------------------------------------------------------------
// APB monitor
// ---------------------------------------------------------------
class apb_monitor extends uvm_monitor;
    `uvm_component_utils(apb_monitor)
    virtual apb_if.mon vif;
    uvm_analysis_port #(apb_txn) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual apb_if.mon)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "apb_monitor: virtual interface not set")
    endfunction

    task run_phase(uvm_phase phase);
        forever 
        begin
            @(posedge vif.clk);
            if (vif.psel && vif.penable && vif.pready) begin
            apb_txn tx = apb_txn::type_id::create("tx");
            tx.wr    = vif.pwrite;
            tx.addr  = vif.paddr;
            tx.wdata = vif.pwdata;
            tx.rdata = vif.prdata;
            ap.write(tx);
            end
        end
    endtask
endclass