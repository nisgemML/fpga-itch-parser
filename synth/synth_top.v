// synth/synth_top.v — wrapper used ONLY for synthesis / place-and-route.
//
// itch50_parser has ~460 output bits, more than any package has pins. This
// wrapper registers every output and XOR-reduces them into one output pin.
// The XOR depends on every output bit, so synthesis cannot remove any parser
// logic as unobservable. The reduction is pipelined behind its own register
// stage, so it does not lengthen the parser's own register-to-register paths.
module synth_top (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       byte_valid,
    input  wire [7:0] byte_in,
    input  wire       byte_last,
    output reg        observe
);
    wire        msg_valid, msg_known, len_ok;
    wire [7:0]  msg_type, side, printable;
    wire [15:0] locate, tracking;
    wire [47:0] timestamp_ns;
    wire [63:0] order_ref, new_ref, stock, match_number;
    wire [31:0] shares, price, attribution;

    itch50_parser dut (
        .clk(clk), .rst_n(rst_n), .byte_valid(byte_valid), .byte_in(byte_in), .byte_last(byte_last),
        .msg_valid(msg_valid), .msg_known(msg_known), .len_ok(len_ok), .msg_type(msg_type),
        .locate(locate), .tracking(tracking), .timestamp_ns(timestamp_ns), .order_ref(order_ref),
        .new_ref(new_ref), .side(side), .shares(shares), .stock(stock), .price(price),
        .match_number(match_number), .printable(printable), .attribution(attribution));

    wire [458:0] all_out = {msg_valid, msg_known, len_ok, msg_type, side, printable, locate, tracking,
                            timestamp_ns, order_ref, new_ref, stock, match_number, shares, price, attribution};
    reg  [463:0] snap;               // 459 output bits + 5 pad bits = 16 x 29
    reg  [15:0]  partial;            // pipeline stage 1: 16 partial XORs of 29 bits
    integer k;
    always @(posedge clk) begin
        snap <= {5'b0, all_out};
        for (k = 0; k < 16; k = k + 1) partial[k] <= ^snap[k*29 +: 29];
        observe <= ^partial;         // pipeline stage 2
    end
endmodule
