function writeArtifacts(out)
% PHASE2.WRITEARTIFACTS Emit the Phase 2A record
%
% Every mapping decision is written with the evidence behind it, because a
% reachability value is only trustworthy if a reader can see which object it
% came from and by what rule. The long CSV is deliberately one row per
% (test, mutant) pair: 4575 rows is small enough to sort in a spreadsheet
% and settle an argument about a single cell.
%
% Files (all under env.phase2Dir):
%   phase2_reachability.mat          R, Rstrict, provenance, coverage, stats
%   phase2_reachability_long.csv     one row per (test, mutant)
%   phase2_reachability_summary.csv  one row per mutant
%   phase2_validation.csv            post-hoc kill check
%   phase2_summary.md                human-readable findings
%
% See also: phase2.buildReachability

    d = out.env.phase2Dir;
    R = out.R; Rs = out.Rstrict; prov = out.prov;
    names = out.testNames;
    [nT, nM] = size(R);

    save(fullfile(d, 'phase2_reachability.mat'), '-struct', 'out', ...
        'R', 'Rstrict', 'prov', 'cov', 'statsUnion', 'statsStrict', ...
        'validation', 'testNames', '-v7');

    % --- long -------------------------------------------------------------
    n = nT * nM;
    T = table('Size', [n 11], ...
        'VariableTypes', {'double','string','double','string','string', ...
                          'string','string','double','string','double','double'}, ...
        'VariableNames', {'testIdx','testName','mutantIdx','operatorName', ...
                          'blockPath','locationKey','candidateSIDs', ...
                          'resolvedCount','evidenceMetric','reachability', ...
                          'reachabilityStrict'});
    k = 0;
    for m = 1:nM
        p = prov(m);
        for t = 1:nT
            k = k + 1;
            T(k, :) = {t, names(t), m, p.operatorName, p.blockPath, ...
                p.locationKey, p.candidateSIDs, p.resolvedCount, ...
                p.evidenceMetric, R(t, m), Rs(t, m)};
        end
    end
    writetable(T, fullfile(d, 'phase2_reachability_long.csv'));

    % --- summary ----------------------------------------------------------
    S = table((1:nM)', [prov.operatorName]', [prov.blockType]', ...
        sum(R == 1, 1)', sum(R == 0, 1)', sum(isnan(R), 1)', ...
        [prov.resolvedCount]', [prov.ambiguous]', [prov.evidenceMetric]', ...
        [prov.mappingStrategy]', [prov.semantics]', [prov.candidateSIDs]', ...
        'VariableNames', {'mutantIdx','operatorName','blockType','nReached', ...
                          'nNotReached','nUnknown','resolvedCount','ambiguous', ...
                          'evidenceMetric','mappingStrategy','semantics', ...
                          'candidateSIDs'});
    writetable(S, fullfile(d, 'phase2_reachability_summary.csv'));

    % --- validation -------------------------------------------------------
    v = out.validation;
    V = table(v.nKills, v.nR1, v.nNaN, v.nR0, v.sound, ...
        'VariableNames', {'nKillPairs','nReached','nUnknown','nUnreached_VIOLATION','sound'});
    writetable(V, fullfile(d, 'phase2_validation.csv'));
    if ~isempty(v.violations)
        writetable(v.violations, fullfile(d, 'phase2_validation_violations.csv'));
    end

    writeSummaryMd(fullfile(d, 'phase2_summary.md'), out);
end

function writeSummaryMd(path, out)
    su = out.statsUnion; ss = out.statsStrict; v = out.validation;
    fid = fopen(path, 'w');
    c = onCleanup(@() fclose(fid));
    w = @(varargin) fprintf(fid, varargin{:});

    w('# Phase 2A - Coverage-based reachability (HybridFSM)\n\n');
    w('Generated %s\n\n', datestr(now, 'yyyy-mm-dd HH:MM')); %#ok<TNOW1,DATST>

    w('## What was built\n\n');
    w('A %d x %d matrix R(test, mutant) derived only from coverage of the\n', su.nTests, su.nMutants);
    w('ORIGINAL, unmutated model. Kill outcomes were not consulted at any\n');
    w('point before the matrix existed.\n\n');
    w('- coverage context: `%s`\n', out.loc.coverageContext);
    w('- SUT context: `%s`\n', out.loc.sutContext);
    w('- coverage objects: %d transitions\n', numel(out.loc.objects));
    w('- coverage replay: %.1f s for %d tests\n\n', out.cov.elapsed, su.nTests);

    w('## Mapping outcome\n\n');
    w('| | Mutants |\n|---|---|\n');
    w('| resolved to exactly one object | %d |\n', su.nResolvedUnique);
    w('| ambiguous (>1 candidate) | %d |\n', su.nAmbiguous);
    w('| unresolved (no objective / unsupported type) | %d |\n\n', su.nUnresolved);

    w('## Discrimination - union semantics (primary)\n\n');
    w('| Value | Cells | Share |\n|---|---|---|\n');
    w('| 1 retained | %d | %.1f%% |\n', su.nReached, su.pctReached);
    w('| 0 eliminated | %d | %.1f%% |\n', su.nUnreached, su.pctUnreached);
    w('| NaN unknown | %d | %.1f%% |\n\n', su.nUnknown, su.pctUnknown);
    w('Mean per mutant: %.2f tests reached, %.2f eliminated, %.2f unknown (of %d).\n\n', ...
        su.meanReachedPerMutant, su.meanUnreachedPerMutant, su.meanUnknownPerMutant, su.nTests);
    w('Distinct mutant patterns: %d (upper bound on how finely the filter can\n', su.nDistinctMutantPatterns);
    w('ever distinguish mutants).\n\n');
    w('Candidate pairs handed to Phase 2B: **%d** of %d.\n\n', su.nCandidatePairs, su.nCells);

    w('## Ablation - strict semantics\n\n');
    w('Ambiguous mutants refused instead of unioned.\n\n');
    w('| Semantics | Eliminated | Unknown |\n|---|---|---|\n');
    w('| union (primary) | %.1f%% | %.1f%% |\n', su.pctUnreached, su.pctUnknown);
    w('| strict (ablation) | %.1f%% | %.1f%% |\n\n', ss.pctUnreached, ss.pctUnknown);
    w('Union is preferred because it eliminates more while keeping the rule\n');
    w('for producing a 0 unchanged: a 0 still requires every candidate to\n');
    w('carry an objective that the test did not evaluate. It trades a weaker\n');
    w('claim behind each 1 - retention, not reach - for a much lower unknown\n');
    w('rate, and false positives cost only wasted executions.\n\n');

    w('## Post-hoc validation\n\n');
    w('Kill data used here and nowhere else, after the matrix was complete.\n\n');
    w('| | Count |\n|---|---|\n');
    w('| killing pairs | %d |\n', v.nKills);
    w('| classified reachable (1) | %d |\n', v.nR1);
    w('| classified unknown (NaN) | %d |\n', v.nNaN);
    w('| classified unreachable (0) - VIOLATIONS | %d |\n\n', v.nR0);
    if v.sound
        w('No killing test was classified unreachable. The filter produced no\n');
        w('false negatives on this data. This does not prove the mapping\n');
        w('correct - it means this data failed to refute it.\n\n');
    else
        w('**%d violations.** The mapping is unsound; see\n', v.nR0);
        w('`phase2_validation_violations.csv`.\n\n');
    end

    w('## Per operator\n\n');
    w('| Operator | Mutants | Eliminated | Unknown | Mean tests reached |\n');
    w('|---|---|---|---|---|\n');
    for i = 1:numel(su.perOperator)
        o = su.perOperator(i);
        w('| %s | %d | %.1f%% | %.1f%% | %.2f |\n', o.operator, o.nMutants, ...
            o.pctUnreached, o.pctUnknown, o.meanReached);
    end
    w('\n');

    w('## Per test\n\n');
    w('| # | Test | Reached | Eliminated | Unknown |\n|---|---|---|---|---|\n');
    for t = 1:su.nTests
        w('| %d | %s | %d | %d | %d |\n', t, su.perTest.name(t), ...
            su.perTest.nReached(t), su.perTest.nUnreached(t), su.perTest.nUnknown(t));
    end
    w('\n');
end
