# Caracterização do ADC SAR do ATmega2560

**TEC513 · Processamento Digital de Sinais · UEFS · Problema 02**

Implementação e caracterização experimental do conversor analógico-digital (ADC) de **8 bits** do **ATmega2560 (Arduino Mega 2560)**, com controle direto dos registradores AVR, aquisição temporizada e análise dos dados no GNU Octave.

O projeto investiga a resolução, os limites de amostragem, os erros de conversão e o comportamento do ADC sob diferentes condições de ensaio, comparando resultados teóricos e experimentais.

## Visão geral

```text
Gerador de funções → ADC SAR (ATmega2560) → Buffer em RAM (4.096 amostras)
                                                 ↓
                                         UART0 / USB (lote)
                                                 ↓
                                    GNU Octave → análise e gráficos
```

O firmware usa o **Timer1 em modo CTC** para cadenciar as conversões. As amostras são armazenadas na RAM e **transmitidas apenas após o término da captura** (*store-and-forward*), evitando que a transmissão UART interfira diretamente na aquisição.

| Parâmetro | Configuração utilizada |
| :--- | :--- |
| Microcontrolador | ATmega2560, clock de 16 MHz |
| ADC | SAR interno, leitura de 8 bits via `ADLAR` e `ADCH` |
| Referência | Interna de 2,56 V (nominal); aproximadamente 2,31 V (estimada experimentalmente) |
| Clock do ADC | 1 MHz (`prescaler = 16`) |
| Taxa máxima de amostragem configurada | Aproximadamente **32,79 kHz** |
| Captura | Blocos de **4.096 amostras** |
| Comunicação | UART0 a 115.200 baud, modo `U2X0`, quadro 8N1 |
| Processamento | GNU Octave, com ensaios inspirados na IEEE Std 1241 |

## Resultados principais

Foram preservadas **35 capturas**, organizadas em **13 ensaios principais**, **4 contraexemplos didáticos** e **18 repetições**. Os intervalos abaixo resumem os 13 ensaios principais, conforme a tabela experimental do projeto.

| Métrica | Resultado observado |
| :--- | :--- |
| Erro RMS residual após ajuste | **0,34 a 0,46 LSB** |
| ENOB estimado após ajuste | **7,26 a 7,70 bits** |
| Faixa dinâmica (DR) estimada | **46,4 a 48,3 dB** |
| Códigos ausentes nos 13 ensaios principais | **0** (pelo método de análise utilizado) |
| Referência interna efetiva estimada | **≈ 2,31 V**, frente a 2,56 V nominais |

Os contraexemplos exploram saturação por desvio da tensão de referência, quantidade insuficiente de amostras por rampa, janela inferior a um ciclo e ocorrência de *missing code* em uma captura. As métricas de ENOB e DR foram obtidas com **tratamento específico para o sinal triangular**, conforme descrito no analisador, e não equivalem automaticamente a um ensaio senoidal padronizado.

## Estrutura do repositório

```text
firmware/adc_uart/adc_uart.ino       # Timer1 + ADC + UART0

tools/octave/uart_capture.m          # Aquisição UART e gravação do .mat essencial
tools/octave/uart_oscilloscope.m     # Osciloscópio leve de bancada em tempo real
tools/octave/adc_analyzer.m          # Orquestrador de condicionamento e análise (GUI / Batch)
tools/octave/src/                    # Núcleo matemático modular (triggering, conditioning, spectral, linearity)
tools/octave/utils/                  # Utilitários de integração, I/O, dashboard GUI e figuras comparativas
tools/octave/data/                   # Capturas .mat
tools/octave/outputs/                # Gráficos e métricas exportadas

data/oscilloscope/                   # Registros de bancada (.BMP)
docs/datasheets/                     # Documentação do hardware
docs/presentation/                   # Apresentação em LaTeX/Beamer
docs/reports/relatorio_tecnico.md    # Relatório técnico em Markdown
docs/reports/relatorio_tecnico.html  # Fundamentação e resultados completos (HTML)
```

## Como executar

No **GNU Octave**, a partir da raiz do repositório:

```octave
addpath("tools/octave");

adc_analyzer()                                    % Abrir o painel de análise
adc_analyzer("adc_f05Hz_fs04000Hz_pre16.mat")    % Inspecionar uma captura
adc_analyzer("batch")                           % Processar os ensaios em lote
uart_oscilloscope                                % Nova aquisição: requer placa conectada
```

Para fazer novas aquisições, grave antes `firmware/adc_uart/adc_uart.ino` no Arduino Mega 2560 e conecte a placa à porta serial configurada nos scripts. Para analisar os arquivos `.mat` já coletados, não é necessário conectar o hardware.