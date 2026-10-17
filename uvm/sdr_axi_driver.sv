// ---------------------------------------------------------------
// AXI driver
// ---------------------------------------------------------------
class axi_driver extends uvm_driver #(axi_txn);
    `uvm_component_utils(axi_driver)
    virtual axi_if.drv vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_if.drv)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "axi_driver: virtual interface not set")
    endfunction

    task run_phase(uvm_phase phase);
        vif.awvalid <= 1'b0;
        vif.wvalid  <= 1'b0;
        vif.bready  <= 1'b1;
        vif.arvalid <= 1'b0;
        vif.rready  <= 1'b1;
        vif.awlen   <= '0;
        vif.awsize  <= 3'b001; // 16-bit (2-byte) beats
        vif.awburst <= 2'b01;  // INCR (unused, single-beat)
        vif.arlen   <= '0;
        vif.arsize  <= 3'b001;
        vif.arburst <= 2'b01;
        vif.wstrb   <= '1;
        vif.wlast   <= 1'b1;
        @(posedge vif.rst_n);

        forever 
        begin
            axi_txn tx;
            seq_item_port.get_next_item(tx);

            if (tx.wr) 
            begin
                @(posedge vif.clk);
                vif.awvalid <= 1'b1;
                vif.awaddr  <= tx.addr;
                vif.awid    <= '0;
                vif.wvalid  <= 1'b1;
                vif.wdata   <= tx.wdata;

                do @(posedge vif.clk); while (!(vif.awready && vif.wready));
                vif.awvalid <= 1'b0;
                vif.wvalid  <= 1'b0;

                do @(posedge vif.clk); while (!vif.bvalid);
            end 
            else 
            begin
                @(posedge vif.clk);
                vif.arvalid <= 1'b1;
                vif.araddr  <= tx.addr;
                vif.arid    <= '0;

                do @(posedge vif.clk); while (!vif.arready);
                vif.arvalid <= 1'b0;

                do @(posedge vif.clk); while (!vif.rvalid);
                tx.rdata = vif.rdata;
            end

            seq_item_port.item_done();
        end
    endtask
endclass