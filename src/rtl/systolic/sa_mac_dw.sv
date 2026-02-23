// DesignWare based MAC + Saturation
module sa_mac_dw
#(
    parameter ADD_DATAWIDTH = 8,
    parameter MUL_DATAWIDTH = 8
)(
    // Inputs
     input logic signed [MUL_DATAWIDTH-1 : 0] i_act
    ,input logic signed [MUL_DATAWIDTH-1 : 0] i_weight
    ,input logic signed [ADD_DATAWIDTH-1 : 0] i_psum

    // Output
    ,output logic signed [ADD_DATAWIDTH-1 : 0] o_psum
);

    localparam width = (2*MUL_DATAWIDTH);
    localparam size = MUL_DATAWIDTH;

    // Please add search_path = search_path + {synopsys_root + "/dw/sim_ver"}
    // to your .synopsys_dc.setup file (for synthesis) and add
    // +incdir+$SYNOPSYS/dw/sim_ver+ to your verilog simulator command line
    // (for simulation).
    `include "DW_dp_sat_function.inc"

    logic signed [(2*MUL_DATAWIDTH)-1 : 0] mac_result;
    logic signed [(2*MUL_DATAWIDTH)-1 : 0] i_psum_ext;

    // DesignWare MAC instance
    DW02_mac #(
        .A_width(MUL_DATAWIDTH), 
        .B_width(MUL_DATAWIDTH)
    ) mac0 (
        .A(i_act),
        .B(i_weight),
        .C(i_psum_ext),
        .TC(1'b1), // two's complement (signed)
        .MAC(mac_result)
    );

    assign i_psum_ext = i_psum; // implicit sign extension
    assign o_psum = DWF_dp_sat_tc(mac_result);
endmodule