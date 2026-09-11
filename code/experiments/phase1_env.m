function env = phase1_env()
% NOTE: Identifiers of the mutation tool have been genericized as
% 'mutationtool.*'. The experiments were executed with MUT4SLX (not
% included in this package); these scripts are provided for inspection
% and require the tool to be obtained separately to execute.
% PHASE1_ENV Identical environment for every Phase 1 HybridFSM runner
%
% All three Phase 1 runners - baseline, Random Mutant, Random Test - call
% this and nothing else to set themselves up. That is the point: a runtime
% comparison between the methods is only meaningful if the project, model,
% test file, the mutation tool commit and MATLAB session are the same for all of
% them, so the setup exists once rather than three times.
%
% Returns:
%   env - Struct with fields:
%         .projectRoot     - the mutation tool repo root
%         .configPath      - HybridFSM full-run config
%         .model           - Model name
%         .testFile        - Test file, absolute path under models/
%         .resultsDir      - Deterministic results directory (created)
%         .totalMutants    - 183
%         .totalTests      - 25
%         .matlabRelease   - e.g. '2026a'
%         .commit          - Short git SHA of the working tree
%         .dirtyWorkTree   - true if the repo has uncommitted changes
%
% WHAT THIS DELIBERATELY DOES NOT DO
% No bdclose('all'), no sltest.testmanager.clear. Clearing Test Manager
% after the project is open leaves the FSM harness unable to resolve its
% models and the whole suite then fails in ~0.07 s per test - which silently
% turns every mutant into a "kill". Opening the project is the entire
% preparation the HybridFSM suite needs.
%
% See also: run_hybridfsm_phase1_baseline,
%           run_hybridfsm_random_mutant_phase1,
%           run_hybridfsm_random_test_phase1

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

    % --- Simulink project ------------------------------------------------
    % Required by the FSM test harness; without it every test fails fast.
    prjPath = fullfile(env.projectRoot, 'models', 'HybridFSM', ...
        'Hybrid-controller', 'HybridController.prj');
    if ~exist(prjPath, 'file')
        error('phase1_env:ProjectMissing', 'Project not found: %s', prjPath);
    end

    current = matlab.project.rootProject;
    if isempty(current) || ~strcmp(current.Name, 'Hybrid-Controller')
        openProject(prjPath);
    end
    cd(env.projectRoot);

    % --- Fixed experiment constants --------------------------------------
    env.configPath = fullfile(env.projectRoot, 'code', 'configs', 'config_hybridfsm.json');
    env.model = 'stateMachine';
    env.testFile = fullfile(env.projectRoot, 'models', 'HybridFSM', ...
        'Hybrid-controller', 'Test', 'FSM Test', 'FSM_test.mldatx');
    env.totalMutants = 183;
    env.totalTests = 25;

    if ~exist(env.configPath, 'file')
        error('phase1_env:ConfigMissing', 'Config not found: %s', env.configPath);
    end

    % --- Results directory ------------------------------------------------
    env.resultsDir = fullfile(env.projectRoot, 'results', 'raw', ...
        'HybridFSM', 'phase1');
    if ~exist(env.resultsDir, 'dir')
        mkdir(env.resultsDir);
    end

    % --- Provenance -------------------------------------------------------
    env.matlabRelease = version('-release');
    [env.commit, env.dirtyWorkTree] = localGitState(env.projectRoot);

    % --- Refuse to start if a stale snapshot would prompt -----------------
    % Orchestrator.initialize asks "restore from backup? [Y/n]" on stdin when
    % it finds one. A runner that blocks on a hidden prompt is worse than one
    % that refuses, so this is checked before any long run begins.
    backupDir = fullfile(env.projectRoot, 'models', 'HybridFSM', ...
        'Hybrid-controller', 'Controller', '.mut4slx_backup');
    if exist(backupDir, 'dir')
        error('phase1_env:StaleSnapshot', ...
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
