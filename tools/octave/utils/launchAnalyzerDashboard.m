function m_current = launchAnalyzerDashboard(mat_files, init_idx, data_dir, output_dir, VREF, LSB_MV, init_wave_type)
    % =========================================================================
    % LAUNCHANALYZERDASHBOARD - Painel Digital Interativo do Analisador de ADC
    % =========================================================================

    if nargin < 7
        init_wave_type = "";
    end

    file_names = {mat_files.name};
    wave_types  = {"triangular", "sine", "sawtooth", "square"};
    wave_labels = {"Triangular", "Senoidal", "Dente de Serra", "Quadrada"};

    init_wave_idx = 1;
    if ~isempty(init_wave_type)
        w0 = getWaveformSpec(init_wave_type);
        idx_match = find(strcmp(wave_types, w0.type), 1);
        if ~isempty(idx_match)
            init_wave_idx = idx_match;
        end
    end

    fig = figure("name", "Analisador de Dados do ADC (ATmega2560 | Vref = 2.56 V | 8 bits = 256 níveis)", ...
                 "numbertitle", "off", ...
                 "toolbar", "figure", ...
                 "color", [0.95, 0.96, 0.98], ...
                 "position", [20, 20, 1520, 880]);

    % 1..6. Gráficos compartilhados com a exportação PNG
    plots = createAnalyzerPlots(fig);

    % 7. PAINEL DE TELEMETRIA DIGITAL EM 3 COLUNAS (Vref = 2.56V, 1 LSB = 10 mV)
    pnl_info = uipanel("parent", fig, ...
                       "title", "Telemetria Completa do ADC (Vref = 2.56 V | 1 LSB = 10.0 mV | 256 Níveis)", ...
                       "units", "normalized", "position", [0.04, 0.085, 0.44, 0.19], ...
                       "backgroundcolor", [0.10, 0.12, 0.16], ...
                       "foregroundcolor", [0.92, 0.96, 1.00]);

    txt_cols = struct();
    txt_cols.col1 = uicontrol("parent", pnl_info, "style", "text", ...
                              "units", "normalized", "position", [0.01, 0.02, 0.32, 0.95], ...
                              "horizontalalignment", "left", ...
                              "fontname", "FixedWidth", "fontsize", 8.5, ...
                              "backgroundcolor", [0.10, 0.12, 0.16], ...
                              "foregroundcolor", [0.35, 1.00, 0.55], ...
                              "string", "Carregando...");

    txt_cols.col2 = uicontrol("parent", pnl_info, "style", "text", ...
                              "units", "normalized", "position", [0.34, 0.02, 0.33, 0.95], ...
                              "horizontalalignment", "left", ...
                              "fontname", "FixedWidth", "fontsize", 8.5, ...
                              "backgroundcolor", [0.10, 0.12, 0.16], ...
                              "foregroundcolor", [1.00, 0.85, 0.35], ...
                              "string", "");

    txt_cols.col3 = uicontrol("parent", pnl_info, "style", "text", ...
                              "units", "normalized", "position", [0.68, 0.02, 0.31, 0.95], ...
                              "horizontalalignment", "left", ...
                              "fontname", "FixedWidth", "fontsize", 8.5, ...
                              "backgroundcolor", [0.10, 0.12, 0.16], ...
                              "foregroundcolor", [0.45, 0.90, 1.00], ...
                              "string", "");

    % 8. CONTROLES INFERIORES (Arquivo, Forma de Onda, Unidade, Escala FFT, Salvar e Lote)
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

    uicontrol(fig, "style", "text", "units", "normalized", ...
              "position", [0.04, 0.008, 0.05, 0.028], ...
              "backgroundcolor", [0.95, 0.96, 0.98], "string", "Onda:");

    pop_wave = uicontrol(fig, "style", "popupmenu", "units", "normalized", ...
                         "position", [0.09, 0.008, 0.16, 0.030], ...
                         "string", wave_labels, "value", init_wave_idx);

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

    uicontrol(fig, "style", "text", "units", "normalized", ...
              "position", [0.53, 0.012, 0.065, 0.028], ...
              "backgroundcolor", [0.95, 0.96, 0.98], "string", "Escala FFT:");

    pop_fft_scale = uicontrol(fig, "style", "popupmenu", "units", "normalized", ...
                              "position", [0.60, 0.012, 0.14, 0.030], ...
                              "string", {"dBFS (log)", "Linear (0-100%)"}, ...
                              "value", 1);

    curr_idx = -1;
    curr_wave_idx = -1;
    m_current = struct();

    set(btn_prev, "callback", @(~, ~) step_file(pop_file, -1, numel(mat_files)));
    set(btn_next, "callback", @(~, ~) step_file(pop_file, +1, numel(mat_files)));

    while ishandle(fig)
        sel_idx = get(pop_file, "value");
        sel_wave_idx = get(pop_wave, "value");
        file_changed = (sel_idx ~= curr_idx);
        wave_changed = (sel_wave_idx ~= curr_wave_idx);

        if file_changed || wave_changed
            curr_idx = sel_idx;
            curr_wave_idx = sel_wave_idx;
            fpath = fullfile(data_dir, mat_files(curr_idx).name);
            selected_wave = wave_types{curr_wave_idx};
            m_current = analyzeSingleCapture(fpath, VREF, LSB_MV, "opt", selected_wave);
            nx = numel(m_current.x_plot);
            default_win = min(max(128, round(2.5 * m_current.period_samples)), round(0.5 * nx));
            prev_unit_mode = -1;
            prev_fft_scale = -1;
        end

        unit_mode = get(pop_unit, "value");
        fft_scale_mode = get(pop_fft_scale, "value");
        % A navegação fica a cargo das ferramentas nativas do Octave.
        % Reinicia a vista somente ao carregar outro arquivo.
        pan_start = [];
        win_len = [];
        if file_changed
            pan_start = 0;
            win_len = max(16, min(default_win, nx));
        end

        if unit_mode ~= prev_unit_mode || fft_scale_mode ~= prev_fft_scale
            updateAnalyzerDashboard(m_current, unit_mode, pan_start, win_len, VREF, LSB_MV, plots, txt_cols, fft_scale_mode);
            prev_unit_mode = unit_mode;
            prev_fft_scale = fft_scale_mode;
        end

        if ishandle(btn_save) && get(btn_save, "value") == 1
            set(btn_save, "value", 0);
            saveEnrichedMat(m_current.file_path, m_current);
            out_png = exportSingleDashboardPng(m_current, output_dir, VREF, LSB_MV, fft_scale_mode);
            printf("Arquivo .mat atualizado (%s) e painel PNG salvo (%s)!\n", m_current.file_path, out_png);
        end

        if ishandle(btn_batch) && get(btn_batch, "value") == 1
            set(btn_batch, "value", 0);
            runBatchAnalysis(mat_files, data_dir, output_dir, VREF, LSB_MV, false, wave_types{curr_wave_idx});
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
