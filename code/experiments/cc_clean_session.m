function info = cc_clean_session(env)
% CC_CLEAN_SESSION Put the session in a known state before a measured run
%
% The CruiseControl counterpart of phase1_clean_session. Every
% independently measured run - the baseline, and each seed/budget point of
% any strategy - starts here, so no run inherits state from the one before
% it. Seed 5 must not be slower than seed 1 merely because it ran later.
%
% What it does, in order:
%   1. forces Test Manager coverage recording OFF
%   2. clears accumulated Test Manager results
%   3. verifies the project, test file, suites, cases and model survived
%
% ON THE COVERAGE GUARD
% This is a SAFETY GUARD, not a performance fix. Coverage recording was
% measured at 1.26x on HybridFSM when it engages, and it was once found
% silently enabled in a session - inherited through sltest.testmanager.load,
% which returns the already-loaded in-memory test file. The CruiseControl
% discovery step also switched coverage on, which makes the guard load
% bearing here rather than theoretical. Structural coverage is a separate
% evaluation step and never belongs inside a timing budget.
%
% ON clearResults VS clear
% sltest.testmanager.clearResults only discards result sets and leaves the
% session usable. sltest.testmanager.clear is NOT used: clearing the Test
% Manager after the project is open leaves harnesses unable to resolve
% their models, after which every test fails almost instantly and every
% mutant looks killed. The validation below exists to catch exactly that
% class of damage before a long run starts, rather than after it.
%
% Parameters:
%   env - Struct from cc_env
%
% Returns:
%   info - Struct with what was cleared and what was verified
%
% See also: cc_env, run_cruisecontrol_baseline, phase1_clean_session

    info = struct();

    % --- The test file must be loaded before its settings can be touched --
    testFile = sltest.testmanager.load(env.testFile);

    % --- 1. Coverage OFF ---------------------------------------------------
    loadedFiles = sltest.testmanager.getTestFiles;
    for i = 1:numel(loadedFiles)
        cs = getCoverageSettings(loadedFiles(i));
        cs.RecordCoverage = false;
    end
    info.coverageOff = true;
    for i = 1:numel(loadedFiles)
        if getCoverageSettings(loadedFiles(i)).RecordCoverage
            info.coverageOff = false;
        end
    end
    if ~info.coverageOff
        error('cc_clean_session:CoverageStillOn', ...
            ['Could not disable Test Manager coverage recording. A timing run ' ...
             'must not start with coverage enabled.']);
    end

    % --- 2. Clear accumulated results -------------------------------------
    info.resultSetsBefore = numel(sltest.testmanager.getResultSets);
    sltest.testmanager.clearResults;
    info.resultSetsAfter = numel(sltest.testmanager.getResultSets);

    % --- 3. Verify the session is still intact ------------------------------
    rootPrj = matlab.project.rootProject;
    if isempty(rootPrj) || ~strcmp(rootPrj.Name, env.projectName)
        error('cc_clean_session:ProjectLost', ...
            'The %s project is not open. The suite cannot run without it.', ...
            env.projectName);
    end
    info.project = rootPrj.Name;

    loadedFiles = sltest.testmanager.getTestFiles;
    if isempty(loadedFiles)
        error('cc_clean_session:TestFileLost', 'No test file loaded after clearResults.');
    end
    suites = getTestSuites(testFile);
    nCases = 0;
    nEnabled = 0;
    for i = 1:numel(suites)
        cases = getTestCases(suites(i));
        nCases = nCases + numel(cases);
        for j = 1:numel(cases)
            if cases(j).Enabled
                nEnabled = nEnabled + 1;
            end
        end
    end
    info.suites = numel(suites);
    info.testCases = nCases;
    info.enabledTestCases = nEnabled;
    if nEnabled ~= env.totalTests
        error('cc_clean_session:TestCountMismatch', ...
            'Expected %d enabled test cases, found %d.', env.totalTests, nEnabled);
    end

    if ~bdIsLoaded(env.model)
        load_system(env.model);
    end
    info.modelLoaded = bdIsLoaded(env.model);
    if ~info.modelLoaded
        error('cc_clean_session:ModelNotLoaded', 'Could not load model %s.', env.model);
    end

    % The chart is where all 67 mutants live; if it is gone the run is void.
    charts = sfroot().find('-isa', 'Stateflow.Chart');
    info.charts = numel(charts);
    if info.charts < 1
        error('cc_clean_session:ChartMissing', ...
            'No Stateflow chart resolvable - every mutant target would be invalid.');
    end

    fprintf(['[clean session] coverage OFF | results %d -> %d | project %s | ' ...
             'suites %d | enabled tests %d | model %s loaded | charts %d\n'], ...
        info.resultSetsBefore, info.resultSetsAfter, info.project, ...
        info.suites, info.enabledTestCases, env.model, info.charts);
end
