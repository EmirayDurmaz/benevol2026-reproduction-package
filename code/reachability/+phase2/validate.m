function v = validate(R, traceCsv)
% PHASE2.VALIDATE Post-hoc soundness check against known kill outcomes
%
% THE ONLY PLACE IN PHASE 2 THAT MAY READ KILL DATA, and it reads it after
% the matrix exists. Nothing it computes is returned into the matrix, the
% adapter, or the semantics - that would be training the filter on the
% answers it is meant to predict.
%
% The check is one-directional. A test that killed a mutant must have
% reached it, so:
%
%     R(t,m) == 0 for a killing pair  =>  the mapping is wrong
%
% No violations does not prove the mapping correct; it only means this data
% failed to refute it. Violations, on the other hand, are conclusive.
%
% Returns v with .nKills, .nR1, .nR0, .nNaN, .violations (table), .sound
%
% See also: phase2.buildReachability, phase2.analyze

    T = readtable(traceCsv);
    if ismember('isBaseline', T.Properties.VariableNames)
        T = T(T.isBaseline == 0, :);
    end
    kills = T(T.killedMutant == 1, :);

    v = struct();
    v.nKills = height(kills);
    v.nR1 = 0; v.nR0 = 0; v.nNaN = 0; v.nOutOfRange = 0;

    vt = table('Size', [0 4], ...
        'VariableTypes', {'double', 'string', 'double', 'double'}, ...
        'VariableNames', {'testIdx', 'testName', 'mutantIdx', 'R'});

    [nT, nM] = size(R);
    for i = 1:height(kills)
        t = kills.testIndex(i);
        m = kills.mutantExecutionOrder(i);
        if t < 1 || t > nT || m < 1 || m > nM
            v.nOutOfRange = v.nOutOfRange + 1;
            continue;
        end
        r = R(t, m);
        if r == 0
            v.nR0 = v.nR0 + 1;
            nm = "";
            if ismember('testName', kills.Properties.VariableNames)
                nm = string(kills.testName{i});
            end
            vt(end+1, :) = {t, nm, m, r}; %#ok<AGROW>
        elseif r == 1
            v.nR1 = v.nR1 + 1;
        else
            v.nNaN = v.nNaN + 1;
        end
    end

    v.violations = vt;
    v.sound = (v.nR0 == 0);
end
