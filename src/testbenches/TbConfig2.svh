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

`define  FETCH_LANE_ACTIVE              {{`FETCH_WIDTH-1{1'b0}},1'b1};
`define  DISPATCH_LANE_ACTIVE           {{`DISPATCH_WIDTH-1{1'b0}},1'b1};
`define  ISSUE_LANE_ACTIVE              {{`ISSUE_WIDTH-3{1'b0}},3'b111};
`define  EXEC_LANE_ACTIVE               {{`EXEC_WIDTH-3{1'b0}},3'b111};
`define  SALU_LANE_ACTIVE               {{`EXEC_WIDTH-3{1'b0}},3'b100};
`define  CALU_LANE_ACTIVE               {{`EXEC_WIDTH-3{1'b0}},3'b100};
`define  COMMIT_LANE_ACTIVE             {{`COMMIT_WIDTH-2{1'b0}},2'b11};
`define  RF_PARTITION_ACTIVE            {{`NUM_PARTS_RF-2{1'b0}},2'b11};
`define  AL_PARTITION_ACTIVE            {{`NUM_PARTS_RF-2{1'b0}},2'b11};
`define  LSQ_PARTITION_ACTIVE           {{`STRUCT_PARTS_LSQ-1{1'b0}},1'b1};
`define  IQ_PARTITION_ACTIVE            {{`STRUCT_PARTS-1{1'b0}},1'b1};
`define  IBUFF_PARTITION_ACTIVE         {{`STRUCT_PARTS-2{2'b0}},2'b11};
