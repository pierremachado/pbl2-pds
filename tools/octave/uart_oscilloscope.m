pkg load instrument-control;

% --- CONFIGURAÇÕES ---
% Ajuste a porta conforme o seu sistema operacional:
% Windows: "COM3", "COM4", etc.
% Linux/macOS: "/dev/ttyACM0", "/dev/ttyUSB0", etc.
serial_port = "/dev/ttyUSB0";
baud_rate = 115200;

signal_frequency = 1;
sampling_frequency = 2000;
adc_prescaler = 16;
sample_amount = 4096;

config_packet = [uint8(adc_prescaler), ...
                 typecast(uint16(sampling_frequency), "uint8"), ...
                 typecast(uint16(sample_amount), "uint8")];

% --- ABERTURA DA PORTA SERIAL ---
disp("Conectando à porta serial...");
s = serial(serial_port, baud_rate);
set(s, 'timeout', 50);
pause(2);

% --- CRIAÇÃO DA INTERFACE DO OSCILOSCÓPIO ---
fig = figure("name", "Osciloscópio Digital - ATmega2560", ...
             "numbertitle", "off", ...
             "position", [100, 100, 950, 650]);

% Área do gráfico na parte superior (deixa a parte inferior para os controles)
ax = axes("parent", fig, "position", [0.08, 0.32, 0.88, 0.62]);
hold(ax, "on");
plot_handle = stairs(ax, 0:(sample_amount - 1), zeros(sample_amount, 1), "linewidth", 1.2);
trigger_line = plot(ax, [0, sample_amount - 1], [128, 128], "--r", "linewidth", 1);
hold(ax, "off");
grid(ax, "on");
title(ax, sprintf("Osciloscópio Digital - ATmega2560 (fs = %d Hz, Prescaler = %d)", ...
                  sampling_frequency, adc_prescaler));
xlabel(ax, "Índice da Amostra");
ylabel(ax, "Nível Digital (0 a 255)");

% --- PAINEL DE CONTROLES (SLIDERS E BOTÃO PAUSAR) ---
% Coluna esquerda: Horizontal (Escala e Posição) + Trigger
uicontrol(fig, "style", "text", "units", "normalized", ...
          "position", [0.05, 0.19, 0.16, 0.035], "string", "Escala Horiz. (N):");
sld_h_scale = uicontrol(fig, "style", "slider", "units", "normalized", ...
                        "position", [0.22, 0.19, 0.24, 0.035], ...
                        "min", 32, "max", sample_amount, "value", sample_amount);

uicontrol(fig, "style", "text", "units", "normalized", ...
          "position", [0.05, 0.12, 0.16, 0.035], "string", "Posição Horiz.:");
sld_h_pos = uicontrol(fig, "style", "slider", "units", "normalized", ...
                      "position", [0.22, 0.12, 0.24, 0.035], ...
                      "min", 0, "max", sample_amount - 32, "value", 0);

uicontrol(fig, "style", "text", "units", "normalized", ...
          "position", [0.05, 0.05, 0.16, 0.035], "string", "Nível de Trigger:");
sld_trigger = uicontrol(fig, "style", "slider", "units", "normalized", ...
                        "position", [0.22, 0.05, 0.24, 0.035], ...
                        "min", 0, "max", 255, "value", 128);

% Coluna direita: Vertical (Escala e Posição) + Botão Pausar
uicontrol(fig, "style", "text", "units", "normalized", ...
          "position", [0.50, 0.19, 0.16, 0.035], "string", "Escala Vert. (Amp):");
sld_v_scale = uicontrol(fig, "style", "slider", "units", "normalized", ...
                        "position", [0.67, 0.19, 0.24, 0.035], ...
                        "min", 10, "max", 300, "value", 275);

uicontrol(fig, "style", "text", "units", "normalized", ...
          "position", [0.50, 0.12, 0.16, 0.035], "string", "Posição Vert. (Centro):");
sld_v_pos = uicontrol(fig, "style", "slider", "units", "normalized", ...
                      "position", [0.67, 0.12, 0.24, 0.035], ...
                      "min", 0, "max", 255, "value", 127.5);

btn_pause = uicontrol(fig, "style", "togglebutton", "units", "normalized", ...
                      "position", [0.50, 0.04, 0.41, 0.05], ...
                      "string", "PAUSAR / CONTINUAR", "value", 0);

samples = zeros(sample_amount, 1);

disp("Osciloscópio ativo! Feche a janela do gráfico para encerrar.");

% --- LOOP PRINCIPAL DO OSCILOSCÓPIO ---
while ishandle(fig)
    is_paused = get(btn_pause, "value");

    if ~is_paused
        srl_flush(s);
        fwrite(s, config_packet, "uint8");
        status = fread(s, 1, "uint8");

        if isempty(status) || status ~= 0
            if isempty(status)
                disp("Timeout na comunicação serial! Quadro descartado.");
            elseif status == 1
                disp("Parâmetros inválidos reportados pelo Arduino (STATUS_ERR_PARAM)! Quadro descartado.");
            elseif status == 2
                disp("Perda de sincronismo (T_conv > T_s) detectada pelo Arduino! Quadro descartado.");
            else
                printf("Erro desconhecido recebido (status = %d)! Quadro descartado.\n", status);
            end
            continue;
        end

        new_samples = fread(s, sample_amount, "uint8");

        if length(new_samples) == sample_amount
            samples = new_samples;
        else
            disp("Perda de dados detectada! Quadro descartado.");
            continue;
        end
    else
        pause(0.05);
    end

    if ~ishandle(fig)
        break;
    end

    % Lê valores atuais dos sliders
    trig_level = get(sld_trigger, "value");
    h_scale = round(get(sld_h_scale, "value"));
    h_pos = round(get(sld_h_pos, "value"));
    v_scale = get(sld_v_scale, "value");
    v_pos = get(sld_v_pos, "value");

    % Alinhamento por Trigger (borda de subida cruzando trig_level)
    trig_idx = find(samples(1:end-1) < trig_level & samples(2:end) >= trig_level, 1, "first");
    if isempty(trig_idx)
        trig_idx = 1;
    end

    % Desloca o sinal para iniciar no ponto de trigger
    aligned_samples = [samples(trig_idx:end); samples(1:trig_idx-1)];

    % Atualiza curva, linha de trigger e limites dos eixos (escala/posição)
    set(plot_handle, "ydata", aligned_samples);
    set(trigger_line, "ydata", [trig_level, trig_level]);

    x_start = max(0, min(h_pos, sample_amount - h_scale));
    xlim(ax, [x_start, x_start + h_scale]);
    ylim(ax, [v_pos - v_scale / 2, v_pos + v_scale / 2]);

    drawnow;
end

% --- FECHAMENTO DA CONEXÃO ---
disp("Janela fechada. Encerrando conexão serial...");
fclose(s);
clear s;
