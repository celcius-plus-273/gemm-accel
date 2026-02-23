module shift_reg
#(
    parameter WIDTH = 4
) (
    // clk, rst
    input   clk_i,
    input   rstn_i,

    // io
    input   logic  d_i,
    output  logic  q_o
);

    // shift reg
    logic [WIDTH-1 : 0] shift_r;

    always_ff @(posedge clk_i or negedge rstn_i) begin : shift_reg_ff
        if (!rstn_i) begin
            shift_r <= '0;
        end
        else begin
            // shift left
            // LSB: new data
            // MSB: old data
            shift_r <= {shift_r[WIDTH-2 : 0], d_i};
        end
    end

    // last reg is output
    assign q_o = shift_r[WIDTH-1];
    
endmodule