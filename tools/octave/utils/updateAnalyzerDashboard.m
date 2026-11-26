function plots = updateAnalyzerDashboard(m, unit_mode, pan_start, win_len, VREF, LSB_MV, plots, fft_scale_mode)
    % =========================================================================
    % UPDATEANALYZERDASHBOARD - Atualiza os 6 gráficos do painel (GUI e PNG)
    % =========================================================================

    if nargin < 8 || isempty(fft_scale_mode)
        fft_scale_mode = 1; % 1: dBFS (log), 2: Linear (0-100% FS)
    end

    u = getUnitConfig(m, unit_mode, VREF, LSB_MV);

    % 1. Sinal no Tempo
    x_end = max(1, numel(m.x_plot) - 1);
    set(plots.h_ideal_cont,  "xdata", m.x_plot, "ydata", m.ideal_cont_plot * u.scale_sig);
    set(plots.h_ideal_quant, "xdata", m.x_plot, "ydata", m.ideal_quant_plot * u.scale_sig);
    set(plots.h_wave,        "xdata", m.x_plot, "ydata", m.y_plot * u.scale_sig);
    set(plots.h_trig,        "xdata", [0, x_end], "ydata", [m.trig_level, m.trig_level] * u.scale_sig);
    % Limites vazios preservam o pan/zoom nativo ao trocar a unidade.
    if ~isempty(pan_start)
        xlim(plots.ax_wave, [pan_start, pan_start + win_len]);
    end
    ylim(plots.ax_wave, u.sig_ylim);
    ylabel(plots.ax_wave, u.sig_unit_lbl);
    title(plots.ax_wave, { ...
        sprintf("Sinal 8b vs. %s Ideal", m.wave_label), ...
        sprintf("f = %.2f Hz | fs = %.1f Hz", m.freq_hz, m.actual_sampling_frequency)}, ...
        "fontsize", 9.5, "interpreter", "none");

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
    if isfinite(m.fund_freq_fft)
        fft_sub = sprintf("Fundamental = %.2f Hz", m.fund_freq_fft);
    else
        fft_sub = "Sem componente AC";
    end
    title(plots.ax_fft, { ...
        sprintf("FFT: ADC vs. Quantizado vs. %s", m.wave_label), ...
        fft_sub}, "fontsize", 9.5, "interpreter", "none");

    % Atualiza legendas de forma de onda apenas quando ela mudar
    if ~strcmp(plots.last_wave_label, m.wave_label)
        legend(plots.ax_wave, {[m.wave_label, " Contínuo"], "Ideal Quant. (256 nív.)", "Capturado (ADC 8b)", "Trigger"}, ...
               "location", "northeast", "fontsize", 8);
        legend(plots.ax_fft, {["FFT ", m.wave_label, " Puro"], "FFT Quantizado 256n", "FFT ADC Capturado", "Fundamental"}, ...
               "location", "northeast", "fontsize", 7.5);
        plots.last_wave_label = m.wave_label;
    end

    % 3. Curva de Transferência Real vs Ideal
    x_codes = (0:255)';
    y_fit_line = m.measured_gain * x_codes + m.intercept_lsb;
    set(plots.h_trans_ideal, "xdata", x_codes, "ydata", x_codes);
    set(plots.h_trans_fit,   "xdata", x_codes, "ydata", y_fit_line);
    set(plots.h_trans_real,  "xdata", x_codes, "ydata", m.mean_adc_per_level);
    if m.linearity_valid
        trans_sub = sprintf(["Ganho: ", u.signed_fmt, " %s (G=%.4f) | Off: ", u.signed_fmt, " %s"], ...
                            u.gain_err, u.err_unit, m.measured_gain, u.off_err, u.err_unit);
    else
        trans_sub = sprintf(["Platôs — Ganho: ", u.signed_fmt, " %s | Off: ", u.signed_fmt, " %s"], ...
                            u.gain_err, u.err_unit, u.off_err, u.err_unit);
    end
    title(plots.ax_trans, {"Curva de Transferência", trans_sub}, "fontsize", 9.5, "interpreter", "none");

    % 4. Erro Instantâneo (Bruto e Intrínseco)
    set(plots.h_err_raw,   "xdata", m.x_plot, "ydata", m.err_vs_cont_lsb * u.err_scale);
    set(plots.h_err_intr,  "xdata", m.x_plot, "ydata", m.err_intrinsic_lsb * u.err_scale);
    set(plots.h_err_lim_p, "xdata", [0, x_end], "ydata", [u.err_lim_val, u.err_lim_val]);
    set(plots.h_err_lim_n, "xdata", [0, x_end], "ydata", [-u.err_lim_val, -u.err_lim_val]);
    if ~isempty(pan_start)
        xlim(plots.ax_err, [pan_start, pan_start + win_len]);
    end
    max_e_plot = max(1.5 * u.err_lim_val, min(25 * u.err_scale, 1.15 * max(abs(m.err_vs_cont_lsb)) * u.err_scale));
    ylim(plots.ax_err, [-max_e_plot, max_e_plot]);
    ylabel(plots.ax_err, u.err_unit_lbl);
    err_sub = sprintf(["RMSE: ", u.val_fmt, " %s (Intrín.: ", u.val_fmt, ") | MAE: ", u.val_fmt, " %s"], ...
                      u.rmse, u.err_unit, u.rmse_intr, u.mae, u.err_unit);
    title(plots.ax_err, {"Erro Instantâneo", err_sub}, "fontsize", 9.5, "interpreter", "none");

    if ~strcmp(plots.last_err_lim_str, u.err_lim_str)
        legend(plots.ax_err, {"Erro Bruto (ADC - Ideal)", "Erro Intrínseco (s/ Ganho/Off)", ...
                              ["+", u.err_lim_str], ["-", u.err_lim_str]}, ...
               "location", "northeast", "fontsize", 7.5);
        plots.last_err_lim_str = u.err_lim_str;
    end

    % 5 e 6. DNL e INL
    if m.linearity_valid
        set(plots.h_dnl, "ydata", m.dnl);
        ylim(plots.ax_dnl, [min(-1.2, m.dnl_min - 0.25), max(1.2, m.dnl_max + 0.25)]);
        dnl_sub = sprintf("Min/Max: %+.2f/%+.2f LSB | RMS: %.2f | %s", ...
                          m.dnl_min, m.dnl_max, m.dnl_rms, formatMonotonicityStatus(m));
        title(plots.ax_dnl, {"DNL", dnl_sub}, "fontsize", 9.5, "interpreter", "none");

        set(plots.h_inl, "ydata", m.inl);
        if ~isempty(m.nonmono_codes)
            set(plots.h_nonmono, "xdata", m.nonmono_codes, "ydata", m.inl(m.nonmono_codes + 1));
        else
            set(plots.h_nonmono, "xdata", NaN, "ydata", NaN);
        end
        ylim(plots.ax_inl, [min(-1.5, m.inl_min - 0.4), max(1.5, m.inl_max + 0.4)]);
        inl_sub = sprintf("Min/Max: %+.2f / %+.2f LSB | Missing: %d", ...
                          m.inl_min, m.inl_max, m.missing_codes);
        title(plots.ax_inl, {"INL", inl_sub}, "fontsize", 9.5, "interpreter", "none");
    else
        set(plots.h_dnl, "ydata", nan(256, 1));
        ylim(plots.ax_dnl, [-1.5, 1.5]);
        title(plots.ax_dnl, {"DNL", "(N/A para Onda Quadrada)"}, "fontsize", 9.5, "interpreter", "none");

        set(plots.h_inl, "ydata", nan(256, 1));
        set(plots.h_nonmono, "xdata", NaN, "ydata", NaN);
        ylim(plots.ax_inl, [-2.5, 2.5]);
        title(plots.ax_inl, {"INL", "(N/A para Onda Quadrada)"}, "fontsize", 9.5, "interpreter", "none");
    end
end

function u = getUnitConfig(m, unit_mode, VREF, LSB_MV)
    u = struct();
    if unit_mode == 2
        u.scale_sig    = VREF / 256.0;
        u.sig_unit_lbl = "Tensão (V)";
        u.sig_ylim     = [-0.04 * VREF, 1.05 * VREF];
        u.err_scale    = LSB_MV;
        u.err_unit_lbl = "Erro (mV)";
        u.err_lim_val  = 0.5 * LSB_MV;
        u.err_lim_str  = sprintf("%.1f mV", u.err_lim_val);
        u.err_unit     = "mV";
        u.val_fmt      = "%.1f";
        u.signed_fmt   = "%+.1f";
        u.gain_err     = m.gain_error_mv;
        u.off_err      = m.offset_error_mv;
        u.rmse         = m.rmse_mv;
        u.rmse_intr    = m.rmse_intrinsic_mv;
        u.mae          = m.mae_mv;
    elseif unit_mode == 3
        u.scale_sig    = 100.0 / 256.0;
        u.sig_unit_lbl = "Escala (%FSR)";
        u.sig_ylim     = [-4, 105];
        u.err_scale    = 100.0 / 256.0;
        u.err_unit_lbl = "Erro Relativo (%FSR)";
        u.err_lim_val  = (0.5 / 256.0) * 100.0;
        u.err_lim_str  = sprintf("%.2f%%FSR", u.err_lim_val);
        u.err_unit     = "%FSR";
        u.val_fmt      = "%.2f";
        u.signed_fmt   = "%+.2f";
        u.gain_err     = m.gain_error_pct;
        u.off_err      = m.offset_error_pct;
        u.rmse         = m.rmse_pct_fsr;
        u.rmse_intr    = m.rmse_intrinsic_pct;
        u.mae          = m.mae_pct_fsr;
    else
        u.scale_sig    = 1.0;
        u.sig_unit_lbl = "Código ADC (0 a 255)";
        u.sig_ylim     = [-10, 265];
        u.err_scale    = 1.0;
        u.err_unit_lbl = "Erro (LSB)";
        u.err_lim_val  = 0.5;
        u.err_lim_str  = "0.5 LSB";
        u.err_unit     = "LSB";
        u.val_fmt      = "%.2f";
        u.signed_fmt   = "%+.2f";
        u.gain_err     = m.gain_error_lsb;
        u.off_err      = m.offset_error_lsb;
        u.rmse         = m.rmse_lsb;
        u.rmse_intr    = m.rmse_intrinsic_lsb;
        u.mae          = m.mae_lsb;
    end
end

function status_str = formatMonotonicityStatus(m)
    if m.is_monotonic
        status_str = "Monotônico";
    else
        status_str = sprintf("Não-monot. (%d inv.)", numel(m.nonmono_codes));
    end
end
