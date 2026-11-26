function spec = computeSpectralMetrics(samples, actual_sampling_frequency, ref, wave_type, window_type, freq_hz, LSB_MV)
    % =========================================================================
    % COMPUTESPECTRALMETRICS - Análise espectral tripla (FFT), DR e piso de ruído
    %
    % Executa a FFT unilateral janelada para:
    %   1. Sinal capturado pelo ADC (8 bits)
    %   2. Sinal ideal quantizado (256 níveis)
    %   3. Sinal contínuo puro da forma de onda selecionada
    % Identifica o componente fundamental e estima o piso de ruído RMS (via
    % Parseval, mascarando DC e harmônicas) e a Faixa Dinâmica (DR) em dB
    % relativa ao fundo de escala senoidal (P_fs = 127,5^2 / 2).
    % =========================================================================

    if nargin < 4 || isempty(wave_type)
        if isfield(ref, "wave_type") && ~isempty(ref.wave_type)
            wave_type = ref.wave_type;
        else
            wave_type = "triangular";
        end
    end
    if nargin < 5 || isempty(window_type)
        window_type = "hanning";
    end
    if nargin < 6
        freq_hz = NaN;
    end
    if nargin < 7 || isempty(LSB_MV)
        LSB_MV = (5.0 / 256.0) * 1e3;
    end

    wspec = getWaveformSpec(wave_type);

    samples = double(samples(:));
    N_fft = numel(samples);

    % FFT tripla usando a mesma função unilateral com a janela selecionada
    s_adc   = computeWindowedSpectrum(samples, actual_sampling_frequency, window_type);
    s_quant = computeWindowedSpectrum(ref.ideal_quant_full, actual_sampling_frequency, window_type);
    s_ref   = computeWindowedSpectrum(ref.ideal_cont_full, actual_sampling_frequency, window_type);

    freq_axis = s_adc.freq_axis;
    half_N    = s_adc.half_N;
    mag_lin   = s_adc.mag_lin;
    mag_db    = s_adc.mag_db;

    % Identificação do bin fundamental na FFT
    if N_fft > 1 && any(samples ~= samples(1))
        [~, fund_bin] = max(mag_lin(2:end));
        fund_bin = fund_bin + 1;
        fund_freq_fft = freq_axis(fund_bin);
        fund_mag_db   = mag_db(fund_bin);
        fund_mag_lin  = mag_lin(fund_bin);
    else
        fund_bin = 1;
        fund_freq_fft = NaN;
        fund_mag_db   = NaN;
        fund_mag_lin  = NaN;
    end

    % Piso de ruído RMS por Parseval (mascarando DC e harmônicas) e Faixa Dinâmica (DR)
    if isempty(freq_hz) || ~isfinite(freq_hz) || freq_hz <= 0
        freq_hz = fund_freq_fft;
    end

    lobe_hw = 3;
    if strcmp(s_adc.window_type, "blackman")
        lobe_hw = 4;
    end

    if isfinite(fund_freq_fft) && isfinite(freq_hz) && freq_hz > 0
        pure_noise_mask = true(half_N, 1);
        pure_noise_mask(1:min(lobe_hw, half_N)) = false;
        max_harm_order = min(60, floor((actual_sampling_frequency / 2.0) / max(0.5, freq_hz)));
        for h_ord = 1:max_harm_order
            exact_bin = 1.0 + h_ord * freq_hz * N_fft / actual_sampling_frequency;
            b_lo = max(2, floor(exact_bin - lobe_hw));
            b_hi = min(half_N, ceil(exact_bin + lobe_hw));
            pure_noise_mask(b_lo:b_hi) = false;
        end

        if any(pure_noise_mask)
            P_spec_noise_adc = sum(s_adc.psd_parseval(pure_noise_mask)) * (half_N / sum(pure_noise_mask));
        else
            P_spec_noise_adc = var(samples - ref.ideal_cont_full);
        end

        noise_floor_rms_lsb = sqrt(max(0.0, P_spec_noise_adc));
        noise_floor_rms_mv  = noise_floor_rms_lsb * LSB_MV;
        noise_floor_rms_pct = (noise_floor_rms_lsb / 256.0) * 100.0;

        P_fs_sin = (127.5 ^ 2) / 2.0;
        dr_db = 10.0 * log10(P_fs_sin / max(1e-12, P_spec_noise_adc));
    else
        noise_floor_rms_lsb = NaN;
        noise_floor_rms_mv  = NaN;
        noise_floor_rms_pct = NaN;
        dr_db = NaN;
    end

    spec = struct();
    spec.wave_type           = wspec.type;
    spec.window_type         = s_adc.window_type;
    spec.window_label        = s_adc.window_label;
    spec.freq_axis           = freq_axis;
    spec.mag_db              = mag_db;
    spec.mag_db_quant        = s_quant.mag_db;
    spec.mag_db_ref          = s_ref.mag_db;
    spec.mag_lin             = mag_lin;
    spec.mag_lin_quant       = s_quant.mag_lin;
    spec.mag_lin_ref         = s_ref.mag_lin;
    spec.phase_deg           = s_adc.phase_deg;
    spec.fund_bin            = fund_bin;
    spec.fund_freq_fft       = fund_freq_fft;
    spec.fund_mag_db         = fund_mag_db;
    spec.fund_mag_lin        = fund_mag_lin;
    spec.dr_db               = dr_db;
    spec.noise_floor_rms_lsb = noise_floor_rms_lsb;
    spec.noise_floor_rms_mv  = noise_floor_rms_mv;
    spec.noise_floor_rms_pct = noise_floor_rms_pct;
end
