if {[info script] ne ""} {
    cd [file join [file dirname [file normalize [info script]]] ..]
}
puts ">>> Working directory: [pwd]"

# ---------------- Configuration ----------------
set PY        "python3"           
set SRC       "src"
set PYDIR     "python"
set PHOTODIR  "photos"

set SRC_PNG   "$PHOTODIR/template_photo_low.png"
set OUT_PNG   "$PHOTODIR/photo_low_out.png"
set HEX_IN    "image.hex"         
set HEX_OUT   "image_out.hex"     

# 1. Path to the built-in BFM library
set BFM_VLIB  "$aldec/vlib/aldec_axi_bfm"
set TOP       "work.img_ram_tb"

# 2. Compile options: pointing to BFM headers (+incdir+)
set OPTS      "-work work +incdir+$SRC +incdir+$BFM_VLIB/hdl"

# ---------------- Preflight: Python + Pillow ----------------
if {[catch {exec $PY -c "import PIL"} out]} {
    puts "Missing Pillow (PIL) module for '$PY' interpreter."
    error "Pillow unavailable - aborting."
}

# ---------------- 1) PNG -> HEX ----------------
puts ">>> png2hex.py: $SRC_PNG -> $HEX_IN"
if {[catch {exec $PY $PYDIR/png2hex.py $SRC_PNG $HEX_IN} out]} {
    error "ERROR in png2hex.py: $out"
}
puts $out

if {![regexp {DIMS\s+(\d+)\s+(\d+)} $out -> IMG_W IMG_H]} {
    error "Failed to read dimensions from png2hex.py"
}
set NUM_PIXELS [expr {$IMG_W * $IMG_H}]
set bits 1
while {(1 << $bits) < $NUM_PIXELS} { incr bits }
set ADDR_W [expr {$bits + 2}]
puts ">>> Image ${IMG_W}x${IMG_H} = $NUM_PIXELS px  ->  ADDR_W=$ADDR_W"

# ---------------- 2) Working library ----------------
alib ./riviera_lib/work
adel -lib work -all
alib ./riviera_lib/work
set worklib work

# ---------------- 3) Project compilation -------
# Removed BFM source compilation. Compiling only custom RTL and TB.
alog -sv2k17 $OPTS $SRC/taxi_axi_if.sv
alog -sv2k17 $OPTS $SRC/taxi_axi_ram.sv
alog -sv2k17 $OPTS $SRC/axi4_master.sv
alog -sv2k17 $OPTS $SRC/img_ram_tb.sv

# ---------------- 4) Simulation -----------------
# 3. Linking precompiled BFM library via -L flag
set ASIM_OPTS "-relax +access +r -t ns +notimingchecks -L aldec_axi_bfm"
eval asim $ASIM_OPTS -gIMG_W=$IMG_W -gIMG_H=$IMG_H -gADDR_W=$ADDR_W $TOP -pli libAxiBfmPliRiv

run -all

# ---------------- 5) HEX -> PNG ----------------
puts ">>> hex2png.py: $HEX_OUT -> $OUT_PNG"
if {[catch {exec $PY $PYDIR/hex2png.py $HEX_OUT $IMG_W $OUT_PNG} out]} {
    quit -sim
    error "ERROR in hex2png.py: $out"
}
puts $out

quit -sim
puts ">>> Done. Result: $OUT_PNG"
