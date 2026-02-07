module parameter_loader #(
    parameter NUM_FILTERS = 64,
    parameter K_SIZE      = 9,
    parameter W_ADDR_W    = 11, 
    parameter B_ADDR_W    = 9,
    parameter AXIS_WIDTH  = 512 // 64 bytes
)(
    input  logic        clk,
    input  logic        rst,
    
    // AXI-Stream Slave (512-bit wide)
    input  logic [AXIS_WIDTH-1:0] s_axis_tdata,
    input  logic                  s_axis_tvalid,
    output logic                  s_axis_tready,
    
    // Control Interface
    input  logic        load_en,
    input  logic [W_ADDR_W-1:0] expected_weight_rows,
    output logic        load_done,
    
    // Weight BRAM Interface (4608-bit row)
    output logic [W_ADDR_W-1:0] weight_addr,
    output logic [NUM_FILTERS*K_SIZE*8-1:0] weight_data,
    output logic        weight_we,
    
    // Bias BRAM Interface (2048-bit row)
    output logic [B_ADDR_W-1:0] bias_addr,
    output logic [NUM_FILTERS*32-1:0] bias_data,
    output logic        bias_we
);

    // Number of 512-bit words per memory row
    // Weights: 4608 bits / 512 = 9 words
    // Bias:    2048 bits / 512 = 4 words
    localparam WORDS_PER_W_ROW = 9; 
    localparam WORDS_PER_B_ROW = 4;

    typedef enum logic [2:0] {IDLE, LOAD_WEIGHTS, LOAD_BIAS, DONE} state_t;
    state_t state;

    logic [3:0] word_cnt;
    logic [W_ADDR_W-1:0] row_cnt;
    
    logic [NUM_FILTERS*K_SIZE*8-1:0] weight_buffer;
    logic [NUM_FILTERS*32-1:0]       bias_buffer;

    assign s_axis_tready = (state == LOAD_WEIGHTS || state == LOAD_BIAS);

    always_ff @(posedge clk) begin
        if (rst) begin
            state       <= IDLE;
            word_cnt    <= '0;
            row_cnt     <= '0;
            weight_we   <= 1'b0;
            bias_we     <= 1'b0;
            load_done   <= 1'b0;
            weight_addr <= '0;
            bias_addr   <= '0;
        end else begin
            case (state)
                IDLE: begin
                    load_done <= 1'b0;
                    if (load_en) begin
                        state    <= LOAD_WEIGHTS;
                        word_cnt <= '0;
                        row_cnt  <= '0;
                    end
                end

                LOAD_WEIGHTS: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        // Load 512 bits at a time into the wide row buffer
                        weight_buffer[word_cnt*512 +: 512] <= s_axis_tdata;
                        
                        if (word_cnt == WORDS_PER_W_ROW - 1) begin
                            word_cnt    <= '0;
                            weight_we   <= 1'b1;
                            weight_addr <= row_cnt;
                            
                            if (row_cnt == expected_weight_rows - 1) begin
                                state   <= LOAD_BIAS;
                                row_cnt <= '0;
                            end else begin
                                row_cnt <= row_cnt + 1'b1;
                            end
                        end else begin
                            word_cnt  <= word_cnt + 1'b1;
                            weight_we <= 1'b0;
                        end
                    end else begin
                        weight_we <= 1'b0;
                    end
                end

                LOAD_BIAS: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        bias_buffer[word_cnt*512 +: 512] <= s_axis_tdata;
                        
                        if (word_cnt == WORDS_PER_B_ROW - 1) begin
                            word_cnt  <= '0;
                            bias_we   <= 1'b1;
                            bias_addr <= '0; // One row of 64 biases
                            state     <= DONE;
                        end else begin
                            word_cnt <= word_cnt + 1'b1;
                            bias_we  <= 1'b0;
                        end
                    end else begin
                        bias_we <= 1'b0;
                    end
                end

                DONE: begin
                    weight_we <= 1'b0;
                    bias_we   <= 1'b0;
                    load_done <= 1'b1;
                    if (!load_en) state <= IDLE;
                end
            endcase
        end
    end

    assign weight_data = weight_buffer;
    assign bias_data   = bias_buffer;

endmodule