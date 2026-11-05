function per = estimateSignalPeriod(samples, actual_sampling_frequency, trig, align_mode)
    % =========================================================================
    % ESTIMATESIGNALPERIOD - Estimativa robusta de período, frequência e fase
    %
    % Combina cruzamentos de subida/descida, inclinação das rampas lineares
    % (para sinais com menos de 1 ciclo completo) e, quando align_mode = "opt",
    % refina conjuntamente o período e a fase inicial por mínimos quadrados.
    % =========================================================================

    if nargin < 4 || isempty(align_mode)
        align_mode = "opt"; % "opt" (mínimos quadrados) ou "trig" (rápido para osciloscópio)
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
        % Estimativa pela inclinação dos segmentos lineares (20 <= ADC <= 235)
        idx_mid = find(samples > 20 & samples < 235);
        breaks = [0; find(diff(idx_mid) > 15); numel(idx_mid)];
        slopes = [];
        for b = 1:(numel(breaks) - 1)
            seg = idx_mid((breaks(b) + 1):breaks(b + 1));
            if numel(seg) > 60
                p_seg = polyfit(seg - 1, samples(seg), 1);
                slopes(end + 1) = abs(p_seg(1)); %#ok<AGROW>
            end
        end
        if ~isempty(slopes)
            T_init = 510.0 / median(slopes);
        elseif ~isempty(trig.rising_crossings) && ~isempty(trig.falling_crossings)
            T_init = 2.0 * abs(trig.rising_crossings(1) - trig.falling_crossings(1));
        else
            T_init = 512.0;
        end
    end

    valid_len = sample_amount - trig.trig_idx + 1;
    x_plot = (0:(valid_len - 1))';
    y_plot = samples(trig.trig_idx:end);

    % Modelo triangular contínuo em [0, 255]
    tri_wave_fn = @(t_vec, T_p, ph_0) 255.0 * (1.0 - abs(1.0 - 2.0 * mod(t_vec / T_p + ph_0, 1.0)));

    % Fase inicial teórica pelo nível de trigger na borda de subida
    ph_trig = (trig.trig_level / 255.0) * 0.5;

    if strcmpi(align_mode, "trig") && (~isempty(trig.rising_crossings) && numel(periods_est) >= 1)
        period_samples = T_init;
        ph_opt = ph_trig;
    elseif strcmpi(align_mode, "trig")
        period_samples = T_init;
        ph_opt = ph_trig;
    else
        % Busca em grade para a fase inicial + refinamento conjunto [período, fase]
        ph_grid = linspace(0, 1, 241);
        ph_grid(end) = [];
        best_mse = inf;
        best_ph = ph_trig;
        for ph_cand = ph_grid
            y_cand = tri_wave_fn(x_plot, T_init, ph_cand);
            mse_cand = mean((y_plot - y_cand) .^ 2);
            if mse_cand < best_mse
                best_mse = mse_cand;
                best_ph = ph_cand;
            end
        end

        cost_fn = @(u) mean((y_plot - tri_wave_fn(x_plot, T_init * exp(u(1)), best_ph + u(2))) .^ 2);
        opts = optimset("TolX", 1e-6, "TolFun", 1e-6, "MaxIter", 400, "Display", "off");
        u_opt = fminsearch(cost_fn, [0, 0], opts);
        if abs(u_opt(1)) < 0.08
            period_samples = T_init * exp(u_opt(1));
            ph_opt = mod(best_ph + u_opt(2), 1.0);
        else
            period_samples = T_init;
            ph_opt = best_ph;
        end
    end

    period_sec = period_samples / actual_sampling_frequency;
    freq_hz = actual_sampling_frequency / period_samples;

    per = struct();
    per.period_samples = period_samples;
    per.period_sec = period_sec;
    per.freq_hz = freq_hz;
    per.signal_frequency = freq_hz;
    per.ph_opt = ph_opt;
    per.x_plot = x_plot;
    per.y_plot = y_plot;
end
