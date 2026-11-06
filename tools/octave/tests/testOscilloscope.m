% Execute da raiz: octave --no-gui --quiet tools/octave/tests/testOscilloscope.m
base = fileparts(fileparts(mfilename("fullpath")));
addpath(genpath(fullfile(base, "src")));
N = 4096;
fs = 8192;
n = (0:(N - 1))';

% A rampa lenta não produz cruzamentos no detector atual: a fase deve ser ajustada.
samples = 255 * (1 - abs(1 - 2 * mod(n / (fs / 5), 1)));
trig = detectSignalTrigger(samples);
assert(isempty(trig.rising_crossings));
for mode = {"trig", "opt"}
    per = estimateSignalPeriod(samples, fs, trig, mode{1});
    ref = generateIdealReference(samples, trig, per, 2.56);
    assert(abs(per.freq_hz - 5) < 0.001);
    assert(sqrt(mean((per.y_plot - ref.ideal_cont_plot).^2)) < 0.01);
end

% Compensação da posição fracionária do trigger em uma triangular mais rápida.
samples = 255 * (1 - abs(1 - 2 * mod(n / (fs / 64) + 0.013, 1)));
trig = detectSignalTrigger(samples);
assert(~isempty(trig.rising_crossings));
per = estimateSignalPeriod(samples, fs, trig, "trig");
ref = generateIdealReference(samples, trig, per, 2.56);
assert(sqrt(mean((per.y_plot - ref.ideal_cont_plot).^2)) < 0.01);

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
disp("Testes do osciloscópio passaram.");
