function ref = generateIdealReference(samples, trig, per, VREF)
    % =========================================================================
    % GENERATEIDEALREFERENCE - Geração dos sinais ideais de referência
    %
    % Constrói os sinais de referência alinhados ao período e fase medidos:
    %   - ideal_cont_plot: triangular contínuo ideal (0.0 a 255.0)
    %   - ideal_quant_plot: triangular ideal quantizado em 256 níveis (0 a 255)
    %   - ideal_cont_full / ideal_quant_full: versões para o buffer completo
    %   - conversões correspondentes para Volts (com base em VREF)
    % =========================================================================

    if nargin < 4 || isempty(VREF)
        VREF = 2.56;
    end

    sample_amount = numel(samples);
    x_plot = per.x_plot;
    y_plot = per.y_plot;
    period_samples = per.period_samples;
    ph_opt = per.ph_opt;

    tri_wave_fn = @(t_vec, T_p, ph_0) 255.0 * (1.0 - abs(1.0 - 2.0 * mod(t_vec / T_p + ph_0, 1.0)));

    % Sinais alinhados a partir do índice de trigger (para visualização no tempo)
    ideal_cont_plot  = tri_wave_fn(x_plot, period_samples, ph_opt);
    ideal_quant_plot = min(255, max(0, round(ideal_cont_plot)));

    % Sinais correspondentes para o buffer completo (1..sample_amount) para a FFT
    n_full = (0:(sample_amount - 1))';
    ph_full_0 = mod(ph_opt - (trig.trig_idx - 1) / period_samples, 1.0);
    ideal_cont_full  = tri_wave_fn(n_full, period_samples, ph_full_0);
    ideal_quant_full = min(255, max(0, round(ideal_cont_full)));

    % Conversão para Volts (ex: Vref = 2.56 V -> 1 LSB = 10 mV)
    y_volts           = y_plot * (VREF / 256.0);
    ideal_cont_volts  = ideal_cont_plot * (VREF / 256.0);
    ideal_quant_volts = ideal_quant_plot * (VREF / 256.0);

    ref = struct();
    ref.ideal_plot       = ideal_cont_plot;
    ref.ideal_cont_plot  = ideal_cont_plot;
    ref.ideal_quant_plot = ideal_quant_plot;
    ref.ideal_cont_full  = ideal_cont_full;
    ref.ideal_quant_full = ideal_quant_full;
    ref.y_volts           = y_volts;
    ref.ideal_cont_volts  = ideal_cont_volts;
    ref.ideal_quant_volts = ideal_quant_volts;
end
