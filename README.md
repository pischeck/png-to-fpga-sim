# FPGA Image Processing Flow via AXI4

## Project Description
This project demonstrates a complete, end-to-end image processing data flow through an FPGA verification environment. It starts with converting a standard PNG image into a flat hexadecimal memory dump, routing it through an AXI4 memory architecture, and reconstructing the output back into a PNG file to visually verify data integrity at the pixel level.

At its core, this is a verification environment for the `taxi_axi_ram` hardware memory module. The architecture utilizes the AXI4 bus for image data transfer (both write and read operations using BURST transactions). The verification process is driven by the Aldec Bus Functional Model (BFM). Automated Python scripts are integrated into the flow to process image files into Verilog `$readmemh` compatible formats, allowing the testbench to operate on realistic data sets.

## Architecture
* **`taxi_axi_ram.sv`**: The target memory module connected to a standard AXI4 Slave interface. It handles the state machines for write, read, and response phases.
* **`axi4_master.sv`**: A hardware wrapper that instantiates the protected `Ax_Axi4MasterBFM` core provided by Aldec. It implements specific SystemVerilog tasks to handle AXI4 `INCR` transfers.
* **`taxi_axi_if.sv`**: A unified SystemVerilog interface carrying all AXI channels (AW, W, B, AR, R) with strictly defined modports for both master and slave endpoints.
* **`img_ram_tb.sv`**: The main testbench driving the execution. It handles bus payload loading, "on-the-fly" verification via backdoor access (directly checking internal `mem` arrays), and dumping the final output data.

## Directory Structure
* `src/` – Source code (interfaces, RTL, and the test environment).
* `python/` – Scripts for format conversion and data extraction: `png2hex.py`, `hex2png.py`.
* `photos/` – Reference input images and generated output `.png` files.

## Simulation Flow
The entire verification loop is automated via the `run.do` (TCL) script, executing the following steps:
1.  **Payload Generation**: Execution of `png2hex.py`, which converts the source `obrazek.png` into a flat text file `image.hex`. It automatically calculates and maps the required address width (`ADDR_W`) based on the image dimensions.
2.  **Compilation & Library Linking**: Linking the precompiled Aldec BFM library (`aldec_axi_bfm`) directly from the Riviera-PRO installation directory, followed by the compilation of custom RTL and testbench files.
3.  **Transactions & Verification**:
    * The testbench initiates a write burst, streaming the `image.hex` payload over the AXI4 bus into the RAM structure.
    * Backdoor write path verification inside the memory array.
    * The testbench initiates a read burst across the address space, verifying full data compliance between the AXI bus output and the reference image array.
    * The verified data is dumped to `image_out.hex` using the `$writememh` system task.
4.  **Image Reconstruction**: Execution of `hex2png.py` to generate the final PNG image from the verified data bus dump.

## Debugging
* **Bus Data Integrity**: Any data misalignments or dropped transfers on the bus are reported directly to the simulator console via `$error` macros. The logs pinpoint the exact pixel index of the faulty transfer (highlighting mismatches between `read_back` and `img_data`).