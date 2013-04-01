
DATA ·jmptab+0(SB)/1, $0
GLOBL ·jmptab(SB), $(3*8)

// for general notes see jumpchain.go.

// setting parameter a == 0 selects control flow through the jump chain.
// the jump chain starts with a preamble, a MOVL and an XORQ, to make it
// stand out in the instruction stream. after the preamble follow a number
// of JNE instructions targeting the handler labels, starting at the handler
// for b == 0, then b == 1 and so on. the JNE branches are not taken since
// the preceding XORQ AX, AX sets the Z flag. the JNE instructions merely serve
// as a medium to encode the addresses of the handler labels. the operand
// following the a JNE instruction contains the offset of the jump target
// of the branch target as measured from the instruction following the JNE.
// the function filljmptab in jumpchain.go uses the preamble to locate the
// jump chain in this function, then picks out the offsets from the JNE
// instructions and calculates the handler addresses and stores them in
// jmptab.
// when the linker detects that a part of the routine is not reachable at
// run time, it does not include said part in the final executable. this
// is why we need the runtime switch on parameter a. the linker does not
// not detect that we never call jumpchain with a == 0. this means that the
// jump chain will appear in the final executable. also, the linker does not
// detect that the JNE instructions in the jump chain never branch out since
// the Z flag was set with XORQ AX, AX. this means that the JNE
// instructions show up in the final executable. having some code after the
// last jump chain JNE prevents the linker from rewriting the last JNE into
// a JE with a fallthrough to the original JNE target. this is what i gathered
// from my experience - it is not based on reading the source code of the
// assembler or the linker and I suspect that the described behavior could
// change at any time.
TEXT ·jumpchain(SB),7,$0
	MOVQ a+0(FP), AX

	// a == 0: pass through jump chain
	// a != 0: use the jump table to dispatch on b
	CMPQ AX, $0
	JEQ chain

	// normal dispatch
	// load table address
	LEAQ ·jmptab+0(SB), CX
	// load offset into table
	MOVQ b+8(FP), BX
	// load label address
	MOVQ (CX)(BX*8), CX

	// go!
	JMP CX

retlab:
	MOVQ AX, r+16(FP)
	RET

nohandler:
	// return value -1 flags illegal handler
	MOVQ $-1, AX
	JMP retlab

handler1:
	MOVQ $42, AX
	JMP retlab

handler2:
	MOVQ $128, AX
	JMP retlab


chain:
	// preamble marking the position of the jump chain
	// its encoding has to match the bytes stored in the
	// variable jcpreamble in jumpchain.go.
	MOVL $0x6a786a63, AX
	XORQ AX, AX
	// Z flag is now set

	// the jump chain:
	JNE nohandler
	JNE handler1
	JNE handler2

	// set return value to 0
	MOVQ $0, AX
	JMP retlab

