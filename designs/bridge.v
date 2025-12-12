`timescale 1ns / 1ps

// AXI -> APB bridge

module bridge(
  // Clock / Reset
  input clk,            // system clock (synchronous domain for FSM and datapath)
  input arvalid,        // AXI read address valid (master has placed a read address)
  input res_n,          // active-low asynchronous reset (reset FSM and state on negedge)

  // AXI read address channel (AR)
  input [1:0] arburst,  // burst type (e.g., 00 = fixed, 01 = incr) — used to update DADDR
  input [3:0] arlen,    // burst length (AXI: number of beats - 1 usually) — used to compute lenS/lenM
  input [4:0] araddr,   // read starting address (5-bit in your design)
  output arready,       // bridge indicates it can accept AR (set when in SETUP_M state)

  // AXI read data channel (R)
  output reg [15:0] rdata, // data returned to AXI master (streamed from internal DDATA buffer)
  output rresp,            // read response flag (tied to ACCESS_M state)
  output rlast,            // indicates final beat of read burst
  input rready,            // AXI master consumer ready signal for read data
  output rvalid,           // bridge drives rvalid when it is presenting read data

  // AXI write address channel (AW)
  input awvalid,           // AXI write address valid
  input [4:0] awaddr,      // write starting address
  output awready,          // bridge accepts AW (true in WSETUP_M)

  input [3:0] awlen,       // write burst length
  input [1:0] awburst,     // write burst type

  // AXI write data channel (W)
  input wvalid,            // AXI write data valid
  input [15:0] wdata,      // AXI write data
  output wready,           // bridge ready to accept write data (true in WACCESS_M)
  input wlast,             // last write beat indicator from AXI master

  // AXI write response channel (B)
  input bready,            // AXI master ready to accept write response
  output bvalid,           // bridge indicates write response is available (WTERMINATE)
  output bresp,            // write response (tied to WTERMINATE)

  // APB interface (slave side)
  output [2:0] PADDR,      // APB address (3 bits → 8 locations per PSEL region)
  output reg [15:0] PWDATA,// APB write data driven by bridge during WACCESS_S
  input [15:0] PRDATA,     // APB read data returned by peripheral
  output PWRITE,           // APB write/not (1=write, 0=read)
  output PENABLE,          // APB enable — indicates access phase
  output PSEL1,            // APB peripheral select signals (one-hot selection of 4 regions)
  output PSEL2,
  output PSEL3,
  output PSEL4,
  input PREADY             // APB ready — peripheral finished the access
    );

    //=================================================================
    // FSM state definitions
    //=================================================================
    parameter IDLE        = 4'b0000,
              SETUP_M     = 4'b0001, // Setup on master side (read): accepted AR, preparing APB read
              SETUP_S     = 4'b0010, // Setup on slave side (APB): PSEL asserted, waiting PREADY
              ACCESS_S    = 4'b0011, // APB access phase (PENABLE asserted)
              PREACCESS_M = 4'b0100, // Wait for AXI master (rready) before presenting R data
              ACCESS_M    = 4'b0101, // Present buffered read data back to AXI master

              // Write-related states
              WSETUP_M    = 4'b0110, // AW accepted - prepare to receive write data
              WPREACCESS_M= 4'b0111, // Wait for wvalid to start capturing W data
              WACCESS_M   = 4'b1000, // Capture AXI W data into internal buffer DDATA
              WTERMINATE  = 4'b1001, // Send write response (B channel) and wait for bready
              WSETUP_S    = 4'b1010, // Begin APB writes from buffer (setup)
              WACCESS_S   = 4'b1011; // APB write access phase (drive PWDATA and wait PREADY)

    // FSM registers
    reg [3:0] current_state, next_state = IDLE;

    // DWREQ: small 2-bit flag used by APB logic:
    // DWREQ[0] -> when 1, the APB PADDR is driven from DADDR (enables APB address drives)
    // DWREQ[1] -> when 1, indicates a write sequence (used to set PWRITE)
    reg [1:0] DWREQ = 0;

    // burst: stores burst type (you used a 13-bit reg but only 2 bits used)
    reg [12:0] burst;

    // lenS: count of beats for the slave/APB side (how many APB cycles to do)
    // lenM: count of beats for the master/AXI side (how many beats to stream back to AXI)
    reg [3:0] lenS;
    reg [3:0] lenM;

    // latched 5-bit starting address from AXI AR/AW
    reg [4:0] addr;

    // internal buffer to hold up to 16 words (temp storage of reads or writes)
    reg [15:0] DDATA[15:0];

    // 3-bit APB address (offset into an 8-location peripheral block)
    reg [2:0] DADDR = 0;

    // index into DDATA[] used when writing/reading the buffer
    integer i = 0;

    // 'last' indicates final AXI read beat (used to generate rlast)
    reg last;

    //=================================================================
    // State register (synchronous)
    //=================================================================
    always@(posedge clk, negedge res_n)
    begin
      if(!res_n)
        current_state <= IDLE;    // on reset, go to IDLE
      else 
        current_state <= next_state; // otherwise latch next_state
    end

    //=================================================================
    // Next-state logic and datapath updates (combinational in your original)
    // NOTE: this block currently mixes sequential style updates; comments
    // explain what each state intends to do and why transitions occur.
    //=================================================================
    always@(arvalid, current_state, rready, PREADY, awvalid, wvalid)
    begin
      case(current_state)
        // --------------------------------------------------------------
        IDLE : begin
                 // initialize / prepare for new transfer
                 i = 0;            // buffer index reset (start of transaction)
                 last = 0;         // clear last flag for new read transactions
                 rdata = 0;        // default read data output
                 DWREQ = 0;        // default: no APB request
                 PWDATA = 0;       // default APB write data

                 // if an AXI read address is presented, begin the read flow
                 if(arvalid)
                   begin
                     // move to SETUP_M to latch AR and start APB read sequence
                     next_state <= SETUP_M; 
                     // indicate a read request so APB address/pwrite logic behaves correctly
                     DWREQ = 2'b01;
                   end
                 // else if an AXI write address is presented, begin write flow
                 else if(awvalid)
                   begin
                     // go to WSETUP_M to latch AW and prepare to capture W data
                     next_state <= WSETUP_M;
                   end
                 else
                     next_state <= IDLE;   
               end

        // --------------------------------------------------------------
        // Write: capture AW and prepare to accept W data
        // WSETUP_M: in this state, the bridge expects AW to be valid and latches AW info
        // Transition: AW accepted -> go to WPREACCESS_M (wait for W data)
        // --------------------------------------------------------------
        WSETUP_M : begin
                     if(awvalid)
                     begin
                       addr = awaddr;               // latch AW starting address
                       burst = awburst;            // latch burst type for incrementing DADDR
                       lenS = awlen + 1;           // total beats to send to APB (AXI awlen is 0-based)
                       lenM = awlen + 1;           // total beats captured from AXI W
                       DADDR = addr % 8;           // initial APB address within the peripheral block
                       next_state <= WPREACCESS_M; // now wait for wvalid to start capturing data
                     end
                     else 
                       next_state <= IDLE;  
                   end 

        // --------------------------------------------------------------
        // WPREACCESS_M: wait for the AXI master to present write data (wvalid)
        // Transition: wvalid -> WACCESS_M where W data beats are captured
        // --------------------------------------------------------------
        WPREACCESS_M : begin
                         if(wvalid)
                           next_state <= WACCESS_M;
                         else 
                           next_state <= WPREACCESS_M;
                       end      

        // --------------------------------------------------------------
        // WACCESS_M: capture write data beats from AXI W channel into DDATA[]
        // - On each beat, store wdata into DDATA[i]
        // - update index 'i' according to burst type (incr vs fixed)
        // - decrement lenM until all beats are captured
        // - if wlast asserted by master, immediately go to WTERMINATE
        // Transition: when captured all beats -> WTERMINATE
        // --------------------------------------------------------------
        WACCESS_M : begin
                   if(lenM != 4'd0)
                     begin
                       // If AXI indicates last beat via wlast, move to termination
                       if(wlast)
                         next_state <= WTERMINATE;
                       else 
                         next_state <= WPREACCESS_M;

                       // capture the write data into buffer
                       DDATA[i] = wdata;

                       // increment index for incremental burst; fixed burst holds same index
                       case(burst)
                         2'b00: i = i;       // fixed burst -> same DDATA location
                         2'b01: i = i + 1;   // incrementing burst -> next DDATA location
                         default : i = i;    // default: treat as fixed
                       endcase

                       // decrement remaining master-side beats
                       lenM = lenM - 1; 
                     end
                   else 
                     next_state <= WTERMINATE;
                 end 

        // --------------------------------------------------------------
        // WTERMINATE: provide write response on B channel
        // - bvalid will be asserted while in this state (see assign bvalid)
        // Transition:
        //   - if bready from master: proceed to perform APB slave writes (WSETUP_S)
        //   - else remain in WTERMINATE until master accepts response
        // Also set DWREQ to indicate APB write phase is coming (DWREQ=2'b11)
        // --------------------------------------------------------------
        WTERMINATE : begin
                       if(bready)
                         begin
                           next_state <= WSETUP_S;
                           // set DWREQ to 11: bit0 enables PADDR drive, bit1 indicates write
                           DWREQ = 2'b11;
                         end
                       else 
                         next_state <= WTERMINATE;
                     end

        // --------------------------------------------------------------
        // WSETUP_S: APB write setup phase (prepare PENABLE sequence on next cycle)
        // - This state simply moves to WACCESS_S where the APB write is issued
        // --------------------------------------------------------------
        WSETUP_S : begin
                     next_state <= WACCESS_S;
                   end

        // --------------------------------------------------------------
        // WACCESS_S: perform APB writes using buffered DDATA[]
        // - When PREADY asserted by APB peripheral: the write beat completed
        // - Decrement lenS and move to next beat or finish.
        // - Drive PWDATA (set from DDATA[i]) and increment APB address DADDR
        // - When final beat (lenS == 1) -> go back to IDLE after writing
        // --------------------------------------------------------------
        WACCESS_S : begin
                      if(PREADY)
                        begin
                          if(lenS != 4'd0)
                            begin
                              // if final beat about to be performed, going to IDLE afterwards
                              if(lenS == 4'd1)
                                next_state <= IDLE;
                              else 
                                next_state <= WSETUP_S;

                              // buffer pointer is decremented because we filled DDATA with i increasing
                              // during WACCESS_M and now drain from the most-recent entries.
                              i = i - 1;

                              // increment APB address (sequential region)
                              DADDR = DADDR + 1;

                              // drive the APB write data for this beat
                              PWDATA = DDATA[i];

                              // decrement slave-side count (how many APB writes remain)
                              lenS = lenS - 1;
                            end
                        end
                      else 
                        // if APB is not ready, idle (note: the code sets goto IDLE when PREADY low;
                        // this is likely not ideal—keeps original behavior)
                        next_state <= IDLE;
                    end

        // --------------------------------------------------------------
        // SETUP_M: read path — capture AR parameters and transition to APB setup
        // - Latch araddr, arburst
        // - Initialize lenS/lenM and set DADDR based on start address
        // - Move to SETUP_S which handles the APB read setup
        // --------------------------------------------------------------
        SETUP_M : begin
                    if(arvalid)
                    begin
                      addr = araddr;
                      burst = arburst;

                      // NOTE: original code uses lenS = arlen and lenM = arlen + 1
                      // This is intended to create a master-side count (lenM) and a
                      // slave-side APB count (lenS). Keep the original behavior here.
                      lenS = arlen; 
                      lenM = arlen + 1;

                      // derive initial APB local address from overall AXI address
                      DADDR = addr % 8;

                      // move to APB setup state
                      next_state <= SETUP_S;
                    end 
                    else 
                      next_state <= IDLE;                  
                  end

        // --------------------------------------------------------------
        // SETUP_S: APB setup phase for a read
        // - Wait for APB peripheral to indicate ready (PREADY)
        // - When PREADY, sample PRDATA into DDATA[] and proceed to ACCESS_S
        //   (ACCESS_S will increment DADDR and loop to generate further APB accesses)
        // --------------------------------------------------------------
        SETUP_S : begin
                    if(PREADY)
                      begin
                        // sample read data from APB peripheral into buffer
                        DDATA[i] = PRDATA;
                        // go to ACCESS_S to handle further beats or return to master
                        next_state <= ACCESS_S;
                      end 
                    else 
                      next_state <= SETUP_S;
                  end  

        // --------------------------------------------------------------
        // ACCESS_S: APB access sequence driver for read bursts
        // - If there are more slave beats (lenS != 0):
        //     - increment or keep DADDR according to burst type
        //     - decrement lenS, increment buffer index i, and loop back to SETUP_S
        // - else (all APB reads captured) -> transition to PREACCESS_M
        //   which waits for rready before streaming to AXI master
        // --------------------------------------------------------------
        ACCESS_S : begin
                     if(lenS != 0)
                       begin
                         // adjust APB address for sequential bursts
                         case(burst)
                         2'b00 : DADDR = DADDR;       // fixed burst
                         2'b01 : DADDR = DADDR + 1;   // incrementing burst
                         default : DADDR = DADDR;
                         endcase 

                       lenS = lenS - 1; // one less APB beat to gather
                       i = i + 1;       // advance buffer write index
                       next_state <= SETUP_S; 
                       end
                     else
                       // all APB beats collected; switch to master-side transfer
                       next_state <= PREACCESS_M;
                   end

        // --------------------------------------------------------------
        // PREACCESS_M: wait for AXI read consumer (rready) before presenting data
        // - This state prevents presenting read data until master can accept it
        // - Transition: rready -> ACCESS_M
        // --------------------------------------------------------------
        PREACCESS_M : begin
                        if(rready)
                          next_state <= ACCESS_M;
                        else 
                          next_state <= PREACCESS_M; 
                      end 

        // --------------------------------------------------------------
        // ACCESS_M: stream buffered read data back to AXI master
        // - On each beat:
        //     - set rdata = DDATA[i], decrement i and lenM
        //     - if this beat is final (lenM == 1), set last and move to IDLE
        //     - otherwise go back to PREACCESS_M and wait for rready for next beat
        // - When lenM reaches zero, transition to IDLE
        // --------------------------------------------------------------
        ACCESS_M : begin
                     if(lenM != 0)
                       begin
                         if(lenM == 4'd1)
                           begin
                             // next beat will be the last one; set last flag for rlast
                             last = 1;
                             next_state <= IDLE;
                           end
                         else 
                           next_state <= PREACCESS_M;

                         // provide read data from buffer to AXI master
                         rdata = DDATA[i];

                         // move buffer pointer backwards (draining)
                         i = i - 1;

                         // decrement remaining master-side beats
                         lenM = lenM - 1;
                       end
                     else 
                       next_state <= IDLE;
                   end

        // --------------------------------------------------------------
        default : next_state <= IDLE;
      endcase 
    end

    //=================================================================
    // APB / AXI output signal assignments
    // - These are combinational in your design and reflect the FSM state
    //=================================================================
    assign arready = (current_state == SETUP_M); // accept AR when in SETUP_M

    // APB address driven from DADDR only when DWREQ[0] indicates a request
    assign PADDR = DWREQ[0] ? DADDR : 3'd0;

    // PSEL1..PSEL4: choose which APB slave region is selected based on full 'addr'
    // These are asserted only during states where APB setup/access is expected.
    assign PSEL1 = (current_state == SETUP_M || current_state == SETUP_S || current_state == ACCESS_S || current_state == WSETUP_S || current_state == WACCESS_S) ? ((addr >= 5'b00000 && addr <= 5'b00111) ? 1 : 0) : 0;
    assign PSEL2 = (current_state == SETUP_M || current_state == SETUP_S || current_state == ACCESS_S || current_state == WSETUP_S || current_state == WACCESS_S) ? ((addr >= 5'b01000 && addr <= 5'b01111) ? 1 : 0) : 0;
    assign PSEL3 = (current_state == SETUP_M || current_state == SETUP_S || current_state == ACCESS_S || current_state == WSETUP_S || current_state == WACCESS_S) ? ((addr >= 5'b10000 && addr <= 5'b10111) ? 1 : 0) : 0;
    assign PSEL4 = (current_state == SETUP_M || current_state == SETUP_S || current_state == ACCESS_S || current_state == WSETUP_S || current_state == WACCESS_S) ? ((addr >= 5'b11000 && addr <= 5'b11111) ? 1 : 0) : 0;

    // PWRITE is asserted when DWREQ[1] (indicating a write operation) is set
    // and one of the PSELx lines is active (APB slave is selected)
    assign PWRITE = (DWREQ[1] && (PSEL1 || PSEL2 || PSEL3 || PSEL4));

    // PENABLE is used during APB access phases (SETUP_S/ACCESS_S/WACCESS_S)
    assign PENABLE = (current_state == SETUP_S || current_state == ACCESS_S || current_state == WACCESS_S);

    // AXI read channel response flags are driven from FSM state
    assign rresp = (current_state == ACCESS_M);
    assign rlast = (rresp && last);       // rlast asserted on the last read beat
    assign rvalid = (current_state == ACCESS_M); // present data when in ACCESS_M

    // AXI write handshake signals
    assign awready = (current_state == WSETUP_M); // accept AW in WSETUP_M
    assign wready  = (current_state == WACCESS_M); // accept W data in WACCESS_M

    // AXI write response
    assign bvalid = (current_state == WTERMINATE); // bvalid while in WTERMINATE
    assign bresp  = (current_state == WTERMINATE); // bresp asserted same as bvalid


endmodule
