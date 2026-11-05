function lin = computeHistogramLinearity(samples, trig, per, ref)
    % =========================================================================
    % COMPUTEHISTOGRAMLINEARITY - Cálculo de DNL, INL, Missing Codes e Monotonicidade
    %
    % Isola um número inteiro de períodos da onda triangular (ou a maior rampa
    % monotônica caso haja menos de 1 ciclo na janela) e calcula:
    %   - Histograma de códigos digitais (0 a 255)
    %   - Não-Linearidade Diferencial (DNL) e Integral (INL) em LSB
    %   - Quantidade de códigos ausentes (Missing Codes)
    %   - Curva de transferência empírica e verificação de monotonicidade
    % =========================================================================

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
    else
        % Se há menos de 1 ciclo completo, extrai a maior rampa entre mínimo e máximo
        [~, idx_smin] = min(samples);
        [~, idx_smax] = max(samples);
        i_start_ramp = min(idx_smin, idx_smax);
        i_end_ramp   = max(idx_smin, idx_smax);
        samples_for_hist = samples(i_start_ramp:i_end_ramp);
        n_int_samples = numel(samples_for_hist);
        k_min = max(0, round(min(samples_for_hist)));
        k_max = min(255, round(max(samples_for_hist)));
    end

    code_counts = histc(round(samples_for_hist), 0:255);
    code_counts = code_counts(:);
    inner_idx = (k_min + 2):(k_max); % Índices 1-based para códigos (k_min+1)..(k_max-1)

    dnl = zeros(256, 1);
    inl = zeros(256, 1);
    if numel(inner_idx) >= 4
        expected_hits = mean(code_counts(inner_idx));
        if expected_hits > 0
            dnl(inner_idx) = (code_counts(inner_idx) / expected_hits) - 1.0;
            dnl_zero_mean = dnl(inner_idx) - mean(dnl(inner_idx));
            inl(inner_idx) = cumsum(dnl_zero_mean);
        end
        missing_codes = sum(code_counts(inner_idx) == 0);
    else
        expected_hits = 0;
        missing_codes = 0;
    end

    % Curva de transferência empírica (média do ADC por nível ideal quantizado 0..255)
    mean_adc_per_level = nan(256, 1);
    for c = 0:255
        mask_c = (ideal_quant_plot == c);
        if any(mask_c)
            mean_adc_per_level(c + 1) = mean(y_plot(mask_c));
        end
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
