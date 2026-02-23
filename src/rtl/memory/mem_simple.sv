// Single Port Memory Model
module mem_simple
#(
    // size of memory
    parameter NUM_ENTRIES,
    parameter DATA_WIDTH,

    // localparams
    parameter ADDR_WIDTH = $clog2(NUM_ENTRIES)
) (
    // clk, rst
    input logic clk,
    input logic rst_n,

    // chip enable and write enable
    input logic i_cenb,         // chip enable (active low)
    input logic i_wenb,         // write enable (active low)

    // Single Port memory
    input  logic [ADDR_WIDTH-1 : 0]     i_addr,
    input  logic [DATA_WIDTH-1  : 0]    i_data,
    output logic [DATA_WIDTH-1  : 0]    o_data
);
    // localparams and variables
    integer i;

    // simple behavioral memory :)
    logic [DATA_WIDTH-1 : 0] mem_array [NUM_ENTRIES];

    // ff read and write logic
    always @( posedge clk or negedge rst_n ) begin : read_write_ff
        // reset memory
        if (!rst_n) begin
            // reset mem array
            for (i = 0; i < NUM_ENTRIES; i += 1) begin
                mem_array[i] <= '0;
            end
            // reset output ff
            o_data <= '0;
        end
        // normal behavior
        else begin
            // memory can only read OR write (can't do both)
            if (i_wenb) begin
                // wenb = 1: READ
                o_data <= i_cenb ? o_data : mem_array[i_addr];
            end
            else begin
                // wenb = 0: WRITE
                mem_array[i_addr] <= i_cenb ? mem_array[i_addr] : i_data;
            end
        end
    end
    
endmodule