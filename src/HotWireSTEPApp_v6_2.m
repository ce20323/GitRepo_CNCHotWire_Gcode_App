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
        % ===========================================================
        % CONSTANTS & DEFAULTS
        % ===========================================================

        % -------- Profile sampling defaults --------
        DefaultProfileTolerance (1,1) double = 0.05;   % [mm] Max error for resampling
        MinProfileTolerance     (1,1) double = 0.01;  % [mm] Highest precision
        MaxProfileTolerance     (1,1) double = 5.0;   % [mm] Lowest precision

        % -------- Kerf / wire offset defaults --------
        DefaultKerf (1,1) double = 0.5;   % [mm] Default wire thickness compensation
        MinKerf     (1,1) double = -4.0;   % [mm] No kerf
        MaxKerf     (1,1) double = 4.0;   % [mm] Maximum allowed kerf

        % -------- View / plane padding factors --------
        AutoFitPaddingFactor (1,1) double = 0.35;  % Padding around model in 3D view
        PlanePaddingFactor   (1,1) double = 0.20;  % Padding for cutting planes

        % --- Billet UI Increments ---
        BilletSizeStep  (1,1) double = 1.0;  % [mm] Step size for Billet Size +/- buttons
        BilletShiftStep (1,1) double = 0.5;  % [mm] Step size for Position +/- buttons


        % ===========================================================
        % MACHINE CONFIGURATION (Physical Limits)
        % ===========================================================

        % Distance between the Left and Right tower cutting planes.
        MachineSpanX   = 1180;            % [mm] Fixed distance between towers

        % Travel Limits (Scalars for Max Travel)
        MachineLimitY  = 750;             % [mm] Total Y travel (0 to 750)
        MachineLimitZ  = 500;             % [mm] Total Z travel (0 to 500)

        % Physical Bed Definition
        % Z=-20 implies the bed top surface is at Z=0 (Home).
        MachineBedPos    = [50, 50, -20];   % [mm] Bed origin [X, Y, Z]
        MachineBedSize   = [1000, 700, 20]; % [mm] Physical dimensions [L, W, H]


        % ===========================================================
        % SAFETY & PLACEMENT RULES
        % ===========================================================

        % --- Machine Tab Safety ---

        % Distance from bed edge to trigger Amber warning (Machine Tab)
        SafetyBuffer_BedEdge = 50.0; % [mm]

        % Rounding grid for auto-placement of Billet (Machine Tab)
        BilletRoundingY  = 10.0; % [mm]

        % Min buffer from Front Home for default placement logic
        BilletMinYBuffer = 50.0; % [mm]

        % --- Billet Tab Safety (Model inside Stock) ---

        % Tolerance for "Outside" Error (Red)
        ModelContainmentTol = 0.0001; % [mm]

        % Buffer for "Too Close" Warning (Amber)
        ModelEdgeWarningBuffer = 4.0; % [mm]

        % Tiny buffer for X placement (Start just inside the block)
        ModelXPlacementBuffer = 0.001; % [mm]
    end

    properties
        % ===========================================================
        % DYNAMIC APP STATE
        % ===========================================================

        % ---------- UI Containers (Tabs) ----------
        UIFigure                        % Main application window
        TabGroup                        % Tabbed container
        TabModel                        % Model import & orient tab
        TabProfiles                     % Profiles tab
        TabBillet                       % Billet tab
        TabMachine                      % Machine tab
        TabCutting                      % Cutting Strategy tab
        TabSimulation                   % Simulation tab
        TabPostProcess                  % Post-Process tab

        % ---------- Layout Containers (Grids/Panels) ----------
        GLModel                         % Model tab layout
        GLLeft                          % Model tab left panel
        GLProfiles                      % Profiles tab layout
        profilesLeft                    % Profiles tab left panel
        GLBillet                        % Billet tab layout
        BilletLeftPanel                 % Billet tab left panel
        BilletRightPanel                % Billet tab right panel
        GLMachine                       % Machine tab layout
        MachineLeftPanel                % Machine tab left panel
        GLCutting                       % Cutting tab layout
        CuttingLeftPanel                % Cutting tab left panel
        GLSimulation                    % Simulation tab layout
        SimLeftPanel                    % Simulation tab left panel
        GLPostProcess                   % Post Process tab layout
        PostLeftPanel                   % Post Process tab left panel
        
        % Tab Feedback
        TxtModelStatus    % Text area for validation messages
        TxtModelGuide     % Text area for instructions
        TxtProfileStatus
        TxtProfileGuide

        % Background panels
        cutPanel; cutGrid               % Toggle switch containers

        % ---------- Axes Handles ----------
        AxModel                         % 3D Model View
        AxLeftProfile                   % 2D Left Profile View
        AxRightProfile                  % 2D Right Profile View
        AxBilletTop                     % Billet Top View
        AxBilletFront                   % Billet Front View
        AxBilletRight                   % Billet Right View
        AxMachine                       % 3D Machine Placement View
        AxCutLeft                       % 2D Cut Strategy View (Left)
        AxCutRight                      % 2D Cut Strategy View (Right)
        AxSim                           % 3D Simulation View
        AxPost                          % 3D Post-Process Verification View

        % ---------- Model Import & State ----------
        BtnImportSTEP                   % Import STEP button
        BtnImportSTL                    % Import STL button
        FileLabel                       % Label showing current filename
        ModelPatch                      % Patch object for the 3D model
        ModelVerticesOriginal           % Original vertices of the model (for resets)
        ModelF                          % Faces of the current model
        CurrentModelName string = ""    % Name of the current model file
        FreeCADExe = "C:\Program Files\FreeCAD 1.0\bin\FreeCADCmd.exe" % Path to FreeCAD

        % --- Home View State ---
        DefaultXLim; DefaultYLim; DefaultZLim
        DefaultDataAspectRatio; DefaultPlotBoxAspectRatio
        DefaultCameraPosition; DefaultCameraTarget
        DefaultCameraUpVector; DefaultCameraViewAngle

        % --- Mouse Interaction ---
        IsDragging logical = false      % Flag for mouse drag state
        LastMousePos (1,2) double = [NaN NaN]  % Last mouse position
        AppState (1,1) double = 0       % 0=Model Only, 1=Active Cutting

        % ---------- Orientation Controls ----------
        RotGrid                         % Layout for rotation controls
        RotEdit                         % Edit fields for rotation angles
        RotAngles double = [0 0 0]      % Rotation angles [X Y Z]
        BtnResetOrientation             % Button to reset model orientation
        BtnResetPlot                    % Button to reset plot view
        TaperToggle                     % Toggle switch for taper mode

        % ---------- Plane Offsets ----------
        NumLeftOffset                   % Numeric edit field for left plane offset
        NumRightOffset                  % Numeric edit field for right plane offset
        BtnResetPlanes                  % Button to reset plane offsets

        % --- Model Bounding Box ---
        ModelXMin; ModelXMax            % Model X bounds
        ModelYMin; ModelYMax            % Model Y bounds
        ModelZMin; ModelZMax            % Model Z bounds

        % --- Plane Graphics ---
        LeftPlanePatch; RightPlanePatch  % Patch objects for the cutting planes
        LeftPlaneText; RightPlaneText    % Text labels for the cutting planes

        % ---------- Profile Extraction ----------
        BtnGenerateProfiles             % Button to generate profiles
        BtnContinue                     % Continue button (Model -> Profiles)
        BtnProfilesContinue             % Continue button (Profiles -> Billet)

        ProfileTolerance (1,1) double = 0.2   % [mm] Target segment size
        ProfileTolSpinner                     % UI handle for tolerance control
        ProfileAxesLocked (1,1) logical = false % Prevent auto zoom on Profile tab
        BtnResetProfileTol                % Button to reset profile tolerance
        BtnResetProfilesView              % Button to reset profiles view
        ProfilePointCountLabel            % Read-only label for profile point count

        % --- Profile Data ---
        LeftProfileLine3D; RightProfileLine3D % 3D line objects for the profiles
        LeftProfilePoints; RightProfilePoints   % Nx3 [X Y Z] (Model relative)
        LeftProfileRawYZ; RightProfileRawYZ     % Raw mesh slices

        % --- 2D Plot Handles ---
        LeftProfile2DLine; RightProfile2DLine   % 2D line objects for the profiles
        LeftProfile2DMeshLine; RightProfile2DMeshLine  % Faint raw mesh slices

        % --- Kerf ---
        KerfValue (1,1) double = 0.5          % [mm] Positive = shrink profile
        KerfSpinner                           % UI handle for kerf control
        KerfPointCountLabel                   % New label for kerf stats
        BtnApplyKerf                          % Button to apply kerf offset
        BtnResetKerf                          % Button to reset kerf
        KerfEnabled (1,1) logical = false     % Only draw kerf when true
        LeftKerf2DLine; RightKerf2DLine       % 2D kerf path lines

        % ---------- Billet Configuration ----------
        BtnAutoFitBillet                    % Button to auto-fit the billet
        BtnResetPosition                    % Button to reset billet position
        BilletMessageLabel                  % Label for displaying billet messages
        BilletModelDimLabels                % Labels for displaying model dimensions
        BtnBilletContinue                   % Button to continue from Billet tab

        % --- Billet Geometry State ---
        BilletSize  = [0 0 0]              % [Length X, Width Y, Height Z]
        BilletShift = [0 0 0]              % [dX, dY, dZ] Machining Offset

        % --- Reference Bounds ---
        BilletRefXMin; BilletRefYMin; BilletRefZMin   % Reference bounds for import position
        BilletXMin; BilletXMax; BilletYMin; BilletYMax; BilletZMin; BilletZMax % Billet bounds

        % --- Billet UI Controls ---
        BilletSizeEdits; BilletSizeMinusBtns; BilletSizePlusBtns  % Size edit fields and buttons
        BtnAutoPositionModel                % Button to auto-position the model in the billet
        BilletNegOffsetEdits; BilletCenterOffsetEdits; BilletPosOffsetEdits % Offset edit fields
        BilletShiftMinusBtns; BilletShiftPlusBtns    % Shift buttons

        % ---------- Machine Setup ----------
        MachinePosSpinners       % 1x3 handles for the spinners
        MachineBilletPos = [100, 50, 0]   % Billet origin relative to machine 0,0,0
        BtnResetMachineBillet
        BtnResetMachinePlot
        BtnMachineContinue
        MachineMessageLabel

        % ---------- Cutting Strategy ----------
        % Note: Tab and Layout handles are defined in "UI Containers" above

        % --- Interaction Controls ---
        SwitchCutDir           % Toggle: Top-First (CW) vs Bottom-First (CCW)
        BtnInteractionGroup    % Button Group for mouse mode

        BtnPickStart           % Button: "Set Start Point"
        BtnPickEntry           % Button: "Set Entry Point" (Future)
        BtnPickEntry2          % New Button
        BtnClearEntries        % Helper to reset points

        % --- Cutting Tab Properties ---
        SyncStartPoints (1,1) logical = true % Default to sync

        % --- Entry Points (Machine Coordinates [y, z]) ---
        EntryPointL = []; EntryPointR = [];
        EntryPoint2L = []; EntryPoint2R = [];

        % --- UI Elements ---
        SwitchSyncStart  % Toggle: Coupled / Independent
        SwitchSyncEntry  % UI Switch for Entry Coupling
        btnAutoStart
        btnAutoEntry
        BtnCuttingContinue

        % --- Strategy State ---
        SelectedStartIdxL = 1  % Index in the profile array
        SelectedStartIdxR = 1
        CutDirection = 'CW'    % 'CW' or 'CCW'

        % ---------- Simulation Tab ----------
        BtnSimContinue

        % --- Controls ---
        SimSlider                         % Slider for timeline control
        SimIndexSpinner                   % NEW: Direct index input
        SimPlayBtn                        % Play button
        SimStopBtn                        % Stop button
        SimSpeedSpinner                   % Playback speed control

        % --- Readouts ---
        LblReadoutX                       % X Coord
        LblReadoutY                       % Y Coord
        LblReadoutZ                       % Z Coord
        LblReadoutA                       % A Coord

        % --- Visual Data (Interpolated for Smoothness) ---
        SimPathL                          % Nx3 [x, y, z] Machine Coords (Left)
        SimPathR                          % Nx3 [x, y, z] Machine Coords (Right)
        SimTowerPathL                     % Nx3 Projected to Left Tower
        SimTowerPathR                     % Nx3 Projected to Right Tower

        % --- Physics / Time-Stepping ---
        SimArcLenL                          % Nx1 Cumulative length (mm)
        SimArcLenR                          % Nx1 Cumulative length (mm)
        SimTotalLength                      % Scalar (Total cut length mm)
        SimPlayDist = 0                     % Current playback head (mm)
        SimStepDist = 2.0                   % Base speed (mm per tick)
        SimTimer                            % Timer object

        % --- Semantic Data (Raw Segments for G-Code) ---
        % These preserve the "Truth" geometry for the Post-Processor
        SimRawRapidL                        % [y z] semantic points for Rapid-In (Left)
        SimRawRapidR                        % [y z] semantic points for Rapid-In (Right)
        SimRawLeadInL                       % [y z] semantic points for Lead-In  (Left)
        SimRawLeadInR                       % [y z] semantic points for Lead-In  (Right)
        SimRawLeadOutL                      % [y z] semantic points for Lead-Out (Left)
        SimRawLeadOutR                      % [y z] semantic points for Lead-Out (Right)
        SimRawReturnL                       % [y z] semantic points for Return (Left)
        SimRawReturnR                       % [y z] semantic points for Return (Right)

        % --- Truth Profiles (Synced) ---
        ProfileSyncL                        % Nx2 [Y Z] (After syncPointCounts)
        ProfileSyncR                        % Nx2 [Y Z] (After syncPointCounts)

        % --- Segment Indices (For coloring the plot) ---
        SimRapidCutoffIndex               % Index where rapid ends
        SimProfileStartIndex              % Index where profile starts
        SimFeedEndIndex                   % Index where feed ends
        SimLeadOutEndIndex                % Index where lead-out ends

        % ---------- Post-Process Tab ----------
        SpinFeedRate
        SpinPower
        FieldFilename
        BtnPostProcess
        BtnGCodePrev; BtnGCodeNext; BtnSaveGCode

        % --- G-Code Viewer ---
        PanelGCode; GridGCode; ListGCode

        % --- Post-Processor State ---
        PP_GCodeLines string = string.empty(0,1)   % full text, one line per row
        PP_LineToPathIndex double = []            % maps gcode line -> motion path index
        PP_PathXYZA double = []                   % Nx4 [X Y Z A] cumulative path
        PP_SelectedLine (1,1) double = 1          % Current selected line number

        % --- Post Verification Paths (Truth-based) ---
        PP_PathL                                  % Left cutting path
        PP_PathR                                  % Right cutting path
        PP_TowerPathL                             % Left Tower path
        PP_TowerPathR                             % Right Tower path

        PP_RapidEndIndex                          % Index where rapid ends
        PP_ProfileStartIndex                        % Index where profile starts
        PP_ProfileEndIndex                          % Index where feed ends
        PP_LeadOutEndIndex                        % Index where lead-out ends
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

            app.GLModel = uigridlayout(app.TabModel,[1 2]);
            app.GLModel.ColumnWidth   = {320,'1x'};
            app.GLModel.Padding       = [10 10 10 10];
            app.GLModel.ColumnSpacing = 10;

            % --- Left Control Panel ---
            app.GLLeft = uigridlayout(app.GLModel,[16 1]);
            app.GLLeft.Layout.Column = 1; app.GLLeft.BackgroundColor = sideBg;

            % Rows: 1-11 Controls, 12 Label, 13 Guide(1x), 14 Label, 15 Status, 16 Buttons
            app.GLLeft.RowHeight = {'fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','1x','fit','fit','fit'};
            app.GLLeft.Padding = [10 10 10 10];

            % 1. File Import
            app.BtnImportSTEP = uibutton(app.GLLeft, 'Text','Import STEP (recommended)', 'FontWeight','bold', ...
                'Tooltip', 'Load a .STEP file. Uses FreeCAD for accurate mesh generation.', ...
                'ButtonPushedFcn',@(~,~)app.onImportSTEP());
            app.BtnImportSTEP.Layout.Row = 1;

            app.BtnImportSTL = uibutton(app.GLLeft, 'Text','Import STL', 'FontWeight','bold', ...
                'Tooltip', 'Load a .STL mesh. Accuracy depends on file export settings.', ...
                'ButtonPushedFcn',@(~,~)app.onImportSTL());
            app.BtnImportSTL.Layout.Row = 2;

            app.FileLabel = uilabel(app.GLLeft, 'Text','Current File: ---', 'FontWeight','bold', 'FontColor',labelCol);
            app.FileLabel.Layout.Row = 3;

            % 2. Taper
            pnl_M_Cut = uipanel(app.GLLeft, 'BackgroundColor', sideBg, 'BorderType', 'line', 'Title', '');
            pnl_M_Cut.Layout.Row = 5;
            grid_M_Cut = uigridlayout(pnl_M_Cut,[1 3]); grid_M_Cut.ColumnWidth = {'1x','fit','1x'}; grid_M_Cut.Padding=[10 0 10 0]; grid_M_Cut.BackgroundColor = sideBg;
            lbl_M_Sp1 = uilabel(grid_M_Cut,'Text',''); lbl_M_Sp1.Layout.Column=1;

            app.TaperToggle = uiswitch(grid_M_Cut,'slider', 'Items',{'Straight','Tapered'}, 'Value','Straight', ...
                'Tooltip', sprintf('Straight: Prismatic (Identical profiles).\nTapered: Independent Left/Right profiles.'), ...
                'ValueChangedFcn',@(~,~)app.onTaperModeChanged());
            app.TaperToggle.Layout.Column = 2;
            lbl_M_Sp2 = uilabel(grid_M_Cut,'Text',''); lbl_M_Sp2.Layout.Column=3;

            % 3. Orientation (Centered)
            pnl_M_Rot = uipanel(app.GLLeft, 'Title','Model Orientation', 'BackgroundColor',panelBg, 'FontWeight','bold', 'ForegroundColor',labelCol);
            pnl_M_Rot.Layout.Row = 7;

            % Outer grid to force centering
            outer_M_Rot = uigridlayout(pnl_M_Rot,[1 3]);
            outer_M_Rot.ColumnWidth={'1x','fit','1x'};
            outer_M_Rot.Padding=[5 5 5 5]; outer_M_Rot.BackgroundColor=panelBg;

            % Inner controls
            app.RotGrid = uigridlayout(outer_M_Rot,[3 4]);
            app.RotGrid.Layout.Column = 2; % Center column
            app.RotGrid.ColumnWidth={'fit','fit',70,'fit'}; app.RotGrid.RowHeight={'fit','fit','fit'};
            app.RotGrid.Padding=[0 0 0 0]; app.RotGrid.BackgroundColor=panelBg;

            axesLabels = {'X','Y','Z'};
            app.RotEdit = gobjects(1,3);
            for i = 1:3
                lbl_M_Rot = uilabel(app.RotGrid, 'Text',axesLabels{i}, 'FontWeight','bold', 'HorizontalAlignment','center', 'FontColor',labelCol); lbl_M_Rot.Layout.Row=i;
                btn_M_Neg = uibutton(app.RotGrid,'Text','-90°', 'ButtonPushedFcn',@(~,~)app.rotateModel([axesLabels{i} 'm'])); btn_M_Neg.Layout.Row=i;

                app.RotEdit(i) = uieditfield(app.RotGrid,'numeric', 'Limits',[0 360], 'Value',0, 'HorizontalAlignment','center', 'ValueDisplayFormat','%.0f°', ...
                    'Tooltip', ['Rotate model around the ' axesLabels{i} ' axis.'], ...
                    'ValueChangedFcn',@(src,~)app.updateRotation(axesLabels{i},src.Value));
                app.RotEdit(i).Layout.Row=i;

                btn_M_Pos = uibutton(app.RotGrid,'Text','+90°', 'ButtonPushedFcn',@(~,~)app.rotateModel([axesLabels{i} 'p'])); btn_M_Pos.Layout.Row=i;
            end

            % Reset Controls
            btnMResO = uibutton(app.GLLeft, 'Text','Reset Orientation', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.resetOrientation());
            btnMResO.Layout.Row = 8;
            btnMResP = uibutton(app.GLLeft, 'Text','Reset Plot View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.resetPlotView());
            btnMResP.Layout.Row = 9;

            % 4. Offsets
            pnl_M_Off = uipanel(app.GLLeft, 'BackgroundColor',panelBg, 'BorderType','line');
            pnl_M_Off.Layout.Row = 11;
            grid_M_Off = uigridlayout(pnl_M_Off,[3 2]); grid_M_Off.ColumnWidth={'1x',90}; grid_M_Off.RowHeight={'fit','fit','fit'};

            lbl_M_OffL = uilabel(grid_M_Off,'Text','Left Plane Offset:','HorizontalAlignment','right','FontWeight','bold', 'FontColor',labelCol); lbl_M_OffL.Layout.Row=1; lbl_M_OffL.Layout.Column=1;

            % [FIX] FontColor=[0 0 0] to ensure readability on colored background
            app.NumLeftOffset = uispinner(grid_M_Off, 'Limits',[0 10000], 'Value',0, 'Step',1, ...
                'BackgroundColor',[0.96 0.86 0.86], 'FontColor', [0 0 0], ...
                'Tooltip', 'Distance from Model Left Face (X Min) to Left Cutting Plane', ...
                'ValueChangedFcn',@(src,evt)app.onPlaneOffsetChanged(src,evt));
            app.NumLeftOffset.Layout.Row=1; app.NumLeftOffset.Layout.Column=2;

            lbl_M_OffR = uilabel(grid_M_Off,'Text','Right Plane Offset:','HorizontalAlignment','right','FontWeight','bold', 'FontColor',labelCol); lbl_M_OffR.Layout.Row=2; lbl_M_OffR.Layout.Column=1;
            app.NumRightOffset = uispinner(grid_M_Off, 'Limits',[0 10000], 'Value',0, 'Step',1, ...
                'BackgroundColor',[0.86 0.96 0.86], 'FontColor', [0 0 0], ...
                'Tooltip', 'Distance from Model Left Face (X Min) to Right Cutting Plane', ...
                'ValueChangedFcn',@(src,evt)app.onPlaneOffsetChanged(src,evt));
            app.NumRightOffset.Layout.Row=2; app.NumRightOffset.Layout.Column=2;

            btn_M_ResPlane = uibutton(grid_M_Off, 'Text','Reset Planes', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.resetPlanes());
            btn_M_ResPlane.Layout.Row=3; btn_M_ResPlane.Layout.Column=[1 2];

            % 5. GUIDANCE (Row 13, Expanded 1x)
            lbl_M_Guide = uilabel(app.GLLeft, 'Text', 'Guidance', 'FontWeight','bold', 'FontColor',labelCol);
            lbl_M_Guide.Layout.Row = 12;

            guideText = {
                '1. Import your model by clicking Import STEP or STL';
                '';
                '2. Select straight for prismatic, or tapered for independant profiles.';
                '';
                '3. Rotate Model: Align cut profile to Y-Z plane.';                                                      
                '';
                '4. (Optional) Move the left/right planes if you want to cut a section of your model';
                '';
                '5. Click generate profiles, check the profiles look correct, then click continue';
                '';
                'TIP: The wire hits start/end of the profile twice, which can leave a "witness mark".';
                'Hide this on a trailing edge, inside the part, or somewhere not important for smoothness.';
                'Rotate the model so this point is toward the front of the machine (Ymin)';  
                };
            app.TxtModelGuide = uitextarea(app.GLLeft, 'Editable','off', 'Value', guideText, ...
                'BackgroundColor', sideBg, 'FontColor', labelCol);
            app.TxtModelGuide.Layout.Row = 13;

            % 6. STATUS (Row 15, Fixed Fit)
            lbl_M_Stat = uilabel(app.GLLeft, 'Text', 'Status', 'FontWeight','bold', 'FontColor',labelCol);
            lbl_M_Stat.Layout.Row = 14;

            app.TxtModelStatus = uitextarea(app.GLLeft, 'Editable','off', 'Value', {'No model loaded.'}, ...
                'BackgroundColor', [0.2 0.2 0.2], 'FontColor', [1 0.8 0]);
            app.TxtModelStatus.Layout.Row = 15;

            % 7. BUTTONS (Row 16)
            pnl_M_Btn = uipanel(app.GLLeft, 'BackgroundColor',sideBg, 'BorderType','none');
            pnl_M_Btn.Layout.Row = 16;
            grid_M_Btn = uigridlayout(pnl_M_Btn,[1 2]); grid_M_Btn.Padding=[0 0 0 0]; grid_M_Btn.BackgroundColor=sideBg;

            app.BtnGenerateProfiles = uibutton(grid_M_Btn, 'Text','Generate Profiles', 'FontWeight','bold', 'BackgroundColor',[0.15 0.45 0.8], 'FontColor',[1 1 1], ...
                'Tooltip', 'Slice model at the defined planes.', ...
                'ButtonPushedFcn',@(~,~)app.onGenerateProfiles());

            app.BtnContinue = uibutton(grid_M_Btn, 'Text','Continue →', 'FontWeight','bold', 'BackgroundColor',[0.3 0.3 0.3], 'FontColor',[0.8 0.8 0.8], ...
                'Enable','off', 'ButtonPushedFcn',@(~,~)app.onContinue());

            % --- Right Panel: 3D Model Axis ---
            app.AxModel = uiaxes(app.GLModel);
            app.AxModel.Layout.Column = 2; app.AxModel.BackgroundColor = [0.11 0.11 0.11];
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
            app.profilesLeft = uigridlayout(app.GLProfiles,[9 1]);
            app.profilesLeft.Layout.Column = 1;
            % Rows: Controls, Guide label, Guide(1x), Status label, Status box, Continue
            app.profilesLeft.RowHeight = {'fit','fit','fit','fit','fit','1x','fit','fit','fit'};
            app.profilesLeft.Padding = [10 10 10 10];
            app.profilesLeft.BackgroundColor = sideBg;

            % -- Tolerance --
            pnlTol = uipanel(app.profilesLeft, 'Title','Profile Sampling', ...
                'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlTol.Layout.Row = 1;

            gridTol = uigridlayout(pnlTol,[2 2]);
            gridTol.ColumnWidth = {'1x',90};
            gridTol.Padding = [10 5 10 5];

            lblTol = uilabel(gridTol, 'Text','Profile Tolerance [mm]:', ...
                'HorizontalAlignment','right', 'FontWeight','bold', 'FontColor',labelCol);

            app.ProfileTolSpinner = uispinner(gridTol, ...
                'Limits',[HotWireSTEPApp_v6_2.MinProfileTolerance, HotWireSTEPApp_v6_2.MaxProfileTolerance], ...
                'Value',HotWireSTEPApp_v6_2.DefaultProfileTolerance, ...
                'Step',0.01, ... % <-- upgrade requested
                'ValueDisplayFormat','%.2f', ...
                'ValueChangedFcn',@(src,~)app.onProfileToleranceChanged(src));
            app.ProfileTolerance = HotWireSTEPApp_v6_2.DefaultProfileTolerance;

            app.ProfilePointCountLabel = uilabel(gridTol, ...
                'Text','Number of Points (L/R): -- / --', ...
                'HorizontalAlignment','right', 'FontColor',labelCol, 'FontAngle','italic');
            app.ProfilePointCountLabel.Layout.Row = 2;
            app.ProfilePointCountLabel.Layout.Column = [1 2];

            % -- Reset Buttons --
            app.BtnResetProfileTol = uibutton(app.profilesLeft, 'Text','Reset Tolerance', 'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~)app.onResetProfileTolerance());
            app.BtnResetProfileTol.Layout.Row = 2;

            app.BtnResetProfilesView = uibutton(app.profilesLeft, 'Text','Reset Profiles View', 'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~)app.resetProfilesView());
            app.BtnResetProfilesView.Layout.Row = 3;

            % -- Kerf --
            pnlKerf = uipanel(app.profilesLeft, 'Title','Kerf Compensation', ...
                'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlKerf.Layout.Row = 4;

            gridKerf = uigridlayout(pnlKerf,[3 2]);
            gridKerf.ColumnWidth = {'1x',90};
            gridKerf.RowHeight = {'fit','fit','fit'};
            gridKerf.Padding = [10 5 10 5];

            lblKerf = uilabel(gridKerf, 'Text','Kerf [mm]:', ...
                'HorizontalAlignment','right', 'FontWeight','bold', 'FontColor',labelCol);
            lblKerf.Layout.Row = 1; lblKerf.Layout.Column = 1;

            app.KerfSpinner = uispinner(gridKerf, ...
                'Limits',[HotWireSTEPApp_v6_2.MinKerf, HotWireSTEPApp_v6_2.MaxKerf], ...
                'Value',HotWireSTEPApp_v6_2.DefaultKerf, ...
                'Step',0.1, ...
                'ValueDisplayFormat','%.2f', ...
                'ValueChangedFcn',@(src,~)app.onKerfChanged(src));
            app.KerfSpinner.Tooltip = 'Compensation for width of cut. Offset distance = Kerf/2';
            app.KerfSpinner.Layout.Row = 1;
            app.KerfSpinner.Layout.Column = 2;
            app.KerfValue = HotWireSTEPApp_v6_2.DefaultKerf;

            app.KerfPointCountLabel = uilabel(gridKerf, ...
                'Text','Number of Points (L/R): -- / --', ...
                'HorizontalAlignment','right', 'FontColor',labelCol, 'FontAngle','italic');
            app.KerfPointCountLabel.Layout.Row = 2;
            app.KerfPointCountLabel.Layout.Column = [1 2];

            app.BtnApplyKerf = uibutton(gridKerf, 'Text','Apply Kerf Offset', 'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~)app.onApplyKerf());
            app.BtnApplyKerf.Tooltip = 'After first press the offset spinner will auto-update the offset profile';
            app.BtnApplyKerf.Layout.Row = 3;
            app.BtnApplyKerf.Layout.Column = [1 2];

            % 5. GUIDANCE (Model-tab style)
            lbl_P_Guide = uilabel(app.profilesLeft, 'Text','Guidance', 'FontWeight','bold', 'FontColor',labelCol);
            lbl_P_Guide.Layout.Row = 5;

            guideTextP = {
                '1. Set the tolerance so the extracted profiles (red/green) conform to the sliced mesh profiles.'
                '   - Smaller tolerance improves accuracy, but increases the number of points and the size of the G-code.'
                ''
                '2. Set and apply Kerf Offset'
                ''
                '3. Check both profiles look correct, then click Continue.'
                ''
                'TIP: Kerf is the width of cut made by a tool or machine.'
                '- For a hot wire cutter, kerf depends mainly on wire power and feed rate (and can vary with material).'
                '- An offset must be applied to the profile to compensate.'
                'Note: the offset distance applied is half the kerf value (Kerf/2).'                
                };

            app.TxtProfileGuide = uitextarea(app.profilesLeft, 'Editable','off', 'Value', guideTextP, ...
                'BackgroundColor', sideBg, 'FontColor', labelCol);
            app.TxtProfileGuide.Layout.Row = 6;

            % 6. STATUS (Model-tab style)
            lbl_P_Stat = uilabel(app.profilesLeft, 'Text','Status', 'FontWeight','bold', 'FontColor',labelCol);
            lbl_P_Stat.Layout.Row = 7;

            app.TxtProfileStatus = uitextarea(app.profilesLeft, 'Editable','off', 'Value', {''}, ...
                'BackgroundColor', [0.2 0.2 0.2], 'FontColor', [1 0.8 0]);
            app.TxtProfileStatus.Layout.Row = 8;

            % -- Continue (bottom, like Model tab buttons section)
            app.BtnProfilesContinue = uibutton(app.profilesLeft, 'Text','Continue →', 'FontWeight','bold', ...
                'Enable', 'off', 'BackgroundColor',[0.3 0.3 0.3], ...
                'ButtonPushedFcn',@(~,~)app.onContinueFromProfiles());
            app.BtnProfilesContinue.Layout.Row = 9;

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
            % Define Tooltips for each axis
            sizeTooltips = { ...
                'Length of stock along Machine X (Span)', ...
                'Depth of stock along Machine Y', ...
                'Height of stock along Machine Z'};

            app.BilletSizeEdits = gobjects(1,3);
            app.BilletSizeMinusBtns = gobjects(1,3);
            app.BilletSizePlusBtns = gobjects(1,3);
            app.BilletModelDimLabels = gobjects(1,3);

            for i = 1:3
                r = i + 1;
                % Axis Label
                lAx = uilabel(gridBSize, 'Text', axisLabels{i}, 'FontWeight','bold', 'HorizontalAlignment','center', 'FontColor',labelCol);
                lAx.Layout.Row = r;

                % Minus Button
                app.BilletSizeMinusBtns(i) = uibutton(gridBSize, 'Text','-', 'FontWeight','bold', ...
                    'ButtonPushedFcn', @(~,~)app.onBilletSizeStep(i,-1));
                app.BilletSizeMinusBtns(i).Layout.Row = r;
                app.BilletSizeMinusBtns(i).Layout.Column = 3;

                % Edit Field (Numeric) - Added Tooltip here
                app.BilletSizeEdits(i) = uieditfield(gridBSize,'numeric', ...
                    'HorizontalAlignment','center', ...
                    'ValueDisplayFormat','%.2f', ...
                    'BackgroundColor',[0.7 0.7 0.8], ...
                    'FontColor', [0 0 0], ...
                    'Tooltip', sizeTooltips{i}, ... % <--- Added Tooltip
                    'ValueChangedFcn', @(src,~)app.onBilletSizeEdited(i,src));
                app.BilletSizeEdits(i).Layout.Row = r;
                app.BilletSizeEdits(i).Layout.Column = 4;

                % Plus Button
                app.BilletSizePlusBtns(i) = uibutton(gridBSize, 'Text','+', 'FontWeight','bold', ...
                    'ButtonPushedFcn', @(~,~)app.onBilletSizeStep(i,+1));
                app.BilletSizePlusBtns(i).Layout.Row = r;
                app.BilletSizePlusBtns(i).Layout.Column = 5;

                % Dimension Label
                app.BilletModelDimLabels(i) = uilabel(gridBSize, 'Text','(---)', 'HorizontalAlignment','center', ...
                    'BackgroundColor', t.readoutBg, 'FontColor', t.readoutTxt);
                app.BilletModelDimLabels(i).Layout.Row = r;
                app.BilletModelDimLabels(i).Layout.Column = 6;
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
            mTooltips   = { ...
                ["Distance from the left side of bed > left side of billet", "(Between left and right towers)"], ...
                ["Distance from the front 'home' position > front of billet", "(Depth)","must be > 50mm"], ...
                ["Distance from bed surface > bottom of billet", "(Z-Axis Height)"] ...
                };
            app.MachinePosSpinners = gobjects(1,3);
            for i=1:3
                lblMAxRow = uilabel(gridMPlace, 'Text',mAxisLabels{i}, 'FontColor',labelCol);
                lblMAxRow.Layout.Row=i+1;
                app.MachinePosSpinners(i) = uispinner(gridMPlace, 'Limits',[-500 2000], 'Value',app.MachineBilletPos(i), 'ValueDisplayFormat','%.2f', 'Step',1.0,'Tooltip', mTooltips{i}, 'ValueChangedFcn',@(src,~)app.onMachinePosEdited(i,src));
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

            % 1. View Controls
            pnlSView = uipanel(app.SimLeftPanel, 'Title','View', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlSView.Layout.Row = 1;

            gridSView = uigridlayout(pnlSView, [1 2]);
            gridSView.Padding=[5 5 5 5];
            gridSView.BackgroundColor=panelBg;

            btnSimViewMach = uibutton(gridSView, 'Text','Machine View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetSimViewMachine());
            btnSimViewBill = uibutton(gridSView, 'Text','Billet View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetSimViewBillet());

            % 2. Playback Controls
            pnlSPlay = uipanel(app.SimLeftPanel, 'Title','Playback', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlSPlay.Layout.Row = 2;

            gridSPlay = uigridlayout(pnlSPlay, [2 3]);
            gridSPlay.ColumnWidth={'1x','1x','1x'};
            gridSPlay.RowHeight={'fit','fit'};
            gridSPlay.Padding=[5 5 5 5];
            gridSPlay.BackgroundColor=panelBg;

            % Row 1: Buttons
            app.SimPlayBtn = uibutton(gridSPlay, 'Text','Play', 'FontWeight','bold', 'BackgroundColor',t.accentBg, 'FontColor',t.editTxt, 'ButtonPushedFcn',@(~,~)app.onSimPlay());

            btnSimPause = uibutton(gridSPlay, 'Text','Pause', 'FontWeight','bold', 'BackgroundColor',panelBg, 'FontColor',labelCol, 'ButtonPushedFcn',@(~,~)app.onSimPause());

            app.SimStopBtn = uibutton(gridSPlay, 'Text','Reset', 'FontWeight','bold', 'BackgroundColor',panelBg, 'FontColor',labelCol, 'ButtonPushedFcn',@(~,~)app.onSimStop());

            % Row 2: Slider + Spinner
            app.SimSlider = uislider(gridSPlay, 'Limits',[1 100], 'Value',1, 'ValueChangedFcn',@(src,~)app.onSimSliderChanging(src));
            app.SimSlider.Layout.Row = 2;
            app.SimSlider.Layout.Column = [1 2];

            app.SimIndexSpinner = uispinner(gridSPlay, 'Limits',[1 100], 'Value',1, 'RoundFractionalValues','on', 'ValueChangedFcn',@(src,~)app.onSimIndexSpinnerChanged(src));
            app.SimIndexSpinner.Layout.Row = 2;
            app.SimIndexSpinner.Layout.Column = 3;

            % 3. Settings
            pnlSSet = uipanel(app.SimLeftPanel, 'Title','Settings', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlSSet.Layout.Row = 3;

            gridSSet = uigridlayout(pnlSSet, [1 2]);
            gridSSet.ColumnWidth={'fit','1x'};
            gridSSet.Padding=[5 5 5 5];
            gridSSet.BackgroundColor=panelBg;

            lblSimSpeed = uilabel(gridSSet, 'Text','Speed (x):', 'FontColor',labelCol, 'HorizontalAlignment','right');

            app.SimSpeedSpinner = uispinner(gridSSet, 'Limits',[0.1 10], 'Value',1.0, 'Step',0.1);

            % 4. Live Coordinates
            pnlSCoord = uipanel(app.SimLeftPanel, 'Title','Live Coordinates', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlSCoord.Layout.Row = 4;

            gridSCoord = uigridlayout(pnlSCoord, [3 5]);
            gridSCoord.ColumnWidth = {'fit', 60, '1x', 'fit', 60};
            gridSCoord.RowHeight = {'fit','fit','fit'};
            gridSCoord.Padding = [5 5 5 5];
            gridSCoord.BackgroundColor = panelBg;

            lblSimHeadL = uilabel(gridSCoord, 'Text','Left Tower', 'FontWeight','bold', 'FontColor',labelCol, 'HorizontalAlignment','center');
            lblSimHeadL.Layout.Column = [1 2];

            lblSimHeadR = uilabel(gridSCoord, 'Text','Right Tower', 'FontWeight','bold', 'FontColor',labelCol, 'HorizontalAlignment','center');
            lblSimHeadR.Layout.Column = [4 5];

            % Row 2: X/Z
            lblSimX = uilabel(gridSCoord, 'Text','X:', 'FontWeight','bold', 'FontColor',t.accentBg, 'HorizontalAlignment','right');
            lblSimX.Layout.Row=2;

            app.LblReadoutX = uilabel(gridSCoord, 'Text','0.00', 'FontName','Monospaced', 'FontColor',labelCol);
            app.LblReadoutX.Layout.Row=2; app.LblReadoutX.Layout.Column=2;

            lblSimZ = uilabel(gridSCoord, 'Text','Z:', 'FontWeight','bold', 'FontColor',t.accentBg, 'HorizontalAlignment','right');
            lblSimZ.Layout.Row=2; lblSimZ.Layout.Column=4;

            app.LblReadoutZ = uilabel(gridSCoord, 'Text','0.00', 'FontName','Monospaced', 'FontColor',labelCol);
            app.LblReadoutZ.Layout.Row=2; app.LblReadoutZ.Layout.Column=5;

            % Row 3: Y/A
            lblSimY = uilabel(gridSCoord, 'Text','Y:', 'FontWeight','bold', 'FontColor',t.accentBg, 'HorizontalAlignment','right');
            lblSimY.Layout.Row=3;

            app.LblReadoutY = uilabel(gridSCoord, 'Text','0.00', 'FontName','Monospaced', 'FontColor',labelCol);
            app.LblReadoutY.Layout.Row=3; app.LblReadoutY.Layout.Column=2;

            lblSimA = uilabel(gridSCoord, 'Text','A:', 'FontWeight','bold', 'FontColor',t.accentBg, 'HorizontalAlignment','right');
            lblSimA.Layout.Row=3; lblSimA.Layout.Column=4;

            app.LblReadoutA = uilabel(gridSCoord, 'Text','0.00', 'FontName','Monospaced', 'FontColor',labelCol);
            app.LblReadoutA.Layout.Row=3; app.LblReadoutA.Layout.Column=5;

            % 5. Spacer & Continue
            lblSimSpacer = uilabel(app.SimLeftPanel, 'Text', '');
            lblSimSpacer.Layout.Row = 5;

            app.BtnSimContinue = uibutton(app.SimLeftPanel, 'Text','Continue', 'FontWeight','bold', 'BackgroundColor',[0.1 0.6 0.1], 'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~)app.onContinue());
            app.BtnSimContinue.Layout.Row = 6;

            % --- Right Panel: 3D Sim Plot ---
            app.AxSim = uiaxes(app.GLSimulation);
            app.AxSim.Layout.Column = 2;
            app.AxSim.BackgroundColor = [0.05 0.05 0.05];
            xlabel(app.AxSim,'X'); ylabel(app.AxSim,'Y'); zlabel(app.AxSim,'Z');
            grid(app.AxSim,'on'); view(app.AxSim, 3); axis(app.AxSim, 'equal');

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
        function [isValid, statusColor, msg] = checkMachineState(app)
            % Centralized Logic for Machine & Bed Safety

            % 1. Defaults (Green)
            isValid = true;
            statusColor = app.getTheme().sideBg;
            msg = "Machine configuration valid.";

            % 2. Geometry
            bPos  = app.MachineBilletPos;
            bSize = app.BilletSize;
            bMin = bPos; bMax = bPos + bSize;

            bedMin = app.MachineBedPos;
            bedMax = app.MachineBedPos + app.MachineBedSize;

            % Limits (Construct ranges from Scalars)
            limX = [0, app.MachineSpanX];
            limY = [0, app.MachineLimitY]; % Scalar -> Range
            limZ = [0, app.MachineLimitZ];

            % 3. Critical Checks (Red)
            crit = strings(0);
            if bMin(1) < limX(1) || bMax(1) > limX(2), crit(end+1)="Billet hits Towers (X)."; end
            if bMin(2) < limY(1) || bMax(2) > limY(2), crit(end+1)="Billet exceeds Y-Travel."; end
            if bMin(3) < limZ(1) || bMax(3) > limZ(2), crit(end+1)="Billet exceeds Z-Travel."; end

            % Check Bed Support
            if bMin(1) < bedMin(1) || bMax(1) > bedMax(1), crit(end+1)="Billet overhangs Bed (X)."; end
            if bMin(2) < bedMin(2) || bMax(2) > bedMax(2), crit(end+1)="Billet overhangs Bed (Y)."; end

            if ~isempty(crit)
                isValid = false; statusColor = [0.3 0.1 0.1]; msg = "CRITICAL: " + crit(1); return;
            end

            % 4. Warning Checks (Amber)
            warn = strings(0);
            buf  = app.SafetyBuffer_BedEdge;

            if (bMin(1)-bedMin(1) < buf) || (bedMax(1)-bMax(1) < buf) || ...
                    (bMin(2)-bedMin(2) < buf) || (bedMax(2)-bMax(2) < buf)
                warn(end+1) = sprintf("Billet close (<%.0fmm) to bed edge.", buf);
            end

            if ~isempty(warn)
                isValid = true; statusColor = [0.3 0.25 0.1]; msg = "Warning: " + warn(end);
            end
        end

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

            % Clear old data
            app.clearProfiles(); app.clearProfiles2D();
            app.SelectedStartIdxL = 1; app.SelectedStartIdxR = 1;

            % Setup Geometry
            V = app.ModelPatch.Vertices; F = app.ModelPatch.Faces;
            spanX = max(V(:,1)) - min(V(:,1)); epsX = 1e-6 * max(spanX, 1);

            xLeft  = app.ModelXMin + app.NumLeftOffset.Value;
            xRight = app.ModelXMin + app.NumRightOffset.Value;

            % --- 1. EXTRACT RAW LOOPS ---
            % Left is always extracted
            [xsL, ysL, zsL] = HotWireSTEPApp_v6_helpers.sliceMeshAtX(V, F, xLeft + epsX);
            if ~isempty(ysL) && any(~isnan(ysL)), app.LeftProfileRawYZ = [ysL(:), zsL(:)]; end
            [yLoopL, zLoopL] = HotWireSTEPApp_v6_helpers.buildMainProfileLoop(xsL, ysL, zsL);

            % Right: Extract if Taper, otherwise Copy Left
            yLoopR = []; zLoopR = [];
            if isTaper
                [xsR, ysR, zsR] = HotWireSTEPApp_v6_helpers.sliceMeshAtX(V, F, xRight - epsX);
                if ~isempty(ysR) && any(~isnan(ysR)), app.RightProfileRawYZ = [ysR(:), zsR(:)]; end
                [yLoopR, zLoopR] = HotWireSTEPApp_v6_helpers.buildMainProfileLoop(xsR, ysR, zsR);
            else
                % Straight Mode: Right = Left
                yLoopR = yLoopL; zLoopR = zLoopL;
                app.RightProfileRawYZ = app.LeftProfileRawYZ;
            end

            % --- 2. RESAMPLING (The Fix) ---
            % Use the Smart RDP Sync for BOTH Straight and Tapered modes.
            % This ensures squares get reduced to corners (~5 pts) instead of 1000 pts.
            if ~isempty(yLoopL) && ~isempty(yLoopR)
                [yLoopL, zLoopL, yLoopR, zLoopR] = HotWireSTEPApp_v6_helpers.resampleProfilesSynced(...
                    yLoopL, zLoopL, yLoopR, zLoopR, app.ProfileTolerance);
            end

            % --- 3. DATA STORAGE & PLOTTING ---
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

            % Update Status
            if ~isempty(yLoopL)
                app.TxtProfileStatus.Value = {
                    sprintf('Profiles extracted.'),
                    sprintf('Left: %d pts', numel(yLoopL)),
                    sprintf('Right: %d pts', numel(yLoopR)),
                    'Ready to apply Kerf.'
                    };
                app.TxtProfileStatus.FontColor = [1 1 1]; % White
            else
                app.TxtProfileStatus.Value = {'Extraction failed.', 'Check model position.'};
                app.TxtProfileStatus.FontColor = [1 0.4 0.4]; % Red
            end

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

            % Axis limits
            yAll = [yL(:); yR(:)]; zAll = [zL(:); zR(:)];
            if isempty(yAll) || isempty(zAll), return; end

            yMin = min(yAll); yMax = max(yAll);
            zMin = min(zAll); zMax = max(zAll);
            dy = max(yMax - yMin, 1); dz = max(zMax - zMin, 1);
            padY = 0.1 * dy; padZ = 0.1 * dz;
            yLim = [yMin - padY, yMax + padY]; zLim = [zMin - padZ, zMax + padZ];

            t = app.getTheme();
            app.clearProfiles2D();

            % Initialize Counters for Label
            nLk = 0; nRk = 0;

            % ----- LEFT AXIS -----
            hold(app.AxLeftProfile,'on');
            if ~isempty(app.LeftProfileRawYZ)
                rawL = app.LeftProfileRawYZ;
                app.LeftProfile2DMeshLine = plot(app.AxLeftProfile, rawL(:,1), rawL(:,2), ...
                    'Color', t.rawMeshCol, 'LineStyle',':', 'LineWidth',2.5);
            end
            if ~isempty(yL)
                app.LeftProfile2DLine = plot(app.AxLeftProfile, yL, zL, 'Color', t.planeRed, 'LineWidth',0.75);
            end

            % Left Kerf Calc & Plot
            if app.KerfEnabled && ~isempty(yL) && app.KerfValue > 0
                % Pass Tolerance
                [yKerfL, zKerfL] = HotWireSTEPApp_v6_helpers.offsetProfileLoop(yL, zL, app.KerfValue, app.ProfileTolerance);
                if ~isempty(yKerfL), nLk = numel(yKerfL); end

                app.LeftKerf2DLine = plot(app.AxLeftProfile, yKerfL, zKerfL, 'Color', t.wireKerf, 'LineWidth',0.75);
            end
            hold(app.AxLeftProfile,'off');

            % ----- RIGHT AXIS -----
            hold(app.AxRightProfile,'on');
            if ~isempty(app.RightProfileRawYZ)
                rawR = app.RightProfileRawYZ;
                app.RightProfile2DMeshLine = plot(app.AxRightProfile, rawR(:,1), rawR(:,2), ...
                    'Color', t.rawMeshCol, 'LineStyle',':', 'LineWidth',2.5);
            end
            if ~isempty(yR)
                app.RightProfile2DLine = plot(app.AxRightProfile, yR, zR, 'Color', t.planeGreen, 'LineWidth',0.75);
            end

            % Right Kerf Calc & Plot
            if app.KerfEnabled && ~isempty(yR) && app.KerfValue > 0
                % Pass Tolerance
                [yKerfR, zKerfR] = HotWireSTEPApp_v6_helpers.offsetProfileLoop(yR, zR, app.KerfValue, app.ProfileTolerance);
                if ~isempty(yKerfR), nRk = numel(yKerfR); end

                app.RightKerf2DLine = plot(app.AxRightProfile, yKerfR, zKerfR, 'Color', t.wireKerf, 'LineWidth',0.75);
            end
            hold(app.AxRightProfile,'off');

            % ----- UPDATE LABEL (Dynamic) -----
            if app.KerfEnabled && ~isempty(app.KerfPointCountLabel) && all(isgraphics(app.KerfPointCountLabel))
                app.KerfPointCountLabel.Text = sprintf('Number of Points (L/R): %d / %d', nLk, nRk);
            end

            % ----- LEGENDS & VIEW -----
            % Left Legend
            hL = gobjects(0); txtL = {};
            if isgraphics(app.LeftProfile2DMeshLine), hL(end+1)=app.LeftProfile2DMeshLine; txtL{end+1}='Model mesh slice'; end
            if isgraphics(app.LeftProfile2DLine), hL(end+1)=app.LeftProfile2DLine; txtL{end+1}='Extracted profile'; end
            if isgraphics(app.LeftKerf2DLine), hL(end+1)=app.LeftKerf2DLine; txtL{end+1}='Kerf path'; end
            if ~isempty(hL), l=legend(app.AxLeftProfile, hL, txtL, 'Location','northeast'); l.Box='off'; end

            % Right Legend
            hR = gobjects(0); txtR = {};
            if isgraphics(app.RightProfile2DMeshLine), hR(end+1)=app.RightProfile2DMeshLine; txtR{end+1}='Model mesh slice'; end
            if isgraphics(app.RightProfile2DLine), hR(end+1)=app.RightProfile2DLine; txtR{end+1}='Extracted profile'; end
            if isgraphics(app.RightKerf2DLine), hR(end+1)=app.RightKerf2DLine; txtR{end+1}='Kerf path'; end
            if ~isempty(hR), l=legend(app.AxRightProfile, hR, txtR, 'Location','northeast'); l.Box='off'; end

            if ~app.ProfileAxesLocked
                xlim(app.AxLeftProfile, yLim); ylim(app.AxLeftProfile, zLim);
                xlim(app.AxRightProfile, yLim); ylim(app.AxRightProfile, zLim);
            end
            daspect(app.AxLeftProfile, [1 1 1]); daspect(app.AxRightProfile,[1 1 1]);

            title(app.AxLeftProfile,  sprintf('Left Profile  (X offset = %.2f mm)', app.NumLeftOffset.Value));
            title(app.AxRightProfile, sprintf('Right Profile (X offset = %.2f mm)', app.NumRightOffset.Value));
            grid(app.AxLeftProfile,'on'); grid(app.AxRightProfile,'on');
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
            targetTab = evt.NewValue;
            oldTab    = evt.OldValue;

            % --- GUARD 1: Model Required ---
            hasModel = ~isempty(app.ModelPatch) && isgraphics(app.ModelPatch);
            if targetTab ~= app.TabModel && ~hasModel
                uialert(app.UIFigure, 'Please load a 3D Model first.', 'Step 1 Missing', 'Icon','warning');
                app.TabGroup.SelectedTab = app.TabModel; return;
            end

            % --- GUARD 2: Profiles Required ---
            hasProfiles = ~isempty(app.LeftProfilePoints) || ~isempty(app.RightProfilePoints);
            if targetTab ~= app.TabModel && targetTab ~= app.TabProfiles && ~hasProfiles
                uialert(app.UIFigure, 'Please generate Cutting Profiles first.', 'Step 2 Missing', 'Icon','warning');
                app.TabGroup.SelectedTab = app.TabProfiles; return;
            end

            % --- GUARD 3: Billet Validity ---
            if (oldTab == app.TabBillet) || (targetTab == app.TabMachine || targetTab == app.TabCutting || targetTab == app.TabSimulation)
                isValidBillet = app.syncBilletUI();
                if ~isValidBillet
                    uialert(app.UIFigure, 'Billet configuration is invalid (Model outside stock).', 'Billet Error', 'Icon','error');
                    app.TabGroup.SelectedTab = app.TabBillet; return;
                end
            end

            % --- GUARD 4: Machine Validity ---
            if (oldTab == app.TabMachine) || (targetTab == app.TabCutting || targetTab == app.TabSimulation)
                [isValidMach, ~, msg] = app.checkMachineState();
                if ~isValidMach
                    uialert(app.UIFigure, msg, 'Machine Error', 'Icon','error');
                    app.TabGroup.SelectedTab = app.TabMachine; return;
                end
            end

            % --- EXECUTE TRANSITION ---
            app.resetInteractionState();

            if targetTab == app.TabBillet
                app.syncBilletUI();
                app.refreshBilletPlots();

            elseif targetTab == app.TabMachine
                % Validate state on entry
                [isValid, col, txt] = app.checkMachineState();
                app.MachineLeftPanel.BackgroundColor = col;
                app.MachineMessageLabel.Text = txt;
                if isValid, app.MachineMessageLabel.FontColor=[1 1 1]; else, app.MachineMessageLabel.FontColor=[1 0.4 0.4]; end

                app.refreshMachinePlot();

            elseif targetTab == app.TabCutting
                if isempty(app.EntryPointL)
                    app.onAutoStart();
                    app.onAutoEntry();
                end
                app.updateCuttingPlots();
                app.onResetCuttingViewBillet();

            elseif targetTab == app.TabSimulation
                app.applyTheme();
                app.generateSimulationData();

            elseif targetTab == app.TabPostProcess
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
            % Kerf value changed.
            % If kerf has already been applied once, your app auto-updates the kerf offset paths,
            % so the status should reflect that (instead of implying a manual re-apply is needed).

            val = src.Value;

            % Basic validation / clamp (keep it gentle; spinner limits should enforce anyway)
            if ~isfinite(val)
                src.Value = app.KerfValue;
                return;
            end

            app.KerfValue = val;

            % If the app is already in a state where profiles exist, refresh the profiles/kerf paths.
            % (This mirrors your "kerf change auto-applies" behaviour.)
            try
                if isprop(app,'AppState') && app.AppState >= 1
                    % If you have a standard refresh function, call it here instead.
                    % Many builds recompute profiles through updatePlanes()/computeProfiles() chain.
                    if ismethod(app,'updatePlanes')
                        app.ProfileAxesLocked = true;
                        app.updatePlanes();
                        app.ProfileAxesLocked = false;
                    elseif ismethod(app,'computeProfiles')
                        app.ProfileAxesLocked = true;
                        app.computeProfiles();
                        app.ProfileAxesLocked = false;
                    end
                end
            catch
                % Don't hard-fail on UI refresh; status message still updates below.
            end

            % --- Status messaging ---
            % We don't assume the exact status field name; try the common ones.
            statusHandle = [];
            if isprop(app,'TxtProfileStatus'), statusHandle = app.TxtProfileStatus; end
            if isempty(statusHandle) && isprop(app,'ProfileStatusTextArea'), statusHandle = app.ProfileStatusTextArea; end

            if ~isempty(statusHandle) && isvalid(statusHandle)
                if isprop(app,'KerfEnabled') && app.KerfEnabled
                    statusHandle.Value = {
                        sprintf('Kerf updated: %.2f mm', app.KerfValue)
                        sprintf('Offset distance: %.3f mm (Kerf/2)', app.KerfValue/2)
                        'Kerf-compensated profiles updated automatically.'
                        'Continue when ready.'
                        };
                else
                    statusHandle.Value = {
                        sprintf('Kerf set: %.2f mm', app.KerfValue)
                        sprintf('Offset distance (when applied): %.3f mm (Kerf/2)', app.KerfValue/2)
                        'Click "Apply Kerf Offset" to generate compensated profiles.'
                        };
                end
            end
        end

        function onApplyKerf(app)
            % Enable kerf drawing and (re)draw kerf paths based on the
            % currently extracted profiles, WITHOUT changing zoom/pan.

            if isempty(app.LeftProfilePoints) && isempty(app.RightProfilePoints)
                return;
            end

            app.KerfEnabled = true;

            % --- ACTIVATE CONTINUE BUTTON ---
            app.BtnProfilesContinue.Enable = 'on';
            app.BtnProfilesContinue.BackgroundColor = [0.1 0.6 0.1];
            app.BtnProfilesContinue.FontColor       = [1 1 1];

            % --- 1. EXTRACT DATA FIRST ---
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

            % --- 2. CALCULATE COUNTS (Updated with Tolerance) ---
            nL_k = 0; nR_k = 0;

            if ~isempty(yL) && app.KerfValue > 0
                % Pass app.ProfileTolerance to optimize point count
                [yk, ~] = HotWireSTEPApp_v6_helpers.offsetProfileLoop(yL, zL, app.KerfValue, app.ProfileTolerance);
                if ~isempty(yk), nL_k = numel(yk); end
            end

            if ~isempty(yR) && app.KerfValue > 0
                % Pass app.ProfileTolerance to optimize point count
                [ykR, ~] = HotWireSTEPApp_v6_helpers.offsetProfileLoop(yR, zR, app.KerfValue, app.ProfileTolerance);
                if ~isempty(ykR), nR_k = numel(ykR); end
            end

            % --- 3. UPDATE LABEL (New Format) ---
            if isgraphics(app.KerfPointCountLabel)
                app.KerfPointCountLabel.Text = sprintf('Number of Points (L/R): %d / %d', nL_k, nR_k);
            end

            % --- 4. REFRESH PLOT ---
            app.ProfileAxesLocked = true;
            app.updateProfiles2D(yL, zL, yR, zR, xLeft, xRight);
            app.ProfileAxesLocked = false;

            % Update Status
            if app.KerfEnabled
                app.TxtProfileStatus.Value = {
                    sprintf('Kerf Applied (%.2f mm)', app.KerfValue),
                    sprintf('Offset: %.3f mm', app.KerfValue/2),
                    'Profiles Valid.',
                    'Click Continue.'
                    };
                app.TxtProfileStatus.FontColor = [0.4 1 0.4]; % Green
            end
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

            % Force SCALAR extraction
            mins = min(V, [], 1);
            maxs = max(V, [], 1);

            app.ModelXMin = mins(1); app.ModelXMax = maxs(1);
            app.ModelYMin = mins(2); app.ModelYMax = maxs(2);
            app.ModelZMin = mins(3); app.ModelZMax = maxs(3);

            % Calculate Model Width
            modelWidth = app.ModelXMax - app.ModelXMin;
            if modelWidth < 1, modelWidth = 1; end % Safety

            % Update Limits (0 to Width)
            % User sees 0 as Left Face, Width as Right Face
            app.NumLeftOffset.Limits  = [0, modelWidth];
            app.NumRightOffset.Limits = [0, modelWidth];

            if nargin < 2, resetOffsets = true; end

            if resetOffsets
                % Reset to Ends
                app.NumLeftOffset.Value  = 0;
                app.NumRightOffset.Value = modelWidth;

                % Update Status
                if ~isempty(app.TxtModelStatus)
                    app.TxtModelStatus.Value = {'Model loaded.', sprintf('Size: %.1f x %.1f x %.1f mm', ...
                        modelWidth, app.ModelYMax-app.ModelYMin, app.ModelZMax-app.ModelZMin)};
                    app.TxtModelStatus.FontColor = [0.4 1 0.4]; % Green
                end
            else
                % Clamp existing values if they are now out of bounds (e.g. after rotation)
                if app.NumLeftOffset.Value > modelWidth, app.NumLeftOffset.Value = modelWidth; end
                if app.NumRightOffset.Value > modelWidth, app.NumRightOffset.Value = modelWidth; end

                % Check if valid
                if ~isempty(app.TxtModelStatus)
                    app.TxtModelStatus.Value = {'Model re-oriented.', 'Check plane positions.'};
                    app.TxtModelStatus.FontColor = [1 0.8 0.4]; % Amber
                end
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

        function isValid = syncBilletUI(app)
            % Returns: true (Valid), false (Model outside stock)

            if isempty(app.BilletSizeEdits) || isempty(app.ModelPatch)
                isValid = false; return;
            end

            % 1. Local CAD Properties
            V  = app.ModelPatch.Vertices;
            xL = app.ModelXMin + app.NumLeftOffset.Value;
            xR = app.ModelXMin + app.NumRightOffset.Value;

            mMin = [min(xL,xR), min(V(:,2)), min(V(:,3))];
            mMax = [max(xL,xR), max(V(:,2)), max(V(:,3))];
            mDim = mMax - mMin;

            % 2. Machining Properties
            workMin = app.BilletShift + mMin;
            workMax = workMin + mDim;
            bSize   = app.BilletSize;

            % 3. Sync UI Fields
            for i = 1:3
                app.BilletSizeEdits(i).Value = bSize(i);
                app.BilletModelDimLabels(i).Text = sprintf('%.2f mm', mDim(i));
                app.BilletNegOffsetEdits(i).Value    = workMin(i);
                app.BilletPosOffsetEdits(i).Value    = bSize(i) - workMax(i);
                app.BilletCenterOffsetEdits(i).Value = app.BilletShift(i);
            end

            % 4. Validation Logic (Using Constants)
            tol = app.ModelContainmentTol;
            buf = app.ModelEdgeWarningBuffer;

            % RED Check: Is Model Outside Stock?
            isOutside  = any(workMin < -tol) || any(workMax > bSize + tol);

            % AMBER Check: Is Model Too Close to Edge? (Y and Z only)
            % We usually don't care about X buffer as much because wires pass through X faces.
            isTooClose = (workMin(2) < buf) || (workMax(2) > bSize(2) - buf) || ...
                (workMin(3) < buf) || (workMax(3) > bSize(3) - buf);

            % Theme Colors
            if app.UIFigure.Color(1) < 0.5
                panelBg = [0.16 0.16 0.16]; successGreen = [0.4 1 0.4];
            else
                panelBg = [0.94 0.94 0.94]; successGreen = [0 0.5 0];
            end

            if isOutside
                app.BilletLeftPanel.BackgroundColor = [0.4 0.16 0.16]; % Dark Red
                app.BilletMessageLabel.Text = 'CRITICAL: Model is outside stock!';
                app.BilletMessageLabel.FontColor = [1 0.4 0.4];
                app.BtnBilletContinue.Enable = 'off';
                isValid = false;
            elseif isTooClose
                app.BilletLeftPanel.BackgroundColor = [0.45 0.35 0.1]; % Amber
                app.BilletMessageLabel.Text = sprintf('Warning: Model is very close (<%.0fmm) to billet edges.', buf);
                app.BilletMessageLabel.FontColor = [1 0.8 0.4];
                app.BtnBilletContinue.Enable = 'on';
                isValid = true;
            else
                app.BilletLeftPanel.BackgroundColor = panelBg;
                app.BilletMessageLabel.Text = 'Billet configuration valid.';
                app.BilletMessageLabel.FontColor = successGreen;
                app.BtnBilletContinue.Enable = 'on';
                isValid = true;
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

            % 2. Direct-Set the Shift (Targets: Safety Buffers)
            % X: Just barely inside (0.001mm)
            % Y/Z: Exactly at the Warning Buffer (5.0mm) so it's safe but efficient

            app.BilletShift(1) = app.ModelXPlacementBuffer - planeMinX;
            app.BilletShift(2) = app.ModelEdgeWarningBuffer - localMins(2);
            app.BilletShift(3) = app.ModelEdgeWarningBuffer - localMins(3);

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
            % Handles edits to Billet Size fields with validation against Machine Limits.

            val = src.Value;

            % 1. Determine Limits based on Axis
            % Min is always 1mm to prevent zero/negative geometry
            minVal = 1.0;
            maxVal = 10000.0; % Default

            switch axisIdx
                case 1 % X Axis
                    maxVal = app.MachineBedSize(1); % 1000mm
                case 2 % Y Axis
                    maxVal = app.MachineBedSize(2); % 700mm
                case 3 % Z Axis
                    maxVal = app.MachineAxisZ(2);   % 500mm
            end

            % 2. Clamp Value
            if val < minVal
                val = minVal;
            elseif val > maxVal
                val = maxVal;
            end

            % 3. Update UI (Visual Feedback) and Data
            src.Value = val;
            app.BilletSize(axisIdx) = val;

            % 4. Refresh
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
            val = src.Value;
            if axisIdx == 1
                % Input is Bed-Relative -> Store Absolute
                app.MachineBilletPos(1) = app.MachineBedPos(1) + val;
            else
                % Input is Absolute
                app.MachineBilletPos(axisIdx) = val;
            end

            % Validation
            [isValid, col, txt] = app.checkMachineState();

            app.MachineLeftPanel.BackgroundColor = col;
            app.MachineMessageLabel.Text = txt;

            if isValid
                app.MachineMessageLabel.FontColor = [1 1 1];
                app.BtnMachineContinue.Enable = 'on';
            else
                app.MachineMessageLabel.FontColor = [1 0.4 0.4];
                app.BtnMachineContinue.Enable = 'off';
            end

            app.refreshMachinePlot();
        end

        function onResetMachineBilletPosition(app)
            if isempty(app.ModelPatch), return; end

            % 1. X-Center Logic
            mSpanX = app.MachineSpanX;
            app.MachineBilletPos(1) = (mSpanX - app.BilletSize(1)) / 2;

            % 2. Y-Default Logic (50mm from home)
            currentMinY = app.ModelYMin + app.BilletShift(2);
            targetY = app.MachineBedPos(2); % Front edge
            app.MachineBilletPos(2) = round((targetY - currentMinY) / 10) * 10;
            if app.MachineBilletPos(2) < targetY, app.MachineBilletPos(2) = targetY; end

            % 3. Z-Lift Logic
            app.MachineBilletPos(3) = 0;

            if ~isempty(app.LeftProfilePoints) && ~isempty(app.RightProfilePoints)
                xL_mach = app.MachineBilletPos(1) + app.NumLeftOffset.Value;
                xR_mach = app.MachineBilletPos(1) + app.NumRightOffset.Value;

                [yL, zL, yR, zR] = HotWireSTEPApp_v6_helpers.syncPointCounts(...
                    app.LeftProfilePoints(:,2), app.LeftProfilePoints(:,3), ...
                    app.RightProfilePoints(:,2), app.RightProfilePoints(:,3));

                [tL, tR] = HotWireSTEPApp_v6_helpers.projectToTowers(...
                    yL + app.MachineBilletPos(2) + app.BilletShift(2), zL, xL_mach, ...
                    yR + app.MachineBilletPos(2) + app.BilletShift(2), zR, xR_mach, ...
                    app.MachineSpanX);

                minProjZ = min([tL.z; tR.z]);
                if minProjZ < 5
                    app.MachineBilletPos(3) = abs(minProjZ) + 5;
                end
            end

            app.syncMachineUI();

            % Validation
            [isValid, col, txt] = app.checkMachineState();
            app.MachineLeftPanel.BackgroundColor = col;
            app.MachineMessageLabel.Text = txt;
            if isValid
                app.BtnMachineContinue.Enable = 'on';
                app.MachineMessageLabel.FontColor = [1 1 1];
            else
                app.BtnMachineContinue.Enable = 'off';
                app.MachineMessageLabel.FontColor = [1 0.4 0.4];
            end

            app.refreshMachinePlot();
        end

        function isValid = validateMachineConfig(app)
            % Checks if Billet fits within Machine Limits and updates UI colors

            % 1. Get Dimensions
            bSize = app.BilletSize;      % [W, D, H]
            bPos  = app.MachineBilletPos; % [X, Y, Z] absolute

            % Machine Limits
            limX = app.MachineSpanX;
            limY = app.MachineLimitY;
            limZ = app.MachineLimitZ;

            % 2. Calculate Boundaries
            % X: Billet must be > 0 and < Span
            % Note: We assume X=0 is Left Tower, X=Span is Right Tower
            minX = bPos(1);
            maxX = bPos(1) + bSize(1);

            minY = bPos(2);
            maxY = bPos(2) + bSize(2);

            minZ = bPos(3);
            maxZ = bPos(3) + bSize(3);

            % 3. Check Violations
            errors = strings(0);

            % X-Axis (Span)
            if minX < 0 || maxX > limX
                errors(end+1) = "Billet hits Towers (X-Axis).";
            end

            % Y-Axis (Travel)
            if minY < 0 || maxY > limY
                errors(end+1) = "Billet exceeds Y-Travel.";
            end

            % Z-Axis (Travel)
            if minZ < 0 || maxZ > limZ
                errors(end+1) = "Billet exceeds Z-Travel.";
            end

            % 4. Visual Feedback
            t = app.getTheme();

            if ~isempty(errors)
                % RED STATE: Critical Error
                app.MachineLeftPanel.BackgroundColor = [0.3 0.1 0.1]; % Dark Red
                app.MachineMessageLabel.Text = "CRITICAL: " + errors(1); % Show first error
                app.MachineMessageLabel.FontColor = [1 0.4 0.4];
                app.BtnMachineContinue.Enable = 'off';
                isValid = false;
            else
                % AMBER STATE: Check Proximity (Buffer < 10mm)
                buffer = 10;
                isClose = (minX < buffer) || (maxX > limX-buffer) || ...
                    (minY < buffer) || (maxY > limY-buffer) || ...
                    (maxZ > limZ-buffer); % Don't care about minZ < buffer usually (bed)

                if isClose
                    app.MachineLeftPanel.BackgroundColor = [0.3 0.25 0.1]; % Amber/Brown
                    app.MachineMessageLabel.Text = "Warning: Billet very close to limits.";
                    app.MachineMessageLabel.FontColor = [1 0.8 0.4];
                    app.BtnMachineContinue.Enable = 'on'; % Allow, but warn
                    isValid = true;
                else
                    % GREEN STATE: Good
                    app.MachineLeftPanel.BackgroundColor = t.sideBg;
                    app.MachineMessageLabel.Text = "Machine configuration valid.";
                    app.MachineMessageLabel.FontColor = [0.4 1 0.4];
                    app.BtnMachineContinue.Enable = 'on';
                    isValid = true;
                end
            end
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

                % --- FIX: Robust Start Triangle (Left) ---
                if numel(yL) > 1
                    idxNext = 2;
                    % Look ahead until we find a distinct point
                    while idxNext < numel(yL) && norm([yL(idxNext),zL(idxNext)] - [yL(1),zL(1)]) < 1e-4
                        idxNext = idxNext + 1;
                    end
                    app.drawRotatedMarker(app.AxCutLeft, [yL(1), zL(1)], [yL(idxNext), zL(idxNext)], 'start');
                    hStartL = drawDummyLegendMarker(app.AxCutLeft, '^', [0 1 0], 'none');
                end
            end

            hRapidR=gobjects(0); hLeadR=gobjects(0); hStartR=gobjects(0); hPathDummyR=gobjects(0); hEntryDotR=gobjects(0); hLoadR=gobjects(0);
            if ~isempty(yR)
                c=(1:numel(yR))';
                patch(app.AxCutRight, 'XData',[yR;NaN], 'YData',[zR;NaN], 'CData',[c;NaN], 'FaceColor','none', 'EdgeColor','interp', 'LineWidth',1.0, 'HitTest','off');
                hPathDummyR = drawDummyLegendMarker(app.AxCutRight, '-', [0 0.5 1], 'none', 1.0);

                [hRapidR, hLeadR, hEntryDotR, hLoadR] = app.drawTravelPath(app.AxCutRight, [yR(1), zR(1)], [yR(end), zR(end)], app.EntryPointR, app.EntryPoint2R);

                % --- FIX: Robust Start Triangle (Right) ---
                if numel(yR) > 1
                    idxNext = 2;
                    % Look ahead until we find a distinct point
                    while idxNext < numel(yR) && norm([yR(idxNext),zR(idxNext)] - [yR(1),zR(1)]) < 1e-4
                        idxNext = idxNext + 1;
                    end
                    app.drawRotatedMarker(app.AxCutRight, [yR(1), zR(1)], [yR(idxNext), zR(idxNext)], 'start');
                    hStartR = drawDummyLegendMarker(app.AxCutRight, '^', [0 1 0], 'none');
                end
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
            % Prepares profile data:
            % 1. Extracts raw coordinates
            % 2. Plots "Ghost" (Raw) profile
            % 3. Applies Kerf (if enabled)
            % 4. Applies Offsets (Machine Position)
            % 5. Applies Modifications (Start Point Shift, Direction Reverse)

            y=[]; z=[]; hGhost=gobjects(0);
            if isempty(pts), return; end

            % 1. Setup Raw Data (Model Coordinates)
            rawY = pts(:,2);
            rawZ = pts(:,3);

            % 2. Plot Ghost (Raw Profile in Machine Coords)
            % We plot this BEFORE applying Kerf or Reordering, so it represents
            % the "Reference Geometry" (the dotted line).
            if ~isempty(ax) && isgraphics(ax)
                gY = rawY + offY;
                gZ = rawZ + offZ;
                hGhost = plot(ax, gY, gZ, ':', 'Color', t.rawMeshCol, 'LineWidth', 0.5, 'HitTest','off');
            end

            % 3. Apply Kerf (if enabled)
            if doKerf
                % Note: We pass app.ProfileTolerance to ensure the kerf offset
                % doesn't generate 1000s of tiny points for corner arcs.
                [rawY, rawZ] = HotWireSTEPApp_v6_helpers.offsetProfileLoop(rawY, rawZ, kVal, app.ProfileTolerance);
            end

            % 4. Apply Machine Offsets (THIS WAS THE MISSING LINE)
            % Transform from Model Relative -> Machine Absolute
            y = rawY + offY;
            z = rawZ + offZ;

            % 5. Apply User Modifications (Start Point & Direction)
            if numel(y) > 2
                % A. Clean up duplicate end point
                if abs(y(1)-y(end)) < 1e-6 && abs(z(1)-z(end)) < 1e-6
                    y(end)=[]; z(end)=[];
                end

                % B. Shift Start Point
                % Ensure index is valid
                N = numel(y);
                idx = max(1, min(startIdx, N));

                y = circshift(y, -(idx - 1));
                z = circshift(z, -(idx - 1));

                % C. Apply Cut Direction (CW/CCW)
                % We keep the new Start Point (1), and flip the rest (2:end)
                if isCCW
                    y(2:end) = flipud(y(2:end));
                    z(2:end) = flipud(z(2:end));
                end

                % D. Force Loop Closure
                y(end+1) = y(1);
                z(end+1) = z(1);
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
                        % FIX: Pass Tolerance
                        [rawY, rawZ] = HotWireSTEPApp_v6_helpers.offsetProfileLoop(rawY, rawZ, app.KerfValue, app.ProfileTolerance);
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
            function idx = findMinYIndex(pts, kerfVal, doKerf, tol)
                if isempty(pts), idx = 1; return; end
                y = pts(:,2); z = pts(:,3);
                if doKerf
                    % FIX: Pass Tolerance to match visual/G-code geometry
                    [y, z] = HotWireSTEPApp_v6_helpers.offsetProfileLoop(y, z, kerfVal, tol);
                end
                [~, idx] = min(y);
            end

            doKerf = app.KerfEnabled && app.KerfValue > 0;
            tol    = app.ProfileTolerance;

            % Left
            idxL = findMinYIndex(app.LeftProfilePoints, app.KerfValue, doKerf, tol);
            app.SelectedStartIdxL = idxL;

            % Right
            idxR = findMinYIndex(app.RightProfilePoints, app.KerfValue, doKerf, tol);
            app.SelectedStartIdxR = idxR;

            disp(['Auto Start: Reset indices to nearest Machine Front (L=' num2str(idxL) ', R=' num2str(idxR) ')']);
            app.updateCuttingPlots();
        end

        function onAutoEntry(app)
            % Calculates Auto Entry points.

            % --- Nested Helper ---
            function [e1, e2] = calcEntryLogic(pts, startIdx, billetMinY, doKerf, kVal, tol, useDual)
                e1 = []; e2 = [];
                if isempty(pts), return; end

                % 1. Get Geometry [y z]
                y = pts(:,2); z = pts(:,3); % Note: pts passed as [x y z] or [0 y z]

                if doKerf
                    % FIX: Pass Tolerance
                    [y, z] = HotWireSTEPApp_v6_helpers.offsetProfileLoop(y, z, kVal, tol);
                end

                N = numel(y);
                % Validate Index
                if startIdx > N, startIdx = 1; end
                if startIdx < 1, startIdx = 1; end

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

                % 5. Project Target Point (15mm)
                distT = 15;
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
            tol    = app.ProfileTolerance;

            bMinY  = app.MachineBilletPos(2);
            offsetY = app.BilletShift(2) + app.MachineBilletPos(2);
            offsetZ = app.BilletShift(3) + app.MachineBilletPos(3);

            % Check if we are in "2 Point Mode" (User has set E2 previously)
            useDualMode = ~isempty(app.EntryPoint2L);

            % --- LEFT ---
            if ~isempty(app.LeftProfilePoints)
                % Pass 3D points, Offset is applied to result
                % Note: Logic above expects raw local coords, adds offset later?
                % Actually, calcEntryLogic needs WORLD coords to check vs BilletMinY.
                % But LeftProfilePoints are local.
                % Let's adjust inputs to calcEntryLogic: Pass Local, Add Offset INSIDE logic?
                % No, previous logic added offset to points BEFORE passing.

                % Correct approach: Pass Local Points, apply Kerf locally, then add Offset Y/Z
                ptsL = app.LeftProfilePoints; % [x y z]
                % We need to modify calcEntryLogic slightly to handle the Offset transform
                % explicitly if we want to be clean, OR just pass shifted points.

                % Quick Fix: Shift points locally for the calculation context
                yL_shift = ptsL(:,2) + offsetY;
                zL_shift = ptsL(:,3) + offsetZ;
                ptsL_shifted = [ptsL(:,1)*0, yL_shift, zL_shift]; % Dummy X

                [e1L, e2L] = calcEntryLogic(ptsL_shifted, app.SelectedStartIdxL, bMinY, doKerf, app.KerfValue, tol, useDualMode);
                app.EntryPointL  = e1L;
                app.EntryPoint2L = e2L;
            end

            % --- RIGHT ---
            if strcmp(app.SwitchSyncEntry.Value, 'Coupled')
                app.EntryPointR  = app.EntryPointL;
                app.EntryPoint2R = app.EntryPoint2L;
            elseif ~isempty(app.RightProfilePoints)
                ptsR = app.RightProfilePoints;
                yR_shift = ptsR(:,2) + offsetY;
                zR_shift = ptsR(:,3) + offsetZ;
                ptsR_shifted = [ptsR(:,1)*0, yR_shift, zR_shift];

                [e1R, e2R] = calcEntryLogic(ptsR_shifted, app.SelectedStartIdxR, bMinY, doKerf, app.KerfValue, tol, useDualMode);
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
            % Draws a rotated triangle at pCurrent
            % NOTE: 'pNext' is usually just the adjacent point, but if they are too close,
            % this function needs to be robust. Ideally, the caller should provide a valid vector.

            % But since we are calling it with y(1), y(2), let's robustify it here:
            % (This assumes the caller passed valid points, but if norm is 0, we can't draw)

            hMarker = gobjects(0);
            v = pNext - pCurrent;
            len = norm(v);

            % Robustness: If points are identical, drawing is impossible.
            % (In a perfect world, we would scan forward, but we don't have the full array here).
            % However, if len is tiny, just skip drawing to avoid errors,
            % OR use a default direction (e.g. Up).
            if len < 1e-6
                return;
            end

            % Normalize
            u = v / len;
            scale = 4; % Size mm

            % Geometry
            if strcmp(type, 'start')
                % Forward pointing triangle (Green)
                xPoly = [0, -1, -1] * scale;
                yPoly = [0, 0.5, -0.5] * scale;
                colFill = 'none'; colEdge = [0 1 0]; % Hollow Green
            else
                % Exit (Reverse/Stop) Triangle (Red)
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

            % Z-Buffer Safety: Lift it slightly towards camera so it sits on top of lines
            zLift = 0.1;

            hMarker = patch(ax, ptsFinal(1,:), ptsFinal(2,:), ptsFinal(2,:)*0 + zLift, ...
                'FaceColor', colFill, 'EdgeColor', colEdge, 'LineWidth', 1.0, 'HitTest','off');
        end

        function onClearEntries(app)
            app.EntryPointL = []; app.EntryPointR = [];
            app.EntryPoint2L = []; app.EntryPoint2R = [];
            app.updateCuttingPlots();
        end

        % ===========================================================
        % SIMULATION LOGIC (Final Clean Version)
        % ===========================================================

        function generateSimulationData(app)
            % 1. Setup & Profile Extraction (Sparse / Truth)
            t = app.getTheme();
            offsetY = app.BilletShift(2) + app.MachineBilletPos(2);
            offsetZ = app.BilletShift(3) + app.MachineBilletPos(3);
            isCCW   = strcmp(app.SwitchCutDir.Value, 'Bottom (CCW)');

            [yL, zL] = app.preparePlotData([], app.LeftProfilePoints,  offsetY, offsetZ, app.SelectedStartIdxL, isCCW, t, app.KerfEnabled, app.KerfValue);
            [yR, zR] = app.preparePlotData([], app.RightProfilePoints, offsetY, offsetZ, app.SelectedStartIdxR, isCCW, t, app.KerfEnabled, app.KerfValue);

            % --- CRITICAL FIX: Guard against empty/degenerate profiles ---
            if isempty(yL) || isempty(yR)
                uialert(app.UIFigure, 'Could not generate toolpath. Profiles may be empty or invalid.', 'Simulation Error');
                return;
            end
            % -------------------------------------------------------------

            % Sync Geometry (TRUTH for G-Code)
            [yL, zL, yR, zR] = HotWireSTEPApp_v6_helpers.syncPointCounts(yL, zL, yR, zR);
            app.ProfileSyncL = [yL(:), zL(:)];
            app.ProfileSyncR = [yR(:), zR(:)];

            % ... [Rest of the function remains identical to previous version] ...
            % ... [Paste the Densify Helper, mkRapid, etc. here] ...

            % --- Helper: Densify for Visual Smoothness (Visual Only) ---
            function [yD, zD] = densify(y, z, step)
                if nargin < 3, step = 2.0; end % 2mm visual resolution
                d = [0; cumsum(hypot(diff(y), diff(z)))];
                if d(end) < 1e-3, yD=y; zD=z; return; end

                % Create dense grid
                d_fine = (0:step:d(end))';
                if d_fine(end) ~= d(end), d_fine = [d_fine; d(end)]; end

                % Interpolate (Linear preserves corners, just adds dots between them)
                [du, iu] = unique(d,'stable');
                yD = interp1(du, y(iu), d_fine, 'linear');
                zD = interp1(du, z(iu), d_fine, 'linear');
            end

            % ... [Copy the rest of the function I gave you previously] ...
            % (Segments, Densify Calls, Combine, Map, Physics, Projection, UI Init)

            % Helper for Segments
            function pts = mkRapid(e1, e2)
                pZero=[0,0]; pSafe=[10,10];
                pLoad=[app.MachineBilletPos(2), app.MachineBilletPos(3)+app.BilletSize(3)/2];
                pRet=[pLoad(1)-10, pLoad(2)];
                pts=[pZero; pSafe; pLoad; pRet];
                if ~isempty(e1), pts=[pts; e1]; end
                if ~isempty(e2), pts=[pts; e2]; end
            end

            function pts = mkLeadIn(start, e1, e2)
                pRet=[app.MachineBilletPos(2)-10, app.MachineBilletPos(3)+app.BilletSize(3)/2];
                if ~isempty(e2), last=e2; elseif ~isempty(e1), last=e1; else, last=pRet; end
                pts=[last; start];
            end

            function pts = mkLeadOut(en, e1, e2)
                first=en;
                if ~isempty(e2), first=e2; elseif ~isempty(e1), first=e1; end
                pts=[en; first];
            end

            function pts = mkReturn(en, e1, e2)
                pts=en;
                if ~isempty(e2) && ~isempty(e1), pts=[pts; e1]; end
                pts=[pts; [0, pts(end,2)]; [0,0]];
            end

            % 2. Generate Raw Segments
            rawRapL = mkRapid(app.EntryPointL, app.EntryPoint2L);
            rawRapR = mkRapid(app.EntryPointR, app.EntryPoint2R);

            rawLiL = mkLeadIn([yL(1),zL(1)], app.EntryPointL, app.EntryPoint2L);
            rawLiR = mkLeadIn([yR(1),zR(1)], app.EntryPointR, app.EntryPoint2R);

            rawLoL = mkLeadOut([yL(end),zL(end)], app.EntryPointL, app.EntryPoint2L);
            rawLoR = mkLeadOut([yR(end),zR(end)], app.EntryPointR, app.EntryPoint2R);

            rawRetL = mkReturn(rawLoL(end,:), app.EntryPointL, app.EntryPoint2L);
            rawRetR = mkReturn(rawLoR(end,:), app.EntryPointR, app.EntryPoint2R);

            % 3. Densify Segments
            % Distributes points based on PHYSICAL DISTANCE, not Index.
            function [yLD, zLD, yRD, zRD] = densifySynced(yL, zL, yR, zR, step)
                if nargin < 5, step = 2.0; end

                N = numel(yL);
                if N < 2, yLD=yL; zLD=zL; yRD=yR; zRD=zR; return; end

                % 1. Calculate cumulative physical distance for both paths
                distL = [0; cumsum(hypot(diff(yL), diff(zL)))];
                distR = [0; cumsum(hypot(diff(yR), diff(zR)))];

                % 2. Normalize both to 0..1 based on their own total length
                maxL = distL(end); if maxL < 1e-6, maxL = 1; end
                maxR = distR(end); if maxR < 1e-6, maxR = 1; end

                sL = distL / maxL;
                sR = distR / maxR;

                % 3. Create a Master Parameter based on the "Longest" path behavior
                s_orig = (sL + sR) / 2;

                % 4. Determine step count based on the longest path
                totalLen = max(distL(end), distR(end));
                nSteps = ceil(totalLen / step);
                nSteps = max(nSteps, N);

                % 5. Create uniform grid for smooth animation (0..1)
                s_smooth = linspace(0, 1, nSteps)';

                % 6. Union: Include EXACT corner times + Smooth times
                s_combined = unique([s_orig; s_smooth]);

                % 7. Interpolate geometry onto this new time grid
                [su, iu] = unique(s_orig, 'stable'); % Ensure unique points for interp1
                yLD = interp1(su, yL(iu), s_combined, 'linear');
                zLD = interp1(su, zL(iu), s_combined, 'linear');
                yRD = interp1(su, yR(iu), s_combined, 'linear');
                zRD = interp1(su, zR(iu), s_combined, 'linear');
            end

            [dRapL_y, dRapL_z, dRapR_y, dRapR_z]     = densifySynced(rawRapL(:,1), rawRapL(:,2), rawRapR(:,1), rawRapR(:,2));
            [dLiL_y, dLiL_z, dLiR_y, dLiR_z]         = densifySynced(rawLiL(:,1), rawLiL(:,2), rawLiR(:,1), rawLiR(:,2));
            [dProfL_y, dProfL_z, dProfR_y, dProfR_z] = densifySynced(yL, zL, yR, zR);
            [dLoL_y, dLoL_z, dLoR_y, dLoR_z]         = densifySynced(rawLoL(:,1), rawLoL(:,2), rawLoR(:,1), rawLoR(:,2));
            [dRetL_y, dRetL_z, dRetR_y, dRetR_z]     = densifySynced(rawRetL(:,1), rawRetL(:,2), rawRetR(:,1), rawRetR(:,2));

            % 4. Combine into Simulation Path
            app.SimRapidCutoffIndex  = numel(dRapL_y);
            app.SimProfileStartIndex = app.SimRapidCutoffIndex + numel(dLiL_y);
            app.SimFeedEndIndex      = app.SimProfileStartIndex + numel(dProfL_y);
            app.SimLeadOutEndIndex   = app.SimFeedEndIndex + numel(dLoL_y);

            fullY_L = [dRapL_y; dLiL_y; dProfL_y; dLoL_y; dRetL_y];
            fullZ_L = [dRapL_z; dLiL_z; dProfL_z; dLoL_z; dRetL_z];
            fullY_R = [dRapR_y; dLiR_y; dProfR_y; dLoR_y; dRetR_y];
            fullZ_R = [dRapR_z; dLiR_z; dProfR_z; dLoR_z; dRetR_z];

            % 5. Map to 3D Machine Space
            if ~isempty(app.LeftProfilePoints),  xL = app.LeftProfilePoints(1,1);  else, xL = app.MachineBilletPos(1); end
            if ~isempty(app.RightProfilePoints), xR = app.RightProfilePoints(1,1); else, xR = app.MachineBilletPos(1)+10; end

            xL = xL + app.BilletShift(1) + app.MachineBilletPos(1);
            xR = xR + app.BilletShift(1) + app.MachineBilletPos(1);

            app.SimPathL = [repmat(xL, numel(fullY_L), 1), fullY_L, fullZ_L];
            app.SimPathR = [repmat(xR, numel(fullY_R), 1), fullY_R, fullZ_R];

            % 6. Physics
            dL = sqrt(sum(diff(app.SimPathL).^2, 2)); dL(isnan(dL)) = 0;
            dR = sqrt(sum(diff(app.SimPathR).^2, 2)); dR(isnan(dR)) = 0;
            app.SimArcLenL = [0; cumsum(dL)];
            app.SimArcLenR = [0; cumsum(dR)];
            app.SimTotalLength = max(app.SimArcLenL(end), app.SimArcLenR(end));
            app.SimPlayDist = 0;

            % 7. Tower Projections
            V = app.SimPathR - app.SimPathL;
            tL = -app.SimPathL(:,1) ./ V(:,1);
            tR = (app.MachineSpanX - app.SimPathL(:,1)) ./ V(:,1);
            app.SimTowerPathL = app.SimPathL + tL .* V;
            app.SimTowerPathR = app.SimPathL + tR .* V;

            % 8. UI Init
            nPoints = size(app.SimPathL, 1);
            app.SimSlider.Limits = [1, max(1, nPoints)];
            app.SimSlider.Value = 1;

            if isprop(app, 'SimIndexSpinner') && ~isempty(app.SimIndexSpinner)
                app.SimIndexSpinner.Limits = [1, max(1, nPoints)];
                app.SimIndexSpinner.Value = 1;
            end

            app.initSimulationPlot();
        end

        % --- View Management ---
        function initSimulationPlot(app)
            % Draws static elements and inits dynamic tags
            ax = app.AxSim; cla(ax); hold(ax,'on'); t=app.getTheme();

            % Setup Geometry
            offX=app.MachineBedPos(1); mSpan=app.MachineSpanX; bp=app.MachineBilletPos;
            [xb,yb,zb] = app.makeBoxVertices(0, app.MachineBedPos(2), -20, 1000, 700, 20); % Bed
            patch(ax, 'Vertices',[xb,yb,zb], 'Faces',app.boxFaces, 'FaceColor',[0.4 0.4 0.4], 'FaceAlpha',0.5, 'EdgeColor',[0.2 0.2 0.2]);

            % Towers
            patch(ax, 'XData',ones(4,1)*(-offX), 'YData',[0;750;750;0], 'ZData',[0;0;500;500], 'FaceColor',t.planeRed, 'FaceAlpha',0.15, 'EdgeColor',t.planeRed);
            patch(ax, 'XData',ones(4,1)*(mSpan-offX), 'YData',[0;750;750;0], 'ZData',[0;0;500;500], 'FaceColor',t.planeGreen, 'FaceAlpha',0.15, 'EdgeColor',t.planeGreen);

            % Billet & Model
            bX=bp(1)-offX; bY=bp(2); bZ=bp(3); bS=app.BilletSize;
            [xm,ym,zm] = app.makeBoxVertices(bX,bY,bZ, bS(1),bS(2),bS(3));
            patch(ax, 'Vertices',[xm,ym,zm], 'Faces',app.boxFaces, 'FaceColor',[0.3 0.5 0.8], 'FaceAlpha',0.2, 'EdgeColor',t.labelCol, 'LineStyle','--');

            if ~isempty(app.ModelPatch)
                patch(ax, 'Vertices', app.ModelPatch.Vertices+[bX,bY,bZ]+app.BilletShift, 'Faces',app.ModelPatch.Faces, ...
                    'FaceColor',[0.6 0.6 0.7], 'FaceAlpha',0.3, 'EdgeColor','none', 'Tag','SimModel');
            end

            % --- Dynamic Elements (Original Styles) ---
            % Wire
            plot3(ax,NaN,NaN,NaN, 'Color',t.wireKerf, 'LineWidth',0.2, 'Tag','SimWire');

            % Tower Dots
            plot3(ax,NaN,NaN,NaN, 'o', 'MarkerSize',4, 'MarkerFaceColor',t.planeRed, 'Tag','SimDotL');
            plot3(ax,NaN,NaN,NaN, 'o', 'MarkerSize',4, 'MarkerFaceColor',t.planeGreen, 'Tag','SimDotR');

            % Model Dots
            plot3(ax,NaN,NaN,NaN, 'o', 'MarkerSize',4, 'MarkerFaceColor',t.planeRed, 'Tag','SimModelDotL');
            plot3(ax,NaN,NaN,NaN, 'o', 'MarkerSize',4, 'MarkerFaceColor',t.planeGreen, 'Tag','SimModelDotR');

            % Trails (Yellow/Orange/Red-Green/Orange/Yellow)
            tags = {'Rapid','LeadIn','Feed','LeadOut','Return'};
            cols = {[0.9 0.8 0], [1 0.5 0], t.planeRed, [1 0.5 0], [0.9 0.8 0]};
            styles = {'-','-','-','--','--'};

            for i=1:5
                plot3(ax,NaN,NaN,NaN, styles{i}, 'Color',cols{i}, 'LineWidth',0.5, 'Tag',['SimTower' tags{i} 'L']);
                plot3(ax,NaN,NaN,NaN, styles{i}, 'Color',cols{i}, 'LineWidth',0.5, 'Tag',['SimTower' tags{i} 'R']);
                plot3(ax,NaN,NaN,NaN, styles{i}, 'Color',cols{i}, 'LineWidth',0.5, 'Tag',['SimModel' tags{i} 'L']);
                colR = cols{i}; if i==3, colR=t.planeGreen; end
                plot3(ax,NaN,NaN,NaN, styles{i}, 'Color',colR, 'LineWidth',0.5, 'Tag',['SimModel' tags{i} 'R']);
            end

            app.updateSimVisuals(1);
            app.onResetSimViewMachine();
        end

        % --- Core Visualization Loop ---
        function updateSimVisuals(app, idx)
            % Efficiently updates coordinates of existing plot objects
            if isempty(app.SimPathL), return; end
            idx = max(1, min(idx, size(app.SimPathL,1)));
            offX = app.MachineBedPos(1);

            % Update Wire & Dots
            pTL = app.SimTowerPathL(idx,:) - [offX,0,0]; pTR = app.SimTowerPathR(idx,:) - [offX,0,0];
            set(findobj(app.AxSim,'Tag','SimWire'), 'XData',[pTL(1) pTR(1)], 'YData',[pTL(2) pTR(2)], 'ZData',[pTL(3) pTR(3)]);
            set(findobj(app.AxSim,'Tag','SimDotL'), 'XData',pTL(1), 'YData',pTL(2), 'ZData',pTL(3));
            set(findobj(app.AxSim,'Tag','SimDotR'), 'XData',pTR(1), 'YData',pTR(2), 'ZData',pTR(3));

            pML = app.SimPathL(idx,:) - [offX,0,0]; pMR = app.SimPathR(idx,:) - [offX,0,0];
            set(findobj(app.AxSim,'Tag','SimModelDotL'), 'XData',pML(1), 'YData',pML(2), 'ZData',pML(3));
            set(findobj(app.AxSim,'Tag','SimModelDotR'), 'XData',pMR(1), 'YData',pMR(2), 'ZData',pMR(3));

            % Helpers for Trails
            function upT(tag, data, s, e)
                h=findobj(app.AxSim,'Tag',tag);
                if ~isempty(h)
                    if s>e, h.XData=[]; h.YData=[]; h.ZData=[]; else
                        dt=data(s:e,:)-[offX,0,0]; h.XData=dt(:,1); h.YData=dt(:,2); h.ZData=dt(:,3);
                    end
                end
            end

            % Update Phase Trails
            phases = {
                1, app.SimRapidCutoffIndex, 'Rapid';
                app.SimRapidCutoffIndex, app.SimProfileStartIndex, 'LeadIn';
                app.SimProfileStartIndex, app.SimFeedEndIndex, 'Feed';
                app.SimFeedEndIndex, app.SimLeadOutEndIndex, 'LeadOut';
                app.SimLeadOutEndIndex, idx, 'Return'
                };

            for i=1:5
                startIdx = phases{i,1}; endLimit = phases{i,2}; tagName = phases{i,3};

                % Logic: Draw from start up to current idx (clamped by limit)
                if idx > startIdx
                    currEnd = min(idx, endLimit);
                    upT(['SimTower' tagName 'L'], app.SimTowerPathL, startIdx, currEnd);
                    upT(['SimTower' tagName 'R'], app.SimTowerPathR, startIdx, currEnd);
                    upT(['SimModel' tagName 'L'], app.SimPathL, startIdx, currEnd);
                    upT(['SimModel' tagName 'R'], app.SimPathR, startIdx, currEnd);
                else
                    % Clear if not reached yet
                    upT(['SimTower' tagName 'L'], [], 1, 0);
                    upT(['SimTower' tagName 'R'], [], 1, 0);
                    upT(['SimModel' tagName 'L'], [], 1, 0);
                    upT(['SimModel' tagName 'R'], [], 1, 0);
                end
            end

            % Readouts
            app.LblReadoutX.Text = sprintf('%.2f', pTL(2)); app.LblReadoutY.Text = sprintf('%.2f', pTL(3));
            app.LblReadoutZ.Text = sprintf('%.2f', pTR(2)); app.LblReadoutA.Text = sprintf('%.2f', pTR(3));
        end

        % --- Interaction Handlers ---
        function onSimPlay(app)
            if isempty(app.SimPathL), return; end
            if app.SimPlayDist >= app.SimTotalLength - 1e-3, app.SimPlayDist = 0; end

            if isempty(app.SimTimer) || ~isvalid(app.SimTimer)
                app.SimTimer = timer('ExecutionMode', 'fixedRate', 'Period', 0.05, 'TimerFcn', @(~,~)app.onSimTimerTick());
            end
            if strcmp(app.SimTimer.Running, 'off')
                start(app.SimTimer);
                app.SimPlayBtn.Enable = 'off';
            end
        end

        function onSimPause(app)
            if ~isempty(app.SimTimer) && isvalid(app.SimTimer), stop(app.SimTimer); end
            app.SimPlayBtn.Enable = 'on';
        end

        function onSimStop(app)
            app.onSimPause();
            app.SimPlayDist = 0;
            app.syncSimControls(1);
            app.updateSimVisuals(1);
        end

        function onSimTimerTick(app)
            % Timer Updates Distance -> Updates UI (One Way)

            % Calculate step based on speed multiplier
            step = app.SimStepDist * app.SimSpeedSpinner.Value;
            app.SimPlayDist = app.SimPlayDist + step;

            isDone = false;
            if app.SimPlayDist >= app.SimTotalLength
                app.SimPlayDist = app.SimTotalLength;
                isDone = true;
            end

            % Map physical distance back to array index
            idx = app.simIndexAtDistance(app.SimPlayDist);

            % Update visual + controls WITHOUT triggering their callbacks (Value update only)
            app.syncSimControls(idx);
            app.updateSimVisuals(idx);

            if isDone, app.onSimPause(); end
        end

        function onSimSliderChanging(app, src)
            % User Interacts with Slider -> Update Distance
            idx = round(src.Value);
            app.setSimFromIndex(idx);
        end

        function onSimIndexSpinnerChanged(app, src)
            % User Interacts with Spinner -> Update Distance
            idx = round(src.Value);
            app.setSimFromIndex(idx);
        end

        function setSimFromIndex(app, idx)
            % Updates simulation state based on a specific index (from Slider/Spinner).
            if isempty(app.SimPathL), return; end
            idx = max(1, min(idx, size(app.SimPathL, 1)));

            % Determine Master Length array for Taper correctness
            lenL = 0; lenR = 0;
            if ~isempty(app.SimArcLenL), lenL = app.SimArcLenL(end); end
            if ~isempty(app.SimArcLenR), lenR = app.SimArcLenR(end); end

            if lenR > lenL
                targetArr = app.SimArcLenR;
            else
                targetArr = app.SimArcLenL;
            end

            % Sync Physics Distance to User Selection
            if idx <= numel(targetArr)
                app.SimPlayDist = targetArr(idx);
            else
                app.SimPlayDist = app.SimTotalLength;
            end

            app.syncSimControls(idx);
            app.updateSimVisuals(idx);
        end

        function syncSimControls(app, idx)
            % Updates UI elements to match index (Visual sync only)
            app.SimSlider.Value = idx;
            if isprop(app, 'SimIndexSpinner') && ~isempty(app.SimIndexSpinner)
                app.SimIndexSpinner.Value = idx;
            end
        end

        function idx = simIndexAtDistance(app, dist)
            % Returns the simulation index corresponding to a physical distance.
            % Handles TAPER by checking which path is the 'master' (longer) path.

            dist = max(0, min(dist, app.SimTotalLength));

            if isempty(app.SimArcLenL) || isempty(app.SimArcLenR)
                idx = 1;
                return;
            end

            % Identify which tower path dictates the total length
            lenL = app.SimArcLenL(end);
            lenR = app.SimArcLenR(end);

            % If Right tower path is significantly longer, use it for lookup.
            % Otherwise default to Left.
            if lenR > lenL
                masterLenArr = app.SimArcLenR;
            else
                masterLenArr = app.SimArcLenL;
            end

            % Find the last index where distance is <= current playback distance
            idx = find(masterLenArr <= dist, 1, 'last');

            if isempty(idx), idx = 1; end
            idx = min(idx, size(app.SimPathL, 1));
        end

        % ===========================================================
        % VIEW & HELPER METHODS
        % ===========================================================

        function onResetSimViewMachine(app)
            app.resetViewToMachine(app.AxSim);
        end

        function onResetSimViewBillet(app)
            app.resetViewToBillet(app.AxSim);
        end

        % --- Shared View Helpers ---
        function resetViewToMachine(app, ax)
            % Standard Machine View (Home at bottom-left)
            offX = app.MachineBedPos(1);
            mX   = app.MachineSpanX;
            mLimY = app.MachineLimitY;
            mLimZ = app.MachineLimitZ;
            bs = app.MachineBedSize;

            view(ax, 3); axis(ax, 'equal');
            xlim(ax, [-offX - 100, mX - offX + 100]);
            ylim(ax, [-50, mLimY + 50]);
            zlim(ax, [-bs(3)-20, mLimZ + 80]);
        end

        function resetViewToBillet(app, ax)
            % Focus View on Billet with buffer
            offX = app.MachineBedPos(1);
            bp   = app.MachineBilletPos; % [X Y Z] absolute machine coords
            bs   = app.BilletSize;       % [W D H]

            % Billet Bounds in Plot Coords
            % Plot X = MachineX - BedOffset
            bMin = [bp(1)-offX, bp(2), bp(3)];
            bMax = bMin + bs;

            % Calculate relative buffer
            maxDim = max(bs);
            if maxDim < 1, maxDim = 100; end
            buffer = maxDim * 0.2;

            % 1. Set Aspect Ratio FIRST
            daspect(ax, [1 1 1]);

            % 2. Apply Limits
            xlim(ax, [bMin(1)-buffer, bMax(1)+buffer]);
            ylim(ax, [bMin(2)-buffer, bMax(2)+buffer]);
            zlim(ax, [bMin(3)-buffer, bMax(3)+buffer]);

            % 3. Standard View Settings
            view(ax, 3);
            grid(ax, 'on');
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
        % APP LIFECYCLE (Must be at the end)
        % ===========================================================
        function delete(app)
            % Ensure Timer is killed when app closes
            if ~isempty(app.SimTimer) && isvalid(app.SimTimer)
                stop(app.SimTimer);
                delete(app.SimTimer);
            end
        end

        function onAppClose(app, src)
            % Cleanup Timer and Close Window
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

            % 1. Determine the target name from the current model
            rawName = "Output";
            if ~isempty(app.CurrentModelName)
                [~, rawName, ~] = fileparts(app.CurrentModelName);
            end

            % Clean up filename (replace spaces with underscores for safety)
            rawName = replace(rawName, ' ', '_');
            newName = sprintf("GCode-V1-%s", rawName);

            % 2. Get current value
            currentVal = app.FieldFilename.Value;

            % 3. Update Condition:
            % - If empty
            % - OR if it looks like an auto-generated name (starts with prefix)
            % This allows the app to update "GCode-V1-OldModel" to "GCode-V1-NewModel",
            % while preserving completely custom names like "Final_Run_01.tap".
            if isempty(currentVal) || startsWith(currentVal, "GCode-V1-")
                app.FieldFilename.Value = newName;
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
            % Maps selected G-code line (k) to Visual Path Index and updates Post plot

            if isempty(app.PP_LineToPathIndex) || isempty(app.PP_PathL) || isempty(app.PP_TowerPathL)
                return;
            end

            % Map Line -> Path Index
            k = max(1, min(k, numel(app.PP_LineToPathIndex)));
            idx = app.PP_LineToPathIndex(k);

            % Handle non-movement lines (scroll back)
            kk = k;
            while (isnan(idx) || idx <= 0) && kk > 1
                kk = kk - 1;
                idx = app.PP_LineToPathIndex(kk);
            end
            if isnan(idx) || idx <= 0, idx = 1; end
            idx = min(idx, size(app.PP_PathL,1));

            ax = app.AxPost;
            offX = app.MachineBedPos(1);

            % Phase Indices
            idxRapidEnd   = app.PP_RapidEndIndex;
            idxProfStart  = app.PP_ProfileStartIndex;
            idxProfEnd    = app.PP_ProfileEndIndex;
            idxLeadOutEnd = app.PP_LeadOutEndIndex;

            towerL = app.PP_TowerPathL; towerR = app.PP_TowerPathR;
            pathL  = app.PP_PathL; pathR  = app.PP_PathR;

            % Update Dots
            pTL = [towerL(idx,1) - offX, towerL(idx,2), towerL(idx,3)];
            pTR = [towerR(idx,1) - offX, towerR(idx,2), towerR(idx,3)];
            pML = [pathL(idx,1) - offX, pathL(idx,2), pathL(idx,3)];
            pMR = [pathR(idx,1) - offX, pathR(idx,2), pathR(idx,3)];

            set(findobj(ax,'Tag','PostWire'), 'XData',[pTL(1) pTR(1)], 'YData',[pTL(2) pTR(2)], 'ZData',[pTL(3) pTR(3)]);
            set(findobj(ax,'Tag','PostDotL'), 'XData',pTL(1), 'YData',pTL(2), 'ZData',pTL(3));
            set(findobj(ax,'Tag','PostDotR'), 'XData',pTR(1), 'YData',pTR(2), 'ZData',pTR(3));
            set(findobj(ax,'Tag','PostModelDotL'), 'XData',pML(1), 'YData',pML(2), 'ZData',pML(3));
            set(findobj(ax,'Tag','PostModelDotR'), 'XData',pMR(1), 'YData',pMR(2), 'ZData',pMR(3));

            % Update Trails (Strict Phases)
            function updateT(tag, data, s, e)
                h = findobj(ax, 'Tag', tag);
                if ~isempty(h)
                    s = max(1, min(s, size(data,1))); e = max(1, min(e, size(data,1)));
                    if e < s, h.XData=[]; h.YData=[]; h.ZData=[]; return; end
                    dt = data(s:e,:);
                    h.XData = dt(:,1) - offX; h.YData = dt(:,2); h.ZData = dt(:,3);
                end
            end

            function clearT(tags)
                for ii=1:numel(tags)
                    h=findobj(ax,'Tag',tags{ii}); if ~isempty(h), h.XData=[]; h.YData=[]; h.ZData=[]; end
                end
            end

            % 1. Rapid (Yellow)
            curEnd = min(idx, idxRapidEnd);
            updateT('PostTowerRapidL', towerL, 1, curEnd);
            updateT('PostTowerRapidR', towerR, 1, curEnd);
            updateT('PostModelRapidL', pathL,  1, curEnd);
            updateT('PostModelRapidR', pathR,  1, curEnd);

            % 2. Lead In (Orange)
            if idx > idxRapidEnd
                curEnd = min(idx, idxProfStart);
                updateT('PostTowerLeadInL', towerL, idxRapidEnd, curEnd);
                updateT('PostTowerLeadInR', towerR, idxRapidEnd, curEnd);
                updateT('PostModelLeadInL', pathL,  idxRapidEnd, curEnd);
                updateT('PostModelLeadInR', pathR,  idxRapidEnd, curEnd);
            else, clearT({'PostTowerLeadInL','PostTowerLeadInR','PostModelLeadInL','PostModelLeadInR'}); end

            % 3. Feed (Red/Green)
            if idx > idxProfStart
                curEnd = min(idx, idxProfEnd);
                updateT('PostTowerFeedL', towerL, idxProfStart, curEnd);
                updateT('PostTowerFeedR', towerR, idxProfStart, curEnd);
                updateT('PostModelFeedL', pathL,  idxProfStart, curEnd);
                updateT('PostModelFeedR', pathR,  idxProfStart, curEnd);
            else, clearT({'PostTowerFeedL','PostTowerFeedR','PostModelFeedL','PostModelFeedR'}); end

            % 4. Lead Out (Orange Dashed)
            if idx > idxProfEnd
                curEnd = min(idx, idxLeadOutEnd);
                updateT('PostTowerLeadOutL', towerL, idxProfEnd, curEnd);
                updateT('PostTowerLeadOutR', towerR, idxProfEnd, curEnd);
                updateT('PostModelLeadOutL', pathL,  idxProfEnd, curEnd);
                updateT('PostModelLeadOutR', pathR,  idxProfEnd, curEnd);
            else, clearT({'PostTowerLeadOutL','PostTowerLeadOutR','PostModelLeadOutL','PostModelLeadOutR'}); end

            % 5. Return (Yellow Dashed)
            if idx > idxLeadOutEnd
                updateT('PostTowerReturnL', towerL, idxLeadOutEnd, idx);
                updateT('PostTowerReturnR', towerR, idxLeadOutEnd, idx);
                updateT('PostModelReturnL', pathL,  idxLeadOutEnd, idx);
                updateT('PostModelReturnR', pathR,  idxLeadOutEnd, idx);
            else, clearT({'PostTowerReturnL','PostTowerReturnR','PostModelReturnL','PostModelReturnR'}); end

            drawnow limitrate;
        end

        function onResetPostViewMachine(app)
            app.resetViewToMachine(app.AxPost);
        end

        function onResetPostViewBillet(app)
            app.resetViewToBillet(app.AxPost);
        end

        function onPostProcess(app)
            % Generates Semantic G-Code using TRUTH data.
            % Builds a visual path (PP_PathL/R) strictly from G-Code coords (1:1 fidelity).

            % 1. Ensure Simulation Data Exists
            if isempty(app.SimPathL) || isempty(app.ProfileSyncL)
                app.generateSimulationData();
                if isempty(app.SimPathL)
                    uialert(app.UIFigure, 'No path data available.', 'Error'); return;
                end
            end

            % --- DATA SYNC ---
            app.PP_PathL = zeros(0,3); app.PP_PathR = zeros(0,3);
            app.PP_TowerPathL = zeros(0,3); app.PP_TowerPathR = zeros(0,3);

            app.PP_RapidEndIndex     = app.SimRapidCutoffIndex;
            app.PP_ProfileStartIndex = app.SimProfileStartIndex;
            app.PP_ProfileEndIndex   = app.SimFeedEndIndex;
            app.PP_LeadOutEndIndex   = app.SimLeadOutEndIndex;

            % 2. Prepare Settings
            feed  = round(app.SpinFeedRate.Value);
            power = round(app.SpinPower.Value);

            % --- ALIGNMENT ---
            baseX = app.MachineBilletPos(1) + app.BilletShift(1) + app.ModelXMin;
            xM_L = baseX + app.NumLeftOffset.Value;
            xM_R = baseX + app.NumRightOffset.Value;
            xT_L = 0; xT_R = app.MachineSpanX;

            mDim = [abs(xM_R - xM_L), app.ModelYMax - app.ModelYMin, app.ModelZMax - app.ModelZMin];

            function [tx, ty, tz, ta] = project(yL, zL, yR, zR)
                rL = (xT_L - xM_L) / (xM_R - xM_L);
                tyL = yL + (yR - yL) * rL;
                tzL = zL + (zR - zL) * rL;
                rR = (xT_R - xM_L) / (xM_R - xM_L);
                tyR = yL + (yR - yL) * rR;
                tzR = zL + (zR - zL) * rR;
                tx = tyL; ty = tzL; tz = tyR; ta = tzR;
            end

            function [mxL, myL, mzL, mxR, myR, mzR] = machineToModelVisual(tx, ty, tz, ta)
                ratioL = (xM_L - xT_L) / (xT_R - xT_L);
                ratioR = (xM_R - xT_L) / (xT_R - xT_L);
                mxL = xM_L; myL = tx + (tz - tx) * ratioL; mzL = ty + (ta - ty) * ratioL;
                mxR = xM_R; myR = tx + (tz - tx) * ratioR; mzR = ty + (ta - ty) * ratioR;
            end

            lines = strings(0,1); map = zeros(0,1); pathIdx = 0;
            curX=0; curY=0; curZ=0; curA=0;

            function add(code, comment, tx, ty, tz, ta)
                if nargin < 6
                    % Command without movement
                    s = code;
                    % Fix Nested Comments: Only add parens if they aren't already there
                    if nargin >= 2 && ~isempty(comment)
                        if startsWith(strtrim(comment), '(')
                            s = sprintf('%-35s %s', code, comment);
                        else
                            s = sprintf('%-35s (%s)', code, comment);
                        end
                    end
                    lines(end+1) = s;
                    map(end+1) = max(1, pathIdx);
                else
                    % Movement command
                    s = sprintf('%-35s (%s)', code, comment);
                    lines(end+1) = s;
                    pathIdx = pathIdx + 1;
                    curX=tx; curY=ty; curZ=tz; curA=ta;

                    app.PP_TowerPathL(pathIdx,:) = [xT_L, tx, ty];
                    app.PP_TowerPathR(pathIdx,:) = [xT_R, tz, ta];
                    [mxL, myL, mzL, mxR, myR, mzR] = machineToModelVisual(tx, ty, tz, ta);
                    app.PP_PathL(pathIdx,:) = [mxL, myL, mzL];
                    app.PP_PathR(pathIdx,:) = [mxR, myR, mzR];
                    map(end+1) = pathIdx;
                end
            end

            % --- 4. G-CODE GENERATION ---
            add('% ------------------------------------------');
            add(sprintf('%%     File: %s', app.FieldFilename.Value));
            add(sprintf('%%    Model: %s', app.CurrentModelName));
            add(sprintf('%%     Date: %s', string(datetime('now'))));
            add(sprintf('%%    Model: X=%.2fmm Y=%.2fmm Z=%.2fmm', mDim));
            add(sprintf('%%   Billet: X=%.2fmm Y=%.2fmm Z=%.2fmm', app.BilletSize));
            add(sprintf('%% Position: X=%.2fmm Y=%.2fmm Z=%.2fmm', app.MachineBilletPos));
            add('% ------------------------------------------');
            add('G21','Metric'); add('G90','Absolute'); add('G94','Feed/min');

            % --- START SEQUENCE (Split G53) ---
            % 1. Retract Horizontals (X, Z) to 0
            pathIdx = pathIdx + 1;
            app.PP_TowerPathL(pathIdx,:) = [xT_L, 0, 0]; app.PP_TowerPathR(pathIdx,:) = [xT_R, 0, 0];
            app.PP_PathL(pathIdx,:) = [xM_L, 0, 0]; app.PP_PathR(pathIdx,:) = [xM_R, 0, 0];

            % Manual add to avoid double parens issue
            lines(end+1) = 'G53 G0 X0 Z0 (Safe Start: Horizontals)';
            map(end+1) = pathIdx;

            % 2. Home Verticals (Y, A) to 0
            lines(end+1) = 'G53 G0 Y0 A0 (Safe Start: Verticals)';
            map(end+1) = pathIdx;

            % --- PHASE 1: LOAD ---
            add('%% --- LOADING ---', '');
            add('G0 X10.00 Y10.00 Z10.00 A10.00', 'Safe Position', 10, 10, 10, 10);

            bY = app.MachineBilletPos(2); bZ = app.MachineBilletPos(3) + app.BilletSize(3)/2;
            add(sprintf('G0 X%.3f Y%.3f Z%.3f A%.3f', bY, bZ, bY, bZ), 'Load Position', bY, bZ, bY, bZ);

            % USE M00 (Compulsory Stop) instead of M1
            add('M00', 'STOP: Load Block');

            bY_Ret = bY - 10;
            add(sprintf('G0 X%.3f Y%.3f Z%.3f A%.3f', bY_Ret, bZ, bY_Ret, bZ), 'Retract Safety', bY_Ret, bZ, bY_Ret, bZ);

            % --- PHASE 2: APPROACH ---
            add('%% --- APPROACH ---', '');

            e1L = app.EntryPointL; e1R = app.EntryPointR;
            e2L = app.EntryPoint2L; e2R = app.EntryPoint2R;

            if ~isempty(e1L)
                [tx, ty, tz, ta] = project(e1L(1), e1L(2), e1R(1), e1R(2));
                add(sprintf('G0 X%.3f Y%.3f Z%.3f A%.3f', tx, ty, tz, ta), 'Entry Point 1', tx, ty, tz, ta);
            end

            if ~isempty(e2L)
                [tx, ty, tz, ta] = project(e2L(1), e2L(2), e2R(1), e2R(2));
                add(sprintf('G0 X%.3f Y%.3f Z%.3f A%.3f', tx, ty, tz, ta), 'Entry Point 2', tx, ty, tz, ta);
            end

            app.PP_RapidEndIndex = pathIdx;

            % Heat Sequence
            add(sprintf('S%d', power), 'Sets Hot Wire Power');
            add('M301', 'Extraction ON > Wait 5s > Power ON');
            add(sprintf('F%d', feed), 'Set Cut Feedrate');

            % --- PHASE 3: PROFILE ---
            add('%% --- PROFILE CUT ---', '');
            pSyncL = app.ProfileSyncL; pSyncR = app.ProfileSyncR;

            [tx, ty, tz, ta] = project(pSyncL(1,1), pSyncL(1,2), pSyncR(1,1), pSyncR(1,2));
            add(sprintf('G1 X%.3f Y%.3f Z%.3f A%.3f', tx, ty, tz, ta), 'Start Point', tx, ty, tz, ta);

            app.PP_ProfileStartIndex = pathIdx;

            for i = 2:size(pSyncL, 1)
                [tx, ty, tz, ta] = project(pSyncL(i,1), pSyncL(i,2), pSyncR(i,1), pSyncR(i,2));
                add(sprintf('G1 X%.3f Y%.3f Z%.3f A%.3f', tx, ty, tz, ta), '', tx, ty, tz, ta);
            end

            app.PP_ProfileEndIndex = pathIdx;

            % --- PHASE 4: EXIT ---
            add('%% --- EXIT SEQUENCE ---', '');
            lastE_L = e1L; lastE_R = e1R;
            exitLabel = 'Lead Out Entry 1';
            if ~isempty(e2L)
                lastE_L = e2L; lastE_R = e2R;
                exitLabel = 'Lead Out Entry 2';
            end

            if ~isempty(lastE_L)
                [tx, ty, tz, ta] = project(lastE_L(1), lastE_L(2), lastE_R(1), lastE_R(2));
                add(sprintf('G1 X%.3f Y%.3f Z%.3f A%.3f', tx, ty, tz, ta), exitLabel, tx, ty, tz, ta);
            end

            app.PP_LeadOutEndIndex = pathIdx;

            add('M302', 'Hot Wire Power OFF > Wait > Ext OFF');

            if ~isempty(e2L) && ~isempty(e1L)
                [tx, ty, tz, ta] = project(e1L(1), e1L(2), e1R(1), e1R(2));
                add(sprintf('G0 X%.3f Y%.3f Z%.3f A%.3f', tx, ty, tz, ta), 'Return to Entry 1', tx, ty, tz, ta);
            end

            % --- FINAL RETURN (Split G53) ---

            % Step 1: Retract Horizontals (X, Z) to 0
            pathIdx = pathIdx + 1;
            app.PP_TowerPathL(pathIdx,:) = [xT_L, 0, curY];
            app.PP_TowerPathR(pathIdx,:) = [xT_R, 0, curA];
            [mxL, myL, mzL, mxR, myR, mzR] = machineToModelVisual(0, curY, 0, curA);
            app.PP_PathL(pathIdx,:) = [mxL, myL, mzL]; app.PP_PathR(pathIdx,:) = [mxR, myR, mzR];

            lines(end+1) = 'G53 G0 X0 Z0 (Retract Horizontals)';
            map(end+1) = pathIdx;

            % Step 2: Retract Verticals (Y, A) to 0
            pathIdx = pathIdx + 1;
            app.PP_TowerPathL(pathIdx,:) = [xT_L, 0, 0];
            app.PP_TowerPathR(pathIdx,:) = [xT_R, 0, 0];
            [mxL, myL, mzL, mxR, myR, mzR] = machineToModelVisual(0, 0, 0, 0);
            app.PP_PathL(pathIdx,:) = [mxL, myL, mzL]; app.PP_PathR(pathIdx,:) = [mxR, myR, mzR];

            lines(end+1) = 'G53 G0 Y0 A0 (Retract Verticals)';
            map(end+1) = pathIdx;

            add('M30', 'End Program');

            % --- FINALIZE ---
            app.PP_GCodeLines = lines;
            app.PP_LineToPathIndex = map;
            app.ListGCode.Items = cellstr(lines);
            app.ListGCode.ItemsData = 1:numel(lines);
            app.ListGCode.Value = 1;

            app.BtnSaveGCode.Enable = 'on';
            app.BtnSaveGCode.BackgroundColor = [0.1 0.6 0.1];

            if isempty(app.AxSim.Children), app.initSimulationPlot(); end
            app.initPostPlot();
            app.updatePostPlotForSelectedLine(1);
        end

        function onPostLineSelected(app, src)
            % Direct index mapping (robust against duplicate G-code lines)
            val = src.Value;

            if isempty(val)
                return;
            end

            % val is already the numeric index (double) because we set ItemsData
            app.PP_SelectedLine = val;

            % Update plot
            app.updatePostPlotForSelectedLine(val);
        end

        function stepPostLine(app, delta)
            % Check if data exists
            if isempty(app.ListGCode.ItemsData)
                return;
            end

            % Get limits
            n = numel(app.ListGCode.ItemsData);

            % Determine current and next index
            cur = app.PP_SelectedLine;
            if isempty(cur) || cur < 1, cur = 1; end

            nxt = max(1, min(n, cur + delta));

            % Update State
            app.PP_SelectedLine = nxt;

            % Update UI (Pass the NUMBER, not the text)
            app.ListGCode.Value = nxt;

            % Update Plot
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
            % Check if data exists
            if isempty(app.PP_GCodeLines)
                uialert(app.UIFigure, 'No G-code generated yet. Please click "Post-Process" first.', 'Save Error');
                return;
            end

            % Mach4 typically uses .tap, .nc, or .gcode
            filter = {'*.tap', 'Mach4 G-Code (*.tap)'; ...
                '*.nc',  'Standard G-Code (*.nc)'; ...
                '*.txt', 'Text File (*.txt)'};

            % Default name from the input field
            defaultName = app.FieldFilename.Value;
            [file, path] = uiputfile(filter, 'Save Toolpath', defaultName);

            if isequal(file, 0), return; end % User cancelled

            fullPath = fullfile(path, file);

            try
                % Open file for writing (text mode)
                fid = fopen(fullPath, 'w');
                if fid == -1
                    error('Could not create file. Check permissions.');
                end

                % 1. Write Header Delimiter (Common for CNC)
                fprintf(fid, '%%\r\n');

                % 2. Write G-Code Lines with Windows Line Endings (CRLF)
                % Many CNC controllers require \r\n, not just \n
                for i = 1:numel(app.PP_GCodeLines)
                    lineStr = app.PP_GCodeLines(i);
                    fprintf(fid, '%s\r\n', lineStr);
                end

                % 3. Write Footer Delimiter
                fprintf(fid, '%%\r\n');

                fclose(fid);

                % Success Confirmation
                uialert(app.UIFigure, ['File saved successfully:' newline fullPath], 'Saved', 'Icon','success');

            catch ME
                if exist('fid', 'var') && fid > -1, fclose(fid); end
                uialert(app.UIFigure, ['Error saving file:' newline ME.message], 'File Error');
            end
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
