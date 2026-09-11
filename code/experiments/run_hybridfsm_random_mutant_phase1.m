function results = run_hybridfsm_random_mutant_phase1(varargin)
% NOTE: Identifiers of the mutation tool have been genericized as
% 'mutationtool.*'. The experiments were executed with MUT4SLX (not
% included in this package); these scripts are provided for inspection
% and require the tool to be obtained separately to execute.
% RUN_HYBRIDFSM_RANDOM_MUTANT_PHASE1 Random Mutant JIT experiment, desktop
%
% Random Mutant semantics:
%   one uniform random mutant permutation per seed
%   -> each selected mutant is tested against the FULL 25-test suite
%   -> existing the mutation tool early exit is untouched
%   -> a WALL-CLOCK budget decides how many mutants get evaluated
%
% THE BUDGET IS TIME, NOT A MUTANT PERCENTAGE
% A 30% budget is 0.30 x T_full_mutation_phase of wall clock. How many
% mutants that buys is an OUTPUT of the run, never an input: mutants cost
% wildly different amounts depending on where early exit lands, so fixing
% the count would answer a different question entirely.
%
% ONE PERMUTATION PER SEED, REUSED AT EVERY BUDGET
% Every budget point of a seed executes a growing prefix of the SAME
% permutation, so the curve across budgets comes from one random world
% rather than from six unrelated draws. RandomPlan guarantees the
% permutation is complete; the budget, not a limit, decides where it stops.
%
% Usage (from the MATLAB Command Window):
%   run_hybridfsm_random_mutant_phase1                      % all 5 seeds
%   run_hybridfsm_random_mutant_phase1('Seeds', 1)          % one seed
%   run_hybridfsm_random_mutant_phase1('DryRun', true)      % plan only, no exec
%
% Name-value arguments:
%   Seeds            - Default 1:5
%   BudgetFractions  - Default [0.10 0.20 0.30 0.40 0.50], the Phase 1 grid.
%                      A bare invocation therefore cannot execute the older
%                      70%/100% points.
%   TFull            - Denominator in seconds. Default: read from the
%                      desktop baseline result saved by
%                      run_hybridfsm_phase1_baseline.
%   DryRun           - Print the plan and exit without executing
%   Resume           - Skip (seed,budget) points already on disk (default true)
%
% Runtime warning: the default fractions sum to 1.5, so one seed costs about
% 1.5 x T_full and five seeds about 7.5 x T_full, plus one baseline suite per
% point.
%
% See also: phase1_env, MutantBudgetGovernor, mutationtool.RandomPlan,
%           run_hybridfsm_phase1_baseline

    p = inputParser;
    p.addParameter('Seeds', 1:5, @isnumeric);
    p.addParameter('BudgetFractions', [0.10 0.20 0.30 0.40 0.50], @isnumeric);
    p.addParameter('TFull', [], @(x) isempty(x) || (isscalar(x) && x > 0));
    p.addParameter('DryRun', false, @(x) islogical(x) || isnumeric(x));
    p.addParameter('Resume', true, @(x) islogical(x) || isnumeric(x));
    p.parse(varargin{:});
    opt = p.Results;

    env = phase1_env();
    T_full = resolveTFull(opt.TFull, env);

    outDir = fullfile(env.resultsDir, 'random_mutant');
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    fprintf('\n=== HybridFSM Phase 1 RANDOM MUTANT (desktop) ===\n');
    fprintf('MATLAB R%s | commit %s\n', env.matlabRelease, env.commit);
    fprintf('T_full (mutation phase) = %.2f s\n', T_full);
    fprintf('seeds = [%s]\n', num2str(opt.Seeds));
    fprintf('budgets:\n');
    for f = opt.BudgetFractions
        fprintf('   %3.0f%% -> %8.2f s\n', f*100, f*T_full);
    end

    % --- The permutations: one per seed, drawn up front ------------------
    plans = struct('seed', {}, 'order', {}, 'hash', {});
    for s = opt.Seeds
        order = mutationtool.RandomPlan.permutation(s, env.totalMutants);
        plans(end+1) = struct('seed', s, 'order', order, ...
            'hash', mutationtool.ExperimentPlan.orderHash(order)); %#ok<AGROW>
        fprintf('seed %d: hash=%s  first 10 = [%s ...]\n', s, plans(end).hash, ...
            num2str(order(1:min(10,end))));
    end

    if opt.DryRun
        fprintf('\nDryRun: nothing executed.\n');
        results = plans;
        return;
    end

    % --- Execute ----------------------------------------------------------
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
                fprintf(2, '   *** telemetry failures=%d -> INVALID ***\n', point.telemetryFailureCount);
            end
        end
    end

    summaryFile = fullfile(outDir, 'random_mutant_summary.mat');
    save(summaryFile, 'results');
    fprintf('\nsaved: %s\n', summaryFile);
end

% ----------------------------------------------------------------------
function point = runOneBudgetPoint(env, plan, budget, fraction, T_full)
    % Same starting state for every point: seed 5 must not be slower than
    % seed 1 merely because thousands of result sets accumulated in between.
    session = phase1_clean_session(env);

    recorder = TestTraceRecorder();
    mutationtool.ExperimentPlan.resetTelemetryFailures();

    orch = mutationtool.Orchestrator();
    orch.loadConfig(env.configPath);

    cfg = orch.Config;
    % Complete permutation, NO limit: wall clock decides where it stops.
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
        error('run_hybridfsm_random_mutant_phase1:NoExecutionWindow', ...
            'No execution window (state=%s).', ctx.State);
    end
    elapsedPhase = seconds(ctx.EndTime - ctx.StartTime);

    telemetry = mutationtool.ExperimentPlan.telemetryFailureStats();

    point = struct();
    point.method = 'random_mutant';
    point.seed = plan.seed;
    point.fullOrderHash = plan.hash;
    point.fullOrder = plan.order;
    point.budgetFraction = fraction;
    point.budget = budget;
    point.T_full = T_full;
    point.elapsedPhase = elapsedPhase;
    point.elapsedTotal = totalWall;
    point.overshoot = elapsedPhase - budget;       % >0 overshoot, <0 undershoot
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
        error('run_hybridfsm_random_mutant_phase1:NoBaseline', ...
            ['No desktop baseline found at\n  %s\n' ...
             'Run run_hybridfsm_phase1_baseline first, or pass ''TFull'', <seconds>. ' ...
             'The historical 623.11 s is deliberately NOT used as a fallback - ' ...
             'it came from a different environment.'], baselineFile);
    end
    loaded = load(baselineFile, 'result');
    T_full = loaded.result.T_full_mutation_phase;
end
