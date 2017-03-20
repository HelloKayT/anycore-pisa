/*******************************************************************************
#                        NORTH CAROLINA STATE UNIVERSITY
#
#                              AnyCore Project
# 
# AnyCore written by NCSU authors Rangeen Basu Roy Chowdhury and Eric Rotenberg.
# 
# AnyCore is based on FabScalar which was written by NCSU authors Niket K. 
# Choudhary, Brandon H. Dwiel, and Eric Rotenberg.
# 
# AnyCore also includes contributions by NCSU authors Elliott Forbes, Jayneel 
# Gandhi, Anil Kumar Kannepalli, Sungkwan Ku, Hiran Mayukh, Hashem Hashemi 
# Najaf-abadi, Sandeep Navada, Tanmay Shah, Ashlesha Shastri, Vinesh Srinivasan, 
# and Salil Wadhavkar.
# 
# AnyCore is distributed under the BSD license.
*******************************************************************************/

`timescale 1ns/100ps

/* Algorithm
   1. Receive new packet to execute each cycle, if there are ready instructions
      in the Issue Queue.

   2. Execute packet contains following information:
       (.) Opcode
       (.) Source Data-1
       (.) Source Register-1
       (.) Source Data-2
       (.) Source Register-2
       (.) Destination Register
       (.) Active List ID
       (.) Load-Store Queue ID
       (.) Ctiq Tag
       (.) Predicted Target Address (for control inst)
       (.) Predicted Direction      (for branch inst)
       (.) Packet Valid bit

   3. Receive bypass inputs from the previous cycle from all functional units.
      Instruction entering into the Execute should compare its source registers
      to bypassed destination registers.
        If, comparision result is true pick the bypassed value.

   4. Bypassed data should contain following information:
       (.) Destination Register
       (.) Output Data

   5. [ For current implementation Load instruction's RSR latency is same as Load execution
        latency plus register file read latency. This means load dependent instructions will not
        have back to back execution in best case. ]

      For Load dependent instructions, source tag should be compared against the load destination.
      If there is a match and the disambi stall signal is high, the instruction should be terminated.
      And the corresponding scheduled bit for the load dependent instruction in the issue queue
      should be set to 0.

   6. Output of a global Functional unit would be:
       (12) Destination Valid
       (11) Executed
       (10) Exception
       (9)  Mispredict
       (8)  Destination Register
       (7)  Active List ID
       (6)  Output Data
       (4)  Load-Store Queue ID
       (2)  Ctiq Tag
       (1)  Computed Target Address
       (0)  Computed Direction

***************************************************************************/

module Execute_Ctrl (
	input  fuPkt                         exePacket_i,
	output wbPkt                         wbPacket_o,

	/* all the bypasses coming from the different pipes */
	input  bypassPkt                     bypassPacket_i [0:`ISSUE_WIDTH-1]
	);


wire [`SIZE_DATA-1:0]                  src1Data;
wire [`SIZE_DATA-1:0]                  src2Data;


/* Check the bypasses for source data */
ForwardCheck src1Bypass (
	.srcReg_i                           (exePacket_i.phySrc1),
	.srcData_i                          (exePacket_i.src1Data),

	.bypassPacket_i                     (bypassPacket_i),

	.dataOut_o                          (src1Data)
	);

ForwardCheck src2Bypass (
	.srcReg_i                           (exePacket_i.phySrc2),
	.srcData_i                          (exePacket_i.src2Data),

	.bypassPacket_i                     (bypassPacket_i),

	.dataOut_o                          (src2Data)
	);


wire [`SIZE_PC-1:0]                    nextPC;
wire [`SIZE_DATA-1:0]                  result;
exeFlgs                                flags;
wire                                   computedDir;


/* Ctrl unit executes control-type instructions */
Ctrl_ALU ctrlAlu(
	.data1_i                            (src1Data),
	.data2_i                            (src2Data),
	.immd_i                             (exePacket_i.immed),
	.opcode_i                           (exePacket_i.opcode),
	.predNPC_i                          (exePacket_i.predNPC),
	.predDir_i                          (exePacket_i.predDir),
	.pc_i                               (exePacket_i.pc),
	.result_o                           (result),
	.nextPC_o                           (nextPC),
	.direction_o                        (computedDir),
	.flags_o                            (flags)
	);


/* Build the packet for the WB stage */
always_comb
begin
	wbPacket_o.seqNo                   = exePacket_i.seqNo;
	wbPacket_o.pc                      = exePacket_i.pc;
	wbPacket_o.flags                   = flags;
	wbPacket_o.phyDest                 = exePacket_i.phyDest;
	wbPacket_o.destData                = result;
	wbPacket_o.alID                    = exePacket_i.alID;
	wbPacket_o.nextPC                  = nextPC;
	wbPacket_o.ctrlType                = exePacket_i.ctrlType;
	wbPacket_o.ctrlDir                 = computedDir;
	wbPacket_o.ctiID                   = exePacket_i.ctiID;
	wbPacket_o.predDir                 = exePacket_i.predDir;
	wbPacket_o.valid                   = exePacket_i.valid;
end


`ifdef ZERO
always_ff @(posedge simulate.clk)
begin
    if ((exePacket_i.valid) &&
        (exePacket_i.opcode == `JR) &&
        (exePacket_i.ctrlType == `RETURN))
    begin
        $display("[%0d] executing a return (pc: %08x predNPC: %08x nextPC: %08x ctiID: %d)",
            simulate.CYCLE_COUNT,
            exePacket_i.pc,
            exePacket_i.predNPC,
            nextPC,
            exePacket_i.ctiID);
        if (flags.mispredict)
            $display("mispredict");

        $display("");
    end
end
`endif

`ifdef SIM
// stats ////////////////////////////////
integer     stat_num_corr;
integer     stat_num_pred;
integer     stat_num_cond_corr;
integer     stat_num_cond_pred;
integer     stat_num_return_corr;
integer     stat_num_return_pred;
integer     stat_num_recover;

always_ff @(posedge simulate.clk)
begin
    if (simulate.reset)
    begin
        stat_num_corr           = 0; 
        stat_num_pred           = 0;
        stat_num_cond_corr      = 0;
        stat_num_cond_pred      = 0;
        stat_num_return_corr    = 0;
        stat_num_return_pred    = 0;
        stat_num_recover        = 0;
    end

    else if (exePacket_i.valid)
    begin
        stat_num_pred++;
        
        if (!flags.mispredict)
            stat_num_corr++;
        else
            stat_num_recover++;

        if (exePacket_i.ctrlType == `COND_BRANCH)
        begin
            stat_num_cond_pred++;

            if (!flags.mispredict)
                stat_num_cond_corr++;
        end
        
        if (exePacket_i.ctrlType == `RETURN)
        begin
            stat_num_return_pred++;

            if (!flags.mispredict)
                stat_num_return_corr++;
        end
    end
end
/////////////////////////////////////////
`endif




endmodule
