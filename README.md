# Reproduction Package — Towards Just-In-Time Mutation Testing for Simulink Cyber-Physical System Models (BENEVOL 2026)

This package accompanies the paper. It contains the experiment, reachability
and analysis code, the seed-level and raw results behind the reported tables
and figures, the figure-generation script, and one of the subject models.

## Contents

```
models/
  HybridFSM/        PHEV torque-allocation state machine (third party, MIT)
code/
  experiments/      Baseline / Random Mutant / Coverage-Based runners,
                    environment and clean-session helpers, budget governor,
                    test-trace recorder
  reachability/     Reachability-matrix builders and the pair selector
                    (+phase2 package)
  evaluation/       Post-hoc structural-coverage evaluation scripts
  configs/          Experiment configuration files
results/
  excel/            Seed-level results per subject (one row per
                    method x budget x seed) plus a Full Baseline sheet
  raw/              Per-run .mat artifacts for HybridFSM and Cruise Control:
                    seeded mutant orders with hashes, test-level execution
                    traces, timings, and outcomes
  reachability/     Reachability matrices with provenance
figures/            Figure PDFs and the Python script that regenerates them
                    from the Excel workbooks
licenses/           Third-party licensing notices
LICENSE             GNU GPL v3.0, covering the original code in code/
```

## Subjects not included

**PID Controller.** Not distributed, because it is an industrial model. Its
seed-level numerical results are included in
`results/excel/results_PIDController.xlsx`; the model, subject-specific
scripts, and raw execution traces are not included.

**Cruise Control.** The subject is based on the MathWorks Requirements-Based
Testing Workflow Example, whose original project files are not distributed
in this package. Our Cruise Control experiment runners, configurations,
reachability artifacts, seed-level and raw results, and figures are
included. The original MathWorks project files have to be obtained
separately from the official MathWorks source.

## Obtaining the Cruise Control subject

1. Obtain the MathWorks Requirements-Based Testing Workflow Example from its
   official source
   (https://github.com/mathworks/requirements-based-testing-example, or the
   corresponding MathWorks documentation example).
2. Either place the obtained project at the default location expected by the
   package, `models/CruiseControl/`, so that
   `models/CruiseControl/Requirements_Based_Testing_Example.prj` exists, or
   set the environment variable `CRUISECONTROL_PROJECT_ROOT` to the
   directory that contains that `.prj` file:

   ```matlab
   setenv('CRUISECONTROL_PROJECT_ROOT', '/path/to/requirements-based-testing-example')
   ```

   `code/experiments/cc_env.m` resolves the subject from this variable and
   falls back to the default location when it is unset.
3. If you use a non-default location, also update the `modelPath` and
   `testFile` entries of `code/configs/config_cruisecontrol.json`, which the
   mutation tool reads directly and which name the default location
   (`../../models/CruiseControl/Models` relative to the config file, and
   `models/CruiseControl/Tests/CruiseControl_TestSuite.mldatx` relative to
   the package root).

## Dependency: the mutation tool

The experiments were conducted with **MUT4SLX**
(https://github.com/haliliceylan/MUT4SLX), which is not included in this
package. In the provided scripts its API calls appear under the genericized
namespace `mutationtool.*`. Reproducing the complete mutation-testing
workflow therefore requires MUT4SLX to be obtained and configured
separately.

Everything that does not depend on mutant generation or execution — the
reachability construction, the test--mutant pair selector, the coverage
evaluation, and all result analyses — is included here.

## Reproducing the reported numbers

- The values reported in the paper can be recomputed from
  `results/excel/*.xlsx`, which hold one row per method, budget and seed,
  plus a Full Baseline sheet per subject.
- `results/raw/` holds the per-run `.mat` artifacts behind those rows:
  seeded mutant orders, test-level execution traces, timings and outcomes,
  under `results/raw/HybridFSM/` and `results/raw/CruiseControl/`.
- The figures can be regenerated from the workbooks alone:

  ```bash
  cd figures && python3 make_worstcase_figures.py
  ```

  This requires Python 3 with pandas, openpyxl and matplotlib.
- The reachability matrices in `results/reachability/` can be reconstructed
  from the subject models with the scripts in `code/reachability/`. For
  HybridFSM this step also reads the mutant metadata in
  `results/raw/HybridFSM/phase2/stateMachine_output.json`, which is included
  in this package.

## Environment

The experiments were run with MATLAB/Simulink R2026a on macOS (Apple
Silicon). Simulink Coverage and Simulink Test are required for the
reachability and evaluation scripts.

The environment helpers `code/experiments/phase1_env.m` (HybridFSM) and
`code/experiments/cc_env.m` (Cruise Control) resolve every path from the
package root, which they derive from their own location, and follow the
directory layout of this package: `code/experiments`, `code/configs`,
`models`, and `results/raw`. Directory names are used with the exact casing
shown above, so the package also works on case-sensitive file systems.

## Licenses

Original code and scripts developed for this reproduction package are
licensed under the GNU General Public License v3.0; see the top-level
`LICENSE`. This license applies only to material developed by us unless
otherwise noted. Third-party materials retain their respective copyright
and licensing terms.

**HybridFSM.** The HybridFSM subject remains under the MIT License,
Copyright (c) 2021 Giuseppe Gallina, Ivan Enzo Gargano, Michele Mirabella,
Francesco Prignoli, Nicolò Rubbini. It is not covered by the GPL-3.0 license
of this package. The original notice is preserved in
`models/HybridFSM/LICENSE` and reproduced in `licenses/HybridFSM-MIT.txt`.
Upstream source: https://github.com/meltinglab/hybrid-controller

**Cruise Control / MathWorks.** The MathWorks Requirements-Based Testing
Workflow Example project files are not redistributed in this package. These
MathWorks materials are not covered by the GNU GPL v3.0 license of this
reproduction package and remain subject to MathWorks' applicable copyright
and usage terms.

**MUT4SLX.** The mutation tool is not included in this package and remains
available separately under its own license.

See `licenses/` for the third-party notices collected in one place.
