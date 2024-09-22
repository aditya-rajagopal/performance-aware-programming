global NormalLoopASM
global NOPLoopASM
global CMPLoopASM
global DECLoopASM

section .text align=128

DECLoopASM: ; For some reason this is very slow and align 16 does not seem to be doing anything
align 16
.loop: 
    dec rcx
    jnz .loop
    ret

NormalLoopASM:
    xor rax, rax ; This clears RAX to 0
.loop:
    mov [rdx + rax], al ; expect the pointer to the array in the second argument per Windows ABI
    inc rax
    cmp rax, rcx ; The length of the array is the first argument and is stored in rcx per windows ABI
    jb .loop
    ret

NOPLoopASM:
    xor rax, rax
.loop:
    db 0x0f, 0x1f, 0x00 ; 3byte NOP based on intel manual
    inc rax
    cmp rax, rcx
    jb .loop
    ret


CMPLoopASM:
    xor rax, rax 
.loop:
    inc rax
    cmp rax, rcx
    jb .loop
    ret
