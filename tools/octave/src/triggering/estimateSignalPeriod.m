function per = estimateSignalPeriod(samples, actual_sampling_frequency, trig, align_mode, wave_type)
    % =========================================================================
    % ESTIMATESIGNALPERIOD - Estimativa robusta de período, frequência e fase
    %
    % Combina cruzamentos de subida/descida, inclinação das rampas lineares
    % (para triangular e dente de serra com menos de 1 ciclo), pico espectral
    % e, quando align_mode = "opt", refina conjuntamente o período e a fase
    % inicial por mínimos quadrados para a forma de onda escolhida.
    % =========================================================================

    if nargin < 4 || isempty(align_mode)
        align_mode = "opt"; % "opt" (mínimos quadrados) ou "trig" (rápido para osciloscópio)
    end
    if nargin < 5 || isempty(wave_type)
        wave_type = "triangular";
    end

    no_ideal = any(strcmpi(strtrim(char(wave_type)), {"none", "off", "desligado", "desativado"}));
    if no_ideal
        wtype = "none";
    else
        wspec = getWaveformSpec(wave_type);
        wtype = wspec.type;
        wave_fn = wspec.eval_fn;
    end

    samples = double(samples(:));
    sample_amount = numel(samples);

    periods_est = [];
    if numel(trig.rising_crossings) >= 2
        periods_est = [periods_est, diff(trig.rising_crossings)];
    end
    if numel(trig.falling_crossings) >= 2
        periods_est = [periods_est, diff(trig.falling_crossings)];
    end

    if ~isempty(periods_est)
        T_init = median(periods_est);
    else
        T_init = NaN;
        if strcmp(wtype, "triangular") || strcmp(wtype, "sawtooth")
            % Estimativa pela inclinação dos segmentos lineares (20 <= ADC <= 235)
            idx_mid = find(samples > 20 & samples < 235);
            breaks = [0; find(diff(idx_mid) > 15); numel(idx_mid)];
            slopes = [];
            for b = 1:(numel(breaks) - 1)
                seg = idx_mid((breaks(b) + 1):breaks(b + 1));
                if numel(seg) > 60
                    p_seg = polyfit(seg - 1, samples(seg), 1);
                    if abs(p_seg(1)) > 1e-6
                        slopes(end + 1) = abs(p_seg(1)); %#ok<AGROW>
                    end
                end
            end
            if ~isempty(slopes)
                span_lsb = ifelse(strcmp(wtype, "sawtooth"), 255.0, 510.0);
                T_init = span_lsb / median(slopes);
            end
        end

        if isnan(T_init)
            if ~isempty(trig.rising_crossings) && ~isempty(trig.falling_crossings) && ~strcmp(wtype, "sawtooth")
                T_init = 2.0 * abs(trig.rising_crossings(1) - trig.falling_crossings(1));
            else
                % Fallback espectral via FFT do sinal sem DC
                s_ac = samples - mean(samples);
                if any(s_ac ~= 0) && sample_amount >= 16
                    half_N = floor(sample_amount / 2) + 1;
                    Y_mag = abs(fft(s_ac));
                    [~, k_pk] = max(Y_mag(2:half_N));
                    T_init = sample_amount / max(1, k_pk);
                else
                    T_init = 512.0;
                end
            end
        end
    end

    valid_len = sample_amount - trig.trig_idx + 1;
    x_plot = (0:(valid_len - 1))';
    y_plot = samples(trig.trig_idx:end);

    if no_ideal
        period_samples = T_init;
        ph_opt = 0.0;
    else
        % Fase inicial teórica pelo nível de trigger na borda de subida
        ph_trig = wspec.trig_phase_fn(trig.trig_level);

        if strcmpi(align_mode, "trig") && ~isempty(trig.rising_crossings)
            period_samples = T_init;
            % Compensa o deslocamento entre a posição fracionária da borda e trig_idx.
            ph_opt = mod(ph_trig + (trig.trig_idx - trig.rising_crossings(1)) / T_init, 1.0);
        else
            % Otimiza período e fase sobre o buffer completo (preserva picos/vales)
            % e projeta a fase resultante para o início da janela pós-trigger.
            n_full = (0:(sample_amount - 1))';
            ph_grid = linspace(0, 1, 241);
            ph_grid(end) = [];
            best_mse = inf;
            best_ph_full = ph_trig;
            for ph_cand = ph_grid
                y_cand = wave_fn(n_full, T_init, ph_cand);
                mse_cand = mean((samples - y_cand) .^ 2);
                if mse_cand < best_mse
                    best_mse = mse_cand;
                    best_ph_full = ph_cand;
                end
            end

            if strcmp(wtype, "square")
                % Para onda quadrada (função degrau), busca em grade 2D fina evita platôs no fminsearch
                t_scales = linspace(-0.03, 0.03, 25);
                ph_deltas = linspace(-0.015, 0.015, 31);
                best_T = T_init;
                best_ph_loc = best_ph_full;
                best_mse_loc = best_mse;
                for du = t_scales
                    T_cand = T_init * exp(du);
                    for dp = ph_deltas
                        ph_c = mod(best_ph_full + dp, 1.0);
                        mse_c = mean((samples - wave_fn(n_full, T_cand, ph_c)) .^ 2);
                        if mse_c < best_mse_loc
                            best_mse_loc = mse_c;
                            best_T = T_cand;
                            best_ph_loc = ph_c;
                        end
                    end
                end
                period_samples = best_T;
                ph_full_opt = best_ph_loc;
            else
                cost_fn = @(u) mean((samples - wave_fn(n_full, T_init * exp(u(1)), best_ph_full + u(2))) .^ 2);
                opts = optimset("TolX", 1e-6, "TolFun", 1e-6, "MaxIter", 400, "Display", "off");
                u_opt = fminsearch(cost_fn, [0, 0], opts);
                if abs(u_opt(1)) < 0.08
                    period_samples = T_init * exp(u_opt(1));
                    ph_full_opt = mod(best_ph_full + u_opt(2), 1.0);
                else
                    period_samples = T_init;
                    ph_full_opt = best_ph_full;
                end
            end
            ph_opt = mod(ph_full_opt + (trig.trig_idx - 1) / period_samples, 1.0);
        end
    end

    period_sec = period_samples / actual_sampling_frequency;
    freq_hz = actual_sampling_frequency / period_samples;

    per = struct();
    per.wave_type = wtype;
    per.period_samples = period_samples;
    per.period_sec = period_sec;
    per.freq_hz = freq_hz;
    per.ph_opt = ph_opt;
    per.x_plot = x_plot;
    per.y_plot = y_plot;
end
