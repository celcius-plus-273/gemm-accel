// --------------------------------------- //
//--------- General Functions ------------ //
// --------------------------------------- //
int i, j, n; // for loops

int fd;
task load_ib_mem(string file);
    fd = $fopen(file, "r");

    if (fd == 0) begin
        $display("ERROR: Could not open input_act bin file");
        $finish;
    end else begin
        $display("SUCCESS: Programming input act buffer...");
    end

    // assume reset has been de-asserted and clock is enabled
    @(posedge clk_i);
    ext_ib_mem_sel_i    = 1'b1; // select ext port (Port B)
    ext_ib_mem_cenb_i   = 1'b0; // chip select
    ext_ib_mem_wenb_i   = 1'b0; // write enable
    for (int i = 0; i < (i_rows_i + w_rows_i - 1); i += 1) begin
        // load the address
        ext_ib_mem_addr_i = i;
        // load the data
        // $fgets(word, fd);
        // ext_ib_mem_data_i = word.atobin();
        $fscanf(fd, "%b", ext_ib_mem_data_i);
        // $display("ib_mem[%0d] = %16h", i, ext_ib_mem_data_i);
        @(posedge clk_i);
    end

    @(posedge clk_i);
    ext_ib_mem_sel_i    = 1'b0;
    ext_ib_mem_cenb_i   = 1'b1; // chip select
    ext_ib_mem_wenb_i   = 1'b1; // write enable
endtask

task load_wb_mem(string file);
    fd = $fopen(file, "r");

    if (fd == 0) begin
        $display("ERROR: Could not open weight bin file");
        $finish;
    end else begin
        $display("SUCCESS: Programming weight buffer...");
    end

    // assume reset has been de-asserted and clock is enabled
    @(posedge clk_i);
    ext_wb_mem_sel_i    = 1'b1; // select ext port (Port B)
    ext_wb_mem_cenb_i   = 1'b0; // chip select
    ext_wb_mem_wenb_i   = 1'b0; // write enable
    for (int i = 0; i < w_rows_i; i += 1) begin
        // load the address
        ext_wb_mem_addr_i = i;
        // load the data
        // $fgets(word, fd);
        // ext_wb_mem_data_i = word.atobin();
        $fscanf(fd, "%b", ext_wb_mem_data_i);
        // $display("wb_mem[%0d] = %16h", i, ext_wb_mem_data_i);
        @(posedge clk_i);
    end

    @(posedge clk_i);
    ext_wb_mem_sel_i    = 1'b0;
    ext_wb_mem_cenb_i   = 1'b1; // chip select
    ext_wb_mem_wenb_i   = 1'b1; // write enable
endtask

logic [MEM_C_WIDTH-1 : 0] temp_out [O_SIZE];
function reset_temp_out();
    for (int i = 0; i < O_SIZE; i += 1) begin
        temp_out[i] = '0;
    end
endfunction

task read_ob_mem(string file);
    // fd = $fopen(file, "w");

    // if (fd == 0) begin
    //     $display("ERROR: Could not open output bin file");
    //     $finish;
    // end else begin
    //     $display("SUCCESS: Dumping output buffer...");
    // end
    reset_temp_out();

    @(negedge clk_i);
    ext_ob_mem_sel_i    = 1'b1; // select ext port (Port B)
    ext_ob_mem_cenb_i   = 1'b0; // chip select
    ext_ob_mem_wenb_i   = 1'b1; // read
    for (int i = 0; i < (i_rows_i + w_cols_i - 1); i += 1) begin
        // note: DW memory has same cycle read
        // load the address
        ext_ob_mem_addr_i = i;
        // @(negedge clk_i); // a small offset is fine
        #OFFSET;

        // read the data
        temp_out[i] = ext_ob_mem_data_o;
    end

    @(negedge clk_i);
    ext_ob_mem_sel_i    = 1'b0;
    ext_ob_mem_cenb_i   = 1'b1; // chip select
    ext_ob_mem_wenb_i   = 1'b1; // write enable

    $writememb(file, temp_out);
endtask

// ----------------------------------- //
//--------- General Tasks ------------ //
// ----------------------------------- //
task automatic reset_ext_memory_control();
    ext_mem_rstn_i          = 1'b0; // assert reset

    ext_ib_mem_sel_i        = 1'b0;
    ext_ib_mem_cenb_i       = 1'b1;
    ext_ib_mem_wenb_i       = 1'b1;
    ext_ib_mem_addr_i       = '0;
    ext_ib_mem_data_i       = '0;

    ext_wb_mem_sel_i        = 1'b0;
    ext_wb_mem_cenb_i       = 1'b1;
    ext_wb_mem_wenb_i       = 1'b1;
    ext_wb_mem_addr_i       = '0;
    ext_wb_mem_data_i       = '0;

    ext_ob_mem_sel_i        = 1'b0;
    ext_ob_mem_cenb_i       = 1'b1;
    ext_ob_mem_wenb_i       = 1'b1;
    ext_ob_mem_addr_i       = '0;
    ext_ob_mem_data_i       = '0;

    ext_ps_mem_sel_i        = 1'b0;
    ext_ps_mem_cenb_i       = 1'b1;
    ext_ps_mem_wenb_i       = 1'b1;
    ext_ps_mem_addr_i       = '0;
    ext_ps_mem_data_i       = '0;
endtask

// reset common signals
task automatic reset_common_control();
    // data config
    w_rows_i       = '0; // not used
    w_cols_i       = '0; // not used
    i_rows_i       = '0; // streaming dimension
    w_offset_i     = '0; // weight memory offset
    i_offset_i     = '0; // input memory offset
    psum_offset_i  = '0; // psum memory offset (not used)
    o_offset_i     = '0; // output memory offset
    accum_enb_i    = 1'b0;  // not used
    extra_config_i = '0; // not used

    // test config
    bypass_i             = 3'b000;   // no bypass
    mode_i               = 2'b00;    // don't care for for this mode
    driver_valid_i       = 1'b0;     // disbable driver
    driver_stop_code_i   = '0;       // don't care

    // external config
    ext_en_i       = 1'b0;  // enable external mode
    ext_input_i    = '0;    // external input act
    ext_weight_i   = '0;    // external weight
    ext_psum_i     = '0;    // external psum
    ext_weight_en_i = 1'b0; // external weight control signal

    reset_ext_memory_control();
endtask

// reset condition for memory mode signals
task automatic init_memory_control();
    // test config
    bypass_i             = 3'b101;   // bypass driver and monitor
    mode_i               = 2'b00;    // don't care for for this mode
    driver_valid_i       = 1'b0;     // disbable driver
    driver_stop_code_i   = '0;       // don't care
endtask

// reset condition for memory mode signals
task automatic init_external_control();
    // test config
    bypass_i             = 3'b101;   // connect external inputs directly to DUT
    mode_i               = 2'b00;    // don't care
    driver_valid_i       = 1'b0;     // disable driver
    driver_stop_code_i   = '0;       // don't care

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

    // reset common signals
    reset_common_control();

    // wait one cycles
    repeat(1) @(posedge clk_i);
endtask

task automatic exit_reset();
    @(negedge clk_i);
    // de-assert reset
    rstn_async_i    = 1'b1;
    ext_mem_rstn_i  = 1'b1;

    // wait for synchronized reset
    repeat(4) @(posedge clk_i);
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
        file_path = $sformatf("bin/test_%0d/", i);

        $display("--------------------------");
        $display("--- Running test: %4d ---", i);
        $display("--------------------------");
        $display("Binary path: %0s", file_path);

        // reset module
        reset_signals();

        // set data config
        set_data_config();

        // exit reset
        exit_reset();

        // load memories
        load_wb_mem({file_path, "weight_rom.bin"});
        load_ib_mem({file_path, "input_rom.bin"});

        // start matmul
        start_matmul();
    
        // results are ready
        @(posedge done_o);
        read_ob_mem({file_path, "output_mem.bin"});
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
    exit_reset();

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