function err = computeStaticAndTimeErrors(samples, trig, per, ref, LSB_MV)
    % =========================================================================
    % COMPUTESTATICANDTIMEERRORS - Cálculo de Offset, Ganho e Erros no Tempo
    %
    % Calcula:
    %   - Ganho medido, intercepto, erro de offset e erro de ganho (LSB, mV, %FSR)
    %   - Vetores de erro ponto-a-ponto (bruto, quantizado, intrínseco sem
    %     ganho/offset e erro teórico puro de quantização de 8 bits)
    %   - Métricas escalares: RMSE bruto, RMSE intrínseco, MAE, Erro Máximo,
    %     Erro Relativo ao fundo de escala (%FSR) e MAPE (% do sinal).
    % =========================================================================

    if nargin < 5 || isempty(LSB_MV)
        LSB_MV = 10.0;
    end

    y_plot = per.y_plot;
    valid_len = numel(y_plot);
    ideal_cont_plot = ref.ideal_cont_plot;
    ideal_quant_plot = ref.ideal_quant_plot;

    % Regressão linear na faixa central livre de saturação das pontas
    lin_mask = (ideal_cont_plot >= 10) & (ideal_cont_plot <= 245) & (y_plot > 0) & (y_plot < 255);
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
        offset_error_lsb = mean(samples) - 127.5;
        gain_error_lsb   = trig.s_vpp - 255.0;
    end
    offset_error_pct = (offset_error_lsb / 255.0) * 100.0;
    gain_error_pct   = (gain_error_lsb / 255.0) * 100.0;
    offset_error_mv  = offset_error_lsb * LSB_MV;
    gain_error_mv    = gain_error_lsb * LSB_MV;

    % Vetores de erro ponto-a-ponto
    err_vs_cont_lsb  = y_plot - ideal_cont_plot;
    abs_err_cont_lsb = abs(err_vs_cont_lsb);

    err_vs_quant_lsb  = y_plot - ideal_quant_plot;

    ideal_bestfit_plot = min(255, max(0, measured_gain * ideal_cont_plot + intercept_lsb));
    err_intrinsic_lsb  = y_plot - ideal_bestfit_plot;

    err_ideal_quant_lsb = ideal_quant_plot - ideal_cont_plot;

    % Métricas escalares de Erro Absoluto, RMSE e Erro Relativo
    rmse_lsb           = sqrt(mean(err_vs_cont_lsb .^ 2));
    rmse_mv            = rmse_lsb * LSB_MV;
    rmse_pct_fsr       = (rmse_lsb / 255.0) * 100.0;

    rmse_vs_quant_lsb  = sqrt(mean(err_vs_quant_lsb .^ 2));
    rmse_intrinsic_lsb = sqrt(mean(err_intrinsic_lsb .^ 2));
    rmse_intrinsic_mv  = rmse_intrinsic_lsb * LSB_MV;
    rmse_intrinsic_pct = (rmse_intrinsic_lsb / 255.0) * 100.0;

    mae_lsb            = mean(abs_err_cont_lsb);
    mae_mv             = mae_lsb * LSB_MV;
    mae_pct_fsr        = (mae_lsb / 255.0) * 100.0;

    max_abs_err_lsb     = max(abs_err_cont_lsb);
    max_abs_err_mv      = max_abs_err_lsb * LSB_MV;
    max_abs_err_pct_fsr = (max_abs_err_lsb / 255.0) * 100.0;

    % Erro relativo ponto-a-ponto (% do valor instantâneo do sinal ideal, para ideal >= 5% FSR)
    rel_valid_mask = (ideal_cont_plot >= 12.75);
    rel_err_instant_pct = nan(valid_len, 1);
    rel_err_instant_pct(rel_valid_mask) = (abs_err_cont_lsb(rel_valid_mask) ./ ideal_cont_plot(rel_valid_mask)) * 100.0;
    mape_signal_pct    = mean(rel_err_instant_pct(rel_valid_mask));
    median_rel_err_pct = median(rel_err_instant_pct(rel_valid_mask));

    rel_err_fsr_pct = (err_vs_cont_lsb / 255.0) * 100.0;

    err = struct();
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
    err.err_vs_quant_lsb    = err_vs_quant_lsb;
    err.err_intrinsic_lsb   = err_intrinsic_lsb;
    err.err_ideal_quant_lsb = err_ideal_quant_lsb;
    err.abs_err_cont_lsb    = abs_err_cont_lsb;
    err.rel_err_fsr_pct     = rel_err_fsr_pct;
    err.rel_err_instant_pct = rel_err_instant_pct;
    err.rmse_lsb            = rmse_lsb;
    err.rmse_mv             = rmse_mv;
    err.rmse_pct_fsr        = rmse_pct_fsr;
    err.rmse_vs_quant_lsb   = rmse_vs_quant_lsb;
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
    err.median_rel_err_pct  = median_rel_err_pct;
end
