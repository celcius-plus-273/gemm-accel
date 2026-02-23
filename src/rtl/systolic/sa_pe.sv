// imports
// none

module sa_pe
#(
    // no default parameter values (MUST BE DEFINED)
    parameter ADD_DATAWIDTH,
    parameter MUL_DATAWIDTH
)(
    // clk, rst_n
    input logic clk,
    input logic rst_n,

    // enable PE
    // input logic i_en, // do we even need this signal

    // mode:
    //  0: weight pre-load
    //  1: compute
    input logic i_mode,

    // inputs: i_act, and i_weight, i_psum
    input logic signed [MUL_DATAWIDTH-1 : 0] i_act,
    input logic signed [MUL_DATAWIDTH-1 : 0] i_weight, // mul vs add datawidth...?
    input logic signed [ADD_DATAWIDTH-1 : 0] i_psum,

    // output
    output logic signed [MUL_DATAWIDTH-1 : 0] o_act, // pass activation to neighbor PE
    output logic signed [ADD_DATAWIDTH-1 : 0] o_weight_psum
);
    // weight register
    //  for now we will only hold a single weight on the PE
    reg signed [MUL_DATAWIDTH-1 : 0] weight_r;

    // mac output psum
    logic signed [ADD_DATAWIDTH-1: 0] mac_psum;

    // PE inputs
    always_ff @(posedge clk or negedge rst_n) begin : pe_in_ff
        if (!rst_n) begin
            weight_r <= '0;
        end
        else begin
            // update weight_r if we're in preload
            weight_r <= ~i_mode ? i_weight : weight_r;
        end
    end

    // PE outputs
    always_ff @(posedge clk or negedge rst_n) begin : pe_out_ff
        if (!rst_n) begin
            o_act <= '0;
            o_weight_psum <= '0;
        end
        else begin
            // if compute fw mac_psum
            // if preload fw i_weight
            o_weight_psum <= i_mode ? mac_psum : i_weight;

            // fw activation if in compute
            o_act <= i_mode ? i_act : o_act;
        end
    end

    // MAC instance
    //    for now only instantiate one MAC/PE
    //    this ratio can ba adjusted based on implementation
    localparam WIDTH = ADD_DATAWIDTH;
    localparam IEEE_COMP = 1; // IEEE 754 - 1985
    // localparam IEEE_COMP = 3; // IEEE 754 - 2008
    localparam ROUNDING = 0;
    `ifdef FP
        // We will break down our FP into three different widths: FP8, FP16, FP32
        generate
            if (WIDTH == 8) begin
                // for FP8 there's two major encodings: E4M3 or E5M2
                // according to FP8 paper E4M3 is used more widely for activations and weights
                sa_mac_dw_fp #(
                    .EXP_WIDTH(4),
                    .SIG_WIDTH(3),
                    .IEEE_COMP(IEEE_COMP),
                    .RND_MODE(ROUNDING)
                ) sa_mac_0 (
                    // mac inputs
                    .i_act(i_act),
                    .i_weight(weight_r),
                    .i_psum(i_psum),
                    // mac outputs
                    .o_psum(mac_psum)
                );
            end
            else if (WIDTH == 16) begin
                // FP16: 1 sign bit + 5 exponent bits + 10 mantissa bits
                sa_mac_dw_fp #(
                    .EXP_WIDTH(5),
                    .SIG_WIDTH(10),
                    .IEEE_COMP(IEEE_COMP),
                    .RND_MODE(ROUNDING)
                ) sa_mac_0 (
                    // mac inputs
                    .i_act(i_act),
                    .i_weight(weight_r),
                    .i_psum(i_psum),
                    // mac outputs
                    .o_psum(mac_psum)
                );
            end
            else if (WIDTH == 32) begin
                // FP32 (float): 1 sign bit + 8 exponent bits + 23 mantissa bits
                sa_mac_dw_fp #(
                    .EXP_WIDTH(8),
                    .SIG_WIDTH(23),
                    .IEEE_COMP(IEEE_COMP),
                    .RND_MODE(ROUNDING)
                ) sa_mac_0 (
                    // mac inputs
                    .i_act(i_act),
                    .i_weight(weight_r),
                    .i_psum(i_psum),
                    // mac outputs
                    .o_psum(mac_psum)
                );
            end
            else $error("Invalid WIDTH for FP MAC. Only 8-bit, 16-bit, and 32-bit are supported");
        endgenerate
    `else
        // Signed INT mac can take any width as input
        sa_mac_dw #(
            .ADD_DATAWIDTH(WIDTH),
            .MUL_DATAWIDTH(WIDTH)
        ) sa_mac_0 (
            // mac inputs
            .i_act(i_act),
            .i_weight(weight_r),
            .i_psum(i_psum),

            // mac outputs
            .o_psum(mac_psum)
        );
    `endif
endmodule
