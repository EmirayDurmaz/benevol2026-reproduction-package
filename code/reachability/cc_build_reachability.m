function out = cc_build_reachability(varargin)
% NOTE: Identifiers of the mutation tool have been genericized as
% 'mutationtool.*'. The experiments were executed with MUT4SLX (not
% included in this package); these scripts are provided for inspection
% and require the tool to be obtained separately to execute.
% CC_BUILD_REACHABILITY Rebuild the CC1 reachability matrix from scratch
%
% Reconstruction of the CruiseControl "discovery step" whose script was not
% archived when results/CruiseControl/phase2/discovery_R.mat was produced on
% 23 Aug 2026. The mechanism is recovered from the artifact's provenance
% (dcm coverage, 15 tests replayed on the unmutated model, columns keyed by
% Stateflow SSIdNumber) and mirrors the HybridFSM builder
% (phase2.collectCoverage + phase2.reachability) with a direct SSId mapping:
%
%   COLLECT  run every enabled test case once on the ORIGINAL model with
%            coverage on (MetricSettings 'dcm'), keeping per-test cvdata
%   MAP      each of the 67 mutants targets one Stateflow element; the
%            element is found by its SSIdNumber in the ComputeTargetSpeed
%            chart (findAllMutants enumeration order = column order)
%   RULE     per element and test, query decisioninfo:
%              no decision objectives on the element -> NaN (undecidable,
%                retained; state/transition actions fall here)
%              objectives exist, none evaluated by the test -> 0
%              any objective evaluated -> 1
%            Doubt never eliminates.
%
% By default this is a VERIFICATION run: the rebuilt matrix is compared
% against results/CruiseControl/phase2/reachability_R.mat and NOT saved.
% Pass 'Save', true to archive the existing file and write the rebuilt one.
%
% Usage:
%   cc_build_reachability                 % rebuild + compare, no writes
%   cc_build_reachability('Save', true)
%
% See also: cc_env, run_cruisecontrol_coverage_based,
%           phase2.collectCoverage, pid_build_reachability

    p = inputParser;
    p.addParameter('Save', false, @(x) islogical(x) || isnumeric(x));
    p.parse(varargin{:});
    opt = p.Results;

    env = cc_env();

    % --- Enumerate mutants (column identity) ------------------------------
    orch = mutationtool.Orchestrator(); %#ok<NASGU>  % ensures package on path
    engine = mutationtool.MutationEngine.createWithDefaultOperators();
    cfgLoader = mutationtool.Orchestrator();
    cfgLoader.loadConfig(env.configPath);
    cfg = cfgLoader.Config;
    if ~bdIsLoaded(cfg.model)
        load_system(cfg.model);
    end
    engine.discoverStateflow(cfg.model);
    muts = engine.findAllMutants(cfg);
    if numel(muts) ~= env.totalMutants
        error('cc_build_reachability:MutantCount', ...
            'Enumerated %d mutants, expected %d.', numel(muts), env.totalMutants);
    end
    sids = cellfun(@(m) double(m.target.SSIdNumber), muts);
    ops  = cellfun(@(m) string(class(m.operator)), muts);

    % --- Resolve each distinct SSId to its Stateflow object ---------------
    rt = sfroot;
    chart = rt.find('-isa', 'Stateflow.Chart', 'Path', [env.model '/ComputeTargetSpeed']);
    if isempty(chart)
        error('cc_build_reachability:ChartMissing', ...
            'Chart %s/ComputeTargetSpeed not loaded.', env.model);
    end
    chart = chart(1);
    elems = [chart.find('-isa','Stateflow.State'); chart.find('-isa','Stateflow.Transition'); ...
             chart.find('-isa','Stateflow.Junction')];
    elemSid = arrayfun(@(e) double(e.SSIdNumber), elems);
    uSid = unique(sids);
    sid2obj = containers.Map('KeyType','double','ValueType','any');
    for s = uSid
        hit = find(elemSid == s);
        if numel(hit) ~= 1
            error('cc_build_reachability:SSIdUnresolved', ...
                'SSId %d resolves to %d chart elements.', s, numel(hit));
        end
        sid2obj(s) = elems(hit);
    end
    fprintf('mutants: %d | distinct SSIds: %d, all resolved in the chart\n', ...
        numel(muts), numel(uSid));

    % --- Per-test coverage of each element (work-copy pattern) ------------
    % Same protection as phase2.collectCoverage: enabling coverage dirties
    % the test file object, so collection runs on a throwaway copy.
    % env.testFile is absolute when the subject is obtained externally and
    % repo-relative in the historical layout; accept both.
    if isfile(env.testFile)
        subjectFile = env.testFile;
    else
        subjectFile = fullfile(env.projectRoot, env.testFile);
    end
    [tfDir, tfName, tfExt] = fileparts(subjectFile);
    workCopy = fullfile(tfDir, [tfName '__ccreach_tmp' tfExt]);
    copyfile(subjectFile, workCopy);
    cleanupCopy = onCleanup(@() cleanupWorkCopy(workCopy)); %#ok<NASGU>

    tf = sltest.testmanager.load(workCopy);
    cs = getCoverageSettings(tf);
    cs.RecordCoverage = true;
    cs.MetricSettings = 'dcm';

    suites = getTestSuites(tf);
    pool = {};
    for i = 1:numel(suites)
        cases = getTestCases(suites(i));
        for j = 1:numel(cases)
            if cases(j).Enabled, pool{end+1} = cases(j); end %#ok<AGROW>
        end
    end
    if numel(pool) ~= env.totalTests
        error('cc_build_reachability:PoolMismatch', ...
            'Pooled %d enabled tests, expected %d.', numel(pool), env.totalTests);
    end

    nT = env.totalTests;
    covered = nan(nT, numel(uSid));
    total = zeros(nT, numel(uSid));
    for k = 1:nT
        ws = warning('off','all');
        r = run(pool{k});
        warning(ws);
        d = cvdata(r.CoverageResults);
        for j = 1:numel(uSid)
            v = decisioninfo(d, sid2obj(uSid(j)));
            if isempty(v)
                covered(k,j) = NaN; total(k,j) = 0;
            else
                covered(k,j) = v(1); total(k,j) = v(2);
            end
        end
        fprintf('  test %2d/%d done\n', k, nT);
    end

    % --- Combine into R ----------------------------------------------------
    R = nan(nT, env.totalMutants);
    for m = 1:env.totalMutants
        j = find(uSid == sids(m));
        for t = 1:nT
            if total(t,j) == 0
                R(t,m) = NaN;               % no decision objective: undecidable
            elseif covered(t,j) > 0
                R(t,m) = 1;
            else
                R(t,m) = 0;
            end
        end
    end

    % --- Verify against the archived matrix --------------------------------
    ref = fullfile(fileparts(env.resultsDir), 'phase2', 'reachability_R.mat');
    out = struct('R', R, 'sids', sids, 'ops', ops);
    if exist(ref, 'file')
        L = load(ref, 'R', 'provenance');
        same = isequaln(R, L.R);
        sidMatch = isequal(sids(:)', double(L.provenance.columnSSId(:))');
        fprintf('\ncolumn SSIds match archived provenance: %d\n', sidMatch);
        fprintf('rebuilt R identical to archived R (isequaln): %d\n', same);
        fprintf('rebuilt: ones=%d zeros=%d NaN=%d | archived: ones=%d zeros=%d NaN=%d\n', ...
            sum(R(:)==1), sum(R(:)==0), sum(isnan(R(:))), ...
            sum(L.R(:)==1), sum(L.R(:)==0), sum(isnan(L.R(:))));
        out.matchesArchived = same && sidMatch;
        if ~(same && sidMatch)
            [tt, mm] = find((R ~= L.R) | (isnan(R) ~= isnan(L.R)));
            for q = 1:min(10, numel(tt))
                fprintf(2, '  diff at (test %d, mutant %d): rebuilt=%g archived=%g\n', ...
                    tt(q), mm(q), R(tt(q),mm(q)), L.R(tt(q),mm(q)));
            end
        end
    else
        fprintf('no archived matrix to compare against.\n');
    end

    if opt.Save
        provenance = struct('subject','CruiseControl', ...
            'source','cc_build_reachability (dcm coverage, per-test replay on unmutated model)', ...
            'columnKey','findAllMutants enumeration order', ...
            'columnSSId', sids, 'columnOperator', ops, ...
            'eliminationPct', 100*sum(R(:)==0)/numel(R), 'builtAt', datetime('now'));
        if exist(ref, 'file')
            stamp = char(datetime('now','Format','yyyy-MM-dd_HHmmss'));
            movefile(ref, strrep(ref, 'reachability_R.mat', ...
                ['superseded_' stamp '_reachability_R.mat']));
        end
        save(ref, 'R', 'provenance');
        fprintf('saved: %s\n', ref);
    end
end

function cleanupWorkCopy(workCopy)
    try
        loaded = sltest.testmanager.getTestFiles;
        for i = 1:numel(loaded)
            if strcmp(loaded(i).FilePath, workCopy), close(loaded(i)); end
        end
    catch
    end
    try
        if exist(workCopy, 'file'), delete(workCopy); end
    catch
        warning('cc_build_reachability:WorkCopyRemains', ...
            'Could not delete %s - remove it manually.', workCopy);
    end
end
