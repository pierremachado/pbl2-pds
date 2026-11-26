function err = computeStaticAndTimeErrors(samples, trig, per, ref, LSB_MV, wave_type)
    % =========================================================================
    % COMPUTESTATICANDTIMEERRORS - Cálculo de Offset, Ganho e Erros no Tempo
    %
    % Calcula:
    %   - Ganho medido, intercepto, erro de offset e erro de ganho (LSB, mV, %FSR)
    %   - Vetores de erro ponto-a-ponto (bruto e intrínseco sem ganho/offset)
    %   - Métricas escalares: RMSE bruto, RMSE intrínseco, MAE, Erro Máximo,
    %     Erro Relativo ao fundo de escala (%FSR = 256 LSB) e MAPE (% do sinal).
    %
    % Adaptado por forma de onda:
    %   - Para quadrada: estima ganho/offset pelas medianas dos platôs alto/baixo.
    %   - Para serra/quadrada: aplica banda de guarda de +-2 amostras nas
    %     transições abruptas para o cálculo de RMSE intrínseco e regressão.
    % =========================================================================

    if nargin < 5 || isempty(LSB_MV)
        LSB_MV = (5.0 / 256.0) * 1e3;
    end
    if nargin < 6 || isempty(wave_type)
        if isfield(ref, "wave_type") && ~isempty(ref.wave_type)
            wave_type = ref.wave_type;
        else
            wave_type = "triangular";
        end
    end

    wspec = getWaveformSpec(wave_type);

    y_plot = per.y_plot;
    valid_len = numel(y_plot);
    ideal_cont_plot = ref.ideal_cont_plot;

    % Máscara de regime estável (exclui +-2 amostras em torno de saltos abruptos)
    steady_mask = true(valid_len, 1);
    if wspec.has_discontinuity && valid_len >= 5
        jump_idx = find(abs(diff(ideal_cont_plot)) > 128.0);
        for j = 1:numel(jump_idx)
            k0 = max(1, jump_idx(j) - 2);
            k1 = min(valid_len, jump_idx(j) + 3);
            steady_mask(k0:k1) = false;
        end
    end

    if strcmp(wspec.type, "square")
        % Estimativa robusta pelos platôs alto e baixo (evita viés de overshoot)
        low_mask  = steady_mask & (ideal_cont_plot < 127.5);
        high_mask = steady_mask & (ideal_cont_plot >= 127.5);
        if sum(low_mask) >= 5 && sum(high_mask) >= 5
            low_val  = median(y_plot(low_mask));
            high_val = median(y_plot(high_mask));
            measured_gain    = (high_val - low_val) / 255.0;
            intercept_lsb    = low_val;
            offset_error_lsb = (measured_gain * 127.5 + intercept_lsb) - 127.5;
            gain_error_lsb   = (measured_gain - 1.0) * 255.0;
        else
            measured_gain    = trig.s_vpp / 255.0;
            intercept_lsb    = mean(y_plot) - measured_gain * 127.5;
            offset_error_lsb = mean(y_plot) - 127.5;
            gain_error_lsb   = trig.s_vpp - 255.0;
        end
    else
        % Regressão linear na faixa central livre de saturação das pontas
        lin_mask = steady_mask & (ideal_cont_plot >= 10) & (ideal_cont_plot <= 245) & (y_plot > 0) & (y_plot < 255);
        if sum(lin_mask) >= 20
            x_lin = ideal_cont_plot(lin_mask);
            y_lin = y_plot(lin_mask);
            x_mean = mean(x_lin);
            y_mean = mean(y_lin);
            measured_gain = sum((x_lin - x_mean) .* (y_lin - y_mean)) / max(1e-9, sum((x_lin - x_mean) .^ 2));
            intercept_lsb = y_mean - measured_gain * x_mean;
            offset_error_lsb = (measured_gain * 127.5 + intercept_lsb) - 127.5;
            gain_error_lsb   = (measured_gain - 1.0) * 255.0;
        else
            measured_gain    = trig.s_vpp / 255.0;
            intercept_lsb    = mean(y_plot) - measured_gain * 127.5;
            offset_error_lsb = mean(y_plot) - 127.5;
            gain_error_lsb   = trig.s_vpp - 255.0;
        end
    end

    offset_error_pct = (offset_error_lsb / 256.0) * 100.0;
    gain_error_pct   = (gain_error_lsb / 256.0) * 100.0;
    offset_error_mv  = offset_error_lsb * LSB_MV;
    gain_error_mv    = gain_error_lsb * LSB_MV;

    % Vetores de erro ponto-a-ponto
    err_vs_cont_lsb  = y_plot - ideal_cont_plot;
    abs_err_cont_lsb = abs(err_vs_cont_lsb);

    ideal_bestfit_plot = min(255, max(0, measured_gain * ideal_cont_plot + intercept_lsb));
    err_intrinsic_lsb  = y_plot - ideal_bestfit_plot;

    % Métricas escalares de Erro Absoluto, RMSE e Erro Relativo (%FSR = 1 LSB / 256)
    rmse_lsb           = sqrt(mean(err_vs_cont_lsb .^ 2));
    rmse_mv            = rmse_lsb * LSB_MV;
    rmse_pct_fsr       = (rmse_lsb / 256.0) * 100.0;

    if sum(steady_mask) >= 20
        rmse_intrinsic_lsb = sqrt(mean(err_intrinsic_lsb(steady_mask) .^ 2));
    else
        rmse_intrinsic_lsb = sqrt(mean(err_intrinsic_lsb .^ 2));
    end
    rmse_intrinsic_mv  = rmse_intrinsic_lsb * LSB_MV;
    rmse_intrinsic_pct = (rmse_intrinsic_lsb / 256.0) * 100.0;

    mae_lsb            = mean(abs_err_cont_lsb);
    mae_mv             = mae_lsb * LSB_MV;
    mae_pct_fsr        = (mae_lsb / 256.0) * 100.0;

    max_abs_err_lsb     = max(abs_err_cont_lsb);
    max_abs_err_mv      = max_abs_err_lsb * LSB_MV;
    max_abs_err_pct_fsr = (max_abs_err_lsb / 256.0) * 100.0;

    % MAPE (% do valor instantâneo do sinal ideal, para ideal >= 5% FSR)
    rel_valid_mask = steady_mask & (ideal_cont_plot >= 12.8);
    if any(rel_valid_mask)
        mape_signal_pct = mean((abs_err_cont_lsb(rel_valid_mask) ./ ideal_cont_plot(rel_valid_mask)) * 100.0);
    else
        mape_signal_pct = NaN;
    end

    err = struct();
    err.steady_mask         = steady_mask;
    err.measured_gain       = measured_gain;
    err.intercept_lsb       = intercept_lsb;
    err.offset_error_lsb    = offset_error_lsb;
    err.offset_error_mv     = offset_error_mv;
    err.offset_error_pct    = offset_error_pct;
    err.gain_error_lsb      = gain_error_lsb;
    err.gain_error_mv       = gain_error_mv;
    err.gain_error_pct      = gain_error_pct;
    err.ideal_bestfit_plot  = ideal_bestfit_plot;
    err.err_vs_cont_lsb     = err_vs_cont_lsb;
    err.err_intrinsic_lsb   = err_intrinsic_lsb;
    err.rmse_lsb            = rmse_lsb;
    err.rmse_mv             = rmse_mv;
    err.rmse_pct_fsr        = rmse_pct_fsr;
    err.rmse_intrinsic_lsb  = rmse_intrinsic_lsb;
    err.rmse_intrinsic_mv   = rmse_intrinsic_mv;
    err.rmse_intrinsic_pct  = rmse_intrinsic_pct;
    err.mae_lsb             = mae_lsb;
    err.mae_mv              = mae_mv;
    err.mae_pct_fsr         = mae_pct_fsr;
    err.max_abs_err_lsb     = max_abs_err_lsb;
    err.max_abs_err_mv      = max_abs_err_mv;
    err.max_abs_err_pct_fsr = max_abs_err_pct_fsr;
    err.mape_signal_pct     = mape_signal_pct;
end
