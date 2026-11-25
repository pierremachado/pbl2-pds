function updateAnalyzerDashboard(m, unit_mode, pan_start, win_len, VREF, LSB_MV, plots, txt_cols, fft_scale_mode)
    % =========================================================================
    % UPDATEANALYZERDASHBOARD - Atualiza os 6 gráficos (GUI/PNG) e telemetria da GUI
    % =========================================================================

    if nargin < 9 || isempty(fft_scale_mode)
        fft_scale_mode = 1; % 1: dBFS (log), 2: Linear (0-100% FS)
    end

    % 1. Seleção de escala (LSB vs Volts vs %FSR = 100 / 256 por LSB)
    if unit_mode == 2
        scale_sig = VREF / 256.0;
        sig_unit_lbl = "Tensão (V)";
        sig_ylim = [-0.10, 2.68];
        err_scale = LSB_MV;
        err_unit_lbl = "Erro (mV)";
        err_lim_val = 0.5 * LSB_MV; % +-5 mV
    elseif unit_mode == 3
        scale_sig = 100.0 / 256.0;
        sig_unit_lbl = "Escala (%FSR)";
        sig_ylim = [-4, 105];
        err_scale = 100.0 / 256.0;
        err_unit_lbl = "Erro Relativo (%FSR)";
        err_lim_val = (0.5 / 256.0) * 100.0; % +-0.1953%
    else
        scale_sig = 1.0;
        sig_unit_lbl = "Código ADC (0 a 255)";
        sig_ylim = [-10, 265];
        err_scale = 1.0;
        err_unit_lbl = "Erro (LSB)";
        err_lim_val = 0.5;
    end

    x_end = max(1, numel(m.x_plot) - 1);
    set(plots.h_ideal_cont,  "xdata", m.x_plot, "ydata", m.ideal_cont_plot * scale_sig);
    set(plots.h_ideal_quant, "xdata", m.x_plot, "ydata", m.ideal_quant_plot * scale_sig);
    set(plots.h_wave,        "xdata", m.x_plot, "ydata", m.y_plot * scale_sig);
    set(plots.h_trig,        "xdata", [0, x_end], "ydata", [m.trig_level, m.trig_level] * scale_sig);
    % Limites vazios preservam o pan/zoom nativo ao trocar a unidade.
    if ~isempty(pan_start)
        xlim(plots.ax_wave, [pan_start, pan_start + win_len]);
    end
    ylim(plots.ax_wave, sig_ylim);
    ylabel(plots.ax_wave, sig_unit_lbl);
    title(plots.ax_wave, sprintf("1. Sinal 8b vs. %s Ideal [%s | f=%.2f Hz | fs=%.1f Hz]", ...
                                 m.wave_label, m.file_name, m.freq_hz, m.actual_sampling_frequency), "interpreter", "none");
    legend(plots.ax_wave, {[m.wave_label, " Contínuo"], "Ideal Quantizado (256 nív.)", "Capturado (ADC 8b)", "Trigger"}, ...
           "location", "northeast", "fontsize", 8);

    % 2. FFT Tripla (ADC vs Quantizado Ideal vs Referência Contínua)
    f_max_view = min(m.actual_sampling_frequency / 2.0, max(150.0, 18.0 * m.freq_hz));
    if fft_scale_mode == 2
        set(plots.h_fft_ref,   "xdata", m.freq_axis, "ydata", m.mag_pct_ref);
        set(plots.h_fft_quant, "xdata", m.freq_axis, "ydata", m.mag_pct_quant);
        set(plots.h_fft_adc,   "xdata", m.freq_axis, "ydata", m.mag_pct);
        set(plots.h_fft_peak,  "xdata", m.fund_freq_fft, "ydata", m.fund_mag_pct);
        max_pct = max([100.0; m.mag_pct(:); m.mag_pct_ref(:)]);
        ylim(plots.ax_fft, [0, max(105.0, 1.05 * max_pct)]);
        ylabel(plots.ax_fft, "Magnitude (% FS)");
    else
        set(plots.h_fft_ref,   "xdata", m.freq_axis, "ydata", m.mag_dbfs_ref);
        set(plots.h_fft_quant, "xdata", m.freq_axis, "ydata", m.mag_dbfs_quant);
        set(plots.h_fft_adc,   "xdata", m.freq_axis, "ydata", m.mag_dbfs);
        set(plots.h_fft_peak,  "xdata", m.fund_freq_fft, "ydata", m.fund_mag_dbfs);
        ylim(plots.ax_fft, [-105, 5]);
        ylabel(plots.ax_fft, "Magnitude (dBFS)");
    end
    if ~isempty(pan_start)
        xlim(plots.ax_fft, [0, f_max_view]);
    end
    title(plots.ax_fft, sprintf("2. FFT: ADC vs. Quantizado vs. %s", m.wave_label));
    legend(plots.ax_fft, {["FFT ", m.wave_label, " Puro"], "FFT Quantizado 256n", "FFT ADC Capturado", "Fundamental"}, ...
           "location", "northeast", "fontsize", 7.5);

    % 3. Curva de Transferência Real vs Ideal
    x_codes = (0:255)';
    y_fit_line = m.measured_gain * x_codes + m.intercept_lsb;
    set(plots.h_trans_ideal, "xdata", x_codes, "ydata", x_codes);
    set(plots.h_trans_fit,   "xdata", x_codes, "ydata", y_fit_line);
    set(plots.h_trans_real,  "xdata", x_codes, "ydata", m.mean_adc_per_level);
    if m.linearity_valid
        title(plots.ax_trans, sprintf("3. Transferência (G=%.4f | Off=%+.2f LSB)", m.measured_gain, m.offset_error_lsb));
    else
        title(plots.ax_trans, "3. Transferência (Apenas Platôs - Quadrada)");
    end

    % 4. Gráfico de Erros no Tempo (Bruto e Intrínseco)
    set(plots.h_err_raw,   "xdata", m.x_plot, "ydata", m.err_vs_cont_lsb * err_scale);
    set(plots.h_err_intr,  "xdata", m.x_plot, "ydata", m.err_intrinsic_lsb * err_scale);
    set(plots.h_err_lim_p, "xdata", [0, x_end], "ydata", [err_lim_val, err_lim_val]);
    set(plots.h_err_lim_n, "xdata", [0, x_end], "ydata", [-err_lim_val, -err_lim_val]);
    if ~isempty(pan_start)
        xlim(plots.ax_err, [pan_start, pan_start + win_len]);
    end
    max_e_plot = max(1.5 * err_lim_val, min(25 * err_scale, 1.15 * max(abs(m.err_vs_cont_lsb)) * err_scale));
    ylim(plots.ax_err, [-max_e_plot, max_e_plot]);
    ylabel(plots.ax_err, err_unit_lbl);
    title(plots.ax_err, sprintf("4. Erro Instantâneo (RMSE Bruto=%.2f LSB [%.2f%%FSR] | Intrínseco=%.2f LSB | MAE=%.2f LSB)", ...
                                m.rmse_lsb, m.rmse_pct_fsr, m.rmse_intrinsic_lsb, m.mae_lsb));

    % 5 e 6. DNL e INL
    if m.linearity_valid
        set(plots.h_dnl, "ydata", m.dnl);
        ylim(plots.ax_dnl, [min(-1.2, m.dnl_min - 0.25), max(1.2, m.dnl_max + 0.25)]);
        hist_tag = ifelse(strcmp(m.hist_mode, "sine"), "IEEE 1241", "Uniforme");
        if m.num_full_cycles >= 1
            dnl_scope_str = sprintf("%d ciclo(s)", m.num_full_cycles);
        else
            dnl_scope_str = "rampa parcial";
        end
        title(plots.ax_dnl, sprintf("5. DNL [%s | %s | RMS=%.2f LSB]", hist_tag, dnl_scope_str, m.dnl_rms));

        set(plots.h_inl, "ydata", m.inl);
        if ~isempty(m.nonmono_codes)
            set(plots.h_nonmono, "xdata", m.nonmono_codes, "ydata", m.inl(m.nonmono_codes + 1));
        else
            set(plots.h_nonmono, "xdata", NaN, "ydata", NaN);
        end
        ylim(plots.ax_inl, [min(-1.5, m.inl_min - 0.4), max(1.5, m.inl_max + 0.4)]);
        title(plots.ax_inl, sprintf("6. INL (Min=%+.2f | Max=%+.2f LSB | Miss=%d)", m.inl_min, m.inl_max, m.missing_codes));
    else
        set(plots.h_dnl, "ydata", nan(256, 1));
        ylim(plots.ax_dnl, [-1.5, 1.5]);
        title(plots.ax_dnl, "5. DNL (N/A para Onda Quadrada)");

        set(plots.h_inl, "ydata", nan(256, 1));
        set(plots.h_nonmono, "xdata", NaN, "ydata", NaN);
        ylim(plots.ax_inl, [-2.5, 2.5]);
        title(plots.ax_inl, "6. INL (N/A para Onda Quadrada)");
    end

    % 7. Textos de Telemetria (3 Colunas, apenas na GUI)
    if nargin < 8 || isempty(txt_cols)
        return;
    end

    if ~m.linearity_valid
        mono_str = "N/A (Quadrada)";
        dnl_line = "DNL (Min/Max) : N/A (Onda Quadrada)";
        inl_line = sprintf("INL (Min/Max) : N/A | %s", mono_str);
        miss_line = "MISSING CODES : N/A (apenas 2 níveis)";
    else
        if m.is_monotonic && m.missing_codes == 0
            mono_str = "SIM (Monotônico)";
        elseif m.is_monotonic
            mono_str = sprintf("SIM (%d miss)", m.missing_codes);
        else
            mono_str = sprintf("NÃO (%d inv | %d miss)", numel(m.nonmono_codes), m.missing_codes);
        end
        dnl_line = sprintf("DNL (Min/Max) : %+.2f / %+.2f LSB (RMS=%.2f)", m.dnl_min, m.dnl_max, m.dnl_rms);
        inl_line = sprintf("INL (Min/Max) : %+.2f / %+.2f LSB | %s", m.inl_min, m.inl_max, mono_str);
        miss_line = sprintf("MISSING CODES : %d cód. ausentes (de %d)", ...
                            m.missing_codes, max(0, round(m.s_max) - round(m.s_min) - 1));
    end

    col1_str = sprintf([ ...
        "ARQUIVO : %s (%s)\n", ...
        "ONDA/FREQ : %s | f=%.2f Hz (FFT:%.2f)\n", ...
        "AMOSTRAGEM: fs = %.1f Hz (Pre=%d | Tconv=%.1fus)\n", ...
        "PERÍODO   : T = %.2f ms (%.1f am/ciclo)\n", ...
        "EXCURSÃO  : %.0f..%.0f LSB (%.2f..%.2f V)\n", ...
        "ERRO OFFS.: %+.2f LSB (%+.1f mV | %+.2f%%FSR)\n", ...
        "ERRO GANHO: %+.2f LSB (%+.1f mV | G=%.4f)"], ...
        m.file_name, ifelse(m.was_full_format, "COMPLETO", "SIMPLES"), ...
        m.wave_label, m.freq_hz, m.fund_freq_fft, ...
        m.actual_sampling_frequency, m.adc_prescaler, m.conversion_time_us, ...
        m.period_sec * 1e3, m.period_samples, ...
        m.s_min, m.s_max, m.s_min * (VREF / 256.0), m.s_max * (VREF / 256.0), ...
        m.offset_error_lsb, m.offset_error_mv, m.offset_error_pct, ...
        m.gain_error_lsb, m.gain_error_mv, m.measured_gain);

    col2_str = sprintf([ ...
        "RMSE BRUTO    : %.2f LSB (%.1f mV | %.2f%%FSR)\n", ...
        "RMSE INTRÍNSEC: %.2f LSB (%.1f mV | %.2f%%FSR)\n", ...
        "ERRO ABS MÉDIO: MAE = %.2f LSB (%.1f mV)\n", ...
        "ERRO ABS MÁX  : Max = %.2f LSB (%.1f mV)\n", ...
        "ERRO RELATIVO : %.2f%%FSR (MAPE=%.2f%% sinal)\n", ...
        "%s\n", ...
        "%s"], ...
        m.rmse_lsb, m.rmse_mv, m.rmse_pct_fsr, ...
        m.rmse_intrinsic_lsb, m.rmse_intrinsic_mv, m.rmse_intrinsic_pct, ...
        m.mae_lsb, m.mae_mv, ...
        m.max_abs_err_lsb, m.max_abs_err_mv, ...
        m.mae_pct_fsr, m.mape_signal_pct, ...
        dnl_line, inl_line);

    if strcmp(m.wave_type, "sine")
        col3_str = sprintf([ ...
            "FAIXA DINÂMICA: DR = %.1f dB (Ideal 8b: %.1f)\n", ...
            "SINAD / THD   : %.1f dB (FFT) | THD=%.1f dB\n", ...
            "SINAD TEMPO   : %.1f dB (Intrín.: %.1f dB)\n", ...
            "ENOB SENOIDAL : %.2f b (FFT) | Intrín.: %.2f b\n", ...
            "SFDR SENOIDAL : %.1f dBc (Bruto: %.1f dBc)\n", ...
            "PISO RUÍDO RMS: %.3f LSB (%.2f mV)\n", ...
            "%s"], ...
            m.dr_db, m.dr_quant_db, ...
            m.sinad_db, m.thd_db, ...
            m.sinad_wave_total_db, m.sinad_wave_intrin_db, ...
            m.enob_bits, m.enob_wave_intrin_bits, ...
            m.sfdr_wave_dbc, m.sfdr_dbc, ...
            m.noise_floor_rms_lsb, m.noise_floor_rms_mv, ...
            miss_line);
    else
        col3_str = sprintf([ ...
            "FAIXA DINÂMICA: DR = %.1f dB (%s: %.1f dB)\n", ...
            "DR IDEAL 8b   : %.1f dB (SQNR %s: %.1f dB)\n", ...
            "SINAD (%s)  : %.1f dB (Intrín.: %.1f dB)\n", ...
            "ENOB  (%s)  : %.2f bits (Intrín.: %.2f b)\n", ...
            "SFDR (s/ Onda): %.1f dBc (Bruto: %.1f dBc)\n", ...
            "PISO RUÍDO RMS: %.3f LSB (%.2f mV)\n", ...
            "%s"], ...
            m.dr_db, m.wave_short, m.dr_wave_db, ...
            m.dr_quant_db, m.wave_short, m.sqnr_ideal_quant_db, ...
            m.wave_short, m.sinad_wave_total_db, m.sinad_wave_intrin_db, ...
            m.wave_short, m.enob_wave_total_bits, m.enob_wave_intrin_bits, ...
            m.sfdr_wave_dbc, m.sfdr_dbc, ...
            m.noise_floor_rms_lsb, m.noise_floor_rms_mv, ...
            miss_line);
    end

    set(txt_cols.col1, "string", col1_str);
    set(txt_cols.col2, "string", col2_str);
    set(txt_cols.col3, "string", col3_str);
end
