function [samples, actual_sampling_frequency, status, file_path] = uart_capture(sampling_frequency, adc_prescaler, sample_amount, serial_target, auto_save, show_plot)
    % =========================================================================
    % UART_CAPTURE - Captura de bloco de amostras do ADC (ATmega2560)
    %
    % Uso autônomo (sem argumentos no terminal ou botão Run):
    %   uart_capture
    %   -> Usa os parâmetros default abaixo, abre a serial, captura 4096
    %      amostras, salva automaticamente em /data/sample_YYYYMMDD_HHMMSS.mat
    %      sem pedir input no terminal e plota o sinal capturado.
    %
    % Uso integrado (chamado pelo uart_oscilloscope_panel.m):
    %   [samples, fs_eff, status] = uart_capture(fs, prescaler, N, s, false, false)
    %   -> Reutiliza a porta serial aberta 's' para captura rápida em tempo real.
    % =========================================================================

    pkg load instrument-control;

    % --- PARÂMETROS DEFAULT ---
    default_serial_port        = "/dev/ttyUSB0";
    default_baud_rate          = 115200;
    default_sampling_frequency = 2^13;
    default_adc_prescaler      = 16;
    default_sample_amount      = 4096;

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

    % --- DIRETÓRIO DE SAÍDA (/data) ---
    base_dir = fileparts(mfilename("fullpath"));
    if isempty(base_dir)
        base_dir = pwd();
    end
    output_dir = fullfile(base_dir, "data");

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

    % Verifica se recebeu o nome da porta (string) ou um objeto serial já aberto
    own_serial = ischar(serial_target);
    if own_serial
        disp("Conectando à porta serial...");
        s = serial(serial_target, default_baud_rate);
        set(s, "timeout", 50);
        pause(2);
    else
        s = serial_target;
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
        if own_serial
            disp("Leitura concluída com sucesso!");
        end

        % --- SALVAMENTO AUTOMÁTICO EM /data (SEM INPUT NO TERMINAL) ---
        if auto_save
            if ~exist(output_dir, "dir")
                mkdir(output_dir);
            end
            file_name = ["sample_", datestr(now, "yyyymmdd_HHMMSS_FFF"), ".mat"];
            file_path = fullfile(output_dir, file_name);
            save("-v7", file_path, ...
                 "samples", "sampling_frequency", "actual_sampling_frequency", ...
                 "adc_prescaler", "sample_amount");
            printf("Amostra salva automaticamente em: %s\n", file_path);
        end

        % --- PLOTAGEM SIMPLES QUANDO EXECUTADO SOZINHO ---
        if show_plot
            figure("name", "Captura UART - ATmega2560", "numbertitle", "off");
            stairs(0:(sample_amount - 1), samples);
            grid on;
            title(sprintf("Sinal Adquirido via ADC (fs efetiva = %.1f Hz, Prescaler = %d)", ...
                          actual_sampling_frequency, adc_prescaler));
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
