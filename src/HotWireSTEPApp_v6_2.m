classdef HotWireSTEPApp_v6_2 < handle
    % ===========================================================
    % HOTWIRE STEP APP (v6.2 baseline, split into main + helpers)
    % University of Bristol — Hot Wire CNC Project
    %
    % - Imports STEP (via FreeCAD) or STL files
    % - Visualises the 3D model in a uiaxes
    % - Orientation controls (±90° + numeric fields)
    % - Left / Right plane offsets (in machine X)
    % - Planes always remain Y–Z aligned; model rotates
    % - Plane offsets are defined relative to the model's left face:
    %       * left plane: offset = 0 at left face
    %       * right plane: default offset = model width (right face)
    % - Uses helper class HotWireSTEPApp_v6_helpers for STEP import
    %
    % This is intentionally conservative and mirrors your last
    % working single-file baseline, but with the STEP-import function
    % moved into a separate helpers class.
    % ===========================================================

    properties (Constant)
        % -------- Profile sampling defaults --------
        DefaultProfileTolerance (1,1) double = 0.2;   % [mm]
        MinProfileTolerance     (1,1) double = 0.01;  % [mm]
        MaxProfileTolerance     (1,1) double = 5.0;   % [mm]

        % -------- Kerf / wire offset defaults --------
        DefaultKerf (1,1) double = 0.8;   % [mm]
        MinKerf     (1,1) double = 0.0;   % [mm]
        MaxKerf     (1,1) double = 5.0;   % [mm]

        % -------- View / plane padding factors --------
        AutoFitPaddingFactor (1,1) double = 0.35;  % model view padding
        PlanePaddingFactor   (1,1) double = 0.20;  % plane extents padding

        % --- Billet UI Increments ---
        BilletSizeStep  = 1.0;  % mm
        BilletShiftStep = 0.5;  % mm

        % Machine Configuration Constants/State
        MachineSpanX   = 1180; % Distance between tower planes [mm]
        MachineLimitY  = 750;  % Total Y travel [mm]
        MachineLimitZ  = 500;  % Total Z travel [mm]
        MachineBedSize   = [1000, 700, 20]  % Physical dimensions [L, W, H]
        MachineBedPos    = [50, 50, -20]      % Bed origin relative to machine 0,0,0

        % --- Placement Rules ---
        BilletMinYBuffer = 50.0; % Distance from front/home
        BilletRoundingY  = 10.0; % Round to nearest 10mm

    end

    properties
        % ---------- UI containers ----------
        UIFigure
        TabGroup
        TabModel
        TabProfiles      % Profiles tab
        TabBillet        % NEW: Billet tab

        GLProfiles
        AxLeftProfile
        AxRightProfile

        GLBillet         % NEW: Billet tab main layout
        BilletLeftPanel
        BilletRightPanel
        AxBilletTop
        AxBilletFront
        AxBilletRight

        GLModel
        GLLeft
        profilesLeft

        % Background panels for the toggle switch
        cutPanel
        cutGrid

        % ---------- File import controls ----------
        BtnImportSTEP
        BtnImportSTL
        FileLabel

        % ---------- Orientation controls ----------
        RotGrid
        RotEdit
        RotAngles double = [0 0 0]

        BtnResetOrientation
        BtnResetPlot

        % ---------- Cut style + offsets ----------
        TaperToggle
        NumLeftOffset
        NumRightOffset
        BtnResetPlanes

        % ---------- Profile sampling ----------
        ProfileTolerance (1,1) double = 0.2     % [mm], target segment size
        ProfileTolSpinner                 % UI handle for tolerance control
        ProfileAxesLocked (1,1) logical = false  % When true, updateProfiles2D will NOT reset xlim/ylim.
        BtnResetProfileTol                % "Reset tolerance" button
        BtnResetProfilesView              % "Reset Profiles View" button
        ProfilePointCountLabel            % read-only "points (L/R)" display

        % ---------- Kerf compensation ----------
        KerfValue (1,1) double = 0.5      % [mm], positive = shrink profile
        KerfSpinner                       % UI handle for kerf control
        BtnApplyKerf                      % "Apply kerf offset" button
        KerfEnabled (1,1) logical = false % only draw kerf when true
        LeftKerf2DLine                    % 2D kerf path (left)
        RightKerf2DLine                   % 2D kerf path (right)

        % ---------- Profile generation (future) ----------
        BtnGenerateProfiles   % stub – no heavy logic yet
        BtnContinue           % Model tab → Profiles
        BtnProfilesContinue   % Profiles tab → Billet (next step)

        % ---------- Billet tab controls ----------
        BtnAutoFitBillet
        BtnResetPosition
        BilletMessageLabel

        % ---------- Billet  ----------
        ModelF   double     % Mx3 faces   of the current model

        % Billet size controls (X/Y/Z)
        BilletSizeEdits          % 1×3 numeric edit fields for billet size [mm]
        BilletSizeMinusBtns      % 1×3 "-" buttons (−1 mm)
        BilletSizePlusBtns       % 1×3 "+" buttons (+1 mm)

        % Billet position controls
        BtnAutoPositionModel
        BilletNegOffsetEdits     % 1×3: min-model to min-billet gap
        BilletCenterOffsetEdits  % 1×3: "current offset" value
        BilletPosOffsetEdits     % 1×3: max-billet to max-model gap
        BilletShiftMinusBtns     % 1×3: shift −0.5 mm
        BilletShiftPlusBtns      % 1×3: shift +0.5 mm

        BtnBilletContinue

        % ---------- Model visualisation ----------
        AxModel
        ModelPatch
        ModelVerticesOriginal
        CurrentModelName string = ""

        % ---------- Planes ----------
        LeftPlanePatch
        RightPlanePatch
        LeftPlaneText
        RightPlaneText

        % ---------- Profiles (3D graphics + raw data) ----------
        LeftProfileLine3D
        RightProfileLine3D
        LeftProfilePoints   % Nx3 double (NaNs removed)
        RightProfilePoints  % Nx3 double (NaNs removed)
        LeftProfile2DLine
        RightProfile2DLine
        LeftProfile2DMeshLine    % faint raw mesh slice (left)
        RightProfile2DMeshLine   % faint raw mesh slice (right)
        LeftProfileRawYZ         % [:,2] = [y, z] raw (NaN-separated)
        RightProfileRawYZ

        % ---------- FreeCAD ----------
        FreeCADExe = "C:\Program Files\FreeCAD 1.0\bin\FreeCADCmd.exe"

        % ---------- Saved "home" view ----------
        DefaultXLim
        DefaultYLim
        DefaultZLim
        DefaultDataAspectRatio
        DefaultPlotBoxAspectRatio
        DefaultCameraPosition
        DefaultCameraTarget
        DefaultCameraUpVector
        DefaultCameraViewAngle

        % ---------- Mouse interaction state ----------
        IsDragging logical = false
        LastMousePos (1,2) double = [NaN NaN]

        % ---------- Model Bounding Box (Crucial for Planes/Billet) ----------
        ModelXMin, ModelXMax
        ModelYMin, ModelYMax
        ModelZMin, ModelZMax
        BilletModelDimLabels     % 1x3 handles for model dimension readouts

        % Reference bounds to define the "Import Position"
        BilletRefXMin
        BilletRefYMin
        BilletRefZMin

        % ---------- Billet State ----------
        BilletXMin, BilletXMax
        BilletYMin, BilletYMax
        BilletZMin, BilletZMax
        BilletSize  = [0 0 0]  % [Length X, Width Y, Height Z] - The Driving Factor
        BilletShift = [0 0 0]  % Cumulative [dX, dY, dZ] from import position

        % ---------- Machine tab ----------
        TabMachine
        GLMachine
        MachineLeftPanel
        AxMachine
        MachinePosSpinners       % 1x3 handles for the spinners
        MachineBilletPos = [100, 50, 0]   % Billet origin relative to machine 0,0,0
        BtnResetMachineBillet
        BtnResetMachinePlot
        BtnMachineContinue
        MachineMessageLabel
        
        % ===========================================================
        % ---------- Cutting / Passes Tab ----------
        % ===========================================================
        TabCutting
        GLCutting
        CuttingLeftPanel
        AxCutLeft
        AxCutRight

        % Interaction Controls
        SwitchCutDir           % Toggle: Top-First (CW) vs Bottom-First (CCW)
        BtnInteractionGroup    % Button Group for mouse mode
        BtnPickStart           % Button: "Set Start Point"
        BtnPickEntry           % Button: "Set Entry Point" (Future)
        BtnPickEntry2   % New Button
        BtnClearEntries % Helper to reset points

        % Cutting Tab Properties
        SyncStartPoints (1,1) logical = true % Default to sync

        % Entry Points (Machine Coordinates [y, z])
        % If empty, we will calculate default later
        EntryPointL = []
        EntryPointR = []
        EntryPoint2L = []
        EntryPoint2R = []

        % UI Elements
        SwitchSyncStart  % Toggle: Coupled / Independent
        SwitchSyncEntry % UI Switch for Entry Coupling
        btnAutoStart
        btnAutoEntry
        BtnCuttingContinue

        % ===========================================================
        % State
        % ===========================================================
        SelectedStartIdxL = 1  % Index in the profile array
        SelectedStartIdxR = 1
        CutDirection = 'CW'    % 'CW' or 'CCW'

        % ---------- Simulation Tab ----------
        TabSimulation
        GLSimulation
        SimLeftPanel
        AxSim
        BtnSimContinue

        % Simulation Controls
        SimSlider
        SimPlayBtn
        SimStopBtn
        SimSpeedSpinner

        % Readout Labels
        LblReadoutX
        LblReadoutY
        LblReadoutZ
        LblReadoutA
        
        % Simulation Data
        SimPathL % Nx3 Array [x, y, z] (Machine Coords)
        SimPathR % Nx3 Array [x, y, z] (Machine Coords)
        SimTowerPathL % Nx3 %Physical Tower Paths (Projected)
        SimTowerPathR % Nx3
        SimRapidCutoffIndex % Index where rapid approach ends
        SimProfileStartIndex % NEW: End of Orange Lead-in / Start of Profile
        SimFeedEndIndex     % NEW: Index where profile ends and return begins
        SimLeadOutEndIndex  % NEW: Index where orange lead-out ends
        SimTimer % timer object for animation
        % --- Truth / semantic toolpath data (NOT interpolated) ---
        ProfileSyncL    % Nx2 [Y Z] after preparePlotData + syncPointCounts
        ProfileSyncR    % Nx2 [Y Z] after preparePlotData + syncPointCounts

        SimRawRapidL    % Mx2 [Y Z] semantic rapid-in points
        SimRawRapidR
        SimRawLeadInL   % 2x2 typically: [entry; start]
        SimRawLeadInR
        SimRawLeadOutL  % 2x2 typically: [end; entry]
        SimRawLeadOutR
        SimRawReturnL   % Kx2 semantic return points
        SimRawReturnR
        % --- Distance-based simulation stepping ---
        SimArcLenL          % cumulative arc length (model left)
        SimArcLenR          % cumulative arc length (model right)
        SimTotalLength      % total cut length (scalar)
        SimStepDist = 2.0   % mm per simulation step (tweakable)
        SimPlayDist = 0     % current distance cursor

        % ---------- Post-Process Tab ----------
        TabPostProcess
        GLPostProcess
        PostLeftPanel
        AxPost

        % Inputs
        SpinFeedRate
        SpinPower
        FieldFilename

        % Buttons
        BtnPostProcess
        BtnGCodePrev
        BtnGCodeNext
        BtnSaveGCode

        % --- Post G-code UI ---
        PanelGCode
        GridGCode
        ListGCode

        % --- Post program data ---
        PP_GCodeLines string = string.empty(0,1)     % full text, one line per row
        PP_LineToPathIndex double = []              % maps gcode line -> motion path index (NaN for non-motion)
        PP_PathXYZA double = []                     % Nx4 [X Y Z A] cumulative path
        PP_SelectedLine (1,1) double = 1
        % --- Post (truth-based) path for plotting / stepping ---
        PP_PathL
        PP_PathR
        PP_TowerPathL
        PP_TowerPathR

        PP_RapidEndIndex
        PP_ProfileStartIndex
        PP_ProfileEndIndex
        PP_LeadOutEndIndex

        % ---------- App state ----------
        % 0 = pre-profile (model only)
        % 1 = active cutting (planes + profiles live)
        AppState (1,1) double = 0

    end

    methods

        function app = HotWireSTEPApp_v6_2()
            % Constructor: close any existing instance of this app and
            % build a fresh UI.

            old = findall(0,'Type','figure','Name','Hot Wire STEP App v6.2');
            if ~isempty(old)
                delete(old);
            end

            %clc;
            app.buildUI();

            % ===========================================================
            % DEV AUTO-LOAD TEST MODEL (REMOVE BEFORE RELEASE)
            % ===========================================================
            try
                testFile = "C:\Users\ce20323\OneDrive - University of Bristol\Documents\MATLAB\CNCHotWire_GCode_App\examples\RibTemplate_NewCNCTest1.step";

                if isfile(testFile)
                    disp("DEV AUTOLOAD: Loading test STEP model...");

                    % --- Use the existing helper to import STEP via FreeCAD ---
                    [V,F] = HotWireSTEPApp_v6_helpers.importSTEP_FreeCAD( ...
                        testFile, app.FreeCADExe);

                    if isempty(V)
                        warning("DEV AUTOLOAD: STEP import returned empty data.");
                    else
                        % Store original vertices for rotation resets
                        app.ModelVerticesOriginal = V;
                        app.CurrentModelName      = "AUTOLOADED: RibTemplate_NewCNCTest1.step";

                        % Reset orientation
                        app.RotAngles = [0 0 0];
                        for i = 1:3
                            app.RotEdit(i).Value = 0;
                        end

                        % Reset plane offsets
                        app.NumLeftOffset.Value  = 0;
                        app.NumRightOffset.Value = 0;

                        % --- Plot mesh and planes ---
                        app.plotMesh(V,F);
                        app.enterState0();

                        disp("DEV AUTOLOAD: Completed.");
                    end
                else
                    warning("DEV AUTOLOAD: File not found:\n%s", testFile);
                end

            catch ME
                warning('DEV_AUTOLOAD:Error','%s', ME.message);
            end
        end


        % ===========================================================
        % BUILD UI (Fixed Spacing & Alignments)
        % ===========================================================
        function buildUI(app)

            % --- 1. Main Window Setup ---
            app.UIFigure = uifigure('Name','Hot Wire STEP App v6.2');
            app.UIFigure.CloseRequestFcn = @(src,event)app.onAppClose(src);
            app.UIFigure.WindowState = 'maximized';
            app.UIFigure.WindowKeyPressFcn = @(src,event)app.onKeyPress(src,event); %key press on post tab to scroll code

            % --- 2. Theme & Colors ---
            t = app.getTheme();
            sideBg   = t.sideBg;
            panelBg  = t.panelBg;
            labelCol = t.labelCol;
            inputBg  = t.inputBg;
            inputTxt = t.inputTxt;

            app.UIFigure.Color = sideBg;

            % --- 3. Tab Group Container ---
            app.TabGroup = uitabgroup(app.UIFigure, ...
                'Units','normalized', ...
                'Position',[0 0 1 1]);

            % ===========================================================
            % TAB 1: MODEL IMPORT & ORIENTATION
            % ===========================================================
            app.TabModel = uitab(app.TabGroup,'Title','Model');

            % Main Layout
            app.GLModel = uigridlayout(app.TabModel,[1 2]);
            app.GLModel.ColumnWidth   = {320,'1x'};
            app.GLModel.Padding       = [10 10 10 10];
            app.GLModel.ColumnSpacing = 10;

            % --- Left Control Panel ---
            app.GLLeft = uigridlayout(app.GLModel,[16 1]);
            app.GLLeft.Layout.Column = 1;
            app.GLLeft.RowHeight = repmat({'fit'},1,16);
            app.GLLeft.RowHeight{15} = '1x'; % Spring
            app.GLLeft.Padding = [10 10 10 10];
            app.GLLeft.BackgroundColor = sideBg;

            % -- File Import --
            app.BtnImportSTEP = uibutton(app.GLLeft, 'Text','Import STEP (recommended)', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onImportSTEP());
            app.BtnImportSTEP.Layout.Row = 1;

            app.BtnImportSTL = uibutton(app.GLLeft, 'Text','Import STL', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onImportSTL());
            app.BtnImportSTL.Layout.Row = 2;

            app.FileLabel = uilabel(app.GLLeft, 'Text','Current File: ---', 'FontWeight','bold', 'FontColor',labelCol);
            app.FileLabel.Layout.Row = 3;

            lblModSpacer1 = uilabel(app.GLLeft,'Text',"");
            lblModSpacer1.Layout.Row = 4;

            % -- Taper Toggle --
            pnlTaper = uipanel(app.GLLeft, 'BackgroundColor', sideBg, 'BorderType', 'line', 'Title', '');
            pnlTaper.Layout.Row = 5;

            gridTaper = uigridlayout(pnlTaper,[1 3]);
            gridTaper.ColumnWidth = {'1x','fit','1x'};
            gridTaper.Padding = [0 0 0 0]; gridTaper.BackgroundColor = sideBg;

            app.TaperToggle = uiswitch(gridTaper,'slider', 'Items',{'Straight','Tapered'}, 'Value','Straight', 'ValueChangedFcn',@(~,~)app.onTaperModeChanged());
            app.TaperToggle.Layout.Column = 2;

            lblModSpacer2 = uilabel(app.GLLeft,'Text',"");
            lblModSpacer2.Layout.Row = 6;

            % -- Orientation Controls --
            pnlRot = uipanel(app.GLLeft, 'Title','Model Orientation Controls', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold');
            pnlRot.Layout.Row = 7;

            gridRotOuter = uigridlayout(pnlRot,[1 3]);
            gridRotOuter.ColumnWidth = {'1x','fit','1x'}; gridRotOuter.Padding = [5 5 5 5];

            app.RotGrid = uigridlayout(gridRotOuter,[3 4]);
            app.RotGrid.Layout.Column = 2;
            app.RotGrid.ColumnWidth = {'fit','fit',70,'fit'};
            app.RotGrid.RowHeight   = {'fit','fit','fit'};

            rotAxes = {'X','Y','Z'};
            app.RotEdit = gobjects(1,3);
            for i = 1:3
                lblRotAxis = uilabel(app.RotGrid, 'Text',rotAxes{i}, 'FontWeight','bold', 'HorizontalAlignment','center');
                lblRotAxis.Layout.Row = i;

                btnRotNeg = uibutton(app.RotGrid,'Text','-90°', 'ButtonPushedFcn',@(~,~)app.rotateModel([rotAxes{i} 'm']));
                btnRotNeg.Layout.Row = i;

                app.RotEdit(i) = uieditfield(app.RotGrid,'numeric', 'Limits',[0 360], 'Value',0, 'HorizontalAlignment','center', 'ValueDisplayFormat','%.0f°', ...
                    'ValueChangedFcn',@(src,~)app.updateRotation(rotAxes{i},src.Value));
                app.RotEdit(i).Layout.Row = i;

                btnRotPos = uibutton(app.RotGrid,'Text','+90°', 'ButtonPushedFcn',@(~,~)app.rotateModel([rotAxes{i} 'p']));
                btnRotPos.Layout.Row = i;
            end

            % -- Reset Controls --
            app.BtnResetOrientation = uibutton(app.GLLeft, 'Text','Reset Orientation', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.resetOrientation());
            app.BtnResetOrientation.Layout.Row = 8;

            app.BtnResetPlot = uibutton(app.GLLeft, 'Text','Reset Plot View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.resetPlotView());
            app.BtnResetPlot.Layout.Row = 9;

            lblModSpacer3 = uilabel(app.GLLeft,'Text',"");
            lblModSpacer3.Layout.Row = 10;

            % -- Plane Offsets --
            pnlOff = uipanel(app.GLLeft, 'BackgroundColor',panelBg, 'BorderType','line');
            pnlOff.Layout.Row = 11;

            gridOff = uigridlayout(pnlOff,[3 2]);
            gridOff.ColumnWidth = {'1x',90}; gridOff.RowHeight = {'fit','fit','fit'}; gridOff.Padding = [10 10 10 10];

            % Colors for offset fields
            valCol = [0 0 0];

            lblOffL = uilabel(gridOff, 'Text','Left Plane Offset [mm]:', 'HorizontalAlignment','right', 'FontWeight','bold');
            lblOffL.Layout.Row = 1;

            app.NumLeftOffset = uispinner(gridOff, 'Limits',[-1000 1000], 'Value',0, 'Step',1, 'ValueDisplayFormat','%.2f', ...
                'FontColor',valCol, 'BackgroundColor',[0.96 0.86 0.86], 'ValueChangedFcn',@(src,evt)app.onPlaneOffsetChanged(src,evt));
            app.NumLeftOffset.Layout.Row = 1; app.NumLeftOffset.Layout.Column = 2;

            lblOffR = uilabel(gridOff, 'Text','Right Plane Offset [mm]:', 'HorizontalAlignment','right', 'FontWeight','bold');
            lblOffR.Layout.Row = 2;

            app.NumRightOffset = uispinner(gridOff, 'Limits',[-1000 1000], 'Value',0, 'Step',1, 'ValueDisplayFormat','%.2f', ...
                'FontColor',valCol, 'BackgroundColor',[0.86 0.96 0.86], 'ValueChangedFcn',@(src,evt)app.onPlaneOffsetChanged(src,evt));
            app.NumRightOffset.Layout.Row = 2; app.NumRightOffset.Layout.Column = 2;

            app.BtnResetPlanes = uibutton(gridOff, 'Text','Reset Planes', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.resetPlanes());
            app.BtnResetPlanes.Layout.Row = 3; app.BtnResetPlanes.Layout.Column = [1 2];

            % -- Bottom Buttons --
            lblModSpring = uilabel(app.GLLeft, 'Text','');
            lblModSpring.Layout.Row = 15;

            pnlBtns = uipanel(app.GLLeft, 'BackgroundColor',[0.16 0.16 0.16], 'BorderType','none');
            pnlBtns.Layout.Row = 16;

            gridBtns = uigridlayout(pnlBtns,[1 2]);
            gridBtns.Padding = [0 0 0 0]; gridBtns.ColumnSpacing = 10;

            app.BtnGenerateProfiles = uibutton(gridBtns, 'Text','Generate Profiles', 'FontWeight','bold', 'BackgroundColor',[0.15 0.45 0.8], 'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~)app.onGenerateProfiles());

            app.BtnContinue = uibutton(gridBtns, 'Text','Continue →', 'FontWeight','bold', 'BackgroundColor',[0.3 0.3 0.3], 'FontColor',[0.8 0.8 0.8], ...
                'Enable','off', 'ButtonPushedFcn',@(~,~)app.onContinue());

            % --- Right Panel: 3D Model Axis ---
            app.AxModel = uiaxes(app.GLModel);
            app.AxModel.Layout.Column = 2;
            app.AxModel.BackgroundColor = [0.11 0.11 0.11];
            xlabel(app.AxModel,'X (mm)'); ylabel(app.AxModel,'Y (mm)'); zlabel(app.AxModel,'Z (mm)');
            grid(app.AxModel,'on'); view(app.AxModel,3);
            hold(app.AxModel,'on');


            % ===========================================================
            % TAB 2: PROFILES
            % ===========================================================
            app.TabProfiles = uitab(app.TabGroup,'Title','Profiles');

            app.GLProfiles = uigridlayout(app.TabProfiles,[1 2]);
            app.GLProfiles.ColumnWidth = {320,'1x'};
            app.GLProfiles.Padding = [10 10 10 10];

            % --- Left Control Panel ---
            app.profilesLeft = uigridlayout(app.GLProfiles,[6 1]);
            app.profilesLeft.Layout.Column = 1;
            app.profilesLeft.RowHeight = {'fit','fit','fit','fit','1x','fit'}; % Row 5 = Spring
            app.profilesLeft.Padding = [10 10 10 10];
            app.profilesLeft.BackgroundColor = sideBg;

            % -- Tolerance --
            pnlTol = uipanel(app.profilesLeft, 'Title','Profile Sampling', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlTol.Layout.Row = 1;

            gridTol = uigridlayout(pnlTol,[2 2]);
            gridTol.ColumnWidth = {'1x',90}; gridTol.Padding = [10 5 10 5];

            lblTol = uilabel(gridTol, 'Text','Profile Tolerance [mm]:', 'HorizontalAlignment','right', 'FontWeight','bold', 'FontColor',labelCol);

            app.ProfileTolSpinner = uispinner(gridTol, 'Limits',[HotWireSTEPApp_v6_2.MinProfileTolerance, HotWireSTEPApp_v6_2.MaxProfileTolerance], ...
                'Value',HotWireSTEPApp_v6_2.DefaultProfileTolerance, 'Step',0.05, 'ValueDisplayFormat','%.2f', 'ValueChangedFcn',@(src,~)app.onProfileToleranceChanged(src));
            app.ProfileTolerance = HotWireSTEPApp_v6_2.DefaultProfileTolerance;

            app.ProfilePointCountLabel = uilabel(gridTol, 'Text','Number of Points (L/R): -- / --', 'HorizontalAlignment','right', 'FontColor',labelCol, 'FontAngle','italic');
            app.ProfilePointCountLabel.Layout.Row = 2; app.ProfilePointCountLabel.Layout.Column = [1 2];

            % -- Reset Buttons --
            app.BtnResetProfileTol = uibutton(app.profilesLeft, 'Text','Reset Tolerance', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetProfileTolerance());
            app.BtnResetProfileTol.Layout.Row = 2;

            app.BtnResetProfilesView = uibutton(app.profilesLeft, 'Text','Reset Profiles View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.resetProfilesView());
            app.BtnResetProfilesView.Layout.Row = 3;

            % -- Kerf --
            pnlKerf = uipanel(app.profilesLeft, 'Title','Kerf Compensation', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlKerf.Layout.Row = 4;

            gridKerf = uigridlayout(pnlKerf,[2 2]);
            gridKerf.ColumnWidth = {'1x',90}; gridKerf.Padding = [10 5 10 5];

            lblKerf = uilabel(gridKerf, 'Text','Kerf [mm]:', 'HorizontalAlignment','right', 'FontWeight','bold', 'FontColor',labelCol);

            app.KerfSpinner = uispinner(gridKerf, 'Limits',[HotWireSTEPApp_v6_2.MinKerf, HotWireSTEPApp_v6_2.MaxKerf], ...
                'Value',HotWireSTEPApp_v6_2.DefaultKerf, 'Step',0.1, 'ValueDisplayFormat','%.2f', 'ValueChangedFcn',@(src,~)app.onKerfChanged(src));
            app.KerfValue = HotWireSTEPApp_v6_2.DefaultKerf;

            app.BtnApplyKerf = uibutton(gridKerf, 'Text','Apply Kerf Offset', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onApplyKerf());
            app.BtnApplyKerf.Layout.Row = 2; app.BtnApplyKerf.Layout.Column = [1 2];

            % -- Spacer --
            lblProfSpacer = uilabel(app.profilesLeft, 'Text','');
            lblProfSpacer.Layout.Row = 5;

            % -- Continue --
            app.BtnProfilesContinue = uibutton(app.profilesLeft, 'Text','Continue →', 'FontWeight','bold', 'Enable', 'off', 'BackgroundColor',[0.3 0.3 0.3], ...
                'ButtonPushedFcn',@(~,~)app.onContinueFromProfiles());
            app.BtnProfilesContinue.Layout.Row = 6;

            % --- Right Panel: 2D Plots ---
            gridProfRight = uigridlayout(app.GLProfiles,[2 1]);
            gridProfRight.Layout.Column = 2;
            gridProfRight.RowHeight = {'1x','1x'};

            app.AxLeftProfile = uiaxes(gridProfRight);
            app.AxLeftProfile.BackgroundColor = [0.11 0.11 0.11];
            title(app.AxLeftProfile,'Left Profile'); grid(app.AxLeftProfile,'on'); axis(app.AxLeftProfile,'equal');

            app.AxRightProfile = uiaxes(gridProfRight);
            app.AxRightProfile.BackgroundColor = [0.11 0.11 0.11];
            title(app.AxRightProfile,'Right Profile'); grid(app.AxRightProfile,'on'); axis(app.AxRightProfile,'equal');


            % ===========================================================
            % TAB 3: BILLET CONFIGURATION
            % ===========================================================
            app.TabBillet = uitab(app.TabGroup,'Title','Billet');

            app.GLBillet = uigridlayout(app.TabBillet,[1 2]);
            app.GLBillet.ColumnWidth = {320,'1x'};
            app.GLBillet.Padding = [10 10 10 10];

            % --- Left Control Panel ---
            app.BilletLeftPanel = uigridlayout(app.GLBillet,[7 1]);
            app.BilletLeftPanel.Layout.Column = 1;
            app.BilletLeftPanel.RowHeight = {'fit','fit','fit','fit','fit','1x','fit'};
            app.BilletLeftPanel.Padding = [10 10 10 10];
            app.BilletLeftPanel.BackgroundColor = sideBg;

            % -- Auto Fit --
            app.BtnAutoFitBillet = uibutton(app.BilletLeftPanel, 'Text','Auto-fit Billet', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onAutoFitBillet());
            app.BtnAutoFitBillet.Layout.Row = 1;

            % -- Size Controls --
            pnlBSize = uipanel(app.BilletLeftPanel, 'Title','Billet Size Controls', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold');
            pnlBSize.Layout.Row = 2;

            gridBSizeOuter = uigridlayout(pnlBSize, [1 1]); gridBSizeOuter.Padding = [5 5 5 5];

            % [FIX] Tighten spacing (ColumnSpacing=4) to prevent cropping on the right
            gridBSize = uigridlayout(gridBSizeOuter, [4 6]);
            gridBSize.ColumnWidth = {35, 65, 20, 65, 20, 65};
            gridBSize.Padding = [4 4 4 4];
            gridBSize.ColumnSpacing = 4; % <-- ADDED to fix cropping

            % Headings
            lblAxH = uilabel(gridBSize, 'Text','Axis', 'FontWeight','bold', 'FontColor',labelCol, 'HorizontalAlignment','center');
            lblAxH.Layout.Row = 1;
            lblStkH = uilabel(gridBSize, 'Text','Stock [mm]', 'FontWeight','bold', 'FontColor',labelCol, 'HorizontalAlignment','center');
            lblStkH.Layout.Row=1; lblStkH.Layout.Column=[3 5];
            lblModH = uilabel(gridBSize, 'Text','Model', 'FontWeight','bold', 'FontColor',labelCol, 'HorizontalAlignment','center');
            lblModH.Layout.Row=1; lblModH.Layout.Column=6;

            axisLabels = {'X','Y','Z'};
            app.BilletSizeEdits = gobjects(1,3); app.BilletSizeMinusBtns = gobjects(1,3); app.BilletSizePlusBtns = gobjects(1,3); app.BilletModelDimLabels = gobjects(1,3);

            for i = 1:3
                r = i + 1;
                lblAx = uilabel(gridBSize, 'Text', axisLabels{i}, 'FontWeight','bold', 'HorizontalAlignment','center', 'FontColor',labelCol);
                lblAx.Layout.Row = r;

                app.BilletSizeMinusBtns(i) = uibutton(gridBSize, 'Text','-', 'FontWeight','bold', 'ButtonPushedFcn', @(~,~)app.onBilletSizeStep(i,-1));
                app.BilletSizeMinusBtns(i).Layout.Row = r; app.BilletSizeMinusBtns(i).Layout.Column = 3;

                app.BilletSizeEdits(i) = uieditfield(gridBSize,'numeric', 'HorizontalAlignment','center', 'ValueDisplayFormat','%.2f', 'BackgroundColor',[0.7 0.7 0.8],'FontColor', [0 0 0], ...
                    'ValueChangedFcn', @(src,~)app.onBilletSizeEdited(i,src));
                app.BilletSizeEdits(i).Layout.Row = r; app.BilletSizeEdits(i).Layout.Column = 4;

                app.BilletSizePlusBtns(i) = uibutton(gridBSize, 'Text','+', 'FontWeight','bold', 'ButtonPushedFcn', @(~,~)app.onBilletSizeStep(i,+1));
                app.BilletSizePlusBtns(i).Layout.Row = r; app.BilletSizePlusBtns(i).Layout.Column = 5;

                app.BilletModelDimLabels(i) = uilabel(gridBSize, 'Text','(---)', 'HorizontalAlignment','center', 'BackgroundColor', t.readoutBg, 'FontColor', t.readoutTxt);
                app.BilletModelDimLabels(i).Layout.Row = r; app.BilletModelDimLabels(i).Layout.Column = 6;
            end

            % -- Position Buttons --
            app.BtnAutoPositionModel = uibutton(app.BilletLeftPanel, 'Text','Auto-position Model', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onAutoPositionModel());
            app.BtnAutoPositionModel.Layout.Row = 3;

            app.BtnResetPosition = uibutton(app.BilletLeftPanel, 'Text','Reset Position', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetPosition());
            app.BtnResetPosition.Layout.Row = 4;

            % -- Position Controls --
            pnlBPos = uipanel(app.BilletLeftPanel, 'Title','Billet Position Controls', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold');
            pnlBPos.Layout.Row = 5;

            % [FIX] Tighten spacing to fix cropping
            gridBPos = uigridlayout(pnlBPos, [4 6]);
            gridBPos.ColumnWidth = {35, 65, 20, 65, 20, 65};
            gridBPos.Padding = [4 4 4 4];
            gridBPos.ColumnSpacing = 4; % <-- ADDED

            lblAxH2 = uilabel(gridBPos, 'Text','Axis', 'FontWeight','bold', 'FontColor',labelCol, 'HorizontalAlignment','center'); lblAxH2.Layout.Row = 1;
            lblNegH = uilabel(gridBPos, 'Text','-ive Gap', 'FontWeight','bold', 'FontColor',labelCol, 'HorizontalAlignment','center'); lblNegH.Layout.Column = 2;
            lblShftH = uilabel(gridBPos, 'Text','Shift [mm]', 'FontWeight','bold', 'FontColor',labelCol, 'HorizontalAlignment','center'); lblShftH.Layout.Row=1; lblShftH.Layout.Column=[3 5];
            lblPosH = uilabel(gridBPos, 'Text','+ive Gap', 'FontWeight','bold', 'FontColor',labelCol, 'HorizontalAlignment','center'); lblPosH.Layout.Column = 6;

            app.BilletNegOffsetEdits = gobjects(1,3); app.BilletCenterOffsetEdits = gobjects(1,3); app.BilletPosOffsetEdits = gobjects(1,3);

            for k = 1:3
                rk = k + 1;
                lblAxRow = uilabel(gridBPos, 'Text', axisLabels{k}, 'FontWeight','bold', 'HorizontalAlignment','center', 'FontColor',labelCol);
                lblAxRow.Layout.Row = rk;

                app.BilletNegOffsetEdits(k) = uieditfield(gridBPos,'numeric', 'HorizontalAlignment','center', 'ValueDisplayFormat','%.2f', ...
                    'BackgroundColor',inputBg, 'FontColor', inputTxt, 'ValueChangedFcn', @(src,~)app.onBilletOffsetEdited(k,"neg",src));
                app.BilletNegOffsetEdits(k).Layout.Row = rk; app.BilletNegOffsetEdits(k).Layout.Column = 2;

                btnMinPos = uibutton(gridBPos, 'Text','-', 'FontWeight','bold', 'ButtonPushedFcn', @(~,~)app.onBilletShift(k,-0.5));
                btnMinPos.Layout.Row = rk;

                app.BilletCenterOffsetEdits(k) = uieditfield(gridBPos,'numeric', 'HorizontalAlignment','center', 'ValueDisplayFormat','%.2f', ...
                    'BackgroundColor',[0.7 0.7 0.8],'FontColor', [0 0 0], 'ValueChangedFcn', @(src,~)app.onBilletOffsetEdited(k,"center",src));
                app.BilletCenterOffsetEdits(k).Layout.Row = rk; app.BilletCenterOffsetEdits(k).Layout.Column = 4;

                btnPlusPos = uibutton(gridBPos, 'Text','+', 'FontWeight','bold', 'ButtonPushedFcn', @(~,~)app.onBilletShift(k,+0.5));
                btnPlusPos.Layout.Row = rk;

                app.BilletPosOffsetEdits(k) = uieditfield(gridBPos,'numeric', 'HorizontalAlignment','center', 'ValueDisplayFormat','%.2f', ...
                    'BackgroundColor',inputBg, 'FontColor', inputTxt, 'ValueChangedFcn', @(src,~)app.onBilletOffsetEdited(k,"pos",src));
                app.BilletPosOffsetEdits(k).Layout.Row = rk; app.BilletPosOffsetEdits(k).Layout.Column = 6;
            end

            % -- Message & Continue --
            app.BilletMessageLabel = uilabel(app.BilletLeftPanel, 'Text','', 'WordWrap','on', 'FontWeight','bold', 'FontColor', [1 1 1], 'VerticalAlignment','top');
            app.BilletMessageLabel.Layout.Row = 6;

            app.BtnBilletContinue = uibutton(app.BilletLeftPanel, 'Text','Continue', 'FontWeight','bold', 'BackgroundColor',[0.1 0.6 0.1], 'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~)app.onContinue());
            app.BtnBilletContinue.Layout.Row = 7;

            % --- Right Panel: 3 Orthographic Views ---
            app.BilletRightPanel = uigridlayout(app.GLBillet,[2 2]);
            app.BilletRightPanel.Layout.Column = 2;

            app.AxBilletTop = uiaxes(app.BilletRightPanel);
            app.AxBilletTop.Layout.Row = 1; app.AxBilletTop.Layout.Column = 1;
            app.AxBilletTop.BackgroundColor = [0.11 0.11 0.11]; title(app.AxBilletTop,'Top View (X/Y)');

            app.AxBilletFront = uiaxes(app.BilletRightPanel);
            app.AxBilletFront.Layout.Row = 2; app.AxBilletFront.Layout.Column = 1;
            app.AxBilletFront.BackgroundColor = [0.11 0.11 0.11]; title(app.AxBilletFront,'Front View (X/Z)');

            app.AxBilletRight = uiaxes(app.BilletRightPanel);
            app.AxBilletRight.Layout.Row = 2; app.AxBilletRight.Layout.Column = 2;
            app.AxBilletRight.BackgroundColor = [0.11 0.11 0.11]; title(app.AxBilletRight,'Right View (Y/Z)');


            % ===========================================================
            % TAB 4: MACHINE SETUP
            % ===========================================================
            app.TabMachine = uitab(app.TabGroup, 'Title', 'Machine');

            app.GLMachine = uigridlayout(app.TabMachine, [1 2]);
            app.GLMachine.ColumnWidth = {320, '1x'};
            app.GLMachine.Padding = [10 10 10 10];

            % --- Left Control Panel ---
            app.MachineLeftPanel = uigridlayout(app.GLMachine, [6 1]);
            app.MachineLeftPanel.RowHeight = {'fit','fit','fit','fit','1x','fit'};
            app.MachineLeftPanel.Padding = [10 10 10 10];
            app.MachineLeftPanel.BackgroundColor = sideBg;

            % -- View --
            pnlMView = uipanel(app.MachineLeftPanel, 'Title','View', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlMView.Layout.Row = 1;

            gridMView = uigridlayout(pnlMView, [1 2]); gridMView.Padding=[5 5 5 5]; gridMView.BackgroundColor=panelBg;

            btnMViewMach = uibutton(gridMView, 'Text','Machine View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetMachineViewMachine());
            btnMViewBill = uibutton(gridMView, 'Text','Billet View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetMachineViewBillet());

            % -- Placement --
            pnlMPlace = uipanel(app.MachineLeftPanel, 'Title','Billet Placement', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold');
            pnlMPlace.Layout.Row = 2;

            gridMPlace = uigridlayout(pnlMPlace, [4 2]); gridMPlace.ColumnWidth={'1x',110}; gridMPlace.Padding=[10 5 10 5]; gridMPlace.BackgroundColor=panelBg;

            lblMAx = uilabel(gridMPlace, 'Text','Axis', 'FontWeight','bold', 'FontColor',labelCol); lblMAx.Layout.Row=1;
            lblMPos = uilabel(gridMPlace, 'Text','Pos [mm]', 'FontWeight','bold', 'FontColor',labelCol); lblMPos.Layout.Column=2;

            mAxisLabels = {'X (Machine)','Y (Machine)','Z (Machine)'};
            app.MachinePosSpinners = gobjects(1,3);
            for i=1:3
                lblMAxRow = uilabel(gridMPlace, 'Text',mAxisLabels{i}, 'FontColor',labelCol);
                lblMAxRow.Layout.Row=i+1;
                app.MachinePosSpinners(i) = uispinner(gridMPlace, 'Limits',[-500 2000], 'Value',app.MachineBilletPos(i), 'ValueDisplayFormat','%.2f', 'Step',1.0, 'ValueChangedFcn',@(src,~)app.onMachinePosEdited(i,src));
                app.MachinePosSpinners(i).Layout.Row=i+1; app.MachinePosSpinners(i).Layout.Column=2;
            end

            % -- Reset --
            btnMReset = uibutton(app.MachineLeftPanel, 'Text','Reset Billet Position', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetMachineBilletPosition());
            btnMReset.Layout.Row = 3;

            % -- Message --
            app.MachineMessageLabel = uilabel(app.MachineLeftPanel, 'Text','Machine configuration valid.', 'WordWrap','on', 'FontWeight','bold', 'FontColor',[1 1 1], 'VerticalAlignment','top');
            app.MachineMessageLabel.Layout.Row = 4;

            % -- Continue --
            app.BtnMachineContinue = uibutton(app.MachineLeftPanel, 'Text','Continue', 'FontWeight','bold', 'BackgroundColor',[0.1 0.6 0.1], 'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~)app.onContinue());
            app.BtnMachineContinue.Layout.Row = 6;

            % --- Right Panel: 3D Machine Plot ---
            app.AxMachine = uiaxes(app.GLMachine); app.AxMachine.Layout.Column=2; app.AxMachine.BackgroundColor=[0.05 0.05 0.05];
            grid(app.AxMachine,'on'); view(app.AxMachine,3); hold(app.AxMachine,'on');


            % ===========================================================
            % TAB 5: CUTTING STRATEGY
            % ===========================================================
            app.TabCutting = uitab(app.TabGroup, 'Title', 'Cutting Strategy');

            app.GLCutting = uigridlayout(app.TabCutting, [2 2]);
            app.GLCutting.ColumnWidth   = {320, '1x'};
            app.GLCutting.RowHeight     = {'1x', '1x'};
            app.GLCutting.Padding       = [10 10 10 10];
            app.GLCutting.ColumnSpacing = 10;

            % --- Left Control Panel (Spans both rows) ---
            app.CuttingLeftPanel = uigridlayout(app.GLCutting, [6 1]);
            app.CuttingLeftPanel.Layout.Row     = [1 2];
            app.CuttingLeftPanel.Layout.Column  = 1;
            app.CuttingLeftPanel.RowHeight = {'fit','fit','fit','fit','1x','fit'};
            app.CuttingLeftPanel.Padding   = [10 10 10 10];
            app.CuttingLeftPanel.BackgroundColor = sideBg;

            % -- View --
            pnlCView = uipanel(app.CuttingLeftPanel, 'Title','View', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlCView.Layout.Row = 1;

            gridCView = uigridlayout(pnlCView, [1 2]); gridCView.Padding=[5 5 5 5]; gridCView.ColumnSpacing=5; gridCView.BackgroundColor=panelBg;
            btnCViewMach = uibutton(gridCView, 'Text','Machine View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetCuttingViewMachine());
            btnCViewBill = uibutton(gridCView, 'Text','Billet View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetCuttingViewBillet());

            % -- Auto Tools --
            pnlCAuto = uipanel(app.CuttingLeftPanel, 'Title','Auto Tools', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlCAuto.Layout.Row = 2;

            gridCAuto = uigridlayout(pnlCAuto, [1 2]); gridCAuto.Padding=[5 5 5 5]; gridCAuto.ColumnSpacing=5; gridCAuto.BackgroundColor=panelBg;
            app.btnAutoStart = uibutton(gridCAuto, 'Text','Auto Start', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onAutoStart());
            app.btnAutoEntry = uibutton(gridCAuto, 'Text','Auto Entry', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onAutoEntry());

            % -- Modes --
            pnlCMode = uipanel(app.CuttingLeftPanel, 'Title','Modes', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlCMode.Layout.Row = 3;

            gridCMode = uigridlayout(pnlCMode, [3 2]); gridCMode.RowHeight = {'fit','fit','fit'}; gridCMode.ColumnWidth = {75, '1x'}; gridCMode.Padding=[5 5 5 5]; gridCMode.BackgroundColor=panelBg;

            lblCDir = uilabel(gridCMode, 'Text','Direction:', 'FontColor',labelCol, 'HorizontalAlignment','right'); lblCDir.Layout.Row=1;
            app.SwitchCutDir = uiswitch(gridCMode, 'slider', 'Items',{'Top (CW)', 'Bottom (CCW)'}, 'Value','Top (CW)', 'ValueChangedFcn',@(~,~)app.onCutDirectionChanged());
            app.SwitchCutDir.Layout.Row=1; app.SwitchCutDir.Layout.Column=2;

            lblCSync = uilabel(gridCMode, 'Text','Start Pts:', 'FontColor',labelCol, 'HorizontalAlignment','right'); lblCSync.Layout.Row=2;
            app.SwitchSyncStart = uiswitch(gridCMode, 'slider', 'Items',{'Coupled', 'Independent'}, 'Value','Coupled', 'ValueChangedFcn',@(src,~)app.onSyncToggleChanged(src));
            app.SwitchSyncStart.Layout.Row=2; app.SwitchSyncStart.Layout.Column=2;

            lblCEntry = uilabel(gridCMode, 'Text','Entry Pts:', 'FontColor',labelCol, 'HorizontalAlignment','right'); lblCEntry.Layout.Row=3;
            app.SwitchSyncEntry = uiswitch(gridCMode, 'slider', 'Items',{'Coupled', 'Independent'}, 'Value','Coupled', 'ValueChangedFcn',@(src,~)app.onSyncEntryToggleChanged(src));
            app.SwitchSyncEntry.Layout.Row=3; app.SwitchSyncEntry.Layout.Column=2;

            % -- Mouse Interaction --
            pnlCInter = uipanel(app.CuttingLeftPanel, 'Title','Mouse Interaction', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlCInter.Layout.Row = 4;

            gridCInter = uigridlayout(pnlCInter, [3 1]); gridCInter.RowHeight = {'fit','fit','fit'}; gridCInter.Padding=[5 5 5 5]; gridCInter.BackgroundColor=panelBg;

            lblCInst = uilabel(gridCInter, 'Text','Click plot to set:', 'FontColor',labelCol); lblCInst.Layout.Row=1;

            bCols = app.getInteractionColors();
            gridCIB1 = uigridlayout(gridCInter, [1 2]); gridCIB1.Layout.Row=2; gridCIB1.Padding=[0 0 0 0]; gridCIB1.BackgroundColor=panelBg;
            app.BtnPickStart = uibutton(gridCIB1, 'state', 'Text','Start Pt', 'FontWeight','bold', 'BackgroundColor',bCols.StartInactive, 'FontColor',bCols.TextInactive, 'ValueChangedFcn',@(src,evt)app.onInteractionStatsChanged(src));
            app.BtnPickEntry = uibutton(gridCIB1, 'state', 'Text','Entry 1', 'FontWeight','bold', 'BackgroundColor',bCols.EntryInactive, 'FontColor',bCols.TextInactive, 'ValueChangedFcn',@(src,evt)app.onInteractionStatsChanged(src));

            gridCIB2 = uigridlayout(gridCInter, [1 2]); gridCIB2.Layout.Row=3; gridCIB2.Padding=[0 0 0 0]; gridCIB2.BackgroundColor=panelBg;
            app.BtnPickEntry2 = uibutton(gridCIB2, 'state', 'Text','Entry 2', 'FontWeight','bold', 'BackgroundColor',bCols.Entry2Inactive, 'FontColor',bCols.TextInactive, 'ValueChangedFcn',@(src,evt)app.onInteractionStatsChanged(src));
            btnCClear = uibutton(gridCIB2, 'Text','Clear Pts', 'FontWeight','bold', 'BackgroundColor',t.accentBg, 'FontColor',t.editTxt, 'ButtonPushedFcn',@(~,~)app.onClearEntries());

            % -- Spacer & Continue --
            lblCSpacer = uilabel(app.CuttingLeftPanel, 'Text', '');
            lblCSpacer.Layout.Row = 5; % Spring

            app.BtnCuttingContinue = uibutton(app.CuttingLeftPanel, 'Text','Continue', 'FontWeight','bold', 'BackgroundColor',[0.1 0.6 0.1], 'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~)app.onContinue());
            app.BtnCuttingContinue.Layout.Row = 6;

            % --- Right Panel: 2D Cut Plots ---
            app.AxCutLeft = uiaxes(app.GLCutting); app.AxCutLeft.Layout.Row=1; app.AxCutLeft.Layout.Column=2;
            app.AxCutLeft.BackgroundColor = t.editBg; grid(app.AxCutLeft,'on'); title(app.AxCutLeft,'Left Profile Cut Path');

            app.AxCutRight = uiaxes(app.GLCutting); app.AxCutRight.Layout.Row=2; app.AxCutRight.Layout.Column=2;
            app.AxCutRight.BackgroundColor = t.editBg; grid(app.AxCutRight,'on'); title(app.AxCutRight,'Right Profile Cut Path');


            % ===========================================================
            % TAB 6: SIMULATION
            % ===========================================================
            app.TabSimulation = uitab(app.TabGroup, 'Title', 'Simulation');

            app.GLSimulation = uigridlayout(app.TabSimulation, [1 2]);
            app.GLSimulation.ColumnWidth = {320, '1x'};
            app.GLSimulation.Padding = [10 10 10 10];

            % --- Left Control Panel ---
            app.SimLeftPanel = uigridlayout(app.GLSimulation, [6 1]);
            app.SimLeftPanel.RowHeight = {'fit', 'fit', 'fit', 'fit', '1x', 'fit'};
            app.SimLeftPanel.Padding = [10 10 10 10];
            app.SimLeftPanel.BackgroundColor = sideBg;

            % -- View --
            pnlSView = uipanel(app.SimLeftPanel, 'Title','View', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlSView.Layout.Row = 1;

            gridSView = uigridlayout(pnlSView, [1 2]); gridSView.Padding=[5 5 5 5]; gridSView.BackgroundColor=panelBg;
            uibutton(gridSView, 'Text','Machine View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetSimViewMachine());
            uibutton(gridSView, 'Text','Billet View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetSimViewBillet());

            % -- Playback --
            pnlSPlay = uipanel(app.SimLeftPanel, 'Title','Playback', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlSPlay.Layout.Row = 2;

            % [FIX] Explicit RowHeight to keep buttons from stretching and cropping the slider
            gridSPlay = uigridlayout(pnlSPlay, [2 3]);
            gridSPlay.ColumnWidth={'1x','1x','1x'};
            gridSPlay.RowHeight={'fit','fit'}; % <-- ADDED
            gridSPlay.Padding=[5 5 5 5];
            gridSPlay.BackgroundColor=panelBg;

            app.SimPlayBtn = uibutton(gridSPlay, 'Text','Play', 'FontWeight','bold', 'BackgroundColor',t.accentBg, 'FontColor',t.editTxt, 'ButtonPushedFcn',@(~,~)app.onSimPlay());
            uibutton(gridSPlay, 'Text','Pause', 'FontWeight','bold', 'BackgroundColor',panelBg, 'FontColor',labelCol, 'ButtonPushedFcn',@(~,~)app.onSimPause());
            app.SimStopBtn = uibutton(gridSPlay, 'Text','Reset', 'FontWeight','bold', 'BackgroundColor',panelBg, 'FontColor',labelCol, 'ButtonPushedFcn',@(~,~)app.onSimStop());

            app.SimSlider = uislider(gridSPlay, 'Limits',[1 100], 'Value',1, 'ValueChangedFcn',@(src,~)app.onSimSliderChanging(src));
            app.SimSlider.Layout.Row = 2; app.SimSlider.Layout.Column = [1 3];

            % -- Settings --
            pnlSSet = uipanel(app.SimLeftPanel, 'Title','Settings', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlSSet.Layout.Row = 3;

            gridSSet = uigridlayout(pnlSSet, [1 2]); gridSSet.ColumnWidth={'fit','1x'}; gridSSet.Padding=[5 5 5 5]; gridSSet.BackgroundColor=panelBg;

            lblSSpeed = uilabel(gridSSet, 'Text','Speed (x):', 'FontColor',labelCol, 'HorizontalAlignment','right');
            app.SimSpeedSpinner = uispinner(gridSSet, 'Limits',[0.1 10], 'Value',1.0, 'Step',0.1);

            % -- Readouts --
            pnlSCoord = uipanel(app.SimLeftPanel, 'Title','Live Coordinates', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlSCoord.Layout.Row = 4;

            gridSCoord = uigridlayout(pnlSCoord, [3 5]); gridSCoord.ColumnWidth = {'fit', 60, '1x', 'fit', 60}; gridSCoord.RowHeight = {'fit','fit','fit'}; gridSCoord.Padding = [5 5 5 5]; gridSCoord.BackgroundColor = panelBg;

            lblHeaderL = uilabel(gridSCoord, 'Text','Left Tower', 'FontWeight','bold', 'FontColor',labelCol, 'HorizontalAlignment','center'); lblHeaderL.Layout.Column = [1 2];
            lblHeaderR = uilabel(gridSCoord, 'Text','Right Tower', 'FontWeight','bold', 'FontColor',labelCol, 'HorizontalAlignment','center'); lblHeaderR.Layout.Column = [4 5];

            % [FIX] Explicit Column=1 for labels to prevent misalignment
            % Left X/Y
            lblXL = uilabel(gridSCoord, 'Text','X:', 'FontWeight','bold', 'FontColor',t.accentBg, 'HorizontalAlignment','right');
            lblXL.Layout.Row = 2; lblXL.Layout.Column = 1; % <-- Explicit
            app.LblReadoutX = uilabel(gridSCoord, 'Text','0.00', 'FontName','Monospaced', 'FontColor',labelCol, 'HorizontalAlignment','left'); app.LblReadoutX.Layout.Row=2; app.LblReadoutX.Layout.Column=2;

            lblYL = uilabel(gridSCoord, 'Text','Y:', 'FontWeight','bold', 'FontColor',t.accentBg, 'HorizontalAlignment','right');
            lblYL.Layout.Row = 3; lblYL.Layout.Column = 1; % <-- Explicit
            app.LblReadoutY = uilabel(gridSCoord, 'Text','0.00', 'FontName','Monospaced', 'FontColor',labelCol, 'HorizontalAlignment','left'); app.LblReadoutY.Layout.Row=3; app.LblReadoutY.Layout.Column=2;

            % Right Z/A
            lblZR = uilabel(gridSCoord, 'Text','Z:', 'FontWeight','bold', 'FontColor',t.accentBg, 'HorizontalAlignment','right'); lblZR.Layout.Row = 2; lblZR.Layout.Column=4;
            app.LblReadoutZ = uilabel(gridSCoord, 'Text','0.00', 'FontName','Monospaced', 'FontColor',labelCol, 'HorizontalAlignment','left'); app.LblReadoutZ.Layout.Row=2; app.LblReadoutZ.Layout.Column=5;

            lblAR = uilabel(gridSCoord, 'Text','A:', 'FontWeight','bold', 'FontColor',t.accentBg, 'HorizontalAlignment','right'); lblAR.Layout.Row = 3; lblAR.Layout.Column=4;
            app.LblReadoutA = uilabel(gridSCoord, 'Text','0.00', 'FontName','Monospaced', 'FontColor',labelCol, 'HorizontalAlignment','left'); app.LblReadoutA.Layout.Row=3; app.LblReadoutA.Layout.Column=5;

            % -- Generate G-Code --
            lblSSpacer = uilabel(app.SimLeftPanel, 'Text', '');
            lblSSpacer.Layout.Row = 5; % Spring

            % 6. CONTINUE (Updated to match other tabs)
            app.BtnSimContinue = uibutton(app.SimLeftPanel, 'Text','Continue', ...
                'FontWeight','bold', 'BackgroundColor',[0.1 0.6 0.1], 'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~)app.onContinue());
            app.BtnSimContinue.Layout.Row = 6;

            % --- Right Panel: 3D Sim Plot ---
            app.AxSim = uiaxes(app.GLSimulation); app.AxSim.Layout.Column = 2; app.AxSim.BackgroundColor = [0.05 0.05 0.05];
            xlabel(app.AxSim,'X'); ylabel(app.AxSim,'Y'); zlabel(app.AxSim,'Z'); grid(app.AxSim,'on'); view(app.AxSim, 3); axis(app.AxSim, 'equal');

            % ===========================================================
            % 7. POST-PROCESSOR TAB
            % ===========================================================
            app.TabPostProcess = uitab(app.TabGroup, 'Title', 'Post-Process');

            app.GLPostProcess = uigridlayout(app.TabPostProcess, [1 2]);
            app.GLPostProcess.ColumnWidth   = {320, '1x'};
            app.GLPostProcess.Padding       = [10 10 10 10];

            % --- Left Control Panel ---
            app.PostLeftPanel = uigridlayout(app.GLPostProcess, [6 1]);
            app.PostLeftPanel.RowHeight = {'fit', 'fit', 'fit', '1x', 'fit', 'fit'};
            app.PostLeftPanel.Padding = [10 10 10 10];
            app.PostLeftPanel.BackgroundColor = sideBg;

            % 1. VIEW CONTROLS
            panPView = uipanel(app.PostLeftPanel, 'Title','View', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            panPView.Layout.Row = 1;

            gridPView = uigridlayout(panPView, [1 2]); gridPView.Padding=[5 5 5 5]; gridPView.BackgroundColor=panelBg;
            btnPVM = uibutton(gridPView, 'Text','Machine View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetPostViewMachine());
            btnPVB = uibutton(gridPView, 'Text','Billet View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetPostViewBillet());

            % 2. SETTINGS (Feed & Power)
            panPSettings = uipanel(app.PostLeftPanel, 'Title','Cutting Parameters', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            panPSettings.Layout.Row = 2;

            gridPSet = uigridlayout(panPSettings, [2 2]);
            gridPSet.ColumnWidth={'1x', 80};
            gridPSet.Padding=[5 5 5 5]; gridPSet.BackgroundColor=panelBg;

            % Feed Rate
            lblFeed = uilabel(gridPSet, 'Text','Feed Rate [mm/min]:', 'FontColor',labelCol, 'HorizontalAlignment','right');
            lblFeed.Layout.Row=1; lblFeed.Layout.Column=1;

            app.SpinFeedRate = uispinner(gridPSet, 'Limits',[20 200], 'Value',100, 'Step',5, 'ValueDisplayFormat','%.0f');
            app.SpinFeedRate.Layout.Row=1; app.SpinFeedRate.Layout.Column=2;

            % Power
            lblPower = uilabel(gridPSet, 'Text','Hot Wire Power [%]:', 'FontColor',labelCol, 'HorizontalAlignment','right');
            lblPower.Layout.Row=2; lblPower.Layout.Column=1;

            app.SpinPower = uispinner(gridPSet, 'Limits',[20 100], 'Value',60, 'Step',5, 'ValueDisplayFormat','%.0f');
            app.SpinPower.Layout.Row=2; app.SpinPower.Layout.Column=2;

            % 3. EXPORT
            panPExport = uipanel(app.PostLeftPanel, 'Title','Export', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            panPExport.Layout.Row = 3;

            gridPExp = uigridlayout(panPExport, [3 1]);
            gridPExp.RowHeight={'fit','fit','fit'};
            gridPExp.Padding=[5 5 5 5]; gridPExp.BackgroundColor=panelBg;

            % Filename
            lblFile = uilabel(gridPExp, 'Text','Filename:', 'FontColor',labelCol);
            app.FieldFilename = uieditfield(gridPExp, 'text', 'Value', 'GCode-V1-Output.gcode');

            % Process Button
            app.BtnPostProcess = uibutton(gridPExp, 'Text','Post-Process', 'FontWeight','bold', ...
                'BackgroundColor',t.accentBg, 'FontColor',t.editTxt, 'ButtonPushedFcn',@(~,~)app.onPostProcess());
            
            % 4. G-CODE VIEWER (scroll + click lines)
            app.PanelGCode = uipanel(app.PostLeftPanel, 'Title','G-Code', ...
                'FontWeight','bold', 'BorderType','line');
            app.PanelGCode.Layout.Row = 4;

            app.GridGCode = uigridlayout(app.PanelGCode, [2 2]);
            app.GridGCode.RowHeight = {'1x', 28};
            app.GridGCode.ColumnWidth = {'1x','1x'};
            app.GridGCode.Padding = [5 5 5 5];

            app.ListGCode = uilistbox(app.GridGCode, ...
                'Items', {'(Generate to view G-code...)'}, ...
                'ValueChangedFcn', @(src,~)app.onPostLineSelected(src));
            app.ListGCode.Layout.Row = 1;
            app.ListGCode.Layout.Column = [1 2];
            app.ListGCode.FontName = 'Courier New';

            app.BtnGCodePrev = uibutton(app.GridGCode,'push','Text','◀ Prev', ...
                'ButtonPushedFcn', @(~,~)app.stepPostLine(-1));
            app.BtnGCodePrev.Layout.Row = 2;
            app.BtnGCodePrev.Layout.Column = 1;

            app.BtnGCodeNext = uibutton(app.GridGCode,'push','Text','Next ▶', ...
                'ButtonPushedFcn', @(~,~)app.stepPostLine(+1));
            app.BtnGCodeNext.Layout.Row = 2;
            app.BtnGCodeNext.Layout.Column = 2;

            % 5. SPACER
            lblPSpacer = uilabel(app.PostLeftPanel, 'Text', '');
            lblPSpacer.Layout.Row = 5;

            % 5. SAVE BUTTON
            app.BtnSaveGCode = uibutton(app.PostLeftPanel, 'Text','Save G-Code', 'FontWeight','bold', ...
                'BackgroundColor',[0.1 0.6 0.1], 'FontColor',[1 1 1], 'Enable','off', ...
                'ButtonPushedFcn',@(~,~)app.onSaveGCode());
            app.BtnSaveGCode.Layout.Row = 6;

            % RIGHT PANEL (Plot Placeholder)
            app.AxPost = uiaxes(app.GLPostProcess);
            app.AxPost.Layout.Column = 2;
            app.AxPost.BackgroundColor = [0.05 0.05 0.05];
            xlabel(app.AxPost,'X'); ylabel(app.AxPost,'Y'); zlabel(app.AxPost,'Z');
            grid(app.AxPost,'on'); view(app.AxPost,3); axis(app.AxPost,'equal');

            % --- Final Theme Application ---
            app.applyTheme();

        end

        % ===========================================================
        % STATE & PROFILE HELPERS
        % ===========================================================
        function clearPlanes(app)
            % Deletes any existing plane graphics and resets handles
            if ~isempty(app.LeftPlanePatch) && isgraphics(app.LeftPlanePatch)
                delete(app.LeftPlanePatch);
            end
            if ~isempty(app.RightPlanePatch) && isgraphics(app.RightPlanePatch)
                delete(app.RightPlanePatch);
            end
            if ~isempty(app.LeftPlaneText) && isgraphics(app.LeftPlaneText)
                delete(app.LeftPlaneText);
            end
            if ~isempty(app.RightPlaneText) && isgraphics(app.RightPlaneText)
                delete(app.RightPlaneText);
            end

            app.LeftPlanePatch  = gobjects(0);
            app.RightPlanePatch = gobjects(0);
            app.LeftPlaneText   = gobjects(0);
            app.RightPlaneText  = gobjects(0);
        end

        function clearProfiles(app)
            % Deletes any existing profile graphics and clears stored data
            if ~isempty(app.LeftProfileLine3D) && isgraphics(app.LeftProfileLine3D)
                delete(app.LeftProfileLine3D);
            end
            if ~isempty(app.RightProfileLine3D) && isgraphics(app.RightProfileLine3D)
                delete(app.RightProfileLine3D);
            end

            app.LeftProfileLine3D  = gobjects(0);
            app.RightProfileLine3D = gobjects(0);
            app.LeftProfilePoints  = [];
            app.RightProfilePoints = [];
        end

        function clearProfiles2D(app)
            % Deletes 2D profile lines on the Profiles tab

            % Main resampled profiles
            if ~isempty(app.LeftProfile2DLine) && isgraphics(app.LeftProfile2DLine)
                delete(app.LeftProfile2DLine);
            end
            if ~isempty(app.RightProfile2DLine) && isgraphics(app.RightProfile2DLine)
                delete(app.RightProfile2DLine);
            end

            % Faint raw mesh slice overlays
            if ~isempty(app.LeftProfile2DMeshLine) && isgraphics(app.LeftProfile2DMeshLine)
                delete(app.LeftProfile2DMeshLine);
            end
            if ~isempty(app.RightProfile2DMeshLine) && isgraphics(app.RightProfile2DMeshLine)
                delete(app.RightProfile2DMeshLine);
            end

            % Kerf paths
            if ~isempty(app.LeftKerf2DLine) && isgraphics(app.LeftKerf2DLine)
                delete(app.LeftKerf2DLine);
            end
            if ~isempty(app.RightKerf2DLine) && isgraphics(app.RightKerf2DLine)
                delete(app.RightKerf2DLine);
            end

            % Reset graphics handles only
            app.LeftProfile2DLine      = gobjects(0);
            app.RightProfile2DLine     = gobjects(0);
            app.LeftProfile2DMeshLine  = gobjects(0);
            app.RightProfile2DMeshLine = gobjects(0);
            app.LeftKerf2DLine         = gobjects(0);
            app.RightKerf2DLine        = gobjects(0);

            % NOTE:
            % We deliberately do NOT change app.KerfEnabled or the
            % 'Continue' button state here. This is a graphics-only function.
            % Logic resets (like rotation or plane movement) should call
            % app.invalidateKerf() instead.

        end

        function clearKerfPaths(app)
            % Delete only the kerf paths on the Profiles tab.
            if ~isempty(app.LeftKerf2DLine) && isgraphics(app.LeftKerf2DLine)
                delete(app.LeftKerf2DLine);
            end
            if ~isempty(app.RightKerf2DLine) && isgraphics(app.RightKerf2DLine)
                delete(app.RightKerf2DLine);
            end
            app.LeftKerf2DLine  = gobjects(0);
            app.RightKerf2DLine = gobjects(0);
        end

        function invalidateKerf(app)
            % This is the "Central Reset" for Kerf logic
            app.KerfEnabled = false;
            app.clearKerfPaths();

            % Mute the Continue button
            if ~isempty(app.BtnProfilesContinue) && isgraphics(app.BtnProfilesContinue)
                app.BtnProfilesContinue.Enable = 'off';
                app.BtnProfilesContinue.BackgroundColor = [0.3 0.3 0.3];
                app.BtnProfilesContinue.FontColor       = [0.8 0.8 0.8];
            end
        end

        function enterState0(app)
            % STATE 0: model only, no planes, no profiles
            app.AppState = 0;

            % Clear planes and profiles
            app.clearPlanes();
            app.clearProfiles();
            app.clearProfiles2D();
            app.invalidateKerf();

            % Continue button disabled and visually muted
            if ~isempty(app.BtnContinue) && isgraphics(app.BtnContinue)
                app.BtnContinue.Enable          = 'off';
                app.BtnContinue.BackgroundColor = [0.3 0.3 0.3];
                app.BtnContinue.FontColor       = [0.8 0.8 0.8];
            end
        end

        function enterState1(app)
            % STATE 1: planes + profiles are live
            if isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch)
                return; % no model → nothing to do
            end

            app.AppState = 1;

            % Continue button becomes active
            if ~isempty(app.BtnContinue) && isgraphics(app.BtnContinue)
                app.BtnContinue.Enable          = 'on';
                app.BtnContinue.BackgroundColor = [0.1 0.6 0.1];
                app.BtnContinue.FontColor       = [1 1 1];
            end

            % Draw planes (and indirectly profiles once computeProfiles is wired)
            app.updatePlanes();
        end

        function computeProfiles(app)
            % Compute and plot intersection profiles for left/right planes.
            if app.AppState == 0 || isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch), return; end

            t = app.getTheme();
            isTaper = strcmp(app.TaperToggle.Value,'Tapered');
            app.clearProfiles(); app.clearProfiles2D(); 
            app.SelectedStartIdxL = 1; app.SelectedStartIdxR = 1;
            V = app.ModelPatch.Vertices; F = app.ModelPatch.Faces;
            spanX = max(V(:,1)) - min(V(:,1)); epsX = 1e-6 * max(spanX, 1);

            xLeft  = app.ModelXMin + app.NumLeftOffset.Value;
            xRight = app.ModelXMin + app.NumRightOffset.Value;

            % --- 2. EXTRACT RAW LOOPS ---
            [xsL, ysL, zsL] = HotWireSTEPApp_v6_helpers.sliceMeshAtX(V, F, xLeft + epsX);
            if ~isempty(ysL) && any(~isnan(ysL)), app.LeftProfileRawYZ = [ysL(:), zsL(:)]; end
            [yLoopL, zLoopL] = HotWireSTEPApp_v6_helpers.buildMainProfileLoop(xsL, ysL, zsL);

            yLoopR = []; zLoopR = [];
            if isTaper
                [xsR, ysR, zsR] = HotWireSTEPApp_v6_helpers.sliceMeshAtX(V, F, xRight - epsX);
                if ~isempty(ysR) && any(~isnan(ysR)), app.RightProfileRawYZ = [ysR(:), zsR(:)]; end
                [yLoopR, zLoopR] = HotWireSTEPApp_v6_helpers.buildMainProfileLoop(xsR, ysR, zsR);
            end

            % --- 3. RESAMPLING LOGIC ---
            if ~isTaper
                % STRAIGHT MODE identity
                if ~isempty(yLoopL)
                    [yLoopL, zLoopL] = HotWireSTEPApp_v6_helpers.resampleProfileByTolerance(yLoopL, zLoopL, app.ProfileTolerance);
                    [yLoopL, zLoopL] = HotWireSTEPApp_v6_helpers.reorderLoopByMinY(yLoopL, zLoopL);
                end
                yLoopR = yLoopL; zLoopR = zLoopL;
            else
                % TAPERED MODE sync
                if ~isempty(yLoopL) && ~isempty(yLoopR)
                    [yLoopL, zLoopL, yLoopR, zLoopR] = HotWireSTEPApp_v6_helpers.resampleProfilesSynced(...
                        yLoopL, zLoopL, yLoopR, zLoopR, app.ProfileTolerance);

                    % Crucial: reorder both independently AFTER sync to align starting clock position
                    [yLoopL, zLoopL] = HotWireSTEPApp_v6_helpers.reorderLoopByMinY(yLoopL, zLoopL);
                    [yLoopR, zLoopR] = HotWireSTEPApp_v6_helpers.reorderLoopByMinY(yLoopR, zLoopR);
                end
            end

            % --- 4. DATA STORAGE & PLOTTING ---
            if ~isempty(yLoopL)
                xVecL = xLeft * ones(numel(yLoopL),1);
                app.LeftProfileLine3D = plot3(app.AxModel, xVecL, yLoopL, zLoopL, 'Color', t.planeRed, 'LineWidth', 1.4);
                app.LeftProfilePoints = [xVecL, yLoopL, zLoopL];
            else, app.LeftProfilePoints = []; end

            if ~isempty(yLoopR)
                xVecR = xRight * ones(numel(yLoopR),1);
                app.RightProfileLine3D = plot3(app.AxModel, xVecR, yLoopR, zLoopR, 'Color', t.planeGreen, 'LineWidth', 1.4);
                app.RightProfilePoints = [xVecR, yLoopR, zLoopR];
            else, app.RightProfilePoints = []; end

            % Update UI Readouts
            nL = 0; nR = 0;
            if ~isempty(app.LeftProfilePoints), nL = size(app.LeftProfilePoints,1); end
            if ~isempty(app.RightProfilePoints), nR = size(app.RightProfilePoints,1); end

            if ~isempty(app.ProfilePointCountLabel) && isgraphics(app.ProfilePointCountLabel)
                app.ProfilePointCountLabel.Text = sprintf('Number of Points (L/R): %d / %d', nL, nR);
            end

            app.updateProfiles2D(yLoopL, zLoopL, yLoopR, zLoopR, xLeft, xRight);
            drawnow limitrate nocallbacks;

            % --- FINAL SYNC DIAGNOSTIC ---
            if ~isempty(app.LeftProfilePoints) && ~isempty(app.RightProfilePoints)
                v = app.RightProfilePoints(:,2:3) - app.LeftProfilePoints(:,2:3);
                % On a straight model, the variance in this vector should be near ZERO
                drift = max(v) - min(v);
                fprintf('Sync Debug: Points=%d, Y-Drift=%.4fmm, Z-Drift=%.4fmm\n', ...
                    size(v,1), drift(1), drift(2));
            end
        end

        function updateProfiles2D(app, yL, zL, yR, zR, xLeft, xRight)
            % Draw 2D Y–Z profiles on the Profiles tab with shared scaling.

            if isempty(app.AxLeftProfile) || ~isgraphics(app.AxLeftProfile) ...
                    || isempty(app.AxRightProfile) || ~isgraphics(app.AxRightProfile)
                return;
            end

            % If no profiles, nothing to show
            if isempty(yL) && isempty(yR)
                return;
            end

            % Axis limits: union of left & right, with padding
            yAll = [yL(:); yR(:)];
            zAll = [zL(:); zR(:)];

            if isempty(yAll) || isempty(zAll)
                return;
            end

            yMin = min(yAll); yMax = max(yAll);
            zMin = min(zAll); zMax = max(zAll);

            dy = yMax - yMin;
            dz = zMax - zMin;
            if dy <= 0, dy = 1; end
            if dz <= 0, dz = 1; end

            padY = 0.1 * dy;
            padZ = 0.1 * dz;

            yLim = [yMin - padY, yMax + padY];
            zLim = [zMin - padZ, zMax + padZ];

            % --- GET CENTRALIZED THEME ---
            t = app.getTheme();

            % Clear only profile lines (labels/titles persist)
            app.clearProfiles2D();

            % ----- LEFT AXIS -----
            hold(app.AxLeftProfile,'on');

            % Raw mesh slice (background - turns Black in Light Mode)
            if ~isempty(app.LeftProfileRawYZ)
                rawL = app.LeftProfileRawYZ;
                app.LeftProfile2DMeshLine = plot(app.AxLeftProfile, ...
                    rawL(:,1), rawL(:,2), ...
                    'Color', t.rawMeshCol, ...
                    'LineStyle',':', ...
                    'LineWidth',2.5);
            end

            % Resampled main loop (geometry, no kerf)
            if ~isempty(yL)
                app.LeftProfile2DLine = plot(app.AxLeftProfile, ...
                    yL, zL, ...
                    'Color', t.planeRed, ...
                    'LineWidth',0.75);
            end

            % Kerf-compensated path (wire centreline)
            if app.KerfEnabled && ~isempty(yL) && app.KerfValue > 0
                [yKerfL, zKerfL] = HotWireSTEPApp_v6_helpers.offsetProfileLoop( ...
                    yL, zL, app.KerfValue);

                app.LeftKerf2DLine = plot(app.AxLeftProfile, ...
                    yKerfL, zKerfL, ...
                    'Color', t.wireKerf, ...
                    'LineWidth',0.75);
            end

            hold(app.AxLeftProfile,'off');

            % ----- RIGHT AXIS -----
            hold(app.AxRightProfile,'on');

            if ~isempty(app.RightProfileRawYZ)
                rawR = app.RightProfileRawYZ;
                app.RightProfile2DMeshLine = plot(app.AxRightProfile, ...
                    rawR(:,1), rawR(:,2), ...
                    'Color', t.rawMeshCol, ...
                    'LineStyle',':', ...
                    'LineWidth',2.5);
            end

            if ~isempty(yR)
                app.RightProfile2DLine = plot(app.AxRightProfile, ...
                    yR, zR, ...
                    'Color', t.planeGreen, ...
                    'LineWidth',0.75);
            end

            if app.KerfEnabled && ~isempty(yR) && app.KerfValue > 0
                [yKerfR, zKerfR] = HotWireSTEPApp_v6_helpers.offsetProfileLoop( ...
                    yR, zR, app.KerfValue);
                app.RightKerf2DLine = plot(app.AxRightProfile, ...
                    yKerfR, zKerfR, ...
                    'Color', t.wireKerf, ...
                    'LineWidth',0.75);
            end

            hold(app.AxRightProfile,'off');

            % Legend / key for left profile
            leftLegendHandles = gobjects(0);
            leftLegendLabels  = {};

            if ~isempty(app.LeftProfile2DMeshLine) && isgraphics(app.LeftProfile2DMeshLine)
                leftLegendHandles(end+1) = app.LeftProfile2DMeshLine;
                leftLegendLabels{end+1}  = 'Model mesh slice';
            end
            if ~isempty(app.LeftProfile2DLine) && isgraphics(app.LeftProfile2DLine)
                leftLegendHandles(end+1) = app.LeftProfile2DLine;
                leftLegendLabels{end+1}  = 'Extracted cutting profile';
            end
            if ~isempty(app.LeftKerf2DLine) && isgraphics(app.LeftKerf2DLine)
                leftLegendHandles(end+1) = app.LeftKerf2DLine;
                leftLegendLabels{end+1}  = 'Kerf path';
            end

            if ~isempty(leftLegendHandles)
                lgdL = legend(app.AxLeftProfile, leftLegendHandles, leftLegendLabels, ...
                    'Location','northeast');
                lgdL.Box = 'off';
            end

            % Legend / key for right profile
            rightLegendHandles = gobjects(0);
            rightLegendLabels  = {};

            if ~isempty(app.RightProfile2DMeshLine) && isgraphics(app.RightProfile2DMeshLine)
                rightLegendHandles(end+1) = app.RightProfile2DMeshLine;
                rightLegendLabels{end+1}  = 'Model mesh slice';
            end
            if ~isempty(app.RightProfile2DLine) && isgraphics(app.RightProfile2DLine)
                rightLegendHandles(end+1) = app.RightProfile2DLine;
                rightLegendLabels{end+1}  = 'Extracted cutting profile';
            end
            if ~isempty(app.RightKerf2DLine) && isgraphics(app.RightKerf2DLine)
                rightLegendHandles(end+1) = app.RightKerf2DLine;
                rightLegendLabels{end+1}  = 'Kerf path';
            end
            if ~isempty(rightLegendHandles)
                lgdR = legend(app.AxRightProfile, rightLegendHandles, rightLegendLabels, ...
                    'Location','northeast');
                lgdR.Box = 'off';
            end

            % Shared limits (only reset when not locked)
            if ~app.ProfileAxesLocked
                xlim(app.AxLeftProfile,  yLim);
                ylim(app.AxLeftProfile,  zLim);
                xlim(app.AxRightProfile, yLim);
                ylim(app.AxRightProfile, zLim);
            end

            % Always keep Y–Z true-scale, even after zoom / tolerance changes
            daspect(app.AxLeftProfile, [1 1 1]);
            daspect(app.AxRightProfile,[1 1 1]);

            % Titles / labels (use offsets relative to model left face)
            offsetLeft  = app.NumLeftOffset.Value;
            offsetRight = app.NumRightOffset.Value;

            title(app.AxLeftProfile,  sprintf('Left Profile  (X offset = %.2f mm)',  offsetLeft));
            title(app.AxRightProfile, sprintf('Right Profile (X offset = %.2f mm)', offsetRight));
            xlabel(app.AxLeftProfile,'Y (mm)');
            ylabel(app.AxLeftProfile,'Z (mm)');
            xlabel(app.AxRightProfile,'Y (mm)');
            ylabel(app.AxRightProfile,'Z (mm)');

            grid(app.AxLeftProfile,'on');
            grid(app.AxRightProfile,'on');
        end

        function resetProfilesView(app)
            % Reset Profiles tab axes limits to fit current profiles.
            % Uses stored LeftProfilePoints / RightProfilePoints so it
            % does not trigger a full recompute.

            if isempty(app.AxLeftProfile) || ~isgraphics(app.AxLeftProfile) ...
                    || isempty(app.AxRightProfile) || ~isgraphics(app.AxRightProfile)
                return;
            end

            yL = [];
            zL = [];
            yR = [];
            zR = [];
            xLeft  = 0;
            xRight = 0;

            if ~isempty(app.LeftProfilePoints)
                yL    = app.LeftProfilePoints(:,2);
                zL    = app.LeftProfilePoints(:,3);
                xLeft = app.LeftProfilePoints(1,1);
            end

            if ~isempty(app.RightProfilePoints)
                yR     = app.RightProfilePoints(:,2);
                zR     = app.RightProfilePoints(:,3);
                xRight = app.RightProfilePoints(1,1);
            end

            if isempty(yL) && isempty(yR)
                return;
            end

            % Force a full relimit of axes
            app.ProfileAxesLocked = false;
            app.updateProfiles2D(yL, zL, yR, zR, xLeft, xRight);
        end

        function updateProfilePointCountLabel(app, nLeft, nRight, capLeft, capRight)
            % Update the read-only "Points (L/R)" label in the Profiles tab.

            if nargin < 2, nLeft  = 0; end
            if nargin < 3, nRight = 0; end
            if nargin < 4, capLeft  = false; end
            if nargin < 5, capRight = false; end

            if isempty(app.ProfilePointCountLabel) || ~isgraphics(app.ProfilePointCountLabel)
                return;
            end

            if nLeft <= 0 && nRight <= 0
                txt = 'Number of Points (L/R): -- / --';
            else
                txt = sprintf('Number of Points (L/R): %d / %d', nLeft, nRight);
            end

            if capLeft || capRight
                txt = [txt '  (max points reached)'];
                % For now, just warn to the command window. Later we can route
                % this into the collapsible "messages/help" panel.
                warning('ProfileSampler:PointCapHit', ...
                    'Profile point cap reached; further reductions in tolerance will not add detail.');
            end

            app.ProfilePointCountLabel.Text = txt;
        end

        function onTaperModeChanged(app)

            if isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch)
                return;
            end

            % Re-run planes + profiles under the new taper mode
            app.invalidateKerf();
            app.updatePlanes();  % will call computeProfiles() in STATE 1

        end

        % ===========================================================
        % TAB CHANGE HANDLER
        % ===========================================================
        function onTabChanged(app, ~, evt)
            % 1. Always reset interaction state when changing tabs
            app.resetInteractionState();

            % 2. Tab Specific Logic
            if evt.NewValue == app.TabBillet
                app.syncBilletUI();
                app.refreshBilletPlots();
            elseif evt.NewValue == app.TabMachine
                app.onResetMachineBilletPosition();
            elseif evt.NewValue == app.TabCutting
                app.onAutoStart();
                app.onAutoEntry();
                app.updateCuttingPlots();
                app.onResetCuttingViewBillet();
            elseif evt.NewValue == app.TabSimulation
                app.applyTheme();
                app.generateSimulationData();
            elseif evt.NewValue == app.TabPostProcess
                app.updatePostProcessUI();
            end
        end

        function onProfileToleranceChanged(app, src)
            % Update stored profile tolerance and recompute profiles if active,
            % preserving any active kerf and current zoom/pan on the Profiles tab.

            val = src.Value;
            if ~isfinite(val) || val <= 0
                % Revert to previous good value
                src.Value = app.ProfileTolerance;
                return;
            end

            app.ProfileTolerance = val;

            % If we're already in STATE 1 (planes + profiles live),
            % recompute profiles (and kerf if enabled) without resetting zoom.
            if app.AppState == 1 && ~isempty(app.ModelPatch) && isgraphics(app.ModelPatch)
                app.ProfileAxesLocked = true;
                app.updatePlanes();           % calls computeProfiles() -> updateProfiles2D()
                app.ProfileAxesLocked = false;
            end
        end

        function onResetProfileTolerance(app)
            % Reset profile tolerance to its default and refresh profiles
            % without resetting the Profiles tab zoom/pan.
            defaultTol = HotWireSTEPApp_v6_2.DefaultProfileTolerance;
            app.ProfileTolerance = defaultTol;

            if ~isempty(app.ProfileTolSpinner) && isgraphics(app.ProfileTolSpinner)
                app.ProfileTolSpinner.Value = defaultTol;
            end

            % Recompute profiles (and kerf if enabled) but keep zoom.
            if app.AppState == 1 && ~isempty(app.ModelPatch) && isgraphics(app.ModelPatch)
                app.ProfileAxesLocked = true;
                app.updatePlanes();
                app.ProfileAxesLocked = false;
            end
        end

        function onKerfChanged(app, src)
            % Update stored kerf value and refresh profiles without
            % resetting the Profiles tab zoom/pan.
            val = src.Value;
            if ~isfinite(val) || val < 0
                % Kerf must be >= 0; revert to previous
                src.Value = app.KerfValue;
                return;
            end

            app.KerfValue = val;

            % If we're already in STATE 1 (planes + profiles live),
            % recompute profiles (and kerf) but keep current zoom.
            if app.AppState == 1 && ~isempty(app.ModelPatch) && isgraphics(app.ModelPatch)
                app.ProfileAxesLocked = true;
                app.updatePlanes();           % will call computeProfiles() -> updateProfiles2D()
                app.ProfileAxesLocked = false;
            end
        end

        function onApplyKerf(app)
            % Enable kerf drawing and (re)draw kerf paths based on the
            % currently extracted profiles, WITHOUT changing zoom/pan.

            if isempty(app.LeftProfilePoints) && isempty(app.RightProfilePoints)
                % No profiles yet (user hasn't generated them)
                return;
            end

            app.KerfEnabled = true;

            % --- ACTIVATE CONTINUE BUTTON ---
            app.BtnProfilesContinue.Enable = 'on';
            app.BtnProfilesContinue.BackgroundColor = [0.1 0.6 0.1]; % Light up Green
            app.BtnProfilesContinue.FontColor       = [1 1 1];

            % Use the stored 3D profile points to rebuild the 2D view.
            yL = []; zL = []; xLeft  = 0;
            yR = []; zR = []; xRight = 0;

            if ~isempty(app.LeftProfilePoints)
                xLeft = app.LeftProfilePoints(1,1);
                yL    = app.LeftProfilePoints(:,2);
                zL    = app.LeftProfilePoints(:,3);
            end

            if ~isempty(app.RightProfilePoints)
                xRight = app.RightProfilePoints(1,1);
                yR     = app.RightProfilePoints(:,2);
                zR     = app.RightProfilePoints(:,3);
            end

            % Just update the 2D plots; keep current zoom.
            app.ProfileAxesLocked = true;
            app.updateProfiles2D(yL, zL, yR, zR, xLeft, xRight);
            app.ProfileAxesLocked = false;
        end

        % ===========================================================
        % IMPORT STEP / STL
        % ===========================================================
        function onImportSTEP(app)
            [file,path] = uigetfile({'*.step;*.stp'},'Select STEP file');
            if isequal(file,0), return; end

            d = uiprogressdlg(app.UIFigure, ...
                'Title','Loading STEP File...', ...
                'Message','Converting and loading model. Please wait...', ...
                'Indeterminate','on');

            try
                app.CurrentModelName = string(file);

                % NOTE: STEP import is now handled by the helpers class
                [V,F] = HotWireSTEPApp_v6_helpers.importSTEP_FreeCAD( ...
                    fullfile(path,file), app.FreeCADExe);
                if isempty(V)
                    close(d);
                    return;
                end

                app.ModelVerticesOriginal = V;

                % Reset rotation
                app.RotAngles = [0 0 0];
                for i = 1:3
                    app.RotEdit(i).Value = 0;
                end

                % Reset plane offsets (will be updated from model extents)
                app.NumLeftOffset.Value  = 0;
                app.NumRightOffset.Value = 0;

                app.plotMesh(V,F);

            catch ME
                close(d);
                rethrow(ME);
            end

            app.enterState0();
            close(d);
        end

        function onImportSTL(app)
            [file,path] = uigetfile({'*.stl'},'Select STL file');
            if isequal(file,0), return; end

            d = uiprogressdlg(app.UIFigure, ...
                'Title','Loading STL File...', ...
                'Message','Reading mesh. Please wait...', ...
                'Indeterminate','on');

            try
                raw = stlread(fullfile(path,file));
                if isa(raw,"triangulation")
                    F = raw.ConnectivityList;
                    V = raw.Points;
                else
                    [F,V] = stlread(fullfile(path,file));
                end
                V = double(V); F = double(F);

                app.CurrentModelName      = string(file);
                app.ModelVerticesOriginal = V;

                app.RotAngles = [0 0 0];
                for i = 1:3
                    app.RotEdit(i).Value = 0;
                end

                app.NumLeftOffset.Value  = 0;
                app.NumRightOffset.Value = 0;

                app.plotMesh(V,F);

            catch ME
                close(d);
                rethrow(ME);
            end

            app.enterState0();
            close(d);
        end

        % ===========================================================
        % PLOTTING (MODEL + PLANES)
        % ===========================================================
        function plotMesh(app,V,F)
            cla(app.AxModel);

            app.ModelPatch = patch(app.AxModel, ...
                'Vertices',V,'Faces',F, ...
                'FaceColor',[0.7 0.7 0.8], ...
                'FaceAlpha',0.6, ...
                'EdgeColor',[0.3 0.3 0.4], ...
                'EdgeAlpha',0.5, ...
                'LineStyle','-', ...
                'LineWidth',0.6);

            if strlength(app.CurrentModelName) > 0
                app.FileLabel.Text = "Current File: " + app.CurrentModelName;
            else
                app.FileLabel.Text = "Current File: ---";
            end

            xlabel(app.AxModel,'X (mm)','FontWeight','bold');
            ylabel(app.AxModel,'Y (mm)','FontWeight','bold');
            zlabel(app.AxModel,'Z (mm)','FontWeight','bold');

            grid(app.AxModel,'on');
            view(app.AxModel,3);

            delete(findall(app.AxModel,'Type','light'));
            camlight(app.AxModel,'headlight');
            lighting(app.AxModel,'gouraud');

            app.autoFitView();
            drawnow;
            app.captureHomeView();

            % Update model X bounds and default plane offsets
            app.updateModelBoundsAndDefaultOffsets();

            % Compute initial billet defaults from this mesh
            app.updateBilletDefaultsFromMesh();

            % Capture the "Home" position for the Billet tab
            app.BilletRefXMin = app.ModelXMin;
            app.BilletRefYMin = app.ModelYMin;
            app.BilletRefZMin = app.ModelZMin;

        end

        function autoFitView(app)
            if isempty(app.ModelPatch) || ~isvalid(app.ModelPatch), return; end

            % 1. Get geometry bounds from physical vertices
            V      = app.ModelPatch.Vertices;
            mins   = min(V,[],1);
            maxs   = max(V,[],1);
            center = mean([mins; maxs],1);
            span   = max(maxs - mins);
            if span <= 0, span = 1; end

            % 2. Apply limits with padding
            pad = app.AutoFitPaddingFactor * span;
            xlim(app.AxModel, [mins(1)-pad, maxs(1)+pad]);
            ylim(app.AxModel, [mins(2)-pad, maxs(2)+pad]);
            zlim(app.AxModel, [mins(3)-pad, maxs(3)+pad]);

            % --- RE-STABILIZE VIEWPORT (Fix for Reset button) ---
            % Lock 1:1:1 internal scaling
            app.AxModel.DataAspectRatio = [1 1 1];
            app.AxModel.DataAspectRatioMode = 'manual';

            % Allow the axes box to match model proportions (prevents squashing)
            app.AxModel.PlotBoxAspectRatioMode = 'auto';

            % Point camera at centroid
            app.AxModel.CameraTarget = center;
            app.AxModel.CameraUpVector = [0 0 1];

            % Move camera to comfortable distance based on model span
            camPos = app.AxModel.CameraPosition;
            dirVec = (camPos - center) / norm(camPos - center);
            if any(isnan(dirVec)), dirVec = [1 1 1]/sqrt(3); end
            app.AxModel.CameraPosition = center + dirVec * (span * 2.5);

            % Refresh lighting
            delete(findall(app.AxModel,'Type','light'));
            camlight(app.AxModel,'headlight');
            lighting(app.AxModel,'gouraud');

            drawnow limitrate;
        end

        function captureHomeView(app)
            if isempty(app.AxModel) || ~isvalid(app.AxModel), return; end
            ax = app.AxModel;
            app.DefaultXLim  = xlim(ax);
            app.DefaultYLim  = ylim(ax);
            app.DefaultZLim  = zlim(ax);
            app.DefaultDataAspectRatio    = ax.DataAspectRatio;
            app.DefaultPlotBoxAspectRatio = ax.PlotBoxAspectRatio;
            app.DefaultCameraPosition     = ax.CameraPosition;
            app.DefaultCameraTarget       = ax.CameraTarget;
            app.DefaultCameraUpVector     = ax.CameraUpVector;
            app.DefaultCameraViewAngle    = ax.CameraViewAngle; % Save zoom level
        end

        function resetPlotView(app)
            if isempty(app.DefaultXLim), app.autoFitView(); return; end
            ax = app.AxModel;

            % Restore viewing frustration
            xlim(ax, app.DefaultXLim); ylim(ax, app.DefaultYLim); zlim(ax, app.DefaultZLim);
            ax.DataAspectRatio    = app.DefaultDataAspectRatio;
            ax.PlotBoxAspectRatio = app.DefaultPlotBoxAspectRatio;
            ax.CameraPosition     = app.DefaultCameraPosition;
            ax.CameraTarget       = app.DefaultCameraTarget;
            ax.CameraUpVector     = app.DefaultCameraUpVector;
            ax.CameraViewAngle    = app.DefaultCameraViewAngle; % Restore zoom

            delete(findall(ax,'Type','light'));
            camlight(ax,'headlight'); lighting(ax,'gouraud');
            drawnow limitrate;
        end

        % ===========================================================
        % ROTATION
        % ===========================================================
        function updateRotation(app, axisChar, newVal)
            if isempty(app.ModelPatch) || ~isvalid(app.ModelPatch)
                return
            end

            % Determine which rotation axis this is
            switch axisChar
                case 'X', idx = 1;
                case 'Y', idx = 2;
                case 'Z', idx = 3;
                otherwise, return;
            end

            oldVal = app.RotAngles(idx);
            delta  = newVal - oldVal;
            if delta == 0
                return
            end

            % Update stored rotation angle
            app.RotAngles(idx) = newVal;

            % Build rotation matrix
            switch axisChar
                case 'X'
                    R = makehgtform('xrotate',deg2rad(delta));
                case 'Y'
                    R = makehgtform('yrotate',deg2rad(delta));
                case 'Z'
                    R = makehgtform('zrotate',deg2rad(-delta)); % inverted Z for UI intuition
            end

            % Rotate mesh vertices about their centroid
            V = app.ModelPatch.Vertices;
            C = mean(V,1);
            V = V - C;
            V = [V,ones(size(V,1),1)] * R.';
            V = V(:,1:3) + C;
            app.ModelPatch.Vertices = V;

            % Refocus view
            app.autoFitView();

            % OPTION A: After rotation, behave like Reset Planes
            % Recompute model bounds and reset offsets so:
            %   LeftOffset  = 0 (left face)
            %   RightOffset = width (right face)
            app.updateModelBoundsAndDefaultOffsets(true);
            % Rotation/Reset defines a new "Home" position for the Billet tab
            app.BilletRefXMin = app.ModelXMin;
            app.BilletRefYMin = app.ModelYMin;
            app.BilletRefZMin = app.ModelZMin;
            app.BilletShift   = [0 0 0]; % Reset the UI offset counter
            app.updatePlanes();

            % Recompute billet based on the rotated model
            app.updateBilletDefaultsFromMesh();

        end

        function rotateModel(app,cmd)
            if isempty(app.ModelPatch) || ~isvalid(app.ModelPatch)
                return
            end

            ax = cmd(1);
            d  = cmd(2);
            theta = 90*(d=='p') - 90*(d=='m');

            % Build rotation matrix for the requested axis
            switch ax
                case 'X'
                    R   = makehgtform('xrotate',deg2rad(theta));
                    idx = 1;
                case 'Y'
                    R   = makehgtform('yrotate',deg2rad(theta));
                    idx = 2;
                case 'Z'
                    R   = makehgtform('zrotate',deg2rad(-theta));
                    idx = 3;
                otherwise
                    return;
            end

            % Update stored angle and edit field
            app.RotAngles(idx)     = mod(app.RotAngles(idx) + theta,360);
            app.RotEdit(idx).Value = app.RotAngles(idx);

            % Rotate mesh vertices about their centroid
            V = app.ModelPatch.Vertices;
            C = mean(V,1);
            V = V - C;
            V = [V,ones(size(V,1),1)] * R.';
            V = V(:,1:3) + C;
            app.ModelPatch.Vertices = V;

            % Update view and store as new "home" orientation
            app.autoFitView();
            app.captureHomeView();
            % Rotation changes the geometry → invalidate kerf
            app.invalidateKerf();
            % OPTION A: After rotation, behave like Reset Planes
            app.updateModelBoundsAndDefaultOffsets(true);
            % Rotation/Reset defines a new "Home" position for the Billet tab
            app.BilletRefXMin = app.ModelXMin;
            app.BilletRefYMin = app.ModelYMin;
            app.BilletRefZMin = app.ModelZMin;
            app.BilletShift   = [0 0 0]; % Reset the UI offset counter
            app.updatePlanes();
            % Recompute billet based on the rotated model
            app.updateBilletDefaultsFromMesh();

        end

        function resetOrientation(app)
            if isempty(app.ModelVerticesOriginal) || isempty(app.ModelPatch)
                return
            end

            app.ModelPatch.Vertices = app.ModelVerticesOriginal;

            app.RotAngles = [0 0 0];
            for i = 1:3
                app.RotEdit(i).Value = 0;
            end

            app.autoFitView();
            app.captureHomeView();

            app.invalidateKerf();

            % Reset model bounds & plane offsets to defaults
            app.updateModelBoundsAndDefaultOffsets(true); % reset offsets
            % Rotation/Reset defines a new "Home" position for the Billet tab
            app.BilletRefXMin = app.ModelXMin;
            app.BilletRefYMin = app.ModelYMin;
            app.BilletRefZMin = app.ModelZMin;
            app.BilletShift   = [0 0 0]; % Reset the UI offset counter
            app.updatePlanes();

            % Recompute billet based on the rotated model
            app.updateBilletDefaultsFromMesh();

        end

        % ===========================================================
        % PLANES
        % ===========================================================
        function updateModelBoundsAndDefaultOffsets(app, resetOffsets)
            if isempty(app.ModelPatch), return; end
            V = app.ModelPatch.Vertices;

            % Force SCALAR extraction (mins(1) instead of mins)
            mins = min(V, [], 1);
            maxs = max(V, [], 1);

            app.ModelXMin = mins(1);
            app.ModelXMax = maxs(1);
            app.ModelYMin = mins(2);
            app.ModelYMax = maxs(2);
            app.ModelZMin = mins(3);
            app.ModelZMax = maxs(3);

            if nargin < 2, resetOffsets = true; end
            if resetOffsets
                app.NumLeftOffset.Value  = 0;
                app.NumRightOffset.Value = app.ModelXMax - app.ModelXMin;
            end
        end

        function onPlaneOffsetChanged(app, ~, ~)
            if isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch)
                return
            end

            % Plane movement invalidates kerf
            app.invalidateKerf();

            app.updatePlanes();  % this will also call computeProfiles() in STATE 1

            % Recompute billet based on the rotated model
            app.updateBilletDefaultsFromMesh();

        end

        function resetPlanes(app)
            if isempty(app.ModelPatch) || ~isvalid(app.ModelPatch)
                return
            end

            app.invalidateKerf();

            app.updateModelBoundsAndDefaultOffsets(true);
            app.updatePlanes();

            % Recompute billet based on the rotated model
            app.updateBilletDefaultsFromMesh();

        end

        function updatePlanes(app)
            app.clearPlanes();
            if app.AppState == 0 || isempty(app.ModelPatch), return; end

            % 1. Setup Theme and Geometry
            t = app.getTheme();
            V = app.ModelPatch.Vertices;
            mins = min(V,[],1); maxs = max(V,[],1);
            span = max(maxs - mins); if span <= 0, span = 1; end
            pad  = app.PlanePaddingFactor * span;

            yLims = [mins(2)-pad; maxs(2)+pad; maxs(2)+pad; mins(2)-pad];
            zLims = [mins(3)-pad; mins(3)-pad; maxs(3)+pad; maxs(3)+pad];

            xL = app.ModelXMin(1) + app.NumLeftOffset.Value;
            xR = app.ModelXMin(1) + app.NumRightOffset.Value;

            % 2. Math for Label Positions
            tY_L = (maxs(2)+pad) - 0.02*((maxs(2)+pad) - (mins(2)-pad));
            tZ_L = (maxs(3)+pad) - 0.50*(maxs(3) - mins(3));
            tY_R = (mins(2)-pad) + 0.02*((maxs(2)+pad) - (mins(2)-pad));
            tZ_R = (maxs(3)+pad) - 0.10*(maxs(3) - mins(3));

            % 3. Draw Left Plane
            app.LeftPlanePatch = patch(app.AxModel, 'XData', [xL;xL;xL;xL], 'YData', yLims, 'ZData', zLims, ...
                'FaceColor', t.planeRed, 'FaceAlpha', 0.15, 'EdgeColor', t.planeRed, 'LineStyle','--', 'HandleVisibility','off');
            app.LeftPlaneText = text(app.AxModel, xL, tY_L, tZ_L, {'LEFT','PLANE'}, ...
                'HorizontalAlignment','left', 'VerticalAlignment', 'top', 'Color', t.planeRedTxt, 'FontWeight','bold');

            % 4. Draw Right Plane
            app.RightPlanePatch = patch(app.AxModel, 'XData', [xR;xR;xR;xR], 'YData', yLims, 'ZData', zLims, ...
                'FaceColor', t.planeGreen, 'FaceAlpha', 0.15, 'EdgeColor', t.planeGreen, 'LineStyle','--', 'HandleVisibility','off');
            app.RightPlaneText = text(app.AxModel, xR, tY_R, tZ_R, {'RIGHT','PLANE '}, ...
                'HorizontalAlignment','right', 'VerticalAlignment', 'top', 'Color', t.planeGreenTxt, 'FontWeight','bold');

            % 5. Maintain Layers and Compute
            if isgraphics(app.LeftPlaneText), uistack(app.LeftPlaneText, 'top'); end
            if isgraphics(app.RightPlaneText), uistack(app.RightPlaneText, 'top'); end
            app.computeProfiles();
        end

        % ===========================================================
        % PROFILE BUTTONS (stubs for now)
        % ===========================================================
        function onGenerateProfiles(app)
            if isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch)
                return; % nothing loaded
            end

            if app.AppState == 0
                % Transition from STATE 0 → STATE 1
                app.enterState1();
            else
                % Already in STATE 1: recompute with current rotation / offsets / taper
                app.updatePlanes();  % will call computeProfiles()
            end
        end

        function onContinue(app)
            if isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch), return; end
            currTab = app.TabGroup.SelectedTab;

            if currTab == app.TabModel
                app.TabGroup.SelectedTab = app.TabProfiles;

            elseif currTab == app.TabProfiles
                app.TabGroup.SelectedTab = app.TabBillet;
                % Ensure the billet view is fresh
                app.syncBilletUI();
                app.refreshBilletPlots();

            elseif currTab == app.TabBillet
                % 1. Trigger the logic to center the Billet on the machine bed
                app.onResetMachineBilletPosition();

                % 2. Switch to Machine Tab
                app.TabGroup.SelectedTab = app.TabMachine;

                % 3. Explicitly refresh the machine simulation
                app.syncMachineUI();
                app.refreshMachinePlot();

            elseif currTab == app.TabMachine
                % Transition Machine -> Cutting
                app.TabGroup.SelectedTab = app.TabCutting;
                
                % Auto-Execute
                app.onAutoStart(); 
                app.onAutoEntry();
                
                app.updateCuttingPlots();
                app.onResetCuttingViewBillet();;
            
            elseif currTab == app.TabCutting
                % Leave Cutting -> Enter Simulation
                app.resetInteractionState(); % <--- ADD THIS

                app.TabGroup.SelectedTab = app.TabSimulation;
                app.applyTheme();
                app.generateSimulationData();
            
            elseif currTab == app.TabSimulation
                % Transition Simulation -> Post Process
                app.TabGroup.SelectedTab = app.TabPostProcess;
                app.updatePostProcessUI();
                % (We will add plotting init here later)

            end
        end

        function onContinueFromProfiles(app)
            % If a Billet tab exists, go there; otherwise just stay on Profiles.
            if isprop(app,'TabBillet') && ~isempty(app.TabBillet) && isgraphics(app.TabBillet)
                app.TabGroup.SelectedTab = app.TabBillet;
            else
                % Placeholder – we can wire this once the Billet tab is in.
                disp('Profiles Continue pressed (Billet tab not wired yet).');
            end
        end

        % ===========================================================
        % BILLET TAB CALLBACKS
        % ===========================================================

        function updateBilletDefaultsFromMesh(app)
            if isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch), return; end

            xL = app.ModelXMin + app.NumLeftOffset.Value;
            xR = app.ModelXMin + app.NumRightOffset.Value;

            b = HotWireSTEPApp_v6_helpers.computeDefaultBilletFromMesh(app.ModelPatch.Vertices, xL, xR);

            % Sync the driving property
            app.BilletSize = [b.Xmax - b.Xmin, b.Ymax - b.Ymin, b.Zmax - b.Zmin];

            % For this tab, the Billet origin is always fixed at 0
            app.BilletXMin = 0; app.BilletYMin = 0; app.BilletZMin = 0;

            app.syncBilletUI();
            app.refreshBilletPlots();
        end

        function syncBilletUI(app)
            if isempty(app.BilletSizeEdits) || isempty(app.ModelPatch), return; end

            % 1. Local CAD Properties (relative to CAD coordinate system)
            V  = app.ModelPatch.Vertices;
            xL = app.ModelXMin + app.NumLeftOffset.Value;
            xR = app.ModelXMin + app.NumRightOffset.Value;

            mMin = [min(xL,xR), min(V(:,2)), min(V(:,3))];
            mMax = [max(xL,xR), max(V(:,2)), max(V(:,3))];
            mDim = mMax - mMin;

            % 2. Machining Properties (World positions in the stock 0..Size)
            % This combines the virtual shift with the physical CAD location
            workMin = app.BilletShift + mMin;
            workMax = workMin + mDim;
            bSize   = app.BilletSize;

            % 3. Sync UI Fields
            for i = 1:3
                app.BilletSizeEdits(i).Value = bSize(i);
                app.BilletModelDimLabels(i).Text = sprintf('%.2f mm', mDim(i));

                % These now reflect EXACTLY what travels into the machining stock
                app.BilletNegOffsetEdits(i).Value    = workMin(i);
                app.BilletPosOffsetEdits(i).Value    = bSize(i) - workMax(i);
                app.BilletCenterOffsetEdits(i).Value = app.BilletShift(i);
            end

            % 4. Red/Amber Safety Logic (Based on the now-fixed workMin/Max)
            tol = 1e-4;
            isOutside  = any(workMin < -tol) || any(workMax > bSize + tol);
            isTooClose = (workMin(2) < 5) || (workMax(2) > bSize(2) - 5) || ...
                (workMin(3) < 5) || (workMax(3) > bSize(3) - 5);

            if app.UIFigure.Color(1) < 0.5
                panelBg = [0.16 0.16 0.16]; successGreen = [0.4 1 0.4];
            else
                panelBg = [0.94 0.94 0.94]; successGreen = [0 0.5 0];
            end

            if isOutside
                app.BilletLeftPanel.BackgroundColor = [0.4 0.16 0.16];
                app.BilletMessageLabel.Text = 'CRITICAL: Model is outside stock!';
                app.BilletMessageLabel.FontColor = [1 0.4 0.4];
                app.BtnBilletContinue.Enable = 'off';
            elseif isTooClose
                app.BilletLeftPanel.BackgroundColor = [0.45 0.35 0.1];
                app.BilletMessageLabel.Text = 'Warning: Model is very close (<5mm) to billet edges.';
                app.BilletMessageLabel.FontColor = [1 0.8 0.4];
                app.BtnBilletContinue.Enable = 'on';
            else
                app.BilletLeftPanel.BackgroundColor = panelBg;
                app.BilletMessageLabel.Text = 'Billet configuration valid.';
                app.BilletMessageLabel.FontColor = successGreen;
                app.BtnBilletContinue.Enable = 'on';
            end
        end

        function onAutoFitBillet(app)
            if isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch), return; end

            % 1. Get cutting plane positions for X-sizing
            xL = app.ModelXMin + app.NumLeftOffset.Value;
            xR = app.ModelXMin + app.NumRightOffset.Value;

            % 2. Get bounds from Helper (Xmin, Xmax, etc.)
            b = HotWireSTEPApp_v6_helpers.computeDefaultBilletFromMesh(app.ModelPatch.Vertices, xL, xR);

            % 3. Calculate and set the Driving Factor (Size)
            app.BilletSize = [b.Xmax - b.Xmin, b.Ymax - b.Ymin, b.Zmax - b.Zmin];

            % 4. Reset shift for a fresh fit
            app.BilletShift = [0 0 0];

            app.syncBilletUI();
            app.refreshBilletPlots();
        end

        function onAutoPositionModel(app)
            if isempty(app.ModelPatch), return; end

            % 1. Get LOCAL dimensions (from fixed CAD part)
            V = app.ModelPatch.Vertices;
            localMins = min(V, [], 1);

            % Account for the user's plane offsets
            xL = app.ModelXMin + app.NumLeftOffset.Value;
            xR = app.ModelXMin + app.NumRightOffset.Value;
            planeMinX = min(xL, xR);

            % 2. Direct-Set the Shift (Targets: X=0.001, Y=5.0, Z=5.0)
            app.BilletShift(1) = 0.001 - planeMinX;
            app.BilletShift(2) = 5.0   - localMins(2);
            app.BilletShift(3) = 5.0   - localMins(3);

            app.syncBilletUI();
            app.refreshBilletPlots();
            if app.TabGroup.SelectedTab == app.TabMachine
                app.refreshMachinePlot();
            end
        end

        function onResetPosition(app)
            if isempty(app.ModelPatch), return; end

            % Zero out the virtual Machining Shift
            app.BilletShift = [0 0 0];

            app.syncBilletUI();
            app.refreshBilletPlots();
        end

        function onBilletSizeStep(app, axisIdx, direction)
            % Increments billet size by BilletSizeStep (1mm)
            delta = direction * app.BilletSizeStep;

            % Update the driving property
            app.BilletSize(axisIdx) = max(0, app.BilletSize(axisIdx) + delta);

            app.syncBilletUI();
            app.refreshBilletPlots();
        end

        function onBilletSizeEdited(app, axisIdx, src)
            % Driving factor: Just update the size
            app.BilletSize(axisIdx) = src.Value;

            app.syncBilletUI();
            app.refreshBilletPlots();
        end

        function onBilletOffsetEdited(app, axisIdx, whichField, src)
            val = src.Value;
            V = app.ModelPatch.Vertices;

            % Base CAD limits
            xL = app.ModelXMin + app.NumLeftOffset.Value;
            xR = app.ModelXMin + app.NumRightOffset.Value;
            mMin = [min(xL,xR), min(V(:,2)), min(V(:,3))];
            mMax = [max(xL,xR), max(V(:,2)), max(V(:,3))];

            if strcmp(whichField, 'neg')
                % Logic: Shift + CAD_Min = Input_Gap -> Shift = Input_Gap - CAD_Min
                app.BilletShift(axisIdx) = val - mMin(axisIdx);
            elseif strcmp(whichField, 'pos')
                % Logic: BilletSize - (Shift + CAD_Max) = Input_Gap -> Shift = BilletSize - CAD_Max - Input_Gap
                app.BilletShift(axisIdx) = app.BilletSize(axisIdx) - mMax(axisIdx) - val;
            elseif strcmp(whichField, 'center')
                app.BilletShift(axisIdx) = val;
            end

            app.syncBilletUI();
            app.refreshBilletPlots();
        end

        function moveModelInSpace(app, axisIdx, delta)
            % STABLE: Only update virtual shift
            app.BilletShift(axisIdx) = app.BilletShift(axisIdx) + delta(1);

            app.syncBilletUI();
            app.refreshBilletPlots();

            if app.TabGroup.SelectedTab == app.TabMachine
                app.refreshMachinePlot();
            end
        end

        function onBilletShift(app, axisIdx, delta)
            app.moveModelInSpace(axisIdx, delta);
        end

        function refreshBilletPlots(app)
            % Check if we have a model to plot
            if isempty(app.ModelPatch), return; end

            % 1. Setup Data
            V     = app.ModelPatch.Vertices;
            F     = app.ModelPatch.Faces;
            bMax  = app.BilletSize;  % <--- THIS LINE FIXES THE ERROR
            shift = app.BilletShift;

            % 2. Get Theme Palette
            t = app.getTheme();
            isDark = app.UIFigure.Color(1) < 0.5;
            outlineCol = 'k--'; if isDark, outlineCol = 'w--'; end

            axs  = {app.AxBilletTop, app.AxBilletFront, app.AxBilletRight};
            pair = {[1 2], [1 3], [2 3]};
            labs = {{'X (mm)','Y (mm)'}, {'X (mm)','Z (mm)'}, {'Y (mm)','Z (mm)'}};

            for i = 1:3
                ax = axs{i}; p = pair{i};
                cla(ax); hold(ax,'on');

                % Draw Billet Outline (Dashed relative to stock origin 0,0,0)
                bx = [0 bMax(p(1)) bMax(p(1)) 0 0];
                by = [0 0 bMax(p(2)) bMax(p(2)) 0];
                plot(ax, bx, by, outlineCol, 'LineWidth', 1.5);

                % Corrected Display: Apply shift only to visual data
                Vplot = V(:,p) + shift(p);
                patch(ax, 'Vertices', Vplot, 'Faces', F, ...
                    'FaceColor', [0.5 0.5 0.6], 'EdgeColor', 'none', 'FaceAlpha', 0.4);

                axis(ax, 'equal'); grid(ax, 'on');
                ax.BackgroundColor = t.panelBg; % Use palette background
                xlabel(ax, labs{i}{1}); ylabel(ax, labs{i}{2});
                set(ax, 'XColor', t.labelCol, 'YColor', t.labelCol);
            end
            drawnow limitrate;
        end

        % ===========================================================
        % MACHINE TAB CALLBACKS
        % ===========================================================

        function onMachinePosEdited(app, axisIdx, src)
            if axisIdx == 1
                % Input is Bed-Relative -> Store Absolute
                app.MachineBilletPos(1) = app.MachineBedPos(1) + src.Value;
            else
                % Input is Machine Absolute -> Store Absolute
                app.MachineBilletPos(axisIdx) = src.Value;
            end
            app.refreshMachinePlot();
        end

        function onResetMachineBilletPosition(app)
            if isempty(app.ModelPatch), return; end

            % 1. X-Position: Center the model in the machine to minimize tower lag
            mSpanX = 1180;
            app.MachineBilletPos(1) = (mSpanX - app.BilletSize(1)) / 2;

            % 2. Y-Position: 50mm from home rounded to 10mm
            % (Accounts for any user-applied shift in the Billet Tab)
            currentMinY = app.ModelYMin + app.BilletShift(2);
            app.MachineBilletPos(2) = round((50 - currentMinY) / 10) * 10;

            % 3. Z-Position: Auto-Lift (0, 50, 75, 100) to clear negative projections
            app.MachineBilletPos(3) = 0; % Start at bed

            if ~isempty(app.LeftProfilePoints) && ~isempty(app.RightProfilePoints)
                % Check projection at Z=0
                [yL, zL, yR, zR] = HotWireSTEPApp_v6_helpers.syncPointCounts(...
                    app.LeftProfilePoints(:,2), app.LeftProfilePoints(:,3), ...
                    app.RightProfilePoints(:,2), app.RightProfilePoints(:,3));

                xL_mach = app.MachineBilletPos(1) + app.NumLeftOffset.Value;
                xR_mach = app.MachineBilletPos(1) + app.NumRightOffset.Value;

                % --- FIX: Added app.MachineSpanX as the 7th argument ---
                [tL, tR] = HotWireSTEPApp_v6_helpers.projectToTowers(...
                    yL + app.MachineBilletPos(2) + app.BilletShift(2), zL, xL_mach, ...
                    yR + app.MachineBilletPos(2) + app.BilletShift(2), zR, xR_mach, ...
                    app.MachineSpanX);

                minProjZ = min([tL.z; tR.z]);
                if minProjZ < 0
                    lifts = [50, 75, 100];
                    idx = find(lifts >= abs(minProjZ) + 5, 1, 'first');
                    if ~isempty(idx), app.MachineBilletPos(3) = lifts(idx); end
                end
            end

            app.syncMachineUI();
            app.refreshMachinePlot();
        end

        function onResetMachineViewMachine(app)
            app.resetViewToMachine(app.AxMachine);
        end

        function onResetMachineViewBillet(app)
            app.resetViewToBillet(app.AxMachine);
        end

        function refreshMachinePlot(app)
            % REFRESH MACHINE PLOT: High-Fidelity Sim with Blue Billet & Ghost Profiles
            ax = app.AxMachine;
            if isempty(ax) || ~isgraphics(ax), return; end

            % Clear and start fresh
            delete(allchild(ax));
            hold(ax, 'on');

            % --- 1. THEME & GEOMETRY PREP ---
            t = app.getTheme();
            isDark = app.UIFigure.Color(1) < 0.5;

            % Tweak Wire Colors for visibility against grid
            if isDark
                cageCol = [0.6 0.6 0.6]; tickCol = [1 1 1];
                % Brighter grey for dark mode
                wireBaseCol  = [0.50 0.50 0.50];
                modelAlpha = 0.35;
                offWhite = [0.9 0.9 0.9];
            else
                cageCol = [0.3 0.3 0.3]; tickCol = [0 0 0];
                % Darker grey for light mode
                wireBaseCol  = [0.40 0.40 0.40];
                modelAlpha = 0.30;
                offWhite = [0.2 0.2 0.2];
            end

            % Constants
            offX = app.MachineBedPos(1); mX = app.MachineSpanX;
            mLimY = app.MachineLimitY; mLimZ = app.MachineLimitZ;
            bs = app.MachineBedSize; bp = app.MachineBedPos;

            % --- 2. PHYSICAL BED ---
            [xb, yb, zb] = app.makeBoxVertices(0, bp(2), -bs(3), bs(1), bs(2), bs(3));
            hBed = patch(ax, 'Vertices',[xb, yb, zb], 'Faces', app.boxFaces, ...
                'FaceColor',[0.4 0.4 0.4], 'FaceAlpha', 0.5, 'EdgeColor',[0.2 0.2 0.2]);

            % --- 3. WORKSPACE CAGE ---
            [xl, yl, zl] = app.makeBoxVertices(-offX, 0, 0, mX, mLimY, mLimZ);
            hLim = patch(ax, 'Vertices',[xl, yl, zl], 'Faces', app.boxFaces, ...
                'FaceColor','none', 'EdgeColor', t.labelCol, 'LineStyle',':', 'EdgeAlpha',0.3);

            % --- 4. TOWER HEAD PLANES & LABELS ---
            pY = [0; mLimY; mLimY; 0]; pZ = [0; 0; mLimZ; mLimZ];
            hTowerL = patch(ax, 'XData',ones(4,1)*(-offX), 'YData',pY, 'ZData',pZ, 'FaceColor', t.planeRed, ...
                'FaceAlpha', 0.15, 'EdgeColor', t.planeRed, 'LineStyle', '-');
            hTowerR = patch(ax, 'XData',ones(4,1)*(mX-offX), 'YData',pY, 'ZData',pZ, 'FaceColor', t.planeGreen, ...
                'FaceAlpha', 0.15, 'EdgeColor', t.planeGreen, 'LineStyle', '-');

            text(ax, -offX, mLimY*0.98, mLimZ*0.92, {' LEFT',' TOWER'}, 'Color', t.planeRedTxt, 'FontWeight','bold', 'FontSize',9);
            text(ax, mX-offX, mLimY*0.02, mLimZ*0.92, {'RIGHT','TOWER '}, 'Color', t.planeGreenTxt, 'FontWeight','bold', 'HorizontalAlignment','right', 'FontSize',9);

            % --- 5. BILLET & MODEL ---
            hBillet = gobjects(0); hModel = gobjects(0);
            hGhostL = gobjects(0); hWireL = gobjects(0);

            isViolated = false;

            if ~isempty(app.ModelPatch) && isgraphics(app.ModelPatch)
                bPlotPos = [app.MachineBilletPos(1)-offX, app.MachineBilletPos(2), app.MachineBilletPos(3)];
                totalShift = bPlotPos + app.BilletShift;

                % A. Billet Outline (Blue Style)
                [xm, ym, zm] = app.makeBoxVertices(bPlotPos(1), bPlotPos(2), bPlotPos(3), app.BilletSize(1), app.BilletSize(2), app.BilletSize(3));
                hBillet = patch(ax, 'Vertices',[xm, ym, zm], 'Faces', app.boxFaces, ...
                    'FaceColor', [0.3 0.5 0.8], 'FaceAlpha', 0.2, ...
                    'EdgeColor', t.labelCol, 'LineStyle','--', 'LineWidth', 1.0);

                % B. Ghost Model
                Vplot = app.ModelPatch.Vertices + totalShift;
                hModel = patch(ax, 'Vertices', Vplot, 'Faces', app.ModelPatch.Faces, ...
                    'FaceColor', [0.6 0.6 0.7], 'FaceAlpha', 0.3, 'EdgeColor', 'none');

                % C. Profiles & Wire Paths
                if ~isempty(app.LeftProfilePoints) && ~isempty(app.RightProfilePoints)

                    % 1. GHOST PROFILES (Raw Foam Boundary) - SOLID & BOLDER
                    [yS_rawL, zS_rawL, yS_rawR, zS_rawR] = HotWireSTEPApp_v6_helpers.syncPointCounts(...\
                        app.LeftProfilePoints(:,2), app.LeftProfilePoints(:,3), ...\
                        app.RightProfilePoints(:,2), app.RightProfilePoints(:,3));

                    xL_world = app.LeftProfilePoints(1,1) + totalShift(1);
                    xR_world = app.RightProfilePoints(1,1) + totalShift(1);

                    hGhostL = plot3(ax, xL_world * ones(size(yS_rawL)), yS_rawL + totalShift(2), zS_rawL + totalShift(3), ...
                        'Color', t.rawMeshCol, 'LineWidth', 1.0, 'LineStyle','-');
                    plot3(ax, xR_world * ones(size(yS_rawR)), yS_rawR + totalShift(2), zS_rawR + totalShift(3), ...
                        'Color', t.rawMeshCol, 'LineWidth', 1.0, 'LineStyle','-');

                    % 2. KERF PATH (Actual Wire - Solid)
                    yL_k = app.LeftProfilePoints(:,2); zL_k = app.LeftProfilePoints(:,3);
                    yR_k = app.RightProfilePoints(:,2); zR_k = app.RightProfilePoints(:,3);

                    if app.KerfEnabled && app.KerfValue > 0
                        [yL_k, zL_k] = HotWireSTEPApp_v6_helpers.offsetProfileLoop(yL_k, zL_k, app.KerfValue);
                        [yR_k, zR_k] = HotWireSTEPApp_v6_helpers.offsetProfileLoop(yR_k, zR_k, app.KerfValue);
                    end
                    [ySyncL, zSyncL, ySyncR, zSyncR] = HotWireSTEPApp_v6_helpers.syncPointCounts(yL_k, zL_k, yR_k, zR_k);

                    hWireL = plot3(ax, xL_world * ones(size(ySyncL)), ySyncL + totalShift(2), zSyncL + totalShift(3), ...
                        'Color', t.wireKerf, 'LineWidth', 1.0);
                    plot3(ax, xR_world * ones(size(ySyncR)), ySyncR + totalShift(2), zSyncR + totalShift(3), ...
                        'Color', t.wireKerf, 'LineWidth', 1.0);

                    % 3. TOWER HEAD PROJECTIONS
                    [tL, tR] = HotWireSTEPApp_v6_helpers.projectToTowers(...\
                        ySyncL + totalShift(2), zSyncL + totalShift(3), xL_world + offX, ...\
                        ySyncR + totalShift(2), zSyncR + totalShift(3), xR_world + offX, app.MachineSpanX);

                    plot3(ax, ones(size(tL.y))*(-offX), tL.y, tL.z, 'Color', t.planeRed, 'LineWidth', 1.0);
                    plot3(ax, ones(size(tR.y))*(mX-offX), tR.y, tR.z, 'Color', t.planeGreen, 'LineWidth', 1.0);

                    % 4. SPECTRUM SYNC DOTS & WIRES
                    step = max(1, floor(numel(tL.y)/20));
                    idx = 1:step:numel(tL.y);
                    if idx(end) ~= numel(tL.y), idx(end+1) = numel(tL.y); end
                    dotCMap = hsv(numel(idx));

                    bad = (tL.y < 0 | tL.y > mLimY | tL.z < 0 | tL.z > mLimZ | tR.y < 0 | tR.y > mLimY | tR.z < 0 | tR.z > mLimZ);
                    if any(bad), isViolated = true; end

                    for k = 1:numel(idx)
                        currIdx = idx(k);
                        % WIRE COLOR FIX: Higher alpha (0.6) and adjusted base color
                        wCol = [wireBaseCol, 0.60];
                        if bad(currIdx), wCol = [1 0.8 0 0.8]; end % Yellow alert

                        % Wire
                        plot3(ax, [-offX, mX-offX], [tL.y(currIdx), tR.y(currIdx)], [tL.z(currIdx), tR.z(currIdx)], ...
                            'Color', wCol, 'LineWidth', 0.8);

                        % Dots
                        plot3(ax, xL_world, ySyncL(currIdx) + totalShift(2), zSyncL(currIdx) + totalShift(3), ...
                            '.', 'Color', dotCMap(k,:), 'MarkerSize', 8);
                        plot3(ax, xR_world, ySyncR(currIdx) + totalShift(2), zSyncR(currIdx) + totalShift(3), ...
                            '.', 'Color', dotCMap(k,:), 'MarkerSize', 8);
                    end
                end
            end

            % --- 6. LEGEND ---
            handles = [hBed, hLim, hTowerL, hTowerR, hBillet, hModel, hGhostL, hWireL];
            labels  = {'Machine Bed', 'Travel Limits', 'Left Tower', 'Right Tower', 'Billet Stock', 'Model Mesh', 'Ghost Profile (Raw)', 'Wire Path (Kerf)'};

            valid = isgraphics(handles);
            if any(valid)
                lgd = legend(ax, handles(valid), labels(valid), 'Location','northeast');
                lgd.Box = 'off'; lgd.TextColor = t.labelCol;
            end

            % --- 7. VIEW SETTINGS ---
            view(ax, 3); axis(ax, 'equal'); grid(ax, 'on');
            ax.BackgroundColor = t.editBg;
            set(ax, 'XColor', t.labelCol, 'YColor', t.labelCol, 'ZColor', t.labelCol);

            xlim(ax, [-offX - 100, mX - offX + 100]);
            ylim(ax, [-50, mLimY + 50]);
            zlim(ax, [-bs(3)-20, mLimZ + 80]);

            % --- 8. STATUS UPDATE ---
            if isViolated
                app.MachineMessageLabel.Text = 'CRITICAL: Tower travel exceeds physical limits!';
                app.MachineMessageLabel.FontColor = [1 0.4 0.4];
                app.MachineLeftPanel.BackgroundColor = [0.4 0.16 0.16];
                app.BtnMachineContinue.Enable = 'off';
            else
                app.MachineMessageLabel.Text = 'Machine configuration valid.';
                app.MachineMessageLabel.FontColor = [0.4 1 0.4];
                app.MachineLeftPanel.BackgroundColor = t.sideBg;
                app.BtnMachineContinue.Enable = 'on';
            end
            drawnow limitrate;
        end

        function syncMachineUI(app)
            % X is relative to bed left edge
            app.MachinePosSpinners(1).Value = app.MachineBilletPos(1) - app.MachineBedPos(1);
            % Y and Z are machine absolute
            app.MachinePosSpinners(2).Value = app.MachineBilletPos(2);
            app.MachinePosSpinners(3).Value = app.MachineBilletPos(3);
        end

        function [vx, vy, vz] = makeBoxVertices(~, x, y, z, dx, dy, dz)
            % Returns the 8 vertices for a box at (x,y,z) with size (dx,dy,dz)
            vx = [x; x+dx; x+dx; x;    x;    x+dx; x+dx; x   ];
            vy = [y; y;    y+dy; y+dy; y;    y;    y+dy; y+dy];
            vz = [z; z;    z;    z;    z+dz; z+dz; z+dz; z+dz];
        end

        function f = boxFaces(~)
            % Returns the face connectivity for a standard 8-vertex box
            f = [1 2 3 4; % Bottom
                5 6 7 8; % Top
                1 2 6 5; % Front
                2 3 7 6; % Right
                3 4 8 7; % Back
                4 1 5 8]; % Left
        end

        function [towerL, towerR] = projectToTowers(profileL, xL, profileR, xB, spanX)
            % profileL: [y, z] at model-left-face (xL)
            % profileR: [y, z] at model-right-face (xB)
            % spanX: total machine width (1180)

            % For each point i in the synced profiles:
            % TowerL (at x=0)
            towerL.y = profileL.y + (0 - xL) .* (profileR.y - profileL.y) ./ (xB - xL);
            towerL.z = profileL.z + (0 - xL) .* (profileR.z - profileL.z) ./ (xB - xL);

            % TowerR (at x=1180)
            towerR.y = profileL.y + (spanX - xL) .* (profileR.y - profileL.y) ./ (xB - xL);
            towerR.z = profileL.z + (spanX - xL) .* (profileR.z - profileL.z) ./ (xB - xL);
        end

        % ===========================================================
        % CUTTING TAB LOGIC
        % ===========================================================
        function updateCuttingPlots(app)
            % Visualizes the data on the Cutting Tab.

            if isempty(app.AxCutLeft) || isempty(app.AxCutRight), return; end

            t = app.getTheme();

            % 1. View Persistence
            preserveView = true;
            curXL = xlim(app.AxCutLeft);
            isInitialized = ~isequal(curXL, [0 1]);

            limsL = []; limsR = [];
            if isInitialized
                limsL = [xlim(app.AxCutLeft); ylim(app.AxCutLeft)];
                limsR = [xlim(app.AxCutRight); ylim(app.AxCutRight)];
            end

            cla(app.AxCutLeft); cla(app.AxCutRight);
            hold(app.AxCutLeft,'on'); hold(app.AxCutRight,'on');

            % 2. Setup
            offsetY = app.BilletShift(2) + app.MachineBilletPos(2);
            offsetZ = app.BilletShift(3) + app.MachineBilletPos(3);
            isCCW   = strcmp(app.SwitchCutDir.Value, 'Bottom (CCW)');

            % 3. Backgrounds
            bedY=[50,750,750,50]; bedZ=[-20,-20,0,0];
            patch(app.AxCutLeft, bedY, bedZ, t.labelCol, 'FaceAlpha',0.1, 'EdgeColor','none', 'HitTest','off');
            patch(app.AxCutRight, bedY, bedZ, t.labelCol, 'FaceAlpha',0.1, 'EdgeColor','none', 'HitTest','off');

            mBoxY=[0,app.MachineLimitY,app.MachineLimitY,0,0]; mBoxZ=[0,0,app.MachineLimitZ,app.MachineLimitZ,0];
            hMachL = plot(app.AxCutLeft, mBoxY, mBoxZ, ':', 'Color',t.labelCol, 'LineWidth',0.5, 'HitTest','off');
            hMachR = plot(app.AxCutRight, mBoxY, mBoxZ, ':', 'Color',t.labelCol, 'LineWidth',0.5, 'HitTest','off');

            bY=app.MachineBilletPos(2); bZ=app.MachineBilletPos(3); bW=app.BilletSize(2); bH=app.BilletSize(3);
            boxY=[bY, bY+bW, bY+bW, bY, bY]; boxZ=[bZ, bZ, bZ+bH, bZ+bH, bZ];
            hBilletL = plot(app.AxCutLeft, boxY, boxZ, '--', 'Color',t.labelCol, 'LineWidth',1.5, 'HitTest','off');
            hBilletR = plot(app.AxCutRight, boxY, boxZ, '--', 'Color',t.labelCol, 'LineWidth',1.5, 'HitTest','off');

            % 4. Process Data
            [yL, zL, hGhostL] = app.preparePlotData(app.AxCutLeft, app.LeftProfilePoints, offsetY, offsetZ, app.SelectedStartIdxL, isCCW, t, app.KerfEnabled, app.KerfValue);
            [yR, zR, hGhostR] = app.preparePlotData(app.AxCutRight, app.RightProfilePoints, offsetY, offsetZ, app.SelectedStartIdxR, isCCW, t, app.KerfEnabled, app.KerfValue);

            % 5. Draw
            function hD = drawDummyLegendMarker(ax, style, color, mFace, lWidth)
                if nargin < 5, lWidth = 1.0; end
                hD = plot(ax, NaN, NaN, style, 'Color', color, 'MarkerFaceColor', mFace, 'LineWidth', lWidth);
            end

            hRapidL=gobjects(0); hLeadL=gobjects(0); hStartL=gobjects(0); hPathDummyL=gobjects(0); hEntryDotL=gobjects(0); hLoadL=gobjects(0);

            if ~isempty(yL)
                c=(1:numel(yL))';
                patch(app.AxCutLeft, 'XData',[yL;NaN], 'YData',[zL;NaN], 'CData',[c;NaN], 'FaceColor','none', 'EdgeColor','interp', 'LineWidth',1.0, 'HitTest','off');
                hPathDummyL = drawDummyLegendMarker(app.AxCutLeft, '-', [0 0.5 1], 'none', 1.0);

                [hRapidL, hLeadL, hEntryDotL, hLoadL] = app.drawTravelPath(app.AxCutLeft, [yL(1), zL(1)], [yL(end), zL(end)], app.EntryPointL, app.EntryPoint2L);

                app.drawRotatedMarker(app.AxCutLeft, [yL(1), zL(1)], [yL(2), zL(2)], 'start');
                hStartL = drawDummyLegendMarker(app.AxCutLeft, '^', [0 1 0], 'none');
            end

            hRapidR=gobjects(0); hLeadR=gobjects(0); hStartR=gobjects(0); hPathDummyR=gobjects(0); hEntryDotR=gobjects(0); hLoadR=gobjects(0);
            if ~isempty(yR)
                c=(1:numel(yR))';
                patch(app.AxCutRight, 'XData',[yR;NaN], 'YData',[zR;NaN], 'CData',[c;NaN], 'FaceColor','none', 'EdgeColor','interp', 'LineWidth',1.0, 'HitTest','off');
                hPathDummyR = drawDummyLegendMarker(app.AxCutRight, '-', [0 0.5 1], 'none', 1.0);

                [hRapidR, hLeadR, hEntryDotR, hLoadR] = app.drawTravelPath(app.AxCutRight, [yR(1), zR(1)], [yR(end), zR(end)], app.EntryPointR, app.EntryPoint2R);

                app.drawRotatedMarker(app.AxCutRight, [yR(1), zR(1)], [yR(2), zR(2)], 'start');
                hStartR = drawDummyLegendMarker(app.AxCutRight, '^', [0 1 0], 'none');
            end

            % 6. Legends
            labels = {'Start Point', 'Load Point', 'Cut Path', 'Rapid Links (Yellow)', 'Leads (Orange)', 'Entry Point', 'Machine Limits', 'Raw Profile'};

            % Dummies
            if ~isgraphics(hEntryDotL), hEntryDotL = drawDummyLegendMarker(app.AxCutLeft, '.', [1 0.5 0], [1 0.5 0], 1.0); end
            if ~isgraphics(hEntryDotR), hEntryDotR = drawDummyLegendMarker(app.AxCutRight, '.', [1 0.5 0], [1 0.5 0], 1.0); end

            handlesL = [hStartL, hLoadL, hPathDummyL, hRapidL, hLeadL, hEntryDotL, hMachL, hGhostL];
            if any(isgraphics(handlesL))
                lgd = legend(app.AxCutLeft, handlesL(isgraphics(handlesL)), labels(isgraphics(handlesL)), 'Location','northeast');
                lgd.Box='off'; lgd.TextColor=t.labelCol;
            end

            handlesR = [hStartR, hLoadR, hPathDummyR, hRapidR, hLeadR, hEntryDotR, hMachR, hGhostR];
            if any(isgraphics(handlesR))
                lgd = legend(app.AxCutRight, handlesR(isgraphics(handlesR)), labels(isgraphics(handlesR)), 'Location','northeast');
                lgd.Box='off'; lgd.TextColor=t.labelCol;
            end

            % 7. Restore View
            title(app.AxCutLeft,'Left Tower'); title(app.AxCutRight,'Right Tower');
            colormap(app.AxCutLeft,'turbo'); colormap(app.AxCutRight,'turbo');

            if isInitialized
                xlim(app.AxCutLeft, limsL(1,:)); ylim(app.AxCutLeft, limsL(2,:));
                xlim(app.AxCutRight, limsR(1,:)); ylim(app.AxCutRight, limsR(2,:));
                daspect(app.AxCutLeft,[1 1 1]); daspect(app.AxCutRight,[1 1 1]);
            else
                axis(app.AxCutLeft,'equal'); axis(app.AxCutRight,'equal');
            end
        end

        function [y, z, hGhost] = preparePlotData(app, ax, pts, offY, offZ, startIdx, isCCW, t, doKerf, kVal)
            % Prepares profile data.
            % If 'ax' is empty/invalid, it skips plotting (Ghost) and just returns data.

            y=[]; z=[]; hGhost=gobjects(0);
            if isempty(pts), return; end

            % 1. Ghost Data
            rawY = pts(:,2); rawZ = pts(:,3);
            gY = rawY + offY; gZ = rawZ + offZ;

            % Only plot if axis is valid
            if ~isempty(ax) && isgraphics(ax)
                hGhost = plot(ax, gY, gZ, ':', 'Color', t.rawMeshCol, 'LineWidth', 0.5, 'HitTest','off');
            end

            % 2. Apply Kerf
            if doKerf, [rawY, rawZ] = HotWireSTEPApp_v6_helpers.offsetProfileLoop(rawY, rawZ, kVal); end
            y = rawY + offY; z = rawZ + offZ;

            % 3. Process Loop
            if numel(y) > 2
                if abs(y(1)-y(end)) < 1e-6 && abs(z(1)-z(end)) < 1e-6, y(end)=[]; z(end)=[]; end
                idx = startIdx; if idx > numel(y), idx = 1; end
                y = circshift(y, -(idx - 1)); z = circshift(z, -(idx - 1));
                if isCCW, y(2:end) = flipud(y(2:end)); z(2:end) = flipud(z(2:end)); end
                y(end+1) = y(1); z(end+1) = z(1);
            end
        end

        function onCutDirectionChanged(app)
            % Triggered when switching between CW (Top First) and CCW (Bottom First)
            disp(['Direction changed to: ' app.SwitchCutDir.Value]);
            app.updateCuttingPlots();
        end

        function onInteractionStatsChanged(app, src)
            % Handles mutual exclusivity and color updates for interaction buttons

            c = app.getInteractionColors();

            % 1. Determine user intent: Did they click it ON or OFF?
            % Since this is a ValueChangedFcn, src.Value holds the NEW state.
            wantsToEnable = src.Value;

            % 2. Reset ALL buttons to OFF/Inactive (Clean Slate)
            % This ensures mutual exclusivity
            app.BtnPickStart.Value = false;
            app.BtnPickStart.BackgroundColor = c.StartInactive;
            app.BtnPickStart.FontColor = c.TextInactive;

            app.BtnPickEntry.Value = false;
            app.BtnPickEntry.BackgroundColor = c.EntryInactive;
            app.BtnPickEntry.FontColor = c.TextInactive;

            app.BtnPickEntry2.Value = false;
            app.BtnPickEntry2.BackgroundColor = c.Entry2Inactive;
            app.BtnPickEntry2.FontColor = c.TextInactive;

            % Reset Plot Interaction
            app.AxCutLeft.ButtonDownFcn = [];
            app.AxCutRight.ButtonDownFcn = [];
            app.UIFigure.Pointer = 'arrow';

            % 3. If the user wanted to enable a button, turn THAT one back on
            if wantsToEnable
                src.Value = true; % Force it active
                app.UIFigure.Pointer = 'crosshair';

                % Enable Click Listeners
                app.AxCutLeft.ButtonDownFcn  = @(src,evt)app.onCutAxesClick(src, evt, 'Left');
                app.AxCutRight.ButtonDownFcn = @(src,evt)app.onCutAxesClick(src, evt, 'Right');

                % Apply Active Colors
                if src == app.BtnPickStart
                    src.BackgroundColor = c.StartActive;
                    src.FontColor = c.TextActive;
                elseif src == app.BtnPickEntry
                    src.BackgroundColor = c.EntryActive;
                    src.FontColor = c.TextActive;
                elseif src == app.BtnPickEntry2
                    src.BackgroundColor = c.Entry2Active;
                    src.FontColor = c.TextActive;
                end
            end
        end

        function resetInteractionState(app)
            % Turns off all interaction buttons and resets cursor
            c = app.getInteractionColors();

            % Reset States
            app.BtnPickStart.Value = false;
            app.BtnPickEntry.Value = false;
            app.BtnPickEntry2.Value = false;

            % Reset Colors
            app.BtnPickStart.BackgroundColor = c.StartInactive;
            app.BtnPickEntry.BackgroundColor = c.EntryInactive;
            app.BtnPickEntry2.BackgroundColor = c.Entry2Inactive;

            % Reset Font Colors
            app.BtnPickStart.FontColor = c.TextInactive;
            app.BtnPickEntry.FontColor = c.TextInactive;
            app.BtnPickEntry2.FontColor = c.TextInactive;

            % Remove Plot Listeners
            app.AxCutLeft.ButtonDownFcn = [];
            app.AxCutRight.ButtonDownFcn = [];
            app.UIFigure.Pointer = 'arrow';
        end

        function onResetCuttingViewMachine(app)
            % View 1: Machine Origin (0,0) at bottom left
            % Fixed scale covering typical machine bed

            mLimY = app.MachineLimitY;
            mLimZ = app.MachineLimitZ;

            limits = [-50, mLimY+50, -50, mLimZ+50];

            axis(app.AxCutLeft, limits);
            axis(app.AxCutRight, limits);
        end

        function onResetCuttingViewBillet(app)
            % View 2: Fit to Billet + Buffer

            bY = app.MachineBilletPos(2);
            bZ = app.MachineBilletPos(3);
            bW = app.BilletSize(2);
            bH = app.BilletSize(3);

            buffer = 50; % mm

            limits = [bY-buffer, bY+bW+buffer, bZ-buffer, bZ+bH+buffer];

            axis(app.AxCutLeft, limits);
            axis(app.AxCutRight, limits);
        end

        function onCutAxesClick(app, ax, ~, side)
            % Handles clicks on the Cutting axes to set Start or Entry points

            % 1. Get Click Coordinates
            cp = ax.CurrentPoint(1, 1:2);
            clickY = cp(1); clickZ = cp(2);

            % --- CASE 1: SET START POINT ---
            if app.BtnPickStart.Value

                % A. Retrieve Data for the clicked side
                yData = []; zData = [];
                offsetY = app.BilletShift(2) + app.MachineBilletPos(2);
                offsetZ = app.BilletShift(3) + app.MachineBilletPos(3);
                useKerf = app.KerfEnabled && app.KerfValue > 0;

                % Select Profile
                pts = [];
                if strcmp(side, 'Left') && ~isempty(app.LeftProfilePoints)
                    pts = app.LeftProfilePoints;
                elseif strcmp(side, 'Right') && ~isempty(app.RightProfilePoints)
                    pts = app.RightProfilePoints;
                end

                % Process Points
                if ~isempty(pts)
                    rawY = pts(:,2); rawZ = pts(:,3);
                    if useKerf
                        [rawY, rawZ] = HotWireSTEPApp_v6_helpers.offsetProfileLoop(rawY, rawZ, app.KerfValue);
                    end
                    yData = rawY + offsetY;
                    zData = rawZ + offsetZ;
                end

                % B. Validate (Exit if clicked on empty plot)
                if isempty(yData)
                    return;
                end

                % C. Find Nearest Point (Define minIdx)
                distances = (yData - clickY).^2 + (zData - clickZ).^2;
                [~, minIdx] = min(distances);

                % D. Apply Index (Start Point Sync Logic)
                if strcmp(app.SwitchSyncStart.Value, 'Coupled')
                    app.SelectedStartIdxL = minIdx;
                    app.SelectedStartIdxR = minIdx;
                else
                    if strcmp(side, 'Left')
                        app.SelectedStartIdxL = minIdx;
                    else
                        app.SelectedStartIdxR = minIdx;
                    end
                end

                % --- CASE 2: SET ENTRY 1 ---
            elseif app.BtnPickEntry.Value

                if strcmp(app.SwitchSyncEntry.Value, 'Coupled')
                    app.EntryPointL = cp;
                    app.EntryPointR = cp;
                else
                    if strcmp(side, 'Left')
                        app.EntryPointL = cp;
                    else
                        app.EntryPointR = cp;
                    end
                end

                % --- CASE 3: SET ENTRY 2 ---
            elseif app.BtnPickEntry2.Value

                if strcmp(app.SwitchSyncEntry.Value, 'Coupled')
                    app.EntryPoint2L = cp;
                    app.EntryPoint2R = cp;
                else
                    if strcmp(side, 'Left')
                        app.EntryPoint2L = cp;
                    else
                        app.EntryPoint2R = cp;
                    end
                end
            end

            % Final Step: Refresh Plot
            app.updateCuttingPlots();
        end

        function onSyncToggleChanged(app, src)
            % Start Point Coupling
            if strcmp(src.Value, 'Coupled')
                app.SelectedStartIdxR = app.SelectedStartIdxL;
                app.updateCuttingPlots();
            end
        end

        function onSyncEntryToggleChanged(app, src)
            % Entry Point Coupling
            if strcmp(src.Value, 'Coupled')
                app.EntryPointR = app.EntryPointL;
                app.updateCuttingPlots();
            end
        end

        function onAutoStart(app)
            % Finds the point with Minimum Y (Machine Front) and sets it as Start

            % Helper to find min index of a profile
            function idx = findMinYIndex(pts, kerfVal, doKerf)
                if isempty(pts), idx = 1; return; end
                y = pts(:,2); z = pts(:,3);
                if doKerf
                    [y, z] = HotWireSTEPApp_v6_helpers.offsetProfileLoop(y, z, kerfVal);
                end
                [~, idx] = min(y);
            end

            doKerf = app.KerfEnabled && app.KerfValue > 0;

            % Left
            idxL = findMinYIndex(app.LeftProfilePoints, app.KerfValue, doKerf);
            app.SelectedStartIdxL = idxL;

            % Right
            idxR = findMinYIndex(app.RightProfilePoints, app.KerfValue, doKerf);
            app.SelectedStartIdxR = idxR;

            disp(['Auto Start: Reset indices to nearest Machine Front (L=' num2str(idxL) ', R=' num2str(idxR) ')']);
            app.updateCuttingPlots();
        end

        function onAutoEntry(app)
            % Calculates Auto Entry points.
            % Mode Logic:
            %   - If Entry2 is empty (Default): Calculates 1 Entry Point (45mm out on bisector).
            %   - If Entry2 exists: Calculates 2 Points (E2 on bisector, E1 aligned to Front-10mm).

            % --- Nested Helper ---
            function [e1, e2] = calcEntryLogic(pts, startIdx, billetMinY, doKerf, kVal, useDual)
                e1 = []; e2 = [];
                if isempty(pts), return; end

                % 1. Get Geometry [y z]
                y = pts(:,1); z = pts(:,2);
                if doKerf, [y, z] = HotWireSTEPApp_v6_helpers.offsetProfileLoop(y, z, kVal); end

                N = numel(y);
                if startIdx > N, startIdx = 1; end

                % 2. Identify Points
                idxS = startIdx;
                idxN = mod(startIdx, N) + 1;
                idxP = mod(startIdx - 2, N) + 1;

                S = [y(idxS), z(idxS)];
                P = [y(idxP), z(idxP)];
                N_pt = [y(idxN), z(idxN)];

                % 3. Calculate Bisector
                vSP = P - S; vSP = vSP / (norm(vSP)+eps);
                vSN = N_pt - S; vSN = vSN / (norm(vSN)+eps);
                vBisect = -(vSP + vSN);

                if norm(vBisect) < 1e-6
                    vTan = N_pt - P; vBisect = [vTan(2), -vTan(1)];
                end
                vBisect = vBisect / norm(vBisect);

                % 4. Outward Check
                testPt = S + vBisect * 0.5;
                if inpolygon(testPt(1), testPt(2), y, z), vBisect = -vBisect; end

                % 5. Project Target Point (45mm)
                distT = 45;
                targetPt = S + vBisect * distT;

                % 6. Z-Safety
                if targetPt(2) < 5.0, targetPt(2) = 5.0; end

                % 7. Assign based on Mode
                if useDual
                    % TWO POINTS: E2 is target, E1 is retraction alignment
                    e2 = targetPt;
                    retractY = billetMinY - 10;
                    e1 = [retractY, e2(2)];
                else
                    % ONE POINT: E1 is target, E2 is empty
                    e1 = targetPt;
                    e2 = [];
                end
            end
            % ---------------------

            doKerf = app.KerfEnabled && app.KerfValue > 0;
            bMinY  = app.MachineBilletPos(2);
            offsetY = app.BilletShift(2) + app.MachineBilletPos(2);
            offsetZ = app.BilletShift(3) + app.MachineBilletPos(3);

            % Check if we are in "2 Point Mode" (User has set E2 previously)
            % We base this on the Left profile state
            useDualMode = ~isempty(app.EntryPoint2L);

            % --- LEFT ---
            if ~isempty(app.LeftProfilePoints)
                ptsL = [app.LeftProfilePoints(:,2) + offsetY, app.LeftProfilePoints(:,3) + offsetZ];
                [e1L, e2L] = calcEntryLogic(ptsL, app.SelectedStartIdxL, bMinY, doKerf, app.KerfValue, useDualMode);
                app.EntryPointL  = e1L;
                app.EntryPoint2L = e2L;
            end

            % --- RIGHT ---
            if strcmp(app.SwitchSyncEntry.Value, 'Coupled')
                app.EntryPointR  = app.EntryPointL;
                app.EntryPoint2R = app.EntryPoint2L;
            elseif ~isempty(app.RightProfilePoints)
                % Check Right specific mode? Or stick to Left's mode decision?
                % Usually consistent to use Left's mode decision for symmetry.
                ptsR = [app.RightProfilePoints(:,2) + offsetY, app.RightProfilePoints(:,3) + offsetZ];
                [e1R, e2R] = calcEntryLogic(ptsR, app.SelectedStartIdxR, bMinY, doKerf, app.KerfValue, useDualMode);
                app.EntryPointR  = e1R;
                app.EntryPoint2R = e2R;
            end

            app.updateCuttingPlots();
        end

        function [hRapid, hLead, hDot, hLoad] = drawTravelPath(app, ax, startPt, endPt, entry1, entry2)
            % Draws Travel Path with split Lead-in/Lead-out colors.

            hRapid = gobjects(0); hLead = gobjects(0); hDot = gobjects(0); hLoad = gobjects(0);
            if isempty(startPt), return; end

            % --- Constants ---
            pZero    = [0, 0];
            pSafe    = [10, 10];
            pLoad    = [app.MachineBilletPos(2), app.MachineBilletPos(3) + app.BilletSize(3)/2];
            pRetract = [pLoad(1)-10, pLoad(2)];

            % --- 1. LOAD POINT ---
            hLoad = plot(ax, pLoad(1), pLoad(2), 'x', 'MarkerSize', 8, 'Color', [1 0 1], 'LineWidth', 1.5, 'HitTest','off');

            % --- 2. APPROACH (Yellow Rapid + Orange Lead-in) ---
            ptsIn = [pZero; pSafe; pLoad; pRetract];
            if ~isempty(entry1), ptsIn = [ptsIn; entry1]; end
            if ~isempty(entry2), ptsIn = [ptsIn; entry2]; end

            % Rapid Chain (Yellow Solid)
            if size(ptsIn, 1) > 1
                hRapid = plot(ax, ptsIn(:,1), ptsIn(:,2), '-', 'Color', [0.9 0.8 0], 'LineWidth', 0.5, 'HitTest','off');
            end

            % Lead-In (Orange Solid)
            lastPt = ptsIn(end,:);
            hLead = plot(ax, [lastPt(1), startPt(1)], [lastPt(2), startPt(2)], '-', 'Color', [1 0.5 0], 'LineWidth', 0.5, 'HitTest','off');

            % --- 3. RETURN (Orange Lead-out + Yellow Rapid) ---
            % Determine first return point
            firstReturnPt = endPt;
            if ~isempty(entry2)
                firstReturnPt = entry2;
            elseif ~isempty(entry1)
                firstReturnPt = entry1;
            end

            % Plot Lead-Out (Orange Dashed, Double Width)
            if ~isequal(endPt, firstReturnPt)
                plot(ax, [endPt(1), firstReturnPt(1)], [endPt(2), firstReturnPt(2)], '--', 'Color', [1 0.5 0], 'LineWidth', 1.0, 'HitTest','off');
            end

            % Build Rapid Return Chain
            ptsOut = firstReturnPt;
            if ~isempty(entry2) && ~isempty(entry1), ptsOut = [ptsOut; entry1]; end

            % Home Y First
            pHomeY = [0, ptsOut(end, 2)];
            ptsOut = [ptsOut; pHomeY; pZero];

            % Plot Rapid Return (Yellow Dashed)
            plot(ax, ptsOut(:,1), ptsOut(:,2), '--', 'Color', [0.9 0.8 0], 'LineWidth', 0.5, 'HitTest','off');

            % --- 4. DOTS ---
            dotPts = [];
            if ~isempty(entry1), dotPts = [dotPts; entry1]; end
            if ~isempty(entry2), dotPts = [dotPts; entry2]; end
            if ~isempty(dotPts)
                hDot = plot(ax, dotPts(:,1), dotPts(:,2), '.', 'MarkerSize', 10, 'Color', [1 0.5 0], 'HitTest','off');
            end
        end

        function hMarker = drawRotatedMarker(app, ax, pCurrent, pNext, type)
            % Draws a rotated triangle at pCurrent, pointing towards pNext
            hMarker = gobjects(0);
            v = pNext - pCurrent;
            len = norm(v);
            if len < 1e-6, return; end
            
            % Normalize
            u = v / len;
            scale = 4; % Size mm
            
            % Geometry
            if strcmp(type, 'start')
                % Forward pointing triangle (Green)
                % Tip at (0,0), base at (-1, 0.5)
                % To point "along" the line, we want the tip pointing in direction U
                % So geometry: Base at back, Tip at front
                xPoly = [0, -1, -1] * scale; 
                yPoly = [0, 0.5, -0.5] * scale;
                colFill = 'none'; colEdge = [0 1 0]; % Hollow Green
            else
                % Exit (Reverse/Stop) Triangle (Red)
                % Just a standard triangle
                xPoly = [0, -1, -1] * scale;
                yPoly = [0, 0.5, -0.5] * scale;
                colFill = 'none'; colEdge = [1 0 0]; % Hollow Red
            end
            
            % Rotation
            theta = atan2(u(2), u(1));
            R = [cos(theta), -sin(theta); sin(theta), cos(theta)];
            ptsRot = R * [xPoly; yPoly];
            
            % Translate
            ptsFinal = ptsRot + pCurrent(:);
            
            hMarker = patch(ax, ptsFinal(1,:), ptsFinal(2,:), 'k', ...
                'FaceColor', colFill, 'EdgeColor', colEdge, 'LineWidth', 1.0, 'HitTest','off');
        end

        function onClearEntries(app)
            app.EntryPointL = []; app.EntryPointR = [];
            app.EntryPoint2L = []; app.EntryPoint2R = [];
            app.updateCuttingPlots();
        end

        % ===========================================================
        % SIMULATION TAB LOGIC
        % ===========================================================
        function generateSimulationData(app)
            % Compiles toolpath and syncs L/R for simulation

            fprintf('--- DEBUG: Generating Simulation Data ---\n');

            t = app.getTheme();
            offsetY = app.BilletShift(2) + app.MachineBilletPos(2);
            offsetZ = app.BilletShift(3) + app.MachineBilletPos(3);
            isCCW   = strcmp(app.SwitchCutDir.Value, 'Bottom (CCW)');

            % 1. Process Profiles
            [yL, zL] = app.preparePlotData([], app.LeftProfilePoints,  offsetY, offsetZ, app.SelectedStartIdxL, isCCW, t, app.KerfEnabled, app.KerfValue);
            [yR, zR] = app.preparePlotData([], app.RightProfilePoints, offsetY, offsetZ, app.SelectedStartIdxR, isCCW, t, app.KerfEnabled, app.KerfValue);

            % 2. Sync Profiles
            [yL, zL, yR, zR] = HotWireSTEPApp_v6_helpers.syncPointCounts(yL, zL, yR, zR);

            app.ProfileSyncL = [yL(:), zL(:)];
            app.ProfileSyncR = [yR(:), zR(:)];

            % --- HELPERS (Raw Segments) ---
            function pts = buildRapidIn(entry1, entry2)
                pZero=[0,0]; pSafe=[10,10];
                pLoad=[app.MachineBilletPos(2), app.MachineBilletPos(3) + app.BilletSize(3)/2];
                pRetract=[pLoad(1)-10, pLoad(2)];
                pts=[pZero; pSafe; pLoad; pRetract];
                if ~isempty(entry1), pts=[pts; entry1]; end
                if ~isempty(entry2), pts=[pts; entry2]; end
            end

            function pts = buildLeadIn(startPt, entry1, entry2)
                lastPt=[];
                pLoad=[app.MachineBilletPos(2), app.MachineBilletPos(3) + app.BilletSize(3)/2];
                pRetract=[pLoad(1)-10, pLoad(2)];
                if ~isempty(entry2), lastPt=entry2; elseif ~isempty(entry1), lastPt=entry1; else, lastPt=pRetract; end
                pts=[lastPt; startPt];
            end

            function pts = buildLeadOut(endPt, entry1, entry2)
                firstRet=endPt;
                if ~isempty(entry2), firstRet=entry2; elseif ~isempty(entry1), firstRet=entry1; end
                pts=[endPt; firstRet];
            end

            function pts = buildRapidReturn(endPt, entry1, entry2)
                pZero=[0,0]; firstRet=endPt;
                if ~isempty(entry2), firstRet=entry2; elseif ~isempty(entry1), firstRet=entry1; end
                pts=firstRet;
                if ~isempty(entry2) && ~isempty(entry1), pts=[pts; entry1]; end
                pHomeY=[0, pts(end,2)]; pts=[pts; pHomeY; pZero];
            end

            % --- GENERATE RAW SEGMENTS ---
            rawRapL = buildRapidIn(app.EntryPointL, app.EntryPoint2L);
            rawRapR = buildRapidIn(app.EntryPointR, app.EntryPoint2R);
            app.SimRawRapidL = rawRapL; app.SimRawRapidR = rawRapR;

            rawLeadInL = buildLeadIn([yL(1), zL(1)], app.EntryPointL, app.EntryPoint2L);
            rawLeadInR = buildLeadIn([yR(1), zR(1)], app.EntryPointR, app.EntryPoint2R);
            app.SimRawLeadInL = rawLeadInL; app.SimRawLeadInR = rawLeadInR;

            profY_L = yL; profZ_L = zL; profY_R = yR; profZ_R = zR;

            rawLeadOutL = buildLeadOut([yL(end), zL(end)], app.EntryPointL, app.EntryPoint2L);
            rawLeadOutR = buildLeadOut([yR(end), zR(end)], app.EntryPointR, app.EntryPoint2R);
            app.SimRawLeadOutL = rawLeadOutL; app.SimRawLeadOutR = rawLeadOutR;

            rawRetL = buildRapidReturn([yL(end), zL(end)], app.EntryPointL, app.EntryPoint2L);
            rawRetR = buildRapidReturn([yR(end), zR(end)], app.EntryPointR, app.EntryPoint2R);
            app.SimRawReturnL = rawRetL; app.SimRawReturnR = rawRetR;

            % Helper: Resample and Sync Two Paths to matching step count
            function [L_out, R_out] = interpolateSynced(L_pts, R_pts)
                if size(L_pts,1)<2 || size(R_pts,1)<2
                    L_out = L_pts; R_out = R_pts; return;
                end

                % Lengths
                dL = sum(sqrt(sum(diff(L_pts).^2, 2)));
                dR = sum(sqrt(sum(diff(R_pts).^2, 2)));
                maxLen = max(dL, dR);

                % Step size 2mm -> N steps
                N = max(20, round(maxLen / 2.0));

                % Interpolate L
                distL = [0; cumsum(sqrt(sum(diff(L_pts).^2, 2)))];
                % Guard against duplicate points causing distL to have repeats (interp1 error)
                [distL, uIdx] = unique(distL, 'stable');
                L_pts = L_pts(uIdx, :);

                targetL = linspace(0, distL(end), N)';
                yL_new = interp1(distL, L_pts(:,1), targetL);
                zL_new = interp1(distL, L_pts(:,2), targetL);
                L_out = [yL_new, zL_new];

                % Interpolate R (forcing same N)
                distR = [0; cumsum(sqrt(sum(diff(R_pts).^2, 2)))];
                [distR, uIdxR] = unique(distR, 'stable');
                R_pts = R_pts(uIdxR, :);

                targetR = linspace(0, distR(end), N)';
                yR_new = interp1(distR, R_pts(:,1), targetR);
                zR_new = interp1(distR, R_pts(:,2), targetR);
                R_out = [yR_new, zR_new];
            end

            % --- INTERPOLATE & SYNC PHASES ---
            [rapL_i, rapR_i] = interpolateSynced(rawRapL, rawRapR);
            [liL_i,  liR_i]  = interpolateSynced(rawLeadInL, rawLeadInR);
            [loL_i,  loR_i]  = interpolateSynced(rawLeadOutL, rawLeadOutR);

            % Return stitch (manual)
            retL_stitch = [[loL_i(end,:)]; rawRetL];
            retR_stitch = [[loR_i(end,:)]; rawRetR];
            [retL_i, retR_i] = interpolateSynced(retL_stitch, retR_stitch);

            % --- INDICES ---
            app.SimRapidCutoffIndex  = size(rapL_i, 1);
            app.SimProfileStartIndex = app.SimRapidCutoffIndex + size(liL_i, 1);
            app.SimFeedEndIndex      = app.SimProfileStartIndex + numel(profY_L);
            app.SimLeadOutEndIndex   = app.SimFeedEndIndex + size(loL_i, 1);

            % --- COMBINE ---
            fullY_L = [rapL_i(:,1); liL_i(:,1); profY_L; loL_i(:,1); retL_i(:,1)];
            fullZ_L = [rapL_i(:,2); liL_i(:,2); profZ_L; loL_i(:,2); retL_i(:,2)];

            fullY_R = [rapR_i(:,1); liR_i(:,1); profY_R; loR_i(:,1); retR_i(:,1)];
            fullZ_R = [rapR_i(:,2); liR_i(:,2); profZ_R; loR_i(:,2); retR_i(:,2)];

            % --- STORE 3D PATHS ---
            if ~isempty(app.LeftProfilePoints),  baseXL = app.LeftProfilePoints(1,1);  else, baseXL = app.MachineBilletPos(1);    end
            if ~isempty(app.RightProfilePoints), baseXR = app.RightProfilePoints(1,1); else, baseXR = app.MachineBilletPos(1)+10; end

            xL_val = baseXL + app.BilletShift(1) + app.MachineBilletPos(1);
            xR_val = baseXR + app.BilletShift(1) + app.MachineBilletPos(1);

            app.SimPathL = [repmat(xL_val, numel(fullY_L), 1), fullY_L, fullZ_L];
            app.SimPathR = [repmat(xR_val, numel(fullY_R), 1), fullY_R, fullZ_R];

            % --- CALCULATE ARC LENGTH ---
            dL = sqrt(sum(diff(app.SimPathL).^2, 2)); dL(isnan(dL))=0;
            dR = sqrt(sum(diff(app.SimPathR).^2, 2)); dR(isnan(dR))=0;

            app.SimArcLenL = [0; cumsum(dL)];
            app.SimArcLenR = [0; cumsum(dR)];
            app.SimTotalLength = max(app.SimArcLenL(end), app.SimArcLenR(end));
            app.SimPlayDist = 0;

            fprintf('DEBUG: Sim Generated. Points L:%d R:%d. Len: %.2f mm\n', ...
                size(app.SimPathL,1), size(app.SimPathR,1), app.SimTotalLength);

            % Towers (sim)
            V = app.SimPathR - app.SimPathL;
            tL = -app.SimPathL(:,1) ./ V(:,1);
            app.SimTowerPathL = app.SimPathL + tL .* V;

            mSpan = app.MachineSpanX;
            tR = (mSpan - app.SimPathL(:,1)) ./ V(:,1);
            app.SimTowerPathR = app.SimPathL + tR .* V;

            % Init Slider
            app.SimSlider.Limits = [1, size(app.SimPathL, 1)];
            app.SimSlider.Value = 1;
            app.initSimulationPlot();
        end

        function initSimulationPlot(app)
            % Sets up the 3D environment for simulation

            ax = app.AxSim;
            cla(ax); hold(ax, 'on');
            t = app.getTheme();

            offX  = app.MachineBedPos(1);
            mSpan = app.MachineSpanX;
            mLimY = app.MachineLimitY; mLimZ = app.MachineLimitZ;
            bs = app.MachineBedSize;

            % --- CRITICAL FIX: Correct Variable Assignments ---
            bedPos = app.MachineBedPos;    % Physical Bed
            bp     = app.MachineBilletPos; % Stock Position (Fixed)

            % 1. STATIC GEOMETRY
            % Bed (Uses bedPos)
            [xb, yb, zb] = app.makeBoxVertices(0, bedPos(2), -bs(3), bs(1), bs(2), bs(3));
            hBed = patch(ax, 'Vertices',[xb, yb, zb], 'Faces', app.boxFaces, ...
                'FaceColor',[0.4 0.4 0.4], 'FaceAlpha', 0.5, 'EdgeColor',[0.2 0.2 0.2]);

            % Limits
            [xl, yl, zl] = app.makeBoxVertices(-offX, 0, 0, mSpan, mLimY, mLimZ);
            patch(ax, 'Vertices',[xl, yl, zl], 'Faces', app.boxFaces, ...
                'FaceColor','none', 'EdgeColor', t.labelCol, 'LineStyle',':', 'EdgeAlpha',0.3);

            % Towers
            hTowerL = patch(ax, 'XData',ones(4,1)*(-offX), 'YData',[0;mLimY;mLimY;0], 'ZData',[0;0;mLimZ;mLimZ], ...
                'FaceColor', t.planeRed, 'FaceAlpha', 0.15, 'EdgeColor', t.planeRed);
            hTowerR = patch(ax, 'XData',ones(4,1)*(mSpan-offX), 'YData',[0;mLimY;mLimY;0], 'ZData',[0;0;mLimZ;mLimZ], ...
                'FaceColor', t.planeGreen, 'FaceAlpha', 0.15, 'EdgeColor', t.planeGreen);

            text(ax, -offX, mLimY*0.98, mLimZ*0.92, {' LEFT',' TOWER'}, 'Color', t.planeRedTxt, 'FontWeight','bold', 'FontSize', 9);
            text(ax, mSpan-offX, mLimY*0.02, mLimZ*0.92, {'RIGHT','TOWER '}, 'Color', t.planeGreenTxt, 'FontWeight','bold', 'HorizontalAlignment','right', 'FontSize', 9);

            % 2. BILLET & MODEL
            % Plot X = BilletMachineX - BedOffsetX
            bPlotX = bp(1) - offX;
            bPlotPos = [bPlotX, bp(2), bp(3)];

            % Billet
            [xm, ym, zm] = app.makeBoxVertices(bPlotX, bp(2), bp(3), app.BilletSize(1), app.BilletSize(2), app.BilletSize(3));
            hBillet = patch(ax, 'Vertices',[xm, ym, zm], 'Faces', app.boxFaces, ...
                'FaceColor', [0.3 0.5 0.8], 'FaceAlpha', 0.2, 'EdgeColor', t.labelCol, 'LineStyle','--', 'LineWidth', 0.5);

            % Model Mesh
            hModel = gobjects(0);
            if ~isempty(app.ModelPatch) && isgraphics(app.ModelPatch)
                modelShift = bPlotPos + app.BilletShift;
                Vplot = app.ModelPatch.Vertices + modelShift;
                hModel = patch(ax, 'Vertices', Vplot, 'Faces', app.ModelPatch.Faces, ...
                    'FaceColor', [0.6 0.6 0.7], 'FaceAlpha', 0.3, 'EdgeColor', 'none', 'Tag', 'SimModel');
            end

            % 3. GHOST PROFILES
            offsetY = bp(2) + app.BilletShift(2);
            offsetZ = bp(3) + app.BilletShift(3);
            % Shift X: (BilletMachineX + InternalShiftX) - BedOffsetX
            shiftX = (bp(1) + app.BilletShift(1)) - offX;

            hGhostL = gobjects(0);
            if ~isempty(app.LeftProfilePoints)
                xPL = app.LeftProfilePoints(:,1) + shiftX;
                hGhostL = plot3(ax, xPL, app.LeftProfilePoints(:,2)+offsetY, app.LeftProfilePoints(:,3)+offsetZ, ...
                    '-', 'Color', t.rawMeshCol, 'LineWidth', 0.5);
            end
            if ~isempty(app.RightProfilePoints)
                xPR = app.RightProfilePoints(:,1) + shiftX;
                plot3(ax, xPR, app.RightProfilePoints(:,2)+offsetY, app.RightProfilePoints(:,3)+offsetZ, ...
                    '-', 'Color', t.rawMeshCol, 'LineWidth', 0.5);
            end

            % 4. DYNAMIC ELEMENTS
            hWire=gobjects(0); hRapids=gobjects(0); hTrails=gobjects(0);

            if ~isempty(app.SimPathL)
                % --- TOWER TRAILS (Projected) ---
                % Rapid (Yellow)
                hRapids = plot3(ax, NaN, NaN, NaN, '-', 'Color', [0.9 0.8 0], 'LineWidth', 0.5, 'Tag', 'SimTowerRapidL');
                plot3(ax, NaN, NaN, NaN, '-', 'Color', [0.9 0.8 0], 'LineWidth', 0.5, 'Tag', 'SimTowerRapidR');
                % Lead In (Orange Solid) - NEW
                plot3(ax, NaN, NaN, NaN, '-', 'Color', [1 0.5 0], 'LineWidth', 0.5, 'Tag', 'SimTowerLeadInL');
                plot3(ax, NaN, NaN, NaN, '-', 'Color', [1 0.5 0], 'LineWidth', 0.5, 'Tag', 'SimTowerLeadInR');

                plot3(ax, NaN, NaN, NaN, '-', 'Color', [1 0.5 0], 'LineWidth', 0.5, 'Tag', 'SimModelLeadInL');
                plot3(ax, NaN, NaN, NaN, '-', 'Color', [1 0.5 0], 'LineWidth', 0.5, 'Tag', 'SimModelLeadInR');
                % Feed (Red/Green) - FIX: Green color corrected
                plot3(ax, NaN, NaN, NaN, '-', 'Color', [0.8 0 0],   'LineWidth', 0.5, 'Tag', 'SimTowerFeedL');
                plot3(ax, NaN, NaN, NaN, '-', 'Color', [0 0.8 0],   'LineWidth', 0.5, 'Tag', 'SimTowerFeedR');
                % Lead Out (Orange Dashed)
                plot3(ax, NaN, NaN, NaN, '--', 'Color', [1 0.5 0], 'LineWidth', 0.5, 'Tag', 'SimTowerLeadOutL');
                plot3(ax, NaN, NaN, NaN, '--', 'Color', [1 0.5 0], 'LineWidth', 0.5, 'Tag', 'SimTowerLeadOutR');
                % Return (Yellow Dashed)
                plot3(ax, NaN, NaN, NaN, '--', 'Color', [0.9 0.8 0], 'LineWidth', 0.5, 'Tag', 'SimTowerReturnL');
                plot3(ax, NaN, NaN, NaN, '--', 'Color', [0.9 0.8 0], 'LineWidth', 0.5, 'Tag', 'SimTowerReturnR');

                % --- MODEL TRAILS (On Block) ---
                % Rapid (Yellow)
                plot3(ax, NaN, NaN, NaN, '-', 'Color', [0.9 0.8 0], 'LineWidth', 0.5, 'Tag', 'SimModelRapidL');
                plot3(ax, NaN, NaN, NaN, '-', 'Color', [0.9 0.8 0], 'LineWidth', 0.5, 'Tag', 'SimModelRapidR');
                % Feed (Red/Green)
                hTrails = plot3(ax, NaN, NaN, NaN, '-', 'Color', t.planeRed,   'LineWidth', 0.5, 'Tag', 'SimModelFeedL');
                plot3(ax, NaN, NaN, NaN, '-', 'Color', t.planeGreen, 'LineWidth', 0.5, 'Tag', 'SimModelFeedR');
                % Lead Out (Orange Dashed)
                plot3(ax, NaN, NaN, NaN, '--', 'Color', [1 0.5 0], 'LineWidth', 0.5, 'Tag', 'SimModelLeadOutL');
                plot3(ax, NaN, NaN, NaN, '--', 'Color', [1 0.5 0], 'LineWidth', 0.5, 'Tag', 'SimModelLeadOutR');
                % Return (Yellow Dashed)
                plot3(ax, NaN, NaN, NaN, '--', 'Color', [0.9 0.8 0], 'LineWidth', 0.5, 'Tag', 'SimModelReturnL');
                plot3(ax, NaN, NaN, NaN, '--', 'Color', [0.9 0.8 0], 'LineWidth', 0.5, 'Tag', 'SimModelReturnR');

                % --- WIRE (Thin: 0.2) ---
                hWire = plot3(ax, NaN, NaN, NaN, 'Color', t.wireKerf, 'LineWidth', 0.2, 'Tag', 'SimWire');

                % --- DOTS (Small: 4) ---
                % Tower
                plot3(ax, NaN, NaN, NaN, 'o', 'MarkerSize', 4, 'MarkerFaceColor', t.planeRed,   'MarkerEdgeColor', 'none', 'Tag', 'SimDotL');
                plot3(ax, NaN, NaN, NaN, 'o', 'MarkerSize', 4, 'MarkerFaceColor', t.planeGreen, 'MarkerEdgeColor', 'none', 'Tag', 'SimDotR');
                % Model
                plot3(ax, NaN, NaN, NaN, 'o', 'MarkerSize', 4, 'MarkerFaceColor', t.planeRed,   'MarkerEdgeColor', 'none', 'Tag', 'SimModelDotL');
                plot3(ax, NaN, NaN, NaN, 'o', 'MarkerSize', 4, 'MarkerFaceColor', t.planeGreen, 'MarkerEdgeColor', 'none', 'Tag', 'SimModelDotR');

                app.onSimSliderChanging(app.SimSlider);
            end

            % 5. LEGEND
            handles = [hBed, hTowerL, hTowerR, hBillet, hModel, hGhostL, hRapids, hTrails, hWire];
            labels  = {'Machine Bed', 'Left Tower', 'Right Tower', 'Billet', 'Model', 'Ghost Profile', 'Rapid Path', 'Cut Path', 'Wire'};

            valid = isgraphics(handles);
            if any(valid)
                lgd = legend(ax, handles(valid), labels(valid), 'Location','northeast');
                lgd.Box = 'off'; lgd.TextColor = t.labelCol;
            end

            app.onResetSimViewMachine();
            ax.BackgroundColor = [0.05 0.05 0.05];
            set(ax, 'XColor', [0.6 0.6 0.6], 'YColor', [0.6 0.6 0.6], 'ZColor', [0.6 0.6 0.6]);
        end

        function onSimSliderChanging(app, src)
            % USER INTERACTION: User drags slider -> Update Distance & Plot

            idx = round(src.Value);

            % Validating index
            if isempty(app.SimPathL), return; end
            idx = max(1, min(idx, size(app.SimPathL, 1)));

            % SYNC: Since USER moved the slider, we must update the physics distance
            % to match this new location, so Play resumes from here.
            if ~isempty(app.SimArcLenL) && idx <= numel(app.SimArcLenL)
                app.SimPlayDist = app.SimArcLenL(idx);
            end

            % Update Visuals
            app.updateSimVisuals(idx);
        end

        % HELPER: Update Trail Data
        function updateTrail(app, tag, dataSrc, startIdx, endIdx, offX)
            h = findobj(app.AxSim, 'Tag', tag);
            if ~isempty(h)
                dat = dataSrc(startIdx:endIdx, :) - [offX, 0, 0];
                h.XData=dat(:,1); h.YData=dat(:,2); h.ZData=dat(:,3);
            end
        end

        function clearTrails(app, tags)
            for i=1:numel(tags)
                h = findobj(app.AxSim, 'Tag', tags{i});
                if ~isempty(h), h.XData=[]; h.YData=[]; h.ZData=[]; end
            end
        end

        function onResetSimViewMachine(app)
            app.resetViewToMachine(app.AxSim);
        end

        function onResetSimViewBillet(app)
            app.resetViewToBillet(app.AxSim);
        end

        % --- Shared Helpers ---
        function resetViewToMachine(app, ax)
            offX = app.MachineBedPos(1);
            mX = app.MachineSpanX;
            mLimY = app.MachineLimitY; mLimZ = app.MachineLimitZ;
            bs = app.MachineBedSize;

            view(ax, 3); axis(ax, 'equal');
            xlim(ax, [-offX - 100, mX - offX + 100]);
            ylim(ax, [-50, mLimY + 50]);
            zlim(ax, [-bs(3)-20, mLimZ + 80]);
        end

        function resetViewToBillet(app, ax)
            % Centers view on the Billet with a dynamic buffer

            offX = app.MachineBedPos(1);
            bp   = app.MachineBilletPos; % [X Y Z] absolute machine coords
            bs   = app.BilletSize;       % [W D H]

            % Billet Bounds in Plot Coords
            % Plot X = MachineX - BedOffset
            bMin = [bp(1)-offX, bp(2), bp(3)];
            bMax = bMin + bs;

            % Calculate a relative buffer (20% of the largest dimension)
            maxDim = max(bs);
            if maxDim < 1, maxDim = 100; end % Fallback
            buffer = maxDim * 0.2;

            % 1. Set Aspect Ratio FIRST (Prevents limit reset)
            daspect(ax, [1 1 1]);

            % 2. Apply Limits
            xlim(ax, [bMin(1)-buffer, bMax(1)+buffer]);
            ylim(ax, [bMin(2)-buffer, bMax(2)+buffer]);
            zlim(ax, [bMin(3)-buffer, bMax(3)+buffer]);

            % 3. Standard View Settings
            view(ax, 3);
            grid(ax, 'on');
        end

        function idx = simIndexAtDistance(app, dist)
            % Returns the simulation path index corresponding to the physical travel distance.

            % Clamp to valid range
            dist = max(0, min(dist, app.SimTotalLength));

            % Find last index whose cumulative arc length <= distance
            % Using Left tower as reference, or Left arc lengths
            if isempty(app.SimArcLenL)
                idx = 1;
                return;
            end

            idx = find(app.SimArcLenL <= dist, 1, 'last');

            if isempty(idx)
                idx = 1;
            end

            % Safety clamp
            idx = min(idx, size(app.SimPathL,1));
        end

        % ===========================================================
        % SIMULATION PLAYBACK
        % ===========================================================
        function onSimPlay(app)
            % Start/Resume Timer
            
            if isempty(app.SimPathL), return; end
            % Auto-rewind if at end
            if app.SimPlayDist >= app.SimTotalLength - 1e-3
                app.SimPlayDist = 0;
            end
            
            if isempty(app.SimTimer) || ~isvalid(app.SimTimer)
                app.SimTimer = timer(...
                    'ExecutionMode', 'fixedRate', ...
                    'Period', 0.05, ... % 20 FPS base
                    'TimerFcn', @(~,~)app.onSimTimerTick());
            end

            if strcmp(app.SimTimer.Running, 'off')
                start(app.SimTimer);
                app.SimPlayBtn.Enable = 'off'; % Disable Play while running
            end
        end

        function updateSimVisuals(app, idx)
            % Updates the 3D scene elements to match the given path index
            if isempty(app.SimPathL), return; end

            idx = max(1, min(idx, size(app.SimPathL, 1)));
            offX = app.MachineBedPos(1);

            % Phase Indices
            idxRapidEnd   = app.SimRapidCutoffIndex;
            idxProfStart  = app.SimProfileStartIndex;
            idxProfEnd    = app.SimFeedEndIndex;
            idxLeadOutEnd = app.SimLeadOutEndIndex;

            % --- HELPERS (Local to this function) ---
            function updateT(tag, data, s, e)
                h = findobj(app.AxSim, 'Tag', tag);
                if ~isempty(h)
                    dt = data(s:e, :) - [offX, 0, 0];
                    h.XData=dt(:,1); h.YData=dt(:,2); h.ZData=dt(:,3);
                end
            end

            function clearT(tags)
                for i=1:numel(tags)
                    h = findobj(app.AxSim, 'Tag', tags{i});
                    if ~isempty(h), h.XData=[]; h.YData=[]; h.ZData=[]; end
                end
            end

            % 1. MOVING ELEMENTS (Wire & Dots)
            pTL = app.SimTowerPathL(idx, :) - [offX, 0, 0];
            pTR = app.SimTowerPathR(idx, :) - [offX, 0, 0];

            hWire = findobj(app.AxSim, 'Tag', 'SimWire');
            if ~isempty(hWire), hWire.XData=[pTL(1),pTR(1)]; hWire.YData=[pTL(2),pTR(2)]; hWire.ZData=[pTL(3),pTR(3)]; end

            hDotL = findobj(app.AxSim, 'Tag', 'SimDotL'); if ~isempty(hDotL), hDotL.XData=pTL(1); hDotL.YData=pTL(2); hDotL.ZData=pTL(3); end
            hDotR = findobj(app.AxSim, 'Tag', 'SimDotR'); if ~isempty(hDotR), hDotR.XData=pTR(1); hDotR.YData=pTR(2); hDotR.ZData=pTR(3); end

            pML = app.SimPathL(idx, :) - [offX, 0, 0]; pMR = app.SimPathR(idx, :) - [offX, 0, 0];
            hMDotL = findobj(app.AxSim, 'Tag', 'SimModelDotL'); if ~isempty(hMDotL), hMDotL.XData=pML(1); hMDotL.YData=pML(2); hMDotL.ZData=pML(3); end
            hMDotR = findobj(app.AxSim, 'Tag', 'SimModelDotR'); if ~isempty(hMDotR), hMDotR.XData=pMR(1); hMDotR.YData=pMR(2); hMDotR.ZData=pMR(3); end

            % 2. RAPID TRAILS (Always active up to current)
            curEnd = min(idx, idxRapidEnd);
            updateT('SimTowerRapidL', app.SimTowerPathL, 1, curEnd);
            updateT('SimTowerRapidR', app.SimTowerPathR, 1, curEnd);
            updateT('SimModelRapidL', app.SimPathL, 1, curEnd);
            updateT('SimModelRapidR', app.SimPathR, 1, curEnd);

            % 3. LEAD IN
            if idx > idxRapidEnd
                curEnd = min(idx, idxProfStart);
                updateT('SimTowerLeadInL', app.SimTowerPathL, idxRapidEnd, curEnd);
                updateT('SimTowerLeadInR', app.SimTowerPathR, idxRapidEnd, curEnd);
                updateT('SimModelLeadInL', app.SimPathL, idxRapidEnd, curEnd);
                updateT('SimModelLeadInR', app.SimPathR, idxRapidEnd, curEnd);
            else
                clearT({'SimTowerLeadInL','SimTowerLeadInR','SimModelLeadInL','SimModelLeadInR'});
            end

            % 4. FEED PROFILE
            if idx > idxProfStart
                curEnd = min(idx, idxProfEnd);
                updateT('SimTowerFeedL', app.SimTowerPathL, idxProfStart, curEnd);
                updateT('SimTowerFeedR', app.SimTowerPathR, idxProfStart, curEnd);
                updateT('SimModelFeedL', app.SimPathL, idxProfStart, curEnd);
                updateT('SimModelFeedR', app.SimPathR, idxProfStart, curEnd);
            else
                clearT({'SimTowerFeedL','SimTowerFeedR','SimModelFeedL','SimModelFeedR'});
            end

            % 5. LEAD OUT
            if idx > idxProfEnd
                curEnd = min(idx, idxLeadOutEnd);
                updateT('SimTowerLeadOutL', app.SimTowerPathL, idxProfEnd, curEnd);
                updateT('SimTowerLeadOutR', app.SimTowerPathR, idxProfEnd, curEnd);
                updateT('SimModelLeadOutL', app.SimPathL, idxProfEnd, curEnd);
                updateT('SimModelLeadOutR', app.SimPathR, idxProfEnd, curEnd);
            else
                clearT({'SimTowerLeadOutL','SimTowerLeadOutR','SimModelLeadOutL','SimModelLeadOutR'});
            end

            % 6. RETURN
            if idx > idxLeadOutEnd
                updateT('SimTowerReturnL', app.SimTowerPathL, idxLeadOutEnd, idx);
                updateT('SimTowerReturnR', app.SimTowerPathR, idxLeadOutEnd, idx);
                updateT('SimModelReturnL', app.SimPathL, idxLeadOutEnd, idx);
                updateT('SimModelReturnR', app.SimPathR, idxLeadOutEnd, idx);
            else
                clearT({'SimTowerReturnL','SimTowerReturnR','SimModelReturnL','SimModelReturnR'});
            end

            % 7. Readouts
            if ~isempty(app.LblReadoutX), app.LblReadoutX.Text = sprintf('%.2f', pTL(2)); end
            if ~isempty(app.LblReadoutY), app.LblReadoutY.Text = sprintf('%.2f', pTL(3)); end
            if ~isempty(app.LblReadoutZ), app.LblReadoutZ.Text = sprintf('%.2f', pTR(2)); end
            if ~isempty(app.LblReadoutA), app.LblReadoutA.Text = sprintf('%.2f', pTR(3)); end

            drawnow limitrate;
        end

        function onSimPause(app)
            if ~isempty(app.SimTimer) && isvalid(app.SimTimer)
                stop(app.SimTimer);
                app.SimPlayBtn.Enable = 'on';
            end
        end

        function onSimStop(app)
            app.onSimPause();
            app.SimPlayDist = 0;          % Reset distance
            app.SimSlider.Value = 1;      % Reset index
            app.onSimSliderChanging(app.SimSlider); % Reset Visuals
        end

        function onSimTimerTick(app)
            % Distance-Based Update Logic

            % 1. Advance distance
            step = app.SimStepDist * app.SimSpeedSpinner.Value;
            app.SimPlayDist = app.SimPlayDist + step;

            % 2. Cap at end
            isDone = false;
            if app.SimPlayDist >= app.SimTotalLength
                app.SimPlayDist = app.SimTotalLength;
                isDone = true;
            end

            % 3. Map distance -> Index
            idx = app.simIndexAtDistance(app.SimPlayDist);

            % 4. Update Slider (Visually only)
            app.SimSlider.Value = idx;

            % 5. Update Plot (Directly, bypassing slider callback logic)
            app.updateSimVisuals(idx);

            % Debug print (Verify loop is broken)
            % fprintf('TICK: Dist=%.1f, Idx=%d\n', app.SimPlayDist, idx);

            if isDone
                fprintf('DEBUG: Simulation Finished.\n');
                app.onSimPause();
            end
        end

        % Ensure Timer is killed when app closes
        function delete(app)
            if ~isempty(app.SimTimer) && isvalid(app.SimTimer)
                stop(app.SimTimer);
                delete(app.SimTimer);
            end
        end

        function onAppClose(app, src)
            % Cleanup Timer
            if ~isempty(app.SimTimer) && isvalid(app.SimTimer)
                stop(app.SimTimer);
                delete(app.SimTimer);
            end
            delete(src); % Close window
        end

        % ===========================================================
        % POST-PROCESS TAB LOGIC
        % ===========================================================

        function updatePostProcessUI(app)
            % Updates the Filename field based on loaded model
            if isempty(app.FieldFilename.Value) || startsWith(app.FieldFilename.Value, 'GCode-V1-Output')
                name = "Output";
                if ~isempty(app.CurrentModelName)
                    [~, name, ~] = fileparts(app.CurrentModelName);
                end
                app.FieldFilename.Value = sprintf("GCode-V1-%s", name);
            end
        end

        function initPostPlot(app)
            axP = app.AxPost;
            cla(axP); hold(axP,'on');

            % Ensure sim plot exists (and has the objects/tags we want)
            if isempty(app.AxSim) || ~isvalid(app.AxSim)
                error('AxSim invalid - cannot clone simulation scene.');
            end

            % If the sim scene hasn't been built yet, build it once
            if isempty(app.AxSim.Children)
                app.initSimulationPlot();
            end

            % Copy the entire scene from Sim axes into Post axes
            copyobj(app.AxSim.Children, axP);

            % Rename Sim* tags to Post* tags in the Post axes
            h = findall(axP, '-property', 'Tag');
            for i = 1:numel(h)
                tg = string(h(i).Tag);
                if startsWith(tg, "Sim")
                    h(i).Tag = "Post" + extractAfter(tg, 3);
                end
            end

            % Match formatting/view (copy key axes props)
            axP.BackgroundColor = app.AxSim.BackgroundColor;
            axP.XColor = app.AxSim.XColor;
            axP.YColor = app.AxSim.YColor;
            axP.ZColor = app.AxSim.ZColor;
            axP.GridColor = app.AxSim.GridColor;
            axP.GridAlpha = app.AxSim.GridAlpha;

            grid(axP,'on');
            axis(axP,'equal');
            view(axP, app.AxSim.View);

            hold(axP,'off');

            drawnow;
        end

        function updatePostPlotForSelectedLine(app, k)
            % Uses PP_* paths (truth-based) so Post stepping matches real G-code moves

            if isempty(app.PP_LineToPathIndex) || isempty(app.PP_PathL) || isempty(app.PP_TowerPathL)
                return;
            end

            % Find motion idx for this selected G-code line (scan backward)
            k = max(1, min(k, numel(app.PP_LineToPathIndex)));
            idx = app.PP_LineToPathIndex(k);
            kk = k;
            while (isnan(idx) || idx <= 0) && kk > 1
                kk = kk - 1;
                idx = app.PP_LineToPathIndex(kk);
            end
            if isnan(idx) || idx <= 0, idx = 1; end
            idx = min(idx, size(app.PP_PathL,1));

            ax = app.AxPost;
            offX = app.MachineBedPos(1);

            % Phase indices (PP indices, not sim indices)
            idxRapidEnd   = app.PP_RapidEndIndex;
            idxProfStart  = app.PP_ProfileStartIndex;
            idxProfEnd    = app.PP_ProfileEndIndex;
            idxLeadOutEnd = app.PP_LeadOutEndIndex;

            % Local references to PP paths
            pathL  = app.PP_PathL;
            pathR  = app.PP_PathR;
            towerL = app.PP_TowerPathL;
            towerR = app.PP_TowerPathR;

            % Helpers (same logic as sim, but Post tags + AxPost)
            function updateT(tag, data, s, e)
                h = findobj(ax, 'Tag', tag);
                if ~isempty(h)
                    s = max(1, min(s, size(data,1)));
                    e = max(1, min(e, size(data,1)));
                    if e < s
                        h.XData=[]; h.YData=[]; h.ZData=[];
                        return;
                    end
                    dt = data(s:e,:) - [offX,0,0];
                    h.XData = dt(:,1);
                    h.YData = dt(:,2);
                    h.ZData = dt(:,3);
                end
            end

            function clearT(tags)
                for ii = 1:numel(tags)
                    h = findobj(ax,'Tag',tags{ii});
                    if ~isempty(h)
                        h.XData=[]; h.YData=[]; h.ZData=[];
                    end
                end
            end

            % Wire + dots at idx (towers)
            pTL = towerL(idx,:) - [offX,0,0];
            pTR = towerR(idx,:) - [offX,0,0];

            hWire = findobj(ax,'Tag','PostWire');
            if ~isempty(hWire)
                hWire.XData = [pTL(1), pTR(1)];
                hWire.YData = [pTL(2), pTR(2)];
                hWire.ZData = [pTL(3), pTR(3)];
            end

            hDotL = findobj(ax,'Tag','PostDotL');
            if ~isempty(hDotL)
                hDotL.XData = pTL(1); hDotL.YData = pTL(2); hDotL.ZData = pTL(3);
            end

            hDotR = findobj(ax,'Tag','PostDotR');
            if ~isempty(hDotR)
                hDotR.XData = pTR(1); hDotR.YData = pTR(2); hDotR.ZData = pTR(3);
            end

            % -----------------------------
            % Phase 1: Rapid (1 -> idxRapidEnd)
            % -----------------------------
            curEnd = min(idx, idxRapidEnd);
            updateT('PostTowerRapidL', towerL, 1, curEnd);
            updateT('PostTowerRapidR', towerR, 1, curEnd);
            updateT('PostModelRapidL', pathL,  1, curEnd);
            updateT('PostModelRapidR', pathR,  1, curEnd);

            % -----------------------------
            % Phase 2: Lead In (idxRapidEnd -> idxProfStart)
            % -----------------------------
            if idx > idxRapidEnd
                curEnd = min(idx, idxProfStart);
                updateT('PostTowerLeadInL', towerL, idxRapidEnd, curEnd);
                updateT('PostTowerLeadInR', towerR, idxRapidEnd, curEnd);
                updateT('PostModelLeadInL', pathL,  idxRapidEnd, curEnd);
                updateT('PostModelLeadInR', pathR,  idxRapidEnd, curEnd);
            else
                clearT({'PostTowerLeadInL','PostTowerLeadInR','PostModelLeadInL','PostModelLeadInR'});
            end

            % -----------------------------
            % Phase 3: Feed profile (idxProfStart -> idxProfEnd)
            % -----------------------------
            if idx > idxProfStart
                curEnd = min(idx, idxProfEnd);
                updateT('PostTowerFeedL', towerL, idxProfStart, curEnd);
                updateT('PostTowerFeedR', towerR, idxProfStart, curEnd);
                updateT('PostModelFeedL', pathL,  idxProfStart, curEnd);
                updateT('PostModelFeedR', pathR,  idxProfStart, curEnd);
            else
                clearT({'PostTowerFeedL','PostTowerFeedR','PostModelFeedL','PostModelFeedR'});
            end

            % -----------------------------
            % Phase 4: Lead out (idxProfEnd -> idxLeadOutEnd)
            % -----------------------------
            if idx > idxProfEnd
                curEnd = min(idx, idxLeadOutEnd);
                updateT('PostTowerLeadOutL', towerL, idxProfEnd, curEnd);
                updateT('PostTowerLeadOutR', towerR, idxProfEnd, curEnd);
                updateT('PostModelLeadOutL', pathL,  idxProfEnd, curEnd);
                updateT('PostModelLeadOutR', pathR,  idxProfEnd, curEnd);
            else
                clearT({'PostTowerLeadOutL','PostTowerLeadOutR','PostModelLeadOutL','PostModelLeadOutR'});
            end

            % -----------------------------
            % Phase 5: Return (idxLeadOutEnd -> idx)
            % -----------------------------
            if idx > idxLeadOutEnd
                updateT('PostTowerReturnL', towerL, idxLeadOutEnd, idx);
                updateT('PostTowerReturnR', towerR, idxLeadOutEnd, idx);
                updateT('PostModelReturnL', pathL,  idxLeadOutEnd, idx);
                updateT('PostModelReturnR', pathR,  idxLeadOutEnd, idx);
            else
                clearT({'PostTowerReturnL','PostTowerReturnR','PostModelReturnL','PostModelReturnR'});
            end

            drawnow limitrate;
        end

        function onResetPostViewMachine(app)
            app.resetViewToMachine(app.AxPost);
        end

        function onResetPostViewBillet(app)
            app.resetViewToBillet(app.AxPost);
        end

        function onPostProcess(app)

            % Ensure truth/semantic arrays exist
            app.generateSimulationData();

            if isempty(app.ProfileSyncL) || isempty(app.ProfileSyncR)
                uialert(app.UIFigure, 'No synced profile available. Build profiles first.', 'Post-Process');
                return;
            end
            if isempty(app.SimRawRapidL) || isempty(app.SimRawRapidR) || ...
                    isempty(app.SimRawLeadInL) || isempty(app.SimRawLeadInR) || ...
                    isempty(app.SimRawLeadOutL) || isempty(app.SimRawLeadOutR) || ...
                    isempty(app.SimRawReturnL) || isempty(app.SimRawReturnR)
                uialert(app.UIFigure, 'No semantic entry/exit segments available. Set Entry points and try again.', 'Post-Process');
                return;
            end

            % Inputs
            feed  = round(app.SpinFeedRate.Value);
            power = round(app.SpinPower.Value);
            if isempty(feed) || ~isfinite(feed) || feed <= 0, feed = 500; end
            if isempty(power) || ~isfinite(power) || power < 0, power = 0; end

            % ------------------------------------------------------------
            % Build PP "truth" 2D paths (Y,Z) for L/R
            % ------------------------------------------------------------
            profL = app.ProfileSyncL;   % Nx2 [Y Z] (synced)
            profR = app.ProfileSyncR;

            rapL  = app.SimRawRapidL;
            rapR  = app.SimRawRapidR;

            liL   = app.SimRawLeadInL;   % 2x2 [lastEntry; start]
            liR   = app.SimRawLeadInR;

            loL   = app.SimRawLeadOutL;  % 2x2 [end; entry]
            loR   = app.SimRawLeadOutR;

            retL  = app.SimRawReturnL;
            retR  = app.SimRawReturnR;

            % De-duplicate junctions so PP stepping and G-code are clean
            % Rapid ends at entry; LeadIn starts at entry -> keep only LeadIn(2)
            % LeadOut starts at end -> keep only LeadOut(2)
            % Return starts at entry -> drop return(1) if it equals leadOut(2)
            liL_emit  = liL(2:end,:);
            liR_emit  = liR(2:end,:);
            loL_emit  = loL(2:end,:);
            loR_emit  = loR(2:end,:);

            if size(retL,1) >= 1 && norm(retL(1,:) - loL(end,:)) < 1e-9
                retL_emit = retL(2:end,:);
            else
                retL_emit = retL;
            end
            if size(retR,1) >= 1 && norm(retR(1,:) - loR(end,:)) < 1e-9
                retR_emit = retR(2:end,:);
            else
                retR_emit = retR;
            end

            % Full PP point sequence (this is what the G-code will follow)
            ppL_yz = [rapL; liL_emit; profL; loL_emit; retL_emit];
            ppR_yz = [rapR; liR_emit; profR; loR_emit; retR_emit];

            % Indices in this PP sequence
            nRap  = size(rapL,1);
            nLi   = size(liL_emit,1);
            nProf = size(profL,1);
            nLo   = size(loL_emit,1);

            app.PP_RapidEndIndex    = nRap;
            app.PP_ProfileStartIndex= nRap + nLi;          % first profile point in PP path
            app.PP_ProfileEndIndex  = nRap + nLi + nProf;  % last profile point in PP path
            app.PP_LeadOutEndIndex  = nRap + nLi + nProf + nLo;

            % ------------------------------------------------------------
            % Convert PP points to 3D paths for plotting (constant X planes)
            % ------------------------------------------------------------
            if ~isempty(app.LeftProfilePoints),  baseXL = app.LeftProfilePoints(1,1);  else, baseXL = app.MachineBilletPos(1);    end
            if ~isempty(app.RightProfilePoints), baseXR = app.RightProfilePoints(1,1); else, baseXR = app.MachineBilletPos(1)+10; end

            xL_val = baseXL + app.BilletShift(1) + app.MachineBilletPos(1);
            xR_val = baseXR + app.BilletShift(1) + app.MachineBilletPos(1);

            app.PP_PathL = [repmat(xL_val, size(ppL_yz,1), 1), ppL_yz(:,1), ppL_yz(:,2)];
            app.PP_PathR = [repmat(xR_val, size(ppR_yz,1), 1), ppR_yz(:,1), ppR_yz(:,2)];

            % Tower paths for Post plot
            V = app.PP_PathR - app.PP_PathL;
            tL = -app.PP_PathL(:,1) ./ V(:,1);
            app.PP_TowerPathL = app.PP_PathL + tL .* V;

            mSpan = app.MachineSpanX;
            tR = (mSpan - app.PP_PathL(:,1)) ./ V(:,1);
            app.PP_TowerPathR = app.PP_PathL + tR .* V;

            % ------------------------------------------------------------
            % Build Mach4 G-code from PP path
            % ------------------------------------------------------------
            % Machine mapping:
            %   X = Left(Y),  Y = Left(Z),  Z = Right(Y),  A = Right(Z)
            X = ppL_yz(:,1);
            Y = ppL_yz(:,2);
            Z = ppR_yz(:,1);
            A = ppR_yz(:,2);

            fmtMove = @(g,i) sprintf('%s X%.3f Y%.3f Z%.3f A%.3f', g, X(i), Y(i), Z(i), A(i));

            lines = strings(0,1);
            map   = zeros(0,1);   % line -> PP path index (NaN for non-motion)

            % Header
            lines(end+1) = "(HotWireSTEP Post-Processor)";
            map(end+1)   = NaN;
            lines(end+1) = "G21  (mm)";
            map(end+1)   = NaN;
            lines(end+1) = "G90  (absolute)";
            map(end+1)   = NaN;
            lines(end+1) = "G94  (feed per minute)";
            map(end+1)   = NaN;
            lines(end+1) = "";
            map(end+1)   = NaN;

            % Emit motion lines by phase
            for i = 1:size(ppL_yz,1)

                % Rapid phase (semantic): G0
                if i <= app.PP_RapidEndIndex
                    lines(end+1) = string(fmtMove("G0", i));
                    map(end+1)   = i;

                    % Insert ON after reaching last entry point
                    if i == app.PP_RapidEndIndex
                        lines(end+1) = sprintf("S%d M301", power);
                        map(end+1)   = NaN;

                        lines(end+1) = sprintf("G1 F%d", feed);
                        map(end+1)   = NaN;
                    end
                    continue;
                end

                % Lead-in + profile + lead-out: G1
                if i <= app.PP_LeadOutEndIndex
                    lines(end+1) = string(fmtMove("G1", i));
                    map(end+1)   = i;

                    % Insert OFF after reaching lead-out end (back to entry)
                    if i == app.PP_LeadOutEndIndex
                        lines(end+1) = "M302";
                        map(end+1)   = NaN;
                    end
                    continue;
                end

                % Return: G0
                lines(end+1) = string(fmtMove("G0", i));
                map(end+1)   = i;
            end

            lines(end+1) = "M30";
            map(end+1)   = NaN;

            % Store + show in UI
            app.PP_GCodeLines      = lines;
            app.PP_LineToPathIndex = map;

            if ~isempty(app.ListGCode) && isvalid(app.ListGCode)
                app.ListGCode.Items = cellstr(lines);
                if ~isempty(app.ListGCode.Items)
                    app.ListGCode.Value = app.ListGCode.Items{1};
                end
            end
            app.PP_SelectedLine = 1;

            if ~isempty(app.BtnSaveGCode) && isvalid(app.BtnSaveGCode)
                app.BtnSaveGCode.Enable = 'on';
            end

            % Plot init + first update
            if isempty(app.AxSim.Children)
                app.initSimulationPlot();
            end
            app.initPostPlot();
            app.updatePostPlotForSelectedLine(1);

        end

        function onPostLineSelected(app, src)
            % Use index, NOT string matching (lines repeat!)
            items = src.Items;
            if isempty(items)
                return;
            end

            % App Designer listbox: Value is the selected item text
            % Find ALL matches and choose the one closest to current index
            val = src.Value;
            matches = find(strcmp(items, val));

            if isempty(matches)
                k = 1;
            elseif isempty(app.PP_SelectedLine)
                k = matches(1);
            else
                % pick the closest match to current index
                [~, ii] = min(abs(matches - app.PP_SelectedLine));
                k = matches(ii);
            end

            app.PP_SelectedLine = k;
            app.updatePostPlotForSelectedLine(k);
        end

        function stepPostLine(app, delta)
            if isempty(app.ListGCode) || isempty(app.ListGCode.Items)
                return;
            end

            n = numel(app.ListGCode.Items);

            % Always step using the stored index
            if isempty(app.PP_SelectedLine) || app.PP_SelectedLine < 1
                cur = 1;
            else
                cur = app.PP_SelectedLine;
            end

            nxt = max(1, min(n, cur + delta));

            % Update state FIRST
            app.PP_SelectedLine = nxt;

            % Push index -> UI (never infer index from UI)
            app.ListGCode.Value = app.ListGCode.Items{nxt};

            % Update plot
            app.updatePostPlotForSelectedLine(nxt);
        end

        function onKeyPress(app, ~, event)
            % Only handle keys when Post tab is active
            if isempty(app.TabGroup) || app.TabGroup.SelectedTab ~= app.TabPostProcess
                return;
            end
            if isempty(app.ListGCode) || isempty(app.ListGCode.Items)
                return;
            end

            switch event.Key
                case 'downarrow'
                    app.stepPostLine(+1);
                case 'uparrow'
                    app.stepPostLine(-1);
                case 'pagedown'
                    app.stepPostLine(+10);
                case 'pageup'
                    app.stepPostLine(-10);
            end

        end

        function onSaveGCode(app)
            if isempty(app.PP_GCodeLines)
                uialert(app.UIFigure, 'No G-code generated yet. Click Generate first.', 'Save G-Code');
                return;
            end

            filter = {'*.gcode';'*.nc';'*.txt'};
            [file, path] = uiputfile(filter, 'Save G-Code', app.FieldFilename.Value);
            if isequal(file,0), return; end

            fullpath = fullfile(path, file);
            writelines(app.PP_GCodeLines, fullpath);

            uialert(app.UIFigure, ['Saved: ' fullpath], 'Save G-Code');
        end

        % ===========================================================
        % MOUSE-DRAG ROTATION FOR 3D AXES
        % ===========================================================
        function onMouseDown(app,~,~)
            % Only respond to left-click
            if ~strcmp(app.UIFigure.SelectionType,'normal')
                return;
            end

            % Check if the click is on the 3D axes (or its children)
            h = hittest(app.UIFigure);
            if isempty(h)
                return;
            end
            ax = ancestor(h,'axes');
            if isempty(ax) || ax ~= app.AxModel
                return;
            end

            % Start dragging
            app.IsDragging  = true;
            app.LastMousePos = app.UIFigure.CurrentPoint;
        end

        function onMouseMove(app,~,~)
            if ~app.IsDragging
                return;
            end
            if isempty(app.AxModel) || ~isvalid(app.AxModel)
                return;
            end

            cp = app.UIFigure.CurrentPoint;
            if any(isnan(app.LastMousePos))
                app.LastMousePos = cp;
                return;
            end

            delta = cp - app.LastMousePos;
            app.LastMousePos = cp;

            % Sensitivity
            rotSpeed = 0.3;  % tweak if too fast/slow

            dAz = -delta(1) * rotSpeed;  % horizontal mouse → azimuth
            dEl = -delta(2) * rotSpeed;  % vertical mouse → elevation

            camorbit(app.AxModel, dAz, dEl, 'camera');
        end

        function onMouseUp(app,~,~)
            app.IsDragging   = false;
            app.LastMousePos = [NaN NaN];
        end
        
        % ===========================================================
        % THEME HELPERS
        % ===========================================================         
        function applyTheme(app)
            t = app.getTheme();
            app.UIFigure.Color = t.sideBg;

            % All sidebar containers
            sidebars = {app.GLLeft, app.profilesLeft, app.BilletLeftPanel, app.MachineLeftPanel, app.CuttingLeftPanel, app.SimLeftPanel, app.PostLeftPanel};

            for i = 1:numel(sidebars)
                container = sidebars{i};
                if isempty(container) || ~isgraphics(container), continue; end

                % 1. Update the Main Grid background
                container.BackgroundColor = t.sideBg;

                % 2. Drill down to components
                allObjs = findall(container);
                for j = 1:numel(allObjs)
                    obj = allObjs(j);

                    % --- A. DETECT READOUTS ---
                    isReadout = false;
                    if ~isempty(app.BilletModelDimLabels) && any(obj == app.BilletModelDimLabels)
                        isReadout = true;
                    end

                    if isReadout
                        obj.BackgroundColor = t.readoutBg;
                        obj.FontColor       = t.readoutTxt;
                        continue; % Move to next object
                    end

                    % --- B. DETECT CONTAINERS (Panels/Inner Grids) ---
                    % These MUST match the sidebar background to stay "invisible"
                    if isa(obj, 'matlab.ui.container.Panel') || isa(obj, 'matlab.ui.container.GridLayout')
                        obj.BackgroundColor = t.sideBg;
                        continue;
                    end

                    % --- C. DETECT LABELS ---
                    if isa(obj, 'matlab.ui.control.Label')
                        obj.FontColor = t.labelCol;
                        % We make label backgrounds match the sidebar
                        obj.BackgroundColor = t.sideBg;
                        continue;
                    end

                    % --- D. INPUT FIELDS (Numeric, Text, etc.) ---
                    % WE DO NOTHING HERE.
                    % This allows them to keep the colors set in buildUI/getTheme.
                end
            end

            % Refresh machine plot for 3D background matching
            if app.TabGroup.SelectedTab == app.TabMachine
                app.refreshMachinePlot();
            end
        end

        function th = getTheme(app)
            % Central source for all App Colors
            if app.UIFigure.Color(1) < 0.5
                % DARK THEME
                th.sideBg      = [0.16 0.16 0.16];
                th.panelBg     = [0.12 0.12 0.12];
                th.labelCol    = [0.90 0.90 0.90];
                th.accentBg    = [0.30 0.35 0.45]; % Muted blue-grey for Dark
                th.editBg      = [0.24 0.24 0.24]; % Darker box for inputs
                th.editTxt     = [1.00 1.00 1.00]; % White text
                th.readoutBg   = [0.7 0.7 0.7]; % Fixed Pale Grey
                th.readoutTxt  = [0.2 0.2 0.2];
                th.inputBg     = [1.00 1.00 1.00];
                th.inputTxt    = [0.00 0.00 0.00];

                th.planeRed    = [0.96 0.06 0.06];
                th.planeGreen  = [0.20 1.00 0.35];
                th.planeRedTxt = [0.96 0.40 0.40];
                th.planeGreenTxt = [0.40 1.00 0.50];

                th.wireKerf  = [1.00 0.75 0.00]; % Warm "Hot Wire" path
                th.wireNeutral = [0.80 0.80 0.80]; % White/Grey for Machining View
                th.rawMeshCol  = [0.50 0.50 0.50]; % Dull grey for mesh slices
            else
                % LIGHT THEME
                th.sideBg      = [0.96 0.96 0.96];
                th.panelBg     = [0.90 0.90 0.90];
                th.labelCol    = [0.15 0.15 0.15];
                th.accentBg    = [0.70 0.70 0.80]; % Classic blue-grey for Light
                th.editBg      = [1.00 1.00 1.00]; % Pure white box for inputs
                th.editTxt     = [0.00 0.00 0.00]; % Black text
                th.readoutBg   = [0.4 0.4 0.4]; % Fixed Pale Grey
                th.readoutTxt  = [0.7 0.7 0.7];
                th.inputBg     = [1.00 1.00 1.00];
                th.inputTxt    = [0.00 0.00 0.00];

                th.planeRed    = [0.80 0.00 0.00];
                th.planeGreen  = [0.00 0.60 0.00];
                th.planeRedTxt = [0.60 0.00 0.00];
                th.planeGreenTxt = [0.00 0.40 0.00];

                th.wireKerf  = [1.00 0.75 0.00]; % Warm "Hot Wire" path
                th.wireNeutral = [0.20 0.20 0.20]; % Black/Dark Grey for Machining View
                th.rawMeshCol  = [0.70 0.70 0.70];
            end
        end

        function cols = getInteractionColors(app)
            t = app.getTheme();
            isDark = app.UIFigure.Color(1) < 0.5;

            cols = struct();

            if isDark
                % Dark Mode
                cols.StartActive   = [0.0 0.8 0.0]; % Bright Green
                cols.StartInactive = [0.15 0.25 0.15];

                % Entry & Entry 2 share colors
                cols.EntryActive   = [1.0 0.6 0.0]; % Bright Orange
                cols.EntryInactive = [0.30 0.20 0.10];

                cols.Entry2Active   = [1.0 0.6 0.0]; % Same as Entry 1
                cols.Entry2Inactive = [0.30 0.20 0.10];

                cols.TextActive    = [0 0 0];
                cols.TextInactive  = [0.9 0.9 0.9];
            else
                % Light Mode
                cols.StartActive   = [0.4 1.0 0.4];
                cols.StartInactive = [0.90 0.96 0.90];

                cols.EntryActive   = [1.0 0.7 0.4];
                cols.EntryInactive = [0.98 0.94 0.90];

                cols.Entry2Active   = [1.0 0.7 0.4];
                cols.Entry2Inactive = [0.98 0.94 0.90];

                cols.TextActive    = [0 0 0];
                cols.TextInactive  = [0 0 0];
            end
        end

    end
end
