module tb_matrix_mult_sapr;

   parameter WIDTH         = 8;
   parameter ROW           = 4;
   parameter COL           = 4;
   parameter W_SIZE        = 512;
   parameter I_SIZE        = 512;
   parameter O_SIZE        = 512;
   parameter DRIVER_WIDTH  = WIDTH * ( ROW + COL );

   parameter CLOCK_PERIOD        = 3;
   parameter real DUTY_CYCLE     = 0.5;
   parameter real OFFSET         = 0.5;
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
   logic [$clog2(MAX_ROW)-1:0]   w_rows_i;
   logic [$clog2(MAX_COL)-1:0]   w_cols_i;
   logic [$clog2(I_SIZE)-1:0]    i_rows_i;
   logic [$clog2(W_SIZE)-1:0]    w_offset;
   logic [$clog2(I_SIZE)-1:0]    i_offset;
   logic [$clog2(O_SIZE)-1:0]    psum_offset_r;
   logic [$clog2(O_SIZE)-1:0]    o_offset_w;
   logic                         accum_enb_i;
   logic [EXTRA_BITS-1:0]        extra_config_i;
   data_config_struct            data_config_i;

   // output buffer memory
   logic                         ob_mem_cenb_o;
   logic                         ob_mem_wenb_o;
   logic [$clog2(O_SIZE)-1:0]    ob_mem_addr_o;
   logic [COL-1:0][WIDTH-1:0]    ob_mem_data_i;
   logic [COL-1:0][WIDTH-1:0]    ob_mem_data_o;
   // input buffer memory
   logic                         ib_mem_cenb_o;
   logic                         ib_mem_wenb_o;
   logic [$clog2(I_SIZE)-1:0]    ib_mem_addr_o;    // matmul
   logic [ROW-1:0][WIDTH-1:0]    ib_mem_data_i;    // matmul
   logic [$clog2(I_SIZE)-1:0]    ext_ib_mem_addr;  // external
   logic [ROW-1:0][WIDTH-1:0]    ext_ib_mem_data;  // external
   logic [$clog2(I_SIZE)-1:0]    ib_mem_addr;      // port
   logic                         ext_ib_mem_cenb;
   logic                         ext_ib_mem_wenb;
   logic                         ib_mem_cenb;
   logic                         ib_mem_wenb;
 
   // weights buffer memory
   logic                         wb_mem_cenb_o;
   logic                         wb_mem_wenb_o;
   logic [$clog2(W_SIZE)-1:0]    wb_mem_addr_o;
   logic [COL-1:0][WIDTH-1:0]    wb_mem_data_i;
   // partial sum buffer memory
   logic                         ps_mem_cenb_o;
   logic                         ps_mem_wenb_o;
   logic [$clog2(W_SIZE)-1:0]    ps_mem_addr_o;
   logic [COL-1:0][WIDTH-1:0]    ps_mem_data_i;
   logic [COL-1:0][WIDTH-1:0]    ps_mem_data_o;

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

   logic                         ext_program_en;

   // outputs memory
   logic                         ob_mem_cenb_w;
   logic                         ob_mem_wenb_w;
   logic [$clog2(O_SIZE)-1:0]    ob_mem_addr_w;
   logic [COL*WIDTH-1:0]         ob_mem_d_i_w;
   logic [COL*WIDTH-1:0]         ob_mem_q_o_w;

   assign test_config_i.bypass                 = bypass_i;
   assign test_config_i.mode                   = mode_i;
   assign test_config_i.driver_valid           = driver_valid_i;
   assign test_config_i.driver_stop_code       = driver_stop_code_i;

   assign data_config_i.w_rows                 = w_rows_i;
   assign data_config_i.w_cols                 = w_cols_i;
   assign data_config_i.i_rows                 = i_rows_i;
   assign data_config_i.w_offset               = w_offset;
   assign data_config_i.i_offset               = i_offset;
   assign data_config_i.psum_offset            = psum_offset_r;
   assign data_config_i.o_offset_w             = o_offset_w;
   assign data_config_i.accum_en               = accum_enb_i;
   assign data_config_i.extra_config           = extra_config_i;

   assign ext_inputs_i.ext_input               = ext_input_i;
   assign ext_inputs_i.ext_weight              = ext_weight_i;
   assign ext_inputs_i.ext_psum                = ext_psum_i;
   assign ext_inputs_i.ext_weight_en           = ext_weight_en_i;
   
   assign ob_mem_cenb_w                        = ob_mem_cenb_o;
   assign ob_mem_wenb_w                        = ob_mem_wenb_o;
   assign ob_mem_addr_w                        = ob_mem_addr_o;
   assign ob_mem_d_i_w                         = ob_mem_data_o;
   assign ob_mem_data_i                        = ob_mem_q_o_w;

   assign ib_mem_addr = ext_program_en ? ext_ib_mem_addr : ib_mem_addr_o;
   assign ib_mem_cenb = ext_program_en ? ext_ib_mem_cenb : ib_mem_cenb_o;
   assign ib_mem_wenb = ext_program_en ? ext_ib_mem_wenb : ib_mem_wenb_o;

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

   // Input Memory //
   // mem_emulator #(
   //    .WIDTH(ROW*WIDTH),
   //    .SIZE(I_SIZE)
   // ) input_mem (
   //    .clk_i(clk_i),
   //    // cenb & wenb
   //    .cenb_i(ib_mem_cenb_o),
   //    .wenb_i(ib_mem_wenb_o),
   //    // addr & data
   //    .addr_i(ib_mem_addr_o),     // addr port
   //    .d_i(),                     // not connected
   //    .q_o(ib_mem_data_i)         // data port
   // );
   DW_ram_rw_s_dff #(
      .data_width(ROW*WIDTH),
      .depth(I_SIZE),
      .rst_mode(0)
   ) input_mem (
      .clk(clk_i),
      .rst_n(rstn_async_i),
      .cs_n(ib_mem_cenb),
      .wr_n(ib_mem_wenb),
      .rw_addr(ib_mem_addr),
      .data_in(ext_ib_mem_data),
      .data_out(ib_mem_data_i)
   );

   // weight buffer/memory
   mem_emulator #(
      .WIDTH(ROW*WIDTH),
      .SIZE(I_SIZE)
   ) weight_mem (
      .clk_i   (clk_i),
      .cenb_i  (wb_mem_cenb_o),
      .wenb_i  (wb_mem_wenb_o),
      .addr_i  (wb_mem_addr_o),  // addr port
      .d_i     (),               // not connected
      .q_o     (wb_mem_data_i)   // data port
   );

   // output buffer/memory
   mem_emulator #(.WIDTH(COL*WIDTH), .SIZE(O_SIZE))
      output_mem (
         .clk_i   (clk_i            ),
         .cenb_i  (ob_mem_cenb_w    ),
         .wenb_i  (ob_mem_wenb_w    ),
         .addr_i  (ob_mem_addr_w    ),
         .d_i     (ob_mem_d_i_w     ),
         .q_o     (ob_mem_q_o_w     )
   );

   //-------------------------//
   //---- MAT MUL WRAPPER ----//
   //-------------------------//
   matrix_mult_wrapper_14 #(
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
         $fsdbDumpvars(0, dut0, input_mem, weight_mem, output_mem);
         $fsdbDumpon;
      `endif
      `ifdef VCD
         // VCD dump
         $dumpfile({dumpfile,".vcd"});
         $dumpvars(0, dut0, input_mem, weight_mem, output_mem);
         $dumpvars(0, watchdog);
         $dumpon;
      `endif

      `ifdef SDF 
         `ifdef APR
            $sdf_annotate("./results/matrix_mult_wrapper_14.wc.sdf", dut0, "./sdf.max.cfg");
         `else
            $sdf_annotate("./results/matrix_mult_wrapper_14.sdf", dut0);
         `endif
      `endif

   end

   initial begin
      // reset signals
      reset_signals();

      case(testname)
      	 "external":   run_rand_mult(num_tests);
      	 "memory":     run_rand_mult(num_tests);
      	 "bist":       run_bist();
      	 default:      run_rand_mult(num_tests);
      endcase

      // exit sim
      $finish;
   end

   always @(posedge clk_i) begin
      if (count_en) cycle += 1;
   end

`include "./testbench/tb_matrix_mult_tasks.sv"
endmodule 
