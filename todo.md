# TODO — fechamento do PBL 2

Atualizado em 05/11/2026

## Apresentação

- [ ] Preencher os slides vazios: faixa dinâmica, tempo de conversão, taxa máxima, registradores, UART, comparações de offset/ganho/DNL/INL e monotonicidade.
- [ ] Inserir os gráficos experimentais copiados para `outputs/`, distinguindo os 13 ensaios principais dos 4 contraexemplos.
- [ ] Acrescentar conclusões, limitações e roteiro de demonstração.
- [ ] Uniformizar unidades e condições dos valores do datasheet (LSB de 10 bits versus leitura de 8 bits).
- [ ] Compilar o Beamer e revisar cortes, legibilidade, referências e duração da apresentação.

## Requisitos e metodologia

- [ ] Conferir o enunciado oficial e mapear cada requisito para código, ensaio e evidência; o PDF citado no relatório não está no diretório analisado.
- [ ] Confirmar a interpretação de 0,39%: degrau aproximado ou limite estrito; a justificativa agora explicita essa diferença.
- [ ] Revisar o rótulo de offset: o cálculo atual representa desvio no centro da escala e inclui contribuição do ganho.
- [ ] Uniformizar nos painéis/tabelas os rótulos “intrínseco” e “residual após ajuste”, preservando compatibilidade dos campos salvos.
- [ ] Revisar a influência do ajuste de período/fase, ganho/offset e clipping nas métricas residuais e no ENOB triangular.
- [ ] Separar códigos não observados no registro de códigos fisicamente ausentes; indicar faixa coberta e insuficiência de dados nas capturas parciais.
- [ ] Rever o indicador de monotonicidade: tolerância de inversão de 0,5 LSB e associação atual com ausência de códigos no histograma.
- [ ] Quantificar a sensibilidade de DNL/INL ao número de amostras e à relação entre frequências; não tratar poucos ciclos como prova geral.
- [ ] Documentar as hipóteses das máscaras espectrais e sua influência na estimativa de DR; não apresentar ENOB adaptado como ensaio senoidal padronizado.
- [ ] Usar as repetições arquivadas para avaliar dispersão e justificar a seleção dos ensaios principais.

## Bancada e reprodução

- [ ] Relacionar cada captura MAT à medição correspondente do osciloscópio, amplitude, offset e configuração do gerador.
- [ ] Registrar instrumentos e incertezas; validar independentemente a referência estimada em aproximadamente 2,31 V.
- [ ] Explicitar que a frequência efetiva calculada usa clock nominal de 16 MHz; verificar desvios frente à frequência de bancada.
- [ ] Documentar versões do Octave, pacote instrument-control, toolchain AVR e procedimento de compilação/gravação.
- [ ] Compilar o firmware, conferir uso de RAM e verificar temporização da ISR e detecção de overrun na configuração usada.
- [ ] Validar aquisição física, interface gráfica e exportação completa antes da demonstração.

## Realizado nesta revisão

- [x] Apresentar o degrau de 8 bits como aproximadamente 0,39%, explicitando o arredondamento.
- [x] Corrigir os intervalos da conclusão para incluir os 13 ensaios principais.
- [x] Reproduzir RMSE residual, ENOB, DR e contagem de códigos ausentes das 17 capturas selecionadas com o analisador existente.