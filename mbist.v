// Module for Built-in Self Test controller.
module BIST_controller (
  input wire start, rst, clk, stop,  
  output wire tmode                  
);

parameter reset = 1'b 0, test = 1'b 1;

reg current = reset;   
always @ (posedge clk) begin  
  if (rst)                
    current <= reset;
  else                   
    case(current)
      reset: if (start)       
        current <= test;     
      else                  
        current <= reset;
      test: if (stop)         
        current <= reset;    
      else                  
        current <= test;
      default:              
        current <= reset;
    endcase
end

assign tmode = (current == test) ? 1'b 1 : 1'b 0; 

endmodule


// Module for comparing two input signals.
module comparator #(parameter wlength=4)(
  input wire clk,                   
  input wire [wlength-1:0] in1, in2, 
  output reg out                     
);

wire check;                 
assign check = (in1 == in2) ? 1'b 1 : 1'b 0; 

always@(posedge clk) begin  
  out <= check;            
end

endmodule


// Module for a binary counter with an optional stop signal.
module counter #(parameter length = 12)(
  input wire clk, ud, en, rst,   
  output wire [length-1:0] q,   
  output stop 
);

reg [length-1:0] cnt_reg;       

always @(posedge clk) begin    
  if (rst|stop)                
    cnt_reg <= {length{1'b0}};
  else if (en) begin           
    if (ud) begin
      cnt_reg <= cnt_reg + 1;  
    end
    else
      cnt_reg <= cnt_reg - 1;  
  end
end

assign q = cnt_reg;            
assign stop = cnt_reg[length-1] & cnt_reg[length-2]; 

endmodule


// Module for decoding a 4-bit input signal and generating a corresponding output signal.
module decoder #(parameter wlength=4)(
  input wire clk,            
  input wire [3:0] in,       
  output reg [wlength-1:0] out
);

reg [wlength-1:0] out_temp_reg;  
reg negate;                    

always@(posedge clk) begin      
  case(in[2:1])                 // Decode input signal based on values of bits 2 and 1.
    'd0: out_temp_reg <= {wlength/4{4'b0000}};  
    'd1: out_temp_reg <= {wlength/4{4'b0101}}; 
    'd2: out_temp_reg <= {wlength/4{4'b0011}};  
    default: out_temp_reg <= {wlength{1'bx}};   
  endcase
  negate <= in[3]~^in[0];      // Determine whether output should be negated based on values of bits 3 and 0.
  out <= negate ? ~out_temp_reg : out_temp_reg; // Assign negated or non-negated decoded value to output signal.
end

endmodule


//MUX
// The 'length' parameter sets the bit-width of the input and output ports
module mux #(parameter length=4)(
    input clk, 
    input sel, 
    input wire [length-1:0] in0, in1, 
    output reg [length-1:0] out 
);

// This is an always block triggered by the positive edge of the clock signal
always@(posedge clk) begin
  case(sel)
    'd0: out <= in0;
    'd1: out <= in1; 
    default: out <= {length{1'bx}}; 
  endcase
end

endmodule


module TOP #(parameter wcount=256, wlength=4)(
  input wire start, rst, clk, rwbarin, 
  input wire [wlength-1:0] datain, 
  input wire [$clog2(wcount)-1:0] address, 
  output wire [wlength-1:0] dataout,
  output reg fail 
);

//wire declarations:
wire tmode, ud, cnt_en, rwbar, rwbartest, stop;
wire [$clog2(wcount)-1:0] addrmem, addrtest; 
wire [$clog2(wcount)+3:0] count; 
wire [wlength-1:0] datamem, datatest, ramout; 
wire [3:0] decode_in; 

BIST_controller BIST_CTRL (
  .start(start),
  .rst(rst),
  .clk(clk),
  .stop(stop),
  .tmode(tmode)
);

reg [7:0] tmode_ppln;
always@(posedge clk) begin
  tmode_ppln[7:0] <= {tmode_ppln[6:0],tmode};
end

counter #(.length($clog2(wcount)+4)) CNT (
  .clk(clk),
  .ud(ud),
  .en(cnt_en),
  .rst(rst),
  .q(count),
  .stop(stop)
);

reg [6:0] rwbartest_ppln;
always@(posedge clk) begin
  rwbartest_ppln[6:0] <= {rwbartest_ppln[5:3],rwbar,rwbartest_ppln[1:0],rwbartest};
end

assign ud = 1'b1;
assign cnt_en = tmode & tmode_ppln[0];
assign rwbartest = (~count[$clog2(wcount)]) & (~stop);
assign rwbar = (~tmode_ppln[2]) ? rwbarin:rwbartest_ppln[2];
assign addrtest = count[$clog2(wcount)-1:0];
assign decode_in = {count[0],count[$clog2(wcount)+3:$clog2(wcount)+1]};

//Pipelining the test address signal
reg [$clog2(wcount)-1:0] addrtest_ppln0, addrtest_ppln1;
always@(posedge clk) begin
  addrtest_ppln0 <= addrtest;
  addrtest_ppln1 <= addrtest_ppln0;
end

decoder #(.wlength(wlength)) DECODE (
  .clk(clk),
  .in(decode_in),
  .out(datatest)
);

//MUX data and address to memory
mux #(.length(wlength)) DMUX (
  .clk(clk),
  .sel(tmode_ppln[2]),
  .in0(datain),
  .in1(datatest),
  .out(datamem)
);

mux #(.length($clog2(wcount))) AMUX (
  .clk(clk),
  .sel(tmode_ppln[2]),
  .in0(address),
  .in1(addrtest_ppln1),
  .out(addrmem)
);

//SRAM Instantiation:
single_port_ram #(.wcount(wcount),.wlength(wlength)) RAM_MEM (
  .datain(datamem),
  .addr(addrmem),
  .we(rwbar),
  .clk(clk),
  .dataout(ramout)
);

//Pipelining the SRAM output data
reg [wlength-1:0] ramout_ppln0;
always@(posedge clk) begin
  ramout_ppln0 <= ramout;
end


//Pipelining the test data
reg [wlength-1:0] datatest_ppln0, datatest_ppln1, datatest_ppln2, datatest_ppln3;
always@(posedge clk) begin
  datatest_ppln0 <= datatest;
  datatest_ppln1 <= datatest_ppln0;
  datatest_ppln2 <= datatest_ppln1;
  datatest_ppln3 <= datatest_ppln2;
end

//Comparator
comparator #(.wlength(wlength)) COMP (
  .clk(clk),
  .in1(datatest_ppln3),
  .in2(ramout_ppln0),
  .out(eq)
);

//Fail Variable Check:
always @(posedge clk) begin
  if (rst) fail <= 1'b0;
  else begin
    if (tmode_ppln[7] && ~rwbartest_ppln[6]) begin
      case(eq)
      'd1: fail <= 1'b0;
      default: fail <= 1'b1;
      endcase
    end
    else fail <= 1'b0;
  end
end

assign dataout = ramout;

endmodule


//SRAM:
module single_port_ram #(parameter wcount=256, wlength=4) (
  input wire [wlength-1:0] datain,
  input wire [$clog2(wcount)-1:0] addr,
  input wire we, clk,
  output reg [wlength-1:0] dataout
);

/* Declare the RAM variable - split into multiple RAMs */
reg [wlength-1:0] ram1[(wcount/8)-1:0];
reg [wlength-1:0] ram2[(wcount/8)-1:0];
reg [wlength-1:0] ram3[(wcount/8)-1:0];
reg [wlength-1:0] ram4[(wcount/8)-1:0];
reg [wlength-1:0] ram5[(wcount/8)-1:0];
reg [wlength-1:0] ram6[(wcount/8)-1:0];
reg [wlength-1:0] ram7[(wcount/8)-1:0];
reg [wlength-1:0] ram8[(wcount/8)-1:0];

/* Pipelining write address decode + Variable to hold the registered read address*/
reg [2:0] mem_sel, mem_sel_reg;
reg [$clog2(wcount)-4:0] mem_addr, mem_addr_reg;
reg [wlength-1:0] datain_reg, dataout_buffer1, dataout_buffer2, dataout_buffer3, dataout_buffer4, dataout_buffer5, dataout_buffer6, dataout_buffer7, dataout_buffer8;
reg we_reg;

always@(posedge clk) begin
  /*Write*/
  mem_sel <= addr[$clog2(wcount)-1:$clog2(wcount)-3];
  mem_addr <= addr[$clog2(wcount)-4:0];
  datain_reg <= datain;
  we_reg <= we;
  if (we_reg) begin
    case(mem_sel)
      'd0: ram1[mem_addr] <= datain_reg;
      'd1: ram2[mem_addr] <= datain_reg;
      'd2: ram3[mem_addr] <= datain_reg;
      'd3: ram4[mem_addr] <= datain_reg;
      'd4: ram5[mem_addr] <= datain_reg;
      'd5: ram6[mem_addr] <= datain_reg;
      'd6: ram7[mem_addr] <= datain_reg;
      'd7: ram8[mem_addr] <= datain_reg;
      default: ; //do nothing
    endcase
  end
  dataout_buffer1 <= ram1[mem_addr];
  dataout_buffer2 <= ram2[mem_addr];
  dataout_buffer3 <= ram3[mem_addr];
  dataout_buffer4 <= ram4[mem_addr];
  dataout_buffer5 <= ram5[mem_addr];
  dataout_buffer6 <= ram6[mem_addr];
  dataout_buffer7 <= ram7[mem_addr];
  dataout_buffer8 <= ram8[mem_addr];
  mem_sel_reg <= mem_sel;
  //mem_addr_reg <= mem_addr;
end

/* Continuous assignment implies read returns NEW datain.
This is the natural behavior of the TriMatrix memory blocks in Single Port mode*/
always@(*) begin
  case(mem_sel_reg)
    'd0: dataout = dataout_buffer1;
    'd1: dataout = dataout_buffer2;
    'd2: dataout = dataout_buffer3;
    'd3: dataout = dataout_buffer4;
    'd4: dataout = dataout_buffer5;
    'd5: dataout = dataout_buffer6;
    'd6: dataout = dataout_buffer7;
    'd7: dataout = dataout_buffer8;
    default: ; //do nothing
  endcase
end
endmodule
