function saveEnrichedMat(mat_path, m)
    % =========================================================================
    % SAVEENRICHEDMAT - Salva/atualiza o arquivo .mat com todas as métricas do ADC
    % =========================================================================

    samples = m.samples;
    x_plot = m.x_plot;
    y_plot = m.y_plot;
    ideal_plot = m.ideal_plot;
    ideal_quant_plot = m.ideal_quant_plot;
    signal_frequency = m.signal_frequency;
    sampling_frequency = m.sampling_frequency;
    actual_sampling_frequency = m.actual_sampling_frequency;
    adc_prescaler = m.adc_prescaler;
    sample_amount = m.sample_amount;
    freq_hz = m.freq_hz;
    fund_freq_fft = m.fund_freq_fft;
    period_sec = m.period_sec;
    period_samples = m.period_samples;
    trig_level = m.trig_level;
    trig_idx = m.trig_idx;
    s_min = m.s_min;
    s_max = m.s_max;
    s_vpp = m.s_vpp;
    rmse_lsb = m.rmse_lsb;
    rmse_intrinsic_lsb = m.rmse_intrinsic_lsb;
    mae_lsb = m.mae_lsb;
    max_abs_err_lsb = m.max_abs_err_lsb;
    mape_signal_pct = m.mape_signal_pct;
    offset_error_lsb = m.offset_error_lsb;
    offset_error_pct = m.offset_error_pct;
    gain_error_lsb = m.gain_error_lsb;
    gain_error_pct = m.gain_error_pct;
    measured_gain = m.measured_gain;
    freq_axis = m.freq_axis;
    mag_dbfs = m.mag_dbfs;
    mag_dbfs_quant = m.mag_dbfs_quant;
    mag_dbfs_tri = m.mag_dbfs_tri;
    phase_deg = m.phase_deg;
    dr_db = m.dr_db;
    dr_tri_db = m.dr_tri_db;
    sfdr_dbc = m.sfdr_dbc;
    sfdr_tri_dbc = m.sfdr_tri_dbc;
    sinad_db = m.sinad_db;
    sinad_tri_total_db = m.sinad_tri_total_db;
    sinad_tri_intrin_db = m.sinad_tri_intrin_db;
    thd_db = m.thd_db;
    enob_bits = m.enob_bits;
    enob_tri_intrin_bits = m.enob_tri_intrin_bits;
    codes_axis = m.codes_axis;
    code_counts = m.code_counts;
    dnl = m.dnl;
    inl = m.inl;
    dnl_min = m.dnl_min;
    dnl_max = m.dnl_max;
    inl_min = m.inl_min;
    inl_max = m.inl_max;
    missing_codes = m.missing_codes;
    is_monotonic = m.is_monotonic;
    nonmono_codes = m.nonmono_codes;

    save("-v7", mat_path, ...
         "samples", "x_plot", "y_plot", "ideal_plot", "ideal_quant_plot", ...
         "signal_frequency", "sampling_frequency", "actual_sampling_frequency", ...
         "adc_prescaler", "sample_amount", ...
         "freq_hz", "fund_freq_fft", "period_sec", "period_samples", ...
         "trig_level", "trig_idx", ...
         "s_min", "s_max", "s_vpp", "rmse_lsb", "rmse_intrinsic_lsb", ...
         "mae_lsb", "max_abs_err_lsb", "mape_signal_pct", ...
         "offset_error_lsb", "offset_error_pct", ...
         "gain_error_lsb", "gain_error_pct", "measured_gain", ...
         "freq_axis", "mag_dbfs", "mag_dbfs_quant", "mag_dbfs_tri", "phase_deg", ...
         "dr_db", "dr_tri_db", "sfdr_dbc", "sfdr_tri_dbc", ...
         "sinad_db", "sinad_tri_total_db", "sinad_tri_intrin_db", ...
         "thd_db", "enob_bits", "enob_tri_intrin_bits", ...
         "codes_axis", "code_counts", "dnl", "inl", ...
         "dnl_min", "dnl_max", "inl_min", "inl_max", ...
         "missing_codes", "is_monotonic", "nonmono_codes");
end
