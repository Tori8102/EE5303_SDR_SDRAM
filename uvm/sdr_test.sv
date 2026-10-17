// ---------------------------------------------------------------
// Tests
// ---------------------------------------------------------------

// Baseline data-integrity test: AXI write/read-back traffic only.
class sdr_base_test extends uvm_test;
    `uvm_component_utils(sdr_base_test)
    sdr_env env;

    function new(string name, uvm_component parent);
    super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = sdr_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
    axi_wr_rd_seq seq = axi_wr_rd_seq::type_id::create("seq");
    phase.raise_objection(this);
    seq.num_txns = 20;
    seq.start(env.axi_agt.seqr);
    #200;
    phase.drop_objection(this);
    endtask
endclass

// -----------------------------------------------------------------
// Suggested 6-test plan
// -----------------------------------------------------------------

// 1. Sanity test: Power-up -> Init -> WR -> RD -> PREA (auto-precharge
// implicit in WRA/RDA -- see rtl header). A single directed write
// followed by a read-back of the same address; the scoreboard's
// check_phase verifies both the AXI-side loopback and the independent
// back-end cross-check.
class sdr_sanity_test extends uvm_test;
    `uvm_component_utils(sdr_sanity_test)
    sdr_env env;

    function new(string name, uvm_component parent);
    super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = sdr_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
    axi_write_seq wr_seq;
    axi_read_seq  rd_seq;

    phase.raise_objection(this);

    wr_seq = axi_write_seq::type_id::create("wr_seq");
    wr_seq.addr = {1'b1 /*AP*/, 22'h001234};
    wr_seq.data = 16'hBEEF;
    wr_seq.start(env.axi_agt.seqr);

    rd_seq = axi_read_seq::type_id::create("rd_seq");
    rd_seq.addr = {1'b1 /*AP*/, 22'h001234};
    rd_seq.start(env.axi_agt.seqr);

    #100;
    phase.drop_objection(this);
    endtask
endclass

// 2. Activate/Precharge/auto-precharge test: Power-up -> Init -> ACT ->
// WRA -> RDA (auto-precharge) repeated across several banks/rows, to
// exercise ACT being reissued for every access since every access here
// uses AP=1 (auto-precharge closes the row every time, so there's never
// an already-open row to reuse). Note the controller *does* support
// same-row reuse without a new ACT, and can also issue a standalone
// single-bank PRE or an automatic all-bank PREA post-init (e.g. ahead of
// REF/SRE/PPDE/MRS when a bank is left open) -- see rtl/sdr_ctrl_core.sv
// "Row lifecycle" header comment; this test just doesn't exercise either
// of those paths (see sdr_refresh_test/sdr_low_power_test for coverage
// closer to the auto-PREA path).
class sdr_act_pre_test extends uvm_test;
    `uvm_component_utils(sdr_act_pre_test)
    sdr_env env;

    function new(string name, uvm_component parent);
    super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = sdr_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
    // One write+read-back per bank (addr[21:20] = bank), forcing a fresh
    // ACT (and, via RDA/WRA, a fresh auto-precharge) each time.
    bit [ADDR_W-1:0] addrs[4] = '{{1'b1, 22'h000010}, {1'b1, 22'h100020},
                                    {1'b1, 22'h200030}, {1'b1, 22'h300040}}; // AP=1

    phase.raise_objection(this);

    foreach (addrs[i]) begin
        axi_write_seq wr_seq = axi_write_seq::type_id::create($sformatf("wr_seq%0d", i));
        axi_read_seq  rd_seq = axi_read_seq::type_id::create($sformatf("rd_seq%0d", i));
        wr_seq.addr = addrs[i];
        wr_seq.data = 16'hA000 + i;
        wr_seq.start(env.axi_agt.seqr);
        rd_seq.addr = addrs[i];
        rd_seq.start(env.axi_agt.seqr);
    end

    #100;
    if (env.sb.act_cnt < 4)
        `uvm_error("ACT_CNT", $sformatf("Expected >=4 ACT commands, observed %0d", env.sb.act_cnt))
    // Every access above uses AP=1, so these land as WRA/RDA (wra_cnt/
    // rda_cnt), not plain WR/RD -- see decode_sdr_cmd's `ap` distinction.
    if (env.sb.wra_cnt < 4 || env.sb.rda_cnt < 4)
        `uvm_error("WR_RD_CNT", $sformatf("Expected >=4 WRA/RDA each, observed wra=%0d rda=%0d",
                                        env.sb.wra_cnt, env.sb.rda_cnt))

    phase.drop_objection(this);
    endtask
endclass

// 3. Refresh test: Power-up -> Init -> (wait several tREFI periods,
// interleaved with normal WR/RD) -> confirm the periodic AUTO REFRESH
// scheduler (see rtl/sdr_ctrl_core.sv) actually fires automatically,
// with no host intervention, by checking the back-end-observed REF
// count via the scoreboard's cmdevt counters.
class sdr_refresh_test extends uvm_test;
    `uvm_component_utils(sdr_refresh_test)
    sdr_env env;
    // Matches sdr_ctrl_core's default T_REFI (cycles) and the testbench
    // clock period (10ns, see top_tb.sv) used to size the wait below.
    localparam int T_REFI_DEFAULT = 32;
    localparam int CLK_PERIOD_NS  = 10;

    function new(string name, uvm_component parent);
    super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = sdr_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
    axi_wr_rd_seq axi_s_eq;

    phase.raise_objection(this);

    axi_s_eq = axi_wr_rd_seq::type_id::create("axi_s_eq");
    axi_s_eq.num_txns = 4;
    axi_s_eq.start(env.axi_agt.seqr);

    // Wait long enough for several automatic REFRESH cycles to elapse
    // while otherwise idle.
    #(T_REFI_DEFAULT * CLK_PERIOD_NS * 4);

    axi_s_eq = axi_wr_rd_seq::type_id::create("axi_s_eq2");
    axi_s_eq.num_txns = 4;
    axi_s_eq.start(env.axi_agt.seqr);

    #100;
    if (env.sb.ref_cnt < 2)
        `uvm_error("REF_CNT", $sformatf("Expected >=2 periodic AUTO REFRESH commands, observed %0d",
                                        env.sb.ref_cnt))
    else
        `uvm_info("REF_CNT", $sformatf("Observed %0d AUTO REFRESH commands", env.sb.ref_cnt), UVM_LOW)

    phase.drop_objection(this);
    endtask
endclass

// 4. Low-power test: Power-up -> Init -> WR -> RD -> APDE -> (implicit
// PREA via auto-precharge) -> PPDE -> SRE. Exercises both Active
// Power-Down (requested while a write is still in flight, so pd_req is
// sampled from S_ACT -- see rtl header) and Precharge Power-Down /
// Self-Refresh (requested while idle). The scoreboard's low-power
// protocol cross-check doesn't need to know which of the two entry
// points actually fired -- PDE/PDX are bit-identical either way (see
// rtl/sdr_ctrl_core.sv header) -- it only checks the PDE/PDX/SRE/SRX
// *sequence* matches the APB requests.
class sdr_low_power_full_test extends uvm_test;
    `uvm_component_utils(sdr_low_power_full_test)
    sdr_env env;

    function new(string name, uvm_component parent);
    super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = sdr_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
    axi_write_seq     wr_seq;
    axi_read_seq      rd_seq;
    apb_pde_entry_seq pde_in;
    apb_pde_exit_seq  pde_out;
    apb_sre_entry_seq sre_in;
    apb_sre_exit_seq  sre_out;

    phase.raise_objection(this);

    // WR, with a pd_req pulse requested shortly after issue, aiming to
    // catch Active Power-Down (row open, tRCD still counting) -- not
    // guaranteed by construction (depends on relative AXI/APB timing),
    // but harmless either way since the scoreboard only checks the
    // PDE/PDX event sequence, not which entry point produced it.
    wr_seq = axi_write_seq::type_id::create("wr_seq");
    wr_seq.addr = {1'b1 /*AP*/, 22'h002000};
    wr_seq.data = 16'h1111;
    fork
        wr_seq.start(env.axi_agt.seqr);
        begin
        #5; // land inside the AXI access, before it completes
        pde_in = apb_pde_entry_seq::type_id::create("pde_in_active");
        pde_in.start(env.apb_agt.seqr);
        #30;
        pde_out = apb_pde_exit_seq::type_id::create("pde_out_active");
        pde_out.start(env.apb_agt.seqr);
        end
    join

    // RD, to confirm normal access still works after the Active
    // Power-Down excursion.
    rd_seq = axi_read_seq::type_id::create("rd_seq");
    rd_seq.addr = {1'b1 /*AP*/, 22'h002000};
    rd_seq.start(env.axi_agt.seqr);
    #20;

    // Now idle (post auto-precharge) -- Precharge Power-Down.
    pde_in = apb_pde_entry_seq::type_id::create("pde_in_precharge");
    pde_in.start(env.apb_agt.seqr);
    #100;
    pde_out = apb_pde_exit_seq::type_id::create("pde_out_precharge");
    pde_out.start(env.apb_agt.seqr);
    #50;

    // Self-Refresh.
    sre_in = apb_sre_entry_seq::type_id::create("sre_in");
    sre_in.start(env.apb_agt.seqr);
    #100;
    sre_out = apb_sre_exit_seq::type_id::create("sre_out");
    sre_out.start(env.apb_agt.seqr);

    #100;
    phase.drop_objection(this);
    endtask
endclass

// 5. MRS test: Power-up -> Init -> WR -> RD -> (implicit PREA) -> MRS
// (runtime re-issue pulse) -> WR -> RD -> (implicit PREA). Confirms the
// runtime MRS re-issue path (APB CTRL bit2, see rtl/sdr_ctrl.sv header)
// actually drives a second MRS on the back-end bus (the first MRS is
// the one-time init MRS program), and that normal accesses still work
// immediately afterward.
class sdr_mrs_test extends uvm_test;
    `uvm_component_utils(sdr_mrs_test)
    sdr_env env;

    function new(string name, uvm_component parent);
    super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = sdr_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
    axi_write_seq     wr_seq;
    axi_read_seq      rd_seq;
    apb_mrs_pulse_seq mrs_seq;

    phase.raise_objection(this);

    wr_seq = axi_write_seq::type_id::create("wr_seq1");
    wr_seq.addr = {1'b1 /*AP*/, 22'h003300};
    wr_seq.data = 16'h2222;
    wr_seq.start(env.axi_agt.seqr);

    rd_seq = axi_read_seq::type_id::create("rd_seq1");
    rd_seq.addr = {1'b1 /*AP*/, 22'h003300};
    rd_seq.start(env.axi_agt.seqr);

    #20;
    mrs_seq = apb_mrs_pulse_seq::type_id::create("mrs_seq");
    mrs_seq.start(env.apb_agt.seqr);
    #20;

    wr_seq = axi_write_seq::type_id::create("wr_seq2");
    wr_seq.addr = {1'b1 /*AP*/, 22'h003301};
    wr_seq.data = 16'h3333;
    wr_seq.start(env.axi_agt.seqr);

    rd_seq = axi_read_seq::type_id::create("rd_seq2");
    rd_seq.addr = {1'b1 /*AP*/, 22'h003301};
    rd_seq.start(env.axi_agt.seqr);

    #50;
    // MRS_cnt should be >=2: one from the one-time init sequence, one
    // from the runtime mrs_req pulse above.
    if (env.sb.MRS_cnt < 2)
        `uvm_error("MRS_CNT", $sformatf("Expected >=2 MRS commands (init + runtime re-issue), observed %0d",
                                        env.sb.MRS_cnt))
    else
        `uvm_info("MRS_CNT", $sformatf("Observed %0d MRS commands", env.sb.MRS_cnt), UVM_LOW)

    phase.drop_objection(this);
    endtask
endclass

// 6. Focus check write-read: directed addresses covering same-bank
// (different column/row), different-bank, and critical/boundary address
// corner cases (address 0, max address, bank/row boundaries) given the
// {bank[1:0],row[11:0],col[7:0]} = 22-bit address map (see
// rtl/sdr_ctrl_core.sv header).
class sdr_addr_focus_test extends uvm_test;
    `uvm_component_utils(sdr_addr_focus_test)
    sdr_env env;

    function new(string name, uvm_component parent);
    super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = sdr_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
    // {addr, data} directed pairs:
    //  - addr 0 (bank0,row0,col0): minimum/critical address
    //  - max address (bank3,row4095,col255): maximum/critical address
    //  - same bank(0)/row(0), different column (col0 vs col255)
    //  - same row/col, different bank (bank0 vs bank1)
    //  - different bank, max row within that bank (bank3,row4095,col0)
    //  - same bank(0), different row (row0 vs row1)
    // AP=1 (top bit) on every entry -- these directed accesses are each
    // standalone, single-shot auto-precharge, as always.
    bit [ADDR_W-1:0] addrs[6] = '{
        {1'b1, 22'h000000}, // min
        {1'b1, 22'h3FFFFF}, // max
        {1'b1, 22'h0000FF}, // bank0,row0,col255 (same bank/row as min, far column)
        {1'b1, 22'h100000}, // bank1,row0,col0   (different bank, same row/col as min)
        {1'b1, 22'h3FFF00}, // bank3,row4095,col0 (different bank, max row)
        {1'b1, 22'h000100}  // bank0,row1,col0   (same bank, different row)
    };
    bit [DATA_W-1:0] datas[6] = '{16'h0001, 16'hFFFE, 16'hA5A5, 16'h5A5A, 16'hC3C3, 16'h1234};

    phase.raise_objection(this);

    // Write all, then read back all (exercises the reference-model
    // cross-check across every address in one pass, not just
    // write-immediately-followed-by-its-own-read).
    foreach (addrs[i]) begin
        axi_write_seq wr_seq = axi_write_seq::type_id::create($sformatf("wr_seq%0d", i));
        wr_seq.addr = addrs[i];
        wr_seq.data = datas[i];
        wr_seq.start(env.axi_agt.seqr);
    end

    foreach (addrs[i]) begin
        axi_read_seq rd_seq = axi_read_seq::type_id::create($sformatf("rd_seq%0d", i));
        rd_seq.addr = addrs[i];
        rd_seq.start(env.axi_agt.seqr);
    end

    #100;
    phase.drop_objection(this);
    endtask
endclass


// Low-power test: AXI traffic interleaved with PDE/PDX and SRE/SRX
// requests driven via the APB agent, exercising the scoreboard's
// low-power protocol cross-check alongside the data-integrity checks.
class sdr_low_power_test extends uvm_test;
    `uvm_component_utils(sdr_low_power_test)
    sdr_env env;

    function new(string name, uvm_component parent);
    super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = sdr_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
    axi_wr_rd_seq    axi_s_eq;
    apb_pde_entry_seq pde_in;
    apb_pde_exit_seq  pde_out;
    apb_sre_entry_seq sre_in;
    apb_sre_exit_seq  sre_out;

    phase.raise_objection(this);

    axi_s_eq = axi_wr_rd_seq::type_id::create("axi_s_eq");
    axi_s_eq.num_txns = 8;
    axi_s_eq.start(env.axi_agt.seqr);

    pde_in = apb_pde_entry_seq::type_id::create("pde_in");
    pde_in.start(env.apb_agt.seqr);
    #100;
    pde_out = apb_pde_exit_seq::type_id::create("pde_out");
    pde_out.start(env.apb_agt.seqr);
    #50;

    axi_s_eq = axi_wr_rd_seq::type_id::create("axi_s_eq2");
    axi_s_eq.num_txns = 8;
    axi_s_eq.start(env.axi_agt.seqr);

    sre_in = apb_sre_entry_seq::type_id::create("sre_in");
    sre_in.start(env.apb_agt.seqr);
    #100;
    sre_out = apb_sre_exit_seq::type_id::create("sre_out");
    sre_out.start(env.apb_agt.seqr);
    #50;

    axi_s_eq = axi_wr_rd_seq::type_id::create("axi_s_eq3");
    axi_s_eq.num_txns = 8;
    axi_s_eq.start(env.axi_agt.seqr);

    #200;
    phase.drop_objection(this);
    endtask
endclass