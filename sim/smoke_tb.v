// sim/smoke_tb.v -- hand-encoded Add Order in the REAL ITCH 5.0 layout, checked field by field (Icarus Verilog).
`timescale 1ns/1ps
module smoke_tb;
    reg clk = 0, rst_n = 0, byte_valid = 0, byte_last = 0; reg [7:0] byte_in = 0;
    wire msg_valid, msg_known, len_ok; wire [7:0] msg_type, side, printable; wire [15:0] locate, tracking;
    wire [47:0] timestamp_ns; wire [63:0] order_ref, new_ref, stock, match_number; wire [31:0] shares, price, attribution;
    itch50_parser dut(.clk(clk), .rst_n(rst_n), .byte_valid(byte_valid), .byte_in(byte_in), .byte_last(byte_last),
        .msg_valid(msg_valid), .msg_known(msg_known), .len_ok(len_ok), .msg_type(msg_type), .locate(locate), .tracking(tracking),
        .timestamp_ns(timestamp_ns), .order_ref(order_ref), .new_ref(new_ref), .side(side), .shares(shares), .stock(stock),
        .price(price), .match_number(match_number), .printable(printable), .attribution(attribution));
    always #5 clk = ~clk;
    reg [7:0] m [0:35]; integer i;
    initial begin
        // type=A locate=7 tracking=0 ts=0x1F1D5C3C1F00 ref=123456789 side=B shares=100 stock=AAPL price=1501716
        m[0]="A"; m[1]=8'h00; m[2]=8'h07; m[3]=8'h00; m[4]=8'h00;
        m[5]=8'h1F; m[6]=8'h1D; m[7]=8'h5C; m[8]=8'h3C; m[9]=8'h1F; m[10]=8'h00;
        m[11]=0; m[12]=0; m[13]=0; m[14]=0; m[15]=8'h07; m[16]=8'h5B; m[17]=8'hCD; m[18]=8'h15;
        m[19]="B"; m[20]=0; m[21]=0; m[22]=0; m[23]=8'd100;
        m[24]="A"; m[25]="A"; m[26]="P"; m[27]="L"; m[28]=" "; m[29]=" "; m[30]=" "; m[31]=" ";
        m[32]=8'h00; m[33]=8'h16; m[34]=8'hEA; m[35]=8'h14;
        repeat (2) @(posedge clk); rst_n = 1; @(posedge clk);
        for (i = 0; i < 36; i = i + 1) begin byte_valid = 1; byte_in = m[i]; byte_last = (i == 35); @(posedge clk); end
        byte_valid = 0; byte_last = 0;
        // msg_valid is high for exactly the cycle after the last byte's edge: check immediately.
        if (msg_valid !== 1'b1)            begin $display("FAIL: msg_valid"); $finish; end
        if (!msg_known || !len_ok)         begin $display("FAIL: known=%b len_ok=%b", msg_known, len_ok); $finish; end
        if (msg_type !== "A")              begin $display("FAIL: type %h", msg_type); $finish; end
        if (locate !== 16'd7)              begin $display("FAIL: locate %0d", locate); $finish; end
        if (timestamp_ns !== 48'h1F1D5C3C1F00) begin $display("FAIL: ts %h", timestamp_ns); $finish; end
        if (order_ref !== 64'd123456789)   begin $display("FAIL: ref %0d", order_ref); $finish; end
        if (side !== "B")                  begin $display("FAIL: side"); $finish; end
        if (shares !== 32'd100)            begin $display("FAIL: shares %0d", shares); $finish; end
        if (stock !== 64'h4141504C20202020) begin $display("FAIL: stock %h", stock); $finish; end
        if (price !== 32'd1501716)         begin $display("FAIL: price %0d", price); $finish; end
        if (new_ref !== 0 || match_number !== 0 || printable !== 0 || attribution !== 0) begin $display("FAIL: unused fields not zero"); $finish; end
        $display("PASS: smoke test -- real-layout Add Order decoded correctly");
        $finish;
    end
endmodule
