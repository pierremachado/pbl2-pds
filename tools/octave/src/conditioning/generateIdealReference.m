function ref = generateIdealReference(samples, trig, per, VREF, wave_type)
    % =========================================================================
    % GENERATEIDEALREFERENCE - Geração dos sinais ideais de referência
    %
    % Constrói os sinais de referência alinhados ao período e fase medidos
    % para a forma de onda escolhida (triangular, sine, sawtooth ou square):
    %   - ideal_cont_plot: sinal contínuo ideal (0.0 a 255.0)
    %   - ideal_quant_plot: sinal ideal quantizado em 256 níveis (0 a 255)
    %   - ideal_cont_full / ideal_quant_full: versões para o buffer completo
    %   - conversões correspondentes para Volts (com base em VREF)
    % =========================================================================

    if nargin < 4 || isempty(VREF)
        VREF = 2.56;
    end
    if nargin < 5 || isempty(wave_type)
        if isfield(per, "wave_type") && ~isempty(per.wave_type)
            wave_type = per.wave_type;
        else
            wave_type = "triangular";
        end
    end

    wspec = getWaveformSpec(wave_type);
    wave_fn = wspec.eval_fn;

    sample_amount = numel(samples);
    x_plot = per.x_plot;
    y_plot = per.y_plot;
    period_samples = per.period_samples;
    ph_opt = per.ph_opt;

    % Sinais alinhados a partir do índice de trigger (para visualização no tempo)
    ideal_cont_plot  = wave_fn(x_plot, period_samples, ph_opt);
    ideal_quant_plot = min(255, max(0, round(ideal_cont_plot)));

    % Sinais correspondentes para o buffer completo (1..sample_amount) para a FFT
    n_full = (0:(sample_amount - 1))';
    ph_full_0 = mod(ph_opt - (trig.trig_idx - 1) / period_samples, 1.0);
    ideal_cont_full  = wave_fn(n_full, period_samples, ph_full_0);
    ideal_quant_full = min(255, max(0, round(ideal_cont_full)));

    % Conversão para Volts (ex: Vref = 2.56 V -> 1 LSB = 10 mV)
    y_volts           = y_plot * (VREF / 256.0);
    ideal_cont_volts  = ideal_cont_plot * (VREF / 256.0);
    ideal_quant_volts = ideal_quant_plot * (VREF / 256.0);

    ref = struct();
    ref.wave_type         = wspec.type;
    ref.wave_label        = wspec.label;
    ref.ideal_plot        = ideal_cont_plot;
    ref.ideal_cont_plot   = ideal_cont_plot;
    ref.ideal_quant_plot  = ideal_quant_plot;
    ref.ideal_cont_full   = ideal_cont_full;
    ref.ideal_quant_full  = ideal_quant_full;
    ref.y_volts           = y_volts;
    ref.ideal_cont_volts  = ideal_cont_volts;
    ref.ideal_quant_volts = ideal_quant_volts;
end
