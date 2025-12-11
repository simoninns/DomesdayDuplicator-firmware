/************************************************************************
	
	IPfifo.v
	Dual-clock FIFO module (replaces Intel IP)
	
	Domesday Duplicator - LaserDisc RF sampler
	SPDX-FileCopyrightText: 2018-2025 Simon Inns
	SPDX-License-Identifier: GPL-3.0-or-later
	
	This is a dual-clock FIFO implementation that replaces the Intel
	dcfifo IP core. It uses Gray code counters for safe clock domain
	crossing between write and read clock domains.
	
	Parameters:
	- DEPTH: Number of words in FIFO (power of 2, default: 8192)
	- DATA_WIDTH: Width of each word in bits (default: 16)
	- Address width is calculated automatically from DEPTH
	- Show-ahead mode (data available without explicit read)
	
	Supported DEPTH values: 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024,
	2048, 4096, 8192, 16384
	
	Usage examples:
	  // Default 8192 x 16-bit FIFO (backward compatible)
	  IPfifo fifo_default (.aclr(), .data(), .rdclk(), ...);
	  
	  // 4096 x 16-bit FIFO
	  IPfifo #(.DEPTH(4096)) fifo_small (.aclr(), .data(), .rdclk(), ...);
	  
	  // 2048 x 32-bit FIFO
	  IPfifo #(.DEPTH(2048), .DATA_WIDTH(32)) fifo_wide (.aclr(), ...);
	
	Note: For compatibility with the original IPfifo interface, the
	used words output is always 14 bits (supports up to 16384 words).
	If DEPTH > 16384, used words will not display the full count.
	
************************************************************************/

module IPfifo #(
	parameter DEPTH = 8192,      // Number of words in FIFO
	parameter DATA_WIDTH = 16    // Width of each word in bits
) (
	input        aclr,                           // Asynchronous clear
	input [DATA_WIDTH-1:0] data,                 // Write data
	input        rdclk,                          // Read clock
	input        rdreq,                          // Read request
	input        wrclk,                          // Write clock
	input        wrreq,                          // Write request
	output [DATA_WIDTH-1:0] q,                   // Read data (show-ahead)
	output       rdempty,                        // Read domain empty flag
	output [13:0] rdusedw,                       // Read domain used words
	output       wrempty,                        // Write domain empty flag
	output [13:0] wrusedw                        // Write domain used words
);

// Calculate address width based on DEPTH
// For DEPTH = 2^n, ADDR_WIDTH = n
localparam ADDR_WIDTH = (DEPTH == 2) ? 1 :
                        (DEPTH == 4) ? 2 :
                        (DEPTH == 8) ? 3 :
                        (DEPTH == 16) ? 4 :
                        (DEPTH == 32) ? 5 :
                        (DEPTH == 64) ? 6 :
                        (DEPTH == 128) ? 7 :
                        (DEPTH == 256) ? 8 :
                        (DEPTH == 512) ? 9 :
                        (DEPTH == 1024) ? 10 :
                        (DEPTH == 2048) ? 11 :
                        (DEPTH == 4096) ? 12 :
                        (DEPTH == 8192) ? 13 :
                        (DEPTH == 16384) ? 14 : 14;

// Memory array
reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

// Write domain signals
reg [ADDR_WIDTH-1:0] wr_ptr;
reg [ADDR_WIDTH-1:0] wr_ptr_gray;
reg [ADDR_WIDTH-1:0] wr_ptr_gray_sync1;
reg [ADDR_WIDTH-1:0] wr_ptr_gray_sync2;

// Read domain signals
reg [ADDR_WIDTH-1:0] rd_ptr;
reg [ADDR_WIDTH-1:0] rd_ptr_gray;
reg [ADDR_WIDTH-1:0] rd_ptr_gray_sync1;
reg [ADDR_WIDTH-1:0] rd_ptr_gray_sync2;

// Binary versions of synchronized pointers
wire [ADDR_WIDTH-1:0] rd_ptr_wr_domain;
wire [ADDR_WIDTH-1:0] wr_ptr_rd_domain;

// --------------------------------------------------------------------
// Write domain logic
// --------------------------------------------------------------------

// Write pointer increment
always @(posedge wrclk or posedge aclr) begin
	if (aclr) begin
		wr_ptr <= {ADDR_WIDTH{1'b0}};
	end else if (wrreq) begin
		wr_ptr <= wr_ptr + 1'b1;
	end
end

// Write to memory
always @(posedge wrclk) begin
	if (wrreq) begin
		mem[wr_ptr] <= data;
	end
end

// Binary to Gray conversion for write pointer
always @(posedge wrclk or posedge aclr) begin
	if (aclr) begin
		wr_ptr_gray <= {ADDR_WIDTH{1'b0}};
	end else begin
		wr_ptr_gray <= wr_ptr ^ (wr_ptr >> 1);
	end
end

// Synchronize read pointer to write clock domain
always @(posedge wrclk or posedge aclr) begin
	if (aclr) begin
		rd_ptr_gray_sync1 <= {ADDR_WIDTH{1'b0}};
		rd_ptr_gray_sync2 <= {ADDR_WIDTH{1'b0}};
	end else begin
		rd_ptr_gray_sync1 <= rd_ptr_gray;
		rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
	end
end

// Gray to binary conversion for synchronized read pointer
function [ADDR_WIDTH-1:0] gray_to_binary;
	input [ADDR_WIDTH-1:0] gray;
	integer i;
	begin
		gray_to_binary[ADDR_WIDTH-1] = gray[ADDR_WIDTH-1];
		for (i = ADDR_WIDTH-2; i >= 0; i = i - 1) begin
			gray_to_binary[i] = gray_to_binary[i+1] ^ gray[i];
		end
	end
endfunction

assign rd_ptr_wr_domain = gray_to_binary(rd_ptr_gray_sync2);

// Write domain empty flag and used words calculation
assign wrempty = (wr_ptr == rd_ptr_wr_domain);
assign wrusedw = wr_ptr - rd_ptr_wr_domain;

// --------------------------------------------------------------------
// Read domain logic
// --------------------------------------------------------------------

// Read pointer increment
always @(posedge rdclk or posedge aclr) begin
	if (aclr) begin
		rd_ptr <= {ADDR_WIDTH{1'b0}};
	end else if (rdreq && !rdempty) begin
		rd_ptr <= rd_ptr + 1'b1;
	end
end

// Binary to Gray conversion for read pointer
always @(posedge rdclk or posedge aclr) begin
	if (aclr) begin
		rd_ptr_gray <= {ADDR_WIDTH{1'b0}};
	end else begin
		rd_ptr_gray <= rd_ptr ^ (rd_ptr >> 1);
	end
end

// Synchronize write pointer to read clock domain
always @(posedge rdclk or posedge aclr) begin
	if (aclr) begin
		wr_ptr_gray_sync1 <= {ADDR_WIDTH{1'b0}};
		wr_ptr_gray_sync2 <= {ADDR_WIDTH{1'b0}};
	end else begin
		wr_ptr_gray_sync1 <= wr_ptr_gray;
		wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
	end
end

assign wr_ptr_rd_domain = gray_to_binary(wr_ptr_gray_sync2);

// Read domain empty flag and used words calculation
assign rdempty = (rd_ptr == wr_ptr_rd_domain);
assign rdusedw = wr_ptr_rd_domain - rd_ptr;

// Show-ahead output - combinational read with register for timing
// This matches Intel's LPM_SHOWAHEAD="ON" behavior
assign q = mem[rd_ptr];

endmodule
