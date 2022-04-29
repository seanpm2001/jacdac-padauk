#ifdef BTN_SECOND
#define SERVICE_CLASS2 0x1473a263
#define SENSOR_SIZE2 2
#define SERV_NUM 2
.sensor_set_service2 EXPAND
	inc pkt_service_number
ENDM
#if !CFG_DUAL_SERVICE
#error "need dual service!"
#endif
#else
// single-service
#define SERVICE_CLASS 0x1473a263
#define SENSOR_SIZE 2
#define SERV_NUM
#endif

#ifdef PIN_BTN
#define PIN_BTN_PH PAPH.PIN_BTN
#define PIN_BTN_RD PA.PIN_BTN
#endif

#define JD_BUTTON_EV_DOWN 0x01
#define JD_BUTTON_EV_UP 0x02
#define JD_BUTTON_EV_HOLD 0x81

#define JD_LED_REG_RO_ANALOG 0x80

#ifdef BTN_SECOND
txp_analog_button equ tx_pending2.0
txp_streaming_samples2 equ tx_pending2.1
txp_streaming_interval2 equ tx_pending2.2
txp_reading2 equ tx_pending2.3
#else
txp_analog_button equ txp_serv0
#endif


	BYTE	t_sample
	BYTE    t_btn_hold
	BYTE    btn_down_l
	BYTE    btn_down_h
	BYTE    ev_code

	.sensor_impl SERV_NUM

.serv_init#SERV_NUM EXPAND
	PIN_BTN_PH = 1 // pullup on btn
	.mova streaming_interval, 100
ENDM

.serv_process#SERV_NUM EXPAND
	.ev_process
	.t16_chk t16_1ms, t_sample, <goto do_sample>
	.sensor_process SERV_NUM
ENDM

.serv_prep_tx#SERV_NUM EXPAND
	if (txp_analog_button) {
		set0 txp_analog_button
		.sensor_set_service#SERV_NUM
		clear pkt_payload[0]
		.mova pkt_size, 1
		.mova pkt_service_command_l, JD_LED_REG_RO_ANALOG
		ret
	}

	ifset txp_event
		goto ev_prep_tx

	.sensor_prep_tx SERV_NUM
ENDM

do_sample:
	.t16_set t16_1ms, t_sample, 20
	mov a, sensor_state#SERV_NUM[0]
	ifclear PIN_BTN_RD
		goto button_active
button_inactive:
	ifset ZF // state==0
		goto loop // just keep going
	clear sensor_state#SERV_NUM[0]
	clear sensor_state#SERV_NUM[1]

		// snapshot duration
		mov a, t16_1ms
		sub a, btn_down_l
		mov btn_down_l, a
		mov a, t16_262ms
		subc a, btn_down_h
		mov btn_down_h, a

	mov a, JD_BUTTON_EV_UP
	goto ev_send_btn
button_active:
	ifset ZF
		goto button_down
	.t16_chk t16_16ms, t_btn_hold, <goto button_hold>
	goto loop
button_hold:
	.t16_set t16_16ms, t_btn_hold, 31
	mov a, JD_BUTTON_EV_HOLD
	goto ev_send_btn
button_down:
	.mova sensor_state#SERV_NUM[0], 0xff
	.mova sensor_state#SERV_NUM[1], 0xff
	.disint
		.mova btn_down_l, t16_1ms
		.mova btn_down_h, t16_262ms
	engint
	.t16_set t16_16ms, t_btn_hold, 31
	mov a, JD_BUTTON_EV_DOWN
	goto ev_send_btn

serv_rx#SERV_NUM:
	mov a, pkt_service_command_h
	if (a == JD_HIGH_REG_RO_GET) {
		mov a, pkt_service_command_l
		.reg_cmp JD_LED_REG_RO_ANALOG, txp_analog_button
	}
	.sensor_rx SERV_NUM

.serv_ev_payload EXPAND
	.mova pkt_size, 4
	.sensor_set_service#SERV_NUM
	mov a, ev_code
	mov pkt_service_command_l, a
	if (a == JD_BUTTON_EV_DOWN) {
		clear pkt_size // down event doesn't have payload
	} else if (a == JD_BUTTON_EV_UP) {
		// we snapshot final duration when emitting up
		.mova pkt_payload[0], btn_down_l
		.mova pkt_payload[1], btn_down_h
	} else {
		// hold events have duration computed on the fly
		mov a, t16_1ms
		sub a, btn_down_l
		mov pkt_payload[0], a
		mov a, t16_262ms
		subc a, btn_down_h
		mov pkt_payload[1], a
	}
ENDM

ev_send_btn:
	mov ev_code, a
	// this starts with ev_send
	.ev_impl
