function saveEnrichedMat(mat_path, m)
    % =========================================================================
    % SAVEENRICHEDMAT - Salva/atualiza o arquivo .mat com as métricas do ADC
    % =========================================================================

    m_out = rmfield(m, intersect(fieldnames(m), {"file_name", "file_path", "was_full_format"}));
    save("-v7", mat_path, "-struct", "m_out");
end
