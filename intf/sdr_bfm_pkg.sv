// ----------------------------------------------------------------------- 
// sdr_bfm_pkg.sv 
// Plain (non-UVM) bus-functional-model tasks
// ----------------------------------------------------------------------- 
package sdr_bfm_pkg; 
  localparam int MEM_ADDR_W = 22; 
  localparam int ADDR_W     = MEM_ADDR_W + 1; 
  localparam int DATA_W     = 16; 
  localparam int ID_W       = 4; 
  localparam int APB_ADDR_W = 8; 
  // ---------------- AXI4 (single-beat
  task automatic axi_write_ap
  ( 
    virtual axi_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W)).drv vif, 
    input bit [MEM_ADDR_W-1:0] addr, 
    input bit [DATA_W-1:0]     data, 
    input bit                  ap 
  ); 
    @(posedge vif.clk); 
    vif.awvalid <= 1'b1; 
    vif.awaddr  <= {ap, addr}; 
    vif.awid    <= '0; 
    vif.wvalid  <= 1'b1; 
    vif.wdata   <= data; 
    vif.wstrb   <= '1;   // only meaningful while wvalid is high
    vif.wlast   <= 1'b1; // only meaningful while wvalid is high
    do @(posedge vif.clk); while (!(vif.awready && vif.wready)); 
    vif.awvalid <= 1'b0; 
    vif.wvalid  <= 1'b0; 
    vif.wstrb   <= 'x;   // not valid while wvalid is low
    vif.wlast   <= 1'bx; // not valid while wvalid is low
    do @(posedge vif.clk); while (!vif.bvalid); 
  endtask 

  task automatic axi_read_ap
  ( 
    virtual axi_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W)).drv vif, 
    input  bit [MEM_ADDR_W-1:0] addr, 
    input  bit                  ap, 
    output bit [DATA_W-1:0]     data 
  ); 
    @(posedge vif.clk); 
    vif.arvalid <= 1'b1; 
    vif.araddr  <= {ap, addr}; 
    vif.arid    <= '0; 
    do @(posedge vif.clk); while (!vif.arready); 
    vif.arvalid <= 1'b0; 
    do @(posedge vif.clk); while (!vif.rvalid); 
    data = vif.rdata; 
  endtask 

  task automatic axi_write_burst_ap
  (
    virtual axi_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W)).drv vif,
    input bit [MEM_ADDR_W-1:0] addr,
    input bit [DATA_W-1:0]     data[],
    input bit                  ap
  );
    int n;
    n = data.size();
    @(posedge vif.clk);
    vif.awvalid <= 1'b1;
    vif.awaddr  <= {ap, addr};
    vif.awid    <= '0;
    vif.awlen   <= n[7:0] - 8'd1; // AWLEN = burst_length - 1
    do @(posedge vif.clk); while (!vif.awready);
    vif.awvalid <= 1'b0;
    for (int i = 0; i < n; i++) begin
      vif.wvalid <= 1'b1;
      vif.wdata  <= data[i];
      vif.wstrb  <= '1;
      vif.wlast  <= (i == n - 1); //  WLAST only on the final beat
      do @(posedge vif.clk); while (!vif.wready);
    end
    vif.wvalid <= 1'b0;
    vif.wstrb  <= 'x;
    vif.wlast  <= 1'bx;
    do @(posedge vif.clk); while (!vif.bvalid); //  single BVALID after the whole burst
  endtask

  task automatic axi_write_burst
  (
    virtual axi_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W)).drv vif,
    input bit [MEM_ADDR_W-1:0] addr,
    input bit [DATA_W-1:0]     data[]
  );
    axi_write_burst_ap(vif, addr, data, 1'b1); // AP=1 on the final beat only
  endtask

  task automatic axi_read_burst_ap
  (
    virtual axi_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W)).drv vif,
    input  bit [MEM_ADDR_W-1:0] addr,
    input  bit                  ap,
    input  int                  n,
    output bit [DATA_W-1:0]     data[]
  );
    data = new[n];
    @(posedge vif.clk);
    vif.arvalid <= 1'b1;
    vif.araddr  <= {ap, addr};
    vif.arid    <= '0;
    vif.arlen   <= n[7:0] - 8'd1; //  ARLEN = burst_length - 1
    do @(posedge vif.clk); while (!vif.arready);
    vif.arvalid <= 1'b0;
    for (int i = 0; i < n; i++) begin
      do @(posedge vif.clk); while (!vif.rvalid);
      data[i] = vif.rdata;
      if (i == n - 1)
        assert (vif.rlast) else $error("axi_read_burst_ap: RLAST not asserted on final beat"); // 
      else
        assert (!vif.rlast) else $error("axi_read_burst_ap: RLAST asserted early"); // 
    end
  endtask

  task automatic axi_read_burst
  (
    virtual axi_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W)).drv vif,
    input  bit [MEM_ADDR_W-1:0] addr,
    input  int                  n,
    output bit [DATA_W-1:0]     data[]
  );
    axi_read_burst_ap(vif, addr, 1'b1, n, data); // AP=1 on the final beat only
  endtask

  task automatic axi_write
  ( 
    virtual axi_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W)).drv vif, 
    input bit [MEM_ADDR_W-1:0] addr, 
    input bit [DATA_W-1:0]     data 
  ); 
    axi_write_ap(vif, addr, data, 1'b1); // AP=1: auto-precharge (legacy default) 
  endtask 

  task automatic axi_read
  ( 
    virtual axi_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W)).drv vif, 
    input  bit [MEM_ADDR_W-1:0] addr, 
    output bit [DATA_W-1:0]     data 
  ); 
    axi_read_ap(vif, addr, 1'b1, data); // AP=1: auto-precharge (legacy default) 
  endtask 

  task automatic axi_write_noap
  ( 
    virtual axi_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W)).drv vif, 
    input bit [MEM_ADDR_W-1:0] addr, 
    input bit [DATA_W-1:0]     data 
  ); 
    axi_write_ap(vif, addr, data, 1'b0); // AP=0: plain, row stays open 
  endtask 

  task automatic axi_read_noap
  ( 
    virtual axi_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W)).drv vif, 
    input  bit [MEM_ADDR_W-1:0] addr, 
    output bit [DATA_W-1:0]     data 
  ); 
    axi_read_ap(vif, addr, 1'b0, data); // AP=0: plain, row stays open 
  endtask 

  task automatic axi_if_init (virtual axi_if #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W)).drv vif); 
    vif.awvalid <= 1'b0; 
    vif.wvalid  <= 1'b0; 
    vif.bready  <= 1'b1; 
    vif.arvalid <= 1'b0; 
    vif.rready  <= 1'b1; 
    vif.awlen   <= '0; 
    vif.awsize  <= 3'b001; 
    vif.awburst <= 2'b01; 
    vif.arlen   <= '0; 
    vif.arsize  <= 3'b001; 
    vif.arburst <= 2'b01; 
    vif.wstrb   <= 'x;   // not valid at reset/idle (no transaction in flight)
    vif.wlast   <= 1'bx; // not valid at reset/idle (no transaction in flight)
  endtask 

  // ---------------- APB (3-phase IDLE/SETUP/ENABLE) ---------------- 
  task automatic apb_write
  ( 
    virtual apb_if #(.ADDR_W(APB_ADDR_W), .DATA_W(DATA_W)).drv vif, 
    input bit [APB_ADDR_W-1:0] addr, 
    input bit [DATA_W-1:0]     data 
  ); 
    @(posedge vif.clk); 
    vif.psel    <= 1'b1; 
    vif.penable <= 1'b0; 
    vif.pwrite  <= 1'b1; 
    vif.paddr   <= addr; 
    vif.pwdata  <= data; 
    @(posedge vif.clk); 
    vif.penable <= 1'b1; 
    do @(posedge vif.clk); while (!vif.pready); 
    vif.psel    <= 1'b0; 
    vif.penable <= 1'b0; 
  endtask 

  task automatic apb_read
  ( 
    virtual apb_if #(.ADDR_W(APB_ADDR_W), .DATA_W(DATA_W)).drv vif, 
    input  bit [APB_ADDR_W-1:0] addr, 
    output bit [DATA_W-1:0]     data 
  ); 
    @(posedge vif.clk); 
    vif.psel    <= 1'b1; 
    vif.penable <= 1'b0; 
    vif.pwrite  <= 1'b0; 
    vif.paddr   <= addr; 
    @(posedge vif.clk); 
    vif.penable <= 1'b1; 
    do @(posedge vif.clk); while (!vif.pready); 
    data = vif.prdata; 
    vif.psel    <= 1'b0; 
    vif.penable <= 1'b0; 
  endtask 

  task automatic apb_if_init (virtual apb_if #(.ADDR_W(APB_ADDR_W), .DATA_W(DATA_W)).drv vif); 
    vif.psel    <= 1'b0; 
    vif.penable <= 1'b0; 
    vif.pwrite  <= 1'b0; 
    vif.paddr   <= '0; 
    vif.pwdata  <= '0; 
  endtask 

  // CTRL register bit positions (see rtl/sdr_ctrl.sv header) 
  localparam bit [APB_ADDR_W-1:0] APB_ADDR_STATUS = 8'h00; 
  localparam bit [APB_ADDR_W-1:0] APB_ADDR_CTRL   = 8'h04; 
  task automatic apb_set_pd_sr
  ( 
    virtual apb_if #(.ADDR_W(APB_ADDR_W), .DATA_W(DATA_W)).drv vif, 
    input bit pd_req, 
    input bit sr_req 
  ); 
    bit [DATA_W-1:0] wdata; 
    wdata = {13'b0, 1'b0 /*mrs_req*/, sr_req, pd_req}; 
    apb_write(vif, APB_ADDR_CTRL, wdata); 
  endtask 

  task automatic apb_mrs_pulse(virtual apb_if #(.ADDR_W(APB_ADDR_W), .DATA_W(DATA_W)).drv vif); 
    apb_write(vif, APB_ADDR_CTRL, 16'h0004); // bit2 = mrs_req (write-1-to-pulse) 
  endtask 

  // ---------------- Manual row open/close (CTRL bit3 + ROW_BANKROW) ------ 
  // See rtl/sdr_ctrl.sv register map: CTRL bit3=act_req; ROW_BANKROW carries {bank,row}, too wide for a single 16-bit APB write's other 
  // fields to share. All actual data access, whether on a row this opened or not, goes through AXI (axi_write_noap/axi_read_noap to keep it 
  // open, axi_write/axi_read -- AP=1 -- to close it) -- there is no APB data path. 
  localparam bit [APB_ADDR_W-1:0] APB_ADDR_ROW_BANKROW = 8'h08; 
  task automatic apb_row_open
  ( 
    virtual apb_if #(.ADDR_W(APB_ADDR_W), .DATA_W(DATA_W)).drv vif, 
    input bit [1:0]  bank, 
    input bit [11:0] row 
  ); 
    apb_write(vif, APB_ADDR_ROW_BANKROW, {2'b0, bank, row}); 
    apb_write(vif, APB_ADDR_CTRL, 16'h0008); // bit3 = act_req = 1 (open/hold) 
  endtask 

  task automatic apb_row_close(virtual apb_if #(.ADDR_W(APB_ADDR_W), .DATA_W(DATA_W)).drv vif); 
    apb_write(vif, APB_ADDR_CTRL, 16'h0000); // bit3 = act_req = 0 (close via PRE) 
  endtask 

  task automatic apb_wait_row_open(virtual apb_if #(.ADDR_W(APB_ADDR_W), .DATA_W(DATA_W)).drv vif); 
    bit [15:0] status; 
    do begin 
      apb_read(vif, APB_ADDR_STATUS, status); 
    end while (!status[4]); // row_open 
  endtask 

  task automatic apb_wait_row_closed(virtual apb_if #(.ADDR_W(APB_ADDR_W), .DATA_W(DATA_W)).drv vif); 
    bit [15:0] status; 
    do begin 
      apb_read(vif, APB_ADDR_STATUS, status); 
    end while (status[4]); // row_open 
  endtask 

  // Auto-precharge / precharge-all qualifier bit position within the 
  // back-end address bus -- mirrors rtl/sdr_ctrl_core.sv's `AP_BIT` 
  // localparam (and tb/sdr_pkg.sv's copy of the same constant) exactly. 
  localparam int AP_BIT = 8; // == COL_W (see rtl/sdr_ctrl_core.sv header) 
  // ---------------- Back-end SDR command decode (non-UVM) ---------------- 
  // Deliberately duplicated (not shared) from tb/sdr_pkg.sv::decode_sdr_cmd -- sdr_pkg depends on uvm_pkg, which these plain "_tb" modules 
  // intentionally avoid. Same decode table, same `ap` (A10/AP_BIT qualifier) distinguishing RD/RDA, WR/WRA, PRE/PREA, and the same PDX/ 
  // SRX disambiguation method (caller-supplied `in_self_refresh` context, mirroring the RTL's own state register -- see rtl/sdr_ctrl_core.sv header). 
  typedef enum {CMD_DES, CMD_NOP, CMD_ACT, CMD_RD, CMD_RDA, CMD_WR, CMD_WRA, 
                CMD_PRE, CMD_PREA, CMD_REF, CMD_MRS, CMD_PDE, CMD_PDX, 
                CMD_SRE, CMD_SRX} sdr_cmd_e; 
  function automatic sdr_cmd_e decode_sdr_cmd
  ( 
    input bit cs_n, ras_n, cas_n, we_n, 
    input bit ap, // address bus's A10/AP_BIT qualifier, same cycle as cs/ras/cas/we 
    input bit cke_prev_n, cke_n, 
    input bit in_self_refresh 
  ); 
    sdr_cmd_e base; 
    if (cs_n)                            base = CMD_NOP; 
    else if (!ras_n && cas_n && we_n)    base = CMD_ACT; 
    else if (ras_n && !cas_n && we_n)    base = ap ? CMD_RDA : CMD_RD; 
    else if (ras_n && !cas_n && !we_n)   base = ap ? CMD_WRA : CMD_WR; 
    else if (!ras_n && cas_n && !we_n)   base = ap ? CMD_PREA : CMD_PRE; 
    else if (!ras_n && !cas_n && we_n)   base = CMD_REF; 
    else if (!ras_n && !cas_n && !we_n)  base = CMD_MRS; 
    else                                  base = CMD_NOP; 
    if (!cke_prev_n && cke_n) begin 
      if (base == CMD_REF) return CMD_SRE; 
      if (base == CMD_NOP) return CMD_PDE; 
    end else if (cke_prev_n && !cke_n) begin 
      if (base == CMD_NOP) return in_self_refresh ? CMD_SRX : CMD_PDX; 
    end 
    return base; 
  endfunction 
endpackage 