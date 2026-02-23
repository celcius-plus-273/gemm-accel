// --------------------------------------- //
//--------- General Functions ------------ //
// --------------------------------------- //
int i, j, n; // for loops

// Load Weight Mem
function load_mem(string mem, string file);
    // $display("Loading %0s Memory", mem);
    case (mem)
        // "I":        $readmemb(file, input_mem.data);
        "W":        $readmemb(file, weight_mem.data);
        default:    $display("Invalid memory type: %0s", mem);
    endcase
endfunction

string word;
int fd;
task load_ib_mem(string file);
    fd = $fopen(file, "r");

    if (fd == 0) begin
        $display("ERROR: Could not open input_act bin file");
        $finish;
    end else begin
        $display("SUCCESS: Reading programming input act memory...");
    end

    // assume reset has been de-asserted and clock is enabled
    @(posedge clk_i);
    ext_program_en = 1'b1;
    ext_ib_mem_cenb = 1'b0; // chip select
    ext_ib_mem_wenb = 1'b0; // write enable
    for (int i = 0; i < (i_rows + w_rows - 1); i += 1) begin
        // load the address
        ext_ib_mem_addr = i;
        // load the data
        $fgets(word, fd);
        ext_ib_mem_data = word.atobin();
        $display("ib_mem[%0d] = %32b", i, ext_ib_mem_data);
        @(posedge clk_i);
    end

    @(posedge clk_i);
    ext_program_en = 1'b0;
    ext_ib_mem_cenb = 1'b1; // chip select
    ext_ib_mem_wenb = 1'b1; // write enable
endtask

// ----------------------------------- //
//--------- General Tasks ------------ //
// ----------------------------------- //
// reset common signals
task automatic reset_common_control();
    // data config
    w_rows_i       = '0; // not used
    w_cols_i       = '0; // not used
    i_rows_i       = '0; // streaming dimension
    w_offset       = '0; // weight memory offset
    i_offset       = '0; // input memory offset
    psum_offset_r  = '0; // psum memory offset (not used)
    o_offset_w     = '0; // output memory offset
    accum_enb_i    = 1'b0;  // not used
    extra_config_i = '0;

    // external config
    ext_en_i       = 1'b0;  // enable external mode
    ext_input_i    = '0;    // external input act
    ext_weight_i   = '0;    // external weight
    ext_psum_i     = '0;    // external psum
    ext_weight_en_i = 1'b0; // external weight control signal
endtask

// reset condition for memory mode signals
task automatic init_memory_control();
    // test config
    bypass_i             = 3'b101;   // bypass driver and monitor
    mode_i               = 2'b00;    // don't care for for this mode
    driver_valid_i       = 1'b0;     // disbable driver
    driver_stop_code_i   = '0;       // don't care

    reset_common_control();
endtask

// reset condition for memory mode signals
task automatic init_external_control();
    // test config
    bypass_i             = 3'b101;   // connect external inputs directly to DUT
    mode_i               = 2'b00;    // don't care
    driver_valid_i       = 1'b0;     // disable driver
    driver_stop_code_i   = '0;       // don't care

    reset_common_control();

    // enable external mode
    ext_en_i = 1'b1;
endtask

// reset condition for memory mode signals
task automatic init_bist_control();
    // test config
    bypass_i             = 3'b000;   // no bypass
    mode_i               = 2'b00;    // LSFR & SA mode
    driver_valid_i       = 1'b0;     // enable driver when ready (need to preload weights first)
    // load LFSR stop code (note this is 64 bits)
    driver_stop_code_i   = 64'hf3f9_bad3_701c_1642; // 10_000 LFSR cycles + dead_dead_abcd_abcd seed

    reset_common_control();

    // enable external mode
    ext_en_i = 1'b1;

    // set driver and sa seed
    ext_input_i = 32'h0101_0404;
    ext_psum_i = 32'h0303_0202;
endtask

// reset signals / init signals
task automatic reset_signals();
    // toggle reset
    rstn_async_i = 1'b0;

    // reset control signals
    start_i = 1'b0;
    en_i = 1'b1;   // enable gclk

    // set signals based on test case (bypass driver and monitor for now)
    case(testname)
      	"external": begin
            init_external_control();
        end
      	"memory": begin
            init_memory_control();
        end
      	"bist": begin
            init_bist_control();
        end
    endcase

    // wait two cycles
    repeat(2) @(posedge clk_i);

    // de-assert reset
    rstn_async_i = 1'b1;

    // wait for synchronized reset
    repeat(10) @(posedge clk_i);
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

task automatic set_data_config();
    // should be parsed alongside mem data
    w_rows_i = w_rows;
    w_cols_i = w_cols;
    i_rows_i = i_rows;
endtask

task automatic run_rand_mult (int num_tests);
    for (int i = 0; i < num_tests; i += 1) begin

        // binary path
        file_path = $sformatf("bin/random/test_%0d/", i);

        $display("--------------------------");
        $display("--- Running test: %4d ---", i);
        $display("--------------------------");
        $display("Binary path: %0s", file_path);

        // reset module
        reset_signals();

        // set data config
        set_data_config();

        // load memories
        load_mem("W", {file_path, "weight_rom.bin"});
        // load_mem("I", {file_path, "input_rom.bin"});
        load_ib_mem({file_path, "input_rom.bin"});

        // start matmul
        start_matmul();
    
        // results are ready
        @(posedge done_o);

        // dump dut output
        $writememb({file_path, "output_mem.bin"}, output_mem.data);
        $display({"Wrote output to: ", file_path, "output_mem.bin"});
    end
endtask

task automatic load_weights_external();
    #OFFSET;
    // load weights
    ext_weight_en_i   = 1'b1;  // load mode

    // weights are loaded reversed
    ext_weight_i      = 32'h0102_0304;
    @(posedge clk_i); // wait one cycle

    #OFFSET;
    ext_weight_i      = 32'h0403_0201;
    @(posedge clk_i); // wait one cycle

    #OFFSET;
    ext_weight_i      = 32'h0104_0203;
    @(posedge clk_i); // wait one cycle

    #OFFSET;
    ext_weight_i      = 32'h0203_0104;
    @(posedge clk_i); // wait one cycle

    #OFFSET;
    ext_weight_en_i   = 1'b0;  // disable load mode
endtask

task automatic run_bist();
    reset_signals();

    // load weights
    load_weights_external();

    // enable LFSR
    driver_valid_i = 1'b1;

    // wait until signature analyzer is done
    // this should be one cycle after the LFSR finds the stop code
    @(posedge ext_valid_o) begin
        $display("Got signature: %8h", ext_result_o);
        if (64'h345c479a38918eb7 == ext_result_o) begin
        $display("----------------------");
        $display("------- PASSED -------");
        $display("----------------------");
        end else begin
        $display("----------------------");
        $display("------- FAILED -------");
        $display("----------------------");
        end

        $finish;
    end
endtask