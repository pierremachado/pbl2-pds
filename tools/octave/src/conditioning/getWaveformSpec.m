function wspec = getWaveformSpec(wave_type)
    % =========================================================================
    % GETWAVEFORMSPEC - Especificação centralizada de formas de onda ideais
    %
    % Normaliza o nome da forma de onda e retorna a função geradora [0, 255],
    % fase inicial de trigger na borda de subida e método de histograma.
    %
    % Formas suportadas:
    %   - "triangular" (padrão)
    %   - "sine"       (aceita "senoidal", "senoide", "sin")
    %   - "sawtooth"   (aceita "dente de serra", "dente_de_serra", "serra", "saw")
    %   - "square"     (aceita "quadrada", "quadrado", "sq")
    % =========================================================================

    if nargin < 1 || isempty(wave_type)
        raw = "triangular";
    else
        raw = lower(strtrim(char(wave_type)));
    end

    if any(strcmp(raw, {"triangular", "tri", "triangle"}))
        wtype = "triangular";
    elseif any(strcmp(raw, {"sine", "sin", "senoidal", "senoide", "seno"}))
        wtype = "sine";
    elseif any(strcmp(raw, {"sawtooth", "saw", "dente de serra", "dente_de_serra", "dente-de-serra", "serra", "rampa"}))
        wtype = "sawtooth";
    elseif any(strcmp(raw, {"square", "sq", "quadrada", "quadrado"}))
        wtype = "square";
    else
        error("Forma de onda não suportada: '%s'. Use 'triangular', 'sine', 'sawtooth' ou 'square'.", raw);
    end

    wspec = struct();
    wspec.type = wtype;

    switch wtype
        case "triangular"
            wspec.label             = "Triangular";
            wspec.short_label       = "Tri.";
            wspec.eval_fn           = @(t_vec, T_p, ph_0) 255.0 * (1.0 - abs(1.0 - 2.0 * mod(t_vec / T_p + ph_0, 1.0)));
            wspec.trig_phase_fn     = @(lvl) max(0.0, min(0.5, (lvl / 255.0) * 0.5));
            wspec.hist_mode         = "uniform";
            wspec.has_discontinuity = false;

        case "sine"
            wspec.label             = "Senoidal";
            wspec.short_label       = "Sen.";
            wspec.eval_fn           = @(t_vec, T_p, ph_0) 127.5 * (1.0 + sin(2.0 * pi * mod(t_vec / T_p + ph_0, 1.0)));
            wspec.trig_phase_fn     = @(lvl) mod(asin(max(-1.0, min(1.0, (lvl - 127.5) / 127.5))) / (2.0 * pi), 1.0);
            wspec.hist_mode         = "sine";
            wspec.has_discontinuity = false;

        case "sawtooth"
            wspec.label             = "Dente de Serra";
            wspec.short_label       = "Serra";
            wspec.eval_fn           = @(t_vec, T_p, ph_0) 255.0 * mod(t_vec / T_p + ph_0, 1.0);
            wspec.trig_phase_fn     = @(lvl) max(0.0, min(1.0, lvl / 255.0));
            wspec.hist_mode         = "uniform";
            wspec.has_discontinuity = true;

        case "square"
            wspec.label             = "Quadrada";
            wspec.short_label       = "Quad.";
            wspec.eval_fn           = @(t_vec, T_p, ph_0) 255.0 * double(mod(t_vec / T_p + ph_0, 1.0) < 0.5);
            wspec.trig_phase_fn     = @(lvl) 0.0;
            wspec.hist_mode         = "none";
            wspec.has_discontinuity = true;
    end
end
