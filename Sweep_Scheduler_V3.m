function [V_emf,R_CT,C_EDL,V_PSU, ...
 RB_G1,RB_G2,RB_G3,RB_G4,RB_G5,RB_G6, ...
 RS_G1,RS_G2,RS_G3,RS_MB,MAIN_GATE,is_EIS,j_current,op_idx] = sweep_scheduler_V3(t)
%#codegen
%SWEEP_SCHEDULER_V3 Matched 10 kHz schedule for SCIS_Post_Processing_V6.
% Paste this ENTIRE file, including local functions, into MATLAB Function3.
% Keep the Clock input and all existing 18 output wires. No external helpers.
%
% BEFORE RUNNING: info = SCIS_Post_Processing_V6;
% Use info.stopTime for BOTH fresh simulations (start time 0):
%   Trial 1: MaxStep = 3.125e-6 s;  Trial 2: MaxStep = 1.5625e-6 s.
% MinStep stays auto. Keep solver tolerances, logging and noise identical.
% New schedule: 47 log-spaced frequencies from 10000 to 1 Hz per OP.
% Old 40 kHz logs/caches are NOT compatible with this schedule.
%
% is_EIS marks acquisition only; excitation also runs during burst settling.
% Cached arrays are constant; evaluation is otherwise stateless so rejected
% solver steps/backtracking cannot advance a persistent state machine.
% Clock-driven gate edges are not explicitly scheduled solver events.
% Code was statically checked; MATLAB/Simulink execution was unavailable.
persistent S OP cap
if isempty(S)
    [S,OP,~,cap,~]=scis_plan();
end
n=size(S,1); nf=n/5;
% Find OP using precomputed start times, including its initial settling.
op=1;
for q=2:5
    if t>=S((q-1)*nf+1,15), op=q; end
end
first=(op-1)*nf+1; last=op*nf;
V_emf=OP(op,2); R_CT=OP(op,3); C_EDL=cap;
j_current=OP(op,1); op_idx=double(op);
mask=uint32(OP(op,5)); sense=uint32(OP(op,4));
RB_G1=double(bitget(mask,1)); RB_G2=double(bitget(mask,2));
RB_G3=double(bitget(mask,3)); RB_G4=double(bitget(mask,4));
RB_G5=double(bitget(mask,5)); RB_G6=double(bitget(mask,6));
RS_G1=double(bitget(sense,1)); RS_G2=double(bitget(sense,2)); RS_G3=double(bitget(sense,3));
RS_MB=0; MAIN_GATE=1; is_EIS=0; V_PSU=S(first,7);
if t<S(first,4), return; end
if t>=S(n,6)
    V_PSU=S(n,7); % Hold last OP, no spurious sense bypass/current step.
    return;
end
% Binary search on burst start times. No logarithms/powers per solver call.
lo=first; hi=last;
while lo<hi
    mid=floor((lo+hi+1)/2);
    if t>=S(mid,4), lo=mid; else, hi=mid-1; end
end
k=lo; V_PSU=S(k,7);
phase=(t-S(k,4))*S(k,3);
MAIN_GATE=double(mod(phase,1)<0.5);
is_EIS=double(t>=S(k,5) && t<S(k,6));
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
