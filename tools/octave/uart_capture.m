pkg load instrument-control;

% --- CONFIGURAÇÕES ---
% Ajuste a porta conforme o seu sistema operacional:
% Windows: "COM3", "COM4", etc.
% Linux/macOS: "/dev/ttyACM0", "/dev/ttyUSB0", etc.
serial_port = "/dev/ttyUSB0";
baud_rate = 115200;
output_dir = fullfile(fileparts(mfilename("fullpath")), "data");

signal_frequency = 1;
sampling_frequency = 1024;
adc_prescaler = 16;
sample_amount = 4096;

% Valida antes das conversões para uint8/uint16 e antes de abrir a serial.
% O firmware recebe fs, prescaler e N; a frequência do sinal só existe aqui.
if ~isfinite(signal_frequency) || signal_frequency < 1
    error("A frequência do sinal deve ser finita e >= 1 Hz.");
end
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

% Mesmo arredondamento do Timer1 no firmware, para CPU nominal de 16 MHz.
timer_ticks = floor(16000000 / (8 * sampling_frequency) + 0.5);
actual_sampling_frequency = 16000000 / (8 * timer_ticks);
if sampling_frequency <= 512 * signal_frequency ...
        || actual_sampling_frequency <= 512 * signal_frequency
    error("fs solicitada e efetiva devem ser estritamente maiores que 512*f.");
end
% Mesmo orçamento conservador do firmware: conversão/alinhamento + ISR.
if 8 * timer_ticks <= 14 * adc_prescaler + 256
    error("fs excede o orçamento de tempo do ADC/ISR para este prescaler.");
end

% --- ABERTURA DA PORTA SERIAL ---
disp("Conectando à porta serial...");
s = serial(serial_port, baud_rate);
% fs > 512 Hz: até 6144 amostras levam menos de 12 s, mais ~0,54 s de envio.
set(s, 'timeout', 50);
pause(2);

while true
    read_option = input("\nDeseja ler uma amostra? (s/n): ", "s");
    if strcmpi(strtrim(read_option), "n")
        disp("Encerrando o programa.");
        break;
    end

    % --- SOLICITAÇÃO E LEITURA DO BLOCO ---
    srl_flush(s);
    disp("Solicitando captura e lendo bytes...");
    config_packet = [uint8(adc_prescaler), ...
                     typecast(uint16(sampling_frequency), "uint8"), ...
                     typecast(uint16(sample_amount), "uint8")];
    fwrite(s, config_packet, "uint8");
    status = fread(s, 1, "uint8");

    if isempty(status) || status ~= 0
        if isempty(status)
            disp("Timeout na comunicação serial! A amostra foi descartada.");
        elseif status == 1
            disp("Parâmetros inválidos reportados pelo Arduino (STATUS_ERR_PARAM)! A amostra foi descartada.");
        elseif status == 2
            disp("Perda de sincronismo detectada pelo Arduino (atraso da ISR)! A amostra foi descartada.");
        else
            printf("Erro desconhecido recebido (status = %d)! A amostra foi descartada.\n", status);
        end
        continue;
    end

    samples = fread(s, sample_amount, "uint8");

    % --- DETECÇÃO DE PERDA DE DADOS ---
    if length(samples) < sample_amount
        disp("Perda de dados detectada! A amostra foi descartada.");
        continue;
    end

    disp("Leitura concluída com sucesso!");

    % --- PLOTAGEM SIMPLES ---
    figure;
    stairs(samples);
    grid on;
    title('Sinal Adquirido via ADC do ATmega2560');
    xlabel(sprintf('Índice da Amostra (0 a %d)', sample_amount - 1));
    ylabel('Nível Digital de Quantização (0 a 255)');
    ylim([-10 265]);
    drawnow;

    % --- SALVAMENTO DA AMOSTRA ---
    save_option = input("Deseja salvar a amostra? (s/n): ", "s");
    if strcmpi(strtrim(save_option), "s")
        if ~exist(output_dir, "dir")
            mkdir(output_dir);
        end

        file_name = strtrim(input("Nome do arquivo (Enter para automático): ", "s"));
        if isempty(file_name)
            file_name = ["sample_", datestr(now, "yyyymmdd_HHMMSS"), ".mat"];
        elseif ~endsWith(file_name, ".mat")
            file_name = [file_name, ".mat"];
        end

        file_path = fullfile(output_dir, file_name);
        save("-v7", file_path, "samples", "signal_frequency", "sampling_frequency", "actual_sampling_frequency", "adc_prescaler", "sample_amount");
        printf("Amostra salva em: %s\n", file_path);
    end
end

% --- FECHAMENTO DA CONEXÃO ---
fclose(s);
clear s;
