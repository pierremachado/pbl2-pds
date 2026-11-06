function m_current = launchAnalyzerDashboard(mat_files, init_idx, data_dir, output_dir, VREF, LSB_MV)
    % =========================================================================
    % LAUNCHANALYZERDASHBOARD - Painel Digital Interativo do Analisador de ADC
    % =========================================================================

    file_names = {mat_files.name};

    fig = figure("name", "Analisador de Dados do ADC (ATmega2560 | Vref = 2.56 V | 8 bits = 256 níveis)", ...
                 "numbertitle", "off", ...
                 "toolbar", "figure", ...
                 "color", [0.95, 0.96, 0.98], ...
                 "position", [20, 20, 1520, 880]);

    % 1. GRÁFICO SUPERIOR ESQUERDO: Sinal Capturado (8b) vs Ideal Quantizado (256 níveis) vs Triangular Ideal
    ax_wave = axes("parent", fig, "position", [0.04, 0.58, 0.44, 0.36]);
    hold(ax_wave, "on");
    h_ideal_cont  = plot(ax_wave, [0, 1], [0, 0], "--", "color", [0.15, 0.65, 0.25], "linewidth", 1.3);
    h_ideal_quant = stairs(ax_wave, [0, 1], [0, 0], "color", [0.90, 0.45, 0.05], "linewidth", 1.2);
    h_wave        = stairs(ax_wave, [0, 1], [0, 0], "color", [0.05, 0.30, 0.85], "linewidth", 1.1);
    h_trig        = plot(ax_wave, [0, 1], [127.5, 127.5], ":r", "linewidth", 1.0);
    hold(ax_wave, "off");
    grid(ax_wave, "on");
    xlabel(ax_wave, "Índice da Amostra (após Trigger)");
    ylabel(ax_wave, "Código ADC (0 a 255)");
    title(ax_wave, "1. Sinal 8 bits Capturado vs. Ideal Quantizado (256 níveis) vs. Triangular Contínuo", "interpreter", "none");
    legend(ax_wave, {"Triangular Contínuo", "Ideal Quantizado (256 nív.)", "Capturado (ADC 8b)", "Trigger"}, ...
           "location", "northeast", "fontsize", 8);

    % 2. GRÁFICO SUPERIOR CENTRAL: FFT Tripla (ADC vs Quantizado Ideal vs Triangular Normal)
    ax_fft = axes("parent", fig, "position", [0.53, 0.58, 0.21, 0.36]);
    hold(ax_fft, "on");
    h_fft_tri   = plot(ax_fft, [0, 1], [-120, -120], "--", "color", [0.15, 0.65, 0.25], "linewidth", 1.3);
    h_fft_quant = plot(ax_fft, [0, 1], [-120, -120], "-",  "color", [0.95, 0.55, 0.10], "linewidth", 1.0);
    h_fft_adc   = plot(ax_fft, [0, 1], [-120, -120], "-",  "color", [0.05, 0.30, 0.85], "linewidth", 1.1);
    h_fft_peak  = plot(ax_fft, 0, 0, "ro", "markersize", 6, "linewidth", 1.5);
    hold(ax_fft, "off");
    grid(ax_fft, "on");
    ylim(ax_fft, [-105, 5]);
    xlabel(ax_fft, "Frequência (Hz)");
    ylabel(ax_fft, "Magnitude (dBFS)");
    title(ax_fft, "2. FFT: ADC vs. Quantizado Ideal vs. Triangular");
    legend(ax_fft, {"FFT Triangular Puro", "FFT Quantizado 256n", "FFT ADC Capturado", "Fundamental"}, ...
           "location", "northeast", "fontsize", 7.5);

    % 3. GRÁFICO SUPERIOR DIREITO: Curva de Quantização Real vs Ideal + Ganho/Offset
    ax_trans = axes("parent", fig, "position", [0.78, 0.58, 0.19, 0.36]);
    hold(ax_trans, "on");
    h_trans_ideal = plot(ax_trans, [0, 255], [0, 255], "--", "color", [0.15, 0.65, 0.25], "linewidth", 1.3);
    h_trans_fit   = plot(ax_trans, [0, 255], [0, 255], "-r", "linewidth", 1.1);
    h_trans_real  = stairs(ax_trans, 0:255, 0:255, "color", [0.05, 0.30, 0.85], "linewidth", 1.1);
    hold(ax_trans, "off");
    grid(ax_trans, "on");
    xlim(ax_trans, [0, 255]);
    ylim(ax_trans, [-5, 260]);
    xlabel(ax_trans, "Nível Ideal de Entrada (0 a 255)");
    ylabel(ax_trans, "Código Médio de Saída do ADC");
    title(ax_trans, "3. Curva de Transferência (Offset e Ganho)");
    legend(ax_trans, {"Ideal (G=1, Off=0)", "Reta Ajustada", "Curva Real ADC"}, ...
           "location", "northwest", "fontsize", 7.5);

    % 4. GRÁFICO CENTRAL ESQUERDO: Erros de Quantização, Absoluto e Relativo no Tempo
    ax_err = axes("parent", fig, "position", [0.04, 0.31, 0.44, 0.18]);
    hold(ax_err, "on");
    h_err_raw   = plot(ax_err, [0, 1], [0, 0], "-", "color", [0.05, 0.30, 0.85], "linewidth", 0.9);
    h_err_intr  = plot(ax_err, [0, 1], [0, 0], "-", "color", [0.85, 0.35, 0.05], "linewidth", 0.9);
    h_err_lim_p = plot(ax_err, [0, 1], [0.5, 0.5], "--k", "linewidth", 0.8);
    h_err_lim_n = plot(ax_err, [0, 1], [-0.5, -0.5], "--k", "linewidth", 0.8);
    hold(ax_err, "off");
    grid(ax_err, "on");
    xlabel(ax_err, "Índice da Amostra");
    ylabel(ax_err, "Erro (LSB)");
    title(ax_err, "4. Erro Instantâneo vs. Ideal (Azul: Bruto | Laranja: Sem Offset/Ganho | Tracejado: +-0.5 LSB = +-0.20%FSR)");
    legend(ax_err, {"Erro Bruto (ADC - Ideal)", "Erro Intrínseco (s/ Ganho/Off)", "+0.5 LSB", "-0.5 LSB"}, ...
           "location", "northeast", "fontsize", 7.5);

    % 5. GRÁFICO INFERIOR CENTRAL: Erro de DNL (LSB)
    ax_dnl = axes("parent", fig, "position", [0.53, 0.10, 0.21, 0.39]);
    hold(ax_dnl, "on");
    h_dnl = plot(ax_dnl, 0:255, zeros(256, 1), "-b", "linewidth", 1.0);
    plot(ax_dnl, [0, 255], [0.5, 0.5], "--k", "linewidth", 0.8);
    plot(ax_dnl, [0, 255], [-0.5, -0.5], "--k", "linewidth", 0.8);
    plot(ax_dnl, [0, 255], [-1.0, -1.0], "-r", "linewidth", 1.0);
    hold(ax_dnl, "off");
    grid(ax_dnl, "on");
    xlim(ax_dnl, [0, 255]);
    ylim(ax_dnl, [-1.5, 1.5]);
    xlabel(ax_dnl, "Código Digital k (0 a 255)");
    ylabel(ax_dnl, "DNL (LSB)");
    title(ax_dnl, "5. Erro de DNL (Não-Linearidade Diferencial)");

    % 6. GRÁFICO INFERIOR DIREITO: Erro de INL (LSB) e Monotonicidade
    ax_inl = axes("parent", fig, "position", [0.78, 0.10, 0.19, 0.39]);
    hold(ax_inl, "on");
    h_inl = plot(ax_inl, 0:255, zeros(256, 1), "-m", "linewidth", 1.1);
    h_nonmono = plot(ax_inl, NaN, NaN, "rx", "markersize", 7, "linewidth", 1.5);
    plot(ax_inl, [0, 255], [1.0, 1.0], "--k", "linewidth", 0.8);
    plot(ax_inl, [0, 255], [-1.0, -1.0], "--k", "linewidth", 0.8);
    hold(ax_inl, "off");
    grid(ax_inl, "on");
    xlim(ax_inl, [0, 255]);
    ylim(ax_inl, [-2.5, 2.5]);
    xlabel(ax_inl, "Código Digital k (0 a 255)");
    ylabel(ax_inl, "INL (LSB)");
    title(ax_inl, "6. Erro de INL (LSB) e Monotonicidade");

    % 7. PAINEL DE TELEMETRIA DIGITAL EM 3 COLUNAS (Vref = 2.56V, 1 LSB = 10 mV)
    pnl_info = uipanel("parent", fig, ...
                       "title", "Telemetria Completa do ADC (Vref = 2.56 V | 1 LSB = 10.0 mV | 256 Níveis)", ...
                       "units", "normalized", "position", [0.04, 0.085, 0.44, 0.19], ...
                       "backgroundcolor", [0.10, 0.12, 0.16], ...
                       "foregroundcolor", [0.92, 0.96, 1.00]);

    txt_col1 = uicontrol("parent", pnl_info, "style", "text", ...
                         "units", "normalized", "position", [0.01, 0.02, 0.32, 0.95], ...
                         "horizontalalignment", "left", ...
                         "fontname", "FixedWidth", "fontsize", 8.5, ...
                         "backgroundcolor", [0.10, 0.12, 0.16], ...
                         "foregroundcolor", [0.35, 1.00, 0.55], ...
                         "string", "Carregando...");

    txt_col2 = uicontrol("parent", pnl_info, "style", "text", ...
                         "units", "normalized", "position", [0.34, 0.02, 0.33, 0.95], ...
                         "horizontalalignment", "left", ...
                         "fontname", "FixedWidth", "fontsize", 8.5, ...
                         "backgroundcolor", [0.10, 0.12, 0.16], ...
                         "foregroundcolor", [1.00, 0.85, 0.35], ...
                         "string", "");

    txt_col3 = uicontrol("parent", pnl_info, "style", "text", ...
                         "units", "normalized", "position", [0.68, 0.02, 0.31, 0.95], ...
                         "horizontalalignment", "left", ...
                         "fontname", "FixedWidth", "fontsize", 8.5, ...
                         "backgroundcolor", [0.10, 0.12, 0.16], ...
                         "foregroundcolor", [0.45, 0.90, 1.00], ...
                         "string", "");

    % 8. CONTROLES INFERIORES (Seletor de Arquivo, Unidade, Salvar e Lote)
    uicontrol(fig, "style", "text", "units", "normalized", ...
              "position", [0.04, 0.045, 0.05, 0.028], ...
              "backgroundcolor", [0.95, 0.96, 0.98], "string", "Arquivo:");

    pop_file = uicontrol(fig, "style", "popupmenu", "units", "normalized", ...
                         "position", [0.09, 0.045, 0.16, 0.030], ...
                         "string", file_names, "value", init_idx);

    btn_prev = uicontrol(fig, "style", "pushbutton", "units", "normalized", ...
                         "position", [0.255, 0.045, 0.03, 0.030], "string", "<");

    btn_next = uicontrol(fig, "style", "pushbutton", "units", "normalized", ...
                         "position", [0.288, 0.045, 0.03, 0.030], "string", ">");

    uicontrol(fig, "style", "text", "units", "normalized", ...
              "position", [0.325, 0.045, 0.045, 0.028], ...
              "backgroundcolor", [0.95, 0.96, 0.98], "string", "Unidade:");

    pop_unit = uicontrol(fig, "style", "popupmenu", "units", "normalized", ...
                         "position", [0.37, 0.045, 0.11, 0.030], ...
                         "string", {"Código ADC (0..255)", "Tensão (0..2.56 V)", "Erro Relativo (%FSR)"}, ...
                         "value", 1);

    btn_save = uicontrol(fig, "style", "togglebutton", "units", "normalized", ...
                         "position", [0.325, 0.008, 0.075, 0.032], ...
                         "backgroundcolor", [0.20, 0.55, 0.30], ...
                         "foregroundcolor", [1.00, 1.00, 1.00], ...
                         "string", "SALVAR .MAT/.PNG", "value", 0);

    btn_batch = uicontrol(fig, "style", "togglebutton", "units", "normalized", ...
                          "position", [0.405, 0.008, 0.075, 0.032], ...
                          "backgroundcolor", [0.18, 0.38, 0.68], ...
                          "foregroundcolor", [1.00, 1.00, 1.00], ...
                          "string", "RELATÓRIO LOTE", "value", 0);

    curr_idx = -1;
    m_current = struct();

    set(btn_prev, "callback", @(~, ~) step_file(pop_file, -1, numel(mat_files)));
    set(btn_next, "callback", @(~, ~) step_file(pop_file, +1, numel(mat_files)));

    while ishandle(fig)
        sel_idx = get(pop_file, "value");
        file_changed = sel_idx ~= curr_idx;
        if file_changed
            curr_idx = sel_idx;
            fpath = fullfile(data_dir, mat_files(curr_idx).name);
            m_current = analyzeSingleCapture(fpath, VREF, LSB_MV, "opt");
            nx = numel(m_current.x_plot);
            default_win = min(max(128, round(2.5 * m_current.period_samples)), round(0.5 * nx));
            prev_unit_mode = -1;
        end

        unit_mode = get(pop_unit, "value");
        % A navegação fica a cargo das ferramentas nativas do Octave.
        % Reinicia a vista somente ao carregar outro arquivo.
        pan_start = [];
        win_len = [];
        if file_changed
            pan_start = 0;
            win_len = max(16, min(default_win, nx));
        end

        if unit_mode ~= prev_unit_mode
            updateAnalyzerDashboard(m_current, unit_mode, pan_start, win_len, VREF, LSB_MV, ...
                                    ax_wave, h_ideal_cont, h_ideal_quant, h_wave, h_trig, ...
                                    ax_fft, h_fft_tri, h_fft_quant, h_fft_adc, h_fft_peak, ...
                                    ax_trans, h_trans_ideal, h_trans_fit, h_trans_real, ...
                                    ax_err, h_err_raw, h_err_intr, h_err_lim_p, h_err_lim_n, ...
                                    ax_dnl, h_dnl, ax_inl, h_inl, h_nonmono, ...
                                    txt_col1, txt_col2, txt_col3);
            prev_unit_mode = unit_mode;
        end

        if ishandle(btn_save) && get(btn_save, "value") == 1
            set(btn_save, "value", 0);
            saveEnrichedMat(m_current.file_path, m_current);
            out_png = exportSingleDashboardPng(m_current, output_dir, VREF, LSB_MV);
            printf("Arquivo .mat atualizado (%s) e painel PNG salvo (%s)!\n", m_current.file_path, out_png);
        end

        if ishandle(btn_batch) && get(btn_batch, "value") == 1
            set(btn_batch, "value", 0);
            runBatchAnalysis(mat_files, data_dir, output_dir, VREF, LSB_MV, false);
        end

        drawnow;
        pause(0.04);
    end
end

function step_file(pop_h, delta, n_total)
    v = get(pop_h, "value");
    v_new = max(1, min(n_total, v + delta));
    set(pop_h, "value", v_new);
end
