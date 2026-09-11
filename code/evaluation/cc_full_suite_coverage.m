function cov = cc_full_suite_coverage()
% CC_FULL_SUITE_COVERAGE Verified full-suite structural coverage for CC1
%
% Runs all 15 enabled CruiseControl test cases once on the UNMUTATED model
% with coverage recording ON and saves the unioned Decision / Condition /
% MC-DC figures. This is the CruiseControl counterpart of the HybridFSM
% full-suite reference measurement, and serves the same two purposes:
%
%   1. it fills the Full Baseline row of the summary table
%   2. cc_evaluate_coverage reuses it for any point whose executed set is
%      all 15 tests, instead of re-running anything
%
% COVERAGE IS AN OUTPUT, NEVER AN INPUT
% This runs outside every timing budget, after the experiments. The timed
% runs themselves executed with coverage OFF; cc_clean_session enforces
% that before each of them.
%
% The result goes to results/CruiseControl/phase1/coverage/
% baseline_full_suite_coverage_summary.mat and an existing file is
% archived, not overwritten.
%
% See also: cc_evaluate_coverage, cc_env, evaluate_phase1_coverage

    env = cc_env();

    tf = sltest.testmanager.load(env.testFile);
    cs = getCoverageSettings(tf);
    cs.RecordCoverage = true;
    cs.MetricSettings = 'dcm';
    restore = onCleanup(@() setRecordOff(env));

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
    if numel(pool) ~= env.totalTests
        error('cc_full_suite_coverage:PoolMismatch', ...
            'Expected %d enabled tests, found %d.', env.totalTests, numel(pool));
    end

    fprintf('replaying all %d tests on the unmutated model, coverage ON\n', numel(pool));
    total = [];
    for k = 1:numel(pool)
        w = warning('off', 'all');
        r = run(pool{k});
        warning(w);
        try
            d = cvdata(r.CoverageResults);
        catch
            fprintf(2, '  [warn] no coverage from test %d (%s)\n', k, pool{k}.Name);
            continue;
        end
        if isempty(total)
            total = d;
        else
            total = total + d;    % union of covered objectives
        end
    end
    if isempty(total)
        error('cc_full_suite_coverage:NoCoverage', 'No coverage data collected.');
    end

    mdl = total.modelinfo.analyzedModel;
    cov = struct();
    cov.analyzedModel = mdl;
    cov.decision = decisioninfo(total, mdl);
    cov.condition = conditioninfo(total, mdl);
    cov.mcdc = mcdcinfo(total, mdl);
    cov.decisionPct = 100 * cov.decision(1) / max(cov.decision(2), 1);
    cov.conditionPct = 100 * cov.condition(1) / max(cov.condition(2), 1);
    cov.mcdcPct = 100 * cov.mcdc(1) / max(cov.mcdc(2), 1);
    cov.source = 'full-suite reference (all 15 tests, unmutated model)';
    cov.subject = 'CruiseControl';
    cov.measuredAt = datetime('now');

    outDir = fullfile(env.resultsDir, 'coverage');
    if ~exist(outDir, 'dir'), mkdir(outDir); end
    outFile = fullfile(outDir, 'baseline_full_suite_coverage_summary.mat');
    if exist(outFile, 'file')
        stamp = char(datetime('now', 'Format', 'yyyy-MM-dd_HHmmss'));
        movefile(outFile, fullfile(outDir, ['superseded_' stamp '_full_suite.mat']));
    end
    save(outFile, 'cov');

    fprintf('analyzed model: %s\n', mdl);
    fprintf('Decision  %3d/%3d  = %6.2f%%\n', cov.decision(1), cov.decision(2), cov.decisionPct);
    fprintf('Condition %3d/%3d  = %6.2f%%\n', cov.condition(1), cov.condition(2), cov.conditionPct);
    fprintf('MC/DC     %3d/%3d  = %6.2f%%\n', cov.mcdc(1), cov.mcdc(2), cov.mcdcPct);
    fprintf('saved: %s\n', outFile);
end

function setRecordOff(env)
    try
        tf = sltest.testmanager.load(env.testFile);
        cs = getCoverageSettings(tf);
        cs.RecordCoverage = false;
    catch
        % session teardown is best effort
    end
end
