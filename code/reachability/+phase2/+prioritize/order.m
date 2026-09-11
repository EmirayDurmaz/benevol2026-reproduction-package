function [P, info] = order(C, strategy, ctx)
% PHASE2.PRIORITIZE.ORDER Phase 2B - order candidate pairs for execution
%
%   P = phase2.prioritize.order(C, 'random',                struct('seed',1))
%   P = phase2.prioritize.order(C, 'shortestFirst',         ctx)
%   P = phase2.prioritize.order(C, 'reachableShortestFirst',ctx)
%
% Takes the candidate set from Phase 2A and returns it in execution order.
% It never adds or removes a pair - filtering already happened, and mixing
% the two would make the safety argument for elimination impossible to
% state. A strategy here can only be wrong about SPEED, never about
% correctness.
%
% ctx fields (all optional, strategy-dependent):
%   .testCostSeconds  1 x nTests, historical per-test cost on the original
%                     model. Phase 1's baseline trace is the natural source.
%   .seed             RNG seed for 'random'
%
% ADDING A LEARNED STRATEGY LATER
% Everything an online policy needs - observed kills, per-operator kill
% rates, per-test cost, how often a pair has been tried - is a function of
% (mutantIdx, testIdx) plus history. Add a case below that computes a score
% per row and sorts by it; nothing else in the pipeline has to change,
% because ordering is the only authority this stage has.
%
% See also: phase2.prioritize.candidates

    if nargin < 3, ctx = struct(); end
    strategy = validatestring(strategy, ...
        {'random', 'shortestFirst', 'reachableShortestFirst'});

    n = height(C);
    info = struct('strategy', strategy, 'nPairs', n);

    switch strategy
        case 'random'
            seed = getfielddef(ctx, 'seed', 0);
            s = rng; restore = onCleanup(@() rng(s));
            rng(seed, 'twister');
            P = C(randperm(n), :);
            info.seed = seed;

        case 'shortestFirst'
            cost = requireCost(ctx, C);
            [~, ord] = sort(cost);
            P = C(ord, :);

        case 'reachableShortestFirst'
            % Known-reachable pairs before unknown ones, each group ordered
            % by test cost. Unknown pairs are not dropped - they are simply
            % the later half, so a budget that runs out spends what it had
            % on the pairs with actual coverage evidence behind them.
            cost = requireCost(ctx, C);
            isUnknown = isnan(C.reachability);
            [~, ord] = sortrows([double(isUnknown), cost], [1 2]);
            P = C(ord, :);
            info.nKnown = sum(~isUnknown);
            info.nUnknown = sum(isUnknown);
    end
end

function cost = requireCost(ctx, C)
    if ~isfield(ctx, 'testCostSeconds') || isempty(ctx.testCostSeconds)
        error('phase2:prioritize:MissingCost', ...
            ['This strategy needs ctx.testCostSeconds (1 x nTests). Derive ' ...
             'it from the Phase 1 baseline trace rather than timing tests ' ...
             'again, so ordering never costs a simulation.']);
    end
    cost = ctx.testCostSeconds(C.testIdx);
    cost = cost(:);
end

function v = getfielddef(s, f, d)
    if isfield(s, f), v = s.(f); else, v = d; end
end
