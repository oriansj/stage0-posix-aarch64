// Copyright (C) 2020 Jeremiah Orians
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
    ldr x1, [sp,16]             // Get the actual input name
    add x20, sp, 32             // Get envp (hopefullY)
    cbnz x1, open_script        // Have real input
    add x20, sp, 24             // Nope, envp is here!
    adr x1, default_file        // Use "kaem.aarch64"

open_script:
    mov x0, -100                // AT_FDCWD, relative to current working directory
    mov x2, 0                   // prepare read_only
    mov x8, 56                  // the syscall number for openat()
    svc 0                       // Now open that damn file
    cmp x0, 0                   // IF NULL We couldn't open the file
    b.le exit                   // Abort hard
    mov x19, x0                 // Set input pointer
    sub sp, sp, 144             // Reserve 128 bytes for siginfo and a separate read byte

    mov x0, 0                   // Get current brk
    mov x8, 214                 // the Syscall # for SYS_BRK
    svc 0                       // Let the kernel do the work
    mov x21, x0                 // Set our malloc pointer

command:
    // Where the main work gets done
    mov x0, 2048                // Using 256 char* of space
    bl alloc                    // get it
    mov x22, x0                 // set tokens
    mov x23, x0                 // I = 0
    str xzr, [sp,24]            // status = 0

word:
    mov x0, 4096                // Using max_string
    bl alloc                    // allocate space
    mov x24, x0                 // token = malloc(max_string);
    mov x25, x0                 // i = 0; set token[i]

scan:
    bl get                      // c = fgetc(input);
    cmp w0, 252                 // if C == EOF
    b.eq done
    cmp w0, 10                  // IF C == '\n'
    b.eq line_end
    cmp w0, 32                  // IF C == ' '
    ccmp w0, 9, 4, ne           // IF C == '\t'
    b.eq word_end
    cmp w0, 34                  // IF C == '\"'
    b.eq quoted
    cmp w0, 35                  // IF C == '#'
    b.eq comment
    cmp w0, 92                  // IF C == '\\'
    b.eq escaped
    strb w0, [x25], 1           // token[i] = C
    b scan                      // Keep going

quoted:
    // It is a RAW STRING
    bl get                      // C = fgetc(input)
    cmp w0, 252                 // if C == EOF
    b.eq exit                   // Something went horribly wrong
    cmp w0, 34
    b.eq word_end               // be done
    strb w0, [x25], 1           // target[index] = C
    b quoted                    // Keep going

escaped:
    // It is an escape char
    bl get                      // Read the char to drop

word_end:
    cmp x24, x25                // IF i == 0
    b.eq word                   // Skip an empty word
    str x24, [x23], 8           // tokens[i] = result
    b word

comment:
// Just throws away everything it reads
    bl get                      // C = fgetc(input)
    cmp w0, 252                 // IF C == EOF
    b.eq exit                   // abort hard
    cmp w0, 10                  // IF C == '\n'
    b.ne comment                // otherwise keep looping

line_end:
    cmp x24, x25
    b.eq run                    // Nothing to append for an empty final word
    str x24, [x23], 8           // tokens[i] = result

run:
    cmp x22, x23
    b.eq command                // Skip a blank command
    adr x1, prefix              // using " +> "
    bl puts                     // print it
    mov x26, x22                // Walk argv without changing its base

print_arg:
    ldr x1, [x26], 8            // using tokens[j]
    bl puts                     // print it
    adr x1, space               // using ' '
    bl puts                     // print it
    cmp x26, x23
    b.ne print_arg              // Stop at the next unused argv slot
    adr x1, newline             // using '\n'
    bl puts                     // print it
    ldr x0, [x22]               // program = tokens[0]
    cbz x0, exit                // IF NULL == program
    mov x0, 17                  // flags = SIGCHILD
    mov x1, 0                   // parent_tid
    mov x2, 0                   // tls
    mov x3, 0                   // child_tid
    mov x8, 220                 // FORKing (SYS_clone)
    svc 0                       // int f = clone()
    cmp x0, 0                   // Check fork
    b.lt exit                   // IF f == -1 abort hard
    b.ne parent                 // Only the child calls execve
    ldr x0, [x22]               // program = tokens[0]
    mov x1, x22
    mov x2, x20                 // third arg = envp
    mov x8, 221                 // EXECVE
    svc 0                       // execve(program, tokens, envp);
    b exit                      // return error

parent:
    mov x1, x0                  // id = f
    mov x0, 1                   // id_type = P_PID
    mov x2, sp                  // infop
    mov x3, 4                   //  options = WEXITED
    mov x8, 95                  // WAITID
    svc 0
    ldr x0, [sp,24]             // Using status
    cbz x0, command             // IF 0 == status
    adr x1, hard                // Using "Subprocess error\nABORTING HARD\n"
    bl puts                     // Print it

done:
    // program completed Successfully
    mov x0, 0                   // All is well

exit:
    mov x8, 93                  // put the exit syscall number in x8
    svc 0

alloc:
    mov x9, x21                 // Save to return later
    add x0, x0, x21             // Request the number of desired bytes
    mov x8, 214                 // the Syscall # for SYS_BRK
    svc 0                       // call the Kernel
    mov x21, x0                 // Update pointer
    mov x0, x9                  // Return the old break
    ret

get:
    mov x0, x19                 // Read from the script
    add x1, sp, 128             // Byte buffer beyond siginfo
    mov x2, 1
    mov w9, 252                 // Leave 0xFC in the buffer if read returns no byte
    strb w9, [x1]
    mov x8, 63                  // the syscall number for read
    svc 0                       // call the Kernel
    ldrb w0, [x1]               // Return the byte as an unsigned value
    ret

puts:
    cbz x1, printed             // Protect against nulls
    mov x2, 1                   // set the size of chars we want
    mov x8, 64                  // the syscall number for write

print_byte:
    ldrb w0, [x1]               // Read byte
    cbz w0, printed             // Check for NULL
    mov x0, 1                   // Write to target file
    svc 0                       // call the Kernel
    add x1, x1, 1               // S = S + 1
    b print_byte                // Keep going

printed:
    ret
default_file: .asciz "kaem.aarch64"
prefix: .asciz " +> "
space: .asciz " "
newline: .asciz "\n"
hard: .asciz "Subprocess error\nABORTING HARD\n"
