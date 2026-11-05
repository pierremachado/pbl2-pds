function results = adc_analyzer(mode_or_file, save_updated_mat)
    % =========================================================================
    % ADC_ANALYZER - Analisador Offline e Painel Digital do ADC (ATmega2560)
    % Inspirado em uart_oscilloscope.m | Configurado para Vref = 2.56 V (8 bits)
    %
    % Recursos:
    %   1. Sinal de 8 bits capturado vs. Ideal Quantizado (256 níveis) vs.
    %      Triangular Contínuo ajustado ao período e fase reais do sinal.
    %   2. FFT comparativa tripla: Sinal Capturado (ADC) vs. Sinal Ideal
    %      Quantizado (256 níveis) vs. Sinal Triangular Contínuo Normal.
    %   3. Erros de quantização e estáticos: Offset, Ganho, DNL, INL,
    %      Missing Codes e Monotonicidade (em LSB, mV e %FSR).
    %   4. Erros Absoluto (MAE, Máx, RMSE) e Relativo (%FSR e % do sinal),
    %      incluindo separação entre erro de ajuste de bancada (ganho/offset)
    %      e erro intrínseco do ADC (quantização + INL + ruído).
    %   5. Faixa Dinâmica (DR), SINAD, SFDR, THD e ENOB (comparando o ADC real
    %      com o limite teórico de 8 bits da onda triangular).
    %
    % Formas de uso no GNU Octave:
    %   adc_analyzer()               -> Abre o Painel Interativo (GUI)
    %   adc_analyzer("batch")        -> Analisa todos os .mat de /data, gera
    %                                   relatório comparativo (f vs fs) e PNGs
    %   adc_analyzer("arquivo.mat")  -> Abre/analisa um arquivo específico
    %   adc_analyzer("batch", true)  -> Lote + atualiza todos os .mat simples
    %                                   com todas as métricas calculadas
    % =========================================================================

    if nargin < 1 || isempty(mode_or_file)
        mode_or_file = "gui";
    end
    if nargin < 2 || isempty(save_updated_mat)
        save_updated_mat = false;
    end

    base_dir = fileparts(mfilename("fullpath"));
    if isempty(base_dir)
        base_dir = pwd();
    end
    data_dir   = fullfile(base_dir, "data");
    output_dir = fullfile(base_dir, "outputs");
    if ~exist(output_dir, "dir")
        mkdir(output_dir);
    end

    % Constantes de Hardware do ADC (ATmega2560 com REFS1:0 = 11 e ADLAR = 1)
    VREF = 2.56;               % Referência interna de 2,56 V
    N_BITS = 8;                % 8 bits mais significativos (ADCH)
    N_LEVELS = 256;            % 2^8 = 256 níveis (códigos 0 a 255)
    LSB_VOLTS = VREF / 256.0;  % 1 LSB = 10 mV (0,01 V)
    LSB_MV = LSB_VOLTS * 1e3;  % 10,0 mV

    mat_files = dir(fullfile(data_dir, "*.mat"));
    if isempty(mat_files)
        error("Nenhum arquivo .mat encontrado em: %s", data_dir);
    end
    [~, sort_idx] = sort({mat_files.name});
    mat_files = mat_files(sort_idx);

    % Modo Lote (Batch)
    if strcmpi(mode_or_file, "batch")
        results = run_batch_analysis(mat_files, data_dir, output_dir, VREF, LSB_MV, save_updated_mat);
        return;
    end

    % Se passou o nome de um arquivo específico, encontra seu índice inicial
    init_file_idx = 1;
    if ~strcmpi(mode_or_file, "gui")
        [~, target_name, target_ext] = fileparts(mode_or_file);
        if isempty(target_ext)
            target_ext = ".mat";
        end
        target_full = [target_name, target_ext];
        for k = 1:numel(mat_files)
            if strcmpi(mat_files(k).name, target_full)
                init_file_idx = k;
                break;
            end
        end
    end

    % Executa o Painel Interativo (Dashboard GUI inspirado no uart_oscilloscope)
    results = launch_interactive_dashboard(mat_files, init_file_idx, data_dir, output_dir, VREF, LSB_MV);
end


% =========================================================================
% NÚCLEO DE PROCESSAMENTO E CÁLCULO DE TODAS AS MÉTRICAS PARA UM ARQUIVO .MAT
% =========================================================================
function m = analyze_single_mat(mat_path, VREF, LSB_MV, align_mode)
    if nargin < 4 || isempty(align_mode)
        align_mode = "opt"; % "opt" (mínimos quadrados) ou "trig" (cruzamento de trigger)
    end

    raw = load(mat_path);
    [~, fname, fext] = fileparts(mat_path);
    m = struct();
    m.file_name = [fname, fext];
    m.file_path = mat_path;
    m.was_full_format = isfield(raw, "rmse_lsb") && isfield(raw, "dnl") && isfield(raw, "dr_db");

    % 1. Extração das variáveis básicas (presentes nos dois formatos de .mat)
    samples = double(raw.samples(:));
    sample_amount = numel(samples);

    if isfield(raw, "sampling_frequency") && ~isempty(raw.sampling_frequency)
        sampling_frequency = double(raw.sampling_frequency);
    elseif isfield(raw, "actual_sampling_frequency")
        sampling_frequency = round(double(raw.actual_sampling_frequency));
    else
        sampling_frequency = 8192;
    end

    if isfield(raw, "actual_sampling_frequency") && ~isempty(raw.actual_sampling_frequency)
        actual_sampling_frequency = double(raw.actual_sampling_frequency);
    else
        timer_ticks = floor(16000000 / (8 * sampling_frequency) + 0.5);
        actual_sampling_frequency = 16000000 / (8 * timer_ticks);
    end

    if isfield(raw, "adc_prescaler") && ~isempty(raw.adc_prescaler)
        adc_prescaler = double(raw.adc_prescaler);
    else
        adc_prescaler = 16;
    end

    % Tempo de conversão teórico do ADC (13 ciclos de clock do ADC no modo single conversion)
    adc_clock_hz = 16000000 / adc_prescaler;
    conversion_time_us = (13.0 / adc_clock_hz) * 1e6;
    max_theoretical_fs = 16000000 / (14.0 * adc_prescaler + 256.0);

    % 2. Análise preliminar de extremos e Trigger Auto com histerese
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
    falling_crossings = [];
    state = 0;
    if samples(1) < (trig_level - hyst)
        state = -1;
    elseif samples(1) > (trig_level + hyst)
        state = 1;
    end

    for k = 2:sample_amount
        if state <= 0 && samples(k - 1) < trig_level && samples(k) >= trig_level
            if any(samples(max(1, k - 60):(k - 1)) < (trig_level - hyst))
                frac = (trig_level - samples(k - 1)) / max(1e-6, (samples(k) - samples(k - 1)));
                rising_crossings(end + 1) = (k - 1) + frac; %#ok<AGROW>
                state = 1;
            end
        elseif state >= 0 && samples(k - 1) > trig_level && samples(k) <= trig_level
            if any(samples(max(1, k - 60):(k - 1)) > (trig_level + hyst))
                frac = (samples(k - 1) - trig_level) / max(1e-6, (samples(k - 1) - samples(k)));
                falling_crossings(end + 1) = (k - 1) + frac; %#ok<AGROW>
                state = -1;
            end
        end
    end

    if ~isempty(rising_crossings)
        trig_idx = max(1, round(rising_crossings(1)));
        trig_str = "AUTO (Travado)";
    else
        trig_idx = 1;
        trig_str = "AUTO (Livre)";
    end

    % 3. Estimativa robusta de período e fase do sinal triangular
    % Combina cruzamentos de subida/descida, inclinação das rampas (para sinais < 1 ciclo)
    % e refinamento por mínimos quadrados na faixa linear.
    periods_est = [];
    if numel(rising_crossings) >= 2
        periods_est = [periods_est, diff(rising_crossings)];
    end
    if numel(falling_crossings) >= 2
        periods_est = [periods_est, diff(falling_crossings)];
    end

    if ~isempty(periods_est)
        T_init = median(periods_est);
    else
        % Estimativa pela inclinação dos segmentos lineares (20 <= ADC <= 235)
        idx_mid = find(samples > 20 & samples < 235);
        breaks = [0; find(diff(idx_mid) > 15); numel(idx_mid)];
        slopes = [];
        for b = 1:(numel(breaks) - 1)
            seg = idx_mid((breaks(b) + 1):breaks(b + 1));
            if numel(seg) > 60
                p_seg = polyfit(seg - 1, samples(seg), 1);
                slopes(end + 1) = abs(p_seg(1)); %#ok<AGROW>
            end
        end
        if ~isempty(slopes)
            T_init = 510.0 / median(slopes);
        elseif ~isempty(rising_crossings) && ~isempty(falling_crossings)
            T_init = 2.0 * abs(rising_crossings(1) - falling_crossings(1));
        else
            T_init = 512.0;
        end
    end

    % Refinamento de período e fase inicial no vetor a partir de trig_idx
    valid_len = sample_amount - trig_idx + 1;
    x_plot = (0:(valid_len - 1))';
    y_plot = samples(trig_idx:end);

    % Modelo triangular contínuo em [0, 255]:
    % Fase u em [0, 1): subida de 0..255 para u em [0, 0.5), descida 255..0 para u em [0.5, 1)
    tri_wave_fn = @(t_vec, T_p, ph_0) 255.0 * (1.0 - abs(1.0 - 2.0 * mod(t_vec / T_p + ph_0, 1.0)));

    % Fase inicial teórica pelo nível de trigger na borda de subida
    ph_trig = (trig_level / 255.0) * 0.5;

    if strcmpi(align_mode, "trig") && (~isempty(rising_crossings) && numel(periods_est) >= 1)
        period_samples = T_init;
        ph_opt = ph_trig;
    else
        % Busca em grade para a fase inicial + refinamento conjunto [período, fase]
        ph_grid = linspace(0, 1, 241);
        ph_grid(end) = [];
        best_mse = inf;
        best_ph = ph_trig;
        for ph_cand = ph_grid
            y_cand = tri_wave_fn(x_plot, T_init, ph_cand);
            mse_cand = mean((y_plot - y_cand) .^ 2);
            if mse_cand < best_mse
                best_mse = mse_cand;
                best_ph = ph_cand;
            end
        end

        % Se há múltiplos ciclos, o período das bordas já é muito preciso (varia <= 2%);
        % se há menos de 1 ciclo, permite ajuste fino de até 5%.
        cost_fn = @(u) mean((y_plot - tri_wave_fn(x_plot, T_init * exp(u(1)), best_ph + u(2))) .^ 2);
        opts = optimset("TolX", 1e-6, "TolFun", 1e-6, "MaxIter", 400, "Display", "off");
        u_opt = fminsearch(cost_fn, [0, 0], opts);
        if abs(u_opt(1)) < 0.08
            period_samples = T_init * exp(u_opt(1));
            ph_opt = mod(best_ph + u_opt(2), 1.0);
        else
            period_samples = T_init;
            ph_opt = best_ph;
        end
    end

    period_sec = period_samples / actual_sampling_frequency;
    freq_hz = actual_sampling_frequency / period_samples;
    signal_frequency = freq_hz;

    % 4. Geração dos sinais ideais:
    %    (a) ideal_plot (ou ideal_cont_plot): triangular contínuo ideal (0.0 a 255.0)
    %    (b) ideal_quant_plot: triangular ideal quantizado em 256 níveis (0 a 255 inteiros)
    ideal_cont_plot  = tri_wave_fn(x_plot, period_samples, ph_opt);
    ideal_quant_plot = min(255, max(0, round(ideal_cont_plot)));
    ideal_plot       = ideal_cont_plot; % Compatibilidade com uart_oscilloscope.m

    % Sinais correspondentes para o buffer completo (1..sample_amount) para a FFT
    n_full = (0:(sample_amount - 1))';
    ph_full_0 = mod(ph_opt - (trig_idx - 1) / period_samples, 1.0);
    ideal_cont_full  = tri_wave_fn(n_full, period_samples, ph_full_0);
    ideal_quant_full = min(255, max(0, round(ideal_cont_full)));

    % Conversão para Volts (Vref = 2.56 V -> 1 LSB = 10 mV)
    y_volts           = y_plot * (VREF / 256.0);
    ideal_cont_volts  = ideal_cont_plot * (VREF / 256.0);
    ideal_quant_volts = ideal_quant_plot * (VREF / 256.0);

    % =====================================================================
    % 5. ERROS ESTÁTICOS (OFFSET E GANHO) + ERROS ABSOLUTO, RELATIVO E QUANTIZAÇÃO
    % =====================================================================
    lin_mask = (ideal_cont_plot >= 10) & (ideal_cont_plot <= 245) & (y_plot > 0) & (y_plot < 255);
    if sum(lin_mask) >= 20
        x_lin = ideal_cont_plot(lin_mask);
        y_lin = y_plot(lin_mask);
        x_mean = mean(x_lin);
        y_mean = mean(y_lin);
        measured_gain = sum((x_lin - x_mean) .* (y_lin - y_mean)) / max(1e-9, sum((x_lin - x_mean) .^ 2));
        intercept_lsb = y_mean - measured_gain * x_mean;
        offset_error_lsb = (measured_gain * 127.5 + intercept_lsb) - 127.5;
        gain_error_lsb   = (measured_gain - 1.0) * 255.0;
    else
        measured_gain    = s_vpp / 255.0;
        intercept_lsb    = mean(y_plot) - measured_gain * 127.5;
        offset_error_lsb = mean(samples) - 127.5;
        gain_error_lsb   = s_vpp - 255.0;
    end
    offset_error_pct = (offset_error_lsb / 255.0) * 100.0;
    gain_error_pct   = (gain_error_lsb / 255.0) * 100.0;
    offset_error_mv  = offset_error_lsb * LSB_MV;
    gain_error_mv    = gain_error_lsb * LSB_MV;

    % Vetores de erro ponto-a-ponto
    % (a) Contra o sinal triangular contínuo ideal
    err_vs_cont_lsb  = y_plot - ideal_cont_plot;
    abs_err_cont_lsb = abs(err_vs_cont_lsb);

    % (b) Contra o sinal ideal quantizado de 256 níveis (diferença de códigos inteiros)
    err_vs_quant_lsb  = y_plot - ideal_quant_plot;
    abs_err_quant_lsb = abs(err_vs_quant_lsb);

    % (c) Erro intrínseco de quantização + não-linearidade (após compensar ganho e offset lineares)
    ideal_bestfit_plot = min(255, max(0, measured_gain * ideal_cont_plot + intercept_lsb));
    err_intrinsic_lsb  = y_plot - ideal_bestfit_plot;

    % (d) Erro teórico puro da quantização de 8 bits (ideal_quant - ideal_cont)
    err_ideal_quant_lsb = ideal_quant_plot - ideal_cont_plot;

    % Métricas escalares de Erro Absoluto, RMSE e Erro Relativo
    rmse_lsb           = sqrt(mean(err_vs_cont_lsb .^ 2));
    rmse_mv            = rmse_lsb * LSB_MV;
    rmse_pct_fsr       = (rmse_lsb / 255.0) * 100.0;

    rmse_vs_quant_lsb  = sqrt(mean(err_vs_quant_lsb .^ 2));
    rmse_intrinsic_lsb = sqrt(mean(err_intrinsic_lsb .^ 2));
    rmse_intrinsic_mv  = rmse_intrinsic_lsb * LSB_MV;
    rmse_intrinsic_pct = (rmse_intrinsic_lsb / 255.0) * 100.0;

    mae_lsb            = mean(abs_err_cont_lsb);
    mae_mv             = mae_lsb * LSB_MV;
    mae_pct_fsr        = (mae_lsb / 255.0) * 100.0;

    max_abs_err_lsb    = max(abs_err_cont_lsb);
    max_abs_err_mv     = max_abs_err_lsb * LSB_MV;
    max_abs_err_pct_fsr = (max_abs_err_lsb / 255.0) * 100.0;

    % Erro relativo ponto-a-ponto (% do valor instantâneo do sinal ideal, para ideal >= 12.75 LSB = 5% FSR)
    rel_valid_mask = (ideal_cont_plot >= 12.75);
    rel_err_instant_pct = nan(valid_len, 1);
    rel_err_instant_pct(rel_valid_mask) = (abs_err_cont_lsb(rel_valid_mask) ./ ideal_cont_plot(rel_valid_mask)) * 100.0;
    mape_signal_pct   = mean(rel_err_instant_pct(rel_valid_mask));
    median_rel_err_pct = median(rel_err_instant_pct(rel_valid_mask));

    % Erro relativo ao Fundo de Escala (%FSR) ponto-a-ponto
    rel_err_fsr_pct = (err_vs_cont_lsb / 255.0) * 100.0;

    % =====================================================================
    % 6. ANÁLISE ESPECTRAL TRIPLA (FFT: ADC vs. IDEAL QUANTIZADO vs. TRIANGULAR NORMAL)
    % =====================================================================
    N_fft = sample_amount;
    n_vec = (0:(N_fft - 1))';
    win_hann = 0.5 * (1.0 - cos(2.0 * pi * n_vec / (N_fft - 1)));
    coherent_gain = mean(win_hann);
    win_power_gain = mean(win_hann .^ 2); % 0.375 para janela de Hann
    half_N = floor(N_fft / 2) + 1;
    freq_axis = (0:(half_N - 1))' * (actual_sampling_frequency / N_fft);

    % 6.1 FFT do Sinal Capturado pelo ADC
    s_ac = samples - mean(samples);
    Y_fft = fft(s_ac .* win_hann);
    Y_half = Y_fft(1:half_N);
    mag_lin = abs(Y_half) / (N_fft * coherent_gain / 2.0);
    mag_lin(1) = abs(Y_half(1)) / (N_fft * coherent_gain);
    mag_dbfs = 20.0 * log10(max(mag_lin / 127.5, 1e-6));
    phase_deg = rad2deg(angle(Y_half));

    % 6.2 FFT do Sinal Ideal Quantizado (256 níveis)
    sq_ac = ideal_quant_full - mean(ideal_quant_full);
    Yq_fft = fft(sq_ac .* win_hann);
    Yq_half = Yq_fft(1:half_N);
    mag_lin_quant = abs(Yq_half) / (N_fft * coherent_gain / 2.0);
    mag_lin_quant(1) = abs(Yq_half(1)) / (N_fft * coherent_gain);
    mag_dbfs_quant = 20.0 * log10(max(mag_lin_quant / 127.5, 1e-6));
    phase_deg_quant = rad2deg(angle(Yq_half));

    % 6.3 FFT do Sinal Triangular Contínuo Normal (sem quantização)
    st_ac = ideal_cont_full - mean(ideal_cont_full);
    Yt_fft = fft(st_ac .* win_hann);
    Yt_half = Yt_fft(1:half_N);
    mag_lin_tri = abs(Yt_half) / (N_fft * coherent_gain / 2.0);
    mag_lin_tri(1) = abs(Yt_half(1)) / (N_fft * coherent_gain);
    mag_dbfs_tri = 20.0 * log10(max(mag_lin_tri / 127.5, 1e-6));
    phase_deg_tri = rad2deg(angle(Yt_half));

    % Identificação do bin fundamental na FFT
    [~, fund_bin] = max(mag_lin(2:end));
    fund_bin = fund_bin + 1;
    fund_freq_fft = freq_axis(fund_bin);
    fund_mag_dbfs = mag_dbfs(fund_bin);

    sig_bins = find(mag_dbfs > -55);
    if isempty(sig_bins)
        sig_bins = fund_bin;
    end

    % --- Métricas originais compatíveis com uart_oscilloscope.m ---
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
    sinad_db = 10.0 * log10(max(P_signal, 1e-12) / max(P_nad, 1e-12));
    thd_db   = 10.0 * log10(max(P_harm, 1e-12) / max(P_signal, 1e-12));
    enob_bits = max(0, (sinad_db - 1.76) / 6.02);
    P_noise_only = max(1e-12, P_nad - P_harm);
    dr_db_legacy = 10.0 * log10((127.5 ^ 2) / P_noise_only);

    % --- Métricas Espectrais e de Faixa Dinâmica Específicas para Onda Triangular ---
    % Na onda triangular, as harmônicas ímpares (3f0, 5f0, 7f0...) pertencem ao sinal!
    % Calculamos a potência por bin com normalização correta de Parseval para janela de Hann:
    P_parseval_adc   = (abs(Y_half) .^ 2) / (N_fft^2 * win_power_gain);
    P_parseval_adc(2:end-1) = 2.0 * P_parseval_adc(2:end-1);

    P_parseval_quant = (abs(Yq_half) .^ 2) / (N_fft^2 * win_power_gain);
    P_parseval_quant(2:end-1) = 2.0 * P_parseval_quant(2:end-1);

    % Mascara todas as harmônicas da frequência real medida (freq_hz) até Nyquist
    pure_noise_mask = true(half_N, 1);
    pure_noise_mask(1:3) = false;
    max_harm_order = min(60, floor((actual_sampling_frequency / 2.0) / max(0.5, freq_hz)));
    P_odd_harm_adc = 0;
    P_even_harm_adc = 0;
    for h_ord = 1:max_harm_order
        exact_bin = 1.0 + h_ord * freq_hz * N_fft / actual_sampling_frequency;
        b_lo = max(2, floor(exact_bin - 3));
        b_hi = min(half_N, ceil(exact_bin + 3));
        pure_noise_mask(b_lo:b_hi) = false;
        if mod(h_ord, 2) == 1
            P_odd_harm_adc = P_odd_harm_adc + sum(P_parseval_adc(b_lo:b_hi));
        else
            P_even_harm_adc = P_even_harm_adc + sum(P_parseval_adc(b_lo:b_hi));
        end
    end

    % Piso de ruído espectral extrapolado para toda a banda de Nyquist
    if any(pure_noise_mask)
        P_spec_noise_adc   = sum(P_parseval_adc(pure_noise_mask)) * (half_N / sum(pure_noise_mask));
        P_spec_noise_quant = sum(P_parseval_quant(pure_noise_mask)) * (half_N / sum(pure_noise_mask));
    else
        P_spec_noise_adc   = mean(err_intrinsic_lsb .^ 2);
        P_spec_noise_quant = mean(err_ideal_quant_lsb .^ 2);
    end

    noise_floor_rms_lsb = sqrt(P_spec_noise_adc);
    noise_floor_rms_mv  = noise_floor_rms_lsb * LSB_MV;

    % Potência de fundo de escala:
    % - Referência Senoidal Full-Scale: (127.5)^2 / 2 = 8128.125 LSB^2
    % - Referência Triangular Full-Scale: (127.5)^2 / 3 = 5418.75 LSB^2
    P_fs_sin = (127.5 ^ 2) / 2.0;
    P_fs_tri = (127.5 ^ 2) / 3.0;

    dr_db       = 10.0 * log10(P_fs_sin / max(1e-12, P_spec_noise_adc));
    dr_tri_db   = 10.0 * log10(P_fs_tri / max(1e-12, P_spec_noise_adc));
    dr_quant_db = 10.0 * log10(P_fs_sin / max(1e-12, P_spec_noise_quant));

    % SINAD e ENOB reais da onda triangular (comparando sinal vs erro de reconstrução no tempo)
    P_sig_tri_actual     = var(ideal_cont_plot);
    sinad_tri_total_db   = 10.0 * log10(P_sig_tri_actual / max(1e-12, mean(err_vs_cont_lsb .^ 2)));
    sinad_tri_intrin_db  = 10.0 * log10(P_sig_tri_actual / max(1e-12, mean(err_intrinsic_lsb .^ 2)));
    sqnr_ideal_quant_db  = 10.0 * log10(P_sig_tri_actual / max(1e-12, mean(err_ideal_quant_lsb .^ 2)));

    % Para onda triangular (fator de crista sqrt(3) vs sqrt(2) da senoide -> +1.25 dB de correção):
    enob_tri_total_bits  = max(0, (sinad_tri_total_db - 1.76 + 1.25) / 6.02);
    enob_tri_intrin_bits = max(0, (sinad_tri_intrin_db - 1.76 + 1.25) / 6.02);
    enob_ideal_quant     = max(0, (sqnr_ideal_quant_db - 1.76 + 1.25) / 6.02);

    % SFDR livre das harmônicas ímpares próprias da triangular
    non_tri_mask = true(half_N, 1);
    non_tri_mask(1:3) = false;
    for h_ord = 1:2:max_harm_order
        exact_bin = 1.0 + h_ord * freq_hz * N_fft / actual_sampling_frequency;
        b_lo = max(2, floor(exact_bin - 3));
        b_hi = min(half_N, ceil(exact_bin + 3));
        non_tri_mask(b_lo:b_hi) = false;
    end
    if any(non_tri_mask)
        sfdr_tri_dbc = fund_mag_dbfs - max(mag_dbfs(non_tri_mask));
    else
        sfdr_tri_dbc = sfdr_dbc;
    end

    % =====================================================================
    % 7. CÁLCULO DE DNL, INL E MONOTONICIDADE (SOBRE CICLOS INTEIROS OU RAMPA)
    % =====================================================================
    codes_axis = (0:255)';
    num_full_cycles = floor(sample_amount / period_samples);
    if num_full_cycles >= 1
        n_int_samples = min(sample_amount, max(256, round(num_full_cycles * period_samples)));
        samples_for_hist = samples(1:n_int_samples);
        k_min = max(0, round(s_min));
        k_max = min(255, round(s_max));
    else
        % Se há menos de 1 ciclo completo na janela, extrai a maior rampa monotônica
        % entre o mínimo e o máximo para evitar contagem dupla de códigos após o vértice!
        [~, idx_smin] = min(samples);
        [~, idx_smax] = max(samples);
        i_start_ramp = min(idx_smin, idx_smax);
        i_end_ramp   = max(idx_smin, idx_smax);
        samples_for_hist = samples(i_start_ramp:i_end_ramp);
        n_int_samples = numel(samples_for_hist);
        k_min = max(0, round(min(samples_for_hist)));
        k_max = min(255, round(max(samples_for_hist)));
    end

    code_counts = histc(round(samples_for_hist), 0:255);
    code_counts = code_counts(:);
    inner_idx = (k_min + 2):(k_max); % Índices 1-based para códigos (k_min+1)..(k_max-1)

    dnl = zeros(256, 1);
    inl = zeros(256, 1);
    if numel(inner_idx) >= 4
        expected_hits = mean(code_counts(inner_idx));
        if expected_hits > 0
            dnl(inner_idx) = (code_counts(inner_idx) / expected_hits) - 1.0;
            dnl_zero_mean = dnl(inner_idx) - mean(dnl(inner_idx));
            inl(inner_idx) = cumsum(dnl_zero_mean);
        end
        missing_codes = sum(code_counts(inner_idx) == 0);
    else
        expected_hits = 0;
        missing_codes = 0;
    end

    % Curva de transferência empírica (média do ADC por nível ideal quantizado 0..255)
    ideal_levels_int = ideal_quant_plot;
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
    [dnl_max, ~] = max(dnl);
    [dnl_min, ~] = min(dnl);
    [inl_max, ~] = max(inl);
    [inl_min, ~] = min(inl);
    dnl_rms = sqrt(mean(dnl(inner_idx) .^ 2));
    inl_rms = sqrt(mean(inl(inner_idx) .^ 2));

    % =====================================================================
    % 8. EMPACOTAMENTO DE TODAS AS VARIÁVEIS NA ESTRUTURA DE RETORNO
    % =====================================================================
    m.samples = samples;
    m.x_plot = x_plot;
    m.y_plot = y_plot;
    m.ideal_plot = ideal_plot;
    m.ideal_cont_plot = ideal_cont_plot;
    m.ideal_quant_plot = ideal_quant_plot;
    m.ideal_bestfit_plot = ideal_bestfit_plot;
    m.y_volts = y_volts;
    m.ideal_cont_volts = ideal_cont_volts;
    m.ideal_quant_volts = ideal_quant_volts;

    m.signal_frequency = signal_frequency;
    m.sampling_frequency = sampling_frequency;
    m.actual_sampling_frequency = actual_sampling_frequency;
    m.adc_prescaler = adc_prescaler;
    m.sample_amount = sample_amount;
    m.adc_clock_hz = adc_clock_hz;
    m.conversion_time_us = conversion_time_us;
    m.max_theoretical_fs = max_theoretical_fs;

    m.freq_hz = freq_hz;
    m.fund_freq_fft = fund_freq_fft;
    m.fund_mag_dbfs = fund_mag_dbfs;
    m.period_sec = period_sec;
    m.period_samples = period_samples;
    m.num_full_cycles = num_full_cycles;
    m.n_int_samples = n_int_samples;
    m.trig_level = trig_level;
    m.trig_idx = trig_idx;
    m.trig_str = trig_str;

    m.s_min = s_min;
    m.s_max = s_max;
    m.s_vpp = s_vpp;

    m.offset_error_lsb = offset_error_lsb;
    m.offset_error_mv  = offset_error_mv;
    m.offset_error_pct = offset_error_pct;
    m.gain_error_lsb   = gain_error_lsb;
    m.gain_error_mv    = gain_error_mv;
    m.gain_error_pct   = gain_error_pct;
    m.measured_gain    = measured_gain;
    m.intercept_lsb    = intercept_lsb;

    m.err_vs_cont_lsb     = err_vs_cont_lsb;
    m.err_vs_quant_lsb    = err_vs_quant_lsb;
    m.err_intrinsic_lsb   = err_intrinsic_lsb;
    m.abs_err_cont_lsb    = abs_err_cont_lsb;
    m.rel_err_fsr_pct     = rel_err_fsr_pct;
    m.rel_err_instant_pct = rel_err_instant_pct;

    m.rmse_lsb            = rmse_lsb;
    m.rmse_mv             = rmse_mv;
    m.rmse_pct_fsr        = rmse_pct_fsr;
    m.rmse_vs_quant_lsb   = rmse_vs_quant_lsb;
    m.rmse_intrinsic_lsb  = rmse_intrinsic_lsb;
    m.rmse_intrinsic_mv   = rmse_intrinsic_mv;
    m.rmse_intrinsic_pct  = rmse_intrinsic_pct;
    m.mae_lsb             = mae_lsb;
    m.mae_mv              = mae_mv;
    m.mae_pct_fsr         = mae_pct_fsr;
    m.max_abs_err_lsb     = max_abs_err_lsb;
    m.max_abs_err_mv      = max_abs_err_mv;
    m.max_abs_err_pct_fsr = max_abs_err_pct_fsr;
    m.mape_signal_pct     = mape_signal_pct;
    m.median_rel_err_pct  = median_rel_err_pct;

    m.freq_axis       = freq_axis;
    m.mag_dbfs        = mag_dbfs;
    m.mag_dbfs_quant  = mag_dbfs_quant;
    m.mag_dbfs_tri    = mag_dbfs_tri;
    m.phase_deg       = phase_deg;
    m.phase_deg_quant = phase_deg_quant;
    m.phase_deg_tri   = phase_deg_tri;
    m.sig_bins        = sig_bins;

    m.dr_db                = dr_db;
    m.dr_tri_db            = dr_tri_db;
    m.dr_quant_db          = dr_quant_db;
    m.dr_db_legacy         = dr_db_legacy;
    m.sfdr_dbc             = sfdr_dbc;
    m.sfdr_tri_dbc         = sfdr_tri_dbc;
    m.sinad_db             = sinad_db;
    m.thd_db               = thd_db;
    m.enob_bits            = enob_bits;
    m.sinad_tri_total_db   = sinad_tri_total_db;
    m.sinad_tri_intrin_db  = sinad_tri_intrin_db;
    m.sqnr_ideal_quant_db  = sqnr_ideal_quant_db;
    m.enob_tri_total_bits  = enob_tri_total_bits;
    m.enob_tri_intrin_bits = enob_tri_intrin_bits;
    m.enob_ideal_quant     = enob_ideal_quant;
    m.noise_floor_rms_lsb  = noise_floor_rms_lsb;
    m.noise_floor_rms_mv   = noise_floor_rms_mv;

    m.codes_axis         = codes_axis;
    m.code_counts        = code_counts;
    m.expected_hits      = expected_hits;
    m.mean_adc_per_level = mean_adc_per_level;
    m.dnl                = dnl;
    m.inl                = inl;
    m.dnl_min            = dnl_min;
    m.dnl_max            = dnl_max;
    m.dnl_rms            = dnl_rms;
    m.inl_min            = inl_min;
    m.inl_max            = inl_max;
    m.inl_rms            = inl_rms;
    m.missing_codes      = missing_codes;
    m.is_monotonic       = is_monotonic;
    m.nonmono_codes      = nonmono_codes;
end


% =========================================================================
% SALVAMENTO DE TODAS AS MÉTRICAS NO ARQUIVO .MAT (FORMATO COMPLETO + EXTRAS)
% =========================================================================
function save_enriched_mat(mat_path, m)
    samples = m.samples;
    x_plot = m.x_plot;
    y_plot = m.y_plot;
    ideal_plot = m.ideal_plot;
    ideal_quant_plot = m.ideal_quant_plot;
    signal_frequency = m.signal_frequency;
    sampling_frequency = m.sampling_frequency;
    actual_sampling_frequency = m.actual_sampling_frequency;
    adc_prescaler = m.adc_prescaler;
    sample_amount = m.sample_amount;
    freq_hz = m.freq_hz;
    fund_freq_fft = m.fund_freq_fft;
    period_sec = m.period_sec;
    period_samples = m.period_samples;
    trig_level = m.trig_level;
    trig_idx = m.trig_idx;
    s_min = m.s_min;
    s_max = m.s_max;
    s_vpp = m.s_vpp;
    rmse_lsb = m.rmse_lsb;
    rmse_intrinsic_lsb = m.rmse_intrinsic_lsb;
    mae_lsb = m.mae_lsb;
    max_abs_err_lsb = m.max_abs_err_lsb;
    mape_signal_pct = m.mape_signal_pct;
    offset_error_lsb = m.offset_error_lsb;
    offset_error_pct = m.offset_error_pct;
    gain_error_lsb = m.gain_error_lsb;
    gain_error_pct = m.gain_error_pct;
    measured_gain = m.measured_gain;
    freq_axis = m.freq_axis;
    mag_dbfs = m.mag_dbfs;
    mag_dbfs_quant = m.mag_dbfs_quant;
    mag_dbfs_tri = m.mag_dbfs_tri;
    phase_deg = m.phase_deg;
    dr_db = m.dr_db;
    dr_tri_db = m.dr_tri_db;
    sfdr_dbc = m.sfdr_dbc;
    sfdr_tri_dbc = m.sfdr_tri_dbc;
    sinad_db = m.sinad_db;
    sinad_tri_total_db = m.sinad_tri_total_db;
    sinad_tri_intrin_db = m.sinad_tri_intrin_db;
    thd_db = m.thd_db;
    enob_bits = m.enob_bits;
    enob_tri_intrin_bits = m.enob_tri_intrin_bits;
    codes_axis = m.codes_axis;
    code_counts = m.code_counts;
    dnl = m.dnl;
    inl = m.inl;
    dnl_min = m.dnl_min;
    dnl_max = m.dnl_max;
    inl_min = m.inl_min;
    inl_max = m.inl_max;
    missing_codes = m.missing_codes;
    is_monotonic = m.is_monotonic;
    nonmono_codes = m.nonmono_codes;

    save("-v7", mat_path, ...
         "samples", "x_plot", "y_plot", "ideal_plot", "ideal_quant_plot", ...
         "signal_frequency", "sampling_frequency", "actual_sampling_frequency", ...
         "adc_prescaler", "sample_amount", ...
         "freq_hz", "fund_freq_fft", "period_sec", "period_samples", ...
         "trig_level", "trig_idx", ...
         "s_min", "s_max", "s_vpp", "rmse_lsb", "rmse_intrinsic_lsb", ...
         "mae_lsb", "max_abs_err_lsb", "mape_signal_pct", ...
         "offset_error_lsb", "offset_error_pct", ...
         "gain_error_lsb", "gain_error_pct", "measured_gain", ...
         "freq_axis", "mag_dbfs", "mag_dbfs_quant", "mag_dbfs_tri", "phase_deg", ...
         "dr_db", "dr_tri_db", "sfdr_dbc", "sfdr_tri_dbc", ...
         "sinad_db", "sinad_tri_total_db", "sinad_tri_intrin_db", ...
         "thd_db", "enob_bits", "enob_tri_intrin_bits", ...
         "codes_axis", "code_counts", "dnl", "inl", ...
         "dnl_min", "dnl_max", "inl_min", "inl_max", ...
         "missing_codes", "is_monotonic", "nonmono_codes");
end


% =========================================================================
% PAINEL DIGITAL INTERATIVO (INSPIRADO EM UART_OSCILLOSCOPE.M)
% =========================================================================
function m_current = launch_interactive_dashboard(mat_files, init_idx, data_dir, output_dir, VREF, LSB_MV)
    file_names = {mat_files.name};

    fig = figure("name", "Analisador de Dados do ADC (ATmega2560 | Vref = 2.56 V | 8 bits = 256 níveis)", ...
                 "numbertitle", "off", ...
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

    % 8. CONTROLES INFERIORES (Seletor de Arquivo, Zoom, Pan, Unidade, Salvar e Lote)
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
              "position", [0.04, 0.010, 0.05, 0.028], ...
              "backgroundcolor", [0.95, 0.96, 0.98], "string", "Zoom:");

    sld_win = uicontrol(fig, "style", "slider", "units", "normalized", ...
                        "position", [0.09, 0.010, 0.10, 0.028], ...
                        "min", 64, "max", 4096, "value", 1024);

    uicontrol(fig, "style", "text", "units", "normalized", ...
              "position", [0.195, 0.010, 0.04, 0.028], ...
              "backgroundcolor", [0.95, 0.96, 0.98], "string", "Pan:");

    sld_pan = uicontrol(fig, "style", "slider", "units", "normalized", ...
                        "position", [0.235, 0.010, 0.085, 0.028], ...
                        "min", 0, "max", 4032, "value", 0);

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

    % Estado interno para atualização rápida
    curr_idx = -1;
    m_current = struct();

    set(btn_prev, "callback", @(~, ~) step_file(pop_file, -1, numel(mat_files)));
    set(btn_next, "callback", @(~, ~) step_file(pop_file, +1, numel(mat_files)));

    while ishandle(fig)
        sel_idx = get(pop_file, "value");
        if sel_idx ~= curr_idx
            curr_idx = sel_idx;
            fpath = fullfile(data_dir, mat_files(curr_idx).name);
            m_current = analyze_single_mat(fpath, VREF, LSB_MV, "opt");
            % Ajusta janela default para ~2.5 períodos do sinal (facilita ver os degraus de quantização)
            default_win = min(numel(m_current.x_plot), max(128, round(2.5 * m_current.period_samples)));
            set(sld_win, "max", numel(m_current.x_plot), "value", default_win);
            set(sld_pan, "max", max(1, numel(m_current.x_plot) - 64), "value", 0);
        end

        unit_mode = get(pop_unit, "value");
        win_len = max(64, min(round(get(sld_win, "value")), numel(m_current.x_plot)));
        max_pan = max(0, numel(m_current.x_plot) - win_len);
        pan_start = min(round(get(sld_pan, "value")), max_pan);

        update_dashboard_plots(m_current, unit_mode, pan_start, win_len, VREF, LSB_MV, ...
                               ax_wave, h_ideal_cont, h_ideal_quant, h_wave, h_trig, ...
                               ax_fft, h_fft_tri, h_fft_quant, h_fft_adc, h_fft_peak, ...
                               ax_trans, h_trans_ideal, h_trans_fit, h_trans_real, ...
                               ax_err, h_err_raw, h_err_intr, h_err_lim_p, h_err_lim_n, ...
                               ax_dnl, h_dnl, ax_inl, h_inl, h_nonmono, ...
                               txt_col1, txt_col2, txt_col3);

        if ishandle(btn_save) && get(btn_save, "value") == 1
            set(btn_save, "value", 0);
            save_enriched_mat(m_current.file_path, m_current);
            out_png = export_single_dashboard_png(m_current, output_dir, VREF, LSB_MV);
            printf("Arquivo .mat atualizado (%s) e painel PNG salvo (%s)!\n", m_current.file_path, out_png);
        end

        if ishandle(btn_batch) && get(btn_batch, "value") == 1
            set(btn_batch, "value", 0);
            run_batch_analysis(mat_files, data_dir, output_dir, VREF, LSB_MV, false);
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


% =========================================================================
% ATUALIZAÇÃO DOS GRÁFICOS E TEXTOS DO PAINEL (USADO NO GUI E NO EXPORT PNG)
% =========================================================================
function update_dashboard_plots(m, unit_mode, pan_start, win_len, VREF, LSB_MV, ...
                                ax_wave, h_ideal_cont, h_ideal_quant, h_wave, h_trig, ...
                                ax_fft, h_fft_tri, h_fft_quant, h_fft_adc, h_fft_peak, ...
                                ax_trans, h_trans_ideal, h_trans_fit, h_trans_real, ...
                                ax_err, h_err_raw, h_err_intr, h_err_lim_p, h_err_lim_n, ...
                                ax_dnl, h_dnl, ax_inl, h_inl, h_nonmono, ...
                                txt_col1, txt_col2, txt_col3)

    % 1. Seleção de escala (LSB vs Volts vs %FSR)
    if unit_mode == 2
        scale_sig = VREF / 256.0;
        sig_unit_lbl = "Tensão (V)";
        sig_ylim = [-0.10, 2.68];
        err_scale = LSB_MV;
        err_unit_lbl = "Erro (mV)";
        err_lim_val = 0.5 * LSB_MV; % +-5 mV
    elseif unit_mode == 3
        scale_sig = 100.0 / 255.0;
        sig_unit_lbl = "Escala (%FSR)";
        sig_ylim = [-4, 105];
        err_scale = 100.0 / 255.0;
        err_unit_lbl = "Erro Relativo (%FSR)";
        err_lim_val = (0.5 / 255.0) * 100.0; % +-0.196% (total 0.39%)
    else
        scale_sig = 1.0;
        sig_unit_lbl = "Código ADC (0 a 255)";
        sig_ylim = [-10, 265];
        err_scale = 1.0;
        err_unit_lbl = "Erro (LSB)";
        err_lim_val = 0.5;
    end

    set(h_ideal_cont,  "xdata", m.x_plot, "ydata", m.ideal_cont_plot * scale_sig);
    set(h_ideal_quant, "xdata", m.x_plot, "ydata", m.ideal_quant_plot * scale_sig);
    set(h_wave,        "xdata", m.x_plot, "ydata", m.y_plot * scale_sig);
    set(h_trig,        "xdata", [0, max(1, numel(m.x_plot) - 1)], ...
                       "ydata", [m.trig_level, m.trig_level] * scale_sig);
    xlim(ax_wave, [pan_start, pan_start + win_len]);
    ylim(ax_wave, sig_ylim);
    ylabel(ax_wave, sig_unit_lbl);
    title(ax_wave, sprintf("1. Sinal 8 bits vs. Ideal Quantizado 256 Níveis [%s | f=%.2f Hz | fs=%.1f Hz]", ...
                           m.file_name, m.freq_hz, m.actual_sampling_frequency), "interpreter", "none");

    % 2. FFT Tripla (ADC vs Quantizado Ideal vs Triangular Contínuo)
    f_max_view = min(m.actual_sampling_frequency / 2.0, max(150.0, 18.0 * m.freq_hz));
    set(h_fft_tri,   "xdata", m.freq_axis, "ydata", m.mag_dbfs_tri);
    set(h_fft_quant, "xdata", m.freq_axis, "ydata", m.mag_dbfs_quant);
    set(h_fft_adc,   "xdata", m.freq_axis, "ydata", m.mag_dbfs);
    set(h_fft_peak,  "xdata", m.fund_freq_fft, "ydata", m.fund_mag_dbfs);
    xlim(ax_fft, [0, f_max_view]);

    % 3. Curva de Transferência Real vs Ideal
    x_codes = (0:255)';
    y_fit_line = m.measured_gain * x_codes + m.intercept_lsb;
    set(h_trans_ideal, "xdata", x_codes, "ydata", x_codes);
    set(h_trans_fit,   "xdata", x_codes, "ydata", y_fit_line);
    set(h_trans_real,  "xdata", x_codes, "ydata", m.mean_adc_per_level);

    % 4. Gráfico de Erros no Tempo (Bruto e Intrínseco)
    set(h_err_raw,   "xdata", m.x_plot, "ydata", m.err_vs_cont_lsb * err_scale);
    set(h_err_intr,  "xdata", m.x_plot, "ydata", m.err_intrinsic_lsb * err_scale);
    set(h_err_lim_p, "xdata", [0, max(1, numel(m.x_plot) - 1)], "ydata", [err_lim_val, err_lim_val]);
    set(h_err_lim_n, "xdata", [0, max(1, numel(m.x_plot) - 1)], "ydata", [-err_lim_val, -err_lim_val]);
    xlim(ax_err, [pan_start, pan_start + win_len]);
    max_e_plot = max(1.5 * err_lim_val, min(25 * err_scale, 1.15 * max(abs(m.err_vs_cont_lsb)) * err_scale));
    ylim(ax_err, [-max_e_plot, max_e_plot]);
    ylabel(ax_err, err_unit_lbl);

    % 5. DNL
    set(h_dnl, "ydata", m.dnl);
    ylim(ax_dnl, [min(-1.2, m.dnl_min - 0.25), max(1.2, m.dnl_max + 0.25)]);
    title(ax_dnl, sprintf("5. DNL (%d ciclo(s) = %d am | RMS=%.2f LSB)", ...
                          max(1, m.num_full_cycles), m.n_int_samples, m.dnl_rms));

    % 6. INL e Monotonicidade
    set(h_inl, "ydata", m.inl);
    if ~isempty(m.nonmono_codes)
        set(h_nonmono, "xdata", m.nonmono_codes, "ydata", m.inl(m.nonmono_codes + 1));
    else
        set(h_nonmono, "xdata", NaN, "ydata", NaN);
    end
    ylim(ax_inl, [min(-1.5, m.inl_min - 0.4), max(1.5, m.inl_max + 0.4)]);

    % 7. Textos de Telemetria (3 Colunas)
    if m.is_monotonic
        mono_str = "SIM (Monotônico)";
    else
        mono_str = sprintf("NÃO (%d inv | %d miss)", numel(m.nonmono_codes), m.missing_codes);
    end

    col1_str = sprintf([ ...
        "ARQUIVO : %s (%s)\n", ...
        "FREQ SINAL: f = %.2f Hz (FFT: %.2f Hz)\n", ...
        "AMOSTRAGEM: fs = %.1f Hz (Pre=%d | Tconv=%.1fus)\n", ...
        "PERÍODO   : T = %.2f ms (%.1f am/ciclo)\n", ...
        "EXCURSÃO  : %.0f..%.0f LSB (%.2f..%.2f V)\n", ...
        "ERRO OFFS.: %+.2f LSB (%+.1f mV | %+.2f%%FSR)\n", ...
        "ERRO GANHO: %+.2f LSB (%+.1f mV | G=%.4f)"], ...
        m.file_name, ifelse(m.was_full_format, "COMPLETO", "SIMPLES"), ...
        m.freq_hz, m.fund_freq_fft, ...
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
        "DNL (Min/Max) : %+.2f / %+.2f LSB (RMS=%.2f)\n", ...
        "INL (Min/Max) : %+.2f / %+.2f LSB | %s"], ...
        m.rmse_lsb, m.rmse_mv, m.rmse_pct_fsr, ...
        m.rmse_intrinsic_lsb, m.rmse_intrinsic_mv, m.rmse_intrinsic_pct, ...
        m.mae_lsb, m.mae_mv, ...
        m.max_abs_err_lsb, m.max_abs_err_mv, ...
        m.mae_pct_fsr, m.mape_signal_pct, ...
        m.dnl_min, m.dnl_max, m.dnl_rms, ...
        m.inl_min, m.inl_max, mono_str);

    col3_str = sprintf([ ...
        "FAIXA DINÂMICA: DR = %.1f dB (Tri: %.1f dB)\n", ...
        "DR IDEAL 8b   : %.1f dB (SQNR Tri: %.1f dB)\n", ...
        "SINAD TRIANG. : %.1f dB (Intrín.: %.1f dB)\n", ...
        "ENOB TRIANG.  : %.2f bits (Intrín.: %.2f b)\n", ...
        "SFDR (s/ Tri) : %.1f dBc (Bruto: %.1f dBc)\n", ...
        "PISO RUÍDO RMS: %.3f LSB (%.2f mV)\n", ...
        "MISSING CODES : %d cód. ausentes (de %d)"], ...
        m.dr_db, m.dr_tri_db, ...
        m.dr_quant_db, m.sqnr_ideal_quant_db, ...
        m.sinad_tri_total_db, m.sinad_tri_intrin_db, ...
        m.enob_tri_total_bits, m.enob_tri_intrin_bits, ...
        m.sfdr_tri_dbc, m.sfdr_dbc, ...
        m.noise_floor_rms_lsb, m.noise_floor_rms_mv, ...
        m.missing_codes, max(0, round(m.s_max) - round(m.s_min) - 1));

    set(txt_col1, "string", col1_str);
    set(txt_col2, "string", col2_str);
    set(txt_col3, "string", col3_str);
end


% =========================================================================
% PROCESSAMENTO EM LOTE E GERAÇÃO DE FIGURAS COMPARATIVAS (f vs fs)
% =========================================================================
function results = run_batch_analysis(mat_files, data_dir, output_dir, VREF, LSB_MV, save_updated_mat)
    n_files = numel(mat_files);
    printf("========================================================================================================================\n");
    printf("INICIANDO ANÁLISE EM LOTE DE %d ARQUIVOS EM: %s (Vref = %.2f V | 1 LSB = %.1f mV)\n", ...
           n_files, data_dir, VREF, LSB_MV);
    printf("========================================================================================================================\n");
    printf("%-31s | %-4s | %7s | %6s | %6s | %5s | %6s | %6s | %5s | %5s | %5s | %5s | %4s\n", ...
           "Arquivo", "Tipo", "fs(Hz)", "f(Hz)", "T(am)", "RMSE", "RMSEin", "MAE", "Offs", "Gain", "DR(dB)", "ENOBi", "Miss");
    printf("------------------------------------------------------------------------------------------------------------------------\n");

    results = cell(n_files, 1);
    csv_path = fullfile(output_dir, "adc_summary_metrics.csv");
    fid = fopen(csv_path, "w");
    fprintf(fid, "file_name,was_full_format,sampling_frequency,actual_sampling_frequency,adc_prescaler,sample_amount,freq_hz,period_samples,num_full_cycles,s_min,s_max,s_vpp,offset_error_lsb,offset_error_mv,offset_error_pct,gain_error_lsb,gain_error_mv,gain_error_pct,measured_gain,rmse_lsb,rmse_mv,rmse_pct_fsr,rmse_intrinsic_lsb,rmse_intrinsic_mv,mae_lsb,mae_mv,mae_pct_fsr,max_abs_err_lsb,max_abs_err_mv,mape_signal_pct,dnl_min,dnl_max,dnl_rms,inl_min,inl_max,inl_rms,missing_codes,is_monotonic,dr_db,dr_tri_db,dr_quant_db,sinad_tri_total_db,sinad_tri_intrin_db,enob_tri_total_bits,enob_tri_intrin_bits,sfdr_tri_dbc,noise_floor_rms_lsb\n");

    for k = 1:n_files
        fpath = fullfile(data_dir, mat_files(k).name);
        m = analyze_single_mat(fpath, VREF, LSB_MV, "opt");
        results{k} = m;

        if save_updated_mat
            save_enriched_mat(fpath, m);
        end

        printf("%-31s | %-4s | %7.1f | %6.2f | %6.1f | %5.2f | %6.2f | %6.2f | %+5.2f | %+5.2f | %6.1f | %5.2f | %4d\n", ...
               m.file_name, ifelse(m.was_full_format, "FULL", "SIMP"), ...
               m.actual_sampling_frequency, m.freq_hz, m.period_samples, ...
               m.rmse_lsb, m.rmse_intrinsic_lsb, m.mae_lsb, ...
               m.offset_error_lsb, m.gain_error_lsb, ...
               m.dr_db, m.enob_tri_intrin_bits, m.missing_codes);

        fprintf(fid, "%s,%d,%.1f,%.2f,%d,%d,%.4f,%.2f,%d,%.0f,%.0f,%.0f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.5f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%d,%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.4f\n", ...
                m.file_name, m.was_full_format, m.sampling_frequency, m.actual_sampling_frequency, ...
                m.adc_prescaler, m.sample_amount, m.freq_hz, m.period_samples, m.num_full_cycles, ...
                m.s_min, m.s_max, m.s_vpp, m.offset_error_lsb, m.offset_error_mv, m.offset_error_pct, ...
                m.gain_error_lsb, m.gain_error_mv, m.gain_error_pct, m.measured_gain, ...
                m.rmse_lsb, m.rmse_mv, m.rmse_pct_fsr, m.rmse_intrinsic_lsb, m.rmse_intrinsic_mv, ...
                m.mae_lsb, m.mae_mv, m.mae_pct_fsr, m.max_abs_err_lsb, m.max_abs_err_mv, m.mape_signal_pct, ...
                m.dnl_min, m.dnl_max, m.dnl_rms, m.inl_min, m.inl_max, m.inl_rms, ...
                m.missing_codes, m.is_monotonic, m.dr_db, m.dr_tri_db, m.dr_quant_db, ...
                m.sinad_tri_total_db, m.sinad_tri_intrin_db, m.enob_tri_total_bits, m.enob_tri_intrin_bits, ...
                m.sfdr_tri_dbc, m.noise_floor_rms_lsb);
    end
    fclose(fid);
    printf("------------------------------------------------------------------------------------------------------------------------\n");
    printf("Tabela CSV salva em: %s\n", csv_path);

    % Gera gráficos comparativos consolidados em tools/octave/outputs/
    if ~isempty(available_graphics_toolkits())
        generate_comparative_figures(results, output_dir, VREF, LSB_MV);
    else
        printf("Aviso: Nenhum toolkit gráfico ativo nesta sessão de terminal sem DISPLAY. Execute adc_analyzer('batch') na GUI do Octave para exportar os PNGs.\n");
    end
end


% =========================================================================
% GERAÇÃO DAS FIGURAS DE ANÁLISE PROFUNDA E COMPARAÇÃO MULTIFREQUÊNCIA
% =========================================================================
function generate_comparative_figures(results, output_dir, VREF, LSB_MV)
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
            export_single_dashboard_png(results{idx_r}, output_dir, VREF, LSB_MV);
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

        % B3: DNL RMS, INL RMS e Missing Codes vs Razão de Sobreamostragem (fs / f = T_samples)
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

        % B5: Número de Amostras por Período (fs/f) vs Missing Codes
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

    % Filtra capturas não clipadas severamente (RMSE < 5 LSB e Vpp >= 250)
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

    % C1: Erros RMSE Bruto, RMSE Intrínseco e MAE por Taxa de Amostragem fs
    subplot(2, 2, 1);
    bar_data_err = [grp_rmse_raw, grp_mae, grp_rmse_in];
    bar(1:n_groups, bar_data_err);
    grid on;
    set(gca, "xtick", 1:n_groups, "xticklabel", grp_labels);
    ylabel("Erro (LSB) [1 LSB = 10 mV]");
    title("1. Erro RMS Bruto, MAE e RMSE Intrínseco por Taxa de Amostragem (fs)");
    legend({"RMSE Bruto (LSB)", "MAE Absoluto (LSB)", "RMSE Intrínseco ADC (LSB)"}, "location", "northwest");

    % C2: Faixa Dinâmica (DR) por Taxa de Amostragem fs
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

    % C3: DNL RMS e INL RMS por Taxa de Amostragem fs
    subplot(2, 2, 3);
    bar_data_lin = [grp_dnl, grp_inl];
    bar(1:n_groups, bar_data_lin);
    grid on;
    set(gca, "xtick", 1:n_groups, "xticklabel", grp_labels);
    ylabel("Erro de Não-Linearidade RMS (LSB)");
    title("3. DNL RMS e INL RMS vs. Frequência de Amostragem (fs)");
    legend({"DNL RMS (LSB)", "INL RMS (LSB)"}, "location", "northwest");

    % C4: Relação Razão de Sobreamostragem (fs / f) vs Erro RMSE Intrínseco em todos os arquivos bons
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


% =========================================================================
% EXPORTAÇÃO DO PAINEL DE 6 GRÁFICOS PARA PNG DE ALTA RESOLUÇÃO
% =========================================================================
function out_png = export_single_dashboard_png(m, output_dir, VREF, LSB_MV)
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

    % Caixa de Resumo Textual Inferior Esquerda (para o PNG exportado)
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
