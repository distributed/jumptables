package main

import (
	"fmt"
)

// the jump table used by the function written in assembler. it is
// uninitialized at program startup.
var jmptab [3]uintptr

// decfunc is a function which can both use and bootstrap its own jump
// table. a is a mode switch, b selects the handler. a == 0 selects table
// bootstrapping, b selects which handler is bootstrapped. every call with
// a == 0 initializes only one handler address in the jump table. a != 0
// selects normal jump table operation, the handler specified by b is
// executed. see bootstrap_amd64.s for details.
func decfunc(a uint64, b uint64) uint64

// main will print
// 1: rinit ..., rres 0xdeadbeef00001111
// 2: rinit ..., rres 0xdeadbeef22220000
// where the ... are the handler addresses stored in the jump table. they
// will vary.
func main() {
	for i := uint64(1); i < 3; i++ {
		// init handler i
		rinit := decfunc(0, i)

		// call handler i
		rres := decfunc(1, i)

		fmt.Printf("%d: rinit %#016x, rres %#016x\n", i, rinit, rres)
	}
}
