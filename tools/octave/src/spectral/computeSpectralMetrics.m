function spec = computeSpectralMetrics(samples, actual_sampling_frequency, ref, wave_type)
    % =========================================================================
    % COMPUTESPECTRALMETRICS - Análise espectral tripla (FFT) e fundamental
    %
    % Executa a FFT unilateral com janela de Hann para:
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

    wspec = getWaveformSpec(wave_type);

    samples = double(samples(:));
    N_fft = numel(samples);

    % FFT tripla usando a mesma função unilateral com janela de Hann
    s_adc   = computeHannSpectrum(samples, actual_sampling_frequency);
    s_quant = computeHannSpectrum(ref.ideal_quant_full, actual_sampling_frequency);
    s_ref   = computeHannSpectrum(ref.ideal_cont_full, actual_sampling_frequency);

    freq_axis = s_adc.freq_axis;
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

    spec = struct();
    spec.wave_type      = wspec.type;
    spec.freq_axis      = freq_axis;
    spec.mag_dbfs       = mag_dbfs;
    spec.mag_dbfs_quant = s_quant.mag_dbfs;
    spec.mag_dbfs_ref   = s_ref.mag_dbfs;
    spec.mag_pct        = s_adc.mag_pct;
    spec.mag_pct_quant  = s_quant.mag_pct;
    spec.mag_pct_ref    = s_ref.mag_pct;
    spec.phase_deg      = s_adc.phase_deg;
    spec.fund_bin       = fund_bin;
    spec.fund_freq_fft  = fund_freq_fft;
    spec.fund_mag_dbfs  = fund_mag_dbfs;
    spec.fund_mag_pct   = fund_mag_pct;
end
