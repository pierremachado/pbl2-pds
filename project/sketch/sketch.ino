#include <avr/io.h>
#include <avr/interrupt.h>

#ifndef
#define F_CPU 16000000UL
#endif

#define BAUD 9600
#define BUFFER_SIZE 4096

static uint8_t adc_buffer[BUFFER_SIZE];
static volatile uint16_t buffer_index = 0;
static volatile uint8_t buffer_full = 0;

void UART0_Init(void) {
    unsigned int ubrr_val = (F_CPU / (16UL * BAUD)) - 1;

    // Define a velocidade (divide em parte alta e baixa)
    UBRR0H = (unsigned char)(ubrr_val >> 8);
    UBRR0L = (unsigned char)(ubrr_val);

    UCSR0B = (1 << TXEN0); // Habilita TX
    UCSR0C = (1 << UCSZ01) | (1 << UCSZ00); // 8N1
}

void ADC_Init(void) {
    // Configuração do ADC
    // Referência AVcc (REFS0=1), Alinhamento à esquerda de 8 bits (ADLAR=1), Canal A0 (MUX=00000)
    ADMUX = (1 << REFS0) | (1 << ADLAR);

    // Habilita ADC (ADEN), Disparo Automático (ADATE), Interrupção ADC (ADIE)
    // Prescaler do ADC = 16 (ADPS2=1 -> Clock ADC = 1 MHz, conversão rápida de 13 us)
    ADCSRA = (1 << ADEN) | (1 << ADATE) | (1 << ADIE) | (1 << ADPS2);

    // Fonte de disparo automático = Compare Match B do Timer 1 (ADTS2:0 = 101)
    ADCSRB = (1 << ADTS2) | (1 << ADTS0);

    // Desabilita buffer digital do pino A0 (ADC0)
    DIDR0 |= (1 << ADC0D);
}

void Timer1_Init(void) {
    // Configuração do Timer 1 (CTC) para f_amostragem = 15,38 kSPS (~60 Hz / 2 ciclos em 512 amostras)
    TCCR1A = 0; 
    TCCR1B = (1 << WGM12) | (1 << CS11); // Modo CTC (WGM12=1), Prescaler = 8 (CS11=1)
    OCR1A = 129;                         // Periodo = 8 * 130 / 16MHz = 65 us
}

// Rotina de Interrupção da Conversão A/D (executada em segundo plano)
ISR(ADC_vect) {
    if (!buffer_full) {
        adc_buffer[buffer_index++] = ADCH; // Leitura do byte de 8 bits
        if (buffer_index >= BUFFER_SIZE) {
            buffer_full = 1;
        }
    }
}

void UART0_Transmit(uint8_t data) {
    while (!(UCSR0A & (1 << UDRE0)));
    UDR0 = data;
}

void setup(void) {
    UART0_Init();
    ADC_Init();
    Timer1_Init();
    sei(); // Habilita interrupções globais
}

void loop(void) {
    if (buffer_full) {
        // Envia o buffer completo via UART
        for (uint16_t i = 0; i < BUFFER_SIZE; i++) {
            UART0_Transmit(adc_buffer[i]);
        }

        // Reinicia a captura para o próximo bloco
        buffer_index = 0;
        buffer_full = 0;
    }
}