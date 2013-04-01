Jump Tables for Fun and Profit
==============================

Recently I became interested in using jump tables in an assembler implementation of my 6502 instruction set
simulator. I ran into trouble while trying to set up jump tables and inquired on the Go Nuts mailing list:
https://groups.google.com/d/msg/golang-nuts/6M0BLgrKBRk/TnxtMuFmk30J

The TL;DR is that with 6a "there is no way to emit a data reference to a specific instruction within a function".

In the days following my post I came up with three approaches to avoid the abovementioned limitation. I will present
them below, complete with examples for the amd64 architecture. I'm convinced that they are easy to port
to other architectures.

### Terminology

It is my goal to write a dispatcher function and a number of handlers. Depending on some input, the dispatcher
function decides which handler is responsible and invokes said handler. The dispatcher is said to dispatch to
the handler function. In the examples, the abovementioned input is provided by the second parameter to the
dispatcher, ```b uint64```. There will typically be two different handlers, labeled something along the lines
of ```handler1``` and ```handler2```.


Level 0: Function tables
------------------------

The source is in ```functable/{functable.go|functable_amd64.go}```.

### Overview

This is the most straightforward way to create a fast dispatch. Each handler is put
in a function of its own. As I only use the functions from within ```callfunc```, the handlers
do not follow the normal Go stack based calling convention, but use a custom convention.

The function table ```functab```, of type ```[3]uintptr```, is initialized to contain the entry
addresses of the handler functions.

The assembler function ```callfunc```, of type ```func(a, b uint64) uint64```, loads ```functab[b]``` and
calls the function at the specified address.

#### Critique

The function table approach does use negligible amounts of magic, is simple and easily understood.
Apart from indexing the function table, dispatch to a handler function costs a ```CALL``` and a ```RET```.
The function table is equivalent to what you would do with a ```[]func(uint64)uint64```table in straight Go.


Level 1: Jump Table Bootstrapping
---------------------------------

The source is in ```bootstrap/{bootstrap.go|bootstrap_amd64.go}```.

### Overview

Jump table operation is confined to the function ```decfunc```. All handlers which are reachable through
the jump table are located at labels within decfunc. 

The jump table ```jmptab``` is not populated at program startup. This is because we cannot take a reference
to a label in the assembler source code at compile time. This limitation is avoided by having ```decfunc```
itself fill, or bootstrap, its jump table. To this end, every handler contains 2 instructions
of instrumentation code. First, a ```CALL``` to the helper function ```getPC``` places the address of the instruction
right after the ```CALL``` in ```AX```. Second, a ```JNE``` may branch away to the label ```buildtable_fixup```. The ```JNE``` is used
for the handler to distinguish between normal or bootstrapping operation. During bootstrapping, the Z
flag is cleared, resulting in the ```JNE``` branching, or deflecting, to ```buildtable_fixup```. During normal
operation, the Z flag is cleared which means execution falls through the ```JNE``` to normal handler code.
The code starting at ```buildtable_fixup``` places the address of the instruction after the ```CALL```, the address
of the ```JNE```, into the jump table at the desired index, stored in ```BX```. This is an interesting
situation. We need the ```JNE``` - because it's there. After the ```CALL``` to ```getPC```, which is needed to find the an address
after the handler label during bootstrapping, we don't want to execute normal handler code. This is why we have
a branch after the ```CALL```. Also, since this instruction is the one reachable through the jump table
we also need to be able to fall through it, in order to reach normal handler code. This[1] makes it necessary
to put a conditional branch after the ```CALL```.

```decfunc``` can be called in two ways: ```decfunc(0, i)``` bootstraps the table entry for handler ```i```, whereas
```decfunc(1, i)``` dispatches to handler ```i```. When the first argument is 0, decfunc jumps to the label
of the handler selected by its second parameter. This transfers control to the 2 bootstrapping instructions
described above. When the first argument is not 0, ```decfunc``` retrieves ```jmptab[i]```, sets the Z
flag and transfers control to the address stored in ```jmptab[i]```. This jumps to the ```JNE``` of
the instrumentation code of handler ```i```. Since Z is set, execution falls through to normal handler code.

#### Critique

Now this is much more interesting! The code is nowhere as simple or easily understood as the function
table approach. It also includes more code. 

In contrast to the function table approach, jump table
bootstrapping only uses a ```JMP```, not a ```CALL``` to dispatch to the handler. There are two conditional
branches for every handler invocation: a ```JEQ``` to select whether to perform jump table bootstrapping or
normal dispatch and a ```JNE``` for the handler to decide whether to perform bootstrapping or normal
operation. Branch prediction certainly helps in the case of the ```JEQ```/```JNE```.

The ```JNE``` in the instrumentation can be skipped by adjusting the jump targets in ```jmptab``` after
bootstrapping. This is certainly feasible, as the following section will show.


Level 2: Jump through Jump Chains
---------------------------------

The source is in ```jumpchain/{jumpchain.go|jumpchain_amd64.go}```.

### Overview

Jump table operation is confined to the function ```jumpchain```. All handlers which are reachable through
the jump table are located at labels within ```jumpchain```.

Similar to jump table bootstrapping, the handler addresses to be retrieved from ```jmptab``` are not known at program startup.
They will be filled in at run time through the Go function ```filljmptab```. In contrast to jump table bootstrapping, the
handler functions do not contain instrumentation code. Instead, ```jumpchain``` is made to contain a very
specific code sequence: a string of ```JNE``` instructions which have the handler labels as their branch targets.
This chain of jumps is the namesake of the method described here. The ```JNE``` instructions contain a relative
offset to their branch targets. This relative offset is used by ```filljmptab``` to calculate the addresses of
the handler labels.

The presence of the jump chain is marked through a prefixed two instruction sequence, called the preamble. When
looking for the jump chain, function ```filljmptab``` assumes it will start right after the preamble.
The preamble consists of a ```MOVL $imm, AX``` and an ```XORQ AX, AX```. When executed it clears the AX
register and thus sets the Z flag. This means that execution will fall right through the jump chain, effectively
making it a no-operation.

The function ```filljmptab``` searches memory for the preamble, starting at the entry point for ```jumpchain```.
After it found the preamble, it expects a sequence of ```numtargets``` JNE instructions. It disassembles
these JNE instructions, both the 8 bit and the 32 bit variant, to extract the relative offset to the jump
target. The absolute addresses of the handlers are calculated from the relative offsets, the instruction lengths
and the absolute positions of the ```JNE``` instructions in question. The absolute addresses are stored
in ```jmptab```, ready for consumption by ```jumpchain```.

The first parameter of ```jumpchain``` selects execution of the jump chain when it is 0 or dispatch through
```jmptab``` when non-zero. This purely serves to make to jump table code reachable in the eyes of the linker, 6l.
6l is rather smart and enthusiastic about repositioning code, rewriting jumps and leaving out unreachable code.
Would the jump chain not be reachable, 6l would leave it out. Having a non-jump instruction after the jump chain
prevented 6l from rewriting the last jump chain instruction. This is not guaranteed by 6l, however.

### Critique

Now this is even more interesting! The code is more baroque than jump table bootstrapping.

In contrast to the jump table bootstrapping approach, the handler functions are missing instrumentation code and
do not contain a ```JNE``` instruction which is executed every time the handler is executed. One conditional
branch remains in the dispatcher function. It is needed to keep the jump chain reachable, such that the jump
chain code is not left out in the executable.


[1] and for the linker not to outsmart us