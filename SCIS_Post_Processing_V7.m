function result = SCIS_Post_Processing_V7(out,options)
%SCIS_POST_PROCESSING_V7 10 kHz extraction, publication tables and step comparison.
% Use the existing sweep_scheduler_V3 unchanged. No model rewiring.
%
% 1. INFO (no simulation needed):
%   info = SCIS_Post_Processing_V7;
%   % Set model StartTime=0, StopTime=info.stopTime, MinStep=auto.
% 2. PUBLICATION RUN: set model MaxStep=3.125e-6, then simulate to obtain out.
%   rFine = SCIS_Post_Processing_V7(out,struct( ...
%       'outputDir','SCIS_V7_publication','runMaxStep',3.125e-6));
%   % After successful save, clear out before running the second simulation.
% 3. COARSER CHECK: set model MaxStep=6.25e-6; start a fresh simulation at 0.
%   rCoarse = SCIS_Post_Processing_V7(out,struct( ...
%       'outputDir','SCIS_V7_coarse','runMaxStep',6.25e-6, ...
%       'makePlots',false,'compareTo', ...
%       fullfile('SCIS_V7_publication','SCIS_results.mat')));
% runMaxStep is DECLARED metadata; it does not configure or verify the solver.
% Keep solver, tolerances, noise and logging identical between simulations.
% Fine/coarse are determined by MaxStep, NOT by execution order.
%
% RECALL / REPLOT without the large raw logs or another DFT:
%   saved = load('SCIS_V7_publication/SCIS_results.mat','result');
%   rFine = SCIS_Post_Processing_V7(saved.result,struct( ...
%       'outputDir','SCIS_V7_publication','compareTo', ...
%       fullfile('SCIS_V7_coarse','SCIS_results.mat')));
% This optional call also adds the comparison sheets to the publication workbook.
% Matching V6 10 kHz caches are supported. Existing declared MaxStep metadata
% is retained when replotting; it cannot be relabelled through options.
%
% OUTPUTS in outputDir (default SCIS_V7_results):
%   SCIS_results.mat       compact spectra, tables, display envelope, examples
%   SCIS_metrics.xlsx      Headlines, Errors_by_OP, Errors_by_band, Per_point,
%                          Metric_summary, Check_limits, Definitions, Run_info,
%                          Convergence_summary, Convergence_points
%   CSV files              equivalent numeric tables including failures
%   PDF/PNG/FIG             publication figures; optional all-record diagnostic
% The MAT cache is saved before comparison, spreadsheet export and plotting.
% It is not a solver checkpoint and cannot reconstruct the full raw logs.
% Raw out is never written to this cache. Do not save the entire workspace.
%
% Nyquist_all_five is sized for a single column (8.8 cm), with 9 pt axis
% labels, 8 pt legend/ticks, enlarged inset text and a model/marker key.
% Other figures, Fourier extraction, checks, EEC and sweep are unchanged.
% NumericalPass excludes only the amplitude-limit check; Pass includes it.
% Summary statistics use ALL finite pairs, including failed-check records.
% Main impedance uses I_cell_Ideal. Shunt-derived errors remain separate.
% Two-step agreement is a sensitivity check, not an automatic convergence proof.
%
% OPTIONS: outputDir, runMaxStep, compareTo, exportXLSX (true), makePlots (true),
% makeDiagnostics (true), figureVisible ('on'), pngResolution (300), saveFIG
% (true), insetFrequency_Hz (100), insetCycles (4), plotStyle (struct).
% Existing numerical thresholds can be set on raw processing only; defaults
% are unchanged from V6. plotStyle accepts the fields in figureStyle below.
% MATLAB/Simulink execution was unavailable during authoring.

% Replot only a cache with this exact 10 kHz schedule and circuit.
if nargin>=1 && isstruct(out) && isfield(out,'plotCacheVersion')
    [Scheck,OPcheck,~,~,~]=scis_plan();
    assert(isfield(out,'schedule') && isequaln(out.schedule,Scheck) && ...
        isequaln(out.operatingPoints,OPcheck), ...
        'SCIS:ScheduleMismatch', ...
        'Cache does not match V7 / scheduler V3. Run a new 10 kHz simulation.');
    result=out;
    result.plotCacheVersion=7;
    result.options.outputDir=fullfile(pwd,'SCIS_V7_results');
    result.options=defaults(result.options,'exportXLSX',true);
    result.options.compareTo=''; % Do not reuse a stale comparison path from a cache.
    if nargin<2, options=struct; end
    allowed={'outputDir','makePlots','makeDiagnostics','figureVisible', ...
        'pngResolution','saveFIG','plotStyle','compareTo','exportXLSX'};
    keys=fieldnames(options);
    for k=1:numel(keys)
        assert(any(strcmp(keys{k},allowed)), ...
            'Replot cannot change %s. Reprocess raw out to change acquisition or checks.',keys{k});
        result.options.(keys{k})=options.(keys{k});
    end
    if ~isfolder(result.options.outputDir), mkdir(result.options.outputDir); end
    result=finishResults(result);
    if result.options.makePlots, plots(result); end
    return;
end

%% 1. Matching sweep schedule and extraction settings
[S,OP,Rohm,C,ESR]=scis_plan();
result.stopTime=S(end,6)+0.02;
result.recommendedMaxStep=1/(32*max(S(:,3)));
result.trialMaxSteps=[result.recommendedMaxStep 2*result.recommendedMaxStep];
result.frequencyRange_Hz=[min(S(:,3)) max(S(:,3))];
result.frequenciesPerOperatingPoint=size(S,1)/size(OP,1);
result.scheduleID='SCIS_10k_47pt_V3_V6'; % Unchanged schedule, compatible V6 cache.
result.analysisVersion=7;
result.schedule=S; result.operatingPoints=OP;
result.area_cm2=5;
result.provenance='Inherited linear EEC, not independently fitted NREL spectra';
if nargin==0
    fprintf('SCIS scheduler V3 / analysis V7: %.0f-%.0f Hz, %d frequencies/OP, %d total records.\n', ...
        result.frequencyRange_Hz,result.frequenciesPerOperatingPoint,size(S,1));
    fprintf('Set Start time to 0 and Stop time to %.12g s for BOTH trials.\n',result.stopTime);
    fprintf('Publication MaxStep: %.12g s; coarser-check MaxStep: %.12g s.\n',result.trialMaxSteps);
    fprintf('Both trials use fresh simulations, identical tolerances and identical logs.\n');
    fprintf('Publication MaxStep = %.12g s; MinStep auto. Compare with twice this MaxStep.\n',result.recommendedMaxStep);
    fprintf('Same Clock input, 18 scheduler outputs and existing workspace logs.\n');
    fprintf('For clean baseline, set existing measurement-noise powers to zero.\n');
    return;
end
if nargin<2, options=struct; end
options=defaults(options,'outputDir',fullfile(pwd,'SCIS_V7_results'));
options=defaults(options,'runMaxStep',NaN);
options=defaults(options,'compareTo','');
options=defaults(options,'exportXLSX',true);
assert(isnumeric(options.runMaxStep) && isscalar(options.runMaxStep) && ...
    (isnan(options.runMaxStep) || (isfinite(options.runMaxStep) && options.runMaxStep>0)), ...
    'runMaxStep must be a positive finite scalar or NaN.');
options=defaults(options,'makePlots',true);
options=defaults(options,'makeDiagnostics',true);
options=defaults(options,'figureVisible','on');
options=defaults(options,'pngResolution',300);
options=defaults(options,'saveFIG',true);
options=defaults(options,'insetFrequency_Hz',100);
options=defaults(options,'insetCycles',4);
assert(isscalar(options.insetFrequency_Hz) && options.insetFrequency_Hz>0, ...
    'insetFrequency_Hz must be a positive scalar.');
assert(isscalar(options.insetCycles) && options.insetCycles>=1 && ...
    options.insetCycles<=min(S(:,13)) && options.insetCycles==floor(options.insetCycles), ...
    'insetCycles must be an integer between 1 and the acquisition-cycle count.');
options=defaults(options,'minSamplesPerCycle',16);
options=defaults(options,'minSamplesPerTau',4);
options=defaults(options,'maxComplexError_pct',1);
options=defaults(options,'maxPhaseError_deg',0.5);
options=defaults(options,'maxHalfRecordDrift_pct',1);
options=defaults(options,'maxMeanCurrentError_pct',1);
options=defaults(options,'maxPeakToPeak_pct',10);
options=defaults(options,'maxSenseVsIdeal_pct',1);
%% 2. Logged signals (no noise is added)
V=readSignal(out,{'v_cell','V_cell'},true);
I=readSignal(out,{'I_cell_Ideal','I_cell_ideal','I_cell'},true);
G=readSignal(out,{'gate1'},true);
In=readSignal(out,{'I_cell_Non_Ideal','I_cell_nonideal'},false);
O=readSignal(out,{'op_idx'},false); E=readSignal(out,{'is_EIS'},false);
N=size(S,1); data=nan(N,20); reasons=cell(N,1); examples=cell(5,1);
Z=complex(nan(N,1)); Zsense=Z; Zref=Z; pass=false(N,1);
%% 3. Extract each coherent frequency record
for n=1:N
    s=S(n,:); op=s(1); f=s(3); a=s(5); b=s(6);
    data(n,1:4)=[op OP(op,1) f OP(op,5)]; why='';
    zref=Rohm+1/(1/OP(op,3)+1/(ESR+1/(2i*pi*f*C))); Zref(n)=zref;
    try
        [tv,v]=window(V,a,b); [ti,i]=window(I,a,b);
        gap=max(max(diff(tv)),max(diff(ti)));
        spc=1/(gap*f); perTau=s(16)/gap;
        if spc<options.minSamplesPerCycle, why=addReason(why,'insufficient samples/cycle'); end
        if perTau<options.minSamplesPerTau, why=addReason(why,'under-resolved RC transient'); end
        [vp,vm]=phasor(tv,v,f,a,b); [ip,im]=phasor(ti,i,f,a,b);
        if abs(ip)<1e-10, error('Current fundamental too small.'); end
        z=vp/ip; Z(n)=z;
        % Two independent coherent half-record estimates flag residual settling/noise.
        half=(a+b)/2;
        [tv1,v1]=window(V,a,half); [ti1,i1]=window(I,a,half);
        [tv2,v2]=window(V,half,b); [ti2,i2]=window(I,half,b);
        p1=phasor(ti1,i1,f,a,half); p2=phasor(ti2,i2,f,half,b);
        if min(abs([p1 p2]))<1e-10, error('Half-record current fundamental too small.'); end
        z1=phasor(tv1,v1,f,a,half)/p1; z2=phasor(tv2,v2,f,half,b)/p2;
        drift=100*abs(z2-z1)/abs(z);
        meanError=100*abs(im-s(12))/s(12);
        pp=100*(max(i)-min(i))/abs(im);
        ce=100*abs(z-zref)/abs(zref); pe=angle(z/zref)*180/pi;
        if ce>options.maxComplexError_pct, why=addReason(why,'complex error above limit'); end
        if abs(pe)>options.maxPhaseError_deg, why=addReason(why,'phase error above limit'); end
        if drift>options.maxHalfRecordDrift_pct, why=addReason(why,'half-record drift/noise above limit'); end
        if meanError>options.maxMeanCurrentError_pct, why=addReason(why,'mean current outside target'); end
        if pp>options.maxPeakToPeak_pct, why=addReason(why,'current excursion above limit'); end
        gateReason=checkGate(G,a,b,f,s(13),options.minSamplesPerCycle);
        if ~isempty(gateReason), why=addReason(why,gateReason); end
        if ~isempty(O.t) && ~checkDiscrete(O,a,b,op), why=addReason(why,'operating-point log mismatch'); end
        if ~isempty(E.t) && ~checkDiscrete(E,a,b,1), why=addReason(why,'acquisition flag mismatch'); end
        senseErr=NaN;
        if ~isempty(In.t)
            [tn,iv]=window(In,a,b); inp=phasor(tn,iv,f,a,b);
            if abs(inp)>1e-10
                Zsense(n)=vp/inp; senseErr=100*abs(Zsense(n)-z)/abs(z);
                if senseErr>options.maxSenseVsIdeal_pct, why=addReason(why,'sense current disagrees with ideal sensor'); end
            else
                why=addReason(why,'sense-current fundamental too small');
            end
        end
        data(n,5:20)=[im vm pp abs(ip) real(z) imag(z) real(zref) imag(zref) ...
            ce pe drift meanError spc perTau senseErr s(11)*100];
        % Retain the requested native-time waveform window for later figure revisions.
        nf=size(S,1)/5; indices=(op-1)*nf+(1:nf);
        [~,kExample]=min(abs(log(S(indices,3)/options.insetFrequency_Hz)));
        if s(2)==kExample
            [te,ie]=window(I,a,min(b,a+options.insetCycles/f));
            examples{op}=struct('time_ms',(te-a)*1000,'Iac_mA',(ie-im)*1000, ...
                'f',f,'pp',pp,'Imean',im);
        end
    catch exception
        why=addReason(why,exception.message);
    end
    pass(n)=isempty(why); reasons{n}=why;
end
names={'OP','j_Acm2','f_Hz','BankMask','MeanI_A','MeanV_V','CurrentPeakToPeak_pct', ...
 'CurrentFundamentalPeak_A','Zreal_Ohm','Zimag_Ohm','ZrefReal_Ohm','ZrefImag_Ohm', ...
 'ComplexError_pct','PhaseError_deg','HalfRecordDrift_pct','MeanCurrentError_pct', ...
 'WorstSamplesPerCycle','WorstSamplesPerTau','SenseVsIdealError_pct','PredictedPeakToPeak_pct'};
%% 4. Results, separate quality flags, and lightweight figure caches
T=array2table(data,'VariableNames',names); T.Pass=pass; T.Reason=reasons;
T.NumericalPass=false(N,1);
for n=1:N
    parts=strsplit(reasons{n},'; ');
    parts=parts(~cellfun('isempty',parts));
    parts=parts(~strcmp(parts,'current excursion above limit'));
    T.NumericalPass(n)=isempty(parts) && isfinite(T.ComplexError_pct(n));
end
T.ExcitationPass=isfinite(T.CurrentPeakToPeak_pct) & ...
    T.CurrentPeakToPeak_pct<=options.maxPeakToPeak_pct;
[td,yd]=envelope(I.t,I.y,5000);
result.displayCurrent=struct('t',td,'y',yd);
result.plotCacheVersion=7;
result.table=T; result.Z=Z; result.Zsense=Zsense; result.Zreference=Zref;
result.options=options; result.examples=examples;
result.reference=struct('Rohm',Rohm,'C',C,'ESR',ESR);
result.allNumericalChecksPassed=all(T.NumericalPass);
result.allChecksPassed=all(pass);
result.solverConvergenceVerified=false; % Report sensitivity without an automatic verdict.
if ~isfolder(options.outputDir), mkdir(options.outputDir); end
result=finishResults(result);
if options.makePlots, plots(result); end
fprintf('%d / %d records passed all checks (%d numerical passes).\n',sum(pass),N,sum(T.NumericalPass));
if any(~pass)
    warning('SCIS:Checks','Inspect SCIS_impedance.csv: failed checks are NOT silently accepted.');
end
if isfield(result,'convergenceSummary')
    fprintf('Paired changes reported; assess them against the claimed accuracy. No automatic convergence verdict.\n');
else
    fprintf('A separate step-size run is needed for paired sensitivity metrics; no convergence claim yet.\n');
end
end

function o=defaults(o,k,v)
if ~isfield(o,k), o.(k)=v; end
end
function s=readSignal(out,names,required)
s=struct('t',[],'y',[],'name',''); x=[];
for k=1:numel(names)
    try
        if isstruct(out), x=out.(names{k}); else, x=out.get(names{k}); end
        if ~isempty(x), s.name=names{k}; break; end
    catch
        x=[];
    end
end
if isempty(x)
    if required, error('Missing log: %s.',strjoin(names,' or ')); end
    return;
end
if isa(x,'timeseries'), s.t=x.Time(:); s.y=x.Data(:);
elseif isstruct(x) && isfield(x,'time'), s.t=x.time(:); s.y=x.signals.values(:);
else, error('Log %s must use Timeseries or Structure With Time format.',s.name); end
assert(numel(s.t)==numel(s.y),'Time/data length mismatch in %s.',s.name);
assert(all(isfinite(s.t)) && all(isfinite(s.y)),'Nonfinite data in %s.',s.name);
assert(all(diff(s.t)>=0),'Nonmonotonic timestamps in %s.',s.name);
% Retain last value at repeated solver timestamps (post-event value).
if any(diff(s.t)==0)
    keep=[diff(s.t)>0;true]; s.t=s.t(keep); s.y=s.y(keep);
end
end
function idx=lowerBound(t,x)
lo=1; hi=numel(t)+1;
while lo<hi
    m=floor((lo+hi)/2);
    if m<=numel(t) && t(m)<x, lo=m+1; else, hi=m; end
end
idx=lo;
end
function [t,y]=window(s,a,b)
assert(numel(s.t)>=2 && s.t(1)<=a && s.t(end)>=b,'Incomplete acquisition window.');
i=max(1,lowerBound(s.t,a)-1); j=min(numel(s.t),lowerBound(s.t,b));
t=s.t(i:j); y=s.y(i:j);
assert(numel(t)>=3,'Too few native samples.');
ya=interp1(t,y,a,'linear'); yb=interp1(t,y,b,'linear');
inside=t>a & t<b;
t=[a;t(inside);b]; y=[ya;y(inside);yb];
end
function [p,m]=phasor(t,y,f,a,b)
% Trapezoidal time weights account for nonuniform solver sampling.
% Process in chunks to bound temporary complex-array memory.
dt=diff(t); m=sum(dt.*(y(1:end-1)+y(2:end))*.5)/(b-a);
p=0; chunk=200000;
for k=1:chunk:numel(t)-1
    e=min(numel(t)-1,k+chunk-1); q=k:e;
    r0=exp(-2i*pi*f*(t(q)-a)); r1=exp(-2i*pi*f*(t(q+1)-a));
    p=p+sum(dt(q).*((y(q)-m).*r0+(y(q+1)-m).*r1))*.5;
end
p=2*p/(b-a);
end
function r=checkGate(s,a,b,f,cycles,minSPC)
i=lowerBound(s.t,a); j=lowerBound(s.t,b)-1; r='';
if j-i<3, r='missing gate samples'; return; end
t=s.t(i:j); g=s.y(i:j)>.5;
if max(diff(t))*f>1/minSPC, r='under-resolved gate log'; return; end
edges=find(diff(g)~=0)+1;
if numel(edges)<2*cycles-1 || numel(edges)>2*cycles
    r='missing/extra gate transitions'; return;
end
if numel(edges)>1
    tolerance=2*max(diff(t))+1e-10;
    if max(abs(diff(t(edges))-.5/f))>tolerance, r='gate periods disagree with schedule'; end
end
end
function yes=checkDiscrete(s,a,b,target)
% Interior only: exclude solver boundary-order ambiguity.
i=lowerBound(s.t,a+1e-8*(b-a)); j=lowerBound(s.t,b-1e-8*(b-a))-1;
yes=j>=i && all(abs(s.y(i:j)-target)<.1);
end
function r=addReason(r,s)
if isempty(r), r=s; else, r=[r '; ' s]; end
end
function r=reportErrors(r)
% Include ALL finite error pairs, including failed numerical records.
% Never report only accepted points as if they represented the whole sweep.
T=r.table; nOP=size(r.operatingPoints,1);
fprintf('\nOutput folder: %s\n',r.options.outputDir);
if isfield(r.options,'runMaxStep') && isfinite(r.options.runMaxStep)
    fprintf('Declared solver MaxStep: %.12g s (metadata supplied by caller).\n',r.options.runMaxStep);
end
allRows=nan(nOP,11); bandRows=zeros(0,11);
bounds=[min(T.f_Hz),1000,10000,max(T.f_Hz)];
bounds=unique(bounds(bounds>=min(T.f_Hz) & bounds<=max(T.f_Hz)));
for op=1:nOP
    q=T.OP==op;
    allRows(op,:)=errorRow(T,q,r.operatingPoints(op,1));
    for k=1:numel(bounds)-1
        if k==1, inside=T.f_Hz>=bounds(k); else, inside=T.f_Hz>bounds(k); end
        inside=inside & T.f_Hz<=bounds(k+1);
        bandRows(end+1,:)=errorRow(T,q & inside,r.operatingPoints(op,1)); %#ok<AGROW>
    end
end
names={'j_Acm2','MinFrequency_Hz','MaxFrequency_Hz','Records','FinitePairs', ...
    'NumericalPass','MeanComplex_pct','MaxComplex_pct','RMSPhase_deg', ...
    'MaxAbsPhase_deg','AcceptedPrefixThrough_Hz'};
r.errorSummaryAll=array2table(allRows,'VariableNames',names);
r.errorSummaryBands=array2table(bandRows,'VariableNames',names);
writetable(r.errorSummaryAll,fullfile(r.options.outputDir,'SCIS_error_summary_all.csv'));
writetable(r.errorSummaryBands,fullfile(r.options.outputDir,'SCIS_error_summary_bands.csv'));
fprintf('\nERROR SUMMARY: ALL RECORDS (configured EEC reference; ideal-current channel)\n');
printErrorTable(r.errorSummaryAll);
fprintf('\nERROR SUMMARY BY FREQUENCY BAND (actual sampled endpoints shown)\n');
printErrorTable(r.errorSummaryBands);
if any(~T.Pass)
    fprintf('\nFAILED CHECKS (all reasons, including excitation-only failures)\n');
    disp(T(~T.Pass,{'j_Acm2','f_Hz','NumericalPass','ExcitationPass','Reason'}));
else
    fprintf('\nAll %d records passed numerical AND excitation checks.\n',height(T));
end
fprintf(['\nComplex error = 100*abs(Z-Zref)/abs(Zref); phase error = angle(Z/Zref) in degrees.\n' ...
    'Means/maxima include every finite pair, including numerical failures; no pass-only filtering.\n' ...
    'OK is the numerical-check count, not a solver-convergence result.\n' ...
    'CSV also records AcceptedPrefixThrough_Hz: consecutive numerical passes from the lowest\n' ...
    'frequency of each row, stopping at the first failure (NaN if the first point fails).\n' ...
    'A low error on a 0-600%% plot alone does not establish an accurate frequency range.\n\n']);
end


function r=finishResults(r)
% Extraction is expensive; secure a compact cache before optional operations.
r.analysisVersion=7; r.plotCacheVersion=7;
r.trialMaxSteps=[r.recommendedMaxStep 2*r.recommendedMaxStep];
r.options=defaults(r.options,'exportXLSX',true);
r.options=defaults(r.options,'compareTo','');
r.options=defaults(r.options,'runMaxStep',NaN);
r=clearComparison(r);
cache=fullfile(r.options.outputDir,'SCIS_results.mat');
if ~isempty(r.options.compareTo) && isfile(r.options.compareTo) && isfile(cache)
    [~,a]=fileattrib(r.options.compareTo); [~,b]=fileattrib(cache);
    assert(~strcmp(a.Name,b.Name),'SCIS:SameCache', ...
        'Use separate output folders: compareTo must not be the cache being overwritten.');
end
r=pointMetrics(r);
result=r; save(cache,'result');
fprintf('\nCompact extraction cache saved: %s\n',cache);
r=reportErrors(r);
r=publicationMetrics(r);
try
    r=compareRuns(r);
catch exception
    r=clearComparison(r);
    r.comparisonStatus=['FAILED: ' exception.message];
    warning('SCIS:Comparison','Comparison failed; current-run extraction is saved. %s',exception.message);
end
writetable(r.table,fullfile(r.options.outputDir,'SCIS_impedance.csv'));
writetable(r.headlines,fullfile(r.options.outputDir,'SCIS_headlines.csv'));
writetable(r.metricSummary,fullfile(r.options.outputDir,'SCIS_metric_summary.csv'));
writetable(r.checkLimits,fullfile(r.options.outputDir,'SCIS_check_limits.csv'));
% Always replace comparison CSVs: an old comparison must not survive a replot.
if isfield(r,'convergencePairs')
    writetable(r.convergencePairs,fullfile(r.options.outputDir,'SCIS_convergence_pairs.csv'));
    writetable(r.convergenceSummary,fullfile(r.options.outputDir,'SCIS_convergence_summary.csv'));
else
    status=table({r.comparisonStatus},'VariableNames',{'Status'});
    writetable(status,fullfile(r.options.outputDir,'SCIS_convergence_pairs.csv'));
    writetable(status,fullfile(r.options.outputDir,'SCIS_convergence_summary.csv'));
end
result=r; save(cache,'result'); % Tables survive even if workbook/graphics fail.
r.workbookWritten=false;
if r.options.exportXLSX
    r.workbookWritten=writeWorkbook(r);
end
result=r; save(cache,'result');
fprintf('Saved compact cache; raw histories are not included.\n');
end

function r=pointMetrics(r)
% Component errors are absolute-unit differences, avoiding division by Re/Im~0.
z=r.Z(:); zr=r.Zreference(:); zs=r.Zsense(:);
T=r.table;
T.RealError_Ohm=real(z-zr); T.ImagError_Ohm=imag(z-zr);
T.AbsImpedanceError_Ohm=abs(z-zr);
T.MagnitudeError_pct=100*(abs(z)-abs(zr))./abs(zr);
T.SenseZreal_Ohm=real(zs); T.SenseZimag_Ohm=imag(zs);
T.SenseReferenceComplexError_pct=100*abs(zs-zr)./abs(zr);
T.SenseReferencePhaseError_deg=angle(zs./zr)*180/pi;
T.FiniteIdealPair=isfinite(real(z)) & isfinite(imag(z)) & ...
    isfinite(real(zr)) & isfinite(imag(zr)) & abs(zr)>0;
T.FiniteSensePair=isfinite(real(zs)) & isfinite(imag(zs)) & ...
    isfinite(real(zr)) & isfinite(imag(zr)) & abs(zr)>0;
r.table=T;
end

function r=publicationMetrics(r)
T=r.table;
row=errorRow(T,true(height(T),1),NaN);
% Across all OPs, accepted bandwidth must be supported by EVERY OP.
prefix=r.errorSummaryAll.AcceptedPrefixThrough_Hz;
if any(~isfinite(prefix)), row(11)=NaN; else, row(11)=min(prefix); end
r.headlines=array2table(row(2:end),'VariableNames', ...
    r.errorSummaryAll.Properties.VariableNames(2:end));
r.headlines.NumericalFailures=sum(~T.NumericalPass);
r.headlines.AllChecksPass=sum(T.Pass);
r.headlines.ExcitationFailures=sum(~T.ExcitationPass);
q=isfinite(T.ComplexError_pct) & isfinite(T.PhaseError_deg);
if any(q), r.headlines.MeanAbsPhase_deg=mean(abs(T.PhaseError_deg(q)));
else, r.headlines.MeanAbsPhase_deg=NaN; end
fprintf('\nPUBLICATION HEADLINES: all OPs, all finite reference pairs\n');
disp(r.headlines);
fields={'ComplexError_pct','PhaseError_deg','MagnitudeError_pct', ...
    'RealError_Ohm','ImagError_Ohm','AbsImpedanceError_Ohm', ...
    'HalfRecordDrift_pct','MeanCurrentError_pct','SenseVsIdealError_pct', ...
    'SenseReferenceComplexError_pct','SenseReferencePhaseError_deg', ...
    'CurrentPeakToPeak_pct'};
units={'%','deg','%','Ohm','Ohm','Ohm','%','%','%','%','deg','%'};
count=(size(r.operatingPoints,1)+1)*numel(fields);
scope=cell(count,1); metric=scope; unit=scope; values=nan(count,8); k=0;
for op=0:size(r.operatingPoints,1)
    if op==0, mask=true(height(T),1); label='All OPs'; j=NaN;
    else, mask=T.OP==op; j=r.operatingPoints(op,1); label=sprintf('OP %d',op); end
    for m=1:numel(fields)
        k=k+1; scope{k}=label; metric{k}=fields{m}; unit{k}=units{m};
        x=T.(fields{m})(mask); good=isfinite(x); x=x(good);
        values(k,1:4)=[j,sum(mask),sum(good),sum(~good)];
        if ~isempty(x), values(k,5:8)=[mean(x),mean(abs(x)),sqrt(mean(x.^2)),max(abs(x))]; end
    end
end
r.metricSummary=[table(scope,metric,unit,'VariableNames',{'Scope','Metric','Unit'}), ...
    array2table(values,'VariableNames',{'j_Acm2','Records','FiniteValues', ...
    'MissingOrNonfinite','MeanSigned','MeanAbsolute','RMS','MaxAbsolute'})];
keys={'minSamplesPerCycle';'minSamplesPerTau';'maxComplexError_pct'; ...
    'maxPhaseError_deg';'maxHalfRecordDrift_pct';'maxMeanCurrentError_pct'; ...
    'maxPeakToPeak_pct';'maxSenseVsIdeal_pct'};
limit=zeros(numel(keys),1);
for k=1:numel(keys), limit(k)=r.options.(keys{k}); end
comparison={'>=';'>=';'<=';'abs <= ';'<=';'<=';'<=';'<='};
unit={'samples/cycle';'samples/tau';'%';'deg';'%';'%';'%';'%'};
r.checkLimits=table(keys,limit,comparison,unit, ...
    'VariableNames',{'Option','Limit','PassCondition','Unit'});
end

function r=clearComparison(r)
keys={'convergencePairs','convergenceSummary','comparisonFineMaxStep_s', ...
    'comparisonCoarseMaxStep_s','comparisonStepRatio'};
for k=1:numel(keys), if isfield(r,keys{k}), r=rmfield(r,keys{k}); end, end
r.solverConvergenceVerified=false;
r.comparisonStatus='Not requested';
end

function r=compareRuns(r)
% Order-independent: smaller declared MaxStep is always the fine result.
if isempty(r.options.compareTo), return; end
filename=r.options.compareTo;
assert((ischar(filename) || (isstring(filename) && isscalar(filename))) && ...
    isfile(filename),'compareTo must name an existing SCIS_results.mat cache.');
previous=load(filename,'result');
assert(isfield(previous,'result'),'Comparison MAT must contain variable result.');
p=previous.result;
assert(isfield(p,'schedule') && isequaln(p.schedule,r.schedule) && ...
    isequaln(p.operatingPoints,r.operatingPoints) && isequaln(p.reference,r.reference), ...
    'SCIS:ComparisonMismatch','Comparison requires the same sweep and circuit.');
assert(isequaln(p.table.OP,r.table.OP) && isequaln(p.table.f_Hz,r.table.f_Hz), ...
    'Comparison records must have identical operating-point/frequency keys.');
assert(isfield(p.options,'runMaxStep') && isscalar(p.options.runMaxStep) && ...
    isfinite(p.options.runMaxStep) && p.options.runMaxStep>0 && ...
    isfinite(r.options.runMaxStep) && r.options.runMaxStep>0, ...
    'Both runs must declare positive runMaxStep values when first processed.');
assert(p.options.runMaxStep~=r.options.runMaxStep, ...
    'Two distinct declared MaxStep values are required for a step-size comparison.');
if r.options.runMaxStep<p.options.runMaxStep, fine=r; coarse=p;
else, fine=p; coarse=r; end
r.comparisonFineMaxStep_s=fine.options.runMaxStep;
r.comparisonCoarseMaxStep_s=coarse.options.runMaxStep;
r.comparisonStepRatio=coarse.options.runMaxStep/fine.options.runMaxStep;
fprintf('\nPAIRED STEP COMPARISON: coarse %.12g s; fine %.12g s (ratio %.6g)\n', ...
    r.comparisonCoarseMaxStep_s,r.comparisonFineMaxStep_s,r.comparisonStepRatio);
zf=fine.Z(:); zc=coarse.Z(:);
assert(numel(zf)==height(r.table) && numel(zc)==numel(zf),'Z array length mismatch.');
finite=isfinite(real(zf)) & isfinite(imag(zf)) & isfinite(real(zc)) & ...
    isfinite(imag(zc)) & abs(zf)>0 & abs(zc)>0;
dz=nan(size(zf)); dp=dz; dm=dz;
dz(finite)=100*abs(zf(finite)-zc(finite))./abs(zf(finite));
dp(finite)=angle(zf(finite)./zc(finite))*180/pi;
dm(finite)=100*(abs(zf(finite))-abs(zc(finite)))./abs(zf(finite));
P=r.table(:,{'OP','j_Acm2','f_Hz'});
P.CoarseMaxStep_s=repmat(r.comparisonCoarseMaxStep_s,height(P),1);
P.FineMaxStep_s=repmat(r.comparisonFineMaxStep_s,height(P),1);
P.CoarseZreal_Ohm=real(zc); P.CoarseZimag_Ohm=imag(zc);
P.FineZreal_Ohm=real(zf); P.FineZimag_Ohm=imag(zf);
P.ComplexChange_pct=dz; P.PhaseChange_deg=dp; P.MagnitudeChange_pct=dm;
P.RealChange_Ohm=real(zf-zc); P.ImagChange_Ohm=imag(zf-zc);
P.FinitePair=finite;
P.CoarseNumericalPass=coarse.table.NumericalPass;
P.FineNumericalPass=fine.table.NumericalPass;
P.BothNumericalPass=P.CoarseNumericalPass & P.FineNumericalPass;
P.CoarseAllChecksPass=coarse.table.Pass; P.FineAllChecksPass=fine.table.Pass;
P.BothAllChecksPass=P.CoarseAllChecksPass & P.FineAllChecksPass;
P.CoarseReason=coarse.table.Reason; P.FineReason=fine.table.Reason;
rows=nan(size(r.operatingPoints,1)+1,11); scope=cell(size(rows,1),1);
for op=0:size(r.operatingPoints,1)
    if op==0, q=true(height(P),1); j=NaN; scope{op+1}='All OPs';
    else, q=P.OP==op; j=r.operatingPoints(op,1); scope{op+1}=sprintf('OP %d',op); end
    good=q & finite;
    rows(op+1,1:7)=[j,sum(q),sum(good),sum(q & ~finite), ...
        sum(q & P.BothNumericalPass),sum(q & P.BothAllChecksPass),sum(q & ~P.BothNumericalPass)];
    if any(good)
        rows(op+1,8:11)=[mean(dz(good)),max(dz(good)), ...
            sqrt(mean(dp(good).^2)),max(abs(dp(good)))];
    end
end
names={'j_Acm2','Records','FinitePairs','MissingOrNonfinitePairs', ...
    'BothNumericalPass','BothAllChecksPass','EitherNumericalFailure', ...
    'MeanComplexChange_pct','MaxComplexChange_pct','RMSPhaseChange_deg','MaxAbsPhaseChange_deg'};
r.convergencePairs=P;
r.convergenceSummary=[table(scope,'VariableNames',{'Scope'}),array2table(rows,'VariableNames',names)];
r.comparisonStatus='Available: step sensitivity reported; no automatic convergence verdict';
disp(r.convergenceSummary);
fprintf(['dZ = 100*abs(Z_fine-Z_coarse)/abs(Z_fine); dPh = angle(Z_fine/Z_coarse) in degrees.\n' ...
    'ALL finite pairs included, including failed records; comparison uses ideal-current Z.\n' ...
    'Declared MaxStep is metadata. Solver tolerances, noise and logging must match.\n' ...
    'This tests sensitivity between these two steps; it does not test further refinement.\n']);
end

function ok=writeWorkbook(r)
% MATLAB native XLSX writer; no Excel automation. Build then replace atomically.
filename=fullfile(r.options.outputDir,'SCIS_metrics.xlsx');
tmp=[tempname(r.options.outputDir) '.xlsx']; ok=false;
try
    notes={ ...
        'Field','Value'; ...
        'Analysis','SCIS Post Processing V7'; ...
        'Schedule',r.scheduleID; ...
        'Frequency range / Hz',sprintf('%.12g to %.12g',r.frequencyRange_Hz); ...
        'Stop time / s',r.stopTime; ...
        'Declared MaxStep / s',r.options.runMaxStep; ...
        'MaxStep provenance','Supplied by caller; not read from or imposed on the solver'; ...
        'Reference',r.provenance; ...
        'Main current channel','I_cell_Ideal (sense-derived channel reported separately)'; ...
        'Comparison status',r.comparisonStatus; ...
        'Comparison cache',char(r.options.compareTo); ...
        'Aggregation','Unweighted arithmetic over finite values, including failed checks'; ...
        'Percent convention','Numeric percent: 0.05 means 0.05%, not 5%'; ...
        'Missing values','NaN exported as blank cells; never substitute zero'; ...
        'Cache','Compact spectra and figure data only; not full logs or a solver checkpoint'; ...
        'Convergence','No automatic solver-convergence verdict; assess accuracy and flags'; ...
        'Graphics','Publication figures should use the 3.125e-6 result'; ...
        'Checks','Thresholds below are unchanged from V6; gate/window/flag checks also apply'};
    if isfield(r,'convergenceSummary')
        notes(end+1,:)={'Comparison fine MaxStep / s',r.comparisonFineMaxStep_s};
        notes(end+1,:)={'Comparison coarse MaxStep / s',r.comparisonCoarseMaxStep_s};
        notes(end+1,:)={'Comparison step ratio',r.comparisonStepRatio};
    end
    writecell(notes,tmp,'Sheet','Run_info','UseExcel',false);
    writetable(r.headlines,tmp,'Sheet','Headlines','UseExcel',false);
    writetable(r.errorSummaryAll,tmp,'Sheet','Errors_by_OP','UseExcel',false);
    writetable(r.errorSummaryBands,tmp,'Sheet','Errors_by_band','UseExcel',false);
    writetable(r.table,tmp,'Sheet','Per_point','UseExcel',false);
    writetable(r.metricSummary,tmp,'Sheet','Metric_summary','UseExcel',false);
    writetable(r.checkLimits,tmp,'Sheet','Check_limits','UseExcel',false);
    definitions={ ...
        'Metric / field','Definition / interpretation'; ...
        'Z','Cell-voltage fundamental / ideal-current fundamental'; ...
        'Zreference','Configured EEC at the same OP and frequency'; ...
        'ComplexError_pct','100*abs(Z-Zreference)/abs(Zreference), nonnegative'; ...
        'PhaseError_deg','angle(Z/Zreference)*180/pi, signed'; ...
        'MagnitudeError_pct','100*(abs(Z)-abs(Zreference))/abs(Zreference), signed'; ...
        'RealError_Ohm / ImagError_Ohm','real(Z-Zreference) / imag(Z-Zreference), signed Ohm'; ...
        'AbsImpedanceError_Ohm','abs(Z-Zreference), nonnegative Ohm'; ...
        'HalfRecordDrift_pct','100*abs(Z_secondHalf-Z_firstHalf)/abs(Z_fullRecord)'; ...
        'MeanCurrentError_pct','100*abs(meanI-targetI)/targetI'; ...
        'CurrentPeakToPeak_pct','100*(max(I)-min(I))/abs(meanI); excursion, not reference error'; ...
        'CurrentFundamentalPeak_A','Peak amplitude of the current fundamental, not RMS'; ...
        'PredictedPeakToPeak_pct','Configured periodic-circuit prediction, not recovered data'; ...
        'WorstSamplesPerCycle','1/(largest native V/I sample gap * frequency)'; ...
        'WorstSamplesPerTau','Fastest configured loaded RC time constant / largest sample gap'; ...
        'SenseVsIdealError_pct','100*abs(Zsense-Z)/abs(Z); optional sense-current channel'; ...
        'SenseReferenceComplexError_pct','100*abs(Zsense-Zreference)/abs(Zreference)'; ...
        'SenseReferencePhaseError_deg','angle(Zsense/Zreference)*180/pi, signed'; ...
        'NumericalPass','All original checks other than the peak-to-peak amplitude limit'; ...
        'ExcitationPass','Finite peak-to-peak excursion within its configured limit'; ...
        'Pass','All original extraction, numerical, sensing and excitation checks'; ...
        'Reason','Every recorded failure reason; blank means no failure recorded'; ...
        'FiniteIdealPair / FiniteSensePair','Finite complex impedance/reference with nonzero reference'; ...
        'FinitePairs (error summaries)','Both complex error and phase error finite'; ...
        'MeanComplex_pct / MaxComplex_pct','Mean / maximum ComplexError_pct over all finite pairs'; ...
        'RMSPhase_deg','sqrt(mean(PhaseError_deg.^2)) over all finite pairs'; ...
        'MaxAbsPhase_deg / MeanAbsPhase_deg','Maximum / mean absolute phase error'; ...
        'AcceptedPrefixThrough_Hz','Contiguous numerical passes starting at lowest frequency in group'; ...
        'Headlines accepted prefix','Minimum OP prefix; blank if any OP fails its lowest frequency'; ...
        'Metric_summary','Each metric uses its own finite-value count; no pass-only filtering'; ...
        'MeanSigned / MeanAbsolute / RMS / MaxAbsolute','mean(x), mean(abs(x)), sqrt(mean(x.^2)), max(abs(x))'; ...
        'ComplexChange_pct','100*abs(Z_fine-Z_coarse)/abs(Z_fine), step sensitivity'; ...
        'PhaseChange_deg','angle(Z_fine/Z_coarse)*180/pi, signed'; ...
        'MagnitudeChange_pct','100*(abs(Z_fine)-abs(Z_coarse))/abs(Z_fine), signed'; ...
        'RealChange_Ohm / ImagChange_Ohm','real(Z_fine-Z_coarse) / imag(Z_fine-Z_coarse)'; ...
        'Fine / coarse','Smaller / larger declared solver MaxStep, independent of run order'; ...
        'BothNumericalPass / BothAllChecksPass','Both simulations pass their respective checks'; ...
        'Nyquist markers','NumericalPass only; rings additionally indicate excitation failures'};
    writecell(definitions,tmp,'Sheet','Definitions','UseExcel',false);
    if isfield(r,'convergenceSummary')
        writetable(r.convergenceSummary,tmp,'Sheet','Convergence_summary','UseExcel',false);
        writetable(r.convergencePairs,tmp,'Sheet','Convergence_points','UseExcel',false);
    else
        status={'Status';r.comparisonStatus};
        writecell(status,tmp,'Sheet','Convergence_summary','UseExcel',false);
        writecell(status,tmp,'Sheet','Convergence_points','UseExcel',false);
    end
    [moved,message]=movefile(tmp,filename,'f');
    assert(moved,'SCIS:WorkbookMove','%s',message);
    ok=true; fprintf('Publication metrics workbook: %s\n',filename);
catch exception
    if isfile(tmp), delete(tmp); end
    warning('SCIS:Workbook', ...
        'XLSX export failed (%s). Current MAT and CSVs are saved. Any existing XLSX may be stale.', ...
        exception.message);
end
end

function row=errorRow(T,q,j)
f=T.f_Hz(q); ce=T.ComplexError_pct(q); pe=T.PhaseError_deg(q);
pass=T.NumericalPass(q); valid=isfinite(ce) & isfinite(pe);
row=[j NaN NaN sum(q) sum(valid) sum(pass) NaN NaN NaN NaN NaN];
if isempty(f), return; end
row(2:3)=[min(f) max(f)];
if any(valid)
    row(7:10)=[mean(ce(valid)),max(ce(valid)),sqrt(mean(pe(valid).^2)),max(abs(pe(valid)))];
end
[f,order]=sort(f); pass=pass(order); firstFailure=find(~pass,1,'first');
if isempty(firstFailure), row(11)=f(end);
elseif firstFailure>1, row(11)=f(firstFailure-1); end
end

function printErrorTable(T)
fprintf('%7s %10s %10s %5s %6s %5s %11s %11s %11s %11s\n', ...
    'j','fmin/Hz','fmax/Hz','N','Finite','OK','Mean |eZ|%','Max |eZ|%','RMS ePh/deg','Max|ePh|deg');
for k=1:height(T)
    fprintf('%7.3g %10.4g %10.4g %5d %6d %5d %11.5g %11.5g %11.5g %11.5g\n', ...
        T.j_Acm2(k),T.MinFrequency_Hz(k),T.MaxFrequency_Hz(k),T.Records(k), ...
        T.FinitePairs(k),T.NumericalPass(k),T.MeanComplex_pct(k),T.MaxComplex_pct(k), ...
        T.RMSPhase_deg(k),T.MaxAbsPhase_deg(k));
end
end

function style = figureStyle(options)
% Typography and stroke weights follow process_SIMC_vs_iSIMC_V22_STEP_CHANGE.
[style.font,style.titleFont,style.titleWeight] = resolveFont();
style.tick = 12.5; style.label = 12.5; style.panel = 12.5;
style.heading = 14; style.legend = 11; style.annotation = 10.5;
style.inset = 10; style.trace = 1.75; style.detail = 1.35;
style.axes = 0.75; style.marker = 5;
style.width_cm = 27.5;
style.nyquistWidth_cm = 8.8; style.nyquistHeight_cm = 9.0;
style.nyquistLabel = 9; style.nyquistTick = 8; style.nyquistLegend = 8;
style.nyquistInset = 7; style.nyquistHeading = 9;
style.nyquistMarker = 3; style.nyquistTrace = 1.0;
% Five identities are preserved in every figure; gold is darkened for white.
style.colours = [.82 .30 .39; .30 .18 1; .67 .49 .06; .05 .47 .22; .08 .53 .73];
style.markers = {'o','d','s','v','^'};
if isfield(options,'plotStyle')
    keys = fieldnames(options.plotStyle);
    for k = 1:numel(keys)
        assert(isfield(style,keys{k}),'Unknown plotStyle field: %s',keys{k});
        style.(keys{k}) = options.plotStyle.(keys{k});
    end
end
end

function plots(r)
% Plot only cached/display data. No resampling or filtering enters the DFT.
st = figureStyle(r.options);
fprintf('Figure body font: %s; title font: %s.\n',st.font,st.titleFont);
fprintf('Nyquist main: %d/%d numerical passes; %d excluded. See diagnostic and CSV.\n', ...
    sum(r.table.NumericalPass),height(r.table),sum(~r.table.NumericalPass));
plotNyquist(r,st);
plotCurrent(r,st);
plotErrors(r,st);
if r.options.makeDiagnostics
    plotNyquistDiagnostic(r,st);
end
end

function plotNyquist(r,st)
% Physical single-column canvas: fonts are specified at the final print size.
st.width_cm=st.nyquistWidth_cm;
st.label=st.nyquistLabel; st.tick=st.nyquistTick;
st.legend=st.nyquistLegend; st.inset=st.nyquistInset;
st.heading=st.nyquistHeading; st.marker=st.nyquistMarker;
st.trace=st.nyquistTrace; st.detail=st.nyquistTrace; st.axes=.6;
scale=1000*r.area_cm2;
fig=newFigure(r,st,st.nyquistHeight_cm,'SCIS: Nyquist');
figureHeading(fig,{'Nyquist overlay at','five current densities'},st,[.06 .925 .92 .07]);
ax=newAxes(fig,[.17 .14 .80 .53],st,st.tick);
allReference=[]; h=gobjects(7,1); labels=cell(7,1);
for op=1:5
    z=referenceCurve(r,op)*scale;
    allReference=[allReference z]; %#ok<AGROW>
    h(op)=plot(ax,real(z),-imag(z),'Color',st.colours(op,:),'LineWidth',st.trace);
    labels{op}=densityLabel(r,op);
    recoveredMarkers(ax,r,op,scale,st);
end
xlabel(ax,'Re(Z) (m\Omega cm^2)','FontSize',st.label);
ylabel(ax,'-Im(Z) (m\Omega cm^2)','FontSize',st.label);
referenceLimits(ax,allReference); daspect(ax,[1 1 1]);
% Explicit handles keep the density key and method key distinct and stable.
h(6)=plot(ax,NaN,NaN,'k-','LineWidth',st.trace);
h(7)=plot(ax,NaN,NaN,'ko','LineStyle','none','MarkerFaceColor','w', ...
    'MarkerSize',st.marker,'LineWidth',.8);
labels{6}='EEC model (line)'; labels{7}='Recovered (points)';
lg=legend(ax,h,labels,'NumColumns',2); styleLegend(lg,st);
lg.ItemTokenSize=[12 9]; lg.Units='normalized';
% Reserve space above the data instead of covering arcs with the larger key.
lg.Position=[.13 .70 .84 .20];
ax.Position=[.17 .14 .80 .53];
drawnow;
p=equalPlotBox(ax);
rel=[.535 .17 .43 .34];
zoomPosition=[p(1)+rel(1)*p(3),p(2)+rel(2)*p(4),rel(3)*p(3),rel(4)*p(4)];
zoom=newAxes(fig,zoomPosition,st,st.inset);
zsmall=[];
for op=3:5
    z=referenceCurve(r,op)*scale; zsmall=[zsmall z]; %#ok<AGROW>
    plot(zoom,real(z),-imag(z),'Color',st.colours(op,:),'LineWidth',st.detail);
    recoveredMarkers(zoom,r,op,scale,st);
end
referenceLimits(zoom,zsmall); daspect(zoom,[1 1 1]);
% Two labelled ticks per direction keep the larger inset text legible.
zoom.XTick=[120 150]; zoom.YTick=[0 20];
xlabel(zoom,'Re(Z) (m\Omega cm^2)','FontSize',st.inset);
ylabel(zoom,'-Im(Z) (m\Omega cm^2)','FontSize',st.inset);
savePlot(fig,r.options,'Nyquist_all_five');
end

function p=equalPlotBox(ax)
% Convert the visible equal-aspect plot rectangle to normalized coordinates.
% Axes.Position may include unused margins imposed by daspect([1 1 1]).
oldUnits=ax.Units; ax.Units='pixels'; px=ax.Position; ax.Units='normalized';
p=ax.Position; ax.Units=oldUnits;
ratio=diff(ax.XLim)/diff(ax.YLim);
if px(3)/px(4)>ratio
    fraction=ratio*px(4)/px(3);
    p(1)=p(1)+p(3)*(1-fraction)/2; p(3)=p(3)*fraction;
else
    fraction=px(3)/(ratio*px(4));
    p(2)=p(2)+p(4)*(1-fraction)/2; p(4)=p(4)*fraction;
end
end

function recoveredMarkers(ax,r,op,scale,st)
T = r.table;
q = T.OP==op & T.NumericalPass & isfinite(real(r.Z)) & isfinite(imag(r.Z));
plot(ax,real(r.Z(q))*scale,-imag(r.Z(q))*scale, ...
    'LineStyle','none','Marker',st.markers{op},'MarkerSize',st.marker, ...
    'Color',st.colours(op,:),'MarkerFaceColor','w','LineWidth',1, ...
    'HandleVisibility','off');
q = q & ~T.ExcitationPass;
plot(ax,real(r.Z(q))*scale,-imag(r.Z(q))*scale,'o', ...
    'MarkerSize',st.marker+3,'Color',[.2 .2 .2],'LineWidth',.8, ...
    'LineStyle','none','HandleVisibility','off');
end

function plotCurrent(r,st)
fig = newFigure(r,st,14.5,'SCIS: cell current time series');
figureHeading(fig,'Cell-current time series',st,[.07 .90 .90 .05]);
mainPosition = [.085 .515 .895 .355];
ax = newAxes(fig,mainPosition,st,st.tick);
d = r.displayCurrent;
plot(ax,d.t,d.y,'Color',[.25 .25 .25],'LineWidth',.65,'HandleVisibility','off');
centres=zeros(1,5); labelY=zeros(1,5);
for op = 1:5
    rows = r.schedule(:,1)==op;
    a = min(r.schedule(rows,15)); b = max(r.schedule(rows,6));
    q = d.t>=a & d.t<b;
    plot(ax,d.t(q),d.y(q),'Color',st.colours(op,:),'LineWidth',.75);
    target = r.area_cm2*r.operatingPoints(op,1);
    plot(ax,[a b],[target target],'--','Color',[.35 .35 .35],'LineWidth',1);
    labelY(op)=target+2;  % 2 A above the respective operating current.
    if op==5, labelY(op)=target+1.25; end
    if any(q), labelY(op)=max(labelY(op),max(d.y(q))+.5); end
    textY=labelY(op);
    if op==5, textY=textY-0.75; end % Lower label only; retain V5 axis limits.
    text(ax,(a+b)/2,textY,densityLabel(r,op),'Units','data', ...
        'FontName',st.font,'FontSize',st.annotation,'FontWeight','normal', ...
        'Color',st.colours(op,:),'HorizontalAlignment','center', ...
        'VerticalAlignment','bottom','Interpreter','tex','Clipping','off');
    centres(op)=mainPosition(1)+mainPosition(3)*(a+b)/(2*r.stopTime);
end
xlim(ax,[0 r.stopTime]);
ylim(ax,[min(0,min(d.y))-.5 max([max(d.y),labelY])+2]);
xlabel(ax,'Simulation time (s)'); ylabel(ax,'Cell current (A)');
% Five compact details, centred directly below their operating-point stages.
% Fixed gap leaves room for the neighbouring tick labels and y-axis labels.
width=min(.135,min(diff(centres))-.045);
for op = 1:5
    a = newAxes(fig,[centres(op)-width/2 .14 width .19],st,9);
    e = r.examples{op};
    if isempty(e)
        text(a,.5,.5,'No complete record','Units','normalized', ...
            'HorizontalAlignment','center','Color','k','FontName',st.font, ...
            'FontSize',9,'FontWeight','normal');
        continue;
    end
    plot(a,e.time_ms,e.Iac_mA,'Color',st.colours(op,:),'LineWidth',st.detail);
    yline(a,0,':','Color',[.55 .55 .55],'LineWidth',.75,'HandleVisibility','off');
    duration=r.options.insetCycles/e.f*1000;
    % Round DISPLAY limits only: avoid 9.9794/19.9588/... tick labels.
    step=10^floor(log10(duration)); upper=ceil(duration/step)*step;
    xlim(a,[0 upper]); xticks(a,[0 upper/2 upper]);
    xtickformat(a,'%g'); xtickangle(a,0);
    peak = max(abs(e.Iac_mA));
    if ~isfinite(peak) || peak==0, peak=1; end
    ylim(a,[-1 1]*peak*1.15);
    xlabel(a,'Time (ms)','FontSize',9);
    % Units and meaning are common to all five panels; one shared label
    % prevents the fourth/fifth labels intruding into neighbouring data.
    if op==1, ylabel(a,'\Delta I (mA)','FontSize',9); end
    t=title(a,{sprintf('%.3g Hz',e.f),sprintf('%.2f%% p-p',e.pp)}, ...
        'FontSize',9,'FontWeight','normal');
    liftTitle(t,1.09);
end
savePlot(fig,r.options,'Current_sweep_and_insets');
end

function plotErrors(r,st)
T = r.table; fig = newFigure(r,st,16,'SCIS: recovery errors');
figureHeading(fig,'Impedance-recovery error',st);
a = newAxes(fig,[.10 .55 .865 .255],st,st.tick);
b = newAxes(fig,[.10 .14 .865 .255],st,st.tick);
set(a,'XScale','log','YScale','linear'); set(b,'XScale','log','YScale','linear');
for op = 1:5
    q = find(T.OP==op); [~,order] = sort(T.f_Hz(q)); q=q(order);
    err = T.ComplexError_pct(q);  % Retain exact zero errors on the linear axis.
    plot(a,T.f_Hz(q),err,'Color',st.colours(op,:),'LineWidth',st.detail, ...
        'Marker',st.markers{op},'MarkerSize',3,'DisplayName',densityLabel(r,op));
    plot(b,T.f_Hz(q),T.PhaseError_deg(q),'Color',st.colours(op,:), ...
        'LineWidth',st.detail,'Marker',st.markers{op},'MarkerSize',3);
    bad = ~T.NumericalPass(q);
    plot(a,T.f_Hz(q(bad)),err(bad),'x','Color',[.25 .25 .25], ...
        'LineStyle','none','MarkerSize',6,'HandleVisibility','off');
    plot(b,T.f_Hz(q(bad)),T.PhaseError_deg(q(bad)),'x','Color',[.25 .25 .25], ...
        'LineStyle','none','MarkerSize',6,'HandleVisibility','off');
end
yline(a,r.options.maxComplexError_pct,'--','Color',[.2 .2 .2], ...
    'LineWidth',1,'HandleVisibility','off');
yline(b,r.options.maxPhaseError_deg,'--','Color',[.2 .2 .2],'LineWidth',1);
yline(b,-r.options.maxPhaseError_deg,'--','Color',[.2 .2 .2],'LineWidth',1);
xlim(a,[min(T.f_Hz) max(T.f_Hz)]); xlim(b,a.XLim);
% Explicit full-range limits prevent inherited graphics settings clipping data.
finiteError=T.ComplexError_pct(isfinite(T.ComplexError_pct));
finitePhase=T.PhaseError_deg(isfinite(T.PhaseError_deg));
ylim(a,[0 1.08*max([r.options.maxComplexError_pct;finiteError;eps])]);
phaseRange=1.1*max([r.options.maxPhaseError_deg;abs(finitePhase);eps]);
ylim(b,[-phaseRange phaseRange]);
ylabel(a,'Complex relative error (%)'); ylabel(b,'Phase error (deg)');
xlabel(b,'Frequency (Hz)');
ta=title(a,'(a) Complex error','FontSize',st.panel);
tb=title(b,'(b) Phase error','FontSize',st.panel);
liftTitle(ta,1.09); liftTitle(tb,1.09);
% Let MATLAB calculate the natural legend width, then centre that width.
% A manually oversized legend box leaves its entries grouped on the left.
originalPosition=a.Position;
lg=legend(a,'Location','northoutside','Orientation','horizontal','NumColumns',5);
styleLegend(lg,st);
drawnow;
lg.Units='normalized'; pos=lg.Position;
pos(1)=0.5-pos(3)/2; pos(2)=.865;
lg.Position=pos; a.Position=originalPosition;
savePlot(fig,r.options,'Recovery_error');
end

function liftTitle(t,y)
t.Units='normalized'; p=t.Position; p(2)=y; t.Position=p;
end
function plotNyquistDiagnostic(r,st)
T = r.table; scale=1000*r.area_cm2;
fig = newFigure(r,st,16,'SCIS: all Nyquist records');
figureHeading(fig,'Nyquist diagnostic: all finite records',st);
ax = newAxes(fig,[.10 .17 .865 .69],st,st.tick);
for op=1:5
    z=referenceCurve(r,op)*scale;
    plot(ax,real(z),-imag(z),'Color',st.colours(op,:),'LineWidth',st.detail, ...
        'DisplayName',densityLabel(r,op));
    q=T.OP==op & isfinite(real(r.Z)) & isfinite(imag(r.Z));
    plot(ax,real(r.Z(q))*scale,-imag(r.Z(q))*scale, ...
        'LineStyle','none','Marker',st.markers{op},'MarkerSize',st.marker, ...
        'Color',st.colours(op,:),'HandleVisibility','off');
    q=q & ~T.NumericalPass;
    plot(ax,real(r.Z(q))*scale,-imag(r.Z(q))*scale,'x', ...
        'Color',[.2 .2 .2],'MarkerSize',8,'LineWidth',1,'HandleVisibility','off');
end
axis(ax,'equal'); axis(ax,'padded');
xlabel(ax,'Re(Z) (m\Omega cm^2)'); ylabel(ax,'-Im(Z) (m\Omega cm^2)');
lg=legend(ax,'Location','best'); styleLegend(lg,st);
footer(fig,sprintf('%d/%d numerical failures. Crosses identify failed records; no finite outliers are removed.', ...
    sum(~T.NumericalPass),height(T)),st);
savePlot(fig,r.options,'Nyquist_diagnostic_all_records');
end

function z=referenceCurve(r,op)
f=logspace(log10(min(r.table.f_Hz)),log10(max(r.table.f_Hz)),600);
p=r.reference; ct=r.operatingPoints(op,3);
z=p.Rohm+1./(1/ct+1./(p.ESR+1./(2i*pi*f*p.C)));
end

function referenceLimits(ax,z)
x=real(z); y=-imag(z);
dx=max(x)-min(x); dy=max(y)-min(y);
px=max(.07*dx,1); py=max(.10*dy,1);
xlim(ax,[min(x)-px max(x)+px]); ylim(ax,[min(0,min(y))-py max(y)+py]);
end

function label=densityLabel(r,op)
label=sprintf('%.2g A/cm^{2}',r.operatingPoints(op,1));end

function fig=newFigure(r,st,height_cm,name)
fig=figure('Color','w','Units','centimeters', ...
    'Position',[2 2 st.width_cm height_cm],'Name',name,'NumberTitle','off', ...
    'Visible',r.options.figureVisible,'MenuBar','none','ToolBar','none', ...
    'InvertHardcopy','off');
end

function ax=newAxes(fig,position,st,size_pt)
% Explicit local properties override dark themes without changing groot.
ax=axes('Parent',fig,'Units','normalized','Position',position, ...
    'Color','w','XColor','k','YColor','k','ZColor','k', ...
    'FontName',st.font,'FontSize',size_pt,'FontWeight','normal', ...
    'LineWidth',st.axes,'Box','on','Layer','top','TickDir','out', ...
    'GridColor',[0 0 0],'GridAlpha',.16,'MinorGridColor',[0 0 0], ...
    'MinorGridAlpha',.07,'XMinorGrid','off','YMinorGrid','off', ...
    'LabelFontSizeMultiplier',1,'TitleFontSizeMultiplier',1, ...
    'TitleFontWeight','normal','TickLabelInterpreter','tex', ...
    'XTickLabelRotation',0,'YTickLabelRotation',0);
hold(ax,'on'); grid(ax,'on');
set([ax.XLabel ax.YLabel ax.ZLabel ax.Title], ...
    'FontName',st.font,'FontSize',size_pt,'FontWeight','normal','Color','k','Interpreter','tex');
if isprop(ax,'Toolbar') && ~isempty(ax.Toolbar), ax.Toolbar.Visible='off'; end
end

function styleLegend(lg,st)
set(lg,'FontName',st.font,'FontSize',st.legend,'FontWeight','normal', ...
    'TextColor','k','Color','w','EdgeColor',[.75 .75 .75], ...
    'Box','off','Interpreter','tex','AutoUpdate','off');
end

function figureHeading(fig,words,st,position)
if nargin<4, position=[.07 .945 .90 .05]; end
annotation(fig,'textbox',position,'String',words, ...
    'EdgeColor','none','Color','k','FontName',st.titleFont, ...
    'FontSize',st.heading,'FontWeight',st.titleWeight, ...
    'HorizontalAlignment','center','VerticalAlignment','middle','Interpreter','none');
end

function footer(fig,words,st)
annotation(fig,'textbox',[.06 .008 .92 .06],'String',words, ...
    'EdgeColor','none','Color',[.2 .2 .2],'FontName',st.font,'FontSize',9, ...
    'FontWeight','normal','HorizontalAlignment','center', ...
    'VerticalAlignment','middle','Interpreter','none');
end

function textBox(fig,position,words,st)
annotation(fig,'textbox',position,'String',words,'Color','k', ...
    'EdgeColor','none','BackgroundColor','w','FontName',st.font, ...
    'FontSize',st.annotation,'FontWeight','normal','Interpreter','tex', ...
    'VerticalAlignment','middle');
end

function [body,titleFace,titleWeight]=resolveFont()
available=string(listfonts);
body=''; titleFace=''; titleWeight='bold';
for name=["Montserrat Medium","Montserrat Regular","Montserrat"]
    if any(strcmpi(available,name)), body=char(name); break; end
end
if isempty(body)
    body='Arial';
    for name=["Arial","Helvetica","DejaVu Sans"]
        if any(strcmpi(available,name)), body=char(name); break; end
    end
    warning('SCIS:Font','Montserrat is unavailable. Using %s; install Montserrat Medium/Regular for the manuscript style.',body);
else
    for name=["Montserrat SemiBold","Montserrat Bold"]
        if any(strcmpi(available,name))
            titleFace=char(name); titleWeight='normal'; break;
        end
    end
end
if isempty(titleFace), titleFace=body; end
end

function savePlot(fig,options,name)
drawnow;
% exportgraphics preserves system fonts in vector PDF where supported.
exportgraphics(fig,fullfile(options.outputDir,[name '.pdf']), ...
    'ContentType','vector','BackgroundColor','white');
exportgraphics(fig,fullfile(options.outputDir,[name '.png']), ...
    'Resolution',options.pngResolution,'BackgroundColor','white');
if options.saveFIG, savefig(fig,fullfile(options.outputDir,[name '.fig'])); end
end

function [t,y]=envelope(t,y,bins)
n=numel(t); if n<=2*bins, return; end
edges=round(linspace(1,n+1,bins+1)); idx=zeros(2*bins,1);
for k=1:bins
    a=edges(k); b=edges(k+1)-1; [~,lo]=min(y(a:b)); [~,hi]=max(y(a:b));
    idx(2*k-1:2*k)=sort([a+lo-1;a+hi-1]);
end
idx=unique([1;idx;n],'stable'); t=t(idx); y=y(idx);
end
function [S,OP,Rohm,C,ESR] = scis_plan()
% EDIT THIS IDENTICAL SECTION IN BOTH FILES when changing the circuit/sweep.
% All resistance values below are in OHMS. Physical blocks must match them.
Rbank = [50 30 15 10 4 2]*1e-3; % RB_G1 ... RB_G6, physical resistor values
Rsense=[100 10 2]*1e-3;        % RS_G1 ... RS_G3, keep existing sense calibration
Ron=0.85e-3; Goff=1e-6; Gdiode=1e-5;
Rohm=0.0212; C=0.4573; ESR=1e-6;
% Columns: j [A/cm2], E [V], Rct [Ohm], sense mask, perturbation mask.
% Branch weights: G1=1, G2=2, G3=4, G4=8, G5=16, G6=32.
% Fixed combinations give about 7% maximum p-p across the configured sweep.
OP = [
    0.05, 1.4270, 0.09887, 1, (1 + 2 + 8);       % G1 + G2 + G4
    0.10, 1.4504, 0.03597, 1, (2 + 8);           % G2 + G4
    0.50, 1.4814, 0.01030, 2, (2 + 4 + 8 + 16);  % G2 + G3 + G4 + G5
    1.00, 1.4970, 0.00607, 2, (1 + 32);          % G1 + G6
    4.00, 1.5250, 0.00287, 4, (2 + 4 + 32)       % G2 + G3 + G6
];
area=5; fmax=10000; fmin=1; nf=47;
acquireCycles=8; minSettleCycles=3; relaxConstants=10; opSettle=0.5;
sourceFilterTau=0.001; % Existing voltage-source input filters
% 47 logarithmic frequencies, descending from 10 kHz to 1 Hz.
% Keep this complete plan and its helpers identical in both files.
f=logspace(log10(fmax),log10(fmin),nf);
% Numeric table: no growing structure arrays.
% 1 OP, 2 freq index, 3 Hz, 4 burst start, 5 acquisition start, 6 end,
% 7 PSU V, 8 sense equivalent, 9 low bank R, 10 high bank R,
% 11 predicted p-p fraction, 12 target I, 13 acquire cycles,
% 14 settle cycles, 15 OP start, 16 fastest loaded RC time constant.
S=zeros(5*nf,16); now=0;
for op=1:5
    rs=bankR(OP(op,4),false,Rsense,Ron,Goff,Gdiode);
    rl=bankR(OP(op,5),true,Rbank,Ron,Goff,Gdiode);
    rh=bankR(OP(op,5),false,Rbank,Ron,Goff,Gdiode);
    opStart=now; now=now+opSettle;
    for k=1:nf
        [meanI,pp,tau]=periodic(f(k),rl,rh,OP(op,3),C,Rohm,rs,ESR);
        ns=max(minSettleCycles,ceil(f(k)*relaxConstants*max([tau sourceFilterTau])));
        target=area*OP(op,1); vs=OP(op,2)+target/meanI;
        a=now+ns/f(k); b=now+(ns+acquireCycles)/f(k);
        S((op-1)*nf+k,:)=[op k f(k) now a b vs rs rl rh pp target acquireCycles ns opStart min(tau)];
        now=b;
    end
end
end
function r=bankR(code,bypass,R,Ron,Goff,Gdiode)
g=0;
for k=1:numel(R)
    if bitget(uint32(code),k), sw=1/(1/Ron+Gdiode);
    else, sw=1/(Goff+Gdiode); end
    g=g+1/(R(k)+sw);
end
if bypass, g=g+1/Ron+Gdiode; else, g=g+Goff+Gdiode; end
r=1/g;
end
function [meanI,pp,tau]=periodic(f,rl,rh,Rct,C,Rohm,rs,ESR)
% Exact periodic solution for unit supply overdrive U=Vpsu-E=1 V.
% Valid for this voltage-fed linear EEC with reverse-biased MOSFET body diodes.
re=Rohm+rs+[rl rh]; D=re*Rct+(re+Rct)*ESR;
tau=C*D./(re+Rct); xi=Rct./(re+Rct);
ci=(Rct+ESR)./D; cx=Rct./D; h=.5/f;
a=exp(-h./tau); b=-expm1(-h./tau);
x0=(xi(2)*b(2)+a(2)*xi(1)*b(1))/(-expm1(-h*sum(1./tau)));
x1=xi(1)+(x0-xi(1))*a(1);
xint=xi*h+([x0 x1]-xi).*tau.*b;
meanI=sum(ci*h-cx.*xint)/(2*h);
v=[ci(1)-cx(1)*x0 ci(1)-cx(1)*x1 ci(2)-cx(2)*x1 ci(2)-cx(2)*x0];
pp=(max(v)-min(v))/meanI;
end
