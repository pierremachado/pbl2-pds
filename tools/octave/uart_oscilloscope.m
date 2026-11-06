pkg load instrument-control;

% =========================================================================
% UART_OSCILLOSCOPE - Osciloscópio Digital Leve em Tempo Real (ATmega2560)
%
% Focado em inspeção rápida de bancada com 2 gráficos em tempo real:
%   1. Forma de onda alinhada por Trigger Auto + Referência Ideal
%   2. Espectro de Magnitude via FFT (dBFS)
% Utiliza uart_capture.m para aquisição e salvamento direto em /data (.mat)
% e delega o condicionamento profundo de dados ao adc_analyzer.m.
% =========================================================================

base_dir = fileparts(mfilename("fullpath"));
if isempty(base_dir)
    base_dir = pwd();
end
addpath(base_dir);
addpath(genpath(fullfile(base_dir, "src")));
addpath(fullfile(base_dir, "utils"));
output_dir = fullfile(base_dir, "outputs");

% --- CONFIGURAÇÕES DE COMUNICAÇÃO E AMOSTRAGEM ---
serial_port        = "/dev/ttyUSB0";
baud_rate          = 115200;
sampling_frequency = 2^13; % 8192 Hz
adc_prescaler      = 16;
sample_amount      = 4096;
VREF               = 2.56;
LSB_MV             = (VREF / 256.0) * 1e3;

% --- ABERTURA DA PORTA SERIAL ---
disp("Conectando à porta serial...");
s = serial(serial_port, baud_rate);
set(s, "timeout", 50);
pause(2);

% --- CRIAÇÃO DA JANELA DO OSCILOSCÓPIO (2 GRÁFICOS + TELEMETRIA DE BANCADA) ---
fig = figure("name", "Osciloscópio Digital UART em Tempo Real (ATmega2560)", ...
             "numbertitle", "off", ...
             "color", [0.95, 0.96, 0.98], ...
             "position", [60, 60, 1280, 720]);

% 1. GRÁFICO ESQUERDO: Forma de Onda + Referência Ideal + Trigger
ax_wave = axes("parent", fig, "position", [0.05, 0.36, 0.52, 0.57]);
hold(ax_wave, "on");
x_init = (0:(sample_amount - 1))';
y_init = zeros(sample_amount, 1);
h_ideal = plot(ax_wave, x_init, y_init, "--", "color", [0.15, 0.65, 0.25], "linewidth", 1.3);
h_wave  = stairs(ax_wave, x_init, y_init, "color", [0.05, 0.30, 0.85], "linewidth", 1.1);
h_trig  = plot(ax_wave, [0, sample_amount - 1], [127.5, 127.5], ":r", "linewidth", 1.1);
hold(ax_wave, "off");
grid(ax_wave, "on");
ylim(ax_wave, [-10, 265]);
xlim(ax_wave, [0, 1536]);
xlabel(ax_wave, "Índice da Amostra (após Trigger Auto)");
ylabel(ax_wave, "Código ADC (0 a 255)");
title(ax_wave, "1. Forma de Onda no Tempo (Azul: ADC | Verde: Referência Ideal)");
legend(ax_wave, {"Referência Ideal", "Sinal ADC (8 bits)", "Nível de Trigger"}, "location", "northeast");

% 2. GRÁFICO DIREITO: Espectro FFT de Magnitude (dBFS)
ax_fft = axes("parent", fig, "position", [0.63, 0.36, 0.34, 0.57]);
hold(ax_fft, "on");
h_fft_mag  = plot(ax_fft, [0, 1], [-100, -100], "-b", "linewidth", 1.1);
h_fft_peak = plot(ax_fft, 0, 0, "ro", "markersize", 6, "linewidth", 1.5);
hold(ax_fft, "off");
grid(ax_fft, "on");
ylim(ax_fft, [-100, 5]);
xlabel(ax_fft, "Frequência (Hz)");
ylabel(ax_fft, "Magnitude (dBFS)");
title(ax_fft, "2. Espectro de Magnitude (FFT Rápida)");

% 3. PAINEL DE TELEMETRIA BÁSICA DE BANCADA
pnl_info = uipanel("parent", fig, "title", "Telemetria Básica de Bancada (Vref = 2.56 V | 1 LSB = 10 mV)", ...
                   "units", "normalized", "position", [0.05, 0.11, 0.92, 0.18], ...
                   "backgroundcolor", [0.10, 0.12, 0.16], ...
                   "foregroundcolor", [0.90, 0.95, 1.00]);

txt_left = uicontrol("parent", pnl_info, "style", "text", ...
                     "units", "normalized", "position", [0.02, 0.05, 0.46, 0.90], ...
                     "horizontalalignment", "left", "fontname", "FixedWidth", "fontsize", 9.5, ...
                     "backgroundcolor", [0.10, 0.12, 0.16], "foregroundcolor", [0.35, 1.00, 0.55], ...
                     "string", "Aguardando captura...");

txt_right = uicontrol("parent", pnl_info, "style", "text", ...
                      "units", "normalized", "position", [0.52, 0.05, 0.46, 0.90], ...
                      "horizontalalignment", "left", "fontname", "FixedWidth", "fontsize", 9.5, ...
                      "backgroundcolor", [0.10, 0.12, 0.16], "foregroundcolor", [0.45, 0.90, 1.00], ...
                      "string", "");

% 4. CONTROLES INFERIORES
uicontrol(fig, "style", "text", "units", "normalized", "position", [0.05, 0.03, 0.08, 0.04], ...
          "backgroundcolor", [0.95, 0.96, 0.98], "string", "Janela (Zoom):");
sld_win = uicontrol(fig, "style", "slider", "units", "normalized", "position", [0.13, 0.03, 0.18, 0.04], ...
                    "min", 16, "max", sample_amount, "value", 1536, ...
                    "sliderstep", [max(1 / sample_amount, 0.01), 0.10]);

uicontrol(fig, "style", "text", "units", "normalized", "position", [0.33, 0.03, 0.07, 0.04], ...
          "backgroundcolor", [0.95, 0.96, 0.98], "string", "Pan/Scroll:");
sld_pan = uicontrol(fig, "style", "slider", "units", "normalized", "position", [0.40, 0.03, 0.18, 0.04], ...
                    "min", 0, "max", sample_amount - 1536, "value", 0, ...
                    "sliderstep", [max(1 / (sample_amount - 1536), 0.01), 0.10]);

btn_pause = uicontrol(fig, "style", "togglebutton", "units", "normalized", ...
                      "position", [0.62, 0.025, 0.16, 0.05], "string", "PAUSAR / CONTINUAR", "value", 0);

btn_save = uicontrol(fig, "style", "togglebutton", "units", "normalized", ...
                     "position", [0.80, 0.025, 0.17, 0.05], ...
                     "backgroundcolor", [0.20, 0.55, 0.30], "foregroundcolor", [1, 1, 1], ...
                     "string", "CAPTURAR E SALVAR", "value", 0);

has_valid_frame = false;
prev_win_len    = -1;
prev_pan_start  = -1;
disp("Osciloscópio ativo! Use 'CAPTURAR E SALVAR' para gravar via uart_capture e depois analise com adc_analyzer.");

unwind_protect
    while ishandle(fig)
        is_paused      = get(btn_pause, "value");
        do_save_now    = (get(btn_save, "value") == 1);
        new_frame_read = false;

        if ~is_paused || do_save_now
            % Delega a captura (e o salvamento do .mat quando solicitado) diretamente ao uart_capture.m
            [captured_samples, actual_sampling_frequency, cap_status, saved_mat_path] = ...
                uart_capture(sampling_frequency, adc_prescaler, sample_amount, s, do_save_now, false);

            if do_save_now
                set(btn_save, "value", 0);
            end

            if cap_status ~= 0 || isempty(captured_samples)
                pause(0.04);
                continue;
            end

            samples        = captured_samples;
            has_valid_frame = true;
            new_frame_read  = true;

            % Usa os módulos compartilhados de src/ em modo rápido ("trig")
            trig = detectSignalTrigger(samples);
            per  = estimateSignalPeriod(samples, actual_sampling_frequency, trig, "trig");
            ref  = generateIdealReference(samples, trig, per, VREF);
            err  = computeStaticAndTimeErrors(samples, trig, per, ref, LSB_MV);

            % FFT rápida apenas do sinal capturado para visualização no osciloscópio
            N_fft = sample_amount;
            win_hann = 0.5 * (1.0 - cos(2.0 * pi * (0:(N_fft - 1))' / (N_fft - 1)));
            Y_half = fft((samples - mean(samples)) .* win_hann)(1:(floor(N_fft / 2) + 1));
            freq_axis = (0:(numel(Y_half) - 1))' * (actual_sampling_frequency / N_fft);
            mag_lin = abs(Y_half) / (N_fft * mean(win_hann) / 2.0);
            mag_dbfs = 20.0 * log10(max(mag_lin / 127.5, 1e-6));
            [~, fund_bin] = max(mag_lin(2:end));
            fund_bin = fund_bin + 1;

            if do_save_now && ~isempty(saved_mat_path)
                if ~exist(output_dir, "dir")
                    mkdir(output_dir);
                end
                [~, base_name, ~] = fileparts(saved_mat_path);
                png_path = fullfile(output_dir, [base_name, "_osc.png"]);
                print(fig, png_path, "-dpng", "-r150");
                printf("Tela do osciloscópio salva em: %s\n", png_path);
            end
        else
            pause(0.04);
        end

        if ~ishandle(fig) || ~has_valid_frame
            drawnow;
            continue;
        end

        % Atualização dos 2 gráficos rápidos e sincronia dos sliders de Zoom/Pan
        valid_len = numel(per.x_plot);
        win_len   = max(16, min(round(get(sld_win, "value")), valid_len));
        max_pan   = max(0, valid_len - win_len);
        pan_start = min(round(get(sld_pan, "value")), max_pan);

        slider_max_pan = max(1, max_pan);
        if abs(get(sld_pan, "max") - slider_max_pan) > 0.5
            set(sld_pan, "max", slider_max_pan, "value", pan_start, ...
                         "sliderstep", [max(1 / slider_max_pan, 0.01), 0.10]);
        elseif get(sld_pan, "value") > max_pan
            set(sld_pan, "value", pan_start);
        end

        sliders_changed = (win_len ~= prev_win_len) || (pan_start ~= prev_pan_start);

        if new_frame_read || sliders_changed
            set(h_ideal, "xdata", per.x_plot, "ydata", ref.ideal_cont_plot);
            set(h_wave,  "xdata", per.x_plot, "ydata", per.y_plot);
            set(h_trig,  "xdata", [0, max(1, valid_len - 1)], "ydata", [trig.trig_level, trig.trig_level]);
            xlim(ax_wave, [pan_start, pan_start + win_len]);
            ylim(ax_wave, [-10, 265]);

            if new_frame_read
                f_max_view = min(actual_sampling_frequency / 2.0, max(200.0, 18.0 * per.freq_hz));
                set(h_fft_mag,  "xdata", freq_axis, "ydata", mag_dbfs);
                set(h_fft_peak, "xdata", freq_axis(fund_bin), "ydata", mag_dbfs(fund_bin));
                xlim(ax_fft, [0, f_max_view]);
                ylim(ax_fft, [-100, 5]);

                % Atualização da telemetria básica de bancada
                set(txt_left, "string", sprintf([ ...
                    "FREQUÊNCIA MEDIDA : f = %.2f Hz (Pico FFT: %.2f Hz)\n", ...
                    "PERÍODO DO SINAL  : T = %.2f ms (%.1f amostras/ciclo)\n", ...
                    "TAXA AMOSTRAGEM   : fs = %.1f Hz (Prescaler = %d)\n", ...
                    "STATUS DO TRIGGER : %s (Nível = %.1f LSB)"], ...
                    per.freq_hz, freq_axis(fund_bin), ...
                    per.period_sec * 1e3, per.period_samples, ...
                    actual_sampling_frequency, adc_prescaler, ...
                    trig.trig_str, trig.trig_level));

                set(txt_right, "string", sprintf([ ...
                    "EXCURSÃO (CÓDIGOS): Min = %.0f | Max = %.0f | Vpp = %.0f LSB\n", ...
                    "EXCURSÃO (TENSÃO) : %.2f V a %.2f V (Vpp = %.2f V)\n", ...
                    "ERRO DE OFFSET    : %+.2f LSB (%+.1f mV | %+.2f %%FSR)\n", ...
                    "ERRO GANHO / RMSE : %+.2f LSB (G=%.4f) | RMSE = %.2f LSB"], ...
                    trig.s_min, trig.s_max, trig.s_vpp, ...
                    trig.s_min * (VREF / 256.0), trig.s_max * (VREF / 256.0), trig.s_vpp * (VREF / 256.0), ...
                    err.offset_error_lsb, err.offset_error_mv, err.offset_error_pct, ...
                    err.gain_error_lsb, err.measured_gain, err.rmse_lsb));
            end

            prev_win_len   = win_len;
            prev_pan_start = pan_start;
        end

        drawnow;
        pause(0.02);
    end
unwind_protect_cleanup
    disp("Encerrando conexão serial com segurança...");
    if exist("s", "var")
        try
            fclose(s);
        catch
        end
        clear s;
    end
end_unwind_protect
