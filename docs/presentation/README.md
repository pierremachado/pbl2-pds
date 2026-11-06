# Apresentação do Problema 02

O arquivo principal é `main.tex`. Os complementos estão em `resultados/*.tex`, inseridos nos espaços vazios e entre os slides existentes. O texto anterior foi preservado. Foi acrescentado um `\item` ausente no slide de caracterização do ganho para permitir a compilação.

## Compilação

Execute dentro de `docs/presentation`:

```bash
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

Alternativamente, use `tectonic main.tex`. O `main.pdf` versionado foi compilado com Tectonic 0.15.0. A apresentação mantém o tema Madrid e tem 47 slides, incluindo capa, sumários e referências.

## Dados e imagens

- Os gráficos de tempo, FFT, DNL, INL e transferência usam `../../tools/octave/data/sample_20261106_102822_177.mat`, por meio dos arquivos numéricos em `resultados/`.
- A comparação anterior de 10 Hz usa `adc_f10Hz_fs08192Hz_pre16.mat`. Os demais ensaios selecionados usam a tabela `../../tools/octave/outputs/adc_summary_metrics.csv`.
- O exemplo de saturação usa `contraex_saturado_2v56_f05Hz_fs02000Hz.mat`.
- As três fotografias em `Imagens/bancada/` foram fornecidas durante a medição de 06/11/2026. As duas primeiras mostram a bancada sem e com Arduino em paralelo. A terceira registra máximo, mínimo, pico a pico e média.
- As figuras teóricas em `Imagens/1.png` a `7.png` e suas referências são as que já constavam na apresentação.

Para regenerar os dados dos gráficos, a partir da raiz do repositório:

```bash
octave --no-gui --quiet docs/presentation/resultados/exportar_dados.m
```

Os gráficos são desenhados pelo PGFPlots a partir desses dados, sem alterar as amostras originais.

## Fontes e interpretação

Os complementos usam os relatórios em `../reports/`, o enunciado do Problema 02, o firmware e os datasheets arquivados em `../datasheets/`. A organização e a escrita seguem a apresentação do primeiro PBL e os slides já existentes.

A edição arquivada do datasheet do ATmega2560 é **2549Q–AVR–02/2014**. Na tabela **31-9, p. 365**, os valores típicos de offset, ganho, INL e DNL são dados em condições de 10 bits, Vref/Vcc de 4 V e clock ADC de 200 kHz. O projeto lê 8 bits e usa clock ADC de 1 MHz. A apresentação explicita essa diferença.

Essa mesma tabela informa **2,4 a 2,8 V** para a referência interna nominal de 2,56 V em entrada simples. O mínimo de **2,3 V** aparece na tabela de canais diferenciais. Por isso, a apresentação não repete a afirmação do relatório de que uma estimativa de 2,31 V confirma atendimento à faixa da entrada simples.

Os **2,30 Vpp** da foto são uma medição do sinal, não uma medição independente da referência. O RMSE residual não isola o erro do ADC, e os valores de DR/ENOB dependem do modelo triangular empregado. A frequência de amostragem calculada considera clock nominal de 16 MHz.
