// rtl/itch_add_order_parser.v
//
// Synthesizable streaming parser for ITCH 5.0 AddOrder ('A'/'F') messages,
// matching the exact wire layout this portfolio's real C++ parser uses --
// third_party/udp-multicast-receiver's own wire_format.hpp, ItchAddOrder::parse() --
// byte-offset for byte-offset, not reimplemented from the ITCH spec
// independently. That's deliberate: tests/ differentially tests this RTL
// against that exact C++ reference, so "matches the real parser" is a
// claim that's actually checked, not assumed from both having read the
// same spec document.
//
// Wire layout (byte offset : field, all multi-byte fields big-endian,
// matching ItchAddOrder::parse()):
//   0      : msg_type   (1 byte,  'A' or 'F')
//   1-6    : timestamp  (6 bytes, 48-bit)
//   7-14   : order_ref  (8 bytes, 64-bit)
//   15     : side       (1 byte,  'B' or 'S')
//   16-19  : shares     (4 bytes, 32-bit)
//   20-27  : stock      (8 bytes, ASCII, space-padded)
//   28-31  : price      (4 bytes, 32-bit, fixed-point x10000)
//   32-35  : reserved / unused by this message type
//
// Interface: one byte per clock, byte_valid-qualified -- a standard,
// realistic streaming interface for a byte-wide feed-parsing block, not
// a toy single-shot combinational "parser." msg_valid pulses for exactly
// one cycle once all 36 bytes of one message have been consumed; the
// parser resets its own byte counter automatically and is ready for the
// next message on the following cycle (back-to-back messages with no
// gap are legal input).

module itch_add_order_parser (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        byte_valid,
    input  wire [7:0]  byte_in,

    output reg         msg_valid,     // one-cycle pulse: all fields below are valid this cycle
    output reg [7:0]   msg_type,
    output reg [47:0]  timestamp_ns,
    output reg [63:0]  order_ref,
    output reg [7:0]   side,
    output reg [31:0]  shares,
    output reg [63:0]  stock,         // 8 ASCII bytes packed MSB-first: stock[63:56] is byte offset 20
    output reg [31:0]  price
);

    localparam MSG_BYTES = 36;

    reg [5:0] byte_count; // 0..35, enough range for MSG_BYTES-1

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_count   <= 6'd0;
            msg_valid    <= 1'b0;
            msg_type     <= 8'd0;
            timestamp_ns <= 48'd0;
            order_ref    <= 64'd0;
            side         <= 8'd0;
            shares       <= 32'd0;
            stock        <= 64'd0;
            price        <= 32'd0;
        end else begin
            msg_valid <= 1'b0; // default: only asserted explicitly on the last byte, below

            if (byte_valid) begin
                case (byte_count)
                    6'd0:  msg_type <= byte_in;

                    // timestamp_ns: bytes 1-6, 48-bit, big-endian accumulate
                    6'd1:  timestamp_ns[47:40] <= byte_in;
                    6'd2:  timestamp_ns[39:32] <= byte_in;
                    6'd3:  timestamp_ns[31:24] <= byte_in;
                    6'd4:  timestamp_ns[23:16] <= byte_in;
                    6'd5:  timestamp_ns[15:8]  <= byte_in;
                    6'd6:  timestamp_ns[7:0]   <= byte_in;

                    // order_ref: bytes 7-14, 64-bit, big-endian
                    6'd7:  order_ref[63:56] <= byte_in;
                    6'd8:  order_ref[55:48] <= byte_in;
                    6'd9:  order_ref[47:40] <= byte_in;
                    6'd10: order_ref[39:32] <= byte_in;
                    6'd11: order_ref[31:24] <= byte_in;
                    6'd12: order_ref[23:16] <= byte_in;
                    6'd13: order_ref[15:8]  <= byte_in;
                    6'd14: order_ref[7:0]   <= byte_in;

                    6'd15: side <= byte_in;

                    // shares: bytes 16-19, 32-bit, big-endian
                    6'd16: shares[31:24] <= byte_in;
                    6'd17: shares[23:16] <= byte_in;
                    6'd18: shares[15:8]  <= byte_in;
                    6'd19: shares[7:0]   <= byte_in;

                    // stock: bytes 20-27, packed MSB-first (stock[63:56] = byte 20)
                    6'd20: stock[63:56] <= byte_in;
                    6'd21: stock[55:48] <= byte_in;
                    6'd22: stock[47:40] <= byte_in;
                    6'd23: stock[39:32] <= byte_in;
                    6'd24: stock[31:24] <= byte_in;
                    6'd25: stock[23:16] <= byte_in;
                    6'd26: stock[15:8]  <= byte_in;
                    6'd27: stock[7:0]   <= byte_in;

                    // price: bytes 28-31, 32-bit, big-endian
                    6'd28: price[31:24] <= byte_in;
                    6'd29: price[23:16] <= byte_in;
                    6'd30: price[15:8]  <= byte_in;
                    6'd31: price[7:0]   <= byte_in;

                    // bytes 32-35: reserved, consumed but not stored --
                    // on byte 35 (the 36th byte, byte_count==35) the
                    // message is complete.
                    default: ; // bytes 32-34: nothing to do but advance the counter
                endcase

                if (byte_count == MSG_BYTES - 1) begin
                    msg_valid  <= 1'b1;
                    byte_count <= 6'd0; // ready for the next message next cycle, no gap required
                end else begin
                    byte_count <= byte_count + 6'd1;
                end
            end
        end
    end

endmodule
