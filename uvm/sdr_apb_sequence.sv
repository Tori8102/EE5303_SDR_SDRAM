
// ---------------------------------------------------------------
// APB sequences
// ---------------------------------------------------------------
class apb_write_seq extends uvm_sequence #(apb_txn);
    `uvm_object_utils(apb_write_seq)
    rand bit [APB_ADDR_W-1:0] addr;
    rand bit [DATA_W-1:0]     data;

    function new(string name = "apb_write_seq");
    super.new(name);
    endfunction

    task body();
    apb_txn tx = apb_txn::type_id::create("tx");
    start_item(tx);
    tx.wr    = 1'b1;
    tx.addr  = addr;
    tx.wdata = data;
    finish_item(tx);
    endtask
endclass

class apb_read_seq extends uvm_sequence #(apb_txn);
    `uvm_object_utils(apb_read_seq)
    rand bit [APB_ADDR_W-1:0] addr;
        bit [DATA_W-1:0]     rdata;

    function new(string name = "apb_read_seq");
    super.new(name);
    endfunction

    task body();
    apb_txn tx = apb_txn::type_id::create("tx");
    start_item(tx);
    tx.wr   = 1'b0;
    tx.addr = addr;
    finish_item(tx);
    rdata = tx.rdata;
    endtask
endclass

// Convenience sequences: PDE/PDX/SRE/SRX requested via the CTRL register
// (address APB_ADDR_CTRL: bit0=pd_req, bit1=sr_req). sr_req takes
// priority over pd_req in the DUT if both are asserted (see
// rtl/sdr_ctrl_core.sv), so these sequences keep the two bits mutually
// exclusive to request one clean state transition at a time.
class apb_pde_entry_seq extends uvm_sequence #(apb_txn);
    `uvm_object_utils(apb_pde_entry_seq)
    function new(string name = "apb_pde_entry_seq");
    super.new(name);
    endfunction
    task body();
    apb_write_seq seq = apb_write_seq::type_id::create("seq");
    seq.addr = APB_ADDR_CTRL;
    seq.data = {{(DATA_W-2){1'b0}}, 1'b0 /*sr_req*/, 1'b1 /*pd_req*/};
    seq.start(m_sequencer, this);
    endtask
endclass

class apb_pde_exit_seq extends uvm_sequence #(apb_txn);
    `uvm_object_utils(apb_pde_exit_seq)
    function new(string name = "apb_pde_exit_seq");
    super.new(name);
    endfunction
    task body();
    apb_write_seq seq = apb_write_seq::type_id::create("seq");
    seq.addr = APB_ADDR_CTRL;
    seq.data = '0;
    seq.start(m_sequencer, this);
    endtask
endclass

class apb_sre_entry_seq extends uvm_sequence #(apb_txn);
    `uvm_object_utils(apb_sre_entry_seq)
    function new(string name = "apb_sre_entry_seq");
    super.new(name);
    endfunction
    task body();
    apb_write_seq seq = apb_write_seq::type_id::create("seq");
    seq.addr = APB_ADDR_CTRL;
    seq.data = {{(DATA_W-2){1'b0}}, 1'b1 /*sr_req*/, 1'b0 /*pd_req*/};
    seq.start(m_sequencer, this);
    endtask
endclass

class apb_sre_exit_seq extends uvm_sequence #(apb_txn);
    `uvm_object_utils(apb_sre_exit_seq)
    function new(string name = "apb_sre_exit_seq");
    super.new(name);
    endfunction
    task body();
    apb_write_seq seq = apb_write_seq::type_id::create("seq");
    seq.addr = APB_ADDR_CTRL;
    seq.data = '0;
    seq.start(m_sequencer, this);
    endtask
endclass

// Runtime MRS re-issue: CTRL bit2 is write-1-to-pulse (not stored -- see
// rtl/sdr_ctrl.sv header), so a single write with bit2=1 is the entire
// request; no separate "clear" sequence is needed (readback is always 0).
class apb_mrs_pulse_seq extends uvm_sequence #(apb_txn);
    `uvm_object_utils(apb_mrs_pulse_seq)
    function new(string name = "apb_mrs_pulse_seq");
    super.new(name);
    endfunction
    task body();
    apb_write_seq seq = apb_write_seq::type_id::create("seq");
    seq.addr = APB_ADDR_CTRL;
    seq.data = {{(DATA_W-3){1'b0}}, 1'b1 /*mrs_req*/, 1'b0 /*sr_req*/, 1'b0 /*pd_req*/};
    seq.start(m_sequencer, this);
    endtask
endclass