function s = computeHannSpectrum(signal, sampling_frequency)
    % =========================================================================
    % COMPUTEHANNSPECTRUM - FFT unilateral com janela de Hann
    %
    % Calcula magnitude unilateral em LSB (mag_lin), em % FS (0-100%,
    % 100% = 127.5 LSB), em dBFS (0 dBFS = 127.5 LSB) e fase em graus,
    % tratando corretamente o bin de Nyquist (N par ou ímpar).
    % =========================================================================

    signal = double(signal(:));
    N = numel(signal);
    win = ones(N, 1);
    if N > 2
        win = 0.5 * (1.0 - cos(2.0 * pi * (0:(N - 1))' / (N - 1)));
    end

    win_sum = sum(win);
    half_N = floor(N / 2) + 1;
    % DC e Nyquist (quando N é par) não possuem par de frequência negativa.
    last_paired = half_N - (mod(N, 2) == 0);

    Y = fft((signal - mean(signal)) .* win);
    Y_half = Y(1:half_N);

    mag_lin = abs(Y_half) / win_sum;
    if last_paired >= 2
        mag_lin(2:last_paired) = 2.0 * mag_lin(2:last_paired);
    end

    s = struct();
    s.freq_axis   = (0:(half_N - 1))' * (sampling_frequency / N);
    s.mag_lin     = mag_lin;
    s.mag_pct     = (mag_lin / 127.5) * 100.0;
    s.mag_dbfs    = 20.0 * log10(max(mag_lin / 127.5, 1e-6));
    s.phase_deg   = rad2deg(angle(Y_half));
    s.half_N      = half_N;
    s.last_paired = last_paired;
end
