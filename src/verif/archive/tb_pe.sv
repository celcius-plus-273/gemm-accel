module tb_matmul;
// Testbench parameters
localparam CLK_PERIOD   = 10;   // it works for now

// Design parameters
localparam WIDTH        = 8;

// Global signals
bit clk;
bit rst_n;

// clkgen
always #(CLK_PERIOD/2) clk=~clk;

// DUT signals
logic i_mode; 
logic signed [WIDTH-1 : 0] i_act; 
logic signed [WIDTH-1 : 0] i_weight;
logic signed [WIDTH-1 : 0] i_psum;
logic signed [WIDTH-1 : 0] o_act;
logic signed [WIDTH-1 : 0] o_weight_psum;

// DUT Instance
sa_pe #(
    .ADD_DATAWIDTH(WIDTH),
    .MUL_DATAWIDTH(WIDTH)
) dut0 (.*);

// Test variables
int cycle = 0;
bit count_en;

initial begin
    string dumpfile = "matmul";
    `ifdef VCS
        // FSDB Dump (Waveform)
        $fsdbDumpfile({dumpfile,".fsdb"});
        $fsdbDumpvars(0, dut0);
        $fsdbDumpon;
    `else
        $dumpfile({dumpfile,".fsdb"});
        $dumpvars(0, dut0);
    `endif
end

initial begin
    // reset signals
    reset_signals();

    // run tests
    run_compute(7, -1, 127);

    // exit sim
    $finish;
end

always @(posedge clk) begin
    if (count_en) cycle += 1;
end


// ----------------------------------- //
//--------- General Tasks ------------ //
// ----------------------------------- //
// reset signals / init signals
task automatic reset_signals();
    // toggle reset
    rst_n = 1'b0;

    // reset control signals
    i_mode = 1'b0;
    i_act = '0;
    i_weight = '0;
    i_psum = '0;

    // wait two cycles
    repeat(2) @(posedge clk);

    // de-assert reset
    rst_n = 1'b1;
endtask

task automatic run_compute(
    input integer act,
    input integer weight,
    input integer psum
);
    $display("Computing: (%0d * %0d) + %0d", act, weight, psum);

    // load the weight
    @(negedge clk);
    count_en = 1'b1; // cycle counter
    i_weight = weight;
    i_mode = 1'b0;  // pre-load mode

    // load act and psum
    @(negedge clk);
    i_act = act;
    i_psum = psum;
    i_mode = 1'b1; // compute act mode

    // read output
    @(negedge clk);
    $display("ADD Min: %0d | ADD Max: %0d", dut0.sa_mac_0.MIN_ADD, dut0.sa_mac_0.MAX_ADD);
    $display("Mult Result: %0d", dut0.sa_mac_0.mult_result_sat);
    $display("ADD Result: %0d", dut0.sa_mac_0.o_psum);
    $display("Result: %0d", dut0.o_weight_psum);
endtask

endmodule
`default_nettype wire