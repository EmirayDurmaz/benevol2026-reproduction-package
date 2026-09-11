function loc = hybridfsm(mutants, env)
% NOTE: Identifiers of the mutation tool have been genericized as
% 'mutationtool.*'. The experiments were executed with MUT4SLX (not
% included in this package); these scripts are provided for inspection
% and require the tool to be obtained separately to execute.
% PHASE2.ADAPTERS.HYBRIDFSM Model-specific mutant -> coverage-object mapping
%
% Everything model-specific about Phase 2A lives in an adapter like this
% one. The core (phase2.buildReachability) only ever sees the generic
% structure returned here, so a second model needs a second adapter and no
% change to the algorithm.
%
% TWO PROBLEMS THIS ADAPTER SOLVES, BOTH SPECIFIC TO HybridFSM
%
% 1. The mutant records do not identify the mutated transition. All 179
%    Stateflow mutants carry blockPath 'stateMachine/Chart' - the chart, not
%    the transition - and no SID. The only location signal left is the
%    transition's condition text, which the mutation tool stores as originalValue.
%    Matching is done on the RAW string: two of this chart's transitions
%    differ only by a space ('[(SOC < SOCmin...' vs '[(SOC<SOCmin...'), so
%    normalising whitespace would merge two genuinely different transitions.
%
% 2. Coverage is not recorded on the model the mutants name. The suite runs
%    the harness FSM_Model, which pulls the chart in as a Subsystem
%    Reference, so coverage objects live under
%    'FSM_Model/Subsystem Reference/Chart' while mutants name
%    'stateMachine/Chart'. Querying the SUT chart's transition objects
%    against harness cvdata returns empty for every one of them - it looks
%    exactly like "no objective exists" and would silently poison the whole
%    matrix. The bridge is verified structurally below rather than assumed.
%
% Returns loc, a struct with:
%   .objects            - coverage-queryable objects, in query order
%   .objectIds          - their SIDs
%   .objectLabels       - their label strings
%   .coverageContext    - path of the model coverage is recorded against
%   .candidates         - 1xN cell, indices into .objects per mutant
%                         (empty = unresolvable)
%   .evidenceMetric     - 1xN string, 'decision' | 'none'
%   .mappingStrategy    - 1xN string, how each mutant was located
%
% See also: phase2.buildReachability, phase2.resolveMutantLocation

    sutChartPath     = 'stateMachine/Chart';
    harnessChartPath = 'FSM_Model/Subsystem Reference/Chart';

    rt = sfroot;
    chSut = rt.find('-isa', 'Stateflow.Chart', 'Path', sutChartPath);
    chCov = rt.find('-isa', 'Stateflow.Chart', 'Path', harnessChartPath);

    if isempty(chSut) || isempty(chCov)
        error('phase2:adapters:ChartMissing', ...
            ['Both charts must be loaded before mapping.\n  SUT     %s: %s' ...
             '\n  harness %s: %s\nOpen the project and run the suite once.'], ...
            sutChartPath, mat2str(~isempty(chSut)), ...
            harnessChartPath, mat2str(~isempty(chCov)));
    end

    trSut = chSut(1).find('-isa', 'Stateflow.Transition');
    trCov = chCov(1).find('-isa', 'Stateflow.Transition');

    % The bridge is only sound if the two charts really are the same chart
    % seen twice. Verify it instead of trusting the Subsystem Reference:
    % same transition count, and the same label in the same position.
    if numel(trSut) ~= numel(trCov)
        error('phase2:adapters:BridgeMismatch', ...
            ['SUT chart has %d transitions, coverage chart has %d. The ' ...
             'index bridge is not valid; mapping would be meaningless.'], ...
            numel(trSut), numel(trCov));
    end
    lblSut = arrayfun(@(t) string(t.LabelString), trSut);
    lblCov = arrayfun(@(t) string(t.LabelString), trCov);
    if ~all(lblSut == lblCov)
        bad = find(lblSut ~= lblCov, 1);
        error('phase2:adapters:BridgeMismatch', ...
            ['Transition %d differs between charts:\n  SUT     : %s\n  ' ...
             'coverage: %s\nPositional bridge rejected.'], ...
            bad, lblSut(bad), lblCov(bad));
    end

    loc = struct();
    loc.objects         = trCov;
    loc.objectIds       = arrayfun(@(t) double(t.Id), trCov);
    loc.objectLabels    = lblCov;
    loc.coverageContext = harnessChartPath;
    loc.sutContext      = sutChartPath;

    n = numel(mutants);
    loc.candidates      = cell(1, n);
    loc.evidenceMetric  = strings(1, n);
    loc.mappingStrategy = strings(1, n);

    for i = 1:n
        m = mutants(i);

        if ~strcmp(m.blockType, 'Stateflow.Transition')
            % Sum and friends carry no decision/condition/MC-DC objective at
            % all. Leaving them unresolved is what makes them NaN downstream,
            % which is the required reading: no objective is not evidence of
            % non-reachability.
            loc.candidates{i}     = [];
            loc.evidenceMetric(i) = "none";
            loc.mappingStrategy(i) = "unsupported-blocktype";
            continue;
        end

        hit = find(lblSut == string(m.originalValue));   % raw, not normalised
        loc.candidates{i}     = hit;
        loc.evidenceMetric(i) = "decision";
        if isempty(hit)
            loc.mappingStrategy(i) = "label-exact:none";
            loc.evidenceMetric(i)  = "none";
        elseif isscalar(hit)
            loc.mappingStrategy(i) = "label-exact:unique";
        else
            loc.mappingStrategy(i) = "label-exact:ambiguous";
        end
    end
end
