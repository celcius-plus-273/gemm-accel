module tb_comp_array_only;
// Testbench parameters
localparam CLK_PERIOD   = 10;   // it works for now
localparam RANGE        = 8;    // range for random values

// Matrix dimensions
//  (M,K) * (K,N) = (M,N)
localparam M            = 4; // streaming dimension (larger is better)
localparam K            = 4; // systolic height (num rows)
localparam N            = 4; // systolic width (num cols)
// Buffer dimensions (for single MatMul)
localparam I_ACT_WIDTH      = M + K - 1;
localparam I_ACT_HEIGHT     = K;
localparam I_WEIGHT_WIDTH   = N;
localparam I_WEIGHT_HEIGHT  = K;
localparam O_ACT_WIDTH      = N;
localparam O_ACT_HEIGHT     = M + N -1;

// Design parameters
localparam ADD_DATAWIDTH    = 8;
localparam MUL_DATAWIDTH    = 8;
localparam NUM_ROWS         = K;    // for now we will make it match to MatMul
localparam NUM_COLS         = N;

// Global signals
bit clk;
bit rst_n;

// clkgen
always #(CLK_PERIOD/2) clk=~clk;

// DUT signals
logic i_mode;         // weight pre-load | compute
logic i_load_psum;    // psum or weight
logic [MUL_DATAWIDTH-1:0] i_act     [NUM_ROWS]; 
logic [MUL_DATAWIDTH-1:0] i_weight  [NUM_COLS]; 
logic [ADD_DATAWIDTH-1:0] i_psum    [NUM_COLS]; 
logic [ADD_DATAWIDTH-1:0] o_psum    [NUM_COLS]; 

// DUT Instance
sa_compute #(
    .ADD_DATAWIDTH(ADD_DATAWIDTH),
    .MUL_DATAWIDTH(MUL_DATAWIDTH),
    .NUM_ROWS(NUM_ROWS),
    .NUM_COLS(NUM_COLS)
) dut0 (.*);

// Test variables
// weight buffer (NUM_ROWS)x(NUM_COLS)
logic [MUL_DATAWIDTH-1:0] weight_buffer     [I_WEIGHT_HEIGHT][I_WEIGHT_WIDTH];  // TODO: double check transpose!
logic [MUL_DATAWIDTH-1:0] input_buffer      [I_ACT_WIDTH]   [I_ACT_HEIGHT];     // NOTE THAT WIDTH AND HEIGHT ARE FLIPPED :)
logic [ADD_DATAWIDTH-1:0] output_buffer     [O_ACT_HEIGHT]   [O_ACT_WIDTH]; 

initial begin
    string dumpfile = "comp_array_only";
    `ifdef VCS
        // FSDB Dump (Waveform)
        $fsdbDumpfile({dumpfile,".fsdb"});
        $fsdbDumpvars(0, dut0);
        $fsdbDumpon;
    `else
        $dumpfile("%0s.fsdb", dumpfile);
        $dumpvars(0, dut0);
    `endif
end

initial begin
    // reset signals
    reset_signals();

    // run sanity tests
    sanity_weight_pre_load();
    // sanity_act_forward();

    // run smoke test
    // smoke_random_mult();

    // exit sim
    $finish;
end

// Monitor for left-most PE column
// always @(negedge clk) begin
//     for (int j = 0; j < NUM_ROWS; j += 1) begin
//         $display("PE[%0d][0]", j);
//         $display("  Computing... (%0d) * (%0d) + %0d",
//             dut0.systolic_inputs[j][0],
//             dut0.systolic_weights[j][0],
//             dut0.systolic_psums[j][0],
//         );
//         $display("  Output PSUM: %0d", dut0.systolic_outputs[j][0]);
//     end
// end

// ------------------------------------------------ //
//--------- General Systolic Functions ------------ //
// ------------------------------------------------ //
int i, j, n; // for loops
// visualize weight buffers
function print_weights(logic [MUL_DATAWIDTH-1:0] weights [NUM_ROWS][NUM_COLS]);
    for (j = 0; j < NUM_ROWS; j += 1) begin
        $write("[");
        for (i = 0; i < NUM_COLS; i += 1) begin
            $write("%4d", weights[j][i]);
        end
        $write("]\n");
    end
endfunction
function print_inputs(logic [MUL_DATAWIDTH-1:0] inputs [I_ACT_WIDTH][I_ACT_HEIGHT]);
    $display("Input Buffer:");
    for (j = 0; j < I_ACT_HEIGHT; j += 1) begin
        $write("[");
        for (i = 0; i < I_ACT_WIDTH; i += 1) begin
            $write("%4d", inputs[i][j]);
        end
        $write("]\n");
    end
endfunction
function print_outputs(logic [MUL_DATAWIDTH-1:0] outputs [O_ACT_HEIGHT][O_ACT_WIDTH]);
    $display("Output Buffer:");
    for (j = 0; j < O_ACT_HEIGHT; j += 1) begin
        $write("[");
        for (i = 0; i < O_ACT_WIDTH; i += 1) begin
            $write("%4d", outputs[j][i]);
        end
        $write("]\n");
    end
endfunction
function print_act_vector(logic [MUL_DATAWIDTH-1:0] act [NUM_ROWS]);
    $write("[");
    for (j = 0; j < NUM_ROWS; j += 1) begin
        $write("%4d", act[j]);
    end
    $write("]");
endfunction
function print_o_psum_vector(logic [ADD_DATAWIDTH-1:0] o_psum [NUM_COLS]);
    $write("o_psum: [");
    for (i = 0; i < NUM_COLS; i += 1) begin
        $write("%4d", o_psum[i]);
    end
    $write("]\n");
endfunction
function generate_random_weights();
    // generate random weight values
    for (j = 0; j < I_WEIGHT_HEIGHT; j += 1) begin
        for (i = 0; i < I_ACT_WIDTH; i += 1) begin
            weight_buffer[j][i] = ({$random} % RANGE) + 1; // random value from [1, 32]
        end
    end
endfunction
function generate_random_inputs();
    // reset to zeroes
    for (j = 0; j < I_ACT_HEIGHT; j += 1) begin
        for (i = 0; i < I_ACT_WIDTH; i += 1) begin
            input_buffer[i][j] = '0; // random value from [1, 32]
        end
    end
    // generate random i_act values
    for (j = 0; j < K; j += 1) begin
        for (i = j; i < j + M; i += 1) begin
            input_buffer[i][j] = ({$random} % RANGE) + 1; // random value from [1, 32]
        end
    end
endfunction
function print_PE(int i, int j);
    $display("|----------------------------------|") ;
    $display("| PE[%0d][%0d]", j, i);
    $display("| mode: %0s", dut0.systolic_mode[j][i]);
    $display("| Input Act: %0d", dut0.systolic_inputs[j][i]);
    $display("| Input Weight: %0d", dut0.systolic_input_weights[j][i]);
    $display("| Input PSUM: %0d", dut0.systolic_psums[j][i]);
    $display("| Computing... (%0d) * (%0d) + %0d",
        dut0.systolic_inputs[j][i],
        dut0.systolic_weights[j][i],
        dut0.systolic_psums[j][i],
    );
    $display("| Output Weight/PSUM: %0d", dut0.systolic_outputs[j][i]);
    $display("|----------------------------------|");
endfunction

// -------------------------------------------- //
//--------- General Systolic Tasks ------------ //
// -------------------------------------------- //
// reset signals / init signals
task automatic reset_signals();
    // toggle reset
    rst_n = 1'b0;

    // reset control signals
    i_mode = 1'b0;      // default is weight pre-load
    i_load_psum = 1'b0; // default is weight on north port

    // clear row-wise IO
    for (i = 0; i < NUM_ROWS; i += 1) begin
        i_act[i] = '0;
    end

    // clear column-wise IO
    for (i = 0; i < NUM_COLS; i += 1) begin
        i_weight[i] = '0;
        i_psum[i] = '0;
    end

    // wait two cycles
    repeat(2) @(posedge clk);

    // de-assert reset
    rst_n = 1'b1;
endtask

// Shifts the weights from the loaded weight buffer into the array
int cycle;
task automatic load_weights();
    // precise cycle count for pre-load
    cycle = 0;
    // sync with posedge
    @(posedge clk);
    // set array to pre-load
    i_mode = 1'b0;
    // connect north port to i_weight
    i_load_psum = 1'b0;

    // now load the values from the random weight buffer
    for (j = 0; j < NUM_ROWS; j += 1) begin
        // load from last row to first
        i_weight = weight_buffer[NUM_ROWS - 1 - j];

        // print PE debug
        #1;
        $display("------------------------");
        $display("------- Cycle: %0d -------", cycle);
        $display("------------------------");
        print_PE(0, 0);
        print_PE(0, 1);
        print_PE(0, 2);
        print_PE(0, 3);
        @(negedge clk);
        $display("------------------------");
        $display("------- Cycle: %0d -------", cycle);
        $display("------------------------");
        print_PE(0, 0);
        print_PE(0, 1);
        print_PE(0, 2);
        print_PE(0, 3);

        // toggle clock
        // - weights should move downwards
        @(posedge clk);

        // update cycle count
        cycle += 1;
    end
endtask

int count, out_count;
task automatic run_compute();
    // sync with posedge
    // @(negedge clk);
    // set array to compute
    i_mode = 1'b1;

    //clear i_weight port
    for (i = 0; i < NUM_COLS; i += 1) begin
        i_weight[i] = '0;
    end

    // reset count
    count = 0;
    out_count = 0;

    for (i = 0; i < I_ACT_WIDTH + O_ACT_WIDTH - 1; i += 1) begin
        // pass in i_act
        i_act = input_buffer[i];

        @(posedge clk);
        count += 1;

        // need to sample at negedge bc of non-blocking assignment
        if (count >= NUM_COLS) begin
            @(negedge clk);
            // write result onto output buffer
            output_buffer[out_count] = dut0.o_psum;

            // increment output counter
            out_count += 1;
        end
    end
endtask

// Sanity test for weight pre-load
//  - Create random weights
//  - Shift them into array in pre-load mode
//  - Assert if they match :)
// expose all of the weights (this is needed for generate loop XMR)
task automatic sanity_weight_pre_load();
    // reset
    reset_signals();

    // fill-up weight buffer with random values
    generate_random_weights();

    // pre-load weights
    load_weights();

    // weight_r is non-blocking, if we try to sample it at the end of (posedge clk)
    // the LHS hasn't updated yet. Instead, sample at negedge or some fixed delay (e.g. #1)
    @(negedge clk);

    // now check that each PE has the right weight
    for (j = 0; j < NUM_ROWS; j += 1) begin
        for (i = 0; i < NUM_COLS; i += 1) begin
            assert(weight_buffer[j][i] == dut0.systolic_weights[j][i]);
        end
    end

    $display("Buffer Weights:");
    print_weights(weight_buffer);

    $display("Systolic Weights:");
    print_weights(dut0.systolic_weights);
endtask

// Sanity test for i_act forwarding
//  - generate random i_act
//  - set array to compute mode (DEBUG = 1)
//  - push i_act
//  - check o_act
task automatic sanity_act_forward();
    // reset
    reset_signals();

    // generate random activations
    generate_random_inputs();

    // sync with posedge
    @(posedge clk);
    // set array to compute
    i_mode = 1'b1;

    // reset count
    count = 0;

    for (i = 0; i < I_ACT_WIDTH + O_ACT_WIDTH - 1; i += 1) begin
        // pass in i_act
        i_act = input_buffer[i];

        @(posedge clk);
        count += 1;

        // need to sample at negedge bc of non-blocking assignment
        if (count >= NUM_COLS) begin
            @(negedge clk);
            // assert o_act == i_act
            assert(dut0.o_act == input_buffer[out_count])

            // debug print
            print_act_vector(dut0.o_act);
            $write(" =? ");
            print_act_vector(input_buffer[out_count]);
            $write("\n");

            // increment output counter
            out_count += 1;
        end
    end
endtask

// Functional test (First Smoke test)
//  - generate random data on i_act buffer
//  - generate random data on i_weight buffer
//  - pre-load weight buffer (i_mode = 0)
//  - stream activations (i_mode = 1)
//  - collect outputs
//      - wait NUM_COLS cycles
//      - write result to output buffer until 
task automatic smoke_random_mult;
    // reset
    reset_signals();

    // generate random activations and weights
    generate_random_inputs();
    generate_random_weights();

    // pre-load weights
    load_weights();

    // stream i_act and capture o_act
    run_compute();

    // verify output (for now we just print)
    print_inputs(input_buffer);
    $display("Systolic Weights:");
    print_weights(dut0.systolic_weights);
    print_outputs(output_buffer);
endtask

endmodule
`default_nettype wire