function env = cc_env()
% NOTE: Identifiers of the mutation tool have been genericized as
% 'mutationtool.*'. The experiments were executed with MUT4SLX (not
% included in this package); these scripts are provided for inspection
% and require the tool to be obtained separately to execute.
% CC_ENV Identical environment for every CruiseControl runner
%
% The CruiseControl counterpart of phase1_env. CruiseControl is the second
% subject model: a Stateflow chart (7 states, 23 transitions) wrapped in a
% thin Simulink shell, 67 mutants against a 15-case requirements-based
% suite. It was selected after a discovery step measured 33.8% pair-level
% reachability elimination on it - low enough to differ from HybridFSM's
% 59.5%, high enough for Coverage-Based to be meaningful.
%
% Every CruiseControl runner calls this and nothing else to set itself up,
% for the same reason phase1_env exists: a runtime comparison between
% methods only means something if project, model, test file, the mutation tool commit
% and MATLAB session are identical across all of them.
%
% Returns:
%   env - Struct with fields:
%         .projectRoot     - the mutation tool repo root
%         .configPath      - CruiseControl full-run config
%         .model           - Model name
%         .subjectRoot     - Cruise Control project root (external)
%         .testFile        - Test file, absolute path under .subjectRoot
%         .resultsDir      - Deterministic results directory (created)
%         .totalMutants    - 67
%         .totalTests      - 15
%         .projectName     - Expected open project
%         .matlabRelease   - e.g. '2026a'
%         .commit          - Short git SHA of the working tree
%         .dirtyWorkTree   - true if the repo has uncommitted changes
%
% WHAT THIS DELIBERATELY DOES NOT DO
% No bdclose('all'), no sltest.testmanager.clear. Both were established on
% HybridFSM to break a loaded harness, after which every test fails almost
% instantly and every mutant looks killed. Opening the project is the whole
% preparation required.
%
% A KNOWN, HARMLESS WARNING
% Loading CruiseControl_TestSuite prints warnings about a missing
% 'loadCruiseControl_dd' PostLoadFcn and a missing requirement set. The
% suite was measured 15/15 green in that state, so these are recorded here
% as expected rather than treated as failures.
%
% See also: cc_clean_session, run_cruisecontrol_baseline, phase1_env

    env = struct();
    % This file lives at <packageRoot>/code/experiments/, so the package root
    % is three levels up. Paths below follow the package layout:
    % code/experiments, code/configs, models, results/raw.
    env.projectRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));

    % --- MATLAB path -----------------------------------------------------
    addpath(env.projectRoot);
    addpath(fullfile(env.projectRoot, 'code', 'experiments'));
    addpath(fullfile(env.projectRoot, 'code', 'reachability'));
    addpath(fullfile(env.projectRoot, 'code', 'evaluation'));

    % --- Cruise Control subject location ---------------------------------
    % The MathWorks Requirements-Based Testing Workflow Example is NOT
    % redistributed with this reproduction package. Obtain it separately and
    % point the environment variable CRUISECONTROL_PROJECT_ROOT at the
    % directory that contains Requirements_Based_Testing_Example.prj. When
    % the variable is unset, the documented default location
    % <packageRoot>/models/CruiseControl is used.
    env.subjectRoot = getenv('CRUISECONTROL_PROJECT_ROOT');
    if isempty(env.subjectRoot)
        env.subjectRoot = fullfile(env.projectRoot, 'models', 'CruiseControl');
    end

    % --- Simulink project ------------------------------------------------
    prjPath = fullfile(env.subjectRoot, ...
        'Requirements_Based_Testing_Example.prj');
    if ~exist(prjPath, 'file')
        error('cc_env:ProjectMissing', ['Cruise Control project not found: %s\n' ...
            'The MathWorks example is not redistributed with this package. ' ...
            'Obtain it separately and set CRUISECONTROL_PROJECT_ROOT to its ' ...
            'directory, or place it at the default location above.'], prjPath);
    end
    env.projectName = 'Requirements_Based_Testing_Example';

    current = matlab.project.rootProject;
    if isempty(current) || ~strcmp(current.Name, env.projectName)
        openProject(prjPath);
    end
    cd(env.projectRoot);

    % --- Fixed experiment constants --------------------------------------
    env.configPath = fullfile(env.projectRoot, 'code', 'configs', 'config_cruisecontrol.json');
    env.model = 'CruiseControl_TestSuite';
    env.testFile = fullfile(env.subjectRoot, 'Tests', 'CruiseControl_TestSuite.mldatx');
    env.totalMutants = 67;
    env.totalTests = 15;

    if ~exist(env.configPath, 'file')
        error('cc_env:ConfigMissing', 'Config not found: %s', env.configPath);
    end

    % --- Results directory ------------------------------------------------
    env.resultsDir = fullfile(env.projectRoot, 'results', 'raw', ...
        'CruiseControl', 'phase1');
    if ~exist(env.resultsDir, 'dir')
        mkdir(env.resultsDir);
    end

    % --- Provenance -------------------------------------------------------
    env.matlabRelease = version('-release');
    [env.commit, env.dirtyWorkTree] = localGitState(env.projectRoot);

    % --- Refuse to start if a stale snapshot would prompt -----------------
    % Orchestrator.initialize asks "restore from backup? [Y/n]" on stdin when
    % it finds one, which silently blocks an unattended run.
    backupDir = fullfile(env.subjectRoot, 'Models', '.mut4slx_backup');
    if exist(backupDir, 'dir')
        error('cc_env:StaleSnapshot', ...
            ['A stale the mutation tool snapshot exists at\n  %s\n' ...
             'It comes from a previous aborted run and will make the run stop ' ...
             'for interactive input. Compare it against the working model, then ' ...
             'delete the folder before starting.'], backupDir);
    end
end

function [sha, dirty] = localGitState(root)
    sha = 'unknown';
    dirty = true;
    try
        [s1, out1] = system(sprintf('git -C "%s" rev-parse --short HEAD', root));
        if s1 == 0
            sha = strtrim(out1);
        end
        [s2, out2] = system(sprintf('git -C "%s" status --porcelain', root));
        if s2 == 0
            dirty = ~isempty(strtrim(out2));
        end
    catch
        % Provenance is nice to have; never a reason to block a run.
    end
end
