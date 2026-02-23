module tb_matrix_mult_mem;

   parameter WIDTH         = `WIDTH;
   parameter ROW           = `ROW;
   parameter COL           = `COL;
   parameter W_SIZE        = 512/WIDTH;
   parameter I_SIZE        = 1024/WIDTH;
   parameter O_SIZE        = 1024/WIDTH;
   parameter MEM_R_WIDTH   = WIDTH * ROW;
   parameter MEM_C_WIDTH   = WIDTH * COL;
   parameter DRIVER_WIDTH  = WIDTH * ( ROW + COL );

   parameter CLOCK_PERIOD        = 10;
   parameter real DUTY_CYCLE     = 0.5;
   parameter real OFFSET         = 1;
   parameter CYCLE_LIMIT         = 20_000;

   // VDD, VSS for STDCELLS
   supply1 VDD;
   supply0 VSS;
   
   logic                         clk_i;
   logic                         rstn_async_i;
   logic                         en_i;
   logic                         start_i;

   // test config
   logic [2:0]                   bypass_i;
   logic [1:0]                   mode_i;
   logic                         driver_valid_i;
   logic [DRIVER_WIDTH-1:0]      driver_stop_code_i;
   test_config_struct            test_config_i;

   // data config
   logic [$clog2(MAX_ROW):0]     w_rows_i;
   logic [$clog2(MAX_COL):0]     w_cols_i;
   logic [$clog2(I_SIZE):0]      i_rows_i;
   logic [$clog2(W_SIZE):0]      w_offset_i;
   logic [$clog2(I_SIZE):0]      i_offset_i;
   logic [$clog2(O_SIZE):0]      psum_offset_i;
   logic [$clog2(O_SIZE):0]      o_offset_i;
   logic                         accum_enb_i;
   logic [EXTRA_BITS-1:0]        extra_config_i;
   data_config_struct            data_config_i;

   // External Memory Interface
   logic                         ext_mem_rstn_i;     // memory reset pin
   // input buffer memory
   logic                         ext_ib_mem_sel_i;    // port select
   logic                         ext_ib_mem_cenb_i;   // memory enable, active low
   logic                         ext_ib_mem_wenb_i;   // write enable, active low
   logic [$clog2(I_SIZE)-1:0]    ext_ib_mem_addr_i;   // address
   logic [MEM_R_WIDTH-1:0]       ext_ib_mem_data_i;   // input data
   logic [MEM_R_WIDTH-1:0]       ext_ib_mem_data_o;   // input data
   // weights buffer memory
   logic                         ext_wb_mem_sel_i;    // port select
   logic                         ext_wb_mem_cenb_i;   // memory enable, active low
   logic                         ext_wb_mem_wenb_i;   // write enable, active low
   logic [$clog2(W_SIZE)-1:0]    ext_wb_mem_addr_i;   // address
   logic [MEM_C_WIDTH-1:0]       ext_wb_mem_data_i;   // input data
   logic [MEM_C_WIDTH-1:0]       ext_wb_mem_data_o;   // input data
   // output buffer memory
   logic                         ext_ob_mem_sel_i;    // port select
   logic                         ext_ob_mem_cenb_i;   // memory enable, active low
   logic                         ext_ob_mem_wenb_i;   // write enable, active low
   logic [$clog2(O_SIZE)-1:0]    ext_ob_mem_addr_i;   // address
   logic [MEM_C_WIDTH-1:0]       ext_ob_mem_data_i;   // input data
   logic [MEM_C_WIDTH-1:0]       ext_ob_mem_data_o;   // output data
   // partial sum buffer memory
   logic                         ext_ps_mem_sel_i;    // port select
   logic                         ext_ps_mem_cenb_i;   // memory enable, active low
   logic                         ext_ps_mem_wenb_i;   // write enable, active low
   logic [$clog2(O_SIZE)-1:0]    ext_ps_mem_addr_i;   // address
   logic [MEM_C_WIDTH-1:0]       ext_ps_mem_data_i;   // input data
   logic [MEM_C_WIDTH-1:0]       ext_ps_mem_data_o;   // output data

   // external config
   logic                         ext_en_i;
   logic [ROW-1:0][WIDTH-1:0]    ext_input_i;
   logic [COL-1:0][WIDTH-1:0]    ext_weight_i;
   logic [COL-1:0][WIDTH-1:0]    ext_psum_i;
   logic                         ext_weight_en_i;
   external_inputs_struct        ext_inputs_i;
   logic [DRIVER_WIDTH-1:0]      ext_result_o;
   logic                         ext_valid_o;

   logic                         sample_clk_o;
   logic                         done_o;

   // simplify signal assignment during tasks
   assign test_config_i.bypass                 = bypass_i;
   assign test_config_i.mode                   = mode_i;
   assign test_config_i.driver_valid           = driver_valid_i;
   assign test_config_i.driver_stop_code       = driver_stop_code_i;

   assign data_config_i.w_rows                 = w_rows_i;
   assign data_config_i.w_cols                 = w_cols_i;
   assign data_config_i.i_rows                 = i_rows_i;
   assign data_config_i.w_offset               = w_offset_i;
   assign data_config_i.i_offset               = i_offset_i;
   assign data_config_i.psum_offset            = psum_offset_i;
   assign data_config_i.o_offset_w             = o_offset_i;
   assign data_config_i.accum_en               = accum_enb_i;
   assign data_config_i.extra_config           = extra_config_i;

   assign ext_inputs_i.ext_input               = ext_input_i;
   assign ext_inputs_i.ext_weight              = ext_weight_i;
   assign ext_inputs_i.ext_psum                = ext_psum_i;
   assign ext_inputs_i.ext_weight_en           = ext_weight_en_i;
   
   string         filename;
   integer        f;
   
   initial begin
      #OFFSET;
      forever begin
         clk_i = 1'b0;
         #(CLOCK_PERIOD-(CLOCK_PERIOD*DUTY_CYCLE)) clk_i = 1'b1;
         #(CLOCK_PERIOD*DUTY_CYCLE);
      end
   end

   //-------------------------//
   //---- MAT MUL WRAPPER ----//
   //-------------------------//
   matrix_mult_wrapper #(
      .WIDTH   (WIDTH   ),
      .ROW     (ROW     ),
      .COL     (COL     ),
      .W_SIZE  (W_SIZE  ),
      .I_SIZE  (I_SIZE  ),
      .O_SIZE  (O_SIZE  )
   ) dut0 (.*);

   // Watchdog Timer
   bit [$clog2(CYCLE_LIMIT):0] watchdog;

   always @(posedge clk_i) begin
      if (driver_valid_i) watchdog += 1;

      if (watchdog == CYCLE_LIMIT) begin
         $display("Watchdog triggered!");
         $display("LFSR Out: %0h", dut0.driver_data_w);
         $finish;
      end
   end

   // fake temp mem
   logic [MEM_C_WIDTH-1 : 0] tmp_ob_mem [O_SIZE];

   // Test variables
   int cycle = 0;
   bit count_en;

   int returnval;

   string testname;
   integer num_tests;
   string dumpfile = "wrapper";
   string file_path; // used in iterative tests

   int i_rows;
   int w_rows;
   int w_cols;

   initial begin
      returnval = $value$plusargs("testname=%s", testname);
      returnval = $value$plusargs("numtests=%d", num_tests);

      returnval = $value$plusargs("actrows=%d", i_rows);
      returnval = $value$plusargs("wrows=%d", w_rows);
      returnval = $value$plusargs("wcols=%d", w_cols);

      $display("=================================");
      $display("===== Running Test: %0s", testname);
      $display("===== Number of Tests: %4d", num_tests);
      $display("=================================");

      `ifdef FSDB
         // FSDB Dump (Waveform)
         $fsdbDumpfile({dumpfile,".fsdb"});
         $fsdbDumpvars(0, dut0);
         $fsdbDumpon;
      `endif
      `ifdef VCD
         // VCD dump
         $dumpfile({dumpfile,".vcd"});
         $dumpvars(0, tb_matrix_mult_mem);
         // $dumpvars(0, dut0);
         // $dumpvars(0, tmp_ob_mem);
         // $dumpvars(0, watchdog);
         $dumpon;
      `endif

      `ifdef SDF 
         `ifdef APR
            $sdf_annotate("./results/matrix_mult_wrapper.wc.sdf", dut0, "./sdf.max.cfg");
         `else
            $sdf_annotate("./results/matrix_mult_wrapper.sdf", dut0);
         `endif
      `endif

   end

   initial begin
      $display("WIDTH = %0d", WIDTH);
      $display("MEM_DEPTH = %0d", I_SIZE);

      run_rand_mult(num_tests);

      // exit sim
      $finish;
   end

   always @(posedge clk_i) begin
      if (count_en) cycle += 1;
   end

`include "./testbench/tb_matrix_mult_mem_tasks.sv"
endmodule 
