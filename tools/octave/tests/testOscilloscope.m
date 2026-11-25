% Execute da raiz: octave --no-gui --quiet tests/testOscilloscope.m
base = fileparts(fileparts(mfilename("fullpath")));
addpath(genpath(fullfile(base, "src")));
N = 4096;
fs = 8192;
n = (0:(N - 1))';

% 1. Triangular lenta (sem cruzamentos no detector): a fase deve ser ajustada.
samples = 255 * (1 - abs(1 - 2 * mod(n / (fs / 5), 1)));
trig = detectSignalTrigger(samples);
assert(isempty(trig.rising_crossings));
for mode = {"trig", "opt"}
    per = estimateSignalPeriod(samples, fs, trig, mode{1}, "triangular");
    ref = generateIdealReference(samples, trig, per, 2.56, "triangular");
    assert(abs(per.freq_hz - 5) < 0.001);
    assert(sqrt(mean((per.y_plot - ref.ideal_cont_plot).^2)) < 0.01);
end

% 2. Compensação da posição fracionária do trigger em uma triangular mais rápida.
samples = 255 * (1 - abs(1 - 2 * mod(n / (fs / 64) + 0.013, 1)));
trig = detectSignalTrigger(samples);
assert(~isempty(trig.rising_crossings));
per = estimateSignalPeriod(samples, fs, trig, "trig", "triangular");
ref = generateIdealReference(samples, trig, per, 2.56, "triangular");
assert(sqrt(mean((per.y_plot - ref.ideal_cont_plot).^2)) < 0.01);

% 3. Testes multi-forma de onda (senoidal, dente de serra e quadrada)
% 3a. Senoidal quantizada (8 bits): frequência, referência, ENOB ~8b e histograma IEEE 1241
samples_sin = round(127.5 * (1 + sin(2 * pi * (n / (fs / 32) + 0.07))));
trig_s = detectSignalTrigger(samples_sin);
per_s  = estimateSignalPeriod(samples_sin, fs, trig_s, "opt", "sine");
ref_s  = generateIdealReference(samples_sin, trig_s, per_s, 2.56, "sine");
err_s  = computeStaticAndTimeErrors(samples_sin, trig_s, per_s, ref_s, 10.0, "sine");
spec_s = computeSpectralMetrics(samples_sin, fs, per_s, ref_s, err_s, 10.0, "sine");
lin_s  = computeHistogramLinearity(samples_sin, trig_s, per_s, ref_s, "sine");
assert(abs(per_s.freq_hz - 32) < 0.05);
assert(err_s.rmse_lsb < 0.5);
assert(lin_s.is_valid && strcmp(lin_s.hist_mode, "sine"));
assert(spec_s.enob_wave_intrin_bits > 7.5);

% 3b. Dente de serra quantizada (8 bits): frequência, referência e histograma uniforme
samples_saw = round(255 * mod(n / (fs / 16) + 0.11, 1));
trig_w = detectSignalTrigger(samples_saw);
per_w  = estimateSignalPeriod(samples_saw, fs, trig_w, "opt", "sawtooth");
ref_w  = generateIdealReference(samples_saw, trig_w, per_w, 2.56, "sawtooth");
err_w  = computeStaticAndTimeErrors(samples_saw, trig_w, per_w, ref_w, 10.0, "sawtooth");
lin_w  = computeHistogramLinearity(samples_saw, trig_w, per_w, ref_w, "sawtooth");
assert(abs(per_w.freq_hz - 16) < 0.1);
assert(err_w.rmse_intrinsic_lsb < 0.5);
assert(lin_w.is_valid && strcmp(lin_w.hist_mode, "uniform"));

% 3c. Quadrada (8 bits): frequência, platôs de ganho/offset e linearidade marcada como N/A
samples_sq = 255 * double(mod(n / (fs / 32) + 0.15, 1) < 0.5);
trig_q = detectSignalTrigger(samples_sq);
per_q  = estimateSignalPeriod(samples_sq, fs, trig_q, "opt", "square");
ref_q  = generateIdealReference(samples_sq, trig_q, per_q, 2.56, "square");
err_q  = computeStaticAndTimeErrors(samples_sq, trig_q, per_q, ref_q, 10.0, "square");
lin_q  = computeHistogramLinearity(samples_sq, trig_q, per_q, ref_q, "square");
assert(abs(per_q.freq_hz - 32) < 0.2);
assert(abs(err_q.measured_gain - 1.0) < 0.01);
assert(~lin_q.is_valid && strcmp(lin_q.hist_mode, "none"));

% 4. Espectro rápido do osciloscópio
% Nyquist tem amplitude de escala cheia; os bins internos continuam dobrados.
spec = computeOscilloscopeSpectrum(127.5 + 127.5 * (-1).^n, fs);
assert(abs(spec.mag_dbfs(end)) < 1e-9);
spec = computeOscilloscopeSpectrum(127.5 + 127.5 * sin(2*pi*64*n/N), fs);
assert(abs(spec.peak_dbfs) < 0.001);
assert(spec.peak_frequency == 128);
% Comprimento ímpar: o último bin ainda tem par de frequência negativa.
n_odd = (0:4094)';
spec = computeOscilloscopeSpectrum(127.5 + 127.5*cos(2*pi*100*n_odd/4095), fs);
assert(abs(spec.peak_dbfs) < 0.001);
for level = [0, 128, 255]
    spec = computeOscilloscopeSpectrum(level * ones(N, 1), fs);
    assert(isnan(spec.peak_frequency) && isnan(spec.peak_dbfs));
end

% 5. Modo sem comparação de onda ideal ("none"): período/frequência e trigger ativos
per_none = estimateSignalPeriod(samples_sin, fs, trig_s, "trig", "none");
assert(strcmp(per_none.wave_type, "none"));
assert(abs(per_none.freq_hz - 32) < 0.1);
assert(numel(per_none.x_plot) == N - trig_s.trig_idx + 1);
trig_dc = detectSignalTrigger(128 * ones(N, 1));
per_dc = estimateSignalPeriod(128 * ones(N, 1), fs, trig_dc, "trig", "none");
assert(strcmp(per_dc.wave_type, "none") && isfinite(per_dc.freq_hz));

disp("Todos os testes (triangular, senoidal, dente de serra, quadrada, desligado e FFT) passaram.");
