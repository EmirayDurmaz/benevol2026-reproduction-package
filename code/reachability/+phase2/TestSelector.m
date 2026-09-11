classdef TestSelector < mutationtool.IExecutionObserver
% NOTE: Identifiers of the mutation tool have been genericized as
% 'mutationtool.*'. The experiments were executed with MUT4SLX (not
% included in this package); these scripts are provided for inspection
% and require the tool to be obtained separately to execute.
    % PHASE2.TESTSELECTOR Mutant-aware test selection for the Phase 2 arms
    %
    % Supplies, for the mutant currently under test, the indices of the tests
    % that should run. Both Phase 2 conditions use this same object and the
    % same execution path; they differ only in what select() returns:
    %
    %   'unfiltered'  every test, in pool order
    %   'filtered'    every test except those with R(test, mutant) == 0
    %
    % R == 1 and R == NaN are BOTH retained. NaN means undecidable, and the
    % safety property of the whole filter is that doubt never eliminates: a
    % wrongly kept pair costs one execution, a wrongly dropped pair silently
    % loses a kill that nothing downstream can recover.
    %
    % HOW IT LEARNS THE MUTANT
    % Orchestrator.executeMutationsPhase4 fires onMutantStarted before it
    % calls TestExecutor.runTests, so by the time the strategy asks for
    % indices the ordinal below is the mutant about to be tested. This is the
    % same interleaving guarantee TestTraceRecorder relies on, which is why
    % no mutant context had to be threaded through TestExecutor.
    %
    % COLUMN MAPPING
    % R's columns are indexed by GLOBAL mutant index (discovery order, 1..183),
    % which equals the execution ordinal only when mutants run in discovery
    % order. Under a mutant plan they differ, so a plan-order run must pass
    % MutantOrder so ordinal -> global index can be resolved. Getting this
    % wrong would filter each mutant with another mutant's row, so it is
    % asserted rather than assumed.
    %
    % Usage:
    %   sel = phase2.TestSelector(R, 'filtered');
    %   cfg.testSelector = @sel.select;
    %   orch.addObserver(sel);
    %
    % See also: phase2.reachability, mutationtool.IExecutionObserver

    properties (SetAccess = private)
        R                   % nTests x nMutants, values 1 / 0 / NaN
        Mode                % 'filtered' | 'unfiltered'
        MutantOrder         % [] (discovery order) or plan order, global indices
        Calls = 0           % select() invocations
        OverheadSeconds = 0 % cumulative time spent inside select()
        Decisions = {}      % per-call record, for validation and audit
    end

    properties (Access = private)
        Ordinal = 0         % execution ordinal of the in-flight mutant
        StartedCount = 0
    end

    methods
        function obj = TestSelector(R, mode, mutantOrder)
            if nargin < 2 || isempty(mode), mode = 'filtered'; end
            if nargin < 3, mutantOrder = []; end

            mode = validatestring(mode, {'filtered', 'unfiltered'});
            if ~isnumeric(R) || isempty(R)
                error('phase2:TestSelector:InvalidR', 'R must be a non-empty numeric matrix.');
            end
            bad = ~(R == 0 | R == 1 | isnan(R));
            if any(bad(:))
                error('phase2:TestSelector:InvalidRValues', ...
                    'R must contain only 0, 1 or NaN (%d other values found).', sum(bad(:)));
            end

            obj.R = R;
            obj.Mode = mode;
            obj.MutantOrder = mutantOrder(:)';
        end

        function idx = select(obj, totalCount)
            % SELECT Test indices to run for the mutant currently under test
            t0 = tic;

            % --- assertion: the pool must match R's test dimension ---------
            if totalCount ~= size(obj.R, 1)
                error('phase2:TestSelector:TestCountMismatch', ...
                    ['Pool has %d tests but R describes %d. The reachability ' ...
                     'matrix was built against a different test set, so its ' ...
                     'columns cannot be trusted to address these tests.'], ...
                    totalCount, size(obj.R, 1));
            end

            % --- assertion: ordinal must resolve to a real R column --------
            if obj.Ordinal < 1
                error('phase2:TestSelector:NoMutantInFlight', ...
                    ['select() was called with no mutant in flight. The selector ' ...
                     'must be registered as an observer so onMutantStarted can ' ...
                     'identify the mutant before tests are chosen.']);
            end
            global_m = obj.globalIndex(obj.Ordinal);
            if global_m < 1 || global_m > size(obj.R, 2)
                error('phase2:TestSelector:MutantIndexOutOfRange', ...
                    ['Execution ordinal %d maps to global mutant %d, outside ' ...
                     'R''s %d columns.'], obj.Ordinal, global_m, size(obj.R, 2));
            end

            all_idx = 1:totalCount;
            switch obj.Mode
                case 'unfiltered'
                    idx = all_idx;
                    removed = [];
                case 'filtered'
                    col = obj.R(:, global_m);
                    keep = ~(col == 0);          % retains 1 and NaN
                    idx = all_idx(keep);
                    removed = all_idx(~keep);
            end

            elapsed = toc(t0);
            obj.Calls = obj.Calls + 1;
            obj.OverheadSeconds = obj.OverheadSeconds + elapsed;
            obj.Decisions{end+1} = struct( ...
                'ordinal', obj.Ordinal, 'globalMutant', global_m, ...
                'mode', obj.Mode, 'kept', idx, 'removed', removed, ...
                'nKept', numel(idx), 'nRemoved', numel(removed), ...
                'seconds', elapsed);
        end

        function g = globalIndex(obj, ordinal)
            % GLOBALINDEX Execution ordinal -> R column
            if isempty(obj.MutantOrder)
                g = ordinal;                      % discovery order
            else
                if ordinal > numel(obj.MutantOrder)
                    error('phase2:TestSelector:OrdinalBeyondPlan', ...
                        'Ordinal %d exceeds the %d-entry mutant order.', ...
                        ordinal, numel(obj.MutantOrder));
                end
                g = obj.MutantOrder(ordinal);
            end
        end

        function s = summary(obj)
            s = struct('mode', obj.Mode, 'calls', obj.Calls, ...
                'overheadSeconds', obj.OverheadSeconds, ...
                'overheadPerCall', obj.OverheadSeconds / max(obj.Calls, 1));
            if isempty(obj.Decisions)
                s.totalKept = 0; s.totalRemoved = 0;
            else
                s.totalKept = sum(cellfun(@(d) d.nKept, obj.Decisions));
                s.totalRemoved = sum(cellfun(@(d) d.nRemoved, obj.Decisions));
            end
        end

        %% IExecutionObserver

        function onExecutionStarted(obj, ~)
            obj.Ordinal = 0;
            obj.StartedCount = 0;
        end

        function onMutantStarted(obj, ~, ~)
            obj.StartedCount = obj.StartedCount + 1;
            obj.Ordinal = obj.StartedCount;
        end

        function onMutantCompleted(obj, ~, ~, ~)
            obj.Ordinal = 0;
        end

        function onExecutionCompleted(obj, ~)
            obj.Ordinal = 0;
        end

        function onLogMessage(~, ~, ~, ~)
        end
    end
end
