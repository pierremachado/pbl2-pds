function spec = computeOscilloscopeSpectrum(samples, sampling_frequency)
    % Espectro unilateral de amplitude com janela de Hann (dBFS e linear 0-100% FS).
    samples = double(samples(:));
    N = numel(samples);
    s = computeHannSpectrum(samples, sampling_frequency);

    spec = struct();
    spec.freq_axis = s.freq_axis;
    spec.mag_dbfs  = s.mag_dbfs;
    spec.mag_pct   = s.mag_pct;
    spec.peak_frequency = NaN;
    spec.peak_dbfs = NaN;
    spec.peak_pct  = NaN;
    if N > 1 && any(samples ~= samples(1))
        [~, k] = max(s.mag_lin(2:end));
        spec.peak_frequency = s.freq_axis(k + 1);
        spec.peak_dbfs = s.mag_dbfs(k + 1);
        spec.peak_pct  = s.mag_pct(k + 1);
    end
end
