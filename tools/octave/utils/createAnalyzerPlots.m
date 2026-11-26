function plots = createAnalyzerPlots(fig, has_controls)
    % =========================================================================
    % CREATEANALYZERPLOTS - Cria os 6 gráficos compartilhados pela GUI e pelo PNG
    % =========================================================================

    if nargin < 2 || isempty(has_controls)
        has_controls = true;
    end

    % Layout 2x3 balanceado (sem painel de telemetria)
    x1 = 0.045; w1 = 0.385;
    x2 = 0.485; w2 = 0.225;
    x3 = 0.760; w3 = 0.220;

    if has_controls
        y_bot = 0.120; h_bot = 0.335;
        y_top = 0.585; h_top = 0.340;
    else
        y_bot = 0.065; h_bot = 0.365;
        y_top = 0.560; h_top = 0.365;
    end

    plots = struct();
    plots.last_wave_label  = "";
    plots.last_err_lim_str = "";

    % Sinal Capturado (8b) vs Ideal Quantizado (256 níveis) vs Referência Contínua
    plots.ax_wave = axes("parent", fig, "position", [x1, y_top, w1, h_top]);
    hold(plots.ax_wave, "on");
    plots.h_ideal_cont  = plot(plots.ax_wave, [0, 1], [0, 0], "--", "color", [0.15, 0.65, 0.25], "linewidth", 1.3);
    plots.h_ideal_quant = stairs(plots.ax_wave, [0, 1], [0, 0], "color", [0.90, 0.45, 0.05], "linewidth", 1.2);
    plots.h_wave        = stairs(plots.ax_wave, [0, 1], [0, 0], "color", [0.05, 0.30, 0.85], "linewidth", 1.1);
    plots.h_trig        = plot(plots.ax_wave, [0, 1], [127.5, 127.5], ":r", "linewidth", 1.0);
    hold(plots.ax_wave, "off");
    grid(plots.ax_wave, "on");
    xlabel(plots.ax_wave, "Índice da Amostra (após Trigger)");
    ylabel(plots.ax_wave, "Código ADC (0 a 255)");
    title(plots.ax_wave, "Sinal 8b vs. Referência Ideal", "fontsize", 9.5, "interpreter", "none");
    legend(plots.ax_wave, {"Ideal Contínuo", "Ideal Quant. (256 nív.)", "Capturado (ADC 8b)", "Trigger"}, ...
           "location", "northeast", "fontsize", 8);

    % FFT Tripla (ADC vs Quantizado Ideal vs Referência Contínua)
    plots.ax_fft = axes("parent", fig, "position", [x2, y_top, w2, h_top]);
    hold(plots.ax_fft, "on");
    plots.h_fft_ref   = plot(plots.ax_fft, [0, 1], [-120, -120], "--", "color", [0.15, 0.65, 0.25], "linewidth", 1.3);
    plots.h_fft_quant = plot(plots.ax_fft, [0, 1], [-120, -120], "-",  "color", [0.95, 0.55, 0.10], "linewidth", 1.0);
    plots.h_fft_adc   = plot(plots.ax_fft, [0, 1], [-120, -120], "-",  "color", [0.05, 0.30, 0.85], "linewidth", 1.1);
    plots.h_fft_peak  = plot(plots.ax_fft, NaN, NaN, "ro", "markersize", 6, "linewidth", 1.5);
    hold(plots.ax_fft, "off");
    grid(plots.ax_fft, "on");
    ylim(plots.ax_fft, [-105, 5]);
    xlabel(plots.ax_fft, "Frequência (Hz)");
    ylabel(plots.ax_fft, "Magnitude (dBFS)");
    title(plots.ax_fft, "FFT: ADC vs. Quantizado vs. Referência", "fontsize", 9.5, "interpreter", "none");
    legend(plots.ax_fft, {"FFT Ideal Puro", "FFT Quantizado 256n", "FFT ADC Capturado", "Fundamental"}, ...
           "location", "northeast", "fontsize", 7.5);

    % Curva de Transferência Real vs Ideal + Reta Ajustada
    plots.ax_trans = axes("parent", fig, "position", [x3, y_top, w3, h_top]);
    hold(plots.ax_trans, "on");
    plots.h_trans_ideal = plot(plots.ax_trans, [0, 255], [0, 255], "--", "color", [0.15, 0.65, 0.25], "linewidth", 1.3);
    plots.h_trans_fit   = plot(plots.ax_trans, [0, 255], [0, 255], "-r", "linewidth", 1.1);
    plots.h_trans_real  = stairs(plots.ax_trans, 0:255, 0:255, "color", [0.05, 0.30, 0.85], "linewidth", 1.1);
    hold(plots.ax_trans, "off");
    grid(plots.ax_trans, "on");
    xlim(plots.ax_trans, [0, 255]);
    ylim(plots.ax_trans, [-5, 260]);
    xlabel(plots.ax_trans, "Nível Ideal de Entrada (0 a 255)");
    ylabel(plots.ax_trans, "Código Médio de Saída do ADC");
    title(plots.ax_trans, "Curva de Transferência", "fontsize", 9.5, "interpreter", "none");
    legend(plots.ax_trans, {"Ideal (G=1, Off=0)", "Reta Ajustada", "Curva Real ADC"}, ...
           "location", "northwest", "fontsize", 7.5);

    % Erros no Tempo (Bruto e Intrínseco)
    plots.ax_err = axes("parent", fig, "position", [x1, y_bot, w1, h_bot]);
    hold(plots.ax_err, "on");
    plots.h_err_raw   = plot(plots.ax_err, [0, 1], [0, 0], "-", "color", [0.05, 0.30, 0.85], "linewidth", 0.9);
    plots.h_err_intr  = plot(plots.ax_err, [0, 1], [0, 0], "-", "color", [0.85, 0.35, 0.05], "linewidth", 0.9);
    plots.h_err_lim_p = plot(plots.ax_err, [0, 1], [0.5, 0.5], "--k", "linewidth", 0.8);
    plots.h_err_lim_n = plot(plots.ax_err, [0, 1], [-0.5, -0.5], "--k", "linewidth", 0.8);
    hold(plots.ax_err, "off");
    grid(plots.ax_err, "on");
    xlabel(plots.ax_err, "Índice da Amostra");
    ylabel(plots.ax_err, "Erro (LSB)");
    title(plots.ax_err, "Erro Instantâneo", "fontsize", 9.5, "interpreter", "none");
    legend(plots.ax_err, {"Erro Bruto (ADC - Ideal)", "Erro Intrínseco (s/ Ganho/Off)", "+0.5 LSB", "-0.5 LSB"}, ...
           "location", "northeast", "fontsize", 7.5);

    % DNL (Não-Linearidade Diferencial)
    plots.ax_dnl = axes("parent", fig, "position", [x2, y_bot, w2, h_bot]);
    hold(plots.ax_dnl, "on");
    plots.h_dnl = plot(plots.ax_dnl, 0:255, nan(256, 1), "-b", "linewidth", 1.0);
    plot(plots.ax_dnl, [0, 255], [0.5, 0.5], "--k", "linewidth", 0.8);
    plot(plots.ax_dnl, [0, 255], [-0.5, -0.5], "--k", "linewidth", 0.8);
    plot(plots.ax_dnl, [0, 255], [-1.0, -1.0], "-r", "linewidth", 1.0);
    hold(plots.ax_dnl, "off");
    grid(plots.ax_dnl, "on");
    xlim(plots.ax_dnl, [0, 255]);
    ylim(plots.ax_dnl, [-1.5, 1.5]);
    xlabel(plots.ax_dnl, "Código Digital k (0 a 255)");
    ylabel(plots.ax_dnl, "DNL (LSB)");
    title(plots.ax_dnl, "DNL", "fontsize", 9.5, "interpreter", "none");

    % INL (Não-Linearidade Integral)
    plots.ax_inl = axes("parent", fig, "position", [x3, y_bot, w3, h_bot]);
    hold(plots.ax_inl, "on");
    plots.h_inl     = plot(plots.ax_inl, 0:255, nan(256, 1), "-m", "linewidth", 1.1);
    plots.h_nonmono = plot(plots.ax_inl, NaN, NaN, "rx", "markersize", 7, "linewidth", 1.5);
    plot(plots.ax_inl, [0, 255], [1.0, 1.0], "--k", "linewidth", 0.8);
    plot(plots.ax_inl, [0, 255], [-1.0, -1.0], "--k", "linewidth", 0.8);
    hold(plots.ax_inl, "off");
    grid(plots.ax_inl, "on");
    xlim(plots.ax_inl, [0, 255]);
    ylim(plots.ax_inl, [-2.5, 2.5]);
    xlabel(plots.ax_inl, "Código Digital k (0 a 255)");
    ylabel(plots.ax_inl, "INL (LSB)");
    title(plots.ax_inl, "INL", "fontsize", 9.5, "interpreter", "none");
end
