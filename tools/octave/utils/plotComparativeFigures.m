function plotComparativeFigures(results, output_dir, VREF, LSB_MV)
    % =========================================================================
    % PLOTCOMPARATIVEFIGURES - Gera as figuras de análise comparativa (f vs fs)
    % =========================================================================

    n = numel(results);
    fs_vec      = zeros(n, 1);
    f_vec       = zeros(n, 1);
    T_samp_vec  = zeros(n, 1);
    rmse_vec    = zeros(n, 1);
    rmse_in_vec = zeros(n, 1);
    mae_vec     = zeros(n, 1);
    off_vec     = zeros(n, 1);
    gain_vec    = zeros(n, 1);
    dnl_rms_vec = zeros(n, 1);
    inl_rms_vec = zeros(n, 1);
    dr_vec      = zeros(n, 1);
    enob_in_vec = zeros(n, 1);
    miss_vec    = zeros(n, 1);
    vpp_vec     = zeros(n, 1);

    for k = 1:n
        r = results{k};
        fs_vec(k)      = r.actual_sampling_frequency;
        f_vec(k)       = r.freq_hz;
        T_samp_vec(k)  = r.period_samples;
        rmse_vec(k)    = r.rmse_lsb;
        rmse_in_vec(k) = r.rmse_intrinsic_lsb;
        mae_vec(k)     = r.mae_lsb;
        off_vec(k)     = r.offset_error_lsb;
        gain_vec(k)    = r.gain_error_lsb;
        dnl_rms_vec(k) = r.dnl_rms;
        inl_rms_vec(k) = r.inl_rms;
        dr_vec(k)      = r.dr_db;
        enob_in_vec(k) = r.enob_tri_intrin_bits;
        miss_vec(k)    = r.missing_codes;
        vpp_vec(k)     = r.s_vpp;
    end

    % ---------------------------------------------------------------------
    % FIGURA A: Painéis Completos dos Melhores Candidatos e Contraexemplos
    % ---------------------------------------------------------------------
    for idx_r = 1:n
        fn_r = results{idx_r}.file_name;
        if strncmp(fn_r, "adc_f01Hz_fs01024", 17) || ...
           strncmp(fn_r, "adc_f05Hz_fs04000", 17) || ...
           strncmp(fn_r, "adc_f08Hz_fs08192", 17) || ...
           strncmp(fn_r, "adc_f30Hz_fs16384", 17) || ...
           strncmp(fn_r, "adc_f60Hz_fs32768", 17) || ...
           strncmp(fn_r, "contraex_", 9)
            exportSingleDashboardPng(results{idx_r}, output_dir, VREF, LSB_MV);
        end
    end

    % ---------------------------------------------------------------------
    % FIGURA B: Varredura de Frequência do Sinal em fs = 8192 Hz (f = 1 Hz a 12 Hz)
    % ---------------------------------------------------------------------
    mask_8k = (abs(fs_vec - 8196.7) < 20) & (vpp_vec >= 200);
    idx_8k = find(mask_8k);
    if numel(idx_8k) >= 4
        [~, ord] = sort(f_vec(idx_8k));
        idx_8k = idx_8k(ord);

        fig_sw = figure("visible", "off", "position", [50, 50, 1400, 820], "color", [1, 1, 1]);

        % B1: RMSE Bruto, RMSE Intrínseco e MAE vs Frequência do Sinal (f)
        subplot(2, 3, 1);
        hold on;
        plot(f_vec(idx_8k), rmse_vec(idx_8k) * LSB_MV, "-ob", "linewidth", 1.5, "markerfacecolor", "b");
        plot(f_vec(idx_8k), mae_vec(idx_8k) * LSB_MV, "-s", "color", [0.1, 0.65, 0.25], "linewidth", 1.5);
        plot(f_vec(idx_8k), rmse_in_vec(idx_8k) * LSB_MV, "-^r", "linewidth", 1.5, "markerfacecolor", "r");
        plot([min(f_vec(idx_8k)), max(f_vec(idx_8k))], [0.289 * LSB_MV, 0.289 * LSB_MV], "--k", "linewidth", 1.0);
        hold off;
        grid on;
        ylim([0, 18.5]);
        xlabel("Frequência do Sinal f (Hz) [fs = 8192 Hz]");
        ylabel("Erro (mV) [1 LSB = 10 mV]");
        title("Erros Absoluto e RMS vs. Frequência f");
        legend({"RMSE Bruto (mV)", "MAE Absoluto (mV)", "RMSE Intrínseco (mV)", "Ruído Quant. Ideal (2.89 mV)"}, ...
               "location", "northeast", "fontsize", 7.5);

        % B2: Faixa Dinâmica (DR) e SINAD Intrínseco vs Frequência (f)
        subplot(2, 3, 2);
        hold on;
        plot(f_vec(idx_8k), dr_vec(idx_8k), "-ob", "linewidth", 1.5, "markerfacecolor", "b");
        sinad_in_8k = cellfun(@(c) c.sinad_tri_intrin_db, results(idx_8k));
        plot(f_vec(idx_8k), sinad_in_8k, "-sr", "linewidth", 1.5, "markerfacecolor", "r");
        plot([min(f_vec(idx_8k)), max(f_vec(idx_8k))], [48.16, 48.16], "--k", "linewidth", 1.0);
        hold off;
        grid on;
        ylim([38, 52]);
        xlabel("Frequência do Sinal f (Hz) [fs = 8192 Hz]");
        ylabel("dB");
        title("Faixa Dinâmica (DR) e SINAD vs. Frequência f");
        legend({"DR Espectral (dB)", "SINAD Intrínseco (dB)", "Limite Ideal 8 bits (48.2 dB)"}, ...
               "location", "southwest", "fontsize", 8);

        % B3: DNL RMS, INL RMS vs Frequência (f)
        subplot(2, 3, 3);
        hold on;
        plot(f_vec(idx_8k), dnl_rms_vec(idx_8k), "-ob", "linewidth", 1.5, "markerfacecolor", "b");
        plot(f_vec(idx_8k), inl_rms_vec(idx_8k), "-sm", "linewidth", 1.5, "markerfacecolor", "m");
        hold off;
        grid on;
        ylim([0.15, 0.34]);
        xlabel("Frequência do Sinal f (Hz) [fs = 8192 Hz]");
        ylabel("Erro de Linearidade RMS (LSB)");
        title("DNL RMS e INL RMS vs. Frequência f");
        legend({"DNL RMS (LSB)", "INL RMS (LSB)"}, "location", "northeast", "fontsize", 8);

        % B4: Erro de Offset e Ganho na Varredura de 8192 Hz
        subplot(2, 3, 4);
        hold on;
        plot(f_vec(idx_8k), off_vec(idx_8k), "-ob", "linewidth", 1.5, "markerfacecolor", "b");
        plot(f_vec(idx_8k), gain_vec(idx_8k), "-sr", "linewidth", 1.5, "markerfacecolor", "r");
        hold off;
        grid on;
        ylim([-1.5, 6.2]);
        xlabel("Frequência do Sinal f (Hz) [fs = 8192 Hz]");
        ylabel("Erro Estático (LSB)");
        title("Estabilidade de Offset e Ganho vs. Frequência f");
        legend({"Erro de Offset (LSB)", "Erro de Ganho (LSB)"}, "location", "northeast", "fontsize", 8);

        % B5: Número de Amostras por Período (fs/f)
        subplot(2, 3, 5);
        yyaxis_sim_left = T_samp_vec(idx_8k);
        plot(f_vec(idx_8k), yyaxis_sim_left, "-ok", "linewidth", 1.5, "markerfacecolor", [0.2, 0.6, 0.3]);
        hold on;
        plot([min(f_vec(idx_8k)), max(f_vec(idx_8k))], [512, 512], "--r", "linewidth", 1.2);
        hold off;
        grid on;
        xlabel("Frequência do Sinal f (Hz) [fs = 8192 Hz]");
        ylabel("Amostras por Período (Np = fs / f)");
        title("Amostras por Ciclo vs. Mínimo Teórico (512 am/ciclo)");
        legend({"Amostras/Ciclo Medidas", "Limiar 512 am/ciclo (Subida+Descida)"}, "location", "northeast", "fontsize", 8);

        % B6: ENOB Intrínseco e Bruto vs Frequência (f)
        subplot(2, 3, 6);
        enob_tot_8k = cellfun(@(c) c.enob_tri_total_bits, results(idx_8k));
        hold on;
        plot(f_vec(idx_8k), enob_in_vec(idx_8k), "-ob", "linewidth", 1.5, "markerfacecolor", "b");
        plot(f_vec(idx_8k), enob_tot_8k, "-s", "color", [0.85, 0.4, 0.1], "linewidth", 1.5);
        plot([min(f_vec(idx_8k)), max(f_vec(idx_8k))], [7.90, 7.90], "--k", "linewidth", 1.0);
        hold off;
        grid on;
        ylim([5.0, 8.2]);
        xlabel("Frequência do Sinal f (Hz) [fs = 8192 Hz]");
        ylabel("Bits Efetivos (ENOB)");
        title("ENOB vs. Frequência f (Vref = 2.56 V)");
        legend({"ENOB Intrínseco do ADC", "ENOB Bruto (c/ Ganho/Off)", "Ideal 8 bits (7.90 b)"}, ...
               "location", "southwest", "fontsize", 8);

        out_sw = fullfile(output_dir, "comparativo_varredura_freq_fs8192.png");
        print(fig_sw, out_sw, "-dpng", "-r150");
        close(fig_sw);
        printf("Gráfico de varredura de frequência salvo em: %s\n", out_sw);
    end

    % ---------------------------------------------------------------------
    % FIGURA C: Comparação Global entre Diferentes Taxas de Amostragem (fs = 1024 a 32768 Hz)
    % ---------------------------------------------------------------------
    fig_fs = figure("visible", "off", "position", [50, 50, 1400, 820], "color", [1, 1, 1]);

    good_mask = (rmse_vec < 5.0) & (vpp_vec >= 250);
    unique_fs = unique(round(fs_vec(good_mask)));
    n_groups = numel(unique_fs);
    grp_labels = cell(n_groups, 1);
    grp_rmse_raw = zeros(n_groups, 1);
    grp_rmse_in  = zeros(n_groups, 1);
    grp_mae      = zeros(n_groups, 1);
    grp_dr       = zeros(n_groups, 1);
    grp_enob     = zeros(n_groups, 1);
    grp_dnl      = zeros(n_groups, 1);
    grp_inl      = zeros(n_groups, 1);

    for g = 1:n_groups
        m_g = good_mask & (abs(round(fs_vec) - unique_fs(g)) < 5);
        f_mean_g = mean(f_vec(m_g));
        grp_labels{g} = sprintf("fs=%d\n(f~%.0fHz)", unique_fs(g), f_mean_g);
        grp_rmse_raw(g) = mean(rmse_vec(m_g));
        grp_rmse_in(g)  = mean(rmse_in_vec(m_g));
        grp_mae(g)      = mean(mae_vec(m_g));
        grp_dr(g)       = mean(dr_vec(m_g));
        grp_enob(g)     = mean(enob_in_vec(m_g));
        grp_dnl(g)      = mean(dnl_rms_vec(m_g));
        grp_inl(g)      = mean(inl_rms_vec(m_g));
    end

    subplot(2, 2, 1);
    bar_data_err = [grp_rmse_raw, grp_mae, grp_rmse_in];
    bar(1:n_groups, bar_data_err);
    grid on;
    set(gca, "xtick", 1:n_groups, "xticklabel", grp_labels);
    ylabel("Erro (LSB) [1 LSB = 10 mV]");
    title("1. Erro RMS Bruto, MAE e RMSE Intrínseco por Taxa de Amostragem (fs)");
    legend({"RMSE Bruto (LSB)", "MAE Absoluto (LSB)", "RMSE Intrínseco ADC (LSB)"}, "location", "northwest");

    subplot(2, 2, 2);
    hold on;
    plot(1:n_groups, grp_dr, "-ob", "linewidth", 1.8, "markersize", 7, "markerfacecolor", "b");
    plot([1, n_groups], [48.16, 48.16], "--r", "linewidth", 1.2);
    hold off;
    grid on;
    set(gca, "xtick", 1:n_groups, "xticklabel", grp_labels);
    ylim([40, 51]);
    ylabel("Faixa Dinâmica DR (dB)");
    title("2. Faixa Dinâmica (DR) Média vs. Frequência de Amostragem (fs)");
    legend({"DR Medido do ADC (dB)", "DR Ideal 8 bits (48.16 dB)"}, "location", "southwest");

    subplot(2, 2, 3);
    bar_data_lin = [grp_dnl, grp_inl];
    bar(1:n_groups, bar_data_lin);
    grid on;
    set(gca, "xtick", 1:n_groups, "xticklabel", grp_labels);
    ylabel("Erro de Não-Linearidade RMS (LSB)");
    title("3. DNL RMS e INL RMS vs. Frequência de Amostragem (fs)");
    legend({"DNL RMS (LSB)", "INL RMS (LSB)"}, "location", "northwest");

    subplot(2, 2, 4);
    scatter(T_samp_vec(good_mask), rmse_in_vec(good_mask), 45, fs_vec(good_mask), "filled");
    hold on;
    plot([512, 512], [0.5, 1.5], "--r", "linewidth", 1.2);
    hold off;
    grid on;
    xlabel("Amostras por Período (N_p = fs / f)");
    ylabel("RMSE Intrínseco do ADC (LSB)");
    title("4. Dispersão: Amostras por Ciclo (fs/f) vs. RMSE Intrínseco");
    legend({"Capturas Experimentais", "Mínimo 512 am/ciclo"}, "location", "northeast");

    out_fs = fullfile(output_dir, "comparativo_multifrequencia_fs.png");
    print(fig_fs, out_fs, "-dpng", "-r150");
    close(fig_fs);
    printf("Gráfico comparativo multifrequência salvo em: %s\n", out_fs);
end
