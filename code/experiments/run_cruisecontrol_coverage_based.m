function results = run_cruisecontrol_coverage_based(varargin)
% NOTE: Identifiers of the mutation tool have been genericized as
% 'mutationtool.*'. The experiments were executed with MUT4SLX (not
% included in this package); these scripts are provided for inspection
% and require the tool to be obtained separately to execute.
% RUN_CRUISECONTROL_COVERAGE_BASED Coverage-Based on CruiseControl, RM protocol
%
% The CruiseControl counterpart of run_hybridfsm_coverage_based, evaluated
% under EXACTLY the protocol every strategy uses so points are directly
% comparable across subjects:
%
%   T_full          from results/CruiseControl/phase1/baseline.mat
%                   (measured 2543.36 s, ground truth 41/67 = 61.19%)
%   budgets         {0.02 0.04 0.06 0.08 0.10 0.20 0.30 0.40 0.50} x T_full
%   seeds           1..5, RandomPlan.permutation(seed, 67)
%   one permutation per seed, reused at every budget
%   budget rule     MutantBudgetGovernor - online, checked after each mutant
%                   completes; the in-flight mutant always finishes, so
%                   overshoot is bounded by one mutant and is recorded
%   early exit      unchanged
%   telemetry       TestTraceRecorder, same schema
%
% THE ONE STRATEGY-SPECIFIC DIFFERENCE
%   every selected mutant is offered only the tests with R(:, mutant) ~= 0,
%   in unchanged ascending pool order. R == 1 and R == NaN are both
%   retained; only a demonstrated R == 0 removes a pair. Nothing is
%   reordered and no kill outcome influences any decision.
%
% COLUMN-IDENTITY GUARD
% R's columns are keyed by the findAllMutants enumeration order captured at
% discovery time, with each column's Stateflow SSIdNumber recorded in the
% provenance struct. Before any point runs, the mutants are re-enumerated
% and their SSIdNumbers compared against that record; a mismatch aborts the
% whole run, because it means every mutant would be filtered with another
% mutant's row. This replaces trusting that enumeration order is stable
% with checking that it is.
%
% Usage:
%   run_cruisecontrol_coverage_based                          % all 45 points
%   run_cruisecontrol_coverage_based('Seeds', 1, 'BudgetFractions', 0.10)
%   run_cruisecontrol_coverage_based('DryRun', true)
%
% Name-value arguments:
%   Seeds            - Default 1:5
%   BudgetFractions  - Default [0.02 0.04 0.06 0.08 0.10 0.20 0.30 0.40 0.50]
%   TFull            - Default: T_full_mutation_phase from baseline.mat
%   RFile            - Default <results>/CruiseControl/phase2/reachability_R.mat
%   Resume           - Skip points already on disk (default true)
%   DryRun           - Print the plan and exit
%
% Results go to results/CruiseControl/phase2/coverage_based/seedSS_bBBB.mat.
%
% See also: run_cruisecontrol_baseline, run_hybridfsm_coverage_based,
%           phase2.TestSelector, MutantBudgetGovernor, cc_env

    p = inputParser;
    p.addParameter('Seeds', 1:5, @isnumeric);
    p.addParameter('BudgetFractions', ...
        [0.02 0.04 0.06 0.08 0.10 0.20 0.30 0.40 0.50], @isnumeric);
    p.addParameter('TFull', [], @(x) isempty(x) || (isscalar(x) && x > 0));
    p.addParameter('RFile', '', @(x) ischar(x) || isstring(x));
    p.addParameter('Resume', true, @(x) islogical(x) || isnumeric(x));
    p.addParameter('DryRun', false, @(x) islogical(x) || isnumeric(x));
    p.parse(varargin{:});
    opt = p.Results;

    env = cc_env();
    T_full = resolveTFull(opt.TFull, env);

    rFile = opt.RFile;
    if isempty(rFile)
        rFile = fullfile(fileparts(env.resultsDir), 'phase2', 'reachability_R.mat');
    end
    L = load(rFile, 'R', 'provenance');
    R = L.R;
    provenance = L.provenance;
    if size(R, 1) ~= env.totalTests || size(R, 2) ~= env.totalMutants
        error('run_cruisecontrol_coverage_based:RShapeMismatch', ...
            'R is %dx%d but the experiment has %d tests and %d mutants.', ...
            size(R,1), size(R,2), env.totalTests, env.totalMutants);
    end

    verifyColumnIdentity(env, provenance);

    outDir = fullfile(fileparts(env.resultsDir), 'phase2', 'coverage_based');
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    fprintf('\n=== CruiseControl COVERAGE-BASED (Random Mutant protocol) ===\n');
    fprintf('MATLAB R%s | commit %s\n', env.matlabRelease, env.commit);
    fprintf('T_full = %.2f s\n', T_full);
    fprintf('R = %d tests x %d mutants (ones=%d zeros=%d NaN=%d)\n', ...
        size(R,1), size(R,2), sum(R(:)==1), sum(R(:)==0), sum(isnan(R(:))));
    fprintf('seeds = [%s]\n', num2str(opt.Seeds));
    fprintf('budgets:\n');
    for f = opt.BudgetFractions
        fprintf('   %3.0f%% -> %8.2f s\n', f*100, f*T_full);
    end
    fprintf('output: %s\n', outDir);

    plans = struct('seed', {}, 'order', {}, 'hash', {});
    for s = opt.Seeds
        order = mutationtool.RandomPlan.permutation(s, env.totalMutants);
        plans(end+1) = struct('seed', s, 'order', order, ...
            'hash', mutationtool.ExperimentPlan.orderHash(order)); %#ok<AGROW>
        fprintf('seed %d: hash=%s  first 10 = [%s ...]\n', s, plans(end).hash, ...
            num2str(order(1:min(10, end))));
    end

    if opt.DryRun
        fprintf('\nDryRun: nothing executed.\n');
        results = plans;
        return;
    end

    results = {};
    for pi = 1:numel(plans)
        for f = opt.BudgetFractions
            budget = f * T_full;
            tag = sprintf('seed%02d_b%03.0f', plans(pi).seed, f*100);
            outFile = fullfile(outDir, [tag '.mat']);

            if opt.Resume && exist(outFile, 'file')
                fprintf('\n[skip] %s already exists\n', tag);
                loaded = load(outFile, 'point');
                results{end+1} = loaded.point; %#ok<AGROW>
                continue;
            end

            fprintf('\n--- %s: budget %.2f s (%.0f%% of T_full) ---\n', tag, budget, f*100);
            point = runOneBudgetPoint(env, R, plans(pi), budget, f, T_full);
            save(outFile, 'point');
            results{end+1} = point; %#ok<AGROW>

            fprintf(['   evaluated=%d/%d  elapsed=%.2f s  overshoot=%+.2f s  ' ...
                     'killed=%d survived=%d  pairs=%d (removed %d)\n'], ...
                point.mutantsEvaluated, env.totalMutants, point.elapsedPhase, ...
                point.overshoot, point.killed, point.survived, ...
                point.pairsExecuted, point.selector.totalRemoved);
            if ~point.traceValid
                fprintf(2, '   *** telemetry failures=%d -> INVALID ***\n', ...
                    point.telemetryFailureCount);
            end
        end
    end

    summaryFile = fullfile(outDir, 'coverage_based_summary.mat');
    save(summaryFile, 'results');
    fprintf('\nsaved: %s\n', summaryFile);
end

% ----------------------------------------------------------------------
function point = runOneBudgetPoint(env, R, plan, budget, fraction, T_full)
    cc_clean_session(env);

    recorder = TestTraceRecorder();
    mutationtool.ExperimentPlan.resetTelemetryFailures();

    orch = mutationtool.Orchestrator();
    orch.loadConfig(env.configPath);

    cfg = orch.Config;
    % Complete permutation, NO limit: the wall clock decides where it stops.
    cfg.mutantPlan = struct('order', plan.order, 'limit', []);
    cfg.telemetry = struct('onTestExecuted', recorder.sink());
    % The single strategy-specific line. No testPlan: tests keep ascending
    % pool order, the selector only removes from it.
    selector = phase2.TestSelector(R, 'filtered', plan.order);
    cfg.testSelector = @selector.select;
    orch.setConfig(cfg);

    governor = MutantBudgetGovernor(orch, budget);
    orch.addObserver(governor);
    orch.addObserver(selector);
    orch.addObserver(recorder);

    tTotal = tic;
    orch.run();
    totalWall = toc(tTotal);

    ctx = orch.Context;
    if isempty(ctx.StartTime) || isempty(ctx.EndTime)
        error('run_cruisecontrol_coverage_based:NoExecutionWindow', ...
            'No execution window (state=%s).', ctx.State);
    end
    elapsedPhase = seconds(ctx.EndTime - ctx.StartTime);

    telemetry = mutationtool.ExperimentPlan.telemetryFailureStats();
    T = recorder.table();
    M = T(T.isBaseline == 0, :);

    point = struct();
    point.method = 'coverage_based';
    point.subject = 'CruiseControl';
    point.seed = plan.seed;
    point.fullOrder = plan.order;
    point.fullOrderHash = plan.hash;
    point.budgetFraction = fraction;
    point.budget = budget;
    point.T_full = T_full;
    point.elapsedPhase = elapsedPhase;
    point.elapsedTotal = totalWall;
    point.overshoot = elapsedPhase - budget;
    point.stopIssued = governor.StopIssued;
    point.stopAfterMutant = governor.StopAfterMutant;
    point.mutantsEvaluated = ctx.KilledCount + ctx.SurvivedCount;
    point.executedOrder = plan.order(1:min(point.mutantsEvaluated, numel(plan.order)));
    point.prefixOrderHash = mutationtool.ExperimentPlan.orderHash(point.executedOrder);
    point.killed = ctx.KilledCount;
    point.survived = ctx.SurvivedCount;
    point.errors = ctx.ErrorCount;
    if point.mutantsEvaluated > 0
        point.mutationScore = 100 * ctx.KilledCount / point.mutantsEvaluated;
    else
        point.mutationScore = NaN;
    end
    point.populationKillCoverage = 100 * ctx.KilledCount / env.totalMutants;
    point.pairsExecuted = height(M);
    point.selector = selector.summary();
    point.telemetryFailureCount = telemetry.count;
    point.traceValid = (telemetry.count == 0);
    point.traceSummary = recorder.summary();
    point.testTrace = T;
    point.timestamp = datetime('now');
end

% ----------------------------------------------------------------------
function verifyColumnIdentity(env, provenance)
% Re-enumerate the mutants and compare SSIdNumbers against the record made
% when R was built. Enumeration must produce the same targets in the same
% order or every column lookup is silently wrong.
    orch = mutationtool.Orchestrator(); %#ok<NASGU>  % ensures package on path
    engine = mutationtool.MutationEngine.createWithDefaultOperators();
    cfgLoader = mutationtool.Orchestrator();
    cfgLoader.loadConfig(env.configPath);
    cfg = cfgLoader.Config;
    if ~bdIsLoaded(cfg.model)
        load_system(cfg.model);
    end
    engine.discoverStateflow(cfg.model);
    muts = engine.findAllMutants(cfg);
    if numel(muts) ~= env.totalMutants
        error('run_cruisecontrol_coverage_based:MutantCountChanged', ...
            'Enumerated %d mutants, R has %d columns.', numel(muts), env.totalMutants);
    end
    sids = cellfun(@(m) double(m.target.SSIdNumber), muts);
    recorded = double(provenance.columnSSId(:))';
    if ~isequal(sids(:)', recorded)
        error('run_cruisecontrol_coverage_based:ColumnIdentityMismatch', ...
            ['Mutant enumeration no longer matches the SSIdNumber record R ' ...
             'was built with. Regenerate reachability_R.mat before running.']);
    end
    fprintf('column-identity guard: %d mutants, SSIdNumbers match R provenance\n', ...
        numel(muts));
end

% ----------------------------------------------------------------------
function T_full = resolveTFull(given, env)
    if ~isempty(given)
        T_full = given;
        return;
    end
    baselineFile = fullfile(env.resultsDir, 'baseline.mat');
    if ~exist(baselineFile, 'file')
        error('run_cruisecontrol_coverage_based:NoBaseline', ...
            ['No desktop baseline at\n  %s\nRun run_cruisecontrol_baseline ' ...
             'first, or pass ''TFull'', <seconds>.'], baselineFile);
    end
    loaded = load(baselineFile, 'result');
    T_full = loaded.result.T_full_mutation_phase;
end
