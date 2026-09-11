function ok = selftest()
% PHASE2.SELFTEST Semantics checks for phase2.reachability
%
% The safety argument for the whole filter rests on one claim: a 0 is only
% ever produced when every candidate mapping demonstrably has an objective
% that this test did not evaluate. These cases pin that down on synthetic
% coverage, where the expected answer is known by construction, so a later
% edit to the semantics cannot quietly weaken it.
%
% Run: phase2.selftest

    cases = {
    % name                       covered        total        cand   union  strict
      'all candidates unevaluated', [0 0 0],     [2 2 2],     [1 2 3], 0,   NaN
      'one candidate evaluated',    [0 1 0],     [2 2 2],     [1 2 3], 1,   NaN
      'missing objective, none hit',[0 NaN 0],   [2 0 2],     [1 2 3], NaN, NaN
      'missing objective, one hit', [1 NaN 0],   [2 0 2],     [1 2 3], 1,   NaN
      'single candidate, unhit',    [0 0 0],     [2 2 2],     2,       0,   0
      'single candidate, hit',      [0 1 0],     [2 2 2],     2,       1,   1
      'single candidate, no obj',   [0 NaN 0],   [2 0 2],     2,       NaN, NaN
      'empty candidate list',       [1 1 1],     [2 2 2],     [],      NaN, NaN
    };

    ok = true;
    fprintf('=== phase2.reachability semantics ===\n');
    for i = 1:size(cases, 1)
        name = cases{i, 1};
        cov = struct('covered', cases{i, 2}, 'total', cases{i, 3});
        cand = {cases{i, 4}};
        expU = cases{i, 5};
        expS = cases{i, 6};

        gotU = phase2.reachability(cov, cand, 'union');
        gotS = phase2.reachability(cov, cand, 'strict');

        passU = same(gotU, expU);
        passS = same(gotS, expS);
        ok = ok && passU && passS;

        fprintf('  %-30s union %-4s (exp %-4s) %s | strict %-4s (exp %-4s) %s\n', ...
            name, str(gotU), str(expU), tick(passU), ...
            str(gotS), str(expS), tick(passS));
    end

    fprintf('\n%s\n', ternary(ok, 'ALL PASS', 'FAILURES PRESENT'));

    % The property that matters most, stated as a property rather than a
    % table row: a 0 must never appear where any candidate was evaluated.
    rng(0, 'twister');
    for trial = 1:2000
        n = randi(4);
        tot = randi([0 2], 1, n) * 2;
        cvd = nan(1, n);
        for j = 1:n
            if tot(j) > 0, cvd(j) = randi([0 tot(j)]); end
        end
        cov = struct('covered', cvd, 'total', tot);
        r = phase2.reachability(cov, {1:n}, 'union');
        if r == 0 && any(cvd > 0)
            fprintf('PROPERTY VIOLATION: 0 with an evaluated candidate\n');
            disp(cvd); disp(tot);
            ok = false; break;
        end
    end
    fprintf('property (no 0 when any candidate evaluated): %s\n', ternary(ok, 'holds', 'VIOLATED'));

    ok = selectorCases() && ok;
end

% ----------------------------------------------------------------------
function ok = selectorCases()
% Checks for phase2.TestSelector, the seam that turns R into per-mutant test
% indices. Synthetic R only - no model, no Test Manager, no mutation run.
%
% The two claims worth pinning down are the ones a later edit could quietly
% break: that only R == 0 is ever dropped (NaN must survive, or the safety
% argument for the filter collapses), and that the seam removes without
% reordering (otherwise the filtered arm would differ from the unfiltered
% arm by test order as well, and the comparison would measure two things).

    ok = true;
    fprintf('\n=== phase2.TestSelector ===\n');

    %        t1  t2  t3  t4
    R = [     1,  0,  1,  NaN;    % test 1
              0,  0,  1,  1;      % test 2
            NaN,  0,  0,  0;      % test 3
              1,  1,  1,  NaN];   % test 4
    nT = size(R, 1);

    expected = { ...
        1, [1 3 4],   [2];        ...  % col 1: one 0, one NaN retained
        2, [4],       [1 2 3];    ...  % col 2: mostly eliminated
        3, [1 2 4],   [3];        ...  % col 3: single elimination
        4, [1 2 4],   [3]};            % col 4: NaN entries retained

    for i = 1:size(expected, 1)
        m = expected{i, 1};
        sel = phase2.TestSelector(R, 'filtered');
        sel.onExecutionStarted([]);
        for k = 1:m, sel.onMutantStarted([], struct()); end
        got = sel.select(nT);

        keptOK = isequal(got, expected{i, 2});
        col = R(:, m);
        removed = setdiff(1:nT, got);
        zeroOnly = all(col(removed) == 0);
        nanKept = all(ismember(find(isnan(col))', got));
        ordered = isequal(got, sort(got));

        pass = keptOK && zeroOnly && nanKept && ordered;
        ok = ok && pass;
        fprintf('  mutant %d: kept [%-8s] expected [%-8s] %s  (0-only %s, NaN kept %s, ordered %s)\n', ...
            m, num2str(got), num2str(expected{i, 2}), tick(pass), ...
            tick(zeroOnly), tick(nanKept), tick(ordered));
    end

    % The unfiltered arm must return the whole pool through the same seam,
    % so the two arms share one execution path.
    selU = phase2.TestSelector(R, 'unfiltered');
    selU.onExecutionStarted([]); selU.onMutantStarted([], struct());
    passAll = isequal(selU.select(nT), 1:nT);
    ok = ok && passAll;
    fprintf('  unfiltered returns the full pool: %s\n', tick(passAll));

    % Ordinal -> R column under a mutant plan. A wrong mapping would filter
    % each mutant with another mutant's row, which no downstream check would
    % catch, so it is asserted here.
    selP = phase2.TestSelector(R, 'filtered', [3 1]);
    selP.onExecutionStarted([]); selP.onMutantStarted([], struct());
    passMap = isequal(selP.select(nT), [1 2 4]);   % column 3
    ok = ok && passMap;
    fprintf('  plan order maps ordinal 1 -> column 3: %s\n', tick(passMap));

    % Guards.
    guards = { ...
        @() selU.select(nT - 1),                       'phase2:TestSelector:TestCountMismatch'; ...
        @() guardNoMutant(R, nT),                      'phase2:TestSelector:NoMutantInFlight'; ...
        @() phase2.TestSelector(R * 2, 'filtered'),    'phase2:TestSelector:InvalidRValues'};
    for i = 1:size(guards, 1)
        got = '<none>';
        try, guards{i, 1}(); catch ME, got = ME.identifier; end
        pass = strcmp(got, guards{i, 2});
        ok = ok && pass;
        fprintf('  guard %-42s %s\n', guards{i, 2}, tick(pass));
    end

    % Conservation, over the real matrix when it is available: every pair is
    % either kept or removed, and removals equal the zero count exactly.
    % This file lives at <packageRoot>/code/reachability/+phase2/, so the
    % package root is four levels up; results live under results/raw.
    rFile = fullfile(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath'))))), ...
        'results', 'raw', 'HybridFSM', 'phase2', 'reachability_R.mat');
    if exist(rFile, 'file')
        L = load(rFile, 'R');
        Rreal = L.R;
        sel = phase2.TestSelector(Rreal, 'filtered');
        sel.onExecutionStarted([]);
        kept = 0;
        for m = 1:size(Rreal, 2)
            sel.onMutantStarted([], struct());
            kept = kept + numel(sel.select(size(Rreal, 1)));
        end
        s = sel.summary();
        expKept = sum(Rreal(:) == 1) + sum(isnan(Rreal(:)));
        pass = (kept == expKept) && (s.totalRemoved == sum(Rreal(:) == 0));
        ok = ok && pass;
        fprintf('  real R: kept %d (= %d ones + %d NaN), removed %d (= %d zeros) %s\n', ...
            kept, sum(Rreal(:) == 1), sum(isnan(Rreal(:))), ...
            s.totalRemoved, sum(Rreal(:) == 0), tick(pass));
    else
        fprintf('  real R not on disk - conservation check skipped\n');
    end

    fprintf('%s\n', ternary(ok, 'selector: ALL PASS', 'selector: FAILURES PRESENT'));
end

function guardNoMutant(R, nT)
    s = phase2.TestSelector(R, 'filtered');
    s.select(nT);
end

function t = same(a, b)
    t = (isnan(a) && isnan(b)) || (~isnan(a) && ~isnan(b) && a == b);
end

function s = str(v)
    if isnan(v), s = 'NaN'; else, s = sprintf('%d', v); end
end

function s = tick(b)
    if b, s = 'ok'; else, s = 'FAIL'; end
end

function o = ternary(c, a, b)
    if c, o = a; else, o = b; end
end
