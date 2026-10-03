// rtl/itch_delete_order_parser.v
//
// Second message type, extending the same methodology as
// itch_add_order_parser.v to a real, different wire layout rather than
// stopping at one message type. A separate module per message type
// (rather than one parser with internal type-dispatch) is a deliberate,
// realistic architectural choice -- many real feed-handling designs use
// per-message-type parser blocks feeding a common downstream dispatcher,
// rather than one monolithic block branching on every possible layout.
//
// Wire layout (byte offset : field), matching
// third_party/udp-multicast-receiver's wire_format.hpp ItchDeleteOrder::parse()
// exactly, including what it does NOT extract:
//   0      : msg_type   (1 byte,  'D')
//   1-6    : timestamp  (6 bytes, 48-bit, big-endian)
//   7-8    : locate     (2 bytes) -- present on the wire, consumed here,
//                                    NOT extracted -- the real C++ parser
//                                    skips these too, so this RTL matches
//                                    that behavior exactly rather than
//                                    "improving" on it and no longer
//                                    being comparable
//   9-10   : tracking   (2 bytes) -- same: consumed, not extracted
//   11-18  : order_ref  (8 bytes, 64-bit, big-endian)
//
// Same streaming interface convention as itch_add_order_parser: one byte
// per clock, byte_valid-qualified, msg_valid pulses for one cycle once
// all 19 bytes are consumed.

module itch_delete_order_parser (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        byte_valid,
    input  wire [7:0]  byte_in,

    output reg         msg_valid,
    output reg [7:0]   msg_type,
    output reg [47:0]  timestamp_ns,
    output reg [63:0]  order_ref
);

    localparam MSG_BYTES = 19;

    reg [4:0] byte_count; // 0..18

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_count   <= 5'd0;
            msg_valid    <= 1'b0;
            msg_type     <= 8'd0;
            timestamp_ns <= 48'd0;
            order_ref    <= 64'd0;
        end else begin
            msg_valid <= 1'b0;

            if (byte_valid) begin
                case (byte_count)
                    5'd0:  msg_type <= byte_in;

                    5'd1:  timestamp_ns[47:40] <= byte_in;
                    5'd2:  timestamp_ns[39:32] <= byte_in;
                    5'd3:  timestamp_ns[31:24] <= byte_in;
                    5'd4:  timestamp_ns[23:16] <= byte_in;
                    5'd5:  timestamp_ns[15:8]  <= byte_in;
                    5'd6:  timestamp_ns[7:0]   <= byte_in;

                    // bytes 7-10 (locate, tracking): consumed, not stored --
                    // matches the real C++ parser's own behavior exactly.

                    5'd11: order_ref[63:56] <= byte_in;
                    5'd12: order_ref[55:48] <= byte_in;
                    5'd13: order_ref[47:40] <= byte_in;
                    5'd14: order_ref[39:32] <= byte_in;
                    5'd15: order_ref[31:24] <= byte_in;
                    5'd16: order_ref[23:16] <= byte_in;
                    5'd17: order_ref[15:8]  <= byte_in;
                    5'd18: order_ref[7:0]   <= byte_in;

                    default: ; // bytes 7-10
                endcase

                if (byte_count == MSG_BYTES - 1) begin
                    msg_valid  <= 1'b1;
                    byte_count <= 5'd0;
                end else begin
                    byte_count <= byte_count + 5'd1;
                end
            end
        end
    end

endmodule
