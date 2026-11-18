// Copyright (C) 2017 Jeremiah Orians
// Copyright (C) 2020 Sanne Wouda
// This file is part of stage0.
//
// stage0 is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// stage0 is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with stage0.  If not, see <http://www.gnu.org/licenses/>.

    .section .text
    .global _start

_start:
    ldr x1, [sp,#16]             // Get the actual input name
    mov x0, #-100                // AT_FDCWD, relative to current working directory
    mov x2, #0                   // Prepare file as read only
    mov x8, #56                  // The syscall number for openat(), aarch64 has no open()
    svc #0                       // Open file!
    mov x9, x0                   // Preserve the file pointer we were given

    ldr x1, [sp,#24]             // Get the output name
    mov x0, #-100                // AT_FDCWD, relative to current working directory
    mov x2, #577                 // Prepare file as O_WRONLY|O_CREAT|O_TRUNC
    mov x3, #448                 // Prepare file as RWX for owner only (700 in octal)
    svc #0                       // Open file!
    mov x10, x0                  // Preserve the file pointer we were given

    str xzr, [sp,#-16]!          // Separate input and output bytes on the stack
    mov x2, #1                  // set the size of chars we want
    mov w11, #0                  // Not in a comment

pair:
    mov w12, #1                 // Start the marker below the first hex digit

read:
   // Attempt to read 1 byte from input file
    mov x0, x9                  // Where are we reading from
    mov x1, sp                  // Where to put it
    mov x8, #63                 // the syscall number for read
    svc #0                      // call the Kernel
    cbz x0, exit                // Got EOF call it done
    ldrb w0, [sp]               // load char, unsigned so zero-extended already
    cmp w0, #10
    csel w11, wzr, w11, eq      // A newline ends the comment
    cbnz w11, read              // Ignore the rest of the comment
    subs w3, w0, #35            // Purge Comment Lines (#)
    ccmp w3, #24, #4, ne        // Purge Comment Lines (;)
    cset w11, eq                // Remember whether a comment starts here
    b.eq read
    sub w3, w0, #48             // Subtract ASCII '0'
    cmp w3, #10
    b.lo digit                  // deal with 0-9
    orr w3, w0, #32             // Fold upper case to lower case
    sub w3, w3, #97
    cmp w3, #6
    b.hs read                   // Ignore bytes outside a through f
    add w3, w3, #10

digit:
    orr w12, w3, w12, lsl #4    // Shift the marker and append the digit
    tbz w12, #8, read           // Until the marker reaches bit 8, read another digit
    strb w12, [sp,#1]           // Only the low byte is output
    add x1, sp, #1              // What we are writing
    mov x0, x10                 // Where are we writing to
    mov x8, #64                 // the syscall number for write
    svc #0                      // call the Kernel
    b pair

exit:
   // program completed Successfully
    mov x8, #93                 // put the exit syscall number in x8
    svc #0
