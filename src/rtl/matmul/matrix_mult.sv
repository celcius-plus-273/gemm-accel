module matrix_mult
#(
    // data params
    parameter WIDTH = 8,
    // array params
    parameter ROW = 4,
    parameter COL = 4,
    parameter MAX_ROW = 16,
    parameter MAX_COL = 16,

    // memory params
    parameter I_SIZE,
    parameter W_SIZE,
    parameter O_SIZE
) (
    //--- Mat Mul Port ---//
    // clk, reset, control signals
    input  logic                          clk_i,            // clock signal
    input  logic                          rstn_i,           // active low reset signal
    input  logic                          start_i,          // active high start calculation, must reset back to 0 first to start a new calculation
    input  data_config_struct             data_config_i,    // test controls
    // external mode
    input  logic                          ext_en_i,         // external mode enable, acitve high
    input  external_inputs_struct         ext_inputs_i,     // external inputs
    output logic [COL-1:0][WIDTH-1:0]     ext_result_o,     // external outputs
    output logic                          ext_valid_o,      // external valid
    // output done
    output logic                          done_o,           // data controls

    // input buffer memory
    output  logic                         ib_mem_cenb_o,    // memory enable, active low
    output  logic                         ib_mem_wenb_o,    // write enable, active low
    output  logic [$clog2(I_SIZE)-1:0]    ib_mem_addr_o,    // address
    input   logic [ROW-1:0][WIDTH-1:0]    ib_mem_data_i,    // input data
    // weights buffer memory
    output  logic                         wb_mem_cenb_o,    // memory enable, active low
    output  logic                         wb_mem_wenb_o,    // write enable, active low
    output  logic [$clog2(W_SIZE)-1:0]    wb_mem_addr_o,    // address
    input   logic [COL-1:0][WIDTH-1:0]    wb_mem_data_i,    // input data
    // output buffer memory
    output  logic                         ob_mem_cenb_o,    // memory enable, active low
    output  logic                         ob_mem_wenb_o,    // write enable, active low
    output  logic [$clog2(O_SIZE)-1:0]    ob_mem_addr_o,    // address
    output  logic [COL-1:0][WIDTH-1:0]    ob_mem_data_o,    // output data
    input   logic [COL-1:0][WIDTH-1:0]    ob_mem_data_i,    // input data
    // partial sum buffer memory
    output  logic                         ps_mem_cenb_o,    // memory enable, active low
    output  logic                         ps_mem_wenb_o,    // write enable, active low
    output  logic [$clog2(O_SIZE)-1:0]    ps_mem_addr_o,    // address
    output  logic [COL-1:0][WIDTH-1:0]    ps_mem_data_o,    // output data
    input   logic [COL-1:0][WIDTH-1:0]    ps_mem_data_i     // input data
);

    //---------------------------------//
    //--- Systolic Array Controller ---//
    //---------------------------------//
    logic ctrl_mode, ctrl_load_psum;
    sa_control #(
        .INPUT_WIDTH(ROW*WIDTH),
        .INPUT_HEIGHT(I_SIZE),
        .WEIGHT_WIDTH(COL*WIDTH),
        .WEIGHT_HEIGHT(W_SIZE),
        .OUTPUT_WIDTH(COL*WIDTH),
        .OUTPUT_HEIGHT(O_SIZE),

        .NUM_ROWS(ROW),
        .NUM_COLS(COL),
        .MAX_ROWS(MAX_ROW),
        .MAX_COLS(MAX_COL)
    ) sys_array_ctrl (
        .clk(clk_i),
        .rst_n(rstn_i),

        // control signals
        // .i_en(),    // not connected
        .i_start(start_i),
        .o_done(done_o),
        .data_config_i(data_config_i),

        // systolic array control signals
        .o_mode(ctrl_mode),
        .o_load_psum(ctrl_load_psum),

        // input activation buffer
        .ib_mem_cenb_o(ib_mem_cenb_o),
        .ib_mem_wenb_o(ib_mem_wenb_o),
        .ib_mem_addr_o(ib_mem_addr_o),

        // weight buffer
        .wb_mem_cenb_o(wb_mem_cenb_o),
        .wb_mem_wenb_o(wb_mem_wenb_o),
        .wb_mem_addr_o(wb_mem_addr_o),

        // output activation buffer
        .ob_mem_cenb_o(ob_mem_cenb_o),
        .ob_mem_wenb_o(ob_mem_wenb_o),
        .ob_mem_addr_o(ob_mem_addr_o),

        // psum buffer
        .ps_mem_cenb_o(ps_mem_cenb_o),
        .ps_mem_wenb_o(ps_mem_wenb_o),
        .ps_mem_addr_o(ps_mem_addr_o)
    );

    //----------------------------------//
    //--- Systolic Computation Array ---//
    //----------------------------------//
    // External Control Signals
    logic array_mode, array_load_psum;

    // Control signals come from external port or internal controller
    assign array_mode = ext_en_i ? ~ext_inputs_i.ext_weight_en : ctrl_mode;
    assign array_load_psum = ext_en_i ? ~ext_inputs_i.ext_weight_en : ctrl_load_psum;

    // External Data Signals
    logic [ROW-1:0][WIDTH-1 : 0] i_act;
    logic [COL-1:0][WIDTH-1 : 0] i_weight;
    logic [COL-1:0][WIDTH-1 : 0] i_psum;
    logic [COL-1:0][WIDTH-1 : 0] o_psum;        // psum is always a full result (assume no tiling) -> write to ob_mem

    // mux b/w memory interface or external port interface
    assign i_act    = ext_en_i ? ext_inputs_i.ext_input  : ib_mem_data_i;
    assign i_weight = ext_en_i ? ext_inputs_i.ext_weight : wb_mem_data_i;
    assign i_psum   = ext_en_i ? ext_inputs_i.ext_psum   : ps_mem_data_i;

    assign ob_mem_data_o    = ext_en_i ? '0 : o_psum;
    assign ext_result_o     = ext_en_i ? o_psum : '0;
    assign ps_mem_data_o    = '0; // not used

    sa_compute #(
        .MUL_DATAWIDTH(WIDTH),
        .ADD_DATAWIDTH(WIDTH),
        .NUM_ROWS(ROW),
        .NUM_COLS(COL)
    ) sys_array (
        .clk(clk_i),
        .rst_n(rstn_i),

        // control signals
        .i_mode(array_mode),
        .i_load_psum(array_load_psum),

        // input act port
        .i_act(i_act),
        // weight port
        .i_weight(i_weight),
        // input psum port        
        .i_psum(i_psum),
        // output act port
        .o_psum(o_psum)
    );

    //---------------------------//
    //--- Shift Reg for Valid ---//
    //---------------------------//
    shift_reg #(
        .WIDTH(4)
    ) valid_shift_reg (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .d_i(ext_inputs_i.ext_valid),
        .q_o(ext_valid_o)
    );

endmodule