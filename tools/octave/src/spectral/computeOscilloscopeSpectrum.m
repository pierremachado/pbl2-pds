function spec = computeOscilloscopeSpectrum(samples, sampling_frequency)
    % Espectro unilateral de amplitude com janela de Hann, em dBFS.
    samples = double(samples(:));
    N = numel(samples);
    win = ones(N, 1);
    if N > 2
        win = 0.5 * (1 - cos(2 * pi * (0:(N - 1))' / (N - 1)));
    end
    Y = fft((samples - mean(samples)) .* win);
    mag = abs(Y(1:(floor(N / 2) + 1))) / sum(win);
    % DC e Nyquist não possuem um par de frequências a somar.
    last_paired = numel(mag) - (mod(N, 2) == 0);
    mag(2:last_paired) = 2 * mag(2:last_paired);
    spec.freq_axis = (0:(numel(mag) - 1))' * sampling_frequency / N;
    spec.mag_dbfs = 20 * log10(max(mag / 127.5, 1e-6));
    spec.peak_frequency = NaN;
    spec.peak_dbfs = NaN;
    if N > 1 && any(samples ~= samples(1))
        [~, k] = max(mag(2:end));
        spec.peak_frequency = spec.freq_axis(k + 1);
        spec.peak_dbfs = spec.mag_dbfs(k + 1);
    end
end
