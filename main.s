;****************** main.s ***************
; Program written by: Valvano, solution
; Date Created: 2/4/2017
; Last Modified: 1/17/2021
; Names: Miguel Gonzalez and Nicholas Richards
; UTEID: mag9688 and nar2797
; Brief description of the program
;   The LED toggles at 2 Hz and a varying duty-cycle
; Hardware connections (External: One button and one LED)
;  PE1 is Button input  (1 means pressed, 0 means not pressed)
;  PE2 is LED output (1 activates external LED on protoboard)
;  PF4 is builtin button SW1 on Launchpad (Internal) 
;        Negative Logic (0 means pressed, 1 means not pressed)
; Overall functionality of this system is to operate like this
;   1) Make PE2 an output and make PE1 and PF4 inputs.
;   2) The system starts with the the LED toggling at 2Hz,
;      which is 2 times per second with a duty-cycle of 30%.
;      Therefore, the LED is ON for 150ms and off for 350 ms.
;   3) When the button (PE1) is pressed-and-released increase
;      the duty cycle by 20% (modulo 100%). Therefore for each
;      press-and-release the duty cycle changes from 30% to 70% to 70%
;      to 90% to 10% to 30% so on
;   4) Implement a "breathing LED" when SW1 (PF4) on the Launchpad is pressed:
;      a) Be creative and play around with what "breathing" means.
;         An example of "breathing" is most computers power LED in sleep mode
;         (e.g., https://www.youtube.com/watch?v=ZT6siXyIjvQ).
;      b) When (PF4) is released while in breathing mode, resume blinking at 2Hz.
;         The duty cycle can either match the most recent duty-
;         cycle or reset to 30%.
;      TIP: debugging the breathing LED algorithm using the real board.
; PortE device registers
GPIO_PORTE_DATA_R  EQU 0x400243FC
GPIO_PORTE_DIR_R   EQU 0x40024400
GPIO_PORTE_AMSEL_R EQU 0x40024528
GPIO_PORTE_PCTL_R  EQU 0x4002452C
GPIO_PORTE_AFSEL_R EQU 0x40024420
GPIO_PORTE_DEN_R   EQU 0x4002451C
SYSCTL_RCGC2_GPIOE EQU 0x00000010  ; port E Clock Gating Control
; PortF device registers
GPIO_PORTF_DATA_R  EQU 0x400253FC
GPIO_PORTF_DIR_R   EQU 0x40025400
GPIO_PORTF_AFSEL_R EQU 0x40025420
GPIO_PORTF_PUR_R   EQU 0x40025510
GPIO_PORTF_DEN_R   EQU 0x4002551C
GPIO_PORTF_LOCK_R  EQU 0x40025520
GPIO_PORTF_CR_R    EQU 0x40025524
; Miscellaneous registers
GPIO_LOCK_KEY      EQU 0x4C4F434B  ; Unlocks the GPIO_CR register
SYSCTL_RCGCGPIO_R  EQU 0x400FE608
	
Count_breathing    EQU 0x1E1F ;7, 711
Count_50ms		   EQU 0xF422C  ;999, 980
Count_150ms 	   EQU 0x2DC684 ;2, 999, 940
Count_250ms		   EQU 0x4C4ADB ;4, 999, 899
Count_350ms		   EQU 0x6ACF33 ;6, 999, 859
Count_450ms        EQU 0x89538C ;8, 999, 820

       IMPORT  TExaS_Init
       THUMB
       AREA    DATA, ALIGN=2

;global variables
Switch_PE1 SPACE 1 ;this variable will hold previous state of the switch
Duty_Cycle SPACE 1 ;this variable will hold the duty cycle
Breathing_Status SPACE 1 ; this variable will control the duty cycle for the breathing state.

       AREA    |.text|, CODE, READONLY, ALIGN=2
       THUMB
       EXPORT  Start

Start
 ; TExaS_Init sets bus clock at 80 MHz
      BL  TExaS_Init 
; voltmeter, scope on PD3
 ; initialization
	  ; activate clock for PortE and PortF
	  LDR R0, =SYSCTL_RCGCGPIO_R      
	  LDR R1, [R0]                   
	  ORR R1, #0x30
	  STR R1, [R0]
	  ; allow time to finish activating
	  NOP		 ; 1
	  NOP	     ; 2
	  
	  ; set PF4 as input
      LDR R0, =GPIO_PORTF_DIR_R    
      LDRB R1, [R0]                
      BIC R1, #0x10
      STR R1, [R0]
      ; Set PE1 as input and set PE2 as Output
      LDR R0, =GPIO_PORTE_DIR_R    
      LDRB R1, [R0]
	  BIC R1, #0x02
      ORR R1, #0x04
      STR R1, [R0]               
      ; Digital enable PF4
      LDR R0, =GPIO_PORTF_DEN_R     
      LDR R1, [R0]    
	  ORR R1, #0x10    
      STR R1, [R0]
      ; Digital Enable PE1 and PE2
      LDR R0, =GPIO_PORTE_DEN_R    
      LDR R1, [R0]                 
      ORR R1, #0x06       
      STR R1, [R0]  	    
	  ; enable pull-up resister for PF4
      LDR R0, =GPIO_PORTF_PUR_R     
      LDR R1, [R0]                
      ORR R1, #0x10
      STR R1, [R0]
	  ; TExaS voltmeter, scope runs on interrupts
	  CPSIE  I
	  
	  LDR R0, = Duty_Cycle
	  MOV R1, #30
	  STRB R1, [R0]		;set duty cycle to start at 30%
	  
	  LDR R0, =GPIO_PORTE_DATA_R
	  LDRB R1, [R0]
	  AND R1, #0x02
	  LSR R1, #1
	  LDR R0, =Switch_PE1
	  STRB R1, [R0] ;set initial value of PE1 to variable "Switch_PE1"
	  
loop
; main engine
	LDR R0, =GPIO_PORTF_DATA_R
	LDRB R1,[R0]
	EOR R1, #0x10
	LSR R1, #4
	CMP R1, #1
	BEQ Breathing     ;Check to see if PF4 was pressed 
	
	LDR R0, =GPIO_PORTE_DATA_R
	LDRB R1, [R0]
	AND R1, #0x02
	LSR R1, #1 ; R1 holds the current state of the switch
	LDR R0, =Switch_PE1   
	LDRB R2, [R0]	; R2 holds the previous state of switch
	CMP R1, R2
	BHI updateSwitch ;If current state is higher than previous state (button just got pressed)
	BLO updateDutyCycle ;If current state is lower than previous state (then button was released)
	CMP R1, #0
	BEQ CheckDutyCycle ;If current state is 0 then the button was not pressed so continue checking
	B loop ;If button is still pressed then loop back

Breathing
	MOV R1, #36 ;R1 will update the loop counter
	MOV R2, #36	; R2 holds the loop counter
	MOV R3, #2 	;R3 will update the 2nd loop counter
	MOV R4, #2 ;R4 holds the 2nd loop counter

Breathing1
	LDR R0, =GPIO_PORTF_DATA_R
	LDRB R7, [R0]
	EOR R7, #0x10
	LSR R7, #4
	CMP R7, #0
	BEQ loop     ;If PF4 is not pressed then go back to main loop
	
	MOV R2, R1    ;update the loop counter
	MOV R4, R3    ; update the second loop counter
	LDR R0, =GPIO_PORTE_DATA_R
	LDRB R7, [R0]
	EOR R7, #0x04 
	STRB R7, [R0]	;toggle the LED on

wait11
	LDR R0, =Count_breathing
wait10
	SUBS R0, R0, #1 ;delay for set time
	BNE wait10
	SUBS R2, #1
	BNE wait11 ;continue delay until loop counter finished
	LDR R0, =GPIO_PORTE_DATA_R
	LDRB R7, [R0]
	BIC R7, #0x04
	STRB R7, [R0] ;toggle the LED off
wait13
	LDR R0, =Count_breathing
wait12
	SUBS R0, R0, #1 ; delay for set time
	BNE wait12
	SUBS R4, #1
	BNE wait13	;continue delay until loop counter finished
	
	CMP R1, #1
	BEQ changeStatus ;if R1 Reach 1 then change status of LED
	CMP R3, #1
	BEQ changeStatus ;if R3 reach 1 then change status of LED
	
Check1
	LDR R0, =Breathing_Status
	LDRB R0, [R0] ;get the current status of the LED
	CMP R0, #1
	BEQ updateBreathing ;if R1, R2 needs to increment
	SUB R1, #1 ;decrement R1 by 1
	ADD R3, #1 ;increament R3 by 1
	B Breathing1
updateBreathing
	SUB R3, #1 ;decrement R3 by 1 
	ADD R1, #1 ; increment R1 by 1
	B Breathing1

;change the status of the Breathing loop
changeStatus
	LDR R0, =Breathing_Status
	LDRB R5, [R0]
	EOR R5, #0x01
	STRB R5, [R0]
	B Check1

;update the variable "Switch_PE1"
updateSwitch
	LDR R0, =GPIO_PORTE_DATA_R
	LDRB R1, [R0]
	AND R1, #0x02
	LSR R1, #1
	LDR R0, =Switch_PE1
	STRB R1, [R0]
	B loop

;update the duty cycle when the buttion is released
updateDutyCycle
	LDR R0, =GPIO_PORTE_DATA_R
	LDRB R1, [R0]
	AND R1, #0x02
	LSR R1, #1
	LDR R0, =Switch_PE1
	STRB R1, [R0] ;update the variable Switch_PE1
	LDR R0, =Duty_Cycle
	LDRB R1, [R0]
	CMP R1, #90 ;if the duty cycle is at 90% change back to 10%
	BEQ update10
	ADD R1, R1, #20 ;increase duty cycle by 20%
	STRB R1, [R0]
	B CheckDutyCycle
update10
	MOV R1, #10
	STRB R1, [R0] ;update the duty cycle from 90% to 10%

CheckDutyCycle
	LDR R0, =Duty_Cycle
	LDRB R1, [R0]
	CMP R1, #10 ;check if duty cycle is 10
	BEQ duty_10
	CMP R1, #30 ;check if duty cycle is 30
	BEQ duty_30
	CMP R1, #50 ;check if duty cycle is 50
	BEQ duty_50
	CMP R1, #70 ;check if duty cycle is 70
	BEQ duty_70
	CMP R1, #90 ;check if duty cycle is 90
	BEQ duty_90

;if duty cycle is 10%, on for 50ms and off for 450ms
duty_10
	LDR R0, =GPIO_PORTE_DATA_R
	LDRB R1, [R0]
	EOR R1, #0x04
	STRB R1, [R0]
	LDR R0, =Count_50ms
wait
	SUBS R0, R0, #1
	BNE wait 
	LDR R0, =GPIO_PORTE_DATA_R
	LDRB R1, [R0]
	BIC R1, #0x04
	STRB R1, [R0]
	LDR R0, =Count_450ms
wait1
	SUBS R0, R0, #1
	BNE wait1
	B loop

;if duty cycle is 30%, on for 150ms and off for 350ms
duty_30
	LDR R0, =GPIO_PORTE_DATA_R
	LDRB R1, [R0]
	EOR R1, #0x04
	STRB R1, [R0]
	LDR R0, =Count_150ms
wait2
	SUBS R0, R0, #1
	BNE wait2
	LDR R0, =GPIO_PORTE_DATA_R
	LDRB R1, [R0]
	BIC R1, #0x04
	STRB R1, [R0]
	LDR R0, =Count_350ms
wait3
	SUBS R0, R0, #1
	BNE wait3
	B loop

;if duty cycle is 50%, on for 250ms and off for 250ms
duty_50
	LDR R0, =GPIO_PORTE_DATA_R
	LDRB R1, [R0]
	EOR R1, #0x04
	STRB R1, [R0]
	LDR R0, =Count_250ms
wait4
	SUBS R0, R0, #1
	BNE wait4
	LDR R0, =GPIO_PORTE_DATA_R
	LDRB R1, [R0]
	BIC R1, #0x04
	STRB R1, [R0]
	LDR R0, =Count_250ms
wait5
	SUBS R0, R0,#1
	BNE wait5
	B loop

;if duty cycle is 70%, on for 350ms and off for 150ms
duty_70
	LDR R0, =GPIO_PORTE_DATA_R
	LDRB R1, [R0]
	EOR R1, #0x04
	STRB R1, [R0]
	LDR R0, =Count_350ms
wait6
	SUBS R0, R0, #1
	BNE wait6
	LDR R0, =GPIO_PORTE_DATA_R
	LDRB R1, [R0]
	BIC R1, #0x04
	STRB R1, [R0]
	LDR R0, =Count_150ms
wait7
	SUBS R0, R0, #1
	BNE wait7
	B loop

;if duty cycle is 90%, on for 450ms and off for 50ms
duty_90
	LDR R0, =GPIO_PORTE_DATA_R
	LDRB R1, [R0]
	EOR R1, #0x04
	STRB R1, [R0]
	LDR R0, =Count_450ms
wait8
	SUBS R0, R0, #1
	BNE wait8
	LDR R0, =GPIO_PORTE_DATA_R
	LDRB R1, [R0]
	BIC R1, #0x04
	STRB R1, [R0]
	LDR R0, =Count_50ms
wait9
	SUBS R0, R0, #1
	BNE wait9
	B loop


    ALIGN      ; make sure the end of this section is aligned
    
	END        ; end of file