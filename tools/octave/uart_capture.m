function [samples, actual_sampling_frequency, status, file_path] = uart_capture(sampling_frequency, adc_prescaler, sample_amount, serial_target, auto_save, show_plot, wave_type)
    % =========================================================================
    % UART_CAPTURE - Captura de bloco de amostras do ADC (ATmega2560)
    %
    % Uso autônomo (sem argumentos no terminal ou botão Run):
    %   uart_capture
    %   -> Usa os parâmetros default abaixo, abre a serial, captura 4096
    %      amostras, calcula o período/frequência medidos, salva automaticamente
    %      em /data/sample_YYYYMMDD_HHMMSS.mat (com wave_type) e plota o sinal.
    %
    % Uso integrado (chamado pelo uart_oscilloscope.m):
    %   [samples, fs_eff, status, file_path] = uart_capture(fs, prescaler, N, s, auto_save, false, wave_type)
    %   -> Reutiliza a porta serial aberta 's' para captura rápida em tempo real.
    % =========================================================================

    if exist("serial") == 0
        pkg load instrument-control;
    end

    % --- DIRETÓRIOS E PATHS DE MÓDULOS ---
    base_dir = fileparts(mfilename("fullpath"));
    if isempty(base_dir)
        base_dir = pwd();
    end
    if exist("detectSignalTrigger", "file") == 0
        addpath(genpath(fullfile(base_dir, "src")));
    end
    output_dir = fullfile(base_dir, "data");

    % --- PARÂMETROS DEFAULT ---
    default_serial_port        = "/dev/ttyUSB0";
    default_baud_rate          = 115200;
    default_sampling_frequency = 2^13;
    default_adc_prescaler      = 16;
    default_sample_amount      = 4096;
    default_wave_type          = "triangular";

    if nargin < 1 || isempty(sampling_frequency)
        sampling_frequency = default_sampling_frequency;
    end
    if nargin < 2 || isempty(adc_prescaler)
        adc_prescaler = default_adc_prescaler;
    end
    if nargin < 3 || isempty(sample_amount)
        sample_amount = default_sample_amount;
    end
    if nargin < 4 || isempty(serial_target)
        serial_target = default_serial_port;
    end
    if nargin < 5 || isempty(auto_save)
        % Salva automaticamente por padrão quando executado sozinho
        auto_save = (nargin < 4);
    end
    if nargin < 6 || isempty(show_plot)
        % Plota automaticamente quando executado de forma autônoma sem saídas
        show_plot = (nargout == 0) && (nargin < 4);
    end
    if nargin < 7 || isempty(wave_type)
        wave_type = default_wave_type;
    end
    no_ideal = any(strcmpi(strtrim(char(wave_type)), {"none", "off", "desligado", "desativado"}));
    if no_ideal
        wave_type = "none";
        wave_label = "Desligado";
    else
        wspec = getWaveformSpec(wave_type);
        wave_type = wspec.type;
        wave_label = wspec.label;
    end

    % --- VALIDAÇÃO DE PARÂMETROS DE HARDWARE E FIRMWARE ---
    if ~isfinite(sampling_frequency) || sampling_frequency ~= fix(sampling_frequency) ...
            || sampling_frequency < 513 || sampling_frequency > 65535
        error("fs deve ser um inteiro entre 513 e 65535 Hz.");
    end
    if ~any(adc_prescaler == [16, 32, 64, 128])
        error("Prescaler do ADC inválido: use 16, 32, 64 ou 128.");
    end
    if ~isfinite(sample_amount) || sample_amount ~= fix(sample_amount) ...
            || sample_amount < 1 || sample_amount > 6144
        error("A quantidade de amostras deve ser um inteiro entre 1 e 6144.");
    end

    % Mesmo arredondamento do Timer1 no firmware (CPU nominal de 16 MHz)
    timer_ticks = floor(16000000 / (8 * sampling_frequency) + 0.5);
    actual_sampling_frequency = 16000000 / (8 * timer_ticks);

    % Orçamento conservador do firmware: conversão/alinhamento + ISR
    if 8 * timer_ticks <= 14 * adc_prescaler + 256
        error("fs excede o orçamento de tempo do ADC/ISR para este prescaler.");
    end

    % Pacote de configuração de 5 bytes: [prescaler (1B), fs (2B), N (2B)]
    config_packet = [uint8(adc_prescaler), ...
                     typecast(uint16(sampling_frequency), "uint8"), ...
                     typecast(uint16(sample_amount), "uint8")];

    samples   = [];
    status    = -1;
    file_path = "";

    % Timeout dinâmico em décimos de segundo compatível com fs baixas (ex.: 513 Hz)
    req_timeout_ds = max(50, ceil((sample_amount / actual_sampling_frequency + 2.0) * 10));

    % Verifica se recebeu o nome da porta (string) ou um objeto serial já aberto
    own_serial = ischar(serial_target);
    if own_serial
        disp("Conectando à porta serial...");
        s = serial(serial_target, default_baud_rate);
        set(s, "timeout", req_timeout_ds);
        pause(2);
    else
        s = serial_target;
        if get(s, "timeout") < req_timeout_ds
            set(s, "timeout", req_timeout_ds);
        end
    end

    unwind_protect
        % --- SOLICITAÇÃO E LEITURA DO BLOCO ---
        srl_flush(s);
        if own_serial
            disp("Solicitando captura e lendo bytes...");
        end
        fwrite(s, config_packet, "uint8");
        status_byte = fread(s, 1, "uint8");

        if isempty(status_byte)
            status = -1;
            disp("Timeout na comunicação serial! A amostra foi descartada.");
            return;
        end

        status = double(status_byte);
        if status ~= 0
            if status == 1
                disp("Parâmetros inválidos reportados pelo Arduino (STATUS_ERR_PARAM)! A amostra foi descartada.");
            elseif status == 2
                disp("Perda de sincronismo detectada pelo Arduino (atraso da ISR)! A amostra foi descartada.");
            else
                printf("Erro desconhecido recebido (status = %d)! A amostra foi descartada.\n", status);
            end
            return;
        end

        raw_samples = fread(s, sample_amount, "uint8");

        % --- DETECÇÃO DE PERDA DE DADOS ---
        if length(raw_samples) < sample_amount
            status = -2;
            disp("Perda de dados detectada! A amostra foi descartada.");
            return;
        end

        samples = double(raw_samples(:));

        % --- CÁLCULO DO PERÍODO E FREQUÊNCIA SOMENTE QUANDO NECESSÁRIO ---
        need_period_info = own_serial || auto_save || show_plot;
        if need_period_info
            trig = detectSignalTrigger(samples);
            per  = estimateSignalPeriod(samples, actual_sampling_frequency, trig, "trig", wave_type);
            period_samples   = per.period_samples;
            period_sec       = per.period_sec;
            signal_frequency = per.freq_hz;
        end

        if own_serial
            printf("Leitura concluída! Onda = %s | f = %.2f Hz | T = %.2f ms (%.1f am/ciclo)\n", ...
                   wave_label, signal_frequency, period_sec * 1e3, period_samples);
        end

        % --- SALVAMENTO AUTOMÁTICO EM /data (SEM INPUT NO TERMINAL) ---
        if auto_save
            if ~exist(output_dir, "dir")
                mkdir(output_dir);
            end
            if no_ideal
                file_name = ["sample_", datestr(now, "yyyymmdd_HHMMSS_FFF"), ".mat"];
                file_path = fullfile(output_dir, file_name);
                save("-v7", file_path, ...
                     "samples", "sampling_frequency", "actual_sampling_frequency", ...
                     "adc_prescaler", "sample_amount", ...
                     "signal_frequency", "period_samples", "period_sec");
            else
                file_name = ["sample_", wave_type, "_", datestr(now, "yyyymmdd_HHMMSS_FFF"), ".mat"];
                file_path = fullfile(output_dir, file_name);
                save("-v7", file_path, ...
                     "wave_type", ...
                     "samples", "sampling_frequency", "actual_sampling_frequency", ...
                     "adc_prescaler", "sample_amount", ...
                     "signal_frequency", "period_samples", "period_sec");
            end
            printf("Amostra salva automaticamente em: %s\n", file_path);
        end

        % --- PLOTAGEM SIMPLES QUANDO EXECUTADO SOZINHO ---
        if show_plot
            figure("name", "Captura UART - ATmega2560", "numbertitle", "off");
            stairs(0:(sample_amount - 1), samples);
            grid on;
            title(sprintf("Sinal Adquirido via ADC (%s | f = %.2f Hz | fs = %.1f Hz | Prescaler = %d)", ...
                          wave_label, signal_frequency, actual_sampling_frequency, adc_prescaler));
            xlabel(sprintf("Índice da Amostra (0 a %d)", sample_amount - 1));
            ylabel("Nível Digital de Quantização (0 a 255)");
            ylim([-10, 265]);
            xlim([0, sample_amount - 1]);
            drawnow;
        end
    unwind_protect_cleanup
        if own_serial && exist("s", "var")
            try
                fclose(s);
            catch
            end
            clear s;
        end
    end_unwind_protect
end
