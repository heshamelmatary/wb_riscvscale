//////////////////////////////////////////////////////////////////
//                                                              //
//  Wishbone wrapper for vscale/riscv core                      //
//                                                              //
//                                                              //
//  Description                                                 //
//  This file wraps the vscale/riscv core to work with the      //
//  existing opencores/openrisc cores and ecosystem.            //
//                                                              //
//  Author(s):                                                  //
//      - Hesham Almatary,  heshamelmatary@gmail.com            //
//                                                              //
//////////////////////////////////////////////////////////////////
//                                                              //
// Copyright (C) 2015 Authors and OPENCORES.ORG                 //
//                                                              //
// This source file may be used and distributed without         //
// restriction provided that this copyright statement is not    //
// removed from the file and that any derivative work contains  //
// the original copyright notice and the associated disclaimer. //
//                                                              //
// This source file is free software; you can redistribute it   //
// and/or modify it under the terms of the GNU Lesser General   //
// Public License as published by the Free Software Foundation; //
// either version 2.1 of the License, or (at your option) any   //
// later version.                                               //
//                                                              //
// This source is distributed in the hope that it will be       //
// useful, but WITHOUT ANY WARRANTY; without even the implied   //
// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      //
// PURPOSE.  See the GNU Lesser General Public License for more //
// details.                                                     //
//                                                              //
// You should have received a copy of the GNU Lesser General    //
// Public License along with this source; if not, download it   //
// from http://www.opencores.org/lgpl.shtml                     //
//                                                              //
//////////////////////////////////////////////////////////////////
`include "vscale_ctrl_constants.vh"
`include "vscale_alu_ops.vh"
`include "rv32_opcodes.vh"
`include "vscale_csr_addr_map.vh"
`include "vscale_md_constants.vh"
module wb_vscale (
    input 			      clk,
    input 			      rst,

    // Wishbone interface
    output [31:0] 		      iwbm_adr_o,
    output 			      iwbm_stb_o,
    output 			      iwbm_cyc_o,
    output [3:0] 		      iwbm_sel_o,
    output 			      iwbm_we_o,
    output [2:0] 		      iwbm_cti_o,
    output [1:0] 		      iwbm_bte_o,
    output [31:0] 		      iwbm_dat_o,
    input 			      iwbm_err_i,
    input 			      iwbm_ack_i,
    input [31:0] 		      iwbm_dat_i,
    input 			      iwbm_rty_i,

    output [31:0] 		      dwbm_adr_o,
    output 			      dwbm_stb_o,
    output 			      dwbm_cyc_o,
    output [3:0] 		      dwbm_sel_o,
    output 			      dwbm_we_o,
    output [2:0] 		      dwbm_cti_o,
    output [1:0] 		      dwbm_bte_o,
    output [31:0] 		      dwbm_dat_o,
    input 			      dwbm_err_i,
    input 			      dwbm_ack_i,
    input [31:0] 		      dwbm_dat_i,
    input 			      dwbm_rty_i
);

wire dmem_request;
wire dmem_we;
wire[31:0] dmem_addr;
wire[31:0] data_wire;
wire[2:0]  dmem_size;
wire[31:0] pc;
wire replay_IF_out;

reg iwbm_riscv_cyc = 0;
reg iwbm_riscv_stb = 0;
reg[31:0] instruction = 0;
reg[31:0] iwbm_riscv_adr = 0;

reg dwbm_riscv_cyc = 0;
reg dwbm_riscv_stb = 0;
reg[2:0] dwbm_riscv_cti = 7;
reg[1:0] dwbm_riscv_bte = 2;
reg[3:0] dwbm_riscv_sel = 4'hF;
reg[31:0] dwbm_riscv_dat = 0;

reg dwbm_riscv_we = 0;
reg[31:0] mem_read_value = 0;
reg[31:0] dwbm_riscv_adr = 0;
reg[2:0] state = 0;
reg[2:0] dstate = 0;
reg[31:0] ddata = 0;

reg dmem_wait = 0;
reg imem_wait = 1;
reg previous_dmem_access = 0;
reg[1:0] kill_wishbone_ireq = 0;
reg cpu_start = 0;

assign iwbm_stb_o = iwbm_riscv_stb;
assign iwbm_cyc_o = iwbm_riscv_cyc;
assign iwbm_cti_o = 0;
assign iwbm_bte_o = 0;
assign iwbm_sel_o = 4'hf;
assign iwbm_we_o = 0;
assign iwbm_adr_o = iwbm_riscv_adr;

assign dwbm_stb_o = dwbm_riscv_stb;
assign dwbm_cyc_o = dwbm_riscv_cyc;
assign dwbm_cti_o = dwbm_riscv_cti;
assign dwbm_bte_o = dwbm_riscv_bte;
assign dwbm_sel_o = dwbm_riscv_sel;
assign dwbm_we_o = dwbm_riscv_we;
assign dwbm_adr_o = dwbm_riscv_adr;

always @(posedge clk)
begin
  if(rst)
	begin
     state <= 3;
   	 instruction <= 0;
  	 iwbm_riscv_adr <= 0;
	   kill_wishbone_ireq <= 0;
     imem_wait <= 1;
	end
  /* initalize */
  if(state == 3)
  begin
         iwbm_riscv_adr <= 32'hf0000000;
         iwbm_riscv_cyc <= 1;
         iwbm_riscv_stb <= 1;
         state <= 2;
  end

    case (state)
    1: begin
         iwbm_riscv_adr <= (kill_wishbone_ireq)? pc - 4 : pc;
         iwbm_riscv_cyc <= 1;
         iwbm_riscv_stb <= 1;
         state <= 2;
         imem_wait <= 1;
//         kill_wishbone_ireq <= (kill_wishbone_ireq[0])? 2 : 0; 
       end
    2: begin
        
          /* Kill wb imem request if jal(r)/branch taken. Avoid reset case */
         if(replay_IF_out && !rst && iwbm_riscv_adr != 32'hf0000000)
         begin
           iwbm_riscv_adr <= pc;
           instruction <= iwbm_dat_i;
           iwbm_riscv_cyc <= 0;
           iwbm_riscv_stb <= 0;
           kill_wishbone_ireq <= 1;
           state <= 1;
           imem_wait <= 1;
         end

         if((iwbm_ack_i) && !replay_IF_out) /*|| kill_wishbone_ireq == 2*/
         begin
           instruction <= iwbm_dat_i;
           kill_wishbone_ireq <= 0;
           iwbm_riscv_cyc <= 0;
           iwbm_riscv_stb <= 0;
           state <=1;
           imem_wait <= 0;
         end
       end
    endcase 
 
end // always

always @(posedge clk)
begin
  if(rst)
	begin
      dstate <= 1;
      dwbm_riscv_we <= 0;
      dwbm_riscv_cyc <= 0;
      dwbm_riscv_stb <= 0;
      dwbm_riscv_cti <= 7;
      dwbm_riscv_bte <= 2;
      dwbm_riscv_sel <= 4'hF;
      mem_read_value <= 0;
      dwbm_riscv_adr <= 0;
      dmem_wait <= 0;
	end
    /* Mem Write Operation */
    if((dmem_request && dmem_we) || (dstate == 2 && dwbm_riscv_we))
    begin
      case(dstate)
        1: begin
          dwbm_riscv_adr <= dmem_addr;
          dwbm_riscv_we  <= dmem_we;
          //dwbm_riscv_sel  <= (dmem_size == 0)? 4'h8 : (dmem_size == 1)? 4'hC : (dmem_size == 2)? 4'hF : 4'hF;
					dwbm_riscv_sel  <= (dmem_size == 0)? (1 << dmem_addr[1:0]) : (dmem_size == 1)? 4'h3 : (dmem_size == 2)? 4'hF : 4'hF;
          //dwbm_riscv_sel  <= (dmem_size == 0)? 4'h1 : (dmem_size == 1)? 4'h3 : (dmem_size == 2)? 4'hF : 4'hF;
          dwbm_riscv_cyc <= 1;
          dwbm_riscv_stb <= 1;
          dmem_wait <= 1;
          dstate <=2;
        end
        2: begin
          if(dwbm_ack_i)
          begin
            dwbm_riscv_cyc <= 0;
            dwbm_riscv_stb <= 0;
            dwbm_riscv_we <= 0;
            dmem_wait <= 0;
            dstate <= 1;
          end
        end
    endcase
    end
    
    /* Mem Read Operation */
    if((dmem_request && !dmem_we) || (dstate == 2 && !dwbm_riscv_we) || dstate == 3)
    begin
    case(dstate)
        1: begin
            dwbm_riscv_adr <= dmem_addr;
            dwbm_riscv_stb <= 1;
            dwbm_riscv_cyc <= 1;
            dmem_wait <= 1;
            //dwbm_riscv_sel  <= (dmem_size == 0)? 4'h8 : (dmem_size == 1)? 4'hC : (dmem_size == 2)? 4'hF : 4'hF;
				   	dwbm_riscv_sel  <= (dmem_size == 0 || dmem_size == 4)? 1 :
(dmem_size == 1 || dmem_size == 5)? 4'h3 : (dmem_size == 2)? 4'hF : 4'hF;
            //dwbm_riscv_sel  <= (dmem_size == 0)? 4'h1 : (dmem_size == 1)? 4'h3 : (dmem_size == 2)? 4'hF : 4'hF;
            dstate <= 2;
          end
        2: begin
           if(dwbm_ack_i)
            begin
              dwbm_riscv_cyc <= 0;
              dwbm_riscv_stb <= 0;
              dstate <= 3;
						  dwbm_riscv_dat <= dwbm_dat_i;
              previous_dmem_access <= 1;
           end
          end
        3: begin
             dmem_wait <= 0;
             dstate <= 1;
					 end

    endcase
    
  end
end

vscale_pipeline vscale_core (
	 .clk(clk),
   .reset(rst),

   .imem_wait(imem_wait), 
   .imem_addr(pc),
   .imem_rdata(instruction),
   .imem_badmem_e(iwbm_err_i), 
	
   .replay_IF_out(replay_IF_out),

   .dmem_wait(dmem_wait), 
   .dmem_en(dmem_request), 
   .dmem_wen(dmem_we),
   .dmem_size(dmem_size), 
   .dmem_addr(dmem_addr),
   .dmem_wdata_delayed(dwbm_dat_o),
   .dmem_rdata(dwbm_riscv_dat),
   .dmem_badmem_e(1'b0) /* TODO */
   );

endmodule
