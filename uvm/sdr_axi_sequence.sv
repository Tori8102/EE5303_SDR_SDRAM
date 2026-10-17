// ---------------------------------------------------------------
// AXI sequences
// ---------------------------------------------------------------
class axi_write_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_write_seq)
    rand bit [ADDR_W-1:0] addr;
    rand bit [DATA_W-1:0] data;

    function new(string name = "axi_write_seq");
        super.new(name);
    endfunction

    task body();
        axi_txn tx = axi_txn::type_id::create("tx");
        start_item(tx);
        tx.wr    = 1'b1;
        tx.addr  = addr;
        tx.wdata = data;
        finish_item(tx);
    endtask
endclass

class axi_read_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_read_seq)
    rand bit [ADDR_W-1:0] addr;

    function new(string name = "axi_read_seq");
        super.new(name);
    endfunction

    task body();
        axi_txn tx = axi_txn::type_id::create("tx");
        start_item(tx);
        tx.wr   = 1'b0;
        tx.addr = addr;
        finish_item(tx);
    endtask
endclass

// Random directed write-then-read-back traffic
class axi_wr_rd_seq extends uvm_sequence #(axi_txn);
    `uvm_object_utils(axi_wr_rd_seq)
    rand int unsigned num_txns = 20;

    function new(string name = "axi_wr_rd_seq");
        super.new(name);
    endfunction

    task body();
        bit [ADDR_W-1:0] addrs[$];
        bit [DATA_W-1:0] datas[$];

        for (int i = 0; i < num_txns; i++) 
        begin
            axi_txn tx = axi_txn::type_id::create("tx");
            bit [ADDR_W-1:0] a;
            bit [DATA_W-1:0] d;
            assert(std::randomize(a, d));
            addrs.push_back(a);
            datas.push_back(d);

            start_item(tx);
            tx.wr    = 1'b1;
            tx.addr  = a;
            tx.wdata = d;
            finish_item(tx);
        end

        foreach (addrs[i]) 
        begin
            axi_txn tx = axi_txn::type_id::create("tx");
            start_item(tx);
            tx.wr   = 1'b0;
            tx.addr = addrs[i];
            finish_item(tx);
        end
    endtask
endclass