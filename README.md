# wb_riscvscale
This is a wishbone compliant RISCV Vscale core intended to run part of FuseSoC project with other (open)cores.

Details/Status

The files are copied from vscale repo [1] and modified to get rid of the nasti/hasti/htif interface. A new wb_vscale.v is added to wrap a slightly modified vscale_pipline.v file. Now the core can run a bare-metal elf-loaded riscv32 hello world program part of FuseSoC on Icarus simulator. The SoC currently contains UART and generic bfm RAM cores. The RAM core is used for both code and data.

On FPGA (Atlys board), the FuseSoC that contains: riscv/vscale, bootrom, UART, GPIO and ddr2 now initially work. 

[1] https://github.com/ucb-bar/vscale

