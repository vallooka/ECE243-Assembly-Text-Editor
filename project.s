# TODO: add line numbers
# TODO: add support for selections

.equ WIDTH, 320
.equ HEIGHT, 240
.equ LOG2_BYTES_PER_ROW, 10
.equ LOG2_BYTES_PER_PIXEL, 1

.equ PIXBUF, 0x08000000	# Pixel buffer. Same on all boards.
.equ CHARBUF, 0x09000000	# Character buffer. Same on all boards.

.equ PS2, 0xff200100
.equ TIMER_BASE, 0xff202000
.equ CHAR_ARRAY_BASE, 0x03fffffc # char array to hold entire file contents

.data
cursor_ptr: .word 0x03FFFFFC # a pointer to the array element the cursor is currently on
cursor_blink: .byte 0

ps2_previous_byte:
.byte 0x00

shiftHeld:
.byte 0x00

.text
.global _start
_start:
	INITIALIZATION:
	# store the char array on the stack
	movia sp, 0x04000000
	subi sp, sp, 4
	# set the first byte to zero; zero length string
	stb r0, 0(sp)
	# max 10000 characters in the array
	subi sp, sp, 10000
	# make the cursor point to the beginning of the array
	movia r9, cursor_ptr
	movia r8, CHAR_ARRAY_BASE
	stw r8, 0(r9)

    # enable global interrupts
    movi r8, 1
    wrctl ctl0, r8
    # enable interrupts on IRQ 7 (PS/2), IRQ 0 (timer1)
    movia r8, 0x81
    wrctl ctl3, r8
    # enable read interrupts on PS/2 device
    movia r8, PS2
    movi r9, 1
    stwio r9, 4(r8)
	# set period to 1 second on timer
	movia r8, TIMER_BASE
	movui r9, 0xe100   # lower half
	ldwio r9, 8(r8)
	movui r9, 0x05f5    # upper half
	ldwio r9, 12(r8)
	# enable timeout interrupts and start timer
	movui r9, 7
	stwio r9, 4(r8)

Loop:
	# Fill screen with black, clear text by drawing over with spaces
	movia r4, 0x0146
    call FillColour		
    call FillSpaces		
    call FillSidebar		
    
	# Draw contents of char array to the screen
	# (r4, r5) := (x, y)
	# r16 := char array iterator
	movia r16, CHAR_ARRAY_BASE
	movi r4, 3
	movi r5, 0

	DRAWING_TEXT:
	# bool := should draw printable ascii char
	movi r18, 1

	# draw cursor if (iterator == cursor_ptr) && (cursor_blink)
	movia r17, cursor_ptr
	ldw r17, 0(r17)
	bne r16, r17, READ_CHAR

	movia r17, cursor_blink
	ldbu r17, 0(r17)
	beq r17, r0, READ_CHAR

	movia r6, 0xffff
	call FillCharBG
	# don't print ascii character over cursor
	movi r18, 1

	READ_CHAR:
	# check if zero terminator
	ldbu r6, 0(r16)
	beq r6, r0, DONE

	# check if newline
	movui r17, '\n'
	bne r6, r17, PRINTABLE_CHAR
	movi r4, 3     # carriage return
	addi r5, r5, 1 # line feed
	br CHAR_DONE

	# print ascii character
	PRINTABLE_CHAR:
	beq r18, r0, CHAR_DONE # don't draw over cursor
	call WriteChar
	# increment x
	addi r4, r4, 1

	CHAR_DONE:
	# increment iterator
	subi r16, r16, 1
	br DRAWING_TEXT

	DONE:
    br Loop

#####################
## VGA SUBROUTINES ##
#####################

# r4: colour
FillColour:
	subi sp, sp, 16
    stw r16, 0(sp)		# Save some registers
    stw r17, 4(sp)
    stw r18, 8(sp)
    stw ra, 12(sp)
    
    mov r18, r4
    
    # Two loops to draw each pixel
    movi r16, WIDTH-1
    1:	movi r17, HEIGHT-1
        2:  mov r4, r16
            mov r5, r17
            mov r6, r18
            call WritePixel		# Draw one pixel
            subi r17, r17, 1
            bge r17, r0, 2b
        subi r16, r16, 1
        bge r16, r0, 1b
    
    ldw ra, 12(sp)
	ldw r18, 8(sp)
    ldw r17, 4(sp)
    ldw r16, 0(sp)    
    addi sp, sp, 16
    ret

# r4: x
# r5: y
# r6: colour
FillCharBG:
	subi sp, sp, 44
    stw r16, 0(sp)		# Save some registers
    stw r17, 4(sp)
    stw r18, 8(sp)
    stw r19, 12(sp)
    stw r20, 16(sp)
    stw r21, 20(sp)
    stw r22, 24(sp)
	stw r4, 28(sp)
	stw r5, 32(sp)
	stw r6, 36(sp)
    stw ra, 40(sp)
    
	# colour
    mov r18, r6
	# calculate rect bounds
	mov r19, r4
	mov r20, r5
	# min: multiply x,y by 8
	muli r19, r19, 4
	muli r20, r20, 4
	# max: add width/height (8 - 1)
	addi r21, r19, 3
	addi r22, r20, 3
    
    # Two loops to draw each pixel
    mov r16, r21
    1:	mov r17, r22
        2:  mov r4, r16
            mov r5, r17
            mov r6, r18
            call WritePixel		# Draw one pixel
            subi r17, r17, 1
            bge r17, r20, 2b
        subi r16, r16, 1
        bge r16, r19, 1b
    
    ldw r16, 0(sp)		# Save some registers
    ldw r17, 4(sp)
    ldw r18, 8(sp)
    ldw r19, 12(sp)
    ldw r20, 16(sp)
    ldw r21, 20(sp)
    ldw r22, 24(sp)
	ldw r4, 28(sp)
	ldw r5, 32(sp)
	ldw r6, 36(sp)
    ldw ra, 40(sp)
    addi sp, sp, 44
    ret

FillSpaces:
	subi sp, sp, 16
    stw r16, 0(sp)		# Save some registers
    stw r17, 4(sp)
    stw r18, 8(sp)
    stw ra, 12(sp)
    
    mov r18, r4
    
    # Two loops to fill screen with spaces
    movi r16, 79
    1:	movi r17, 59
        2:  mov r4, r16
            mov r5, r17
            movi r6, ' '     # this is a space
            call WriteChar		# Draw one space
            subi r17, r17, 1
            bge r17, r0, 2b
        subi r16, r16, 1
        bge r16, r0, 1b
    
    ldw ra, 12(sp)
	ldw r18, 8(sp)
    ldw r17, 4(sp)
    ldw r16, 0(sp)
    addi sp, sp, 16
    ret


# r4: col
# r5: row
# r6: character
WriteChar:
	subi sp, sp, 12
	stw r4, 0(sp)
	stw r5, 4(sp)
	stw r6, 8(sp)
	
	slli r5, r5, 7
    add r5, r5, r4
    movia r4, CHARBUF
    add r5, r5, r4
    stbio r6, 0(r5)

	ldw r4, 0(sp)
	ldw r5, 4(sp)
	ldw r6, 8(sp)
	addi sp, sp, 12
    ret

# r4: col (x)
# r5: row (y)
# r6: colour value
WritePixel:
	movi r2, LOG2_BYTES_PER_ROW		# log2(bytes per row)
    movi r3, LOG2_BYTES_PER_PIXEL	# log2(bytes per pixel)
    
    sll r5, r5, r2
    sll r4, r4, r3
    add r5, r5, r4
    movia r4, PIXBUF
    add r5, r5, r4
    
	sthio r6, 0(r5)		# Write 16-bit pixel
	ret

FillSidebar:
	subi sp, sp, 16
    stw r16, 0(sp)		# Save some registers
    stw r17, 4(sp)
    stw r18, 8(sp)
    stw ra, 12(sp)

    movi r16, 2
    1:	movi r17, 59
        2:  mov r4, r16
            mov r5, r17
            movi r6, 0x01A8     # sidebar colour
            call FillCharBG		
            subi r17, r17, 1
            bge r17, r0, 2b
        subi r16, r16, 1
        bge r16, r0, 1b

    ldw r16, 0(sp)		# Save some registers
    ldw r17, 4(sp)
    ldw r18, 8(sp)
    ldw ra, 12(sp)
	addi sp, sp, 16
	ret

# r4: number
# r5: column
DrawNumber:
	subi sp, sp, 16
    stw r16, 0(sp)		# Save some registers
    stw r17, 4(sp)
    stw r18, 8(sp)
    stw ra, 12(sp)


    ldw r16, 0(sp)		# Save some registers
    ldw r17, 4(sp)
    ldw r18, 8(sp)
    ldw ra, 12(sp)
	addi sp, sp, 16
	ret

###################################
## TEXT MANIPULATION SUBROUTINES ##
###################################

# insert r4 char into array at position cursor_ptr
# shift everything after one place to the right
insert_char:
	subi sp, sp, 12
	stw r8, 0(sp)
	stw r9, 4(sp)
	stw r10, 8(sp)

	# buffptr is starting point in the array
	movia r8, cursor_ptr
	ldw r8, 0(r8)
	
	# r9 := copy register
	# r10 := paste register
	mov r9, r4

	SHIFT_ARRAY_RIGHT:
	# last value that was copied is now being pasted
	mov r10, r9

	# copy at position
	ldb r9, 0(r8)

	# paste at position
	stb r10, 0(r8)

	subi r8, r8, 1
	
	# after paste, check if zero was just pasted
	bne r10, r0, SHIFT_ARRAY_RIGHT

	# shift cursor one over to the right
	movia r9, cursor_ptr
	ldw r8, 0(r9)
	subi r8, r8, 1
	stw r8, 0(r9)

	ldw r8, 0(sp)
	ldw r9, 4(sp)
	ldw r10, 8(sp)
	addi sp, sp, 12
	ret

# delete a character in the array at position cursor_ptr
# shift everything after one place to the left
delete_char:
	subi sp, sp, 8
	stw r8, 0(sp)
	stw r9, 4(sp)

	movia r8, cursor_ptr
	ldw r8, 0(r8)

	# check if trying to delete at the beginning of the array
	movia r9, CHAR_ARRAY_BASE
	beq r8, r9, DC_DONE

	addi r8, r8, 1
	SHIFT_ARRAY_LEFT:
	# copy char at next position into current position
	ldb r9, -1(r8)
	stb r9, 0(r8)
    
    subi r8, r8, 1

	# stop if zero was just moved
	bne r9, r0, SHIFT_ARRAY_LEFT

	# move cursor one over to the left
	movia r8, cursor_ptr
	ldw r9, 0(r8)
	addi r9, r9, 1
	stw r9, 0(r8)

	DC_DONE:
	ldw r8, 0(sp)
	ldw r9, 4(sp)
	addi sp, sp, 8
	ret

move_cursor_left:
	subi sp, sp, 8
	stw r8, 0(sp)
	stw r9, 4(sp)

	movia r8, cursor_ptr
	ldw r8, 0(r8)

	# at beginning of char array
	movia r9, CHAR_ARRAY_BASE
	beq r8, r9, MCL_DONE

	# increment cursor pointer
	addi r8, r8, 1
	movia r9, cursor_ptr
	stw r8, 0(r9)

	MCL_DONE:
	ldw r8, 0(sp)
	ldw r9, 4(sp)
	addi sp, sp, 8
	ret

move_cursor_right:
	subi sp, sp, 8
	stw r8, 0(sp)
	stw r9, 4(sp)

	movia r8, cursor_ptr
	ldw r8, 0(r8)

	# at end of char array
	ldbu r9, 0(r8)
	beq r9, r0, MCR_DONE

	# decrement cursor pointer
	subi r8, r8, 1
	movia r9, cursor_ptr
	stw r8, 0(r9)

	MCR_DONE:
	ldw r8, 0(sp)
	ldw r9, 4(sp)
	addi sp, sp, 8
	ret

# first step: count number of columns while moving cursor left to the start of the current line
# second step: go to start of the previous line
# third step: go the specified number of columns to the right
move_cursor_up:
	subi sp, sp, 16
	stw r8, 0(sp)
	stw r9, 4(sp)
	stw r10, 8(sp)
	stw r11, 12(sp)

	# check if cursor is at beginning of array
	movia r8, cursor_ptr
	ldw r8, 0(r8)
	movia r11, CHAR_ARRAY_BASE
	beq r8, r11, MCU_EXIT

	# r9 := column
	movi r9, 0

	# the following ensures that: columns start at 0, cursor at newline isn't on column 0
	addi r8, r8, 1

	# count which column the cursor is on
	MCU_COUNT_COLUMNS:
	movia r11, CHAR_ARRAY_BASE  
	beq r8, r11, MCU_EXIT # hit beginning of array, can't move up
	ldbu r10, 0(r8)
	movui r11, '\n'
	beq r10, r11, MCU_COUNT_COLUMNS_DONE # hit newline

	addi r9, r9, 1 # increment column
	addi r8, r8, 1 # move cursor left
	br MCU_COUNT_COLUMNS
	MCU_COUNT_COLUMNS_DONE:

	# continuing from previous loop, the cursor is now at the end of the previous line.
	addi r8, r8, 1

	# move cursor to the beginning of the line
	MCU_TO_PREV_LINE_START:
	# check for beginning of array
	movia r10, CHAR_ARRAY_BASE
	beq r8, r10, MCU_NEXT_LINE_DONE
	# check for newline
	ldb r10, 0(r8)
	movui r11, '\n'
	beq r10, r11, MCU_NEXT_LINE_DONE_NEWLINE
	# move cursor left
	addi r8, r8, 1
	br MCU_TO_PREV_LINE_START
	
	MCU_NEXT_LINE_DONE_NEWLINE:
	# move cursor after newline
	subi r8, r8, 1
	MCU_NEXT_LINE_DONE:

	# move cursor to the same column as the previous, or up to newline
	MCU_TO_COLUMN:
	# check if at correct position
	beq r9, r0, MCU_SAVE_CURSOR
	# check for newline
	ldb r10, 0(r8)
	movui r11, '\n'
	beq r10, r11, MCU_SAVE_CURSOR
	# move cursor right
	subi r8, r8, 1
	subi r9, r9, 1
	br MCU_TO_COLUMN

	MCU_SAVE_CURSOR:
	movia r9, cursor_ptr
	stw r8, 0(r9)

	MCU_EXIT:
	ldw r8, 0(sp)
	ldw r9, 4(sp)
	ldw r10, 8(sp)
	ldw r11, 12(sp)
	addi sp, sp, 16
	ret

# first step: count number of columns
# second step: move cursor to the start of the next line
# third step: go the specified number of columns to the right
move_cursor_down:
	subi sp, sp, 16
	stw r8, 0(sp)
	stw r9, 4(sp)
	stw r10, 8(sp)
	stw r11, 12(sp)

	# r9 := column
	movi r9, 0

	# check if cursor is at beginning of array, otherwise upcoming loop fails
	movia r8, cursor_ptr
	ldw r8, 0(r8)
	movia r11, CHAR_ARRAY_BASE
	beq r8, r11, MCD_COUNT_COLUMNS_DONE

	# the following ensures that: columns start at 0, cursor at newline isn't on column 0
	addi r8, r8, 1

	# count which column the cursor is on
	MCD_COUNT_COLUMNS:
	movia r11, CHAR_ARRAY_BASE  
	beq r8, r11, MCD_COUNT_COLUMNS_DONE_ARRAY_START # hit beginning of array
	ldbu r10, 0(r8)
	movui r11, '\n'
	beq r10, r11, MCD_COUNT_COLUMNS_DONE # hit newline

	addi r9, r9, 1 # increment column
	addi r8, r8, 1 # move cursor left
	br MCD_COUNT_COLUMNS

	# increment column to compensate for no newline
	MCD_COUNT_COLUMNS_DONE_ARRAY_START:
	addi r9, r9, 1

	# move cursor to next line
	MCD_COUNT_COLUMNS_DONE:
	movia r8, cursor_ptr
	ldw r8, 0(r8)

	MCD_TO_NEXT_LINE:
	# check for newline
	ldb r10, 0(r8)
	movui r11, '\n'
	beq r10, r11, MCD_NEXT_LINE_DONE
	# check for zero terminator
	beq r10, r0, MCD_EXIT
	# move cursor right
	subi r8, r8, 1
	br MCD_TO_NEXT_LINE
	
	MCD_NEXT_LINE_DONE:
	# move cursor past newline
	subi r8, r8, 1

	# move cursor to the same column as the previous, or up to newline/zero terminator
	MCD_TO_COLUMN:
	# check if at correct position
	beq r9, r0, MCD_SAVE_CURSOR
	# check for newline or zero terminator
	ldb r10, 0(r8)
	movui r11, '\n'
	beq r10, r11, MCD_SAVE_CURSOR
	beq r10, r0, MCD_SAVE_CURSOR
	# move cursor right
	subi r8, r8, 1
	subi r9, r9, 1
	br MCD_TO_COLUMN

	MCD_SAVE_CURSOR:
	movia r9, cursor_ptr
	stw r8, 0(r9)

	MCD_EXIT:
	ldw r8, 0(sp)
	ldw r9, 4(sp)
	ldw r10, 8(sp)
	ldw r11, 12(sp)
	addi sp, sp, 16
	ret

#######################
## INTERRUPT HANDLER ##
#######################
.section .exceptions, "ax"
interrupt_handler:
    subi sp, sp, 56
    stw r8, 0(sp)
    stw r9, 4(sp)
    stw r10, 8(sp)
    stw r11, 12(sp)
    stw r12, 16(sp)
    stw r13, 20(sp)
    stw r14, 24(sp)
    stw r4, 28(sp)
    stw r5, 32(sp)
    stw r6, 36(sp)
    stw r7, 40(sp)
    stw r15, 44(sp)
    stw r16, 48(sp)
	# NOTE: control flow must not call more than one function in this section
	# ra is saved here to reduce overhead of calling a function
    stw ra, 52(sp)

	# check which device triggered interrupt
	movia r8, PS2
	ldwio r8, 4(r8)
	andi r8, r8, 0x100
	bne r8, r0, KEYBOARD_INTERRUPT

	###########################################
	######### TIMER INTERRUPT SECTION ######### 
	###########################################
	
	# toggle cursor_blink
	movia r8, cursor_blink
	ldbu r9, 0(r8)
	beq r9, r0, TOGGLE_ON

	TOGGLE_OFF:
	stb r0, 0(r8)
	br TOGGLE_DONE

	TOGGLE_ON:
	movui r9, 1
	stb r9, 0(r8)

	TOGGLE_DONE:
	# acknowledge interrupt, clear timeout bit
	movia r8, TIMER_BASE
	stwio r0, 0(r8)
	br end

	KEYBOARD_INTERRUPT:
	############################################
	######## KEYBOARD INTERRUPT SECTION ########
	############################################
	# ** r8 CONST REGISTER **
	# r8 := previously read byte
    movia r10, ps2_previous_byte
	ldbu r8, 0(r10)

	# ** R9 CONST REGISTER **
	# r9 := byte from PS/2
    movia r9, PS2
    ldwio r9, 0(r9)
    andi  r9, r9, 0xFF
	
	# update the 'previously read byte' variable with new value
	stb r9, 0(r10)

	# ascii character starts at 'a' or 'A' depending on shift held
	movui r14, 'a'
    movia r15, shiftHeld
	ldb r15, 0(r15)
	beq r15, r0, shift_checked:
	movui r14, 'A'
	shift_checked:

	# check if shift was pressed/released
    cmpeqi r10, r9, 0x12
    bne   r10, r0, shift
	br extended

    shift:
    movia r15, shiftHeld
    movi r16, 1
    stb r16, 0(r15)
	cmpeqi r10, r8, 0xf0
    bne   r10, r0, shift_released
	br end

	shift_released:
    stb r0, 0(r15)
	br end
    
    # CapsCheck:
    # ldb r16, 0(r15)
    # addi r16, r16, 1
    # stb r16, 0(r15)
    # andi r16, r16, 0x01 
    
    extended:

	# now that shift was checked, all break codes can be ignored
	movui r10, 0xf0
	beq r8, r10, end

	# extended code means previous byte is E0
	movui r13, 0xe0
    bne r8, r13, alphabet

    # Up Arrow
    cmpeqi   r10, r9, 0x75
    bne   r10, r0, caseUpArrow
    
    # Down Arrow
    cmpeqi   r10, r9, 0x72
    bne   r10, r0, caseDownArrow
    
    # Left Arrow
    cmpeqi   r10, r9, 0x6b
    bne   r10, r0, caseLeftArrow
    
    # Right Arrow
    cmpeqi   r10, r9, 0x74
    bne   r10, r0, caseRightArrow
	
	alphabet:
    # A
    cmpeqi   r10, r9, 0x1c
    bne   r10, r0, case_insert_char 
    # B
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x32
    bne   r10, r0, case_insert_char
    # C
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x21
    bne   r10, r0, case_insert_char
    # D
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x23
    bne   r10, r0, case_insert_char
    # E
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x24
    bne   r10, r0, case_insert_char
	# F
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x2b
    bne   r10, r0, case_insert_char
    # G
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x34
    bne   r10, r0, case_insert_char
    # H
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x33
    bne   r10, r0, case_insert_char
    # I
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x43
    bne   r10, r0, case_insert_char
    # J
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x3b
    bne   r10, r0, case_insert_char
    # K
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x42
    bne   r10, r0, case_insert_char
    # L
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x4b
    bne   r10, r0, case_insert_char
    # M
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x3a
    bne   r10, r0, case_insert_char
    # N
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x31
    bne   r10, r0, case_insert_char
    # O
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x44
    bne   r10, r0, case_insert_char
    # P
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x4d
    bne   r10, r0, case_insert_char
    # Q
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x15
    bne   r10, r0, case_insert_char
    # R
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x2d
    bne   r10, r0, case_insert_char
    # S
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x1b
    bne   r10, r0, case_insert_char
    # T
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x2c
    bne   r10, r0, case_insert_char
    # U
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x3c
    bne   r10, r0, case_insert_char
    # V
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x2a
    bne   r10, r0, case_insert_char
    # W
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x1d
    bne   r10, r0, case_insert_char
    # X
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x22
    bne   r10, r0, case_insert_char
    # Y
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x35
    bne   r10, r0, case_insert_char
    # Z
    addi r14, r14, 1
    cmpeqi   r10, r9, 0x1a
    bne   r10, r0, case_insert_char


	# r11 := is shift currently held down?
	movia r11, shiftHeld
	ldbu r11, 0(r11)
    # 0
    movi r14, '0'
	beq r11, r0, a
	movui r14, ')'
	a: cmpeqi   r10, r9, 0x45
    bne   r10, r0, case_insert_char
    
    # 1
    movi r14, '1'
	beq r11, r0, b
	movui r14, '!'
	b: cmpeqi   r10, r9, 0x16
    bne   r10, r0, case_insert_char
    
    # 2
    movi r14, '2'
	beq r11, r0, c
	movui r14, '@'
	c: cmpeqi   r10, r9, 0x1e
    bne   r10, r0, case_insert_char
    
    # 3
    movi r14, '3'
	beq r11, r0, d
	movui r14, '#'
	d: cmpeqi   r10, r9, 0x26
    bne   r10, r0, case_insert_char
    
    # 4
    movi r14, '4'
	beq r11, r0, e
	movui r14, '$'
	e: cmpeqi   r10, r9, 0x25
    bne   r10, r0, case_insert_char
    
    # 5
    movi r14, '5'
	beq r11, r0, f
	movui r14, '%'
	f: cmpeqi   r10, r9, 0x2e
    bne   r10, r0, case_insert_char
    
    # 6
    movi r14, '6'
	beq r11, r0, g
	movui r14, '^'
	g: cmpeqi   r10, r9, 0x36
    bne   r10, r0, case_insert_char
    
    # 7
    movi r14, '7'
	beq r11, r0, h
	movui r14, '&'
	h:
    cmpeqi   r10, r9, 0x3d
    bne   r10, r0, case_insert_char
    
    # 8
    movi r14, '8'
	beq r11, r0, i
	movui r14, '*'
	i: cmpeqi   r10, r9, 0x3e
    bne   r10, r0, case_insert_char
    
    # 9
    movi r14, '9'
	beq r11, r0, j
	movui r14, '('
	j: cmpeqi   r10, r9, 0x46
    bne   r10, r0, case_insert_char

    # spacebar
    cmpeqi   r10, r9, 0x29
	movi r14, ' '
    bne   r10, r0, case_insert_char

    # backspace
    cmpeqi   r10, r9, 0x66
    bne   r10, r0, caseBackspace

    # enter
    cmpeqi   r10, r9, 0x5a
    bne   r10, r0, caseEnter

	# comma
    movi r14, ','
	beq r11, r0, k
	movui r14, '<'
	k: cmpeqi   r10, r9, 0x41
    bne   r10, r0, case_insert_char

	# period
    movi r14, '.'
	beq r11, r0, l
	movui r14, '>'
	l: cmpeqi   r10, r9, 0x49
    bne   r10, r0, case_insert_char

	# f slash /
    movi r14, '/'
	beq r11, r0, m
	movui r14, '?'
	m: cmpeqi   r10, r9, 0x4a
    bne   r10, r0, case_insert_char

	# semicolon
    movi r14, ';'
	beq r11, r0, n
	movui r14, ':'
	n: cmpeqi   r10, r9, 0x4c
    bne   r10, r0, case_insert_char

	# Apostrophe
    movi r14, 39
	beq r11, r0, o
	movui r14, 34
	o: cmpeqi   r10, r9, 0x52
    bne   r10, r0, case_insert_char

	# LeftBracket
    movi r14, '['
	beq r11, r0, p
	movui r14, '{'
	p: cmpeqi   r10, r9, 0x54
    bne   r10, r0, case_insert_char

	# RightBracket
    movi r14, ']'
	beq r11, r0, q
	movui r14, '}'
	q: cmpeqi   r10, r9, 0x5b
    bne   r10, r0, case_insert_char

    # Minus
    movi r14, '-'
	beq r11, r0, r
	movui r14, '_'
	r: cmpeqi   r10, r9, 0x4e
    bne   r10, r0, case_insert_char

    # Equals
    movi r14, '='
	beq r11, r0, s
	movui r14, '+'
	s: cmpeqi   r10, r9, 0x55
    bne   r10, r0, case_insert_char

	br end
    
	########################################
    ############# CASES ####################
	########################################
    
	case_insert_char:
    # call insert_char, pass in ascii char
	mov r4, r14
    call insert_char
    br end  
    
    caseBackspace:
    call delete_char
	br end
    
    caseEnter:
	movui r4, '\n'

    call insert_char
	br end
    
	caseUpArrow:
	mov r4, r14
    call move_cursor_up
	br end

	caseDownArrow:
	mov r4, r14
    call move_cursor_down
	br end

	caseLeftArrow:
	mov r4, r14
    call move_cursor_left
	br end

	caseRightArrow:
	mov r4, r14
    call move_cursor_right
	br end

    end:
    
    ldw r8, 0(sp)
    ldw r9, 4(sp)
    ldw r10, 8(sp)
    ldw r11, 12(sp)
    ldw r12, 16(sp)
    ldw r13, 20(sp)
    ldw r14, 24(sp)
    ldw r4, 28(sp)
    ldw r5, 32(sp)
    ldw r6, 36(sp)
    ldw r7, 40(sp)
    ldw r15, 44(sp)
    ldw r16, 48(sp)
    ldw ra, 52(sp)
    addi sp, sp, 56
    subi ea, ea, 4
    eret
