function result = run_cruisecontrol_baseline()
% NOTE: Identifiers of the mutation tool have been genericized as
% 'mutationtool.*'. The experiments were executed with MUT4SLX (not
% included in this package); these scripts are provided for inspection
% and require the tool to be obtained separately to execute.
% RUN_CRUISECONTROL_BASELINE Full unsampled CruiseControl run, desktop MATLAB
%
% The CruiseControl reference point, and the direct counterpart of
% run_hybridfsm_phase1_baseline: all 67 mutants, each against the full
% 15-test suite, default early exit, no plans and no samplers. Everything
% the JIT budgets are a fraction OF is measured here, so this must run in
% the same desktop session as the strategy runners it will be compared
% against - a batch session was measured at roughly twice the per-mutant
% cost on HybridFSM, which would make any cross-environment comparison
% meaningless.
%
% Usage (from the MATLAB Command Window):
%   run_cruisecontrol_baseline
%
% Requires no interactive input.
%
% ON THE EXPECTED DURATION
% Deliberately not predicted here. A single clean suite pass measures about
% 32 s, but that is one pass over an unmutated model and is NOT the mutation
% phase: the baseline mutates, recompiles and re-runs 67 times with early
% exit. On HybridFSM the mutation phase came out roughly 58x a single clean
% pass. Measuring that ratio for a second subject is part of what this run
% is for, so no estimate is baked in.
%
% TWO TIMING SCOPES, BOTH SAVED
%   T_full_mutation_phase - RunContext StartTime..EndTime, the window
%                           Orchestrator opens at startExecution and closes
%                           at completeExecution. The mutation workload
%                           alone: no setup, no model load, no mutant
%                           discovery, no baseline suite, no reporting.
%   T_full_total          - the whole orchestration, loadConfig through
%                           run() returning. Reported as a secondary metric.
%
% JIT budgets use T_full = T_full_mutation_phase as the denominator, exactly
% as on HybridFSM, so the two subjects' budget grids mean the same thing.
%
% Returns (and saves):
%   result - Struct with timings, budgets, counts, score and trace summary
%
% See also: cc_env, cc_clean_session, TestTraceRecorder,
%           run_hybridfsm_phase1_baseline

    env = cc_env();

    fprintf('\n=== CruiseControl BASELINE (desktop) ===\n');
    fprintf('MATLAB R%s | commit %s%s\n', env.matlabRelease, env.commit, ...
        ternary(env.dirtyWorkTree, ' (working tree dirty)', ''));
    fprintf('subject: %s | %d mutants | %d tests\n', env.model, ...
        env.totalMutants, env.totalTests);
    fprintf('started %s\n\n', datetime('now'));

    % --- Known session state before measuring -----------------------------
    session = cc_clean_session(env);

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
        error('run_cruisecontrol_baseline:NoExecutionWindow', ...
            ['The run never opened/closed an execution window (state=%s). ' ...
             'Most likely the baseline suite failed - check that the ' ...
             '%s project is open.'], ctx.State, env.projectName);
    end
    T_full_mutation_phase = seconds(ctx.EndTime - ctx.StartTime);

    % --- Telemetry integrity ---------------------------------------------
    telemetry = mutationtool.ExperimentPlan.telemetryFailureStats();
    traceValid = (telemetry.count == 0);

    % --- Assemble ---------------------------------------------------------
    summaryCtx = ctx.getSummary();
    result = struct();
    result.subject = 'CruiseControl';
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

    % --- Sanity check against the discovery step ---------------------------
    % The discovery step enumerated 67 mutants. A different count here means
    % the model, config or operator set changed underneath the reachability
    % matrix in results/CruiseControl/phase2/discovery_R.mat, which would
    % silently misalign every Coverage-Based column.
    if ctx.TotalMutants ~= env.totalMutants
        fprintf(2, ['*** WARNING: %d mutants discovered, expected %d. ' ...
            'discovery_R.mat is keyed to %d and must be regenerated ' ...
            'before any Coverage-Based run. ***\n'], ...
            ctx.TotalMutants, env.totalMutants, env.totalMutants);
    end

    % --- Budgets ----------------------------------------------------------
    % Same grid as the HybridFSM strategy runs, so the two subjects' curves
    % are read on the same axis.
    T_full = T_full_mutation_phase;
    fracs = [0.02 0.04 0.06 0.08 0.10 0.20 0.30 0.40 0.50];
    result.budgetFractions = fracs;
    result.budgets = fracs * T_full;

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
    for i = 1:numel(fracs)
        fprintf('B%-4.0f = %8.2f s\n', fracs(i)*100, result.budgets(i));
    end

    fprintf('\nsaved: %s\n       %s\n', matFile, csvFile);
    fprintf('finished %s\n\n', datetime('now'));
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
