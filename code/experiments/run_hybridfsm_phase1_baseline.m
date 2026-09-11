function result = run_hybridfsm_phase1_baseline()
% NOTE: Identifiers of the mutation tool have been genericized as
% 'mutationtool.*'. The experiments were executed with MUT4SLX (not
% included in this package); these scripts are provided for inspection
% and require the tool to be obtained separately to execute.
% RUN_HYBRIDFSM_PHASE1_BASELINE Full unsampled HybridFSM run, desktop MATLAB
%
% The Phase 1 reference point: all 183 mutants, each against the full
% 25-test suite, default early exit, no plans and no samplers. Everything
% the JIT budgets are a fraction OF is measured here, so this must run in
% the same desktop session as the Random Mutant and Random Test runners -
% a batch session measured roughly twice the per-mutant cost, which would
% make any cross-environment comparison meaningless.
%
% Usage (from the MATLAB Command Window):
%   run_hybridfsm_phase1_baseline
%
% Requires no interactive input. Expect roughly 10-20 minutes.
%
% TWO TIMING SCOPES, BOTH SAVED
%   T_full_mutation_phase - RunContext StartTime..EndTime, the window
%                           Orchestrator opens at startExecution and closes
%                           at completeExecution. This is the mutation
%                           workload alone: no setup, no model load, no
%                           mutant discovery, no baseline suite, no
%                           reporting. It is ALSO exactly what the mutation tool has
%                           always printed as "Script executed in", so the
%                           historical 623.11 s was never end-to-end.
%   T_full_total          - the whole orchestration, loadConfig through
%                           run() returning. Reported as a secondary metric.
%
% JIT budgets use T_full = T_full_mutation_phase as the denominator.
%
% Returns (and saves):
%   result - Struct with timings, budgets, counts, score and trace summary
%
% See also: phase1_env, TestTraceRecorder,
%           run_hybridfsm_random_mutant_phase1, run_hybridfsm_random_test_phase1

    env = phase1_env();

    fprintf('\n=== HybridFSM Phase 1 BASELINE (desktop) ===\n');
    fprintf('MATLAB R%s | commit %s%s\n', env.matlabRelease, env.commit, ...
        ternary(env.dirtyWorkTree, ' (working tree dirty)', ''));
    fprintf('started %s\n\n', datetime('now'));

    % --- Known session state before measuring -----------------------------
    % Coverage OFF (safety guard) and Test Manager results cleared, so this
    % run starts from the same state as every Random Mutant / Random Test
    % point it will later be compared against.
    session = phase1_clean_session(env);

    % --- Telemetry: one row per executed test, mutant-correlated ---------
    recorder = TestTraceRecorder();
    mutationtool.ExperimentPlan.resetTelemetryFailures();

    orch = mutationtool.Orchestrator();
    orch.loadConfig(env.configPath);

    cfg = orch.Config;
    cfg.telemetry = struct('onTestExecuted', recorder.sink());
    % No mutantPlan, no testPlan: this is the default path by construction.
    orch.setConfig(cfg);
    orch.addObserver(recorder);

    % --- Run -------------------------------------------------------------
    tTotal = tic;
    orch.run();
    T_full_total = toc(tTotal);

    ctx = orch.Context;
    if isempty(ctx.StartTime) || isempty(ctx.EndTime)
        error('run_hybridfsm_phase1_baseline:NoExecutionWindow', ...
            ['The run never opened/closed an execution window (state=%s). ' ...
             'Most likely the baseline suite failed - check that the ' ...
             'Hybrid-Controller project is open.'], ctx.State);
    end
    T_full_mutation_phase = seconds(ctx.EndTime - ctx.StartTime);

    % --- Telemetry integrity ---------------------------------------------
    telemetry = mutationtool.ExperimentPlan.telemetryFailureStats();
    traceValid = (telemetry.count == 0);

    % --- Assemble ---------------------------------------------------------
    summaryCtx = ctx.getSummary();
    result = struct();
    result.timestamp = datetime('now');
    result.matlabRelease = env.matlabRelease;
    result.commit = env.commit;
    result.dirtyWorkTree = env.dirtyWorkTree;
    result.environment = 'desktop';
    result.T_full_mutation_phase = T_full_mutation_phase;
    result.T_full_total = T_full_total;
    result.T_setup_baseline_report = T_full_total - T_full_mutation_phase;
    result.killed = ctx.KilledCount;
    result.survived = ctx.SurvivedCount;
    result.errors = ctx.ErrorCount;
    result.totalMutants = ctx.TotalMutants;
    if isfield(summaryCtx, 'mutationScore')
        result.mutationScore = summaryCtx.mutationScore;
    else
        result.mutationScore = NaN;
    end
    result.session = session;
    result.telemetryFailureCount = telemetry.count;
    result.telemetryFailureId = telemetry.identifier;
    result.traceValid = traceValid;
    result.traceSummary = recorder.summary();
    % 623.11 s is deliberately absent. It was retired as a reference: it is
    % inconsistent with its own log (that run's baseline rate implies ~1728 s
    % for the same 2556 executions) and a sibling run of the same config that
    % day scored 52.5% against this run's 76.50%.

    % --- Budgets ----------------------------------------------------------
    T_full = T_full_mutation_phase;
    fracs = [0.10 0.20 0.30 0.50 0.70 1.00];
    names = {'B10','B20','B30','B50','B70','B100'};
    budgets = struct();
    for i = 1:numel(fracs)
        budgets.(names{i}) = fracs(i) * T_full;
    end
    result.budgetFractions = fracs;
    result.budgets = budgets;

    % --- Persist ----------------------------------------------------------
    % An existing baseline is archived rather than overwritten: a measured
    % run is expensive and irreplaceable, and a superseded one is still
    % evidence.
    matFile = fullfile(env.resultsDir, 'baseline.mat');
    csvFile = fullfile(env.resultsDir, 'baseline_test_trace.csv');
    if exist(matFile, 'file')
        stamp = char(datetime('now', 'Format', 'yyyy-MM-dd_HHmmss'));
        archiveDir = fullfile(env.resultsDir, ['superseded_' stamp]);
        mkdir(archiveDir);
        movefile(matFile, fullfile(archiveDir, 'baseline.mat'));
        if exist(csvFile, 'file')
            movefile(csvFile, fullfile(archiveDir, 'baseline_test_trace.csv'));
        end
        fprintf('archived previous baseline to %s\n', archiveDir);
    end
    save(matFile, 'result');
    try
        recorder.writeCsv(csvFile);
    catch ME
        fprintf('WARNING: could not write trace CSV: %s\n', ME.message);
    end

    % --- Report -----------------------------------------------------------
    fprintf('\n=== TIMING ===\n');
    fprintf('T_full_mutation_phase = %8.2f s   <- PRIMARY denominator\n', T_full_mutation_phase);
    fprintf('T_full_total          = %8.2f s   (secondary)\n', T_full_total);
    fprintf('setup+baseline+report = %8.2f s\n', result.T_setup_baseline_report);

    fprintf('\n=== RESULTS ===\n');
    fprintf('killed=%d  survived=%d  errors=%d  total=%d  score=%.2f%%\n', ...
        result.killed, result.survived, result.errors, result.totalMutants, result.mutationScore);

    ts = result.traceSummary;
    fprintf('\n=== TRACE ===\n');
    fprintf('rows=%d (baseline=%d, mutant=%d)  erroredTests=%d  didNotComplete=%d  mutantsStarted=%d\n', ...
        ts.rows, ts.baselineRows, ts.mutantRows, ts.erroredTestRows, ...
        ts.didNotCompleteRows, ts.mutantsStarted);
    if traceValid
        fprintf('telemetry failures = 0  -> trace VALID for experimental use\n');
    else
        fprintf(2, '*** telemetry failures = %d (%s) -> trace INVALID for experimental use ***\n', ...
            telemetry.count, telemetry.identifier);
    end

    fprintf('\n=== JIT BUDGETS (denominator = T_full_mutation_phase) ===\n');
    for i = 1:numel(names)
        fprintf('%-5s = %8.2f s  (%.0f%%)\n', names{i}, budgets.(names{i}), fracs(i)*100);
    end

    fprintf('\nsaved: %s\n       %s\n', matFile, csvFile);
    fprintf('finished %s\n\n', datetime('now'));
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
