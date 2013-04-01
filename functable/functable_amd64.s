// the function table functab is declared in functable.go

// callfunc is the dispatcher function. it figures out the handler address
// corresponding to the index b, call the handler with one parameter, a,
// collects the return value of the handler and returns it to the caller.
TEXT ·callfunc(SB),7,$16
	// load table address
	LEAQ ·functab+0(SB), CX
	// load offset into table
	MOVQ b+8(FP), BX
	// load label address
	MOVQ (CX)(BX*8), CX

	// we have got 16 bytes of stack at (SP). we use this space for the
	// arguments and the return value of the handler function.

	// move a to the callee stack frame
	MOVQ a+0(FP), BX
	MOVQ BX, 0(SP)

	// call handler
	CALL CX

	// transfer return value
	MOVQ 8(SP), BX
	MOVQ BX, r+16(FP)

	RET


TEXT ·handler1(SB),7,$0
	MOVL $0xcafe1100, AX
	ADDQ a+0(FP), AX
	MOVQ AX, r+8(FP)
	RET	

TEXT ·handler2(SB),7,$0
	MOVL $0xcafe2222, AX
	MOVQ AX, r+8(FP)
	RET
