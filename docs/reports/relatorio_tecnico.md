# Caracterização e Análise do Conversor A/D (SAR) do ATmega2560

Projeto de implementação em nível de registradores, aquisição determinística e análise estática/dinâmica da conversão Analógica-Digital (A/D) de 8 bits no microcontrolador **ATmega2560** (Arduino Mega 2560), desenvolvido para o **Problema 02 da disciplina TEC513 — Processamento Digital de Sinais (UEFS)**.

---

## Sumário

1. [Arquitetura e Estrutura do Repositório](#1-arquitetura-e-estrutura-do-repositório)
2. [Fundamentação Teórica e Especificações do Datasheet (ATmega2560)](#2-fundamentação-teórica-e-especificações-do-datasheet-atmega2560)
3. [Cálculos Teóricos vs. Práticos ($f_s$, $f_{\text{sinal}}$, UART U2X0, Buffer de 4096 Amostras e Firmware `.ino`)](#3-cálculos-teóricos-vs-práticos-f_s-f_textsinal-uart-u2x0-buffer-de-4096-amostras-e-firmware-ino)
4. [Metodologia de Ensaio com Referência à IEEE Std 1241](#4-metodologia-de-ensaio-com-referência-à-ieee-std-1241)
5. [Calibração com Osciloscópio de Bancada: Estimativa de $V_{\text{ref}}$ e o Erro de Ganho/Offset](#5-calibração-com-osciloscópio-de-bancada-estimativa-de-v_textref-e-o-erro-de-ganhooffset)
6. [Organização dos Dados e Resultados Experimentais](#6-organização-dos-dados-e-resultados-experimentais)
7. [Principais Conclusões Físicas e de Engenharia](#7-principais-conclusões-físicas-e-de-engenharia)
8. [Como Executar os Scripts no GNU Octave](#8-como-executar-os-scripts-no-gnu-octave)
9. [Referências Bibliográficas e Normativas](#9-referências-bibliográficas-e-normativas)

---

## 1. Arquitetura e Estrutura do Repositório

O sistema foi projetado seguindo a arquitetura **Store-and-Forward** (Aquisição em Bloco Determinística em RAM seguida de Transmissão Serial em Lote), minimizando o jitter de amostragem, eliminando a interferência direta da transmissão serial durante a aquisição e os gargalos de taxa de transmissão da UART durante a conversão A/D:

```text
pbl2-pds/
├── docs/
│   ├── assignments/
│   │   └── tec513_2026_2_problema_02.pdf          # Especificação oficial do Problema 02
│   ├── datasheets/
│   │   ├── atmega_640_1280_1281_2560_2561_datasheet.pdf  # Datasheet oficial Microchip ATmega2560
│   │   ├── arduino_mega_2560_datasheet.pdf
│   │   ├── arduino_mega_2560_pinout.pdf
│   │   └── arduino_mega_2560_schematics.pdf
│   ├── presentation/                              # Apresentação do projeto (LaTeX/Beamer)
│   ├── table_reports/                             # Relatórios de mesa das sessões tutoriais
│   └── reports/                                   # Relatório técnico completo (.md e .html)
├── firmware/
│   └── adc_uart/
│       └── adc_uart.ino                           # Firmware bare-metal AVR (Timer1 CTC + ADC SAR + UART0)
├── data/
│   └── oscilloscope/                              # Capturas do osciloscópio de bancada (.BMP)
│       ├── osc_f01Hz_vpp2v34_200ms.BMP
│       ├── osc_f01Hz_vpp2v34_500ms.BMP
│       ├── osc_f02Hz_vpp2v34_100ms.BMP
│       ├── osc_f05Hz_vpp2v34_50ms.BMP
│       ├── osc_f05Hz_vpp2v34_50ms_cursores.BMP
│       ├── osc_f30Hz_vpp2v30_10ms.BMP
│       ├── osc_f60Hz_vpp2v32_10ms.BMP
│       └── archive/                               # Capturas redundantes preservadas
└── tools/
    └── octave/
        ├── uart_capture.m                         # Driver de aquisição de blocos via UART (115200 bps)
        ├── uart_oscilloscope.m                    # Osciloscópio leve e telemetria de bancada em tempo real
        ├── adc_analyzer.m                         # Orquestrador de análise offline e em lote (IEEE Std 1241)
        ├── src/                                   # Núcleo matemático e de condicionamento de sinais
        │   ├── triggering/                        # detectSignalTrigger.m, estimateSignalPeriod.m
        │   ├── conditioning/                      # generateIdealReference.m, computeStaticAndTimeErrors.m
        │   ├── spectral/                          # computeSpectralMetrics.m (FFT tripla, DR, SINAD, ENOB)
        │   └── linearity/                         # computeHistogramLinearity.m (DNL, INL, Missing Codes)
        ├── utils/                                 # Utilitários de integração, I/O, GUI e exportação PNG/CSV
        │   ├── analyzeSingleCapture.m
        │   ├── saveEnrichedMat.m
        │   ├── launchAnalyzerDashboard.m
        │   ├── updateAnalyzerDashboard.m
        │   ├── runBatchAnalysis.m
        │   └── exportSingleDashboardPng.m
        ├── data/                                  # 17 capturas selecionadas (13 principais + 4 contraexemplos)
        │   └── archive/                           # 18 repetições preservadas sem exclusão
        └── outputs/                               # Painéis .png e tabela consolidada adc_summary_metrics.csv
```

---

## 2. Fundamentação Teórica e Especificações do Datasheet (ATmega2560)

### 2.1. Dimensionamento da Resolução ($N = 8\text{ bits}$) para Erro de Quantização $\le 0.39\%$

O Problema 02 exige determinar a quantidade mínima de bits $n$ para que o erro máximo de quantização não ultrapasse $0.39\%$ do fundo de escala ($FSR = V_{\text{ref}}$). Sendo o passo de quantização $\Delta = q = \frac{V_{\text{ref}}}{2^n}$:

1. **Critério do Degrau de Quantização (Truncamento: $Q(x) = \Delta \lfloor x/\Delta \rfloor$):**
   $$n = 8 \implies \frac{\Delta}{V_{\text{ref}}} = \frac{1}{256} = 0.00390625 \implies \frac{\Delta}{V_{\text{ref}}}\times 100\% = 0.390625\% \approx \mathbf{0.39\%\text{ FSR}}$$

   O valor de 0,39% é considerado arredondado neste critério. Se o limite de 0,390000% for estrito para um degrau inteiro, são necessários 9 bits; pelo critério de erro máximo de meio LSB abaixo, 8 bits atendem ao limite.
2. **Critério do Erro Centrado de Meio LSB (Arredondamento: $Q(x) = \Delta \lfloor x/\Delta + 1/2 \rfloor$):**
   $$|e_q(x)| \le \frac{\Delta}{2} = \frac{V_{\text{ref}}}{2^{n+1}} \implies \frac{|e_q|_{\max}}{V_{\text{ref}}} = \pm\frac{1}{512} = \mathbf{\pm 0.1953\%\text{ FSR}} \quad (\text{excursão pico-a-pico de erro igual a } 1\text{ LSB} = 0.3906\%\text{ FSR})$$
3. **Erro Quadrático Médio (EQM / RMSE Teórico de Quantização Uniforme):**
   Assumindo distribuição uniforme do erro $e_q \sim \mathcal{U}(-\Delta/2, +\Delta/2)$:
   $$\text{EQM}_{\text{ideal}} = \sigma_q^2 = \int_{-\Delta/2}^{+\Delta/2} \frac{e^2}{\Delta}\,de = \frac{\Delta^2}{12} \implies \text{RMSE}_{q,\text{ideal}} = \frac{1\text{ LSB}}{\sqrt{12}} \approx \mathbf{0.2887\text{ LSB}} \quad (2.89\text{ mV para } V_{\text{ref}} = 2.56\text{ V})$$

### 2.2. Técnica de Conversão SAR (*Successive Approximation Register*) e Troca de 10 para 8 bits

O conversor A/D interno do ATmega2560 utiliza a arquitetura de **Aproximações Sucessivas (SAR)**:
- Um circuito **Sample & Hold (S/H)** amostra a tensão de entrada $V_{\text{in}}$ e a mantém constante em um capacitor de retenção ($C_{\text{hold}} \approx 14\text{ pF}$) a partir de $1.5\text{ ciclo}$ de clock do ADC após o disparo.
- A lógica SAR realiza uma **busca binária** do bit mais significativo (MSB) ao menos significativo (LSB), ajustando um DAC interno de 10 bits alimentado por $V_{\text{ref}}$ e comparando $V_{\text{DAC}}$ com $V_{\text{in}}$ através de um comparador analógico a cada ciclo de clock do ADC.
- **Vantagens de utilizar 8 bits (`ADLAR = 1` lendo apenas `ADCH`) em vez dos 10 bits nativos:**
  1. **Tolerância $4\times$ maior aos erros estáticos:** como $1\text{ LSB}_{8\text{b}} = 4 \times 1\text{ LSB}_{10\text{b}}$ ($10.0\text{ mV}$ em vez de $2.5\text{ mV}$), as não-linearidades (DNL/INL) e o ruído térmico expressos em $\text{LSB}_{8\text{b}}$ são divididos por 4.
  2. **Aumento de $8\times$ na velocidade de clock do ADC (Seção 26.4 do Datasheet):** para 10 bits, o DAC interno exige $f_{\text{ADC}} \in [50\text{ kHz}, 200\text{ kHz}]$ (`prescaler = 128` $\to 125\text{ kHz}$). Para resolução de 8 bits, o próprio datasheet da Microchip autoriza operar com $f_{\text{ADC}}$ até **$1\text{ MHz}$ (`prescaler = 16`)**, reduzindo o tempo de conversão de $104\text{ }\mu\text{s}$ para **$13.0\text{ }\mu\text{s}$**.
  3. **Metade do consumo de RAM e de banda serial:** cada amostra ocupa exatamente `1 byte` (`uint8_t`), permitindo armazenar $4096$ a $6144$ amostras nos $8\text{ KB}$ de SRAM do ATmega2560 e transmitir cada amostra em um único frame UART 8N1.

### 2.3. Parâmetros do Datasheet da Microchip (ATmega2560 — Seções 26 e 29.8)

| Parâmetro do Datasheet (Tabelas 29-16 e 29-17) | Símbolo | Mín. | Típ. | Máx. | Unidade | Condição no Projeto |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **Referência Interna de 2.56 V** | $V_{\text{INT}}$ | **$2.30$** | **$2.56$** | **$2.80$** | $\text{V}$ | `REFS1:0 = 11` em `ADMUX` ($1\text{ LSB}_{\text{nom}} = 10.0\text{ mV}$) |
| **Impedância da Fonte Analógica** | $R_{\text{ain}}$ | — | — | $10$ | $\text{k}\Omega$ | Gerador de funções de bancada ($50\text{ }\Omega \ll 10\text{ k}\Omega$) |
| **Tempo de Conversão Normal** | $T_{\text{conv}}$ | — | **$13$** | — | $\text{ciclos ADC}$ | $13.0\text{ }\mu\text{s}$ com `prescaler = 16` ($f_{\text{ADC}} = 1\text{ MHz}$) |
| **Tempo da 1ª Conversão (Aquecimento)** | $T_{\text{conv,1}}$ | — | **$25$** | — | $\text{ciclos ADC}$ | Descartada por `DISCARDED_READS = 16U` leituras prévias |
| **Não-Linearidade Integral (INL)** | $\text{INL}$ | — | $0.5$ | — | $\text{LSB}_{10\text{b}}$ | Equivale a $\pm 0.125\text{ LSB}_{8\text{b}}$ típico em $f_{\text{ADC}} \le 200\text{ kHz}$ |
| **Não-Linearidade Diferencial (DNL)** | $\text{DNL}$ | — | $0.25$ | — | $\text{LSB}_{10\text{b}}$ | Ausência de *missing codes* especificada nas condições de ensaio do fabricante |

---

## 3. Cálculos Teóricos vs. Práticos ($f_s$, $f_{\text{sinal}}$, UART U2X0, Buffer de 4096 Amostras e Firmware `.ino`)

Esta seção detalha todos os cálculos de projeto com os parâmetros operacionais do sistema: **$F_{\text{CPU}} = 16\text{ MHz}$**, **`adc_prescaler = 16`**, **`BAUD = 115200` em velocidade dupla (`U2X0 = 1`)** e bloco fixo de **$N = 4096\text{ amostras}$**.

### 3.1. Frequência de Amostragem Máxima ($f_{s,\max}$): Teórica vs. Prática com `prescaler = 16`

1. **Clock do ADC e Tempo de Conversão Teórico (`prescaler = 16`):**
   $$f_{\text{ADC}} = \frac{F_{\text{CPU}}}{\text{Prescaler}} = \frac{16\,000\,000\text{ Hz}}{16} = \mathbf{1\,000\,000\text{ Hz} \; (1.0\text{ MHz})} \implies T_{\text{ADC}} = 1.0\text{ }\mu\text{s}$$
   Como uma conversão normal exige $13\text{ ciclos}$ do clock do ADC:
   $$T_{\text{conv,teórico}} = 13 \times T_{\text{ADC}} = \mathbf{13.0\text{ }\mu\text{s}} \quad (208\text{ ciclos de CPU})$$
   - **Frequência de amostragem máxima teórica pura do hardware ADC:**
     $$f_{s,\max,\text{teórico}} = \frac{f_{\text{ADC}}}{13} = \frac{1\,000\,000}{13} \approx \mathbf{76\,923.08\text{ Hz}}$$

2. **Frequência de Amostragem Máxima Prática no Firmware (`adc_uart.ino`):**
   Na prática, cada conversão é iniciada por software (`ADCSRA |= (1 << ADSC)`) dentro da rotina de interrupção `ISR(TIMER1_COMPA_vect)` e deve armazenar a amostra em RAM e verificar *overrun* antes da próxima interrupção:
   - **Sincronismo do ADC ($14\text{ ciclos de clock do ADC}$):** como o disparo de `ADSC` ocorre no domínio de clock da CPU ($16\text{ MHz}$) e o ADC roda em um clock dividido por 16 ($1\text{ MHz}$), pode haver até **1 ciclo extra de clock do ADC** para alinhar o início da conversão, totalizando $14 \times 16 = \mathbf{224\text{ ciclos de CPU}}$ ($14.0\text{ }\mu\text{s}$).
   - **Orçamento de Software da ISR (`ISR_BUDGET_CYCLES = 256UL`):** reserva $256\text{ ciclos de CPU}$ ($16.0\text{ }\mu\text{s}$) para a latência de atendimento da interrupção AVR, salvamento de contexto (`push` de registradores), leitura de `ADCH`, escrita em `sampling_buffer[idx++]`, checagem de atraso (`TIFR1 & (1 << OCF1A)`), controle de fim de bloco e retorno (`reti`).
   - **Custo Total Mínimo por Amostra (`required_cycles`):**
     $$C_{\text{req}} = 14 \times \text{Prescaler} + \text{ISR\_BUDGET\_CYCLES} = 14 \times 16 + 256 = \mathbf{480\text{ ciclos de CPU}} \quad (30.0\text{ }\mu\text{s})$$
   - **Quantização pelo `Timer1` (Modo CTC com Prescaler $8$, $1\text{ tick} = 8\text{ ciclos de CPU} = 0.5\text{ }\mu\text{s}$):**
     Em `Capture_Validate`, a condição de segurança é estrita (`ticks * 8UL > required_cycles`, ou seja, $\text{ticks} \times 8 > 480 \implies \text{ticks} > 60$):
     $$\text{ticks}_{\min} = \mathbf{61\text{ ticks}} \quad (\text{OCR1A} = \text{timer\_top} = 60, \quad T_{s,\min,\text{prático}} = 61 \times 0.5\text{ }\mu\text{s} = \mathbf{30.5\text{ }\mu\text{s}})$$
   - **Resultado Comparativo ($f_{s,\max}$ com `prescaler = 16`):**
     - **Teto Teórico Puro do ADC ($13\text{ }\mu\text{s}$):** $76\,923.08\text{ Hz}$
     - **Teto Assintótico do Orçamento de Tempo ($30.0\text{ }\mu\text{s}$):** $\frac{16\text{ MHz}}{480} = 33\,333.33\text{ Hz}$
     - **Teto Prático Efetivo do Firmware ($\text{ticks}_{\min} = 61$, $30.5\text{ }\mu\text{s}$):**
       $$f_{s,\max,\text{prático}} = \frac{16\,000\,000}{8 \times 61} = \frac{2\,000\,000}{61} = \mathbf{32\,786.89\text{ Hz}}$$
       *(Ao solicitar $f_s = 2^{15} = 32\,768\text{ Hz}$ no script Octave, o arredondamento `ticks = round(2000000 / 32768) = 61` seleciona exatamente o limite máximo de **$32\,786.89\text{ Hz}$**, testado com sucesso em `adc_f60Hz_fs32768Hz_pre16.mat`!)*

### 3.2. Frequência do Sinal Triangular ($f_{\min}$ e $f_{\max}$): Teórica vs. Prática com $N = 4096$

Para que a captura cumpra simultaneamente (i) a visitação de todos os $256$ níveis na subida e dos $256$ níveis na descida de um mesmo ciclo e (ii) a presença de pelo menos $M_{\text{ciclos}} \ge 1$ período inteiro dentro do buffer fixo de $N = 4096\text{ amostras}$:

1. **Frequência Máxima do Sinal ($f_{\max}$) pela Condição dos 512 Pontos por Ciclo ($N_p = f_s / f \ge 512$):**
   $$f_{\max} = \frac{f_s}{2 \times 2^8} = \frac{f_s}{512}$$
   - **Limite Teórico Puro ($f_{s,\max,\text{teórico}} = 76\,923.08\text{ Hz}$):**
     $$f_{\max,\text{teórico}} = \frac{76\,923.08}{512} = \mathbf{150.24\text{ Hz}}$$
   - **Limite Prático no Firmware com `prescaler = 16` ($f_{s,\max,\text{prático}} = 32\,786.89\text{ Hz}$):**
     $$f_{\max,\text{prático}} = \frac{32\,786.89}{512} = \mathbf{64.037\text{ Hz}}$$
     *(Comprovado experimentalmente em `adc_f60Hz_fs32768Hz_pre16.mat` com $f = 60.49\text{ Hz} \le 64.04\text{ Hz}$, onde $N_p = 542.0\text{ am/ciclo} > 512$.)*

2. **Frequência Mínima do Sinal ($f_{\min}$) pelo Tamanho Fixo do Buffer ($N = 4096\text{ amostras}$):**
   O tempo total de janela capturada é $T_{\text{janela}} = \frac{N}{f_s} = \frac{4096}{f_s}$. Para conter $M_{\text{ciclos}}$ períodos completos ($T_{\text{janela}} \ge M_{\text{ciclos}} / f$):
   $$f_{\min}(f_s) = M_{\text{ciclos}} \cdot \frac{f_s}{4096}$$
   - Para uma frequência de amostragem $f_s$ escolhida e $N = 4096$, a janela comporta entre **$1\text{ ciclo}$ ($f_{\min} = f_s / 4096$)** e **$8\text{ ciclos}$ ($f_{\max} = f_s / 512$)** obedecendo a $N_p \ge 512$:
     $$\frac{f_s}{4096} \le f \le \frac{f_s}{512}$$
   - Considerando a menor taxa de amostragem permitida pelo firmware (`MIN_SAMPLE_RATE = 513U`, definida especificamente para satisfazer $f_s > 512 \cdot f$ em $f = 1\text{ Hz}$):
     - Em $f_s = 513\text{ Hz}$: $f_{\min} = \frac{513}{4096} = \mathbf{0.125\text{ Hz}}$ (para 1 ciclo) ou **$0.25\text{ Hz}$** (para 2 ciclos), e em $f = 1.00\text{ Hz}$ capturam-se **8 ciclos completos** ($T_{\text{janela}} = 7.98\text{ s}$).
     - Em $f_s = 1024\text{ Hz}$ (`adc_f01Hz_fs01024Hz_pre16.mat`): $T_{\text{janela}} = 4.00\text{ s}$, capturando **4 ciclos completos de $1.00\text{ Hz}$** com $1017.5\text{ amostras/ciclo}$.
     - Já em $f_s = 8192\text{ Hz}$, $f_{\min}(1\text{ ciclo}) = \frac{8196.7}{4096} = \mathbf{2.00\text{ Hz}}$ (`adc_f02Hz_fs08192Hz_pre16.mat`); qualquer sinal abaixo de $2\text{ Hz}$ nessa taxa (como $1.0\text{ Hz}$ em `contraex_meio_ciclo_f01Hz_fs08192Hz.mat`) terá menos de 1 ciclo dentro das 4096 amostras!

| Taxa Solicitada ($f_s$) | Ticks do Timer1 ($\text{OCR1A}+1$) | Taxa Efetiva Real ($f_{s,\text{efetiva}}$) | Duração da Janela ($4096 / f_s$) | $f_{\min}$ p/ 1 Ciclo ($f_s / 4096$) | $f_{\min}$ p/ 2 Ciclos ($2 f_s / 4096$) | $f_{\max}$ p/ $N_p \ge 512$ ($f_s / 512$) |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| $513\text{ Hz}$ (Mín.) | $3899$ | $512.95\text{ Hz}$ | $7.985\text{ s}$ | $0.125\text{ Hz}$ | $0.250\text{ Hz}$ | $1.002\text{ Hz}$ |
| $1024\text{ Hz}$ | $1953$ | $1024.07\text{ Hz}$ | $4.000\text{ s}$ | $0.250\text{ Hz}$ | $0.500\text{ Hz}$ | $2.000\text{ Hz}$ |
| $2000\text{ Hz}$ | $1000$ | $2000.00\text{ Hz}$ | $2.048\text{ s}$ | $0.488\text{ Hz}$ | $0.977\text{ Hz}$ | $3.906\text{ Hz}$ |
| $4000\text{ Hz}$ | $500$ | $4000.00\text{ Hz}$ | $1.024\text{ s}$ | $0.977\text{ Hz}$ | $1.953\text{ Hz}$ | $7.813\text{ Hz}$ |
| $8192\text{ Hz}$ | $244$ | $8196.72\text{ Hz}$ | $0.4997\text{ s}$ | $2.001\text{ Hz}$ | $4.002\text{ Hz}$ | $16.009\text{ Hz}$ |
| $16384\text{ Hz}$ | $122$ | $16393.44\text{ Hz}$ | $0.2499\text{ s}$ | $4.002\text{ Hz}$ | $8.005\text{ Hz}$ | $32.018\text{ Hz}$ |
| $32768\text{ Hz}$ (Máx.) | $61$ | **$32786.89\text{ Hz}$** | $0.1249\text{ s}$ | $8.005\text{ Hz}$ | $16.009\text{ Hz}$ | **$64.037\text{ Hz}$** |

### 3.3. Cálculos da UART0 a `115200 baud` em Velocidade Dupla (`U2X0 = 1`) e Tempo de Transmissão

1. **Por que o modo de Velocidade Dupla (`U2X0 = 1`) é indispensável em $16\text{ MHz}$ para $115200\text{ baud}$?**
   Pela Seção 22.3 do datasheet do ATmega2560:
   - **No Modo Normal (`U2X0 = 0`, divisor $16$):**
     $$\text{UBRR} = \text{round}\!\left(\frac{F_{\text{CPU}}}{16 \cdot \text{BAUD}}\right) - 1 = \text{round}\!\left(\frac{16\,000\,000}{16 \times 115200}\right) - 1 = \text{round}(8.68) - 1 = 8$$
     $$\text{BAUD}_{\text{normal}} = \frac{16\,000\,000}{16 \times (8 + 1)} = \mathbf{111\,111.1\text{ bps}} \implies \text{Erro de Baud} = \mathbf{-3.55\%}$$
     Um desvio de $-3.55\%$ ultrapassa o limite máximo de recepção assíncrona 8N1 ($\pm 2.0\%$), gerando corrupção de bytes.
   - **No Modo de Velocidade Dupla (`UCSR0A = (1 << U2X0)`, divisor $8$, implementado em `UART0_Init`):**
     $$\text{UBRR} = \left\lfloor \frac{F_{\text{CPU}}}{8 \cdot \text{BAUD}} \right\rfloor - 1 = \left\lfloor \frac{16\,000\,000}{8 \times 115200} \right\rfloor - 1 = \lfloor 17.361 \rfloor - 1 = \mathbf{16}$$
     $$\text{BAUD}_{\text{U2X0}} = \frac{16\,000\,000}{8 \times (16 + 1)} = \frac{16\,000\,000}{136} = \mathbf{117\,647.06\text{ bps}} \implies \text{Erro de Baud} = \mathbf{+2.12\%}$$
     Reduzindo o divisor para 8, o erro cai para $+2.12\%$, compatível com a comunicação observada nos ensaios; a margem depende também do clock e do receptor USB-Serial utilizado.

2. **Tempo por Byte, Limite de *Streaming* e Tempo de Envio do Bloco de $4096\text{ Amostras}$:**
   - No formato de quadro **8N1** (`UCSR0C = (1 << UCSZ01) | (1 << UCSZ00)`), cada byte transmitido ocupa **$10\text{ bits}$** na linha serial ($1\text{ start bit} + 8\text{ data bits} + 1\text{ stop bit}$):
     $$R_{\text{bytes,nom}} = \frac{115\,200}{10} = 11\,520\text{ B/s} \; (T_{\text{byte,nom}} = 86.81\text{ }\mu\text{s}), \qquad R_{\text{bytes,real}} = \frac{117\,647.06}{10} = \mathbf{11\,764.7\text{ B/s}} \; (T_{\text{byte,real}} = \mathbf{85.00\text{ }\mu\text{s}})$$
   - **Impossibilidade de transmissão simultânea à conversão (*Streaming*):**
     Como $T_{\text{byte,real}} = 85.0\text{ }\mu\text{s}$, mesmo que o envio da UART ocorresse em paralelo à conversão do ADC, jamais seria possível transmitir mais de $11\,764\text{ amostras/s}$ em tempo real (e se fosse feito por *polling* sequencial após `ADC_Read()`, $T_{\text{ciclo}} \ge 13.0 + 85.0 = 98.0\text{ }\mu\text{s} \implies f_s \le 10\,204\text{ Hz}$).
   - **Tempo de Transmissão do Bloco *Store-and-Forward* ($1\text{ byte de status} + 4096\text{ bytes de amostras} = 4097\text{ bytes}$):**
     $$T_{\text{tx,real}} = \frac{4097 \times 10\text{ bits}}{117\,647.06\text{ bps}} = \mathbf{0.3482\text{ s} \; (348.2\text{ ms})} \quad (\text{ou } 355.6\text{ ms nominais a } 115200\text{ bps})$$

### 3.4. Decisões Críticas de Engenharia no Firmware (`firmware/adc_uart/adc_uart.ino`)

O arquivo `adc_uart.ino` implementa seis mecanismos essenciais em nível de registradores AVR:

1. **Bloqueio do `Timer0` do Arduino (`TIMSK0 = 0` no `setup()`):**
   O ambiente Arduino ativa por padrão a interrupção `TIMER0_OVF_vect` a cada $1.024\text{ ms}$ para atualizar `millis()`. Se `TIMSK0` permanecesse ativo, toda vez que o `Timer0` transbordasse durante uma captura, a CPU ficaria com interrupções globais desabilitadas por $\sim 6\text{ }\mu\text{s}$, atrasando o disparo da `ISR(TIMER1_COMPA_vect)` e introduzindo *jitter* periódico nas amostras (ou causando *overrun* em $32.79\text{ kHz}$).
2. **Desacoplamento dos Buffers Digitais (`DIDR0` e `DIDR2` em `ADC_Init`):**
   Os comandos `DIDR0 = (channel < 8) ? (1 << channel) : 0;` desligam o *Schmitt-Trigger* digital do pino analógico em uso (`A0`), evitando que tensões intermediárias da rampa triangular (próximas de $V_{CC}/2$) coloquem os transistores CMOS de entrada em condução simultânea, o que injetaria ruído de corrente no pino analógico.
3. **Descarte de Leituras de Estabilização (`DISCARDED_READS = 16U`):**
   Executado tanto na inicialização (`setup()`) quanto após qualquer troca de prescaler (`ADC_SetPrescaler()`), absorvendo os $25\text{ ciclos}$ da primeira conversão do circuito SAR e estabilizando o capacitor de referência interna de $2.56\text{ V}$.
4. **Arredondamento Simétrico em Ponto Fixo (`Capture_Validate`):**
   A expressão `ticks = (F_CPU + 4UL * sample_rate) / (8UL * sample_rate)` calcula $\left\lfloor \frac{F_{\text{CPU}} + \frac{1}{2}(8 f_s)}{8 f_s} \right\rfloor = \text{round}\!\left(\frac{F_{\text{CPU}}}{8 f_s}\right)$ usando apenas inteiros de 32 bits (`uint32_t`), sem custo de biblioteca `float` na Flash/CPU, e programa `OCR1A = ticks - 1`.
5. **Detecção Hardware de *Overrun* / Perda de Sincronismo (`if (TIFR1 & (1 << OCF1A))`):**
   Dentro da `ISR(TIMER1_COMPA_vect)`, imediatamente após concluir `ADC_Read()` e salvar no `sampling_buffer`, o código lê o registrador de flags `TIFR1`. Se o bit `OCF1A` já estiver em `1`, significa que um novo período do `Timer1` expirou antes de a ISR terminar. O firmware desliga imediatamente o timer e retorna `STATUS_ERR_OVERRUN (0x02)` ao Octave, descartando o lote corrompido.
6. **Protocolo Binário de Controle de 5 Bytes e Barreiras de Memória (`asm volatile("" ::: "memory")`):**
   O Octave envia `[prescaler (1B), fs_low (1B), fs_high (1B), N_low (1B), N_high (1B)]`. O uso de barreiras de memória em torno de `Timer1_Start` e `while (!capture_done)` busca impedir reordenações e reutilização de valores de memória nesses pontos; a temporização e o código gerado devem ser verificados na compilação utilizada.

---

## 4. Metodologia de Ensaio com Referência à IEEE Std 1241

A metodologia de pós-processamento implementada em `tools/octave/adc_analyzer.m` utiliza conceitos de caracterização associados à **IEEE Std 1241 (*IEEE Standard for Terminology and Test Methods for Analog-to-Digital Converters*)**:

### 4.1. Aquisição por Registro em Bloco (*Data Record Acquisition*) e Pós-Processamento

Segundo a Seção 5 da IEEE Std 1241, o ensaio de um ADC parte da coleta de um registro finito de $N$ amostras equiespaçadas $y(0), y(1), \dots, y(N-1)$ sob estímulo periódico conhecido. Armazenar os registros em arquivos `.mat` permite:
- Aplicar **ajuste de mínimos quadrados de 4 parâmetros** (amplitude/ganho, offset, frequência/período e fase) sem restrição de tempo de execução de *loop* serial;
- Auditar e reproduzir todas as métricas estáticas e dinâmicas offline a qualquer momento, mantendo o `uart_oscilloscope.m` dedicado à inspeção visual imediata na bancada.

As métricas aqui apresentadas são estimativas experimentais adaptadas ao estímulo triangular, sem demonstração de conformidade integral com a norma. O termo “intrínseco”, mantido em nomes de campos e tabelas do analisador, designa o resíduo após ajuste: ele não separa, por si só, os efeitos do ADC, do gerador e do modelo. A limitação do modelo a 0–255 também reduz a contribuição das regiões saturadas ao resíduo.

### 4.2. Formulação Matemática das Métricas em `adc_analyzer.m`

1. **Sinal Triangular Ideal Contínuo e Sinal Ideal Quantizado de 256 Níveis:**
   A partir do período medido $T_p = f_{s,\text{efetiva}} / f$ (em amostras) e fase $\phi_0 \in [0, 1)$ refinados por mínimos quadrados:
   $$y_{\text{tri,cont}}(n) = 255 \cdot \left(1 - \left|1 - 2 \cdot \bmod\!\left(\frac{n}{T_p} + \phi_0,\, 1\right)\right|\right), \qquad y_{\text{tri,quant}}(n) = \min\!\left(255, \max\!\left(0, \text{round}(y_{\text{tri,cont}}(n))\right)\right)$$

2. **Ganho Medido ($G$), Erro de Ganho e Erro de Offset (Regressão Linear na Região Não-Saturada $10 \le y_{\text{ideal}} \le 245$):**
   $$\text{Erro de Ganho (LSB)} = (G - 1.0) \times 255, \qquad \text{Erro de Offset (LSB)} = (G \cdot 127.5 + b) - 127.5$$

3. **Erros Absoluto, RMS Bruto, RMS Residual e Relativo:**
   - **Erro Instantâneo Bruto:** $e_{\text{bruto}}(n) = y_{\text{ADC}}(n) - y_{\text{tri,cont}}(n)$
   - **Erro Instantâneo Residual (após ajuste de ganho/offset e limitação do modelo):** $e_{\text{intr}}(n) = y_{\text{ADC}}(n) - \text{clip}_{[0,255]}(G \cdot y_{\text{tri,cont}}(n) + b)$
   - **MAE (Erro Absoluto Médio):** $\text{MAE} = \frac{1}{N}\sum_{n=0}^{N-1} |e_{\text{bruto}}(n)|$
   - **RMSE (Raiz do Erro Quadrático Médio):** $\text{RMSE} = \sqrt{\frac{1}{N}\sum_{n=0}^{N-1} e_{\text{bruto}}^2(n)}$
   - **Erro Relativo ao Fundo de Escala ($\%FSR$):** $\varepsilon_{\%FSR} = \frac{\text{Erro (LSB)}}{255} \times 100\%$
   - **MAPE (Erro Percentual Absoluto Médio sobre o Sinal):** $\text{MAPE} = \frac{100\%}{|S|} \sum_{n \in S} \frac{|e_{\text{bruto}}(n)|}{y_{\text{tri,cont}}(n)}$, para $y_{\text{tri,cont}}(n) \ge 5\%\text{ FSR}$.

4. **DNL, INL, *Missing Codes* e Monotonicidade (Teste de Histograma Linear — IEEE Std 1241):**
   Sobre um número inteiro de períodos $N_{\text{int}} = \lfloor N / T_p \rfloor \cdot T_p$ (ou sobre a maior rampa monotônica quando $N < T_p$), seja $H(k)$ a contagem de ocorrências do código $k \in \{k_{\min}+1, \dots, k_{\max}-1\}$ e $\overline{H}$ a contagem média esperada por nível:
   $$\text{DNL}(k) = \frac{H(k)}{\overline{H}} - 1, \qquad \text{INL}(k) = \sum_{j=k_{\min}+1}^{k} \left[\text{DNL}(j) - \overline{\text{DNL}}\right]$$
   - Se $\text{DNL}(k) = -1.0\text{ LSB}$ ($H(k) = 0$), o código $k$ **não foi observado no registro analisado**; isso, isoladamente, não demonstra um código ausente na transferência física do ADC.
   - Se $\text{DNL}(k) > -1.0\text{ LSB}$ para todo $k$ e a curva de transferência média $\overline{y}_{\text{ADC}}(k)$ não apresenta inversões de inclinação ($\Delta \overline{y}_{\text{ADC}} \ge 0$), o resultado é **compatível com comportamento monotônico na faixa e nas condições avaliadas**. A rotina admite pequenas inversões de até 0,5 LSB na curva média; portanto, seu indicador não constitui uma prova de monotonicidade.

5. **Espectro Analítico da Onda Triangular, FFT Tripla e Faixa Dinâmica ($\text{DR}$):**
   - Analiticamente, um pulso triangular $\text{tri}(t/\tau) = \frac{1}{\tau}\text{rect}(t/\tau)*\text{rect}(t/\tau)$ possui Transformada de Fourier $\tau\,\text{sinc}^2(f\tau)$. Quando periódico com frequência $f_0 = 1/T$, sua série de Fourier contém **exclusivamente harmônicas ímpares** ($k = 1, 3, 5, \dots$) com decaimento proporcional a $1/k^2$ ($-12\text{ dB/oitava}$):
     $$x_{\text{tri}}(t) = \frac{A}{2} - \frac{4A}{\pi^2}\sum_{m=1}^{\infty} \frac{1}{(2m-1)^2}\cos\!\left(2\pi (2m-1)f_0 t\right)$$
   - A 3ª harmônica ($3f_0$) está a $20\log_{10}(1/9) = \mathbf{-19.08\text{ dBc}}$ da fundamental, e a potência somada das harmônicas ímpares ($3f_0, 5f_0, \dots$) equivale a $\left(\frac{\pi^4}{96}-1\right) \approx \mathbf{-18.33\text{ dB}}$.
   - Por isso, tratar a onda triangular como se fosse uma senoide pura limitaria artificialmente o $\text{SINAD}$ a $18.33\text{ dB}$ ($\text{ENOB} = 2.75\text{ bits}$). Em `adc_analyzer.m`, mascaramos as harmônicas da triangular na sua frequência exata medida (`freq_hz`) e aplicamos a normalização de Parseval para janela de Hann ($\text{ENBW} = 1.5$), estimando o piso de ruído do registro nas bandas restantes ($P_{\text{ruído}}$), a Faixa Dinâmica ($\text{DR}$) e o $\text{ENOB}$ da onda triangular:
     $$\text{DR}_{\text{dB}} = 10\log_{10}\!\left(\frac{127.5^2 / 2}{P_{\text{ruído}}}\right), \qquad \text{SINAD}_{\text{tri}} = 10\log_{10}\!\left(\frac{\text{Var}(y_{\text{ideal}})}{\text{MSE}}\right), \qquad \text{ENOB}_{\text{tri}} = \frac{\text{SINAD}_{\text{tri}} - 1.76 + 1.25}{6.02}$$

---

## 5. Calibração com Osciloscópio de Bancada: Estimativa de $V_{\text{ref}}$ e o Erro de Ganho/Offset

As capturas do osciloscópio digital em `data/oscilloscope/*.BMP` registraram o sinal analógico real aplicado ao pino `A0` do ATmega2560:

| Arquivo de Osciloscópio (`data/oscilloscope/`) | Frequência no Osciloscópio | Base de Tempo | Tensão Pico-a-Pico Medida ($V_{pp,\text{osc}}$) | Excursão Observada no Grid ($500\text{ mV/div}$) |
| :--- | :---: | :---: | :---: | :--- |
| `osc_f01Hz_vpp2v34_200ms.BMP` | $1.00\text{ Hz}$ | $200\text{ ms/div}$ | **$2.34\text{ V}$** | $V_{\min} \approx 0.00\text{ V}$ (marcador `1>`) a $V_{\max} \approx 2.34\text{ V}$ |
| `osc_f01Hz_vpp2v34_500ms.BMP` | $1.00\text{ Hz}$ | $500\text{ ms/div}$ | **$2.34\text{ V}$** | $V_{\min} \approx 0.00\text{ V}$ a $V_{\max} \approx 2.34\text{ V}$ |
| `osc_f02Hz_vpp2v34_100ms.BMP` | $2.00\text{ Hz}$ | $100\text{ ms/div}$ | **$2.32\text{ V}$** | $V_{\min} \approx 0.00\text{ V}$ a $V_{\max} \approx 2.32\text{ V}$ |
| `osc_f05Hz_vpp2v34_50ms_cursores.BMP` | $5.00\text{ Hz}$ | $50\text{ ms/div}$ | **$2.34\text{ V}$** (Pico-Pico explícito) | $V_{\min} \approx 0.00\text{ V}$ a $V_{\max} \approx 2.34\text{ V}$ ($4.68\text{ div} \times 0.5\text{ V}$) |
| `osc_f05Hz_vpp2v34_50ms.BMP` | $5.00\text{ Hz}$ | $50\text{ ms/div}$ | **$2.32\text{ V}$** | $V_{\min} \approx 0.00\text{ V}$ a $V_{\max} \approx 2.34\text{ V}$ |
| `osc_f30Hz_vpp2v30_10ms.BMP` | $29.99\text{ Hz}$ | $10\text{ ms/div}$ | **$2.30\text{ V}$** | $V_{\min} \approx 0.00\text{ V}$ a $V_{\max} \approx 2.34\text{ V}$ |
| `osc_f60Hz_vpp2v32_10ms.BMP` | $59.96\text{ Hz}$ | $10\text{ ms/div}$ | **$2.32\text{ V}$** | $V_{\min} \approx 0.00\text{ V}$ a $V_{\max} \approx 2.34\text{ V}$ |

### 5.1. Estimativa Experimental da Referência Interna ($V_{\text{ref,real}} \approx 2.31\text{ V}$)

1. Como o sinal analógico de **$V_{pp,\text{osc}} = 2.34\text{ V}$** ($0\text{ V}$ a $2.34\text{ V}$) preencheu todos os 256 níveis do ADC ($0$ a $255$) com ganho relativo de $G_{\text{rel}} \approx 1.009\text{ a }1.0168$, a tensão de referência interna real ($V_{\text{ref,real}}$) da placa utilizada é:
   $$V_{\text{ref,real}} = \frac{2.34\text{ V}}{1.013} \approx \mathbf{2.31\text{ V}} \implies 1\text{ LSB}_{\text{real}} = \frac{2.31\text{ V}}{256} \approx \mathbf{9.02\text{ mV}}$$
A estimativa depende da amplitude medida, do ajuste e das condições de bancada. Não foi estabelecida uma incerteza de medição nem feita uma medição independente da referência; por isso, o valor não deve ser interpretado como calibração metrológica.

2. Esse valor está dentro da especificação oficial da Microchip para a referência bandgap interna ($2.30\text{ V} \le V_{\text{INT}} \le 2.80\text{ V}$), situando-se **$-9.8\%$ abaixo** do valor nominal de $2.56\text{ V}$.
3. **Erro de Ganho Absoluto vs. Erro de Ganho Residual:**
   - **Antes da calibração (`contraex_saturado_2v56_f05Hz_fs02000Hz.mat`):** injetando $2.56\text{ V}$ nominais no pino `A0`, o ADC saturou no código $255$ acima de $2.31\text{ V}$, permitindo estimar o **desvio de ganho do conjunto de medição, incluindo ADC e referência interna**:
     $$G_{\text{abs}} = \frac{2.56\text{ V}}{2.32\text{ V}} = \mathbf{1.100} \quad (\text{Erro de Ganho Absoluto} = \mathbf{+25.4\text{ LSB} = +9.97\%\text{ FSR}})$$
   - **Após calibração com o osciloscópio ($V_{pp} = 2.34\text{ V}$):** ajustando a excursão do gerador para varrer $0\text{ V}$ a $V_{\text{ref,real}}$, o **Erro de Ganho Residual** ficou em $+0.88\%\text{ a }+1.68\%\text{ FSR}$ ($+2.26\text{ a }+4.30\text{ LSB}$) e o **Erro de Offset** em $-0.38\text{ a }+0.39\text{ LSB}$ ($\pm 0.15\%\text{ FSR}$).

---

## 6. Organização dos Dados e Resultados Experimentais

Os 35 arquivos `.mat` originais foram preservados e organizados em:
- **13 Candidatos Principais** em `tools/octave/data/adc_f<XX>Hz_fs<YYYYY>Hz_pre16.mat`
- **4 Contraexemplos Didáticos** em `tools/octave/data/contraex_*.mat`
- **18 Repetições/Duplicatas** arquivadas em `tools/octave/data/archive/dup_*.mat`

### 6.1. Tabela dos 13 Candidatos Principais (`tools/octave/data/`)

| Arquivo Padronizado | $f_s$ Efetiva ($\text{Hz}$) | $f$ Sinal ($\text{Hz}$) | Amostras/Ciclo ($N_p$) | Ciclos Inteiros | RMSE Bruto ($\text{LSB}$ / $\text{mV}^*$) | RMSE Intrín. ($\text{LSB}$ / $\text{mV}^*$) | MAE ($\text{LSB}$) | Offset ($\text{LSB}$ / $\%FSR$) | Ganho Residual ($\text{LSB}$ / $\%FSR$) | DNL $[\min, \max]$ ($\text{LSB}$) | INL $[\min, \max]$ ($\text{LSB}$) | DR ($\text{dB}$) | ENOB Intrín. ($\text{bits}$) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| ★ **`adc_f01Hz_fs01024Hz_pre16.mat`** | $1024.1$ | $1.01$ | $1017.5$ | $4$ | $0.82$ ($8.2\text{ mV}$) | **$0.35$** ($3.5\text{ mV}$) | $0.66$ | $-0.38$ ($-0.15\%$) | $+2.31$ ($+0.91\%$) | $[-0.43, +0.52]$ | $[-0.45, +0.38]$ | **$48.3$** | **$7.62$** |
| `adc_f01Hz_fs02000Hz_pre16.mat` | $2000.0$ | $1.01$ | $1987.3$ | $2$ | $0.80$ ($8.0\text{ mV}$) | $0.37$ ($3.7\text{ mV}$) | $0.66$ | $-0.32$ ($-0.13\%$) | $+2.24$ ($+0.88\%$) | $[-0.61, +0.55]$ | $[-0.53, +0.37]$ | $47.7$ | $7.52$ |
| ★ **`adc_f05Hz_fs04000Hz_pre16.mat`** | $4000.0$ | $5.03$ | $794.9$ | $5$ | $0.81$ ($8.1\text{ mV}$) | **$0.35$** ($3.5\text{ mV}$) | $0.66$ | $-0.38$ ($-0.15\%$) | $+2.26$ ($+0.89\%$) | $[-0.48, +0.49]$ | $[-0.32, +0.50]$ | **$48.2$** | **$7.63$** |
| `adc_f02Hz_fs08192Hz_pre16.mat` | $8196.7$ | $2.01$ | $4069.3$ | $1$ | $1.24$ ($12.4\text{ mV}$) | $0.38$ ($3.8\text{ mV}$) | $1.05$ | $-0.34$ ($-0.13\%$) | $+4.01$ ($+1.57\%$) | $[-0.62, +0.66]$ | $[-0.48, +0.41]$ | $48.1$ | $7.53$ |
| `adc_f04Hz_fs08192Hz_pre16.mat` | $8196.7$ | $4.04$ | $2030.3$ | $2$ | $1.23$ ($12.3\text{ mV}$) | $0.46$ ($4.6\text{ mV}$) | $1.03$ | $-0.27$ ($-0.11\%$) | $+3.84$ ($+1.50\%$) | $[-0.49, +0.59]$ | $[-0.48, +0.41]$ | $48.0$ | $7.26$ |
| `adc_f05Hz_fs08192Hz_pre16.mat` | $8196.7$ | $5.04$ | $1625.7$ | $2$ | $1.21$ ($12.1\text{ mV}$) | $0.36$ ($3.6\text{ mV}$) | $1.03$ | $-0.13$ ($-0.05\%$) | $+4.03$ ($+1.58\%$) | $[-0.52, +0.52]$ | $[-0.27, +0.66]$ | $48.1$ | $7.58$ |
| `adc_f06Hz_fs08192Hz_pre16.mat` | $8196.7$ | $6.05$ | $1355.1$ | $3$ | $1.23$ ($12.3\text{ mV}$) | $0.37$ ($3.7\text{ mV}$) | $1.04$ | $-0.35$ ($-0.14\%$) | $+4.02$ ($+1.58\%$) | $[-0.55, +0.85]$ | $[-0.45, +0.66]$ | $47.9$ | $7.57$ |
| `adc_f07Hz_fs08192Hz_pre16.mat` | $8196.7$ | $7.06$ | $1161.5$ | $3$ | $1.25$ ($12.5\text{ mV}$) | $0.37$ ($3.7\text{ mV}$) | $1.07$ | $-0.34$ ($-0.13\%$) | $+4.10$ ($+1.61\%$) | $[-0.55, +0.71]$ | $[-0.42, +0.63]$ | $47.7$ | $7.56$ |
| ★ **`adc_f08Hz_fs08192Hz_pre16.mat`** | $8196.7$ | $8.07$ | $1016.3$ | $4$ | $1.27$ ($12.7\text{ mV}$) | **$0.36$** ($3.6\text{ mV}$) | $1.08$ | $-0.37$ ($-0.14\%$) | $+4.04$ ($+1.58\%$) | $[-0.49, +0.59]$ | $[-0.40, +0.53]$ | **$47.9$** | **$7.59$** |
| `adc_f10Hz_fs08192Hz_pre16.mat` | $8196.7$ | $10.08$ | $813.1$ | $5$ | $1.23$ ($12.3\text{ mV}$) | $0.36$ ($3.6\text{ mV}$) | $1.05$ | $-0.24$ ($-0.09\%$) | $+4.07$ ($+1.60\%$) | $[-0.43, +0.53]$ | $[-0.22, +0.61]$ | $48.0$ | $7.59$ |
| `adc_f12Hz_fs08192Hz_pre16.mat` | $8196.7$ | $12.10$ | $677.5$ | $6$ | $1.22$ ($12.2\text{ mV}$) | $0.37$ ($3.7\text{ mV}$) | $1.04$ | $-0.31$ ($-0.12\%$) | $+3.97$ ($+1.55\%$) | $[-0.55, +0.46]$ | $[-0.26, +0.51]$ | $48.2$ | $7.54$ |
| ★ **`adc_f30Hz_fs16384Hz_pre16.mat`** | $16393.4$ | $30.25$ | $542.0$ | $7$ | $1.28$ ($12.8\text{ mV}$) | **$0.34$** ($3.4\text{ mV}$) | $1.09$ | $+0.05$ ($+0.02\%$) | $+4.29$ ($+1.68\%$) | $[-0.52, +0.50]$ | $[-0.22, +0.62]$ | **$47.7$** | **$7.70$** |
| ★ **`adc_f60Hz_fs32768Hz_pre16.mat`** | $32786.9$ | $60.49$ | $542.0$ | $7$ | $1.12$ ($11.2\text{ mV}$) | **$0.35$** ($3.5\text{ mV}$) | $0.94$ | $-0.26$ ($-0.10\%$) | $+3.69$ ($+1.45\%$) | $[-0.66, +0.77]$ | $[-0.45, +0.63]$ | **$46.4$** | **$7.63$** |

*(\*Valores em $\text{mV}$ na escala nominal $1\text{ LSB}_{\text{nom}} = 10.0\text{ mV}$; na escala calibrada real $1\text{ LSB}_{\text{real}} = 9.02\text{ mV}$, os erros em $\text{mV}$ são $9.8\%$ menores. Em todos os 13 candidatos principais, **`missing_codes = 0`** e **`is_monotonic = 1`**.)*

### 6.2. Tabela dos 4 Contraexemplos Didáticos (`tools/octave/data/contraex_*.mat`)

| Arquivo Contraexemplo | Condição Experimental | Métricas Observadas | Fenômeno Físico / Matemático Demonstrado |
| :--- | :--- | :--- | :--- |
| **`contraex_saturado_2v56_f05Hz_fs02000Hz.mat`** | $f=5.03\text{ Hz}, f_s=2000\text{ Hz}$<br>Gerador em $2.56\text{ V}_{\max}$ | $\text{Offset} = +11.88\text{ LSB}$<br>$\text{Ganho} = +25.41\text{ LSB}$ ($+9.97\%$)<br>$\text{RMSE} = 12.91\text{ LSB}$ | **Saturação no topo (`255`) por desvio de $V_{\text{ref}}$:** é compatível com a hipótese de que $V_{\text{ref,real}} \approx 2.31\text{ V} < 2.56\text{ V}$, ceifando os $250\text{ mV}$ superiores da onda triangular. |
| **`contraex_subamostrado_Np397_f05Hz_fs02000Hz.mat`** | $f=5.03\text{ Hz}, f_s=2000\text{ Hz}$<br>Gerador ajustado ($2.34\text{ V}_{pp}$) | $N_p = \mathbf{397.4\text{ am/ciclo}} < 512$<br>$\text{RMSE} = 0.83\text{ LSB}$ | **Violação da condição $f_s > 512 \cdot f$:** com apenas $198.7$ amostras por rampa para $256$ níveis, cada subida/descida individual salta $\sim 57$ códigos. |
| **`contraex_meio_ciclo_f01Hz_fs08192Hz.mat`** | $f=1.01\text{ Hz}, f_s=8196.7\text{ Hz}$<br>$N = 4096\text{ amostras}$ | Janela $= 0.50\text{ s}$ ($0.50\text{ ciclo}$)<br>Excursão $= 0..207\text{ LSB}$ | **Janela de aquisição inferior a 1 período ($N < T_p$):** a captura termina antes de a rampa atingir o código $255$, impedindo o teste de fundo de escala completo. |
| **`contraex_missing_code_f30Hz_fs16384Hz.mat`** | $f=30.25\text{ Hz}, f_s=16393.4\text{ Hz}$<br>$N_p = 542.0\text{ am/ciclo}$ | `missing_codes = 1`<br>$\text{DNL}_{\min} = -1.00\text{ LSB}$ | **Operação no limiar $N_p \approx 512$:** com apenas $1.058\text{ amostras/nível/rampa}$ e sincronismo inteiro ($N_p = 542.0$), ocorre efeito pente no DNL e perda pontual de 1 código. |

---

## 7. Principais Conclusões Físicas e de Engenharia

1. **Resultados residuais nas condições ensaiadas:**
   Nos 13 ensaios principais, com clock do ADC de $1\text{ MHz}$, o RMSE residual após ajuste ficou entre aproximadamente $0.34$ e $0.46\text{ LSB}$, o ENOB estimado pelo modelo triangular entre $7.26$ e $7.70\text{ bits}$ e a DR estimada entre $46.4$ e $48.3\text{ dB}$. Esses resultados descrevem os registros analisados e não isolam o desempenho do núcleo SAR.
2. **Influência da amostragem nos histogramas:**
   Nos registros próximos de $542\text{ amostras/ciclo}$, há cerca de $271$ amostras por rampa para $256$ níveis. A distribuição discreta das amostras e a relação entre os clocks podem contribuir para padrões periódicos em DNL/INL. Os ensaios com aproximadamente 795 e 1018 amostras por ciclo apresentaram INL RMS próximo de 0,18 e 0,16 LSB, respectivamente; isso não estabelece um limiar universal de eliminação do efeito.
3. **Hipótese sobre a referência interna:**
   As medições de bancada e o ajuste de ganho sugerem referência efetiva próxima de $2.31\text{ V}$, abaixo do valor nominal de $2.56\text{ V}$. A referência pode explicar parte do desvio observado, mas os ensaios não permitem atribuir todo o erro a ela nem separar completamente as contribuições do gerador, do ADC e dos instrumentos.

---

## 8. Como Executar os Scripts no GNU Octave

Abra o **GNU Octave** e navegue até `tools/octave/` (ou adicione a pasta ao `path`):

```octave
addpath("tools/octave");

% 1. Abrir o Painel Digital Interativo (seleção entre os 17 arquivos .mat, Zoom, Pan,
%    alternância entre Código ADC [0..255], Tensão [0..2.56 V] e Erro Relativo [%FSR]):
adc_analyzer()

% 2. Abrir o Painel diretamente em um candidato específico:
adc_analyzer("adc_f05Hz_fs04000Hz_pre16.mat")

% 3. Processar todos os arquivos em lote, atualizar adc_summary_metrics.csv e exportar
%    os painéis individuais em tools/octave/outputs/:
adc_analyzer("batch")

% 4. Para realizar novas capturas em tempo real com o Arduino Mega 2560 conectado via USB:
uart_oscilloscope
```

---

## 9. Referências Bibliográficas e Normativas

1. **Microchip Technology Inc.** *ATmega640/V-1280/V-1281/V-2560/V-2561/V — 8-bit Atmel Microcontroller with 16/32/64KB In-System Programmable Flash Datasheet*, DS40002211A (Seção 22: *USART*, pp. 200–225; Seção 26: *Analog-to-Digital Converter*, pp. 268–288; Seção 29.8: *ADC Characteristics*, pp. 363–365). Disponível em `docs/datasheets/atmega_640_1280_1281_2560_2561_datasheet.pdf`.
2. **IEEE Std 1241-2010 (R2023).** *IEEE Standard for Terminology and Test Methods for Analog-to-Digital Converters*, Institute of Electrical and Electronics Engineers, New York, NY.
3. **Oppenheim, A. V.; Schafer, R. W.** *Discrete-Time Signal Processing*, 3rd ed., Prentice-Hall, 2009.
4. **Ball, S. R.** *Analog Interfacing to Embedded Microprocessors: Real World Design*, 2nd ed., Newnes, 2003.
5. **Haykin, S.; Van Veen, B.** *Sinais e Sistemas*, Bookman, 2001.
6. **Lathi, B. P.** *Sinais e Sistemas Lineares*, 2ª ed., Bookman, 2006.
7. **Ingle, V. K.; Proakis, J. G.** *Digital Signal Processing Using MATLAB*, 3rd ed., Cengage Learning, 2011.
