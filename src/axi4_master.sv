`timescale 1ns / 1ps

module axi4_master #(
    parameter int DATA_W    = 32,           // szerokosc danych AXI w BITACH (1 piksel RGB888)
    parameter int ADDR_W    = 16,           // szerokosc adresu
    parameter int ID_W      = 8,            // szerokosc ID
    parameter int STRB_W    = DATA_W/8,     // = 2 dla 32-bit (4 bajty)
    parameter int MAX_BEATS = 256           // ARLEN max -> 256 beatow/burst
)
(
    input  wire                 ACLK,
    input  wire                 ARESETn,

    // --- Write address channel ---
    output wire [ID_W-1:0]      AWID,
    output wire [ADDR_W-1:0]    AWADDR,
    output wire [3:0]           AWREGION,
    output wire [7:0]           AWLEN,
    output wire [2:0]           AWSIZE,
    output wire [1:0]           AWBURST,
    output wire                 AWLOCK,
    output wire [3:0]           AWCACHE,
    output wire [2:0]           AWPROT,
    output wire [3:0]           AWQOS,
    output wire                 AWVALID,
    input  wire                 AWREADY,

    // --- Write data channel ---
    output wire [DATA_W-1:0]    WDATA,
    output wire [STRB_W-1:0]    WSTRB,
    output wire                 WLAST,
    output wire                 WVALID,
    input  wire                 WREADY,

    // --- Write response channel ---
    input  wire [ID_W-1:0]      BID,
    input  wire [1:0]           BRESP,
    input  wire                 BVALID,
    output wire                 BREADY,

    // --- Read address channel ---
    output wire [ID_W-1:0]      ARID,
    output wire [ADDR_W-1:0]    ARADDR,
    output wire [3:0]           ARREGION,
    output wire [7:0]           ARLEN,
    output wire [2:0]           ARSIZE,
    output wire [1:0]           ARBURST,
    output wire                 ARLOCK,
    output wire [3:0]           ARCACHE,
    output wire [2:0]           ARPROT,
    output wire [3:0]           ARQOS,
    output wire                 ARVALID,
    input  wire                 ARREADY,

    // --- Read data channel ---
    input  wire [ID_W-1:0]      RID,
    input  wire [DATA_W-1:0]    RDATA,
    input  wire [1:0]           RRESP,
    input  wire                 RLAST,
    input  wire                 RVALID,
    output wire                 RREADY
);

    // -----------------------------------------------------------------
    //  Instancja BFM mastera AXI4 (Aldec). Porty wg UP.v.
    //  DATA_BUS_WIDTH = szerokosc szyny w BITACH.
    //  Porty *USER (AWUSER/WUSER/BUSER/ARUSER/RUSER) zostawiamy
    //  niepodlaczone - obraz ich nie uzywa.
    // -----------------------------------------------------------------
    Ax_Axi4MasterBFM #(
        .DATA_BUS_WIDTH (DATA_W),
        .ADDRESS_WIDTH  (ADDR_W),
        .ID_WIDTH       (ID_W)
    ) bfm (
        .ACLK     (ACLK),
        .ARESETn  (ARESETn),
        .AWID     (AWID),      .AWADDR   (AWADDR),   .AWREGION (AWREGION),
        .AWLEN    (AWLEN),     .AWSIZE   (AWSIZE),   .AWBURST  (AWBURST),
        .AWLOCK   (AWLOCK),    .AWCACHE  (AWCACHE),  .AWPROT   (AWPROT),
        .AWQOS    (AWQOS),     .AWVALID  (AWVALID),  .AWREADY  (AWREADY),
        .WDATA    (WDATA),     .WSTRB    (WSTRB),    .WLAST    (WLAST),
        .WVALID   (WVALID),    .WREADY   (WREADY),
        .BID      (BID),       .BRESP    (BRESP),    .BVALID   (BVALID),  .BREADY (BREADY),
        .ARID     (ARID),      .ARADDR   (ARADDR),   .ARREGION (ARREGION),
        .ARLEN    (ARLEN),     .ARSIZE   (ARSIZE),   .ARBURST  (ARBURST),
        .ARLOCK   (ARLOCK),    .ARCACHE  (ARCACHE),  .ARPROT   (ARPROT),
        .ARQOS    (ARQOS),     .ARVALID  (ARVALID),  .ARREADY  (ARREADY),
        .RID      (RID),       .RDATA    (RDATA),    .RRESP    (RRESP),
        .RLAST    (RLAST),     .RVALID   (RVALID),   .RREADY   (RREADY)
    );

    // Stale AXI4
    localparam [1:0] BURST_INCR = 2'b01;
    localparam [2:0] BEAT_SIZE  = 3'($clog2(STRB_W));   // 1 dla 16-bit (2 bajty)

    // Bufor wynikow ostatniego odczytu (TB czyta z niego po read_burst)
    logic [DATA_W-1:0] rbuf [0:MAX_BEATS-1];

    // -----------------------------------------------------------------
    //  read_burst: jeden burst AXI4 INCR.
    //   start_addr - adres BAJTOWY pierwszego slowa
    //   beats      - liczba slow (1..MAX_BEATS)
    //  Wynik -> rbuf[0 .. beats-1].
    // -----------------------------------------------------------------
    task automatic read_burst (
        input [ADDR_W-1:0] start_addr,
        input int          beats
    );
        logic [ID_W-1:0]   rid;
        logic [1:0]        rresp;
        logic [DATA_W-1:0] rdata;
        logic              rlast;
        logic [0:0]        ruser;
        int                k;
        begin
            // Faza adresu (pozycyjnie, kolejnosc wg TB_mst.v):
            // arid, araddr, arregion, arlen, arsize, arburst, arlock, arcache, arprot, arqos, aruser
            bfm.BfmReadAddress(
                '0,            // arid
                start_addr,    // araddr (bajtowy)
                4'h0,          // arregion
                8'(beats-1),   // arlen
                BEAT_SIZE,     // arsize
                BURST_INCR,    // arburst
                1'b0,          // arlock
                4'h0,          // arcache
                3'h0,          // arprot
                4'h0,          // arqos
                1'b0           // aruser
            );
            // Faza danych: ARLEN+1 odebran. Wyjscia: rid, rresp, rdata, rlast, ruser
            for (k = 0; k < beats; k++) begin
                bfm.BfmWaitForReadResponse(rid, rresp, rdata, rlast, ruser);
                rbuf[k] = rdata;
            end
        end
    endtask

    // -----------------------------------------------------------------
    //  write_burst: jeden burst zapisu AXI4 INCR (opcjonalny - ladowanie
    //  obrazu robimy przez $readmemh; zostawiam do testu sciezki zapisu).
    // -----------------------------------------------------------------
    task automatic write_burst (
        input [ADDR_W-1:0] start_addr,
        input int          beats,
        ref   [DATA_W-1:0] wdata_arr [0:MAX_BEATS-1]
    );
        logic [ID_W-1:0] bid;
        logic [1:0]      bresp;
        logic [0:0]      buser;
        int              k;
        begin
            // awid, awaddr, awregion, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awuser
            bfm.BfmWriteAddress(
                '0,            // awid
                start_addr,    // awaddr
                4'h0,          // awregion
                8'(beats-1),   // awlen
                BEAT_SIZE,     // awsize
                BURST_INCR,    // awburst
                1'b0,          // awlock
                4'h0,          // awcache
                3'h0,          // awprot
                4'h0,          // awqos
                1'b0           // awuser
            );
            // wdata, wstrb, wlast, wuser
            for (k = 0; k < beats; k++) begin
                bfm.BfmWriteData(wdata_arr[k], {STRB_W{1'b1}}, (k == beats-1), 1'b0);
            end
            // bid, bresp, buser (wyjscia)
            bfm.BfmWaitForWriteResponse(bid, bresp, buser);
        end
    endtask

endmodule