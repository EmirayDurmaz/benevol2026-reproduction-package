function s = analyze(R, prov, testNames, opFields)
% PHASE2.ANALYZE Discrimination metrics for a reachability matrix
%
% Answers the only question that decides whether filtering is worth keeping:
% how much of the candidate space does it actually remove, and at what
% unknown rate. Reports what it finds - a matrix that eliminates nothing is
% a result, not a failure.
%
% Pure function. No kill data.
%
% Returns s with cell/mutant/test/operator breakdowns and pattern counts.
%
% See also: phase2.reachability, phase2.validate

    [nT, nM] = size(R);
    s = struct();
    s.nTests = nT;
    s.nMutants = nM;
    s.nCells = numel(R);

    s.nReached    = sum(R(:) == 1);
    s.nUnreached  = sum(R(:) == 0);
    s.nUnknown    = sum(isnan(R(:)));
    s.pctReached   = 100 * s.nReached   / s.nCells;
    s.pctUnreached = 100 * s.nUnreached / s.nCells;
    s.pctUnknown   = 100 * s.nUnknown   / s.nCells;

    % Per mutant
    s.perMutant = struct();
    s.perMutant.nReached   = sum(R == 1, 1);
    s.perMutant.nUnreached = sum(R == 0, 1);
    s.perMutant.nUnknown   = sum(isnan(R), 1);
    s.meanReachedPerMutant   = mean(s.perMutant.nReached);
    s.meanUnreachedPerMutant = mean(s.perMutant.nUnreached);
    s.meanUnknownPerMutant   = mean(s.perMutant.nUnknown);

    % Per test: how many mutant pairs this test is excused from
    s.perTest = struct();
    s.perTest.name       = testNames(:)';
    s.perTest.nReached   = sum(R == 1, 2)';
    s.perTest.nUnreached = sum(R == 0, 2)';
    s.perTest.nUnknown   = sum(isnan(R), 2)';

    % Distinct patterns bound how fine-grained the filter can ever be: two
    % mutants with the same column are indistinguishable to it.
    s.nDistinctMutantPatterns = size(unique(R', 'rows'), 1);
    s.nDistinctTestPatterns   = size(unique(R,  'rows'), 1);

    % Resolution provenance
    s.nResolvedUnique = sum([prov.resolvedCount] == 1);
    s.nAmbiguous      = sum([prov.resolvedCount] > 1);
    s.nUnresolved     = sum([prov.resolvedCount] == 0);

    % Per operator
    ops = unique(opFields, 'stable');
    s.perOperator = struct('operator', {}, 'nMutants', {}, ...
        'pctUnreached', {}, 'pctUnknown', {}, 'meanReached', {});
    for i = 1:numel(ops)
        sel = opFields == ops(i);
        sub = R(:, sel);
        s.perOperator(end+1) = struct( ...
            'operator', ops(i), ...
            'nMutants', sum(sel), ...
            'pctUnreached', 100 * sum(sub(:) == 0) / numel(sub), ...
            'pctUnknown',   100 * sum(isnan(sub(:))) / numel(sub), ...
            'meanReached',  mean(sum(sub == 1, 1))); %#ok<AGROW>
    end

    % What Phase 2B inherits: everything not provably unreachable.
    s.nCandidatePairs = s.nReached + s.nUnknown;
    s.pctPairsEliminated = s.pctUnreached;
end
