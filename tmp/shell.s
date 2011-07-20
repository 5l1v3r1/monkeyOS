; command line, loaded to sectors 4 and possibly 5
; kstdio.s will follow this file.
; kstdlib.s will follow kstdio.s
; shellconstants.s will follow kstdlib.s

; 0x2000 = command buffer length
; 0x2002 = command buffer

org 0x1400
section .text
global _start

_start:
	push bp
	mov bp, sp
	
prompt:
	mov ax, commandPrompt
	push ax
	call kprint
	add sp, 2
	; kbzero(commandbuffer, 512)
	mov ax, 514
	mov bx, 0x2000
	push ax ; length
	push bx ; buffer
	call kbzero
	add sp, 4

inputLoop:
	call kgetch
	; al is now set to the read character...
	cmp al, 0x0D ; \r is enter...
	je cmdAccept ; if they hit enter, cmdAccept()
	cmp al, 0x08 ; if they hit backspace, print space first.
	jne appendBuffer
	; print space, restoring previous backspace character

; only reached if the user hit backspace.
; backspace: should decrement the command length and clear the active cell
backspace:
	mov al, 0x08
	mov bh, 0
	mov ah, 0x0e
	int 0x10
	; clear the cell
	mov al, 0x20
	mov bh, 0
	mov ah, 0x0e
	int 0x10
	mov al, 0x08 ; move back again

	; decrement the buffer length
	mov bx, 0x2000
	mov cx, [bx]
	cmp cx, 0
	je inputLoop	; if there is nothing to delete, loop
	sub cx, 1
	mov [bx], cx
	; zero the current character
	mov bx, 0x2002
	add bx, cx
	mov cl, 0
	mov [bx], cl
	; jump directly to the echo function to echo the backspace.
	; we do not want to append the backspace ASCII code to our
	; character buffer
	jmp echoInput

; called if the user didn't hit backspace.
; appendBuffer: should append the value of al to the cmd buffer and increment
; the length.
appendBuffer:
	mov bx, 0x2000
	mov cx, [bx]
	mov bx, 0x2002
	add bx, cx
	mov [bx], al ; add a new byte to the buffer
	add cx, 1
	mov bx, 0x2000
	mov [bx], cx

; echo the value of al and jump to the input loop
echoInput:
	mov bh, 0 ; page num
	mov ah, 0x0e
	int 0x10
	jmp inputLoop

; the user hit enter.
; cmdAccept: should print the last command and jump back to a new prompt
cmdAccept:
	mov ax, commandEnter
	push ax
	call kprint
	pop ax

	; print the previous command
	mov ax, commandMsg
	push ax
	call kprint
	mov ax, 0x2002
	push ax
	call kprint
	add sp, 4
	
	mov ax, commandEnter
	push ax
	call kprint
	pop ax

	mov ax, 0x2002
	mov bx, exitCmd
	push ax
	push bx
	call kstrcmp
	add sp, 4
	cmp al, 1
	je shell_done

	jmp prompt

shell_done:
; return from the command line... never should happen
	mov sp, bp
	pop bp
	xor ax, ax

	retf

global kprint
kprint:
	mov bx, sp
	add bx, 2	; stack pointer + 4 = first argument
	mov ax, [bx]
	mov bx, ax
_kprint_loop:
	; expects bx to be a ptr to the null terminated message.
	mov ah, 0x0e
	mov al, [bx]
	cmp al, 0
	je _kprint_done
	int 0x10
	add bx, 1
	jmp _kprint_loop
_kprint_done:
	xor ax, ax
	ret

global kgetch
kgetch:
	mov ah, 0x0
	int 0x16
	ret

commandPrompt:	db '$ ',0
commandEnter:	db 13,10,0
commandMsg:		db 'You wrote: ',0
exitCmd:		db 'exit',0


; kbzero(const void * buffer, unsigned uint16_t length)
; stack upon calling:
; length (2 bytes [uint])
; buffer (2 bytes [ptr])
; return address (2 bytes [ptr])
kbzero:
	push bp
	mov bp, sp
	
	; cx = buffer
	; ax = length
	mov ax, sp
	mov cx, sp
	add ax, 6
	add cx, 4
	; cx = *cx
	mov bx, cx
	mov cx, [bx]
	; ax = *ax
	mov bx, ax
	mov ax, [bx]

kbzero_loop:
	mov dl, 0
	mov bx, cx ; bx doesn't support being a pointer?!?!?!
	mov [bx], dl
	inc cx
	sub ax, 1
	cmp ax, 0
	je kbzero_done
	jmp kbzero_loop

kbzero_done:	
	mov sp, bp
	pop bp
	ret

; compare two null terminated strings
; kstrcmp(const char * buffer, const char * buffer2);
; stack upon calling:
; buffer2 (2 bytes [ptr])
; buffer (2 bytes [ptr])
; return address (2 bytes [ptr])
; return:
; al = 0 if no match
; al = 1 if math
kstrcmp:
	push bp
	mov bp, sp
	
	; ax = length
	; cx = buffer
	; dx = buffer2
	mov ax, 0 ; length
	mov bx, sp
	mov cx, [bx + 4]
	mov dx, [bx + 6]
	
kstrcmp_loop:
	push ax
	mov bx, cx
	mov al, [bx]
	mov bx, dx
	mov ah, [bx]
	cmp al, ah
	jne kstrcmp_notequal
	cmp al, 0
	je kstrcmp_gotlen
	pop ax
	inc ax
	inc cx
	inc dx
	jmp kstrcmp_loop

kstrcmp_gotlen:
	pop ax
	sub cx, ax
	sub dx, ax
	push ax
	push cx
	push dx
	call kbcmp
	add sp, 12
	
	mov sp, bp
	pop bp
	ret
kstrcmp_notequal:
	mov sp, bp
	pop bp
	mov ax, 0
	ret

; compare two buffers
; kbcmp(const void * buffer1, const void * buffer2, unsigned uint16_t length);
; stack upon calling:
; length (2 bytes [uint])
; buffer2 (2 bytes [ptr])
; buffer (2 bytes [ptr])
; return address (2 bytes [ptr])
; return:
; al = 0 if no match
; al = 1 if match
kbcmp:
	push bp
	mov bp, sp
	
	; cx = buffer1
	; dx = buffer2
	; ax = length left
	mov bx, sp
	mov cx, bx
	mov dx, bx
	mov ax, bx
	add cx, 4
	add dx, 6
	add ax, 8
	; cx = *cx
	mov bx, cx
	mov cx, [bx]
	; dx = *dx
	mov bx, dx
	mov dx, [bx]
	; ax = *ax
	mov bx, ax
	mov ax, [bx]
	
kbcmp_loop:
	push ax
	mov bx, dx
	mov al, [bx]
	mov bx, cx
	mov ah, [bx]
	cmp ah, al
	jne kbcmp_notequal
	pop ax
	sub ax, 1
	cmp ax, 0
	je kbcmp_done
	jmp kbcmp_loop
kbcmp_done:
	mov sp, bp
	pop bp
	mov ah, 0
	mov al, 1
	ret
kbcmp_notequal:
	mov sp, bp
	pop bp
	mov ax, 0
	ret

