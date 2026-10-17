// ----------------------------------------------------------------------- 
// sdr_sdram_model.sv 
// Minimal behavioral SDR SDRAM device model for standalone / UVM back-end use. 
// ----------------------------------------------------------------------- 

module sdr_sdram_model 
#( 
    // Parameter ------------------------------------------- 
    parameter int                       DATA_W = 16, 
    parameter int                       BANK_W = 2,                         // 4 banks 
    parameter int                       ROW_W  = 12,                        // 4096 rows 
    parameter int                       COL_W  = 8,                         // 256 columns 
    parameter int                       T_CL   = 2 
) 
( 
    input  logic                        clk, 
    input  logic                        rst_n, 
    input  logic                        cs_n, 
    input  logic                        ras_n, 
    input  logic                        cas_n, 
    input  logic                        we_n, 
    input  logic                        cke_n, 
    input  logic [BANK_W-1:0]           ba, 
    input  logic [ROW_W-1:0]            addr, 
    input  logic                        dqm, 
    inout  wire  [DATA_W-1:0]           dq 
); 
    typedef enum logic [2:0] { 
        CMD_NOP,  
        CMD_ACT,  
        CMD_RD,  
        CMD_WR,  
        CMD_PRE 
    } cmd_e; 

    function automatic cmd_e decode_cmd(input logic cs_n, ras_n, cas_n, we_n); 
        if (cs_n)                           decode_cmd = CMD_NOP; 
        else if (!ras_n && cas_n && we_n)   decode_cmd = CMD_ACT; 
        else if (ras_n && !cas_n && we_n)   decode_cmd = CMD_RD; 
        else if (ras_n && !cas_n && !we_n)  decode_cmd = CMD_WR; 
        else if (!ras_n && cas_n && !we_n)  decode_cmd = CMD_PRE; 
        else                                decode_cmd = CMD_NOP; 
    endfunction 
    
    // Storage: key = {bank,row,col} 
    logic [DATA_W-1:0] mem [logic [BANK_W+ROW_W+COL_W-1:0]]; 
    // Fixed-size (one entry per bank) — ordinary unpacked array, nonblocking OK 
    logic [ROW_W-1:0] open_row [0:(1<<BANK_W)-1]; 
    logic [DATA_W-1:0] dq_out; 
    logic              dq_drive; 
    int unsigned       rd_pipe_cnt; 
    logic              rd_pipe_active; 
    logic [BANK_W+ROW_W+COL_W-1:0] rd_pipe_key; 

    assign dq = dq_drive ? dq_out : {DATA_W{1'bz}}; 
    
    always_ff @(posedge clk or negedge rst_n)  
    begin 
        if (!rst_n)  
        begin 
            dq_drive       <= 1'b0; 
            rd_pipe_active <= 1'b0; 
            rd_pipe_cnt    <= '0; 
        end  
        else  
        begin 
            automatic cmd_e cmd = decode_cmd(cs_n, ras_n, cas_n, we_n); 
            case (cmd) 
                CMD_ACT : open_row[ba] <= addr; 
                CMD_WR  :  
                begin 
                    logic [BANK_W+ROW_W+COL_W-1:0] key; 
                    key = {ba, open_row[ba], addr[COL_W-1:0]}; 
                    if (!dqm) mem[key] = dq; 
                end 
                CMD_RD  :  
                begin 
                    rd_pipe_active <= 1'b1; 
                    rd_pipe_cnt    <= '0; 
                    rd_pipe_key    <= {ba, open_row[ba], addr[COL_W-1:0]}; 
                end 
                CMD_NOP : ; 
                CMD_PRE : ; // precharge/precharge-all: not modeled (open_row is overwritten on next ACTIVE) 
                default : ; 
            endcase 
            // CAS-latency pipeline for read data drive 
            if (rd_pipe_active)  
            begin 
                if (rd_pipe_cnt == unsigned'(T_CL-1))  
                begin 
                    dq_drive       <= 1'b1; 
                    dq_out         <= mem.exists(rd_pipe_key) ? mem[rd_pipe_key] : '0; 
                    rd_pipe_active <= 1'b0; 
                end  
                else  
                begin 
                    rd_pipe_cnt <= rd_pipe_cnt + 1'b1; 
                end 
            end  
            else  
            begin 
                dq_drive <= 1'b0; 
            end 
        end 
    end 
endmodule 

