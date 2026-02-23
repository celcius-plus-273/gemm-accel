module matrix_mult_wrapper #(
    parameter WIDTH         = `WIDTH, 
    parameter ROW           = `ROW, 
    parameter COL           = `COL, 
    parameter MEM_R_WIDTH   = WIDTH * ROW,
    parameter MEM_C_WIDTH   = WIDTH * COL,
    parameter W_SIZE        = 2048/MEM_C_WIDTH, 
    parameter I_SIZE        = 4096/MEM_R_WIDTH, 
    parameter O_SIZE        = 4096/MEM_C_WIDTH, 
    parameter DRIVER_WIDTH  = WIDTH * ( ROW + COL )
) (
  input  logic                        clk_i,            // clock signal
  input  logic                        rstn_async_i,     // active low reset signal
  input  logic                        en_i,             // global clock enable
  input  logic                        start_i,          // active high start calculation, must reset back to 0 first to start a new calculation
  input  test_config_struct           test_config_i,    // test controls
  input  data_config_struct           data_config_i,    // data controls

  // external mode
  input  logic                        ext_en_i,        // external mode enable, acitve high
  input  external_inputs_struct       ext_inputs_i,    // external inputs
  output logic [DRIVER_WIDTH-1:0]     ext_result_o,    // external outputs
  output logic                        ext_valid_o,     // external valid output
  // sample clock
  output logic                        sample_clk_o,    // sample clock used for dll
  // done
  output logic                        done_o,          // active high finish signal, goes to 1 after reset

  // External Memory Interface
  input   logic                       ext_mem_rstn_i,     // memory reset pin
  // input buffer memory
  input   logic                       ext_ib_mem_sel_i,    // port select
  input   logic                       ext_ib_mem_cenb_i,   // memory enable, active low
  input   logic                       ext_ib_mem_wenb_i,   // write enable, active low
  input   logic [$clog2(I_SIZE)-1:0]  ext_ib_mem_addr_i,   // address
  input   logic [MEM_R_WIDTH-1:0]     ext_ib_mem_data_i,   // input data
  output  logic [MEM_R_WIDTH-1:0]     ext_ib_mem_data_o,   // input data
  // weights buffer memory
  input   logic                       ext_wb_mem_sel_i,    // port select
  input   logic                       ext_wb_mem_cenb_i,   // memory enable, active low
  input   logic                       ext_wb_mem_wenb_i,   // write enable, active low
  input   logic [$clog2(W_SIZE)-1:0]  ext_wb_mem_addr_i,   // address
  input   logic [MEM_C_WIDTH-1:0]     ext_wb_mem_data_i,   // input data
  output  logic [MEM_C_WIDTH-1:0]     ext_wb_mem_data_o,   // input data
  // output buffer memory
  input   logic                       ext_ob_mem_sel_i,    // port select
  input   logic                       ext_ob_mem_cenb_i,   // memory enable, active low
  input   logic                       ext_ob_mem_wenb_i,   // write enable, active low
  input   logic [$clog2(O_SIZE)-1:0]  ext_ob_mem_addr_i,   // address
  input   logic [MEM_C_WIDTH-1:0]     ext_ob_mem_data_i,   // input data
  output  logic [MEM_C_WIDTH-1:0]     ext_ob_mem_data_o,   // output data
  // partial sum buffer memory
  input   logic                       ext_ps_mem_sel_i,    // port select
  input   logic                       ext_ps_mem_cenb_i,   // memory enable, active low
  input   logic                       ext_ps_mem_wenb_i,   // write enable, active low
  input   logic [$clog2(O_SIZE)-1:0]  ext_ps_mem_addr_i,   // address
  input   logic [MEM_C_WIDTH-1:0]     ext_ps_mem_data_i,   // input data
  output  logic [MEM_C_WIDTH-1:0]     ext_ps_mem_data_o    // output data
);

  logic                       rstn_i;
  logic                       dut_bypass_w;
  logic                       g_clk;

  logic                       driver_bypass_w;
  logic                       driver_mode_w;
  logic [DRIVER_WIDTH-1:0]    driver_seed_w;
  logic                       driver_valid_o_w;
  logic [DRIVER_WIDTH-1:0]    driver_data_w;
  logic                       driver_done_w;

  logic                       sa_bypass_w;
  logic                       sa_mode_w;
  logic                       sa_dut_valid_w;
  logic [DRIVER_WIDTH-1:0]    sa_dut_data_w;
  logic                       sa_valid_w;
  logic [DRIVER_WIDTH-1:0]    sa_data_w;
  logic [DRIVER_WIDTH-1:0]    sa_seed_w;
  logic                       sa_stop_w;


  logic [ROW-1:0][WIDTH-1:0]  ext_input_w;
  logic                       ext_valid_i_w;
  logic [COL-1:0][WIDTH-1:0]  ext_psum_w;
  logic [COL-1:0][WIDTH-1:0]  ext_result_w;
  logic                       ext_valid_o_w;

  external_inputs_struct      ext_inputs_w;

  // input buffer memory
  logic                         mm_ib_mem_cenb_o;    // memory enable, active low
  logic                         mm_ib_mem_wenb_o;    // write enable, active low
  logic [$clog2(I_SIZE)-1:0]    mm_ib_mem_addr_o;    // address
  logic [ROW-1:0][WIDTH-1:0]    mm_ib_mem_data_o;    // not used
  logic [ROW-1:0][WIDTH-1:0]    mm_ib_mem_data_i;    // input data
  // weights buffer memory
  logic                         mm_wb_mem_cenb_o;    // memory enable, active low
  logic                         mm_wb_mem_wenb_o;    // write enable, active low
  logic [$clog2(W_SIZE)-1:0]    mm_wb_mem_addr_o;    // address
  logic [COL-1:0][WIDTH-1:0]    mm_wb_mem_data_o;    // not used
  logic [COL-1:0][WIDTH-1:0]    mm_wb_mem_data_i;    // input data
  // output buffer memory
  logic                         mm_ob_mem_cenb_o;    // memory enable, active low
  logic                         mm_ob_mem_wenb_o;    // write enable, active low
  logic [$clog2(O_SIZE)-1:0]    mm_ob_mem_addr_o;    // address
  logic [COL-1:0][WIDTH-1:0]    mm_ob_mem_data_o;    // mm to mem data
  logic [COL-1:0][WIDTH-1:0]    mm_ob_mem_data_i;    // not used
  // partial sum buffer memory (... not used rn)
  logic                         mm_ps_mem_cenb_o;    // memory enable, active low
  logic                         mm_ps_mem_wenb_o;    // write enable, active low
  logic [$clog2(O_SIZE)-1:0]    mm_ps_mem_addr_o;    // address
  logic [COL-1:0][WIDTH-1:0]    mm_ps_mem_data_o;    // input data
  logic [COL-1:0][WIDTH-1:0]    mm_ps_mem_data_i;    // output data

  // sample clock and global clock
  assign sample_clk_o     = clk_i;
  assign g_clk            = clk_i & en_i; 

  // test control signals
  assign driver_bypass_w  = test_config_i.bypass[0];
  assign dut_bypass_w     = test_config_i.bypass[1];
  assign sa_bypass_w      = test_config_i.bypass[2];

  assign driver_mode_w    = test_config_i.mode[0];
  assign sa_mode_w        = test_config_i.mode[1];

  // connect seeds
  assign driver_seed_w    = { ext_inputs_i.ext_input, ext_inputs_i.ext_psum };
  assign sa_seed_w        = { ext_inputs_i.ext_psum, ext_inputs_i.ext_input }; // if driver seed and sa seed are the same, weird things happen 

  // bypass external inputs that never go through the driver
  assign ext_inputs_w.ext_weight_en   = ext_inputs_i.ext_weight_en;
  assign ext_inputs_w.ext_input       = ext_input_w;
  assign ext_inputs_w.ext_valid       = ext_valid_i_w;
  assign ext_inputs_w.ext_weight      = ext_inputs_i.ext_weight ;
  assign ext_inputs_w.ext_psum        = ext_psum_w;

  // assign unused memory ports
  assign mm_ib_mem_data_o = '0;
  assign mm_wb_mem_data_o = '0;

  //-------------------------------------------------------------------------//
  //    Reset synchronizer                                                   //
  //-------------------------------------------------------------------------//
	async_nreset_synchronizer async_nreset_synchronizer_0 (
		 .clk_i			    (g_clk			  )
		,.async_nreset_i(rstn_async_i	)
		,.rstn_o		    (rstn_i			  )
	);

  //-------------------------------------------------------------------------//
  //    Scratch Memory                                                       //
  //-------------------------------------------------------------------------//
  // Input Act Buffer
  mem_dw_buffer #(
    .WIDTH(MEM_R_WIDTH),
    .DEPTH(I_SIZE),
    .RST_MODE(1'b0) // async reset
  ) ib_mem_0 (
    .clk_i(clk_i),
    .rstn_i(ext_mem_rstn_i),
    .p_mem_sel_i(ext_ib_mem_sel_i),

    // Matrix Mult Port
    .pA_mem_cenb_i(mm_ib_mem_cenb_o),
    .pA_mem_wenb_i(mm_ib_mem_wenb_o),
    .pA_mem_addr_i(mm_ib_mem_addr_o),
    .pA_mem_data_i(mm_ib_mem_data_o), // not used
    .pA_mem_data_o(mm_ib_mem_data_i),

    // External Port
    .pB_mem_cenb_i(ext_ib_mem_cenb_i),
    .pB_mem_wenb_i(ext_ib_mem_wenb_i),
    .pB_mem_addr_i(ext_ib_mem_addr_i),
    .pB_mem_data_i(ext_ib_mem_data_i),
    .pB_mem_data_o(ext_ib_mem_data_o)
  );

  // Weight Buffer
  mem_dw_buffer #(
    .WIDTH(MEM_C_WIDTH),
    .DEPTH(W_SIZE),
    .RST_MODE(1'b0) // async reset
  ) wb_mem_0 (
    .clk_i(clk_i),
    .rstn_i(ext_mem_rstn_i),
    .p_mem_sel_i(ext_wb_mem_sel_i),

    // Matrix Mult Port
    .pA_mem_cenb_i(mm_wb_mem_cenb_o),
    .pA_mem_wenb_i(mm_wb_mem_wenb_o),
    .pA_mem_addr_i(mm_wb_mem_addr_o),
    .pA_mem_data_i(mm_wb_mem_data_o), // not used
    .pA_mem_data_o(mm_wb_mem_data_i),

    // External Port
    .pB_mem_cenb_i(ext_wb_mem_cenb_i),
    .pB_mem_wenb_i(ext_wb_mem_wenb_i),
    .pB_mem_addr_i(ext_wb_mem_addr_i),
    .pB_mem_data_i(ext_wb_mem_data_i),
    .pB_mem_data_o(ext_wb_mem_data_o)
  );

  // Output Buffer
  mem_dw_buffer #(
    .WIDTH(MEM_C_WIDTH),
    .DEPTH(O_SIZE),
    .RST_MODE(1'b0) // async reset
  ) ob_mem_0 (
    .clk_i(clk_i),
    .rstn_i(ext_mem_rstn_i),
    .p_mem_sel_i(ext_ob_mem_sel_i),

    // Matrix Mult Port
    .pA_mem_cenb_i(mm_ob_mem_cenb_o),
    .pA_mem_wenb_i(mm_ob_mem_wenb_o),
    .pA_mem_addr_i(mm_ob_mem_addr_o),
    .pA_mem_data_i(mm_ob_mem_data_o),
    .pA_mem_data_o(mm_ob_mem_data_i), // not used

    // External Port
    .pB_mem_cenb_i(ext_ob_mem_cenb_i),
    .pB_mem_wenb_i(ext_ob_mem_wenb_i),
    .pB_mem_addr_i(ext_ob_mem_addr_i),
    .pB_mem_data_i(ext_ob_mem_data_i),
    .pB_mem_data_o(ext_ob_mem_data_o)
  );

  // Internal psum buffer
  mem_dw_buffer #(
    .WIDTH(MEM_C_WIDTH),
    .DEPTH(O_SIZE),
    .RST_MODE(1'b0) // async reset
  ) ps_mem_0 (
    .clk_i(clk_i),
    .rstn_i(ext_mem_rstn_i),
    .p_mem_sel_i(ext_ps_mem_sel_i),

    // Matrix Mult Port
    .pA_mem_cenb_i(mm_ps_mem_cenb_o),
    .pA_mem_wenb_i(mm_ps_mem_wenb_o),
    .pA_mem_addr_i(mm_ps_mem_addr_o),
    .pA_mem_data_i(mm_ps_mem_data_o),
    .pA_mem_data_o(mm_ps_mem_data_i),

    // External Port
    .pB_mem_cenb_i(ext_ps_mem_cenb_i),
    .pB_mem_wenb_i(ext_ps_mem_wenb_i),
    .pB_mem_addr_i(ext_ps_mem_addr_i),
    .pB_mem_data_i(ext_ps_mem_data_i),
    .pB_mem_data_o(ext_ps_mem_data_o)
  );

  //-------------------------------------------------------------------------//
  //    Driver                                                               //
  //-------------------------------------------------------------------------//
  pseudo_rand_num_gen #(.DATA_WIDTH (DRIVER_WIDTH)) 
    driver_0 (
      .clk_i        (g_clk                            ),
      .rstn_i       (rstn_i                           ),
      .bypass_i     (driver_mode_w                    ),
      .valid_i      (test_config_i.driver_valid       ),
      .seed_i       (driver_seed_w                    ),
      .stop_code_i  (test_config_i.driver_stop_code   ),
      .valid_o      (driver_valid_o_w                 ),
      .data_o       (driver_data_w                    ),
      .done_o       (driver_done_w                    )
    );

  // driver bypass
  assign { ext_input_w, ext_psum_w } = ( driver_bypass_w)  ? { ext_inputs_i.ext_input, ext_inputs_i.ext_psum } : driver_data_w;
  assign ext_valid_i_w               = ( driver_bypass_w)  ? ext_inputs_i.ext_valid : driver_valid_o_w; 

  //-------------------------------------------------------------------------//
  //    Matrix mult                                                          //
  //-------------------------------------------------------------------------//
  matrix_mult #( .WIDTH(WIDTH) , .ROW(ROW) , .COL(COL) , .W_SIZE(W_SIZE) , .I_SIZE(I_SIZE) , .O_SIZE(O_SIZE) )
    matrix_mult_0 (
      .clk_i                (g_clk                ),
      .rstn_i               (rstn_i               ),
      .start_i              (start_i              ),
      .data_config_i        (data_config_i        ),
      .ext_en_i             (ext_en_i             ),
      .ext_inputs_i         (ext_inputs_w         ),
      .ext_result_o         (ext_result_w         ),
      .ext_valid_o          (ext_valid_o_w        ),
      .done_o               (done_o               ),
      // mem
      .ib_mem_cenb_o        (mm_ib_mem_cenb_o     ),
      .ib_mem_wenb_o        (mm_ib_mem_wenb_o     ),
      .ib_mem_addr_o        (mm_ib_mem_addr_o     ),
      .ib_mem_data_i        (mm_ib_mem_data_i     ),
      .wb_mem_cenb_o        (mm_wb_mem_cenb_o     ),
      .wb_mem_wenb_o        (mm_wb_mem_wenb_o     ),
      .wb_mem_addr_o        (mm_wb_mem_addr_o     ),
      .wb_mem_data_i        (mm_wb_mem_data_i     ),
      .ob_mem_cenb_o        (mm_ob_mem_cenb_o     ),
      .ob_mem_wenb_o        (mm_ob_mem_wenb_o     ),
      .ob_mem_addr_o        (mm_ob_mem_addr_o     ),
      .ob_mem_data_o        (mm_ob_mem_data_o     ),
      .ob_mem_data_i        (mm_ob_mem_data_i     ),
      .ps_mem_cenb_o        (mm_ps_mem_cenb_o     ),
      .ps_mem_wenb_o        (mm_ps_mem_wenb_o     ),
      .ps_mem_addr_o        (mm_ps_mem_addr_o     ),
      .ps_mem_data_o        (mm_ps_mem_data_o     ),
      .ps_mem_data_i        (mm_ps_mem_data_i     )
    );

  // dut bypass
  assign sa_dut_data_w  = ( dut_bypass_w ) ? { ext_input_w, ext_psum_w } : { {(WIDTH*ROW){1'b0}}, ext_result_w } ;
  assign sa_dut_valid_w = ( dut_bypass_w ) ? ext_valid_i_w : ext_valid_o_w ;
  assign sa_stop_w      = driver_done_w;

  //-------------------------------------------------------------------------//
  //    Monitor                                                              //
  //-------------------------------------------------------------------------//
  signature_analyzer #(.DATA_WIDTH (DRIVER_WIDTH) ) 
    monitor_0 (
      .clk_i        (g_clk          ),
      .rstn_i       (rstn_i         ),
      .bypass_i     (sa_mode_w      ),     
      .stop_i       (sa_stop_w      ),     
      .seed_i       (sa_seed_w      ),
      .dut_valid_i  (sa_dut_valid_w ),     
      .dut_data_i   (sa_dut_data_w  ),
      .valid_o      (sa_valid_w     ),
      .data_o       (sa_data_w      )
    );

  // signature analyzer bypass
  assign ext_result_o = (sa_bypass_w) ? sa_dut_data_w : sa_data_w ;
  assign ext_valid_o  = (sa_bypass_w) ? sa_dut_valid_w : sa_valid_w ;

endmodule