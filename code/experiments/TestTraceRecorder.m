classdef TestTraceRecorder < mutationtool.IExecutionObserver
% NOTE: Identifiers of the mutation tool have been genericized as
% 'mutationtool.*'. The experiments were executed with MUT4SLX (not
% included in this package); these scripts are provided for inspection
% and require the tool to be obtained separately to execute.
    % TESTTRACERECORDER Per-test trace, correlated to mutants by observation
    %
    % Records one row per executed test case and stamps it with the mutant
    % that was under test at the time.
    %
    % WHY THE MUTANT LABEL LIVES HERE AND NOT IN CORE
    % Orchestrator.executeMutationsPhase4 is sequential and single-threaded,
    % and it already brackets every test run:
    %
    %   onMutantStarted(mutant)  ->  TestExecutor.runTests  ->  onMutantCompleted
    %
    % Every test event emitted from inside the strategy therefore falls, in
    % call order, strictly between one start and its completion. That
    % interleaving IS the correlation, so no mutant-context state needs to be
    % added to TestExecutor or Orchestrator - this recorder simply remembers
    % what it was last told.
    %
    % TWO DIFFERENT MUTANT KEYS, KEPT APART
    %   mutantExecutionOrder - 1,2,3... in the order mutants were STARTED.
    %                          An ordinal of this run only. Under a mutant
    %                          plan it indexes the plan's executed order, not
    %                          the discovered-mutant pool, so ordinal 5 is a
    %                          DIFFERENT mutant in every permutation.
    %   mutantKey            - target path + operator + value transition,
    %                          which is what identifies the same mutant
    %                          across seeds and is what a cross-run join must
    %                          use. Composed here because the mutant struct
    %                          built by MutationEngine.findAllMutants carries
    %                          no id field, despite what IExecutionObserver's
    %                          comment advertises.
    %
    % THE BASELINE RUN CANNOT BE MISLABELLED
    % runInitialTests happens before startExecution and before any
    % onMutantStarted fires, so no mutant is in flight while the unmutated
    % suite runs and those rows are recorded with isBaseline = true and
    % mutantExecutionOrder = 0.
    %
    % onMutantStarted IS THE BOUNDARY, NOT onMutantCompleted
    % A mutant that throws, and a run stopped mid-flight, both leave
    % Orchestrator's try block without reaching onMutantCompleted. Clearing
    % only on completion would let a dead label leak forward, so the label is
    % OVERWRITTEN on every start: one mutant's tests can never be attributed
    % to the next.
    %
    % WHAT THE FLAG DOES AND DOES NOT CLAIM
    % Rows left open keep the identity onMutantStarted established - those
    % tests really did run under that mutant - and are flagged
    % mutantDidNotComplete. That flag is deliberately NEUTRAL about cause.
    % These boundaries cannot separate "the mutant errored" from "the run was
    % terminated": if the LAST mutant errors, no further onMutantStarted ever
    % arrives and the rows are settled by onExecutionCompleted, exactly as a
    % termination would settle them. Distinguishing the two needs an explicit
    % error signal that Phase 1 does not have, so the recorder declines to
    % guess. Downstream: treat mutantDidNotComplete rows as unusable for
    % kill accounting, whatever the cause.
    %
    % Usage:
    %   rec = TestTraceRecorder();
    %   config.telemetry.onTestExecuted = rec.sink();
    %   orchestrator.addObserver(rec);
    %   mutationtool.ExperimentPlan.resetTelemetryFailures();
    %   orchestrator.run();
    %   stats = mutationtool.ExperimentPlan.telemetryFailureStats();
    %   % stats.count > 0  =>  trace is incomplete, INVALID for experiments
    %   T = rec.table();
    %
    % See also: mutationtool.ExperimentPlan, mutationtool.IExecutionObserver

    properties (SetAccess = private)
        Events = {}             % Cell array of recorded event structs
    end

    properties (Access = private)
        InMutant = false        % Is a mutant currently in flight?
        ExecutionOrder = 0      % Ordinal of the in-flight mutant
        CurrentKey = ''
        CurrentOperator = ''
        CurrentTarget = ''
        CurrentTransition = ''
        StartedCount = 0
        OpenRows = []           % Row numbers belonging to the in-flight mutant
    end

    methods
        function h = sink(obj)
            % SINK Function handle for config.telemetry.onTestExecuted
            h = @obj.recordTestEvent;
        end

        function recordTestEvent(obj, event)
            % RECORDTESTEVENT Stamp one test event with the current mutant
            %
            % Deliberately cheap: field assignment only. No clock call, no
            % formatting, no I/O - this runs inside the measured loop.

            event.mutantExecutionOrder = obj.ExecutionOrder;
            event.mutantKey = obj.CurrentKey;
            event.mutantOperator = obj.CurrentOperator;
            event.mutantTarget = obj.CurrentTarget;
            event.mutantTransition = obj.CurrentTransition;
            event.isBaseline = ~obj.InMutant;
            event.mutantCompleted = false;       % settled at the boundary
            event.mutantDidNotComplete = false;  % cause deliberately unstated

            obj.Events{end+1} = event;
            if obj.InMutant
                obj.OpenRows(end+1) = numel(obj.Events);
            end
        end

        %% IExecutionObserver

        function onExecutionStarted(obj, ~)
            % Baseline rows precede this point and are not mutant rows, so
            % there should be nothing open; settle defensively.
            obj.settleOpenRows(false);
        end

        function onMutantStarted(obj, ~, mutant)
            % The authoritative boundary: anything still open belongs to the
            % previous mutant and is settled before the label is replaced.
            obj.settleOpenRows(false);

            obj.StartedCount = obj.StartedCount + 1;
            obj.InMutant = true;
            obj.ExecutionOrder = obj.StartedCount;

            obj.CurrentOperator = obj.fieldOr(mutant, 'operatorName', '');
            obj.CurrentTarget = obj.fieldOr(mutant, 'targetPath', ...
                obj.fieldOr(mutant, 'target', ''));
            obj.CurrentTransition = sprintf('%s->%s', ...
                obj.fieldOr(mutant, 'originalValue', ''), ...
                obj.fieldOr(mutant, 'mutatedValue', ''));
            obj.CurrentKey = sprintf('%s|%s|%s', ...
                obj.CurrentTarget, obj.CurrentOperator, obj.CurrentTransition);
        end

        function onMutantCompleted(obj, ~, ~, ~)
            obj.settleOpenRows(true);
            obj.clearMutant();
        end

        function onExecutionCompleted(obj, ~)
            % The run ended with rows still open. Flagged, cause unstated.
            obj.settleOpenRows(false);
            obj.clearMutant();
        end

        function onLogMessage(~, ~, ~, ~)
        end

        %% Reporting

        function T = table(obj)
            % TABLE Trace as a table, one row per executed test
            if isempty(obj.Events)
                T = table();
                return;
            end
            T = struct2table([obj.Events{:}], 'AsArray', true);
        end

        function writeCsv(obj, filename)
            % WRITECSV Persist the trace
            writetable(obj.table(), filename);
        end

        function s = summary(obj)
            % SUMMARY Row counts, including the ones that need flagging
            T = obj.table();
            s = struct('rows', 0, 'baselineRows', 0, 'mutantRows', 0, ...
                       'erroredTestRows', 0, 'didNotCompleteRows', 0, ...
                       'mutantsStarted', obj.StartedCount);
            if isempty(T)
                return;
            end
            s.rows = height(T);
            s.baselineRows = sum(T.isBaseline);
            s.mutantRows = sum(~T.isBaseline);
            s.erroredTestRows = sum(T.errored);
            s.didNotCompleteRows = sum(T.mutantDidNotComplete);
        end
    end

    methods (Access = private)
        function settleOpenRows(obj, completed)
            for k = obj.OpenRows
                obj.Events{k}.mutantCompleted = completed;
                obj.Events{k}.mutantDidNotComplete = ~completed;
            end
            obj.OpenRows = [];
        end

        function clearMutant(obj)
            obj.InMutant = false;
            obj.ExecutionOrder = 0;
            obj.CurrentKey = '';
            obj.CurrentOperator = '';
            obj.CurrentTarget = '';
            obj.CurrentTransition = '';
        end
    end

    methods (Static, Access = private)
        function v = fieldOr(s, name, default)
            % Reads a struct field or an object property. MutationEngine
            % hands out a struct today, but the observer interface is public
            % and nothing forces that to stay true.
            v = default;
            try
                if isstruct(s) && isfield(s, name)
                    v = s.(name);
                elseif isobject(s) && isprop(s, name)
                    v = s.(name);
                else
                    return;
                end
            catch
                v = default;
                return;
            end
            if isempty(v)
                v = default;
            elseif ~ischar(v)
                if isstring(v) || isnumeric(v) || islogical(v)
                    v = char(string(v));
                else
                    v = default;   % not representable as a label
                end
            end
        end
    end
end
