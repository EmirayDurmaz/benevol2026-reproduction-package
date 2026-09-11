function results = run_hybridfsm_random_test_phase1(varargin)
% NOTE: Identifiers of the mutation tool have been genericized as
% 'mutationtool.*'. The experiments were executed with MUT4SLX (not
% included in this package); these scripts are provided for inspection
% and require the tool to be obtained separately to execute.
% RUN_HYBRIDFSM_RANDOM_TEST_PHASE1 Random Test JIT experiment, desktop
%
% Random Test semantics, which are NOT the Random Mutant semantics:
%   one uniform random permutation of the 25 tests per seed
%   -> a prefix length k is fixed UP FRONT
%   -> ALL 183 mutants are then evaluated against that SAME prefix
%   -> existing per-mutant early exit stays active
%
% WHY THE RUN IS NEVER CUT SHORT BY THE CLOCK
% A mutation score only means something if every mutant faced the same
% tests. Stopping halfway through the mutant set because a wall-clock
% budget expired would leave a score computed over a different test regime
% for different mutants - not a noisier measurement, a meaningless one. So
% here the budget acts BEFORE the run, by choosing k; the run itself always
% goes to completion over all 183 mutants, and its actual runtime is
% measured afterwards.
%
% k IS PLANNED FROM COST, BEFORE ANY MUTATION RUNS
% k comes from a conservative pre-execution cost model built ONLY from the
% original, unmutated model:
%
%   predictedCost(k) = N_mutants * sum(testCost(order(1:k)))
%   k = max { k : predictedCost(k) <= targetBudgetSeconds }
%
% testCost is the per-test runtime of the baseline suite on the UNMUTATED
% model (the isBaseline rows of baseline_test_trace.csv). No kill positions,
% no failedTests, no survivor counts and no mutant execution traces enter
% the planning, so k cannot be tuned by the outcomes it is meant to predict.
%
% The model assumes NO early exit: every mutant is charged for every
% selected test. Real runs finish sooner because killed mutants stop early,
% so predictedCost is an upper bound and measured runtime lands under the
% target. That undershoot is a RESULT of the static planner - reported as
% budgetUtilizationPct / undershootSeconds - not something to correct. k is
% never grown during execution.
%
% This replaces the earlier k = ceil(fraction x 25) planner, which assumed
% runtime scales with prefix length. It did not: tests differ in cost by
% 2.1x, and every one of its points overshot its label (the "10%" point
% consumed 16.9% of T_full on average, worst case 20.0%).
%
% INFEASIBLE POINTS ARE A REAL RESULT
% If even the first test of a seed's permutation exceeds the budget, no
% prefix satisfies the constraint and the correct answer is k = 0. Such a
% point is recorded with status 'infeasible_no_test_fits' and is NOT
% executed. It is never promoted to k = 1 and the budget grid is never
% adjusted to make it disappear.
%
% Usage (from the MATLAB Command Window):
%   run_hybridfsm_random_test_phase1                      % all 5 seeds
%   run_hybridfsm_random_test_phase1('Seeds', 1)          % one seed
%   run_hybridfsm_random_test_phase1('DryRun', true)      % plan only
%
% Name-value arguments:
%   Seeds            - Default 1:5
%   BudgetFractions  - Default [0.10 0.20 0.30 0.40 0.50], the Phase 1 grid.
%                      A bare invocation therefore cannot execute the older
%                      70%/100% points.
%   PrefixLengths    - Override k directly, bypassing the cost planner.
%                      Diagnostic escape hatch; the planned k is then not
%                      budget-derived and status is 'manual_prefix'.
%   TFull            - Denominator in seconds; default from the desktop
%                      baseline saved by run_hybridfsm_phase1_baseline
%   CostFile         - Baseline test trace CSV supplying per-test cost;
%                      default <resultsDir>/baseline_test_trace.csv
%   IncludeOverhead  - Add the per-mutant framework overhead to
%                      predictedCost (default false). Kept off because the
%                      only available estimate is derived from the baseline
%                      run's MUTANT rows, which the leakage rule excludes
%                      from planning. It shifts k in 2 of 25 grid cells.
%   DryRun           - Print the plan and exit
%   Resume           - Skip (seed,k) points already on disk (default false).
%                      Off by default because the results directory may hold
%                      points from the superseded length-based planner whose
%                      file names collide with cost-planned k values.
%
% See also: phase1_env, mutationtool.RandomPlan, mutationtool.ExperimentPlan,
%           run_hybridfsm_phase1_baseline

    p = inputParser;
    p.addParameter('Seeds', 1:5, @isnumeric);
    p.addParameter('BudgetFractions', [0.10 0.20 0.30 0.40 0.50], @isnumeric);
    p.addParameter('PrefixLengths', [], @isnumeric);
    p.addParameter('TFull', [], @(x) isempty(x) || (isscalar(x) && x > 0));
    p.addParameter('CostFile', '', @(x) ischar(x) || isstring(x));
    p.addParameter('IncludeOverhead', false, @(x) islogical(x) || isnumeric(x));
    p.addParameter('DryRun', false, @(x) islogical(x) || isnumeric(x));
    p.addParameter('Resume', false, @(x) islogical(x) || isnumeric(x));
    p.parse(varargin{:});
    opt = p.Results;

    env = phase1_env();
    T_full = resolveTFull(opt.TFull, env);
    [testCost, costFile] = loadOriginalTestCosts(opt.CostFile, env);

    overheadPerMutant = 0;
    if opt.IncludeOverhead
        overheadPerMutant = resolveOverheadPerMutant(costFile, env, T_full);
    end
    overheadTotal = env.totalMutants * overheadPerMutant;

    outDir = fullfile(env.resultsDir, 'random_test');
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    fprintf('\n=== HybridFSM Phase 1 RANDOM TEST (desktop, cost-based planner) ===\n');
    fprintf('MATLAB R%s | commit %s\n', env.matlabRelease, env.commit);
    fprintf('T_full (mutation phase) = %.2f s\n', T_full);
    fprintf('per-test cost source    = %s\n', costFile);
    fprintf('sum(testCost)           = %.4f s over %d tests\n', sum(testCost), numel(testCost));
    fprintf('N * sum(testCost)       = %.2f s  (predicted cost of the FULL prefix)\n', ...
        env.totalMutants * sum(testCost));
    if opt.IncludeOverhead
        fprintf('framework overhead      = %.4f s/mutant -> %.2f s added to every prediction\n', ...
            overheadPerMutant, overheadTotal);
    else
        fprintf('framework overhead      = excluded (leakage rule); predictedCost is test time only\n');
    end
    fprintf('seeds = [%s]\n', num2str(opt.Seeds));

    % --- Plan every (seed, budget) point BEFORE anything executes --------
    plan = planAllPoints(opt, env, T_full, testCost, overheadTotal);
    printPlan(plan, env);

    if opt.DryRun
        fprintf('\nDryRun: nothing executed.\n');
        results = plan;
        return;
    end

    % Clear superseded points for the seeds about to be rerun, so the
    % directory ends up holding exactly this planner's grid instead of a
    % mixture with the old length-based one (whose file names collide).
    clearStalePoints(outDir, opt.Seeds);

    results = {};
    for i = 1:numel(plan)
        pt = plan(i);
        tag = sprintf('seed%02d_k%02d', pt.seed, pt.k);
        outFile = fullfile(outDir, [tag '.mat']);

        if opt.Resume && exist(outFile, 'file')
            fprintf('\n[skip] %s already exists\n', tag);
            loaded = load(outFile, 'point');
            results{end+1} = loaded.point; %#ok<AGROW>
            continue;
        end

        if pt.k == 0
            % Conservative planner admits no prefix at this budget. Recorded
            % as the experimental outcome it is; nothing is executed.
            fprintf('\n--- %s: INFEASIBLE at %.0f%% (target %.2f s) ---\n', ...
                tag, pt.fraction*100, pt.targetBudgetSeconds);
            fprintf('   cheapest available first test T%d costs %.4f s -> predicted %.2f s, exceeds target by %.2f s\n', ...
                pt.firstTestIndex, pt.firstTestCost, pt.firstTestPredictedCost, pt.firstTestExcessSeconds);
            point = buildInfeasiblePoint(pt, env, T_full, costFile, opt.IncludeOverhead, overheadPerMutant);
            save(outFile, 'point');
            results{end+1} = point; %#ok<AGROW>
            continue;
        end

        fprintf('\n--- %s: %.0f%% budget, prefix [%s] over all %d mutants ---\n', tag, ...
            pt.fraction*100, num2str(pt.prefix), env.totalMutants);
        point = runOnePrefixPoint(env, pt, T_full);
        point = attachPlanMetadata(point, pt, costFile, opt.IncludeOverhead, overheadPerMutant, env);
        save(outFile, 'point');
        results{end+1} = point; %#ok<AGROW>

        fprintf('   elapsed=%.2f s  target=%.2f s  utilization=%.1f%%  undershoot=%.2f s\n', ...
            point.actualMutationPhaseSeconds, point.targetBudgetSeconds, ...
            point.budgetUtilizationPct, point.undershootSeconds);
        fprintf('   killed=%d survived=%d  mutationCoverage=%.2f%%\n', ...
            point.killedMutants, point.survived, point.mutationCoverage);
        if ~point.traceValid
            fprintf(2, '   *** telemetry failures=%d -> INVALID ***\n', point.telemetryFailureCount);
        end
        if ~point.samePrefixEverywhere
            fprintf(2, '   *** prefix was NOT identical across mutants -> INVALID ***\n');
        end
    end

    summaryFile = fullfile(outDir, 'random_test_summary.mat');
    save(summaryFile, 'results');
    fprintf('\nsaved: %s\n', summaryFile);
end

% ----------------------------------------------------------------------
function point = runOnePrefixPoint(env, pt, T_full)
    plan = struct('seed', pt.seed, 'order', pt.order, 'hash', pt.orderHash);
    k = pt.k;
    fraction = pt.fraction;
    % Same starting state for every point, so a later prefix is not slower
    % simply for having run later.
    session = phase1_clean_session(env);

    recorder = TestTraceRecorder();
    mutationtool.ExperimentPlan.resetTelemetryFailures();

    orch = mutationtool.Orchestrator();
    orch.loadConfig(env.configPath);

    cfg = orch.Config;
    % Full permutation plus limit: ExperimentPlan hands the SAME prefix to
    % every mutant, and keeps the complete order for the provenance hash.
    cfg.testPlan = struct('order', plan.order, 'limit', k);
    cfg.telemetry = struct('onTestExecuted', recorder.sink());
    orch.setConfig(cfg);
    orch.addObserver(recorder);

    tTotal = tic;
    orch.run();
    totalWall = toc(tTotal);

    ctx = orch.Context;
    if isempty(ctx.StartTime) || isempty(ctx.EndTime)
        error('run_hybridfsm_random_test_phase1:NoExecutionWindow', ...
            'No execution window (state=%s).', ctx.State);
    end
    elapsedPhase = seconds(ctx.EndTime - ctx.StartTime);

    telemetry = mutationtool.ExperimentPlan.telemetryFailureStats();

    point = struct();
    point.method = 'random_test';
    point.seed = plan.seed;
    point.fullOrder = plan.order;
    point.fullOrderHash = plan.hash;
    point.prefixLength = k;
    point.executedPrefix = plan.order(1:k);
    point.prefixOrderHash = mutationtool.ExperimentPlan.orderHash(point.executedPrefix);
    point.budgetFraction = fraction;
    point.predictedBudget = fraction * T_full;
    point.T_full = T_full;
    point.elapsedPhase = elapsedPhase;
    point.elapsedTotal = totalWall;
    point.predictionError = elapsedPhase - point.predictedBudget;
    point.mutantsEvaluated = ctx.KilledCount + ctx.SurvivedCount;
    point.killed = ctx.KilledCount;
    point.survived = ctx.SurvivedCount;
    point.errors = ctx.ErrorCount;
    if point.mutantsEvaluated > 0
        point.mutationScore = 100 * ctx.KilledCount / point.mutantsEvaluated;
    else
        point.mutationScore = NaN;
    end
    point.session = session;
    point.telemetryFailureCount = telemetry.count;
    point.traceValid = (telemetry.count == 0);
    point.traceSummary = recorder.summary();
    point.testTrace = recorder.table();
    point.samePrefixEverywhere = checkSamePrefix(point.testTrace, point.executedPrefix);
    point.timestamp = datetime('now');
end

% ----------------------------------------------------------------------
function [cost, srcFile] = loadOriginalTestCosts(given, env)
    % LOADORIGINALTESTCOSTS Per-test runtime on the UNMUTATED model
    %
    % The only cost source the planner is allowed to see. These are the
    % isBaseline rows of the baseline trace: the suite executed once against
    % the original model, before any mutation existed. Nothing here depends
    % on a mutant, a kill or a survivor.

    srcFile = char(given);
    if isempty(srcFile)
        srcFile = fullfile(env.resultsDir, 'baseline_test_trace.csv');
    end
    if ~exist(srcFile, 'file')
        error('run_hybridfsm_random_test_phase1:NoCostData', ...
            ['No baseline test trace at\n  %s\n' ...
             'Run run_hybridfsm_phase1_baseline first, or pass ''CostFile'', <csv>.'], srcFile);
    end

    T = readtable(srcFile);
    required = {'isBaseline', 'testIndex', 'elapsedSeconds'};
    missing = required(~ismember(required, T.Properties.VariableNames));
    if ~isempty(missing)
        error('run_hybridfsm_random_test_phase1:BadCostData', ...
            'Cost file %s is missing column(s): %s', srcFile, strjoin(missing, ', '));
    end

    base = T(logical(T.isBaseline), :);
    if height(base) ~= env.totalTests
        error('run_hybridfsm_random_test_phase1:CostCountMismatch', ...
            ['Expected %d baseline test rows in %s, found %d. The cost model ' ...
             'must cover every test the permutation can select.'], ...
            env.totalTests, srcFile, height(base));
    end

    cost = nan(1, env.totalTests);
    cost(base.testIndex) = base.elapsedSeconds;
    if any(isnan(cost)) || any(cost <= 0)
        error('run_hybridfsm_random_test_phase1:BadCostValues', ...
            'Baseline costs must be positive and cover test indices 1..%d.', env.totalTests);
    end
end

% ----------------------------------------------------------------------
function h = resolveOverheadPerMutant(costFile, env, T_full)
    % RESOLVEOVERHEADPERMUTANT Framework (apply/revert/orchestration) cost
    %
    % Only used when IncludeOverhead is on. Off by default: the estimate is
    % T_full minus the summed MUTANT test rows, and those rows are mutant
    % execution trace - which the leakage rule keeps out of planning. It is
    % an aggregate, not an outcome, so the option exists; the default is the
    % strict reading.

    T = readtable(costFile);
    mutantRows = T(~logical(T.isBaseline), :);
    if isempty(mutantRows)
        error('run_hybridfsm_random_test_phase1:NoOverheadData', ...
            'Cannot estimate framework overhead: %s has no mutant rows.', costFile);
    end
    h = max(0, (T_full - sum(mutantRows.elapsedSeconds)) / env.totalMutants);
end

% ----------------------------------------------------------------------
function plan = planAllPoints(opt, env, T_full, testCost, overheadTotal)
    % PLANALLPOINTS Fix every (seed, budget) -> k before execution starts
    %
    % k = max { k : N*sum(testCost(order(1:k))) [+ overheadTotal] <= budget }
    %
    % k = 0 when not even the first test fits. That is kept, not rounded up.

    plan = struct('seed', {}, 'order', {}, 'orderHash', {}, 'fraction', {}, ...
        'targetBudgetSeconds', {}, 'k', {}, 'prefix', {}, ...
        'predictedCostSeconds', {}, 'firstTestIndex', {}, 'firstTestCost', {}, ...
        'firstTestPredictedCost', {}, 'firstTestExcessSeconds', {}, 'status', {});

    manualK = opt.PrefixLengths;

    for s = opt.Seeds
        order = mutationtool.RandomPlan.permutation(s, env.totalTests);
        hash = mutationtool.ExperimentPlan.orderHash(order);
        cumCost = cumsum(testCost(order));
        predicted = env.totalMutants * cumCost + overheadTotal;

        for bi = 1:numel(opt.BudgetFractions)
            f = opt.BudgetFractions(bi);
            B = f * T_full;

            if ~isempty(manualK)
                k = manualK(min(bi, numel(manualK)));
                status = 'manual_prefix';
            else
                k = find(predicted <= B, 1, 'last');
                if isempty(k), k = 0; end
                if k == 0
                    status = 'infeasible_no_test_fits';
                else
                    status = 'planned';
                end
            end

            firstCost = testCost(order(1));
            firstPredicted = env.totalMutants * firstCost + overheadTotal;

            entry = struct();
            entry.seed = s;
            entry.order = order;
            entry.orderHash = hash;
            entry.fraction = f;
            entry.targetBudgetSeconds = B;
            entry.k = k;
            if k > 0
                entry.prefix = order(1:k);
                entry.predictedCostSeconds = predicted(k);
            else
                entry.prefix = [];
                entry.predictedCostSeconds = 0;
            end
            entry.firstTestIndex = order(1);
            entry.firstTestCost = firstCost;
            entry.firstTestPredictedCost = firstPredicted;
            entry.firstTestExcessSeconds = firstPredicted - B;
            entry.status = status;
            plan(end+1) = entry; %#ok<AGROW>
        end
    end
end

% ----------------------------------------------------------------------
function printPlan(plan, env)
    fprintf('\n--- PLAN (fixed before execution) ---\n');
    fprintf('%-5s %-7s %-11s %-3s %-13s %-24s %s\n', ...
        'seed', 'budget', 'target(s)', 'k', 'predicted(s)', 'prefix', 'status');
    for i = 1:numel(plan)
        p = plan(i);
        if p.k > 0
            prefixStr = num2str(p.prefix);
        else
            prefixStr = '(none)';
        end
        if numel(prefixStr) > 23
            prefixStr = [prefixStr(1:20) '...'];
        end
        fprintf('%-5d %-7s %-11.2f %-3d %-13.2f %-24s %s\n', ...
            p.seed, sprintf('%.0f%%', p.fraction*100), p.targetBudgetSeconds, ...
            p.k, p.predictedCostSeconds, prefixStr, p.status);
    end
    nInf = sum(strcmp({plan.status}, 'infeasible_no_test_fits'));
    if nInf > 0
        fprintf('%d of %d points are INFEASIBLE and will not be executed.\n', nInf, numel(plan));
    end
    fprintf('total mutants per executed point: %d\n', env.totalMutants);
end

% ----------------------------------------------------------------------
function clearStalePoints(outDir, seeds)
    % CLEARSTALEPOINTS Drop earlier points for the seeds being rerun
    %
    % The directory may still hold points from the superseded length-based
    % planner (k = 3,5,8,10,13,25). Their file names collide with
    % cost-planned k values and both consumers glob seed*.mat, so leaving
    % them would silently mix two planners in one curve.

    for s = seeds
        stale = dir(fullfile(outDir, sprintf('seed%02d_k*.mat', s)));
        for i = 1:numel(stale)
            f = fullfile(outDir, stale(i).name);
            delete(f);
            fprintf('[clean] removed superseded point %s\n', stale(i).name);
        end
    end
end

% ----------------------------------------------------------------------
function point = attachPlanMetadata(point, pt, costFile, includeOverhead, overheadPerMutant, env)
    % ATTACHPLANMETADATA Budget accounting on top of the executed result
    point.status = pt.status;
    point.targetBudgetPct = pt.fraction * 100;
    point.targetBudgetSeconds = pt.targetBudgetSeconds;
    point.predictedCostSeconds = pt.predictedCostSeconds;
    point.actualMutationPhaseSeconds = point.elapsedPhase;
    point.undershootSeconds = pt.targetBudgetSeconds - point.elapsedPhase;
    if pt.targetBudgetSeconds > 0
        point.budgetUtilizationPct = 100 * point.elapsedPhase / pt.targetBudgetSeconds;
    else
        point.budgetUtilizationPct = NaN;
    end
    point.killedMutants = point.killed;
    point.mutationCoverage = 100 * point.killed / env.totalMutants;
    point.selectedPrefix = pt.prefix;
    point.plannerCostFile = costFile;
    point.plannerIncludesOverhead = logical(includeOverhead);
    point.plannerOverheadPerMutant = overheadPerMutant;
    point.firstTestIndex = pt.firstTestIndex;
    point.firstTestCost = pt.firstTestCost;
    point.firstTestPredictedCost = pt.firstTestPredictedCost;
    point.firstTestExcessSeconds = pt.firstTestExcessSeconds;
end

% ----------------------------------------------------------------------
function point = buildInfeasiblePoint(pt, ~, T_full, costFile, includeOverhead, overheadPerMutant)
    % BUILDINFEASIBLEPOINT Record a budget that admits no prefix at all
    %
    % Nothing is executed, so every measured quantity is zero by definition
    % rather than missing. The first-test figures explain WHY the point is
    % infeasible without needing the run.

    point = struct();
    point.method = 'random_test';
    point.status = pt.status;
    point.seed = pt.seed;
    point.fullOrder = pt.order;
    point.fullOrderHash = pt.orderHash;
    point.prefixLength = 0;
    point.selectedPrefix = [];
    point.executedPrefix = [];
    point.prefixOrderHash = '';
    point.budgetFraction = pt.fraction;
    point.targetBudgetPct = pt.fraction * 100;
    point.targetBudgetSeconds = pt.targetBudgetSeconds;
    point.predictedCostSeconds = 0;
    point.predictedBudget = pt.targetBudgetSeconds;
    point.T_full = T_full;
    point.actualMutationPhaseSeconds = 0;
    point.elapsedPhase = 0;
    point.elapsedTotal = 0;
    point.budgetUtilizationPct = 0;
    point.undershootSeconds = pt.targetBudgetSeconds;
    point.predictionError = 0;
    point.mutantsEvaluated = 0;
    point.killed = 0;
    point.killedMutants = 0;
    point.survived = 0;
    point.errors = 0;
    point.mutationScore = 0;
    point.mutationCoverage = 0;
    % Why it is infeasible: the cheapest prefix possible is the first test.
    point.firstTestIndex = pt.firstTestIndex;
    point.firstTestCost = pt.firstTestCost;
    point.firstTestPredictedCost = pt.firstTestPredictedCost;
    point.firstTestExcessSeconds = pt.firstTestExcessSeconds;
    point.plannerCostFile = costFile;
    point.plannerIncludesOverhead = logical(includeOverhead);
    point.plannerOverheadPerMutant = overheadPerMutant;
    point.session = struct();
    point.telemetryFailureCount = 0;
    point.traceValid = true;
    point.traceSummary = struct();
    point.testTrace = table();
    point.samePrefixEverywhere = true;
    point.timestamp = datetime('now');
end

% ----------------------------------------------------------------------
function tf = checkSamePrefix(T, expectedPrefix)
    % Every mutant must have seen the same prefix, in the same order, up to
    % the point where early exit stopped it. Verified from the trace rather
    % than assumed from the config - this is the invariant the whole method
    % rests on.
    tf = true;
    if isempty(T) || ~ismember('mutantExecutionOrder', T.Properties.VariableNames)
        tf = false;
        return;
    end
    mutantRows = T(~T.isBaseline, :);
    if isempty(mutantRows)
        tf = false;
        return;
    end
    for m = unique(mutantRows.mutantExecutionOrder)'
        seen = mutantRows.testIndex(mutantRows.mutantExecutionOrder == m)';
        if ~isequal(seen, expectedPrefix(1:numel(seen)))
            tf = false;
            return;
        end
    end
end

% ----------------------------------------------------------------------
function T_full = resolveTFull(given, env)
    if ~isempty(given)
        T_full = given;
        return;
    end
    baselineFile = fullfile(env.resultsDir, 'baseline.mat');
    if ~exist(baselineFile, 'file')
        error('run_hybridfsm_random_test_phase1:NoBaseline', ...
            ['No desktop baseline found at\n  %s\n' ...
             'Run run_hybridfsm_phase1_baseline first, or pass ''TFull'', <seconds>.'], ...
            baselineFile);
    end
    loaded = load(baselineFile, 'result');
    T_full = loaded.result.T_full_mutation_phase;
end
