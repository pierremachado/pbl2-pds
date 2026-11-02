"""Recebe ADC de 8 bits em formato binario: um byte por amostra.

Instalacao: python -m pip install pyserial matplotlib
Uso: python uart_plotter.py /dev/ttyACM0
Windows: python uart_plotter.py COM3
"""

import argparse
import math
import threading
from collections import deque

import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation
from matplotlib.widgets import TextBox
import serial

BAUD = 9600
FPS = 5
BUFFER_SIZE = 32768  # Buffer circular: descarta as amostras mais antigas.


def receber(porta, buffer, lock, parar, erros):
    """Leitura independente da velocidade de desenho do grafico."""
    try:
        while not parar.is_set():
            dados = porta.read(min(4096, max(1, porta.in_waiting)))
            if dados:
                with lock:
                    buffer.extend(dados)  # bytes -> inteiros entre 0 e 255
    except (serial.SerialException, OSError) as exc:
        with lock:
            erros.append(str(exc))
        parar.set()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("porta", help="Ex.: /dev/ttyACM0 ou COM3")
    args = parser.parse_args()

    try:
        porta = serial.Serial(args.porta, BAUD, timeout=0.1)
    except (serial.SerialException, OSError) as exc:
        parser.exit(1, f"Nao foi possivel abrir a porta: {exc}\n")

    buffer = deque(maxlen=BUFFER_SIZE)
    lock = threading.Lock()
    parar = threading.Event()
    erros = []
    estado = {"janela": 2048}
    thread = threading.Thread(
        target=receber, args=(porta, buffer, lock, parar, erros), daemon=True
    )

    fig, ax = plt.subplots(figsize=(10, 5))
    fig.subplots_adjust(bottom=0.28)
    linha, = ax.plot([], [], linewidth=1)
    ax.set(title="UART - ADC de 8 bits", xlabel="Amostra na janela", ylabel="Codigo ADC")
    ax.set_xlim(0, estado["janela"] - 1)
    ax.set_ylim(0, 255)
    ax.grid(True, alpha=0.3)
    status = fig.text(0.1, 0.04, "Aguardando dados...")

    # Digite e pressione Enter para aplicar os limites.
    campo_x = TextBox(fig.add_axes([0.15, 0.14, 0.17, 0.055]), "N (X): ", initial="2048")
    campo_ymin = TextBox(fig.add_axes([0.46, 0.14, 0.13, 0.055]), "Y min: ", initial="0")
    campo_ymax = TextBox(fig.add_axes([0.76, 0.14, 0.13, 0.055]), "Y max: ", initial="255")

    def ajustar(_):
        try:
            janela = int(campo_x.text)
            ymin, ymax = float(campo_ymin.text), float(campo_ymax.text)
            if not 2 <= janela <= BUFFER_SIZE:
                raise ValueError(f"N deve estar entre 2 e {BUFFER_SIZE}.")
            if not (math.isfinite(ymin) and math.isfinite(ymax) and ymin < ymax):
                raise ValueError("Y min deve ser menor que Y max; use valores finitos.")
            estado["janela"] = janela
            ax.set_xlim(0, janela - 1)
            ax.set_ylim(ymin, ymax)
            estado.pop("aviso", None)
        except ValueError as exc:
            estado["aviso"] = f"Limites invalidos: {exc}"
        fig.canvas.draw_idle()

    for campo in (campo_x, campo_ymin, campo_ymax):
        campo.on_submit(ajustar)

    def atualizar(_):
        with lock:
            valores = list(buffer)[-estado["janela"]:]
            erro = erros[-1] if erros else None
        linha.set_data(range(len(valores)), valores)
        status.set_text(
            f"Serial desconectada: {erro}" if erro else estado.get(
                "aviso", f"{len(valores)} amostras visiveis | {FPS} FPS (alvo)"
            )
        )
        return linha, status

    # Mantenha esta referencia viva enquanto a janela estiver aberta.
    animacao = FuncAnimation(
        fig, atualizar, interval=1000 / FPS, blit=False, cache_frame_data=False
    )
    thread.start()
    try:
        plt.show()
    finally:
        parar.set()
        thread.join(timeout=1)
        porta.close()


if __name__ == "__main__":
    main()
