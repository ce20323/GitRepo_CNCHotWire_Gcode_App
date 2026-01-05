function run_HotWireSTEPApp_v6_2
% Simple launcher for the HotWire STEP App v6.2
%
% Usage (from Command Window):
%   run_HotWireSTEPApp_v6_2
% Close any existing app figures first
delete(findall(0, 'Type', 'figure', 'Name', 'Hot Wire STEP App v6.2'));

% Clear variables but NOT classes (to avoid the warnings you saw)
clearvars;
clc;
% Launch
app = HotWireSTEPApp_v6_2();
end