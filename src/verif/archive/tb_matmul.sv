module tb_matmul;
// Testbench parameters
localparam CLK_PERIOD   = 10;   // it works for now
localparam RANGE        = 8;    // range for random values

// Matrix dimensions
//  (M,K) * (K,N) = (M,N)
localparam M = 3; // streaming dimension (larger is better)
localparam K = 3; // systolic height (num rows)
localparam N = 3; // systolic width (num cols)

// Design parameters
localparam WIDTH    = 8;
localparam ROW      = K;    // for now we will make it match to MatMul
localparam COL      = N;

// Memory parameters
localparam I_SIZE = 5;
localparam W_SIZE = 3;
localparam O_SIZE = 5;

// Global signals
bit clk_i;
bit rstn_i;

// clkgen
always #(CLK_PERIOD/2) clk_i=~clk_i;

//------------------//
//-- Input Memory --//
//------------------//
logic                         ib_mem_cenb_o;
logic                         ib_mem_wenb_o;
logic [$clog2(I_SIZE)-1:0]    ib_mem_addr_o;
logic [ROW-1:0][WIDTH-1:0]    ib_mem_data_i;
mem_emulator #(
    .WIDTH(ROW*WIDTH),
    .SIZE(I_SIZE)
) input_mem (
    .clk_i(clk_i),
    // cenb & wenb
    .cenb_i(ib_mem_cenb_o),
    .wenb_i(ib_mem_wenb_o),
    // addr & data
    .addr_i(ib_mem_addr_o),     // addr port
    .d_i(),                     // not connected
    .q_o(ib_mem_data_i)         // data port
);
    
//-------------------//
//-- Weight Memory --//
//-------------------//
logic                         wb_mem_cenb_o;
logic                         wb_mem_wenb_o;
logic [$clog2(W_SIZE)-1:0]    wb_mem_addr_o;
logic [COL-1:0][WIDTH-1:0]    wb_mem_data_i;
mem_emulator #(
    .WIDTH(ROW*WIDTH),
    .SIZE(I_SIZE)
) weight_mem (
    .clk_i(clk_i),
    // cenb & wenb
    .cenb_i(wb_mem_cenb_o),
    .wenb_i(wb_mem_wenb_o),
    // addr & data
    .addr_i(wb_mem_addr_o),     // addr port
    .d_i(),                     // not connected
    .q_o(wb_mem_data_i)         // data port
);
    
//-------------------//
//-- Output Memory --//
//-------------------//
logic                         ob_mem_cenb_o;
logic                         ob_mem_wenb_o;
logic [$clog2(O_SIZE)-1:0]    ob_mem_addr_o;
logic [COL-1:0][WIDTH-1:0]    ob_mem_data_i;
logic [COL-1:0][WIDTH-1:0]    ob_mem_data_o;
mem_emulator #(
    .WIDTH(ROW*WIDTH),
    .SIZE(I_SIZE)
) output_mem (
    .clk_i(clk_i),
    // cenb & wenb
    .cenb_i(ob_mem_cenb_o),
    .wenb_i(ob_mem_wenb_o),
    // addr & data
    .addr_i(ob_mem_addr_o),     // addr port
    .d_i(ob_mem_data_o),        // data write port
    .q_o(ob_mem_data_i)         // not used
);
    
//-----------------//
//-- Psum Memory --//
//-----------------//
logic                         ps_mem_cenb_o;
logic                         ps_mem_wenb_o;
logic [$clog2(W_SIZE)-1:0]    ps_mem_addr_o;
logic [COL-1:0][WIDTH-1:0]    ps_mem_data_o;
logic [COL-1:0][WIDTH-1:0]    ps_mem_data_i;

//-----------------//
//---- MAT MUL ----//
//-----------------//
// DUT signals
logic start_i;
logic done_o;

// DUT Instance
sa_matmul #(
    .WIDTH(WIDTH),
    .ROW(ROW),
    .COL(COL),
    .W_SIZE(W_SIZE),
    .I_SIZE(I_SIZE),
    .O_SIZE(O_SIZE)
) dut0 (.*);

// Test variables
int cycle = 0;
bit count_en;
int returnval;
string testname;
integer num_tests;
string dumpfile = "matmul";
string file_path; // used in iterative tests

initial begin
    returnval = $value$plusargs("testname=%s", testname);
    returnval = $value$plusargs("numtests=%d", num_tests);

    $display("---- Running Test: %0s ----", testname);
    $display("Number of Tests: %0d", num_tests);

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

    // run test case
    run_rand_mult(num_tests);

    // exit sim
    $finish;
end

always @(posedge clk_i) begin
    if (count_en) cycle += 1;
end

// Monitor FSM of design :)
// always @(negedge clk) begin
//     $display("========== CYCLE: %0d ===========", cycle);
//     $display("STATE = %0s", dut0.sys_array_ctrl.curr_state);
//     $display("COUNT_R = %0d", dut0.sys_array_ctrl.count_r);

//     print_PE(0, 0);
//     print_PE(1, 0);
//     print_PE(2, 0);
//     print_PE(3, 0);
//     print_PE(3, 1);
//     print_PE(3, 2);
//     print_PE(3, 3);
// end

// ------------------------------------------------ //
//--------- General Systolic Functions ------------ //
// ------------------------------------------------ //
int i, j, n; // for loops

// Print PE: shows what a specific PE is computing 
function print_PE(int j, int i);
    $display("|----------------------------------|") ;
    $display("| PE[%0d][%0d]", j, i);
    // $display("| mode: %0b", dut0.sys_array.systolic_mode[j][i]);
    // $display("| Input Act: %0d", dut0.sys_array.systolic_inputs[j][i]);
    // $display("| Input Weight: %0d", dut0.sys_array.systolic_input_weights[j][i]);
    // $display("| Input PSUM: %0d", dut0.sys_array.systolic_psums[j][i]);
    $display("| Computing... (%0d) * (%0d) + %0d",
        dut0.sys_array.systolic_inputs[j][i],
        dut0.sys_array.systolic_weights[j][i],
        dut0.sys_array.systolic_psums[j][i],
    );
    $display("| Output Weight/PSUM: %0d", dut0.sys_array.systolic_outputs[j][i]);
    $display("|----------------------------------|");
endfunction

function print_weight_r();
    $display("Systolic Array Weights (R)\n");
    for (j = 0; j < ROW; j += 1) begin
        $write("[");
        for (i = 0; i < COL; i += 1) begin
            $write("%2d", dut0.sys_array.systolic_weights[j][i]);
        end
        $write("]\n");
    end
endfunction

// Load Weight Mem
function load_mem(string mem, string file);
    // $display("Loading %0s Memory", mem);
    case (mem)
        "I":        $readmemh(file, input_mem.data);
        "W":        $readmemh(file, weight_mem.data);
        default:    $display("Invalid memory type: %0s", mem);
    endcase
endfunction

// -------------------------------------------- //
//--------- General Systolic Tasks ------------ //
// -------------------------------------------- //
// reset signals / init signals
task automatic reset_signals();
    // toggle reset
    rstn_i = 1'b0;

    // reset control signals
    start_i = 1'b0;

    // wait two cycles
    repeat(2) @(posedge clk_i);

    // de-assert reset
    rstn_i = 1'b1;
endtask

task automatic start_matmul();
    // assert start
    @(negedge clk_i);
    start_i = 1'b1;
    count_en = 1'b1;

    // de-assert start
    @(negedge clk_i);
    start_i = 1'b0;
endtask

// Sanity test for weight pre-load
//  - Create random weights
//  - Assert if they match :)
// expose all of the weights (this is needed for generate loop XMR)
task automatic sanity_weight_pre_load();
    // reset
    reset_signals();

    // fill-up weight buffer with random values
    // generate_random_weights();

    // pre-load weights
    load_mem("W", "bin/weight_rom.hex");

    // start preload
    start_matmul();

    repeat(ROW + 2) @(negedge clk_i);

    print_weight_r();
endtask

// Functional test (First Smoke test)
//  - generate random data on i_act buffer
//  - generate random data on i_weight buffer
//  - start matmul
//  - write output results when done_o = 1
task automatic smoke_random_mult;
    // reset
    reset_signals();

    // generate random activations and weights
    load_mem("W", "bin/weight_rom.hex");
    load_mem("I", "bin/input_rom.hex");

    // start matmul
    start_matmul();
    
    // results are ready
    @(posedge done_o);

    // verify output (for now we just dump it into output_mem.hex)
    $writememh("bin/output_mem.hex", output_mem.data);
endtask

task automatic run_rand_mult (int num_tests);
    for (int i = 0; i < num_tests; i += 1) begin

        // binary path
        file_path = $sformatf("bin/random/test_%0d/", i);

        $display("Running test: %0d", i);
        $display("Binary path: %0s", file_path);

        // reset module
        reset_signals();

        // generate random activations and weights
        load_mem("W", {file_path, "weight_rom.hex"});
        load_mem("I", {file_path, "input_rom.hex"});

        // start matmul
        start_matmul();
    
        // results are ready
        @(posedge done_o);

        // dump dut output
        $writememh({file_path, "output_mem.hex"}, output_mem.data);
    end
endtask

endmodule
`default_nettype wire