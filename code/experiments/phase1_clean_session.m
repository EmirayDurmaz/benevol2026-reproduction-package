function info = phase1_clean_session(env)
% PHASE1_CLEAN_SESSION Put the session in a known state before a measured run
%
% Every independently measured Phase 1 run - the baseline, and each
% seed/budget point of Random Mutant and Random Test - starts here, so that
% no run inherits state from the one before it. Seed 5 must not be slower
% than seed 1 merely because it ran later.
%
% What it does, in order:
%   1. forces Test Manager coverage recording OFF
%   2. clears accumulated Test Manager results
%   3. verifies the project, test file, suites, cases and model survived
%
% ON THE COVERAGE GUARD
% This is a SAFETY GUARD, not a performance fix. Coverage recording was
% measured at 1.26x when it engages, and it was found silently enabled in a
% session by an earlier evaluation run - inherited through
% sltest.testmanager.load, which returns the already-loaded in-memory test
% file. It is not the cause of any large slowdown. Structural coverage is a
% separate evaluation step and never belongs inside a timing budget.
%
% ON clearResults VS clear
% sltest.testmanager.clearResults only discards result sets and leaves the
% session usable. sltest.testmanager.clear is NOT used here: clearing the
% Test Manager after the project is open leaves the FSM harness unable to
% resolve its models, after which every test fails in ~0.07 s and every
% mutant looks killed. The validation below exists to catch exactly that
% class of damage before a long run starts, rather than after it.
%
% Parameters:
%   env - Struct from phase1_env
%
% Returns:
%   info - Struct with what was cleared and what was verified
%
% See also: phase1_env, run_hybridfsm_phase1_baseline

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
        error('phase1_clean_session:CoverageStillOn', ...
            ['Could not disable Test Manager coverage recording. A timing run ' ...
             'must not start with coverage enabled.']);
    end

    % --- 2. Clear accumulated results -------------------------------------
    info.resultSetsBefore = numel(sltest.testmanager.getResultSets);
    sltest.testmanager.clearResults;
    info.resultSetsAfter = numel(sltest.testmanager.getResultSets);

    % --- 3. Verify the session is still intact ------------------------------
    rootPrj = matlab.project.rootProject;
    if isempty(rootPrj) || ~strcmp(rootPrj.Name, 'Hybrid-Controller')
        error('phase1_clean_session:ProjectLost', ...
            ['The Hybrid-Controller project is not open. The FSM suite cannot ' ...
             'run without it - every test would fail in ~0.07 s.']);
    end
    info.project = rootPrj.Name;

    loadedFiles = sltest.testmanager.getTestFiles;
    if isempty(loadedFiles)
        error('phase1_clean_session:TestFileLost', 'No test file loaded after clearResults.');
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
        error('phase1_clean_session:TestCountMismatch', ...
            'Expected %d enabled test cases, found %d.', env.totalTests, nEnabled);
    end

    harness = which('FSM_Model');
    if isempty(harness)
        error('phase1_clean_session:HarnessUnresolvable', ...
            'FSM_Model is not resolvable on the path - the harness is broken.');
    end
    info.harness = harness;

    if ~bdIsLoaded(env.model)
        load_system(env.model);
    end
    info.modelLoaded = bdIsLoaded(env.model);
    if ~info.modelLoaded
        error('phase1_clean_session:ModelNotLoaded', 'Could not load model %s.', env.model);
    end

    fprintf(['[clean session] coverage OFF | results %d -> %d | project %s | ' ...
             'suites %d | enabled tests %d | model %s loaded\n'], ...
        info.resultSetsBefore, info.resultSetsAfter, info.project, ...
        info.suites, info.enabledTestCases, env.model);
end
