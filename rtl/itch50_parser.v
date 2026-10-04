// rtl/itch50_parser.v
//
// Synthesizable streaming parser for the REAL NASDAQ TotalView-ITCH 5.0 message layout
// (TOTALVIEW-ITCH 5.0 spec, v5.0 03/06/2015, section 4), for the book-affecting messages plus the
// Stock Directory: 'R' 'A' 'F' 'E' 'C' 'X' 'D' 'U'.
//
// Every message starts: type@0, stock locate@1 (2 bytes), tracking number@3 (2 bytes), timestamp@5
// (6 bytes); fields after that depend on the type (offsets below are straight from the spec tables).
// All multi-byte fields are big-endian; alpha fields are ASCII, left-justified, space-padded.
//
//   R  Stock Directory  39 bytes  stock@11(8)
//   A  Add Order        36 bytes  ref@11(8) side@19 shares@20(4) stock@24(8) price@32(4)
//   F  Add Order+MPID   40 bytes  as A, plus attribution@36(4)
//   E  Order Executed   31 bytes  ref@11(8) shares@19(4) match@23(8)
//   C  Exec With Price  36 bytes  as E, plus printable@31 price@32(4)
//   X  Order Cancel     23 bytes  ref@11(8) shares@19(4)              (shares = shares CANCELED)
//   D  Order Delete     19 bytes  ref@11(8)
//   U  Order Replace    35 bytes  orig ref@11(8) new ref@19(8) shares@27(4) price@31(4)
//
// Interface: one byte per clock, qualified by byte_valid. Message FRAMING comes from the transport
// (MoldUDP64, or the 2-byte length prefix in NASDAQ's sample files), exactly as in real hardware:
// byte_last marks the final byte of each message, so this block never has to guess where a message
// ends -- including types it doesn't decode. After byte_last, msg_valid pulses for one cycle and the
// output registers hold that message's fields; read them only while msg_valid is high. Fields that a
// given type does not carry read as zero (they are cleared at the first byte of every message).
//   msg_known : the type is one this block decodes
//   len_ok    : the received length equals the spec's length for that type (flags truncated/overlong)
//
// This replaces itch_add_order_parser.v / itch_delete_order_parser.v, which implemented the
// portfolio's simplified layout (no locate/tracking fields) rather than NASDAQ's -- see BUGS_FOUND.md #4.

module itch50_parser (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        byte_valid,
    input  wire [7:0]  byte_in,
    input  wire        byte_last,

    output reg         msg_valid,
    output reg         msg_known,
    output reg         len_ok,
    output reg  [7:0]  msg_type,
    output reg  [15:0] locate,
    output reg  [15:0] tracking,
    output reg  [47:0] timestamp_ns,
    output reg  [63:0] order_ref,      // A F E C X D: the order; U: the ORIGINAL order
    output reg  [63:0] new_ref,        // U only
    output reg  [7:0]  side,           // A F
    output reg  [31:0] shares,         // A F: total; E C: executed; X: canceled; U: new total
    output reg  [63:0] stock,          // R A F (8 ASCII bytes, first byte in the top 8 bits)
    output reg  [31:0] price,          // A F: display price; C: execution price; U: new price
    output reg  [63:0] match_number,   // E C
    output reg  [7:0]  printable,      // C
    output reg  [31:0] attribution     // F
);

    // Spec length by type; 0 = a type this block does not decode.
    function [7:0] spec_len(input [7:0] t);
        case (t)
            "R":     spec_len = 8'd39;
            "A":     spec_len = 8'd36;
            "F":     spec_len = 8'd40;
            "E":     spec_len = 8'd31;
            "C":     spec_len = 8'd36;
            "X":     spec_len = 8'd23;
            "D":     spec_len = 8'd19;
            "U":     spec_len = 8'd35;
            default: spec_len = 8'd0;
        endcase
    endfunction

    reg  [6:0] idx;                                   // index of the incoming byte within its message
    wire [7:0] cur_type  = (idx == 7'd0) ? byte_in : msg_type;
    wire [7:0] total_len = {1'b0, idx} + 8'd1;        // message length if THIS byte is the last

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idx <= 7'd0; msg_valid <= 1'b0; msg_known <= 1'b0; len_ok <= 1'b0; msg_type <= 8'd0;
            locate <= 16'd0; tracking <= 16'd0; timestamp_ns <= 48'd0; order_ref <= 64'd0; new_ref <= 64'd0;
            side <= 8'd0; shares <= 32'd0; stock <= 64'd0; price <= 32'd0; match_number <= 64'd0;
            printable <= 8'd0; attribution <= 32'd0;
        end else begin
            msg_valid <= 1'b0;
            if (byte_valid) begin
                if (idx == 7'd0) begin
                    msg_type <= byte_in;
                    locate <= 16'd0; tracking <= 16'd0; timestamp_ns <= 48'd0; order_ref <= 64'd0; new_ref <= 64'd0;
                    side <= 8'd0; shares <= 32'd0; stock <= 64'd0; price <= 32'd0; match_number <= 64'd0;
                    printable <= 8'd0; attribution <= 32'd0;
                end else begin
                    if (idx == 7'd1 || idx == 7'd2)  locate       <= {locate[7:0], byte_in};
                    if (idx == 7'd3 || idx == 7'd4)  tracking     <= {tracking[7:0], byte_in};
                    if (idx >= 7'd5 && idx <= 7'd10) timestamp_ns <= {timestamp_ns[39:0], byte_in};
                    case (msg_type)
                        "R": begin
                            if (idx >= 7'd11 && idx <= 7'd18) stock <= {stock[55:0], byte_in};
                        end
                        "A", "F": begin
                            if (idx >= 7'd11 && idx <= 7'd18) order_ref <= {order_ref[55:0], byte_in};
                            if (idx == 7'd19)                 side      <= byte_in;
                            if (idx >= 7'd20 && idx <= 7'd23) shares    <= {shares[23:0], byte_in};
                            if (idx >= 7'd24 && idx <= 7'd31) stock     <= {stock[55:0], byte_in};
                            if (idx >= 7'd32 && idx <= 7'd35) price     <= {price[23:0], byte_in};
                            if (msg_type == "F" && idx >= 7'd36 && idx <= 7'd39) attribution <= {attribution[23:0], byte_in};
                        end
                        "E", "C": begin
                            if (idx >= 7'd11 && idx <= 7'd18) order_ref    <= {order_ref[55:0], byte_in};
                            if (idx >= 7'd19 && idx <= 7'd22) shares       <= {shares[23:0], byte_in};
                            if (idx >= 7'd23 && idx <= 7'd30) match_number <= {match_number[55:0], byte_in};
                            if (msg_type == "C" && idx == 7'd31)                 printable <= byte_in;
                            if (msg_type == "C" && idx >= 7'd32 && idx <= 7'd35) price     <= {price[23:0], byte_in};
                        end
                        "X": begin
                            if (idx >= 7'd11 && idx <= 7'd18) order_ref <= {order_ref[55:0], byte_in};
                            if (idx >= 7'd19 && idx <= 7'd22) shares    <= {shares[23:0], byte_in};
                        end
                        "D": begin
                            if (idx >= 7'd11 && idx <= 7'd18) order_ref <= {order_ref[55:0], byte_in};
                        end
                        "U": begin
                            if (idx >= 7'd11 && idx <= 7'd18) order_ref <= {order_ref[55:0], byte_in};
                            if (idx >= 7'd19 && idx <= 7'd26) new_ref   <= {new_ref[55:0], byte_in};
                            if (idx >= 7'd27 && idx <= 7'd30) shares    <= {shares[23:0], byte_in};
                            if (idx >= 7'd31 && idx <= 7'd34) price     <= {price[23:0], byte_in};
                        end
                        default: ;
                    endcase
                end

                if (byte_last) begin
                    msg_valid <= 1'b1;
                    msg_known <= (spec_len(cur_type) != 8'd0);
                    len_ok    <= (spec_len(cur_type) == total_len);
                    idx       <= 7'd0;
                end else if (idx != 7'd127) begin
                    idx <= idx + 7'd1;
                end
            end
        end
    end

endmodule
