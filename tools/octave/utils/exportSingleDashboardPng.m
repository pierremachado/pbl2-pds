function out_png = exportSingleDashboardPng(m, output_dir, VREF, LSB_MV, fft_scale_mode, unit_mode)
    % =========================================================================
    % EXPORTSINGLEDASHBOARDPNG - Exporta o painel de 6 gráficos de uma captura para PNG
    % =========================================================================

    if nargin < 3 || isempty(VREF)
        if isfield(m, "vref") && isfinite(m.vref) && m.vref > 0
            VREF = m.vref;
        else
            VREF = 5.0;
        end
    end
    if nargin < 4 || isempty(LSB_MV)
        if isfield(m, "lsb_mv") && isfinite(m.lsb_mv) && m.lsb_mv > 0
            LSB_MV = m.lsb_mv;
        else
            LSB_MV = (VREF / 256.0) * 1e3;
        end
    end
    if nargin < 5 || isempty(fft_scale_mode)
        fft_scale_mode = 1;
    end
    if nargin < 6 || isempty(unit_mode)
        unit_mode = 1;
    end

    fig = figure("visible", "off", "position", [20, 20, 1520, 880], "color", [0.95, 0.96, 0.98]);

    win_show = min(numel(m.x_plot), max(256, round(2.2 * m.period_samples)));
    plots = createAnalyzerPlots(fig, false);
    updateAnalyzerDashboard(m, unit_mode, 0, win_show, VREF, LSB_MV, plots, fft_scale_mode);

    [~, base_n, ~] = fileparts(m.file_name);
    out_png = fullfile(output_dir, ["analysis_", base_n, "_", m.wave_type, ".png"]);
    print(fig, out_png, "-dpng", "-r150");
    close(fig);
    printf("Painel exportado para: %s\n", out_png);
end
