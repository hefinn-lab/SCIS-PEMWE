# Attribution and AI Utilisation 

[README](README.md) · [MIT licence](LICENSE) · [Citation](CITATION.cff)

## Research context and parameter provenance

The model is informed by the H2NEW PEM electrolysis benchmarking study:

M. R. Parimuha et al., “Proton exchange membrane electrolysis benchmarking: Identifying and removing sources of variation in test stations, hardware, and membrane electrode assembly fabrication,” *International Journal of Hydrogen Energy*, vol. 114, pp. 486–496, 2025. [doi:10.1016/j.ijhydene.2025.02.443](https://doi.org/10.1016/j.ijhydene.2025.02.443).

Supplement II, Fig. S2.12, provides polarisation and impedance context for the five operating current densities. The repository uses prescribed whole-cell model parameters; the analytical reference curves are not digitised experimental spectra or an independently validated fit.

The fixed capacitance of **0.4573 F** is adopted from the CV-derived capacitance shown after conditioning in Supplement II, Fig. S2.8. That measurement was used to compare anode electrochemical surface area. Its use as the capacitance of a single-RC impedance model is a modelling assumption.

The constant series source `E_0` provides the model's DC voltage offset. For the implemented linear circuit, the steady cell voltage is `E_0 + I_DC*(R_ohm + R_ct)`. The offset is not identified with thermoneutral voltage and contributes no incremental impedance while held constant.

Square-wave and switched-resistor impedance methods precede this project. Relevant examples include:

- T. Yokoshima et al., “Application of electrochemical impedance spectroscopy to ferri/ferrocyanide redox couple and lithium ion battery systems using a square wave as signal input,” *Electrochimica Acta*, vol. 180, pp. 922–928, 2015. [doi:10.1016/j.electacta.2015.08.083](https://doi.org/10.1016/j.electacta.2015.08.083).
- G. Chen et al., “Accuracy-enhanced broadband impedance of Li-ion battery measured by portable discharge paradigm,” *Journal of Energy Storage*, vol. 101, article 113828, 2024. [doi:10.1016/j.est.2024.113828](https://doi.org/10.1016/j.est.2024.113828).

This release concerns a configurable resistor-bank architecture and its simulation workflow. It does not claim invention of square-wave excitation or Fourier impedance extraction.

## AI Utilisation 

GPT-6 and Opus 5.5 assisted post-processing software development, drafting, proofreading, editing and formatting. Some individual figure icons were generated using GPT image 2.5. Final figure layouts were assembled manually in Microsoft PowerPoint. 
## Licensing scope

The [MIT licence](LICENSE) applies to original project contributions, including the simulation model, analysis software, documentation and original figure content, to the extent the author holds the rights to license them. Preserve any separate notices attached to third-party material.

MATLAB, Simulink, MathWorks block libraries and third-party publications retain their respective terms. Citation of a publication does not relicense it. Research citation is requested through [CITATION.cff](CITATION.cff); this request adds no condition to the MIT licence.
