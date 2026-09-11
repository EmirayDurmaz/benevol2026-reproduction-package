function results = evaluate_phase1_coverage(varargin)
% EVALUATE_PHASE1_COVERAGE Structural coverage of the tests each run executed
%
% For every saved seed x budget point, reconstructs the set of test cases the
% run ACTUALLY EXECUTED, then replays exactly that set on the ORIGINAL,
% UNMUTATED model with coverage recording ON and reports Decision /
% Condition / MC-DC.
%
% COVERAGE IS AN OUTPUT, NEVER AN INPUT
% This runs AFTER the timed experiments, as a separate step. Its runtime is
% deliberately NOT part of any JIT budget, and nothing it computes feeds back
% into selection. The mutation runs themselves execute with coverage OFF.
%
% WHY REPLAY INSTEAD OF RECORDING DURING THE RUN
% Coverage recorded during mutation execution would describe a MUTATED model
% - a different artifact for every mutant. The question here is what the
% SELECTED TESTS cover on the model under test, so the selected set is
% replayed once against the original model.
%
% WHICH ROWS COUNT
% Only mutation-phase rows (isBaseline == 0). Every run starts with an
% unmutated baseline suite that executes all 25 tests; counting those would
% make every point look like full coverage.
%
% WORK AVOIDED (the executed SET is what matters, not how often it ran)
%   - each unique test is replayed once per set, never once per trace row
%   - sets are cached by signature, so two points with the same executed set
%     are evaluated once
%   - a set of all 25 tests reuses the already verified full-suite figures
%     instead of re-running anything
%
% Usage:
%   evaluate_phase1_coverage                          % every saved point
%   evaluate_phase1_coverage('Method','random_mutant')
%   evaluate_phase1_coverage('Resume', false)         % recompute everything
%
% See also: plot_phase1_figures, run_hybridfsm_random_mutant_phase1

    p = inputParser;
    % 'both' is kept meaning the two original Phase 1 strategies so existing
    % invocations keep their meaning; 'all' adds Coverage-Based.
    p.addParameter('Method', 'all', @(x) ismember(x, ...
        {'all','both','random_mutant','random_test','coverage_based'}));
    p.addParameter('BudgetFractions', [0.10 0.20 0.30 0.40 0.50], @isnumeric);
    p.addParameter('Resume', true, @(x) islogical(x) || isnumeric(x));
    p.parse(varargin{:});
    opt = p.Results;

    env = phase1_env();
    outDir = fullfile(env.resultsDir, 'coverage', 'points');
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    switch opt.Method
        case 'all'
            methods = {'random_mutant', 'random_test', 'coverage_based'};
        case 'both'
            methods = {'random_mutant', 'random_test'};
        otherwise
            methods = {opt.Method};
    end

    fullSuite = loadFullSuiteReference(env);
    pool = buildTestPool(env);
    fprintf('=== Phase 1 COVERAGE EVALUATION (separate from timing) ===\n');
    fprintf('pool: %d enabled test cases | full-suite reference: D=%.2f%% C=%.2f%% MCDC=%.2f%%\n', ...
        numel(pool), fullSuite.decisionPct, fullSuite.conditionPct, fullSuite.mcdcPct);

    cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
    results = {};

    for mi = 1:numel(methods)
        method = methods{mi};
        srcDir = phase1_method_dir(env, method);
        files = dir(fullfile(srcDir, 'seed*.mat'));
        fprintf('\n--- %s: %d saved point files ---\n', method, numel(files));

        for fi = 1:numel(files)
            tag = erase(files(fi).name, '.mat');
            loaded = load(fullfile(srcDir, files(fi).name), 'point');
            point = loaded.point;

            % Only the budget grid this experiment is about - never older
            % 20/70/100 smoke or diagnostic points.
            if ~isfield(point, 'budgetFraction') || ...
                    ~any(abs(point.budgetFraction - opt.BudgetFractions) < 1e-9)
                fprintf('[skip] %s (not in budget grid)\n', tag);
                continue;
            end

            outFile = fullfile(outDir, sprintf('%s_%s.mat', method, tag));
            if opt.Resume && exist(outFile, 'file')
                loadedCov = load(outFile, 'cov');
                results{end+1} = loadedCov.cov; %#ok<AGROW>
                fprintf('[skip] %s_%s already evaluated\n', method, tag);
                continue;
            end

            executed = reconstructExecutedTests(point);
            if isempty(executed)
                fprintf(2, '[warn] %s_%s: no mutation-phase rows, skipped\n', method, tag);
                continue;
            end

            signature = sprintf('%d,', executed);
            if isKey(cache, signature)
                cov = cache(signature);
                fprintf('%s_%s: %2d unique tests -> cached\n', method, tag, numel(executed));
            elseif numel(executed) == env.totalTests
                cov = fullSuite;
                cov.source = 'full-suite reference (all 25 executed)';
                cache(signature) = cov;
                fprintf('%s_%s: all %d tests -> reusing verified full-suite values\n', ...
                    method, tag, env.totalTests);
            else
                fprintf('%s_%s: %2d unique tests -> replaying on unmutated model\n', ...
                    method, tag, numel(executed));
                cov = replayCoverage(env, pool, executed);
                cache(signature) = cov;
            end

            cov.method = method;
            cov.tag = tag;
            cov.seed = point.seed;
            cov.budgetFraction = point.budgetFraction;
            cov.uniqueTests = numel(executed);
            cov.executedTestIndices = executed;
            cov.evaluatedAt = datetime('now');
            if isfield(point, 'prefixLength')
                cov.prefixLength = point.prefixLength;
            else
                cov.prefixLength = NaN;
            end

            save(outFile, 'cov');
            results{end+1} = cov; %#ok<AGROW>
            fprintf('   D=%.2f%%  C=%.2f%%  MCDC=%.2f%%\n', ...
                cov.decisionPct, cov.conditionPct, cov.mcdcPct);
        end
    end

    if ~isempty(results)
        summaryFile = fullfile(env.resultsDir, 'coverage', 'coverage_points_summary.mat');
        save(summaryFile, 'results');
        fprintf('\nsaved: %s  (%d points)\n', summaryFile, numel(results));
    else
        fprintf('\nNo points evaluated - run the experiments first.\n');
    end
end

% ----------------------------------------------------------------------
function executed = reconstructExecutedTests(point)
% Unique pool indices executed during the MUTATION PHASE only.
    executed = [];
    if ~isfield(point, 'testTrace') || isempty(point.testTrace)
        return;
    end
    T = point.testTrace;
    if ~ismember('isBaseline', T.Properties.VariableNames)
        return;
    end
    M = T(T.isBaseline == 0, :);
    if isempty(M)
        return;
    end
    executed = sort(unique(M.testIndex))';
end

% ----------------------------------------------------------------------
function pool = buildTestPool(env)
% Mirrors SimulinkTestStrategy.runTests pooling: every top-level suite in
% order, every Enabled case in order. Pool index N here is the same N that
% appears as testIndex in the trace.
    tf = sltest.testmanager.load(env.testFile);
    suites = getTestSuites(tf);
    pool = {};
    for i = 1:numel(suites)
        cases = getTestCases(suites(i));
        for j = 1:numel(cases)
            if cases(j).Enabled
                pool{end+1} = cases(j); %#ok<AGROW>
            end
        end
    end
end

% ----------------------------------------------------------------------
function ref = loadFullSuiteReference(env)
    f = fullfile(env.resultsDir, 'coverage', 'baseline_full_suite_coverage_summary.mat');
    if ~exist(f, 'file')
        error('evaluate_phase1_coverage:NoFullSuiteReference', ...
            'Missing verified full-suite coverage at %s', f);
    end
    L = load(f, 'cov');
    ref = struct('decision', L.cov.decision, 'condition', L.cov.condition, ...
        'mcdc', L.cov.mcdc, 'decisionPct', L.cov.decisionPct, ...
        'conditionPct', L.cov.conditionPct, 'mcdcPct', L.cov.mcdcPct, ...
        'analyzedModel', L.cov.analyzedModel, 'source', 'full-suite reference');
end

% ----------------------------------------------------------------------
function cov = replayCoverage(env, pool, executedIdx)
% Replay one test SET on the unmutated model with coverage ON, unioning the
% per-test cvdata. Union rather than a whole-file run because the executed
% set is an arbitrary subset.
    tf = sltest.testmanager.load(env.testFile);
    cs = getCoverageSettings(tf);
    cs.RecordCoverage = true;
    cs.MetricSettings = 'dcm';

    if ~bdIsLoaded(env.model)
        load_system(env.model);
    end

    total = [];
    for k = executedIdx
        warnState = warning('off', 'all');
        r = run(pool{k});
        warning(warnState);
        try
            d = cvdata(r.CoverageResults);
        catch
            continue;
        end
        if isempty(total)
            total = d;
        else
            total = total + d;    % union of covered objectives
        end
    end

    cov = struct('decision', [NaN NaN], 'condition', [NaN NaN], 'mcdc', [NaN NaN], ...
        'decisionPct', NaN, 'conditionPct', NaN, 'mcdcPct', NaN, ...
        'analyzedModel', '', 'source', 'replayed');

    if isempty(total)
        cs.RecordCoverage = false;
        return;
    end

    mdl = total.modelinfo.analyzedModel;
    cov.analyzedModel = mdl;
    cov.decision = decisioninfo(total, mdl);
    cov.condition = conditioninfo(total, mdl);
    cov.mcdc = mcdcinfo(total, mdl);
    cov.decisionPct = 100 * cov.decision(1) / max(cov.decision(2), 1);
    cov.conditionPct = 100 * cov.condition(1) / max(cov.condition(2), 1);
    cov.mcdcPct = 100 * cov.mcdc(1) / max(cov.mcdc(2), 1);

    % Leave the session as the timing runners expect to find it.
    cs.RecordCoverage = false;
end
