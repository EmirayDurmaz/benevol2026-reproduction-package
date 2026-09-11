function cov = collectCoverage(env, objects, opts)
% PHASE2.COLLECTCOVERAGE Per-test coverage of a fixed set of model objects
%
% Runs every enabled test case once on the ORIGINAL, UNMUTATED model with
% coverage recording on, and asks each object how many of its decision
% objectives that test evaluated. Nothing here knows about mutants: it
% answers "which tests exercised which objects", and that is all.
%
% Returns cov with:
%   .covered   nTests x nObjects, objectives evaluated (NaN when none exist)
%   .total     nTests x nObjects, objectives the object has (0 = none)
%   .testNames 1 x nTests
%   .elapsed   seconds
%
% WHY PER TEST AND NOT PER SUITE
% The whole point is discrimination between tests, so the per-test cvdata is
% the primitive. phase1's evaluate_phase1_coverage unions them for a set;
% this keeps them apart.
%
% POOL ORDER IS LOAD-BEARING
% Test index k here must be the same k that appears as testIndex in the
% Phase 1 trace, otherwise validation would compare unrelated columns. The
% pooling below mirrors SimulinkTestStrategy.runTests (every top-level
% suite in order, every Enabled case in order) and the count is checked
% against env.totalTests rather than assumed.
%
% See also: phase2.buildReachability, evaluate_phase1_coverage

    if nargin < 3, opts = struct(); end
    verbose = ~isfield(opts, 'verbose') || opts.verbose;

    % --- Work on a throwaway copy, never the experiment subject -----------
    % Enabling coverage writes RecordCoverage and MetricSettings into the
    % test file object, which dirties it; a later save then rewrites the
    % .mldatx. That file is the subject every Phase 1 result was measured
    % against, so it must come out of Phase 2 byte-identical. Restoring the
    % properties afterwards is not enough - it depends on the cleanup running
    % and on knowing every property that was touched. A copy cannot fail that
    % way. It lives beside the original so any relative reference from the
    % test file to its harness resolves identically.
    [subjectDir, subjectName, subjectExt] = fileparts(env.testFile);
    if isempty(subjectDir)
        subjectDir = fileparts(which(env.testFile));
    end
    workCopy = fullfile(subjectDir, [subjectName '__phase2_tmp' subjectExt]);
    copyfile(env.testFile, workCopy);
    cleanupCopy = onCleanup(@() cleanupWorkCopy(workCopy));

    tf = sltest.testmanager.load(workCopy);
    cs = getCoverageSettings(tf);
    cs.RecordCoverage = true;
    cs.MetricSettings = 'dcm';

    suites = getTestSuites(tf);
    pool = {};
    names = strings(0);
    for i = 1:numel(suites)
        cases = getTestCases(suites(i));
        for j = 1:numel(cases)
            if cases(j).Enabled
                pool{end+1} = cases(j);              %#ok<AGROW>
                names(end+1) = string(cases(j).Name); %#ok<AGROW>
            end
        end
    end

    nT = numel(pool);
    if isfield(env, 'totalTests') && nT ~= env.totalTests
        error('phase2:collectCoverage:PoolMismatch', ...
            ['Pooled %d enabled tests but the environment expects %d. Test ' ...
             'index alignment with the Phase 1 trace cannot be assumed.'], ...
            nT, env.totalTests);
    end

    nO = numel(objects);
    cov = struct();
    cov.covered = nan(nT, nO);
    cov.total = zeros(nT, nO);
    cov.testNames = names;

    t0 = tic;
    for k = 1:nT
        ws = warning('off', 'all');
        r = run(pool{k});
        warning(ws);

        d = cvdata(r.CoverageResults);
        for j = 1:nO
            v = decisioninfo(d, objects(j));
            if isempty(v)
                % No decision objective on this object. Recorded as total 0,
                % which downstream must read as "cannot tell", never as 0.
                cov.covered(k, j) = NaN;
                cov.total(k, j) = 0;
            else
                cov.covered(k, j) = v(1);
                cov.total(k, j) = v(2);
            end
        end

        if verbose
            fprintf('  %2d/%2d %-24s evaluated %2d/%d objects\n', ...
                k, nT, names(k), sum(cov.covered(k, :) > 0), nO);
        end
    end
    cov.elapsed = toc(t0);
end

function cleanupWorkCopy(workCopy)
% Close the copy in Test Manager and delete it. Any coverage settings written
% during collection die with it, so the subject file is never involved.
    try
        loaded = sltest.testmanager.getTestFiles;
        for i = 1:numel(loaded)
            if strcmp(loaded(i).FilePath, workCopy)
                close(loaded(i));
            end
        end
    catch
        % Closing is best-effort; deleting the file is what actually matters.
    end
    try
        if exist(workCopy, 'file')
            delete(workCopy);
        end
    catch
        warning('phase2:collectCoverage:WorkCopyRemains', ...
            'Could not delete the temporary test file %s - delete it manually.', workCopy);
    end
end
