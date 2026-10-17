// -----------------------------------------------------------------------
// sdram_if.sv
// Back-end SDR SDRAM device interface, used by the BFM monitor to
// independently snoop the commands the DUT actually drives.
// -----------------------------------------------------------------------
 
interface sdram_if #(
  parameter int BANK_W = 2,   // 4 banks
  parameter int ROW_W  = 12,  // 4096 rows
  parameter int DATA_W = 16
)(
  input logic clk,
  input logic rst_n
);
 
  logic                 cs_n;
  logic                 ras_n;
  logic                 cas_n;
  logic                 we_n;
  logic                 cke_n;
  logic [BANK_W-1:0]    ba;
  logic [ROW_W-1:0]     addr;
  logic                 dqm;
  wire  [DATA_W-1:0]    dq;
 
  modport mon (
    input cs_n, ras_n, cas_n, we_n, cke_n, ba, addr, dqm, dq, clk, rst_n
  );
 
endinterface
