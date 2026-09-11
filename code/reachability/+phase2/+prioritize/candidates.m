function C = candidates(R, opts)
% PHASE2.PRIORITIZE.CANDIDATES The Phase 2A -> Phase 2B boundary
%
% Converts a reachability matrix into the list of (mutant, test) pairs that
% are still worth considering. This is the ONLY thing Phase 2A hands over:
% a set, with no order and no scores. Whatever Phase 2B does with it -
% random, shortest-first, or a learned policy - cannot resurrect a pair that
% was eliminated here, and cannot be blamed for one that was kept.
%
%   R == 0   -> excluded (provably not worth running)
%   R == 1   -> candidate
%   R == NaN -> candidate (unknown is not unreachable)
%
% Returns C, a table with mutantIdx, testIdx, reachability - deliberately
% unsorted, so that any ordering a caller sees is one it chose.
%
% See also: phase2.reachability, phase2.prioritize.random,
%           phase2.prioritize.shortestFirst,
%           phase2.prioritize.reachableShortestFirst

    if nargin < 2, opts = struct(); end
    includeUnknown = ~isfield(opts, 'includeUnknown') || opts.includeUnknown;

    [nT, nM] = size(R);
    keep = (R == 1);
    if includeUnknown
        keep = keep | isnan(R);
    end

    [tIdx, mIdx] = find(keep);
    vals = arrayfun(@(k) R(tIdx(k), mIdx(k)), (1:numel(tIdx))');

    C = table(mIdx, tIdx, vals, ...
        'VariableNames', {'mutantIdx', 'testIdx', 'reachability'});

    C = sortrows(C, {'mutantIdx', 'testIdx'});   % stable identity, not a priority
end
