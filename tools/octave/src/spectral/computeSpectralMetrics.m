function spec = computeSpectralMetrics(samples, actual_sampling_frequency, per, ref, err, LSB_MV)
    % =========================================================================
    % COMPUTESPECTRALMETRICS - Análise espectral tripla (FFT) e faixa dinâmica
    %
    % Executa a FFT com janela de Hann para:
    %   1. Sinal capturado pelo ADC (8 bits)
    %   2. Sinal triangular ideal quantizado (256 níveis)
    %   3. Sinal triangular contínuo puro
    % E calcula DR (Faixa Dinâmica), SINAD, SFDR, THD, ENOB e piso de ruído RMS,
    % com estimativas adaptadas à triangular e máscaras em torno das harmônicas.
    % =========================================================================

    if nargin < 6 || isempty(LSB_MV)
        LSB_MV = 10.0;
    end

    samples = double(samples(:));
    N_fft = numel(samples);
    freq_hz = per.freq_hz;

    n_vec = (0:(N_fft - 1))';
    win_hann = 0.5 * (1.0 - cos(2.0 * pi * n_vec / (N_fft - 1)));
    coherent_gain = mean(win_hann);
    win_power_gain = mean(win_hann .^ 2);
    half_N = floor(N_fft / 2) + 1;
    freq_axis = (0:(half_N - 1))' * (actual_sampling_frequency / N_fft);

    % 1. FFT do Sinal Capturado pelo ADC
    s_ac = samples - mean(samples);
    Y_fft = fft(s_ac .* win_hann);
    Y_half = Y_fft(1:half_N);
    mag_lin = abs(Y_half) / (N_fft * coherent_gain / 2.0);
    mag_lin(1) = abs(Y_half(1)) / (N_fft * coherent_gain);
    mag_dbfs = 20.0 * log10(max(mag_lin / 127.5, 1e-6));
    phase_deg = rad2deg(angle(Y_half));

    % 2. FFT do Sinal Ideal Quantizado (256 níveis)
    sq_ac = ref.ideal_quant_full - mean(ref.ideal_quant_full);
    Yq_fft = fft(sq_ac .* win_hann);
    Yq_half = Yq_fft(1:half_N);
    mag_lin_quant = abs(Yq_half) / (N_fft * coherent_gain / 2.0);
    mag_lin_quant(1) = abs(Yq_half(1)) / (N_fft * coherent_gain);
    mag_dbfs_quant = 20.0 * log10(max(mag_lin_quant / 127.5, 1e-6));
    phase_deg_quant = rad2deg(angle(Yq_half));

    % 3. FFT do Sinal Triangular Contínuo Normal (sem quantização)
    st_ac = ref.ideal_cont_full - mean(ref.ideal_cont_full);
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

    % Métricas clássicas (tratando apenas a fundamental como sinal)
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

    % Métricas espectrais e de faixa dinâmica específicas para onda triangular
    P_parseval_adc   = (abs(Y_half) .^ 2) / (N_fft^2 * win_power_gain);
    P_parseval_adc(2:end-1) = 2.0 * P_parseval_adc(2:end-1);

    P_parseval_quant = (abs(Yq_half) .^ 2) / (N_fft^2 * win_power_gain);
    P_parseval_quant(2:end-1) = 2.0 * P_parseval_quant(2:end-1);

    pure_noise_mask = true(half_N, 1);
    pure_noise_mask(1:3) = false;
    max_harm_order = min(60, floor((actual_sampling_frequency / 2.0) / max(0.5, freq_hz)));
    for h_ord = 1:max_harm_order
        exact_bin = 1.0 + h_ord * freq_hz * N_fft / actual_sampling_frequency;
        b_lo = max(2, floor(exact_bin - 3));
        b_hi = min(half_N, ceil(exact_bin + 3));
        pure_noise_mask(b_lo:b_hi) = false;
    end

    if any(pure_noise_mask)
        P_spec_noise_adc   = sum(P_parseval_adc(pure_noise_mask)) * (half_N / sum(pure_noise_mask));
        P_spec_noise_quant = sum(P_parseval_quant(pure_noise_mask)) * (half_N / sum(pure_noise_mask));
    else
        P_spec_noise_adc   = mean(err.err_intrinsic_lsb .^ 2);
        P_spec_noise_quant = mean(err.err_ideal_quant_lsb .^ 2);
    end

    noise_floor_rms_lsb = sqrt(P_spec_noise_adc);
    noise_floor_rms_mv  = noise_floor_rms_lsb * LSB_MV;

    P_fs_sin = (127.5 ^ 2) / 2.0;
    P_fs_tri = (127.5 ^ 2) / 3.0;

    dr_db       = 10.0 * log10(P_fs_sin / max(1e-12, P_spec_noise_adc));
    dr_tri_db   = 10.0 * log10(P_fs_tri / max(1e-12, P_spec_noise_adc));
    dr_quant_db = 10.0 * log10(P_fs_sin / max(1e-12, P_spec_noise_quant));

    P_sig_tri_actual    = var(ref.ideal_cont_plot);
    sinad_tri_total_db  = 10.0 * log10(P_sig_tri_actual / max(1e-12, mean(err.err_vs_cont_lsb .^ 2)));
    sinad_tri_intrin_db = 10.0 * log10(P_sig_tri_actual / max(1e-12, mean(err.err_intrinsic_lsb .^ 2)));
    sqnr_ideal_quant_db = 10.0 * log10(P_sig_tri_actual / max(1e-12, mean(err.err_ideal_quant_lsb .^ 2)));

    enob_tri_total_bits  = max(0, (sinad_tri_total_db - 1.76 + 1.25) / 6.02);
    enob_tri_intrin_bits = max(0, (sinad_tri_intrin_db - 1.76 + 1.25) / 6.02);
    enob_ideal_quant     = max(0, (sqnr_ideal_quant_db - 1.76 + 1.25) / 6.02);

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

    spec = struct();
    spec.freq_axis            = freq_axis;
    spec.mag_dbfs             = mag_dbfs;
    spec.mag_dbfs_quant       = mag_dbfs_quant;
    spec.mag_dbfs_tri         = mag_dbfs_tri;
    spec.phase_deg            = phase_deg;
    spec.phase_deg_quant      = phase_deg_quant;
    spec.phase_deg_tri        = phase_deg_tri;
    spec.fund_bin             = fund_bin;
    spec.fund_freq_fft        = fund_freq_fft;
    spec.fund_mag_dbfs        = fund_mag_dbfs;
    spec.sig_bins             = sig_bins;
    spec.dr_db                = dr_db;
    spec.dr_tri_db            = dr_tri_db;
    spec.dr_quant_db          = dr_quant_db;
    spec.dr_db_legacy         = dr_db_legacy;
    spec.sfdr_dbc             = sfdr_dbc;
    spec.sfdr_tri_dbc         = sfdr_tri_dbc;
    spec.sinad_db             = sinad_db;
    spec.thd_db               = thd_db;
    spec.enob_bits            = enob_bits;
    spec.sinad_tri_total_db   = sinad_tri_total_db;
    spec.sinad_tri_intrin_db  = sinad_tri_intrin_db;
    spec.sqnr_ideal_quant_db  = sqnr_ideal_quant_db;
    spec.enob_tri_total_bits  = enob_tri_total_bits;
    spec.enob_tri_intrin_bits = enob_tri_intrin_bits;
    spec.enob_ideal_quant     = enob_ideal_quant;
    spec.noise_floor_rms_lsb  = noise_floor_rms_lsb;
    spec.noise_floor_rms_mv   = noise_floor_rms_mv;
end
