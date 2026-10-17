// ---------------------------------------------------------------
// AXI monitor
// ---------------------------------------------------------------
class axi_monitor extends uvm_monitor;
    `uvm_component_utils(axi_monitor)
    virtual axi_if.mon vif;
    uvm_analysis_port #(axi_txn) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_if.mon)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "axi_monitor: virtual interface not set")
    endfunction

    task run_phase(uvm_phase phase);
        fork
            // Write side: AW+W accepted -> record expected write, wait for B
            forever 
            begin
            @(posedge vif.clk);
            if (vif.awvalid && vif.awready && vif.wvalid && vif.wready) 
            begin
                axi_txn tx = axi_txn::type_id::create("tx");
                tx.wr    = 1'b1;
                tx.addr  = vif.awaddr;
                tx.wdata = vif.wdata;
                do @(posedge vif.clk); while (!(vif.bvalid && vif.bready));
                ap.write(tx);
            end
            end
            // Read side: AR accepted -> wait for R, record read-back data
            forever 
            begin
                @(posedge vif.clk);
                if (vif.arvalid && vif.arready) begin
                    axi_txn tx = axi_txn::type_id::create("tx");
                    tx.wr   = 1'b0;
                    tx.addr = vif.araddr;
                    do @(posedge vif.clk); while (!(vif.rvalid && vif.rready));
                    tx.rdata = vif.rdata;
                    ap.write(tx);
                end
            end
        join
    endtask
endclass