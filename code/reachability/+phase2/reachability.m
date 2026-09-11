function [R, semantics] = reachability(cov, candidates, mode)
% PHASE2.REACHABILITY Turn per-object coverage into an R(test, mutant) matrix
%
% Pure function: no model, no test manager, no kill data. Given which tests
% evaluated which objects, and which objects each mutant might sit on, it
% decides reachability under one of two semantics.
%
%   R(t,m) =  1   the pair is retained: at least one candidate mapping for
%                 this mutant was evaluated by test t. Under a direct
%                 (single-candidate) mapping this does mean the mutant's own
%                 element was evaluated. Under union semantics it does NOT -
%                 the mutant sits on exactly one of several candidates and
%                 which one is unknown, so 1 asserts only that the test
%                 could not be ruled out, not that it reached the mutation.
%             0   every candidate carries a decision objective and test t
%                 evaluated none of them, so the mutant's element - whichever
%                 candidate it is - was not evaluated
%             NaN cannot be decided
%
% THE SAFETY PROPERTY
% A false 1 costs one wasted execution. A false 0 silently discards a test
% that could have killed the mutant, and nothing downstream can recover it.
% So every branch below resolves doubt towards 1 or NaN, never towards 0.
%
% MODE 'union' (primary)
%   A mutant whose location is ambiguous across several candidate objects is
%   still decidable: if NONE of the candidates was evaluated, then whichever
%   one the mutant actually sits on was not evaluated either, so 0 is sound.
%   If ANY candidate was evaluated the pair is kept as 1. That 1 is a
%   retention decision, not a claim about the mutation site: the evaluated
%   candidate may not be the one the mutant is on. Over-retaining costs one
%   execution, which is the acceptable direction.
%
% MODE 'strict' (ablation)
%   Ambiguous mutants are refused outright (NaN). Reported alongside the
%   primary result so the choice of semantics is visible rather than
%   asserted: it eliminates fewer pairs at a much higher unknown rate.
%
% Inputs:
%   cov        - struct from phase2.collectCoverage (.covered, .total)
%   candidates - 1xN cell of index vectors into the object list
%   mode       - 'union' (default) or 'strict'
%
% See also: phase2.collectCoverage, phase2.buildReachability

    if nargin < 3 || isempty(mode), mode = 'union'; end
    mode = validatestring(mode, {'union', 'strict'});

    nT = size(cov.covered, 1);
    nM = numel(candidates);
    R = nan(nT, nM);
    semantics = strings(1, nM);

    for m = 1:nM
        cand = candidates{m};

        if isempty(cand)
            semantics(m) = "unknown-unresolved";
            continue;                      % stays NaN for every test
        end

        if numel(cand) > 1 && strcmp(mode, 'strict')
            semantics(m) = "unknown-ambiguous";
            continue;
        end

        if isscalar(cand)
            semantics(m) = "direct";
        else
            semantics(m) = "union";
        end

        for t = 1:nT
            tot = cov.total(t, cand);
            cvd = cov.covered(t, cand);

            if all(tot == 0)
                R(t, m) = NaN;                     % no objective anywhere
            elseif any(cvd > 0)
                R(t, m) = 1;                       % some candidate evaluated
            elseif all(tot > 0 & cvd == 0)
                R(t, m) = 0;                       % all exist, none evaluated
            else
                % Mixed: some candidates carry an objective and some do not,
                % and none of the ones that do was evaluated. The mutant may
                % sit on an objective-less candidate, so 0 is not supportable.
                R(t, m) = NaN;
            end
        end
    end
end
