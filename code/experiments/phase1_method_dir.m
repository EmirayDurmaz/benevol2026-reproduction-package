function d = phase1_method_dir(env, method)
% PHASE1_METHOD_DIR Where a strategy's per-point result files live
%
% The three strategies are evaluated under one protocol but their artifacts
% sit in different trees: Random Mutant and Random Test were produced as
% Phase 1 and stay there untouched, while Coverage-Based is Phase 2 work
% evaluated under the Phase 1 protocol. Both the coverage evaluator and the
% plotter need the same answer, so the mapping lives in one place rather
% than being duplicated and drifting.
%
% Parameters:
%   env    - struct from phase1_env
%   method - 'random_mutant' | 'random_test' | 'coverage_based'
%
% Returns:
%   d - absolute directory holding seed*.mat point files
%
% See also: phase1_env, evaluate_phase1_coverage, plot_phase1_figures

    switch method
        case {'random_mutant', 'random_test'}
            d = fullfile(env.resultsDir, method);
        case 'coverage_based'
            d = fullfile(fileparts(env.resultsDir), 'phase2', 'coverage_based');
        otherwise
            error('phase1_method_dir:UnknownMethod', ...
                'Unknown method "%s".', method);
    end
end
