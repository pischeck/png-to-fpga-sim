transcript file sim.txt

if {[info script] ne ""} {
    cd [file join [file dirname [file normalize [info script]]] ..]
}
puts ">>> Katalog roboczy: [pwd]"

# ---------------- Konfiguracja ----------------
set PY        "python3"           
set SRC       "src"
set PYDIR     "python"
set PHOTODIR  "photos"

set SRC_PNG   "$PHOTODIR/obrazek.png"
set OUT_PNG   "$PHOTODIR/obrazek_out.png"
set HEX_IN    "image.hex"         ;# = HEX_IN  w img_ram_tb.sv (w korzeniu projektu)
set HEX_OUT   "image_out.hex"     ;# = HEX_OUT w img_ram_tb.sv
# IMG_W / IMG_H / ADDR_W wyliczane automatycznie z wyjscia png2hex.py (ponizej)

# ---------------- BFM -------------------------
set ALDEC_DIR "$::env(HOME)/Aldec"
set BFM_DIRS [glob -nocomplain -directory $ALDEC_DIR BFM_AMBA_AXI.*]
if {[llength $BFM_DIRS] == 0} {
    error "Nie znaleziono paczki BFM w katalogu $ALDEC_DIR"
}
set BFM_HOME [lindex [lsort -decreasing $BFM_DIRS] 0]
puts ">>> Znaleziono katalog BFM: $BFM_HOME"


set TOP       "work.img_ram_tb"
set OPTS      "-work work +incdir+$SRC +incdir+$BFM_HOME/hdl/aldec_cores/common"

# ---------------- Preflight: Python + Pillow ----------------
if {[catch {exec $PY -c "import PIL"} out]} {
    puts "Brak modulu Pillow (PIL) dla interpretera '$PY'."
    puts "  Instalacja:  $PY -m pip install --user pillow"
    puts "  lub ustaw 'set PY' na interpreter z Pillow (np. z venv)."
    error "Pillow niedostepny - przerywam run.do."
}

# ---------------- 1) PNG -> HEX ----------------
puts ">>> png2hex.py: $SRC_PNG -> $HEX_IN"
if {[catch {exec $PY $PYDIR/png2hex.py $SRC_PNG $HEX_IN} out]} {
    puts "BLAD png2hex.py:\n$out"
    error "png2hex.py nie powiodlo sie - przerywam run.do."
}
puts $out

# Odczytaj rozdzielczosc z MASZYNOWEJ linii "DIMS <W> <H>" 
if {![regexp {DIMS\s+(\d+)\s+(\d+)} $out -> IMG_W IMG_H]} {
    error "Nie udalo sie odczytac wymiarow (oczekiwana linia 'DIMS W H') z png2hex.py - sprawdz wydruk."
}
set NUM_PIXELS [expr {$IMG_W * $IMG_H}]
# ADDR_W = ceil(log2(NUM_PIXELS)) + clog2(STRB_W); STRB_W=4 (32-bit) -> +2
set bits 1
while {(1 << $bits) < $NUM_PIXELS} { incr bits }
set ADDR_W [expr {$bits + 2}]
puts ">>> Obraz ${IMG_W}x${IMG_H} = $NUM_PIXELS px  ->  ADDR_W=$ADDR_W (pojemnosc [expr {1 << ($ADDR_W-1)}] px)"

# ---------------- 2) Biblioteka ----------------
alib ./riviera_lib/work
adel -lib work -all
alib ./riviera_lib/work
set worklib work

# ---------------- 3) Kompilacja BFM Aldec ------
alog -v2005 -work work -F $BFM_HOME/hdl/filelists/filelist_v.f

# ---------------- 4) Kompilacja projektu -------
# Kolejnosc: interfejs -> modul -> wrapper BFM -> TB
alog -sv2k17 $OPTS $SRC/taxi_axi_if.sv
alog -sv2k17 $OPTS $SRC/taxi_axi_ram.sv
alog -sv2k17 $OPTS $SRC/axi4_master.sv
alog -sv2k17 $OPTS $SRC/img_ram_tb.sv

# ---------------- 5) Symulacja -----------------
# TB konczy przez $stop -> run -all zwraca sterowanie do skryptu.
# Wymiary i ADDR_W przekazujemy jako parametry top-poziomu (-g).
set ASIM_OPTS "-relax +access +r -t ns +notimingchecks"
eval asim $ASIM_OPTS -gIMG_W=$IMG_W -gIMG_H=$IMG_H -gADDR_W=$ADDR_W $TOP -pli libAxiBfmPliRiv


run -all

# ---------------- 6) HEX -> PNG ----------------
puts ">>> hex2png.py: $HEX_OUT -> $OUT_PNG (szerokosc $IMG_W)"
if {[catch {exec $PY $PYDIR/hex2png.py $HEX_OUT $IMG_W $OUT_PNG} out]} {
    puts "BLAD hex2png.py:\n$out"
    quit -sim
    error "hex2png.py nie powiodlo sie."
}
puts $out

quit -sim
puts ">>> Gotowe. Wynik: $OUT_PNG"