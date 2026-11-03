pkg load instrument-control;

% --- CONFIGURAÇÕES ---
% Ajuste a porta conforme o seu sistema operacional:
% Windows: "COM3", "COM4", etc.
% Linux/macOS: "/dev/ttyACM0", "/dev/ttyUSB0", etc.
porta_serial = "/dev/ttyUSB0";
baud_rate = 115200;
tamanho_buffer = 16384;

% --- ABERTURA DA PORTA SERIAL ---
disp("Conectando à porta serial...");
s = serial(porta_serial, baud_rate);
set(s, 'timeout', 10);

disp("Aguardando envio e lendo bytes...");
dados = fread(s, tamanho_buffer, "uint8");

% --- FECHAMENTO DA CONEXÃO ---
fclose(s);
clear s;
disp("Leitura concluída com sucesso!");

% --- PLOTAGEM SIMPLES ---
figure;
stairs(dados);
grid on;
title('Sinal Adquirido via ADC do ATmega2560');
xlabel('Índice da Amostra (0 a 1023)');
ylabel('Nível Digital de Quantização (0 a 255)');
ylim([-10 265]);
