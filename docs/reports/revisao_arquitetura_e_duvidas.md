# Revisão de Arquitetura, Firmware (`adc_uart.ino`) e Métodos de Medição no Octave

Este documento sintetiza a revisão de código, funcionamento em nível de registradores, limites teóricos vs. práticos e métodos matemáticos de pós-processamento discutidos sobre o projeto do **Problema 02 (TEC513 — Processamento Digital de Sinais)**.

---

## 1. Visão Geral da Arquitetura *Store-and-Forward*

O sistema opera em modo **Store-and-Forward** (armazena em RAM e encaminha em lote), dividindo o trabalho entre o firmware embarcado no **ATmega2560** (`firmware/adc_uart/adc_uart.ino`) e os scripts no **GNU Octave** (`tools/octave/`):

1. **Recepção de Configuração (5 bytes):** O Arduino aguarda via UART (por *polling*) um pacote de 5 bytes enviado pelo Octave:
   - `1 byte` (`uint8_t`): **Prescaler do ADC** (`16`, `32`, `64` ou `128`).
   - `2 bytes` (`uint16_t`, *little-endian*): **Frequência de amostragem solicitada** ($f_s$ em Hz).
   - `2 bytes` (`uint16_t`, *little-endian*): **Quantidade de amostras** ($N$, até `6144`).
2. **Validação e Estabilização:**
   - A função `Capture_Validate()` verifica se os parâmetros respeitam os limites de memória, de frequência mínima e de orçamento de ciclos da CPU. Se forem inválidos, responde imediatamente com `STATUS_ERR_PARAM (0x01)` e aborta.
   - Se o prescaler do ADC mudou em relação à captura anterior, `ADC_SetPrescaler()` atualiza `ADCSRA` e executa **16 leituras de descarte** (`DISCARDED_READS = 16U`) para estabilizar o circuito analógico e absorver os 25 ciclos da primeira conversão.
3. **Amostragem Determinística em RAM (Sem Tráfego UART):**
   - O `Timer1` é acionado em modo **CTC** (`WGM12 = 1`, prescaler `8`) e dispara a interrupção `ISR(TIMER1_COMPA_vect)` na frequência $f_s$.
   - A cada interrupção, a CPU solicita uma conversão ao ADC (`ADC_Read()`), aguarda os $13\text{ ciclos}$ do clock do ADC, lê os 8 bits mais significativos em `ADCH` (`ADLAR = 1`, $V_{\text{ref}} = 2{,}56\text{ V}$) e armazena o byte em `sampling_buffer[write_idx++]`.
   - Durante toda a captura, o `loop()` fica parado em `while (!capture_done);` e a linha UART permanece **100% silenciosa e sem interrupções**.
4. **Verificação de *Overrun* e Transmissão em Lote:**
   - Se em qualquer amostra a flag `OCF1A` do `Timer1` disparar novamente antes do término da ISR atual (`TIFR1 & (1 << OCF1A)`), a captura é abortada imediatamente, o `Timer1` é desligado e o Arduino envia apenas `STATUS_ERR_OVERRUN (0x02)`.
   - Quando o buffer atinge `target_samples`, a própria ISR desliga o `Timer1` e sinaliza `capture_done = 1`. O `loop()` então envia `STATUS_OK (0x00)` seguido dos $N$ bytes de amostras pela UART e volta a aguardar novos 5 bytes.

---

## 2. Limites de Hardware, Memória e Parâmetros no `adc_uart.ino`

| Parâmetro | Limite no Código | Justificativa Técnica |
| :--- | :--- | :--- |
| **SRAM / Tamanho do Buffer (`MAX_BUFFER_SIZE`)** | `1` a `6144` bytes (`4096` padrão) | Dos $8\text{ KiB}$ ($8192\text{ bytes}$) de SRAM do ATmega2560, reservam-se $6\text{ KiB}$ ($6144\text{ bytes}$) para `sampling_buffer`, deixando $2\text{ KiB}$ livres para variáveis globais e pilha (*stack*). |
| **Prescaler do ADC (`prescaler`)** | `16`, `32`, `64` ou `128` | Com $F_{\text{CPU}} = 16\text{ MHz}$ e resolução de 8 bits (`ADLAR = 1`), o datasheet autoriza $f_{\text{ADC}}$ até $1\text{ MHz}$ (`prescaler = 16`), reduzindo o tempo de conversão para $13\text{ }\mu\text{s}$. |
| **Taxa de Amostragem Mínima (`MIN_SAMPLE_RATE`)** | `513 Hz` | Garante a condição $f_s > 512 \cdot f$ para sinais a partir de $f = 1\text{ Hz}$ com valores inteiros de $f_s$. |
| **Taxa de Amostragem Máxima ($f_{s,\text{máx}}$)** | Dinâmica conforme o prescaler:<br>• **$32\,786{,}89\text{ Hz}$** (`prescaler = 16`, $2^{15}\text{ Hz}$ pedido)<br>• $\approx 7\,800\text{ Hz}$ (`prescaler = 128`) | Determinada pela equação de orçamento de ciclos em `Capture_Validate()`:<br>$\text{required\_cycles} = 14 \times \text{prescaler} + 256$.<br>O período do Timer1 (`ticks * 8`) precisa ser maior que `required_cycles`. |

---

## 3. Dúvidas Técnicas sobre o Firmware e a Comunicação Serial

### 3.1. Papel de `asm volatile("" ::: "memory");`
* Trata-se de uma **barreira de memória de compilador** (*compiler memory barrier*) do `avr-gcc`. Ela não gera nenhuma instrução de máquina (custo zero de CPU e de Flash), servindo apenas para proibir o otimizador do compilador de reordenar leituras e escritas na RAM através daquele ponto.
* **Por que aparece duas vezes no `loop()`?**
  1. **Antes de `Timer1_Start(timer_top)`:** Garante que `target_samples = num_samples`, `write_idx = 0`, `capture_error = 0` e `capture_done = 0` já tenham sido gravados na SRAM antes de a primeira interrupção do `Timer1` acontecer.
  2. **Depois de `while (!capture_done)`:** Garante que a leitura de `sampling_buffer[i]` no envio pela UART ocorra estritamente após `capture_done` tornar-se `1`, buscando os valores recém-escritos pela ISR na RAM.

### 3.2. O que é *Jitter* de Amostragem e por que desativar o `Timer0` (`TIMSK0 = 0`)?
* **Jitter de amostragem ($\Delta t_n$):** É a variação no instante exato em que cada amostra é colhida ($t_n = nT_s + \Delta t_n$). Quando o sinal analógico varia com taxa $\frac{dx}{dt}$, um atraso $\Delta t_n$ no disparo produz um erro instantâneo de tensão $\Delta V \approx \frac{dx}{dt}\cdot\Delta t_n$.
* **Interferência do `Timer0`:** O Arduino mantém o `Timer0` ativo por padrão para atualizar `millis()` a cada $1{,}024\text{ ms}$, consumindo $\sim 6\text{ }\mu\text{s}$ dentro de `TIMER0_OVF_vect` com interrupções globais bloqueadas. Se o `Timer1` disparasse durante esse intervalo, a leitura do ADC atrasaria até $6\text{ }\mu\text{s}$ (gerando jitter periódico e causando *overrun* em $32{,}78\text{ kHz}$, onde o período total é de apenas $30{,}5\text{ }\mu\text{s}$).
* **Benefício de `TIMSK0 = 0`:** Torna o `Timer1` a **única** fonte de interrupção ativa no microcontrolador, garantindo latência de disparo constante e determinística.

### 3.3. Formato do Quadro UART `8N1` e Modo `U2X0 = 1`
* **Significado de `8N1`:** Comunicação assíncrona com **1 Start bit** + **8 bits de dados** + **Sem paridade (`N`)** + **1 Stop bit** = **10 bits transmitidos na linha para cada 1 byte de amostra**.
* **Por que usar `8N1`?** Como cada amostra do ADC tem exatamente 8 bits (`uint8_t`, de `0` a `255`), ela cabe inteira em um único quadro sem desperdício de bits extras de paridade ou segundo *stop bit*.
* **Por que `U2X0 = 1` (Velocidade Dupla)?** Em $16\text{ MHz}$, o modo normal (`U2X0 = 0`) gera um erro de baud rate de **$-3{,}55\%$** em `115200 bps` (corrompendo dados). Com `U2X0 = 1` (`UBRR0 = 16`), a taxa efetiva passa a ser **$117\,647\text{ bps}$** ($11\,764{,}7\text{ bytes/s}$, erro de $+2{,}12\%$).

### 3.4. E se o `Timer1` usasse Prescaler `1` ou o ADC operasse em *Free Running*?
* **Prescaler do `Timer1` (`8` vs. `1`):** Mesmo com prescaler `8` ($0{,}5\text{ }\mu\text{s/tick}$), o `Timer1` já conseguiria contar $13\text{ }\mu\text{s}$ (`26 ticks`). O que limita $f_s$ a $32\,786{,}89\text{ Hz}$ (`61 ticks` = $30{,}5\text{ }\mu\text{s}$) é o **orçamento de tempo da ISR** ($14\text{ }\mu\text{s}$ da conversão do ADC + $16\text{ }\mu\text{s}$ reservados em `ISR_BUDGET_CYCLES = 256`). Além disso, com prescaler `1`, o contador de 16 bits estouraria em $4{,}096\text{ ms}$, impedindo taxas menores que $244\text{ Hz}$.
* **Por que não usar *Free Running* ($76\,923\text{ Hz}$)?**
  1. **Ruído de chaveamento digital:** No código atual, a CPU espera parada em `while (ADCSRA & (1 << ADSC));` enquanto o ADC amostra e converte. Em *Free Running*, a CPU gravaria na SRAM e executaria código de interrupção simultaneamente ao fechamento da chave do *Sample & Hold*, injetando ruído digital na conversão.
  2. **Perda de ajuste de $f_s$ e encurtamento da janela:** A $76{,}9\text{ kHz}$, um buffer de $4096\text{ amostras}$ dura apenas **$53{,}2\text{ ms}$**, incapaz de conter 1 ciclo completo de qualquer sinal abaixo de $18{,}8\text{ Hz}$.

---

## 4. Limites Teóricos vs. Práticos, FPS do Osciloscópio e Alternativas em Python

### 4.1. Resumo de Limites ($f_s$, $f_{\text{sinal}}$ e Baud Rate)
1. **Frequência de Amostragem ($f_s$):**
   - **Teto Teórico Puro do ADC (`prescaler = 16`):** $f_{s,\text{máx,teórico}} = \frac{1\text{ MHz}}{13} = \mathbf{76\,923{,}08\text{ Hz}}$ ($13\text{ }\mu\text{s}$).
   - **Teto Prático Determinístico no Firmware:** $f_{s,\text{máx,prático}} = \frac{16\text{ MHz}}{8 \times 61} = \mathbf{32\,786{,}89\text{ Hz}}$ ($30{,}5\text{ }\mu\text{s}$).
2. **Frequência do Sinal Triangular ($f$) para $N = 4096$ e $\ge 512\text{ pontos/ciclo}$:**
   - **Limite Inferior ($f_{\min}$ para caber $\ge 1$ ciclo no buffer):** $f_{\min} = \frac{f_s}{4096}$ ($0{,}125\text{ Hz}$ em $f_s = 513\text{ Hz}$; $2{,}0\text{ Hz}$ em $f_s = 8192\text{ Hz}$).
   - **Limite Superior Prático ($f_{\max}$ para $N_p \ge 512$):** $f_{\max,\text{prático}} = \frac{32\,786{,}89}{512} = \mathbf{64{,}04\text{ Hz}}$ (comprovado pelo ensaio de $60\text{ Hz}$).
   - **Limite Superior Teórico Puro:** $f_{\max,\text{teórico}} = \frac{76\,923{,}08}{512} = \mathbf{150{,}24\text{ Hz}}$.
   - **Por que medir de $1\text{ Hz}$ a $60\text{ Hz}$ é ideal?** O clock do ADC já opera no máximo ($1\text{ MHz}$) em todos os ensaios, e taxas com maior sobreamostragem ($N_p \approx 800\text{ a }2000\text{ amostras/ciclo}$, como em $1\text{ Hz}$ a $10\text{ Hz}$) fornecem muitas visitas por degrau de quantização, produzindo estimativas de DNL/INL estatisticamente muito mais limpas do que operar colado no limiar $N_p = 512$.

### 4.2. Impacto do Baud Rate no FPS do `uart_oscilloscope.m` e Uso de Python
O tempo de atualização de cada quadro no osciloscópio é a soma:
$$T_{\text{frame}} = \underbrace{\frac{N}{f_s}}_{\text{Aquisição ADC}} + \underbrace{\frac{4097 \times 10}{\text{Baud Rate}}}_{\text{Transmissão UART}} + \underbrace{T_{\text{plot}}}_{\text{FFT + Redesenho}}$$
* Em `115200 baud`, o envio de $4097\text{ bytes}$ consome **$348\text{ ms}$**. Em $f_s = 32\,768\text{ Hz}$ ($T_{\text{aq}} = 125\text{ ms}$), a UART representa quase 65% do tempo total ($\sim 1{,}8\text{ FPS}$).
* Subindo para **`1 000 000 baud` ($1\text{ Mbps}$)** ou **`2 000 000 baud` ($2\text{ Mbps}$)**, o tempo de envio cai para **$41\text{ ms}$** (ou **$20{,}5\text{ ms}$**) e o erro de divisão de clock no ATmega2560 ($16\text{ MHz}$) cai para **0,00%** (`UBRR0 = 1` ou `0`).
* **Alternativa moderna em Python:** Enquanto o Octave é limitado pelo pacote `instrument-control` e pelo redesenho na CPU (`drawnow` $\approx 70\text{ ms}$), em **Python** utiliza-se **`pyserial`** (que suporta $1\text{ Mbps}$ e $2\text{ Mbps}$ nativamente) combinado com **`PyQtGraph`** ou **`DearPyGui`** (renderização em GPU/OpenGL em $< 2\text{ ms}$) em *threads* separadas, alcançando até **60 FPS** em tempo real.

---

## 5. Análise Espectral, Distorções, `dBFS` e Métricas Dinâmicas

### 5.1. Onde começam a surgir maiores distorções espectrais?
1. **Janela com menos de 1 ciclo ($f < f_s / 4096$):** Causa forte **vazamento espectral (*spectral leakage*)** na FFT, pois o sinal é truncado no meio de uma rampa.
2. **Sinal próximo ou acima de $f_s / 512$ ($f > 64\text{ Hz}$ em $f_s = 32{,}78\text{ kHz}$):** Passa a saltar níveis de quantização nas rampas ($N_p < 512$) e as harmônicas ímpares de ordem alta da onda triangular ($3f, 5f, 7f, \dots$) ultrapassam a frequência de Nyquist ($f_s / 2$), dobrando de volta para dentro do espectro (*aliasing* harmônico) e elevando o piso de ruído.
3. **Clock do ADC acima de $1\text{ MHz}$ (`prescaler < 16`):** O DAC interno e o capacitor de *Sample & Hold* ($14\text{ pF}$) não têm tempo de estabilizar a tensão antes da decisão do comparador SAR, gerando não-linearidade severa.

### 5.2. O que é a FFT em `dBFS`?
* No gráfico da FFT, o **eixo X** continua sendo a **Frequência em $\text{Hz}$**.
* O **eixo Y** utiliza a escala logarítmica **$\text{dBFS}$ (*Decibels relative to Full Scale*)**, onde $0\text{ dBFS}$ corresponde à amplitude máxima de fundo de escala do ADC ($127{,}5\text{ LSB}$ de pico AC):
  $$\text{Magnitude (dBFS)} = 20 \cdot \log_{10}\!\left(\frac{\text{Amplitude Linear}}{127{,}5}\right)$$
* Isso permite enxergar simultaneamente o pico da frequência fundamental (próximo de $-1{,}9\text{ dBFS}$) e o piso de ruído/espúrios (entre $-60\text{ dBFS}$ e $-85\text{ dBFS}$, que são milhares de vezes menores e ficariam invisíveis numa escala vertical linear).
* No `uart_oscilloscope.m` ela é chamada de **"FFT rápida"** porque calcula apenas 1 FFT (do sinal bruto) para economizar CPU, enquanto o `adc_analyzer.m` calcula **3 FFTs simultâneas** (sinal do ADC, triangular ideal quantizada e triangular contínua).

### 5.3. Significado de DR, SNR, THD, SINAD, ENOB e SFDR (e Escopo no Problema 02)
* **O que é obrigatório pelo enunciado (`tec513_2026_2_problema_02.pdf`, Seção 2.4, Item 6):** Determinar a **Faixa Dinâmica (DR)**, o **tempo de conversão** e a **taxa de amostragem máxima**, além dos erros estáticos (Item 5: Offset, Ganho, DNL, INL e Monotonicidade) e da comparação no tempo e na frequência (Seção 2.6).
* **As demais siglas (SNR, THD, SINAD, SFDR, ENOB)** foram incluídas no `adc_analyzer.m` como complemento da norma **IEEE Std 1241**:
  - **DR (*Dynamic Range* — Obrigatório):** Razão em dB entre a potência de fundo de escala e o piso de ruído do conversor ($\approx 49{,}92\text{ dB}$ teórico em 8 bits; **$46{,}4\text{ a }48{,}3\text{ dB}$** medidos no projeto).
  - **SNR (*Signal-to-Noise Ratio*):** Razão entre a potência do sinal e a potência do ruído térmico/quantização (excluindo harmônicas).
  - **THD (*Total Harmonic Distortion*):** Razão entre a soma das potências das harmônicas e a potência da fundamental (usada classicamente para entrada senoidal).
  - **SINAD (*Signal-to-Noise and Distortion Ratio*):** Razão em dB entre a potência do sinal ideal e o erro quadrático médio total (ruído + distorção).
  - **ENOB (*Effective Number of Bits*):** Quantidade de bits efetivos que o ADC entrega na prática a partir do SINAD ($\text{ENOB} \approx 7{,}5\text{ a }7{,}7\text{ bits}$ medidos nos candidatos principais).
  - **SFDR (*Spurious-Free Dynamic Range*):** Distância em dB (`dBc`) entre o pico da fundamental e o maior espúrio fora das harmônicas da onda triangular.

---

## 6. Métodos Empregados para Cada Medição nos Scripts do Octave

| Medição / Etapa | Arquivo em `tools/octave/` | Método Matemático / Algoritmo Empregado |
| :--- | :--- | :--- |
| **1. Taxa de Amostragem Efetiva ($f_{s,\text{efetiva}}$)** | `uart_capture.m` | Replica o arredondamento inteiro do `Timer1` (`ticks = floor(16e6 / (8 * fs) + 0.5)`) e calcula $f_{s,\text{efetiva}} = \frac{16\text{ MHz}}{8 \cdot \text{ticks}}$. |
| **2. Trigger e Cruzamentos de Borda** | `src/triggering/detectSignalTrigger.m` | Define o limiar em $50\%$ da excursão ($0{,}5(s_{\max}+s_{\min})$) com **histerese de $\pm 8\% V_{pp}$** (mín. $2\text{ LSB}$) para rejeitar ruído, e encontra o instante exato de cruzamento por **interpolação linear sub-amostra**. |
| **3. Período ($T_p$), Frequência ($f$) e Fase ($\phi_0$)** | `src/triggering/estimateSignalPeriod.m` | **Estágio 1:** Mediana das diferenças entre cruzamentos de subida/descida (ou regressão linear `polyfit` da inclinação das rampas caso haja $< 1$ ciclo).<br>**Estágio 2 (modo `"opt"`):** Busca em grade de 240 fases seguida de otimização não-linear Simplex (`fminsearch`) minimizando o MSE contra o modelo triangular contínuo. |
| **4. Sinais Ideais de Referência** | `src/conditioning/generateIdealReference.m` | Avalia a equação analítica da onda triangular contínua $y_{\text{cont}}(n) \in [0, 255]$ com o período $T_p$ e fase $\phi_0$ otimizados, e obtém a versão quantizada ideal por arredondamento inteiro `round(y_cont)`. |
| **5. Erro de Ganho e Erro de Offset** | `src/conditioning/computeStaticAndTimeErrors.m` | **Regressão linear por mínimos quadrados** ($y_{\text{ADC}} \approx G \cdot y_{\text{ideal}} + b$) restrita à região central livre de saturação ($10 \le y_{\text{ideal}} \le 245$).<br>• $\text{Erro de Ganho} = (G - 1) \times 255\text{ [LSB]}$<br>• $\text{Erro de Offset} = (G \cdot 127{,}5 + b) - 127{,}5\text{ [LSB]}$ |
| **6. RMSE Bruto, RMSE Residual e MAE** | `src/conditioning/computeStaticAndTimeErrors.m` | Diferença ponto a ponto no tempo: $e_{\text{bruto}}(n) = y_{\text{ADC}}(n) - y_{\text{cont}}(n)$ e $e_{\text{residual}}(n) = y_{\text{ADC}}(n) - \text{clip}_{[0,255]}(G\cdot y_{\text{cont}}(n)+b)$, extraindo raiz da média quadrática (RMSE) e média absoluta (MAE). |
| **7. DNL, INL, *Missing Codes* e Monotonicidade** | `src/linearity/computeHistogramLinearity.m` | **Teste de Histograma Linear (IEEE Std 1241)** recortado sobre um número inteiro de períodos ($\lfloor N/T_p\rfloor \cdot T_p$):<br>• $\text{DNL}(k) = \frac{H(k)}{\overline{H}} - 1$ nos códigos internos $[k_{\min}+1, k_{\max}-1]$.<br>• $\text{INL}(k) = \sum_{j} (\text{DNL}(j) - \overline{\text{DNL}})$ (soma acumulada `cumsum`).<br>• *Missing Codes*: contagem de níveis internos com $H(k) = 0$ ($\text{DNL} = -1\text{ LSB}$).<br>• Monotonicidade: ausência de *missing codes* e de inversões $> 0{,}5\text{ LSB}$ na curva de transferência média por nível. |
| **8. Espectro (FFT Tripla) e Faixa Dinâmica (DR)** | `src/spectral/computeSpectralMetrics.m` | Remove DC, aplica **janela de Hann**, calcula a FFT de $N$ pontos normalizada em $\text{dBFS}$ e **mascara $\pm 3\text{ bins}$ ao redor de todas as harmônicas da triangular** ($k \cdot f_0$), integrando a potência de Parseval nos bins restantes para obter o piso de ruído puro ($P_{\text{ruído}}$) e calcular $\text{DR} = 10\log_{10}\!\left(\frac{127{,}5^2/2}{P_{\text{ruído}}}\right)$. |
