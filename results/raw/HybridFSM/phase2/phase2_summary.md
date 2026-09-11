# Phase 2A - Coverage-based reachability (HybridFSM)

Generated 2026-08-19 15:41

## What was built

A 25 x 183 matrix R(test, mutant) derived only from coverage of the
ORIGINAL, unmutated model. Kill outcomes were not consulted at any
point before the matrix existed.

- coverage context: `FSM_Model/Subsystem Reference/Chart`
- SUT context: `stateMachine/Chart`
- coverage objects: 22 transitions
- coverage replay: 14.5 s for 25 tests

## Mapping outcome

| | Mutants |
|---|---|
| resolved to exactly one object | 149 |
| ambiguous (>1 candidate) | 30 |
| unresolved (no objective / unsupported type) | 4 |

## Discrimination - union semantics (primary)

| Value | Cells | Share |
|---|---|---|
| 1 retained | 1755 | 38.4% |
| 0 eliminated | 2720 | 59.5% |
| NaN unknown | 100 | 2.2% |

Mean per mutant: 9.59 tests reached, 14.86 eliminated, 0.55 unknown (of 25).

Distinct mutant patterns: 16 (upper bound on how finely the filter can
ever distinguish mutants).

Candidate pairs handed to Phase 2B: **1855** of 4575.

## Ablation - strict semantics

Ambiguous mutants refused instead of unioned.

| Semantics | Eliminated | Unknown |
|---|---|---|
| union (primary) | 59.5% | 2.2% |
| strict (ablation) | 54.3% | 18.6% |

Union is preferred because it eliminates more while keeping the rule
for producing a 0 unchanged: a 0 still requires every candidate to
carry an objective that the test did not evaluate. It trades a weaker
claim behind each 1 - retention, not reach - for a much lower unknown
rate, and false positives cost only wasted executions.

## Post-hoc validation

Kill data used here and nowhere else, after the matrix was complete.

| | Count |
|---|---|
| killing pairs | 140 |
| classified reachable (1) | 136 |
| classified unknown (NaN) | 4 |
| classified unreachable (0) - VIOLATIONS | 0 |

No killing test was classified unreachable. The filter produced no
false negatives on this data. This does not prove the mapping
correct - it means this data failed to refute it.

## Per operator

| Operator | Mutants | Eliminated | Unknown | Mean tests reached |
|---|---|---|---|---|
| SumOperator | 4 | 0.0% | 100.0% | 0.00 |
| TransitionConditionOperator | 125 | 62.4% | 0.0% | 9.40 |
| TransitionLogicalOperator | 17 | 61.2% | 0.0% | 9.71 |
| TransitionMathOperator | 16 | 61.8% | 0.0% | 9.56 |
| TransitionNotOperator | 21 | 50.1% | 0.0% | 12.48 |

## Per test

| # | Test | Reached | Eliminated | Unknown |
|---|---|---|---|---|
| 1 | Dead-Dead | 27 | 152 | 4 |
| 2 | Dead-Regen | 27 | 152 | 4 |
| 3 | Dead-ED | 55 | 124 | 4 |
| 4 | Dead-NoCharge | 75 | 104 | 4 |
| 5 | Dead-Combined | 66 | 113 | 4 |
| 6 | NoCharge-DEAD | 75 | 104 | 4 |
| 7 | NoCharge-Regen | 75 | 104 | 4 |
| 8 | NoCharge-ED | 110 | 69 | 4 |
| 9 | NoCharge-Combined | 102 | 77 | 4 |
| 10 | NoCharge-NoCharge | 75 | 104 | 4 |
| 11 | ED-ED | 55 | 124 | 4 |
| 12 | ED-Regen | 55 | 124 | 4 |
| 13 | ED-DEAD | 62 | 117 | 4 |
| 14 | ED-NoCharge | 103 | 76 | 4 |
| 15 | ED-Combined | 108 | 71 | 4 |
| 16 | Combined-Combined | 66 | 113 | 4 |
| 17 | Combined-Regen | 66 | 113 | 4 |
| 18 | Combined-DEAD | 80 | 99 | 4 |
| 19 | Combined-ED | 101 | 78 | 4 |
| 20 | Combined-NoCharge | 88 | 91 | 4 |
| 21 | Regen-Regen | 4 | 175 | 4 |
| 22 | Regen-DEAD | 35 | 144 | 4 |
| 23 | Regen-ED | 60 | 119 | 4 |
| 24 | Regen-NoCharge | 86 | 93 | 4 |
| 25 | Regen-Combined | 99 | 80 | 4 |

