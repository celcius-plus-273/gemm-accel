
module sa_control
#(
    // memory parameters
    parameter INPUT_WIDTH,      // input mem width
    parameter INPUT_HEIGHT,     // input mem height
    parameter WEIGHT_WIDTH,     // weight mem width
    parameter WEIGHT_HEIGHT,    // weight mem height
    parameter OUTPUT_WIDTH,     // output mem width
    parameter OUTPUT_HEIGHT,    // output mem height
    parameter READ_LATENCY = 0,

    // array params
    parameter NUM_ROWS,
    parameter NUM_COLS,
    parameter MAX_ROWS,
    parameter MAX_COLS
) (
    // clk, rst
    input logic clk,
    input logic rst_n,

    //-- Memory Interfaces --//
    // for now we will use fake memories that rely on a start signal :)
    // i_act memory interface
    output logic                                ib_mem_cenb_o,
    output logic                                ib_mem_wenb_o,
    output logic [$clog2(INPUT_HEIGHT)-1 : 0]   ib_mem_addr_o,

    // i_weight memory interface
    output logic                                wb_mem_cenb_o,
    output logic                                wb_mem_wenb_o,
    output logic [$clog2(WEIGHT_HEIGHT)-1 : 0]  wb_mem_addr_o,

    // o_act memory interface
    output logic                                ob_mem_cenb_o,
    output logic                                ob_mem_wenb_o,
    output logic [$clog2(OUTPUT_HEIGHT)-1 : 0]  ob_mem_addr_o,

    // o_psum memory interface (won't use for now)
    output logic                                ps_mem_cenb_o,
    output logic                                ps_mem_wenb_o,
    output logic [$clog2(OUTPUT_HEIGHT)-1 : 0]  ps_mem_addr_o,

    //-- control signals --//
    // input logic i_en,        // clock gating?
    input logic i_start,        // mult start
    output logic o_done,        // mult done
    
    //-- data config --//
    input data_config_struct data_config_i, // static instruction

    //-- systolic signals --//
    output logic o_mode,
    output logic o_load_psum
);
    //-- localparams  & imports --//
    import sa_pkg::*;
    localparam MAX_COUNT        = (NUM_COLS + INPUT_HEIGHT - 1) + NUM_COLS + READ_LATENCY;
    localparam COUNT_WIDTH      = $clog2(MAX_COUNT);

    localparam MAX_LOAD_COUNT   = 1 + MAX_ROWS + READ_LATENCY; // num rows + 1 + read latency
    localparam LOAD_COUNT_WIDTH = $clog2(MAX_LOAD_COUNT);

    // only remaining fixed local param
    //  -> because we are loading the subarray from index [0][0] (top-left) corner
    //     so it will still take NUM_ROWS cycles for the data to propagate down the physical array
    localparam OUTPUT_START_WRITE = NUM_COLS + READ_LATENCY;
    
    //-- data config decode --//
    logic [$clog2(INPUT_HEIGHT) : 0]    num_act_rows;
    logic [$clog2(MAX_ROWS)     : 0]    num_w_rows;
    logic [$clog2(MAX_COLS)     : 0]    num_w_cols;

    logic [LOAD_COUNT_WIDTH     : 0]    preload_total_cycles;
    logic [COUNT_WIDTH          : 0]    stream_iact_cycles;
    logic [COUNT_WIDTH          : 0]    stream_total_cycles;

    assign num_act_rows         = data_config_i.i_rows;
    assign num_w_rows           = data_config_i.w_rows;
    assign num_w_cols           = data_config_i.w_cols;

    assign preload_total_cycles = 1 + num_w_rows + READ_LATENCY;
    assign stream_iact_cycles   = num_w_cols + num_act_rows - 1;
    assign stream_total_cycles  = stream_iact_cycles + NUM_COLS + READ_LATENCY; // keep NUM_COLS because of physical array dimensions

    //-- state variable --//
    sa_state_e curr_state, next_state;

    //-- internal counters --//
    logic [LOAD_COUNT_WIDTH : 0] load_count_r, next_load_count;
    logic [COUNT_WIDTH      : 0] stream_count_r, next_stream_count;

    //-- start edge detection --//
    logic start_r, next_start, start;

    //-- state update ff --//
    always_ff @( posedge clk or negedge rst_n ) begin : state_update_ff
        if (!rst_n) begin
            // reset values
            curr_state      <= IDLE;     // IDLE is reset
            stream_count_r  <= '0;       // reset count
            load_count_r    <= '0;       // reset count
            start_r         <= 1'b0;     // reset start edge detector
        end 
        else begin
            // normal operation
            curr_state      <= next_state;
            stream_count_r  <= next_stream_count;
            load_count_r    <= next_load_count;
            start_r         <= next_start;
        end
    end

    //-- next state comb --//
    always_comb begin : next_state_comb
        // start edge detector
        start = ~start_r & i_start;
        next_start = i_start;

        // default assignments
        next_state          = STATEX;
        next_load_count     = 'x;
        next_stream_count   = 'x;

        case (curr_state)
            IDLE: begin
                next_state          = start ? PRELOAD : IDLE;
                next_load_count     = '0;
                next_stream_count   = '0;
            end
            PRELOAD: begin
                // preload cycles
                next_state          = (load_count_r == (preload_total_cycles - 1'b1)) ? STREAM : PRELOAD;
                // increment count (reset when we are done :))
                next_load_count     = (load_count_r == (preload_total_cycles - 1'b1)) ? '0 : load_count_r + 1'b1;
                next_stream_count   = '0;
            end
            STREAM: begin
                // keep streaming for (stream cycles + cols + 1) cycles
                next_state          = (stream_count_r == stream_total_cycles - 1'b1) ? IDLE : STREAM;
                // increment count
                next_stream_count   = (stream_count_r == stream_total_cycles - 1'b1) ? '0 : stream_count_r + 1'b1;
                next_load_count     = '0;
            end
            default: begin
                next_state = STATEX;
                next_load_count     = 'x;
                next_stream_count   = 'x;
            end
        endcase
    end

    //-- output ff --//
    always_ff @( posedge clk or negedge rst_n ) begin : output_ff
        if (!rst_n) begin
            // reset memory addr pointers
            ib_mem_cenb_o    <= 1'b1;
            ib_mem_wenb_o    <= 1'b1;
            ib_mem_addr_o    <= '0;

            wb_mem_cenb_o   <= 1'b1;
            wb_mem_wenb_o   <= 1'b1;
            wb_mem_addr_o   <= '0;

            ob_mem_cenb_o   <= 1'b1;
            ob_mem_wenb_o   <= 1'b1;
            ob_mem_addr_o   <= '0;

            ps_mem_cenb_o  <= 1'b1;
            ps_mem_wenb_o  <= 1'b1;
            ps_mem_addr_o  <= '0;

            // reset o_done
            o_done <= 1'b0;

            // systolic outputs
            o_mode      <= 1'b0;
            o_load_psum <= 1'b0;
        end
        else begin
            // default outputs
            ib_mem_cenb_o    <= 1'b1;
            ib_mem_wenb_o    <= 1'b1;
            ib_mem_addr_o    <= data_config_i.i_offset;
            wb_mem_cenb_o   <= 1'b1;
            wb_mem_wenb_o   <= 1'b1;
            wb_mem_addr_o   <= data_config_i.w_offset;
            ob_mem_cenb_o   <= 1'b1;
            ob_mem_wenb_o   <= 1'b1;
            ob_mem_addr_o   <= data_config_i.o_offset_w; // this is a typo lol (remove _w)

            // o_done <= 1'b0; // we actually want o_done to preserve it's prev value
            o_mode      <= 1'b0;
            o_load_psum <= 1'b0;

            case (next_state)
                IDLE: begin
                    // for the future might want to add ready signal :)
                    o_done <= 1'b1;

                    // all of the default outputs will be captured during IDLE state
                    // note that data_config signals must be static with respect to the module
                end
                PRELOAD: begin
                    // only enable mem for w_rows cycles :)
                    wb_mem_cenb_o <= (load_count_r < preload_total_cycles - 2'b10) ? 1'b0 : 1'b1;       // enable weight mem
                    wb_mem_wenb_o <= 1'b1;                                                              // read mode
                    wb_mem_addr_o <= wb_mem_cenb_o ? wb_mem_addr_o : wb_mem_addr_o + 1'b1;              // addr

                    o_mode <= 1'b0; // set systolic to preload
                    o_load_psum <= 1'b0;
                    o_done <= 1'b0; // actually reset o_done :)

                    // prefetch input buffer on last preload cycle :)
                    ib_mem_cenb_o <= (load_count_r == preload_total_cycles - 2'b10) ? 1'b0 : 1'b1;
                    ib_mem_wenb_o <= 1'b1;
                    ib_mem_addr_o <= ib_mem_cenb_o ? ib_mem_addr_o : ib_mem_addr_o + 1'b1;
                end
                STREAM: begin
                    // we enable read act inputs for (i_rows + w_rows - 1) - 2 (-1 for counter index and -1 for prefetch)
                    ib_mem_cenb_o <= (stream_count_r <= (stream_iact_cycles - 2'b11)) ? 1'b0 : 1'b1;    // enable act mem
                    ib_mem_wenb_o <= 1'b1;                                                              // read mode
                    ib_mem_addr_o <= ib_mem_cenb_o ? ib_mem_addr_o : ib_mem_addr_o + 1'b1;              // addr

                    // next we enable write output acts for remaining cycles
                    // note that there is one cycle of overlap!
                    ob_mem_cenb_o <= (stream_count_r >= (OUTPUT_START_WRITE - 1'b1)) ? 1'b0 : 1'b1;     // enable output mem
                    ob_mem_wenb_o <= (stream_count_r >= (OUTPUT_START_WRITE - 1'b1)) ? 1'b0 : 1'b1;     // write mode
                    ob_mem_addr_o <= ob_mem_cenb_o ? ob_mem_addr_o : ob_mem_addr_o + 1'b1;              // addr

                    o_mode      <= 1'b1; // set systolic to compute mode
                    o_load_psum <= 1'b1; // we need to clear the i_weight port or just swtich it to psum (will be tied to 0)
                end
                default: begin
                    // for debug purposes
                    ib_mem_cenb_o    <= 'x;
                    ib_mem_wenb_o    <= 'x;
                    ib_mem_addr_o    <= 'x;

                    wb_mem_cenb_o   <= 'x;
                    wb_mem_wenb_o   <= 'x;
                    wb_mem_addr_o   <= 'x;

                    ob_mem_cenb_o   <= 'x;
                    ob_mem_wenb_o   <= 'x;
                    ob_mem_addr_o   <= 'x;

                    ps_mem_cenb_o  <= 'x;
                    ps_mem_wenb_o  <= 'x;
                    ps_mem_addr_o  <= 'x;

                    o_mode          <= 'x;
                    o_load_psum     <= 'x;
                    o_done          <= 'x;
                end
            endcase
        end
    end

endmodule