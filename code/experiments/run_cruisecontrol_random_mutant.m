function results = run_cruisecontrol_random_mutant(varargin)
% NOTE: Identifiers of the mutation tool have been genericized as
% 'mutationtool.*'. The experiments were executed with MUT4SLX (not
% included in this package); these scripts are provided for inspection
% and require the tool to be obtained separately to execute.
% RUN_CRUISECONTROL_RANDOM_MUTANT Random Mutant JIT experiment on CC1
%
% The CruiseControl-1 counterpart of run_cruisecontrol2_random_mutant,
% under EXACTLY the shared protocol so points are directly comparable with
% the CC1 Coverage-Based grid:
%
%   T_full          from results/CruiseControl/phase1/baseline.mat
%   budgets         {0.02 0.04 0.06 0.08 0.10 0.20 0.30 0.40 0.50} x T_full
%   seeds           1..5, RandomPlan.permutation(seed, 67)
%   one permutation per seed, reused at every budget
%   budget rule     MutantBudgetGovernor - online, checked after each mutant
%                   completes; the in-flight mutant always finishes
%   early exit      unchanged
%   telemetry       TestTraceRecorder, same schema
%
% Random Mutant semantics: each selected mutant faces the FULL 15-test
% suite in ascending pool order (no selector, no filtering); a wall-clock
% budget decides how many mutants get evaluated. How many mutants a budget
% buys is an OUTPUT, never an input.
%
% Usage:
%   run_cruisecontrol_random_mutant                       % all 45 points
%   run_cruisecontrol_random_mutant('Seeds', 1)
%   run_cruisecontrol_random_mutant('DryRun', true)
%
% Name-value arguments:
%   Seeds            - Default 1:5
%   BudgetFractions  - Default [0.02 0.04 0.06 0.08 0.10 0.20 0.30 0.40 0.50]
%   TFull            - Default: T_full_mutation_phase from baseline.mat
%   Resume           - Skip points already on disk (default true)
%   DryRun           - Print the plan and exit
%
% Results go to results/CruiseControl/phase1/random_mutant/seedSS_bBBB.mat.
%
% See also: run_cruisecontrol_baseline, run_cruisecontrol_coverage_based,
%           run_cruisecontrol2_random_mutant, MutantBudgetGovernor, cc_env,
%           cc_clean_session

    p = inputParser;
    p.addParameter('Seeds', 1:5, @isnumeric);
    p.addParameter('BudgetFractions', ...
        [0.02 0.04 0.06 0.08 0.10 0.20 0.30 0.40 0.50], @isnumeric);
    p.addParameter('TFull', [], @(x) isempty(x) || (isscalar(x) && x > 0));
    p.addParameter('Resume', true, @(x) islogical(x) || isnumeric(x));
    p.addParameter('DryRun', false, @(x) islogical(x) || isnumeric(x));
    p.parse(varargin{:});
    opt = p.Results;

    env = cc_env();
    T_full = resolveTFull(opt.TFull, env);

    outDir = fullfile(env.resultsDir, 'random_mutant');
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    fprintf('\n=== CruiseControl-1 RANDOM MUTANT (desktop) ===\n');
    fprintf('MATLAB R%s | commit %s\n', env.matlabRelease, env.commit);
    fprintf('T_full (mutation phase) = %.2f s\n', T_full);
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
            point = runOneBudgetPoint(env, plans(pi), budget, f, T_full);
            save(outFile, 'point');
            results{end+1} = point; %#ok<AGROW>

            fprintf('   evaluated=%d/%d  elapsed=%.2f s  overshoot=%+.2f s  killed=%d survived=%d\n', ...
                point.mutantsEvaluated, env.totalMutants, point.elapsedPhase, ...
                point.overshoot, point.killed, point.survived);
            if ~point.traceValid
                fprintf(2, '   *** telemetry failures=%d -> INVALID ***\n', ...
                    point.telemetryFailureCount);
            end
        end
    end

    summaryFile = fullfile(outDir, 'random_mutant_summary.mat');
    save(summaryFile, 'results');
    fprintf('\nsaved: %s\n', summaryFile);
end

% ----------------------------------------------------------------------
function point = runOneBudgetPoint(env, plan, budget, fraction, T_full)
    session = cc_clean_session(env);

    recorder = TestTraceRecorder();
    mutationtool.ExperimentPlan.resetTelemetryFailures();

    orch = mutationtool.Orchestrator();
    orch.loadConfig(env.configPath);

    cfg = orch.Config;
    % Complete permutation, NO limit: the wall clock decides where it stops.
    cfg.mutantPlan = struct('order', plan.order, 'limit', []);
    cfg.telemetry = struct('onTestExecuted', recorder.sink());
    orch.setConfig(cfg);

    governor = MutantBudgetGovernor(orch, budget);
    orch.addObserver(governor);
    orch.addObserver(recorder);

    tTotal = tic;
    orch.run();
    totalWall = toc(tTotal);

    ctx = orch.Context;
    if isempty(ctx.StartTime) || isempty(ctx.EndTime)
        error('run_cruisecontrol_random_mutant:NoExecutionWindow', ...
            'No execution window (state=%s).', ctx.State);
    end
    elapsedPhase = seconds(ctx.EndTime - ctx.StartTime);

    telemetry = mutationtool.ExperimentPlan.telemetryFailureStats();

    point = struct();
    point.method = 'random_mutant';
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
    point.session = session;
    point.telemetryFailureCount = telemetry.count;
    point.traceValid = (telemetry.count == 0);
    point.traceSummary = recorder.summary();
    point.testTrace = recorder.table();
    point.timestamp = datetime('now');
end

% ----------------------------------------------------------------------
function T_full = resolveTFull(given, env)
    if ~isempty(given)
        T_full = given;
        return;
    end
    baselineFile = fullfile(env.resultsDir, 'baseline.mat');
    if ~exist(baselineFile, 'file')
        error('run_cruisecontrol_random_mutant:NoBaseline', ...
            ['No desktop baseline at\n  %s\nRun run_cruisecontrol_baseline ' ...
             'first, or pass ''TFull'', <seconds>.'], baselineFile);
    end
    loaded = load(baselineFile, 'result');
    T_full = loaded.result.T_full_mutation_phase;
end
