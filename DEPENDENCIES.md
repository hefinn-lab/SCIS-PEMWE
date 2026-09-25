# Setup and dependencies

[README](README.md) · [Release notes](RELEASE-NOTES.md)

## Environment

The reference simulation was run in **MATLAB/Simulink R2025b**. Install the block-library products required by `SCIS_V3.slx`; electrical models may require Simscape and Simscape Electrical, depending on the blocks used. Determine the model-specific requirements in MATLAB:

```matlab
products = dependencies.toolboxDependencyAnalysis('SCIS_V3.slx')
```

The [MathWorks dependency-analysis documentation](https://www.mathworks.com/help/simulink/slref/dependencies.toolboxdependencyanalysis.html) describes this check. It does not replace installing and licensing the reported products.

The post-processor uses MATLAB's Fourier quadrature, table and graphics functions. No Python environment or external FFT package is required. Montserrat is preferred for figures; the script selects an available fallback font if needed. Excel workbooks are written without launching Microsoft Excel.

## Model and scheduler

Keep `SCIS_V3.slx`, `Sweep_Scheduler_V3.m` and `SCIS_Post_Processing_V7.m` in the repository root and make that folder the MATLAB current folder.

Open the model and verify that its embedded MATLAB Function scheduler matches `Sweep_Scheduler_V3.m`. To update it, paste the complete scheduler source, including its local functions, into the existing scheduler block. Preserve the Clock input and all 18 output connections. The standalone file documents the embedded function; editing it alone does not update the model block.

The `scis_plan` section and its circuit helpers must agree between the scheduler and post-processor. Physical block parameters must also match. The default sweep uses:

| Setting | Value |
| --- | --- |
| Active area | 5 cm² |
| Current densities | 0.05, 0.10, 0.50, 1.00, 4.00 A/cm² |
| Frequencies per operating point | 47, logarithmically spaced from 10,000 to 1 Hz |
| Duty cycle | 50% |
| Initial settling per operating point | 0.5 s |
| Burst settling | At least three cycles and ten times the largest loaded RC/source-filter time constant, rounded up to whole cycles |
| Acquired cycles | 8 per frequency |
| Source-filter time constant used by scheduler | 1 ms |

The perturbation resistors are `[50 30 15 10 4 2]` mΩ; the sensing resistors are `[100 10 2]` mΩ. MOSFET on-state resistance is modelled separately as 0.85 mΩ. Current-dependent source offsets and RC values are specified in the scheduler.

## Run settings

```matlab
open_system('SCIS_V3');
info = SCIS_Post_Processing_V7;
```

In the model settings, use:

| Setting | Reference value |
| --- | --- |
| Start time | 0 s |
| Stop time | `info.stopTime` = approximately 318.104085210079 s |
| Maximum step | `3.125e-6` s |
| Minimum step | Auto |
| Relative tolerance | `1e-5` |
| Absolute tolerance | `1e-6` |

Retain the solver and physical-network settings in the released model. Record the solver choice, local-solver settings and noise-block configuration when reporting a reproduction or modified run. The post-processor neither configures those settings nor adds measurement noise.

Run the model with single simulation output enabled so its workspace logs are available in `out`. Required logs are cell voltage (`v_cell` or `V_cell`), ideal current (`I_cell_Ideal`) and switching state (`gate`). Optional logs are `I_cell_Non_Ideal`, `op_idx` and `is_EIS`. Signals must use Timeseries or Structure With Time format and cover the full acquisition windows.

```matlab
out = sim('SCIS_V3','ReturnWorkspaceOutputs','on');
result = SCIS_Post_Processing_V7(out,struct( ...
    'outputDir','SCIS_V7_publication', ...
    'runMaxStep',3.125e-6));
```

## Saved results

`SCIS_metrics.xlsx` contains overall metrics, errors by operating point and frequency band, per-point values, thresholds and metric definitions. CSV exports retain numerical values and failure reasons. Main Nyquist markers include numerical passes; additional rings mark excitation-limit failures. All finite records contribute to the reported error summaries.

To regenerate figures without loading raw simulation histories or repeating extraction:

```matlab
cached = load('SCIS_V7_publication/SCIS_results.mat','result');
result = SCIS_Post_Processing_V7(cached.result,struct( ...
    'outputDir','SCIS_V7_replot'));
```

For tables and caching without figures, supply `'makePlots',false` in the options structure. Raw logging can require substantial memory; the compact result cache is not a simulation checkpoint and cannot reconstruct the full histories.

V7 also supports paired runs through `compareTo`, using a saved `SCIS_results.mat` from the same schedule and circuit. Each run must declare its actual maximum step. This optional feature does not mean a convergence study was completed for v1.0.
