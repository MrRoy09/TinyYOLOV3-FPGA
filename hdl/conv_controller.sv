module conv_controller #(
    parameter WT_ADDR_WIDTH   = 12,
    parameter BIAS_ADDR_WIDTH = 7,
    parameter WT_LATENCY      = 3,
    parameter CONV_PE_PIPE    = 4,  // 4 stages after timing fix
    parameter QUANT_LATENCY   = 4,
    parameter MAXPOOL_LATENCY = 4,
    parameter PIPE_DEPTH      = WT_LATENCY + CONV_PE_PIPE + 1 + QUANT_LATENCY + MAXPOOL_LATENCY  // = 16
)(
    input  logic        clk,
    input  logic        rst,

    // CPU config
    input  logic [9:0]                  cfg_ci_groups,
    input  logic [BIAS_ADDR_WIDTH-1:0]  cfg_output_group,
    input  logic [WT_ADDR_WIDTH-1:0]    cfg_wt_base_addr,
    input  logic                        go,
    output logic                        busy,
    output logic                        done,

    // bias store
    output logic                        bias_rd_en,
    output logic [BIAS_ADDR_WIDTH-1:0]  bias_rd_group,
    input  logic                        bias_valid,

    // weight manager
    output logic                        wt_rd_en,
    output logic [WT_ADDR_WIDTH-1:0]    wt_rd_addr,
    input  logic                        wt_data_ready,

    // pixel stream from kernel_window
    input  logic                        pixel_valid,
    input  logic                        last_pixel,

    // conv_3x3 control — aligned with weight arrival
    output logic                        conv_valid_in,
    output logic                        conv_last_channel
);

typedef enum logic [2:0] {
    IDLE,
    LOAD_BIAS,
    WAIT_BIAS,
    CONV,
    DRAIN
} state_t;

state_t state;
logic [9:0] ci_cnt;
logic [4:0] drain_cnt;  // 5 bits to hold PIPE_DEPTH (up to 31)

// raw control signals generated in CONV state
logic valid_raw;
logic last_ch_raw;

// delay valid_in and last_channel to align with weight arrival (WT_LATENCY cycles)
logic [WT_LATENCY-1:0] valid_dly;
logic [WT_LATENCY-1:0] last_ch_dly;

assign conv_valid_in     = valid_dly[WT_LATENCY-1];
assign conv_last_channel = last_ch_dly[WT_LATENCY-1];

always_ff @(posedge clk) begin
    if (rst) begin
        valid_dly   <= '0;
        last_ch_dly <= '0;
    end else begin
        valid_dly   <= {valid_dly[WT_LATENCY-2:0], valid_raw};
        last_ch_dly <= {last_ch_dly[WT_LATENCY-2:0], last_ch_raw};
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        state         <= IDLE;
        busy          <= 0;
        done          <= 0;
        bias_rd_en    <= 0;
        bias_rd_group <= 0;
        wt_rd_en      <= 0;
        wt_rd_addr    <= 0;
        valid_raw     <= 0;
        last_ch_raw   <= 0;
        ci_cnt        <= 0;
        drain_cnt     <= 0;
    end else begin
        done        <= 0;
        bias_rd_en  <= 0;
        valid_raw   <= 0;
        last_ch_raw <= 0;
        wt_rd_en    <= 0;

        case (state)
            IDLE: begin
                if (go) begin
                    busy  <= 1;
                    state <= LOAD_BIAS;
                end
            end

            LOAD_BIAS: begin
                bias_rd_en    <= 1;
                bias_rd_group <= cfg_output_group;
                state         <= WAIT_BIAS;
            end

            WAIT_BIAS: begin
                if (bias_valid)
                    state <= CONV;
            end

            CONV: begin
                if (pixel_valid) begin
                    wt_rd_en    <= 1;
                    wt_rd_addr  <= cfg_wt_base_addr + ci_cnt;
                    valid_raw   <= 1;

                    if (ci_cnt == cfg_ci_groups - 10'd1) begin
                        last_ch_raw <= 1;
                        ci_cnt      <= 0;

                        if (last_pixel) begin
                            state     <= DRAIN;
                            drain_cnt <= 0;
                        end
                    end else begin
                        ci_cnt <= ci_cnt + 1;
                    end
                end
            end

            DRAIN: begin
                drain_cnt <= drain_cnt + 1;
                if (drain_cnt == PIPE_DEPTH[4:0] - 5'd1) begin
                    busy  <= 0;
                    done  <= 1;
                    state <= IDLE;
                end
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule
