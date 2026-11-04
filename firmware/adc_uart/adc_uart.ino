#include <avr/io.h>
#include <avr/interrupt.h>

#ifndef F_CPU
#define F_CPU 16000000UL
#endif

#define BAUD 115200UL
#define BUFFER_SIZE 1024U
#define SAMPLE_RATE 4000U
#define DISCARDED_READS 16U

// Variáveis globais usadas pelas interrupções
static volatile uint8_t sampling_buffer[BUFFER_SIZE];
static volatile uint16_t write_idx = 0;
static volatile uint16_t read_idx = 0;
static volatile uint8_t buffer_overrun = 0;

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

  // habilita apenas o transmissor (TX)
  UCSR0B = (1 << TXEN0);
}

// transmissão por polling: só deve ser usada quando o ISR da UART não está
// ativo, para que exista um único escritor em UDR0
uint8_t UART0_Transmit(unsigned char data) {
  while (!(UCSR0A & (1 << UDRE0)));

  UDR0 = data;
  return 1;
}

// transmite uma string completa (também por polling)
void UART0_Print(const char* str) {
  while (*str) {
      UART0_Transmit(*str++);
  }
}

// inicializa o ADC
void ADC_Init(uint8_t channel) {
  channel &= 0b1111;  // canais 0 a 15

  // REFS1:0 = 11: referência interna de 2,56 V
  // ADLAR = 1: resultado justificado à esquerda, os 8 bits mais significativos ficam em ADCH
  // MUX2:0: três bits menos significativos do canal
  ADMUX = (1 << REFS1) | (1 << REFS0) | (1 << ADLAR) | (channel & 0b111);

  // MUX5 = 1 seleciona os canais 8 a 15
  if (channel & 0b1000) {
      ADCSRB |= (1 << MUX5);
  } else {
      ADCSRB &= ~(1 << MUX5);
  }

  // ADEN = 1: liga o ADC
  // ADPS2:0 = 100: prescaler 16, ou seja, clock do ADC de 1 MHz
  ADCSRA = (1 << ADEN) | (1 << ADPS2);

  // desabilita o buffer digital do pino do canal escolhido
  if (channel > 8) {
      DIDR0 |= (1 << channel);
  } else {
      DIDR2 |= (1 << (channel - 8));
  }
}

uint8_t ADC_Read(void) {
  // inicia a conversão
  ADCSRA |= (1 << ADSC);

  // aguarda a conversão terminar
  while (ADCSRA & (1 << ADSC));

  return ADCH;
}

void Timer1_Init(void) {
  TCCR1A = 0;
  TCCR1B = 0;
  TCNT1 = 0;

  // período da amostragem: (OCR1A + 1) * prescaler / F_CPU, com prescaler 8
  // F_CPU / (8 * 2000) =  1000
  OCR1A = (F_CPU / (8UL * SAMPLE_RATE)) - 1;

  // limpa interrupção pendente
  TIFR1 = (1 << OCF1A);

  // habilita interrupção por comparação A
  TIMSK1 = (1 << OCIE1A);

  // modo CTC (WGM12 = 1) e prescaler 8 (CS11 = 1)
  TCCR1B = (1 << WGM12) | (1 << CS11);
}

// Executada a cada período de amostragem
ISR(TIMER1_COMPA_vect) {
  uint8_t sample = ADC_Read();

  uint16_t next = write_idx + 1;
  if (next >= BUFFER_SIZE) {
      next = 0;
  }

  // buffer cheio: avançar write_idx o faria alcançar read_idx
  if (next == read_idx) {
      // a amostra foi perdida e a captura deixa de ser válida.
      // para a amostragem (desliga a interrupção do Timer1) e avisa o loop()
      buffer_overrun = 1;
      TIMSK1 &= ~(1 << OCIE1A);
      return;
  }

  sampling_buffer[write_idx] = sample;
  write_idx = next;

  // habilita o envio por interrupção
  UCSR0B |= (1 << UDRIE0);
}

// executada quando UDR0 está disponível para outro byte
ISR(USART0_UDRE_vect) {
  if (read_idx == write_idx) {
      // sem dados: desliga a interrupção de transmissão
      UCSR0B &= ~(1 << UDRIE0);
      return;
  }

  UDR0 = sampling_buffer[read_idx];

  read_idx++;
  if (read_idx >= BUFFER_SIZE) {
      read_idx = 0;
  }
}

void setup(void) {
  cli();
  ADC_Init(0);
  UART0_Init();

  for (uint8_t i = 0; i < DISCARDED_READS; i++) {
    ADC_Read();
  }

  Timer1_Init();
  sei();
}

void loop(void) {
  if (buffer_overrun) {
    // o Timer1 já foi desligado. espera o ISR da UART esvaziar o buffer,
    // depois disso o loop passa a ser o único escritor em UDR0
    while (read_idx != write_idx);

    UART0_Print("\nPERDA\n");

    // captura inválida: fica parado até o reset
    while (1);
  }
}