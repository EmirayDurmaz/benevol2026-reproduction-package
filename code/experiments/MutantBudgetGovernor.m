classdef MutantBudgetGovernor < mutationtool.IExecutionObserver
% NOTE: Identifiers of the mutation tool have been genericized as
% 'mutationtool.*'. The experiments were executed with MUT4SLX (not
% included in this package); these scripts are provided for inspection
% and require the tool to be obtained separately to execute.
    % MUTANTBUDGETGOVERNOR Stop a run once its wall-clock budget is spent
    %
    % Implements the Random Mutant budget rule literally:
    %
    %   after a mutant completes:
    %       if elapsed >= budget, do not start another mutant
    %
    % A mutant already under test is never cut short, so a run can and will
    % overshoot its budget by up to the cost of one mutant. That overshoot is
    % real and is measured rather than hidden - a budget honoured by
    % abandoning a half-tested mutant would report a kill count that no
    % actual execution produced.
    %
    % The clock starts at onExecutionStarted, so it measures the same window
    % as T_full_mutation_phase - the quantity the budget is a fraction of.
    %
    % Termination goes through Orchestrator.requestTermination, i.e. the
    % existing cooperative stop path. Because the check happens in
    % onMutantCompleted - after the orchestrator has already recorded the
    % result - the last mutant's outcome is kept, and the next loop iteration
    % exits cleanly with the iterator reverted.
    %
    % See also: run_hybridfsm_random_mutant_phase1, mutationtool.Orchestrator

    properties (SetAccess = private)
        Budget              % Seconds
        Elapsed = NaN       % Wall clock at the moment the stop was issued
        MutantsCompleted = 0
        StopIssued = false
        StopAfterMutant = NaN
    end

    properties (Access = private)
        Orchestrator
        Timer
    end

    methods
        function obj = MutantBudgetGovernor(orchestrator, budgetSeconds)
            obj.Orchestrator = orchestrator;
            obj.Budget = budgetSeconds;
        end

        function t = elapsedNow(obj)
            if isempty(obj.Timer)
                t = 0;
            else
                t = toc(obj.Timer);
            end
        end

        function onExecutionStarted(obj, ~)
            obj.Timer = tic;
        end

        function onMutantStarted(~, ~, ~)
        end

        function onMutantCompleted(obj, ~, ~, ~)
            obj.MutantsCompleted = obj.MutantsCompleted + 1;
            if obj.StopIssued
                return;
            end
            if obj.elapsedNow() >= obj.Budget
                obj.Elapsed = obj.elapsedNow();
                obj.StopIssued = true;
                obj.StopAfterMutant = obj.MutantsCompleted;
                obj.Orchestrator.requestTermination();
            end
        end

        function onExecutionCompleted(obj, ~)
            if ~obj.StopIssued
                % Budget outlived the mutant set: the whole run fitted.
                obj.Elapsed = obj.elapsedNow();
            end
        end

        function onLogMessage(~, ~, ~, ~)
        end
    end
end
