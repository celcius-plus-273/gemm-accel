module mem_dw_buffer 
#(
    parameter WIDTH     = 32,
    parameter DEPTH     = 32,
    parameter RST_MODE  = 0
) (
    // control signals
    input logic                         clk_i,
    input logic                         rstn_i,
    input logic                         p_mem_sel_i, // port select signal

    // Port A
    input logic                         pA_mem_cenb_i,
    input logic                         pA_mem_wenb_i,
    input logic [$clog2(DEPTH)-1:0]     pA_mem_addr_i,
    input logic [WIDTH-1 : 0]           pA_mem_data_i,
    output logic [WIDTH-1 : 0]          pA_mem_data_o,

    // Port B
    input logic                         pB_mem_cenb_i,
    input logic                         pB_mem_wenb_i,
    input logic [$clog2(DEPTH)-1:0]     pB_mem_addr_i,
    input logic [WIDTH-1 : 0]           pB_mem_data_i,
    output logic [WIDTH-1 : 0]          pB_mem_data_o
);

    // Maybe check out DW_ram_2r_2w_s_dff for an alternative...
    // - this an isolated r/w dual port memory...
    // - not sure how useful it is...

    // We will use muxes to simulate a dual port
    // This works because we don't need true dual port memory
    logic                       mem_cenb_i;
    logic                       mem_wenb_i;
    logic [$clog2(DEPTH)-1:0]   mem_addr_i;
    logic [WIDTH-1 : 0]         mem_data_i;
    logic [WIDTH-1 : 0]         mem_data_o;

    // input muxes
    assign mem_cenb_i = p_mem_sel_i ? pB_mem_cenb_i : pA_mem_cenb_i;
    assign mem_wenb_i = p_mem_sel_i ? pB_mem_wenb_i : pA_mem_wenb_i;
    assign mem_addr_i = p_mem_sel_i ? pB_mem_addr_i : pA_mem_addr_i;
    assign mem_data_i = p_mem_sel_i ? pB_mem_data_i : pA_mem_data_i;

    // output demux (is this right...?)
    assign pA_mem_data_o = p_mem_sel_i ? '0 : mem_data_o;
    assign pB_mem_data_o = p_mem_sel_i ? mem_data_o : '0;

    DW_ram_rw_s_dff #(
      .data_width(WIDTH),
      .depth(DEPTH),
      .rst_mode(RST_MODE)
    ) mem0 (
      .clk(clk_i),
      .rst_n(rstn_i),
      .cs_n(mem_cenb_i),
      .wr_n(mem_wenb_i),
      .rw_addr(mem_addr_i),
      .data_in(mem_data_i),
      .data_out(mem_data_o)
   ); 

endmodule