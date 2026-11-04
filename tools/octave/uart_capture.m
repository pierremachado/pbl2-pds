pkg load instrument-control;

% --- CONFIGURAÇÕES ---
% Ajuste a porta conforme o seu sistema operacional:
% Windows: "COM3", "COM4", etc.
% Linux/macOS: "/dev/ttyACM0", "/dev/ttyUSB0", etc.
serial_port = "/dev/ttyUSB0";
baud_rate = 115200;
output_dir = fullfile(fileparts(mfilename("fullpath")), "data");

signal_frequency = 1;
sampling_frequency = 2000;
adc_prescaler = 16;
sample_amount = 4096;

% --- ABERTURA DA PORTA SERIAL ---
disp("Conectando à porta serial...");
s = serial(serial_port, baud_rate);
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
            disp("Perda de sincronismo detectada pelo Arduino (T_conv > T_s)! A amostra foi descartada.");
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
        save("-v7", file_path, "samples", "signal_frequency", "sampling_frequency", "adc_prescaler", "sample_amount");
        printf("Amostra salva em: %s\n", file_path);
    end
end

% --- FECHAMENTO DA CONEXÃO ---
fclose(s);
clear s;
