% Execute da raiz: octave --no-gui --quiet tools/octave/tests/testOscilloscope.m
base = fileparts(fileparts(mfilename("fullpath")));
addpath(base);
addpath(genpath(fullfile(base, "src")));
addpath(fullfile(base, "utils"));
N = 4096;
fs = 8192;
n = (0:(N - 1))';

% 1. Triangular lenta (5 Hz @ 8192 Hz, T = 1638.4 am): Schmitt trigger deve detectar bordas.
w_tri = getWaveformSpec("triangular");
samples = w_tri.eval_fn(n, fs / 5, 0);
trig = detectSignalTrigger(samples);
assert(~isempty(trig.rising_crossings));
assert(numel(trig.rising_crossings) == 3);
for mode = {"trig", "opt"}
    per = estimateSignalPeriod(samples, fs, trig, mode{1}, "triangular");
    ref = generateIdealReference(samples, trig, per, "triangular");
    assert(abs(per.freq_hz - 5) < 0.001);
    assert(sqrt(mean((per.y_plot - ref.ideal_cont_plot).^2)) < 0.01);
end

% 1b. Sem cruzamento de subida (rampa de descida): fallback deve ajustar período e fase.
samples_fall = w_tri.eval_fn(n, 2 * N, 0.55);
trig_fall = detectSignalTrigger(samples_fall);
assert(isempty(trig_fall.rising_crossings));
for mode = {"trig", "opt"}
    per = estimateSignalPeriod(samples_fall, fs, trig_fall, mode{1}, "triangular");
    ref = generateIdealReference(samples_fall, trig_fall, per, "triangular");
    assert(abs(per.period_samples - 2 * N) / (2 * N) < 0.005);
    assert(sqrt(mean((per.y_plot - ref.ideal_cont_plot).^2)) < 0.5);
end

% 2. Compensação da posição fracionária do trigger em uma triangular mais rápida.
samples = w_tri.eval_fn(n, fs / 64, 0.013);
trig = detectSignalTrigger(samples);
assert(~isempty(trig.rising_crossings));
per = estimateSignalPeriod(samples, fs, trig, "trig", "triangular");
ref = generateIdealReference(samples, trig, per, "triangular");
assert(sqrt(mean((per.y_plot - ref.ideal_cont_plot).^2)) < 0.01);

% 3. Testes multi-forma de onda (senoidal, dente de serra e quadrada)
lsb_mv_5v = (5.0 / 256.0) * 1e3;

% 3a. Senoidal quantizada (8 bits): frequência, referência, FFT e histograma senoidal
samples_sin = round(127.5 * (1 + sin(2 * pi * (n / (fs / 32) + 0.07))));
trig_s = detectSignalTrigger(samples_sin);
per_s  = estimateSignalPeriod(samples_sin, fs, trig_s, "opt", "sine");
ref_s  = generateIdealReference(samples_sin, trig_s, per_s, "sine");
err_s  = computeStaticAndTimeErrors(samples_sin, trig_s, per_s, ref_s, lsb_mv_5v, "sine");
spec_s = computeSpectralMetrics(samples_sin, fs, ref_s, "sine");
lin_s  = computeHistogramLinearity(samples_sin, trig_s, per_s, ref_s, "sine");
assert(abs(per_s.freq_hz - 32) < 0.05);
assert(err_s.rmse_lsb < 0.5);
assert(abs(err_s.rmse_mv - err_s.rmse_lsb * lsb_mv_5v) < 1e-9);
assert(lin_s.is_valid && strcmp(lin_s.hist_mode, "sine"));
assert(isnan(lin_s.dnl(1)) && isnan(lin_s.dnl(256)));
assert(abs(spec_s.fund_freq_fft - 32) < 0.5);
assert(abs(spec_s.fund_mag_db) < 0.2);
assert(abs(spec_s.fund_mag_lin - 127.5) < 1.5);
assert(strcmp(spec_s.window_type, "hanning") && strcmp(spec_s.window_label, "Hanning"));
assert(~isfield(spec_s, "enob_bits") && ~isfield(spec_s, "sinad_db") && ~isfield(spec_s, "thd_db") && ~isfield(spec_s, "dr_db"));
assert(~isfield(spec_s, "mag_pct") && ~isfield(spec_s, "mag_dbfs"));

% 3b. Dente de serra quantizada (8 bits): frequência, referência e histograma uniforme
samples_saw = round(255 * mod(n / (fs / 16) + 0.11, 1));
trig_w = detectSignalTrigger(samples_saw);
per_w  = estimateSignalPeriod(samples_saw, fs, trig_w, "opt", "sawtooth");
ref_w  = generateIdealReference(samples_saw, trig_w, per_w, "sawtooth");
err_w  = computeStaticAndTimeErrors(samples_saw, trig_w, per_w, ref_w, lsb_mv_5v, "sawtooth");
lin_w  = computeHistogramLinearity(samples_saw, trig_w, per_w, ref_w, "sawtooth");
assert(abs(per_w.freq_hz - 16) < 0.1);
assert(err_w.rmse_intrinsic_lsb < 0.5);
assert(lin_w.is_valid && strcmp(lin_w.hist_mode, "uniform"));

% 3c. Quadrada (8 bits): frequência, platôs de ganho/offset e linearidade marcada como N/A
samples_sq = 255 * double(mod(n / (fs / 32) + 0.15, 1) < 0.5);
trig_q = detectSignalTrigger(samples_sq);
per_q  = estimateSignalPeriod(samples_sq, fs, trig_q, "opt", "square");
ref_q  = generateIdealReference(samples_sq, trig_q, per_q, "square");
err_q  = computeStaticAndTimeErrors(samples_sq, trig_q, per_q, ref_q, lsb_mv_5v, "square");
lin_q  = computeHistogramLinearity(samples_sq, trig_q, per_q, ref_q, "square");
assert(abs(per_q.freq_hz - 32) < 0.2);
assert(abs(err_q.measured_gain - 1.0) < 0.01);
assert(~lin_q.is_valid && strcmp(lin_q.hist_mode, "none"));

% 3d. Monotonicidade desacoplada de missing codes e NaN fora da faixa medida
samples_tri_q = round(w_tri.eval_fn(n, 813.06, 0));
samples_miss = samples_tri_q;
samples_miss(samples_miss == 100) = 101;
trig_m = detectSignalTrigger(samples_miss);
per_m  = estimateSignalPeriod(samples_miss, fs, trig_m, "opt", "triangular");
ref_m  = generateIdealReference(samples_miss, trig_m, per_m, "triangular");
lin_m  = computeHistogramLinearity(samples_miss, trig_m, per_m, ref_m, "triangular");
assert(isnan(lin_m.dnl(1)) && isnan(lin_m.dnl(256)));
assert(isnan(lin_m.inl(1)) && isnan(lin_m.inl(256)));
assert(lin_m.missing_codes == 1 && lin_m.is_monotonic);

% 4. Espectro unilateral (dB e amplitude linear em LSB): Nyquist, N ímpar, DC e 4 janelas
spec = computeOscilloscopeSpectrum(127.5 + 127.5 * (-1).^n, fs);
assert(abs(spec.mag_db(end)) < 1e-9);
assert(abs(spec.mag_lin(end) - 127.5) < 1e-6);
spec = computeOscilloscopeSpectrum(127.5 + 127.5 * sin(2*pi*64*n/N), fs);
assert(abs(spec.peak_db) < 0.001);
assert(abs(spec.peak_lin - 127.5) < 0.02);
assert(spec.peak_frequency == 128);
n_odd = (0:4094)';
spec = computeOscilloscopeSpectrum(127.5 + 127.5*cos(2*pi*100*n_odd/4095), fs);
assert(abs(spec.peak_db) < 0.001);
assert(abs(spec.peak_lin - 127.5) < 0.02);
for level = [0, 128, 255]
    spec = computeOscilloscopeSpectrum(level * ones(N, 1), fs);
    assert(isnan(spec.peak_frequency) && isnan(spec.peak_db) && isnan(spec.peak_lin));
end

% 4b. Janelas FFT (retangular, hanning, hamming e blackman): preservação de amplitude e lóbulos
sine_exact = 127.5 + 127.5 * sin(2 * pi * 64 * n / N);
for wname = {"rectangular", "hanning", "hamming", "blackman"}
    sw = computeOscilloscopeSpectrum(sine_exact, fs, wname{1});
    assert(strcmp(sw.window_type, wname{1}));
    assert(abs(sw.peak_db) < 0.01);
    assert(abs(sw.peak_lin - 127.5) < 0.15);
    assert(sw.peak_frequency == 128);
end
sine_leak = 127.5 + 127.5 * sin(2 * pi * 64.5 * n / N);
sw_rect  = computeOscilloscopeSpectrum(sine_leak, fs, "rectangular");
sw_black = computeOscilloscopeSpectrum(sine_leak, fs, "blackman");
assert(mean(sw_black.mag_db(200:400)) < mean(sw_rect.mag_db(200:400)) - 25.0);

% 5. Modo sem comparação de onda ideal ("none"): período/frequência e trigger ativos
per_none = estimateSignalPeriod(samples_sin, fs, trig_s, "trig", "none");
assert(strcmp(per_none.wave_type, "none"));
assert(abs(per_none.freq_hz - 32) < 0.1);
assert(numel(per_none.x_plot) == N - trig_s.trig_idx + 1);
trig_dc = detectSignalTrigger(128 * ones(N, 1));
per_dc = estimateSignalPeriod(128 * ones(N, 1), fs, trig_dc, "trig", "none");
assert(strcmp(per_dc.wave_type, "none") && isfinite(per_dc.freq_hz));

disp("Todos os testes (triangular, senoidal, dente de serra, quadrada, desligado e FFT) passaram.");
