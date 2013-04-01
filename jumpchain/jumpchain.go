package main

import (
	"bytes"
	"errors"
	"fmt"
	"log"
	"reflect"
	"unsafe"
)

// jumpchain is a function which dispatches on its parameter b with the
// help of a jump table. calling jumpchain with a != 0 selects normal
// operation, calling it with a == 0 does nothing but have the function
// return 0. the a == 0 path is present to prevent the linker from not
// emitting code for the jump chain.
func jumpchain(a uint64, b uint64) uint64

var jmptab [3]uintptr

// main contains a demo of how to fill and use a jump table created
// through a jump chain. the handlers should return uint64(-1), 42 and
// 128, respectively.
func main() {
	faddr := reflect.ValueOf(jumpchain).Pointer()
	numtargets := 3

	err := filljmptab(faddr, numtargets)
	if err != nil {
		log.Fatal(err)
	}

	for i := 0; i < numtargets; i++ {
		fmt.Printf("calling handler %d	: ", i)
		ret := jumpchain(1, uint64(i))
		fmt.Printf("%#016x\n", ret)
	}
}

// jcpreamble contains encodings of the instructions leading up to the
// jump chain. it is presented in GDB notation.
var jcpreamble []byte = []byte{0xb8, 0x63, 0x6a, 0x78, 0x6a, //mov    $0x6a786a63,%eax
	0x48, 0x31, 0xc0, // xor %rax, %rax
}

// filljmptab fills the jump table corresponding to the instruction stream
// pointed to by faddr. it finds the jump chain by searching the instruction
// stream for the preamble contained in jcpreamble. if there's no preamble,
// it might run into "forbidden" memory. after the preamble it expects
// a jump chain built with JNE instructions. it disassembles both the
// 8 bit (opcode 75) and the 32 bit (opcode 0f 85) variants, picks out
// the relative offset and calculates the absolute position of the handler.
// the handler addresses are stored in jmptab.
// for instruction encodings, please refer to the "AMD64 Architecture
// Programmer's Manual, Volume 3", "Jcc - Jump on Condition".
func filljmptab(faddr uintptr, numtargets int) error {
	mw := newmemWindow(faddr)

	// find the preamble in the instruction stream. quit if not found afer
	// 64kbytes
	pos := 0
	msl := (1 << 16)
	for pos < msl {
		if bytes.Equal(jcpreamble, mw.getWindow(len(jcpreamble))) {
			fmt.Printf("found jump chain preamble at offset %#04x\n", pos)
			break
		}

		pos++
		mw.moveWindow(1)
	}

	if pos == msl {
		return errors.New("did not find jump chain preamble")
	}

	mw.moveWindow(len(jcpreamble))

	// now mw points to the beginning of the jump chain. the following loop
	// disassembles a total of numtargets instructions.
	for i := 0; i < numtargets; i++ {
		opc0 := mw.getWindow(1)[0]
		if opc0 == 0x75 {
			// rel8off

			mw.moveWindow(1)
			var offs int = int(int8(mw.getWindow(1)[0]))
			mw.moveWindow(1)

			abs := mw.p + uintptr(offs)

			fmt.Printf("handler idx %d  8 bit joffset  % 3d  abs %#08x  (JNE @ fn+%#04x)\n", i, offs, abs, mw.p-2-faddr)
			jmptab[i] = abs
		} else if opc0 == 0x0f {
			// rel32off

			mw.moveWindow(1)
			opcext := mw.getWindow(1)[0]
			if opcext != 0x85 {
				return fmt.Errorf("error: unknown opcode %02x %02x\n", opc0, opcext)
			}

			mw.moveWindow(1)
			memoffs := mw.getWindow(4)
			var offs int = 0
			offs |= int(uint8(memoffs[0])) << 0
			offs |= int(uint8(memoffs[1])) << 8
			offs |= int(uint8(memoffs[2])) << 8
			offs |= int(int8(memoffs[3])) << 8
			mw.moveWindow(4)

			abs := mw.p + uintptr(offs)

			fmt.Printf("handler idx %d 32 bit joffset % 3d  abs %#08x  (JNE @ fn+%#04x)\n", i, offs, abs, mw.p-6-faddr)
			jmptab[i] = abs
		} else {
			return fmt.Errorf("error: unknown opcode starting with %02x\n", mw.getWindow(1)[0])
		}
	}

	return nil
}

// helper type for peeking into the instruction stream.
type memWindow struct {
	p uintptr
}

func newmemWindow(p uintptr) *memWindow {
	mr := &memWindow{p}
	return mr
}

func (m *memWindow) getWindow(length int) []byte {
	var sh reflect.SliceHeader
	sh.Data = m.p
	sh.Len = length
	sh.Cap = length
	return *((*[]byte)(unsafe.Pointer(&sh)))
}

func (m *memWindow) moveWindow(offs int) {
	m.p += uintptr(offs)
}
