// -----------------------------------------------------------------------
// apb_if.sv
// APB interface between the UVM APB agent and the sdr_ctrl DUT's config/
// status port (STATUS @ 0x00, CTRL @ 0x04 — see rtl/sdr_ctrl.sv header).
// -----------------------------------------------------------------------
 
interface apb_if #(
  parameter int ADDR_W = 8,
  parameter int DATA_W = 16
)(
  input logic clk,
  input logic rst_n
);
 
  logic                psel;
  logic                penable;
  logic                pwrite;
  logic [ADDR_W-1:0]   paddr;
  logic [DATA_W-1:0]   pwdata;
  logic [DATA_W-1:0]   prdata;
  logic                pready;
  logic                pslverr;
 
  modport drv (
    output psel, penable, pwrite, paddr, pwdata,
    input  prdata, pready, pslverr,
    input  clk, rst_n
  );
 
  modport mon (
    input psel, penable, pwrite, paddr, pwdata, prdata, pready, pslverr,
    input clk, rst_n
  );
 
endinterface