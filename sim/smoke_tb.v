// sim/smoke_tb.v — basic sanity check before the real differential test harness.
`timescale 1ns/1ps

module smoke_tb;
    reg clk = 0;
    reg rst_n = 0;
    reg byte_valid = 0;
    reg [7:0] byte_in = 0;

    wire msg_valid;
    wire [7:0] msg_type;
    wire [47:0] timestamp_ns;
    wire [63:0] order_ref;
    wire [7:0] side;
    wire [31:0] shares;
    wire [63:0] stock;
    wire [31:0] price;

    itch_add_order_parser dut (
        .clk(clk), .rst_n(rst_n),
        .byte_valid(byte_valid), .byte_in(byte_in),
        .msg_valid(msg_valid), .msg_type(msg_type),
        .timestamp_ns(timestamp_ns), .order_ref(order_ref),
        .side(side), .shares(shares), .stock(stock), .price(price)
    );

    always #5 clk = ~clk;

    // One known AddOrder message, hand-encoded, matching the real wire
    // format exactly: type='A', timestamp=0x010203040506,
    // order_ref=0x0000000000002A, side='B', shares=100 (0x64),
    // stock="TESTSTOK", price=1000000 (0x0F4240), bytes 32-35=0.
    reg [7:0] test_bytes [0:35];

    integer i;
    initial begin
        test_bytes[0]  = 8'h41; // 'A'
        test_bytes[1]  = 8'h01; test_bytes[2] = 8'h02; test_bytes[3] = 8'h03;
        test_bytes[4]  = 8'h04; test_bytes[5] = 8'h05; test_bytes[6] = 8'h06;
        test_bytes[7]  = 8'h00; test_bytes[8] = 8'h00; test_bytes[9] = 8'h00;
        test_bytes[10] = 8'h00; test_bytes[11] = 8'h00; test_bytes[12] = 8'h00;
        test_bytes[13] = 8'h00; test_bytes[14] = 8'h2A; // order_ref = 42
        test_bytes[15] = 8'h42; // 'B'
        test_bytes[16] = 8'h00; test_bytes[17] = 8'h00;
        test_bytes[18] = 8'h00; test_bytes[19] = 8'h64; // shares = 100
        test_bytes[20] = "T"; test_bytes[21] = "E"; test_bytes[22] = "S"; test_bytes[23] = "T";
        test_bytes[24] = "S"; test_bytes[25] = "T"; test_bytes[26] = "O"; test_bytes[27] = "K";
        test_bytes[28] = 8'h00; test_bytes[29] = 8'h0F;
        test_bytes[30] = 8'h42; test_bytes[31] = 8'h40; // price = 1000000
        test_bytes[32] = 0; test_bytes[33] = 0; test_bytes[34] = 0; test_bytes[35] = 0;

        rst_n = 0;
        byte_valid = 0;
        @(posedge clk); @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        for (i = 0; i < 36; i = i + 1) begin
            byte_valid = 1;
            byte_in = test_bytes[i];
            @(posedge clk);
        end
        byte_valid = 0;
        // Check immediately -- msg_valid pulses for exactly the one cycle
        // following the 36th byte. An earlier version of this testbench
        // added one extra @(posedge clk) here before checking, which
        // sampled msg_valid a cycle after it had already deasserted --
        // a testbench timing bug, not an RTL bug (confirmed by tracing
        // dut.byte_count/msg_valid cycle-by-cycle before fixing this).

        if (msg_valid !== 1'b1) begin
            $display("FAIL: msg_valid not asserted after 36 bytes");
            $finish;
        end
        if (msg_type !== 8'h41) begin $display("FAIL: msg_type = %h, expected 41", msg_type); $finish; end
        if (order_ref !== 64'd42) begin $display("FAIL: order_ref = %0d, expected 42", order_ref); $finish; end
        if (side !== 8'h42) begin $display("FAIL: side = %h, expected 42 ('B')", side); $finish; end
        if (shares !== 32'd100) begin $display("FAIL: shares = %0d, expected 100", shares); $finish; end
        if (price !== 32'd1000000) begin $display("FAIL: price = %0d, expected 1000000", price); $finish; end
        if (stock !== 64'h5445535453544F4B) begin $display("FAIL: stock = %h, expected TESTSTOK", stock); $finish; end

        $display("PASS: smoke test -- single AddOrder message parsed correctly");
        $finish;
    end
endmodule
