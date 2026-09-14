; x86_64 interrupt stubs
; This file contains assembly stubs for handling interrupts and exceptions in long mode

section .text
bits 64

; External C handlers
extern isr_handleException
extern irq_handleIrq

; Macro to create an ISR stub without error code
%macro ISR_NOERRCODE 1
global isr_stub_%1
isr_stub_%1:
    ; Save general purpose registers
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    
    ; Push interrupt number and error code (0 for no error)
    push %1          ; int_num
    push 0           ; error_code
    
    ; Call C handler with pointer to CPU state
    mov rdi, rsp     ; First argument = pointer to CpuState
    call isr_handleException
    
    ; Pop error code and interrupt number
    add rsp, 16
    
    ; Restore registers
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    
    iretq
%endmacro

; Macro to create an ISR stub with error code
%macro ISR_ERRCODE 1
global isr_stub_err_%1
isr_stub_err_%1:
    ; Save general purpose registers
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    
    ; Error code is already on stack from CPU
    push %1          ; int_num
    
    ; Call C handler
    mov rdi, rsp
    call isr_handleException
    
    ; Pop interrupt number
    add rsp, 8
    
    ; Restore registers
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    
    iretq
%endmacro

; Macro to create an IRQ stub
%macro IRQ_STUB 2
global irq_stub_%1
irq_stub_%1:
    ; Save registers
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    
    ; Push interrupt number and error code
    push %2          ; int_num (IRQ base + IRQ number)
    push 0           ; error_code
    
    ; Call C handler
    mov rdi, rsp
    mov rsi, %1      ; IRQ number
    call irq_handleIrq
    
    ; Pop error code and interrupt number
    add rsp, 16
    
    ; Restore registers
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    
    iretq
%endmacro

; Define ISRs for exceptions 0-31
ISR_NOERRCODE 0    ; Division By Zero
ISR_NOERRCODE 1    ; Debug
ISR_NOERRCODE 2    ; Non Maskable Interrupt
ISR_NOERRCODE 3    ; Breakpoint
ISR_NOERRCODE 4    ; Overflow
ISR_NOERRCODE 5    ; Bound Range Exceeded
ISR_NOERRCODE 6    ; Invalid Opcode
ISR_NOERRCODE 7    ; Device Not Available
ISR_ERRCODE 8      ; Double Fault
ISR_NOERRCODE 9    ; Coprocessor Segment Overrun
ISR_ERRCODE 10     ; Invalid TSS
ISR_ERRCODE 11     ; Segment Not Present
ISR_ERRCODE 12     ; Stack-Segment Fault
ISR_ERRCODE 13     ; General Protection Fault
ISR_ERRCODE 14     ; Page Fault
ISR_NOERRCODE 15   ; Reserved
ISR_NOERRCODE 16   ; x87 FPU Error
ISR_ERRCODE 17     ; Alignment Check
ISR_NOERRCODE 18   ; Machine Check
ISR_NOERRCODE 19   ; SIMD FPU Exception
ISR_NOERRCODE 20   ; Virtualization Exception
ISR_NOERRCODE 21   ; Control Protection Exception
ISR_NOERRCODE 22   ; Reserved
ISR_NOERRCODE 23   ; Reserved
ISR_NOERRCODE 24   ; Reserved
ISR_NOERRCODE 25   ; Reserved
ISR_NOERRCODE 26   ; Reserved
ISR_NOERRCODE 27   ; Reserved
ISR_NOERRCODE 28   ; Reserved
ISR_NOERRCODE 29   ; Hypervisor Injection Exception
ISR_NOERRCODE 30   ; VMM Communication Exception
ISR_ERRCODE 31     ; Security Exception

; Define IRQs 0-15 (remapped to interrupts 32-47)
IRQ_STUB 0, 32     ; Timer
IRQ_STUB 1, 33     ; Keyboard
IRQ_STUB 2, 34     ; Cascade (Slave PIC)
IRQ_STUB 3, 35     ; COM2
IRQ_STUB 4, 36     ; COM1
IRQ_STUB 5, 37     ; LPT2
IRQ_STUB 6, 38     ; Floppy Disk
IRQ_STUB 7, 39     ; LPT1 / Spurious
IRQ_STUB 8, 40     ; RTC
IRQ_STUB 9, 41     ; Free
IRQ_STUB 10, 42    ; Free
IRQ_STUB 11, 43    ; Free
IRQ_STUB 12, 44    ; PS/2 Mouse
IRQ_STUB 13, 45    ; FPU / Coprocessor
IRQ_STUB 14, 46    ; Primary ATA
IRQ_STUB 15, 47    ; Secondary ATA

; Array of ISR stub addresses for IDT initialization
section .data
align 8
global isr_stub_table
isr_stub_table:
    dq isr_stub_0
    dq isr_stub_1
    dq isr_stub_2
    dq isr_stub_3
    dq isr_stub_4
    dq isr_stub_5
    dq isr_stub_6
    dq isr_stub_7
    dq isr_stub_err_8
    dq isr_stub_9
    dq isr_stub_err_10
    dq isr_stub_err_11
    dq isr_stub_err_12
    dq isr_stub_err_13
    dq isr_stub_err_14
    dq isr_stub_15
    dq isr_stub_16
    dq isr_stub_err_17
    dq isr_stub_18
    dq isr_stub_19
    dq isr_stub_20
    dq isr_stub_21
    dq isr_stub_22
    dq isr_stub_23
    dq isr_stub_24
    dq isr_stub_25
    dq isr_stub_26
    dq isr_stub_27
    dq isr_stub_28
    dq isr_stub_29
    dq isr_stub_30
    dq isr_stub_err_31

; Array of IRQ stub addresses
global irq_stub_table
irq_stub_table:
    dq irq_stub_0
    dq irq_stub_1
    dq irq_stub_2
    dq irq_stub_3
    dq irq_stub_4
    dq irq_stub_5
    dq irq_stub_6
    dq irq_stub_7
    dq irq_stub_8
    dq irq_stub_9
    dq irq_stub_10
    dq irq_stub_11
    dq irq_stub_12
    dq irq_stub_13
    dq irq_stub_14
    dq irq_stub_15
