function results = run_hybridfsm_phase2_reachability(varargin)
% NOTE: Identifiers of the mutation tool have been genericized as
% 'mutationtool.*'. The experiments were executed with MUT4SLX (not
% included in this package); these scripts are provided for inspection
% and require the tool to be obtained separately to execute.
% RUN_HYBRIDFSM_PHASE2_REACHABILITY Filtered vs unfiltered mutation testing
%
% The Phase 2 experiment: does coverage-based reachability filtering save
% wall-clock time without losing kills? Two arms, one changed factor.
%
%   'unfiltered'  the seam returns all 25 tests for every mutant
%   'filtered'    the seam returns every test except those with R == 0
%
% BOTH ARMS RUN HERE, IN ONE SESSION
% The Phase 1 clean baseline is also an unfiltered full-suite run over the
% same 183 mutants, but it was measured days earlier. Machine drift across
% sessions was measured at up to +47% per test execution, which is larger
% than the effect being studied. So the unfiltered arm is re-run through the
% same seam, in the same session, and the Phase 1 baseline is kept only as a
% historical reference.
%
% WHAT IS HELD IDENTICAL
% Test order (ascending pool order in both arms), mutant set and order,
% operators, per-mutant early exit, telemetry, session hygiene, model and
% test file. The ONLY difference is the index vector the selector returns.
% Both arms go through the same branch of SimulinkTestStrategy, so a
% divergence in execution path is not possible by construction.
%
% THE SOUNDNESS CHECK
% Filtering may only remove pairs that could not have killed. So the two arms
% must agree on WHICH mutants die, not merely on how many. A mutant killed
% unfiltered but surviving filtered is a filter defect, and this runner
% reports the offending mutants rather than a pass/fail count.
%
% Usage:
%   run_hybridfsm_phase2_reachability('MutantLimit', 12)   % smoke
%   run_hybridfsm_phase2_reachability                      % full, 183 mutants
%
% Name-value arguments:
%   Arms        - Default {'unfiltered','filtered'}; both, in this order
%   MutantLimit - Run only the first N mutants in discovery order (smoke).
%                 Default [] = all.
%   RFile       - Reachability matrix; default <phase2>/reachability_R.mat
%   Tag         - Filename tag; default 'full' or sprintf('smoke%02d', N)
%
% See also: phase2.TestSelector, phase2.reachability, phase1_clean_session

    p = inputParser;
    p.addParameter('Arms', {'unfiltered', 'filtered'}, @iscell);
    p.addParameter('MutantLimit', [], @(x) isempty(x) || (isscalar(x) && x >= 1));
    p.addParameter('RFile', '', @(x) ischar(x) || isstring(x));
    p.addParameter('Tag', '', @(x) ischar(x) || isstring(x));
    p.parse(varargin{:});
    opt = p.Results;

    env = phase1_env();
    phase2Dir = fullfile(fileparts(env.resultsDir), 'phase2');
    outDir = fullfile(phase2Dir, 'runs');
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    rFile = opt.RFile;
    if isempty(rFile)
        rFile = fullfile(phase2Dir, 'reachability_R.mat');
    end
    L = load(rFile, 'R');
    R = L.R;

    if isempty(opt.Tag)
        if isempty(opt.MutantLimit)
            tag = 'full';
        else
            tag = sprintf('smoke%02d', opt.MutantLimit);
        end
    else
        tag = char(opt.Tag);
    end

    fprintf('\n=== HybridFSM Phase 2: REACHABILITY FILTERING ===\n');
    fprintf('MATLAB R%s | commit %s\n', env.matlabRelease, env.commit);
    fprintf('R = %d tests x %d mutants (ones=%d zeros=%d NaN=%d)\n', ...
        size(R,1), size(R,2), sum(R(:)==1), sum(R(:)==0), sum(isnan(R(:))));
    if isempty(opt.MutantLimit)
        fprintf('scope: all %d mutants\n', env.totalMutants);
    else
        fprintf('scope: first %d mutants (smoke)\n', opt.MutantLimit);
    end

    results = struct();
    for ai = 1:numel(opt.Arms)
        arm = opt.Arms{ai};
        fprintf('\n--- arm: %s ---\n', arm);
        results.(arm) = runArm(env, R, arm, opt.MutantLimit);
        outFile = fullfile(outDir, sprintf('%s_%s.mat', arm, tag));
        armResult = results.(arm);
        save(outFile, 'armResult');
        fprintf('saved: %s\n', outFile);
    end

    if all(isfield(results, {'unfiltered', 'filtered'}))
        results.comparison = compareArms(results.unfiltered, results.filtered);
        printComparison(results.comparison);
        cmp = results.comparison;
        save(fullfile(outDir, sprintf('comparison_%s.mat', tag)), 'cmp');
    end
end

% ----------------------------------------------------------------------
function out = runArm(env, R, arm, mutantLimit)
    phase1_clean_session(env);

    recorder = TestTraceRecorder();
    mutationtool.ExperimentPlan.resetTelemetryFailures();

    orch = mutationtool.Orchestrator();
    orch.loadConfig(env.configPath);
    cfg = orch.Config;

    % Mutant scope. Discovery order in both arms, so execution ordinal maps
    % straight onto R's columns; passed to the selector explicitly rather
    % than relied upon.
    if isempty(mutantLimit)
        mutantOrder = [];
    else
        mutantOrder = 1:mutantLimit;
        cfg.mutantPlan = struct('order', mutantOrder, 'limit', mutantLimit);
    end

    selector = phase2.TestSelector(R, arm, mutantOrder);
    cfg.testSelector = @selector.select;
    cfg.telemetry = struct('onTestExecuted', recorder.sink());
    % No testPlan: both arms take the pool in ascending order, and the
    % selector only removes from it.
    orch.setConfig(cfg);
    orch.addObserver(selector);
    orch.addObserver(recorder);

    tTotal = tic;
    orch.run();
    totalWall = toc(tTotal);

    ctx = orch.Context;
    if isempty(ctx.StartTime) || isempty(ctx.EndTime)
        error('run_hybridfsm_phase2_reachability:NoExecutionWindow', ...
            'Arm %s did not open an execution window (state=%s).', arm, ctx.State);
    end

    T = recorder.table();
    M = T(T.isBaseline == 0, :);

    out = struct();
    out.arm = arm;
    out.elapsedPhase = seconds(ctx.EndTime - ctx.StartTime);
    out.elapsedTotal = totalWall;
    out.mutantsEvaluated = ctx.KilledCount + ctx.SurvivedCount;
    out.killed = ctx.KilledCount;
    out.survived = ctx.SurvivedCount;
    out.errors = ctx.ErrorCount;
    out.pairsExecuted = height(M);
    out.killedOrdinals = killedOrdinals(M);
    out.perMutantPairs = pairsPerMutant(M);
    out.selector = selector.summary();
    out.telemetry = mutationtool.ExperimentPlan.telemetryFailureStats();
    out.traceValid = (out.telemetry.count == 0);
    out.testTrace = T;
    out.timestamp = datetime('now');

    fprintf(['  elapsed=%.1f s  pairs=%d  killed=%d  survived=%d  ' ...
             'selectorOverhead=%.1f ms\n'], ...
        out.elapsedPhase, out.pairsExecuted, out.killed, out.survived, ...
        1000 * out.selector.overheadSeconds);
    if ~out.traceValid
        fprintf(2, '  *** telemetry failures=%d -> INVALID ***\n', out.telemetry.count);
    end
end

% ----------------------------------------------------------------------
function k = killedOrdinals(M)
    k = [];
    for m = unique(M.mutantExecutionOrder)'
        if any(M.killedMutant(M.mutantExecutionOrder == m) == 1)
            k(end+1) = m; %#ok<AGROW>
        end
    end
end

% ----------------------------------------------------------------------
function t = pairsPerMutant(M)
    ord = unique(M.mutantExecutionOrder)';
    n = arrayfun(@(m) sum(M.mutantExecutionOrder == m), ord);
    t = table(ord(:), n(:), 'VariableNames', {'ordinal', 'pairs'});
end

% ----------------------------------------------------------------------
function c = compareArms(u, f)
    c = struct();
    c.killsIdentical = isequal(sort(u.killedOrdinals), sort(f.killedOrdinals));
    c.lostKills = setdiff(u.killedOrdinals, f.killedOrdinals);   % filter defects
    c.extraKills = setdiff(f.killedOrdinals, u.killedOrdinals);  % should be empty
    c.pairsUnfiltered = u.pairsExecuted;
    c.pairsFiltered = f.pairsExecuted;
    c.pairsSaved = u.pairsExecuted - f.pairsExecuted;
    c.pairReductionPct = 100 * c.pairsSaved / max(u.pairsExecuted, 1);
    c.elapsedUnfiltered = u.elapsedPhase;
    c.elapsedFiltered = f.elapsedPhase;
    c.timeSaved = u.elapsedPhase - f.elapsedPhase;
    c.timeReductionPct = 100 * c.timeSaved / max(u.elapsedPhase, 1);
    c.killedUnfiltered = u.killed;
    c.killedFiltered = f.killed;
end

% ----------------------------------------------------------------------
function printComparison(c)
    fprintf('\n=== COMPARISON ===\n');
    fprintf('pairs   : %d -> %d   (saved %d, %.1f%%)\n', ...
        c.pairsUnfiltered, c.pairsFiltered, c.pairsSaved, c.pairReductionPct);
    fprintf('elapsed : %.1f s -> %.1f s   (saved %.1f s, %.1f%%)\n', ...
        c.elapsedUnfiltered, c.elapsedFiltered, c.timeSaved, c.timeReductionPct);
    fprintf('killed  : %d -> %d\n', c.killedUnfiltered, c.killedFiltered);
    if c.killsIdentical
        fprintf('kill sets IDENTICAL - filter removed no killing pair\n');
    else
        fprintf(2, '*** KILL SETS DIFFER ***\n');
        if ~isempty(c.lostKills)
            fprintf(2, '  lost kills (filter defect): %s\n', mat2str(c.lostKills));
        end
        if ~isempty(c.extraKills)
            fprintf(2, '  extra kills (impossible, investigate): %s\n', mat2str(c.extraKills));
        end
    end
end
