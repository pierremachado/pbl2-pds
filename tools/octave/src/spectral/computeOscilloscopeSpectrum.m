function spec = computeOscilloscopeSpectrum(samples, sampling_frequency, window_type)
    % Espectro unilateral de amplitude janelado (dB e linear em LSB).
    if nargin < 3 || isempty(window_type)
        window_type = "hanning";
    end

    samples = double(samples(:));
    N = numel(samples);
    s = computeWindowedSpectrum(samples, sampling_frequency, window_type);

    spec = struct();
    spec.window_type    = s.window_type;
    spec.window_label   = s.window_label;
    spec.freq_axis      = s.freq_axis;
    spec.mag_db         = s.mag_db;
    spec.mag_lin        = s.mag_lin;
    spec.peak_frequency = NaN;
    spec.peak_db        = NaN;
    spec.peak_lin       = NaN;
    if N > 1 && any(samples ~= samples(1))
        [~, k] = max(s.mag_lin(2:end));
        spec.peak_frequency = s.freq_axis(k + 1);
        spec.peak_db        = s.mag_db(k + 1);
        spec.peak_lin       = s.mag_lin(k + 1);
    end
end
