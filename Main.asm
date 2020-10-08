; MIDI Filter - By Nicholas Tate - October 2020

	LIST 		p=16F877
	#include	<P16F877.inc>

	__config _HS_OSC & _WDT_OFF & _PWRTE_ON & _CP_OFF & _BODEN_ON & _LVP_ON & _CPD_ON & _WRT_ENABLE_ON & _DEBUG_OFF

	errorlevel -302				;Suppress message 302 from list file

;Constants
SPBRG_VAL	EQU	.39				;set baud rate 31250 for 20Mhz clock

;Bit Definitions
newData		   equ	0			;bit indicates new data received

status         equ            0x03           	;Flag reqister.
zero           equ            2              	;Zero flag.
digitcarry     equ            1              	;Digit carry flag.
carry          equ            0              	;Carry flag.

PCL            equ            0x02           	;Program counter low byte.

;Variables
		CBLOCK	0x020
		Flags				
		temp
		rxbuffer
		txbuffer
		keyPressState							;Saves the Note ON or OFF byte.
		noteValue								;Saves the note number pressed.
		velocityState							;Saves the velocity.
		ENDC
			
Bank0		MACRO					;macro to select data RAM bank 0
		bcf	STATUS,RP0
		bcf	STATUS,RP1
		ENDM

Bank1		MACRO					;macro to select data RAM bank 1
		bsf	STATUS,RP0
		bcf	STATUS,RP1
		ENDM

Bank2		MACRO					;macro to select data RAM bank 2
		bcf	STATUS,RP0
		bsf	STATUS,RP1
		ENDM

Bank3		MACRO					;macro to select data RAM bank 3
		bsf	STATUS,RP0
		bsf	STATUS,RP1
		ENDM


		ORG     0x0000				;place code at reset vector

ResetCode	
		clrf    PCLATH				;select program memory page 0
  		goto    init				;go to beginning of program

;This code executes when an interrupt occurs.
		ORG	0x0004					;place code at interrupt vector
InterruptCode						;do interrupts here
		retfie						;return from interrupt

init
		call	serial_init			;Set up serial port...>
serialRead     
		call	receive        
        movlw   0x90              	;Check for 1st byte, NOTE ON, CHANNEL 1.
        subwf 	rxbuffer,w
        btfss  	status,zero
		goto	isNoteOff
       	goto  	saveKeyPressState    
isNoteOff
		movlw	0x80				;Check for 1st byte, NOTE OFF, CHANNEL 1.
		subwf	rxbuffer,w
		btfss	status, zero
		goto	serialRead			;Any other message type is ignored.
saveKeyPressState
		movf	rxbuffer,w
		movwf	keyPressState		;Save the note ON or OFF state for later.
midi_clk    
	 	call	receive        		;2nd byte, NOTE NUMBER.
       	movlw	0xF8          	 	;Test for mid message MIDI CLOCK.
      	subwf 	rxbuffer,w
      	btfsc 	status,zero
       	goto  	midi_clk			;Re read after MIDI clock.
noteNumber     
		btfsc	rxbuffer,7			;Check for valid NOTE NUMBER byte by testing if bit 7 is zero.
      	goto  	serialRead
		movf	rxbuffer,w
		movwf	noteValue	
midi_clk2       
		call    receive	        	;3rd byte the VELOCITY.						
     	movlw 	0xF8           		;Test for mid message midi clock.
       	subwf  	rxbuffer,w
      	btfsc 	status,zero
     	goto 	midi_clk2			;Re read after MIDI clock.
velocityNumber
		btfsc	rxbuffer,7			;Check for valid NOTE NUMBER byte by testing bit 7 is zero.
		goto 	serialRead
		movf	rxbuffer,w
		movwf	velocityState		;Save velocity value for later.
NoteOn
		movlw	0x90				;Test for NOTE ON, CHANNEL 1 value.
		subwf	keyPressState,w
		btfss	status,zero
		goto	NoteOff
noteOnVelocity
		movlw	0x00
		subwf	velocityState,w		
		btfsc	status,zero			
		goto	setNoteOff			;If a NOTE ON value with a velocity of zero then just send out a simplified NOTE OFF message.	
		movf	noteValue,w
		movwf	txbuffer
		bsf		txbuffer,7			;Send a simplified NOTE ON message.
		call	transmit
		goto	serialRead
NoteOff								
		movlw	0x80
		subwf	keyPressState,w		;Check for NOTE OFF.
		btfss	status,zero
		goto	serialRead			;If this ever happens an error occured somehow.
setNoteOff
		movf	noteValue,w
		movwf	txbuffer
		bcf		txbuffer,7			;Send a simplified NOTE OFF message.
		call	transmit
		goto	serialRead
		
serial_init
		Bank1						;select bank 1
		movlw	0xC0				;set tris bits for TX and RX
		iorwf	TRISC,F
		movlw	SPBRG_VAL			;set baud rate
		movwf	SPBRG
		movlw	0x24				;enable transmission and high baud rate
		movwf	TXSTA
		Bank0						;select bank 0
		movlw	0x90				;enable serial port and reception
		movwf	RCSTA
		clrf	Flags				;clear all flags
		return

;Check if data received and if so, return it in the working register.
receive	
		Bank0						;select bank 0
		btfss	PIR1,RCIF			;check if data
		goto	$-1					;Wait until byte recieved

		btfsc	RCSTA,OERR			;if overrun error occurred
		goto	ErrSerialOverr		; then go handle error
		btfsc	RCSTA,FERR			;if framing error occurred
		goto	ErrSerialFrame		; then go handle error

		movf	RCREG,W				;get received data
		bsf		Flags,newData 		;indicate new data received
		movwf	rxbuffer
		return

;error because OERR overrun error bit is set
;can do special error handling here - this code simply clears and continues
ErrSerialOverr
		bcf		RCSTA,CREN		;reset the receiver logic
		bsf		RCSTA,CREN		;enable reception again
		return

;error because FERR framing error bit is set
;can do special error handling here - this code simply clears and continues
ErrSerialFrame	
		movf	RCREG,W			;discard received data that has error
		return

;Transmit data in WREG when the transmit register is empty.
transmit	
		Bank0					;select bank 0
		btfss	PIR1,TXIF		;check if transmitter busy
		goto	$-1				;wait until transmitter is not busy
		movf 	txbuffer,w
		movwf	TXREG			;and transmit the data
		return


		END