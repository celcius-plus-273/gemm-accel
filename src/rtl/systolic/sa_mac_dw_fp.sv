// DesignWare based MAC + Saturation
module sa_mac_dw_fp
#(
    parameter EXP_WIDTH = 8,
    parameter SIG_WIDTH = 23,
    parameter IEEE_COMP = 1,
    parameter RND_MODE  = 0
)(
    // Inputs
     input logic signed [EXP_WIDTH+SIG_WIDTH : 0] i_act
    ,input logic signed [EXP_WIDTH+SIG_WIDTH : 0] i_weight
    ,input logic signed [EXP_WIDTH+SIG_WIDTH : 0] i_psum

    // Output
    ,output logic signed [EXP_WIDTH+SIG_WIDTH : 0] o_psum
);
    // check DWBB FP Overview Doc for rounding modes
    logic [2:0] rnd;
    assign rnd = RND_MODE;

    // status
    logic [7:0] mac_status;

    // DesignWare FP MAC instance
    DW_fp_mac #(
        .sig_width(SIG_WIDTH), 
        .exp_width(EXP_WIDTH),
        .ieee_compliance(IEEE_COMP)
    ) mac0 (
        .a(i_act),
        .b(i_weight),
        .c(i_psum),
        .rnd(rnd),
        .z(o_psum),
        .status(mac_status)
    );
endmodule