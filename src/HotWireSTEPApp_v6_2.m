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
        SimTimer % timer object for animation
        SimTowerPathL % Nx3 %Physical Tower Paths (Projected)
        SimTowerPathR % Nx3

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
        % BUILD UI
        % ===========================================================
        function buildUI(app)

            % --- Main figure ---
            app.UIFigure = uifigure('Name','Hot Wire STEP App v6.2');
            app.UIFigure.CloseRequestFcn = @(src,event)app.onAppClose(src);
            app.UIFigure.WindowState = 'maximized';

            % --- UNPACK PALETTE (This fixes your "Unrecognized variable" error) ---
            t = app.getTheme();
            sideBg = t.sideBg; panelBg = t.panelBg; labelCol = t.labelCol;
            inputBg = t.inputBg; inputTxt = t.inputTxt;

            app.UIFigure.Color = sideBg; % Apply background

            % --- Tab group ---
            app.TabGroup = uitabgroup(app.UIFigure, ...
                'Units','normalized', ...
                'Position',[0 0 1 1]);

            app.TabModel    = uitab(app.TabGroup,'Title','Model');
            app.TabProfiles = uitab(app.TabGroup,'Title','Profiles'); % Profiles tab
            app.TabBillet   = uitab(app.TabGroup,'Title','Billet');   % NEW: Billet tab

            % -------------------------------------------------------
            % PROFILES TAB LAYOUT
            % Left: control panel (like model tab)
            % Right: 2D profiles (left on top, right on bottom)
            % -------------------------------------------------------
            app.GLProfiles = uigridlayout(app.TabProfiles,[1 2]);
            app.GLProfiles.ColumnWidth   = {320,'1x'};
            app.GLProfiles.RowHeight     = {'1x'};
            app.GLProfiles.Padding       = [10 10 10 10];
            app.GLProfiles.ColumnSpacing = 10;

            % ================================
            % LEFT CONTROL COLUMN (Profiles tab)
            % ================================
            app.profilesLeft = uigridlayout(app.GLProfiles,[6 1]);
            profilesLeft = app.profilesLeft; % This one line makes all your "profilesLeft" code below it work!
            profilesLeft.Layout.Column   = 1;
            profilesLeft.RowHeight       = {'fit','fit','fit','fit','1x','fit'};  % row 5 = spacer, row 6 = button
            profilesLeft.Padding         = [10 10 10 10];
            profilesLeft.BackgroundColor = sideBg;


            % --- Profile Sampling Panel (tolerance) ---
            tolPanel = uipanel(profilesLeft, ...
                'Title','Profile Sampling', ...
                'BackgroundColor',panelBg, ...
                'ForegroundColor',labelCol, ...
                'FontWeight','bold', ...
                'BorderType','line');
            tolPanel.Layout.Row = 1;

            % 2 rows:
            %   row 1: label + spinner
            %   row 2: read-only points label
            tolGrid = uigridlayout(tolPanel,[2 2]);
            tolGrid.ColumnWidth    = {'1x',90};
            tolGrid.RowHeight      = {'fit','fit'};
            tolGrid.Padding        = [10 5 10 5];
            tolGrid.ColumnSpacing  = 8;


            lblTol = uilabel(tolGrid, ...
                'Text','Profile Tolerance [mm]:', ...
                'HorizontalAlignment','right', ...
                'FontWeight','bold', ...
                'FontColor',labelCol);
            lblTol.Layout.Row    = 1;
            lblTol.Layout.Column = 1;

            app.ProfileTolSpinner = uispinner(tolGrid, ...
                'Limits',[HotWireSTEPApp_v6_2.MinProfileTolerance, ...
                HotWireSTEPApp_v6_2.MaxProfileTolerance], ...
                'Value',HotWireSTEPApp_v6_2.DefaultProfileTolerance, ...
                'Step',0.05, ...
                'ValueDisplayFormat','%.2f', ...
                'Tooltip','Maximum segment length along profile (mm)', ...
                'ValueChangedFcn',@(src,~)app.onProfileToleranceChanged(src));
            % Keep the stored tolerance in sync with the UI default
            app.ProfileTolerance = HotWireSTEPApp_v6_2.DefaultProfileTolerance;
            app.ProfileTolSpinner.Layout.Row    = 1;
            app.ProfileTolSpinner.Layout.Column = 2;

            % Read-only point-count label (L/R)
            app.ProfilePointCountLabel = uilabel(tolGrid, ...
                'Text','Number of Points (L/R): -- / --', ...
                'HorizontalAlignment','right', ...
                'FontColor',labelCol, ...
                'FontAngle','italic');
            app.ProfilePointCountLabel.Layout.Row    = 2;
            app.ProfilePointCountLabel.Layout.Column = [1 2];

            % --- Reset tolerance to default ---
            app.BtnResetProfileTol = uibutton(profilesLeft, ...
                'Text','Reset Tolerance', ...
                'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~)app.onResetProfileTolerance());
            app.BtnResetProfileTol.Layout.Row = 2;

            % --- Reset Profiles plot view (optional) ---
            app.BtnResetProfilesView = uibutton(profilesLeft, ...
                'Text','Reset Profiles View', ...
                'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~)app.resetProfilesView());
            app.BtnResetProfilesView.Layout.Row = 3;

            % --- Kerf Compensation Panel ---
            kerfPanel = uipanel(profilesLeft, ...
                'Title','Kerf Compensation', ...
                'BackgroundColor',panelBg, ...
                'ForegroundColor',labelCol, ...
                'FontWeight','bold', ...
                'BorderType','line');
            kerfPanel.Layout.Row = 4;

            % 2-row grid: row 1 = label+spinner, row 2 = "Apply kerf" button
            kerfGrid = uigridlayout(kerfPanel,[2 2]);
            % Match the offset panel style:
            % left column stretches, right column is a fixed-width spinner
            kerfGrid.ColumnWidth   = {'1x',90};
            kerfGrid.RowHeight     = {'fit','fit'};
            kerfGrid.Padding       = [10 5 10 5];
            kerfGrid.ColumnSpacing = 8;
            kerfGrid.RowSpacing    = 6;

            lblKerf = uilabel(kerfGrid, ...
                'Text','Kerf [mm]:', ...
                'HorizontalAlignment','right', ...
                'FontWeight','bold', ...
                'FontColor',labelCol);
            lblKerf.Layout.Row    = 1;
            lblKerf.Layout.Column = 1;

            app.KerfSpinner = uispinner(kerfGrid, ...
                'Limits',[HotWireSTEPApp_v6_2.MinKerf, ...
                HotWireSTEPApp_v6_2.MaxKerf], ...
                'Value',HotWireSTEPApp_v6_2.DefaultKerf, ...
                'Step',0.1, ...
                'ValueDisplayFormat','%.2f', ...
                'Tooltip','Positive kerf expands profile (wire centreline offset)', ...
                'ValueChangedFcn',@(src,~)app.onKerfChanged(src));
            % Keep stored kerf value in sync with the UI default
            app.KerfValue = HotWireSTEPApp_v6_2.DefaultKerf;
            app.KerfSpinner.Layout.Row    = 1;
            app.KerfSpinner.Layout.Column = 2;

            % --- Apply kerf button (generates kerf path when pressed) ---
            app.BtnApplyKerf = uibutton(kerfGrid, ...
                'Text','Apply Kerf Offset', ...
                'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~)app.onApplyKerf());
            app.BtnApplyKerf.Layout.Row    = 2;
            app.BtnApplyKerf.Layout.Column = [1 2];

            % (rows 5–6 of profilesLeft left free for future options)
            % --- Spacer to push the button to the bottom ---
            spProfilesBottom = uilabel(profilesLeft, ...
                'Text','');
            spProfilesBottom.Layout.Row = 5;

            % --- Continue button at the bottom of the left panel ---
            app.BtnProfilesContinue = uibutton(profilesLeft, ...
                'Text','Continue →', ...
                'FontWeight','bold', ...
                'Enable', 'off', ...                     % START DISABLED
                'BackgroundColor',[0.3 0.3 0.3], ...      % START GREY'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~)app.onContinueFromProfiles());
            app.BtnProfilesContinue.Layout.Row = 6;

            % ================================
            % RIGHT COLUMN: 2D PROFILE AXES
            % ================================
            profilesRight = uigridlayout(app.GLProfiles,[2 1]);
            profilesRight.Layout.Column   = 2;
            profilesRight.RowHeight       = {'1x','1x'};
            profilesRight.ColumnWidth     = {'1x'};
            profilesRight.Padding         = [0 0 0 0];
            profilesRight.RowSpacing      = 10;

            % Left profile axes (top)
            app.AxLeftProfile = uiaxes(profilesRight);
            app.AxLeftProfile.Layout.Row    = 1;
            app.AxLeftProfile.Layout.Column = 1;
            app.AxLeftProfile.BackgroundColor = [0.11 0.11 0.11];
            title(app.AxLeftProfile,'Left Profile');
            xlabel(app.AxLeftProfile,'Y (mm)');
            ylabel(app.AxLeftProfile,'Z (mm)');
            grid(app.AxLeftProfile,'on');
            % True-scale Y–Z: 1 mm in Y = 1 mm in Z, but the axes
            % box size itself is controlled by the grid layout.
            app.AxLeftProfile.DataAspectRatio        = [1 1 1];
            app.AxLeftProfile.DataAspectRatioMode    = 'manual';
            app.AxLeftProfile.PlotBoxAspectRatioMode = 'auto';

            % Right profile axes (bottom)
            app.AxRightProfile = uiaxes(profilesRight);
            app.AxRightProfile.Layout.Row    = 2;
            app.AxRightProfile.Layout.Column = 1;
            app.AxRightProfile.BackgroundColor = [0.11 0.11 0.11];
            title(app.AxRightProfile,'Right Profile');
            xlabel(app.AxRightProfile,'Y (mm)');
            ylabel(app.AxRightProfile,'Z (mm)');
            grid(app.AxRightProfile,'on');
            app.AxRightProfile.DataAspectRatio        = [1 1 1];
            app.AxRightProfile.DataAspectRatioMode    = 'manual';
            app.AxRightProfile.PlotBoxAspectRatioMode = 'auto';

            % -------------------------------------------------------
            % BILLET TAB LAYOUT
            % Left: control panel
            % Right: 3 orthographic views (Top / Front / Right)
            % -------------------------------------------------------
            app.GLBillet = uigridlayout(app.TabBillet,[1 2]);
            app.GLBillet.ColumnWidth   = {320,'1x'};
            app.GLBillet.RowHeight     = {'1x'};
            app.GLBillet.Padding       = [10 10 10 10];
            app.GLBillet.ColumnSpacing = 10;

            % ================================
            % LEFT CONTROL COLUMN (Billet tab)
            % ================================
            app.BilletLeftPanel = uigridlayout(app.GLBillet,[7 1]); % 7 rows total
            app.BilletLeftPanel.Layout.Column   = 1;
            % Row 1-5: controls, Row 6: warning message (expands), Row 7: button
            app.BilletLeftPanel.RowHeight       = {'fit','fit','fit','fit','fit','1x','fit'};
            app.BilletLeftPanel.Padding         = [10 10 10 10];
            app.BilletLeftPanel.BackgroundColor = sideBg;

            % --- [Auto-fit Billet] button (row 1)
            app.BtnAutoFitBillet = uibutton(app.BilletLeftPanel, ...
                'Text','Auto-fit Billet', ...
                'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~)app.onAutoFitBillet());
            app.BtnAutoFitBillet.Layout.Row = 1;

            % --- Billet size controls block (row 2) ---
            billetSizePanel = uipanel(app.BilletLeftPanel);
            billetSizePanel.Title = 'Billet Size Controls';
            billetSizePanel.BackgroundColor = panelBg;
            billetSizePanel.ForegroundColor = labelCol;
            billetSizePanel.FontWeight = 'bold';
            billetSizePanel.Layout.Row = 2;

            sizeOuter = uigridlayout(billetSizePanel, [1 1]);
            sizeOuter.Padding = [5 5 5 5];

            % 6-Column Symmetric Layout
            sizeGrid = uigridlayout(sizeOuter, [4 6]);
            sizeGrid.ColumnWidth = {35, 65, 20, 65, 20, 65};
            sizeGrid.RowHeight = {'fit','fit','fit','fit'};
            sizeGrid.Padding = [4 4 4 4];
            sizeGrid.ColumnSpacing = 4;
            sizeGrid.RowSpacing = 4;

            % --- Size Headings ---
            hS1 = uilabel(sizeGrid, 'Text','Axis', 'FontWeight','bold', 'FontSize',10, 'HorizontalAlignment','center', 'FontColor',labelCol);
            hS1.Layout.Row = 1; hS1.Layout.Column = 1;

            hS2 = uilabel(sizeGrid, 'Text','Stock [mm]', 'FontWeight','bold', 'FontSize',10, 'HorizontalAlignment','center', 'FontColor',labelCol);
            hS2.Layout.Row = 1; hS2.Layout.Column = [3 5];

            hS3 = uilabel(sizeGrid, 'Text','Model', 'FontWeight','bold', 'FontSize',10, 'HorizontalAlignment','center', 'FontColor',labelCol);
            hS3.Layout.Row = 1; hS3.Layout.Column = 6;

            axisLabels = {'X','Y','Z'};
            app.BilletSizeEdits      = gobjects(1,3);
            app.BilletSizeMinusBtns  = gobjects(1,3);
            app.BilletSizePlusBtns   = gobjects(1,3);
            app.BilletModelDimLabels = gobjects(1,3);

            t_init = app.getTheme(); % Get the colors defined in getTheme

            for i = 1:3
                r = i + 1;
                lblA = uilabel(sizeGrid, 'Text', axisLabels{i}, 'FontWeight','bold', 'HorizontalAlignment','center', 'FontColor',labelCol);
                lblA.Layout.Row = r; lblA.Layout.Column = 1;

                lblSp = uilabel(sizeGrid, 'Text','', 'BackgroundColor', panelBg);
                lblSp.Layout.Row = r; lblSp.Layout.Column = 2;

                app.BilletSizeMinusBtns(i) = uibutton(sizeGrid, 'Text','-', 'FontWeight','bold', 'ButtonPushedFcn', @(~,~)app.onBilletSizeStep(i,-1));
                app.BilletSizeMinusBtns(i).Layout.Row = r; app.BilletSizeMinusBtns(i).Layout.Column = 3;

                app.BilletSizeEdits(i) = uieditfield(sizeGrid,'numeric', 'HorizontalAlignment','center', 'ValueDisplayFormat','%.1f', ...
                    'BackgroundColor',[0.7 0.7 0.8], 'FontColor',[0 0 0], 'ValueChangedFcn', @(src,~)app.onBilletSizeEdited(i,src));
                app.BilletSizeEdits(i).Layout.Row = r; app.BilletSizeEdits(i).Layout.Column = 4;

                app.BilletSizePlusBtns(i) = uibutton(sizeGrid, 'Text','+', 'FontWeight','bold', 'ButtonPushedFcn', @(~,~)app.onBilletSizeStep(i,+1));
                app.BilletSizePlusBtns(i).Layout.Row = r; app.BilletSizePlusBtns(i).Layout.Column = 5;

                app.BilletModelDimLabels(i) = uilabel(sizeGrid, 'Text','(---)', 'HorizontalAlignment','center', ...
                    'BackgroundColor', t.readoutBg, 'FontColor', t.readoutTxt);
                app.BilletModelDimLabels(i).Layout.Row = r; app.BilletModelDimLabels(i).Layout.Column = 6;
            end

            % --- [Auto-position Model] & [Reset] ---
            app.BtnAutoPositionModel = uibutton(app.BilletLeftPanel, 'Text','Auto-position Model', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onAutoPositionModel());
            app.BtnAutoPositionModel.Layout.Row = 3;

            app.BtnResetPosition = uibutton(app.BilletLeftPanel, 'Text','Reset Position', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetPosition());
            app.BtnResetPosition.Layout.Row = 4;

            % --- Billet position controls block (row 5) ---
            posPanel = uipanel(app.BilletLeftPanel, 'Title','Billet Position Controls', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold');
            posPanel.Layout.Row = 5;

            posGrid = uigridlayout(posPanel, [4 6]);
            posGrid.ColumnWidth = {35, 65, 20, 65, 20, 65};
            posGrid.RowHeight = {'fit','fit','fit','fit'};
            posGrid.Padding = [4 4 4 4];
            posGrid.ColumnSpacing = 4;
            posGrid.RowSpacing = 4;

            hP1 = uilabel(posGrid, 'Text','Axis', 'FontWeight','bold', 'FontSize',10, 'HorizontalAlignment','center', 'FontColor',labelCol);
            hP1.Layout.Row = 1; hP1.Layout.Column = 1;

            hP2 = uilabel(posGrid, 'Text','-ive Gap', 'FontWeight','bold', 'FontSize',10, 'HorizontalAlignment','center', 'FontColor',labelCol);
            hP2.Layout.Row = 1; hP2.Layout.Column = 2;

            hP3 = uilabel(posGrid, 'Text','Shift [mm]', 'FontWeight','bold', 'FontSize',10, 'HorizontalAlignment','center', 'FontColor',labelCol);
            hP3.Layout.Row = 1; hP3.Layout.Column = [3 5];

            hP4 = uilabel(posGrid, 'Text','+ive Gap', 'FontWeight','bold', 'FontSize',10, 'HorizontalAlignment','center', 'FontColor',labelCol);
            hP4.Layout.Row = 1; hP4.Layout.Column = 6;

            app.BilletNegOffsetEdits    = gobjects(1,3);
            app.BilletCenterOffsetEdits = gobjects(1,3);
            app.BilletPosOffsetEdits    = gobjects(1,3);

            for k = 1:3
                rk = k + 1;
                lblB = uilabel(posGrid, 'Text', axisLabels{k}, 'FontWeight','bold', 'HorizontalAlignment','center', 'FontColor',labelCol);
                lblB.Layout.Row = rk; lblB.Layout.Column = 1;

                app.BilletNegOffsetEdits(k) = uieditfield(posGrid,'numeric', 'HorizontalAlignment','center', 'ValueDisplayFormat','%.1f', ...
                    'BackgroundColor',inputBg, 'FontColor', inputTxt, 'ValueChangedFcn', @(src,~)app.onBilletOffsetEdited(k,"neg",src));
                app.BilletNegOffsetEdits(k).Layout.Row = rk; app.BilletNegOffsetEdits(k).Layout.Column = 2;

                btnM2 = uibutton(posGrid, 'Text','-', 'FontWeight','bold', 'ButtonPushedFcn', @(~,~)app.onBilletShift(k,-0.5));
                btnM2.Layout.Row = rk; btnM2.Layout.Column = 3;

                app.BilletCenterOffsetEdits(k) = uieditfield(posGrid,'numeric', 'HorizontalAlignment','center', 'ValueDisplayFormat','%.1f', ...
                    'BackgroundColor',[0.7 0.7 0.8], 'FontColor',[0 0 0], 'ValueChangedFcn', @(src,~)app.onBilletOffsetEdited(k,"center",src));
                app.BilletCenterOffsetEdits(k).Layout.Row = rk; app.BilletCenterOffsetEdits(k).Layout.Column = 4;

                btnP2 = uibutton(posGrid, 'Text','+', 'FontWeight','bold', 'ButtonPushedFcn', @(~,~)app.onBilletShift(k,+0.5));
                btnP2.Layout.Row = rk; btnP2.Layout.Column = 5;

                app.BilletPosOffsetEdits(k) = uieditfield(posGrid,'numeric', 'HorizontalAlignment','center', 'ValueDisplayFormat','%.1f', ...
                    'BackgroundColor',inputBg, 'FontColor', inputTxt, 'ValueChangedFcn', @(src,~)app.onBilletOffsetEdited(k,"pos",src));
                app.BilletPosOffsetEdits(k).Layout.Row = rk; app.BilletPosOffsetEdits(k).Layout.Column = 6;
            end

            % --- Message Label (row 6 - replaces old spacer) ---
            app.BilletMessageLabel = uilabel(app.BilletLeftPanel, ...
                'Text','', ...
                'WordWrap','on', ...
                'FontWeight','bold', ...
                'FontColor', [1 1 1], ...
                'VerticalAlignment','top');
            app.BilletMessageLabel.Layout.Row = 6;

            % --- [Continue] button (row 7 – bottom, green) ---
            app.BtnBilletContinue = uibutton(app.BilletLeftPanel, ...
                'Text','Continue', ...
                'FontWeight','bold', ...
                'BackgroundColor',[0.1 0.6 0.1], ...
                'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~)app.onContinue());
            app.BtnBilletContinue.Layout.Row = 7;

            % ================================
            % RIGHT COLUMN: BILLET PLOTS
            % ================================
            app.BilletRightPanel = uigridlayout(app.GLBillet,[2 2]);
            app.BilletRightPanel.Layout.Column   = 2;
            app.BilletRightPanel.RowHeight       = {'1x','1x'};
            app.BilletRightPanel.ColumnWidth     = {'1x','1x'};
            app.BilletRightPanel.Padding         = [0 0 0 0];
            app.BilletRightPanel.RowSpacing      = 10;
            app.BilletRightPanel.ColumnSpacing   = 10;

            % Top view (XY) – spans both columns in row 1
            app.AxBilletTop = uiaxes(app.BilletRightPanel);
            app.AxBilletTop.Layout.Row    = 1;
            app.AxBilletTop.Layout.Column = 1;
            app.AxBilletTop.BackgroundColor = [0.11 0.11 0.11];
            title(app.AxBilletTop,'Top View (X/Y)');
            xlabel(app.AxBilletTop,'X (mm)');
            ylabel(app.AxBilletTop,'Y (mm)');
            grid(app.AxBilletTop,'on');
            app.AxBilletTop.DataAspectRatio        = [1 1 1];
            app.AxBilletTop.DataAspectRatioMode    = 'manual';
            app.AxBilletTop.PlotBoxAspectRatioMode = 'auto';

            % Front view (XZ) – row 2, col 1
            app.AxBilletFront = uiaxes(app.BilletRightPanel);
            app.AxBilletFront.Layout.Row    = 2;
            app.AxBilletFront.Layout.Column = 1;
            app.AxBilletFront.BackgroundColor = [0.11 0.11 0.11];
            title(app.AxBilletFront,'Front View (X/Z)');
            xlabel(app.AxBilletFront,'X (mm)');
            ylabel(app.AxBilletFront,'Z (mm)');
            grid(app.AxBilletFront,'on');
            app.AxBilletFront.DataAspectRatio        = [1 1 1];
            app.AxBilletFront.DataAspectRatioMode    = 'manual';
            app.AxBilletFront.PlotBoxAspectRatioMode = 'auto';

            % Right view (YZ) – row 2, col 2
            app.AxBilletRight = uiaxes(app.BilletRightPanel);
            app.AxBilletRight.Layout.Row    = 2;
            app.AxBilletRight.Layout.Column = 2;
            app.AxBilletRight.BackgroundColor = [0.11 0.11 0.11];
            title(app.AxBilletRight,'Right View (Y/Z)');
            xlabel(app.AxBilletRight,'Y (mm)');
            ylabel(app.AxBilletRight,'Z (mm)');
            grid(app.AxBilletRight,'on');
            app.AxBilletRight.DataAspectRatio        = [1 1 1];
            app.AxBilletRight.DataAspectRatioMode    = 'manual';
            app.AxBilletRight.PlotBoxAspectRatioMode = 'auto';

            % --- Main layout: left controls / right plot ---
            app.GLModel = uigridlayout(app.TabModel,[1 2]);
            app.GLModel.ColumnWidth   = {320,'1x'};
            app.GLModel.RowHeight     = {'1x'};
            app.GLModel.Padding       = [10 10 10 10];
            app.GLModel.ColumnSpacing = 10;

            % --- Left control column ---
            app.GLLeft = uigridlayout(app.GLModel,[16 1]);
            app.GLLeft.Layout.Column = 1;
            app.GLLeft.Padding       = [10 10 10 10];

            app.GLLeft.RowHeight = repmat({'fit'},1,16);
            app.GLLeft.RowHeight{15} = '1x';   % row 15 = spacer
            % row 16 stays 'fit' so the buttons sit at the bottom
            app.GLLeft.BackgroundColor = sideBg;


            % -------------------------------------------------------
            % FILE IMPORT BUTTONS
            % -------------------------------------------------------
            app.BtnImportSTEP = uibutton(app.GLLeft, ...
                'Text','Import STEP (recommended)', ...
                'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~)app.onImportSTEP());
            app.BtnImportSTEP.Layout.Row = 1;

            app.BtnImportSTL = uibutton(app.GLLeft, ...
                'Text','Import STL', ...
                'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~)app.onImportSTL());
            app.BtnImportSTL.Layout.Row = 2;

            % -------------------------------------------------------
            % CURRENT FILE LABEL
            % -------------------------------------------------------
            app.FileLabel = uilabel(app.GLLeft, ...
                'Text','Current File: ---', ...
                'FontWeight','bold', ...
                'HorizontalAlignment','left', ...
                'FontColor',labelCol);
            app.FileLabel.Layout.Row = 3;

            % Spacer
            sp = uilabel(app.GLLeft,'Text',"");
            sp.Layout.Row = 4;

            % -------------------------------------------------------
            % STRAIGHT / TAPER SWITCH (Fixed Background + Faint Border)
            % -------------------------------------------------------
            cutPanel = uipanel(app.GLLeft, ...
                'BackgroundColor', sideBg, ...
                'BorderType', 'line', ... % Adds the faint border
                'Title', '');
            cutPanel.Layout.Row = 5;

            cutGrid = uigridlayout(cutPanel,[1 3]);
            cutGrid.ColumnWidth = {'1x','fit','1x'};
            cutGrid.Padding     = [10 0 10 0];
            cutGrid.RowSpacing  = 0;
            cutGrid.ColumnSpacing = 0;

            % Match the panel color exactly to avoid the error
            cutGrid.BackgroundColor = sideBg;

            spL = uilabel(cutGrid,'Text',"");
            spL.Layout.Column = 1;

            app.TaperToggle = uiswitch(cutGrid,'slider', ...
                'Items',{'Straight','Tapered'}, ...
                'Value','Straight', ...
                'ValueChangedFcn',@(~,~)app.onTaperModeChanged());
            app.TaperToggle.Layout.Column = 2;

            spR = uilabel(cutGrid,'Text',"");
            spR.Layout.Column = 3;

            % Spacer
            sp = uilabel(app.GLLeft,'Text',"");
            sp.Layout.Row = 6;

            % -------------------------------------------------------
            % ROTATION CONTROL PANEL
            % -------------------------------------------------------
            rotPanel = uipanel(app.GLLeft, ...
                'Title','Model Orientation Controls', ...
                'BackgroundColor',panelBg, ...
                'FontWeight','bold', ...
                'ForegroundColor',labelCol);
            rotPanel.Layout.Row = 7;

            outer = uigridlayout(rotPanel,[1 3]);
            outer.ColumnWidth = {'1x','fit','1x'};
            outer.RowHeight   = {'fit'};
            outer.Padding     = [5 5 5 5];

            app.RotGrid = uigridlayout(outer,[3 4]);
            app.RotGrid.Layout.Column = 2;
            app.RotGrid.ColumnWidth   = {'fit','fit',70,'fit'};
            app.RotGrid.RowHeight     = {'fit','fit','fit'};
            app.RotGrid.Padding       = [10 10 10 10];
            app.RotGrid.ColumnSpacing = 8;

            axesLabels = {'X','Y','Z'};
            app.RotEdit = gobjects(1,3);

            for i = 1:3
                lbl = uilabel(app.RotGrid, ...
                    'Text',axesLabels{i}, ...
                    'FontWeight','bold', ...
                    'HorizontalAlignment','center');
                lbl.Layout.Row    = i;
                lbl.Layout.Column = 1;

                btnNeg = uibutton(app.RotGrid,'Text','-90°', ...
                    'ButtonPushedFcn',@(~,~)app.rotateModel([axesLabels{i} 'm']));
                btnNeg.Layout.Row    = i;
                btnNeg.Layout.Column = 2;

                app.RotEdit(i) = uieditfield(app.RotGrid,'numeric', ...
                    'Limits',[0 360], ...
                    'Value',0, ...
                    'HorizontalAlignment','center', ...
                    'ValueDisplayFormat','%.0f°', ...
                    'ValueChangedFcn',@(src,~)app.updateRotation(axesLabels{i},src.Value));
                app.RotEdit(i).Layout.Row    = i;
                app.RotEdit(i).Layout.Column = 3;

                btnPos = uibutton(app.RotGrid,'Text','+90°', ...
                    'ButtonPushedFcn',@(~,~)app.rotateModel([axesLabels{i} 'p']));
                btnPos.Layout.Row    = i;
                btnPos.Layout.Column = 4;
            end

            % -------------------------------------------------------
            % RESET ORIENTATION / RESET PLOT VIEW
            % -------------------------------------------------------
            app.BtnResetOrientation = uibutton(app.GLLeft, ...
                'Text','Reset Orientation', ...
                'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~)app.resetOrientation());
            app.BtnResetOrientation.Layout.Row = 8;

            app.BtnResetPlot = uibutton(app.GLLeft, ...
                'Text','Reset Plot View', ...
                'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~)app.resetPlotView());
            app.BtnResetPlot.Layout.Row = 9;

            % Spacer
            sp = uilabel(app.GLLeft,'Text',"");
            sp.Layout.Row = 10;

            % -------------------------------------------------------
            % PLANE OFFSETS PANEL (with Reset Planes)
            % -------------------------------------------------------
            offsetPanel = uipanel(app.GLLeft,...
                'BackgroundColor',panelBg,...
                'BorderType','line');
            offsetPanel.Layout.Row = 11;

            offsetGrid = uigridlayout(offsetPanel,[3 2]);
            offsetGrid.ColumnWidth = {'1x',90};
            offsetGrid.RowHeight   = {'fit','fit','fit'};
            offsetGrid.Padding     = [10 10 10 10];
            offsetGrid.RowSpacing  = 5;

            % Theme-aware label colours
            if app.UIFigure.Color(1) < 0.5
                labelColor = [1 1 1];
                valueColor = [0 0 0];
            else
                labelColor = [0 0 0];
                valueColor = [0 0 0];
            end

            % Left plane
            lblLeft = uilabel(offsetGrid,...
                'Text','Left Plane Offset [mm]:',...
                'HorizontalAlignment','right',...
                'FontWeight','bold');
            lblLeft.Layout.Row    = 1;
            lblLeft.Layout.Column = 1;


            app.NumLeftOffset = uispinner(offsetGrid, ...
                'Limits',[-1000 1000], ...
                'Value',0, ...
                'Step',1, ...
                'ValueDisplayFormat','%.2f', ...
                'FontColor',valueColor, ...
                'BackgroundColor',[0.96 0.86 0.86], ...
                'ValueChangedFcn',@(src,evt)app.onPlaneOffsetChanged(src,evt));
            app.NumLeftOffset.Layout.Row    = 1;
            app.NumLeftOffset.Layout.Column = 2;

            % Right plane
            lblRight = uilabel(offsetGrid,...
                'Text','Right Plane Offset [mm]:',...
                'HorizontalAlignment','right',...
                'FontWeight','bold');
            lblRight.Layout.Row    = 2;
            lblRight.Layout.Column = 1;

            app.NumRightOffset = uispinner(offsetGrid, ...
                'Limits',[-1000 1000], ...
                'Value',0, ...
                'Step',1, ...
                'ValueDisplayFormat','%.2f', ...
                'FontColor',valueColor, ...
                'BackgroundColor',[0.86 0.96 0.86], ...
                'ValueChangedFcn',@(src,evt)app.onPlaneOffsetChanged(src,evt));
            app.NumRightOffset.Layout.Row    = 2;
            app.NumRightOffset.Layout.Column = 2;

            % Reset planes button on row 3
            app.BtnResetPlanes = uibutton(offsetGrid, ...
                'Text','Reset Planes', ...
                'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~)app.resetPlanes());
            app.BtnResetPlanes.Layout.Row    = 3;
            app.BtnResetPlanes.Layout.Column = [1 2];

            % -------------------------------------------------------
            % GENERATE PROFILES / CONTINUE BUTTONS (stubs)
            % -------------------------------------------------------
            spModelBottom = uilabel(app.GLLeft, 'Text','');
            spModelBottom.Layout.Row = 15;

            btnPanel = uipanel(app.GLLeft, ...
                'BackgroundColor',[0.16 0.16 0.16], ...
                'BorderType','none');
            btnPanel.Layout.Row = 16;

            btnGrid = uigridlayout(btnPanel,[1 2]);
            btnGrid.ColumnWidth = {'1x','1x'};
            btnGrid.ColumnSpacing = 10;
            btnGrid.Padding = [0 0 0 0];

            app.BtnGenerateProfiles = uibutton(btnGrid, ...
                'Text','Generate Profiles', ...
                'FontWeight','bold', ...
                'BackgroundColor',[0.15 0.45 0.8], ...
                'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~)app.onGenerateProfiles());
            app.BtnGenerateProfiles.Layout.Column = 1;

            app.BtnContinue = uibutton(btnGrid, ...
                'Text','Continue →', ...
                'FontWeight','bold', ...
                'BackgroundColor',[0.3 0.3 0.3], ...
                'FontColor',[0.8 0.8 0.8], ...
                'Enable','off', ...
                'ButtonPushedFcn',@(~,~)app.onContinue());
            app.BtnContinue.Layout.Column = 2;

            % -------------------------------------------------------
            % RIGHT-SIDE 3D AXES
            % -------------------------------------------------------
            app.AxModel = uiaxes(app.GLModel);
            app.AxModel.Layout.Column   = 2;
            app.AxModel.BackgroundColor = [0.11 0.11 0.11];

            % Hide the built-in axes toolbar so our custom mouse
            % rotation isn't fighting the zoom/pan tools.
            %app.AxModel.Toolbar.Visible = 'off';

            % Default labels to reserve space
            xlabel(app.AxModel,'X (mm)','FontWeight','bold');
            ylabel(app.AxModel,'Y (mm)','FontWeight','bold');
            zlabel(app.AxModel,'Z (mm)','FontWeight','bold');

            drawnow;
            pause(0.02);
            drawnow;

            grid(app.AxModel,'on');
            view(app.AxModel,3);

            % Ensure additional plots (planes, profiles) don't wipe the model
            hold(app.AxModel,'on');
            app.AxModel.NextPlot = 'add';

            grid(app.AxModel,'on');
            view(app.AxModel,3);

            % Ensure additional plots (planes, profiles) don't wipe the model
            hold(app.AxModel,'on');
            app.AxModel.NextPlot = 'add';

            % ===========================================================
            % 4. MACHINE TAB
            % ===========================================================
            app.TabMachine = uitab(app.TabGroup, 'Title', 'Machine');
            app.GLMachine = uigridlayout(app.TabMachine, [1 2]);
            app.GLMachine.ColumnWidth = {320, '1x'};
            app.GLMachine.Padding = [10 10 10 10];

            % --- Left Panel ---
            app.MachineLeftPanel = uigridlayout(app.GLMachine, [6 1]);
            app.MachineLeftPanel.RowHeight = {'fit','fit','fit','fit','1x','fit'};
            app.MachineLeftPanel.Padding = [10 10 10 10];
            app.MachineLeftPanel.BackgroundColor = sideBg;

            % 1. View Controls (New)
            pMView = uipanel(app.MachineLeftPanel, 'Title','View', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pMView.Layout.Row = 1;
            gMView = uigridlayout(pMView, [1 2]); gMView.Padding=[5 5 5 5]; gMView.BackgroundColor=panelBg;
            btnMMach = uibutton(gMView, 'Text','Machine View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetMachineViewMachine());
            btnMBill = uibutton(gMView, 'Text','Billet View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetMachineViewBillet());

            % 2. Placement
            pMPlace = uipanel(app.MachineLeftPanel, 'Title','Billet Placement', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold');
            pMPlace.Layout.Row = 2;
            gMPlace = uigridlayout(pMPlace, [4 2]); gMPlace.ColumnWidth={'1x',110}; gMPlace.Padding=[10 5 10 5]; gMPlace.BackgroundColor=panelBg;

            lblMAx = uilabel(gMPlace, 'Text','Axis', 'FontWeight','bold', 'FontColor',labelCol); lblMAx.Layout.Row=1; lblMAx.Layout.Column=1;
            lblMPos = uilabel(gMPlace, 'Text','Pos [mm]', 'FontWeight','bold', 'FontColor',labelCol); lblMPos.Layout.Row=1; lblMPos.Layout.Column=2;

            mAxisLabels = {'X (Machine)','Y (Machine)','Z (Machine)'};
            app.MachinePosSpinners = gobjects(1,3);
            for i=1:3
                lblMAxi = uilabel(gMPlace, 'Text',mAxisLabels{i}, 'FontColor',labelCol);
                lblMAxi.Layout.Row=i+1; lblMAxi.Layout.Column=1;
                sM = uispinner(gMPlace, 'Limits',[-500 2000], 'Value',app.MachineBilletPos(i), 'ValueDisplayFormat','%.2f', 'Step',1.0, 'ValueChangedFcn',@(src,~)app.onMachinePosEdited(i,src));
                sM.Layout.Row=i+1; sM.Layout.Column=2;
                app.MachinePosSpinners(i) = sM;
            end

            % 3. Reset Button
            btnMReset = uibutton(app.MachineLeftPanel, 'Text','Reset Billet Position', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetMachineBilletPosition());
            btnMReset.Layout.Row = 3;

            % 4. Message
            app.MachineMessageLabel = uilabel(app.MachineLeftPanel, 'Text','Machine configuration valid.', 'WordWrap','on', 'FontWeight','bold', 'FontColor',[1 1 1], 'VerticalAlignment','top');
            app.MachineMessageLabel.Layout.Row = 4;

            % 5. Spacer (Implicit '1x' Row 5)

            % 6. Continue
            app.BtnMachineContinue = uibutton(app.MachineLeftPanel, 'Text','Continue', 'FontWeight','bold', 'BackgroundColor',[0.1 0.6 0.1], 'FontColor',[1 1 1], 'ButtonPushedFcn',@(~,~)app.onContinue());
            app.BtnMachineContinue.Layout.Row = 6;

            % Right Plot
            app.AxMachine = uiaxes(app.GLMachine); app.AxMachine.Layout.Column=2; app.AxMachine.BackgroundColor=[0.05 0.05 0.05];
            grid(app.AxMachine,'on'); view(app.AxMachine,3); hold(app.AxMachine,'on');

            % ===========================================================
            % 5. CUTTING STRATEGY TAB
            % ===========================================================
            app.TabCutting = uitab(app.TabGroup, 'Title', 'Cutting Strategy');

            app.GLCutting = uigridlayout(app.TabCutting, [1 2]);
            app.GLCutting.ColumnWidth   = {320, '1x'};
            app.GLCutting.Padding       = [10 10 10 10];
            app.GLCutting.ColumnSpacing = 10;

            % --- Left Control Column ---
            app.CuttingLeftPanel = uigridlayout(app.GLCutting, [7 1]);
            % Rows: View(1), Auto(2), Modes(3), Interaction(4), Spacer(5), Continue(7)
            % Row 5 ('1x') pushes the Continue button (Row 7) to the bottom
            app.CuttingLeftPanel.RowHeight = {'fit','fit','fit','fit','1x','fit','fit'};
            app.CuttingLeftPanel.Padding   = [10 10 10 10];
            app.CuttingLeftPanel.BackgroundColor = sideBg;

            % 1. VIEW CONTROLS
            p_C_View = uipanel(app.CuttingLeftPanel, 'Title','View', ...
                'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'BorderType','line');
            p_C_View.Layout.Row = 1;

            g_C_View = uigridlayout(p_C_View, [1 2]);
            g_C_View.Padding=[5 5 5 5]; g_C_View.ColumnSpacing=5; g_C_View.BackgroundColor=panelBg;

            btn_C_VM = uibutton(g_C_View, 'Text','Machine View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetCuttingViewMachine());
            btn_C_VM.Layout.Column = 1;

            btn_C_VB = uibutton(g_C_View, 'Text','Billet View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetCuttingViewBillet());
            btn_C_VB.Layout.Column = 2;

            % 2. AUTO TOOLS
            p_C_Auto = uipanel(app.CuttingLeftPanel, 'Title','Auto Tools', ...
                'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'BorderType','line');
            p_C_Auto.Layout.Row = 2;

            g_C_Auto = uigridlayout(p_C_Auto, [1 2]);
            g_C_Auto.Padding=[5 5 5 5]; g_C_Auto.ColumnSpacing=5; g_C_Auto.BackgroundColor=panelBg;

            app.btnAutoStart = uibutton(g_C_Auto, 'Text','Auto Start', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onAutoStart());
            app.btnAutoStart.Layout.Column = 1;

            app.btnAutoEntry = uibutton(g_C_Auto, 'Text','Auto Entry', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onAutoEntry());
            app.btnAutoEntry.Layout.Column = 2;

            % 3. MODES
            p_C_Mode = uipanel(app.CuttingLeftPanel, 'Title','Modes', ...
                'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'BorderType','line');
            p_C_Mode.Layout.Row = 3;

            g_C_Mode = uigridlayout(p_C_Mode, [3 2]);
            g_C_Mode.RowHeight = {'fit','fit','fit'};
            g_C_Mode.ColumnWidth = {75, '1x'};
            g_C_Mode.Padding=[5 5 5 5]; g_C_Mode.RowSpacing=8; g_C_Mode.BackgroundColor=panelBg;

            % Direction
            lbl_C_Dir = uilabel(g_C_Mode, 'Text','Direction:', 'FontColor',labelCol, 'HorizontalAlignment','right', 'VerticalAlignment','center');
            lbl_C_Dir.Layout.Row=1; lbl_C_Dir.Layout.Column=1;

            app.SwitchCutDir = uiswitch(g_C_Mode, 'slider', ...
                'Items',{'Top (CW)', 'Bottom (CCW)'}, 'Value','Top (CW)', ...
                'ValueChangedFcn',@(~,~)app.onCutDirectionChanged());
            app.SwitchCutDir.Layout.Row=1; app.SwitchCutDir.Layout.Column=2;

            % Sync Start
            lbl_C_Sync = uilabel(g_C_Mode, 'Text','Start Pts:', 'FontColor',labelCol, 'HorizontalAlignment','right', 'VerticalAlignment','center');
            lbl_C_Sync.Layout.Row=2; lbl_C_Sync.Layout.Column=1;

            app.SwitchSyncStart = uiswitch(g_C_Mode, 'slider', ...
                'Items',{'Coupled', 'Independent'}, 'Value','Coupled', ...
                'ValueChangedFcn',@(src,~)app.onSyncToggleChanged(src));
            app.SwitchSyncStart.Layout.Row=2; app.SwitchSyncStart.Layout.Column=2;

            % Sync Entry
            lbl_C_ESync = uilabel(g_C_Mode, 'Text','Entry Pts:', 'FontColor',labelCol, 'HorizontalAlignment','right', 'VerticalAlignment','center');
            lbl_C_ESync.Layout.Row=3; lbl_C_ESync.Layout.Column=1;

            app.SwitchSyncEntry = uiswitch(g_C_Mode, 'slider', ...
                'Items',{'Coupled', 'Independent'}, 'Value','Coupled', ...
                'ValueChangedFcn',@(src,~)app.onSyncEntryToggleChanged(src));
            app.SwitchSyncEntry.Layout.Row=3; app.SwitchSyncEntry.Layout.Column=2;

            % 4. INTERACTION
            p_C_Inter = uipanel(app.CuttingLeftPanel, 'Title','Mouse Interaction', ...
                'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'BorderType','line');
            p_C_Inter.Layout.Row = 4;

            g_C_Inter = uigridlayout(p_C_Inter, [3 1]);
            g_C_Inter.RowHeight = {'fit','fit','fit'};
            g_C_Inter.Padding=[5 5 5 5]; g_C_Inter.BackgroundColor=panelBg;

            lbl_C_Inst = uilabel(g_C_Inter, 'Text','Click plot to set:', 'FontColor',labelCol);
            lbl_C_Inst.Layout.Row=1;

            % Row 1 Buttons
            g_C_IB1 = uigridlayout(g_C_Inter, [1 2]); g_C_IB1.Layout.Row=2;
            g_C_IB1.Padding=[0 0 0 0]; g_C_IB1.ColumnSpacing=5; g_C_IB1.BackgroundColor=panelBg;

            bCols = app.getInteractionColors();
            app.BtnPickStart = uibutton(g_C_IB1, 'state', 'Text','Start Pt', 'FontWeight','bold', ...
                'BackgroundColor',bCols.StartInactive, 'FontColor',bCols.TextInactive, 'ValueChangedFcn',@(src,evt)app.onInteractionStatsChanged(src));
            app.BtnPickStart.Layout.Column = 1;

            app.BtnPickEntry = uibutton(g_C_IB1, 'state', 'Text','Entry 1', 'FontWeight','bold', ...
                'BackgroundColor',bCols.EntryInactive, 'FontColor',bCols.TextInactive, 'ValueChangedFcn',@(src,evt)app.onInteractionStatsChanged(src));
            app.BtnPickEntry.Layout.Column = 2;

            % Row 2 Buttons
            g_C_IB2 = uigridlayout(g_C_Inter, [1 2]); g_C_IB2.Layout.Row=3;
            g_C_IB2.Padding=[0 0 0 0]; g_C_IB2.ColumnSpacing=5; g_C_IB2.BackgroundColor=panelBg;

            app.BtnPickEntry2 = uibutton(g_C_IB2, 'state', 'Text','Entry 2', 'FontWeight','bold', ...
                'BackgroundColor',bCols.Entry2Inactive, 'FontColor',bCols.TextInactive, 'ValueChangedFcn',@(src,evt)app.onInteractionStatsChanged(src));
            app.BtnPickEntry2.Layout.Column = 1;

            btn_C_Clear = uibutton(g_C_IB2, 'Text','Clear Pts', 'FontWeight','bold', 'BackgroundColor',t.accentBg, 'FontColor',t.editTxt, ...
                'ButtonPushedFcn',@(~,~)app.onClearEntries());
            btn_C_Clear.Layout.Column = 2;

            % 5. SPACER (Important for layout!)
            lbl_C_Spacer = uilabel(app.CuttingLeftPanel, 'Text', '');
            lbl_C_Spacer.Layout.Row = 5;

            % 7. CONTINUE
            app.BtnCuttingContinue = uibutton(app.CuttingLeftPanel, 'Text','Continue', 'FontWeight','bold', ...
                'BackgroundColor',[0.1 0.6 0.1], 'FontColor',[1 1 1], 'ButtonPushedFcn',@(~,~)app.onContinue());
            app.BtnCuttingContinue.Layout.Row = 7;

            % RIGHT PLOTS
            app.AxCutLeft = uiaxes(app.GLCutting); app.AxCutLeft.Layout.Row=1; app.AxCutLeft.Layout.Column=2;
            app.AxCutLeft.BackgroundColor = t.editBg; grid(app.AxCutLeft,'on'); title(app.AxCutLeft,'Left Profile Cut Path');

            app.AxCutRight = uiaxes(app.GLCutting); app.AxCutRight.Layout.Row=2; app.AxCutRight.Layout.Column=2;
            app.AxCutRight.BackgroundColor = t.editBg; grid(app.AxCutRight,'on'); title(app.AxCutRight,'Right Profile Cut Path');

            % ===========================================================
            % 6. SIMULATION TAB
            % ===========================================================
            app.TabSimulation = uitab(app.TabGroup, 'Title', 'Simulation');

            app.GLSimulation = uigridlayout(app.TabSimulation, [1 2]);
            app.GLSimulation.ColumnWidth   = {320, '1x'};
            app.GLSimulation.Padding       = [10 10 10 10];

            % --- Left Control Panel ---
            app.SimLeftPanel = uigridlayout(app.GLSimulation, [6 1]);
            app.SimLeftPanel.RowHeight = {'fit', 'fit', 'fit', 'fit', '1x', 'fit'};
            app.SimLeftPanel.Padding = [10 10 10 10];
            app.SimLeftPanel.BackgroundColor = sideBg;

            % 1. VIEW
            p_S_View = uipanel(app.SimLeftPanel, 'Title','View', ...
                'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'BorderType','line');
            p_S_View.Layout.Row = 1;

            g_S_View = uigridlayout(p_S_View, [1 2]);
            g_S_View.Padding=[5 5 5 5]; g_S_View.ColumnSpacing=5; g_S_View.BackgroundColor=panelBg;

            btn_S_VM = uibutton(g_S_View, 'Text','Machine View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetSimViewMachine());
            btn_S_VM.Layout.Column = 1;

            btn_S_VB = uibutton(g_S_View, 'Text','Billet View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetSimViewBillet());
            btn_S_VB.Layout.Column = 2;

            % 2. PLAYBACK
            p_S_Play = uipanel(app.SimLeftPanel, 'Title','Playback', ...
                'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'BorderType','line');
            p_S_Play.Layout.Row = 2;

            g_S_Play = uigridlayout(p_S_Play, [2 3]);
            g_S_Play.ColumnWidth={'1x','1x','1x'}; g_S_Play.RowHeight={'fit','fit'};
            g_S_Play.Padding=[5 5 5 5]; g_S_Play.ColumnSpacing=5; g_S_Play.BackgroundColor=panelBg;

            app.SimPlayBtn = uibutton(g_S_Play, 'Text','Play', 'FontWeight','bold', ...
                'BackgroundColor',t.accentBg, 'FontColor',t.editTxt, 'ButtonPushedFcn',@(~,~)app.onSimPlay());
            app.SimPlayBtn.Layout.Column = 1;

            btn_S_Pause = uibutton(g_S_Play, 'Text','Pause', 'FontWeight','bold', 'BackgroundColor',panelBg, 'FontColor',labelCol, ...
                'ButtonPushedFcn',@(~,~)app.onSimPause());
            btn_S_Pause.Layout.Column = 2;

            app.SimStopBtn = uibutton(g_S_Play, 'Text','Reset', 'FontWeight','bold', 'BackgroundColor',panelBg, 'FontColor',labelCol, ...
                'ButtonPushedFcn',@(~,~)app.onSimStop());
            app.SimStopBtn.Layout.Column = 3;

            app.SimSlider = uislider(g_S_Play, 'Limits',[1 100], 'Value',1, 'ValueChangedFcn',@(src,~)app.onSimSliderChanging(src));
            app.SimSlider.Layout.Row = 2; app.SimSlider.Layout.Column = [1 3];

            % 3. SETTINGS
            p_S_Set = uipanel(app.SimLeftPanel, 'Title','Settings', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            p_S_Set.Layout.Row = 3;

            g_S_Set = uigridlayout(p_S_Set, [1 2]);
            g_S_Set.ColumnWidth={'fit','1x'}; g_S_Set.Padding=[5 5 5 5]; g_S_Set.BackgroundColor=panelBg;

            lbl_S_Speed = uilabel(g_S_Set, 'Text','Speed (x):', 'FontColor',labelCol, 'HorizontalAlignment','right');
            lbl_S_Speed.Layout.Column = 1;

            app.SimSpeedSpinner = uispinner(g_S_Set, 'Limits',[0.1 10], 'Value',1.0, 'Step',0.1);
            app.SimSpeedSpinner.Layout.Column = 2;

            % 4. COORDINATES (Fixed Layout)
            p_S_Coord = uipanel(app.SimLeftPanel, 'Title','Live Coordinates', ...
                'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            p_S_Coord.Layout.Row = 4;

            % 5 Cols: [Label] [Value] [Spacer] [Label] [Value]
            g_S_Coord = uigridlayout(p_S_Coord, [3 5]);
            g_S_Coord.ColumnWidth={'fit', 65, 15, 'fit', 65};
            g_S_Coord.RowHeight={'fit','fit','fit'};
            g_S_Coord.Padding=[5 5 5 5]; g_S_Coord.BackgroundColor=panelBg;

            % Headers
            lbl_S_HL = uilabel(g_S_Coord, 'Text','Left Tower', 'FontWeight','bold', 'FontColor',labelCol, 'HorizontalAlignment','center');
            lbl_S_HL.Layout.Column=[1 2];

            lbl_S_HR = uilabel(g_S_Coord, 'Text','Right Tower', 'FontWeight','bold', 'FontColor',labelCol, 'HorizontalAlignment','center');
            lbl_S_HR.Layout.Column=[4 5];

            % Left Data
            lbl_S_XL = uilabel(g_S_Coord, 'Text','X:', 'FontWeight','bold', 'FontColor',t.accentBg, 'HorizontalAlignment','right');
            lbl_S_XL.Layout.Row=2;
            app.LblReadoutX = uilabel(g_S_Coord, 'Text','0.00', 'FontName','Monospaced', 'FontColor',labelCol, 'HorizontalAlignment','left');
            app.LblReadoutX.Layout.Row=2; app.LblReadoutX.Layout.Column=2;

            lbl_S_YL = uilabel(g_S_Coord, 'Text','Y:', 'FontWeight','bold', 'FontColor',t.accentBg, 'HorizontalAlignment','right');
            lbl_S_YL.Layout.Row=3;
            app.LblReadoutY = uilabel(g_S_Coord, 'Text','0.00', 'FontName','Monospaced', 'FontColor',labelCol, 'HorizontalAlignment','left');
            app.LblReadoutY.Layout.Row=3; app.LblReadoutY.Layout.Column=2;

            % Right Data
            lbl_S_ZR = uilabel(g_S_Coord, 'Text','Z:', 'FontWeight','bold', 'FontColor',t.accentBg, 'HorizontalAlignment','right');
            lbl_S_ZR.Layout.Row=2; lbl_S_ZR.Layout.Column=4;
            app.LblReadoutZ = uilabel(g_S_Coord, 'Text','0.00', 'FontName','Monospaced', 'FontColor',labelCol, 'HorizontalAlignment','left');
            app.LblReadoutZ.Layout.Row=2; app.LblReadoutZ.Layout.Column=5;

            lbl_S_AR = uilabel(g_S_Coord, 'Text','A:', 'FontWeight','bold', 'FontColor',t.accentBg, 'HorizontalAlignment','right');
            lbl_S_AR.Layout.Row=3; lbl_S_AR.Layout.Column=4;
            app.LblReadoutA = uilabel(g_S_Coord, 'Text','0.00', 'FontName','Monospaced', 'FontColor',labelCol, 'HorizontalAlignment','left');
            app.LblReadoutA.Layout.Row=3; app.LblReadoutA.Layout.Column=5;

            % 5. SPACER
            lbl_S_Spacer = uilabel(app.SimLeftPanel, 'Text', '');
            lbl_S_Spacer.Layout.Row = 5;

            % 6. CONTINUE
            app.BtnSimContinue = uibutton(app.SimLeftPanel, 'Text','Generate G-Code', 'FontWeight','bold', ...
                'BackgroundColor',[0.15 0.45 0.8], 'FontColor',[1 1 1], 'ButtonPushedFcn',@(~,~)app.onGenerateGCode());
            app.BtnSimContinue.Layout.Row = 6;

            % RIGHT COLUMN
            app.AxSim = uiaxes(app.GLSimulation);
            app.AxSim.Layout.Column = 2;
            app.AxSim.BackgroundColor = [0.05 0.05 0.05];
            xlabel(app.AxSim,'X'); ylabel(app.AxSim,'Y'); zlabel(app.AxSim,'Z');
            grid(app.AxSim,'on'); view(app.AxSim, 3); axis(app.AxSim, 'equal');

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
        % function onTabChanged(app, ~, evt)
        %     % Enable custom mouse rotation only on the Model tab.
        %     % When on other tabs (e.g. Profiles), disable the UIFigure
        %     % mouse callbacks so built-in uiaxes interactions work.
        %
        %     newTab = evt.NewValue;
        %
        %     if newTab == app.TabModel
        %         % Model tab active: enable our custom mouse handlers
        %         app.UIFigure.WindowButtonDownFcn   = @(src,ev)app.onMouseDown(src,ev);
        %         app.UIFigure.WindowButtonMotionFcn = @(src,ev)app.onMouseMove(src,ev);
        %         app.UIFigure.WindowButtonUpFcn     = @(src,ev)app.onMouseUp(src,ev);
        %     else
        %         % Any other tab: disable our handlers so the axes
        %         % use MATLAB's built-in interactions.
        %         app.UIFigure.WindowButtonDownFcn   = [];
        %         app.UIFigure.WindowButtonMotionFcn = [];
        %         app.UIFigure.WindowButtonUpFcn     = [];
        %     end
        % end

        function onTabChanged(app, ~, evt)
            % Standard tab house-keeping
            if evt.NewValue == app.TabBillet
                app.syncBilletUI();
                app.refreshBilletPlots();
            elseif evt.NewValue == app.TabMachine
                app.onResetMachineBilletPosition();
            elseif evt.NewValue == app.TabCutting
                % NEW: Auto-Execute Start/Entry Logic
                app.onAutoStart();
                app.onAutoEntry();

                app.updateCuttingPlots();
                app.onResetCuttingViewBillet();
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
                app.TabGroup.SelectedTab = app.TabSimulation;
                app.applyTheme();
                app.generateSimulationData();

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

                    plot3(ax, ones(size(tL.y))*(-offX), tL.y, tL.z, 'Color', t.planeRed, 'LineWidth', 1.2);
                    plot3(ax, ones(size(tR.y))*(mX-offX), tR.y, tR.z, 'Color', t.planeGreen, 'LineWidth', 1.2);

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
                            '.', 'Color', dotCMap(k,:), 'MarkerSize', 16);
                        plot3(ax, xR_world, ySyncR(currIdx) + totalShift(2), zSyncR(currIdx) + totalShift(3), ...
                            '.', 'Color', dotCMap(k,:), 'MarkerSize', 16);
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
            % Fixes: View Persistence now works for ALL interactions (Toggles, Auto, etc).

            if isempty(app.AxCutLeft) || isempty(app.AxCutRight), return; end

            t = app.getTheme();

            % --- 1. View Persistence (FIXED) ---
            % We no longer care which button is pressed.
            % If the axes limits are not the default [0 1], we assume the view is valid and keep it.
            curXL = xlim(app.AxCutLeft);
            isInitialized = ~isequal(curXL, [0 1]);

            limsL = []; limsR = [];
            if isInitialized
                limsL = [xlim(app.AxCutLeft); ylim(app.AxCutLeft)];
                limsR = [xlim(app.AxCutRight); ylim(app.AxCutRight)];
            end

            % Clear
            cla(app.AxCutLeft); cla(app.AxCutRight);
            hold(app.AxCutLeft,'on'); hold(app.AxCutRight,'on');

            % --- 2. Setup ---
            offsetY = app.BilletShift(2) + app.MachineBilletPos(2);
            offsetZ = app.BilletShift(3) + app.MachineBilletPos(3);
            isCCW   = strcmp(app.SwitchCutDir.Value, 'Bottom (CCW)');

            % --- 3. Backgrounds ---
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

            % --- 4. Process Data ---
            [yL, zL, hGhostL] = app.preparePlotData(app.AxCutLeft, app.LeftProfilePoints, offsetY, offsetZ, app.SelectedStartIdxL, isCCW, t, app.KerfEnabled, app.KerfValue);
            [yR, zR, hGhostR] = app.preparePlotData(app.AxCutRight, app.RightProfilePoints, offsetY, offsetZ, app.SelectedStartIdxR, isCCW, t, app.KerfEnabled, app.KerfValue);

            % --- 5. Draw Profiles ---

            function hD = drawDummyLegendMarker(ax, style, color, mFace, lWidth)
                if nargin < 5, lWidth = 1.0; end
                hD = plot(ax, NaN, NaN, style, 'Color', color, 'MarkerFaceColor', mFace, 'LineWidth', lWidth);
            end

            hRapidL=gobjects(0); hLeadL=gobjects(0); hStartL=gobjects(0); hPathDummyL=gobjects(0); hEntryDotL=gobjects(0);

            if ~isempty(yL)
                % Profile
                c=(1:numel(yL))';
                patch(app.AxCutLeft, 'XData',[yL;NaN], 'YData',[zL;NaN], 'CData',[c;NaN], 'FaceColor','none', 'EdgeColor','interp', 'LineWidth',1.0, 'HitTest','off');
                hPathDummyL = drawDummyLegendMarker(app.AxCutLeft, '-', [0 0.5 1], 'none', 1.0);

                % Travel Paths
                [hRapidL, hLeadL, hEntryDotL] = app.drawTravelPath(app.AxCutLeft, [yL(1), zL(1)], app.EntryPointL, app.EntryPoint2L);

                % Start Marker
                app.drawRotatedMarker(app.AxCutLeft, [yL(1), zL(1)], [yL(2), zL(2)], 'start');

                % Legend Dummy
                hStartL = drawDummyLegendMarker(app.AxCutLeft, '^', [0 1 0], 'none');
            end

            hRapidR=gobjects(0); hLeadR=gobjects(0); hStartR=gobjects(0); hPathDummyR=gobjects(0); hEntryDotR=gobjects(0);
            if ~isempty(yR)
                c=(1:numel(yR))';
                patch(app.AxCutRight, 'XData',[yR;NaN], 'YData',[zR;NaN], 'CData',[c;NaN], 'FaceColor','none', 'EdgeColor','interp', 'LineWidth',1.0, 'HitTest','off');
                hPathDummyR = drawDummyLegendMarker(app.AxCutRight, '-', [0 0.5 1], 'none', 1.0);

                [hRapidR, hLeadR, hEntryDotR] = app.drawTravelPath(app.AxCutRight, [yR(1), zR(1)], app.EntryPointR, app.EntryPoint2R);

                app.drawRotatedMarker(app.AxCutRight, [yR(1), zR(1)], [yR(2), zR(2)], 'start');

                hStartR = drawDummyLegendMarker(app.AxCutRight, '^', [0 1 0], 'none');
            end

            % --- 6. Legends ---
            labels = {'Start Point', 'Cut Path', 'Rapid Links (Yellow)', 'Leads (Orange)', 'Entry Point', 'Machine Limits', 'Raw Profile'};

            if ~isgraphics(hEntryDotL), hEntryDotL = drawDummyLegendMarker(app.AxCutLeft, '.', [1 0.5 0], [1 0.5 0], 1.0); end
            if ~isgraphics(hEntryDotR), hEntryDotR = drawDummyLegendMarker(app.AxCutRight, '.', [1 0.5 0], [1 0.5 0], 1.0); end

            handlesL = [hStartL, hPathDummyL, hRapidL, hLeadL, hEntryDotL, hMachL, hGhostL];
            if any(isgraphics(handlesL))
                lgd = legend(app.AxCutLeft, handlesL(isgraphics(handlesL)), labels(isgraphics(handlesL)), 'Location','northeast');
                lgd.Box='off'; lgd.TextColor=t.labelCol;
            end

            handlesR = [hStartR, hPathDummyR, hRapidR, hLeadR, hEntryDotR, hMachR, hGhostR];
            if any(isgraphics(handlesR))
                lgd = legend(app.AxCutRight, handlesR(isgraphics(handlesR)), labels(isgraphics(handlesR)), 'Location','northeast');
                lgd.Box='off'; lgd.TextColor=t.labelCol;
            end

            % --- 7. Restore View ---
            title(app.AxCutLeft,'Left Tower'); title(app.AxCutRight,'Right Tower');
            colormap(app.AxCutLeft,'turbo'); colormap(app.AxCutRight,'turbo');

            if isInitialized
                % RESTORE PREVIOUS VIEW
                xlim(app.AxCutLeft, limsL(1,:)); ylim(app.AxCutLeft, limsL(2,:));
                xlim(app.AxCutRight, limsR(1,:)); ylim(app.AxCutRight, limsR(2,:));
                daspect(app.AxCutLeft,[1 1 1]); daspect(app.AxCutRight,[1 1 1]);
            else
                % FIRST RUN (Auto Fit)
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

        function onGenerateGCode(app)
            uialert(app.UIFigure, 'G-Code Generation not yet implemented.', 'Info');
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
            % Calculates "Neutral Angle" lead-in points for Left and Right profiles.
            % Logic: Bisects the angle at the start point and projects outwards.
            % Constraint: Must be at least 10mm in front of Billet Min-Y.

            % --- Nested Helper: The Math ---
            function ptEntry = calcNeutralEntry(pts, startIdx, billetMinY, doKerf, kVal)
                ptEntry = [];
                if isempty(pts), return; end

                % 1. Get Geometry [y z]
                y = pts(:,1); z = pts(:,2);
                if doKerf, [y, z] = HotWireSTEPApp_v6_helpers.offsetProfileLoop(y, z, kVal); end

                N = numel(y);
                if startIdx > N, startIdx = 1; end

                % 2. Identify Points (Prev, Start, Next)
                idxS = startIdx;
                idxN = mod(startIdx, N) + 1;
                idxP = mod(startIdx - 2, N) + 1;

                P = [y(idxP), z(idxP)];
                S = [y(idxS), z(idxS)];
                N_pt = [y(idxN), z(idxN)];

                % 3. Calculate Vectors (Outward from S)
                vSP = P - S; vSP = vSP / (norm(vSP)+eps);
                vSN = N_pt - S; vSN = vSN / (norm(vSN)+eps);

                % 4. Calculate Bisector (Pointing Outwards)
                % Vector pointing 'in' to corner is (vSP + vSN). Negate for 'out'.
                vBisect = -(vSP + vSN);
                if norm(vBisect) < 1e-6, vBisect = [-1, 0]; end % Fallback Left
                vBisect = vBisect / norm(vBisect);

                % 5. Project Entry Point
                limitY = billetMinY - 10; % 10mm clearance line

                % Default projection: 20mm out
                defaultDist = 20;
                candidate = S + vBisect * defaultDist;

                % 6. Apply Y-Constraint (Must be <= limitY)
                if candidate(1) > limitY
                    % We need S + v*d = limitY  =>  d = (limitY - Sy) / vy
                    if abs(vBisect(1)) > 1e-3
                        d = (limitY - S(1)) / vBisect(1);
                        if d < 0, d = 20; end
                        candidate = S + vBisect * d;
                    else
                        candidate(1) = limitY; % Pure vertical clamp
                    end
                end
                ptEntry = candidate;
            end
            % ---------------------

            % 1. Setup Context
            doKerf = app.KerfEnabled && app.KerfValue > 0;
            bMinY  = app.MachineBilletPos(2);
            offsetY = app.BilletShift(2) + app.MachineBilletPos(2);
            offsetZ = app.BilletShift(3) + app.MachineBilletPos(3);

            % 2. Calculate LEFT
            if ~isempty(app.LeftProfilePoints)
                % Extract [y z] directly in Machine Coords
                ptsL = [app.LeftProfilePoints(:,2) + offsetY, app.LeftProfilePoints(:,3) + offsetZ];
                app.EntryPointL = calcNeutralEntry(ptsL, app.SelectedStartIdxL, bMinY, doKerf, app.KerfValue);
            end

            % 3. Calculate RIGHT (Coupled or Independent)
            isEntryCoupled = strcmp(app.SwitchSyncEntry.Value, 'Coupled');

            if isEntryCoupled
                % COUPLED: Just copy Left to Right
                app.EntryPointR = app.EntryPointL;
            else
                % INDEPENDENT: Calculate based on Right Profile geometry
                if ~isempty(app.RightProfilePoints)
                    ptsR = [app.RightProfilePoints(:,2) + offsetY, app.RightProfilePoints(:,3) + offsetZ];
                    app.EntryPointR = calcNeutralEntry(ptsR, app.SelectedStartIdxR, bMinY, doKerf, app.KerfValue);
                end
            end

            % 4. Refresh
            app.updateCuttingPlots();
        end

        function [hRapid, hLead, hDot] = drawTravelPath(app, ax, startPt, entry1, entry2)
            % Draws Travel Path with specific sequence:
            % 1. Machine Zero
            % 2. Billet Front Face (Mid-Height)
            % 3. Retract 10mm (Safety)
            % 4. Entry 1
            % 5. Entry 2
            % 6. Start Point
            %
            % Coloring:
            % - Yellow (Rapid): Everything up to the last Entry Point.
            % - Orange (Feed): Only the final segment (Last Entry -> Start).

            hRapid = gobjects(0); hLead = gobjects(0); hDot = gobjects(0);
            if isempty(startPt), return; end

            % --- Define Key Points ---
            pZero = [0, 0];

            % Front Face @ Mid Height
            bFrontY = app.MachineBilletPos(2);
            bMidZ   = app.MachineBilletPos(3) + app.BilletSize(3)/2;
            pFront  = [bFrontY, bMidZ];

            % Retract 10mm (-Y)
            pRetract = [bFrontY - 10, bMidZ];

            % --- Build Path Sequence ---
            % Base Rapid sequence
            pts = [pZero; pFront; pRetract];

            % Append Entries
            if ~isempty(entry1), pts = [pts; entry1]; end
            if ~isempty(entry2), pts = [pts; entry2]; end

            % --- Split Rapid vs Feed ---
            % Feed is ONLY the segment from the very last point in 'pts' to 'startPt'
            % Rapid is everything in 'pts'

            % 1. Plot Rapid Chain (Yellow)
            % This connects Zero->Front->Retract->Entry1->Entry2
            if size(pts, 1) > 1
                hRapid = plot(ax, pts(:,1), pts(:,2), '-', 'Color', [0.9 0.8 0], 'LineWidth', 1.0, 'HitTest','off');
            end

            % 2. Plot Feed Segment (Orange)
            % Connects Last Point of Rapid Chain -> Start Point
            lastRapidPt = pts(end, :);
            hLead = plot(ax, [lastRapidPt(1), startPt(1)], [lastRapidPt(2), startPt(2)], '-', 'Color', [1 0.5 0], 'LineWidth', 1.0, 'HitTest','off');

            % 3. Plot Dots for Entry Points
            dotPts = [];
            if ~isempty(entry1), dotPts = [dotPts; entry1]; end
            if ~isempty(entry2), dotPts = [dotPts; entry2]; end

            if ~isempty(dotPts)
                hDot = plot(ax, dotPts(:,1), dotPts(:,2), '.', 'MarkerSize', 12, 'Color', [1 0.5 0], 'HitTest','off');
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
            % Compiles the full toolpath (Rapid + Feed) for simulation

            t = app.getTheme();
            offsetY = app.BilletShift(2) + app.MachineBilletPos(2);
            offsetZ = app.BilletShift(3) + app.MachineBilletPos(3);
            isCCW   = strcmp(app.SwitchCutDir.Value, 'Bottom (CCW)');

            % 1. Process Profiles
            [yL, zL] = app.preparePlotData([], app.LeftProfilePoints, offsetY, offsetZ, app.SelectedStartIdxL, isCCW, t, app.KerfEnabled, app.KerfValue);
            [yR, zR] = app.preparePlotData([], app.RightProfilePoints, offsetY, offsetZ, app.SelectedStartIdxR, isCCW, t, app.KerfEnabled, app.KerfValue);

            % 2. Sync Profile Counts
            [yL, zL, yR, zR] = HotWireSTEPApp_v6_helpers.syncPointCounts(yL, zL, yR, zR);

            % 3. Build Approach Sequences
            function pts = buildPathSeq(startPt, entry1, entry2)
                pZero = [0, 0];
                pFront = [app.MachineBilletPos(2), app.MachineBilletPos(3) + app.BilletSize(3)/2];
                pRetract = [pFront(1)-10, pFront(2)];
                pts = [pZero; pFront; pRetract];
                if ~isempty(entry1), pts = [pts; entry1]; end
                if ~isempty(entry2), pts = [pts; entry2]; end
                pts = [pts; startPt];
            end

            rapidL = buildPathSeq([yL(1), zL(1)], app.EntryPointL, app.EntryPoint2L);
            rapidR = buildPathSeq([yR(1), zR(1)], app.EntryPointR, app.EntryPoint2R);

            % 4. Interpolate Rapids
            function [upY, upZ] = interpolatePath(pts, numSteps)
                if size(pts,1) < 2, upY=pts(:,1); upZ=pts(:,2); return; end
                d = [0; cumsum(sqrt(sum(diff(pts,1,1).^2, 2)))];
                if d(end) == 0, upY=pts(:,1); upZ=pts(:,2); return; end
                query = linspace(0, d(end), numSteps)';
                upY = interp1(d, pts(:,1), query);
                upZ = interp1(d, pts(:,2), query);
            end

            rapidSteps = 100;
            [rLy, rLz] = interpolatePath(rapidL, rapidSteps);
            [rRy, rRz] = interpolatePath(rapidR, rapidSteps);

            % 5. Combine & Store (SimPathL/R)
            % FIX: Add BilletShift(1) to X position calculation for model-relative path
            xL_val = app.MachineBilletPos(1) + app.NumLeftOffset.Value + app.BilletShift(1);
            xR_val = app.MachineBilletPos(1) + app.NumRightOffset.Value + app.BilletShift(1);

            fullY_L = [rLy; yL]; fullZ_L = [rLz; zL];
            fullY_R = [rRy; yR]; fullZ_R = [rRz; zR];

            app.SimPathL = [repmat(xL_val, numel(fullY_L), 1), fullY_L, fullZ_L];
            app.SimPathR = [repmat(xR_val, numel(fullY_R), 1), fullY_R, fullZ_R];

            % 6. Calculate Projected Tower Paths
            V = app.SimPathR - app.SimPathL;

            % Left Tower (X=0)
            tL = -app.SimPathL(:,1) ./ V(:,1);
            app.SimTowerPathL = app.SimPathL + tL .* V;

            % Right Tower (X=MachineSpan)
            mSpan = app.MachineSpanX;
            tR = (mSpan - app.SimPathL(:,1)) ./ V(:,1);
            app.SimTowerPathR = app.SimPathL + tR .* V;

            % 7. Init Controls
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
            bs = app.MachineBedSize; bp = app.MachineBedPos;

            % 1. STATIC GEOMETRY
            [xb, yb, zb] = app.makeBoxVertices(0, bp(2), -bs(3), bs(1), bs(2), bs(3));
            patch(ax, 'Vertices',[xb, yb, zb], 'Faces', app.boxFaces, ...
                'FaceColor',[0.4 0.4 0.4], 'FaceAlpha', 0.5, 'EdgeColor',[0.2 0.2 0.2]);

            [xl, yl, zl] = app.makeBoxVertices(-offX, 0, 0, mSpan, mLimY, mLimZ);
            patch(ax, 'Vertices',[xl, yl, zl], 'Faces', app.boxFaces, ...
                'FaceColor','none', 'EdgeColor', t.labelCol, 'LineStyle',':', 'EdgeAlpha',0.3);

            % Towers & Labels
            patch(ax, 'XData',ones(4,1)*(-offX), 'YData',[0;mLimY;mLimY;0], 'ZData',[0;0;mLimZ;mLimZ], ...
                'FaceColor', t.planeRed, 'FaceAlpha', 0.15, 'EdgeColor', t.planeRed);
            patch(ax, 'XData',ones(4,1)*(mSpan-offX), 'YData',[0;mLimY;mLimY;0], 'ZData',[0;0;mLimZ;mLimZ], ...
                'FaceColor', t.planeGreen, 'FaceAlpha', 0.15, 'EdgeColor', t.planeGreen);

            text(ax, -offX, mLimY*0.98, mLimZ*0.92, {' LEFT',' TOWER'}, ...
                'Color', t.planeRedTxt, 'FontWeight','bold', 'FontSize', 9);
            text(ax, mSpan-offX, mLimY*0.02, mLimZ*0.92, {'RIGHT','TOWER '}, ...
                'Color', t.planeGreenTxt, 'FontWeight','bold', 'HorizontalAlignment','right', 'FontSize', 9);

            % 2. BILLET & GHOSTS (FIXED POSITIONING)
            % Base position relative to Machine Zero: bp
            % Applied user shift: app.BilletShift
            % Final Machine Coords: bp + BilletShift
            % Plot Coords: (Machine Coords) - [offX, 0, 0]

            finalBilletPos = bp + app.BilletShift;
            bPlotPos = finalBilletPos - [offX, 0, 0];

            [xm, ym, zm] = app.makeBoxVertices(bPlotPos(1), bPlotPos(2), bPlotPos(3), app.BilletSize(1), app.BilletSize(2), app.BilletSize(3));
            patch(ax, 'Vertices',[xm, ym, zm], 'Faces', app.boxFaces, ...
                'FaceColor', [0.3 0.5 0.8], 'FaceAlpha', 0.2, 'EdgeColor', t.labelCol, 'LineStyle','--', 'LineWidth', 1.0);

            % Ghost Profiles
            offsetY = finalBilletPos(2);
            offsetZ = finalBilletPos(3);
            % X-Shift for ghosts (Machine X -> Plot X)
            shiftX = app.BilletShift(1) - offX;

            if ~isempty(app.LeftProfilePoints)
                xPL = (app.MachineBilletPos(1) + app.NumLeftOffset.Value) + shiftX;
                plot3(ax, xPL*ones(size(app.LeftProfilePoints,1),1), app.LeftProfilePoints(:,2)+offsetY, app.LeftProfilePoints(:,3)+offsetZ, ...
                    '-', 'Color', t.rawMeshCol, 'LineWidth', 1.0);
            end
            if ~isempty(app.RightProfilePoints)
                xPR = (app.MachineBilletPos(1) + app.NumRightOffset.Value) + shiftX;
                plot3(ax, xPR*ones(size(app.RightProfilePoints,1),1), app.RightProfilePoints(:,2)+offsetY, app.RightProfilePoints(:,3)+offsetZ, ...
                    '-', 'Color', t.rawMeshCol, 'LineWidth', 1.0);
            end

            % 3. DYNAMIC ELEMENTS
            if ~isempty(app.SimPathL)
                % Model Trails
                plot3(ax, NaN, NaN, NaN, '-', 'Color', t.planeRed,   'LineWidth', 1.5, 'Tag', 'SimTrailL');
                plot3(ax, NaN, NaN, NaN, '-', 'Color', t.planeGreen, 'LineWidth', 1.5, 'Tag', 'SimTrailR');
                % Tower Trails
                plot3(ax, NaN, NaN, NaN, '-', 'Color', [0.8 0 0],   'LineWidth', 1.0, 'Tag', 'SimTowerL');
                plot3(ax, NaN, NaN, NaN, '-', 'Color', [0 0.8 0],   'LineWidth', 1.0, 'Tag', 'SimTowerR');
                % Wire
                plot3(ax, NaN, NaN, NaN, 'Color', t.wireKerf, 'LineWidth', 1.0, 'Tag', 'SimWire');
                % Dots
                plot3(ax, NaN, NaN, NaN, 'o', 'MarkerSize', 6, 'MarkerFaceColor', t.planeRed,   'MarkerEdgeColor', 'none', 'Tag', 'SimDotL');
                plot3(ax, NaN, NaN, NaN, 'o', 'MarkerSize', 6, 'MarkerFaceColor', t.planeGreen, 'MarkerEdgeColor', 'none', 'Tag', 'SimDotR');

                app.onSimSliderChanging(app.SimSlider);
            end

            app.onResetSimViewMachine();
            ax.BackgroundColor = [0.05 0.05 0.05];
            set(ax, 'XColor', [0.6 0.6 0.6], 'YColor', [0.6 0.6 0.6], 'ZColor', [0.6 0.6 0.6]);
        end

        function onSimSliderChanging(app, src)
            idx = round(src.Value);
            if isempty(app.SimPathL), return; end
            idx = min(idx, size(app.SimPathL, 1));

            offX = app.MachineBedPos(1);

            % 1. Update Wire Ends
            pTL = app.SimTowerPathL(idx, :) - [offX, 0, 0];
            pTR = app.SimTowerPathR(idx, :) - [offX, 0, 0];

            hWire = findobj(app.AxSim, 'Tag', 'SimWire');
            if ~isempty(hWire)
                hWire.XData = [pTL(1), pTR(1)]; hWire.YData = [pTL(2), pTR(2)]; hWire.ZData = [pTL(3), pTR(3)];
            end

            % 2. Update Dots
            hDotL = findobj(app.AxSim, 'Tag', 'SimDotL');
            if ~isempty(hDotL), hDotL.XData=pTL(1); hDotL.YData=pTL(2); hDotL.ZData=pTL(3); end
            hDotR = findobj(app.AxSim, 'Tag', 'SimDotR');
            if ~isempty(hDotR), hDotR.XData=pTR(1); hDotR.YData=pTR(2); hDotR.ZData=pTR(3); end

            % 3. Update Tower Trails
            hTowerL = findobj(app.AxSim, 'Tag', 'SimTowerL');
            if ~isempty(hTowerL)
                histL = app.SimTowerPathL(1:idx, :) - [offX, 0, 0];
                hTowerL.XData = histL(:,1); hTowerL.YData = histL(:,2); hTowerL.ZData = histL(:,3);
            end
            hTowerR = findobj(app.AxSim, 'Tag', 'SimTowerR');
            if ~isempty(hTowerR)
                histR = app.SimTowerPathR(1:idx, :) - [offX, 0, 0];
                hTowerR.XData = histR(:,1); hTowerR.YData = histR(:,2); hTowerR.ZData = histR(:,3);
            end

            % 4. Update Model Trails (Fixed Artifacts)
            % Using plot3 (Solid Line), so we just pass valid X/Y/Z data
            hTrailL = findobj(app.AxSim, 'Tag', 'SimTrailL');
            if ~isempty(hTrailL)
                dat = app.SimPathL(1:idx, :) - [offX, 0, 0];
                hTrailL.XData = dat(:,1); hTrailL.YData = dat(:,2); hTrailL.ZData = dat(:,3);
            end
            hTrailR = findobj(app.AxSim, 'Tag', 'SimTrailR');
            if ~isempty(hTrailR)
                dat = app.SimPathR(1:idx, :) - [offX, 0, 0];
                hTrailR.XData = dat(:,1); hTrailR.YData = dat(:,2); hTrailR.ZData = dat(:,3);
            end

            % 5. Readouts (Live Machine Coords)
            % Note: Use pTL/pTR but add offX back to get Machine Absolute
            if ~isempty(app.LblReadoutX), app.LblReadoutX.Text = sprintf('%.2f', pTL(2)); end
            if ~isempty(app.LblReadoutY), app.LblReadoutY.Text = sprintf('%.2f', pTL(3)); end
            if ~isempty(app.LblReadoutZ), app.LblReadoutZ.Text = sprintf('%.2f', pTR(2)); end
            if ~isempty(app.LblReadoutA), app.LblReadoutA.Text = sprintf('%.2f', pTR(3)); end

            drawnow limitrate;
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
            % Centers view on the Billet (Machine Coords)
            % Billet Position 'bp' is relative to Machine Zero.
            % Plot X-Zero is Bed Left Edge (Machine Zero is at -offX).

            offX = app.MachineBedPos(1);
            bp   = app.MachineBilletPos; % [X Y Z] absolute
            bs   = app.BilletSize;

            % Billet Bounds in Plot Coords
            bMin = [bp(1)-offX, bp(2), bp(3)];
            bMax = bMin + bs;

            buffer = 50;
            xlim(ax, [bMin(1)-buffer, bMax(1)+buffer]);
            ylim(ax, [bMin(2)-buffer, bMax(2)+buffer]);
            zlim(ax, [bMin(3)-buffer, bMax(3)+buffer]);

            view(ax, 3); axis(ax, 'equal');
        end

        % ===========================================================
        % SIMULATION PLAYBACK
        % ===========================================================
        function onSimPlay(app)
            % Start/Resume Timer
            if isempty(app.SimPathL), return; end

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

        function onSimPause(app)
            if ~isempty(app.SimTimer) && isvalid(app.SimTimer)
                stop(app.SimTimer);
                app.SimPlayBtn.Enable = 'on';
            end
        end

        function onSimStop(app)
            app.onSimPause();
            app.SimSlider.Value = 1;
            app.onSimSliderChanging(app.SimSlider); % Reset Visuals
        end

        function onSimTimerTick(app)
            % Advance Slider
            current = app.SimSlider.Value;
            limit   = app.SimSlider.Limits(2);

            % Speed Multiplier
            step = 1 + round(app.SimSpeedSpinner.Value * 5);

            nextVal = current + step;

            if nextVal >= limit
                nextVal = limit;
                app.onSimPause(); % Stop at end
            end

            app.SimSlider.Value = nextVal;
            app.onSimSliderChanging(app.SimSlider);
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
            sidebars = {app.GLLeft, app.profilesLeft, app.BilletLeftPanel, app.MachineLeftPanel, app.CuttingLeftPanel};

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
