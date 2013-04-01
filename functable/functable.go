package main

import (
	"fmt"
	"reflect"
)

// callfunc is the dispatcher function.
// a is the parameter passed to the handler, b selects which handler to call.
func callfunc(a uint64, b uint64) uint64

// returns 0xcafe1100 + a
func handler1(a uint64) uint64

// returns 0xcafe2222
func handler2(a uint64) uint64

// functab is the function table used by callfunc. its entries are the
// addresses of the first instructions of the handler function, or 0
// if no handler is defined.
var functab [3]uintptr = [3]uintptr{0,
	reflect.ValueOf(handler1).Pointer(),
	reflect.ValueOf(handler2).Pointer()}

func main() {
	fmt.Printf("1: %#08x\n", callfunc(0x11, 0x1))
	fmt.Printf("2: %#08x\n", callfunc(0x00, 0x2))
}
