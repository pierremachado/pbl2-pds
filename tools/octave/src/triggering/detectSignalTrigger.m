function trig = detectSignalTrigger(samples)
    % =========================================================================
    % DETECTSIGNALTRIGGER - Detecção automática de extremos e trigger com histerese
    %
    % Calcula o valor mínimo, máximo e pico-a-pico das amostras do ADC, define
    % o nível de trigger automático em 50% da excursão (ou 127.5 se o sinal for
    % muito pequeno) com histerese proporcional, e localiza todos os cruzamentos
    % de borda de subida e descida com interpolação linear sub-amostra.
    % =========================================================================

    samples = double(samples(:));
    sample_amount = numel(samples);

    s_min = min(samples);
    s_max = max(samples);
    s_vpp = s_max - s_min;

    if s_vpp >= 6
        trig_level = 0.5 * (s_max + s_min);
        hyst = max(2, 0.08 * s_vpp);
    else
        trig_level = 127.5;
        hyst = 2;
    end

    rising_crossings = [];
    falling_crossings = [];
    state = 0;
    if samples(1) < (trig_level - hyst)
        state = -1;
    elseif samples(1) > (trig_level + hyst)
        state = 1;
    end

    for k = 2:sample_amount
        if state <= 0 && samples(k - 1) < trig_level && samples(k) >= trig_level
            if any(samples(max(1, k - 60):(k - 1)) < (trig_level - hyst))
                frac = (trig_level - samples(k - 1)) / max(1e-6, (samples(k) - samples(k - 1)));
                rising_crossings(end + 1) = (k - 1) + frac; %#ok<AGROW>
                state = 1;
            end
        elseif state >= 0 && samples(k - 1) > trig_level && samples(k) <= trig_level
            if any(samples(max(1, k - 60):(k - 1)) > (trig_level + hyst))
                frac = (samples(k - 1) - trig_level) / max(1e-6, (samples(k - 1) - samples(k)));
                falling_crossings(end + 1) = (k - 1) + frac; %#ok<AGROW>
                state = -1;
            end
        end
    end

    if ~isempty(rising_crossings)
        trig_idx = max(1, round(rising_crossings(1)));
        trig_str = "AUTO (Travado)";
    else
        trig_idx = 1;
        trig_str = "AUTO (Livre)";
    end

    trig = struct();
    trig.s_min = s_min;
    trig.s_max = s_max;
    trig.s_vpp = s_vpp;
    trig.trig_level = trig_level;
    trig.hyst = hyst;
    trig.rising_crossings = rising_crossings;
    trig.falling_crossings = falling_crossings;
    trig.trig_idx = trig_idx;
    trig.trig_str = trig_str;
end
