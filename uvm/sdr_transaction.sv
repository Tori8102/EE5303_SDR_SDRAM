// ---------------------------------------------------------------
// AXI transaction
// ---------------------------------------------------------------
class axi_txn extends uvm_sequence_item;
    rand bit                    wr;      // 1 = write, 0 = read
    rand bit    [ADDR_W-1:0]    addr;
    rand bit    [DATA_W-1:0]    wdata;
    bit         [DATA_W-1:0]    rdata;

    `uvm_object_utils_begin(axi_txn)
        `uvm_field_int(wr,    UVM_ALL_ON)
        `uvm_field_int(addr,  UVM_ALL_ON)
        `uvm_field_int(wdata, UVM_ALL_ON)
        `uvm_field_int(rdata, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "axi_txn");
        super.new(name);
    endfunction
endclass


// ---------------------------------------------------------------
// APB transaction
// ---------------------------------------------------------------
class apb_txn extends uvm_sequence_item;
    rand bit                        wr;    // 1 = write, 0 = read
    rand bit    [APB_ADDR_W-1:0]    addr;
    rand bit    [DATA_W-1:0]        wdata;
    bit         [DATA_W-1:0]        rdata;

    `uvm_object_utils_begin(apb_txn)
        `uvm_field_int(wr,    UVM_ALL_ON)
        `uvm_field_int(addr,  UVM_ALL_ON)
        `uvm_field_int(wdata, UVM_ALL_ON)
        `uvm_field_int(rdata, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "apb_txn");
        super.new(name);
    endfunction
endclass

// ---------------------------------------------------------------
// sdr_monitor: back-end BFM monitor. 
// Independently decodes SDR commands from the physical command bus and:
//  (a) tracks the data the DUT actually wrote into {bank,row,col} (sdram_cmd_txn), for the AXI-vs-backend data cross-check
//  (b) detects PDE/PDX/SRE/SRX low-power events from CKE transitions relative to the command bus (sdr_pwr_evt_txn), for the low-power protocol cross-check.
// ---------------------------------------------------------------
class sdram_cmd_txn extends uvm_sequence_item;
    bit     [BANK_W-1:0]            bank;
    bit     [ROW_W-1:0]             row;
    bit     [COL_W-1:0]             col;
    bit                             is_write;
    bit     [DATA_W-1:0]            data;

    `uvm_object_utils(sdram_cmd_txn)
        function new(string name = "sdram_cmd_txn");
        super.new(name);
    endfunction
endclass

typedef enum {PWR_EVT_PDE, PWR_EVT_PDX, PWR_EVT_SRE, PWR_EVT_SRX} pwr_evt_e;

class sdr_pwr_evt_txn extends uvm_sequence_item;
    pwr_evt_e                       evt;

    `uvm_object_utils(sdr_pwr_evt_txn)
        function new(string name = "sdr_pwr_evt_txn");
        super.new(name);
    endfunction
endclass

class sdr_cmd_evt_txn extends uvm_sequence_item;
    sdr_cmd_e        cmd;
    bit [BANK_W-1:0] bank;
    bit [ROW_W-1:0]  addr; // raw address bus at the time (row/col/MRS value, depending on cmd)

    `uvm_object_utils(sdr_cmd_evt_txn)
    function new(string name = "sdr_cmd_evt_txn");
    super.new(name);
    endfunction
endclass