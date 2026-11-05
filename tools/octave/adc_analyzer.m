function results = adc_analyzer(mode_or_file, save_updated_mat)
    % =========================================================================
    % ADC_ANALYZER - Orquestrador de Condicionamento e Análise Offline do ADC
    % Configurado para ATmega2560 com Vref = 2.56 V (8 bits = 256 níveis)
    %
    % Arquitetura modular:
    %   - src/triggering/   : detectSignalTrigger, estimateSignalPeriod
    %   - src/conditioning/ : generateIdealReference, computeStaticAndTimeErrors
    %   - src/spectral/     : computeSpectralMetrics (FFT tripla, DR, SINAD, ENOB)
    %   - src/linearity/    : computeHistogramLinearity (DNL, INL, Missing Codes)
    %   - utils/            : analyzeSingleCapture, launchAnalyzerDashboard,
    %                         runBatchAnalysis, plotComparativeFigures, etc.
    %
    % Formas de uso no GNU Octave:
    %   adc_analyzer()               -> Abre o Painel Interativo Completo (GUI)
    %   adc_analyzer("batch")        -> Analisa todos os .mat de /data, gera CSV
    %                                   e figuras comparativas em /outputs
    %   adc_analyzer("arquivo.mat")  -> Abre o painel focado no arquivo indicado
    %   adc_analyzer("batch", true)  -> Lote + enriquece todos os .mat com métricas
    % =========================================================================

    if nargin < 1 || isempty(mode_or_file)
        mode_or_file = "gui";
    end
    if nargin < 2 || isempty(save_updated_mat)
        save_updated_mat = false;
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

    % Constantes de Hardware do ADC (ATmega2560 com REFS1:0 = 11 e ADLAR = 1)
    VREF      = 2.56;              % Referência interna de 2,56 V
    LSB_VOLTS = VREF / 256.0;      % 1 LSB = 10 mV (0,01 V)
    LSB_MV    = LSB_VOLTS * 1e3;   % 10,0 mV

    mat_files = dir(fullfile(data_dir, "*.mat"));
    if isempty(mat_files)
        error("Nenhum arquivo .mat encontrado em: %s", data_dir);
    end
    [~, sort_idx] = sort({mat_files.name});
    mat_files = mat_files(sort_idx);

    % 1. Modo Lote (Batch): processa todos os arquivos, exporta CSV e gráficos
    if strcmpi(mode_or_file, "batch")
        results = runBatchAnalysis(mat_files, data_dir, output_dir, VREF, LSB_MV, save_updated_mat);
        return;
    end

    % 2. Localiza o arquivo inicial caso tenha sido especificado por nome
    init_file_idx = 1;
    if ~strcmpi(mode_or_file, "gui")
        [~, target_name, target_ext] = fileparts(mode_or_file);
        if isempty(target_ext)
            target_ext = ".mat";
        end
        target_full = [target_name, target_ext];
        for k = 1:numel(mat_files)
            if strcmpi(mat_files(k).name, target_full)
                init_file_idx = k;
                break;
            end
        end
    end

    % 3. Abre o Painel Digital Interativo (ou retorna a estrutura se sem display)
    if ~isempty(available_graphics_toolkits())
        results = launchAnalyzerDashboard(mat_files, init_file_idx, data_dir, output_dir, VREF, LSB_MV);
    else
        target_path = fullfile(data_dir, mat_files(init_file_idx).name);
        results = analyzeSingleCapture(target_path, VREF, LSB_MV, "opt");
    end
end
