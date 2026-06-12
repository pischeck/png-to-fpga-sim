`timescale 1ns / 1ps

module img_ram_tb #(
    // Nadpisywane z run.do:  asim -gIMG_W=.. -gIMG_H=.. -gADDR_W=..
    parameter int IMG_W  = 16,            // szerokosc obrazu (px)
    parameter int IMG_H  = 16,            // wysokosc obrazu (px)
    parameter int ADDR_W = 16             // szerokosc adresu AXI; pojemnosc = 2**(ADDR_W-1) pikseli
);

    // ---------------- Konfiguracja szyny -----------------------------
    localparam int DATA_W    = 32;                // 1 piksel RGB888 = 1 slowo AXI
    localparam int ID_W      = 8;
    localparam int STRB_W    = DATA_W/8;          // = 2
    localparam int MAX_BEATS = 256;               // AWLEN/ARLEN max -> 256 beatow/burst
    localparam int NUM_PIXELS = IMG_W * IMG_H;    // = liczba linii w pliku .hex

    localparam string HEX_IN  = "image.hex";      // wejscie (z png2hex.py)
    localparam string HEX_OUT = "image_out.hex";  // wyjscie (do hex2png.py)

    // ---------------- Zegar i reset ----------------------------------
    bit clk = 0;
    always #5 clk = ~clk;        // 100 MHz

    bit rst = 1;                 // taxi: reset aktywny w stanie wysokim
    initial begin
        repeat (10) @(posedge clk);
        rst = 0;
    end

    // ---------------- Interfejs AXI4 (taxi) --------------------------
    // Jedna instancja interfejsu; do RAM podajemy modporty wr_slv/rd_slv.
    taxi_axi_if #(
        .DATA_W (DATA_W),
        .ADDR_W (ADDR_W),
        .ID_W   (ID_W)
    ) axi_if ();

    // ---------------- DUT: pamiec taxi_axi_ram -----------------------
    taxi_axi_ram #(
        .ADDR_W          (ADDR_W),
        .PIPELINE_OUTPUT (1'b0)
    ) u_ram (
        .clk      (clk),
        .rst      (rst),
        .s_axi_wr (axi_if),      // modport wr_slv
        .s_axi_rd (axi_if)       // modport rd_slv
    );

    // ---------------- Master BFM AXI4 (Aldec) ------------------------
    // Porty wrappera laczymy bezposrednio z sygnalami interfejsu po nazwie.
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

    // ---------------- Bufory obrazu ----------------------------------
    logic [DATA_W-1:0] img_data  [0:NUM_PIXELS-1];   // obraz zrodlowy (referencja, z HEX_IN)
    logic [DATA_W-1:0] read_back [0:NUM_PIXELS-1];   // obraz odczytany po AXI

    // ---------------- Scenariusz testu -------------------------------
    initial begin : main
        int                remaining, beats, word_idx, k, i;
        int                err;
        logic [ADDR_W-1:0] byte_addr;
        logic [DATA_W-1:0] wr_chunk [0:MAX_BEATS-1];

        err = 0;

        // 1) Wczytaj obraz zrodlowy do bufora TB (referencja do porownan).
        $readmemh(HEX_IN, img_data);
        $display("[%0t] Wczytano '%s' (%0d pikseli) do bufora TB", $time, HEX_IN, NUM_PIXELS);

        // Poczekaj na koniec resetu
        wait (rst == 0);
        repeat (4) @(posedge clk);

        // 2) ZAPIS calego obrazu po AXI4, burstami po max MAX_BEATS.
        word_idx  = 0;
        remaining = NUM_PIXELS;
        while (remaining > 0) begin
            beats     = (remaining > MAX_BEATS) ? MAX_BEATS : remaining;
            byte_addr = ADDR_W'(word_idx * STRB_W);   // adres bajtowy slowa startowego
            for (k = 0; k < beats; k++)
                wr_chunk[k] = img_data[word_idx + k];

            m_axi.write_burst(byte_addr, beats, wr_chunk);

            word_idx  += beats;
            remaining -= beats;
        end
        $display("[%0t] Zapisano %0d pikseli po AXI4 (kanal AW/W/B)", $time, NUM_PIXELS);

        // 2a) Kontrola SCIEZKI ZAPISU (backdoor do mem): izoluje blad zapisu od odczytu.
        for (i = 0; i < NUM_PIXELS; i++)
            if (u_ram.mem[i] !== img_data[i]) begin
                $error("ZAPIS: niezgodnosc na pikselu %0d: mem=%h oczek=%h", i, u_ram.mem[i], img_data[i]);
                err++;
            end

        // 3) ODCZYT calego obrazu po AXI4, burstami po max MAX_BEATS.
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
        $display("[%0t] Odczytano %0d pikseli po AXI4 (kanal AR/R)", $time, NUM_PIXELS);

        // 3a) Kontrola SCIEZKI ODCZYTU: odczyt po AXI vs obraz zrodlowy.
        for (i = 0; i < NUM_PIXELS; i++)
            if (read_back[i] !== img_data[i]) begin
                $error("ODCZYT: niezgodnosc na pikselu %0d: AXI=%h oczek=%h", i, read_back[i], img_data[i]);
                err++;
            end

        // 4) Zrzut odczytanych danych do .hex (4 cyfry hex/linia -> zgodne z hex2png.py)
        $writememh(HEX_OUT, read_back);
        $display("[%0t] Zapisano '%s'", $time, HEX_OUT);

        if (err == 0)
            $display("[%0t] WYNIK: PASS - pelna petla AXI zapis->odczyt zgodna (%0d px)", $time, NUM_PIXELS);
        else
            $display("[%0t] WYNIK: FAIL - %0d niezgodnosci", $time, err);

        #50 $stop;
    end

endmodule