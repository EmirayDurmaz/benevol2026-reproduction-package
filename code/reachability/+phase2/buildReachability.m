function out = buildReachability(varargin)
% PHASE2.BUILDREACHABILITY Phase 2A - build and report the R matrix
%
%   out = phase2.buildReachability()
%   out = phase2.buildReachability('Adapter', @phase2.adapters.hybridfsm)
%   out = phase2.buildReachability('Reuse', true)   % reuse saved coverage
%
% Pipeline position:
%   Sampling -> [ REACHABILITY FILTERING ] -> Prioritization -> Execution
%
% This stage only shrinks the candidate space. It assigns no scores, no
% ordering and no preferences - a pair is either provably not worth running
% (R=0) or it is handed to Phase 2B untouched. Keeping that boundary sharp
% is why filtering and prioritisation are separate packages: mixing a
% "definitely skip" decision into a "probably later" score makes the safety
% argument for the former impossible to state.
%
% Name-value arguments:
%   Adapter - model-specific location resolver (default hybridfsm)
%   Reuse   - reuse coverage from a previous call if present (default true);
%             the coverage replay is ~13 s, so this is convenience, not a
%             cache the results depend on
%   Verbose - print progress (default true)
%
% See also: phase2.collectCoverage, phase2.reachability, phase2.analyze,
%           phase2.validate, phase2.writeArtifacts

    p = inputParser;
    p.addParameter('Adapter', @phase2.adapters.hybridfsm, @(f) isa(f, 'function_handle'));
    p.addParameter('Reuse', true, @(x) islogical(x) || isnumeric(x));
    p.addParameter('Verbose', true, @(x) islogical(x) || isnumeric(x));
    p.parse(varargin{:});
    opt = p.Results;

    e = phase2.env();
    covFile = fullfile(e.phase2Dir, 'coverage_per_test.mat');

    % --- mutants ---------------------------------------------------------
    J = jsondecode(fileread(e.mutantJson));
    mutants = J.mutants;
    nM = numel(mutants);
    if opt.Verbose
        fprintf('=== PHASE 2A - REACHABILITY ===\n');
        fprintf('mutants: %d  |  model: %s\n', nM, e.model);
    end

    % --- locations (model-specific) --------------------------------------
    loc = opt.Adapter(mutants, e);
    if opt.Verbose
        fprintf('coverage context: %s\n', loc.coverageContext);
        fprintf('coverage objects: %d\n', numel(loc.objects));
    end

    % --- coverage on the ORIGINAL model ----------------------------------
    if opt.Reuse && exist(covFile, 'file')
        S = load(covFile, 'cov');
        cov = S.cov;
        if size(cov.covered, 2) ~= numel(loc.objects)
            error('phase2:buildReachability:StaleCoverage', ...
                ['Saved coverage has %d objects, the adapter resolved %d. ' ...
                 'Delete %s and re-run.'], size(cov.covered, 2), ...
                numel(loc.objects), covFile);
        end
        if opt.Verbose, fprintf('coverage: reused from %s\n', covFile); end
    else
        if opt.Verbose, fprintf('coverage: replaying %d tests...\n', e.totalTests); end
        cov = phase2.collectCoverage(e, loc.objects, struct('verbose', opt.Verbose));
        save(covFile, 'cov', '-v7');
        if opt.Verbose, fprintf('coverage: %.1f s -> %s\n', cov.elapsed, covFile); end
    end

    % --- semantics: primary and ablation ---------------------------------
    [R, semUnion]  = phase2.reachability(cov, loc.candidates, 'union');
    [Rs, semStrict] = phase2.reachability(cov, loc.candidates, 'strict');

    % --- provenance ------------------------------------------------------
    prov = struct('mutantIdx', {}, 'operatorName', {}, 'blockPath', {}, ...
        'blockType', {}, 'locationKey', {}, 'coverageContext', {}, ...
        'candidateSIDs', {}, 'resolvedCount', {}, 'evidenceMetric', {}, ...
        'mappingStrategy', {}, 'ambiguous', {}, 'semantics', {});
    for i = 1:nM
        cand = loc.candidates{i};
        prov(i) = struct( ...
            'mutantIdx', i, ...
            'operatorName', string(mutants(i).operatorName), ...
            'blockPath', string(mutants(i).blockPath), ...
            'blockType', string(mutants(i).blockType), ...
            'locationKey', string(mutants(i).originalValue), ...
            'coverageContext', string(loc.coverageContext), ...
            'candidateSIDs', strjoin(string(loc.objectIds(cand)), ','), ...
            'resolvedCount', numel(cand), ...
            'evidenceMetric', loc.evidenceMetric(i), ...
            'mappingStrategy', loc.mappingStrategy(i), ...
            'ambiguous', numel(cand) > 1, ...
            'semantics', semUnion(i));
    end

    % --- analysis and post-hoc validation --------------------------------
    ops = arrayfun(@(m) string(m.operatorName), mutants);
    statsUnion  = phase2.analyze(R,  prov, cov.testNames, ops);
    statsStrict = phase2.analyze(Rs, prov, cov.testNames, ops);
    val = phase2.validate(R, e.traceCsv);

    out = struct('R', R, 'Rstrict', Rs, 'cov', cov, 'loc', loc, ...
        'prov', prov, 'statsUnion', statsUnion, 'statsStrict', statsStrict, ...
        'validation', val, 'semanticsStrict', semStrict, ...
        'testNames', cov.testNames, 'env', e);

    phase2.writeArtifacts(out);

    if opt.Verbose
        fprintf('\nunion : %.1f%% eliminated, %.1f%% unknown\n', ...
            statsUnion.pctUnreached, statsUnion.pctUnknown);
        fprintf('strict: %.1f%% eliminated, %.1f%% unknown\n', ...
            statsStrict.pctUnreached, statsStrict.pctUnknown);
        fprintf('validation: %d kills, %d violations (sound=%d)\n', ...
            val.nKills, val.nR0, val.sound);
        fprintf('artifacts -> %s\n', e.phase2Dir);
    end
end
