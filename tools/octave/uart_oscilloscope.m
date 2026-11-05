pkg load instrument-control;

% =========================================================================
% PAINEL DIGITAL DE OSCILOSCÓPIO E ANALISADOR DE ADC (ATmega2560)
% Utiliza uart_capture.m para realizar a aquisição das amostras via UART.
% Período e frequência identificados automaticamente pelas amostras medidas.
% Salvamento automático (sem input no terminal) em /data (.mat) e /outputs (.png).
% =========================================================================

% --- CONFIGURAÇÕES DE COMUNICAÇÃO E AMOSTRAGEM ---
serial_port = "/dev/ttyUSB0";
baud_rate = 115200;

base_dir = fileparts(mfilename("fullpath"));
if isempty(base_dir)
    base_dir = pwd();
end
addpath(base_dir);
data_dir   = fullfile(base_dir, "data");
output_dir = fullfile(base_dir, "outputs");

sampling_frequency = 2^14; % 16384 Hz (apenas fs declarada; f do sinal é medida)
adc_prescaler = 16;
sample_amount = 4096;

% Mesmo arredondamento do Timer1 no firmware (CPU nominal de 16 MHz)
timer_ticks = floor(16000000 / (8 * sampling_frequency) + 0.5);
actual_sampling_frequency = 16000000 / (8 * timer_ticks);

% --- SINAL TRIANGULAR IDEAL BASE (512 AMOSTRAS: 0..255 NA SUBIDA, 255..0 NA DESCIDA) ---
ideal_triangle_512 = [0:255, 255:-1:0]';

% --- ABERTURA DA PORTA SERIAL ---
disp("Conectando à porta serial...");
s = serial(serial_port, baud_rate);
set(s, "timeout", 50);
pause(2);

% --- CRIAÇÃO DO PAINEL DIGITAL (DASHBOARD) ---
fig = figure("name", "Painel Digital do Osciloscópio - FFT, DNL, INL, Offset/Ganho e Monotonicidade", ...
             "numbertitle", "off", ...
             "color", [0.95, 0.96, 0.98], ...
             "position", [30, 30, 1400, 840]);

% 1. QUADRADO MAIOR (Superior Esquerdo): Forma de Onda + Referência Ideal + Trigger
ax_wave = axes("parent", fig, "position", [0.04, 0.43, 0.46, 0.51]);
hold(ax_wave, "on");
x_init = (0:(sample_amount - 1))';
y_init = zeros(sample_amount, 1);
h_ideal = plot(ax_wave, x_init, y_init, "--", "color", [0.15, 0.65, 0.25], "linewidth", 1.4);
h_wave  = plot(ax_wave, x_init, y_init, "-b", "linewidth", 1.1);
h_trig  = plot(ax_wave, [0, sample_amount - 1], [127.5, 127.5], ":r", "linewidth", 1.1);
hold(ax_wave, "off");
grid(ax_wave, "on");
ylim(ax_wave, [-10, 265]);
xlim(ax_wave, [0, 2048]);
xlabel(ax_wave, "Índice da Amostra (após Trigger Auto)");
ylabel(ax_wave, "Código ADC (0 a 255)");
title(ax_wave, "Osciloscópio em Tempo Real (Azul: ADC | Verde Tracejado: Referência Ideal)");
legend(ax_wave, {"Referência Ideal", "Sinal Adquirido (ADC)", "Nível de Trigger"}, ...
       "location", "northeast");

% 2. GRÁFICO FFT MAGNITUDE (Superior Central-Direito)
ax_fft_mag = axes("parent", fig, "position", [0.55, 0.57, 0.20, 0.37]);
hold(ax_fft_mag, "on");
h_fft_mag  = plot(ax_fft_mag, [0, 1], [-100, -100], "-b", "linewidth", 1.1);
h_fft_peak = plot(ax_fft_mag, 0, 0, "ro", "markersize", 6, "linewidth", 1.5);
hold(ax_fft_mag, "off");
grid(ax_fft_mag, "on");
ylim(ax_fft_mag, [-100, 5]);
xlabel(ax_fft_mag, "Frequência (Hz)");
ylabel(ax_fft_mag, "Magnitude (dBFS)");
title(ax_fft_mag, "FFT - Magnitude");

% 3. GRÁFICO FFT FASE (Superior Extremo-Direito)
ax_fft_phase = axes("parent", fig, "position", [0.78, 0.57, 0.19, 0.37]);
hold(ax_fft_phase, "on");
h_fft_phase = plot(ax_fft_phase, [0, 1], [0, 0], "-o", "markersize", 4, ...
                   "color", [0.55, 0.15, 0.65], "markerfacecolor", [0.55, 0.15, 0.65]);
hold(ax_fft_phase, "off");
grid(ax_fft_phase, "on");
ylim(ax_fft_phase, [-185, 185]);
xlabel(ax_fft_phase, "Frequência (Hz)");
ylabel(ax_fft_phase, "Fase (Graus)");
title(ax_fft_phase, "FFT - Fase (Harmônicas Relevantes)");

% 4. GRÁFICO DNL (Inferior Central-Direito)
ax_dnl = axes("parent", fig, "position", [0.55, 0.10, 0.20, 0.37]);
hold(ax_dnl, "on");
codes_axis = (0:255)';
h_dnl = plot(ax_dnl, codes_axis, zeros(256, 1), "-b", "linewidth", 1.0);
plot(ax_dnl, [0, 255], [0.5, 0.5], "--k", "linewidth", 0.8);
plot(ax_dnl, [0, 255], [-0.5, -0.5], "--k", "linewidth", 0.8);
plot(ax_dnl, [0, 255], [-1.0, -1.0], "-r", "linewidth", 1.0);
hold(ax_dnl, "off");
grid(ax_dnl, "on");
xlim(ax_dnl, [0, 255]);
ylim(ax_dnl, [-1.5, 1.5]);
xlabel(ax_dnl, "Código Digital k (0 a 255)");
ylabel(ax_dnl, "DNL (LSB)");
title(ax_dnl, "Erro de DNL (Ciclos Inteiros)");

% 5. GRÁFICO INL E MONOTONICIDADE (Inferior Extremo-Direito)
ax_inl = axes("parent", fig, "position", [0.78, 0.10, 0.19, 0.37]);
hold(ax_inl, "on");
h_inl = plot(ax_inl, codes_axis, zeros(256, 1), "-m", "linewidth", 1.1);
h_nonmono = plot(ax_inl, NaN, NaN, "rx", "markersize", 7, "linewidth", 1.5);
plot(ax_inl, [0, 255], [1.0, 1.0], "--k", "linewidth", 0.8);
plot(ax_inl, [0, 255], [-1.0, -1.0], "--k", "linewidth", 0.8);
hold(ax_inl, "off");
grid(ax_inl, "on");
xlim(ax_inl, [0, 255]);
ylim(ax_inl, [-3.0, 3.0]);
xlabel(ax_inl, "Código Digital k (0 a 255)");
ylabel(ax_inl, "INL (LSB)");
title(ax_inl, "Erro de INL (LSB) e Monotonicidade");

% 6. PAINEL DE TELEMETRIA DIGITAL EM DUAS COLUNAS (evita corte por quebra de linha)
pnl_info = uipanel("parent", fig, "title", "Telemetria Digital em Tempo Real", ...
                   "units", "normalized", "position", [0.04, 0.14, 0.46, 0.23], ...
                   "backgroundcolor", [0.10, 0.12, 0.16], ...
                   "foregroundcolor", [0.90, 0.95, 1.00]);

txt_telemetry_left = uicontrol("parent", pnl_info, "style", "text", ...
                               "units", "normalized", "position", [0.015, 0.03, 0.48, 0.94], ...
                               "horizontalalignment", "left", ...
                               "fontname", "FixedWidth", "fontsize", 9, ...
                               "backgroundcolor", [0.10, 0.12, 0.16], ...
                               "foregroundcolor", [0.35, 1.00, 0.55], ...
                               "string", "Aguardando dados...");

txt_telemetry_right = uicontrol("parent", pnl_info, "style", "text", ...
                                "units", "normalized", "position", [0.505, 0.03, 0.48, 0.94], ...
                                "horizontalalignment", "left", ...
                                "fontname", "FixedWidth", "fontsize", 9, ...
                                "backgroundcolor", [0.10, 0.12, 0.16], ...
                                "foregroundcolor", [0.45, 0.90, 1.00], ...
                                "string", "");

% Controles inferiores: Zoom, Pan/Scroll, Modo do Sinal Ideal, Pausa e Salvar
uicontrol(fig, "style", "text", "units", "normalized", ...
          "position", [0.04, 0.080, 0.08, 0.035], ...
          "backgroundcolor", [0.95, 0.96, 0.98], ...
          "string", "Janela (Zoom):");
sld_win = uicontrol(fig, "style", "slider", "units", "normalized", ...
                    "position", [0.12, 0.080, 0.14, 0.035], ...
                    "min", 64, "max", sample_amount, "value", 2048);

uicontrol(fig, "style", "text", "units", "normalized", ...
          "position", [0.04, 0.030, 0.08, 0.035], ...
          "backgroundcolor", [0.95, 0.96, 0.98], ...
          "string", "Pan / Scroll:");
sld_pan = uicontrol(fig, "style", "slider", "units", "normalized", ...
                    "position", [0.12, 0.030, 0.14, 0.035], ...
                    "min", 0, "max", sample_amount - 64, "value", 0);

uicontrol(fig, "style", "text", "units", "normalized", ...
          "position", [0.27, 0.080, 0.06, 0.035], ...
          "backgroundcolor", [0.95, 0.96, 0.98], ...
          "string", "Ref. Ideal:");
pop_ref = uicontrol(fig, "style", "popupmenu", "units", "normalized", ...
                    "position", [0.33, 0.080, 0.17, 0.038], ...
                    "string", {"Triangular Ajustado ao Período", ...
                               "Triangular 512 (Fixo 0..255..0)", ...
                               "Senoidal Ajustada ao Período"}, ...
                    "value", 1);

btn_pause = uicontrol(fig, "style", "togglebutton", "units", "normalized", ...
                      "position", [0.27, 0.025, 0.11, 0.045], ...
                      "string", "PAUSAR / CONT.", "value", 0);

btn_save = uicontrol(fig, "style", "togglebutton", "units", "normalized", ...
                     "position", [0.39, 0.025, 0.11, 0.045], ...
                     "backgroundcolor", [0.20, 0.55, 0.30], ...
                     "foregroundcolor", [1.00, 1.00, 1.00], ...
                     "string", "SALVAR DADOS", "value", 0);

samples = zeros(sample_amount, 1);
has_valid_frame = false;

disp("Painel Digital ativo! Clique em 'SALVAR DADOS' para gravação automática em /data e /outputs.");

unwind_protect
    while ishandle(fig)
        is_paused = get(btn_pause, "value");

        if ~is_paused
            % Chama uart_capture.m passando o objeto serial aberto 's'
            [captured_samples, actual_sampling_frequency, cap_status] = ...
                uart_capture(sampling_frequency, adc_prescaler, sample_amount, s, false, false);

            if cap_status ~= 0 || isempty(captured_samples)
                pause(0.05);
                continue;
            end

            samples = captured_samples;
            has_valid_frame = true;
        else
            pause(0.05);
        end

        if ~ishandle(fig)
            break;
        end

        if ~has_valid_frame
            drawnow;
            continue;
        end

        % =====================================================================
        % 1. ANÁLISE ESPECTRAL PRELIMINAR (FFT) + TRIGGER AUTO E PERÍODO MEDIDO
        % =====================================================================
        N_fft = sample_amount;
        s_ac = samples - mean(samples);
        n_vec = (0:(N_fft - 1))';
        win_hann = 0.5 * (1 - cos(2 * pi * n_vec / (N_fft - 1)));
        coherent_gain = mean(win_hann);

        Y_fft = fft(s_ac .* win_hann);
        half_N = floor(N_fft / 2) + 1;
        Y_half = Y_fft(1:half_N);
        freq_axis = (0:(half_N - 1))' * (actual_sampling_frequency / N_fft);

        mag_lin = abs(Y_half) / (N_fft * coherent_gain / 2);
        mag_lin(1) = abs(Y_half(1)) / (N_fft * coherent_gain);
        mag_dbfs = 20 * log10(max(mag_lin / 127.5, 1e-6));

        [~, fund_bin] = max(mag_lin(3:end));
        fund_bin = fund_bin + 2;
        fund_freq_fft = freq_axis(fund_bin);
        fund_mag_dbfs = mag_dbfs(fund_bin);

        % Trigger em Auto e cruzamentos de borda de subida com histerese
        s_min = min(samples);
        s_max = max(samples);
        s_vpp = s_max - s_min;

        if s_vpp >= 6
            trig_level = 0.5 * (s_max + s_min);
            hyst = max(2, 0.08 * s_vpp);
        else
            trig_level = 127.5;
            hyst = 2;
        end

        rising_crossings = [];
        armed = (samples(1) < (trig_level - hyst));
        for k = 2:sample_amount
            if ~armed && samples(k) < (trig_level - hyst)
                armed = true;
            elseif armed && samples(k - 1) < trig_level && samples(k) >= trig_level
                frac = (trig_level - samples(k - 1)) / max(1e-6, (samples(k) - samples(k - 1)));
                rising_crossings(end + 1) = (k - 1) + frac; %#ok<AGROW>
                armed = false;
            end
        end

        if ~isempty(rising_crossings)
            trig_idx = max(1, round(rising_crossings(1)));
            trig_str = "AUTO (Travado)";
        else
            trig_idx = 1;
            trig_str = "AUTO (Livre)";
        end

        % Identificação automática do período e frequência pelas amostras (com fallback via FFT)
        if numel(rising_crossings) >= 2
            period_samples = mean(diff(rising_crossings));
            period_sec = period_samples / actual_sampling_frequency;
            freq_hz = 1.0 / period_sec;
        elseif fund_freq_fft > 0
            freq_hz = fund_freq_fft;
            period_sec = 1.0 / freq_hz;
            period_samples = actual_sampling_frequency / freq_hz;
        else
            period_samples = 512;
            period_sec = period_samples / actual_sampling_frequency;
            freq_hz = actual_sampling_frequency / period_samples;
        end
        signal_frequency = freq_hz;

        % =====================================================================
        % 2. GERAÇÃO DO SINAL IDEAL DE REFERÊNCIA E CÁLCULO DE OFFSET E GANHO
        % =====================================================================
        valid_len = sample_amount - trig_idx + 1;
        x_plot = (0:(valid_len - 1))';
        y_plot = samples(trig_idx:end);

        ref_mode = get(pop_ref, "value");
        if ref_mode == 1
            % Triangular Ideal ajustado ao período medido real (period_samples)
            norm_phase = mod((trig_level / 255.0) * 0.5 + (x_plot / period_samples), 1.0);
            ideal_plot = zeros(valid_len, 1);
            up_mask = (norm_phase < 0.5);
            ideal_plot(up_mask)  = 255.0 * (norm_phase(up_mask) * 2.0);
            ideal_plot(~up_mask) = 255.0 * (2.0 - norm_phase(~up_mask) * 2.0);
        elseif ref_mode == 2
            % Sinal Triangular Ideal de exatas 512 amostras (0..255 na subida, 255..0 na descida)
            start_offset = round(min(255, max(0, trig_level)));
            idx_512 = mod(start_offset + x_plot, 512) + 1;
            ideal_plot = ideal_triangle_512(idx_512);
        else
            % Senoidal Ideal ajustada ao período medido (0 a 255)
            phase_rad = 2 * pi * (x_plot / period_samples);
            ideal_plot = 127.5 + 127.5 * sin(phase_rad);
        end

        rmse_lsb = sqrt(mean((y_plot - ideal_plot) .^ 2));

        % --- ERRO DE OFFSET E ERRO DE GANHO (em LSB e %FSR) ---
        lin_mask = (ideal_plot >= 5) & (ideal_plot <= 250);
        if sum(lin_mask) >= 20
            x_lin = ideal_plot(lin_mask);
            y_lin = y_plot(lin_mask);
            x_mean = mean(x_lin);
            y_mean = mean(y_lin);
            measured_gain = sum((x_lin - x_mean) .* (y_lin - y_mean)) / max(1e-9, sum((x_lin - x_mean) .^ 2));
            intercept_lsb = y_mean - measured_gain * x_mean;
            offset_error_lsb = (measured_gain * 127.5 + intercept_lsb) - 127.5;
            gain_error_lsb   = (measured_gain - 1.0) * 255.0;
        else
            measured_gain    = s_vpp / 255.0;
            offset_error_lsb = mean(samples) - 127.5;
            gain_error_lsb   = s_vpp - 255.0;
        end
        offset_error_pct = (offset_error_lsb / 255.0) * 100.0;
        gain_error_pct   = (gain_error_lsb / 255.0) * 100.0;

        % =====================================================================
        % 3. MÉTRICAS ESPECTRAIS (FASE, SFDR, SINAD, THD, ENOB, DR)
        % =====================================================================
        phase_deg = rad2deg(angle(Y_half));
        sig_bins = find(mag_dbfs > -55);
        if isempty(sig_bins)
            sig_bins = fund_bin;
        end

        fund_lobe = max(2, fund_bin - 3):min(half_N, fund_bin + 3);
        psd_bins = (mag_lin .^ 2);
        P_signal = sum(psd_bins(fund_lobe));

        noise_dist_mask = true(half_N, 1);
        noise_dist_mask(1:2) = false;
        noise_dist_mask(fund_lobe) = false;
        P_nad = sum(psd_bins(noise_dist_mask));

        P_harm = 0;
        for h_idx = 2:7
            h_bin = round(1 + (fund_bin - 1) * h_idx);
            if h_bin <= half_N
                h_lobe = max(2, h_bin - 2):min(half_N, h_bin + 2);
                P_harm = P_harm + sum(psd_bins(h_lobe));
            end
        end

        max_spur_dbfs = max(mag_dbfs(noise_dist_mask));
        sfdr_dbc = fund_mag_dbfs - max_spur_dbfs;
        sinad_db = 10 * log10(max(P_signal, 1e-12) / max(P_nad, 1e-12));
        thd_db   = 10 * log10(max(P_harm, 1e-12) / max(P_signal, 1e-12));
        enob_bits = max(0, (sinad_db - 1.76) / 6.02);

        P_noise_only = max(1e-12, P_nad - P_harm);
        dr_db = 10 * log10((127.5 ^ 2) / P_noise_only);

        % =====================================================================
        % 4. CÁLCULO DE DNL, INL E MONOTONICIDADE (SOBRE CICLOS INTEIROS!)
        % =====================================================================
        num_full_cycles = floor(sample_amount / period_samples);
        if num_full_cycles >= 1
            n_int_samples = min(sample_amount, max(256, round(num_full_cycles * period_samples)));
            samples_for_hist = samples(1:n_int_samples);
        else
            n_int_samples = sample_amount;
            samples_for_hist = samples;
        end

        code_counts = histc(round(samples_for_hist), 0:255);
        code_counts = code_counts(:);

        k_min = max(0, round(s_min));
        k_max = min(255, round(s_max));
        inner_idx = (k_min + 2):(k_max);

        dnl = zeros(256, 1);
        inl = zeros(256, 1);
        if numel(inner_idx) >= 4
            expected_hits = mean(code_counts(inner_idx));
            if expected_hits > 0
                dnl(inner_idx) = (code_counts(inner_idx) / expected_hits) - 1.0;
                dnl_zero_mean = dnl(inner_idx) - mean(dnl(inner_idx));
                inl(inner_idx) = cumsum(dnl_zero_mean);
            end
        end

        if numel(inner_idx) >= 4
            missing_codes = sum(code_counts(inner_idx) == 0);
        else
            missing_codes = 0;
        end

        ideal_levels_int = min(255, max(0, round(ideal_plot)));
        mean_adc_per_level = nan(256, 1);
        for c = 0:255
            mask_c = (ideal_levels_int == c);
            if any(mask_c)
                mean_adc_per_level(c + 1) = mean(y_plot(mask_c));
            end
        end
        valid_curve = find(~isnan(mean_adc_per_level));
        nonmono_codes = [];
        if numel(valid_curve) >= 4
            diffs_curve = diff(mean_adc_per_level(valid_curve));
            inv_pos = find(diffs_curve < -0.5);
            if ~isempty(inv_pos)
                nonmono_codes = valid_curve(inv_pos + 1) - 1;
            end
        end

        is_monotonic = isempty(nonmono_codes) && (missing_codes == 0);
        if is_monotonic
            mono_str = "SIM (Monotônico)";
        else
            mono_str = sprintf("NÃO (%d inv | %d miss)", numel(nonmono_codes), missing_codes);
        end

        [dnl_max, ~] = max(dnl);
        [dnl_min, ~] = min(dnl);
        [inl_max, ~] = max(inl);
        [inl_min, ~] = min(inl);

        % =====================================================================
        % 5. ATUALIZAÇÃO DOS GRÁFICOS E DO PAINEL DIGITAL
        % =====================================================================
        set(h_wave,  "xdata", x_plot, "ydata", y_plot);
        set(h_ideal, "xdata", x_plot, "ydata", ideal_plot);
        set(h_trig,  "xdata", [0, sample_amount - 1], "ydata", [trig_level, trig_level]);

        win_len = max(64, min(round(get(sld_win, "value")), valid_len));
        max_pan = max(0, valid_len - win_len);
        pan_start = min(round(get(sld_pan, "value")), max_pan);
        xlim(ax_wave, [pan_start, pan_start + win_len]);

        f_max_view = min(actual_sampling_frequency / 2, max(1000, 20 * freq_hz));
        set(h_fft_mag,  "xdata", freq_axis, "ydata", mag_dbfs);
        set(h_fft_peak, "xdata", fund_freq_fft, "ydata", fund_mag_dbfs);
        xlim(ax_fft_mag, [0, f_max_view]);

        set(h_fft_phase, "xdata", freq_axis(sig_bins), "ydata", phase_deg(sig_bins));
        xlim(ax_fft_phase, [0, f_max_view]);

        set(h_dnl, "ydata", dnl);
        ylim(ax_dnl, [min(-1.2, dnl_min - 0.3), max(1.2, dnl_max + 0.3)]);
        title(ax_dnl, sprintf("Erro de DNL (%d Ciclos Inteiros = %d am)", ...
                              max(1, num_full_cycles), n_int_samples));

        set(h_inl, "ydata", inl);
        if ~isempty(nonmono_codes)
            set(h_nonmono, "xdata", nonmono_codes, "ydata", inl(nonmono_codes + 1));
        else
            set(h_nonmono, "xdata", NaN, "ydata", NaN);
        end
        ylim(ax_inl, [min(-1.5, inl_min - 0.5), max(1.5, inl_max + 0.5)]);

        left_col_text = sprintf([ ...
            "FREQ / PERÍODO : f = %.2f Hz (FFT: %.2f Hz)\n", ...
            "PERÍODO MEDIDO : T = %.3f ms (%.1f am/ciclo)\n", ...
            "STATUS TRIGGER : %s (Nível = %.1f)\n", ...
            "EXCURSÃO (ADC) : Min = %.0f | Max = %.0f | Vpp = %.0f LSB\n", ...
            "ERRO VS IDEAL  : RMSE = %.2f LSB\n", ...
            "ERRO DE OFFSET : %+.2f LSB (%+.2f %%FSR)\n", ...
            "ERRO DE GANHO  : %+.2f LSB (%+.2f %%FSR | G=%.4f)"], ...
            freq_hz, fund_freq_fft, ...
            period_sec * 1e3, period_samples, ...
            trig_str, trig_level, ...
            s_min, s_max, s_vpp, ...
            rmse_lsb, ...
            offset_error_lsb, offset_error_pct, ...
            gain_error_lsb, gain_error_pct, measured_gain);

        right_col_text = sprintf([ ...
            "FAIXA DINÂMICA : DR = %.1f dB | SFDR = %.1f dBc\n", ...
            "REL. SINAL/RUÍDO: SINAD = %.1f dB | THD = %.1f dB\n", ...
            "BITS EFETIVOS  : ENOB = %.2f bits (harm. incl.)\n", ...
            "ERRO DNL (LSB) : Min = %+.2f | Max = %+.2f LSB\n", ...
            "ERRO INL (LSB) : Min = %+.2f | Max = %+.2f LSB\n", ...
            "MISSING CODES  : %d códigos ausentes\n", ...
            "MONOTONICIDADE : %s"], ...
            dr_db, sfdr_dbc, ...
            sinad_db, thd_db, ...
            enob_bits, ...
            dnl_min, dnl_max, ...
            inl_min, inl_max, ...
            missing_codes, ...
            mono_str);

        set(txt_telemetry_left,  "string", left_col_text);
        set(txt_telemetry_right, "string", right_col_text);

        drawnow;

        % =====================================================================
        % 6. SALVAMENTO AUTOMÁTICO (/data/*.mat E /outputs/*.png SEM INPUT)
        % =====================================================================
        if ishandle(btn_save) && get(btn_save, "value") == 1
            set(btn_save, "value", 0);

            if ~exist(data_dir, "dir")
                mkdir(data_dir);
            end
            if ~exist(output_dir, "dir")
                mkdir(output_dir);
            end

            timestamp_str = datestr(now, "yyyymmdd_HHMMSS_FFF");
            base_name = ["sample_", timestamp_str];

            mat_path = fullfile(data_dir, [base_name, ".mat"]);
            png_path = fullfile(output_dir, [base_name, ".png"]);

            save("-v7", mat_path, ...
                 "samples", "x_plot", "y_plot", "ideal_plot", ...
                 "signal_frequency", "sampling_frequency", "actual_sampling_frequency", ...
                 "adc_prescaler", "sample_amount", ...
                 "freq_hz", "fund_freq_fft", "period_sec", "period_samples", ...
                 "trig_level", "trig_idx", ...
                 "s_min", "s_max", "s_vpp", "rmse_lsb", ...
                 "offset_error_lsb", "offset_error_pct", ...
                 "gain_error_lsb", "gain_error_pct", "measured_gain", ...
                 "freq_axis", "mag_dbfs", "phase_deg", ...
                 "dr_db", "sfdr_dbc", "sinad_db", "thd_db", "enob_bits", ...
                 "codes_axis", "code_counts", "dnl", "inl", ...
                 "dnl_min", "dnl_max", "inl_min", "inl_max", ...
                 "missing_codes", "is_monotonic", "nonmono_codes");

            print(fig, png_path, "-dpng", "-r150");

            printf("Dados salvos automaticamente em: %s\n", mat_path);
            printf("Gráfico salvo automaticamente em: %s\n", png_path);
        end

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
