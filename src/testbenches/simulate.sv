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


`timescale 1ns/1ps

//`define PRINT_EN

//`define DUMP_STATS

//`define WAVES

module simulate();

integer CYCLE_COUNT;
integer COMMIT_COUNT;
// Commit count at which the wave dumping begins
parameter START_DUMP_WAVE_COUNT = 269800;

// Commit count at which the wave dumping stops
parameter STOP_DUMP_WAVE_COUNT  = 369800;

//* Stop Simulation when COMMIT_COUNT >= SIM_STOP_COUNT
//`ifdef SCRATCH_EN
//  parameter SIM_STOP_COUNT      = 100;
//`else
  parameter SIM_STOP_COUNT      = 1_000_000;
//`endif

//* Print when (COMMIT_COUNT >= COMMIT_PRINT_COUNT) && (CYCLE_COUNT >= CYCLE_PRINT_COUNT)
parameter COMMIT_PRINT_COUNT  = 686000;
parameter CYCLE_PRINT_COUNT   = 0;
parameter PHASE_INTERVAL_COUNT     = 1_000;
parameter STAT_PRINT_COUNT    = 10_000;

parameter CLKPERIOD           =  `CLKPERIOD;

//`ifdef SCRATCH_EN
//  parameter INST_SCRATCH_ENABLED = 1;
//  parameter DATA_SCRATCH_ENABLED = 1;
//`else
  parameter INST_SCRATCH_ENABLED = 0;
  parameter DATA_SCRATCH_ENABLED = 0;
//`endif

`ifdef INST_CACHE
  parameter INST_CACHE_BYPASS = 0;
`else
  parameter INST_CACHE_BYPASS = 1;
`endif

`ifdef DATA_CACHE
  parameter DATA_CACHE_BYPASS = 0;
`else
  parameter DATA_CACHE_BYPASS = 1;
`endif


reg clk;
reg reset;

`ifdef PERF_MON
  reg [`REG_DATA_WIDTH-1:0] perfMonRegAddr; 
  reg [31:0]                perfMonRegData; 
  reg                       perfMonRegRun ;
  reg                       perfMonRegClr ;
  reg                       perfMonRegGlobalClr ;
`endif

//`define WAVES
`ifdef WAVES
  reg dumpWave;
  initial
  begin
    dumpWave = 1'b0;
  end

  always @(*)
    dumpWave = ((COMMIT_COUNT >= START_DUMP_WAVE_COUNT) && (COMMIT_COUNT <= STOP_DUMP_WAVE_COUNT));

  always @(posedge dumpWave)
  begin
    $shm_open("waves.shm");
    $shm_probe(simulate, "ACM");
    //$dumpfile("waves.vcd");
    //$dumpvars(0,fabScalar);
    //$dumplimit(600000000);
  end

  always @(negedge dumpWave)
  begin
    $shm_close("waves.shm");
  end
`endif //WAVES


// Following defines the clk for the simulation.
always #(CLKPERIOD/2.0) 
begin
  clk = ~clk;
end


reg  [`SIZE_DATA-1:0]              LOGICAL_REG [`SIZE_RMT-1:0];
reg  [`SIZE_DATA-1:0]              PHYSICAL_REG [`SIZE_PHYSICAL_TABLE-1:0];
reg  [`SIZE_PC-1:0]                startPC;
reg                                resetFetch;
reg                                verifyCommits;
reg                                cacheModeOverride; //If 1 -> Forces caches to operate in CACHE mode
reg                                stallFetch;

`ifdef DYNAMIC_CONFIG
  // Power management signals
  reg  [`FETCH_WIDTH-1:0]            fetchLaneActive;
  reg  [`DISPATCH_WIDTH-1:0]         dispatchLaneActive;
  reg  [`ISSUE_WIDTH-1:0]            issueLaneActive;
  reg  [`EXEC_WIDTH-1:0]             execLaneActive;
  reg  [`EXEC_WIDTH-1:0]             saluLaneActive;
  reg  [`EXEC_WIDTH-1:0]             caluLaneActive;
  reg  [`COMMIT_WIDTH-1:0]           commitLaneActive;
  reg  [`NUM_PARTS_RF-1:0]           rfPartitionActive;
  reg  [`NUM_PARTS_RF-1:0]           alPartitionActive;
  reg  [`STRUCT_PARTS_LSQ-1:0]       lsqPartitionActive;
  reg  [`STRUCT_PARTS-1:0]           iqPartitionActive;
  reg  [`STRUCT_PARTS-1:0]           ibuffPartitionActive;
  reg                                reconfigureCore;
`endif

//`ifdef SCRATCH_PAD
//  reg [`DEBUG_INST_RAM_LOG+`DEBUG_INST_RAM_WIDTH_LOG-1:0]  instScratchAddr;
//  reg [7:0]                       instScratchWrData;  
//  reg                             instScratchWrEn; 
//  reg [`DEBUG_DATA_RAM_LOG+`DEBUG_DATA_RAM_WIDTH_LOG-1:0] dataScratchAddr;
//  reg [7:0]                       dataScratchWrData;  
//  reg                             dataScratchWrEn;  
//  reg [7:0]                       instScratchRdData;  
//  reg [7:0]                       dataScratchRdData;  
//  reg                             instScratchPadEn = INST_SCRATCH_ENABLED;
//  reg                             dataScratchPadEn = DATA_SCRATCH_ENABLED;
//`endif

  logic                           instCacheBypass = INST_CACHE_BYPASS;
  logic                           icScratchModeEn;
`ifdef INST_CACHE
  logic [`ICACHE_SIZE_MEM_ADDR-1:0]ic2memReqAddr;     // memory read address
  logic                           ic2memReqValid;     // memory read enable
  logic [`ICACHE_TAG_BITS-1:0]    mem2icTag;          // tag of the incoming data
  logic [`ICACHE_INDEX_BITS-1:0]  mem2icIndex;        // index of the incoming data
  logic [`ICACHE_LINE_SIZE-1:0]   mem2icData;         // requested data
  logic                           mem2icRespValid;    // requested data is ready
`endif  

  logic                              dataCacheBypass = DATA_CACHE_BYPASS;
  logic                              dcScratchModeEn;
`ifdef DATA_CACHE
  logic [`DCACHE_SIZE_MEM_ADDR-1:0]  dc2memLdAddr;  // memory read address
  logic                              dc2memLdValid; // memory read enable
  logic [`DCACHE_TAG_BITS-1:0]       mem2dcLdTag;       // tag of the incoming datadetermine
  logic [`DCACHE_INDEX_BITS-1:0]     mem2dcLdIndex;     // index of the incoming data
  logic [`DCACHE_LINE_SIZE-1:0]      mem2dcLdData;      // requested data
  logic                              mem2dcLdValid;     // indicates the requested data is ready
  logic [`DCACHE_SIZE_ST_ADDR-1:0]   dc2memStAddr;  // memory read address
  logic [`SIZE_DATA-1:0]             dc2memStData;  // memory read address
  logic [3:0]                        dc2memStByteEn;  // memory read address
  logic                              dc2memStValid; // memory read enable
  logic                              mem2dcStComplete;
`endif

initial 
begin:INIT_TB
  int i;

  reset                = 1'b0;
  resetFetch           = 1'b0;
  verifyCommits        = 1'b0;
  stallFetch           = 1'b0;
`ifdef DYNAMIC_CONFIG
  reconfigureCore      = 1'b0;
`endif


  //if(!INST_SCRATCH_ENABLED)
  //begin
    $initialize_sim();
    $copyMemory();
  //end

//  $display("");
//  $display("");
//  $display("**********   ******   ********     *******    ********   ******   ****         ******   ********  ");
//  $display("*        *  *      *  *       *   *      *   *       *  *      *  *  *        *      *  *       * ");
//  $display("*  ******* *   **   * *  ***   * *   *****  *   ****** *   **   * *  *       *   **   * *  ***   *");
//  $display("*  *       *  *  *  * *  *  *  * *  *       *  *       *  *  *  * *  *       *  *  *  * *  *  *  *");
//  $display("*  *****   *  ****  * *  ***   * *   ****   *  *       *  ****  * *  *       *  ****  * *  ***   *");
//  $display("*      *   *        * *       *   *      *  *  *       *        * *  *       *        * *       * ");
//  $display("*  *****   *  ****  * *  ***   *   ****   * *  *       *  ****  * *  *       *  ****  * *  ***   *");
//  $display("*  *       *  *  *  * *  *  *  *       *  * *  *       *  *  *  * *  *       *  *  *  * *  *  *  *");
//  $display("*  *       *  *  *  * *  ***   *  *****   * *   ****** *  *  *  * *  ******* *  *  *  * *  *  *  *");
//  $display("*  *       *  *  *  * *       *   *      *   *       * *  *  *  * *        * *  *  *  * *  *  *  *");
//  $display("****       ****  **** ********    *******     ******** ****  **** ********** ****  **** ****  ****");
//  $display("");
//  $display("FabScalar Copyright (c) 2007-2012 by Niket K. Choudhary, Brandon H. Dwiel, and Eric Rotenberg.");
//  $display("All Rights Reserved.");
//  $display("");
//  $display("");


  $display("");
  $display("");
  $display("                   ###    ##    ## ##    ##  ######   #######  ########  ######## "); 
  $display("                  ## ##   ###   ##  ##  ##  ##    ## ##     ## ##     ## ##       "); 
  $display("                 ##   ##  ####  ##   ####   ##       ##     ## ##     ## ##       "); 
  $display("                ##     ## ## ## ##    ##    ##       ##     ## ########  ######   "); 
  $display("                ######### ##  ####    ##    ##       ##     ## ##   ##   ##       "); 
  $display("                ##     ## ##   ###    ##    ##    ## ##     ## ##    ##  ##       "); 
  $display("                ##     ## ##    ##    ##     ######   #######  ##     ## ######## "); 
  $display("");
  $display("AnyCore Copyright (c) 20011-2016 by Rangeen Basu Roy Chowdhury, Anil K. Kannepalli, and Eric Rotenberg.");
  $display("AnyCore was derived from AnyCore Copyright (c) 2007-2016 by Niket K. Choudhary, Brandon H. Dwiel,");
  $display("                            and Eric Rotenberg. All Rights Reserved.");
  $display("");
  $display("");


  //if(!INST_SCRATCH_ENABLED)
  //begin
    for (i = 0; i < `SIZE_RMT-2; i = i + 1)
    begin
      LOGICAL_REG[i]               = $getArchRegValue(i);
    end

    LOGICAL_REG[32]                = $getArchRegValue(65);
    LOGICAL_REG[33]                = $getArchRegValue(64);

    init_registers();
    $funcsimRunahead();
  //end

  clk                            = 0;

  // Initialize the caches to SCRATCH mode
  // NOTE: This is not required in fab_top mode as 
  // they initialize to SCRATCH mode by default
  `ifdef INST_CACHE
    icScratchModeEn       = 1'b1;
  `endif
  `ifdef DATA_CACHE
    dcScratchModeEn       = 1'b1;
  `endif  

  // Assert reset
  #(15*CLKPERIOD) 
  reset                 = 1;
  
  `ifdef PERF_MON
    perfMonRegAddr      = 8'h00;
    perfMonRegClr       = 1'b0;
    perfMonRegRun       = 1'b0;
    perfMonRegGlobalClr = 1'b0;
  `endif

  // Release reset asynchronously to make sure it works
  #(10*CLKPERIOD-4) 
  reset                 = 0;
  #4;

  `ifdef INST_CACHE
  
    // Let the core run in BIST mode for a while before reconfiguring and loading benchmarks/microkernel
    #(500*CLKPERIOD)
  
    stallFetch            = 1'b1;
    #(500*CLKPERIOD)  //Enough time to drain pipeline
    //Reset fetch to start fetching from PC 0x0000 (to load checkpoint and benchmark)
    resetFetch            = 1'b1;
    #(200*CLKPERIOD)  //Enough time to drain pipeline

  `else // If in perfect cache mode

    resetFetch            = 1'b0;
    verifyCommits         = 1'b1;
    stallFetch            = 1'b0;
  `ifdef DYNAMIC_CONFIG
    reconfigureCore       = 1'b0;
  `endif

  `endif

  //// If in microbenchmark mode, load the kernel and data into scratch pads (or caches)
  //if(INST_SCRATCH_ENABLED)
  //begin
  //  // Stall the fetch before loading microbenchmark
  ////`ifdef DYNAMIC_CONFIG
  //  #CLKPERIOD
  //  stallFetch           = 1'b1;  
  //  #(2*CLKPERIOD)
  ////`endif

  //  //$readmemh("kernel.dat",fabScalar.fs1.l1icache.ic.ram);
  //  //$readmemh("data.dat",fabScalar.lsu.datapath.ldx_path.L1dCache.dc.ram); 
  //  //for (i = 0; i < 256; i = i + 1)
  //  //begin
  //  //    $display("@%d: %08x", i, fabScalar.lsu.datapath.ldx_path.L1dCache.dc.ram[i]);
  //  //end
  //  `ifdef SCRATCH_PAD
	//	  load_kernel_scratch();
	//	  instScratchWrEn   = 0;   
	//	  read_kernel_scratch();
	//	  
	//	  load_data_scratch();
	//	  dataScratchWrEn   = 0;   
	//	  read_data_scratch();
  //  `endif

  //  //Unstall the fetch once loading is complete loading microbenchmark
  //  #(2*CLKPERIOD)
  ////`ifdef DYNAMIC_CONFIG
  //  stallFetch           = 1'b0;  
  ////`endif
  //  resetFetch           = 1'b0;
  //  //TODO: Wait for pipeline to be empty
  //  verifyCommits        = 1'b1;
  //end
  //// If not in microbenchmark mode, change the cache mode else let it run un SCRATCH mode
  //else 
  //begin
    `ifdef INST_CACHE

      icScratchModeEn      = 1'b0;
      dcScratchModeEn      = 1'b0;
      #(2*CLKPERIOD)
      //TODO: Wait for pipeline to be empty
      verifyCommits        = 1'b1;
      stallFetch           = 1'b0;
      resetFetch           = 1'b0;
      #(2*CLKPERIOD)
      // If not in microbenchmark mode, let the core run in CACHE mode for a while with actual 
      // benchmark before reconfiguring
      #(1000*CLKPERIOD)
      //Change mode of the caches
      dcScratchModeEn      = 1'b0; // Dummy statement to avoid error. Doesn't really do anything

    `endif
  //end


//load_checkpoint_PRF();
//read_checkpoint_PRF();
  
`ifdef DYNAMIC_CONFIG


  // Stall the fetch before reconfiguring
  // TODO: Test that it works without this as well
  #CLKPERIOD
  stallFetch           = 1'b1;  
  #(10*CLKPERIOD)

  `ifdef DYNAMIC_WIDTH
    fetchLaneActive  =       `FETCH_LANE_ACTIVE     ; 
    dispatchLaneActive  =    `DISPATCH_LANE_ACTIVE  ; 
    issueLaneActive  =       `ISSUE_LANE_ACTIVE     ; 
    execLaneActive  =        `EXEC_LANE_ACTIVE      ; 
    saluLaneActive  =        `SALU_LANE_ACTIVE      ;
    caluLaneActive  =        `CALU_LANE_ACTIVE      ;
    commitLaneActive  =      `COMMIT_LANE_ACTIVE    ; 
  `else
    fetchLaneActive  =       0  ; 
    dispatchLaneActive  =    0  ; 
    issueLaneActive  =       0  ; 
    execLaneActive  =        0  ; 
    saluLaneActive  =        0  ;
    caluLaneActive  =        0  ;
    commitLaneActive  =      0  ; 
  `endif

  `ifdef DYNAMIC_SIZE
    rfPartitionActive  =     `RF_PARTITION_ACTIVE   ; 
    alPartitionActive  =     `AL_PARTITION_ACTIVE   ; 
    lsqPartitionActive  =    `LSQ_PARTITION_ACTIVE  ; 
    iqPartitionActive  =     `IQ_PARTITION_ACTIVE   ; 
    ibuffPartitionActive  =  `IBUFF_PARTITION_ACTIVE;
  `else
    rfPartitionActive  =     0; 
    alPartitionActive  =     0; 
    lsqPartitionActive  =    0; 
    iqPartitionActive  =     0; 
    ibuffPartitionActive  =  0;
  `endif

  reconfigureCore           = 1'b1;



  #(3*CLKPERIOD)
  reconfigureCore      = 1'b0;
  #CLKPERIOD
  stallFetch           = 1'b0;

`endif 

`ifdef PERF_MON
  read_perf_mon();
`endif  

end


reg  [`SIZE_PC-1:0]                instPC [0:`FETCH_WIDTH-1];
reg  [`SIZE_INSTRUCTION-1:0]       inst   [0:`FETCH_WIDTH-1];

wire [`SIZE_PC-1:0]                ldAddr;
wire [`SIZE_DATA-1:0]              ldData;
wire                               ldEn;

wire [`SIZE_PC-1:0]                stAddr;
wire [`SIZE_DATA-1:0]              stData;
wire [3:0]                         stEn;

reg [`SIZE_DATA_BYTE_OFFSET+`SIZE_PHYSICAL_LOG-1:0] debugPRFAddr  ;
reg [`SRAM_DATA_WIDTH-1:0] 			   debugPRFWrData;             
reg 					                     debugPRFWrEn  = 1'b0;
reg [`SRAM_DATA_WIDTH-1:0] 			   debugPRFRdData;


FABSCALAR fabScalar(

    .clk                                 (clk),
    .reset                               (reset),
    .resetFetch_i                        (resetFetch), 
    .toggleFlag_o                        (toggleFlag),

`ifdef SCRATCH_PAD
    .instScratchAddr_i                  (instScratchAddr),
    .instScratchWrData_i                (instScratchWrData),
    .instScratchWrEn_i                  (instScratchWrEn),
    .instScratchRdData_o                (instScratchRdData),
    .dataScratchAddr_i                  (dataScratchAddr),
    .dataScratchWrData_i                (dataScratchWrData),
    .dataScratchWrEn_i                  (dataScratchWrEn),
    .dataScratchRdData_o                (dataScratchRdData),
    .instScratchPadEn_i                 (instScratchPadEn),
    .dataScratchPadEn_i                 (dataScratchPadEn),
`endif

`ifdef INST_CACHE
    .ic2memReqAddr_o                    (ic2memReqAddr     ),    // memory read address
    .ic2memReqValid_o                   (ic2memReqValid    ),    // memory read enable
    .mem2icTag_i                        (mem2icTag         ),    // tag of the incoming data
    .mem2icIndex_i                      (mem2icIndex       ),    // index of the incoming data
    .mem2icData_i                       (mem2icData        ),    // requested data
    .mem2icRespValid_i                  (mem2icRespValid   ),    // requested data is ready
    .instCacheBypass_i                  (instCacheBypass   ),
    .icScratchModeEn_i                  (icScratchModeEn   ),

    .icScratchWrAddr_i                   ($random%1024),
    .icScratchWrEn_i                     (1'b0),
    .icScratchWrData_i                   (8'bxxxx),
    .icScratchRdData_o                   (),
`endif  

`ifdef DATA_CACHE
    .dc2memLdAddr_o                     (dc2memLdAddr     ), // memory read address
    .dc2memLdValid_o                    (dc2memLdValid    ), // memory read enable
                                                           
    .mem2dcLdTag_i                      (mem2dcLdTag      ), // tag of the incoming datadetermine
    .mem2dcLdIndex_i                    (mem2dcLdIndex    ), // index of the incoming data
    .mem2dcLdData_i                     (mem2dcLdData     ), // requested data
    .mem2dcLdValid_i                    (mem2dcLdValid    ), // indicates the requested data is ready
                                                           
    .dc2memStAddr_o                     (dc2memStAddr     ), // memory read address
    .dc2memStData_o                     (dc2memStData     ), // memory read address
    .dc2memStByteEn_o                   (dc2memStByteEn   ), // memory read address
    .dc2memStValid_o                    (dc2memStValid    ), // memory read enable
                                                           
    .mem2dcStComplete_i                 (mem2dcStComplete ),
    .mem2dcStStall_i                    (1'b0),
    .dataCacheBypass_i                  (dataCacheBypass  ),
    .dcScratchModeEn_i                  (dcScratchModeEn  ),

    .dcScratchWrAddr_i                   ($random%1024),
    .dcScratchWrEn_i                     (1'b0),
    .dcScratchWrData_i                   (8'bxxxx),
    .dcScratchRdData_o                   (),
`endif    

    .stallFetch_i                        (stallFetch), 
`ifdef DYNAMIC_CONFIG
    .fetchLaneActive_i                   (fetchLaneActive), 
    .dispatchLaneActive_i                (dispatchLaneActive), 
    .issueLaneActive_i                   (issueLaneActive), 
    .execLaneActive_i                    (issueLaneActive),
    .saluLaneActive_i                    (saluLaneActive),
    .caluLaneActive_i                    (caluLaneActive),
    .commitLaneActive_i                  (commitLaneActive), 
    .rfPartitionActive_i                 (rfPartitionActive),
    .alPartitionActive_i                 (alPartitionActive),
    .lsqPartitionActive_i                (lsqPartitionActive),
    .iqPartitionActive_i                 (iqPartitionActive),
    .ibuffPartitionActive_i              (ibuffPartitionActive),
    .reconfigureCore_i                   (reconfigureCore),
    .reconfigDone_o                      (reconfigDone),
`endif
`ifdef PERF_MON
    .perfMonRegAddr_i                    (perfMonRegAddr),
    .perfMonRegData_o                    (perfMonRegData),
    .perfMonRegRun_i                     (perfMonRegRun),
    .perfMonRegClr_i                     (perfMonRegClr),
    .perfMonRegGlobalClr_i               (perfMonRegGlobalClr),
`endif

    .startPC_i                           (startPC),

    .instPC_o                            (instPC),
    .fetchReq_o                          (instReq), //Useful in case of CHIP simulations
    .fetchRecoverFlag_o                  (), //Useful in case of CHIP simulations
    .inst_i                              (inst),  // Send Xs to make sure this is not source 
    .instValid_i                         (instCacheBypass ? 1'b1 : 1'bx), //Constant in case of unit simulation, not in case of CHIP simulation

    .ldAddr_o                            (ldAddr),
    .ldData_i                            (ldData),
    .ldDataValid_i                       (ldEn), //Loopback
    .ldEn_o                              (ldEn),

    .stAddr_o                            (stAddr),
    .stData_o                            (stData),
    .stEn_o                              (stEn),

    .debugPRFAddr_i                      (debugPRFAddr),
    .debugPRFWrData_i                    (debugPRFWrData),             
    .debugPRFWrEn_i                      (debugPRFWrEn),
    .debugPRFRdData_o                    (debugPRFRdData),

    .debugAMTAddr_i                      ('b0),

    /* Initialize the PRF from top */
    .dbAddr_i                            ({`SIZE_PHYSICAL_LOG{1'b0}}),
    .dbData_i                            ({`SIZE_DATA{1'b0}}),
    .dbWe_i                              (1'b0)

 );

memory_hier mem (
    .icClk                               (clk),
    .dcClk                               (clk),
    .reset                               (reset),
//
//    .icPC_i                              (instPC),
//    .icInst_o                            (inst),
//
//    .ldAddr_i                            (ldAddr),
//    .ldData_o                            (ldData),
//    .ldEn_i                              (ldEn),
//
//    .stAddr_i                            (stAddr),
//    .stData_i                            (stData),
//    .stEn_i                              (stEn)
//);

    .icPC_i                              (instPC),
    .icInstReq_i                         (instReq & (INST_SCRATCH_ENABLED ? 1'b0 : 1'b1)), //Mask requests to prevent crash
    .icInst_o                            (inst),

  `ifdef INST_CACHE
    .ic2memReqAddr_i                     (ic2memReqAddr),
    .ic2memReqValid_i                    (ic2memReqValid),
    .mem2icTag_o                         (mem2icTag), 
    .mem2icIndex_o                       (mem2icIndex),     
    .mem2icData_o                        (mem2icData),      
    .mem2icRespValid_o                   (mem2icRespValid), 
  `endif

  `ifdef DATA_CACHE
    .dc2memLdAddr_i                      (dc2memLdAddr     ), // memory read address
    .dc2memLdValid_i                     (dc2memLdValid    ), // memory read enable
                                                            
    .mem2dcLdTag_o                       (mem2dcLdTag      ), // tag of the incoming datadetermine
    .mem2dcLdIndex_o                     (mem2dcLdIndex    ), // index of the incoming data
    .mem2dcLdData_o                      (mem2dcLdData     ), // requested data
    .mem2dcLdValid_o                     (mem2dcLdValid    ), // indicates the requested data is ready
                                                            
    .dc2memStAddr_i                      (dc2memStAddr     ), // memory read address
    .dc2memStData_i                      (dc2memStData     ), // memory read address
    .dc2memStByteEn_i                    (dc2memStByteEn   ), // memory read address
    .dc2memStValid_i                     (dc2memStValid    ), // memory read enable
                                                            
    .mem2dcStComplete_o                  (mem2dcStComplete ),
  `endif    
  
    .ldAddr_i                            (ldAddr),
    .ldData_o                            (ldData),
    .ldEn_i                              (ldEn & (DATA_SCRATCH_ENABLED ? 1'b0 : 1'b1)), //Mask En to prevent crash

    .stAddr_i                            (stAddr),
    .stData_i                            (stData),
    .stEn_i                              (stEn & {4{DATA_SCRATCH_ENABLED ? 1'b0 : 1'b1}}) //Mask En to prevent crash
);


always @(posedge clk)
begin:HANDLE_EXCEPTION
  int i;
  reg [`SIZE_PC-1:0] TRAP_PC;
  if(!INST_SCRATCH_ENABLED) // This is controlled in the testbench
  begin
    // Following code handles the SYSCALL (trap).
    if (fabScalar.activeList.exceptionFlag[0] && (|fabScalar.activeList.alCount))
    begin

      /* Functional simulator is stalled waiting to execute the trap.
       * Signal it to proceed with the trap.
       */

      TRAP_PC = fabScalar.activeList.commitPC[0];

      $display("TRAP (Cycle: %0d PC: %08x Code: %0d)\n",
               CYCLE_COUNT,
               TRAP_PC,
               $getArchRegValue(2));

      if ($getArchRegValue(2) == 1)
      begin
          $display("SS_SYS_exit encountered. Exiting the simulation");

          // Dump performance counters
          `ifdef PERF_MON
            read_perf_mon();
          `endif  

          $finish;
      end

      $handleTrap();

      /* The memory state of the timing simulator is now stale.
       * Copy values from the functional simulator.
       */
      $copyMemory();

      /* Registers of the timing simulator are now stale.
       * Copy values from the functional simulator.
       */
      for (i = 0; i < `SIZE_RMT - 2; i++) 
      begin
        LOGICAL_REG[i]  = $getArchRegValue(i);
      end

      LOGICAL_REG[32]   = $getArchRegValue(65);
      LOGICAL_REG[33]   = $getArchRegValue(64);

      /* Functional simulator is waiting to resume after the trap.
       * Signal it to resume.
       */
      $resumeTrap();

      $getRetireInstPC(1,CYCLE_COUNT,TRAP_PC,0,0,0);
      init_registers;
    end
  end // !INST_SCRATCH_ENABLED

  /* After the SYSCALL is handled by the functional simulator, architectural
   * values from functional simulator should be copied to the Register File.
   */
  if (fabScalar.activeList.exceptionFlag_reg) 
  begin
    $display("CYCLE:%d Exception is High\n", CYCLE_COUNT);
    /* init_registers; */
    /* copyRF; */
    /* copySimRF; */
  end
end

wire    PRINT;
assign  PRINT = (COMMIT_COUNT >= COMMIT_PRINT_COUNT) && (CYCLE_COUNT > CYCLE_PRINT_COUNT);

integer last_commit_cnt;
integer prev_commit_point;
integer phase_mispredicts;
integer fs_commit_count;
integer prev_branch_point;
integer prev_br_mispredict_point;
integer last_cycle_cnt;
integer load_violation_count;
integer br_count;
integer br_mispredict_count;
integer ic_miss;
integer ld_count;
integer ld_miss;
integer st_miss;
integer btb_miss;
integer btb_miss_rtn;
integer fetch1_stall;
integer ctiq_stall;
integer instBuf_stall;
integer freelist_stall;
integer smt_stall;
integer backend_stall;
integer rob_stall;
integer iq_stall;
integer ldq_stall;
integer stq_stall;

real    runtime_ipc        ;
integer total_cycles       ;
integer total_insts        ;
integer int_insts          ;
integer branch_insts       ;
integer branch_misp        ;
integer load_insts         ;
integer store_insts        ;
integer committed_insts    ;
integer committed_int_insts;
integer rob_reads          ;
integer rob_writes         ;
integer rmt_reads          ;
integer rmt_writes         ;
integer iq_reads           ;
integer iq_writes          ;
integer iq_wakeups         ;
integer prf_reads          ;
integer prf_writes         ;
integer ialu_access        ;
integer mul_access         ;
integer btb_reads          ;
integer btb_writes         ;
integer ibuff_reads        ;
integer ibuff_writes       ;
integer ldq_reads          ;
integer ldq_writes         ;
integer stq_reads          ;
integer stq_writes         ;
integer freelist_reads     ;
integer freelist_writes    ;
integer bp_writes          ;
integer ras_reads          ;
integer ras_writes         ;
integer ctiq_reads         ;
integer ctiq_writes        ;
integer amt_writes         ;
integer lane0_access       ;
integer lane1_access       ;
integer lane2_access       ;
integer lane3_access       ;
integer lane4_access       ;
integer fetched_bundles    ;
integer dispatched_bundles ;
integer issued_bundles     ;
integer retired_bundles    ;
integer recovery_count     ;



// cti stats ////////////////////
`define     stat_num_corr           fabScalar.exePipe1.execute.stat_num_corr
`define     stat_num_pred           fabScalar.exePipe1.execute.stat_num_pred
`define     stat_num_cond_corr      fabScalar.exePipe1.execute.stat_num_cond_corr
`define     stat_num_cond_pred      fabScalar.exePipe1.execute.stat_num_cond_pred
`define     stat_num_return_corr    fabScalar.exePipe1.execute.stat_num_return_corr
`define     stat_num_return_pred    fabScalar.exePipe1.execute.stat_num_return_pred
/////////////////////////////////

int     ib_count;
int     fl_count;
int     iq_count;
int     ldq_count;
int     stq_count;
int     al_count;

int     commit_1;
int     commit_2;
int     commit_3;
int     commit_4;

real    ib_avg;
real    fl_avg;
real    iq_avg;
real    ldq_avg;
real    stq_avg;
real    al_avg;

real    ipc;
real    phase_ipc;
real    phase_mispred;
real    phase_mpki;

integer fd0;
integer fd1;
integer fd2;
integer fd3;
integer fd4;
integer fd5;
integer fd6;
integer fd7;
integer fd8;
integer fd9;
integer fd10;
integer fd11;
integer fd12;
integer fd13;
integer fd14;
integer fd16;
integer fd17;
integer fd18;
integer fd19;
integer fd20;
integer fd21;
integer fd22;
integer fd23;
integer fd24;
integer fd25;

initial
begin
    CYCLE_COUNT          = 0;
    COMMIT_COUNT         = 0;
    load_violation_count = 0;
    br_count             = 0;
    br_mispredict_count  = 0;
    ic_miss              = 0;
    ld_count             = 0;
    ld_miss              = 0;
    st_miss              = 0;
    btb_miss             = 0;
    btb_miss_rtn         = 0;
    fetch1_stall         = 0;
    ctiq_stall           = 0;
    instBuf_stall        = 0;
    freelist_stall       = 0;
    smt_stall            = 0;
    backend_stall        = 0;
    rob_stall            = 0;
    iq_stall             = 0;
    ldq_stall            = 0;
    stq_stall            = 0;
    last_commit_cnt      = 0;
    prev_commit_point    = 0;
    prev_branch_point    = 0;
    prev_br_mispredict_point = 0;
    last_cycle_cnt       = 0;

    ib_count             = 0;
    fl_count             = 0;
    iq_count             = 0;
    ldq_count            = 0;
    stq_count            = 0;
    al_count             = 0;

    commit_1             = 0;
    commit_2             = 0;
    commit_3             = 0;
    commit_4             = 0;

    total_cycles         = 0;
    total_insts          = 0;
    int_insts            = 0;
    branch_insts         = 0;
    branch_misp          = 0;
    load_insts           = 0;
    store_insts          = 0;
    committed_insts      = 0;
    committed_int_insts  = 0;
    rob_reads            = 0;
    rob_writes           = 0;
    rmt_reads            = 0;
    rmt_writes           = 0;
    iq_reads             = 0;
    iq_writes            = 0;
    iq_wakeups           = 0;
    prf_reads            = 0;
    prf_writes           = 0;
    ialu_access          = 0;
    mul_access           = 0;
    btb_reads            = 0;
    btb_writes           = 0;
    ibuff_reads          = 0;
    ibuff_writes         = 0;
    ldq_reads            = 0;
    ldq_writes           = 0;
    stq_reads            = 0;
    stq_writes           = 0;

    freelist_reads       = 0; 
    freelist_writes      = 0; 
    bp_writes            = 0; 
    ras_reads            = 0; 
    ras_writes           = 0; 
    ctiq_reads           = 0; 
    ctiq_writes          = 0; 
    amt_writes           = 0; 
    lane0_access         = 0; 
    lane1_access         = 0; 
    lane2_access         = 0; 
    lane3_access         = 0; 
    lane4_access         = 0; 
    fetched_bundles      = 0; 
    dispatched_bundles   = 0;
    issued_bundles       = 0; 
    retired_bundles      = 0; 
    recovery_count       = 0; 


    fd9         = $fopen("results/fetch1.txt","w");
    fd14        = $fopen("results/fetch2.txt","w");
    fd2         = $fopen("results/decode.txt","w");
    fd1         = $fopen("results/instBuf.txt","w");
    fd0         = $fopen("results/rename.txt","w");
    fd3         = $fopen("results/dispatch.txt","w");
    fd4         = $fopen("results/select.txt","w");
    fd5         = $fopen("results/issueq.txt","w");
    fd6         = $fopen("results/regread.txt","w");
    fd23        = $fopen("results/PhyRegFile.txt","w");
    fd13        = $fopen("results/exe.txt","w");
    fd7         = $fopen("results/activeList.txt","w");
    fd10        = $fopen("results/lsu.txt","w");
    fd8         = $fopen("results/writebk.txt","w");

    fd16        = $fopen("results/statistics.txt","w");
    fd17        = $fopen("results/fabscalar.txt","w");

    fd21        = $fopen("results/stats.txt","w");

    fd24        = $fopen("results/bhr.txt","w");
    fd25        = $fopen("results/specBHR.txt","w");

`ifdef DUMP_STATS
    $fwrite(fd16, "CYCLE, "); 
    $fwrite(fd16, "COMMIT, "); 

    $fwrite(fd16, "IB-avg, "); 
    $fwrite(fd16, "FL-avg, "); 
    $fwrite(fd16, "IQ-avg, "); 
    $fwrite(fd16, "LDQ-avg, "); 
    $fwrite(fd16, "STQ-avg, "); 
    $fwrite(fd16, "AL-avg, "); 

    $fwrite(fd16, "FS1-stall, ");
    $fwrite(fd16, "CTI-stall, ");
    $fwrite(fd16, "IB-stall, ");
    $fwrite(fd16, "FL-stall, ");
    $fwrite(fd16, "BE-stall, ");
    $fwrite(fd16, "LDQ-stall, ");
    $fwrite(fd16, "STQ-stall, ");
    $fwrite(fd16, "IQ-stall, ");
    $fwrite(fd16, "AL-stall, ");

    $fwrite(fd16, "BTB-Miss, ");
    $fwrite(fd16, "Miss-Rtn, ");
    $fwrite(fd16, "BR-Count, ");
    $fwrite(fd16, "Mis-Cnt, ");
    $fwrite(fd16, "LdVio-Cnt, ");

    $fwrite(fd16, "stat_num_corr, ");
    $fwrite(fd16, "stat_num_pred, ");
    $fwrite(fd16, "stat_num_cond_corr, ");
    $fwrite(fd16, "stat_num_cond_pred, ");
    $fwrite(fd16, "stat_num_return_corr, ");
    $fwrite(fd16, "stat_num_return_pred, ");

    $fwrite(fd16, "Commit_1, ");
    $fwrite(fd16, "Commit_2, ");
    $fwrite(fd16, "Commit_3, ");
    $fwrite(fd16, "Commit_4\n");
`endif
end


always @(posedge clk)
begin: HEARTBEAT
    
    CYCLE_COUNT = CYCLE_COUNT + 1;

    COMMIT_COUNT = COMMIT_COUNT + fabScalar.activeList.totalCommit;

    if ((CYCLE_COUNT % STAT_PRINT_COUNT) == 0)
    begin
        ipc = $itor(COMMIT_COUNT)/$itor(CYCLE_COUNT);
        if ((COMMIT_COUNT - last_commit_cnt) == 0)
        begin
            $display("Cycle Count:%d Commit Count:%d IPC:%2.2f BTB-Miss:%d BTB-Miss-Rtn:%d  Br-Count:%d Br-Mispredict:%d Ld Violation: %0d",
                     CYCLE_COUNT,
                     COMMIT_COUNT,
                     ipc,
                     btb_miss,
                     btb_miss_rtn,
                     br_count,
                     br_mispredict_count,
                     load_violation_count);

            $display("ERROR: instruction committing has stalled (Cycle: %0d, Commit: %0d, PC: %x", CYCLE_COUNT, COMMIT_COUNT, fabScalar.activeList.commitPC[0] );
            // Dump performance counters
            `ifdef PERF_MON
              read_perf_mon();
            `endif  

            $finish;
        end

        $display("Cycle: %d Commit: %d IPC:%2.2f BTB-Miss: %0d  BTB-Miss-Rtn: %0d  Br-Count: %0d  Br-Mispredict: %0d Ld Violation: %0d",
                 CYCLE_COUNT,
                 COMMIT_COUNT,
                 ipc,
                 btb_miss,
                 btb_miss_rtn,
                 br_count,
                 br_mispredict_count,
                 load_violation_count);

        
`ifdef DUMP_STATS
        ib_avg    = ib_count/(CYCLE_COUNT-10.0);
        fl_avg    = fl_count/(CYCLE_COUNT-10.0);
        iq_avg    = iq_count/(CYCLE_COUNT-10.0);
        ldq_avg   = ldq_count/(CYCLE_COUNT-10.0);
        stq_avg   = stq_count/(CYCLE_COUNT-10.0);
        al_avg    = al_count/(CYCLE_COUNT-10.0);

        $fwrite(fd16, "%d, ", CYCLE_COUNT); 
        $fwrite(fd16, "%d, ", COMMIT_COUNT); 

        $fwrite(fd16, "%2.3f, ", ib_avg); 
        $fwrite(fd16, "%2.3f, ", fl_avg); 
        $fwrite(fd16, "%2.3f, ", iq_avg); 
        $fwrite(fd16, "%2.4f, ", ldq_avg); 
        $fwrite(fd16, "%2.4f, ", stq_avg); 
        $fwrite(fd16, "%2.3f, ", al_avg); 

        $fwrite(fd16, "%d, ", fetch1_stall); 
        $fwrite(fd16, "%d, ", ctiq_stall); 
        $fwrite(fd16, "%d, ", instBuf_stall); 
        $fwrite(fd16, "%d, ", freelist_stall); 
        $fwrite(fd16, "%d, ", backend_stall); 
        $fwrite(fd16, "%d, ", ldq_stall); 
        $fwrite(fd16, "%d, ", stq_stall); 
        $fwrite(fd16, "%d, ", iq_stall); 
        $fwrite(fd16, "%d, ", rob_stall); 

        $fwrite(fd16, "%d, ", btb_miss); 
        $fwrite(fd16, "%d, ", btb_miss_rtn); 
        $fwrite(fd16, "%d, ", br_count); 
        $fwrite(fd16, "%d, ", br_mispredict_count); 
        $fwrite(fd16, "%d, ", load_violation_count); 

        $fwrite(fd16, "%d, ", `stat_num_corr);
        $fwrite(fd16, "%d, ", `stat_num_pred);
        $fwrite(fd16, "%d, ", `stat_num_cond_corr);
        $fwrite(fd16, "%d, ", `stat_num_cond_pred);
        $fwrite(fd16, "%d, ", `stat_num_return_corr);
        $fwrite(fd16, "%d, ", `stat_num_return_pred);

        $fwrite(fd16, "%d, ", commit_1); 
        $fwrite(fd16, "%d, ", commit_2); 
        $fwrite(fd16, "%d, ", commit_3); 
        $fwrite(fd16, "%d\n", commit_4); 
`endif

        last_commit_cnt = COMMIT_COUNT;
    end

  `ifdef PER_PHASE_STATS

    //if (((COMMIT_COUNT - prev_commit_point) >= PHASE_INTERVAL_COUNT) & (CYCLE_COUNT > 0) & (COMMIT_COUNT != prev_commit_point))
    if (((COMMIT_COUNT - prev_commit_point) >= PHASE_INTERVAL_COUNT) & (CYCLE_COUNT > 0))
    begin
        phase_mispredicts = br_mispredict_count - prev_br_mispredict_point; 
        phase_mispred = 100*$itor(phase_mispredicts)/$itor(br_count - prev_branch_point);
        phase_mpki    = $itor(phase_mispredicts)/$itor(PHASE_INTERVAL_COUNT/1000);
        phase_ipc = $itor(PHASE_INTERVAL_COUNT)/$itor(CYCLE_COUNT-last_cycle_cnt);
        fs_commit_count = $getFSCommitCount();

        $display("Cycle: %d Commit: %d FS Commit: %d PC: 0x%x Phase IPC:%2.2f Mispred:%2.2f MPKI:%2.2f",
                 CYCLE_COUNT,
                 COMMIT_COUNT,
                 fs_commit_count,
                 fabScalar.activeList.commitPC[0],
                 phase_ipc,
                 phase_mispred,
                 phase_mpki);

        last_cycle_cnt  = CYCLE_COUNT;
        prev_commit_point = prev_commit_point + PHASE_INTERVAL_COUNT;
        prev_branch_point = br_count;
        prev_br_mispredict_point = br_mispredict_count;
    end
  `endif

end

fuPkt                           exePacket      [0:`ISSUE_WIDTH-1];

always @(*)
begin

    exePacket[0]      = fabScalar.exePipe0.exePacket;
    exePacket[1]      = fabScalar.exePipe1.exePacket;
    exePacket[2]      = fabScalar.exePipe2.exePacket;
`ifdef ISSUE_FOUR_WIDE
    exePacket[3]      = fabScalar.exePipe3.exePacket;
`endif
end


/* Following maintains all the performance related counters. */
always @(posedge clk)
begin: UPDATE_STATS
    int i;

    if (CYCLE_COUNT > 20 & ~reset )
    begin
        fetch1_stall      = fetch1_stall   + fabScalar.fs1.stall_i;
        ctiq_stall        = ctiq_stall     + fabScalar.fs2.ctiQueueFull;
        instBuf_stall     = instBuf_stall  + fabScalar.instBuf.instBufferFull;
        freelist_stall    = freelist_stall + fabScalar.rename.freeListEmpty;
        backend_stall     = backend_stall  + fabScalar.dispatch.stall;
        ldq_stall         = ldq_stall      + fabScalar.dispatch.loadStall;
        stq_stall         = stq_stall      + fabScalar.dispatch.storeStall;
        iq_stall          = iq_stall       + fabScalar.dispatch.iqStall;
        rob_stall         = rob_stall      + fabScalar.dispatch.alStall;

        btb_miss          = btb_miss       + (~fabScalar.fs1.stall_i & fabScalar.fs1.fs2RecoverFlag_i);
        btb_miss_rtn      = btb_miss_rtn   + (~fabScalar.fs1.stall_i &
                                               fabScalar.fs1.fs2MissedReturn_i &
                                               fabScalar.fs1.fs2RecoverFlag_i);
        for (i = 0; i < `COMMIT_WIDTH; i++)
        begin
            br_count        = br_count       + ((fabScalar.activeList.totalCommit >= (i+1)) & fabScalar.activeList.ctrlAl[i][5]);
            ld_count        = ld_count       + fabScalar.activeList.commitLoad_o[i];
        end

        ic_miss = ic_miss + fabScalar.fs1.icMiss_o;
        ld_miss = ld_miss + fabScalar.lsu.ldMiss_o;
        st_miss = st_miss + fabScalar.lsu.stMiss_o;

        br_mispredict_count =  br_mispredict_count + fabScalar.activeList.mispredFlag_reg;

        load_violation_count = load_violation_count + fabScalar.activeList.violateFlag_reg;

        ib_count  = ib_count  + fabScalar.instBuf.instCount;
        fl_count  = fl_count  + fabScalar.rename.specfreelist.freeListCnt;
        iq_count  = iq_count  + fabScalar.cntInstIssueQ;
        ldq_count = ldq_count + fabScalar.ldqCount;
        stq_count = stq_count + fabScalar.stqCount;
        al_count  = al_count  + fabScalar.activeListCnt;
        
        commit_1  = commit_1  + ((fabScalar.activeList.totalCommit == 1) ? 1'h1: 1'h0);
        commit_2  = commit_2  + ((fabScalar.activeList.totalCommit == 2) ? 1'h1: 1'h0);
        commit_3  = commit_3  + ((fabScalar.activeList.totalCommit == 3) ? 1'h1: 1'h0);
        commit_4  = commit_4  + ((fabScalar.activeList.totalCommit == 4) ? 1'h1: 1'h0);

    end
end

always @(posedge clk)
begin: UPDATE_COUNTS
    int i;
    logic iq_granted          = 1'b0;

    if (COMMIT_COUNT >= COMMIT_PRINT_COUNT)
    begin
        total_cycles        = total_cycles + 1;

        // Instructions in the front end - at dispatch
        for(i=0;i <  2*`FETCH_WIDTH;i=i+2)
        begin
          total_insts       = total_insts         + (fabScalar.instBuf.wrEnGated[i] ? fabScalar.ibPacket[i].valid           : 0);    
          int_insts         = int_insts           + ((fabScalar.instBuf.wrEnGated[i] & (fabScalar.ibPacket[i].fu == `SIMPLE_TYPE)) ? 1 : 0) 
                                                  + ((fabScalar.instBuf.wrEnGated[i] & (fabScalar.ibPacket[i].fu == `COMPLEX_TYPE)) ? 1 : 0);              
          branch_insts      = branch_insts        + ((fabScalar.instBuf.wrEnGated[i] & (fabScalar.ibPacket[i].fu == `CONTROL_TYPE)) ? 1 : 0);
          load_insts        = load_insts          + (fabScalar.instBuf.wrEnGated[i] ? fabScalar.ibPacket[i].isLoad          : 0);
          store_insts       = store_insts         + (fabScalar.instBuf.wrEnGated[i] ? fabScalar.ibPacket[i].isStore         : 0);
        end
        branch_misp         = branch_misp         + fabScalar.activeList.mispredFlag_reg;

        // Committed counts
        committed_insts     = committed_insts     + fabScalar.activeList.totalCommit;
        for(i=0;i <  `COMMIT_WIDTH;i++)
        begin
          committed_int_insts = committed_int_insts + (fabScalar.activeList.amtPacket_o[i].valid & ~fabScalar.activeList.commitLoad_o[i]);
          amt_writes          = amt_writes          + fabScalar.activeList.amtPacket_o[i].valid; 
          freelist_writes     = freelist_writes     + fabScalar.rename.freedPhyReg_i[i].valid; 
        end

        rob_reads           = rob_reads           + (|fabScalar.activeList.commitReady ? `COMMIT_WIDTH : 0);
        rob_writes          = rob_writes          + (fabScalar.backEndReady ? `DISPATCH_WIDTH : 0);

        rmt_reads           = rmt_reads           + (~fabScalar.rename.RMT.stall_i ? 2*`DISPATCH_WIDTH : 0);
        ldq_reads           = ldq_reads           + fabScalar.lsu.datapath.stx_path.replayPacket_o.valid
                                                  + fabScalar.lsu.datapath.stx_path.stxVioPacket_o.valid;
        stq_reads           = stq_reads           + (fabScalar.lsu.datapath.ldPacket.valid & fabScalar.lsu.datapath.ldx_path.stqHit)
                                                  + fabScalar.lsu.datapath.ldx_path.commitSt_i;
        for(i=0;i <  `DISPATCH_WIDTH;i++)
        begin
          rmt_writes        = rmt_writes          + fabScalar.rename.RMT.writeEn[i];
          ldq_writes        = ldq_writes          + (fabScalar.issueq.backEndReady_i ? fabScalar.lsqPacket[i].isLoad : 0);
          stq_writes        = stq_writes          + (fabScalar.issueq.backEndReady_i ? fabScalar.lsqPacket[i].isStore : 0);
          freelist_reads    = freelist_reads      + (~fabScalar.rename.specfreelist.stall_i ? fabScalar.rename.specfreelist.reqPhyReg_i[i] : 0); 
        end

        for(i=0;i <  `ISSUE_WIDTH;i++)
        begin
          iq_reads          = iq_reads            + fabScalar.issueq.grantedEntry[i].valid;
          iq_wakeups        = iq_wakeups          + fabScalar.issueq.rsrTag[i].valid;
          prf_reads         = prf_reads           + (fabScalar.rrPacket[i].valid ? 2 : 0);
          prf_writes        = prf_writes          + fabScalar.bypassPacket[i].valid;
        end
        iq_writes           = iq_writes           + (fabScalar.issueq.backEndReady_i ? `DISPATCH_WIDTH : 0);


        for(i=2;i <  `ISSUE_WIDTH;i++)
        begin
          ialu_access       = ialu_access         + (fabScalar.rrPacket[i].valid & fabScalar.rrPacket[i].isSimple);
          iq_granted        = iq_granted          | fabScalar.rrPacket[i].valid;
        end
        mul_access          = mul_access          + (fabScalar.rrPacket[2].valid & ~fabScalar.rrPacket[2].isSimple);

        btb_reads           = btb_reads           + (~fabScalar.fs1.stall_i ? `FETCH_WIDTH : 0);
        btb_writes          = btb_writes          + fabScalar.fs1.updateBTB;
        bp_writes           = bp_writes           + fabScalar.fs1.updateBPB; 
        ras_reads           = ras_reads           + fabScalar.fs1.popRAS; 
        ras_writes          = ras_writes          + fabScalar.fs1.ras.arch_push + fabScalar.fs1.ras.stack_we; 
        ctiq_reads          = ctiq_reads          + fabScalar.commitCti; 
        ctiq_writes         = ctiq_writes         + fabScalar.exeCtrlValid; 


        ibuff_reads         = ibuff_reads         + (fabScalar.instBuf.instBufferReady_o ? `DISPATCH_WIDTH : 0);
        for(i=0;i <  2*`DISPATCH_WIDTH;i++)
        begin
          ibuff_writes      = ibuff_writes        + fabScalar.instBuf.wrEnGated[i];
        end


        lane0_access         = lane0_access       + fabScalar.rrPacket[0].valid; 
        lane1_access         = lane1_access       + fabScalar.rrPacket[1].valid; 
        lane2_access         = lane2_access       + fabScalar.rrPacket[2].valid; 
        lane3_access         = lane3_access       + fabScalar.rrPacket[3].valid; 
        lane4_access         = lane4_access       + fabScalar.rrPacket[4].valid; 

        fetched_bundles      = fetched_bundles    + (~fabScalar.fs2.stall_i ? fabScalar.decPacket[0].valid : 0); 
        dispatched_bundles   = dispatched_bundles + fabScalar.issueq.backEndReady_i;
        issued_bundles       = issued_bundles     + iq_granted; 
        retired_bundles      = retired_bundles    + ((fabScalar.activeList.totalCommit != 0) ? 1 : 0); 
        recovery_count       = recovery_count     + fabScalar.recoverFlag; 



    end
end

always @(posedge clk)
begin: END_SIMULATION

    if (COMMIT_COUNT >= SIM_STOP_COUNT)
    begin

        ipc = $itor(COMMIT_COUNT)/$itor(CYCLE_COUNT);

        // Before the simulator is terminated, print all the stats:
        $display(" Fetch1-Stall:%d \n Ctiq-Stall:%d \n InstBuff-Stall:%d \n FreeList-Stall:%d \n SMT-Stall:%d \n Backend-Stall:%d \n LDQ-Stall:%d \n STQ-Stall:%d \n IQ-Stall:%d \n ROB-Stall:%d\n",
        fetch1_stall,
        ctiq_stall,
        instBuf_stall,
        freelist_stall,
        smt_stall,
        backend_stall,
        ldq_stall,
        stq_stall,
        iq_stall,
        rob_stall);

        $display("stat_num_corr        %d", `stat_num_corr);
        $display("stat_num_pred        %d", `stat_num_pred);
        $display("stat_num_cond_corr   %d", `stat_num_cond_corr);
        $display("stat_num_cond_pred   %d", `stat_num_cond_pred);
        $display("stat_num_return_corr %d", `stat_num_return_corr);
        $display("stat_num_return_pred %d", `stat_num_return_pred);
        $display("");

        ib_avg    = ib_count/(CYCLE_COUNT-10.0);
        fl_avg    = fl_count/(CYCLE_COUNT-10.0);
        iq_avg    = iq_count/(CYCLE_COUNT-10.0);
        ldq_avg   = ldq_count/(CYCLE_COUNT-10.0);
        stq_avg   = stq_count/(CYCLE_COUNT-10.0);
        al_avg    = al_count/(CYCLE_COUNT-10.0);

        $write(" IB-avg: %2.1f\n", ib_avg); 
        $write(" FL-avg: %2.1f\n", fl_avg); 
        $write(" IQ-avg: %2.1f\n", iq_avg); 
        $write(" LDQ-avg: %2.1f\n", ldq_avg); 
        $write(" STQ-avg: %2.1f\n", stq_avg); 
        $write(" AL-avg: %2.1f\n", al_avg); 

        $display("Cycle Count:%d Commit Count:%d    IPC:%2.2f     BTB-Miss:%d BTB-Miss-Rtn:%d  Br-Count:%d Br-Mispredict:%d IC Miss:%d Ld Count:%d Ld Miss:%d St Miss:%d Ld Violation:%d",
        CYCLE_COUNT,
        COMMIT_COUNT,
        ipc,
        btb_miss,
        btb_miss_rtn,
        br_count,
        br_mispredict_count,
        ic_miss,
        ld_count,
        ld_miss,
        st_miss,
        load_violation_count);

        `ifdef DUMP_STATS
          ib_avg    = ib_count/(CYCLE_COUNT-10.0);
          fl_avg    = fl_count/(CYCLE_COUNT-10.0);
          iq_avg    = iq_count/(CYCLE_COUNT-10.0);
          ldq_avg   = ldq_count/(CYCLE_COUNT-10.0);
          stq_avg   = stq_count/(CYCLE_COUNT-10.0);
          al_avg    = al_count/(CYCLE_COUNT-10.0);

          $fwrite(fd16, "%d, ", CYCLE_COUNT); 
          $fwrite(fd16, "%d, ", COMMIT_COUNT); 

          $fwrite(fd16, "%2.3f, ", ib_avg); 
          $fwrite(fd16, "%2.3f, ", fl_avg); 
          $fwrite(fd16, "%2.3f, ", iq_avg); 
          $fwrite(fd16, "%2.4f, ", ldq_avg); 
          $fwrite(fd16, "%2.4f, ", stq_avg); 
          $fwrite(fd16, "%2.3f, ", al_avg); 

          $fwrite(fd16, "%d, ", fetch1_stall); 
          $fwrite(fd16, "%d, ", ctiq_stall); 
          $fwrite(fd16, "%d, ", instBuf_stall); 
          $fwrite(fd16, "%d, ", freelist_stall); 
          $fwrite(fd16, "%d, ", backend_stall); 
          $fwrite(fd16, "%d, ", ldq_stall); 
          $fwrite(fd16, "%d, ", stq_stall); 
          $fwrite(fd16, "%d, ", iq_stall); 
          $fwrite(fd16, "%d, ", rob_stall); 

          $fwrite(fd16, "%d, ", btb_miss); 
          $fwrite(fd16, "%d, ", btb_miss_rtn); 
          $fwrite(fd16, "%d, ", br_count); 
          $fwrite(fd16, "%d, ", br_mispredict_count); 
          $fwrite(fd16, "%d, ", load_violation_count); 

          $fwrite(fd16, "%d, ", `stat_num_corr);
          $fwrite(fd16, "%d, ", `stat_num_pred);
          $fwrite(fd16, "%d, ", `stat_num_cond_corr);
          $fwrite(fd16, "%d, ", `stat_num_cond_pred);
          $fwrite(fd16, "%d, ", `stat_num_return_corr);
          $fwrite(fd16, "%d, ", `stat_num_return_pred);

          $fwrite(fd16, "%d, ", commit_1); 
          $fwrite(fd16, "%d, ", commit_2); 
          $fwrite(fd16, "%d, ", commit_3); 
          $fwrite(fd16, "%d\n", commit_4); 
        `endif

        runtime_ipc = $itor(committed_insts)/$itor(total_cycles);

        $fwrite(fd21, "[knobs]\n[stats]\n");                     
        $fwrite(fd21, "runtime_ipc        : %8.2f\n", runtime_ipc      );                     
        $fwrite(fd21, "total_cycles       : %d\n", total_cycles        );                     
        $fwrite(fd21, "total_insts        : %d\n", total_insts         );                     
        $fwrite(fd21, "int_insts          : %d\n", int_insts           );  
        $fwrite(fd21, "branch_insts       : %d\n", branch_insts        );  
        $fwrite(fd21, "branch_misp        : %d\n", branch_misp         );  
        $fwrite(fd21, "load_insts         : %d\n", load_insts          );
        $fwrite(fd21, "store_insts        : %d\n", store_insts         );
        $fwrite(fd21, "committed_insts    : %d\n", committed_insts     );  
        $fwrite(fd21, "committed_int_insts: %d\n", committed_int_insts );
        $fwrite(fd21, "rob_reads          : %d\n", rob_reads           );  
        $fwrite(fd21, "rob_writes         : %d\n", rob_writes          );  
        $fwrite(fd21, "rmt_reads          : %d\n", rmt_reads           );  
        $fwrite(fd21, "rmt_writes         : %d\n", rmt_writes          );
        $fwrite(fd21, "iq_reads           : %d\n", iq_reads            );  
        $fwrite(fd21, "iq_writes          : %d\n", iq_writes           );  
        $fwrite(fd21, "iq_wakeups         : %d\n", iq_wakeups          );  
        $fwrite(fd21, "prf_reads          : %d\n", prf_reads           );  
        $fwrite(fd21, "prf_writes         : %d\n", prf_writes          );  
        $fwrite(fd21, "ialu_access        : %d\n", ialu_access         );
        $fwrite(fd21, "mul_access         : %d\n", mul_access          );  
        $fwrite(fd21, "btb_reads          : %d\n", btb_reads           );  
        $fwrite(fd21, "btb_writes         : %d\n", btb_writes          );  
        $fwrite(fd21, "ibuff_reads        : %d\n", ibuff_reads         );  
        $fwrite(fd21, "ibuff_writes       : %d\n", ibuff_writes        );
        $fwrite(fd21, "ldq_reads          : %d\n", ldq_reads           );  
        $fwrite(fd21, "ldq_writes         : %d\n", ldq_writes          );
        $fwrite(fd21, "stq_reads          : %d\n", stq_reads           );  
        $fwrite(fd21, "stq_writes         : %d\n", stq_writes          );

        $fwrite(fd21, "freelist_reads     : %d\n", freelist_reads      ); 
        $fwrite(fd21, "freelist_writes    : %d\n", freelist_writes     ); 
        $fwrite(fd21, "bp_writes          : %d\n", bp_writes           ); 
        $fwrite(fd21, "ras_reads          : %d\n", ras_reads           ); 
        $fwrite(fd21, "ras_writes         : %d\n", ras_writes          ); 
        $fwrite(fd21, "ctiq_reads         : %d\n", ctiq_reads          ); 
        $fwrite(fd21, "ctiq_writes        : %d\n", ctiq_writes         ); 
        $fwrite(fd21, "amt_writes         : %d\n", amt_writes          ); 
        $fwrite(fd21, "lane0_access       : %d\n", lane0_access        ); 
        $fwrite(fd21, "lane1_access       : %d\n", lane1_access        ); 
        $fwrite(fd21, "lane2_access       : %d\n", lane2_access        ); 
        $fwrite(fd21, "lane3_access       : %d\n", lane3_access        ); 
        $fwrite(fd21, "lane4_access       : %d\n", lane4_access        ); 
        $fwrite(fd21, "fetched_bundles    : %d\n", fetched_bundles     ); 
        $fwrite(fd21, "dispatched_bundles : %d\n", dispatched_bundles  );
        $fwrite(fd21, "issued_bundles     : %d\n", issued_bundles      ); 
        $fwrite(fd21, "retired_bundles    : %d\n", retired_bundles     ); 
        $fwrite(fd21, "recovery_count     : %d\n", recovery_count      ); 




        $fclose(fd0);
        $fclose(fd1);
        $fclose(fd2);
        $fclose(fd3);
        $fclose(fd4);
        $fclose(fd5);
        $fclose(fd6);
        $fclose(fd7);
        $fclose(fd8);
        $fclose(fd9);
        $fclose(fd10);
        $fclose(fd11);
        $fclose(fd12);
        $fclose(fd13);
        $fclose(fd14);
        $fclose(fd16);
        $fclose(fd17);
        $fclose(fd18);
        $fclose(fd19);
        $fclose(fd20);
        $fclose(fd21);
        $fclose(fd22);
        $fclose(fd23);

        // Dump performance counters
        `ifdef PERF_MON
          read_perf_mon();
        `endif  

        $finish;
    end
end

`ifdef PRINT_EN

/*  Prints fetch1 stage related latches in a file every cycle. */
always @(posedge clk)
begin : FABSCALAR
    int i;

  if (PRINT)
  begin
        $fwrite(fd9, "------------------------------------------------------\n");
        $fwrite(fd9, "Cycle: %0d  Commit: %0d\n\n",CYCLE_COUNT, COMMIT_COUNT);

`ifdef DYNAMIC_CONFIG
        $fwrite(fd9, "stallFetch: %b\n\n", fabScalar.stallFetch_i);
        $fwrite(fd9, "resetFetch: %b\n\n", fabScalar.resetFetch_i);
`endif        

  end
end
`endif



`ifdef PRINT_EN
btbDataPkt                           btbData       [0:`FETCH_WIDTH-1];

always @(*)
begin
    int i;
    for (i = 0; i < `FETCH_WIDTH; i++)
    begin
        btbData[i]  = fabScalar.fs1.btb.btbData[i];
    end
end

/*  Prints fetch1 stage related latches in a file every cycle. */
always @(posedge clk)
begin : FETCH1
    int i;

  if (PRINT)
  begin
        $fwrite(fd9, "------------------------------------------------------\n");
        $fwrite(fd9, "Cycle: %0d  Commit: %0d\n\n",CYCLE_COUNT, COMMIT_COUNT);

        $fwrite(fd9, "stall_i: %b\n\n", fabScalar.fs1.stall_i);

        $fwrite(fd9, "               -- Next PC --\n\n");
        
        $fwrite(fd9, "PC:             %08x\n",
                fabScalar.fs1.PC);

        $fwrite(fd9, "recoverPC_i:    %08x recoverFlag_i: %b mispredFlag_reg: %b violateFlag_reg: %b\n",
                fabScalar.fs1.recoverPC_i,
                fabScalar.fs1.recoverFlag_i,
                fabScalar.activeList.mispredFlag_reg,
                fabScalar.activeList.violateFlag_reg);

        $fwrite(fd9, "exceptionPC_i:  %08x exceptionFlag_i: %b\n",
                fabScalar.fs1.exceptionPC_i,
                fabScalar.fs1.exceptionFlag_i);

        $fwrite(fd9, "fs2RecoverPC_i: %08x fs2RecoverFlag_i: %b\n",
                fabScalar.fs1.fs2RecoverPC_i,
                fabScalar.fs1.fs2RecoverFlag_i);

        $fwrite(fd9, "nextPC:         %08x\n\n",
                fabScalar.fs1.nextPC);

        $fwrite(fd9, "takenVect:  %04b\n",
                fabScalar.fs1.takenVect);

        $fwrite(fd9, "addrRAS:    %08x\n\n",
                fabScalar.fs1.addrRAS);

        $fwrite(fd9, "               -- BTB --\n\n");
        
        $fwrite(fd9, "\nbtbData       ");
        for (i = 0; i < `FETCH_WIDTH; i++)
            $fwrite(fd9, "     [%1d] ", i);

        $fwrite(fd9, "\ntag           ");
        for (i = 0; i < `FETCH_WIDTH; i++)
            $fwrite(fd9, "%08x ", btbData[i].tag);

        $fwrite(fd9, "\ntakenPC       ");
        for (i = 0; i < `FETCH_WIDTH; i++)
            $fwrite(fd9, "%08x ", btbData[i].takenPC);

        $fwrite(fd9, "\nctrlType      ");
        for (i = 0; i < `FETCH_WIDTH; i++)
            $fwrite(fd9, "%08x ", btbData[i].ctrlType);

        $fwrite(fd9, "\nvalid         ");
        for (i = 0; i < `FETCH_WIDTH; i++)
            $fwrite(fd9, "%08x ", btbData[i].valid);

        $fwrite(fd9, "\n\nupdatePC_i:     %08x\n",
                fabScalar.fs1.updatePC_i);

        $fwrite(fd9, "updateNPC_i:    %08x\n",
                fabScalar.fs1.updateNPC_i);

        $fwrite(fd9, "updateBrType_i: %x\n",
                fabScalar.fs1.updateBrType_i);

        $fwrite(fd9, "updateDir_i:    %b\n",
                fabScalar.fs1.updateDir_i);

        $fwrite(fd9, "updateEn_i:     %b\n\n",
                fabScalar.fs1.updateEn_i);


        $fwrite(fd9, "               -- BP --\n\n");
        
        $fwrite(fd9, "predDir:    %04b\n",
                fabScalar.fs1.predDir);

        $fwrite(fd9, "instOffset[0]:    %x\n",
                fabScalar.fs1.bp.instOffset[0]);

        $fwrite(fd9, "rdAddr         ");
        for (i = 0; i < `FETCH_WIDTH; i++)
            $fwrite(fd9, "%x ", fabScalar.fs1.bp.rdAddr[i]);

        $fwrite(fd9, "\nrdData         ");
        for (i = 0; i < `FETCH_WIDTH; i++)
            $fwrite(fd9, "%x ", fabScalar.fs1.bp.rdData[i]);

        $fwrite(fd9, "\npredCounter    ");
        for (i = 0; i < `FETCH_WIDTH; i++)
            $fwrite(fd9, "%x ", fabScalar.fs1.bp.predCounter[i]);

        $fwrite(fd9, "\n\nwrAddr:        %x\n",
                fabScalar.fs1.bp.wrAddr);

        $fwrite(fd9, "\nwrData:        %x\n",
                fabScalar.fs1.bp.wrData);

        $fwrite(fd9, "\nwrEn         ");
        for (i = 0; i < `FETCH_WIDTH; i++)
            $fwrite(fd9, "%x ", fabScalar.fs1.bp.wrEn[i]);


        $fwrite(fd9, "\n\n               -- RAS --\n\n");
        
        $fwrite(fd9, "pushAddr:   %08x\n",
                fabScalar.fs1.pushAddr);

        $fwrite(fd9, "pushRAS:   %b  popRAS: %b\n",
                fabScalar.fs1.pushRAS,
                fabScalar.fs1.popRAS);

        $fwrite(fd9, "\n\n");

        if (fabScalar.instBufferFull)
            $fwrite(fd9, "instBufferFull:%b\n",
                    fabScalar.instBufferFull);

    if (fabScalar.ctiQueueFull)
      $fwrite(fd9, "ctiQueueFull:%b\n",
              fabScalar.ctiQueueFull);

    if (fabScalar.fs1.recoverFlag_i)

    if(fabScalar.fs1.ras.pop_i)
      $fwrite(fd9, "BTB hit for Rtr instr, spec_tos:%d, Pop Addr: %x",
              fabScalar.fs1.ras.spec_tos,
              fabScalar.fs1.ras.addrRAS_o);

    if (fabScalar.fs1.ras.push_i)
      $fwrite(fd9, "BTB hit for CALL instr, Push Addr: %x",
              fabScalar.fs1.ras.pushAddr_i);

    $fwrite(fd9, "RAS POP Addr:%x\n",
            fabScalar.fs1.ras.addrRAS_o);

    if (fabScalar.fs1.fs2RecoverFlag_i)
      $fwrite(fd9, "Fetch-2 fix BTB miss (target addr): %h\n",
              fabScalar.fs1.fs2RecoverPC_i);

        $fwrite(fd9, "\n\n\n");
  end
end
`endif


`ifdef PRINT_EN
/* Prints fetch2/Ctrl Queue related latches in a file every cycle. */
always_ff @(posedge clk) 
begin : FETCH2
    int i;

  if (PRINT)
  begin
        $fwrite(fd14, "------------------------------------------------------\n");
        $fwrite(fd14, "Cycle: %0d  Commit: %0d\n\n\n",CYCLE_COUNT, COMMIT_COUNT);

    if (fabScalar.fs2.ctiQueue.stall_i)
    begin
      $fwrite(fd14, "Fetch2 is stalled ....\n");
    end

    if (fabScalar.fs2.ctiQueueFull_o)
    begin
      $fwrite(fd14, "CTI Queue is full ....\n");
    end

    $fwrite(fd14, "\n");

    $fwrite(fd14, "Control vector:%b fs1Ready:%b\n",
            fabScalar.fs2.ctiQueue.ctrlVect_i,
            fabScalar.fs2.ctiQueue.fs1Ready_i);


    $fwrite(fd14, "\n");

    $fwrite(fd14, "ctiq Tag0:%d ",
            fabScalar.fs2.ctiQueue.ctiID_o[0]);

`ifdef FETCH_TWO_WIDE
    $fwrite(fd14, "ctiq Tag1:%d ",
            fabScalar.fs2.ctiQueue.ctiID_o[1]);
`endif

`ifdef FETCH_THREE_WIDE
    $fwrite(fd14, "ctiq Tag2:%d ",
            fabScalar.fs2.ctiQueue.ctiID_o[2]);
`endif

`ifdef FETCH_FOUR_WIDE
    $fwrite(fd14, "ctiq Tag3:%d ",
            fabScalar.fs2.ctiQueue.ctiID_o[3]);
`endif

`ifdef FETCH_FIVE_WIDE
    $fwrite(fd14, "ctiq Tag4:%d ",
            fabScalar.fs2.ctiQueue.ctiID_o[4]);
`endif

`ifdef FETCH_SIX_WIDE
    $fwrite(fd14, "ctiq Tag5:%d ",
            fabScalar.fs2.ctiQueue.ctiID_o[5]);
`endif

`ifdef FETCH_SEVEN_WIDE
    $fwrite(fd14, "ctiq Tag6:%d ",
            fabScalar.fs2.ctiQueue.ctiID_o[6]);
`endif

`ifdef FETCH_EIGHT_WIDE
    $fwrite(fd14, "ctiq Tag7:%d ",
            fabScalar.fs2.ctiQueue.ctiID_o[7]);
`endif

        $fwrite(fd14, "\nupdateCounter_i:   %x\n",
                fabScalar.fs1.bp.updateCounter_i);

        $fwrite(fd14, "\ncti.headPtr:       %x\n",
                fabScalar.fs2.ctiQueue.headPtr);

        $fwrite(fd14, "\nctiq.ctiID            ");
        for (i = 0; i < `FETCH_WIDTH; i++)
            $fwrite(fd14, "%x ", fabScalar.fs2.ctiQueue.ctiID[i]);

        $fwrite(fd14, "\nctiq.predCounter_i    ");
        for (i = 0; i < `FETCH_WIDTH; i++)
            $fwrite(fd14, "%x ", fabScalar.fs2.ctiQueue.predCounter_i[i]);

        $fwrite(fd14, "\nctiq.ctrlVect_i       ");
        for (i = 0; i < `FETCH_WIDTH; i++)
            $fwrite(fd14, "%x ", fabScalar.fs2.ctiQueue.ctrlVect_i[i]);

    $fwrite(fd14, "\n\n");

    if (fabScalar.fs2.ctiQueue.exeCtrlValid_i) begin
      $fwrite(fd14, "\nwriting back a control instruction.....\n");

      $fwrite(fd14,"ctiq index:%d target addr:%h br outcome:%b\n\n",
              fabScalar.fs2.ctiQueue.exeCtiID_i,
              fabScalar.fs2.ctiQueue.exeCtrlNPC_i,
              fabScalar.fs2.ctiQueue.exeCtrlDir_i);
    end

    if (fabScalar.fs2.ctiQueue.recoverFlag_i)
    begin
      $fwrite(fd14, "Recovery Flag is High....\n\n");
    end

    if (fabScalar.fs2.ctiQueue.updateEn_o)
    begin
      $fwrite(fd14, "\nupdating the BTB and BPB.....\n");

      $fwrite(fd14, "updatePC:%h updateNPC: %h updateCtrlType:%b updateDir:%b\n\n",
              fabScalar.fs2.ctiQueue.updatePC_o,
              fabScalar.fs2.ctiQueue.updateNPC_o,
              fabScalar.fs2.ctiQueue.updateCtrlType_o,
              fabScalar.fs2.updateDir_o);
    end

    $fwrite(fd14, "ctiq=> headptr:%d tailptr:%d commitPtr:%d instcount:%d commitCnt:%d\n",
            fabScalar.fs2.ctiQueue.headPtr,
            fabScalar.fs2.ctiQueue.tailPtr,
            fabScalar.fs2.ctiQueue.commitPtr,
            fabScalar.fs2.ctiQueue.ctrlCount,
            fabScalar.fs2.ctiQueue.commitCnt);

    $fwrite(fd14, "\n");
  end
end



/*  Prints decode stage related latches in a file every cycle. */
decPkt                     decPacket [0:`FETCH_WIDTH-1];
renPkt                     ibPacket [0:2*`FETCH_WIDTH-1];

always @(*)
begin
    int i;
    for (i = 0; i < `FETCH_WIDTH; i++)
    begin
        decPacket[i]    = fabScalar.decPacket_l1[i];
        ibPacket[2*i]   = fabScalar.ibPacket[2*i];
        ibPacket[2*i+1] = fabScalar.ibPacket[2*i+1];
    end
end

always_ff @(posedge clk)
begin : DECODE
    int i;

    if (PRINT)
    begin
        $fwrite(fd2, "------------------------------------------------------\n");
        $fwrite(fd2, "Cycle: %0d  Commit: %0d\n\n\n",CYCLE_COUNT, COMMIT_COUNT);

        $fwrite(fd2, "fs2Ready_i: %b\n", fabScalar.decode.fs2Ready_i);

        $fwrite(fd2, "\n               -- decPackets --\n");
        
        $fwrite(fd2, "\ndecPacket_i   ");
        for (i = 0; i < `FETCH_WIDTH; i++)
            $fwrite(fd2, "     [%1d] ", i);

        $fwrite(fd2, "\npc:           ");
        for (i = 0; i < `FETCH_WIDTH; i++)
            $fwrite(fd2, "%08x ", decPacket[i].pc);

        $fwrite(fd2, "\nctrlType:     ");
        for (i = 0; i < `FETCH_WIDTH; i++)
            $fwrite(fd2, "      %2x ", decPacket[i].ctrlType);

        $fwrite(fd2, "\nctiID:        ");
        for (i = 0; i < `FETCH_WIDTH; i++)
            $fwrite(fd2, "      %2x ", decPacket[i].ctiID);

        $fwrite(fd2, "\npredNPC:      ");
        for (i = 0; i < `FETCH_WIDTH; i++)
            $fwrite(fd2, "%08x ", decPacket[i].predNPC);

        $fwrite(fd2, "\npredDir:      ");
        for (i = 0; i < `FETCH_WIDTH; i++)
            $fwrite(fd2, "       %1x ", decPacket[i].predDir);

        $fwrite(fd2, "\nvalid:        ");
        for (i = 0; i < `FETCH_WIDTH; i++)
            $fwrite(fd2, "       %1x ", decPacket[i].valid);


        $fwrite(fd2, "\n\n               -- ibPackets --\n");
        
        $fwrite(fd2, "\nibPacket_o    ");
        for (i = 0; i < 2*`FETCH_WIDTH; i++)
            $fwrite(fd2, "     [%1d] ", i);

        $fwrite(fd2, "\npc:           ");
        for (i = 0; i < 2*`FETCH_WIDTH; i++)
            $fwrite(fd2, "%08x ", ibPacket[i].pc);

        $fwrite(fd2, "\nopcode:       ");
        for (i = 0; i < 2*`FETCH_WIDTH; i++)
            $fwrite(fd2, "      %2x ",  ibPacket[i].opcode);

        $fwrite(fd2, "\nlogDest (V):  ");
        for (i = 0; i < 2*`FETCH_WIDTH; i++)
            $fwrite(fd2, "  %2x (%d) ", ibPacket[i].logDest, ibPacket[i].logDestValid);

        $fwrite(fd2, "\nlogSrc1 (V):  ");
        for (i = 0; i < 2*`FETCH_WIDTH; i++)
            $fwrite(fd2, "  %2x (%d) ", ibPacket[i].logSrc1, ibPacket[i].logSrc1Valid);

        $fwrite(fd2, "\nlogSrc2 (V):  ");
        for (i = 0; i < 2*`FETCH_WIDTH; i++)
            $fwrite(fd2, "  %2x (%d) ", ibPacket[i].logSrc2, ibPacket[i].logSrc2Valid);

        $fwrite(fd2, "\nimmed (V):    ");
        for (i = 0; i < 2*`FETCH_WIDTH; i++)
            $fwrite(fd2, "%04x (%d) ", ibPacket[i].immed, ibPacket[i].immedValid);

        $fwrite(fd2, "\nisLoad:       ");
        for (i = 0; i < 2*`FETCH_WIDTH; i++)
            $fwrite(fd2, "       %1x ", ibPacket[i].isLoad);

        $fwrite(fd2, "\nisStore:      ");
        for (i = 0; i < 2*`FETCH_WIDTH; i++)
            $fwrite(fd2, "       %1x ", ibPacket[i].isStore);

        $fwrite(fd2, "\nldstSize:     ");
        for (i = 0; i < 2*`FETCH_WIDTH; i++)
            $fwrite(fd2, "       %1x ", ibPacket[i].ldstSize);

        $fwrite(fd2, "\nctrlType:     ");
        for (i = 0; i < 2*`FETCH_WIDTH; i++)
            $fwrite(fd2, "      %2x ", ibPacket[i].ctrlType);

        $fwrite(fd2, "\nctiID:        ");
        for (i = 0; i < 2*`FETCH_WIDTH; i++)
            $fwrite(fd2, "      %2x ", ibPacket[i].ctiID);

        $fwrite(fd2, "\npredNPC:      ");
        for (i = 0; i < 2*`FETCH_WIDTH; i++)
            $fwrite(fd2, "%08x ", ibPacket[i].predNPC);

        $fwrite(fd2, "\npredDir:      ");
        for (i = 0; i < 2*`FETCH_WIDTH; i++)
            $fwrite(fd2, "       %1x ", ibPacket[i].predDir);

        $fwrite(fd2, "\nvalid:        ");
        for (i = 0; i < 2*`FETCH_WIDTH; i++)
            $fwrite(fd2, "       %1x ", ibPacket[i].valid);

        $fwrite(fd2, "\n\n\n");

    end
end


/*  Prints Instruction Buffer stage related latches in a file every cycle. */
always @(posedge clk)
begin:INSTBUF

  if (PRINT)
  begin
        $fwrite(fd1, "------------------------------------------------------\n");
        $fwrite(fd1, "Cycle: %0d  Commit: %0d\n\n\n",CYCLE_COUNT, COMMIT_COUNT);

    $fwrite(fd1, "Inst Buffer Full:%b freelistEmpty:%b stallFrontEnd:%b\n",
            fabScalar.instBuf.stallFetch_i,
            fabScalar.freeListEmpty,
            fabScalar.stallfrontEnd);

    $fwrite(fd1, "\n");

    $fwrite(fd1, "Decode Ready=%b\n",
            fabScalar.instBuf.decodeReady_i);

    $fwrite(fd1, "instbuffer head=%d instbuffer tail=%d inst count=%d\n",
            fabScalar.instBuf.headPtr,
            fabScalar.instBuf.tailPtr,
            fabScalar.instBuf.instCount);

    $fwrite(fd1, "instBufferReady_o:%b\n",
            fabScalar.instBuf.instBufferReady_o);

    if (fabScalar.recoverFlag)
      $fwrite(fd1, "recoverFlag_i is High\n");

    if (fabScalar.instBuf.flush_i)
      $fwrite(fd1, "flush_i is High\n");

    if (fabScalar.instBuf.instCount > `INST_QUEUE)
    begin
      $fwrite(fd1, "Instruction Buffer overflow\n");
      $display("\n** Cycle: %d Instruction Buffer Overflow **\n",CYCLE_COUNT);
    end

    $fwrite(fd1,"\n");
  end
end


/*  Prints rename stage related latches in a file every cycle. */
disPkt                     disPacket [0:`DISPATCH_WIDTH-1];
phys_reg                   freedPhyReg [0:`COMMIT_WIDTH-1];

always @(*)
begin
    int i;
    for (i = 0; i < `DISPATCH_WIDTH; i++)
    begin
        disPacket[i]    = fabScalar.disPacket[i];
        freedPhyReg[i]  = fabScalar.rename.specfreelist.freedPhyReg_i[i];
    end
end

always @(posedge clk)
begin:RENAME
    int i;

  if (PRINT)
  begin
        $fwrite(fd0, "------------------------------------------------------\n");
        $fwrite(fd0, "Cycle: %0d  Commit: %0d\n\n\n",CYCLE_COUNT, COMMIT_COUNT);

        $fwrite(fd0, "Decode Ready: %b\n",
                fabScalar.rename.decodeReady_i);
                /* fabScalar.rename.branchCount_i); */

    $fwrite(fd0, "freeListEmpty: %b\n",
            fabScalar.rename.freeListEmpty);

        /* disPacket_o */
        $fwrite(fd0, "disPacket_o   ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd0, "     [%1d] ", i);

        $fwrite(fd0, "\npc:           ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd0, "%08x ", disPacket[i].pc);

        $fwrite(fd0, "\nopcode:       ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd0, "      %2x ",  disPacket[i].opcode);

        $fwrite(fd0, "\nfu:           ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd0, "       %1x ", disPacket[i].fu);

        $fwrite(fd0, "\nlogDest:      ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd0, "      %2x ", disPacket[i].logDest);

        $fwrite(fd0, "\nphyDest (V):  ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd0, "  %2x (%d) ", disPacket[i].phyDest, disPacket[i].phyDestValid);

        $fwrite(fd0, "\nphySrc1 (V):  ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd0, "  %2x (%d) ", disPacket[i].phySrc1, disPacket[i].phySrc1Valid);

        $fwrite(fd0, "\nphySrc2 (V):  ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd0, "  %2x (%d) ", disPacket[i].phySrc2, disPacket[i].phySrc2Valid);

        $fwrite(fd0, "\nimmed (V):    ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd0, "%04x (%d) ", disPacket[i].immed, disPacket[i].immedValid);

        $fwrite(fd0, "\nisLoad:       ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd0, "       %1x ", disPacket[i].isLoad);

        $fwrite(fd0, "\nisStore:      ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd0, "       %1x ", disPacket[i].isStore);

        $fwrite(fd0, "\nldstSize:     ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd0, "       %1x ", disPacket[i].ldstSize);

        $fwrite(fd0, "\nctiID:        ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd0, "      %2x ", disPacket[i].ctiID);

        $fwrite(fd0, "\npredNPC:      ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd0, "%08x ", disPacket[i].predNPC);

        $fwrite(fd0, "\npredDir:      ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd0, "       %1x ", disPacket[i].predDir);

        $fwrite(fd0, "\n\nrename ready:%b\n\n", fabScalar.rename.renameReady_o);

        $fwrite(fd0, "               -- Free List (Popped) --\n\n");

        $fwrite(fd0, "freeListHead: %x\n", fabScalar.rename.specfreelist.freeListHead);
        $fwrite(fd0, "freeListTail: %x\n", fabScalar.rename.specfreelist.freeListTail);
        $fwrite(fd0, "freeListCnt: d%d\n", fabScalar.rename.specfreelist.freeListCnt);
        $fwrite(fd0, "pushNumber: d%d\n", fabScalar.rename.specfreelist.pushNumber);
        
        $fwrite(fd0, "\nrdAddr:       ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd0, "      %2x ", fabScalar.rename.specfreelist.readAddr[i]);

        $fwrite(fd0, "\nfreePhyReg:   ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd0, "      %2x ", fabScalar.rename.specfreelist.freePhyReg[i]);

        $fwrite(fd0, "\n\n\n               -- Free List (Pushed) --\n\n");

        $fwrite(fd0, "\nfreedPhyReg (V): ");
        for (i = 0; i < `COMMIT_WIDTH; i++)
            $fwrite(fd0, "      %2x ", freedPhyReg[i].reg_id, freedPhyReg[i].valid);

    $fwrite(fd0,"\n\n\n");
  end
end
`endif


`ifdef PRINT_EN
/* Prints dispatch related signals and latch value. */
disPkt                           disPacket_l1 [0:`DISPATCH_WIDTH-1];
iqPkt                            iqPacket  [0:`DISPATCH_WIDTH-1];
alPkt                            alPacket  [0:`DISPATCH_WIDTH-1];
lsqPkt                           lsqPacket [0:`DISPATCH_WIDTH-1];

always @(*)
begin
    int i;
    for (i = 0; i < `DISPATCH_WIDTH; i++)
    begin
        disPacket_l1[i]               = fabScalar.disPacket_l1[i];
        iqPacket[i]                = fabScalar.iqPacket[i];
        alPacket[i]                = fabScalar.alPacket[i];
        lsqPacket[i]               = fabScalar.lsqPacket[i];
    end
end

always_ff @(posedge clk)
begin:DISPATCH
    int i;

    if (PRINT)
    begin
        $fwrite(fd3, "----------------------------------------------------------------------\n");
        $fwrite(fd3, "Cycle: %d Commit Count: %d\n\n", CYCLE_COUNT, COMMIT_COUNT);

        /* disPacket_i */
        $fwrite(fd3, "disPacket_i   ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "     [%1d] ", i);

        $fwrite(fd3, "\npc:           ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "%08x ", disPacket_l1[i].pc);

        $fwrite(fd3, "\nopcode:       ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "      %2x ",  disPacket_l1[i].opcode);

        $fwrite(fd3, "\nfu:           ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "       %1x ", disPacket_l1[i].fu);

        $fwrite(fd3, "\nlogDest:      ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "      %2x ", disPacket_l1[i].logDest);

        $fwrite(fd3, "\nphyDest (V):  ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "  %2x (%d) ", disPacket_l1[i].phyDest, disPacket_l1[i].phyDestValid);

        $fwrite(fd3, "\nphySrc1 (V):  ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "  %2x (%d) ", disPacket_l1[i].phySrc1, disPacket_l1[i].phySrc1Valid);

        $fwrite(fd3, "\nphySrc2 (V):  ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "  %2x (%d) ", disPacket_l1[i].phySrc2, disPacket_l1[i].phySrc2Valid);

        $fwrite(fd3, "\nimmed (V):    ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "%04x (%d) ", disPacket_l1[i].immed, disPacket_l1[i].immedValid);

        $fwrite(fd3, "\nisLoad:       ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "       %1x ", disPacket_l1[i].isLoad);

        $fwrite(fd3, "\nisStore:      ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "       %1x ", disPacket_l1[i].isStore);

        $fwrite(fd3, "\nldstSize:     ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "       %1x ", disPacket_l1[i].ldstSize);

        $fwrite(fd3, "\nctiID:        ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "      %2x ", disPacket_l1[i].ctiID);

        $fwrite(fd3, "\npredNPC:      ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "%08x ", disPacket_l1[i].predNPC);

        $fwrite(fd3, "\npredDir:      ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "       %1x ", disPacket_l1[i].predDir);

        /* iqPacket_o */
        $fwrite(fd3, "\n\niqPacket_o    ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "     [%1d] ", i);

        $fwrite(fd3, "\npc:           ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "%08x ", iqPacket[i].pc);

        $fwrite(fd3, "\nopcode:       ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "      %2x ",  iqPacket[i].opcode);

        $fwrite(fd3, "\nfu:           ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "       %1x ", iqPacket[i].fu);

        $fwrite(fd3, "\nphyDest (V):  ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "  %2x (%d) ", iqPacket[i].phyDest, iqPacket[i].phyDestValid);

        $fwrite(fd3, "\nphySrc1 (V):  ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "  %2x (%d) ", iqPacket[i].phySrc1, iqPacket[i].phySrc1Valid);

        $fwrite(fd3, "\nphySrc2 (V):  ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "  %2x (%d) ", iqPacket[i].phySrc2, iqPacket[i].phySrc2Valid);

        $fwrite(fd3, "\nimmed (V):    ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "%04x (%d) ", iqPacket[i].immed, iqPacket[i].immedValid);

        $fwrite(fd3, "\nisLoad:       ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "       %1x ", iqPacket[i].isLoad);

        $fwrite(fd3, "\nisStore:      ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "       %1x ", iqPacket[i].isStore);

        $fwrite(fd3, "\nldstSize:     ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "       %1x ", iqPacket[i].ldstSize);

        $fwrite(fd3, "\nctiID:        ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "      %2x ", iqPacket[i].ctiID);

        $fwrite(fd3, "\npredNPC:      ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "%08x ", iqPacket[i].predNPC);

        $fwrite(fd3, "\npredDir:      ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd3, "       %1x ", iqPacket[i].predDir);


    $fwrite(fd3, "\n\nloadCnt: d%d storeCnt: d%d\n",
            fabScalar.dispatch.loadCnt,
            fabScalar.dispatch.storeCnt);

    $fwrite(fd3, "backendReady_o: %b\n",
            fabScalar.dispatch.backEndReady_o);

    if (fabScalar.dispatch.loadStall)       $fwrite(fd3,"LDQ Stall\n");
    if (fabScalar.dispatch.storeStall)      $fwrite(fd3,"STQ Stall\n");
    if (fabScalar.dispatch.iqStall)         $fwrite(fd3,"IQ Stall: IQ Cnt:%d\n",
                                                    fabScalar.dispatch.issueQueueCnt_i);
    if (fabScalar.dispatch.alStall)         $fwrite(fd3,"Active List Stall\n");
    if (~fabScalar.dispatch.renameReady_i)  $fwrite(fd3,"renameReady_i Stall\n");


`ifdef ENABLE_LD_VIOLATION_PRED
    $fwrite(fd3, "predictLdViolation: %b\n",
            fabScalar.dispatch.predLoadVio);

    if (fabScalar.dispatch.ldVioPred.loadViolation_i && fabScalar.dispatch.ldVioPred.recoverFlag_i)
    begin
      $fwrite(fd3, "Update Load Violation Predictor\n");

      $fwrite(fd3, "PC:0x%x Addr:0x%x Tag:0x%x\n",
              fabScalar.dispatch.ldVioPred.recoverPC_i,
              fabScalar.dispatch.ldVioPred.predAddr0wr,
              fabScalar.dispatch.ldVioPred.predTag0wr);
    end
`endif
    $fwrite(fd3,"\n",);
  end
end
`endif


`ifdef PRINT_EN
phys_reg                        phyDest  [0:`DISPATCH_WIDTH-1];
iqEntryPkt                      iqFreeEntry [0:`DISPATCH_WIDTH-1];

iqEntryPkt                      iqFreedEntry   [0:`ISSUE_WIDTH-1];
iqEntryPkt                      iqGrantedEntry [0:`ISSUE_WIDTH-1];
payloadPkt                      rrPacket       [0:`ISSUE_WIDTH-1];

always @(*)
begin
    int i;
    for (i = 0; i < `DISPATCH_WIDTH; i++)
    begin
        phyDest[i]     = fabScalar.phyDest[i];
        iqFreeEntry[i] = fabScalar.issueq.freeEntry[i];
    end

    for (i = 0; i < `ISSUE_WIDTH; i++)
    begin
        iqFreedEntry[i] = fabScalar.issueq.freedEntry[i];
        iqGrantedEntry[i] = fabScalar.issueq.grantedEntry[i];
        rrPacket[i]     = fabScalar.rrPacket[i];
    end
end

/* Prints issue queue related signals and latch values. */
always_ff @(posedge clk)
begin: ISSUEQ
  int i;

    if (PRINT)
    begin
        $fwrite(fd5, "------------------------------------------------------\n");
        $fwrite(fd5, "Cycle: %0d  Commit: %0d\n\n\n",CYCLE_COUNT, COMMIT_COUNT);

`ifdef DYNAMIC_CONFIG
        $fwrite(fd7, "dispatchLaneActive_i: %x\n",
        fabScalar.issueq.dispatchLaneActive_i);

        $fwrite(fd7, "issueLaneActive_i: %x\n",
        fabScalar.issueq.issueLaneActive_i);
`endif        

        $fwrite(fd5, "               -- Dispatched Instructions --\n\n");
        
        $fwrite(fd5, "backEndReady_i:          %b\n", fabScalar.issueq.backEndReady_i);

        /* iqPacket_i */
        $fwrite(fd5, "iqPacket_i        ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "     [%1d] ", i);

        $fwrite(fd5, "\npc:               ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "%08x ", iqPacket[i].pc);

        $fwrite(fd5, "\nopcode:           ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "      %2x ",  iqPacket[i].opcode);

        $fwrite(fd5, "\nfu:               ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "       %1x ", iqPacket[i].fu);

        $fwrite(fd5, "\nphyDest (V):      ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "  %2x (%d) ", iqPacket[i].phyDest, iqPacket[i].phyDestValid);

        $fwrite(fd5, "\nphySrc1 (V):      ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "  %2x (%d) ", iqPacket[i].phySrc1, iqPacket[i].phySrc1Valid);

        $fwrite(fd5, "\nphySrc2 (V):      ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "  %2x (%d) ", iqPacket[i].phySrc2, iqPacket[i].phySrc2Valid);

        $fwrite(fd5, "\nimmed (V):        ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "%04x (%d) ", iqPacket[i].immed, iqPacket[i].immedValid);

        $fwrite(fd5, "\nisLoad:           ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "       %1x ", iqPacket[i].isLoad);

        $fwrite(fd5, "\nisStore:          ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "       %1x ", iqPacket[i].isStore);

        $fwrite(fd5, "\nldstSize:         ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "       %1x ", iqPacket[i].ldstSize);

        $fwrite(fd5, "\nctiID:            ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "      %2x ", iqPacket[i].ctiID);

        $fwrite(fd5, "\npredNPC:          ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "%08x ", iqPacket[i].predNPC);

        $fwrite(fd5, "\npredDir:          ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "       %1x ", iqPacket[i].predDir);

        $fwrite(fd5, "\nfreeEntry:        ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "     d%2d ", iqFreeEntry[i].id);

        $fwrite(fd5, "\nlsqID:            ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "      %2x ", fabScalar.lsqID[i]);

        $fwrite(fd5, "\nalID:             ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "      %2x ", fabScalar.alID[i]);

        /* phyDest_i */
        $fwrite(fd5, "\n\nphyDest_i         ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "     [%1d] ", i);

        $fwrite(fd5, "\nreg_id (V):       ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "  %2x (%1x) ", phyDest[i].reg_id, phyDest[i].valid);

        $fwrite(fd5, "\nnewSrc1Ready:     ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "       %b ", fabScalar.issueq.newSrc1Ready[i]);
 
        $fwrite(fd5, "\nnewSrc2Ready:     ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd5, "       %b ", fabScalar.issueq.newSrc2Ready[i]);

        $fwrite(fd5, "\nrsrTag:        ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
        begin
            $fwrite(fd5, "       %b ",fabScalar.issueq.rsrTag[i]);
        end 

        $fwrite(fd5, "\nrsrTag_t:    ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
        begin
            `ifndef DYNAMIC_CONFIG
              $fwrite(fd5, "       %b ",fabScalar.issueq.rsr.rsrTag_o[i]);
            `else
            `endif
        end
 
        $fwrite(fd5, "\nISsimple_t:    ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
        begin
            $fwrite(fd5, "       %b ",fabScalar.issueq.ISsimple_t[i]);
        end


        /* IQ Freelist */

        $fwrite(fd5, "\n\n               -- IQ Freelist --\n\n");

        $fwrite(fd5, "issueQCount: d%d headPtr: d%d tailPtr: d%d\n",
                fabScalar.issueq.issueQfreelist.issueQCount,
                fabScalar.issueq.issueQfreelist.headPtr,
                fabScalar.issueq.issueQfreelist.tailPtr);


        /* Wakeup */

        $fwrite(fd5, "\n\n               -- Wakeup --\n\n");

        $fwrite(fd5, "phyRegValidVect: %b\n\n", fabScalar.issueq.phyRegValidVect);
        
        $fwrite(fd5, "rsrTag (V):      ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
        begin
            $fwrite(fd5, "%2x (%b) ",
                    fabScalar.issueq.rsrTag[i][`SIZE_PHYSICAL_LOG:1],
                    fabScalar.issueq.rsrTag[i][0]);
        end

        //$fwrite(fd5, "\n\niqValidVect:     %b\n", fabScalar.issueq.iqValidVect);
        $fwrite(fd5, "src1MatchVect:   %b\n",     fabScalar.issueq.src1MatchVect);
        //$fwrite(fd5, "src1Valid_t1:    %b\n",     fabScalar.issueq.src1Valid_t1);
        //$fwrite(fd5, "src1ValidVect:   %b\n",     fabScalar.issueq.src1ValidVect);

        //$fwrite(fd5, "\n\niqValidVect:     %b\n", fabScalar.issueq.iqValidVect);
        $fwrite(fd5, "src2MatchVect:   %b\n",     fabScalar.issueq.src2MatchVect);
        //$fwrite(fd5, "src2Valid_t1:    %b\n",     fabScalar.issueq.src2Valid_t1);
        //$fwrite(fd5, "src2ValidVect:   %b\n",     fabScalar.issueq.src2ValidVect);


        /* Select */

        $fwrite(fd5, "\n\n               -- Select --\n\n");

        //$fwrite(fd5, "iqValidVect:     %b\n", fabScalar.issueq.iqValidVect);
        //$fwrite(fd5, "src1ValidVect:   %b\n", fabScalar.issueq.src1ValidVect);
        //$fwrite(fd5, "src2ValidVect:   %b\n", fabScalar.issueq.src2ValidVect);
        $fwrite(fd5, "reqVect:         %b\n", fabScalar.issueq.reqVect);
        `ifndef DYNAMIC_CONFIG
          $fwrite(fd5, "reqVectFU0:      %b\n", fabScalar.issueq.reqVectFU0);
          $fwrite(fd5, "reqVectFU1:      %b\n", fabScalar.issueq.reqVectFU1);
          $fwrite(fd5, "reqVectFU2:      %b\n", fabScalar.issueq.reqVectFU2);
          `ifdef ISSUE_FOUR_WIDE
            $fwrite(fd5, "reqVectFU3:      %b\n", fabScalar.issueq.reqVectFU3);
          `endif
          `ifdef ISSUE_FIVE_WIDE
            $fwrite(fd5, "reqVectFU4:      %b\n", fabScalar.issueq.reqVectFU4);
          `endif
        `else
        `endif

        //$fwrite(fd5, "grantedVect:     %b\n", fabScalar.issueq.grantedVect);

        /* rrPacket_o */
        $fwrite(fd5, "\nrrPacket_o        ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd5, "     [%1d] ", i);

        $fwrite(fd5, "\npc:               ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd5, "%08x ", rrPacket[i].pc);

        $fwrite(fd5, "\nopcode:           ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd5, "      %2x ",  rrPacket[i].opcode);

        $fwrite(fd5, "\nphyDest:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd5, "      %2x ", rrPacket[i].phyDest);

        $fwrite(fd5, "\nphySrc1:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd5, "      %2x ", rrPacket[i].phySrc1);

        $fwrite(fd5, "\nphySrc2:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd5, "      %2x ", rrPacket[i].phySrc2);

        $fwrite(fd5, "\nimmed:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd5, "    %04x ", rrPacket[i].immed);

        $fwrite(fd5, "\nlsqID:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd5, "      %2x ", rrPacket[i].lsqID);

        $fwrite(fd5, "\nalID:             ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd5, "      %2x ", rrPacket[i].alID);

        $fwrite(fd5, "\nldstSize:         ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd5, "       %1x ", rrPacket[i].ldstSize);

        $fwrite(fd5, "\nctiID:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd5, "      %2x ", rrPacket[i].ctiID);

        $fwrite(fd5, "\npredNPC:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd5, "%08x ", rrPacket[i].predNPC);

        $fwrite(fd5, "\npredDir:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd5, "       %1x ", rrPacket[i].predDir);

        $fwrite(fd5, "\ngrantedEntry (V): ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd5, "  %2x (%1d) ", iqGrantedEntry[i].id, iqGrantedEntry[i].valid);

        $fwrite(fd5,"\n\n");

        //$fwrite(fd5, "freedVect:       %b\n", fabScalar.issueq.freedVect);
        $fwrite(fd5, "freedEntry (V): ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd5, "  %2x (%1d) ", iqFreedEntry[i].id, iqFreedEntry[i].valid);
        
        $fwrite(fd5,"\n");
        /* for (i = 0;i< `NO_OF_COMPLEX; i++) */
        /* $fwrite(fd5,"issue_simple[%x] : %b    ",i,fabScalar.issueq.issue_simple[i]); */    
/*
        $fwrite(fd5,"\n\n");
        $fwrite(fd5,"RSR1 (V) :");
        for (i = 0;i < `FU1_LATENCY;i++)
            $fwrite(fd5,"   %2x (%1d) ",fabScalar.issueq.rsr.RSR_CALU1[i],fabScalar.issueq.rsr.RSR_CALU_VALID1[i]);
        $fwrite(fd5,"\n\n");
        
        $fwrite(fd5,"RSR2 (V) :");
        for (i = 0;i < `FU1_LATENCY;i++)
            $fwrite(fd5,"   %2x (%1d) ",fabScalar.issueq.rsr.RSR_CALU2[i],fabScalar.issueq.rsr.RSR_CALU_VALID2[i]);
*/
        $fwrite(fd5,"\n\n\n");
    end
end
`endif /* PRINT_EN */


payloadPkt                      rrPacket_l1    [0:`ISSUE_WIDTH-1];
bypassPkt                       bypassPacket   [0:`ISSUE_WIDTH-1];
/* fuPkt                           exePacket      [0:`ISSUE_WIDTH-1]; */

always @(*)
begin
    int i;
    for (i = 0; i < `ISSUE_WIDTH; i++)
    begin
        rrPacket_l1[i]  = fabScalar.rrPacket_l1[i];
        bypassPacket[i] = fabScalar.bypassPacket[i];
    end
end

`ifdef PRINT_EN
/* Prints register read related signals and latch value. */
always_ff @(posedge clk)
begin : REG_READ
    int i;

    if (PRINT)
    begin

        $fwrite(fd6, "------------------------------------------------------\n");
        $fwrite(fd6, "Cycle: %0d  Commit: %0d\n\n",CYCLE_COUNT, COMMIT_COUNT);

        $fwrite(fd6, "               -- rrPacket_i --\n");

        /* rrPacket_i */
        $fwrite(fd6, "\nrrPacket_i        ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "     [%1d] ", i);

        $fwrite(fd6, "\npc:               ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "%08x ", rrPacket_l1[i].pc);

        $fwrite(fd6, "\nopcode:           ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "      %2x ",  rrPacket_l1[i].opcode);

        $fwrite(fd6, "\nphyDest:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "      %2x ", rrPacket_l1[i].phyDest);

        $fwrite(fd6, "\nphySrc1:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "      %2x ", rrPacket_l1[i].phySrc1);

        $fwrite(fd6, "\nphySrc2:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "      %2x ", rrPacket_l1[i].phySrc2);

        $fwrite(fd6, "\nimmed:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "    %04x ", rrPacket_l1[i].immed);

        $fwrite(fd6, "\nlsqID:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "      %2x ", rrPacket_l1[i].lsqID);

        $fwrite(fd6, "\nalID:             ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "      %2x ", rrPacket_l1[i].alID);

        /* $fwrite(fd6, "\nldstSize:         "); */
        /* for (i = 0; i < `ISSUE_WIDTH; i++) */
        /*     $fwrite(fd6, "       %1x ", rrPacket_l1[i].ldstSize); */

        $fwrite(fd6, "\nctiID:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "      %2x ", rrPacket_l1[i].ctiID);

        $fwrite(fd6, "\npredNPC:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "%08x ", rrPacket_l1[i].predNPC);

        $fwrite(fd6, "\npredDir:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "       %1x ", rrPacket_l1[i].predDir);

        $fwrite(fd6, "\nvalid:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "       %1x ", rrPacket_l1[i].valid);


        $fwrite(fd6, "\n\n               -- bypassPacket_i --\n");

        /* rrPacket_i */
        $fwrite(fd6, "\nbypassPacket_i    ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "     [%1d] ", i);

        $fwrite(fd6, "\ntag:              ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "      %2x ", bypassPacket[i].tag);

        $fwrite(fd6, "\ndata:             ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "%08x ",  bypassPacket[i].data);

        $fwrite(fd6, "\nvalid:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "       %1x ", bypassPacket[i].valid);


        $fwrite(fd6, "\n\n               -- exePacket_o --\n");

        /* rrPacket_i */
        $fwrite(fd6, "\nexePacket_o       ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "     [%1d] ", i);

        $fwrite(fd6, "\npc:               ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "%08x ", exePacket[i].pc);

        $fwrite(fd6, "\nopcode:           ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "      %2x ",  exePacket[i].opcode);

        $fwrite(fd6, "\nphyDest:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "      %2x ", exePacket[i].phyDest);

        $fwrite(fd6, "\nphySrc1:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "      %2x ", exePacket[i].phySrc1);

        $fwrite(fd6, "\nsrc1Data:         ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "%08x ", exePacket[i].src1Data);

        $fwrite(fd6, "\nphySrc2:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "      %2x ", exePacket[i].phySrc2);

        $fwrite(fd6, "\nsrc2Data:         ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "%08x ", exePacket[i].src2Data);

        $fwrite(fd6, "\nimmed:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "    %04x ", exePacket[i].immed);

        $fwrite(fd6, "\nlsqID:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "      %2x ", exePacket[i].lsqID);

        $fwrite(fd6, "\nalID:             ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "      %2x ", exePacket[i].alID);

        /* $fwrite(fd6, "\nldstSize:         "); */
        /* for (i = 0; i < `ISSUE_WIDTH; i++) */
        /*     $fwrite(fd6, "       %1x ", exePacket[i].ldstSize); */

        $fwrite(fd6, "\nctiID:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "      %2x ", exePacket[i].ctiID);

        $fwrite(fd6, "\npredNPC:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "%08x ", exePacket[i].predNPC);

        $fwrite(fd6, "\npredDir:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "       %1x ", exePacket[i].predDir);

        $fwrite(fd6, "\nvalid:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd6, "       %1x ", exePacket[i].valid);

        $fwrite(fd6, "\n\n\n");

    end
end
`endif // PRINT_EN


`ifdef PRINT_EN
reg  [`SIZE_PHYSICAL_LOG-1:0]               src1Addr_byte0 [0:`ISSUE_WIDTH-1];
reg  [`SIZE_PHYSICAL_LOG-1:0]               src1Addr_byte1 [0:`ISSUE_WIDTH-1];
reg  [`SIZE_PHYSICAL_LOG-1:0]               src1Addr_byte2 [0:`ISSUE_WIDTH-1];
reg  [`SIZE_PHYSICAL_LOG-1:0]               src1Addr_byte3 [0:`ISSUE_WIDTH-1];
reg  [`SIZE_PHYSICAL_LOG-1:0]               src2Addr_byte0 [0:`ISSUE_WIDTH-1];
reg  [`SIZE_PHYSICAL_LOG-1:0]               src2Addr_byte1 [0:`ISSUE_WIDTH-1];
reg  [`SIZE_PHYSICAL_LOG-1:0]               src2Addr_byte2 [0:`ISSUE_WIDTH-1];
reg  [`SIZE_PHYSICAL_LOG-1:0]               src2Addr_byte3 [0:`ISSUE_WIDTH-1];
reg  [`SIZE_PHYSICAL_LOG-1:0]               destAddr_byte0 [0:`ISSUE_WIDTH-1];
reg  [`SIZE_PHYSICAL_LOG-1:0]               destAddr_byte1 [0:`ISSUE_WIDTH-1];
reg  [`SIZE_PHYSICAL_LOG-1:0]               destAddr_byte2 [0:`ISSUE_WIDTH-1];
reg  [`SIZE_PHYSICAL_LOG-1:0]               destAddr_byte3 [0:`ISSUE_WIDTH-1];

always @(*)
begin
    int i, j;
    for (i = 0; i < `ISSUE_WIDTH; i++)
    begin
        for (j = 0; j < `SIZE_PHYSICAL_TABLE; j++)
        begin
            if (fabScalar.registerfile.src1Addr_byte0[i][j])
            begin
                src1Addr_byte0[i]              = j;
            end

            if (fabScalar.registerfile.src1Addr_byte1[i][j])
            begin
                src1Addr_byte1[i]              = j;
            end

            if (fabScalar.registerfile.src1Addr_byte2[i][j])
            begin
                src1Addr_byte2[i]              = j;
            end

            if (fabScalar.registerfile.src1Addr_byte3[i][j])
            begin
                src1Addr_byte3[i]              = j;
            end


            if (fabScalar.registerfile.src2Addr_byte0[i][j])
            begin
                src2Addr_byte0[i]              = j;
            end

            if (fabScalar.registerfile.src2Addr_byte1[i][j])
            begin
                src2Addr_byte1[i]              = j;
            end

            if (fabScalar.registerfile.src2Addr_byte2[i][j])
            begin
                src2Addr_byte2[i]              = j;
            end

            if (fabScalar.registerfile.src2Addr_byte3[i][j])
            begin
                src2Addr_byte3[i]              = j;
            end


            if (fabScalar.registerfile.destAddr_byte0[i][j])
            begin
                destAddr_byte0[i]              = j;
            end

            if (fabScalar.registerfile.destAddr_byte1[i][j])
            begin
                destAddr_byte1[i]              = j;
            end

            if (fabScalar.registerfile.destAddr_byte2[i][j])
            begin
                destAddr_byte2[i]              = j;
            end

            if (fabScalar.registerfile.destAddr_byte3[i][j])
            begin
                destAddr_byte3[i]              = j;
            end
        end
    end
end


/* Prints register read related signals and latch value. */
always_ff @(posedge clk)
begin : PHY_REG_FILE
    int i;

    if (PRINT)
    begin

        $fwrite(fd23, "------------------------------------------------------\n");
        $fwrite(fd23, "Cycle: %0d  Commit: %0d\n\n",CYCLE_COUNT, COMMIT_COUNT);

        $fwrite(fd23, "               -- Read --\n");

        /* Read */
        $fwrite(fd23, "\n                  ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "     [%1d] ", i);

        $fwrite(fd23, "\nsrc1Addr_byte0:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", src1Addr_byte0[i]);

        $fwrite(fd23, "\nsrc1Data_byte0:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", fabScalar.registerfile.src1Data_byte0_o[i]);

        $fwrite(fd23, "\n\nsrc1Addr_byte1:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", src1Addr_byte1[i]);

        $fwrite(fd23, "\nsrc1Data_byte1:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", fabScalar.registerfile.src1Data_byte1_o[i]);

        $fwrite(fd23, "\n\nsrc1Addr_byte2:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", src1Addr_byte2[i]);

        $fwrite(fd23, "\nsrc1Data_byte2:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", fabScalar.registerfile.src1Data_byte2_o[i]);

        $fwrite(fd23, "\n\nsrc1Addr_byte3:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", src1Addr_byte3[i]);

        $fwrite(fd23, "\nsrc1Data_byte3:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", fabScalar.registerfile.src1Data_byte3_o[i]);


        $fwrite(fd23, "\n\nsrc2Addr_byte0:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", src2Addr_byte0[i]);

        $fwrite(fd23, "\nsrc2Data_byte0:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", fabScalar.registerfile.src2Data_byte0_o[i]);

        $fwrite(fd23, "\n\nsrc2Addr_byte1:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", src2Addr_byte1[i]);

        $fwrite(fd23, "\nsrc2Data_byte1:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", fabScalar.registerfile.src2Data_byte1_o[i]);

        $fwrite(fd23, "\n\nsrc2Addr_byte2:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", src2Addr_byte2[i]);

        $fwrite(fd23, "\nsrc2Data_byte2:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", fabScalar.registerfile.src2Data_byte2_o[i]);

        $fwrite(fd23, "\n\nsrc2Addr_byte3:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", src2Addr_byte3[i]);

        $fwrite(fd23, "\nsrc2Data_byte3:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", fabScalar.registerfile.src2Data_byte3_o[i]);

        $fwrite(fd23, "\n\n\n               -- Write --\n");

        /* Write */
        $fwrite(fd23, "\n                  ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "     [%1d] ", i);

        $fwrite(fd23, "\ndestAddr_byte0:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", destAddr_byte0[i]);

        $fwrite(fd23, "\ndestData_byte0:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", fabScalar.registerfile.destData_byte0[i]);

        $fwrite(fd23, "\ndestWe_byte0:     ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "       %1x ", fabScalar.registerfile.destWe_byte0[i]);

        $fwrite(fd23, "\n\ndestAddr_byte1:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", destAddr_byte1[i]);

        $fwrite(fd23, "\ndestData_byte1:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", fabScalar.registerfile.destData_byte1[i]);

        $fwrite(fd23, "\ndestWe_byte1:     ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "       %1x ", fabScalar.registerfile.destWe_byte1[i]);

        $fwrite(fd23, "\n\ndestAddr_byte2:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", destAddr_byte2[i]);

        $fwrite(fd23, "\ndestData_byte2:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", fabScalar.registerfile.destData_byte2[i]);

        $fwrite(fd23, "\ndestWe_byte2:     ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "       %1x ", fabScalar.registerfile.destWe_byte2[i]);

        $fwrite(fd23, "\n\ndestAddr_byte3:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", destAddr_byte3[i]);

        $fwrite(fd23, "\ndestData_byte3:   ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "      %02x ", fabScalar.registerfile.destData_byte3[i]);

        $fwrite(fd23, "\ndestWe_byte3:     ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd23, "       %1x ", fabScalar.registerfile.destWe_byte3[i]);

        $fwrite(fd23, "\n\n\n");

    end
end
`endif // PRINT_EN


`ifdef PRINT_EN
/* Prints functional units */
fuPkt                           exePacket_l1   [0:`ISSUE_WIDTH-1];
wbPkt                           wbPacket       [0:`ISSUE_WIDTH-1];
reg  [31:0]                     src1Data       [0:`ISSUE_WIDTH-1];
reg  [31:0]                     src2Data       [0:`ISSUE_WIDTH-1];

always @(*)
begin
    int i;

    exePacket_l1[0]   = fabScalar.exePipe0.exePacket_l1;
    wbPacket[0]       = fabScalar.wbPacket;
    src1Data[0]       = fabScalar.exePipe0.execute.src1Data;
    src2Data[0]       = fabScalar.exePipe0.execute.src2Data;

    exePacket_l1[1]   = fabScalar.exePipe1.exePacket_l1;
    wbPacket[1]       = fabScalar.exePipe1.wbPacket;
    src1Data[1]       = fabScalar.exePipe1.execute.src1Data;
    src2Data[1]       = fabScalar.exePipe1.execute.src2Data;

    exePacket_l1[2]   = fabScalar.exePipe2.exePacket_l1;
    wbPacket[2]       = fabScalar.exePipe2.wbPacket;
    src1Data[2]       = fabScalar.exePipe2.execute.src1Data;
    src2Data[2]       = fabScalar.exePipe2.execute.src2Data;


`ifdef ISSUE_FOUR_WIDE
    exePacket_l1[3]   = fabScalar.exePipe3.exePacket_l1;
    wbPacket[3]       = fabScalar.exePipe3.wbPacket;
    src1Data[3]       = fabScalar.exePipe3.execute.src1Data;
    src2Data[3]       = fabScalar.exePipe3.execute.src2Data;
`endif

`ifdef ISSUE_FIVE_WIDE
    exePacket_l1[4]   = fabScalar.exePipe4.exePacket_l1;
    wbPacket[4]       = fabScalar.exePipe4.wbPacket;
    src1Data[4]       = fabScalar.exePipe4.execute.src1Data;
    src2Data[4]       = fabScalar.exePipe4.execute.src2Data;
`endif

`ifdef ISSUE_SIX_WIDE
    exePacket_l1[5]   = fabScalar.exePipe5.exePacket_l1;
    wbPacket[5]       = fabScalar.exePipe5.wbPacket;
    src1Data[5]       = fabScalar.exePipe5.execute.src1Data;
    src2Data[5]       = fabScalar.exePipe5.execute.src2Data;
`endif

`ifdef ISSUE_SEVEN_WIDE
    exePacket_l1[6]   = fabScalar.exePipe6.exePacket_l1;
    wbPacket[6]       = fabScalar.exePipe6.wbPacket;
    src1Data[6]       = fabScalar.exePipe6.execute.src1Data;
    src2Data[6]       = fabScalar.exePipe6.execute.src2Data;
`endif

end


always_ff @(posedge clk)
begin : EXE
    int i;

    if (PRINT)
    begin

        $fwrite(fd13, "------------------------------------------------------\n");
        $fwrite(fd13, "Cycle: %0d  Commit: %0d\n\n", CYCLE_COUNT, COMMIT_COUNT);


        $fwrite(fd13, "               -- exePacket_i --\n");

        /* exePacket_l1_i */
        $fwrite(fd13, "\nexePacket_i       ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "     [%1d] ", i);

        $fwrite(fd13, "\npc:               ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "%08x ", exePacket_l1[i].pc);

        $fwrite(fd13, "\nopcode:           ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "      %2x ",  exePacket_l1[i].opcode);

        $fwrite(fd13, "\nphyDest:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "      %2x ", exePacket_l1[i].phyDest);

        $fwrite(fd13, "\nphySrc1:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "      %2x ", exePacket_l1[i].phySrc1);

        $fwrite(fd13, "\nsrc1Data:         ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "%08x ", exePacket_l1[i].src1Data);

        $fwrite(fd13, "\nphySrc2:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "      %2x ", exePacket_l1[i].phySrc2);

        $fwrite(fd13, "\nsrc2Data:         ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "%08x ", exePacket_l1[i].src2Data);

        $fwrite(fd13, "\nimmed:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "    %04x ", exePacket_l1[i].immed);

        $fwrite(fd13, "\nlsqID:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "      %2x ", exePacket_l1[i].lsqID);

        $fwrite(fd13, "\nalID:             ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "      %2x ", exePacket_l1[i].alID);

        $fwrite(fd13, "\nctiID:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "      %2x ", exePacket_l1[i].ctiID);

        $fwrite(fd13, "\npredNPC:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "%08x ", exePacket_l1[i].predNPC);

        $fwrite(fd13, "\npredDir:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "       %1x ", exePacket_l1[i].predDir);

        $fwrite(fd13, "\nvalid:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "       %1x ", exePacket_l1[i].valid);


        $fwrite(fd13, "\n\n               -- bypassPacket_i --\n");

        /* rrPacket_i */
        $fwrite(fd13, "\nbypassPacket_i    ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "     [%1d] ", i);

        $fwrite(fd13, "\ntag:              ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "      %2x ", bypassPacket[i].tag);

        $fwrite(fd13, "\ndata:             ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "%8x ",  bypassPacket[i].data);

        $fwrite(fd13, "\nvalid:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "       %1x ", bypassPacket[i].valid);


        $fwrite(fd13, "\n\nsrc1Data:         ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "%08x ", src1Data[i]);

        $fwrite(fd13, "\nsrc2Data:         ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "%08x ", src2Data[i]);


        $fwrite(fd13, "\n\n               -- wbPacket_o --\n");

        /* wbPacket_i */
        $fwrite(fd13, "\nwbPacket_i        ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "     [%1d] ", i);

        $fwrite(fd13, "\npc:               ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "%08x ", wbPacket[i].pc);

        $fwrite(fd13, "\nflags:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "      %2x ",  wbPacket[i].flags);

        $fwrite(fd13, "\nphyDest:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "      %2x ", wbPacket[i].phyDest);

        $fwrite(fd13, "\ndestData:         ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "%08x ", wbPacket[i].destData);

        $fwrite(fd13, "\nalID:             ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "      %2x ", wbPacket[i].alID);

        $fwrite(fd13, "\nnextPC:           ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "%08x ", wbPacket[i].nextPC);

        $fwrite(fd13, "\nctrlType:         ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "      %2x ", wbPacket[i].ctrlType);

        $fwrite(fd13, "\nctrlDir:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "       %x ", wbPacket[i].ctrlDir);

        $fwrite(fd13, "\nctiID:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "      %2x ", wbPacket[i].ctiID);

        $fwrite(fd13, "\npredDir:          ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "       %1x ", wbPacket[i].predDir);

        $fwrite(fd13, "\nvalid:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd13, "       %1x ", wbPacket[i].valid);

        $fwrite(fd13, "\n\n\n");

    end
end
`endif // PRINT_EN


`ifdef PRINT_EN
/* Prints load-store related signals and latch value. */

memPkt                         memPacket;
memPkt                         replayPacket;

wbPkt                          lsuWbPacket;
ldVioPkt                       ldVioPacket;

always @(*)
begin
    memPacket      = fabScalar.memPacket;
    replayPacket   = fabScalar.lsu.datapath.replayPacket;
    lsuWbPacket    = fabScalar.wbPacket;
    ldVioPacket    = fabScalar.ldVioPacket;
end


always @(posedge clk)
begin:LSU
    reg [`SIZE_LSQ_LOG-1:0]               lastMatch;
  reg [2+`SIZE_PC+`SIZE_RMT_LOG+2*`SIZE_PHYSICAL_LOG:0] val;
  int i;

  if (PRINT)
  begin
        $fwrite(fd10, "------------------------------------------------------\n");
        $fwrite(fd10, "Cycle: %0d  Commit: %0d\n\n\n",CYCLE_COUNT, COMMIT_COUNT);

        $fwrite(fd10, "               -- Dispatched Instructions --\n\n");
        
        $fwrite(fd10, "ldqHead_i:      %x\n", fabScalar.lsu.datapath.stx_path.ldqHead_i);
        $fwrite(fd10, "ldqTail_i:      %x\n", fabScalar.lsu.datapath.stx_path.ldqTail_i);
        $fwrite(fd10, "stqHead_i:      %x\n", fabScalar.lsu.datapath.ldx_path.stqHead_i);
        $fwrite(fd10, "stqTail_i:      %x\n", fabScalar.lsu.datapath.ldx_path.stqTail_i);
        $fwrite(fd10, "backEndReady_i: %b\n", fabScalar.lsu.backEndReady_i);
        $fwrite(fd10, "recoverFlag_i : %b\n", fabScalar.lsu.recoverFlag_i);

        /* lsqPacket_i */
        $fwrite(fd10, "lsqPacket_i       ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd10, "     [%1d] ", i);

        $fwrite(fd10, "\npredLoadVio:      ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd10, "       %1x ", lsqPacket[i].predLoadVio);

        $fwrite(fd10, "\nisLoad:           ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd10, "       %1x ", lsqPacket[i].isLoad);

        $fwrite(fd10, "\nisStore:          ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd10, "       %1x ", lsqPacket[i].isStore);

        $fwrite(fd10, "\nlsqID:            ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd10, "      %2x ", fabScalar.lsqID[i]);

        $fwrite(fd10, "\nldqID:            ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd10, "      %2x ", fabScalar.lsu.ldqID[i]);

        $fwrite(fd10, "\nstqID:            ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd10, "      %2x ", fabScalar.lsu.stqID[i]);

        $fwrite(fd10, "\nnextLd:            ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd10, "      %x ", fabScalar.lsu.datapath.nextLdIndex_i[i]);

        $fwrite(fd10, "\nlastSt:            ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd10, "      %x ", fabScalar.lsu.datapath.lastStIndex_i[i]);

        $fwrite(fd10, "\n\n\n               -- Executed Instructions --\n\n");
        
        /* memPacket_i */
        $fwrite(fd10, "memPacket_i       ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "     [%1d] ", i);

        $fwrite(fd10, "\nPC:            ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "      %x  ", memPacket.pc);

        $fwrite(fd10, "\nflags:            ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "      %2x ", memPacket.flags);

        $fwrite(fd10, "\nldstSize:         ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "       %1x ", memPacket.ldstSize);

        $fwrite(fd10, "\nphyDest:          ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "      %2x ", memPacket.phyDest);

        $fwrite(fd10, "\naddress:          ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "%08x ",     memPacket.address);

        $fwrite(fd10, "\nsrc2Data:         ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "%08x ",     memPacket.src2Data);

        $fwrite(fd10, "\nlsqID:            ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "      %2x ", memPacket.lsqID);

        $fwrite(fd10, "\nalID:             ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "      %2x ", memPacket.alID);

        $fwrite(fd10, "\nvalid:            ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "       %1x ", memPacket.valid);

        /* replayPacket_i */
        $fwrite(fd10, "\n\nreplayPacket       ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "     [%1d] ", i);

        $fwrite(fd10, "\nPC:            ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "      %x  ", replayPacket.pc);

        $fwrite(fd10, "\nflags:            ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "      %2x ", replayPacket.flags);

        $fwrite(fd10, "\nldstSize:         ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "       %1x ", replayPacket.ldstSize);

        $fwrite(fd10, "\nphyDest:          ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "      %2x ", replayPacket.phyDest);

        $fwrite(fd10, "\naddress:          ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "%08x ",     replayPacket.address);

        $fwrite(fd10, "\nsrc2Data:         ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "%08x ",     replayPacket.src2Data);

        $fwrite(fd10, "\nlsqID:            ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "      %2x ", replayPacket.lsqID);

        $fwrite(fd10, "\nalID:             ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "      %2x ", replayPacket.alID);

        $fwrite(fd10, "\nvalid:            ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "       %1x ", replayPacket.valid);

        $fwrite(fd10, "\n\n\nlastSt:            ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "       %x ", fabScalar.lsu.datapath.ldx_path.LD_DISAMBIGUATION.lastSt);


        /* lsuWbPacket_o */
        $fwrite(fd10, "\n\nlsuWbPacket_o        ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "     [%1d] ", i);

        $fwrite(fd10, "\npc:               ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "%08x ", lsuWbPacket.pc);

        $fwrite(fd10, "\nflags:            ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "      %2x ", lsuWbPacket.flags);

        $fwrite(fd10, "\nphyDest:          ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "      %2x ", lsuWbPacket.phyDest);

        $fwrite(fd10, "\ndestData:         ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "%08x ",     lsuWbPacket.destData);

        $fwrite(fd10, "\nalID:             ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "      %2x ", lsuWbPacket.alID);

        $fwrite(fd10, "\nvalid:            ");
        for (i = 0; i < 1; i++)
            $fwrite(fd10, "       %1x ", lsuWbPacket.valid);


        $fwrite(fd10, "\n\n\n               -- LD Disambiguation (LDX) --\n\n");

        $fwrite(fd10, "stqCount_i:  %x\n",
                fabScalar.lsu.datapath.ldx_path.stqCount_i);

        $fwrite(fd10, "stqAddrValid:  %b\n",
                fabScalar.lsu.datapath.ldx_path.stqAddrValid);

        $fwrite(fd10, "stqValid:  %b\n",
                fabScalar.lsu.control.stqValid);

        $fwrite(fd10, "vulnerableStVector_t1:  %b\n",
                fabScalar.lsu.datapath.ldx_path.LD_DISAMBIGUATION.vulnerableStVector_t1);

        $fwrite(fd10, "vulnerableStVector_t2:  %b\n",
                fabScalar.lsu.datapath.ldx_path.LD_DISAMBIGUATION.vulnerableStVector_t2);

        $fwrite(fd10, "vulnerableStVector:     %b\n",
                fabScalar.lsu.datapath.ldx_path.LD_DISAMBIGUATION.vulnerableStVector);

//`ifndef DYNAMIC_CONFIG                
//        $fwrite(fd10, "addr1MatchVector:       %b\n",
//                fabScalar.lsu.datapath.ldx_path.LD_DISAMBIGUATION.addr1MatchVector);
//
//        $fwrite(fd10, "addr2MatchVector:       %b\n",
//                fabScalar.lsu.datapath.ldx_path.LD_DISAMBIGUATION.addr2MatchVector);
//`else                
        $fwrite(fd10, "addr1MatchVector:       %b\n",
                fabScalar.lsu.datapath.ldx_path.addr1MatchVector);

        $fwrite(fd10, "addr2MatchVector:       %b\n",
                fabScalar.lsu.datapath.ldx_path.addr2MatchVector);
//`endif

        //$fwrite(fd10, "sizeMismatchVector:     %b\n",
        //        fabScalar.lsu.datapath.ldx_path.LD_DISAMBIGUATION.sizeMismatchVector);

        $fwrite(fd10, "forwardVector1:         %b\n",
                fabScalar.lsu.datapath.ldx_path.LD_DISAMBIGUATION.forwardVector1);

        $fwrite(fd10, "forwardVector2:         %b\n\n",
                fabScalar.lsu.datapath.ldx_path.LD_DISAMBIGUATION.forwardVector2);


//`ifndef DYNAMIC_CONFIG        
//        lastMatch = fabScalar.lsu.datapath.ldx_path.LD_DISAMBIGUATION.lastMatch;
//`else
        lastMatch = fabScalar.lsu.datapath.ldx_path.lastMatch;
//`endif
        $fwrite(fd10, "stqHit:         %b\n", fabScalar.lsu.datapath.ldx_path.stqHit);
        $fwrite(fd10, "lastMatch:      %x\n", lastMatch);
        $fwrite(fd10, "partialStMatch: %b\n", fabScalar.lsu.datapath.ldx_path.partialStMatch);
        $fwrite(fd10, "disambigStall:  %b\n\n", fabScalar.lsu.datapath.ldx_path.LD_DISAMBIGUATION.disambigStall);

        $fwrite(fd10, "loadDataValid_o: %b\n", fabScalar.lsu.datapath.ldx_path.loadDataValid_o);
        $fwrite(fd10, "dcacheData:  %08x\n", fabScalar.lsu.datapath.ldx_path.dcacheData);
//`ifndef DYNAMIC_CONFIG        
//        $fwrite(fd10, "stqData[%d]: %08x\n", lastMatch, fabScalar.lsu.datapath.ldx_path.stqData[lastMatch]);
//`else        
        $fwrite(fd10, "stqData[%d]: %08x\n", lastMatch, fabScalar.lsu.datapath.ldx_path.stqHitData);
//`endif
        $fwrite(fd10, "loadData_t:  %08x\n", fabScalar.lsu.datapath.ldx_path.loadData_t);
        $fwrite(fd10, "loadData_o:  %08x\n", fabScalar.lsu.datapath.ldx_path.loadData_o);
        

        $fwrite(fd10, "\n\n\n               -- LD Violation (STX) --\n\n");

        $fwrite(fd10, "ldqAddrValid:           %b\n",
                fabScalar.lsu.datapath.stx_path.ldqAddrValid);

        $fwrite(fd10, "ldqWriteBack:           %b\n",
                fabScalar.lsu.datapath.stx_path.ldqWriteBack);

        $fwrite(fd10, "vulnerableLdVector_t1:  %b\n",
                fabScalar.lsu.datapath.stx_path.LD_VIOLATION.vulnerableLdVector_t1);

        $fwrite(fd10, "vulnerableLdVector_t2:  %b\n",
                fabScalar.lsu.datapath.stx_path.LD_VIOLATION.vulnerableLdVector_t2);

        $fwrite(fd10, "vulnerableLdVector_t3:  %b\n",
                fabScalar.lsu.datapath.stx_path.LD_VIOLATION.vulnerableLdVector_t3);

        $fwrite(fd10, "vulnerableLdVector_t4:  %b\n",
                fabScalar.lsu.datapath.stx_path.LD_VIOLATION.vulnerableLdVector_t4);

        $fwrite(fd10, "matchVector_st:         %b\n",
                fabScalar.lsu.datapath.stx_path.LD_VIOLATION.matchVector_st);

//`ifndef DYNAMIC_CONFIG
//        $fwrite(fd10, "matchVector_st1:        %b\n",
//                fabScalar.lsu.datapath.stx_path.LD_VIOLATION.matchVector_st1);
//`else                
        $fwrite(fd10, "matchVector_st1:        %b\n",
                fabScalar.lsu.datapath.stx_path.matchVector_st1);
//`endif

        //$fwrite(fd10, "matchVector_st2:        %b\n",
        //        fabScalar.lsu.datapath.stx_path.LD_VIOLATION.matchVector_st2);

        //$fwrite(fd10, "matchVector_st3:        %b\n",
        //        fabScalar.lsu.datapath.stx_path.LD_VIOLATION.matchVector_st3);

        $fwrite(fd10, "violateVector:          %b\n",
                fabScalar.lsu.datapath.stx_path.LD_VIOLATION.violateVector);


        //$fwrite(fd10, "nextLoad:       %x\n", fabScalar.lsu.datapath.stx_path.LD_VIOLATION.nextLoad);
//`ifndef DYNAMIC_CONFIG
//        $fwrite(fd10, "firstMatch:     %x\n", fabScalar.lsu.datapath.stx_path.LD_VIOLATION.firstMatch);
//`else                
        $fwrite(fd10, "firstMatch:     %x\n", fabScalar.lsu.datapath.stx_path.firstMatch);
//`endif
        $fwrite(fd10, "agenLdqMatch:   %b\n", fabScalar.lsu.datapath.stx_path.LD_VIOLATION.agenLdqMatch);
        $fwrite(fd10, "violateLdValid: %x\n", fabScalar.lsu.datapath.stx_path.violateLdValid);
        $fwrite(fd10, "violateLdALid:  %x\n", fabScalar.lsu.datapath.stx_path.violateLdALid);
        
        $fwrite(fd10, "\n\n\n               -- Committed Instructions --\n\n");
        
        $fwrite(fd10, "stqHead_i:   %d\n", fabScalar.lsu.datapath.ldx_path.stqHead_i);
        $fwrite(fd10, "commitSt_i:  %x\n", fabScalar.lsu.datapath.ldx_path.commitSt_i);
        $fwrite(fd10, "stCommitAddr:  %x\n", fabScalar.lsu.datapath.ldx_path.stCommitAddr);
        $fwrite(fd10, "stCommitData:  %x\n", fabScalar.lsu.datapath.ldx_path.stCommitData);
        $fwrite(fd10, "commitStCount:  %x", fabScalar.lsu.control.commitStCount);
        $fwrite(fd10, "commitStIndex: ");
        for (i = 0; i < 4; i++)
        begin
          $fwrite(fd10, "  %x", fabScalar.lsu.control.commitStIndex[i]);
        end

        for (i = 0; i < `SIZE_LSQ; i++)
        begin
//`ifndef DYNAMIC_CONFIG          
//            $fwrite(fd10, "stqAddr[%0d]: %08x\n", i, {fabScalar.lsu.datapath.ldx_path.stqAddr1[i],
//                                                      fabScalar.lsu.datapath.ldx_path.stqAddr2[i]});
//`endif                                                      
        end
        
        for (i = 0; i < `SIZE_LSQ; i++)
        begin
//`ifndef DYNAMIC_CONFIG          
//            $fwrite(fd10, "stqData[%0d]: %08x\n", i, fabScalar.lsu.datapath.ldx_path.stqData[i]);
//`endif
        end

    $fwrite(fd10, "commitLoad_i:  %b\n",
              fabScalar.lsu.commitLoad_i);

    $fwrite(fd10, "commitStore_i: %b\n",
              fabScalar.lsu.commitStore_i);

    $fwrite(fd10,"\n\n");
  end
end
`endif // 0



`ifdef PRINT_EN
ctrlPkt                         ctrlPacket [0:`ISSUE_WIDTH-1];
commitPkt                       amtPacket [0:`COMMIT_WIDTH-1];

always @(*)
begin
    int i;
    for (i = 0; i < `ISSUE_WIDTH; i++)
    begin
        ctrlPacket[i]   = fabScalar.ctrlPacket[i];
    end

    for (i = 0; i < `COMMIT_WIDTH; i++)
    begin
        amtPacket[i]   = fabScalar.amtPacket[i];
    end
end

always_ff @(posedge clk)
begin: ACTIVE_LIST
    int i;

    if (PRINT)
    begin
        $fwrite(fd7, "------------------------------------------------------\n");
        $fwrite(fd7, "Cycle: %0d  Commit: %0d\n\n\n",CYCLE_COUNT, COMMIT_COUNT);

`ifdef DYNAMIC_CONFIG
        $fwrite(fd7, "dispatchLaneActive_i: %x\n",
        fabScalar.activeList.dispatchLaneActive_i);

        $fwrite(fd7, "issueLaneActive_i: %x\n",
        fabScalar.activeList.issueLaneActive_i);
`endif        

        $fwrite(fd7, "totalCommit: d%d\n",
        fabScalar.activeList.totalCommit);

        $fwrite(fd7, "alCount: d%d\n",
        fabScalar.activeList.alCount);

        $fwrite(fd7, "headPtr: %x tailPtr: %x\n",
        fabScalar.activeList.headPtr,
        fabScalar.activeList.tailPtr);

        $fwrite(fd7, "backEndReady_i: %b\n\n",
        fabScalar.activeList.backEndReady_i);

        $fwrite(fd7, "               -- Dispatched Instructions --\n\n");
        
        /* alPacket_i */
        $fwrite(fd7, "\nalPacket_i    ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd7, "     [%1d] ", i);

        $fwrite(fd7, "\npc:           ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd7, "%08x ", alPacket[i].pc);

        $fwrite(fd7, "\nlogDest:      ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd7, "      %2x ", alPacket[i].logDest);

        $fwrite(fd7, "\nphyDest (V):  ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd7, "  %2x (%d) ", alPacket[i].phyDest, alPacket[i].phyDestValid);

        $fwrite(fd7, "\nisLoad:       ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd7, "       %1x ", alPacket[i].isLoad);

        $fwrite(fd7, "\nisStore:      ");
        for (i = 0; i < `DISPATCH_WIDTH; i++)
            $fwrite(fd7, "       %1x ", alPacket[i].isStore);

        $fwrite(fd7, "\n\n\n               -- Executed Instructions --\n");

        $fwrite(fd7, "\nctrlPacket_i      ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd7, "     [%1d] ", i);

        $fwrite(fd7, "\nnextPC:           ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd7, "%08x ", ctrlPacket[i].nextPC);

        $fwrite(fd7, "\nalID:             ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd7, "      %2x ", ctrlPacket[i].alID);

        $fwrite(fd7, "\nflags:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd7, "      %2x ", ctrlPacket[i].flags);

        $fwrite(fd7, "\nvalid:            ");
        for (i = 0; i < `ISSUE_WIDTH; i++)
            $fwrite(fd7, "       %1x ", ctrlPacket[i].valid);
        
        
        $fwrite(fd7, "\n\n\n               -- Committing Instructions --\n\n");
        
        $fwrite(fd7, "              ");
        for (i = 0; i < `COMMIT_WIDTH; i++)
            $fwrite(fd7, "     [%1d] ", i);

        $fwrite(fd7, "\nmispredFlag:  "); 
        for (i = 0; i < `COMMIT_WIDTH; i++)
            $fwrite(fd7, "       %b ", fabScalar.activeList.mispredFlag[i]);

        $fwrite(fd7, "\nviolateFlag:  ");
        for (i = 0; i < `COMMIT_WIDTH; i++)
            $fwrite(fd7, "       %b ", fabScalar.activeList.violateFlag[i]);
        
        $fwrite(fd7, "\nexceptionFlag:");
        for (i = 0; i < `COMMIT_WIDTH; i++)
            $fwrite(fd7, "       %b ", fabScalar.activeList.exceptionFlag[i]);

        $fwrite(fd7, "\n\ncommitReady:  ");
        for (i = 0; i < `COMMIT_WIDTH; i++)
            $fwrite(fd7, "       %b ", fabScalar.activeList.commitReady[i]);

        $fwrite(fd7, "\ncommitVector: ");
        for (i = 0; i < `COMMIT_WIDTH; i++)
            $fwrite(fd7, "       %b ", fabScalar.activeList.commitVector[i]);


        $fwrite(fd7, "\n\namtPacket_o   ");
        for (i = 0; i < `COMMIT_WIDTH; i++)
            $fwrite(fd7, "     [%1d] ", i);

        $fwrite(fd7, "\nlogDest:      ");
        for (i = 0; i < `COMMIT_WIDTH; i++)
            $fwrite(fd7, "      %2x ", amtPacket[i].logDest);

        $fwrite(fd7, "\nphyDest:      ");
        for (i = 0; i < `COMMIT_WIDTH; i++)
            $fwrite(fd7, "      %2x ", amtPacket[i].phyDest);

        $fwrite(fd7, "\nvalid:        ");
        for (i = 0; i < `COMMIT_WIDTH; i++)
            $fwrite(fd7, "       %1x ", amtPacket[i].valid);

        $fwrite(fd7, "\npc:           ");
        for (i = 0; i < `COMMIT_WIDTH; i++)
            $fwrite(fd7, "%08x ", fabScalar.activeList.commitPC[i]);

        $fwrite(fd7, "\n\ncommitStore:  ");
        for (i = 0; i < `COMMIT_WIDTH; i++)
            $fwrite(fd7, "       %1x ", fabScalar.activeList.commitStore_o[i]);

        $fwrite(fd7, "\ncommitLoad:   ");
        for (i = 0; i < `COMMIT_WIDTH; i++)
            $fwrite(fd7, "       %1x ", fabScalar.activeList.commitLoad_o[i]);

        $fwrite(fd7, "\ncommitCti:    ");
        for (i = 0; i < `COMMIT_WIDTH; i++)
            $fwrite(fd7, "       %1x ", fabScalar.activeList.commitCti_o[i]);

        $fwrite(fd7,"\n\n");

        
        if (fabScalar.activeList.violateFlag_reg)
        begin
            $fwrite(fd7, "violateFlag_reg: %d recoverPC_o: %h\n",
            fabScalar.activeList.violateFlag_reg,
            fabScalar.activeList.recoverPC_o);
        end

        if (fabScalar.activeList.mispredFlag_reg)
        begin
            $fwrite(fd7,"mispredFlag_reg: %d recoverPC_o: %h\n",
            fabScalar.activeList.mispredFlag_reg,
            fabScalar.activeList.recoverPC_o);
        end

        if (fabScalar.activeList.exceptionFlag_reg)
        begin
            $fwrite(fd7,"exceptionFlag_reg: %d exceptionPC_o: %h\n",
            fabScalar.activeList.exceptionFlag_reg,
            fabScalar.activeList.exceptionPC_o);
        end

        $fwrite(fd7,"\n");
    end
end

`endif


always_ff @(posedge clk)
begin : UPDATE_PHYSICAL_REG
    int i;
    for (i = 0; i < `ISSUE_WIDTH; i++)
    begin
        if (bypassPacket[i].valid)
        begin
            PHYSICAL_REG[bypassPacket[i].tag] <= bypassPacket[i].data;
        end
    end
end

integer skip_instructions = 69;

always @(posedge clk)
begin: VERIFY_INSTRUCTIONS
    reg [`SIZE_PC-1:0]           PC           [`COMMIT_WIDTH-1:0];
    reg [`SIZE_RMT_LOG-1:0]      logDest      [`COMMIT_WIDTH-1:0];
    reg [`SIZE_PHYSICAL_LOG-1:0] phyDest      [`COMMIT_WIDTH-1:0];
    reg [`SIZE_DATA-1:0]         result       [`COMMIT_WIDTH-1:0];
    reg                          isBranch     [`COMMIT_WIDTH-1:0];
    reg                          isMispredict [`COMMIT_WIDTH-1:0];
    reg                          eChecker     [`COMMIT_WIDTH-1:0];
    reg                          isFission    [`COMMIT_WIDTH-1:0];
    reg [`SIZE_PC-1:0]           lastCommitPC;
    int i;

    reg [7:0] reg_part1;
    reg [7:0] reg_part2;
    reg [7:0] reg_part3;
    reg [7:0] reg_part4;

    for (i = 0; i < `COMMIT_WIDTH; i++)
    begin
        PC[i]           = fabScalar.activeList.commitPC[i];
        logDest[i]      = fabScalar.activeList.logDest[i];
        phyDest[i]      = fabScalar.activeList.phyDest[i];
        /* reg_part1       = fabScalar.registerfile_4W_2D.PhyRegFile_byte0.ram[phyDest[i]]; */
        /* reg_part2       = fabScalar.registerfile_4W_2D.PhyRegFile_byte1.ram[phyDest[i]]; */
        /* reg_part3       = fabScalar.registerfile_4W_2D.PhyRegFile_byte2.ram[phyDest[i]]; */
        /* reg_part4       = fabScalar.registerfile_4W_2D.PhyRegFile_byte3.ram[phyDest[i]]; */
        /* result[i]       = {reg_part4, reg_part3, reg_part2, reg_part1}; */
        result[i]       = PHYSICAL_REG[phyDest[i]];
  
        eChecker[i]     = (fabScalar.activeList.totalCommit >= (i+1)) ? 1'h1 : 1'h0;
        isFission[i]    = fabScalar.activeList.commitFission[i];
        isBranch[i]     = fabScalar.activeList.ctrlAl[i][5];

        isMispredict[i] = fabScalar.activeList.ctrlAl[i][0] & fabScalar.activeList.ctrlAl[i][5];
    end

    // No need to skip instructions when SCRATCH PAD is the active source of instructions.
    // When SCRATCH  PAD is bypassed, skip the required number of instructions.
    if (eChecker[0] && (skip_instructions != 0) && !INST_SCRATCH_ENABLED && verifyCommits)
    begin
        skip_instructions = skip_instructions - fabScalar.activeList.totalCommit;
    end

    else if(verifyCommits)
    begin

        if (lastCommitPC == PC[0] && eChecker[0])
        begin
            lastCommitPC = PC[0];
        end

        else
        begin
          if(!INST_SCRATCH_ENABLED) // Controlled in the testbench
          begin
              if (eChecker[0]) lastCommitPC = PC[0];
              $getRetireInstPC(eChecker[0],CYCLE_COUNT,PC[0],logDest[0],result[0],isFission[0]);
          end
          else
          begin
	            if (eChecker[0]) 
		            begin	
			            lastCommitPC = PC[0];
			            if (fabScalar.activeList.activeList.data0_o[2])
           	    	begin	
               	 		$display("%x R[%d] P[%d] <- 0x%08x", 
               	 		  fabScalar.activeList.commitPC[0],
	             		    fabScalar.activeList.logDest[0],
                   	  fabScalar.activeList.phyDest[0],
	             		    result[0]);
                 	end
	        		    else
             			  $display("%x",fabScalar.activeList.commitPC[0]); 
	  	          end
	        end // INST_SCRATCH_ENABLED
        end

    `ifdef COMMIT_TWO_WIDE
        if (lastCommitPC == PC[1] && eChecker[1])
        begin
            lastCommitPC = PC[1];
        end

        else
        begin
          if(!INST_SCRATCH_ENABLED) // Controlled in the testbench
          begin
                	if(eChecker[1]) lastCommitPC = PC[1];
               	$getRetireInstPC(eChecker[1],CYCLE_COUNT,PC[1],logDest[1],result[1],isFission[1]);
          end
          else
          begin
		          if (eChecker[1]) 
		          begin	
			          lastCommitPC = PC[1];
			          if (fabScalar.activeList.activeList.data1_o[2])
     	        	begin
                    $display("%x R[%d] P[%d] <- 0x%08x",
                      fabScalar.activeList.commitPC[1],
                     	fabScalar.activeList.logDest[1],
                     	fabScalar.activeList.phyDest[1],
                     	result[1]);
	         		  end
	         		  else
               			$display("%x",fabScalar.activeList.commitPC[1]);
            	end
	          end
          end // INST_SCRATCH_ENABLED 
    `endif // COMMIT_TWO_WIDE

    `ifdef COMMIT_THREE_WIDE
        if (lastCommitPC == PC[2] && eChecker[2])
        begin
            lastCommitPC = PC[2];
        end

        else
        begin
          if(!INST_SCRATCH_ENABLED) // Controlled in the testbench
          begin
                	if(eChecker[2]) lastCommitPC = PC[2];
                	$getRetireInstPC(eChecker[2],CYCLE_COUNT,PC[2],logDest[2],result[2],isFission[2]);
          end
          else
          begin
		          if (eChecker[2]) 
		          begin	
			          lastCommitPC = PC[2];
			          if (fabScalar.activeList.activeList.data2_o[2])
            		begin
            	   	 	$display("%x R[%d] P[%d] <- 0x%08x", 
            	   	    	fabScalar.activeList.commitPC[2],
            	        	fabScalar.activeList.logDest[2],
            	        	fabScalar.activeList.phyDest[2],
            	        	result[2]);
            		end
            		else
            	   		$display("%x",fabScalar.activeList.commitPC[2]);
		          end 
            end
          end // INST_SCRATCH_ENABLED
    `endif // COMMIT_THREE_WIDE

    `ifdef COMMIT_FOUR_WIDE
        if (lastCommitPC == PC[3] && eChecker[3])
        begin
            lastCommitPC = PC[3];
        end

        else
        begin
          if(!INST_SCRATCH_ENABLED) // Controlled in the testbench
          begin
                	if(eChecker[3]) lastCommitPC = PC[3];
                	$getRetireInstPC(eChecker[3],CYCLE_COUNT,PC[3],logDest[3],result[3],isFission[3]);
          end
          else
          begin
              if (eChecker[3]) 
		          begin	
			          lastCommitPC = PC[3];
			          if (fabScalar.activeList.activeList.data3_o[2])
            		begin
            	   		$display("%x R[%d] P[%d] <- 0x%08x", 
            	        	fabScalar.activeList.commitPC[3],
            	        	fabScalar.activeList.logDest[3],
            	        	fabScalar.activeList.phyDest[3],
            	        	result[3]);
            		end
            		else
            	    	$display("%x",fabScalar.activeList.commitPC[3]);
		          end
	          end
          end // INSTR_SCRATCH_ENABLED
    `endif // COMMIT_FOUR_WIDE

 	end // SKIP_INSTRUCTIONS
end


task copyRF;

    integer i;

    begin
`ifdef DYNAMIC_CONFIG          
        for (i = 0; i < 32; i++)
        begin
            fabScalar.registerfile.PhyRegFile_byte0.ram_partitioned_no_decode.INST_LOOP[0].ram_instance_no_decode.ram[i] = LOGICAL_REG[i][7:0];
            fabScalar.registerfile.PhyRegFile_byte1.ram_partitioned_no_decode.INST_LOOP[0].ram_instance_no_decode.ram[i] = LOGICAL_REG[i][15:8];
            fabScalar.registerfile.PhyRegFile_byte2.ram_partitioned_no_decode.INST_LOOP[0].ram_instance_no_decode.ram[i] = LOGICAL_REG[i][23:16];
            fabScalar.registerfile.PhyRegFile_byte3.ram_partitioned_no_decode.INST_LOOP[0].ram_instance_no_decode.ram[i] = LOGICAL_REG[i][31:24];
        end
        for (i = 32; i < 34; i++)
        begin
            fabScalar.registerfile.PhyRegFile_byte0.ram_partitioned_no_decode.INST_LOOP[1].ram_instance_no_decode.ram[i-32] = LOGICAL_REG[i][7:0];
            fabScalar.registerfile.PhyRegFile_byte1.ram_partitioned_no_decode.INST_LOOP[1].ram_instance_no_decode.ram[i-32] = LOGICAL_REG[i][15:8];
            fabScalar.registerfile.PhyRegFile_byte2.ram_partitioned_no_decode.INST_LOOP[1].ram_instance_no_decode.ram[i-32] = LOGICAL_REG[i][23:16];
            fabScalar.registerfile.PhyRegFile_byte3.ram_partitioned_no_decode.INST_LOOP[1].ram_instance_no_decode.ram[i-32] = LOGICAL_REG[i][31:24];
        end
`else
        for (i = 0; i < 34; i++)
        begin
            fabScalar.registerfile.PhyRegFile_byte0.ram[i] = LOGICAL_REG[i][7:0];
            fabScalar.registerfile.PhyRegFile_byte1.ram[i] = LOGICAL_REG[i][15:8];
            fabScalar.registerfile.PhyRegFile_byte2.ram[i] = LOGICAL_REG[i][23:16];
            fabScalar.registerfile.PhyRegFile_byte3.ram[i] = LOGICAL_REG[i][31:24];
        end
`endif
    end
endtask

task copySimRF;

    int i;

    begin
        for (i = 0; i < 34; i++)
        begin
            PHYSICAL_REG[i] = LOGICAL_REG[i];
        end

        for (i = 34; i < `SIZE_PHYSICAL_TABLE; i++)
        begin
            PHYSICAL_REG[i] = 0;
        end
    end
endtask

task init_registers;
    integer i;
    reg  [31:0] opcode;
    reg  [7:0]  dest;
    reg  [7:0]  src1;
    reg  [7:0]  src2;
    reg  [15:0] immed;
    reg  [25:0] target; 

    begin
        for (i = 1; i < 34; i = i + 1)
        begin
            opcode  = {24'h0, `LUI};
            dest    = i;
            immed   = LOGICAL_REG[i][31:16];
            `WRITE_WORD(opcode, (32'h0000_0000 + 16*(i-1)));
            `WRITE_WORD({8'h0, dest, immed}, (32'h0000_0000 + 16*(i-1)+4));

            opcode  = {24'h0, `ORI};
            dest    = i;
            src1    = i;
            immed   = LOGICAL_REG[i][15:0];
            `WRITE_WORD(opcode, (32'h0000_0000 + 16*(i-1)+8)); 
            `WRITE_WORD({src1, dest, immed}, (32'h0000_0000 + 16*(i-1)+12)); 
            /* $display("@%d[%08x]", i, LOGICAL_REG[i]); */
            PHYSICAL_REG[i] = LOGICAL_REG[i];
        end

        // return from subroutine
        opcode  = {24'h0, `RET};
        target  = `GET_ARCH_PC >> 2;
        `WRITE_WORD(opcode, (32'h0000_0000 + 16*(i-1))); 
        `WRITE_WORD({6'h0, target}, (32'h0000_0000 + 16*(i-1)+4)); 

        // skip two instructions per register plus 1 for jump
        skip_instructions = 2*33 + 1;
    end
endtask

`ifdef SCRATCH_PAD
  task load_scratch;
   integer  ram_index;
   integer  offset;
   
   for(ram_index = 0; ram_index < `DEBUG_INST_RAM_DEPTH ; ram_index++ )
   //for(ram_index = 0; ram_index < 2 ; ram_index++ )
    begin
    for(offset =0; offset < 5 ; offset ++)
    begin
      instScratchAddr   = {offset[2:0],ram_index[7:0]};
      instScratchWrEn   = 1;   
      instScratchWrData = ram_index[7:0]^offset[7:0];
      #(CLKPERIOD);
    end
    end
  endtask
  
  //task to load the INSTRUCTION scratch pad with the microbenchmark
  task load_kernel_scratch;
   integer  ram_index;
   integer  offset;
   integer  data_file; 
   integer  scan_file; 
   reg [`DEBUG_INST_RAM_WIDTH-1:0] kernel_line;
  
   data_file = $fopen("kernel.dat","r");
  
   for(ram_index = 0; ram_index < `DEBUG_INST_RAM_DEPTH ; ram_index++ )
    begin
    scan_file = $fscanf(data_file, "%10x\n",kernel_line);
    for(offset = 0; offset < 5 ; offset ++)
    begin
      instScratchAddr   = {offset[2:0],ram_index[7:0]};
      instScratchWrEn   = 1;   
      instScratchWrData = kernel_line[8*(offset+1)-1-:8];
      #(CLKPERIOD);
    end
    end
  endtask
  
  //task to read the INSTRUCTION scratch pad
  task read_scratch;
   integer ram_index;
   integer offset;
  for(ram_index = 0; ram_index < `DEBUG_INST_RAM_DEPTH ; ram_index++ )
    begin
    for(offset =0; offset < 5 ; offset ++)
    begin
      instScratchAddr   = {offset[2:0],ram_index[7:0]};   
      #(CLKPERIOD);
      if(instScratchRdData != (ram_index[7:0]^offset[7:0]))
      begin
        $display("READ MISMATCH at %x index %d byte\n",ram_index,offset);
        $display("Read %x , expected %x\n",instScratchRdData,ram_index[7:0]^offset[7:0]);
      end
    end
   end
  endtask
  
  task read_kernel_scratch;
   integer  ram_index;
   integer  offset;
   integer  data_file; 
   integer  scan_file; 
   reg [`DEBUG_INST_RAM_WIDTH-1:0] kernel_line;
  
   data_file = $fopen("kernel.dat","r");
  for(ram_index = 0; ram_index < `DEBUG_INST_RAM_DEPTH ; ram_index++ )
    begin
    scan_file = $fscanf(data_file, "%10x\n",kernel_line);
    for(offset =0; offset < 5 ; offset ++)
    begin
      instScratchAddr   = {offset[2:0],ram_index[7:0]};   
      #(CLKPERIOD);
      if(instScratchRdData != kernel_line[8*(offset+1)-1-:8])
      begin
        $display("READ MISMATCH at %x index %d byte\n",ram_index,offset);
        $display("Read %x , expected %x\n",instScratchRdData,kernel_line[8*(offset+1)-1-:8]);
      end
    end
   end
  
  endtask
`endif // SCRATCH_PAD

//task to load the PRF from checkpoint
task load_checkpoint_PRF;
 integer  ram_index;
 integer  offset;

for(ram_index = 0; ram_index < `SIZE_PHYSICAL_TABLE ; ram_index++)
  begin
  for(offset = 0; offset < 4 ; offset++)
  begin
    debugPRFAddr      = {offset[`SIZE_DATA_BYTE_OFFSET-1:0],ram_index[`SIZE_PHYSICAL_LOG-1:0]};
    debugPRFWrEn      = 1;   
    debugPRFWrData    = offset+ram_index;
    #(2*CLKPERIOD);
  end
  end
debugPRFWrEn      = 0;
endtask

//task to read the PRF byte by byte
task read_checkpoint_PRF;
 integer  ram_index;
 integer  offset;

for(ram_index = 0; ram_index < `SIZE_PHYSICAL_TABLE ; ram_index++)
begin
  for(offset = 3; offset >= 0 ; offset--)
  begin
    debugPRFAddr      = {offset[`SIZE_DATA_BYTE_OFFSET-1:0],ram_index[`SIZE_PHYSICAL_LOG-1:0]};
    //debugPRFWrEn      = 1;  
    #(2*CLKPERIOD);
    if(debugPRFRdData      != offset+ram_index)
    begin
      $display("READ MISMATCH at %x index %d byte\n",ram_index,offset);
      $display("Read %x , expected %x\n",debugPRFRdData,offset+ram_index);
    end
  end
end
endtask

//task to read the ARF byte by byte
task read_ARF;
 integer  ram_index;
 integer  offset;
 reg  [7:0]      captureRF[3:0]; 

for(ram_index = 0; ram_index < `SIZE_RMT ; ram_index++)
  begin
  for(offset = 3; offset >= 0 ; offset--)
  begin
    debugPRFAddr      = {offset[`SIZE_DATA_BYTE_OFFSET-1:0],ram_index[`SIZE_PHYSICAL_LOG-1:0]};
    //debugPRFWrEn      = 1;  
    #(2*CLKPERIOD);
    captureRF[offset] = debugPRFRdData;
    if(offset == 0)
    $display("read %x%x%x%x\n",captureRF[3],captureRF[2],captureRF[1],captureRF[0]);
  end
end
endtask

`ifdef SCRATCH_PAD
task load_data_scratch;
 integer  ram_index;
 integer  offset;
 integer  data_file; 
 integer  scan_file; 
 reg [`DEBUG_DATA_RAM_WIDTH-1:0] data_line;

 data_file = $fopen("data.dat","r");

 for(ram_index = 0; ram_index < `DEBUG_DATA_RAM_DEPTH ; ram_index++ )
  begin
  scan_file = $fscanf(data_file, "%8x\n",data_line);
  for(offset = 0; offset < 3 ; offset ++)
  begin
    dataScratchAddr   = {offset[1:0],ram_index[7:0]};
    dataScratchWrEn   = 1;   
    dataScratchWrData = data_line[8*(offset+1)-1-:8];
    #(CLKPERIOD);
  end
  end
endtask

task read_data_scratch;
 integer  ram_index;
 integer  offset;
 integer  data_file; 
 integer  scan_file; 
 reg [`DEBUG_DATA_RAM_WIDTH-1:0] data_line;

 data_file = $fopen("data.dat","r");
for(ram_index = 0; ram_index < `DEBUG_DATA_RAM_DEPTH ; ram_index++ )
  begin
  scan_file = $fscanf(data_file, "%8x\n",data_line);
  for(offset =0; offset < 3 ; offset ++)
  begin
    dataScratchAddr   = {offset[1:0],ram_index[7:0]};   
    #(CLKPERIOD);
    //if(dataScratchRdData != data_line[8*(offset+1)-1-:8])
    if(dataScratchRdData != data_line[8*(offset+1)-1-:8])
    begin
      $display("READ MISMATCH at %x index %d byte\n",ram_index,offset);
      $display("Read %x , expected %x\n",dataScratchRdData,data_line[8*(offset+1)-1-:8]);
    end
  end
 end
endtask

`endif // SCRATCH_PAD



`ifdef PERF_MON

task read_perf_mon;
  integer  index;
  
  perfMonRegRun        = 1'b1;
  #(1000*CLKPERIOD)
  perfMonRegRun        = 1'b0;
  #CLKPERIOD;
  for(index = 8'h00; index < 8'h05 ; index++ )
  begin
    perfMonRegAddr       = index[7:0];
    #CLKPERIOD;
  end
  for(index = 8'h10; index < 8'h12 ; index++ )
  begin
    perfMonRegAddr       = index[7:0];
    #CLKPERIOD;
  end
  for(index = 8'h20; index < 8'h21 ; index++ )
  begin
    perfMonRegAddr       = index[7:0];
    #CLKPERIOD;
  end
  for(index = 8'h30; index < 8'h32 ; index++ )
  begin
    perfMonRegAddr       = index[7:0];
    #CLKPERIOD;
  end
  for(index = 8'h40; index < 8'h49 ; index++ )
  begin
    perfMonRegAddr       = index[7:0];
    #CLKPERIOD;
  end
  for(index = 8'h50; index < 8'h55 ; index++ )
  begin
    perfMonRegAddr       = index[7:0];
    #CLKPERIOD;
  end
 
  perfMonRegRun        = 1'b1;
  perfMonRegClr        = 1'b1;  //clearPerfMon = 1
    perfMonRegAddr       = 8'h00;
    #CLKPERIOD;
  
  perfMonRegClr        = 1'b0;  //clearPerfMon = 0
    #CLKPERIOD;
  perfMonRegRun        = 1'b0;
  
  for(index = 8'h00; index < 8'h05 ; index++ )
  begin
    perfMonRegAddr       = index[7:0];
    #CLKPERIOD;
  end
  
  for(index = 8'h10; index < 8'h20 ; index++ )
  begin
    perfMonRegAddr       = index[7:0];
    #CLKPERIOD;
  end
   
  perfMonRegGlobalClr  = 1'b1;  //Global clearPerfMon = 1
  #CLKPERIOD;
  for(index = 8'h00; index < 8'h05 ; index++ )
  begin
    perfMonRegAddr       = index[7:0];
    #CLKPERIOD;
  end
  for(index = 8'h10; index < 8'h12 ; index++ )
  begin
    perfMonRegAddr       = index[7:0];
    #CLKPERIOD;
  end
  for(index = 8'h20; index < 8'h21 ; index++ )
  begin
    perfMonRegAddr       = index[7:0];
    #CLKPERIOD;
  end
  for(index = 8'h30; index < 8'h32 ; index++ )
  begin
    perfMonRegAddr       = index[7:0];
    #CLKPERIOD;
  end
  for(index = 8'h40; index < 8'h49 ; index++ )
  begin
    perfMonRegAddr       = index[7:0];
    #CLKPERIOD;
  end
  for(index = 8'h50; index < 8'h55 ; index++ )
  begin
    perfMonRegAddr       = index[7:0];
    #CLKPERIOD;
  end
endtask
`endif

//initial
//begin
////beginConsolidation_reg = 1'b0;
////#(2000*CLKPERIOD);
////stallFetch = 1'b1;
////#(10*CLKPERIOD);
////beginConsolidation_reg = 1'b1;
////#CLKPERIOD;
////beginConsolidation_reg = 1'b0;
//////#(100*CLKPERIOD);
//wait (fabScalar.consolidationDone);
//read_ARF();
//end

//assign fabScalar.beginConsolidation = beginConsolidation_reg;


`ifdef GSHARE

  //`define SMALL_GSHARE;
  `define SIZE_BPB 4096
  `ifdef SMALL_GSHARE
    `define SIZE_BPB_LOG 12
  `else
    `define SIZE_BPB_LOG 14
  `endif
  logic [`SIZE_PC-1:0]                gsharePredPC [0:`FETCH_WIDTH-1];
  logic [`SIZE_PC-1:0]                gshareUpdatePC;
  logic [31:0]        branchHistoryReg;
  logic [31:0]        retiredBranchHistoryReg;
  logic [31:0]        specBranchHistoryReg;
  logic [31:0]        specBranchHistoryReg_l1;
  //logic [31:0]        specBranchHistoryReg_prev;
  logic [31:0]        specBranchHistoryReg_next;
  logic [31:0]        specBranchHistoryRegFs2;
  logic [`SIZE_BPB-1:0][1:0] branchCounterTable0;
  `ifndef SMALL_GSHARE
    logic [`SIZE_BPB-1:0][1:0] branchCounterTable1;
    logic [`SIZE_BPB-1:0][1:0] branchCounterTable2;
    logic [`SIZE_BPB-1:0][1:0] branchCounterTable3;
  `endif
  logic [`FETCH_WIDTH_LOG-1:0][1:0]        instrType;
  logic [`SIZE_BPB_LOG-1:0]  gshareIndex_pred;
  logic [1:0]                predCount_pred;
  
  function logic get_gshare_pred;
    input [31:0]  instrPC;
    output[1:0]   predCount;
    logic [`SIZE_BPB_LOG-1:0]  gshareIndex;
    logic         predDir;
    
    gshareIndex = {3'b000,instrPC[31:3]} ^ specBranchHistoryReg_next;
    gshareIndex_pred = gshareIndex;
  `ifdef SMALL_GSHARE
      predCount   = branchCounterTable0[gshareIndex];
  `else
    case(gshareIndex[1:0])
      2'b00: predCount   = branchCounterTable0[gshareIndex[`SIZE_BPB_LOG-1:2]];
      2'b01: predCount   = branchCounterTable1[gshareIndex[`SIZE_BPB_LOG-1:2]];
      2'b10: predCount   = branchCounterTable2[gshareIndex[`SIZE_BPB_LOG-1:2]];
      2'b11: predCount   = branchCounterTable3[gshareIndex[`SIZE_BPB_LOG-1:2]];
    endcase
  `endif
    predCount_pred = predCount;
    predDir     = predCount > 1;
    specBranchHistoryReg_next  = {specBranchHistoryReg_next[30:0],predDir};
    get_gshare_pred = predDir;
  endfunction
  
  task update_gshare;
    input [31:0]  instrPC;
    input         actualDir;
    logic [`SIZE_BPB_LOG-1:0]  gshareIndex;
    logic [1:0]   predCount;
    gshareIndex = {3'b000,instrPC[31:3]} ^ branchHistoryReg;
  `ifdef SMALL_GSHARE
      predCount   = branchCounterTable0[gshareIndex];
  `else
    case(gshareIndex[1:0])
      2'b00: predCount   = branchCounterTable0[gshareIndex[`SIZE_BPB_LOG-1:2]];
      2'b01: predCount   = branchCounterTable1[gshareIndex[`SIZE_BPB_LOG-1:2]];
      2'b10: predCount   = branchCounterTable2[gshareIndex[`SIZE_BPB_LOG-1:2]];
      2'b11: predCount   = branchCounterTable3[gshareIndex[`SIZE_BPB_LOG-1:2]];
    endcase
  `endif
    predCount   = actualDir 
                    ? (predCount < 3 ? predCount + 1 : predCount)
                    : (predCount > 0 ? predCount - 1 : predCount);
  `ifdef SMALL_GSHARE
      branchCounterTable0[gshareIndex] = predCount; 
  `else
    case(gshareIndex[1:0])
      2'b00: branchCounterTable0[gshareIndex[`SIZE_BPB_LOG-1:2]] = predCount; 
      2'b01: branchCounterTable1[gshareIndex[`SIZE_BPB_LOG-1:2]] = predCount;
      2'b10: branchCounterTable2[gshareIndex[`SIZE_BPB_LOG-1:2]] = predCount;
      2'b11: branchCounterTable3[gshareIndex[`SIZE_BPB_LOG-1:2]] = predCount;
    endcase
  `endif
    branchHistoryReg  = {branchHistoryReg[30:0],actualDir};
    `ifdef PRINT_EN
      $fwrite(fd24, "BHR: %X Index: %X  Count %X\n", branchHistoryReg, gshareIndex, predCount); 
    `endif
  endtask
  
  initial
  begin
    int i;
    //specBranchHistoryReg  = 32'b0;
    branchHistoryReg      = 32'b0;
    retiredBranchHistoryReg      = 32'b0;
  
    for(i=0;i<4096;i++)
    begin
      branchCounterTable0[i] = 2'b10;  //Weakly taken  
    `ifndef SMALL_GSHARE
      branchCounterTable1[i] = 2'b10;  //Weakly taken  
      branchCounterTable2[i] = 2'b10;  //Weakly taken  
      branchCounterTable3[i] = 2'b10;  //Weakly taken  
    `endif
    end
  end
  
  logic [`FETCH_WIDTH-1:0]      gsharePred;
  logic [`FETCH_WIDTH-1:0]      gsharePred_l1;
  logic [1:0]                   gsharePredCount[0:`FETCH_WIDTH-1];
  
  fs2Pkt                        instPacket   [0:`FETCH_WIDTH-1];
  logic                         ctrlVect     [0:`FETCH_WIDTH-1];
  logic                         ctrlVect_t   [0:`FETCH_WIDTH-1];
  logic [`BRANCH_TYPE-1:0]      ctrlType     [0:`FETCH_WIDTH-1];
  
  // LANE: Per lane logic
  always @(*)
  begin
    int i;
    for (i = 0; i < `FETCH_WIDTH; i = i + 1)
    begin
      instPacket[i].pc    = instPC[i];
      instPacket[i].inst  = inst[i];
    end
  end
  
  genvar g;
  generate
    for (g = 0; g < `FETCH_WIDTH; g = g + 1)
    begin : preDecode_gen
  
    PreDecode_PISA preDecode(
      .fs2Packet_i    (instPacket[g]),
  
    `ifdef DYNAMIC_CONFIG
      .ctrlInst_o     (ctrlVect_t[g]),
      .laneActive_i   (fabScalar.fs1.fetchLaneActive_i[g]), // Used only for power gating internaly
    `else
      .ctrlInst_o     (ctrlVect[g]),
    `endif
      .predNPC_o      (),
      .ctrlType_o     (ctrlType[g])
      );
  
  // Mimic an isolation cell      
  `ifdef DYNAMIC_CONFIG      
    always @(*)
    begin
      ctrlVect[g] = fabScalar.fs1.fetchLaneActive_i[g] ? ctrlVect_t[g] : 1'b0;
    end
  `endif
    end
  endgenerate
  
  always_ff @(posedge clk or posedge reset)
  begin
    if(reset)
      specBranchHistoryReg  <= 32'b0;
    else
    begin
      //specBranchHistoryReg_prev   <=  specBranchHistoryReg;
  
      if(fabScalar.fs1.bp.updateEn_i)
      begin
        gshareUpdatePC  <=  fabScalar.updatePC_l1;
        update_gshare(fabScalar.updatePC_l1,fabScalar.updateDir_l1);
      end
  
      // Recover the history registors if there's a recovery
      if(fabScalar.recoverFlag)
        specBranchHistoryReg  <=  retiredBranchHistoryReg;  // Revert to non-speculative history
      else if(fabScalar.fs2RecoverFlag)
      begin
        //$display ("Cycle: %d Reloading from FS2 BHR %x original %x \n",CYCLE_COUNT,specBranchHistoryRegFs2,specBranchHistoryReg);
        //specBranchHistoryReg  <=  specBranchHistoryReg; // Hold value, do not update with wrong info
        specBranchHistoryReg  <=  specBranchHistoryRegFs2; // Hold value, do not update with wrong info
      end
      else
        specBranchHistoryReg  <=  specBranchHistoryReg_next; // Update history with current cycles results
    end
  end
  
  
  always @(clk)
  begin
    int i;
    if(~clk)
    begin
      // This is the precise retired state since CTI queue and BPB update might lag
      for(i=0;i<`COMMIT_WIDTH;i++)
      begin
        if(fabScalar.activeList.commitCti_o[i] & fabScalar.activeList.ctrlAl[i][5])
        begin
          retiredBranchHistoryReg = {retiredBranchHistoryReg[30:0],fabScalar.activeList.actualDir_o[i]};
          `ifdef PRINT_EN
            //$fwrite(fd25, "BHR: %X ActualDir: %b\n", retiredBranchHistoryReg, fabScalar.activeList.actualDir_o[i]); 
          `endif
        end
      end
    end
  end
  
  always @(posedge clk)
  begin
    `ifdef PRINT_EN
      $fwrite(fd25, "BHR: %X specBHR: %X PredDir: %X\n", branchHistoryReg, specBranchHistoryRegFs2, gsharePred_l1); 
    `endif
  
    //gsharePred_l1     <=  gsharePred;
    if(fabScalar.recoverFlag)
      specBranchHistoryReg_l1 <= retiredBranchHistoryReg;
    //else if(~fabScalar.fs2RecoverFlag & instReq)
    else if(instReq)
    begin
      specBranchHistoryReg_l1 <= specBranchHistoryReg;
      gsharePred_l1     <=  gsharePred;
    end
  end
  
  // Speculative Branch History in FS2 stage
  always @(*)
  begin
    int i;
    if(~fabScalar.fs2.stall_i)
    begin
      // Undo the shifts to capture the correct number of shifts i.e shifts only for branches before the taken branch.
      specBranchHistoryRegFs2 = specBranchHistoryReg_l1;
      for(i=0;i < `FETCH_WIDTH;i++)
        // Update the FS2 BHR with valid conditional branches in the bundle upto the first taken conditional branch
        if(fabScalar.fs2.ctiQueue.ctrlVect_i[i] & fabScalar.fs2.VALIDATE_BTB.condBranchVect[i])
        begin
          specBranchHistoryRegFs2 = {specBranchHistoryRegFs2[30:0],gsharePred_l1[i]};
        end
    end
  end
  
  // Generates the predictions at negative edge of the clock
  always @(clk)
  begin
    int i;
    if(~clk)
    begin
      specBranchHistoryReg_next  =  specBranchHistoryReg;
      for(i=0;i<`FETCH_WIDTH;i++)
      begin
      `ifdef DYNAMIC_CONFIG
        if(instReq & fabScalar.fs1.fetchLaneActive_i[i] & (ctrlType[i] == `COND_BRANCH))
      `else
        if(instReq & (ctrlType[i] == `COND_BRANCH))
      `endif
        begin
          gsharePredPC[i] <= instPC[i];
          gsharePred[i] <= get_gshare_pred(instPC[i],gsharePredCount[i]);
        end
        else
        begin
          gsharePred[i] <= 1'b0;
        end
      end
    end
  end
  
  // Force the prediction from the testbench
  always @(*)
  begin
    int i;
    for(i=0;i<`FETCH_WIDTH;i++)
    begin
      fabScalar.fs1.bp.predDir_o[i]       = gsharePred[i];
      fabScalar.fs1.bp.predCounter_o[i]   = gsharePredCount[i];
    end
  end
`endif //GSHARE

endmodule

module ANTENNATF(
  input A
  );
endmodule
