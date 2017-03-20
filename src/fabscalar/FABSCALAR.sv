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

module FABSCALAR(

	input                            clk,
	input                            reset,
  input                            resetFetch_i,

  output reg                       toggleFlag_o,

	input  [`SIZE_PC-1:0]            startPC_i,
	
	output [`SIZE_PC-1:0]            instPC_o [0:`FETCH_WIDTH-1],
  output                           fetchReq_o, //Indicates whether the instruction PC 
                                                // in a particular clock cycle is valid
  output                           fetchRecoverFlag_o, // Indicates that fetch is being recovered
                                                  // due to a bad event in CPU
	input  [`SIZE_INSTRUCTION-1:0]   inst_i   [0:`FETCH_WIDTH-1],
  input                            instValid_i, //Indicates whether the instruction stream 
                                                // in a particular clock cycle is valid

//`ifdef SCRATCH_PAD
//  input [`DEBUG_INST_RAM_LOG+`DEBUG_INST_RAM_WIDTH_LOG-1:0]   instScratchAddr_i   ,
//  input  [7:0]                     instScratchWrData_i ,
//  input                            instScratchWrEn_i   ,
//  output [7:0]                     instScratchRdData_o ,
//  input  [`DEBUG_DATA_RAM_LOG+`DEBUG_DATA_RAM_WIDTH_LOG-1:0]  dataScratchAddr_i   ,
//  input  [7:0]                     dataScratchWrData_i ,
//  input                            dataScratchWrEn_i   ,
//  output [7:0]                     dataScratchRdData_o ,
//  input                            instScratchPadEn_i,
//  input                            dataScratchPadEn_i,
//`endif

`ifdef INST_CACHE
  output [`ICACHE_SIZE_MEM_ADDR-1:0]  ic2memReqAddr_o,      // memory read address
  output                              ic2memReqValid_o,     // memory read enable
  input  [`ICACHE_TAG_BITS-1:0]       mem2icTag_i,          // tag of the incoming data
  input  [`ICACHE_INDEX_BITS-1:0]     mem2icIndex_i,        // index of the incoming data
  input  [`ICACHE_LINE_SIZE-1:0]      mem2icData_i,         // requested data
  input                               mem2icRespValid_i,    // requested data is ready
  input                               instCacheBypass_i,
  input                               icScratchModeEn_i,    // Should ideally be disabled by default
  input [`ICACHE_INDEX_BITS+`ICACHE_BYTES_IN_LINE_LOG-1:0]  icScratchWrAddr_i,
  input                                                     icScratchWrEn_i,
  input [7:0]                                               icScratchWrData_i,
  output [7:0]                                              icScratchRdData_o,
`endif  

`ifdef DATA_CACHE
  input                               dataCacheBypass_i,
  input                               dcScratchModeEn_i,    // Should ideally be disabled by default

  // cache-to-memory interface for Loads
  output [`DCACHE_SIZE_MEM_ADDR-1:0]  dc2memLdAddr_o,  // memory read address
  output reg                          dc2memLdValid_o, // memory read enable

  // memory-to-cache interface for Loads
  input  [`DCACHE_TAG_BITS-1:0]       mem2dcLdTag_i,       // tag of the incoming datadetermine
  input  [`DCACHE_INDEX_BITS-1:0]     mem2dcLdIndex_i,     // index of the incoming data
  input  [`DCACHE_LINE_SIZE-1:0]      mem2dcLdData_i,      // requested data
  input                               mem2dcLdValid_i,     // indicates the requested data is ready

  // cache-to-memory interface for stores
  output [`DCACHE_SIZE_ST_ADDR-1:0]   dc2memStAddr_o,  // memory read address
  output [`SIZE_DATA-1:0]             dc2memStData_o,  // memory read address
  output [3:0]                        dc2memStByteEn_o,  // memory read address
  output reg                          dc2memStValid_o, // memory read enable

  // memory-to-cache interface for stores
  input                               mem2dcStComplete_i,
  input                               mem2dcStStall_i,

  input [`DCACHE_INDEX_BITS+`DCACHE_BYTES_IN_LINE_LOG-1:0]  dcScratchWrAddr_i,
  input                                                     dcScratchWrEn_i,
  input [7:0]                                               dcScratchWrData_i,
  output [7:0]                                              dcScratchRdData_o,
`endif

  input                            stallFetch_i,
  // These should be controlled by power manager
  // Making these as inputs to the core for now
`ifdef DYNAMIC_CONFIG
// Wires for the power management unit that does dynamic reconfiguration
  input  [`FETCH_WIDTH-1:0]        fetchLaneActive_i,
  input  [`DISPATCH_WIDTH-1:0]     dispatchLaneActive_i,
  input  [`ISSUE_WIDTH-1:0]        issueLaneActive_i,
  input  [`EXEC_WIDTH-1:0]         execLaneActive_i,
  input  [`EXEC_WIDTH-1:0]         saluLaneActive_i,
  input  [`EXEC_WIDTH-1:0]         caluLaneActive_i,
  input  [`COMMIT_WIDTH-1:0]       commitLaneActive_i,
  input  [`NUM_PARTS_RF-1:0]       rfPartitionActive_i,
  input  [`NUM_PARTS_RF-1:0]       alPartitionActive_i,
  input  [`STRUCT_PARTS_LSQ-1:0]   lsqPartitionActive_i,
  input  [`STRUCT_PARTS-1:0]       iqPartitionActive_i,
  input  [`STRUCT_PARTS-1:0]       ibuffPartitionActive_i,
  input                            reconfigureCore_i,

  output                           reconfigDone_o,
  output                           pipeDrained_o,
`endif

`ifdef PERF_MON
  input  [7:0]                     perfMonRegAddr_i,
  output [31:0]                    perfMonRegData_o,
  input                            perfMonRegRun_i       ,
  input                            perfMonRegClr_i       ,
  input                            perfMonRegGlobalClr_i ,           
`endif


	/* To memory */
	output  [`SIZE_PC-1:0]                ldAddr_o,
	input   [`SIZE_DATA-1:0]              ldData_i,
  input                                 ldDataValid_i,
	output                                ldEn_o,

	output  [`SIZE_PC-1:0]                stAddr_o,
	output  [`SIZE_DATA-1:0]              stData_o,
	output  [3:0]                         stEn_o,

  // This is used to update the fake Gshare in the testbench
	output [`COMMIT_WIDTH-1:0]            actualDir_o,
	output [`COMMIT_WIDTH-1:0]            ctrlType_o,

	input  [`SIZE_PHYSICAL_LOG-1:0]       dbAddr_i,
	input  [`SIZE_DATA-1:0]               dbData_i,
	input                                 dbWe_i,

	input  [`SIZE_PHYSICAL_LOG+`SIZE_DATA_BYTE_OFFSET-1:0]       debugPRFAddr_i,
	input  [`SRAM_DATA_WIDTH-1:0]         debugPRFWrData_i,
	input                                 debugPRFWrEn_i,
	output [`SRAM_DATA_WIDTH-1:0]         debugPRFRdData_o,

	input  [`SIZE_RMT_LOG-1:0]            debugAMTAddr_i,
	output [`SIZE_PHYSICAL_LOG-1:0]       debugAMTRdData_o
	);


/*****************************Wire Declaration**********************************/

// Wires from FetchStage1 module
fs2Pkt                            fs2Packet      [0:`FETCH_WIDTH-1];
fs2Pkt                            fs2Packet_l1   [0:`FETCH_WIDTH-1];

wire                              fs1Ready;
wire                              fs1Ready_l1;

wire [`SIZE_PC-1:0]               addrRAS;

reg  [1:0]                        predCounter    [0:`FETCH_WIDTH-1];
reg  [1:0]                        predCounter_l1 [0:`FETCH_WIDTH-1];

`ifdef DYNAMIC_CONFIG
  wire [`FETCH_WIDTH-1:0]         fs1Fs2Valid;
  wire [`FETCH_WIDTH-1:0]         fs2DecValid;
  wire [`DISPATCH_WIDTH-1:0]      renDisValid;
  wire [`DISPATCH_WIDTH-1:0]      instBufRenValid;
  wire [`DISPATCH_WIDTH-1:0]      disIqValid;
  wire [`ISSUE_WIDTH-1:0]         iqRegReadValid;
  wire                            ibuffInsufficientCnt;
`endif

// Wires from FetchStage2 module
wire                              fs2RecoverFlag;
wire [`SIZE_PC-1:0]               fs2RecoverPC;
wire                              fs2MissedReturn;
wire                              fs2MissedCall;
wire [`SIZE_PC-1:0]               fs2CallPC;

wire [`SIZE_PC-1:0]               updatePC;
wire [`SIZE_PC-1:0]               updateNPC;
wire [`BRANCH_TYPE-1:0]           updateCtrlType;
wire                              updateDir;
wire [1:0]                        updateCounter;
wire                              updateEn;

wire                              ctiQueueFull;
wire                              fs2Ready;

decPkt                            decPacket    [0:`FETCH_WIDTH-1];
decPkt                            decPacket_l1 [0:`FETCH_WIDTH-1];


// Wires from Fetch2Decode module
wire [`SIZE_PC-1:0]               updatePC_l1;
wire [`SIZE_PC-1:0]               updateNPC_l1;
wire [`BRANCH_TYPE-1:0]           updateCtrlType_l1;
wire                              updateDir_l1;
wire [1:0]                        updateCounter_l1;
wire                              updateEn_l1;

wire                              fs2Ready_l1;


// Wires from Decode module
wire                              decodeReady;

renPkt                            ibPacket [0:2*`FETCH_WIDTH-1];
renPkt                            ibPacketClamped [0:2*`FETCH_WIDTH-1];

// Wires from Instruction Buffer module
wire                              instBufferFull;
wire                              instBufferReady;

renPkt                            renPacket [0:`DISPATCH_WIDTH-1];


// Wires from InstBufRename
wire                              instBufferReady_l1;

renPkt                            renPacket_l1 [0:`DISPATCH_WIDTH-1];

`ifdef PERF_MON
wire [`INST_QUEUE_LOG:0]          instBuffCount     ;
`endif

// Wires from Rename module
wire                              freeListEmpty;
wire                              renameReady;

disPkt                            disPacket [0:`DISPATCH_WIDTH-1];
phys_reg                          phyDest   [0:`DISPATCH_WIDTH-1];

`ifdef PERF_MON
wire [`SIZE_FREE_LIST_LOG-1:0]    freeListCnt;
wire [`SIZE_LSQ_LOG:0]            iqReqCount;
wire [`SIZE_LSQ_LOG:0]            iqIssuedCount;
`endif
// Wires from RenameDispatch module
wire                              renameReady_l1;
disPkt                            disPacket_l1 [0:`DISPATCH_WIDTH-1];

//wires from Dispatch module
wire                              stallfrontEnd;

//wires from Dispatch module
wire                              backEndReady;

iqPkt                             iqPacket  [0:`DISPATCH_WIDTH-1];
alPkt                             alPacket  [0:`DISPATCH_WIDTH-1];
lsqPkt                            lsqPacket [0:`DISPATCH_WIDTH-1];


// wires for issueq module
wire [`SIZE_ISSUEQ_LOG:0]         cntInstIssueQ;
payloadPkt                        rrPacket      [0:`ISSUE_WIDTH-1];

// wires for iq_regread module
payloadPkt                        rrPacket_l1   [0:`ISSUE_WIDTH-1];


// wires from execute module
memPkt                            memPacket;
wire  [`ISSUE_WIDTH-1:0]          toggleFlag;


// wire from writeback module
wire [`SIZE_PC-1:0]               exeCtrlPC;
wire [`BRANCH_TYPE-1:0]           exeCtrlType;
wire                              exeCtrlValid;
wire [`SIZE_PC-1:0]               exeCtrlNPC;
wire                              exeCtrlDir;
wire [`SIZE_CTI_LOG-1:0]          exeCtiID;

ctrlPkt                           ctrlPacket [0:`ISSUE_WIDTH-1];
ctrlPkt                           ctrlPacket_a1 [0:`ISSUE_WIDTH-1];

memPkt                            memPacket_l1;


// wire from Load-Store Unit
reg  [`SIZE_LSQ_LOG-1:0]          lsqID [0:`DISPATCH_WIDTH-1];
wire [`SIZE_LSQ_LOG:0]            ldqCount;
wire [`SIZE_LSQ_LOG:0]            stqCount;
wbPkt                             wbPacket;
ldVioPkt                          ldVioPacket;
ldVioPkt                          ldVioPacket_l1;


// wires from activeList module
reg  [`SIZE_ACTIVELIST_LOG-1:0]   alHead;
reg  [`SIZE_ACTIVELIST_LOG-1:0]   alTail;
reg  [`SIZE_ACTIVELIST_LOG-1:0]   alID [0:`DISPATCH_WIDTH-1];

commitPkt                         amtPacket [0:`COMMIT_WIDTH-1];

`ifdef PERF_MON
wire [`COMMIT_WIDTH-1:0]           commitValid; 
wire [`COMMIT_WIDTH-1:0]           totalCommit; 
`endif

wire [`SIZE_ACTIVELIST_LOG:0]     activeListCnt;
reg  [`COMMIT_WIDTH-1:0]          commitStore;
reg  [`COMMIT_WIDTH-1:0]          commitLoad;
wire [`COMMIT_WIDTH-1:0]          commitCti;
wire                              recoverFlag;
/* wire                              repairFlag; */
wire [`SIZE_PC-1:0]               recoverPC;
wire                              exceptionFlag;
wire [`SIZE_PC-1:0]               exceptionPC;
wire                              loadViolation;


// wires from amt module
phys_reg                          freedPhyReg  [0:`COMMIT_WIDTH-1];
/* recoverPkt                           repairPacket [0:`COMMIT_WIDTH-1]; */
wire                              repairFlag;
reg  [`SIZE_RMT_LOG-1:0]          repairAddr  [0:`N_REPAIR_PACKETS-1];
reg  [`SIZE_PHYSICAL_LOG-1:0]     repairData  [0:`N_REPAIR_PACKETS-1];
`ifdef DYNAMIC_CONFIG
wire 				                      consolidateFlag;
wire 				                      consolidationDone;
wire [`SIZE_RMT_LOG-1:0]	        logAddr;
//wire [`SIZE_PHYSICAL_LOG-1:0]  	  phyAddrToPRF;
wire [`SIZE_PHYSICAL_LOG-1:0]  	  phyAddrFromAMT;
bypassPkt                         bypassPacket_recon;
wire [`SIZE_PHYSICAL_LOG-1:0]     phySrc1_recon;
wire 				                      beginConsolidation;
`endif

// WIRES DECLARED FOR THE INTERACTION BETWEEN REGISTER FILE AND EXECUTION PIPES
reg  [`SRAM_DATA_WIDTH-1:0]  src1Data_byte0 [0:`ISSUE_WIDTH-1];
reg  [`SRAM_DATA_WIDTH-1:0]  src1Data_byte1 [0:`ISSUE_WIDTH-1];
reg  [`SRAM_DATA_WIDTH-1:0]  src1Data_byte2 [0:`ISSUE_WIDTH-1];
reg  [`SRAM_DATA_WIDTH-1:0]  src1Data_byte3 [0:`ISSUE_WIDTH-1];
reg  [`SRAM_DATA_WIDTH-1:0]  src2Data_byte0 [0:`ISSUE_WIDTH-1];
reg  [`SRAM_DATA_WIDTH-1:0]  src2Data_byte1 [0:`ISSUE_WIDTH-1];
reg  [`SRAM_DATA_WIDTH-1:0]  src2Data_byte2 [0:`ISSUE_WIDTH-1];
reg  [`SRAM_DATA_WIDTH-1:0]  src2Data_byte3 [0:`ISSUE_WIDTH-1];

reg  [`SIZE_PHYSICAL_LOG-1:0] phySrc1 [0:`ISSUE_WIDTH-1];
reg  [`SIZE_PHYSICAL_LOG-1:0] phySrc2 [0:`ISSUE_WIDTH-1];

bypassPkt                              bypassPacket [0:`ISSUE_WIDTH-1];
bypassPkt                              bypassPacket_a1 [0:`ISSUE_WIDTH-1];

`ifdef DYNAMIC_CONFIG
  reg  [`SIZE_PHYSICAL_LOG-1:0] phySrc1_PRF [0:`ISSUE_WIDTH-1];
  reg  [`SIZE_PHYSICAL_LOG-1:0] phySrc2_PRF [0:`ISSUE_WIDTH-1];
  bypassPkt                              bypassPacket_PRF [0:`ISSUE_WIDTH-1];
`endif


`ifdef DYNAMIC_CONFIG
  logic  [`FETCH_WIDTH-1:0]        fetchLaneActive;
  logic  [`DISPATCH_WIDTH-1:0]     dispatchLaneActive;
  logic  [`ISSUE_WIDTH-1:0]        issueLaneActive;
  logic  [`EXEC_WIDTH-1:0]         execLaneActive;
  logic  [`EXEC_WIDTH-1:0]         saluLaneActive;
  logic  [`EXEC_WIDTH-1:0]         caluLaneActive;
  logic  [`COMMIT_WIDTH-1:0]       commitLaneActive;
  logic  [`NUM_PARTS_RF-1:0]       rfPartitionActive;
  logic  [`NUM_PARTS_RF-1:0]       alPartitionActive;
  logic  [`STRUCT_PARTS_LSQ-1:0]   lsqPartitionActive;
  logic  [`STRUCT_PARTS-1:0]       iqPartitionActive;
  logic  [`STRUCT_PARTS-1:0]       ibuffPartitionActive;
  logic                            loadNewConfig;
  logic                            reconfigureFlag;
`endif
  logic                            stallFetch;

`ifdef PERF_MON
  logic                            loadStall;
  logic                            storeStall;
  logic                            iqStall;
  logic                            alStall;
 `ifdef INST_CACHE  
  logic                            icMiss;
 `endif
 `ifdef DATA_CACHE
  logic                            ldMiss;
  logic                            stMiss;
 `endif
`endif

`ifdef DATA_CACHE
  logic                            stallStCommit;
`endif








 /**********************************************************************************
 *  "fetch1" module is the first stage of the instruction fetching process. This
 *  module contains L1 Insturction Cache, Branch Target Buffer, Branch Prediction
 *  Buffer and Return Address Stack structures.
 **********************************************************************************/

  assign fetchRecoverFlag_o =  recoverFlag | exceptionFlag | fs2RecoverFlag;

FetchStage1 fs1(
	.clk                  (clk),
	.reset                (reset),
  .resetFetch_i         (resetFetch_i), // Does not reset the cache

	.startPC_i            (startPC_i),

//`ifdef SCRATCH_PAD
//  .instScratchAddr_i    (instScratchAddr_i),
//  .instScratchWrData_i  (instScratchWrData_i),
//  .instScratchWrEn_i    (instScratchWrEn_i),
//  .instScratchRdData_o  (instScratchRdData_o),
//  .instScratchPadEn_i   (instScratchPadEn_i),
//`endif

`ifdef INST_CACHE
  .ic2memReqAddr_o      (ic2memReqAddr_o  ),     // memory read address
  .ic2memReqValid_o     (ic2memReqValid_o ),     // memory read enable
  .mem2icTag_i          (mem2icTag_i      ),     // tag of the incoming data
  .mem2icIndex_i        (mem2icIndex_i    ),     // index of the incoming data
  .mem2icData_i         (mem2icData_i     ),     // requested data
  .mem2icRespValid_i    (mem2icRespValid_i),     // requested data is ready
  .instCacheBypass_i    (instCacheBypass_i),
  .icScratchModeEn_i    (icScratchModeEn_i),

  .icScratchWrAddr_i    (icScratchWrAddr_i),
  .icScratchWrEn_i      (icScratchWrEn_i  ),
  .icScratchWrData_i    (icScratchWrData_i),
  .icScratchRdData_o    (icScratchRdData_o),
`endif  

`ifdef PERF_MON
  .icMiss_o             (icMiss),
`endif
  //TODO: stallFetch might not be needed as
  // it is part of instBufferFull
  .stallFetch_i         (stallFetch),
`ifdef DYNAMIC_CONFIG  
	//.stall_i              (instBufferFull | ctiQueueFull | stallFetch),
  .fetchLaneActive_i    (fetchLaneActive),
  .reconfigureCore_i    (loadNewConfig),
`endif

	.stall_i              (instBufferFull | ctiQueueFull),

	.recoverFlag_i        (recoverFlag),
	.recoverPC_i          (recoverPC),

	.exceptionFlag_i      (exceptionFlag),
	.exceptionPC_i        (exceptionPC),

	.fs2RecoverFlag_i     (fs2RecoverFlag),
	.fs2MissedCall_i      (fs2MissedCall),
	.fs2CallPC_i          (fs2CallPC),
	.fs2MissedReturn_i    (fs2MissedReturn),
	.fs2RecoverPC_i       (fs2RecoverPC),

	.updatePC_i           (updatePC_l1),
	.updateNPC_i          (updateNPC_l1),
	.updateBrType_i       (updateCtrlType_l1),
	.updateDir_i          (updateDir_l1),
	.updateCounter_i      (updateCounter_l1),
	.updateEn_i           (updateEn_l1),

	.instPC_o             (instPC_o),
  .fetchReq_o           (fetchReq_o),
	.inst_i               (inst_i),
  .instValid_i          (instValid_i),

	.fs1Ready_o           (fs1Ready),
	.addrRAS_o            (addrRAS),
	.predCounter_o        (predCounter),

	.fs2Packet_o          (fs2Packet)

	);



 /**********************************************************************************
 *  "fs1fs2" module is the pipeline stage between Fetch Stage-1 and Fetch
 *  Stage-2.
 **********************************************************************************/

Fetch1Fetch2 fs1fs2(
	.clk                  (clk),
	.reset                (reset),

	.flush_i              (fs2RecoverFlag | recoverFlag | exceptionFlag | resetFetch_i),
  //TODO: stallFetch might not be needed as
  // it is part of instBufferFull
`ifdef DYNAMIC_CONFIG
  .laneActive_i         (fetchLaneActive),
	//.stall_i              (instBufferFull | ctiQueueFull | stallFetch),
	.valid_bundle_o       (fs1Fs2Valid),
`endif

	.stall_i              (instBufferFull | ctiQueueFull),

	.fs1Ready_i           (fs1Ready),
	.predCounter_i        (predCounter),
	.fs2Packet_i          (fs2Packet),

	.fs1Ready_o           (fs1Ready_l1),
	.predCounter_o        (predCounter_l1),
	.fs2Packet_o          (fs2Packet_l1)
	);



 /**********************************************************************************
 *  "fetch2" module is the second stage of the instruction fetching process. This
 *  module contains small decode logic for control instructions and verifies the
 *  target address provided by BTB or RAS in "fetch1".
 *
 *  The module also contains CTI Queue structure, which keeps tracks of number of
 *  branch instructions in the processor.
 **********************************************************************************/
// NOTE: Clamping of valid bits is not necessary as the corresponding lane in
// the following pipeline register and decode stage will also be gated and
// valid bits from Decode will be clamped. Note that valid bit from decode
// needs to be clamped as Instruction buffer is more or less a monolithic
// piece of logic and valid clamping is necessary for correctness purposes.

// NOTE: Not much except the predecode can be converted to per lane logic.
// Hence, just gate the predecodes and leave rest of the logic as a single
// blob.
FetchStage2 fs2(

	.clk                  (clk),
	.reset                (reset | resetFetch_i),

	.recoverFlag_i        (recoverFlag),
	.exceptionFlag_i      (exceptionFlag),
  //TODO: stallFetch might not be needed as
  // it is part of instBufferFull
`ifdef DYNAMIC_CONFIG
	//.stall_i              (instBufferFull | stallFetch),
  .fetchLaneActive_i    (fetchLaneActive),
`endif

	.stall_i              (instBufferFull),

	.fs1Ready_i           (fs1Ready_l1),
	.addrRAS_i            (addrRAS),
	.predCounter_i        (predCounter_l1),

	.fs2Packet_i          (fs2Packet_l1),

	.decPacket_o          (decPacket),

	.exeCtrlPC_i          (exeCtrlPC),
	.exeCtrlType_i        (exeCtrlType),
	.exeCtiID_i           (exeCtiID),
	.exeCtrlNPC_i         (exeCtrlNPC),
	.exeCtrlDir_i         (exeCtrlDir),
	.exeCtrlValid_i       (exeCtrlValid),

	.commitCti_i          (commitCti),

	.fs2RecoverFlag_o     (fs2RecoverFlag),
	.fs2RecoverPC_o       (fs2RecoverPC),
	.fs2MissedReturn_o    (fs2MissedReturn),
	.fs2MissedCall_o      (fs2MissedCall),
	.fs2CallPC_o          (fs2CallPC),

	.updatePC_o           (updatePC),
	.updateNPC_o          (updateNPC),
	.updateCtrlType_o     (updateCtrlType),
	.updateDir_o          (updateDir),
	.updateCounter_o      (updateCounter),
	.updateEn_o           (updateEn),

	.fs2Ready_o           (fs2Ready),
	.ctiQueueFull_o       (ctiQueueFull)
	);



 /**********************************************************************************
 * "fs2dec" module is the pipeline stage between Fetch Stage-2 and decode stage.
 **********************************************************************************/
Fetch2Decode fs2dec(
	.clk                  (clk),
	.reset                (reset),
	.flush_i              (recoverFlag | exceptionFlag | resetFetch_i),
  //TODO: stallFetch might not be needed as
  // it is part of instBufferFull
`ifdef DYNAMIC_CONFIG
  .laneActive_i         (fetchLaneActive),
	//.stall_i              (instBufferFull | stallFetch),
	.valid_bundle_o       (fs2DecValid),
`endif

	.stall_i              (instBufferFull),

	.updatePC_i           (updatePC),
	.updateNPC_i          (updateNPC),
	.updateCtrlType_i     (updateCtrlType),
	.updateDir_i          (updateDir),
	.updateCounter_i      (updateCounter),
	.updateEn_i           (updateEn),

	.fs2Ready_i           (fs2Ready),

	.decPacket_i          (decPacket),
	.decPacket_o          (decPacket_l1),

	.updatePC_o           (updatePC_l1),
	.updateNPC_o          (updateNPC_l1),
	.updateCtrlType_o     (updateCtrlType_l1),
	.updateDir_o          (updateDir_l1),
	.updateCounter_o      (updateCounter_l1),
	.updateEn_o           (updateEn_l1),

	.fs2Ready_o           (fs2Ready_l1)
	);



 /**********************************************************************************
 * "decode" module decodes the incoming instruction and generate appropriate
 * signals required by the rest of the pipeline stages.
 **********************************************************************************/

// NOTE: Already per lane and can be easily power gated
Decode decode (
	.clk                  (clk),
	.reset                (reset),

`ifdef DYNAMIC_CONFIG  
  .fetchLaneActive_i    (fetchLaneActive),
`endif  

	.fs2Ready_i           (fs2Ready_l1),

	.decPacket_i          (decPacket_l1),

	.ibPacket_o           (ibPacket),

	.decodeReady_o        (decodeReady)
	);

`ifdef DYNAMIC_CONFIG_AND_WIDTH
// This cell clamps the output at specific values
// Similar in operation to an isolation cell used
// to clamp signals during power gating. Only the
// valid bits need to be clamped thus leading to
// a very small overheaaad.

genvar f;
generate
  for (f=0 ; f < `FETCH_WIDTH; f++)
  begin

    wire [1:0]  clampedValid;
    PGIsolationCell #(
      .WIDTH(2)
    ) dec2ibufIsolation
    (
      .clampEn(~fetchLaneActive[f]),
      .signalIn({ibPacket[2*f+1].valid,ibPacket[2*f].valid}),
      //.signalOut({ibPacketClamped[2*f+1].valid,ibPacketClamped[2*f].valid}),
      .signalOut(clampedValid),
      .clampValue(2'b00)
    );
  
    // Assign both the instructions in case of a complex instr
    always_comb
    begin
      ibPacketClamped[2*f]        = ibPacket[2*f];
      ibPacketClamped[2*f+1]      = ibPacket[2*f+1];

      ibPacketClamped[2*f].valid        = clampedValid[0];
      ibPacketClamped[2*f+1].valid      = clampedValid[1];
    end
  end
endgenerate

`endif



 /**********************************************************************************
 *  "InstructionBuffer" module decouples instruction fetching process and the rest
 *   of the pipeline stages.
 *
 *  This module contains Instruction Queue structure, which can accept variable
 *  number of instructions but always 4 instructions can be read from instruction
 *  buffer.
 **********************************************************************************/

// NOTE: Not much opportunity for per lane power gating.
// Correctness is taken care by clamping valid bits from 
// Decode stage and using valid bits in Instruction buffer
// write logic.

InstructionBuffer instBuf (
	.clk                  (clk),
	.reset                (reset),

`ifdef DYNAMIC_CONFIG  
  .fetchLaneActive_i    (fetchLaneActive),
  .dispatchLaneActive_i (dispatchLaneActive),
  //.ibuffPartitionActive_i (ibuffPartitionActive),
  .ibuffPartitionActive_i ({`STRUCT_PARTS{1'b1}}), // Making instbuff non-configurable
  .ibuffInsufficientCnt_o (ibuffInsufficientCnt),
  // Instruction read out of instruction buffer is stalled during loading new config as
  // there is a possibility that previously partial dispatch bundles might issue due to
  // narrowing of the dispatch width. Keep it stalled until the backend is ready to accept
  // new instructions. The sequencing is controlled by power manager state machine.
	.stall_i              (freeListEmpty | stallfrontEnd | repairFlag | reconfigureFlag),
  //.stallFetch_i         (stallFetch),
  .stallFetch_i         (1'b0),
`else
	.stall_i              (freeListEmpty | stallfrontEnd | repairFlag),
  .stallFetch_i         (1'b0),
`endif  

  // Cannot flush during reconfiguring as there might be residual instructions
  // that could not be dispatched due to lack of a full dispatch bundle.
  // Moreover the size is not being reconfigured and flush is not needed.
	//.flush_i              (recoverFlag | exceptionFlag | reconfigureFlag),
	.flush_i              (recoverFlag | exceptionFlag | resetFetch_i),  
  // Stall read side (Dispatch) when trying to reconfigure so that no new
  // instructions are dispatched. Does not affect the writing of new instructions
  // by decode, provided space is available in instruction buffer.
	//.stall_i              (freeListEmpty | stallfrontEnd | repairFlag | stallFetch),
`ifdef DYNAMIC_CONFIG_AND_WIDTH 
	.ibPacket_i           (ibPacketClamped),
`else  
	.ibPacket_i           (ibPacket),
`endif

	.decodeReady_i        (decodeReady),

	.instBufferFull_o     (instBufferFull),
	.instBufferReady_o    (instBufferReady),
`ifdef PERF_MON
	.instCount_o          (instBuffCount),
`endif

	.renPacket_o          (renPacket)
	);


 /**********************************************************************************
 *  "InstBufRename" module is the pipeline stage between Instruction buffer and
 *  Rename Stage.
 **********************************************************************************/

InstBufRename instBufRen (
	.clk                  (clk),
	.reset                (reset),

`ifdef DYNAMIC_CONFIG
  .laneActive_i         (dispatchLaneActive),
	.valid_bundle_o       (instBufRenValid),
	.flush_i              (recoverFlag | exceptionFlag | reconfigureFlag),
`else  
	.flush_i              (recoverFlag | exceptionFlag),
`endif
	.stall_i              (freeListEmpty | stallfrontEnd | repairFlag),
	.instBufferReady_i    (instBufferReady),

	.renPacket_i          (renPacket),
	.renPacket_o          (renPacket_l1),

	.instBufferReady_o    (instBufferReady_l1)
	);


 /**********************************************************************************
 *  "rename" module remaps logical source and destination registers to physical
 *  source and destination registers.
 *  This module contains Rename Map Table and Speculative Free List structures.
 **********************************************************************************/

// NOTE: Rename converted to per lane modular logic.
Rename rename (
	.clk                  (clk),
	.reset                (reset | exceptionFlag),

`ifdef DYNAMIC_CONFIG  
  .commitLaneActive_i   (commitLaneActive),
  .dispatchLaneActive_i (dispatchLaneActive),
  .rfPartitionActive_i  (rfPartitionActive),
  .reconfigureCore_i    (reconfigureFlag),
`endif  

	.stall_i              (stallfrontEnd),

	.decodeReady_i        (instBufferReady_l1),

	.renPacket_i          (renPacket_l1),
	.disPacket_o          (disPacket),

	.phyDest_o            (phyDest),

	.freedPhyReg_i        (freedPhyReg),

	/* .repairPacket_i       (repairPacket), */

	.recoverFlag_i        (recoverFlag),
	.repairFlag_i         (repairFlag),
	.repairAddr_i         (repairAddr),
	.repairData_i         (repairData),
`ifdef PERF_MON
	.freeListCnt_o        (freeListCnt),
`endif

	.freeListEmpty_o      (freeListEmpty),
	.renameReady_o        (renameReady)
	);


/*********************************************************************************
* "renDis" module is the pipeline stage between Rename and Dispatch Stage.
*
**********************************************************************************/

RenameDispatch renDis (
	.clk                   (clk),
	.reset                 (reset),

`ifdef DYNAMIC_CONFIG  
  .laneActive_i          (dispatchLaneActive),  
  .valid_bundle_o        (renDisValid),
	.flush_i               (recoverFlag | exceptionFlag | reconfigureFlag),
`else
	.flush_i               (recoverFlag | exceptionFlag),
`endif  
	.stall_i               (stallfrontEnd),

	.renameReady_i         (renameReady),

	.disPacket_i           (disPacket),
	.disPacket_o           (disPacket_l1),

	.renameReady_o         (renameReady_l1)
	);



/***********************************************************************************
* "dispatch" module dispatches renamed packets to Issue Queue, Active List, and
* Load-Store queue.
*
***********************************************************************************/

// NOTE: Most of the logic is either monolithic control logic or
// simple per lane assigns. No need to do complex per lane gating.
// Everything can be in always on domain. 
// Dispatch probably also has most correctness logic.
Dispatch dispatch (
	.clk                   (clk),
	.reset                 (reset),

`ifdef DYNAMIC_CONFIG  
  .dispatchLaneActive_i  (dispatchLaneActive),
  .execLaneActive_i      (execLaneActive),
  .saluLaneActive_i      (saluLaneActive),
  .caluLaneActive_i      (caluLaneActive),
  .alPartitionActive_i   (alPartitionActive),
  .iqPartitionActive_i   (iqPartitionActive),
  .lsqPartitionActive_i  (lsqPartitionActive),
  .reconfigureCore_i     (reconfigureFlag),    
`endif  

	.renameReady_i         (renameReady_l1),

	.recoverFlag_i         (recoverFlag),
	.recoverPC_i           (recoverPC),
	.loadViolation_i       (loadViolation),

	.disPacket_i           (disPacket_l1),

	.iqPacket_o            (iqPacket),
	.alPacket_o            (alPacket),
	.lsqPacket_o           (lsqPacket),

	.loadQueueCnt_i        (ldqCount),
	.storeQueueCnt_i       (stqCount),
	.issueQueueCnt_i       (cntInstIssueQ),
	.activeListCnt_i       (activeListCnt),
`ifdef PERF_MON
  .loadStall_o           (loadStall),
  .storeStall_o          (storeStall),
  .iqStall_o             (iqStall),
  .alStall_o             (alStall),
`endif
	.backEndReady_o        (backEndReady),
	.stallfrontEnd_o       (stallfrontEnd)
);


/************************************************************************************
* "issueq" module implements wake-up and select logic.
*
************************************************************************************/

// The issueQueue acts as the pipeline stage between dispatch and backend
IssueQueue issueq (
	.clk                  (clk),
	.reset                (reset),
	.flush_i              (recoverFlag | exceptionFlag),

`ifdef DYNAMIC_CONFIG  
  .issueLaneActive_i    (issueLaneActive),
  .dispatchLaneActive_i (dispatchLaneActive),
  .execLaneActive_i     (execLaneActive),
  .iqPartitionActive_i  (iqPartitionActive),
  .reconfigureCore_i    (loadNewConfig),
  .valid_bundle_o       (disIqValid),
`endif  

	.exceptionFlag_i      (exceptionFlag),
	.backEndReady_i       (backEndReady),

	.phyDest_i            (phyDest),

	.iqPacket_i           (iqPacket),

	.alHead_i             (alHead),
	.alTail_i             (alTail),
	.alID_i               (alID),
	.lsqID_i              (lsqID),

	.rrPacket_o           (rrPacket),

`ifdef PERF_MON
  .reqCount_o           (iqReqCount),
  .issuedCount_o        (iqIssuedCount),
`endif
	// this input comes from the bypass coming out of the load-store execution pipe
  // Instructions dependent on loads should only be woken up when the load completes
  // execution. Hence the bypass tag is used to wake up such instructions instead
  // internal RSR tag
	.rsr0Tag_i            ({bypassPacket[0].tag, bypassPacket[0].valid}),

	.cntInstIssueQ_o      (cntInstIssueQ)
);


/************************************************************************************
* "iq_regread" module is the pipeline stage between Issue Queue stage and physical
* register file read stage.
*
* This module also interfaces with RSR.
*
************************************************************************************/
IssueQRegRead iq_regread (

	.clk                  (clk),
	.reset                (reset),

`ifdef DYNAMIC_CONFIG
  .laneActive_i         (execLaneActive),
	.flush_i              (recoverFlag | exceptionFlag | loadNewConfig),
  .valid_bundle_o       (iqRegReadValid),
`else
	.flush_i              (recoverFlag | exceptionFlag),
`endif

	.rrPacket_i           (rrPacket),
	.rrPacket_o           (rrPacket_l1)
);


/************************************************************************************
* THE FOLLOWING IS THE INSTANTIATION OF THE PHYSICAL REGISTER FILE
************************************************************************************/

// NOTE: Not much opportunity for per lane logic except for
// gating the decoder and output muxes. This has to be decided
// based on power numbers.
PhyRegFile registerfile (

	.clk(clk),
	.reset(reset),

`ifdef DYNAMIC_CONFIG  
  .execLaneActive_i (execLaneActive),
  .rfPartitionActive_i(rfPartitionActive),

	/* inputs coming from the r-r stage */
	.phySrc1_i  (phySrc1_PRF),
	.phySrc2_i  (phySrc2_PRF),
	// inputs coming from the writeback stage
	.bypassPacket_i(bypassPacket_PRF),
`else
	/* inputs coming from the r-r stage */
	.phySrc1_i  (phySrc1),
	.phySrc2_i  (phySrc2),
	// inputs coming from the writeback stage
	.bypassPacket_i(bypassPacket),
`endif


	// outputs going to the r-r stage
	.src1Data_byte0_o(src1Data_byte0),
	.src1Data_byte1_o(src1Data_byte1),
	.src1Data_byte2_o(src1Data_byte2),
	.src1Data_byte3_o(src1Data_byte3),

	.src2Data_byte0_o(src2Data_byte0),
	.src2Data_byte1_o(src2Data_byte1),
	.src2Data_byte2_o(src2Data_byte2),
	.src2Data_byte3_o(src2Data_byte3),

	/* Initialize the PRF from top */
	.dbAddr_i        (dbAddr_i),
	.dbData_i        (dbData_i),
	.dbWe_i          (dbWe_i),
        
  .debugPRFAddr_i  (debugPRFAddr_i),
  .debugPRFWrData_i(debugPRFWrData_i),             
  .debugPRFWrEn_i  (debugPRFWrEn_i),
  .debugPRFRdData_o(debugPRFRdData_o)

);


/************************************************************************************
* THE FOLLOWING ARE THE INSTANTIATIONS OF THE EXECUTION PIPES
************************************************************************************/

assign toggleFlag[0]  = 1'b0; //Mem Lane
assign toggleFlag[1]  = 1'b0; //Ctrl Lane

// This serves as a signal to the outside world that the chip
// is alive. 
always_ff @(posedge clk or posedge reset)
begin
  if(reset)
  begin
    toggleFlag_o  <= 1'b0;
  end
  else
  begin
    `ifdef DYNAMIC_CONFIG_AND_WIDTH
      toggleFlag_o  <= toggleFlag_o ^ (|(toggleFlag & issueLaneActive));
    `else
      toggleFlag_o  <= toggleFlag_o ^ (|toggleFlag);
    `endif
  end
end

ExecutionPipe_M 
	exePipe0 (

	.clk(clk),
	.reset(reset),
	.recoverFlag_i(recoverFlag),
	.exceptionFlag_i(exceptionFlag),

`ifdef DYNAMIC_CONFIG_AND_WIDTH 
  .laneActive_i   (execLaneActive[0]),
`endif  

	// inputs coming from the register file
	.src1Data_byte0_i(src1Data_byte0[0]),
	.src1Data_byte1_i(src1Data_byte1[0]),
	.src1Data_byte2_i(src1Data_byte2[0]),
	.src1Data_byte3_i(src1Data_byte3[0]),

	.src2Data_byte0_i(src2Data_byte0[0]),
	.src2Data_byte1_i(src2Data_byte1[0]),
	.src2Data_byte2_i(src2Data_byte2[0]),
	.src2Data_byte3_i(src2Data_byte3[0]),

	// input from the issue queue going to the reg read stage
	.rrPacket_i(rrPacket_l1[0]),

	// bypasses coming from adjacent execution pipes
	.bypassPacket_i (bypassPacket),

	// inputs from the lsu coming to the writeback stage
	.wbPacket_i(wbPacket),
	.ldVioPacket_i(ldVioPacket),
	.ldVioPacket_o(ldVioPacket_l1),

	// bypass going from this pipe to other pipes
	.bypassPacket_o(bypassPacket[0]),

	// the output from the agen going to the lsu via the agenlsu latch
	.memPacket_o(memPacket),

	// output going to the active list from the load store pipe
	.ctrlPacket_o   (ctrlPacket[0]),

	// source operands extracted from the packet going to the physical register file
	.phySrc1_o(phySrc1[0]),
	.phySrc2_o(phySrc2[0])

);


ExecutionPipe_Ctrl
	exePipe1 (

	.clk(clk),
	.reset(reset),
	.recoverFlag_i(recoverFlag),
	.exceptionFlag_i(exceptionFlag),

`ifdef DYNAMIC_CONFIG_AND_WIDTH 
  .laneActive_i   (execLaneActive[1]),
`endif  

	// inputs coming from the register file
	.src1Data_byte0_i(src1Data_byte0[1]),
	.src1Data_byte1_i(src1Data_byte1[1]),
	.src1Data_byte2_i(src1Data_byte2[1]),
	.src1Data_byte3_i(src1Data_byte3[1]),
	.src2Data_byte0_i(src2Data_byte0[1]),
	.src2Data_byte1_i(src2Data_byte1[1]),
	.src2Data_byte2_i(src2Data_byte2[1]),
	.src2Data_byte3_i(src2Data_byte3[1]),

	// input from the issue queue going to the reg read stage
	.rrPacket_i(rrPacket_l1[1]),

	// bypasses coming from adjacent execution pipes
	.bypassPacket_i (bypassPacket),

	// bypass going from this pipe to other pipes
	.bypassPacket_o (bypassPacket[1]),

	// miscellaneous signals going to frontend stages as well as to other execution pipes
	.exeCtrlPC_o          (exeCtrlPC),
	.exeCtrlType_o        (exeCtrlType),
	.exeCtrlValid_o       (exeCtrlValid),
	.exeCtrlNPC_o         (exeCtrlNPC),
	.exeCtrlDir_o         (exeCtrlDir),
	.exeCtiID_o           (exeCtiID),

	// outputs going to the active list
	.ctrlPacket_o   (ctrlPacket[1]),

	// source operands extracted from the packet going to the physical register file
	.phySrc1_o(phySrc1[1]),
	.phySrc2_o(phySrc2[1])

);


localparam SIMPLE_VECT  = `SIMPLE_VECT;
localparam COMPLEX_VECT = `COMPLEX_VECT;

ExecutionPipe_SC #(
	.SIMPLE               (SIMPLE_VECT[2]),
	.COMPLEX              (COMPLEX_VECT[2])
)
	exePipe2 (

	.clk                  (clk),
	.reset                (reset),
  .toggleFlag_o         (toggleFlag[2]),

`ifdef DYNAMIC_CONFIG_AND_WIDTH 
  .laneActive_i         (execLaneActive[2]),
  .saluLaneActive_i     (saluLaneActive[2] & execLaneActive[2]),
  .caluLaneActive_i     (caluLaneActive[2] & execLaneActive[2]),
`endif  

	.recoverFlag_i        (recoverFlag),
	.exceptionFlag_i      (exceptionFlag),

	// inputs coming from the register file
	.src1Data_byte0_i     (src1Data_byte0[2]),
	.src1Data_byte1_i     (src1Data_byte1[2]),
	.src1Data_byte2_i     (src1Data_byte2[2]),
	.src1Data_byte3_i     (src1Data_byte3[2]),
	
	.src2Data_byte0_i     (src2Data_byte0[2]),
	.src2Data_byte1_i     (src2Data_byte1[2]),
	.src2Data_byte2_i     (src2Data_byte2[2]),
	.src2Data_byte3_i     (src2Data_byte3[2]),

	// input from the issue queue going to the reg read stage
	.rrPacket_i           (rrPacket_l1[2]),

	// bypasses coming from adjacent execution pipes
	.bypassPacket_i       (bypassPacket),

	// bypass going from this pipe to other pipes
	.bypassPacket_o       (bypassPacket[2]),

	// output going to the active list from the simple pipe
	.ctrlPacket_o         (ctrlPacket[2]),

	// source operands extracted from the packet going to the physical register file
	.phySrc1_o            (phySrc1[2]),
	.phySrc2_o            (phySrc2[2])

);


`ifdef ISSUE_FOUR_WIDE
ExecutionPipe_SC #(
	.SIMPLE               (SIMPLE_VECT[3]),
	.COMPLEX              (COMPLEX_VECT[3])
)
	exePipe3 (

	.clk                  (clk),
	.reset                (reset),
  .toggleFlag_o         (toggleFlag[3]),

`ifdef DYNAMIC_CONFIG_AND_WIDTH 
  .laneActive_i         (execLaneActive[3]),
  .saluLaneActive_i     (saluLaneActive[3] & execLaneActive[3]),
  .caluLaneActive_i     (caluLaneActive[3] & execLaneActive[3]),
`endif

	.recoverFlag_i        (recoverFlag),
	.exceptionFlag_i      (exceptionFlag),

	// inputs coming from the register file
	.src1Data_byte0_i     (src1Data_byte0[3]),
	.src1Data_byte1_i     (src1Data_byte1[3]),
	.src1Data_byte2_i     (src1Data_byte2[3]),
	.src1Data_byte3_i     (src1Data_byte3[3]),
	
	.src2Data_byte0_i     (src2Data_byte0[3]),
	.src2Data_byte1_i     (src2Data_byte1[3]),
	.src2Data_byte2_i     (src2Data_byte2[3]),
	.src2Data_byte3_i     (src2Data_byte3[3]),

	// input from the issue queue going to the reg read stage
	.rrPacket_i           (rrPacket_l1[3]),

	// bypasses coming from adjacent execution pipes
	.bypassPacket_i       (bypassPacket),

`ifdef DYNAMIC_CONFIG_AND_WIDTH 
	// bypass going from this pipe to other pipes
	.bypassPacket_o       (bypassPacket_a1[3]),

	// output going to the active list from the simple pipe
	.ctrlPacket_o         (ctrlPacket_a1[3]),
`else
	// bypass going from this pipe to other pipes
	.bypassPacket_o       (bypassPacket[3]),

	// output going to the active list from the simple pipe
	.ctrlPacket_o         (ctrlPacket[3]),
`endif

	// source operands extracted from the packet going to the physical register file
	.phySrc1_o            (phySrc1[3]),
	.phySrc2_o            (phySrc2[3])
);


`ifdef DYNAMIC_CONFIG_AND_WIDTH 
// This cell clamps the output at specific values
// Similar in operation to an isolation cell used
// to clamp signals during power gating. Only the
// valid bits need to be clamped thus leading to
// a very small overheaaad.

PGIsolationCell #(
  .WIDTH(2)
) exePipe3Isolation
(
  .clampEn(~execLaneActive[3]),
  .signalIn({bypassPacket_a1[3].valid,ctrlPacket_a1[3].valid}),
  .signalOut({bypassPacket[3].valid,ctrlPacket[3].valid}),
  .clampValue(2'b00)
);

// Allow signals other than vaid to be pass throughs
assign bypassPacket[3].tag  = bypassPacket_a1[3].tag;
assign bypassPacket[3].data = bypassPacket_a1[3].data;

assign ctrlPacket[3].seqNo  = ctrlPacket_a1[3].seqNo;
assign ctrlPacket[3].nextPC = ctrlPacket_a1[3].nextPC;
assign ctrlPacket[3].alID   = ctrlPacket_a1[3].alID;
assign ctrlPacket[3].flags  = ctrlPacket_a1[3].flags;
`endif

`endif


`ifdef ISSUE_FIVE_WIDE
ExecutionPipe_SC #(
	.SIMPLE               (SIMPLE_VECT[4]),
	.COMPLEX              (COMPLEX_VECT[4])
)
	exePipe4 (

	.clk                  (clk),
	.reset                (reset),
  .toggleFlag_o         (toggleFlag[4]),

`ifdef DYNAMIC_CONFIG_AND_WIDTH 
  .laneActive_i         (execLaneActive[4]),
  .saluLaneActive_i     (saluLaneActive[4] & execLaneActive[4]),
  .caluLaneActive_i     (caluLaneActive[4] & execLaneActive[4]),
`endif

	.recoverFlag_i        (recoverFlag),
	.exceptionFlag_i      (exceptionFlag),

	// inputs coming from the register file
	.src1Data_byte0_i     (src1Data_byte0[4]),
	.src1Data_byte1_i     (src1Data_byte1[4]),
	.src1Data_byte2_i     (src1Data_byte2[4]),
	.src1Data_byte3_i     (src1Data_byte3[4]),
	
	.src2Data_byte0_i     (src2Data_byte0[4]),
	.src2Data_byte1_i     (src2Data_byte1[4]),
	.src2Data_byte2_i     (src2Data_byte2[4]),
	.src2Data_byte3_i     (src2Data_byte3[4]),

	// input from the issue queue going to the reg read stage
	.rrPacket_i           (rrPacket_l1[4]),

	// bypasses coming from adjacent execution pipes
	.bypassPacket_i       (bypassPacket),

`ifdef DYNAMIC_CONFIG_AND_WIDTH 
	// bypass going from this pipe to other pipes
	.bypassPacket_o       (bypassPacket_a1[4]),

	// output going to the active list from the simple pipe
	.ctrlPacket_o         (ctrlPacket_a1[4]),
`else
	// bypass going from this pipe to other pipes
	.bypassPacket_o       (bypassPacket[4]),

	// output going to the active list from the simple pipe
	.ctrlPacket_o         (ctrlPacket[4]),
`endif

	// source operands extracted from the packet going to the physical register file
	.phySrc1_o            (phySrc1[4]),
	.phySrc2_o            (phySrc2[4])
);

`ifdef DYNAMIC_CONFIG_AND_WIDTH 
// This cell clamps the output at specific values
// Similar in operation to an isolation cell used
// to clamp signals during power gating. Only the
// valid bits need to be clamped thus leading to
// a very small overheaaad.

PGIsolationCell #(
  .WIDTH(2)
) exePipe4Isolation
(
  .clampEn(~execLaneActive[4]),
  .signalIn({bypassPacket_a1[4].valid,ctrlPacket_a1[4].valid}),
  .signalOut({bypassPacket[4].valid,ctrlPacket[4].valid}),
  .clampValue(2'b00)
);

// Allow signals other than vaid to be pass throughs
assign bypassPacket[4].tag  = bypassPacket_a1[4].tag;
assign bypassPacket[4].data = bypassPacket_a1[4].data;

assign ctrlPacket[4].seqNo  = ctrlPacket_a1[4].seqNo;
assign ctrlPacket[4].nextPC = ctrlPacket_a1[4].nextPC;
assign ctrlPacket[4].alID   = ctrlPacket_a1[4].alID;
assign ctrlPacket[4].flags  = ctrlPacket_a1[4].flags;
`endif



`endif


`ifdef ISSUE_SIX_WIDE
ExecutionPipe_SC #(
	.SIMPLE               (SIMPLE_VECT[5]),
	.COMPLEX              (COMPLEX_VECT[5])
)
	exePipe5 (

	.clk                  (clk),
	.reset                (reset),
  .toggleFlag_o         (toggleFlag[5]),

`ifdef DYNAMIC_CONFIG_AND_WIDTH 
  .laneActive_i         (execLaneActive[5]),
  .saluLaneActive_i     (saluLaneActive[5] & execLaneActive[5]),
  .caluLaneActive_i     (caluLaneActive[5] & execLaneActive[5]),
`endif

	.recoverFlag_i        (recoverFlag),
	.exceptionFlag_i      (exceptionFlag),

	// inputs coming from the register file
	.src1Data_byte0_i     (src1Data_byte0[5]),
	.src1Data_byte1_i     (src1Data_byte1[5]),
	.src1Data_byte2_i     (src1Data_byte2[5]),
	.src1Data_byte3_i     (src1Data_byte3[5]),
	
	.src2Data_byte0_i     (src2Data_byte0[5]),
	.src2Data_byte1_i     (src2Data_byte1[5]),
	.src2Data_byte2_i     (src2Data_byte2[5]),
	.src2Data_byte3_i     (src2Data_byte3[5]),

	// input from the issue queue going to the reg read stage
	.rrPacket_i           (rrPacket_l1[5]),

	// bypasses coming from adjacent execution pipes
	.bypassPacket_i       (bypassPacket),

`ifdef DYNAMIC_CONFIG_AND_WIDTH 
	// bypass going from this pipe to other pipes
	.bypassPacket_o       (bypassPacket_a1[5]),

	// output going to the active list from the simple pipe
	.ctrlPacket_o         (ctrlPacket_a1[5]),
`else
	// bypass going from this pipe to other pipes
	.bypassPacket_o       (bypassPacket[5]),

	// output going to the active list from the simple pipe
	.ctrlPacket_o         (ctrlPacket[5]),
`endif

	// source operands extracted from the packet going to the physical register file
	.phySrc1_o            (phySrc1[5]),
	.phySrc2_o            (phySrc2[5])
);


`ifdef DYNAMIC_CONFIG_AND_WIDTH 
// This cell clamps the output at specific values
// Similar in operation to an isolation cell used
// to clamp signals during power gating. Only the
// valid bits need to be clamped thus leading to
// a very small overheaaad.

PGIsolationCell #(
  .WIDTH(2)
) exePipe5Isolation
(
  .clampEn(~execLaneActive[5]),
  .signalIn({bypassPacket_a1[5].valid,ctrlPacket_a1[5].valid}),
  .signalOut({bypassPacket[5].valid,ctrlPacket[5].valid}),
  .clampValue(2'b00)
);

// Allow signals other than vaid to be pass throughs
assign bypassPacket[5].tag  = bypassPacket_a1[5].tag;
assign bypassPacket[5].data = bypassPacket_a1[5].data;

assign ctrlPacket[5].seqNo  = ctrlPacket_a1[5].seqNo;
assign ctrlPacket[5].nextPC = ctrlPacket_a1[5].nextPC;
assign ctrlPacket[5].alID   = ctrlPacket_a1[5].alID;
assign ctrlPacket[5].flags  = ctrlPacket_a1[5].flags;
`endif


`endif


`ifdef ISSUE_SEVEN_WIDE
ExecutionPipe_SC #(
	.SIMPLE               (SIMPLE_VECT[6]),
	.COMPLEX              (COMPLEX_VECT[6])
)
	exePipe6 (

	.clk                  (clk),
	.reset                (reset),
  .toggleFlag_o         (toggleFlag[6]),

`ifdef DYNAMIC_CONFIG_AND_WIDTH 
  .laneActive_i         (execLaneActive[6]),
  .saluLaneActive_i     (saluLaneActive[6] & execLaneActive[6]),
  .caluLaneActive_i     (caluLaneActive[6] 7 execLaneActive[6]),
`endif

	.recoverFlag_i        (recoverFlag),
	.exceptionFlag_i      (exceptionFlag),

	// inputs coming from the register file
	.src1Data_byte0_i     (src1Data_byte0[6]),
	.src1Data_byte1_i     (src1Data_byte1[6]),
	.src1Data_byte2_i     (src1Data_byte2[6]),
	.src1Data_byte3_i     (src1Data_byte3[6]),
	
	.src2Data_byte0_i     (src2Data_byte0[6]),
	.src2Data_byte1_i     (src2Data_byte1[6]),
	.src2Data_byte2_i     (src2Data_byte2[6]),
	.src2Data_byte3_i     (src2Data_byte3[6]),

	// input from the issue queue going to the reg read stage
	.rrPacket_i           (rrPacket_l1[6]),

	// bypasses coming from adjacent execution pipes
	.bypassPacket_i       (bypassPacket),

`ifdef DYNAMIC_CONFIG_AND_WIDTH 
	// bypass going from this pipe to other pipes
	.bypassPacket_o       (bypassPacket_a1[6]),

	// output going to the active list from the simple pipe
	.ctrlPacket_o         (ctrlPacket_a1[6]),
`else
	// bypass going from this pipe to other pipes
	.bypassPacket_o       (bypassPacket[6]),

	// output going to the active list from the simple pipe
	.ctrlPacket_o         (ctrlPacket[6]),
`endif

	// source operands extracted from the packet going to the physical register file
	.phySrc1_o            (phySrc1[6]),
	.phySrc2_o            (phySrc2[6])
);

`ifdef DYNAMIC_CONFIG_AND_WIDTH 
// This cell clamps the output at specific values
// Similar in operation to an isolation cell used
// to clamp signals during power gating. Only the
// valid bits need to be clamped thus leading to
// a very small overheaaad.

PGIsolationCell #(
  .WIDTH(2)
) exePipe6Isolation
(
  .clampEn(~execLaneActive[6]),
  .signalIn({bypassPacket_a1[6].valid,ctrlPacket_a1[6].valid}),
  .signalOut({bypassPacket[6].valid,ctrlPacket[6].valid}),
  .clampValue(2'b00)
);

// Allow signals other than vaid to be pass throughs
assign bypassPacket[6].tag  = bypassPacket_a1[6].tag;
assign bypassPacket[6].data = bypassPacket_a1[6].data;

assign ctrlPacket[6].seqNo  = ctrlPacket_a1[6].seqNo;
assign ctrlPacket[6].nextPC = ctrlPacket_a1[6].nextPC;
assign ctrlPacket[6].alID   = ctrlPacket_a1[6].alID;
assign ctrlPacket[6].flags  = ctrlPacket_a1[6].flags;
`endif

`endif


`ifdef ISSUE_EIGHT_WIDE
ExecutionPipe_SC #(
	.SIMPLE               (SIMPLE_VECT[7]),
	.COMPLEX              (COMPLEX_VECT[7])
)
	exePipe7 (

	.clk                  (clk),
	.reset                (reset),
  .toggleFlag_o         (toggleFlag[7]),

`ifdef DYNAMIC_CONFIG_AND_WIDTH 
  .laneActive_i         (execLaneActive[7]),
  .saluLaneActive_i     (saluLaneActive[7] & execLaneActive[7]),
  .caluLaneActive_i     (caluLaneActive[7] & execLaneActive[7]),
`endif

	.recoverFlag_i        (recoverFlag),
	.exceptionFlag_i      (exceptionFlag),

	// inputs coming from the register file
	.src1Data_byte0_i     (src1Data_byte0[7]),
	.src1Data_byte1_i     (src1Data_byte1[7]),
	.src1Data_byte2_i     (src1Data_byte2[7]),
	.src1Data_byte3_i     (src1Data_byte3[7]),
	
	.src2Data_byte0_i     (src2Data_byte0[7]),
	.src2Data_byte1_i     (src2Data_byte1[7]),
	.src2Data_byte2_i     (src2Data_byte2[7]),
	.src2Data_byte3_i     (src2Data_byte3[7]),

	// input from the issue queue going to the reg read stage
	.rrPacket_i           (rrPacket_l1[7]),

	// bypasses coming from adjacent execution pipes
	.bypassPacket_i       (bypassPacket),

`ifdef DYNAMIC_CONFIG_AND_WIDTH 
	// bypass going from this pipe to other pipes
	.bypassPacket_o       (bypassPacket_a1[7]),

	// output going to the active list from the simple pipe
	.ctrlPacket_o         (ctrlPacket_a1[7]),
`else
	// bypass going from this pipe to other pipes
	.bypassPacket_o       (bypassPacket[7]),

	// output going to the active list from the simple pipe
	.ctrlPacket_o         (ctrlPacket[7]),
`endif

	// source operands extracted from the packet going to the physical register file
	.phySrc1_o            (phySrc1[7]),
	.phySrc2_o            (phySrc2[7])
);

`ifdef DYNAMIC_CONFIG_AND_WIDTH 
// This cell clamps the output at specific values
// Similar in operation to an isolation cell used
// to clamp signals during power gating. Only the
// valid bits need to be clamped thus leading to
// a very small overheaaad.

PGIsolationCell #(
  .WIDTH(2)
) exePipe7Isolation
(
  .clampEn(~execLaneActive[7]),
  .signalIn({bypassPacket_a1[7].valid,ctrlPacket_a1[7].valid}),
  .signalOut({bypassPacket[7].valid,ctrlPacket[7].valid}),
  .clampValue(2'b00)
);

// Allow signals other than vaid to be pass throughs
assign bypassPacket[7].tag  = bypassPacket_a1[7].tag;
assign bypassPacket[7].data = bypassPacket_a1[7].data;

assign ctrlPacket[7].seqNo  = ctrlPacket_a1[7].seqNo;
assign ctrlPacket[7].nextPC = ctrlPacket_a1[7].nextPC;
assign ctrlPacket[7].alID   = ctrlPacket_a1[7].alID;
assign ctrlPacket[7].flags  = ctrlPacket_a1[7].flags;
`endif


`endif


/************************************************************************************
* agenLsu module has the pipeline latch between Address generation unit and LSU
* stage.
*
************************************************************************************/
/* AgenLsu agenLsu ( */
/* 	.clk                  (clk), */
/* 	.reset                (reset), */
/* 	.flush_i              (recoverFlag | exceptionFlag), */

/* 	.memPacket_i          (memPacket), */
/* 	.memPacket_o          (memPacket_l1) */
/* 	); */


/************************************************************************************
* "lsu" module is the pipeline stage between functional unit-3 (address generator)
*  stage and data cache. The pipeline stage contains load-store address disambiguation
*  logic.
*
*  The module interfaces with AGEN and Writeback modules.
*
************************************************************************************/
// TODO: Store queue data and Load queue data need to converted into RAMs
// TODO: Opportunity for per lane gating present but needs rewriting some 
// code.
LSU lsu (
	.clk                  (clk),
	.reset                (reset),
 
//`ifdef SCRATCH_PAD  
//  .dataScratchAddr_i    (dataScratchAddr_i),
//  .dataScratchWrData_i  (dataScratchWrData_i),
//  .dataScratchWrEn_i    (dataScratchWrEn_i),
//  .dataScratchRdData_o  (dataScratchRdData_o),
//  .dataScratchPadEn_i   (dataScratchPadEn_i),
//`endif  

`ifdef DYNAMIC_CONFIG  
  .dispatchLaneActive_i (dispatchLaneActive),
  .commitLaneActive_i   (commitLaneActive_i),
  .lsqPartitionActive_i (lsqPartitionActive),
`endif  


`ifdef DATA_CACHE
  .dataCacheBypass_i    (dataCacheBypass_i),
  .dcScratchModeEn_i    (dcScratchModeEn_i),

  .dc2memLdAddr_o       (dc2memLdAddr_o     ), // memory read address
  .dc2memLdValid_o      (dc2memLdValid_o    ), // memory read enable
                                           
  .mem2dcLdTag_i        (mem2dcLdTag_i      ), // tag of the incoming datadetermine
  .mem2dcLdIndex_i      (mem2dcLdIndex_i    ), // index of the incoming data
  .mem2dcLdData_i       (mem2dcLdData_i     ), // requested data
  .mem2dcLdValid_i      (mem2dcLdValid_i    ), // indicates the requested data is ready
                                           
  .dc2memStAddr_o       (dc2memStAddr_o     ), // memory read address
  .dc2memStData_o       (dc2memStData_o     ), // memory read address
  .dc2memStByteEn_o     (dc2memStByteEn_o   ), // memory read address
  .dc2memStValid_o      (dc2memStValid_o    ), // memory read enable
                                           
  .mem2dcStComplete_i   (mem2dcStComplete_i ),
  .mem2dcStStall_i      (mem2dcStStall_i    ),

  .stallStCommit_o      (stallStCommit    ),

  .dcScratchWrAddr_i    (dcScratchWrAddr_i),
  .dcScratchWrEn_i      (dcScratchWrEn_i  ),
  .dcScratchWrData_i    (dcScratchWrData_i),
  .dcScratchRdData_o    (dcScratchRdData_o),

`endif    

`ifdef PERF_MON
  `ifdef DATA_CACHE
    .ldMiss_o             (ldMiss),
    .stMiss_o             (stMiss),
  `endif
`endif

	.recoverFlag_i        (recoverFlag | exceptionFlag),
	.backEndReady_i       (backEndReady),

	.lsqPacket_i          (lsqPacket),
	
	.lsqID_o              (lsqID),

	.commitLoad_i         (commitLoad),
	.commitStore_i        (commitStore),

	.memPacket_i          (memPacket),

	.ldqCount_o           (ldqCount),
	.stqCount_o           (stqCount),

	.wbPacket_o           (wbPacket),
	.ldVioPacket_o        (ldVioPacket),

	.ldAddr_o             (ldAddr_o),
	.ldData_i             (ldData_i),
  .ldDataValid_i        (ldDataValid_i),
	.ldEn_o               (ldEn_o),

	.stAddr_o             (stAddr_o),
	.stData_o             (stData_o),
	.stEn_o               (stEn_o)
	);



/************************************************************************************
* "activeList" module is the pipeline stage between Dispatch stage and out-of-order
*  back-end.
*  The module interfaces with Active List, Issue Queue and Load-Store Queue.
*
************************************************************************************/

// NOTE: Not much opportunity for per lane power gating.
// Most of the logic is monolitic except some minor combinational
// logic.

ActiveList activeList(
	.clk                  (clk),
	.reset                (reset),

`ifdef DYNAMIC_CONFIG  
  .dispatchLaneActive_i (dispatchLaneActive),
  .issueLaneActive_i    (issueLaneActive),
  .commitLaneActive_i   (commitLaneActive),
  .alPartitionActive_i  (alPartitionActive),
  .squashPipe_i         (1'b0),
`endif  

//`ifdef DATA_CACHE
//  .stallStCommit_i      (stallStCommit),
//`else
  .stallStCommit_i      (1'b0),
//`endif

	.backEndReady_i       (backEndReady),

	.alPacket_i           (alPacket),

	.alHead_o             (alHead),
	.alTail_o             (alTail),
	.alID_o               (alID),

	.ctrlPacket_i         (ctrlPacket),

	.ldVioPacket_i        (ldVioPacket_l1),

	.activeListCnt_o      (activeListCnt),

	.amtPacket_o          (amtPacket),
`ifdef PERF_MON
  .commitValid_o        (commitValid),
	.totalCommit_o        (totalCommit),
`endif
	.commitStore_o        (commitStore),
	.commitLoad_o         (commitLoad),

	.commitCti_o          (commitCti),
	.actualDir_o          (actualDir_o),
	.ctrlType_o           (ctrlType_o),

	.recoverFlag_o        (recoverFlag),
	.recoverPC_o          (recoverPC),

	.exceptionFlag_o      (exceptionFlag),
	.exceptionPC_o        (exceptionPC),

	.loadViolation_o      (loadViolation)
	);


/************************************************************************************
* "amt" module is the pipeline stage between Dispatch stage and out-of-order
*  back-end.
*  The module interfaces with ActiveList Pipe, Issue Queue and Load-Store Queue.
*
************************************************************************************/

//TODO: Fix the repair mechanism so that it can change dynamically 
// depending upon the number of read ports in AMT and number of
// write ports in RMT. 
// *** Might be able to use all ports (even inactive ones) but this
// might have higer penalty of restoring RAMs and all. Rather just
// use the active ports
ArchMapTable amt(

	.clk                  (clk),

`ifdef DYNAMIC_CONFIG  
	.reset                (reset | loadNewConfig), // Needs to be reset to original mapping
  .commitLaneActive_i   (commitLaneActive),
`else  
	.reset                (reset),
`endif  

	.debugAMTAddr_i       (debugAMTAddr_i),
	.debugAMTRdData_o     (debugAMTRdData_o),
	
	.recoverFlag_i        (recoverFlag),
	.exceptionFlag_i      (exceptionFlag),

	.amtPacket_i          (amtPacket),

	.freedPhyReg_o        (freedPhyReg),
`ifdef DYNAMIC_CONFIG  
	.consolidateFlag_i    (consolidateFlag),
	.logAddr_i	          (logAddr),
	.phyAddr_o	          (phyAddrFromAMT),	
`endif  
	.repairFlag_o         (repairFlag),
	/* .repairPacket_o       (repairPacket) */
	.repairAddr_o         (repairAddr),
	.repairData_o         (repairData)
	);


/**************************************************************************************
* This unit captures all vital counters that can be used to monitor performance.

**************************************************************************************/
`ifdef PERF_MON
 
 PerfMon perfmon (
	.clk                  (clk),
	.reset                (reset),
	.perfMonRegAddr_i     (perfMonRegAddr_i),
	.perfMonRegData_o     (perfMonRegData_o),
  .perfMonRegRun_i      (perfMonRegRun_i),
  .perfMonRegClr_i      (perfMonRegClr_i),
  .perfMonRegGlobalClr_i(perfMonRegGlobalClr_i),
`ifdef DATA_CACHE  
  .loadMiss_i           (ldMiss),
  .storeMiss_i          (stMiss),
  .l2InstFetchReq_i     (dc2memLdValid_o),
`endif  
`ifdef INST_CACHE  
  .instMiss_i           (icMiss),
  .l2DataFetchReq_i     (ic2memReqValid_o),
`endif  
  .commitStore_i        (commitStore),
  .commitLoad_i         (commitLoad),
  .recoverFlag_i        (recoverFlag),
  .loadViolation_i      (loadViolation),
  .totalCommit_i        (totalCommit),
	.ibCount_i            (instBuffCount),
	.flCount_i            (freeListCnt),
	.iqCount_i            (cntInstIssueQ),
	.ldqCount_i           (ldqCount),
	.stqCount_i	          (stqCount),
	.alCount_i            (activeListCnt),
  .fetch1_stall_i       (instBufferFull | ctiQueueFull),   
  .ctiq_stall_i         (ctiQueueFull),    
  .instBuf_stall_i      (instBufferFull), 
  .freelist_stall_i     (freeListEmpty),
  .backend_stall_i      (stallfrontEnd), 
  .ldq_stall_i          (loadStall),     
  .stq_stall_i          (storeStall),     
  .iq_stall_i           (iqStall),      
  .rob_stall_i          (alStall),
	.fs1Fs2Valid_i        (fs1Fs2Valid),     
	.fs2DecValid_i        (fs2DecValid),     
	.renDisValid_i        (renDisValid),     
	.instBufRenValid_i    (instBufRenValid),
	.disIqValid_i         (disIqValid), 
	.iqRegReadValid_i     (iqRegReadValid),
  
  .iqReqCount_i         (iqReqCount),
  .iqIssuedCount_i      (iqIssuedCount)
	);
`endif

`ifdef DYNAMIC_CONFIG
RegisterConsolidate rc (
	.clk			              (clk),
	.reset			            (reset),
	
	.startConsolidate_i	    (beginConsolidation),
	.phyAddrAMT_i           (phyAddrFromAMT),
	.phySrc1_i  	          (phySrc1),
	.phySrc2_i  	          (phySrc2),
  .bypassPacket_i         (bypassPacket),
	.regVal_byte0_i         (src1Data_byte0),
	.regVal_byte1_i         (src1Data_byte1),
	.regVal_byte2_i         (src1Data_byte2),
	.regVal_byte3_i         (src1Data_byte3),

	.logAddr_o		          (logAddr),
	.phySrc1_rd_o		        (phySrc1_PRF),
	.phySrc2_rd_o		        (phySrc2_PRF),
  .bypassPacket_o         (bypassPacket_PRF),
	.consolidateFlag_o      (consolidateFlag),
	.doneConsolidate_o	    (consolidationDone)
);
`endif

/**************************************************************************************
* This is a place holder for the power management unit that will be plugged in
* to control dynamic reconfiguartion of the core
*
*
**************************************************************************************/
`ifdef DYNAMIC_CONFIG
PowerManager PwrMan
  ( 
    .clk                  (clk),
    .reset                (reset),

    .fetchLaneActive_i        (fetchLaneActive_i      ),
    .dispatchLaneActive_i     (dispatchLaneActive_i   ),
    .issueLaneActive_i        (issueLaneActive_i      ),
    .execLaneActive_i         (execLaneActive_i       ),
    .saluLaneActive_i         (saluLaneActive_i       ),
    .caluLaneActive_i         (caluLaneActive_i       ),
    .commitLaneActive_i       (commitLaneActive_i     ),
    .rfPartitionActive_i      (rfPartitionActive_i    ),
    .alPartitionActive_i      (alPartitionActive_i    ),
    .lsqPartitionActive_i     (lsqPartitionActive_i   ),
    .iqPartitionActive_i      (iqPartitionActive_i    ),
    .ibuffPartitionActive_i   (ibuffPartitionActive_i ),


    .reconfigureCore_i        (reconfigureCore_i),
    .stallFetch_i             (stallFetch_i),
    .activeListCnt_i          (activeListCnt),
    .fs1Fs2Valid_i            (fs1Fs2Valid),
    .fs2DecValid_i            (fs2DecValid),
    .instBufRenValid_i        (instBufRenValid),
    .renDisValid_i            (renDisValid),
    .disIqValid_i             (disIqValid),
    .ibuffInsufficientCnt_i   (ibuffInsufficientCnt),

    .consolidationDone_i      (consolidationDone),

    .fetchLaneActive_o        (fetchLaneActive      ),
    .dispatchLaneActive_o     (dispatchLaneActive   ),
    .issueLaneActive_o        (issueLaneActive      ),
    .execLaneActive_o         (execLaneActive       ),
    .saluLaneActive_o         (saluLaneActive       ),
    .caluLaneActive_o         (caluLaneActive       ),
    .commitLaneActive_o       (commitLaneActive     ),
    .rfPartitionActive_o      (rfPartitionActive    ),
    .alPartitionActive_o      (alPartitionActive    ),
    .lsqPartitionActive_o     (lsqPartitionActive   ),
    .iqPartitionActive_o      (iqPartitionActive    ),
    .ibuffPartitionActive_o   (ibuffPartitionActive ),


    .reconfigureFlag_o        (reconfigureFlag),
    .loadNewConfig_o          (loadNewConfig),
    .drainPipeFlag_o          (stallFetch),
    .beginConsolidation_o     (beginConsolidation),
    .reconfigDone_o           (reconfigDone_o),
    .pipeDrained_o            (pipeDrained_o)
  );
`else
  assign stallFetch = stallFetch_i;
`endif

endmodule
