`timescale 1ns / 1ps

module img_ram_tb #(
    // Overwritten by run.do:  asim -gIMG_W=.. -gIMG_H=.. -gADDR_W=..
    parameter int IMG_W  = 16,            // Image width (px)
    parameter int IMG_H  = 16,            // Image height (px)
    parameter int ADDR_W = 16             // AXI address width; capacity = 2**(ADDR_W-1) pixels
);

    // ---------------- Bus Configuration ------------------------------
    localparam int DATA_W    = 32;                // 1 RGB888 pixel = 1 AXI word
    localparam int ID_W      = 8;
    localparam int STRB_W    = DATA_W/8;          // = 4
    localparam int MAX_BEATS = 256;               // Max AWLEN/ARLEN -> 256 beats/burst
    localparam int NUM_PIXELS = IMG_W * IMG_H;    // = number of lines in .hex file

    localparam string HEX_IN  = "image.hex";      // input (from png2hex.py)
    localparam string HEX_OUT = "image_out.hex";  // output (to hex2png.py)

    // ---------------- Clock and Reset --------------------------------
    bit clk = 0;
    always #5 clk = ~clk;        // 100 MHz

    bit rst = 1;                 // taxi: active-high reset
    initial begin
        repeat (10) @(posedge clk);
        rst = 0;
    end

    // ---------------- AXI4 Interface (taxi) --------------------------
    // Single interface instance; wr_slv/rd_slv modports connected to RAM.
    taxi_axi_if #(
        .DATA_W (DATA_W),
        .ADDR_W (ADDR_W),
        .ID_W   (ID_W)
    ) axi_if ();

    // ---------------- DUT: taxi_axi_ram memory -----------------------
    taxi_axi_ram #(
        .ADDR_W          (ADDR_W),
        .PIPELINE_OUTPUT (1'b0)
    ) u_ram (
        .clk      (clk),
        .rst      (rst),
        .s_axi_wr (axi_if),      // modport wr_slv
        .s_axi_rd (axi_if)       // modport rd_slv
    );

    // ---------------- AXI4 Master BFM (Aldec) ------------------------
    // Wrapper ports are connected directly to interface signals by name.
    axi4_master #(
        .DATA_W (DATA_W),
        .ADDR_W (ADDR_W),
        .ID_W   (ID_W)
    ) m_axi (
        .ACLK     (clk),
        .ARESETn  (~rst),

        .AWID     (axi_if.awid),     .AWADDR  (axi_if.awaddr),  .AWLEN   (axi_if.awlen),
        .AWSIZE   (axi_if.awsize),   .AWBURST (axi_if.awburst), .AWLOCK  (axi_if.awlock),
        .AWCACHE  (axi_if.awcache),  .AWPROT  (axi_if.awprot),  .AWQOS   (axi_if.awqos),
        .AWREGION (axi_if.awregion), .AWVALID (axi_if.awvalid), .AWREADY (axi_if.awready),

        .WDATA    (axi_if.wdata),    .WSTRB   (axi_if.wstrb),   .WLAST   (axi_if.wlast),
        .WVALID   (axi_if.wvalid),   .WREADY  (axi_if.wready),

        .BID      (axi_if.bid),      .BRESP   (axi_if.bresp),   .BVALID  (axi_if.bvalid),
        .BREADY   (axi_if.bready),

        .ARID     (axi_if.arid),     .ARADDR  (axi_if.araddr),  .ARLEN   (axi_if.arlen),
        .ARSIZE   (axi_if.arsize),   .ARBURST (axi_if.arburst), .ARLOCK  (axi_if.arlock),
        .ARCACHE  (axi_if.arcache),  .ARPROT  (axi_if.arprot),  .ARQOS   (axi_if.arqos),
        .ARREGION (axi_if.arregion), .ARVALID (axi_if.arvalid), .ARREADY (axi_if.arready),

        .RID      (axi_if.rid),      .RDATA   (axi_if.rdata),   .RRESP   (axi_if.rresp),
        .RLAST    (axi_if.rlast),    .RVALID  (axi_if.rvalid),  .RREADY  (axi_if.rready)
    );

    // ---------------- Image Buffers ----------------------------------
    logic [DATA_W-1:0] img_data  [0:NUM_PIXELS-1];   // source image (reference, from HEX_IN)
    logic [DATA_W-1:0] read_back [0:NUM_PIXELS-1];   // image read via AXI

    // ---------------- Test Scenario ----------------------------------
    initial begin : main
        int                remaining, beats, word_idx, k, i;
        int                err;
        logic [ADDR_W-1:0] byte_addr;
        logic [DATA_W-1:0] wr_chunk [0:MAX_BEATS-1];

        err = 0;

        // 1) Load source image into TB buffer (reference for comparisons).
        $readmemh(HEX_IN, img_data);
        $display("[%0t] Loaded '%s' (%0d pixels) into TB buffer", $time, HEX_IN, NUM_PIXELS);

        // Wait for reset to deassert
        wait (rst == 0);
        repeat (4) @(posedge clk);

        // 2) WRITE the entire image via AXI4, using bursts up to MAX_BEATS.
        word_idx  = 0;
        remaining = NUM_PIXELS;
        while (remaining > 0) begin
            beats     = (remaining > MAX_BEATS) ? MAX_BEATS : remaining;
            byte_addr = ADDR_W'(word_idx * STRB_W);   // byte address of the starting word
            for (k = 0; k < beats; k++)
                wr_chunk[k] = img_data[word_idx + k];

            m_axi.write_burst(byte_addr, beats, wr_chunk);

            word_idx  += beats;
            remaining -= beats;
        end
        $display("[%0t] Written %0d pixels via AXI4 (AW/W/B channels)", $time, NUM_PIXELS);

        // 2a) WRITE PATH check (backdoor to mem): isolates write errors from read errors.
        for (i = 0; i < NUM_PIXELS; i++)
            if (u_ram.mem[i] !== img_data[i]) begin
                $error("WRITE: mismatch at pixel %0d: mem=%h expected=%h", i, u_ram.mem[i], img_data[i]);
                err++;
            end

        // 3) READ the entire image via AXI4, using bursts up to MAX_BEATS.
        word_idx  = 0;
        remaining = NUM_PIXELS;
        while (remaining > 0) begin
            beats     = (remaining > MAX_BEATS) ? MAX_BEATS : remaining;
            byte_addr = ADDR_W'(word_idx * STRB_W);

            m_axi.read_burst(byte_addr, beats);

            for (k = 0; k < beats; k++)
                read_back[word_idx + k] = m_axi.rbuf[k];

            word_idx  += beats;
            remaining -= beats;
        end
        $display("[%0t] Read %0d pixels via AXI4 (AR/R channels)", $time, NUM_PIXELS);

        // 3a) READ PATH check: AXI read vs source image.
        for (i = 0; i < NUM_PIXELS; i++)
            if (read_back[i] !== img_data[i]) begin
                $error("READ: mismatch at pixel %0d: AXI=%h expected=%h", i, read_back[i], img_data[i]);
                err++;
            end

        // 4) Dump read data to .hex (4 hex digits/line -> compatible with hex2png.py)
        $writememh(HEX_OUT, read_back);
        $display("[%0t] Saved '%s'", $time, HEX_OUT);

        if (err == 0)
            $display("[%0t] RESULT: PASS - full AXI write->read loop matches (%0d px)", $time, NUM_PIXELS);
        else
            $display("[%0t] RESULT: FAIL - %0d mismatches", $time, err);

        #50 $stop;
    end

endmodule