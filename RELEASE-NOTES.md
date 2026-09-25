# Release notes

## v1.0

Initial simulation release of **Switched-Current Impedance Spectroscopy for PEM Water Electrolysis**.

### Components

- `SCIS_V3.slx`: circuit model.
- `Sweep_Scheduler_V3.m`: embedded scheduler source.
- `SCIS_Post_Processing_V7.m`: extraction, plotting and result export.
- Proposed system and circuit diagrams in `figures/`.

Repository version 1.0 identifies this collection. Component version numbers remain V3 and V7.

### Reference-run results

The run covers 47 frequencies from 10 kHz to 1 Hz at each of five operating points, with a maximum solver step of 3.125 µs. Impedance is recovered using the ideal-current channel and compared with the configured analytical EEC.

| Metric | Value |
| --- | ---: |
| Finite impedance records | 235 / 235 |
| Numerical checks passed | 235 / 235 |
| Numerical and excitation checks passed | 233 / 235 |
| Mean complex relative error | 0.0107814% |
| Maximum complex relative error | 0.0236719% |
| RMS phase error | 0.00209164° |
| Maximum absolute phase error | 0.00464922° |

Statistics include all finite records, including excitation-flagged records. They quantify impedance reconstruction, not fitted-parameter error or experimental instrument accuracy.

### Known limitations

- One maximum-step configuration is reported. Solver convergence has not been established. The comparison functionality in V7 is available for further work.
- The 1 Hz records at 0.10 and 1.00 A/cm² report peak-to-peak excursions of **223.06%** and **23.00%**, respectively, exceeding the 10% criterion. These anomalies require raw-waveform inspection; they are not silently excluded or assumed to be harmless. The other 233 records span approximately 4.91–7.07%.
- The 5.12–7.00% excursions displayed in the current-detail panels apply to the 100 Hz records, not the entire sweep.
- The EEC is a prescribed linear, single-RC model. Its response does not establish small-signal electrochemical validity, realistic noise performance or agreement with independent experimental spectra. See [parameter provenance](ATTRIBUTION.md).
- No independent EEC parameter fitting, physical instrument validation or CI experiment is reported. The proposed figures do not constitute a fabrication-ready hardware release.

V7 exports full error and check tables so these distinctions remain visible when the analysis is reused.
