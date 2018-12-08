module cpu(
  input clk,
  input sys_clk,
  input rst,
  output [9:0] LEDR,
  output [23:0] PCSEG
);

  // Program counter and instruction
  wire [31:0] pc2addr;
  wire [31:0] instr;
  wire [31:0] instr_sign_ex;

  // Signals
  wire        signal_data_mem_wren;
  wire        signal_reg_file_wren;
  wire        signal_reg_file_dmux_sel;
  wire        signal_reg_file_rmux_sel;
  wire        signal_alu_imux_sel;
  wire  [3:0] signal_alu_op;
  wire  [2:0] signal_pc_control;

  // Registers
  wire  [4:0] reg_waddr;
  wire  [4:0] reg_raddr0;
  wire  [4:0] reg_raddr1;
  wire [31:0] reg_rdata0;
  wire [31:0] reg_rdata1;
  wire [31:0] reg_wdata;
  
  // ALU
  wire [31:0] alu_src;
  wire [31:0] alu_dest;
  wire        alu_eflags_of;
  wire        alu_eflags_zf;

  // Data Memory
  wire [31:0] data_mem_paddr;
  wire [31:0] data_mem_rdata;
  
  // Debug Output
  assign LEDR = {
    signal_data_mem_wren, signal_reg_file_wren,
	 signal_reg_file_dmux_sel, signal_reg_file_rmux_sel,
	 signal_alu_imux_sel, signal_alu_op[3:0], (signal_pc_control != 0)
  };
  assign PCSEG = {reg_wdata[15:0], pc2addr[7:0]};

  //-------------------------------------
  // Instantiations
  //-------------------------------------
  program_counter mPC(
    .clk(clk),
    .rst(rst),
    .pc_control(signal_pc_control),
    .jmp_addr(instr[25:0]),
    .branch_offset(instr[15:0]),
    .reg_addr(reg_rdata0),
    .pc(pc2addr)
  );

  instr_memory mINSTRMEM(
    .addr(pc2addr),
    .instr(instr)
  );

  sign_ex mSIEX(
    .in(instr[15:0]),
    .out(instr_sign_ex)
  );

  decoder mDECODER(
    .instr(instr),
    .alu_zf(alu_eflags_zf),
    .data_mem_wren(signal_data_mem_wren),
    .reg_file_wren(signal_reg_file_wren),
    .reg_file_dmux_sel(signal_reg_file_dmux_sel),
    .reg_file_rmux_sel(signal_reg_file_rmux_sel),
    .alu_imux_sel(signal_alu_imux_sel),
    .alu_op(signal_alu_op),
    .pc_control(signal_pc_control)
  );

  assign reg_raddr0 = instr[25:21];
  assign reg_raddr1 = instr[20:16];

  // if R-mux signal is valid, use rd register;
  // otherwise, use rt register.
  mux21 #(.DATA_WIDTH(5)) mRegMUX(
    .in0(reg_raddr1),
    .in1(instr[15:11]),
    .sel(signal_reg_file_rmux_sel),
    .out(reg_waddr)
  );
  
  // if D-mux signal is valid, load result from ALU to register;
  // otherwise, load data_mem_rdata read from memory.
  mux21 mMEMMUX(
    .in0(data_mem_rdata),
	 .in1(alu_dest),
	 .sel(signal_reg_file_dmux_sel),
	 .out(reg_wdata)
  );
  
  // if I-mux signal is valid, use the sign extended immediate from instruction;
  // otherwise, use rt register for second operand.
  mux21 mIMMMUX(
    .in0(reg_rdata1),
	 .in1(instr_sign_ex),
	 .sel(signal_alu_imux_sel),
	 .out(alu_src)
  );
  
  // read/write from registers.
  register_file mREG(
    .clk(clk),
	 .raddr0(reg_raddr0),
    .rdata0(reg_rdata0),
    .raddr1(reg_raddr1),
    .rdata1(reg_rdata1),
    .waddr(reg_waddr),
    .wdata(reg_wdata),
    .wren(signal_reg_file_wren)
  );
  
  // ALU module
  alu mALU(
    .op(signal_alu_op),
    .rs(reg_rdata0),
    .rt(alu_src),
    .rd(alu_dest),
    .zf(alu_eflags_zf),
    .of(alu_eflags_of)
  );
  
  // All data address begins from 0x10000000 to fit MARS.
  assign data_mem_paddr = alu_dest - 8'h10000000;
  data_memory mMEM(
	 .address(data_mem_paddr), // Rs + offset
	 .clock(sys_clk),          // use system clock for RAM
	 .data(reg_rdata1),        // Rt
	 .wren(signal_data_mem_wren),
	 .q(data_mem_rdata)
  );
endmodule
