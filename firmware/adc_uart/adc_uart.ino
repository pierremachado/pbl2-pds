#include <avr/io.h>
#include <avr/interrupt.h>

#ifndef F_CPU
#define F_CPU 16000000UL
#endif

#define BAUD 115200UL
#define MAX_BUFFER_SIZE 6144U
// fs > 512*f, com f >= 1 Hz e fs inteiro
#define MIN_SAMPLE_RATE 513U
#define DISCARDED_READS 16U
// margem em ciclos de CPU para entrada, saída e trabalho da ISR fora do ADC
#define ISR_BUDGET_CYCLES 256UL

// códigos de status enviados ao Octave antes do bloco de amostras
#define STATUS_OK          0x00U
#define STATUS_ERR_PARAM   0x01U
#define STATUS_ERR_OVERRUN 0x02U

// buffer em RAM para armazenar o bloco completo antes do envio (Store-and-Forward)
static uint8_t sampling_buffer[MAX_BUFFER_SIZE];
static uint16_t target_samples = 4096U;
static uint16_t write_idx = 0;
static volatile uint8_t capture_done = 0;
static volatile uint8_t capture_error = 0;

// inicializa o uart
void UART0_Init(void) {
  // modo de velocidade dupla (U2X0 = 1): o divisor do baud rate passa de 16 para 8
  UCSR0A = (1 << U2X0);

  // baud rate: UBRR = F_CPU / (8 * BAUD) - 1 (fórmula do datasheet para U2X0 = 1)
  // para 115200 baud o resultado é 16, que gera 117647 baud (erro de +2,1%)
  uint16_t ubrr_val = (F_CPU / (8UL * BAUD)) - 1;
  UBRR0H = (uint8_t)(ubrr_val >> 8);
  UBRR0L = (uint8_t)(ubrr_val);

  // formato do frame: assíncrono, 8 bits de dados, sem paridade, 1 stop bit (8N1)
  UCSR0C = (1 << UCSZ01) | (1 << UCSZ00);

  // habilita receptor (RX para receber configuração/gatilho) e transmissor (TX)
  UCSR0B = (1 << RXEN0) | (1 << TXEN0);
}

// transmite um byte por polling
void UART0_Transmit(uint8_t data) {
  while (!(UCSR0A & (1 << UDRE0)));
  UDR0 = data;
}

// recebe um byte pela UART por polling
uint8_t UART0_Receive(void) {
  while (!(UCSR0A & (1 << RXC0)));
  return UDR0;
}

// recebe um inteiro de 16 bits (little-endian) pela UART
uint16_t UART0_Receive16(void) {
  uint8_t low = UART0_Receive();
  uint8_t high = UART0_Receive();
  return (uint16_t)low | ((uint16_t)high << 8);
}

// inicializa o ADC
void ADC_Init(uint8_t channel) {
  channel &= 0b1111;  // canais 0 a 15

  // REFS1:0 = 11: referência interna de 2,56 V
  // ADLAR = 1: resultado justificado à esquerda, os 8 bits mais significativos ficam em ADCH
  // MUX2:0: três bits menos significativos do canal
  ADMUX = (1 << REFS1) | (1 << REFS0) | (1 << ADLAR) | (channel & 0b111);

  // limpa ADCSRB (ADTS2:0 = 000, ACME = 0) e define MUX5 = 1 para canais 8 a 15
  ADCSRB = (channel & 0b1000) ? (1 << MUX5) : 0;

  // ADEN = 1: liga o ADC com prescaler inicial 16 (1 MHz)
  ADCSRA = (1 << ADEN) | (1 << ADPS2);

  // desabilita apenas o buffer digital do pino do canal escolhido
  DIDR0 = (channel < 8) ? (1 << channel) : 0;
  DIDR2 = (channel >= 8) ? (1 << (channel - 8)) : 0;
}

uint8_t ADC_Read(void) {
  // inicia a conversão
  ADCSRA |= (1 << ADSC);

  // aguarda a conversão terminar
  while (ADCSRA & (1 << ADSC));

  return ADCH;
}

// configura o prescaler do ADC (16, 32, 64 ou 128) apenas se mudar
void ADC_SetPrescaler(uint8_t prescaler) {
  static uint8_t current_prescaler = 16;
  if (prescaler == current_prescaler) {
    return;
  }

  uint8_t adps_bits;
  switch (prescaler) {
    case 16:  adps_bits = (1 << ADPS2); break;
    case 32:  adps_bits = (1 << ADPS2) | (1 << ADPS0); break;
    case 64:  adps_bits = (1 << ADPS2) | (1 << ADPS1); break;
    case 128: adps_bits = (1 << ADPS2) | (1 << ADPS1) | (1 << ADPS0); break;
    default:  return;  // o comando já deve ter sido rejeitado
  }

  ADCSRA = (ADCSRA & ~((1 << ADPS2) | (1 << ADPS1) | (1 << ADPS0))) | adps_bits;
  current_prescaler = prescaler;

  for (uint8_t i = 0; i < DISCARDED_READS; i++) {
    ADC_Read();
  }
}

// retorna 1 para parâmetros válidos e 0 para erro, sem usar bool.
uint8_t Capture_Validate(uint8_t prescaler, uint16_t sample_rate,
                         uint16_t num_samples, uint16_t *timer_top) {
  if ((prescaler != 16 && prescaler != 32 &&
       prescaler != 64 && prescaler != 128) ||
      sample_rate < MIN_SAMPLE_RATE ||
      num_samples == 0 || num_samples > MAX_BUFFER_SIZE) {
    return 0;
  }

  const uint32_t ticks =
      (F_CPU + 4UL * sample_rate) / (8UL * sample_rate);
  if (ticks == 0 || ticks > 65536UL) {
    return 0;
  }

  // 13 clocks por conversão normal + até 1 para alinhamento do início
  // a primeira conversão (25 clocks) já foi descartada antes da captura
  const uint32_t required_cycles = 14UL * prescaler + ISR_BUDGET_CYCLES;
  if (ticks * 8UL <= required_cycles) {
    return 0;
  }

  *timer_top = (uint16_t)(ticks - 1UL);
  return 1;
}

void Timer1_Start(uint16_t timer_top) {
  TCCR1A = 0;
  TCCR1B = 0;
  TCNT1 = 0;

  // período previamente arredondado e validado, com prescaler 8
  OCR1A = timer_top;

  // limpa interrupção pendente
  TIFR1 = (1 << OCF1A);

  // habilita interrupção por comparação A
  TIMSK1 = (1 << OCIE1A);

  // modo CTC (WGM12 = 1) e prescaler 8 (CS11 = 1)
  TCCR1B = (1 << WGM12) | (1 << CS11);
}

// executada a cada período de amostragem (sem concorrência da UART)
ISR(TIMER1_COMPA_vect) {
  uint8_t sample = ADC_Read();

  uint16_t idx = write_idx;
  sampling_buffer[idx++] = sample;
  write_idx = idx;

  if (TIFR1 & (1 << OCF1A)) {
      TIMSK1 &= ~(1 << OCIE1A);
      TCCR1B = 0;
      capture_error = 1;
      capture_done = 1;
      return;
  }

  if (idx >= target_samples) {
      // bloco completo: para o Timer1 e sinaliza o fim da captura para o loop()
      TIMSK1 &= ~(1 << OCIE1A);
      TCCR1B = 0;
      capture_done = 1;
  }
}

void setup(void) {
  // cli(): limpa o bit I de SREG, bloqueando globalmente as interrupções
  // os periféricos continuam funcionando e podem acumular flags pendentes
  cli();
  TIMSK0 = 0;  // desabilita o Timer0 do Arduino (millis) para evitar jitter na amostragem
  ADC_Init(0);
  UART0_Init();

  for (uint8_t i = 0; i < DISCARDED_READS; i++) {
    ADC_Read();
  }

  // sei(): seta I em SREG; permite interrupções habilitadas nos periféricos
  sei();
}

void loop(void) {
  // aguarda pacote de 5 bytes do Octave:
  //    - 1 byte (uint8):   prescaler do ADC (16, 32, 64 ou 128)
  //    - 2 bytes (uint16): frequência de amostragem fs em Hz
  //    - 2 bytes (uint16): quantidade de amostras a capturar
  uint8_t prescaler = UART0_Receive();
  uint16_t sample_rate = UART0_Receive16();
  uint16_t num_samples = UART0_Receive16();

  uint16_t timer_top;
  if (!Capture_Validate(prescaler, sample_rate, num_samples, &timer_top)) {
      UART0_Transmit(STATUS_ERR_PARAM);
      return;
  }

  // atualiza o prescaler (se mudou, descarta leituras iniciais para estabilizar)
  ADC_SetPrescaler(prescaler);

  // captura em RAM sem transmissão UART
  target_samples = num_samples;
  write_idx = 0;
  capture_error = 0;
  capture_done = 0;

  asm volatile("" ::: "memory");

  Timer1_Start(timer_top);
  while (!capture_done);

  asm volatile("" ::: "memory");

  // se detectou atraso da ISR, notifica erro ao script
  if (capture_error) {
      UART0_Transmit(STATUS_ERR_OVERRUN);
      return;
  }

  // envia byte de status OK seguido do bloco completo pela UART
  UART0_Transmit(STATUS_OK);
  for (uint16_t i = 0; i < num_samples; i++) {
      UART0_Transmit(sampling_buffer[i]);
  }
}
