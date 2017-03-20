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

module RAM_PARTITIONED_NO_DECODE #(
	/* Parameters */
	parameter DEPTH = `RAM_CONFIG_DEPTH,
	parameter INDEX = `RAM_CONFIG_INDEX,
	parameter WIDTH = `RAM_CONFIG_WIDTH,
  parameter NUM_WR_PORTS = `RAM_CONFIG_WP,
  parameter NUM_RD_PORTS = `RAM_CONFIG_RP,
  parameter WR_PORTS_LOG = `RAM_CONFIG_WP_LOG,
  parameter NUM_PARTS    = `STRUCT_PARTS,
  parameter NUM_PARTS_LOG= `STRUCT_PARTS_LOG,
  parameter LATCH_BASED_RAM= `LATCH_BASED_RAM,
  parameter RESET_VAL = `RAM_RESET_ZERO, //RAM_RESET_SEQ or RAM_RESET_ZERO
  parameter SEQ_START = 0,       // valid only when RESET_VAL = "SEQ"
  parameter PARENT_MODULE = "NO_PARENT_NO_DECODE" // This gives the module name in which this is instantiated
) (

  input       [NUM_RD_PORTS-1:0][NUM_PARTS_LOG-1:0]       rdDataPartition_i,
  input       [NUM_PARTS-1:0]          partitionGated_i,

	input       [NUM_RD_PORTS-1:0][DEPTH-1:0]       addr_i,
	output reg  [NUM_RD_PORTS-1:0][WIDTH-1:0]       data_o,

	input       [NUM_WR_PORTS-1:0][DEPTH-1:0]       addrWr_i,
	input       [NUM_WR_PORTS-1:0][WIDTH-1:0]       dataWr_i,

	input       [NUM_WR_PORTS-1:0]       wrEn_i,

	input                    clk,
	input                    reset,
  output                   ramReady_o //Used to signal that the RAM is ready for operation
);

  //function ceileven;
  //  input rd_ports;
  //  begin
  //    ceileven = rd_ports%2 ? (rd_ports+1) : rd_ports;
  //  end
  //endfunction


  wire [NUM_RD_PORTS-1:0][WIDTH-1:0]  rdData[NUM_PARTS-1:0];
  wire [NUM_RD_PORTS-1:0][DEPTH/NUM_PARTS-1:0]  addrPartition[NUM_PARTS-1:0];
  wire [NUM_WR_PORTS-1:0][DEPTH/NUM_PARTS-1:0]  addrWrPartition[NUM_PARTS-1:0];
  reg  [NUM_RD_PORTS-1:0][NUM_PARTS_LOG-1:0]    addrPartSelect;
  wire [NUM_PARTS-1:0]  ramReady;


  genvar rp;
  genvar wp;
  genvar rp1;
  genvar wp1;
  genvar part;
  generate

    //for(rp1 = 0; rp1< NUM_RD_PORTS; rp1++)
    //begin
    //  addrPartSelect[rp1]  = rdDataPartition_i[rp1];
    //end

    for(part = 0; part < NUM_PARTS; part++)//For every dispatch lane read port pair
    begin:INST_LOOP

      // For each read port split up the DEPTH wide word lines into NUM_PARTS equal parts and send them
      // to the corresponding partition. The RAM partitions do not have decoders inside them and perform
      // operations based on word select lines
      for(rp = 0; rp < NUM_RD_PORTS; rp++)
      begin:READ_ADDR
        assign addrPartition[part][rp]   = addr_i[rp][(DEPTH/NUM_PARTS)*(part+1)-1:(DEPTH/NUM_PARTS)*part];
      end

      // For each write port split up the DEPTH wide word lines into NUM_PARTS equal parts and send them
      // to the corresponding partition. The RAM partitions do not have decoders inside them and perform
      // operations based on word select lines
      for(wp = 0; wp < NUM_WR_PORTS; wp++)
      begin:WR_ADDR
        assign addrWrPartition[part][wp]   = addrWr_i[wp][(DEPTH/NUM_PARTS)*(part+1)-1:(DEPTH/NUM_PARTS)*part];
      end

      RAM_STATIC_CONFIG_NO_DECODE 
      #(
        .DEPTH(DEPTH/NUM_PARTS),
        .INDEX(INDEX-NUM_PARTS_LOG),
        .WIDTH(WIDTH),
        .NUM_WR_PORTS(NUM_WR_PORTS),
        .NUM_RD_PORTS(NUM_RD_PORTS),
        .WR_PORTS_LOG(WR_PORTS_LOG),
        .RESET_VAL(RESET_VAL),
        .SEQ_START(SEQ_START+(part*DEPTH/NUM_PARTS)),
        .GATING_ENABLED(1),
        .PARENT_MODULE({PARENT_MODULE,"_RAM_STATIC_NO_DECODE"})
      ) ram_instance_no_decode
      ( 
        .ramGated_i         (partitionGated_i[part]),
        .addr_i             (addrPartition[part]),
        .addrWr_i           (addrWrPartition[part]), //Write to the same address in RAM for each read port
        .wrEn_i             (wrEn_i),
        .dataWr_i           (dataWr_i),  // Write the same data in each RAM for each read port
        .clk                (clk),
        .reset              (reset),
        .data_o             (rdData[part]),
        .ramReady_o         (ramReady[part])
      );

    end //for INSTANCE_LOOP
  endgenerate

  /* RAM reset state machine */
  //TODO: To be used in future if requred
  assign ramReady_o = &ramReady;

  /* Read operation */
  always_comb 
  begin
    int rp;
    for(rp = 0; rp< NUM_RD_PORTS; rp++)
    begin
      //case(addrPartSelect[rp])
      case(rdDataPartition_i[rp])
        0: data_o[rp] = rdData[0][rp];
        1: data_o[rp] = rdData[1][rp];
        2: data_o[rp] = rdData[2][rp];
        3: data_o[rp] = rdData[3][rp];
        4: data_o[rp] = rdData[4][rp];
        5: data_o[rp] = rdData[5][rp];
        6: data_o[rp] = rdData[6][rp];
        7: data_o[rp] = rdData[7][rp];
      endcase
    end
  end
//  always_comb 
//  begin
//    int rp;
//    for(rp = 0; rp< NUM_RD_PORTS; rp++)
//    begin
//      addrPartSelect[rp]  = rdDataPartition_i[rp];
//      data_o[rp] = rdData[addrPartSelect[rp]][rp];
//    end
//  end

endmodule


