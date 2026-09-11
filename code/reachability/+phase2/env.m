function e = env()
% NOTE: Identifiers of the mutation tool have been genericized as
% 'mutationtool.*'. The experiments were executed with MUT4SLX (not
% included in this package); these scripts are provided for inspection
% and require the tool to be obtained separately to execute.
% PHASE2.ENV Environment for Phase 2, layered on Phase 1's
%
% Reuses phase1_env verbatim for project/model/test-file setup, so a
% reachability matrix can never be built against a differently-configured
% model than the one Phase 1 measured. Only the output directory differs.
%
% Added fields:
%   .phase2Dir  - Phase 2 artifacts (created)
%   .phase1Dir  - Phase 1 results, read-only from here
%   .mutantJson - mutation-tool run output holding the mutant records,
%                 shipped at <phase2Dir>/stateMachine_output.json
%   .traceCsv   - Baseline per-(mutant,test) trace. Read ONLY by
%                 phase2.validate; nothing upstream of it may touch this
%                 file, because it carries kill outcomes.
%
% See also: phase1_env, phase2.buildReachability

    e = phase1_env();

    e.phase1Dir = e.resultsDir;
    e.phase2Dir = fullfile(e.projectRoot, 'results', 'raw', ...
        'HybridFSM', 'phase2');
    if ~exist(e.phase2Dir, 'dir')
        mkdir(e.phase2Dir);
    end

    % Mutant records produced by a mutation-tool run on the unmutated
    % HybridFSM model. Phase 2 reads only the mutant list (block paths,
    % operators and original values) to locate mutants; the copy shipped
    % with this package lives beside the other Phase 2 artifacts.
    e.mutantJson = fullfile(e.phase2Dir, 'stateMachine_output.json');
    e.traceCsv = fullfile(e.phase1Dir, 'baseline_test_trace.csv');

    if ~exist(e.mutantJson, 'file')
        error('phase2:MutantRecordsMissing', ...
            ['Mutant records not found: %s\n' ...
             'This file is the JSON report of a mutation-tool run on the ' ...
             'unmutated model (<model>_output.json). It ships with this ' ...
             'package; if it is missing, regenerate it by running the ' ...
             'mutation tool once on the HybridFSM subject with the ' ...
             'configuration in code/configs/config_hybridfsm.json and ' ...
             'copying the resulting stateMachine_output.json here.'], ...
            e.mutantJson);
    end
end
