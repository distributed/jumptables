// the jump table. at program startup it is zero filled and needs
// to be populated by jump table bootstrapping.
DATA ·jmptab+0(SB)/1, $0
GLOBL ·jmptab(SB), $(3*8)


// for the external semantics of decfunc, please refer to bootstrap.go

// first, the mode switch is loaded into AX. a zero value is used
// to request jump table bootstrapping, decfunc will continue at
// buildtable. a non-zero value request normal jump table operation.

// as a general convention, BX holds the second function argument:
// the index into the jump table. at the beginning of the function
// AX holds the mode switch argument, just before the exit of the
// function at retlab, AX is expected to contain the return value

// buildtable determines which table entry is to be bootstrapped
// and jumps to the label of the corresponding table entry.
// the instruction at the label is a CALL to getPC, getPC returns
// the address of the instruction after the CALL. this instruction
// will be the entry point reached from the jump table. in order
// to discern between jump table bootstrapping and normal jump
// table operation, getPC clears the Z flag so that the handler
// code can deflect control away from its body and towards
// buildtable_fixup. buildtable_fixup stores the address of the
// first instruction of the handler, which is now contained in AX
// into the jump table at the index contained in BX.

// normal jump table operation works as follows. the jump table
// address is loaded into CX, the jump table index is loaded
// into BX. the jump table entry is then loaded into CX and 
// the Z flag is cleared. the processor then jumps to the address
// contained in CX. execution continues at the first instruction
// of the handler, this is the second instruction after the label
// of the corresponding handler. it is a JNE which will not branch
// since the Z flag has been cleared beforehand and thus the 
// handlers body is executed.
TEXT ·decfunc(SB),7,$0
	MOVQ a+0(FP), AX

	// AX == 0 -> buildtable, AX != 0 -> normal operation
	ANDQ AX, AX
	JEQ buildtable
	
	// normal dispatch
	// load table address
	LEAQ ·jmptab+0(SB), CX
	// load offset into table
	MOVQ b+8(FP), BX
	// load jump table target
	MOVQ (CX)(BX*8), CX

	// clear Z for jump table target fallthrough
	XORQ AX, AX

	// jump to handler
	JMP CX


handler1_lab:
	// instrumentation instructions
	CALL ·getPC(SB)
	JNE buildtable_fixup

	// normal handler code
	MOVQ $0xdeadbeef00001111, AX
	JMP retlab

	
handler2_lab:
	// instrumentation instructions
	CALL ·getPC(SB)
	JNE buildtable_fixup

	// normal handler code
	MOVQ $0xdeadbeef22220000, AX
	JMP retlab
	

buildtable:
	MOVQ b+8(FP), BX

	CMPQ BX, $1
	JEQ handler1_lab

	CMPQ BX, $2
	JEQ handler2_lab

	// returns 0: no jump table bootstrapping performed
	// because no valid target was given
	MOVQ $0, AX
	JMP retlab


buildtable_fixup:
	// jump table address into CX
	LEAQ ·jmptab+0(SB), CX
	// the jump target is contained in AX and saved
	// into the jump table at the index contained in
	// BX.
	MOVQ AX, (CX)(BX*8)

	// as a side effect, the target address which was
	// just stored in the jump table is returned to the
	// caller
	JMP retlab


retlab:	
	MOVQ AX, r+16(FP)
	RET



// getPC is defined for use with a custom calling convention
// and not for use from a go program. the return address is
// stored in AX, the Z flag is cleared.
TEXT ·getPC(SB),7,$0
	MOVQ retpc+0(SP), AX
	
	// since the return address will not be $0, this instruction
	// clears the Z flag and thus enables deflection to the fixup
	// step
	ANDQ AX, AX
	
	RET
	