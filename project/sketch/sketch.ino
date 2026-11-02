#define F_CPU 16000000UL

#include <avr/io.h>
#include <util/delay.h>
#include <stdlib.h>
#include <stdio.h>
#include <avr/interrupt.h>

#define BAUD 9600
#define BUFFER_SIZE 1024
#define SAMPLE_RATE 500UL

// Variáveis globais usadas pelas interrupções.
volatile uint8_t sampling_buffer[BUFFER_SIZE];

volatile uint16_t escrita = 0;
volatile uint16_t leitura = 0;
volatile uint16_t perdas = 0;

// Função para inicializar a UART0
void UART0_Init(unsigned int baudrate) {
    // Calcular o valor do registrador UBRR para o modo normal (Asynchronous Normal)
    // Fórmula do datasheet: UBRR = (F_CPU / (16 * Baud)) - 1
    unsigned int ubrr_val = (F_CPU / (16UL * baudrate)) - 1;
    
    // Define a velocidade (divide em parte alta e baixa)
    UBRR0H = (unsigned char)(ubrr_val >> 8);
    UBRR0L = (unsigned char)(ubrr_val);
    
    // Habilita o Transmissor (TX) e o Receptor (RX)
    UCSR0B = (1 << RXEN0) | (1 << TXEN0);
    
    // Configura o formato do frame: Assíncrono, Sem Paridade, 1 Stop Bit, 8 bits de dados (8N1)
    UCSR0C = (1 << UCSZ01) | (1 << UCSZ00);
}

uint8_t UART0_Transmit(unsigned char data) {
    while (!(UCSR0A & (1 << UDRE0)));

    UDR0 = data;
    return 1;
}

// Função para transmitir uma string completa
void UART0_Print(const char* str) {
    while (*str) {
        UART0_Transmit(*str++);
    }
}

// Inicializa o ADC
void ADC_Init(void) {
    // 1. Configura a Referência de Tensão para AVCC (5V no Arduino Mega)
    // REFS1 = 0, REFS0 = 1
    ADMUX = (1 << REFS0);
    
    // 2. Ativa o ADC e define o Prescaler para 128 (16MHz / 128 = 125kHz)
    // ADEN = 1 (Liga ADC)
    // ADPS2=1, ADPS1=1, ADPS0=1 (Prescaler 128)
    ADCSRA = (1 << ADEN) | (1 << ADPS2) | (1 << ADPS1) | (1 << ADPS0);
}

uint8_t ADC_Read(uint8_t canal) {
    canal &= 0x0F;

    // Referência interna de 2,56 V
    // Alinhamento à esquerda para leitura de 8 bits
    ADMUX = (1 << REFS1) | (1 << REFS0)
          | (1 << ADLAR) | (canal & 0x07);

    // Seleciona canais 0 a 15
    if (canal & 0x08) {
        ADCSRB |= (1 << MUX5);
    } else {
        ADCSRB &= ~(1 << MUX5);
    }

    // Inicia a conversão
    ADCSRA |= (1 << ADSC);

    // Aguarda a conversão terminar
    while (ADCSRA & (1 << ADSC));

    return ADCH;
}

void Timer1_Init(void) {
    // Para o timer durante a configuração.
    TCCR1A = 0;
    TCCR1B = 0;
    TCNT1 = 0;

    // 16 MHz / (64 * (499 + 1)) = 500 Hz
    OCR1A = (F_CPU / (64UL * SAMPLE_RATE)) - 1;

    // Limpa uma possível interrupção pendente.
    TIFR1 = (1 << OCF1A);

    // Habilita interrupção por comparação A.
    TIMSK1 = (1 << OCIE1A);

    // Modo CTC e prescaler de 64.
    TCCR1B = (1 << WGM12)
           | (1 << CS11)
           | (1 << CS10);
}

// Executada a cada 2 ms.
ISR(TIMER1_COMPA_vect) {
    uint8_t amostra = ADC_Read(0);

    uint16_t proxima = escrita + 1;
    if (proxima >= BUFFER_SIZE) {
        proxima = 0;
    }

    // Uma posição fica reservada para distinguir cheio de vazio.
    if (proxima == leitura) {
        perdas++;
        return;
    }

    sampling_buffer[escrita] = amostra;
    escrita = proxima;

    // Habilita o envio por interrupção.
    UCSR0B |= (1 << UDRIE0);
}

// Executada quando UDR0 está disponível para outro byte.
ISR(USART0_UDRE_vect) {
    if (leitura == escrita) {
        // Sem dados: desliga a interrupção de transmissão.
        UCSR0B &= ~(1 << UDRIE0);
        return;
    }

    UDR0 = sampling_buffer[leitura];

    leitura++;
    if (leitura >= BUFFER_SIZE) {
        leitura = 0;
    }
}

int main(void) {
    cli();

    ADC_Init();
    UART0_Init(BAUD);

    // Seleciona a referência interna e permite estabilização.
    ADC_Read(0);
    _delay_ms(2);
    ADC_Read(0);  // Descarta a leitura de preparação.

    Timer1_Init();
    sei();

    while (1) {
        // Captura e transmissão acontecem nas interrupções.
    }

    return 0;
}