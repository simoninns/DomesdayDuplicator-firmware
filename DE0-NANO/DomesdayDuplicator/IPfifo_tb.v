/************************************************************************
	
	IPfifo_tb.v
	Testbench for dual-clock FIFO module
	
	Domesday Duplicator - LaserDisc RF sampler
	SPDX-FileCopyrightText: 2018-2025 Simon Inns
	SPDX-License-Identifier: GPL-3.0-or-later
	
	This testbench verifies the FIFO functionality including:
	- Basic write/read operations
	- Clock domain crossing
	- Empty/full flag behavior
	- Used words counters
	- Show-ahead mode
	- Asynchronous clear
	
************************************************************************/

`timescale 1ns / 1ps

module IPfifo_tb;

// Clock periods
localparam WR_CLK_PERIOD = 10;  // 100 MHz write clock
localparam RD_CLK_PERIOD = 8;   // 125 MHz read clock (different to test CDC)

// Testbench signals
reg aclr;
reg [15:0] data;
reg rdclk;
reg rdreq;
reg wrclk;
reg wrreq;
wire [15:0] q;
wire rdempty;
wire [13:0] rdusedw;
wire wrempty;
wire [13:0] wrusedw;

// Test control
integer errors;
integer i;
reg [15:0] expected_data;

// Instantiate the FIFO
IPfifo uut (
	.aclr(aclr),
	.data(data),
	.rdclk(rdclk),
	.rdreq(rdreq),
	.wrclk(wrclk),
	.wrreq(wrreq),
	.q(q),
	.rdempty(rdempty),
	.rdusedw(rdusedw),
	.wrempty(wrempty),
	.wrusedw(wrusedw)
);

// Generate write clock
initial begin
	wrclk = 0;
	forever #(WR_CLK_PERIOD/2) wrclk = ~wrclk;
end

// Generate read clock
initial begin
	rdclk = 0;
	forever #(RD_CLK_PERIOD/2) rdclk = ~rdclk;
end

// Main test sequence
initial begin
	$display("=== IPfifo Testbench Start ===");
	errors = 0;
	
	// Initialize signals
	aclr = 1;
	data = 16'h0000;
	rdreq = 0;
	wrreq = 0;
	
	// Wait for a few clocks
	repeat(10) @(posedge wrclk);
	aclr = 0;
	repeat(5) @(posedge wrclk);
	
	// Test 1: Check initial empty state
	$display("\n--- Test 1: Initial State ---");
	@(posedge wrclk);
	if (wrempty !== 1'b1) begin
		$display("ERROR: FIFO should be empty after reset (wrempty)");
		errors = errors + 1;
	end
	@(posedge rdclk);
	if (rdempty !== 1'b1) begin
		$display("ERROR: FIFO should be empty after reset (rdempty)");
		errors = errors + 1;
	end
	$display("Initial empty state: PASS");
	
	// Test 2: Write single word
	$display("\n--- Test 2: Single Write ---");
	@(posedge wrclk);
	data = 16'hA5A5;
	wrreq = 1;
	@(posedge wrclk);
	wrreq = 0;
	
	// Wait for synchronization
	repeat(10) @(posedge rdclk);
	
	if (rdempty) begin
		$display("ERROR: FIFO should not be empty after write");
		errors = errors + 1;
	end else begin
		$display("Single write: PASS");
	end
	
	// Test 3: Check show-ahead data
	$display("\n--- Test 3: Show-Ahead Mode ---");
	@(posedge rdclk);
	if (q !== 16'hA5A5) begin
		$display("ERROR: Show-ahead data incorrect. Expected: A5A5, Got: %h", q);
		errors = errors + 1;
	end else begin
		$display("Show-ahead mode: PASS (data = %h)", q);
	end
	
	// Test 4: Read single word
	$display("\n--- Test 4: Single Read ---");
	@(posedge rdclk);
	rdreq = 1;
	@(posedge rdclk);
	rdreq = 0;
	
	// Wait for synchronization
	repeat(10) @(posedge wrclk);
	
	if (!wrempty) begin
		$display("ERROR: FIFO should be empty after reading single word");
		errors = errors + 1;
	end else begin
		$display("Single read: PASS");
	end
	
	// Test 5: Write multiple words
	$display("\n--- Test 5: Multiple Writes ---");
	for (i = 0; i < 100; i = i + 1) begin
		@(posedge wrclk);
		data = i[15:0];
		wrreq = 1;
	end
	@(posedge wrclk);
	wrreq = 0;
	
	// Wait for synchronization
	repeat(10) @(posedge rdclk);
	
	if (rdusedw < 100) begin
		$display("ERROR: Used words counter incorrect. Expected >= 100, Got: %d", rdusedw);
		errors = errors + 1;
	end else begin
		$display("Multiple writes: PASS (rdusedw = %d)", rdusedw);
	end
	
	// Test 6: Read and verify multiple words
	$display("\n--- Test 6: Multiple Reads with Verification ---");
	// Wait for first data to cross clock domains
	repeat(10) @(posedge rdclk);
	
	for (i = 0; i < 100; i = i + 1) begin
		expected_data = i[15:0];
		// In show-ahead mode, data at rd_ptr is immediately visible on q
		if (q !== expected_data) begin
			$display("ERROR: Data mismatch at word %d. Expected: %h, Got: %h", i, expected_data, q);
			errors = errors + 1;
		end
		// Issue read to increment pointer for next word
		rdreq = 1;
		@(posedge rdclk);  // rd_ptr increments on this edge
		rdreq = 0;
		// q now shows new data combinationally after rd_ptr changed
	end
	
	if (errors == 0) begin
		$display("Multiple reads with verification: PASS");
	end
	
	if (errors == 0) begin
		$display("Multiple reads with verification: PASS");
	end
	
	// Test 7: Concurrent read/write (different rates)
	$display("\n--- Test 7: Concurrent Read/Write ---");
	
	// Empty FIFO first
	repeat(20) @(posedge wrclk);
	
	fork
		// Writer task - write 500 words
		begin
			for (i = 1000; i < 1500; i = i + 1) begin
				@(posedge wrclk);
				data = i[15:0];
				wrreq = 1;
			end
			@(posedge wrclk);
			wrreq = 0;
		end
		
		// Reader task - read after data accumulates, slower than write
		begin
			repeat(100) @(posedge rdclk);  // Wait for lots of data
			for (i = 1000; i < 1500; i = i + 1) begin
				expected_data = i[15:0];
				// Wait extra cycles occasionally to let writer get ahead
				if ((i % 10) == 0) repeat(3) @(posedge rdclk);
				@(posedge rdclk);
				// Check show-ahead data
				if (q !== expected_data) begin
					$display("ERROR: Concurrent R/W data mismatch at %d. Expected: %h, Got: %h", i, expected_data, q);
					errors = errors + 1;
				end
				rdreq = 1;
				@(posedge rdclk);
				rdreq = 0;
			end
		end
	join
	
	// Drain any remaining data
	repeat(50) @(posedge rdclk);
	while (!rdempty) begin
		@(posedge rdclk);
		rdreq = 1;
		@(posedge rdclk);
		rdreq = 0;
	end
	
	$display("Concurrent read/write: COMPLETE");
	
	// Test 8: Fill FIFO significantly (test counter wrap)
	$display("\n--- Test 8: Large Data Transfer ---");
	for (i = 0; i < 4096; i = i + 1) begin
		@(posedge wrclk);
		data = (i ^ 16'h5555);  // Pattern to detect errors
		wrreq = 1;
	end
	@(posedge wrclk);
	wrreq = 0;
	
	// Wait for sync
	repeat(20) @(posedge rdclk);
	
	$display("Written 4096 words, rdusedw = %d", rdusedw);
	
	// Read them back
	for (i = 0; i < 4096; i = i + 1) begin
		expected_data = (i ^ 16'h5555);
		@(posedge rdclk);
		if (q !== expected_data) begin
			$display("ERROR: Large transfer data mismatch at %d. Expected: %h, Got: %h", 
			         i, expected_data, q);
			errors = errors + 1;
			if (errors > 10) begin
				$display("Too many errors, stopping verification...");
				i = 4096;  // Exit loop
			end
		end
		rdreq = 1;
		@(posedge rdclk);
		rdreq = 0;
	end
	
	// Test 9: Async clear during operation
	$display("\n--- Test 9: Asynchronous Clear ---");
	// Write some data
	for (i = 0; i < 50; i = i + 1) begin
		@(posedge wrclk);
		data = 16'hFFFF;
		wrreq = 1;
	end
	@(posedge wrclk);
	wrreq = 0;
	
	// Assert clear
	#100;
	aclr = 1;
	#100;
	aclr = 0;
	
	// Check empty flags
	repeat(10) @(posedge wrclk);
	if (!wrempty) begin
		$display("ERROR: FIFO should be empty after async clear (write domain)");
		errors = errors + 1;
	end
	repeat(10) @(posedge rdclk);
	if (!rdempty) begin
		$display("ERROR: FIFO should be empty after async clear (read domain)");
		errors = errors + 1;
	end
	$display("Async clear: PASS");
	
	// Final results
	$display("\n=== Test Results ===");
	if (errors == 0) begin
		$display("ALL TESTS PASSED!");
	end else begin
		$display("TESTS FAILED with %d errors", errors);
	end
	$display("====================\n");
	
	#1000;
	$finish;
end

// Timeout watchdog
initial begin
	#1000000;  // 1ms timeout
	$display("ERROR: Testbench timeout!");
	$finish;
end

// Optional: Dump waveforms for GTKWave or ModelSim
initial begin
	$dumpfile("IPfifo_tb.vcd");
	$dumpvars(0, IPfifo_tb);
end

endmodule
