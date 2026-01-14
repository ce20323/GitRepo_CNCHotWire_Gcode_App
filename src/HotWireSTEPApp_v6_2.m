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
        DefaultKerf (1,1) double = 0.5;   % [mm]
        MinKerf     (1,1) double = 0.0;   % [mm]
        MaxKerf     (1,1) double = 5.0;   % [mm]

        % -------- View / plane padding factors --------
        AutoFitPaddingFactor (1,1) double = 0.35;  % model view padding
        PlanePaddingFactor   (1,1) double = 0.20;  % plane extents padding

        % --- Billet UI Increments ---
        BilletSizeStep  = 1.0;  % mm
        BilletShiftStep = 0.5;  % mm

        % Machine Configuration Constants/State
        MachineSpan      = [1100, 550, 400] % Tower movement range [X, Y, Z]
        MachineBedSize   = [1000, 500, 20]  % Physical dimensions [L, W, H]
        MachineBedPos    = [50, 50, -20]      % Bed origin relative to machine 0,0,0

        % (Future)
        % MachineSpanX (1,1) double = 2000;  % mm, for example
        % MachineSpanY (1,1) double = 1000;
        % MachineSpanZ (1,1) double = 600;
        % etc...
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
            app.UIFigure = uifigure( ...
                'Name','Hot Wire STEP App v6.2', ...
                'Color',[0.1 0.1 0.1]);
            app.UIFigure.WindowState = 'maximized';

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
            profilesLeft = uigridlayout(app.GLProfiles,[6 1]);
            profilesLeft.Layout.Column   = 1;
            profilesLeft.RowHeight       = {'fit','fit','fit','fit','1x','fit'};  % row 5 = spacer, row 6 = button
            profilesLeft.Padding         = [10 10 10 10];
            profilesLeft.BackgroundColor = [0.16 0.16 0.16];


            % --- Profile Sampling Panel (tolerance) ---
            tolPanel = uipanel(profilesLeft, ...
                'Title','Profile Sampling', ...
                'BackgroundColor',[0.12 0.12 0.12], ...
                'ForegroundColor',[0.9 0.9 0.9], ...
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
                'FontColor',[0.9 0.9 0.9]);
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
                'FontColor',[0.9 0.9 0.9], ...
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
                'BackgroundColor',[0.12 0.12 0.12], ...
                'ForegroundColor',[0.9 0.9 0.9], ...
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
                'FontColor',[0.9 0.9 0.9]);
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
            app.BilletLeftPanel.BackgroundColor = [0.16 0.16 0.16];

            % --- [Auto-fit Billet] button (row 1)
            app.BtnAutoFitBillet = uibutton(app.BilletLeftPanel, ...
                'Text','Auto-fit Billet', ...
                'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~)app.onAutoFitBillet());
            app.BtnAutoFitBillet.Layout.Row = 1;

            % --- Billet size controls block (row 2) ---
            billetSizePanel = uipanel(app.BilletLeftPanel);
            billetSizePanel.Title = 'Billet Size Controls';
            billetSizePanel.BackgroundColor = [0.12 0.12 0.12];
            billetSizePanel.ForegroundColor = [0.9 0.9 0.9];
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
            hS1 = uilabel(sizeGrid, 'Text','Axis', 'FontWeight','bold', 'FontSize',10, 'HorizontalAlignment','center', 'FontColor',[0.9 0.9 0.9]);
            hS1.Layout.Row = 1; hS1.Layout.Column = 1;

            hS2 = uilabel(sizeGrid, 'Text','Stock [mm]', 'FontWeight','bold', 'FontSize',10, 'HorizontalAlignment','center', 'FontColor',[0.9 0.9 0.9]);
            hS2.Layout.Row = 1; hS2.Layout.Column = [3 5];

            hS3 = uilabel(sizeGrid, 'Text','Model', 'FontWeight','bold', 'FontSize',10, 'HorizontalAlignment','center', 'FontColor',[0.9 0.9 0.9]);
            hS3.Layout.Row = 1; hS3.Layout.Column = 6;

            axisLabels = {'X','Y','Z'};
            app.BilletSizeEdits      = gobjects(1,3);
            app.BilletSizeMinusBtns  = gobjects(1,3);
            app.BilletSizePlusBtns   = gobjects(1,3);
            app.BilletModelDimLabels = gobjects(1,3);

            for i = 1:3
                r = i + 1;
                lblA = uilabel(sizeGrid, 'Text', axisLabels{i}, 'FontWeight','bold', 'HorizontalAlignment','center', 'FontColor',[0.9 0.9 0.9]);
                lblA.Layout.Row = r; lblA.Layout.Column = 1;

                lblSp = uilabel(sizeGrid, 'Text','', 'BackgroundColor', [0.12 0.12 0.12]);
                lblSp.Layout.Row = r; lblSp.Layout.Column = 2;

                app.BilletSizeMinusBtns(i) = uibutton(sizeGrid, 'Text','-', 'FontWeight','bold', 'ButtonPushedFcn', @(~,~)app.onBilletSizeStep(i,-1));
                app.BilletSizeMinusBtns(i).Layout.Row = r; app.BilletSizeMinusBtns(i).Layout.Column = 3;

                app.BilletSizeEdits(i) = uieditfield(sizeGrid,'numeric', 'HorizontalAlignment','center', 'ValueDisplayFormat','%.1f', ...
                    'BackgroundColor',[0.7 0.7 0.8], 'FontColor',[0 0 0], 'ValueChangedFcn', @(src,~)app.onBilletSizeEdited(i,src));
                app.BilletSizeEdits(i).Layout.Row = r; app.BilletSizeEdits(i).Layout.Column = 4;

                app.BilletSizePlusBtns(i) = uibutton(sizeGrid, 'Text','+', 'FontWeight','bold', 'ButtonPushedFcn', @(~,~)app.onBilletSizeStep(i,+1));
                app.BilletSizePlusBtns(i).Layout.Row = r; app.BilletSizePlusBtns(i).Layout.Column = 5;

                app.BilletModelDimLabels(i) = uilabel(sizeGrid, 'Text','(---)', 'HorizontalAlignment','center', ...
                    'BackgroundColor',[0.12 0.12 0.12], 'FontColor',[0.7 0.7 0.7]);
                app.BilletModelDimLabels(i).Layout.Row = r; app.BilletModelDimLabels(i).Layout.Column = 6;
            end

            % --- [Auto-position Model] & [Reset] ---
            app.BtnAutoPositionModel = uibutton(app.BilletLeftPanel, 'Text','Auto-position Model', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onAutoPositionModel());
            app.BtnAutoPositionModel.Layout.Row = 3;

            app.BtnResetPosition = uibutton(app.BilletLeftPanel, 'Text','Reset Position', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetPosition());
            app.BtnResetPosition.Layout.Row = 4;

            % --- Billet position controls block (row 5) ---
            posPanel = uipanel(app.BilletLeftPanel, 'Title','Billet Position Controls', 'BackgroundColor',[0.12 0.12 0.12], 'ForegroundColor',[0.9 0.9 0.9], 'FontWeight','bold');
            posPanel.Layout.Row = 5;

            posGrid = uigridlayout(posPanel, [4 6]);
            posGrid.ColumnWidth = {35, 65, 20, 65, 20, 65};
            posGrid.RowHeight = {'fit','fit','fit','fit'};
            posGrid.Padding = [4 4 4 4];
            posGrid.ColumnSpacing = 4;
            posGrid.RowSpacing = 4;

            hP1 = uilabel(posGrid, 'Text','Axis', 'FontWeight','bold', 'FontSize',10, 'HorizontalAlignment','center', 'FontColor',[0.9 0.9 0.9]);
            hP1.Layout.Row = 1; hP1.Layout.Column = 1;

            hP2 = uilabel(posGrid, 'Text','-ive Gap', 'FontWeight','bold', 'FontSize',10, 'HorizontalAlignment','center', 'FontColor',[0.9 0.9 0.9]);
            hP2.Layout.Row = 1; hP2.Layout.Column = 2;

            hP3 = uilabel(posGrid, 'Text','Shift [mm]', 'FontWeight','bold', 'FontSize',10, 'HorizontalAlignment','center', 'FontColor',[0.9 0.9 0.9]);
            hP3.Layout.Row = 1; hP3.Layout.Column = [3 5];

            hP4 = uilabel(posGrid, 'Text','+ive Gap', 'FontWeight','bold', 'FontSize',10, 'HorizontalAlignment','center', 'FontColor',[0.9 0.9 0.9]);
            hP4.Layout.Row = 1; hP4.Layout.Column = 6;

            app.BilletNegOffsetEdits    = gobjects(1,3);
            app.BilletCenterOffsetEdits = gobjects(1,3);
            app.BilletPosOffsetEdits    = gobjects(1,3);

            for k = 1:3
                rk = k + 1;
                lblB = uilabel(posGrid, 'Text', axisLabels{k}, 'FontWeight','bold', 'HorizontalAlignment','center', 'FontColor',[0.9 0.9 0.9]);
                lblB.Layout.Row = rk; lblB.Layout.Column = 1;

                app.BilletNegOffsetEdits(k) = uieditfield(posGrid,'numeric', 'HorizontalAlignment','center', 'ValueDisplayFormat','%.1f', ...
                    'BackgroundColor',[0.12 0.12 0.12], 'FontColor', [0.9 0.9 0.9], 'ValueChangedFcn', @(src,~)app.onBilletOffsetEdited(k,"neg",src));
                app.BilletNegOffsetEdits(k).Layout.Row = rk; app.BilletNegOffsetEdits(k).Layout.Column = 2;

                btnM2 = uibutton(posGrid, 'Text','-', 'FontWeight','bold', 'ButtonPushedFcn', @(~,~)app.onBilletShift(k,-0.5));
                btnM2.Layout.Row = rk; btnM2.Layout.Column = 3;

                app.BilletCenterOffsetEdits(k) = uieditfield(posGrid,'numeric', 'HorizontalAlignment','center', 'ValueDisplayFormat','%.1f', ...
                    'BackgroundColor',[0.7 0.7 0.8], 'FontColor',[0 0 0], 'ValueChangedFcn', @(src,~)app.onBilletOffsetEdited(k,"center",src));
                app.BilletCenterOffsetEdits(k).Layout.Row = rk; app.BilletCenterOffsetEdits(k).Layout.Column = 4;

                btnP2 = uibutton(posGrid, 'Text','+', 'FontWeight','bold', 'ButtonPushedFcn', @(~,~)app.onBilletShift(k,+0.5));
                btnP2.Layout.Row = rk; btnP2.Layout.Column = 5;

                app.BilletPosOffsetEdits(k) = uieditfield(posGrid,'numeric', 'HorizontalAlignment','center', 'ValueDisplayFormat','%.1f', ...
                    'BackgroundColor',[0.12 0.12 0.12], 'FontColor', [0.9 0.9 0.9], 'ValueChangedFcn', @(src,~)app.onBilletOffsetEdited(k,"pos",src));
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
            app.GLLeft.BackgroundColor = [0.16 0.16 0.16];


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
                'FontColor',[0.9 0.9 0.9]);
            app.FileLabel.Layout.Row = 3;

            % Spacer
            sp = uilabel(app.GLLeft,'Text',"");
            sp.Layout.Row = 4;

            % -------------------------------------------------------
            % STRAIGHT / TAPER SWITCH (just under file label)
            % -------------------------------------------------------
            cutPanel = uipanel(app.GLLeft, ...
                'BackgroundColor',[0.16 0.16 0.16], ...
                'BorderType','none');
            cutPanel.Layout.Row = 5;

            cutGrid = uigridlayout(cutPanel,[1 3]);
            cutGrid.ColumnWidth = {'1x','fit','1x'};
            cutGrid.Padding     = [10 0 10 0];

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
                'BackgroundColor',[0.12 0.12 0.12], ...
                'FontWeight','bold', ...
                'ForegroundColor',[0.9 0.9 0.9]);
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
                'BackgroundColor',[0.12 0.12 0.12],...
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

            % Add Machine Tab to group
            app.TabMachine = uitab(app.TabGroup, 'Title', 'Machine');

            app.GLMachine = uigridlayout(app.TabMachine, [1 2]);
            app.GLMachine.ColumnWidth = {320, '1x'};
            app.GLMachine.Padding = [10 10 10 10];

            % --- Left Control Column ---
            app.MachineLeftPanel = uigridlayout(app.GLMachine, [6 1]); % 6 Rows
            app.MachineLeftPanel.RowHeight = {'fit','fit','fit','fit','1x','fit'};
            app.MachineLeftPanel.Padding = [10 10 10 10];
            app.MachineLeftPanel.BackgroundColor = [0.16 0.16 0.16];

            % --- Placement Panel ---
            mPanel = uipanel(app.MachineLeftPanel);
            mPanel.Title = 'Billet Placement on Machine';
            mPanel.BackgroundColor = [0.12 0.12 0.12];
            mPanel.ForegroundColor = [0.9 0.9 0.9];
            mPanel.FontWeight = 'bold';
            mPanel.Layout.Row = 1;

            mOuter = uigridlayout(mPanel, [1 1]);
            mGrid = uigridlayout(mOuter, [4 2]);
            mGrid.ColumnWidth = {'1x', 110};
            mGrid.RowHeight = {'fit','fit','fit','fit'};
            mGrid.Padding = [10 5 10 5];

            % Headings
            hM1 = uilabel(mGrid, 'Text','Axis', 'FontWeight','bold', 'FontColor',[0.9 0.9 0.9]);
            hM1.Layout.Row=1; hM1.Layout.Column=1;
            hM2 = uilabel(mGrid, 'Text','Pos [mm]', 'FontWeight','bold', 'FontColor',[0.9 0.9 0.9]);
            hM2.Layout.Row=1; hM2.Layout.Column=2;

            mAxisLabels = {'X (Machine)','Y (Machine)','Z (Machine)'};
            app.MachinePosSpinners = gobjects(1,3);
            for i = 1:3
                ri = i + 1;
                lbl = uilabel(mGrid, 'Text', mAxisLabels{i}, 'FontColor',[0.9 0.9 0.9]);
                lbl.Layout.Row = ri; lbl.Layout.Column = 1;

                % Clean Spinner (No background fill)
                s = uispinner(mGrid);
                s.Limits = [-500, 2000];
                s.Value = app.MachineBilletPos(i);
                s.ValueDisplayFormat = '%.2f'; % 2 decimal places
                s.Step = 1.0;
                s.ValueChangedFcn = @(src,~)app.onMachinePosEdited(i,src);
                s.Layout.Row = ri; s.Layout.Column = 2;
                app.MachinePosSpinners(i) = s;
            end

            % --- Reset Billet Position Button ---
            app.BtnResetMachineBillet = uibutton(app.MachineLeftPanel, ...
                'Text','Reset Billet Position', ...
                'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~)app.onResetMachineBilletPosition());
            app.BtnResetMachineBillet.Layout.Row = 3; % Adjust row index as needed

            % --- Reset Machine Plot View Button ---
            app.BtnResetMachinePlot = uibutton(app.MachineLeftPanel, ...
                'Text','Reset Plot View', ...
                'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~)app.onResetMachinePlotView());
            app.BtnResetMachinePlot.Layout.Row = 4; % Adjust row index as needed

            % Row 6: Continue Button (Green)
            app.BtnMachineContinue = uibutton(app.MachineLeftPanel, ...
                'Text','Continue', ...
                'FontWeight','bold', ...
                'BackgroundColor',[0.1 0.6 0.1], 'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~)app.onContinue());
            app.BtnMachineContinue.Layout.Row = 6;

            % --- Machine Visualization Plot ---
            app.AxMachine = uiaxes(app.GLMachine);
            app.AxMachine.Layout.Column = 2;
            app.AxMachine.BackgroundColor = [0.05 0.05 0.05];
            xlabel(app.AxMachine, 'X'); ylabel(app.AxMachine, 'Y'); zlabel(app.AxMachine, 'Z');
            grid(app.AxMachine, 'on'); view(app.AxMachine, 3);
            hold(app.AxMachine, 'on');

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
            %  - 3D curves in the Model tab (ordered main loop)
            %  - 2D Y–Z curves in the Profiles tab (shared scaling)

            if app.AppState == 0 ...
                    || isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch)
                return;
            end

            % Determine cut mode from toggle: 'Straight' or 'Tapered'
            isTaper = true;
            if ~isempty(app.TaperToggle) && isgraphics(app.TaperToggle)
                isTaper = strcmp(app.TaperToggle.Value,'Tapered');
            end

            % Clear previous graphics
            app.clearProfiles();
            app.clearProfiles2D();

            % --- Current rotated mesh ---
            V = app.ModelPatch.Vertices;
            F = app.ModelPatch.Faces;

            mins    = min(V,[],1);
            maxs    = max(V,[],1);
            spanVec = maxs - mins;
            span    = max(spanVec);
            if span <= 0, span = 1; end

            epsX = 1e-6 * span;

            % Plane positions
            xLeft  = app.ModelXMin + app.NumLeftOffset.Value;
            xRight = app.ModelXMin + app.NumRightOffset.Value;

            % Colours matching planes
            leftColor  = [0.96 0.06 0.06];
            rightColor = [0.20 1.00 0.35];

            % -------------------------------------------------------
            % LEFT PROFILE
            % -------------------------------------------------------
            [xsL, ysL, zsL] = HotWireSTEPApp_v6_helpers.sliceMeshAtX( ...
                V, F, xLeft + epsX);

            % Raw mesh slice (for faint overlay in Profiles tab)
            if ~isempty(ysL) && any(~isnan(ysL))
                app.LeftProfileRawYZ = [ysL(:), zsL(:)];
            else
                app.LeftProfileRawYZ = [];
            end

            yLoopL = [];
            zLoopL = [];
            if ~isempty(xsL) && any(~isnan(xsL))
                [yLoopL, zLoopL] = HotWireSTEPApp_v6_helpers.buildMainProfileLoop( ...
                    xsL, ysL, zsL);
            end

            % Resample left profile by tolerance (if available)
            if ~isempty(yLoopL)
                tol = app.ProfileTolerance;
                if isfinite(tol) && tol > 0
                    [yLoopL, zLoopL] = HotWireSTEPApp_v6_helpers.resampleProfileByTolerance( ...
                        yLoopL, zLoopL, tol);
                end

                % --- NEW: re-order loop so it starts at minimum Y (then Z) ---
                [yLoopL, zLoopL] = HotWireSTEPApp_v6_helpers.reorderLoopByMinY( ...
                    yLoopL, zLoopL);

                xVecL = xLeft * ones(numel(yLoopL),1);
                app.LeftProfileLine3D = plot3(app.AxModel, ...
                    xVecL, yLoopL, zLoopL, ...
                    'Color', leftColor, 'LineWidth',1.4);

                app.LeftProfilePoints = [xVecL, yLoopL, zLoopL];
            else
                app.LeftProfilePoints = [];
            end

            % -------------------------------------------------------
            % RIGHT PROFILE
            % -------------------------------------------------------
            [xsR, ysR, zsR] = HotWireSTEPApp_v6_helpers.sliceMeshAtX( ...
                V, F, xRight - epsX);

            % Raw mesh slice (for faint overlay in Profiles tab)
            if ~isempty(ysR) && any(~isnan(ysR))
                app.RightProfileRawYZ = [ysR(:), zsR(:)];
            else
                app.RightProfileRawYZ = [];
            end

            yLoopR = [];
            zLoopR = [];

            if isTaper
                % TAPERED MODE:
                %   Right profile is a true slice at the right plane.
                if ~isempty(xsR) && any(~isnan(xsR))
                    [yLoopR, zLoopR] = HotWireSTEPApp_v6_helpers.buildMainProfileLoop( ...
                        xsR, ysR, zsR);
                end

                % Resample right profile by tolerance
                if ~isempty(yLoopR)
                    tol = app.ProfileTolerance;
                    if isfinite(tol) && tol > 0
                        [yLoopR, zLoopR] = HotWireSTEPApp_v6_helpers.resampleProfileByTolerance( ...
                            yLoopR, zLoopR, tol);
                    end

                    % --- NEW: re-order loop so it starts at minimum Y (then Z) ---
                    [yLoopR, zLoopR] = HotWireSTEPApp_v6_helpers.reorderLoopByMinY( ...
                        yLoopR, zLoopR);
                end
            else
                % STRAIGHT MODE:
                %   Force right cutting profile to match left profile
                %   (same Y–Z loop), but drawn at the right plane X.
                yLoopR = yLoopL;
                zLoopR = zLoopL;
            end

            % Draw right profile in 3D if we have something
            if ~isempty(yLoopR)
                xVecR = xRight * ones(numel(yLoopR),1);
                app.RightProfileLine3D = plot3(app.AxModel, ...
                    xVecR, yLoopR, zLoopR, ...
                    'Color', rightColor, 'LineWidth',1.4);

                app.RightProfilePoints = [xVecR, yLoopR, zLoopR];
            else
                app.RightProfilePoints = [];
            end

            % -------------------------------------------------------
            % Update "points (L/R)" read-out + simple cap indication
            % -------------------------------------------------------
            nL = 0;
            nR = 0;
            if ~isempty(app.LeftProfilePoints)
                nL = size(app.LeftProfilePoints,1);
            end
            if ~isempty(app.RightProfilePoints)
                nR = size(app.RightProfilePoints,1);
            end

            if ~isempty(app.ProfilePointCountLabel) && isgraphics(app.ProfilePointCountLabel)
                capN = HotWireSTEPApp_v6_helpers.ProfileResampleMaxPoints;

                if nL == 0 && nR == 0
                    app.ProfilePointCountLabel.Text = 'Number of Points (L/R): -- / --';
                else
                    if (nL >= capN) || (nR >= capN)
                        suffix = sprintf('  (cap at %d pts)', capN);
                    else
                        suffix = '';
                    end
                    app.ProfilePointCountLabel.Text = ...
                        sprintf('Number of Points (L/R): %d / %d%s', nL, nR, suffix);
                end
            end


            % -------------------------------------------------------
            % 2D PROFILES TAB UPDATE (shared Y/Z limits)
            % -------------------------------------------------------
            app.updateProfiles2D(yLoopL, zLoopL, yLoopR, zLoopR, xLeft, xRight);

            drawnow limitrate nocallbacks;
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

            leftColor  = [0.96 0.06 0.06];
            rightColor = [0.20 1.00 0.35];

            % Faint "mesh slice" colours: grey with a hint of red/green
            leftRawColor  = [0.80 0.80 0.80];
            rightRawColor = [0.80 0.80 0.80];

            % Clear only profile lines (labels/titles persist)
            app.clearProfiles2D();

            % ----- LEFT AXIS -----
            hold(app.AxLeftProfile,'on');

            % Raw mesh slice (background)
            if ~isempty(app.LeftProfileRawYZ)
                rawL = app.LeftProfileRawYZ;
                app.LeftProfile2DMeshLine = plot(app.AxLeftProfile, ...
                    rawL(:,1), rawL(:,2), ...
                    'Color',leftRawColor, ...
                    'LineStyle',':', ...
                    'LineWidth',2.5);
            end

            % Resampled main loop (geometry, no kerf)
            if ~isempty(yL)
                app.LeftProfile2DLine = plot(app.AxLeftProfile, ...
                    yL, zL, ...
                    'Color', leftColor, ...
                    'LineWidth',0.75);
            end

            % Kerf-compensated path (wire centreline)
            if app.KerfEnabled && ~isempty(yL) && app.KerfValue > 0
                [yKerfL, zKerfL] = HotWireSTEPApp_v6_helpers.offsetProfileLoop( ...
                    yL, zL, app.KerfValue);

                app.LeftKerf2DLine = plot(app.AxLeftProfile, ...
                    yKerfL, zKerfL, ...
                    'Color',[1.0 0.75 0.0], ...   % warm "wire" colour
                    'LineWidth',0.75);
            end

            hold(app.AxLeftProfile,'off');

            % ----- RIGHT AXIS -----
            hold(app.AxRightProfile,'on');

            if ~isempty(app.RightProfileRawYZ)
                rawR = app.RightProfileRawYZ;
                app.RightProfile2DMeshLine = plot(app.AxRightProfile, ...
                    rawR(:,1), rawR(:,2), ...
                    'Color',rightRawColor, ...
                    'LineStyle',':', ...
                    'LineWidth',2.5);
            end

            if ~isempty(yR)
                app.RightProfile2DLine = plot(app.AxRightProfile, ...
                    yR, zR, ...
                    'Color', rightColor, ...
                    'LineWidth',0.75);
            end

            if app.KerfEnabled && ~isempty(yR) && app.KerfValue > 0
                [yKerfR, zKerfR] = HotWireSTEPApp_v6_helpers.offsetProfileLoop( ...
                    yR, zR, app.KerfValue);
                app.RightKerf2DLine = plot(app.AxRightProfile, ...
                    yKerfR, zKerfR, ...
                    'Color',[1.0 0.75 0.0], ...
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

            V = app.ModelPatch.Vertices;
            mins = min(V,[],1); maxs = max(V,[],1);
            span = max(maxs - mins); if span <= 0, span = 1; end
            pad  = app.PlanePaddingFactor * span;

            % Force COLUMN vectors (4x1) with semicolons
            yLims = [mins(2)-pad; maxs(2)+pad; maxs(2)+pad; mins(2)-pad];
            zLims = [mins(3)-pad; mins(3)-pad; maxs(3)+pad; maxs(3)+pad];

            % Protect X with (1) indexing
            xL = app.ModelXMin(1) + app.NumLeftOffset.Value;
            xR = app.ModelXMin(1) + app.NumRightOffset.Value;

            app.LeftPlanePatch = patch(app.AxModel, 'XData', [xL;xL;xL;xL], ...
                'YData', yLims, 'ZData', zLims, ...
                'FaceColor', [0.96 0.06 0.06], 'FaceAlpha', 0.4, ...
                'EdgeColor', [0.96 0.06 0.06], 'LineStyle','--', 'LineWidth', 1.0);

            app.RightPlanePatch = patch(app.AxModel, 'XData', [xR;xR;xR;xR], ...
                'YData', yLims, 'ZData', zLims, ...
                'FaceColor', [0.20 1.00 0.35], 'FaceAlpha', 0.4, ...
                'EdgeColor', [0.20 1.00 0.35], 'LineStyle','--', 'LineWidth', 1.0);

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
            elseif currTab == app.TabBillet
                % [Billet to Machine transition logic from previous turn...]
                app.TabGroup.SelectedTab = app.TabMachine;
                app.syncMachineUI();
                app.refreshMachinePlot();
            elseif currTab == app.TabMachine
                % Final Step: Transition to G-Code Export (Placeholder)
                uialert(app.UIFigure, 'Setup Complete! Proceeding to G-code Generation...', 'Success', 'Icon', 'success');
                % app.TabGroup.SelectedTab = app.TabExport; % If you add an export tab later
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
            if isempty(app.BilletSizeEdits), return; end

            % 1. Calculate Model Bounds & Dimensions
            V = app.ModelPatch.Vertices;
            xL = app.ModelXMin + app.NumLeftOffset.Value;
            xR = app.ModelXMin + app.NumRightOffset.Value;

            % mMin and mMax are the boundaries of the model
            mMin = [min(xL,xR), min(V(:,2)), min(V(:,3))];
            mMax = [max(xL,xR), max(V(:,2)), max(V(:,3))];
            mDim = mMax - mMin;
            bSize = app.BilletSize; % The current user-defined stock size

            for i = 1:3
                % Update stock size field
                app.BilletSizeEdits(i).Value = bSize(i);

                % Update the model dimension readout label
                app.BilletModelDimLabels(i).Text = sprintf('%.2f mm', mDim(i));

                % Positioning Fields
                app.BilletNegOffsetEdits(i).Value    = mMin(i);
                app.BilletCenterOffsetEdits(i).Value = app.BilletShift(i);
                app.BilletPosOffsetEdits(i).Value    = bSize(i) - mMax(i);
            end

            % 2. Safety Warnings (Color Coding)
            eps = 1e-5;
            % isOutside = Is any part of the model below 0 or beyond the stock size?
            isOutside = any(mMin < -eps) || any(mMax > bSize + eps);

            % isTooClose = Less than 5mm clearance on Y or Z faces
            isTooClose = (mMin(2) < 5) || (mMax(2) > bSize(2) - 5) || ...
                (mMin(3) < 5) || (mMax(3) > bSize(3) - 5);

            if isOutside
                app.BilletLeftPanel.BackgroundColor = [0.4 0.16 0.16]; % Red
                % --- BLOCK BUTTON ---
                app.BtnBilletContinue.Enable = 'off';
                app.BtnBilletContinue.BackgroundColor = [0.3 0.3 0.3];
                app.BtnBilletContinue.FontColor       = [0.8 0.8 0.8];
                app.BilletMessageLabel.Text = 'CRITICAL: Model is outside billet bounds!';
                app.BilletMessageLabel.FontColor = [1 0.4 0.4];
            else
                % If Valid or Amber
                if isTooClose
                    app.BilletLeftPanel.BackgroundColor = [0.45 0.35 0.1]; % Amber
                    app.BilletMessageLabel.Text = 'Warning: Model is very close to billet edges.';
                    app.BilletMessageLabel.FontColor = [1 0.8 0.4];
                else
                    app.BilletLeftPanel.BackgroundColor = [0.16 0.16 0.16]; % Normal
                    app.BilletMessageLabel.Text = 'Billet configuration valid.';
                    app.BilletMessageLabel.FontColor = [0.4 1 0.4];
                end

                % --- ALLOW PROGRESS ---
                app.BtnBilletContinue.Enable = 'on';
                app.BtnBilletContinue.BackgroundColor = [0.1 0.6 0.1]; % Highlight Green
                app.BtnBilletContinue.FontColor       = [1 1 1];
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
            if isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch), return; end

            % 1. Get current model minima (currently relative to 0,0,0 stock corner)
            V = app.ModelPatch.Vertices;
            xL = app.ModelXMin + app.NumLeftOffset.Value;
            xR = app.ModelXMin + app.NumRightOffset.Value;
            mMin = [min(xL,xR), min(V(:,2)), min(V(:,3))];

            % 2. Targets from Helper
            h = HotWireSTEPApp_v6_helpers;
            targetMin = [h.BilletXBuffer, h.BilletYBuffer, h.BilletZMinClear];

            % 3. Calculate movement required
            deltas = targetMin - mMin;

            % 4. Apply Virtual movements (will NOT move Model Tab vertices)
            for i = 1:3
                app.moveModelInSpace(i, deltas(i));
            end

            % DO NOT reset app.BilletShift = [0 0 0] here!
            % The shift is now the source of truth for the position.
        end

        function onResetPosition(app)
            if isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch), return; end

            % Calculate delta needed to get back to the Reference (Import) bounds
            dx = app.BilletRefXMin - app.ModelXMin;
            dy = app.BilletRefYMin - app.ModelYMin;
            dz = app.BilletRefZMin - app.ModelZMin;

            % Physically move the model back
            app.moveModelInSpace(1, dx);
            app.moveModelInSpace(2, dy);
            app.moveModelInSpace(3, dz);

            % Since we are now back at the Reference point, reset the UI shift counter
            app.BilletShift = [0 0 0];
            app.syncBilletUI();
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

            % Current Model Bounds (including current planes for X)
            xL = app.ModelXMin + app.NumLeftOffset.Value;
            xR = app.ModelXMin + app.NumRightOffset.Value;
            mMin = [min(xL,xR), min(V(:,2)), min(V(:,3))];
            mMax = [max(xL,xR), max(V(:,2)), max(V(:,3))];

            % Billet is fixed at 0 in this tab
            bMin = [0, 0, 0];
            bMax = app.BilletSize;

            delta = 0;
            if strcmp(whichField, 'neg')
                % Target ModelMin = BilletMin(0) + InputGap
                delta = (bMin(axisIdx) + val) - mMin(axisIdx);
            elseif strcmp(whichField, 'pos')
                % Target ModelMax = BilletMax(Size) - InputGap
                delta = (bMax(axisIdx) - val) - mMax(axisIdx);
            elseif strcmp(whichField, 'center')
                % Manual shift input
                delta = val - app.BilletShift(axisIdx);
            end

            app.moveModelInSpace(axisIdx, delta);
        end

        function moveModelInSpace(app, axisIdx, delta)
            % Update the virtual shift counter only
            % (Supports the multi-model workflow where vertices stay put)
            app.BilletShift(axisIdx) = app.BilletShift(axisIdx) + delta(1);

            % Update UI and Billet visuals
            app.syncBilletUI();
            app.refreshBilletPlots();

            % Update Machine simulation if visible
            if app.TabGroup.SelectedTab == app.TabMachine
                app.refreshMachinePlot();
            end
        end

        function onBilletShift(app, axisIdx, delta)
            app.moveModelInSpace(axisIdx, delta);
        end

        function refreshBilletPlots(app)
            if isempty(app.ModelPatch), return; end

            V = app.ModelPatch.Vertices;
            F = app.ModelPatch.Faces;
            bMax  = app.BilletSize;
            shift = app.BilletShift;

            axs  = {app.AxBilletTop, app.AxBilletFront, app.AxBilletRight};
            pair = {[1 2], [1 3], [2 3]};
            labs = {{'X (mm)','Y (mm)'}, {'X (mm)','Z (mm)'}, {'Y (mm)','Z (mm)'}};

            for i = 1:3
                ax = axs{i}; p = pair{i};
                cla(ax); hold(ax,'on');

                % Draw Billet Outline (Dashed relative to stock origin 0,0,0)
                bx = [0 bMax(p(1)) bMax(p(1)) 0 0];
                by = [0 0 bMax(p(2)) bMax(p(2)) 0];
                plot(ax, bx, by, 'w--', 'LineWidth', 1.5);

                % SHIFT-CORRECTED Display: Apply shift only to visual data
                Vplot = V(:,p) + shift(p);
                patch(ax, 'Vertices', Vplot, 'Faces', F, ...
                    'FaceColor', [0.5 0.5 0.6], 'EdgeColor', 'none', 'FaceAlpha', 0.4);

                axis(ax, 'equal'); grid(ax, 'on');
                xlabel(ax, labs{i}{1}); ylabel(ax, labs{i}{2});
            end
            drawnow limitrate;
        end

        % ===========================================================
        % MACHINE TAB CALLBACKS
        % ===========================================================

        function onMachinePosEdited(app, axisIdx, src)
            oldVal = app.MachineBilletPos(axisIdx);
            if axisIdx == 1
                app.MachineBilletPos(1) = app.MachineBedPos(1) + src.Value;
            else
                app.MachineBilletPos(axisIdx) = src.Value;
            end

            % Move the model by the same delta
            delta = app.MachineBilletPos(axisIdx) - oldVal;
            app.moveModelInSpace(axisIdx, delta);

            app.refreshMachinePlot();
        end

        function onResetMachineBilletPosition(app)
            % 1. Calculate the "Clever Default" target
            offX = app.MachineBedPos(1);
            idealUserX = (app.MachineBedSize(1) - app.BilletSize(1)) / 2;
            roundedUserX = 50 * floor(idealUserX / 50);

            targetPos = [offX + max(0, roundedUserX), 50.0, 0.0];

            % 2. Calculate delta and move model/billet
            for i = 1:3
                delta = targetPos(i) - app.MachineBilletPos(i);
                app.moveModelInSpace(i, delta);
            end

            % 3. Update state and UI
            app.MachineBilletPos = targetPos;
            app.syncMachineUI();
            app.refreshMachinePlot();
        end

        function onResetMachinePlotView(app)
            ax = app.AxMachine;
            if isempty(ax) || ~isgraphics(ax), return; end

            % Reset to the isometric overview
            view(ax, 3);

            % Re-apply the standard limits used in refreshMachinePlot
            offX = app.MachineBedPos(1);
            mSpan = app.MachineSpan;
            bs = app.MachineBedSize;

            xlim(ax, [-offX - 50, mSpan(1)-offX + 50]);
            ylim(ax, [-50, mSpan(2) + 50]);
            zlim(ax, [-bs(3)-10, mSpan(3) + 20]);

            % Force a redraw to fix any rotation artifacts
            drawnow limitrate;
        end

        function refreshMachinePlot(app)
            ax = app.AxMachine;
            if isempty(ax) || ~isgraphics(ax), return; end

            % --- 0. DEEP CLEAR (Fixes Ghosting) ---
            % delete(allchild(ax)) removes everything, even objects with hidden handles
            delete(allchild(ax));
            hold(ax, 'on');

            % --- 1. THEME & GEOMETRY PREP ---
            if app.UIFigure.Color(1) < 0.5
                cageCol = [0.6 0.6 0.6]; tickCol = [1 1 1]; bgCol = [0.05 0.05 0.05];
                planeAlpha = 0.15; wireCol = [0.8 0.8 0.8];
            else
                cageCol = [0.3 0.3 0.3]; tickCol = [0 0 0]; bgCol = [1 1 1];
                planeAlpha = 0.08; wireCol = [0.2 0.2 0.2];
            end

            offX  = app.MachineBedPos(1);
            mSpan = app.MachineSpan;
            bs    = app.MachineBedSize;
            bp    = app.MachineBedPos;

            bPlotPos = [app.MachineBilletPos(1) - offX, app.MachineBilletPos(2), app.MachineBilletPos(3)];

            % --- 2. PHYSICAL BED & CAGE ---
            [xb, yb, zb] = app.makeBoxVertices(0, bp(2), -bs(3), bs(1), bs(2), bs(3));
            patch(ax, 'Vertices',[xb, yb, zb], 'Faces', app.boxFaces, ...
                'FaceColor',[0.4 0.4 0.4], 'FaceAlpha', 0.5, 'EdgeColor',[0.2 0.2 0.2]);

            [xl, yl, zl] = app.makeBoxVertices(-offX, 0, 0, mSpan(1), mSpan(2), mSpan(3));
            patch(ax, 'Vertices',[xl, yl, zl], 'Faces', app.boxFaces, ...
                'FaceColor','none', 'EdgeColor', cageCol, 'LineStyle',':', 'EdgeAlpha',0.3);

            % --- 3. TOWER HEAD PLANES ---
            xL_edge = 0 - offX;
            xR_edge = mSpan(1) - offX;
            pY = [0; mSpan(2); mSpan(2); 0]; pZ = [0; 0; mSpan(3); mSpan(3)];

            patch(ax, 'XData',ones(4,1)*xL_edge, 'YData',pY, 'ZData',pZ, 'FaceColor', [0.96 0.06 0.06], ...
                'FaceAlpha', planeAlpha, 'EdgeColor',[0.96 0.06 0.06], 'LineStyle', '--');
            patch(ax, 'XData',ones(4,1)*xR_edge, 'YData',pY, 'ZData',pZ, 'FaceColor', [0.20 1.00 0.35], ...
                'FaceAlpha', planeAlpha, 'EdgeColor',[0.20 1.00 0.35], 'LineStyle', '--');

            % --- 4. BILLET & MODEL ---
            [xm, ym, zm] = app.makeBoxVertices(bPlotPos(1), bPlotPos(2), bPlotPos(3), app.BilletSize(1), app.BilletSize(2), app.BilletSize(3));
            patch(ax, 'Vertices',[xm, ym, zm], 'Faces', app.boxFaces, 'FaceColor', tickCol, 'FaceAlpha', 0.03, ...
                'EdgeColor', tickCol, 'LineStyle','--', 'LineWidth', 1.2, 'EdgeAlpha', 0.8);

            if ~isempty(app.ModelPatch) && isgraphics(app.ModelPatch)
                V = app.ModelPatch.Vertices;
                totalShift = bPlotPos + app.BilletShift;
                Vplot = V + totalShift;
                patch(ax, 'Vertices', Vplot, 'Faces', app.ModelPatch.Faces, 'FaceColor',[0.6 0.6 0.7], 'FaceAlpha', 0.8, 'EdgeColor','none');

                % --- WIREFRAME PROFILE OVERLAYS ---
                if ~isempty(app.LeftProfilePoints)
                    LP = app.LeftProfilePoints + totalShift;
                    plot3(ax, LP(:,1), LP(:,2), LP(:,3), 'Color', wireCol, 'LineWidth', 0.8);
                end
                if ~isempty(app.RightProfilePoints)
                    RP = app.RightProfilePoints + totalShift;
                    plot3(ax, RP(:,1), RP(:,2), RP(:,3), 'Color', wireCol, 'LineWidth', 0.8);
                end
            end

            % --- 5. TOWER LABELS ---
            hL = text(ax, xL_edge, mSpan(2)*0.98, mSpan(3)*0.92, {' LEFT',' TOWER'}, 'Color', [0.96 0.4 0.4], ...
                'FontWeight', 'bold', 'FontSize', 10, 'VerticalAlignment', 'top', 'HorizontalAlignment', 'left');
            hR = text(ax, xR_edge, mSpan(2)*0.01, mSpan(3)*0.92, {'RIGHT','TOWER '}, 'Color', [0.4 1.00 0.5], ...
                'FontWeight', 'bold', 'FontSize', 10, 'VerticalAlignment', 'top', 'HorizontalAlignment', 'right');
            uistack(hL, 'top'); uistack(hR, 'top');

            % --- 6. FORMATTING ---
            view(ax, 3); axis(ax, 'equal'); grid(ax, 'on');
            xlabel(ax, 'X (Bed Relative)'); ylabel(ax, 'Y (Machine)'); zlabel(ax, 'Z');
            ax.BackgroundColor = bgCol;
            set(ax, 'XColor', tickCol, 'YColor', tickCol, 'ZColor', tickCol);

            xlim(ax, [-offX - 100, mSpan(1)-offX + 100]);
            ylim(ax, [-50, mSpan(2) + 50]);
            zlim(ax, [-bs(3)-20, mSpan(3) + 80]);

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

    end
end
