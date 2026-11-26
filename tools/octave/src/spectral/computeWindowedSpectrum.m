function s = computeWindowedSpectrum(signal, sampling_frequency, window_type)
    % =========================================================================
    % COMPUTEWINDOWEDSPECTRUM - FFT unilateral janelada (amplitude linear e dB)
    %
    % Janelas suportadas:
    %   - "hanning" (padrão; aceita "hann")
    %   - "rectangular" (aceita "retangular", "rect")
    %   - "hamming"
    %   - "blackman"
    %
    % Calcula magnitude unilateral em LSB (mag_lin, normalizada pela soma da
    % janela), em dB relativos ao fundo de escala senoidal (0 dB = 127,5 LSB),
    % densidade de potência normalizada por Parseval (psd_parseval), fase em
    % graus e eixo de frequências, tratando corretamente o bin de Nyquist para
    % N par ou ímpar.
    % =========================================================================

    if nargin < 3 || isempty(window_type)
        window_type = "hanning";
    end

    [wtype, wlabel] = normalizeWindowType(window_type);

    signal = double(signal(:));
    N = numel(signal);
    win = buildWindow(N, wtype);

    win_sum = sum(win);
    win_power_gain = mean(win .^ 2);
    half_N = floor(N / 2) + 1;
    % DC e Nyquist (quando N é par) não possuem par de frequência negativa.
    last_paired = half_N - (mod(N, 2) == 0);

    Y = fft((signal - mean(signal)) .* win);
    Y_half = Y(1:half_N);

    mag_lin = abs(Y_half) / win_sum;
    if last_paired >= 2
        mag_lin(2:last_paired) = 2.0 * mag_lin(2:last_paired);
    end

    psd_parseval = (abs(Y_half) .^ 2) / (N^2 * win_power_gain);
    if last_paired >= 2
        psd_parseval(2:last_paired) = 2.0 * psd_parseval(2:last_paired);
    end

    s = struct();
    s.window_type  = wtype;
    s.window_label = wlabel;
    s.freq_axis    = (0:(half_N - 1))' * (sampling_frequency / N);
    s.mag_lin      = mag_lin;
    s.mag_db       = 20.0 * log10(max(mag_lin / 127.5, 1e-6));
    s.psd_parseval = psd_parseval;
    s.phase_deg    = rad2deg(angle(Y_half));
    s.half_N       = half_N;
    s.last_paired  = last_paired;
end

function [wtype, wlabel] = normalizeWindowType(window_type)
    raw = lower(strtrim(char(window_type)));
    if any(strcmp(raw, {"hanning", "hann"}))
        wtype  = "hanning";
        wlabel = "Hanning";
    elseif any(strcmp(raw, {"rectangular", "retangular", "rect", "boxcar", "none"}))
        wtype  = "rectangular";
        wlabel = "Retangular";
    elseif strcmp(raw, "hamming")
        wtype  = "hamming";
        wlabel = "Hamming";
    elseif strcmp(raw, "blackman")
        wtype  = "blackman";
        wlabel = "Blackman";
    else
        error("Janela FFT não suportada: '%s'. Use 'hanning', 'rectangular', 'hamming' ou 'blackman'.", raw);
    end
end

function win = buildWindow(N, wtype)
    if N <= 1 || strcmp(wtype, "rectangular")
        win = ones(N, 1);
        return;
    end
    n = (0:(N - 1))';
    M = N - 1;
    switch wtype
        case "hanning"
            win = 0.5 - 0.5 * cos(2.0 * pi * n / M);
        case "hamming"
            win = 0.54 - 0.46 * cos(2.0 * pi * n / M);
        case "blackman"
            win = 0.42 - 0.5 * cos(2.0 * pi * n / M) + 0.08 * cos(4.0 * pi * n / M);
        otherwise
            win = ones(N, 1);
    end
end
