//===-- SystemZOperands.td - SystemZ instruction operands ----*- tblgen-*--===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
// Class definitions
//===----------------------------------------------------------------------===//

class ImmediateAsmOperand<string name>
  : AsmOperandClass {
  let Name = name;
  let RenderMethod = "addImmOperands";
}

// Constructs both a DAG pattern and instruction operand for an immediate
// of type VT.  PRED returns true if a node is acceptable and XFORM returns
// the operand value associated with the node.  ASMOP is the name of the
// associated asm operand, and also forms the basis of the asm print method.
class Immediate<ValueType vt, code pred, SDNodeXForm xform, string asmop>
  : PatLeaf<(vt imm), pred, xform>, Operand<vt> {
  let PrintMethod = "print"##asmop##"Operand";
  let DecoderMethod = "decode"##asmop##"Operand";
  let ParserMatchClass = !cast<AsmOperandClass>(asmop);
}

// Constructs an asm operand for a PC-relative address.  SIZE says how
// many bits there are.
class PCRelAsmOperand<string size> : ImmediateAsmOperand<"PCRel"##size> {
  let PredicateMethod = "isImm";
  let ParserMethod = "parsePCRel"##size;
}

// Constructs an operand for a PC-relative address with address type VT.
// ASMOP is the associated asm operand.
class PCRelOperand<ValueType vt, AsmOperandClass asmop> : Operand<vt> {
  let PrintMethod = "printPCRelOperand";
  let ParserMatchClass = asmop;
}

// Constructs both a DAG pattern and instruction operand for a PC-relative
// address with address size VT.  SELF is the name of the operand and
// ASMOP is the associated asm operand.
class PCRelAddress<ValueType vt, string self, AsmOperandClass asmop>
  : ComplexPattern<vt, 1, "selectPCRelAddress", [z_pcrel_wrapper]>,
    PCRelOperand<vt, asmop> {
  let MIOperandInfo = (ops !cast<Operand>(self));
}

// Constructs an AsmOperandClass for addressing mode FORMAT, treating the
// registers as having BITSIZE bits and displacements as having DISPSIZE bits.
// LENGTH is "LenN" for addresses with an N-bit length field, otherwise it
// is "".
class AddressAsmOperand<string format, string bitsize, string dispsize,
                        string length = "">
  : AsmOperandClass {
  let Name = format##bitsize##"Disp"##dispsize##length;
  let ParserMethod = "parse"##format##bitsize;
  let RenderMethod = "add"##format##"Operands";
}

// Constructs both a DAG pattern and instruction operand for an addressing mode.
// FORMAT, BITSIZE, DISPSIZE and LENGTH are the parameters to an associated
// AddressAsmOperand.  OPERANDS is a list of NUMOPS individual operands
// (base register, displacement, etc.).  SELTYPE is the type of the memory
// operand for selection purposes; sometimes we want different selection
// choices for the same underlying addressing mode.  SUFFIX is similarly
// a suffix appended to the displacement for selection purposes;
// e.g. we want to reject small 20-bit displacements if a 12-bit form
// also exists, but we want to accept them otherwise.
class AddressingMode<string seltype, string bitsize, string dispsize,
                     string suffix, string length, int numops, string format,
                     dag operands>
  : ComplexPattern<!cast<ValueType>("i"##bitsize), numops,
                   "select"##seltype##dispsize##suffix##length,
                   [add, sub, or, frameindex, z_adjdynalloc]>,
    Operand<!cast<ValueType>("i"##bitsize)> {
  let PrintMethod = "print"##format##"Operand";
  let EncoderMethod = "get"##format##dispsize##length##"Encoding";
  let DecoderMethod =
    "decode"##format##bitsize##"Disp"##dispsize##length##"Operand";
  let MIOperandInfo = operands;
  let ParserMatchClass =
    !cast<AddressAsmOperand>(format##bitsize##"Disp"##dispsize##length);
}

// An addressing mode with a base and displacement but no index.
class BDMode<string type, string bitsize, string dispsize, string suffix>
  : AddressingMode<type, bitsize, dispsize, suffix, "", 2, "BDAddr",
                   (ops !cast<RegisterOperand>("ADDR"##bitsize),
                        !cast<Immediate>("disp"##dispsize##"imm"##bitsize))>;

// An addressing mode with a base, displacement and index.
class BDXMode<string type, string bitsize, string dispsize, string suffix>
  : AddressingMode<type, bitsize, dispsize, suffix, "", 3, "BDXAddr",
                   (ops !cast<RegisterOperand>("ADDR"##bitsize),
                        !cast<Immediate>("disp"##dispsize##"imm"##bitsize),
                        !cast<RegisterOperand>("ADDR"##bitsize))>;

// A BDMode paired with an immediate length operand of LENSIZE bits.
class BDLMode<string type, string bitsize, string dispsize, string suffix,
              string lensize>
  : AddressingMode<type, bitsize, dispsize, suffix, "Len"##lensize, 3,
                   "BDLAddr",
                   (ops !cast<RegisterOperand>("ADDR"##bitsize),
                        !cast<Immediate>("disp"##dispsize##"imm"##bitsize),
                        !cast<Immediate>("imm"##bitsize))>;

//===----------------------------------------------------------------------===//
// Extracting immediate operands from nodes
// These all create MVT::i64 nodes to ensure the value is not sign-extended
// when converted from an SDNode to a MachineOperand later on.
//===----------------------------------------------------------------------===//

// Bits 0-15 (counting from the lsb).
def LL16 : SDNodeXForm<imm, [{
  uint64_t Value = N->getZExtValue() & 0x000000000000FFFFULL;
  return CurDAG->getTargetConstant(Value, MVT::i64);
}]>;

// Bits 16-31 (counting from the lsb).
def LH16 : SDNodeXForm<imm, [{
  uint64_t Value = (N->getZExtValue() & 0x00000000FFFF0000ULL) >> 16;
  return CurDAG->getTargetConstant(Value, MVT::i64);
}]>;

// Bits 32-47 (counting from the lsb).
def HL16 : SDNodeXForm<imm, [{
  uint64_t Value = (N->getZExtValue() & 0x0000FFFF00000000ULL) >> 32;
  return CurDAG->getTargetConstant(Value, MVT::i64);
}]>;

// Bits 48-63 (counting from the lsb).
def HH16 : SDNodeXForm<imm, [{
  uint64_t Value = (N->getZExtValue() & 0xFFFF000000000000ULL) >> 48;
  return CurDAG->getTargetConstant(Value, MVT::i64);
}]>;

// Low 32 bits.
def LF32 : SDNodeXForm<imm, [{
  uint64_t Value = N->getZExtValue() & 0x00000000FFFFFFFFULL;
  return CurDAG->getTargetConstant(Value, MVT::i64);
}]>;

// High 32 bits.
def HF32 : SDNodeXForm<imm, [{
  uint64_t Value = N->getZExtValue() >> 32;
  return CurDAG->getTargetConstant(Value, MVT::i64);
}]>;

// Truncate an immediate to a 8-bit signed quantity.
def SIMM8 : SDNodeXForm<imm, [{
  return CurDAG->getTargetConstant(int8_t(N->getZExtValue()), MVT::i64);
}]>;

// Truncate an immediate to a 8-bit unsigned quantity.
def UIMM8 : SDNodeXForm<imm, [{
  return CurDAG->getTargetConstant(uint8_t(N->getZExtValue()), MVT::i64);
}]>;

// Truncate an immediate to a 16-bit signed quantity.
def SIMM16 : SDNodeXForm<imm, [{
  return CurDAG->getTargetConstant(int16_t(N->getZExtValue()), MVT::i64);
}]>;

// Truncate an immediate to a 16-bit unsigned quantity.
def UIMM16 : SDNodeXForm<imm, [{
  return CurDAG->getTargetConstant(uint16_t(N->getZExtValue()), MVT::i64);
}]>;

// Truncate an immediate to a 32-bit signed quantity.
def SIMM32 : SDNodeXForm<imm, [{
  return CurDAG->getTargetConstant(int32_t(N->getZExtValue()), MVT::i64);
}]>;

// Truncate an immediate to a 32-bit unsigned quantity.
def UIMM32 : SDNodeXForm<imm, [{
  return CurDAG->getTargetConstant(uint32_t(N->getZExtValue()), MVT::i64);
}]>;

// Negate and then truncate an immediate to a 32-bit unsigned quantity.
def NEGIMM32 : SDNodeXForm<imm, [{
  return CurDAG->getTargetConstant(uint32_t(-N->getZExtValue()), MVT::i64);
}]>;

//===----------------------------------------------------------------------===//
// Immediate asm operands.
//===----------------------------------------------------------------------===//

def U4Imm  : ImmediateAsmOperand<"U4Imm">;
def U6Imm  : ImmediateAsmOperand<"U6Imm">;
def S8Imm  : ImmediateAsmOperand<"S8Imm">;
def U8Imm  : ImmediateAsmOperand<"U8Imm">;
def S16Imm : ImmediateAsmOperand<"S16Imm">;
def U16Imm : ImmediateAsmOperand<"U16Imm">;
def S32Imm : ImmediateAsmOperand<"S32Imm">;
def U32Imm : ImmediateAsmOperand<"U32Imm">;

//===----------------------------------------------------------------------===//
// 8-bit immediates
//===----------------------------------------------------------------------===//

def uimm8zx4 : Immediate<i8, [{
  return isUInt<4>(N->getZExtValue());
}], NOOP_SDNodeXForm, "U4Imm">;

def uimm8zx6 : Immediate<i8, [{
  return isUInt<6>(N->getZExtValue());
}], NOOP_SDNodeXForm, "U6Imm">;

def simm8    : Immediate<i8, [{}], SIMM8, "S8Imm">;
def uimm8    : Immediate<i8, [{}], UIMM8, "U8Imm">;

//===----------------------------------------------------------------------===//
// i32 immediates
//===----------------------------------------------------------------------===//

// Immediates for the lower and upper 16 bits of an i32, with the other
// bits of the i32 being zero.
def imm32ll16 : Immediate<i32, [{
  return SystemZ::isImmLL(N->getZExtValue());
}], LL16, "U16Imm">;

def imm32lh16 : Immediate<i32, [{
  return SystemZ::isImmLH(N->getZExtValue());
}], LH16, "U16Imm">;

// Immediates for the lower and upper 16 bits of an i32, with the other
// bits of the i32 being one.
def imm32ll16c : Immediate<i32, [{
  return SystemZ::isImmLL(uint32_t(~N->getZExtValue()));
}], LL16, "U16Imm">;

def imm32lh16c : Immediate<i32, [{
  return SystemZ::isImmLH(uint32_t(~N->getZExtValue()));
}], LH16, "U16Imm">;

// Short immediates
def imm32sx8 : Immediate<i32, [{
  return isInt<8>(N->getSExtValue());
}], SIMM8, "S8Imm">;

def imm32zx8 : Immediate<i32, [{
  return isUInt<8>(N->getZExtValue());
}], UIMM8, "U8Imm">;

def imm32zx8trunc : Immediate<i32, [{}], UIMM8, "U8Imm">;

def imm32sx16 : Immediate<i32, [{
  return isInt<16>(N->getSExtValue());
}], SIMM16, "S16Imm">;

def imm32zx16 : Immediate<i32, [{
  return isUInt<16>(N->getZExtValue());
}], UIMM16, "U16Imm">;

def imm32sx16trunc : Immediate<i32, [{}], SIMM16, "S16Imm">;

// Full 32-bit immediates.  we need both signed and unsigned versions
// because the assembler is picky.  E.g. AFI requires signed operands
// while NILF requires unsigned ones.
def simm32 : Immediate<i32, [{}], SIMM32, "S32Imm">;
def uimm32 : Immediate<i32, [{}], UIMM32, "U32Imm">;

def imm32 : ImmLeaf<i32, [{}]>;

//===----------------------------------------------------------------------===//
// 64-bit immediates
//===----------------------------------------------------------------------===//

// Immediates for 16-bit chunks of an i64, with the other bits of the
// i32 being zero.
def imm64ll16 : Immediate<i64, [{
  return SystemZ::isImmLL(N->getZExtValue());
}], LL16, "U16Imm">;

def imm64lh16 : Immediate<i64, [{
  return SystemZ::isImmLH(N->getZExtValue());
}], LH16, "U16Imm">;

def imm64hl16 : Immediate<i64, [{
  return SystemZ::isImmHL(N->getZExtValue());
}], HL16, "U16Imm">;

def imm64hh16 : Immediate<i64, [{
  return SystemZ::isImmHH(N->getZExtValue());
}], HH16, "U16Imm">;

// Immediates for 16-bit chunks of an i64, with the other bits of the
// i32 being one.
def imm64ll16c : Immediate<i64, [{
  return SystemZ::isImmLL(uint64_t(~N->getZExtValue()));
}], LL16, "U16Imm">;

def imm64lh16c : Immediate<i64, [{
  return SystemZ::isImmLH(uint64_t(~N->getZExtValue()));
}], LH16, "U16Imm">;

def imm64hl16c : Immediate<i64, [{
  return SystemZ::isImmHL(uint64_t(~N->getZExtValue()));
}], HL16, "U16Imm">;

def imm64hh16c : Immediate<i64, [{
  return SystemZ::isImmHH(uint64_t(~N->getZExtValue()));
}], HH16, "U16Imm">;

// Immediates for the lower and upper 32 bits of an i64, with the other
// bits of the i32 being zero.
def imm64lf32 : Immediate<i64, [{
  return SystemZ::isImmLF(N->getZExtValue());
}], LF32, "U32Imm">;

def imm64hf32 : Immediate<i64, [{
  return SystemZ::isImmHF(N->getZExtValue());
}], HF32, "U32Imm">;

// Immediates for the lower and upper 32 bits of an i64, with the other
// bits of the i32 being one.
def imm64lf32c : Immediate<i64, [{
  return SystemZ::isImmLF(uint64_t(~N->getZExtValue()));
}], LF32, "U32Imm">;

def imm64hf32c : Immediate<i64, [{
  return SystemZ::isImmHF(uint64_t(~N->getZExtValue()));
}], HF32, "U32Imm">;

// Short immediates.
def imm64sx8 : Immediate<i64, [{
  return isInt<8>(N->getSExtValue());
}], SIMM8, "S8Imm">;

def imm64zx8 : Immediate<i64, [{
  return isUInt<8>(N->getSExtValue());
}], UIMM8, "U8Imm">;

def imm64sx16 : Immediate<i64, [{
  return isInt<16>(N->getSExtValue());
}], SIMM16, "S16Imm">;

def imm64zx16 : Immediate<i64, [{
  return isUInt<16>(N->getZExtValue());
}], UIMM16, "U16Imm">;

def imm64sx32 : Immediate<i64, [{
  return isInt<32>(N->getSExtValue());
}], SIMM32, "S32Imm">;

def imm64zx32 : Immediate<i64, [{
  return isUInt<32>(N->getZExtValue());
}], UIMM32, "U32Imm">;

def imm64zx32n : Immediate<i64, [{
  return isUInt<32>(-N->getSExtValue());
}], NEGIMM32, "U32Imm">;

def imm64 : ImmLeaf<i64, [{}]>, Operand<i64>;

//===----------------------------------------------------------------------===//
// Floating-point immediates
//===----------------------------------------------------------------------===//

// Floating-point zero.
def fpimm0 : PatLeaf<(fpimm), [{ return N->isExactlyValue(+0.0); }]>;

// Floating point negative zero.
def fpimmneg0 : PatLeaf<(fpimm), [{ return N->isExactlyValue(-0.0); }]>;

//===----------------------------------------------------------------------===//
// Symbolic address operands
//===----------------------------------------------------------------------===//

// PC-relative asm operands.
def PCRel16 : PCRelAsmOperand<"16">;
def PCRel32 : PCRelAsmOperand<"32">;

// PC-relative offsets of a basic block.  The offset is sign-extended
// and multiplied by 2.
def brtarget16 : PCRelOperand<OtherVT, PCRel16> {
  let EncoderMethod = "getPC16DBLEncoding";
  let DecoderMethod = "decodePC16DBLOperand";
}
def brtarget32 : PCRelOperand<OtherVT, PCRel32> {
  let EncoderMethod = "getPC32DBLEncoding";
  let DecoderMethod = "decodePC32DBLOperand";
}

// A PC-relative offset of a global value.  The offset is sign-extended
// and multiplied by 2.
def pcrel32 : PCRelAddress<i64, "pcrel32", PCRel32> {
  let EncoderMethod = "getPC32DBLEncoding";
  let DecoderMethod = "decodePC32DBLOperand";
}

// A PC-relative offset of a global value when the value is used as a
// call target.  The offset is sign-extended and multiplied by 2.
def pcrel16call : PCRelAddress<i64, "pcrel16call", PCRel16> {
  let PrintMethod = "printCallOperand";
  let EncoderMethod = "getPLT16DBLEncoding";
  let DecoderMethod = "decodePC16DBLOperand";
}
def pcrel32call : PCRelAddress<i64, "pcrel32call", PCRel32> {
  let PrintMethod = "printCallOperand";
  let EncoderMethod = "getPLT32DBLEncoding";
  let DecoderMethod = "decodePC32DBLOperand";
}

//===----------------------------------------------------------------------===//
// Addressing modes
//===----------------------------------------------------------------------===//

// 12-bit displacement operands.
def disp12imm32 : Operand<i32>;
def disp12imm64 : Operand<i64>;

// 20-bit displacement operands.
def disp20imm32 : Operand<i32>;
def disp20imm64 : Operand<i64>;

def BDAddr32Disp12      : AddressAsmOperand<"BDAddr",   "32", "12">;
def BDAddr32Disp20      : AddressAsmOperand<"BDAddr",   "32", "20">;
def BDAddr64Disp12      : AddressAsmOperand<"BDAddr",   "64", "12">;
def BDAddr64Disp20      : AddressAsmOperand<"BDAddr",   "64", "20">;
def BDXAddr64Disp12     : AddressAsmOperand<"BDXAddr",  "64", "12">;
def BDXAddr64Disp20     : AddressAsmOperand<"BDXAddr",  "64", "20">;
def BDLAddr64Disp12Len8 : AddressAsmOperand<"BDLAddr",  "64", "12", "Len8">;

// DAG patterns and operands for addressing modes.  Each mode has
// the form <type><range><group>[<len>] where:
//
// <type> is one of:
//   shift    : base + displacement (32-bit)
//   bdaddr   : base + displacement
//   mviaddr  : like bdaddr, but reject cases with a natural index
//   bdxaddr  : base + displacement + index
//   laaddr   : like bdxaddr, but used for Load Address operations
//   dynalloc : base + displacement + index + ADJDYNALLOC
//   bdladdr  : base + displacement with a length field
//
// <range> is one of:
//   12       : the displacement is an unsigned 12-bit value
//   20       : the displacement is a signed 20-bit value
//
// <group> is one of:
//   pair     : used when there is an equivalent instruction with the opposite
//              range value (12 or 20)
//   only     : used when there is no equivalent instruction with the opposite
//              range value
//
// <len> is one of:
//
//   <empty>  : there is no length field
//   len8     : the length field is 8 bits, with a range of [1, 0x100].
def shift12only       : BDMode <"BDAddr",   "32", "12", "Only">;
def shift20only       : BDMode <"BDAddr",   "32", "20", "Only">;
def bdaddr12only      : BDMode <"BDAddr",   "64", "12", "Only">;
def bdaddr12pair      : BDMode <"BDAddr",   "64", "12", "Pair">;
def bdaddr20only      : BDMode <"BDAddr",   "64", "20", "Only">;
def bdaddr20pair      : BDMode <"BDAddr",   "64", "20", "Pair">;
def mviaddr12pair     : BDMode <"MVIAddr",  "64", "12", "Pair">;
def mviaddr20pair     : BDMode <"MVIAddr",  "64", "20", "Pair">;
def bdxaddr12only     : BDXMode<"BDXAddr",  "64", "12", "Only">;
def bdxaddr12pair     : BDXMode<"BDXAddr",  "64", "12", "Pair">;
def bdxaddr20only     : BDXMode<"BDXAddr",  "64", "20", "Only">;
def bdxaddr20only128  : BDXMode<"BDXAddr",  "64", "20", "Only128">;
def bdxaddr20pair     : BDXMode<"BDXAddr",  "64", "20", "Pair">;
def dynalloc12only    : BDXMode<"DynAlloc", "64", "12", "Only">;
def laaddr12pair      : BDXMode<"LAAddr",   "64", "12", "Pair">;
def laaddr20pair      : BDXMode<"LAAddr",   "64", "20", "Pair">;
def bdladdr12onlylen8 : BDLMode<"BDLAddr",  "64", "12", "Only", "8">;

//===----------------------------------------------------------------------===//
// Miscellaneous
//===----------------------------------------------------------------------===//

// Access registers.  At present we just use them for accessing the thread
// pointer, so we don't expose them as register to LLVM.
def AccessReg : AsmOperandClass {
  let Name = "AccessReg";
  let ParserMethod = "parseAccessReg";
}
def access_reg : Immediate<i8, [{ return N->getZExtValue() < 16; }],
                           NOOP_SDNodeXForm, "AccessReg"> {
  let ParserMatchClass = AccessReg;
}

// A 4-bit condition-code mask.
def cond4 : PatLeaf<(i8 imm), [{ return (N->getZExtValue() < 16); }]>,
            Operand<i8> {
  let PrintMethod = "printCond4Operand";
}
