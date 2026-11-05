function out_png = exportSingleDashboardPng(m, output_dir, VREF, LSB_MV)
    % =========================================================================
    % EXPORTSINGLEDASHBOARDPNG - Exporta o painel de 6 gráficos de uma captura para PNG
    % =========================================================================

    fig = figure("visible", "off", "position", [20, 20, 1520, 880], "color", [0.95, 0.96, 0.98]);

    win_show = min(numel(m.x_plot), max(256, round(2.2 * m.period_samples)));
    x_win_mask = (m.x_plot <= win_show);

    % 1. Sinal Capturado vs Ideal Quantizado (256 níveis) vs Triangular Contínuo
    ax1 = axes("parent", fig, "position", [0.04, 0.59, 0.44, 0.35]);
    hold(ax1, "on");
    plot(ax1, m.x_plot(x_win_mask), m.ideal_cont_plot(x_win_mask), "--", "color", [0.15, 0.65, 0.25], "linewidth", 1.3);
    stairs(ax1, m.x_plot(x_win_mask), m.ideal_quant_plot(x_win_mask), "color", [0.90, 0.45, 0.05], "linewidth", 1.1);
    stairs(ax1, m.x_plot(x_win_mask), m.y_plot(x_win_mask), "color", [0.05, 0.30, 0.85], "linewidth", 1.1);
    plot(ax1, [0, win_show], [m.trig_level, m.trig_level], ":r", "linewidth", 1.0);
    hold(ax1, "off");
    grid(ax1, "on");
    xlim(ax1, [0, win_show]);
    ylim(ax1, [-10, 265]);
    xlabel(ax1, "Índice da Amostra (após Trigger)");
    ylabel(ax1, "Código ADC (0 a 255) [Vref = 2.56 V]");
    title(ax1, sprintf("1. Sinal 8b vs. Ideal Quantizado 256n [%s | f=%.2f Hz | fs=%.1f Hz]", ...
                       m.file_name, m.freq_hz, m.actual_sampling_frequency), "interpreter", "none");
    legend(ax1, {"Triangular Contínuo", "Ideal Quantizado (256 nív.)", "Capturado (ADC 8b)", "Trigger"}, ...
           "location", "northeast", "fontsize", 8);

    % 2. FFT Tripla
    ax2 = axes("parent", fig, "position", [0.53, 0.59, 0.21, 0.35]);
    f_max_view = min(m.actual_sampling_frequency / 2.0, max(120.0, 16.0 * m.freq_hz));
    hold(ax2, "on");
    plot(ax2, m.freq_axis, m.mag_dbfs_tri, "--", "color", [0.15, 0.65, 0.25], "linewidth", 1.3);
    plot(ax2, m.freq_axis, m.mag_dbfs_quant, "-", "color", [0.95, 0.55, 0.10], "linewidth", 1.0);
    plot(ax2, m.freq_axis, m.mag_dbfs, "-", "color", [0.05, 0.30, 0.85], "linewidth", 1.1);
    plot(ax2, m.fund_freq_fft, m.fund_mag_dbfs, "ro", "markersize", 6, "linewidth", 1.5);
    hold(ax2, "off");
    grid(ax2, "on");
    xlim(ax2, [0, f_max_view]);
    ylim(ax2, [-105, 5]);
    xlabel(ax2, "Frequência (Hz)");
    ylabel(ax2, "Magnitude (dBFS)");
    title(ax2, "2. FFT: ADC vs. Quantizado Ideal vs. Triangular");
    legend(ax2, {"FFT Triangular Puro", "FFT Quantizado 256n", "FFT ADC Capturado", "Fundamental"}, ...
           "location", "northeast", "fontsize", 7.5);

    % 3. Curva de Transferência Real vs Ideal
    ax3 = axes("parent", fig, "position", [0.78, 0.59, 0.19, 0.35]);
    x_codes = (0:255)';
    y_fit_line = m.measured_gain * x_codes + m.intercept_lsb;
    hold(ax3, "on");
    plot(ax3, x_codes, x_codes, "--", "color", [0.15, 0.65, 0.25], "linewidth", 1.3);
    plot(ax3, x_codes, y_fit_line, "-r", "linewidth", 1.1);
    stairs(ax3, x_codes, m.mean_adc_per_level, "color", [0.05, 0.30, 0.85], "linewidth", 1.1);
    hold(ax3, "off");
    grid(ax3, "on");
    xlim(ax3, [0, 255]);
    ylim(ax3, [-5, 260]);
    xlabel(ax3, "Nível Ideal de Entrada (0 a 255)");
    ylabel(ax3, "Código Médio de Saída do ADC");
    title(ax3, sprintf("3. Transferência (G=%.4f | Off=%+.2f LSB)", m.measured_gain, m.offset_error_lsb));
    legend(ax3, {"Ideal (G=1, Off=0)", "Reta Ajustada", "Curva Real ADC"}, ...
           "location", "northwest", "fontsize", 7.5);

    % 4. Erros no Tempo (Bruto e Intrínseco)
    ax4 = axes("parent", fig, "position", [0.04, 0.30, 0.44, 0.19]);
    hold(ax4, "on");
    plot(ax4, m.x_plot(x_win_mask), m.err_vs_cont_lsb(x_win_mask), "-", "color", [0.05, 0.30, 0.85], "linewidth", 0.9);
    plot(ax4, m.x_plot(x_win_mask), m.err_intrinsic_lsb(x_win_mask), "-", "color", [0.85, 0.35, 0.05], "linewidth", 0.9);
    plot(ax4, [0, win_show], [0.5, 0.5], "--k", "linewidth", 0.8);
    plot(ax4, [0, win_show], [-0.5, -0.5], "--k", "linewidth", 0.8);
    hold(ax4, "off");
    grid(ax4, "on");
    xlim(ax4, [0, win_show]);
    max_e = max(1.5, min(20, 1.15 * max(abs(m.err_vs_cont_lsb(x_win_mask)))));
    ylim(ax4, [-max_e, max_e]);
    xlabel(ax4, "Índice da Amostra");
    ylabel(ax4, "Erro (LSB)");
    title(ax4, sprintf("4. Erro Instantâneo (RMSE Bruto=%.2f LSB [%.2f%%FSR] | Intrínseco=%.2f LSB | MAE=%.2f LSB)", ...
                       m.rmse_lsb, m.rmse_pct_fsr, m.rmse_intrinsic_lsb, m.mae_lsb));
    legend(ax4, {"Erro Bruto (ADC - Ideal)", "Erro Intrínseco (s/ Ganho/Off)", "+0.5 LSB", "-0.5 LSB"}, ...
           "location", "northeast", "fontsize", 7.5);

    % 5. DNL
    ax5 = axes("parent", fig, "position", [0.53, 0.10, 0.21, 0.38]);
    hold(ax5, "on");
    plot(ax5, 0:255, m.dnl, "-b", "linewidth", 1.0);
    plot(ax5, [0, 255], [0.5, 0.5], "--k", "linewidth", 0.8);
    plot(ax5, [0, 255], [-0.5, -0.5], "--k", "linewidth", 0.8);
    plot(ax5, [0, 255], [-1.0, -1.0], "-r", "linewidth", 1.0);
    hold(ax5, "off");
    grid(ax5, "on");
    xlim(ax5, [0, 255]);
    ylim(ax5, [min(-1.2, m.dnl_min - 0.25), max(1.2, m.dnl_max + 0.25)]);
    xlabel(ax5, "Código Digital k (0 a 255)");
    ylabel(ax5, "DNL (LSB)");
    title(ax5, sprintf("5. DNL (Min=%+.2f | Max=%+.2f | RMS=%.2f LSB)", m.dnl_min, m.dnl_max, m.dnl_rms));

    % 6. INL e Monotonicidade
    ax6 = axes("parent", fig, "position", [0.78, 0.10, 0.19, 0.38]);
    hold(ax6, "on");
    plot(ax6, 0:255, m.inl, "-m", "linewidth", 1.1);
    if ~isempty(m.nonmono_codes)
        plot(ax6, m.nonmono_codes, m.inl(m.nonmono_codes + 1), "rx", "markersize", 7, "linewidth", 1.5);
    end
    plot(ax6, [0, 255], [1.0, 1.0], "--k", "linewidth", 0.8);
    plot(ax6, [0, 255], [-1.0, -1.0], "--k", "linewidth", 0.8);
    hold(ax6, "off");
    grid(ax6, "on");
    xlim(ax6, [0, 255]);
    ylim(ax6, [min(-1.5, m.inl_min - 0.4), max(1.5, m.inl_max + 0.4)]);
    xlabel(ax6, "Código Digital k (0 a 255)");
    ylabel(ax6, "INL (LSB)");
    title(ax6, sprintf("6. INL (Min=%+.2f | Max=%+.2f LSB | Miss=%d)", m.inl_min, m.inl_max, m.missing_codes));

    % Caixa de Resumo Textual Inferior Esquerda
    ax_txt = axes("parent", fig, "position", [0.04, 0.04, 0.44, 0.21], ...
                  "xtick", [], "ytick", [], "color", [0.10, 0.12, 0.16], "box", "on");
    if m.is_monotonic
        mono_s = "SIM (Monotônico)";
    else
        mono_s = sprintf("NÃO (%d inv | %d miss)", numel(m.nonmono_codes), m.missing_codes);
    end

    summary_left = sprintf([ ...
        "TELEMETRIA DO ADC (Vref = 2.56 V | 1 LSB = 10.0 mV)\n", ...
        "Arquivo    : %s\n", ...
        "Frequência : f = %.2f Hz | fs = %.1f Hz (Pre=%d)\n", ...
        "Período    : T = %.2f ms (%.1f amostras/ciclo)\n", ...
        "Excursão   : %.0f a %.0f LSB (%.2f a %.2f V)\n", ...
        "Offset     : %+.2f LSB (%+.1f mV | %+.2f %%FSR)\n", ...
        "Ganho      : %+.2f LSB (%+.1f mV | %+.2f %%FSR | G=%.4f)"], ...
        m.file_name, m.freq_hz, m.actual_sampling_frequency, m.adc_prescaler, ...
        m.period_sec * 1e3, m.period_samples, ...
        m.s_min, m.s_max, m.s_min * (VREF / 256.0), m.s_max * (VREF / 256.0), ...
        m.offset_error_lsb, m.offset_error_mv, m.offset_error_pct, ...
        m.gain_error_lsb, m.gain_error_mv, m.gain_error_pct, m.measured_gain);

    summary_right = sprintf([ ...
        "ERROS E FAIXA DINÂMICA\n", ...
        "RMSE Bruto / Intrín.: %.2f LSB (%.1f mV) / %.2f LSB (%.1f mV)\n", ...
        "Erro Abs Médio / Máx: MAE = %.2f LSB / Max = %.2f LSB\n", ...
        "Erro Relativo       : %.2f %%FSR (MAPE = %.2f%% do sinal)\n", ...
        "DNL / INL (LSB)     : [%+.2f, %+.2f] / [%+.2f, %+.2f]\n", ...
        "Monotonicidade      : %s\n", ...
        "Faixa Dinâmica /ENOB: DR = %.1f dB (Ideal 8b: %.1f dB) | ENOB = %.2f b"], ...
        m.rmse_lsb, m.rmse_mv, m.rmse_intrinsic_lsb, m.rmse_intrinsic_mv, ...
        m.mae_lsb, m.max_abs_err_lsb, ...
        m.mae_pct_fsr, m.mape_signal_pct, ...
        m.dnl_min, m.dnl_max, m.inl_min, m.inl_max, ...
        mono_s, ...
        m.dr_db, m.dr_quant_db, m.enob_tri_intrin_bits);

    text(ax_txt, 0.015, 0.50, summary_left, "color", [0.10, 0.45, 0.18], ...
         "fontname", "FixedWidth", "fontsize", 8.0, "verticalalignment", "middle", "interpreter", "none");
    text(ax_txt, 0.485, 0.50, summary_right, "color", [0.08, 0.30, 0.62], ...
         "fontname", "FixedWidth", "fontsize", 8.0, "verticalalignment", "middle", "interpreter", "none");

    [~, base_n, ~] = fileparts(m.file_name);
    out_png = fullfile(output_dir, ["analysis_", base_n, ".png"]);
    print(fig, out_png, "-dpng", "-r150");
    close(fig);
    printf("Painel exportado para: %s\n", out_png);
end
