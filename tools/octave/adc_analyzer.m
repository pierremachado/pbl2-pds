function results = adc_analyzer(target_file, wave_type)
    % =========================================================================
    % ADC_ANALYZER - Orquestrador de Condicionamento e Análise Offline do ADC
    % Configurado para ATmega2560 com Vref = 5.0 V (AVCC, 8 bits = 256 níveis)
    %
    % Arquitetura modular:
    %   - src/triggering/   : detectSignalTrigger, estimateSignalPeriod
    %   - src/conditioning/ : getWaveformSpec, generateIdealReference,
    %                         computeStaticAndTimeErrors
    %   - src/spectral/     : computeSpectralMetrics (FFT tripla, DR e piso de ruído)
    %   - src/linearity/    : computeHistogramLinearity (DNL, INL, Missing Codes)
    %   - utils/            : analyzeSingleCapture, launchAnalyzerDashboard,
    %                         createAnalyzerPlots, updateAnalyzerDashboard,
    %                         exportSingleDashboardPng, saveEnrichedMat
    %
    % Formas de uso no GNU Octave:
    %   adc_analyzer()                       -> Painel Interativo (GUI)
    %   adc_analyzer("arquivo.mat")          -> Painel focado no arquivo
    %   adc_analyzer("arquivo.mat", "sine")  -> Painel com forma de onda inicial
    %
    % Formas de onda aceitas em wave_type:
    %   "triangular" | "sine" ("senoidal") | "sawtooth" ("dente de serra") | "square" ("quadrada")
    % =========================================================================

    if nargin < 1 || isempty(target_file)
        target_file = "";
    end
    if nargin < 2
        wave_type = "";
    end

    % Configuração de diretórios e paths dos submódulos (src/ e utils/)
    base_dir = fileparts(mfilename("fullpath"));
    if isempty(base_dir)
        base_dir = pwd();
    end
    addpath(genpath(fullfile(base_dir, "src")));
    addpath(fullfile(base_dir, "utils"));

    data_dir   = fullfile(base_dir, "data");
    output_dir = fullfile(base_dir, "outputs");
    if ~exist(output_dir, "dir")
        mkdir(output_dir);
    end

    % Constantes de Hardware do ADC (ATmega2560 com REFS1:0 = 01 [AVCC] e ADLAR = 1)
    VREF      = 5.0;               % Referência AVCC de 5,0 V
    LSB_VOLTS = VREF / 256.0;      % 1 LSB ≈ 19,53 mV
    LSB_MV    = LSB_VOLTS * 1e3;

    mat_files = dir(fullfile(data_dir, "*.mat"));
    if isempty(mat_files)
        error("Nenhum arquivo .mat encontrado em: %s", data_dir);
    end
    [~, sort_idx] = sort({mat_files.name});
    mat_files = mat_files(sort_idx);

    % 1. Localiza o arquivo inicial caso tenha sido especificado por nome
    init_file_idx = 1;
    if ~isempty(target_file) && ~strcmpi(target_file, "gui")
        [~, target_name, target_ext] = fileparts(target_file);
        if isempty(target_ext)
            target_ext = ".mat";
        end
        target_full = [target_name, target_ext];
        found = false;
        for k = 1:numel(mat_files)
            if strcmpi(mat_files(k).name, target_full)
                init_file_idx = k;
                found = true;
                break;
            end
        end
        if ~found
            error("Arquivo '%s' não encontrado em: %s", target_full, data_dir);
        end
    end

    % 2. Abre o Painel Digital Interativo (ou retorna a estrutura se sem display)
    if ~isempty(available_graphics_toolkits())
        results = launchAnalyzerDashboard(mat_files, init_file_idx, data_dir, output_dir, VREF, LSB_MV, wave_type);
    else
        target_path = fullfile(data_dir, mat_files(init_file_idx).name);
        results = analyzeSingleCapture(target_path, VREF, LSB_MV, "opt", wave_type);
    end
end
