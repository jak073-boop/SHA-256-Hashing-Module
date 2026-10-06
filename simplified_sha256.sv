module simplified_sha256 #(parameter integer NUM_OF_WORDS = 20)(
 input logic  clk, reset_n, start,
 input logic  [15:0] message_addr, output_addr,
 output logic done, mem_clk, mem_we,
 output logic [15:0] mem_addr,
 output logic [31:0] mem_write_data,
 input logic [31:0] mem_read_data);

// FSM state variables
// Note : Students can add more states or remove states as per their implementation
enum logic [2:0] {IDLE, READ, BLOCK, COMPUTE, WRITE} state;


// Local variables
// Note : Add or remove variables as per your implementation
logic [31:0] w[16]; // This is for word expansion in compute sate. For optimized implementation this can be w[16]
logic [31:0] message[20]; // Stores 20 message words after read from the memory
logic [31:0] wt;
logic [31:0] h0, h1, h2, h3, h4, h5, h6, h7;
logic [31:0] a, b, c, d, e, f, g, h;
logic [ 7:0] i, j;
logic [15:0] offset; // in word address
logic [ 7:0] num_blocks;
logic        cur_we;
logic [15:0] cur_addr;
logic [31:0] cur_write_data;
logic [512:0] memory_block;
logic [ 7:0] tstep;
logic read_pending;
logic [31:0] s0, s1, w_new;




// SHA256 K constants
parameter int k[0:63] = '{
   32'h428a2f98,32'h71374491,32'hb5c0fbcf,32'he9b5dba5,32'h3956c25b,32'h59f111f1,32'h923f82a4,32'hab1c5ed5,
   32'hd807aa98,32'h12835b01,32'h243185be,32'h550c7dc3,32'h72be5d74,32'h80deb1fe,32'h9bdc06a7,32'hc19bf174,
   32'he49b69c1,32'hefbe4786,32'h0fc19dc6,32'h240ca1cc,32'h2de92c6f,32'h4a7484aa,32'h5cb0a9dc,32'h76f988da,
   32'h983e5152,32'ha831c66d,32'hb00327c8,32'hbf597fc7,32'hc6e00bf3,32'hd5a79147,32'h06ca6351,32'h14292967,
   32'h27b70a85,32'h2e1b2138,32'h4d2c6dfc,32'h53380d13,32'h650a7354,32'h766a0abb,32'h81c2c92e,32'h92722c85,
   32'ha2bfe8a1,32'ha81a664b,32'hc24b8b70,32'hc76c51a3,32'hd192e819,32'hd6990624,32'hf40e3585,32'h106aa070,
   32'h19a4c116,32'h1e376c08,32'h2748774c,32'h34b0bcb5,32'h391c0cb3,32'h4ed8aa4a,32'h5b9cca4f,32'h682e6ff3,
   32'h748f82ee,32'h78a5636f,32'h84c87814,32'h8cc70208,32'h90befffa,32'ha4506ceb,32'hbef9a3f7,32'hc67178f2
};

// Get num of blocks
assign num_blocks = determine_num_blocks(NUM_OF_WORDS);
assign tstep = (i - 1);


// for compute state/bubble removal, never waiting on w_new as it 
//fixed formula from SHA-256 spec (FIPS 180-4)
assign s0 = rightrotate(w[1], 7) ^ rightrotate(w[1], 18) ^ (w[1] >> 3);
assign s1 = rightrotate(w[14], 17) ^ rightrotate(w[14], 19) ^ (w[14] >> 10);
// already holds the correct value for round 16
assign w_new = w[0] + s0 + w[9] + s1;



// Note : Function defined are for reference purpose. Feel free to add more functions or modify below.
// Function to determine number of blocks in memory to fetch
function logic [15:0] determine_num_blocks(input logic [31:0] size);

  // Student to add function implementation
  // message + padding word + 64-bit length
    determine_num_blocks = (size + 18) / 16;

endfunction


// SHA256 hash round
function logic [255:0] sha256_op(input logic [31:0] a, b, c, d, e, f, g, h, w,
                                 input logic [7:0] t);
    logic [31:0] S1, S0, ch, maj, t1, t2; // internal signals
begin
    S1 = rightrotate(e, 6) ^ rightrotate(e, 11) ^ rightrotate(e, 25);
    // Student to add remaning code below
    // Refer to SHA256 discussion slides to get logic for this function
    ch = (e & f) ^ ((~e) & g);
    t1 = h + S1 + ch + k[t] + w;
    S0 = rightrotate(a, 2) ^ rightrotate(a, 13) ^ rightrotate(a, 22);
    maj = (a & b) ^ (a & c) ^ (b & c);
    t2 = S0 + maj;

    sha256_op = {t1 + t2, a, b, c, d + t1, e, f, g};
end
endfunction


// Generate request to memory
// for reading from memory to get original message
// for writing final computed has value
assign mem_clk = clk;
assign mem_addr = cur_addr + offset;
assign mem_we = cur_we;
assign mem_write_data = cur_write_data;


// Right Rotation Example : right rotate input x by r
// Lets say input x = 1111 ffff 2222 3333 4444 6666 7777 8888
// lets say r = 4
// x >> r  will result in : 0000 1111 ffff 2222 3333 4444 6666 7777
// x << (32-r) will result in : 8888 0000 0000 0000 0000 0000 0000 0000
// final right rotate expression is = (x >> r) | (x << (32-r));
// (0000 1111 ffff 2222 3333 4444 6666 7777) | (8888 0000 0000 0000 0000 0000 0000 0000)
// final value after right rotate = 8888 1111 ffff 2222 3333 4444 6666 7777
// Right rotation function
function logic [31:0] rightrotate(input logic [31:0] x,
                                  input logic [ 7:0] r);
   rightrotate = (x >> r) | (x << (32 - r));
endfunction

// Generate the next SHA256 expanded word using the rolling w[16] array
function logic [31:0] wtnew;
   logic [31:0] s0, s1;
begin

   s0 = rightrotate(w[1], 7)
        ^ rightrotate(w[1], 18)
        ^ (w[1] >> 3);

   s1 = rightrotate(w[14], 17)
        ^ rightrotate(w[14], 19)
        ^ (w[14] >> 10);

   wtnew = w[0] + s0 + w[9] + s1;

end
endfunction

// SHA-256 FSM
// Get a BLOCK from the memory, COMPUTE Hash output using S
// and write back hash value back to memory
// Note : Inside always_ff all statements should use non-bl
always_ff @(posedge clk, negedge reset_n)
begin
  if (!reset_n) begin
    cur_we <= 1'b0;
    state <= IDLE;
  end
  else case (state)
    // Initialize hash values h0 to h7 and a to h, other va
    IDLE: begin
      if(start) begin
        // Student to add rest of the code
        h0 <= 32'h6a09e667;
        h1 <= 32'hbb67ae85;
        h2 <= 32'h3c6ef372;
        h3 <= 32'ha54ff53a;
        h4 <= 32'h510e527f;
        h5 <= 32'h9b05688c;
        h6 <= 32'h1f83d9ab;
        h7 <= 32'h5be0cd19;

        a <= 32'h6a09e667;
        b <= 32'hbb67ae85;
        c <= 32'h3c6ef372;
        d <= 32'ha54ff53a;
        e <= 32'h510e527f;
        f <= 32'h9b05688c;
        g <= 32'h1f83d9ab;
        h <= 32'h5be0cd19;

        i <= 8'd0;
        j <= 8'd0;

        offset <= 16'd0;

        cur_addr <= message_addr;
        cur_we <= 1'b0;
        cur_write_data <= 32'd0;
		  read_pending <= 1'b1;

        state <= READ;
      end
    end

    // READ state was already declared in the original FSM,
    // but the starter file did not provide the READ state b
    READ: begin

      if (offset < NUM_OF_WORDS)
			//streaming addresses unconditionally, every cycle
			offset <= offset + 16'd1; 
      if (read_pending) begin
			//address for word 0 -> not valid yet
			read_pending <= 1'b0;
		end
      else begin
        message[i] <= mem_read_data;

        if (i == NUM_OF_WORDS - 1) begin
          i <= 8'd0;
          offset <= 16'd0;
          state <= BLOCK;
        end
        else begin
          i <= i + 8'd1;
        end
      end
    end

    // SHA-256 FSM
    // Get a BLOCK from the memory, COMPUTE Hash output usin
    // and write back hash value back to memory
    BLOCK: begin
    // Fetch message in 512-bit block size
    // For each of 512-bit block initiate hash value computat
      for (int n = 0; n < 16; n = n + 1) begin 

        // Original message words
        if ((j * 16 + n) < NUM_OF_WORDS) begin

          w[n] <= message[j * 16 + n];

        end

        // First padding bit
        else if ((j * 16 + n) == NUM_OF_WORDS) begin

          w[n] <= 32'h80000000;

        end

        // Final word contains the original message length in bits
        else if ((j * 16 + n) == (num_blocks * 16 - 1)) begin

          w[n] <= NUM_OF_WORDS * 32;

        end

        // Remaining padding words
        else begin

          w[n] <= 32'h00000000;

        end

      

          a <= h0;
          b <= h1;
          c <= h2;
          d <= h3;
          e <= h4;
          f <= h5;
          g <= h6;
          h <= h7;

          i <= 8'd0;
          state <= COMPUTE;

      end
	 end
	 


    // For each block compute hash function
    // Go back to BLOCK stage after each block hash computation is c
    // there are still number of message blocks available in memory
    // move to WRITE stage
    COMPUTE: begin
    // 64 processing rounds steps for 512-bit block
    // Rounds 0-15 use original message words
    if (i < 16) begin
      {a, b, c, d, e, f, g, h}
          <= sha256_op(a, b, c, d, e, f, g, h, w[i], i);
      i <= i + 8'd1;
    end

    /* Generate w[16]. SHA is skipped for this clock cycle.
    else if (i == 16) begin
		for (int n = 0; n < 15; n = n + 1) begin
       w[n] <= w[n + 1];
      end

		i <= i + 8'd1;

    end


    // w[15] contains the newest expanded word.
    // tstep = i - 1
    else if (i <= 64) begin
      {a, b, c, d, e, f, g, h}
          <= sha256_op(a, b, c, d, e, f, g, h, w[15], tstep);

      if (i < 64) begin
        for (int n = 0; n < 15; n = n + 1) begin
          w[n] <= w[n + 1];
        end
        w[15] <= wtnew;
      end
      i <= i + 8'd1;
    end*/
	 
	 else if (i < 64) begin
		{a,b,c,d,e,f,g,h} <= sha256_op(a,b,c,d,e,f,g,h, w_new, i);
		for (int n = 0; n < 15; n = n + 1) begin
				w[n] <= w[n+1];
			end
			w[15] <= w_new;
			i <= i + 8'd1;
	  end

    // All 64 rounds finished
    else begin

      h0 <= h0 + a;
      h1 <= h1 + b;
      h2 <= h2 + c;
      h3 <= h3 + d;
      h4 <= h4 + e;
      h5 <= h5 + f;
      h6 <= h6 + g;
      h7 <= h7 + h;

      i <= 8'd0;

      // Process another 512-bit block if one remains.
      if ((j + 1) < num_blocks) begin

        j <= j + 8'd1;

        state <= BLOCK;
      end

      // All blocks finished.
      else begin
        j <= 8'd0;

        cur_we <= 1'b0;
        cur_addr <= output_addr;
        offset <= 16'd0;

        state <= WRITE;

      end
    end
    // END OF COMPUTE STATE
    end


    // h0 to h7 each are 32 bit hashes, which mak
    // h0 to h7 after compute stage has final com
    // write back these h0 to h7 to memory starti
    WRITE: begin


      // Student to add rest of the code

      // Prepare H0 for the first memory write.
      if (!cur_we) begin

        cur_we <= 1'b1;

        cur_addr <= output_addr;
        offset <= 16'd0;

        i <= 8'd0;

        cur_write_data <= h0;

      end

      // Write H1 through H7.
      else if (i < 7) begin

        i <= i + 8'd1;
        offset <= offset + 16'd1;

        case (i)

          0: cur_write_data <= h1;
          1: cur_write_data <= h2;
          2: cur_write_data <= h3;
          3: cur_write_data <= h4;
          4: cur_write_data <= h5;
          5: cur_write_data <= h6;
          6: cur_write_data <= h7;

          default: cur_write_data <= h0;
        endcase
      end

      // All eight hash words have been written.
      else begin

        cur_we <= 1'b0;

        offset <= 16'd0;
        i <= 8'd0;

        state <= IDLE;

      end
    end

  endcase
end

// Generate done when SHA256 hash computation has
assign done = (state == IDLE);

endmodule