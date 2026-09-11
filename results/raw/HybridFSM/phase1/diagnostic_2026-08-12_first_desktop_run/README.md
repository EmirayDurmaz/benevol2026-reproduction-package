# Diagnostic artifacts - first desktop baseline (12 Aug 2026)

T_full_mutation_phase = 2725.78 s, T_full_total = 2749.71 s
183 mutants, 140 killed, 43 survived, 0 errors, 76.50%, 2556 mutant-test
executions, 0 telemetry failures.

MUTATION RESULTS ARE VALID. Early exit verified intact from the trace: 2556
executions vs 4575 without early exit, and all 132 short runs end on a
failing test.

TIMING IS NOT VALID AS THE PHASE 1 DENOMINATOR. The session carried
RecordCoverage=1 (inherited from a structural-coverage evaluation run) and
2683 accumulated Test Manager result sets. Measured contributions of both:
coverage 1.26x only when it engages, result accumulation 1.05x - neither
explains the gap to the historical 623.11 s, which is itself unreliable
(inconsistent with its own baseline rate, and a sibling run of the same
config that day scored 52.5% instead of 76.50%).

Kept for diagnosis only. The clean run written to ../baseline.mat supersedes
it as the Phase 1 denominator.
