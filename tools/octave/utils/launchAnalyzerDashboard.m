function m_current = launchAnalyzerDashboard(mat_files, init_idx, data_dir, output_dir, VREF, LSB_MV, init_wave_type)
    % =========================================================================
    % LAUNCHANALYZERDASHBOARD - Painel Digital Interativo do Analisador de ADC
    % =========================================================================

    if nargin < 7
        init_wave_type = "";
    end

    file_names  = {mat_files.name};
    wave_types  = {"triangular", "sine", "sawtooth", "square"};
    wave_labels = {"Triangular", "Senoidal", "Dente de Serra", "Quadrada"};

    bg_color = [0.95, 0.96, 0.98];
    fig = figure("name", sprintf("Analisador de ADC (ATmega2560 | Vref = %.3g V | 8 bits)", VREF), ...
                 "numbertitle", "off", ...
                 "toolbar", "figure", ...
                 "color", bg_color, ...
                 "position", [20, 20, 1520, 880]);

    % Gráficos compartilhados com a exportação PNG (layout 2x3)
    plots = createAnalyzerPlots(fig, true);

    % Barra única de controles inferiores alinhada aos gráficos (0.045 .. 0.980)
    uicontrol(fig, "style", "text", "units", "normalized", ...
              "position", [0.045, 0.015, 0.045, 0.032], ...
              "horizontalalignment", "right", ...
              "backgroundcolor", bg_color, "string", "Arquivo:");

    pop_file = uicontrol(fig, "style", "popupmenu", "units", "normalized", ...
                         "position", [0.094, 0.015, 0.198, 0.036], ...
                         "string", file_names, "value", init_idx);

    btn_prev = uicontrol(fig, "style", "pushbutton", "units", "normalized", ...
                         "position", [0.296, 0.015, 0.026, 0.036], "string", "<");

    btn_next = uicontrol(fig, "style", "pushbutton", "units", "normalized", ...
                         "position", [0.325, 0.015, 0.026, 0.036], "string", ">");

    uicontrol(fig, "style", "text", "units", "normalized", ...
              "position", [0.362, 0.015, 0.038, 0.032], ...
              "horizontalalignment", "right", ...
              "backgroundcolor", bg_color, "string", "Onda:");

    pop_wave = uicontrol(fig, "style", "popupmenu", "units", "normalized", ...
                         "position", [0.404, 0.015, 0.106, 0.036], ...
                         "string", wave_labels, "value", 1);

    uicontrol(fig, "style", "text", "units", "normalized", ...
              "position", [0.520, 0.015, 0.048, 0.032], ...
              "horizontalalignment", "right", ...
              "backgroundcolor", bg_color, "string", "Unidade:");

    pop_unit = uicontrol(fig, "style", "popupmenu", "units", "normalized", ...
                         "position", [0.572, 0.015, 0.124, 0.036], ...
                         "string", {"Código ADC (0..255)", sprintf("Tensão (0..%.3g V)", VREF), "Erro Relativo (%FSR)"}, ...
                         "value", 1);

    uicontrol(fig, "style", "text", "units", "normalized", ...
              "position", [0.706, 0.015, 0.060, 0.032], ...
              "horizontalalignment", "right", ...
              "backgroundcolor", bg_color, "string", "Escala FFT:");

    pop_fft_scale = uicontrol(fig, "style", "popupmenu", "units", "normalized", ...
                              "position", [0.770, 0.015, 0.100, 0.036], ...
                              "string", {"dBFS (log)", "Linear (0-100%)"}, ...
                              "value", 1);

    btn_save = uicontrol(fig, "style", "togglebutton", "units", "normalized", ...
                         "position", [0.882, 0.013, 0.098, 0.040], ...
                         "backgroundcolor", [0.20, 0.55, 0.30], ...
                         "foregroundcolor", [1.00, 1.00, 1.00], ...
                         "string", "SALVAR .MAT/.PNG", "value", 0);

    curr_idx = -1;
    curr_wave_idx = -1;
    pending_init_wave = init_wave_type;
    m_current = struct();

    set(btn_prev, "callback", @(~, ~) step_file(pop_file, -1, numel(mat_files)));
    set(btn_next, "callback", @(~, ~) step_file(pop_file, +1, numel(mat_files)));

    while ishandle(fig)
        sel_idx = get(pop_file, "value");
        sel_wave_idx = get(pop_wave, "value");
        file_changed = (sel_idx ~= curr_idx);
        wave_changed = (~file_changed) && (sel_wave_idx ~= curr_wave_idx);

        if file_changed || wave_changed
            curr_idx = sel_idx;
            fpath = fullfile(data_dir, mat_files(curr_idx).name);

            if file_changed
                % Sincroniza automaticamente a forma de onda com o .mat ao trocar de arquivo
                req_wave = pending_init_wave;
                pending_init_wave = "";
            else
                req_wave = wave_types{sel_wave_idx};
            end

            m_current = analyzeSingleCapture(fpath, VREF, LSB_MV, "opt", req_wave);
            idx_match = find(strcmp(wave_types, m_current.wave_type), 1);
            if isempty(idx_match)
                idx_match = 1;
            end
            curr_wave_idx = idx_match;
            if get(pop_wave, "value") ~= curr_wave_idx
                set(pop_wave, "value", curr_wave_idx);
            end

            set(fig, "name", sprintf("Analisador de ADC (ATmega2560 | Vref = %.3g V | 8 bits) — %s", ...
                                     VREF, m_current.file_name));

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
            plots = updateAnalyzerDashboard(m_current, unit_mode, pan_start, win_len, VREF, LSB_MV, plots, fft_scale_mode);
            prev_unit_mode = unit_mode;
            prev_fft_scale = fft_scale_mode;
        end

        if ishandle(btn_save) && get(btn_save, "value") == 1
            set(btn_save, "value", 0);
            saveEnrichedMat(m_current.file_path, m_current);
            out_png = exportSingleDashboardPng(m_current, output_dir, VREF, LSB_MV, fft_scale_mode, unit_mode);
            printf("Arquivo .mat atualizado (%s) e painel PNG salvo (%s)!\n", m_current.file_path, out_png);
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
