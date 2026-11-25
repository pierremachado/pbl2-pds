function lin = computeHistogramLinearity(samples, trig, per, ref, wave_type)
    % =========================================================================
    % COMPUTEHISTOGRAMLINEARITY - Cálculo de DNL, INL, Missing Codes e Monotonicidade
    %
    % Adapta o método de histograma à forma de onda selecionada:
    %   - Triangular / Dente de Serra ("uniform"): PDF uniforme em [0, 255].
    %   - Senoidal ("sine"): Método de Histograma Senoidal (IEEE Std 1241),
    %     calculando os níveis de transição via -cos(pi * C(k) / N).
    %   - Quadrada ("none"): Não aplicável (não excita códigos intermediários).
    % =========================================================================

    if nargin < 5 || isempty(wave_type)
        if isfield(ref, "wave_type") && ~isempty(ref.wave_type)
            wave_type = ref.wave_type;
        else
            wave_type = "triangular";
        end
    end

    wspec = getWaveformSpec(wave_type);

    samples = double(samples(:));
    sample_amount = numel(samples);
    period_samples = per.period_samples;
    y_plot = per.y_plot;
    ideal_quant_plot = ref.ideal_quant_plot;

    codes_axis = (0:255)';
    num_full_cycles = floor(sample_amount / period_samples);
    if num_full_cycles >= 1
        n_int_samples = min(sample_amount, max(256, round(num_full_cycles * period_samples)));
        samples_for_hist = samples(1:n_int_samples);
        k_min = max(0, round(trig.s_min));
        k_max = min(255, round(trig.s_max));
    elseif strcmp(wspec.hist_mode, "uniform")
        % Se há menos de 1 ciclo completo de rampa, extrai a maior rampa entre mínimo e máximo
        [~, idx_smin] = min(samples);
        [~, idx_smax] = max(samples);
        i_start_ramp = min(idx_smin, idx_smax);
        i_end_ramp   = max(idx_smin, idx_smax);
        samples_for_hist = samples(i_start_ramp:i_end_ramp);
        n_int_samples = numel(samples_for_hist);
        k_min = max(0, round(min(samples_for_hist)));
        k_max = min(255, round(max(samples_for_hist)));
    else
        samples_for_hist = samples;
        n_int_samples = sample_amount;
        k_min = max(0, round(trig.s_min));
        k_max = min(255, round(trig.s_max));
    end

    code_counts = histc(round(samples_for_hist), 0:255);
    code_counts = code_counts(:);

    % Curva de transferência empírica (média do ADC por nível ideal quantizado 0..255)
    mean_adc_per_level = nan(256, 1);
    for c = 0:255
        mask_c = (ideal_quant_plot == c);
        if any(mask_c)
            mean_adc_per_level(c + 1) = mean(y_plot(mask_c));
        end
    end

    if strcmp(wspec.hist_mode, "none")
        % Onda quadrada não excita códigos intermediários -> DNL/INL não aplicáveis
        lin = struct();
        lin.is_valid           = false;
        lin.hist_mode          = wspec.hist_mode;
        lin.num_full_cycles    = num_full_cycles;
        lin.n_int_samples      = n_int_samples;
        lin.codes_axis         = codes_axis;
        lin.code_counts        = code_counts;
        lin.expected_hits      = NaN;
        lin.mean_adc_per_level = mean_adc_per_level;
        lin.dnl                = nan(256, 1);
        lin.inl                = nan(256, 1);
        lin.dnl_min            = NaN;
        lin.dnl_max            = NaN;
        lin.dnl_rms            = NaN;
        lin.inl_min            = NaN;
        lin.inl_max            = NaN;
        lin.inl_rms            = NaN;
        lin.missing_codes      = NaN;
        lin.is_monotonic       = false;
        lin.nonmono_codes      = [];
        return;
    end

    inner_idx = (k_min + 2):(k_max); % Índices 1-based para códigos (k_min+1)..(k_max-1)
    dnl = zeros(256, 1);
    inl = zeros(256, 1);

    if numel(inner_idx) >= 4
        expected_hits = mean(code_counts(inner_idx));
        if strcmp(wspec.hist_mode, "sine")
            % Método de Histograma Senoidal (IEEE Std 1241)
            n_tot = sum(code_counts);
            if n_tot > 0
                cum_counts = cumsum(code_counts);
                % Para código c (índice 1-based idx = c + 1):
                % transição inferior usa C(c-1) = cum_counts(idx - 1),
                % transição superior usa C(c)   = cum_counts(idx).
                t_lo = -cos(pi * (cum_counts(inner_idx - 1) / n_tot));
                t_hi = -cos(pi * (cum_counts(inner_idx) / n_tot));
                w_codes = t_hi - t_lo;
                w_avg = mean(w_codes);
                if w_avg > 0
                    dnl(inner_idx) = (w_codes / w_avg) - 1.0;
                    dnl_zero_mean = dnl(inner_idx) - mean(dnl(inner_idx));
                    inl(inner_idx) = cumsum(dnl_zero_mean);
                end
            end
        else
            % Histograma uniforme (Triangular e Dente de Serra)
            if expected_hits > 0
                dnl(inner_idx) = (code_counts(inner_idx) / expected_hits) - 1.0;
                dnl_zero_mean = dnl(inner_idx) - mean(dnl(inner_idx));
                inl(inner_idx) = cumsum(dnl_zero_mean);
            end
        end
        missing_codes = sum(code_counts(inner_idx) == 0);
    else
        expected_hits = 0;
        missing_codes = 0;
    end

    valid_curve = find(~isnan(mean_adc_per_level));
    nonmono_codes = [];
    if numel(valid_curve) >= 4
        diffs_curve = diff(mean_adc_per_level(valid_curve));
        inv_pos = find(diffs_curve < -0.5);
        if ~isempty(inv_pos)
            nonmono_codes = valid_curve(inv_pos + 1) - 1;
        end
    end

    is_monotonic = isempty(nonmono_codes) && (missing_codes == 0);
    [dnl_max, ~] = max(dnl);
    [dnl_min, ~] = min(dnl);
    [inl_max, ~] = max(inl);
    [inl_min, ~] = min(inl);

    if ~isempty(inner_idx)
        dnl_rms = sqrt(mean(dnl(inner_idx) .^ 2));
        inl_rms = sqrt(mean(inl(inner_idx) .^ 2));
    else
        dnl_rms = 0;
        inl_rms = 0;
    end

    lin = struct();
    lin.is_valid           = true;
    lin.hist_mode          = wspec.hist_mode;
    lin.num_full_cycles    = num_full_cycles;
    lin.n_int_samples      = n_int_samples;
    lin.codes_axis         = codes_axis;
    lin.code_counts        = code_counts;
    lin.expected_hits      = expected_hits;
    lin.mean_adc_per_level = mean_adc_per_level;
    lin.dnl                = dnl;
    lin.inl                = inl;
    lin.dnl_min            = dnl_min;
    lin.dnl_max            = dnl_max;
    lin.dnl_rms            = dnl_rms;
    lin.inl_min            = inl_min;
    lin.inl_max            = inl_max;
    lin.inl_rms            = inl_rms;
    lin.missing_codes      = missing_codes;
    lin.is_monotonic       = is_monotonic;
    lin.nonmono_codes      = nonmono_codes;
end
