function spec = computeSpectralMetrics(samples, actual_sampling_frequency, ref, wave_type, window_type)
    % =========================================================================
    % COMPUTESPECTRALMETRICS - Análise espectral tripla (FFT) e fundamental
    %
    % Executa a FFT unilateral janelada para:
    %   1. Sinal capturado pelo ADC (8 bits)
    %   2. Sinal ideal quantizado (256 níveis)
    %   3. Sinal contínuo puro da forma de onda selecionada
    % E identifica a frequência e magnitude do componente fundamental.
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

    wspec = getWaveformSpec(wave_type);

    samples = double(samples(:));
    N_fft = numel(samples);

    % FFT tripla usando a mesma função unilateral com a janela selecionada
    s_adc   = computeWindowedSpectrum(samples, actual_sampling_frequency, window_type);
    s_quant = computeWindowedSpectrum(ref.ideal_quant_full, actual_sampling_frequency, window_type);
    s_ref   = computeWindowedSpectrum(ref.ideal_cont_full, actual_sampling_frequency, window_type);

    freq_axis = s_adc.freq_axis;
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

    spec = struct();
    spec.wave_type      = wspec.type;
    spec.window_type    = s_adc.window_type;
    spec.window_label   = s_adc.window_label;
    spec.freq_axis      = freq_axis;
    spec.mag_db         = mag_db;
    spec.mag_db_quant   = s_quant.mag_db;
    spec.mag_db_ref     = s_ref.mag_db;
    spec.mag_lin        = mag_lin;
    spec.mag_lin_quant  = s_quant.mag_lin;
    spec.mag_lin_ref    = s_ref.mag_lin;
    spec.phase_deg      = s_adc.phase_deg;
    spec.fund_bin       = fund_bin;
    spec.fund_freq_fft  = fund_freq_fft;
    spec.fund_mag_db    = fund_mag_db;
    spec.fund_mag_lin   = fund_mag_lin;
end
