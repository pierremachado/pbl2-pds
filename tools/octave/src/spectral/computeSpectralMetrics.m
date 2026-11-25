function spec = computeSpectralMetrics(samples, actual_sampling_frequency, per, ref, err, LSB_MV, wave_type)
    % =========================================================================
    % COMPUTESPECTRALMETRICS - Análise espectral tripla (FFT) e faixa dinâmica
    %
    % Executa a FFT unilateral com janela de Hann para:
    %   1. Sinal capturado pelo ADC (8 bits)
    %   2. Sinal ideal quantizado (256 níveis)
    %   3. Sinal contínuo puro da forma de onda selecionada
    % E calcula DR (Faixa Dinâmica), SINAD, SFDR, THD, ENOB e piso de ruído RMS
    % via Parseval, com potência de fundo de escala, fator de crista e máscaras
    % harmônicas adaptados à forma de onda (triangular, sine, sawtooth ou square).
    % =========================================================================

    if nargin < 6 || isempty(LSB_MV)
        LSB_MV = 10.0;
    end
    if nargin < 7 || isempty(wave_type)
        if isfield(ref, "wave_type") && ~isempty(ref.wave_type)
            wave_type = ref.wave_type;
        else
            wave_type = "triangular";
        end
    end

    wspec = getWaveformSpec(wave_type);

    samples = double(samples(:));
    N_fft = numel(samples);
    freq_hz = per.freq_hz;

    % FFT tripla usando a mesma função unilateral com janela de Hann
    s_adc   = computeHannSpectrum(samples, actual_sampling_frequency);
    s_quant = computeHannSpectrum(ref.ideal_quant_full, actual_sampling_frequency);
    s_ref   = computeHannSpectrum(ref.ideal_cont_full, actual_sampling_frequency);

    freq_axis = s_adc.freq_axis;
    half_N    = s_adc.half_N;
    mag_lin   = s_adc.mag_lin;
    mag_dbfs  = s_adc.mag_dbfs;

    % Identificação do bin fundamental na FFT
    if N_fft > 1 && any(samples ~= samples(1))
        [~, fund_bin] = max(mag_lin(2:end));
        fund_bin = fund_bin + 1;
        fund_freq_fft = freq_axis(fund_bin);
        fund_mag_dbfs = mag_dbfs(fund_bin);
        fund_mag_pct  = s_adc.mag_pct(fund_bin);
    else
        fund_bin = 1;
        fund_freq_fft = NaN;
        fund_mag_dbfs = NaN;
        fund_mag_pct  = NaN;
    end

    % Métricas clássicas IEEE para senoide usando potência normalizada por Parseval
    fund_lobe = max(2, fund_bin - 3):min(half_N, fund_bin + 3);
    psd_bins = s_adc.psd_parseval;
    P_signal = sum(psd_bins(fund_lobe));

    noise_dist_mask = true(half_N, 1);
    noise_dist_mask(1:min(2, half_N)) = false;
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

    db_per_bit = 20.0 * log10(2.0);
    if isfinite(fund_mag_dbfs) && any(noise_dist_mask)
        sfdr_dbc = fund_mag_dbfs - max(mag_dbfs(noise_dist_mask));
        sinad_db = 10.0 * log10(max(P_signal, 1e-12) / max(P_nad, 1e-12));
        thd_db   = 10.0 * log10(max(P_harm, 1e-12) / max(P_signal, 1e-12));
        enob_bits = max(0, (sinad_db - 1.7609) / db_per_bit);
    else
        sfdr_dbc = NaN;
        sinad_db = NaN;
        thd_db   = NaN;
        enob_bits = 0;
    end

    % Piso de ruído por Parseval mascarando DC e todas as harmônicas do sinal
    pure_noise_mask = true(half_N, 1);
    pure_noise_mask(1:min(3, half_N)) = false;
    max_harm_order = min(60, floor((actual_sampling_frequency / 2.0) / max(0.5, freq_hz)));
    for h_ord = 1:max_harm_order
        exact_bin = 1.0 + h_ord * freq_hz * N_fft / actual_sampling_frequency;
        b_lo = max(2, floor(exact_bin - 3));
        b_hi = min(half_N, ceil(exact_bin + 3));
        pure_noise_mask(b_lo:b_hi) = false;
    end

    if any(pure_noise_mask)
        P_spec_noise_adc   = sum(s_adc.psd_parseval(pure_noise_mask)) * (half_N / sum(pure_noise_mask));
        P_spec_noise_quant = sum(s_quant.psd_parseval(pure_noise_mask)) * (half_N / sum(pure_noise_mask));
    else
        P_spec_noise_adc   = err.rmse_intrinsic_lsb ^ 2;
        P_spec_noise_quant = mean(err.err_ideal_quant_lsb .^ 2);
    end

    noise_floor_rms_lsb = sqrt(P_spec_noise_adc);
    noise_floor_rms_mv  = noise_floor_rms_lsb * LSB_MV;

    P_fs_sin  = (127.5 ^ 2) / 2.0;
    P_fs_wave = wspec.p_fs;

    dr_db       = 10.0 * log10(P_fs_sin / max(1e-12, P_spec_noise_adc));
    dr_wave_db  = 10.0 * log10(P_fs_wave / max(1e-12, P_spec_noise_adc));
    dr_quant_db = 10.0 * log10(P_fs_sin / max(1e-12, P_spec_noise_quant));

    % Potência do sinal em número inteiro de ciclos (quando disponível)
    n_plot = numel(ref.ideal_cont_plot);
    n_cycles_plot = floor(n_plot / per.period_samples);
    if n_cycles_plot >= 1
        n_sig_eval = min(n_plot, max(2, round(n_cycles_plot * per.period_samples)));
        P_sig_wave_actual = var(ref.ideal_cont_plot(1:n_sig_eval));
    else
        P_sig_wave_actual = var(ref.ideal_cont_plot);
    end

    sinad_wave_total_db  = 10.0 * log10(P_sig_wave_actual / max(1e-12, mean(err.err_vs_cont_lsb .^ 2)));
    sinad_wave_intrin_db = 10.0 * log10(P_sig_wave_actual / max(1e-12, err.rmse_intrinsic_lsb ^ 2));
    sqnr_ideal_quant_db  = 10.0 * log10(P_sig_wave_actual / max(1e-12, mean(err.err_ideal_quant_lsb .^ 2)));

    enob_offset_db = wspec.enob_offset_db;
    enob_wave_total_bits  = max(0, (sinad_wave_total_db - enob_offset_db) / db_per_bit);
    enob_wave_intrin_bits = max(0, (sinad_wave_intrin_db - enob_offset_db) / db_per_bit);

    % Máscara de harmônicas intrínsecas da forma de onda para SFDR livre da onda
    non_wave_mask = true(half_N, 1);
    non_wave_mask(1:min(3, half_N)) = false;
    if strcmp(wspec.harmonic_mode, "fundamental")
        harm_list = 1;
    elseif strcmp(wspec.harmonic_mode, "odd")
        harm_list = 1:2:max_harm_order;
    else
        harm_list = 1:max_harm_order;
    end

    for h_ord = harm_list
        exact_bin = 1.0 + h_ord * freq_hz * N_fft / actual_sampling_frequency;
        b_lo = max(2, floor(exact_bin - 3));
        b_hi = min(half_N, ceil(exact_bin + 3));
        non_wave_mask(b_lo:b_hi) = false;
    end
    if isfinite(fund_mag_dbfs) && any(non_wave_mask)
        sfdr_wave_dbc = fund_mag_dbfs - max(mag_dbfs(non_wave_mask));
    else
        sfdr_wave_dbc = sfdr_dbc;
    end

    spec = struct();
    spec.wave_type             = wspec.type;
    spec.freq_axis             = freq_axis;
    spec.mag_dbfs              = mag_dbfs;
    spec.mag_dbfs_quant        = s_quant.mag_dbfs;
    spec.mag_dbfs_ref          = s_ref.mag_dbfs;
    spec.mag_dbfs_tri          = s_ref.mag_dbfs; % Alias mantido para exportar_dados.m
    spec.mag_pct               = s_adc.mag_pct;
    spec.mag_pct_quant         = s_quant.mag_pct;
    spec.mag_pct_ref           = s_ref.mag_pct;
    spec.phase_deg             = s_adc.phase_deg;
    spec.fund_bin              = fund_bin;
    spec.fund_freq_fft         = fund_freq_fft;
    spec.fund_mag_dbfs         = fund_mag_dbfs;
    spec.fund_mag_pct          = fund_mag_pct;
    spec.dr_db                 = dr_db;
    spec.dr_wave_db            = dr_wave_db;
    spec.dr_quant_db           = dr_quant_db;
    spec.sfdr_dbc              = sfdr_dbc;
    spec.sfdr_wave_dbc         = sfdr_wave_dbc;
    spec.sinad_db              = sinad_db;
    spec.thd_db                = thd_db;
    spec.enob_bits             = enob_bits;
    spec.sinad_wave_total_db   = sinad_wave_total_db;
    spec.sinad_wave_intrin_db  = sinad_wave_intrin_db;
    spec.sqnr_ideal_quant_db   = sqnr_ideal_quant_db;
    spec.enob_wave_total_bits  = enob_wave_total_bits;
    spec.enob_wave_intrin_bits = enob_wave_intrin_bits;
    spec.noise_floor_rms_lsb   = noise_floor_rms_lsb;
    spec.noise_floor_rms_mv    = noise_floor_rms_mv;
end
