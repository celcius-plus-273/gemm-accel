module sa_compute
#(
    parameter ADD_DATAWIDTH,
    parameter MUL_DATAWIDTH,
    parameter NUM_ROWS,
    parameter NUM_COLS
)(
    // clk, rst
    input logic clk,
    input logic rst_n,

    // mode:
    //  0: weight pre-load
    //  1: compute
    input logic i_mode,

    // Is this a better idea than having an external accumulator block?
    // load psum (mux control)
    // 0: col_inter[0][n] <- i_weights
    // 1: col_inter[0][n] <- i_psum
    input logic i_load_psum,

    // inputs
    // i_act buffer & weight buffer
    input logic signed [NUM_ROWS-1:0][MUL_DATAWIDTH-1 : 0] i_act,
    input logic signed [NUM_COLS-1:0][MUL_DATAWIDTH-1 : 0] i_weight,

    // intermediate partial sums buffer
    input logic signed [NUM_COLS-1:0][ADD_DATAWIDTH-1 : 0] i_psum,

    // output partial sums buffer
    output logic signed [NUM_COLS-1:0][ADD_DATAWIDTH-1 : 0] o_psum
);

    // --------------------------------------- //
    // --------- Memory Data Buffers --------- //
    // --------------------------------------- //
    // Decouples memory data arrival time (due to long wires) from the systolic array logic
    // - 1 cycle buffer
    logic signed [NUM_ROWS-1:0][MUL_DATAWIDTH-1 : 0] i_act_r;
    logic signed [NUM_COLS-1:0][MUL_DATAWIDTH-1 : 0] i_weight_r;
    logic signed [NUM_COLS-1:0][ADD_DATAWIDTH-1 : 0] i_psum_r;
    
    // caputre the input data into the buffers
    always_ff @(posedge clk or negedge rst_n) begin : data_buffer_ff
        if (!rst_n) begin
            i_act_r     <= '0;
            i_weight_r  <= '0;
            i_psum_r    <= '0;
        end
        else begin
            i_act_r     <= i_act;
            i_weight_r  <= i_weight;
            i_psum_r    <= i_psum;
        end
    end

    // --------------------------------------- //
    // ------ PE array interconnections ------ //
    // --------------------------------------- //
    // Row-wise (horizontal) interconnection
    // Dimensions: (NUM_ROWS)x(NUM_COLS+1)
    // Note: NUM_COLS + 1 is needed for the output of the right-most PEs
    //       which gets connected to an o_act signal used with DEBUG ifdef
    wire signed [MUL_DATAWIDTH-1 : 0] row_inter [NUM_ROWS][NUM_COLS+1]; // row_inter[j][i]

    // Column-wise (vertical) interconnection
    // Dimensions: (NUM_ROWS+1)x(NUM_COLS)
    // Note: NUM_ROWS + 1 is needed for the output of the bottom-most PEs
    //       which is connected to o_psum
    wire signed [ADD_DATAWIDTH-1 : 0] col_inter [NUM_ROWS+1][NUM_COLS]; // column_inter[j][i]

    // ---------------------------------------- //
    // ------ PE Array Generate For-Loop ------ //
    // ---------------------------------------- //
    // j = row coordinate       (y)
    // i = column coordinate    (x)
    genvar i, j; // (x,y) = (i,j)
    generate
        for (j = 0; j < NUM_ROWS; j += 1) begin : row_coord
            for (i = 0; i < NUM_COLS; i += 1) begin : col_coord
                sa_pe #(
                    .ADD_DATAWIDTH(ADD_DATAWIDTH),
                    .MUL_DATAWIDTH(MUL_DATAWIDTH)
                ) sa_pe_inst (
                    // clk, rst, mode
                    .clk(clk),
                    .rst_n(rst_n),
                    .i_mode(i_mode),
                    // inputs
                    .i_act(row_inter[j][i]),
                    .i_weight(col_inter[j][i]),
                    .i_psum(col_inter[j][i]),
                    // outputs
                    .o_act(row_inter[j][i+1]),
                    .o_weight_psum(col_inter[j+1][i])
                );
            end
        end
    endgenerate

    // -------------------------------------- //
    // ----- Input / Output Assignments ----- //
    // -------------------------------------- //
    // Input Weights and Psums
    genvar n;
    generate
        for (n = 0; n < NUM_COLS; n += 1) begin : gen_i_weight_psum
            assign col_inter[0][n] = i_load_psum ? i_psum_r[n] : i_weight_r[n];
        end
    endgenerate

    // Input Act
    generate
        for (n = 0; n < NUM_ROWS; n += 1) begin : gen_i_act
            // For WS Systolic, iActs need to be shifted, the compute array expects
            // a shifted set of i_act i.e. it will take the entire iActs word and pass
            // it into the array. 
            // Shifting MUST be handled by the level above
            assign row_inter[n][0] = i_act_r[n];
        end
    endgenerate

    // Output sum (total or partial)
    generate
        for (n = 0; n < NUM_COLS; n += 1) begin : gen_o_psum
            // last row of column interconnect
            assign o_psum[n] = col_inter[NUM_ROWS][n];
        end
    endgenerate

    // ------------------------- //
    // ----- DEBUG Signals ----- //
    // ------------------------- //
    `ifdef DEBUG
        // Output activations for visualization of iAct propagation through array
        logic [MUL_DATAWIDTH-1 : 0] o_act [NUM_ROWS];
        generate
            for (n = 0; n < NUM_ROWS; n += 1) begin : gen_o_act
                assign o_act[n] = row_inter[n][NUM_COLS];
            end
        endgenerate

        // Expose all of the internal weight registers
        logic [MUL_DATAWIDTH-1:0] systolic_weights [NUM_ROWS][NUM_COLS];  // array of wires
        genvar x, y;
        generate
            for (y = 0; y < NUM_ROWS; y += 1) begin
                for (x = 0; x < NUM_COLS; x += 1) begin
                    assign systolic_weights[y][x] = row_coord[y].col_coord[x].sa_pe_inst.weight_r;
                end
            end
        endgenerate

        logic [MUL_DATAWIDTH-1:0] systolic_input_weights [NUM_ROWS][NUM_COLS];  // array of wires
        generate
            for (y = 0; y < NUM_ROWS; y += 1) begin
                for (x = 0; x < NUM_COLS; x += 1) begin
                    assign systolic_input_weights[y][x] = row_coord[y].col_coord[x].sa_pe_inst.i_weight;
                end
            end
        endgenerate

        logic [MUL_DATAWIDTH-1:0] systolic_inputs [NUM_ROWS][NUM_COLS];  // array of wires
        generate
            for (y = 0; y < NUM_ROWS; y += 1) begin
                for (x = 0; x < NUM_COLS; x += 1) begin
                    assign systolic_inputs[y][x] = row_coord[y].col_coord[x].sa_pe_inst.i_act;
                end
            end
        endgenerate

        logic [ADD_DATAWIDTH-1:0] systolic_outputs [NUM_ROWS][NUM_COLS];  // array of wires
        generate
            for (y = 0; y < NUM_ROWS; y += 1) begin
                for (x = 0; x < NUM_COLS; x += 1) begin
                    assign systolic_outputs[y][x] = row_coord[y].col_coord[x].sa_pe_inst.o_weight_psum;
                end
            end
        endgenerate

        logic [ADD_DATAWIDTH-1:0] systolic_psums [NUM_ROWS][NUM_COLS];  // array of wires
        generate
            for (y = 0; y < NUM_ROWS; y += 1) begin
                for (x = 0; x < NUM_COLS; x += 1) begin
                    assign systolic_psums[y][x] = row_coord[y].col_coord[x].sa_pe_inst.i_psum;
                end
            end
        endgenerate

        logic [ADD_DATAWIDTH-1:0] systolic_mode [NUM_ROWS][NUM_COLS];  // array of wires
        generate
            for (y = 0; y < NUM_ROWS; y += 1) begin
                for (x = 0; x < NUM_COLS; x += 1) begin
                    assign systolic_mode[y][x] = row_coord[y].col_coord[x].sa_pe_inst.i_mode;
                end
            end
        endgenerate
    `endif

    // TODO: Add functional coverage :)
    //  - interconnect coverage
endmodule