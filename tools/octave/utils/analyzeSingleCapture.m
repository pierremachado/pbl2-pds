function m = analyzeSingleCapture(mat_path, VREF, LSB_MV, align_mode)
    % =========================================================================
    % ANALYZESINGLECAPTURE - Condiciona os dados e calcula todas as métricas de um .mat
    %
    % Orquestra os módulos de src/ (triggering, conditioning, spectral, linearity)
    % e empacota todos os resultados na estrutura padronizada 'm'.
    % =========================================================================

    if nargin < 2 || isempty(VREF)
        VREF = 2.56;
    end
    if nargin < 3 || isempty(LSB_MV)
        LSB_MV = (VREF / 256.0) * 1e3;
    end
    if nargin < 4 || isempty(align_mode)
        align_mode = "opt";
    end

    raw = load(mat_path);
    [~, fname, fext] = fileparts(mat_path);
    m = struct();
    m.file_name = [fname, fext];
    m.file_path = mat_path;
    m.was_full_format = isfield(raw, "rmse_lsb") && isfield(raw, "dnl") && isfield(raw, "dr_db");

    % 1. Extração das variáveis básicas da captura
    samples = double(raw.samples(:));
    sample_amount = numel(samples);

    if isfield(raw, "sampling_frequency") && ~isempty(raw.sampling_frequency)
        sampling_frequency = double(raw.sampling_frequency);
    elseif isfield(raw, "actual_sampling_frequency")
        sampling_frequency = round(double(raw.actual_sampling_frequency));
    else
        sampling_frequency = 8192;
    end

    if isfield(raw, "actual_sampling_frequency") && ~isempty(raw.actual_sampling_frequency)
        actual_sampling_frequency = double(raw.actual_sampling_frequency);
    else
        timer_ticks = floor(16000000 / (8 * sampling_frequency) + 0.5);
        actual_sampling_frequency = 16000000 / (8 * timer_ticks);
    end

    if isfield(raw, "adc_prescaler") && ~isempty(raw.adc_prescaler)
        adc_prescaler = double(raw.adc_prescaler);
    else
        adc_prescaler = 16;
    end

    adc_clock_hz = 16000000 / adc_prescaler;
    conversion_time_us = (13.0 / adc_clock_hz) * 1e6;
    max_theoretical_fs = 16000000 / (14.0 * adc_prescaler + 256.0);

    % 2. Execução encadeada dos módulos de processamento em src/
    trig = detectSignalTrigger(samples);
    per  = estimateSignalPeriod(samples, actual_sampling_frequency, trig, align_mode);
    ref  = generateIdealReference(samples, trig, per, VREF);
    err  = computeStaticAndTimeErrors(samples, trig, per, ref, LSB_MV);
    spec = computeSpectralMetrics(samples, actual_sampling_frequency, per, ref, err, LSB_MV);
    lin  = computeHistogramLinearity(samples, trig, per, ref);

    % 3. Empacotamento unificado na estrutura 'm'
    m.samples            = samples;
    m.x_plot             = per.x_plot;
    m.y_plot             = per.y_plot;
    m.ideal_plot         = ref.ideal_plot;
    m.ideal_cont_plot    = ref.ideal_cont_plot;
    m.ideal_quant_plot   = ref.ideal_quant_plot;
    m.ideal_bestfit_plot = err.ideal_bestfit_plot;
    m.y_volts            = ref.y_volts;
    m.ideal_cont_volts   = ref.ideal_cont_volts;
    m.ideal_quant_volts  = ref.ideal_quant_volts;

    m.signal_frequency          = per.signal_frequency;
    m.sampling_frequency        = sampling_frequency;
    m.actual_sampling_frequency = actual_sampling_frequency;
    m.adc_prescaler             = adc_prescaler;
    m.sample_amount             = sample_amount;
    m.adc_clock_hz              = adc_clock_hz;
    m.conversion_time_us        = conversion_time_us;
    m.max_theoretical_fs        = max_theoretical_fs;

    m.freq_hz         = per.freq_hz;
    m.fund_freq_fft   = spec.fund_freq_fft;
    m.fund_mag_dbfs   = spec.fund_mag_dbfs;
    m.period_sec      = per.period_sec;
    m.period_samples  = per.period_samples;
    m.num_full_cycles = lin.num_full_cycles;
    m.n_int_samples   = lin.n_int_samples;
    m.trig_level      = trig.trig_level;
    m.trig_idx        = trig.trig_idx;
    m.trig_str        = trig.trig_str;

    m.s_min = trig.s_min;
    m.s_max = trig.s_max;
    m.s_vpp = trig.s_vpp;

    m.offset_error_lsb = err.offset_error_lsb;
    m.offset_error_mv  = err.offset_error_mv;
    m.offset_error_pct = err.offset_error_pct;
    m.gain_error_lsb   = err.gain_error_lsb;
    m.gain_error_mv    = err.gain_error_mv;
    m.gain_error_pct   = err.gain_error_pct;
    m.measured_gain    = err.measured_gain;
    m.intercept_lsb    = err.intercept_lsb;

    m.err_vs_cont_lsb     = err.err_vs_cont_lsb;
    m.err_vs_quant_lsb    = err.err_vs_quant_lsb;
    m.err_intrinsic_lsb   = err.err_intrinsic_lsb;
    m.abs_err_cont_lsb    = err.abs_err_cont_lsb;
    m.rel_err_fsr_pct     = err.rel_err_fsr_pct;
    m.rel_err_instant_pct = err.rel_err_instant_pct;

    m.rmse_lsb            = err.rmse_lsb;
    m.rmse_mv             = err.rmse_mv;
    m.rmse_pct_fsr        = err.rmse_pct_fsr;
    m.rmse_vs_quant_lsb   = err.rmse_vs_quant_lsb;
    m.rmse_intrinsic_lsb  = err.rmse_intrinsic_lsb;
    m.rmse_intrinsic_mv   = err.rmse_intrinsic_mv;
    m.rmse_intrinsic_pct  = err.rmse_intrinsic_pct;
    m.mae_lsb             = err.mae_lsb;
    m.mae_mv              = err.mae_mv;
    m.mae_pct_fsr         = err.mae_pct_fsr;
    m.max_abs_err_lsb     = err.max_abs_err_lsb;
    m.max_abs_err_mv      = err.max_abs_err_mv;
    m.max_abs_err_pct_fsr = err.max_abs_err_pct_fsr;
    m.mape_signal_pct     = err.mape_signal_pct;
    m.median_rel_err_pct  = err.median_rel_err_pct;

    m.freq_axis       = spec.freq_axis;
    m.mag_dbfs        = spec.mag_dbfs;
    m.mag_dbfs_quant  = spec.mag_dbfs_quant;
    m.mag_dbfs_tri    = spec.mag_dbfs_tri;
    m.phase_deg       = spec.phase_deg;
    m.phase_deg_quant = spec.phase_deg_quant;
    m.phase_deg_tri   = spec.phase_deg_tri;
    m.sig_bins        = spec.sig_bins;

    m.dr_db                = spec.dr_db;
    m.dr_tri_db            = spec.dr_tri_db;
    m.dr_quant_db          = spec.dr_quant_db;
    m.dr_db_legacy         = spec.dr_db_legacy;
    m.sfdr_dbc             = spec.sfdr_dbc;
    m.sfdr_tri_dbc         = spec.sfdr_tri_dbc;
    m.sinad_db             = spec.sinad_db;
    m.thd_db               = spec.thd_db;
    m.enob_bits            = spec.enob_bits;
    m.sinad_tri_total_db   = spec.sinad_tri_total_db;
    m.sinad_tri_intrin_db  = spec.sinad_tri_intrin_db;
    m.sqnr_ideal_quant_db  = spec.sqnr_ideal_quant_db;
    m.enob_tri_total_bits  = spec.enob_tri_total_bits;
    m.enob_tri_intrin_bits = spec.enob_tri_intrin_bits;
    m.enob_ideal_quant     = spec.enob_ideal_quant;
    m.noise_floor_rms_lsb  = spec.noise_floor_rms_lsb;
    m.noise_floor_rms_mv   = spec.noise_floor_rms_mv;

    m.codes_axis         = lin.codes_axis;
    m.code_counts        = lin.code_counts;
    m.expected_hits      = lin.expected_hits;
    m.mean_adc_per_level = lin.mean_adc_per_level;
    m.dnl                = lin.dnl;
    m.inl                = lin.inl;
    m.dnl_min            = lin.dnl_min;
    m.dnl_max            = lin.dnl_max;
    m.dnl_rms            = lin.dnl_rms;
    m.inl_min            = lin.inl_min;
    m.inl_max            = lin.inl_max;
    m.inl_rms            = lin.inl_rms;
    m.missing_codes      = lin.missing_codes;
    m.is_monotonic       = lin.is_monotonic;
    m.nonmono_codes      = lin.nonmono_codes;
end
