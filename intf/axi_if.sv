
// -----------------------------------------------------------------------
// axi_if.sv
// AXI4 slave-facing interface between the UVM agent and the sdr_ctrl DUT.
// Single-beat only (AWLEN/ARLEN forced to 0), matching the DUT's supported
// transaction size.
// -----------------------------------------------------------------------
 
interface axi_if #(
  parameter int ADDR_W = 16,
  parameter int DATA_W = 16,
  parameter int ID_W   = 4
)(
  input logic clk,
  input logic rst_n
);
 
  // Write Address Channel
  logic                  awvalid;
  logic                  awready;
  logic [ADDR_W-1:0]     awaddr;
  logic [ID_W-1:0]       awid;
  logic [7:0]            awlen;
  logic [2:0]            awsize;
  logic [1:0]            awburst;
 
  // Write Data Channel
  logic                  wvalid;
  logic                  wready;
  logic [DATA_W-1:0]     wdata;
  logic [(DATA_W/8)-1:0] wstrb;
  logic                  wlast;
 
  // Write Response Channel
  logic                  bvalid;
  logic                  bready;
  logic [1:0]            bresp;
  logic [ID_W-1:0]       bid;
 
  // Read Address Channel
  logic                  arvalid;
  logic                  arready;
  logic [ADDR_W-1:0]     araddr;
  logic [ID_W-1:0]       arid;
  logic [7:0]            arlen;
  logic [2:0]            arsize;
  logic [1:0]            arburst;
 
  // Read Data Channel
  logic                  rvalid;
  logic                  rready;
  logic [DATA_W-1:0]     rdata;
  logic [1:0]            rresp;
  logic                  rlast;
  logic [ID_W-1:0]       rid;
 
  modport drv (
    output awvalid, awaddr, awid, awlen, awsize, awburst,
    input  awready,
    output wvalid, wdata, wstrb, wlast,
    input  wready,
    input  bvalid, bresp, bid,
    output bready,
    output arvalid, araddr, arid, arlen, arsize, arburst,
    input  arready,
    input  rvalid, rdata, rresp, rlast, rid,
    output rready,
    input  clk, rst_n
  );
 
  modport mon (
    input awvalid, awready, awaddr, awid, awlen, awsize, awburst,
    input wvalid, wready, wdata, wstrb, wlast,
    input bvalid, bready, bresp, bid,
    input arvalid, arready, araddr, arid, arlen, arsize, arburst,
    input rvalid, rready, rdata, rresp, rlast, rid,
    input clk, rst_n
  );
 
endinterface