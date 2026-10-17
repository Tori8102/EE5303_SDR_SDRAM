// ---------------------------------------------------------------
// APB driver (standard 3-phase IDLE/SETUP/ENABLE handshake)
// ---------------------------------------------------------------
class apb_driver extends uvm_driver #(apb_txn);
    `uvm_component_utils(apb_driver)
    virtual apb_if.drv vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual apb_if.drv)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "apb_driver: virtual interface not set")
    endfunction

    task run_phase(uvm_phase phase);
        vif.psel    <= 1'b0;
        vif.penable <= 1'b0;
        vif.pwrite  <= 1'b0;
        vif.paddr   <= '0;
        vif.pwdata  <= '0;
        @(posedge vif.rst_n);

        forever 
        begin
            apb_txn tx;
            seq_item_port.get_next_item(tx);

            // SETUP phase
            @(posedge vif.clk);
            vif.psel    <= 1'b1;
            vif.penable <= 1'b0;
            vif.pwrite  <= tx.wr;
            vif.paddr   <= tx.addr;
            vif.pwdata  <= tx.wdata;

            // ENABLE phase
            @(posedge vif.clk);
            vif.penable <= 1'b1;

            do @(posedge vif.clk); while (!vif.pready);
            if (!tx.wr) tx.rdata = vif.prdata;

            vif.psel    <= 1'b0;
            vif.penable <= 1'b0;

            seq_item_port.item_done();
        end
    endtask
endclass