classdef HotWireSTEPApp_v6_2 < handle
    % ===========================================================
    % HOTWIRE CNC G-CODE GENERATOR (v6.2)
    % University of Bristol — Rapid Prototyping Workshop
    %
    % A comprehensive 4-axis CAM application for hot wire foam cutting.
    % This software provides an end-to-end workflow from 3D CAD to Mach4 G-code.
    %
    % CORE FEATURES:
    % - Import & Orient: Load STEP (via FreeCAD) or STL models. Rotate and
    %   align models, and define custom Left/Right cutting planes.
    % - Profile Extraction: Slice meshes to extract 2D profiles. Supports both
    %   straight (prismatic) and tapered (independent) cuts.
    % - Kerf & Sync: Apply coupled or independent kerf compensation. Automatically
    %   synchronizes L/R profile point counts for smooth 4-axis kinematics.
    % - Billet & Machine Setup: Auto-fit and auto-position stock material.
    %   Features independent manual locks for size and position. Validates
    %   placement against physical machine limits and bed dimensions.
    % - Cutting Strategy: Auto-calculate or manually pick Start, Lead-In, and
    %   Link points. Includes collision detection (gouging/rapid through stock).
    % - Kinematic Simulation: 3D visualizer with timeline scrubbing, live
    %   coordinate readouts, and wire extension (pulley travel) safety monitoring.
    % - Post-Processing: Generates Mach4-compatible G-code. Features dynamic
    %   feed rate scaling for tapered cuts and an interactive G-code viewer.
    %
    % ARCHITECTURE:
    % - Main App: HotWireSTEPApp_v6_2 (UI, State Machine, Plotting)
    % - Helpers: HotWireSTEPApp_v6_helpers (STEP Import, Geometry Math)
    % ===========================================================

    properties (Constant)
        %% --- PHYSICAL MACHINE LIMITS ---
        MachineSpanX   (1,1) double = 1180;            % [mm] Fixed distance between left and right towers
        MachineLimitY  (1,1) double = 750;             % [mm] Total Y-axis travel (0 to 750)
        MachineLimitZ  (1,1) double = 500;             % [mm] Total Z-axis travel (0 to 500)
        MachineBedPos  (1,3) double = [48, 50, -20];   % [mm] Physical bed origin [X, Y, Z] relative to machine zero (front bottom left)
        MachineBedSize (1,3) double = [1088, 700, 20]; % [mm] Physical 'sacrificail' bed dimensions [X, Y, Z]

        %% --- SAFETY THRESHOLDS ---
        SafetyBuffer_BedEdge   (1,1) double = 50.0;   % [mm] Distance billet is from bed edge to trigger Amber warning
        BilletRoundingY        (1,1) double = 10.0;   % [mm] Rounding grid increment for billet auto-placement
        BilletMinYBuffer       (1,1) double = 50.0;   % [mm] Min billet Y position (match distance from home to front of sacrificial bed)
        ModelContainmentTol    (1,1) double = 0.0001; % [mm] Max allowable numerical rounding error for 'Red' collision checks
        ModelEdgeWarningBuffer (1,1) double = 3.0;    % [mm] Buffer for model "Too Close" to billet edge Warning (Amber)
        MaxWasteBuffer         (1,1) double = 24.0;   % [mm] Allowable extra slack before "Waste" Warning on billet size
        ModelXPlacementBuffer  (1,1) double = 0.001;  % [mm] Tiny offset used in Auto-Position to avoid mathematical edge-case errors
        WireExt_Amber          (1,1) double = 25.0;   % [mm] Trigger warning for pulley travel extension
        WireExt_Red            (1,1) double = 40.0;   % [mm] Hardware limit for pulley extension / Block save
        MachineSafeHeight      (1,1) double = 50.0;   % [mm] Z-clearance above billet for auto rapid Link points

        %% --- ALGORITHM SETTINGS ---
        DefaultProfileTolerance (1,1) double = 0.04;  % [mm] Max error for profile resampling
        MinProfileTolerance     (1,1) double = 0.01;  % [mm] Highest precision allowed for resampling
        MaxProfileTolerance     (1,1) double = 4.0;   % [mm] Lowest precision allowed for resampling
        DefaultKerf             (1,1) double = 1.0;   % [mm] Default wire thickness compensation
        MinKerf                 (1,1) double = -4.0;  % [mm] Minimum allowed kerf (negative allows expansion)
        MaxKerf                 (1,1) double = 4.0;   % [mm] Maximum allowed kerf
        SimFramesPerSecond      (1,1) double = 25.0;  % [Hz] Redraw rate for the 3D simulation plot
        SimSpatialResolution    (1,1) double = 0.5;   % [mm] Distance between interpolated path points in simulation

        %% --- UI DEFAULTS ---
        AutoFitPaddingFactor (1,1) double = 0.35; % Padding factor around model in 3D view
        PlanePaddingFactor   (1,1) double = 0.20; % Padding factor for cutting planes visualization
        BilletSizeStep       (1,1) double = 1.0;  % [mm] Step size for Billet Size +/- buttons
        BilletShiftStep      (1,1) double = 0.5;  % [mm] Step size for Position +/- buttons
        DefaultFeedRate      (1,1) double = 40.0; % [mm/min] Default feed rate
        DefaultPower         (1,1) double = 35.0; % [%] Default power as % for PWM machine output.
        %% --- UI LAYOUT CONSTANTS ---
        PanelWidth       (1,1) double = 320;  % [px] Standard width for left-hand control panels
        ButtonHeight     (1,1) double = 26;   % [px] Standard height for action buttons
        RowHeightNormal  (1,1) double = 26;   % [px] Standard row height for inputs/spinners
    end

    properties
        %% --- UI HANDLES: GLOBAL ---
        UIFigure  % Main application window figure
        TabGroup  % Main tab group container holding all workflow tabs

        %% --- UI HANDLES: WELCOME TAB ---
        TabWelcome       % Welcome tab container
        GLWelcome        % Grid layout for Welcome tab
        FieldFreeCADPath % Edit field for FreeCAD executable path
        BtnBrowseFreeCAD % Button to browse for FreeCAD executable
        ThemeSwitch      % Switch to toggle between Light and Dark themes
        ImgWelcomeLogo   % Image component for the application logo

        %% --- UI HANDLES: GUIDE TAB ---
        TabGuide         % Interface Guide tab container
        GLGuide          % Grid layout for Guide tab
        %% --- UI HANDLES: MODEL TAB ---
        TabModel            % Model import and orientation tab container
        GLModel             % Grid layout for Model tab
        GLLeft              % Left control panel grid for Model tab
        AxModel             % 3D axes for visualizing the imported model
        BtnImportSTEP       % Button to import STEP files
        BtnImportSTL        % Button to import STL files
        FileLabel           % Label displaying the currently loaded filename
        TaperToggle         % Switch to toggle between Straight and Tapered cut modes
        RotGrid             % Grid layout for rotation controls
        RotEdit = gobjects(1,3) % Array of 3 edit fields for X, Y, Z rotation angles
        BtnResetOrientation % Button to reset model rotation to original state
        BtnResetPlot        % Button to reset the 3D plot camera view
        NumLeftOffset       % Spinner for left cutting plane offset
        NumRightOffset      % Spinner for right cutting plane offset
        BtnResetPlanes      % Button to reset cutting planes to model extents
        TxtModelGuide       % Text area for Model tab user guidance
        TxtModelStatus      % Text area for Model tab status feedback
        BtnGenerateProfiles % Button to execute profile extraction
        BtnContinue         % Button to proceed to the Profiles tab

        %% --- UI HANDLES: PROFILES TAB ---
        TabProfiles            % Profiles tab container
        GLProfiles             % Grid layout for Profiles tab
        profilesLeft           % Left control panel grid for Profiles tab
        AxLeftProfile          % 2D axes for left profile visualization
        AxRightProfile         % 2D axes for right profile visualization
        ProfileTolSpinner      % Spinner for profile resampling tolerance
        ProfilePointCountLabel % Label displaying the number of points in extracted profiles
        BtnResetProfileTol     % Button to reset tolerance to default
        BtnResetProfilesView   % Button to reset 2D profile plot views
        KerfModeSwitch         % Switch to toggle Coupled/Independent kerf modes
        KerfLeftSpinner        % Spinner for left profile kerf value
        KerfRightSpinner       % Spinner for right profile kerf value
        KerfPointCountLabel    % Label displaying point count after kerf application
        BtnApplyKerf           % Button to apply kerf offset to profiles
        TxtProfileGuide        % Text area for Profiles tab user guidance
        TxtProfileStatus       % Text area for Profiles tab status feedback
        BtnProfilesContinue    % Button to proceed to the Billet tab

        %% --- UI HANDLES: BILLET TAB ---
        TabBillet               % Billet tab container
        GLBillet                % Grid layout for Billet tab
        BilletLeftPanel         % Left control panel grid for Billet tab
        BilletRightPanel        % Right panel grid holding the 4 Billet views
        AxBilletTop             % 2D axes for Billet Top view (X/Y)
        AxBilletFront           % 2D axes for Billet Front view (X/Z)
        AxBilletRight           % 2D axes for Billet Right view (Y/Z)
        AxBilletIso             % 3D axes for Billet Isometric view
        BtnAutoFitBillet        % Button to automatically size billet to model
        BtnAutoPositionModel    % Button to automatically position model within billet
        BtnResetPosition        % Button to reset model position to origin
        BilletSizeEdits         = gobjects(1,3) % Array of 3 edit fields for Billet dimensions (X,Y,Z)
        BilletSizeMinusBtns     = gobjects(1,3) % Array of 3 buttons to decrease Billet dimensions
        BilletSizePlusBtns      = gobjects(1,3) % Array of 3 buttons to increase Billet dimensions
        BilletModelDimLabels    = gobjects(1,3) % Array of 3 labels showing model dimensions
        BilletNegOffsetEdits    = gobjects(1,3) % Array of 3 edit fields for negative gap offsets
        BilletCenterOffsetEdits = gobjects(1,3) % Array of 3 edit fields for center shift offsets
        BilletPosOffsetEdits    = gobjects(1,3) % Array of 3 edit fields for positive gap offsets
        TxtBilletGuide          % Text area for Billet tab user guidance
        TxtBilletStatus         % Text area for Billet tab status feedback
        BtnBilletContinue       % Button to proceed to the Machine tab

        %% --- UI HANDLES: MACHINE TAB ---
        TabMachine         % Machine tab container
        GLMachine          % Grid layout for Machine tab
        MachineLeftPanel   % Left control panel grid for Machine tab
        AxMachine          % 3D axes for visualizing machine bed and towers
        MachinePosSpinners = gobjects(1,3) % Array of 3 spinners for Billet position on machine bed
        TxtMachineGuide    % Text area for Machine tab user guidance
        TxtMachineStatus   % Text area for Machine tab status feedback
        BtnMachineContinue % Button to proceed to the Cutting Strategy tab

        %% --- UI HANDLES: CUTTING STRATEGY TAB ---
        TabCutting         % Cutting Strategy tab container
        GLCutting          % Grid layout for Cutting Strategy tab
        CuttingLeftPanel   % Left control panel grid for Cutting Strategy tab
        AxCutLeft          % 2D axes for left cut path visualization
        AxCutRight         % 2D axes for right cut path visualization
        SwitchCutDir       % Switch to toggle cut direction (CW/CCW)
        SwitchSyncStart    % Switch to toggle Coupled/Independent start points
        SwitchSyncEntry    % Switch to toggle Coupled/Independent entry points
        BtnPickStart       % Toggle button to pick start point on plot
        BtnPickEntry       % Toggle button to pick lead-in point on plot
        BtnPickEntry2      % Toggle button to pick first link point on plot
        BtnPickEntry3      % Toggle button to pick second link point on plot
        btnAutoStart       % Button to auto-calculate start points
        btnAutoEntry       % Button to auto-calculate entry points
        TxtCuttingGuide    % Text area for Cutting Strategy tab user guidance
        TxtCuttingStatus   % Text area for Cutting Strategy tab status feedback
        BtnCuttingContinue % Button to proceed to the Simulation tab

        %% --- UI HANDLES: SIMULATION TAB ---
        TabSimulation   % Simulation tab container
        GLSimulation    % Grid layout for Simulation tab
        SimLeftPanel    % Left control panel grid for Simulation tab
        AxSim           % 3D axes for kinematics simulation
        SimPlayBtn      % Button to play simulation
        SimStopBtn      % Button to stop/reset simulation
        SimSlider       % Slider to scrub through simulation timeline
        SimIndexSpinner % Spinner to select specific simulation index
        SimSpeedSpinner % Spinner to adjust simulation playback speed multiplier
        LblBaseFeed     % Label displaying the base feed rate
        LblReadoutX     % Label displaying live X coordinate
        LblReadoutY     % Label displaying live Y coordinate
        LblReadoutZ     % Label displaying live Z coordinate
        LblReadoutA     % Label displaying live A coordinate
        SimGaugeExt     % Gauge displaying live wire extension
        LblSimExtMin  = gobjects(1,1) % Label displaying minimum program extents
        LblSimExtMax  = gobjects(1,1) % Label displaying maximum program extents
        LblSimExtWire = gobjects(1,1) % Label displaying maximum wire extension
        BtnSimContinue  % Button to proceed to the Post-Process tab

        %% --- UI HANDLES: POST-PROCESS TAB ---
        TabPostProcess % Post-Process tab container
        GLPostProcess  % Grid layout for Post-Process tab
        PostLeftPanel  % Left control panel grid for Post-Process tab
        AxPost         % 3D axes for G-code verification visualization
        ChkDynamicFeed % Checkbox to enable dynamic feed rate scaling
        SpinFeedRate   % Spinner to set base feed rate
        SpinPower      % Spinner to set hot wire power percentage
        FieldFilename  % Edit field for output G-code filename
        BtnPostProcess % Button to generate G-code
        PanelGCode     % Panel containing the G-code viewer
        GridGCode      % Grid layout for G-code viewer
        ListGCode      % Listbox displaying generated G-code lines
        BtnGCodePrev   % Button to step to previous G-code line
        BtnGCodeNext   % Button to step to next G-code line
        TxtPostGuide   % Text area for Post-Process tab user guidance
        TxtPostStatus  % Text area for Post-Process tab status feedback
        BtnSaveGCode   % Button to save generated G-code to file

        %% --- GEOMETRIC STATE: MODEL & PROFILES ---
        CurrentModelName string = "" % Filename of the currently loaded model
        FreeCADExe       string = "" % Path to the FreeCAD executable
        GitHubLink       string = "https://github.com/YourUsername/HotWireSTEPApp" % Link to project repository

        ModelPatch            % Patch object representing the 3D model mesh
        ModelVerticesOriginal % Original vertices of the model (used for resets)
        ModelF                % Faces array of the current model
        RotAngles double = [0 0 0] % Current rotation angles [X, Y, Z]

        ModelXMin double; ModelXMax double % Model bounding box X limits
        ModelYMin double; ModelYMax double % Model bounding box Y limits
        ModelZMin double; ModelZMax double % Model bounding box Z limits

        LeftPlanePatch; RightPlanePatch % Patch objects for the 3D cutting planes
        LeftPlaneText;  RightPlaneText  % Text labels for the 3D cutting planes

        ProfileTolerance  (1,1) double = 0.2 % Current tolerance for profile resampling
        ProfileAxesLocked (1,1) logical = false % Flag to prevent auto-zooming on Profile tab

        LeftProfileLine3D;  RightProfileLine3D % 3D line objects for extracted profiles
        LeftProfilePoints;  RightProfilePoints % Nx3 array of extracted profile points[X, Y, Z]
        LeftProfileRawYZ;   RightProfileRawYZ  % Raw mesh slice data before loop reconstruction

        LeftProfile2DLine;     RightProfile2DLine     % 2D line objects for resampled profiles
        LeftProfile2DMeshLine; RightProfile2DMeshLine % 2D line objects for raw mesh slices

        KerfEnabled    (1,1) logical = false % Flag indicating if kerf is currently applied
        KerfValue      (1,1) double = 0.5    % Global kerf value (used when coupled)
        KerfLeftValue  (1,1) double = HotWireSTEPApp_v6_2.DefaultKerf % Independent left kerf value
        KerfRightValue (1,1) double = HotWireSTEPApp_v6_2.DefaultKerf % Independent right kerf value
        LeftKerf2DLine; RightKerf2DLine      % 2D line objects for kerf-offset paths

        %% --- MACHINE & BILLET STATE ---
        BilletSize  double =[0 0 0] % Current billet dimensions [Length, Width, Height]
        BilletShift double =[0 0 0] % Current model shift within the billet [dX, dY, dZ]
        BilletRefXMin double; BilletRefYMin double; BilletRefZMin double % Reference bounds for import position

        MachineBilletPos double = [100, 50, 0] % Billet origin relative to machine zero [X, Y, Z]

        SelectedStartIdxL double = 1 % Index of the selected start point on the left profile
        SelectedStartIdxR double = 1 % Index of the selected start point on the right profile
        EntryPointL;  EntryPointR    % Coordinates of the Lead-In points
        EntryPoint2L; EntryPoint2R   % Coordinates of the first Link points
        EntryPoint3L; EntryPoint3R   % Coordinates of the second Link points

        MaxPathExtension double = 0 % Maximum calculated wire extension during cut
        TowerL_Bounds double = [0 0 0 0] % Left tower path bounds[MinY, MaxY, MinZ, MaxZ]
        TowerR_Bounds double =[0 0 0 0] % Right tower path bounds [MinY, MaxY, MinZ, MaxZ]

        SimPathL; SimPathR           % Interpolated simulation paths in machine coordinates
        SimTowerPathL; SimTowerPathR % Interpolated simulation paths projected to towers
        SimArcLenL; SimArcLenR       % Cumulative arc lengths for simulation timing
        SimTotalLength double        % Total length of the longest simulation path
        SimPlayDist double = 0       % Current playback distance along the path
        SimStepDist double = 0.5     % Base distance step per simulation tick
        SimTimer                     % Timer object for simulation playback

        ProfileSyncL; ProfileSyncR   % Final synchronized profile points (Truth data)
        SimRapidCutoffIndex double   % Index where rapid moves end and lead-in begins
        SimProfileStartIndex double  % Index where lead-in ends and profile cut begins
        SimFeedEndIndex double       % Index where profile cut ends and lead-out begins
        SimLeadOutEndIndex double    % Index where lead-out ends and return begins

        PP_GCodeLines string = string.empty(0,1) % Array of generated G-code strings
        PP_LineToPathIndex double =[]            % Mapping from G-code line to simulation path index
        PP_SelectedLine (1,1) double = 1         % Currently selected line in the G-code viewer
        PP_PathL; PP_PathR                       % Post-process verification paths (Model)
        PP_TowerPathL; PP_TowerPathR             % Post-process verification paths (Towers)
        PP_RapidEndIndex double                  % Post-process index for rapid end
        PP_ProfileStartIndex double              % Post-process index for profile start
        PP_ProfileEndIndex double                % Post-process index for profile end
        PP_LeadOutEndIndex double                % Post-process index for lead-out end

        %% --- PERSISTENCE & TRACKING FLAGS ---
        AppState (1,1) double = 0              % Current app state (0=Model Only, 1=Active Cutting)
        IsDragging logical = false             % Flag indicating if 3D view is being dragged
        LastMousePos (1,2) double = [NaN NaN]  % Last recorded mouse position during drag

        IsBilletUserModified    (1,1) logical = false % Flag if user manually locked billet size
        IsBilletPosUserModified (1,1) logical = false % Flag if user manually locked billet position
        BilletViewMode          string = "Billet"     % Current view mode on Billet tab ("Billet" or "Model")

        IsMachineInit         (1,1) logical = false % Flag if machine tab has been initialized
        IsMachineUserModified (1,1) logical = false % Flag if user manually locked machine position

        IsCuttingInit         (1,1) logical = false % Flag if cutting strategy has been initialized
        IsCuttingUserModified (1,1) logical = false % Flag if user manually locked cutting strategy

        DefaultXLim; DefaultYLim; DefaultZLim             % Stored default X/Y/Z limits for 3D view reset
        DefaultDataAspectRatio; DefaultPlotBoxAspectRatio % Stored default aspect ratios for 3D view reset
        DefaultCameraPosition; DefaultCameraTarget        % Stored default camera position/target for 3D view reset
        DefaultCameraUpVector; DefaultCameraViewAngle     % Stored default camera up vector/angle for 3D view reset
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
            % try
            %     testFile = "C:\Users\ce20323\OneDrive - University of Bristol\Documents\MATLAB\CNCHotWire_GCode_App\examples\RibTemplate_NewCNCTest1.step";
            %
            %     if isfile(testFile)
            %         disp("DEV AUTOLOAD: Loading test STEP model...");
            %
            %         % --- Use the existing helper to import STEP via FreeCAD ---
            %         [V,F] = HotWireSTEPApp_v6_helpers.importSTEP_FreeCAD( ...
            %             testFile, app.FreeCADExe);
            %
            %         if isempty(V)
            %             warning("DEV AUTOLOAD: STEP import returned empty data.");
            %         else
            %             % Store original vertices for rotation resets
            %             app.ModelVerticesOriginal = V;
            %             app.CurrentModelName      = "AUTOLOADED: RibTemplate_NewCNCTest1.step";
            %
            %             % Reset orientation
            %             app.RotAngles = [0 0 0];
            %             for i = 1:3
            %                 app.RotEdit(i).Value = 0;
            %             end
            %
            %             % Reset plane offsets
            %             app.NumLeftOffset.Value  = 0;
            %             app.NumRightOffset.Value = 0;
            %
            %             % --- Plot mesh and planes ---
            %             app.plotMesh(V,F);
            %             app.enterState0();
            %
            %             disp("DEV AUTOLOAD: Completed.");
            %         end
            %     else
            %         warning("DEV AUTOLOAD: File not found:\n%s", testFile);
            %     end
            %
            % catch ME
            %     warning('DEV_AUTOLOAD:Error','%s', ME.message);
            % end
        end

        % ===========================================================
        % BUILD UI (Modular Construction)
        % ===========================================================
        function buildUI(app)
            % Purpose: Main entry point for constructing the user interface.
            % Note: To prevent this function from becoming a monolithic, unreadable 
            % block of code, the actual construction of each tab is delegated to 
            % private methods located at the bottom of this class (e.g., createWelcomeTab).
            % This prevents variable shadowing and allows code folding.

            %% --- MAIN WINDOW SETUP ---
            app.UIFigure = uifigure('Name','Hot Wire STEP App v6.2');
            app.UIFigure.CloseRequestFcn = @(src,event)app.onAppClose(src);
            app.UIFigure.WindowState = 'maximized';
            app.UIFigure.WindowKeyPressFcn = @(src,event)app.onKeyPress(src,event); %key press on post tab to scroll code

            % --- Theme & Colors ---
            t = app.getTheme();
            sideBg   = t.sideBg;
            panelBg  = t.panelBg;
            labelCol = t.labelCol;
            inputBg  = t.inputBg;
            inputTxt = t.inputTxt;

            app.UIFigure.Color = sideBg;

            %% --- Tab Group Container ---
            app.TabGroup = uitabgroup(app.UIFigure, ...
                'Units','normalized', ...
                'Position',[0 0 1 1], ...
                'SelectionChangedFcn', @(src,evt)app.onTabChanged(src,evt));

            %% --- Tab Builders ---
            app.createWelcomeTab();     % TAB 0: WELCOME & SETUP
            app.createGuideTab();       % TAB 1: INTERFACE GUIDE
            app.createModelTab();       % TAB 2: MODEL IMPORT & ORIENTATION
            app.createProfilesTab();    % TAB 3: PROFILES
            app.createBilletTab();      % TAB 4: BILLET CONFIGURATION
            app.createMachineTab();     % TAB 5: MACHINE SETUP
            app.createCuttingTab();     % TAB 6: CUTTING STRATEGY
            app.createSimulationTab();  % TAB 7: SIMULATION
            app.createPostProcessTab(); % TAB 8: POST-PROCESS

            %% --- Set Initial State and Theme ---
            
            app.onTaperModeChanged();   % Force initial UI state sync
            
            app.applyTheme();           % Sweeps the UI on startup to replace any hardcoded colors with the active theme.
        end

        % ===========================================================
        % STATE & PROFILE HELPERS
        % ===========================================================
        function[isValid, panelCol, textCol, msgLines] = checkMachineState(app)
            bPos  = app.MachineBilletPos;
            bSize = app.BilletSize;
            bMin = bPos;
            bMax = bPos + bSize;
            bedMin = app.MachineBedPos;
            bedMax = app.MachineBedPos + app.MachineBedSize;
            limZ = [0, app.MachineLimitZ];

            t = app.getTheme(); % <--- Master Palette

            crit = strings(0);
            if bMin(1) < bedMin(1) - 0.1 || bMax(1) > bedMax(1) + 0.1, crit(end+1) = "Billet overhangs Bed (X)."; end
            if bMin(2) < bedMin(2) - 0.1 || bMax(2) > bedMax(2) + 0.1, crit(end+1) = "Billet overhangs Bed (Y)."; end
            if bMin(3) < 0 - 0.1, crit(end+1) = "Billet below bed surface (Z < 0)."; end
            if bMax(3) > limZ(2) + 0.1, crit(end+1) = "Billet exceeds max Z travel."; end

            if ~isempty(crit)
                isValid = false;
                panelCol = t.statErrBg;
                textCol = t.statErrTxt;
                msgLines = ["CRITICAL ERROR:"; crit'];
                return;
            end

            warn = strings(0);
            buf = app.SafetyBuffer_BedEdge;

            if (bMin(1) - bedMin(1) < buf), warn(end+1) = sprintf("Close to Left bed edge (<%.0fmm).", buf); end
            if (bedMax(1) - bMax(1) < buf)
                warn(end+1) = sprintf("Close to Right bed edge (<%.0fmm).", buf);
                if strcmp(app.TaperToggle.Value, 'Tapered')
                    warn(end+1) = "TAPER WARNING: Brass wire fixture may hit right tower.";
                end
            end
            if (bedMax(2) - bMax(2) < buf), warn(end+1) = sprintf("Close to Back bed edge (<%.0fmm).", buf); end

            if ~isempty(warn)
                isValid = true;
                panelCol = t.statWarnBg;
                textCol = t.statWarnTxt;
                msgLines =["Warning: Proximity to bed edge."; warn'];
            else
                isValid = true;
                panelCol = t.statPassBg;
                textCol = t.statPassTxt;
                msgLines =["Machine configuration valid.", "Ready to proceed."];
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

            app.clearProfiles(); app.clearProfiles2D();
            app.SelectedStartIdxL = 1; app.SelectedStartIdxR = 1;

            V = app.ModelPatch.Vertices;
            F = app.ModelPatch.Faces;
            spanX = max(V(:,1)) - min(V(:,1));
            epsX = 1e-6 * max(spanX, 1);

            xLeft  = app.ModelXMin + app.NumLeftOffset.Value;
            xRight = app.ModelXMin + app.NumRightOffset.Value;

            % Left Extraction
            meshL = cell(1,3);
            [meshL{1}, meshL{2}, meshL{3}] = HotWireSTEPApp_v6_helpers.sliceMeshAtX(V, F, xLeft + epsX);
            xsL = meshL{1}; ysL = meshL{2}; zsL = meshL{3};

            if ~isempty(ysL) && any(~isnan(ysL)), app.LeftProfileRawYZ = [ysL(:), zsL(:)]; end

            loopL = cell(1,2);
            [loopL{1}, loopL{2}] = HotWireSTEPApp_v6_helpers.buildMainProfileLoop(xsL, ysL, zsL);
            yLoopL = loopL{1}; zLoopL = loopL{2};

            % Right Extraction
            yLoopR =[]; zLoopR = [];
            if isTaper
                meshR = cell(1,3);
                [meshR{1}, meshR{2}, meshR{3}] = HotWireSTEPApp_v6_helpers.sliceMeshAtX(V, F, xRight - epsX);
                xsR = meshR{1}; ysR = meshR{2}; zsR = meshR{3};

                if ~isempty(ysR) && any(~isnan(ysR)), app.RightProfileRawYZ =[ysR(:), zsR(:)]; end

                loopR = cell(1,2);
                [loopR{1}, loopR{2}] = HotWireSTEPApp_v6_helpers.buildMainProfileLoop(xsR, ysR, zsR);
                yLoopR = loopR{1}; zLoopR = loopR{2};
            else
                yLoopR = yLoopL; zLoopR = zLoopL;
                app.RightProfileRawYZ = app.LeftProfileRawYZ;
            end

            % Resampling
            if ~isempty(yLoopL) && ~isempty(yLoopR)
                resmp = cell(1,4);
                [resmp{1}, resmp{2}, resmp{3}, resmp{4}] = HotWireSTEPApp_v6_helpers.resampleProfilesSynced(...
                    yLoopL, zLoopL, yLoopR, zLoopR, app.ProfileTolerance);
                yLoopL = resmp{1}; zLoopL = resmp{2}; yLoopR = resmp{3}; zLoopR = resmp{4};
            end

            % Storage
            if ~isempty(yLoopL)
                xVecL = xLeft * ones(numel(yLoopL),1);
                app.LeftProfileLine3D = plot3(app.AxModel, xVecL, yLoopL, zLoopL, 'Color', t.planeRed, 'LineWidth', 1.4);
                app.LeftProfilePoints =[xVecL, yLoopL, zLoopL];
            else
                app.LeftProfilePoints =[];
            end

            if ~isempty(yLoopR)
                xVecR = xRight * ones(numel(yLoopR),1);
                app.RightProfileLine3D = plot3(app.AxModel, xVecR, yLoopR, zLoopR, 'Color', t.planeGreen, 'LineWidth', 1.4);
                app.RightProfilePoints = [xVecR, yLoopR, zLoopR];
            else
                app.RightProfilePoints =[];
            end

            nL = size(app.LeftProfilePoints,1);
            nR = size(app.RightProfilePoints,1);

            if ~isempty(app.ProfilePointCountLabel) && isgraphics(app.ProfilePointCountLabel)
                app.ProfilePointCountLabel.Text = sprintf('Number of Points (L/R): %d / %d', nL, nR);
            end

            app.updateProfiles2D(yLoopL, zLoopL, yLoopR, zLoopR, xLeft, xRight);

            t = app.getTheme(); % Fetch theme
            if ~isempty(yLoopL)
                app.TxtProfileStatus.Value = {
                    sprintf('Profiles extracted.');
                    sprintf('Left: %d pts', numel(yLoopL));
                    sprintf('Right: %d pts', numel(yLoopR));
                    'Ready to apply Kerf.'
                    };
                app.TxtProfileStatus.FontColor = t.labelCol; % <--- FIX: Neutral text before kerf is applied
            else
                app.TxtProfileStatus.Value = {'Extraction failed.', 'Check model position.'};
                app.TxtProfileStatus.FontColor = t.statErrTxt; % <--- FIX
            end

            drawnow limitrate nocallbacks;

        end

        function updateProfiles2D(app, yL, zL, yR, zR, xLeft, xRight)
            % Draw 2D Y–Z profiles on the Profiles tab with shared scaling.

            if isempty(app.AxLeftProfile) || ~isgraphics(app.AxLeftProfile) || isempty(app.AxRightProfile) || ~isgraphics(app.AxRightProfile)
                return;
            end

            if isempty(yL) && isempty(yR)
                return;
            end

            % Axis limits
            yAll = [yL(:); yR(:)];
            zAll = [zL(:); zR(:)];
            if isempty(yAll) || isempty(zAll)
                return;
            end

            yMin = min(yAll); yMax = max(yAll);
            zMin = min(zAll); zMax = max(zAll);
            dy = max(yMax - yMin, 1); dz = max(zMax - zMin, 1);
            padY = 0.1 * dy; padZ = 0.1 * dz;
            yLim = [yMin - padY, yMax + padY];
            zLim =[zMin - padZ, zMax + padZ];

            t = app.getTheme();
            app.clearProfiles2D();

            % --- 1. DETERMINE FINAL PROFILES (Raw or Kerfed) ---
            final_yL = yL;
            final_zL = zL;
            final_yR = yR;
            final_zR = zR;

            doKerfL = app.KerfEnabled && ~isempty(yL) && app.KerfLeftValue ~= 0;
            doKerfR = app.KerfEnabled && ~isempty(yR) && app.KerfRightValue ~= 0;

            if doKerfL
                [final_yL, final_zL] = HotWireSTEPApp_v6_helpers.offsetProfileLoop(yL, zL, app.KerfLeftValue, app.ProfileTolerance);
            end

            if doKerfR[final_yR, final_zR] = HotWireSTEPApp_v6_helpers.offsetProfileLoop(yR, zR, app.KerfRightValue, app.ProfileTolerance);
            end

            % --- 2. SYNC POINT COUNTS UNIVERSALLY ---
            % Always sync the final shapes so the UI exactly matches the Simulation.
            if ~isempty(final_yL) && ~isempty(final_yR)
                [final_yL, final_zL, final_yR, final_zR] = HotWireSTEPApp_v6_helpers.syncPointCounts(final_yL, final_zL, final_yR, final_zR);
            end

            nLk = numel(final_yL);
            nRk = numel(final_yR);

            % --- 3. DRAW PLOTS ---
            % LEFT
            hold(app.AxLeftProfile,'on');
            if ~isempty(app.LeftProfileRawYZ)
                rawL = app.LeftProfileRawYZ;
                app.LeftProfile2DMeshLine = plot(app.AxLeftProfile, rawL(:,1), rawL(:,2), 'Color', t.rawMeshCol, 'LineStyle',':', 'LineWidth',2.5);
            end
            if ~isempty(yL)
                app.LeftProfile2DLine = plot(app.AxLeftProfile, yL, zL, 'Color', t.planeRed, 'LineWidth',0.75);
            end
            if doKerfL && ~isempty(final_yL)
                app.LeftKerf2DLine = plot(app.AxLeftProfile, final_yL, final_zL, 'Color', t.wireKerf, 'LineWidth',0.75);
            end
            hold(app.AxLeftProfile,'off');

            % RIGHT
            hold(app.AxRightProfile,'on');
            if ~isempty(app.RightProfileRawYZ)
                rawR = app.RightProfileRawYZ;
                app.RightProfile2DMeshLine = plot(app.AxRightProfile, rawR(:,1), rawR(:,2), 'Color', t.rawMeshCol, 'LineStyle',':', 'LineWidth',2.5);
            end
            if ~isempty(yR)
                app.RightProfile2DLine = plot(app.AxRightProfile, yR, zR, 'Color', t.planeGreen, 'LineWidth',0.75);
            end
            if doKerfR && ~isempty(final_yR)
                app.RightKerf2DLine = plot(app.AxRightProfile, final_yR, final_zR, 'Color', t.wireKerf, 'LineWidth',0.75);
            end
            hold(app.AxRightProfile,'off');

            % --- 4. UPDATE LABEL ---
            if app.KerfEnabled && ~isempty(app.KerfPointCountLabel) && all(isgraphics(app.KerfPointCountLabel))
                app.KerfPointCountLabel.Text = sprintf('Number of Points (L/R): %d / %d', nLk, nRk);
            end

            % ----- LEGENDS & VIEW -----
            hL = gobjects(0); txtL = {};
            if isgraphics(app.LeftProfile2DMeshLine), hL(end+1)=app.LeftProfile2DMeshLine; txtL{end+1}='Model mesh slice'; end
            if isgraphics(app.LeftProfile2DLine), hL(end+1)=app.LeftProfile2DLine; txtL{end+1}='Extracted profile'; end
            if isgraphics(app.LeftKerf2DLine), hL(end+1)=app.LeftKerf2DLine; txtL{end+1}='Kerf path'; end
            if ~isempty(hL), l=legend(app.AxLeftProfile, hL, txtL, 'Location','northeast'); l.Box='off'; end

            hR = gobjects(0); txtR = {};
            if isgraphics(app.RightProfile2DMeshLine), hR(end+1)=app.RightProfile2DMeshLine; txtR{end+1}='Model mesh slice'; end
            if isgraphics(app.RightProfile2DLine), hR(end+1)=app.RightProfile2DLine; txtR{end+1}='Extracted profile'; end
            if isgraphics(app.RightKerf2DLine), hR(end+1)=app.RightKerf2DLine; txtR{end+1}='Kerf path'; end
            if ~isempty(hR), l=legend(app.AxRightProfile, hR, txtR, 'Location','northeast'); l.Box='off'; end

            if ~app.ProfileAxesLocked
                xlim(app.AxLeftProfile, yLim); ylim(app.AxLeftProfile, zLim);
                xlim(app.AxRightProfile, yLim); ylim(app.AxRightProfile, zLim);
            end
            daspect(app.AxLeftProfile, [1 1 1]);
            daspect(app.AxRightProfile,[1 1 1]);

            title(app.AxLeftProfile,  sprintf('Left Profile  (X offset = %.2f mm)', app.NumLeftOffset.Value));
            title(app.AxRightProfile, sprintf('Right Profile (X offset = %.2f mm)', app.NumRightOffset.Value));
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
            % 1. UI LOGIC (Always run this, regardless of model state)
            isTaper = strcmp(app.TaperToggle.Value, 'Tapered');

            if ~isTaper
                % Straight Mode: Must be Coupled Kerf and NO Dynamic Feed
                if isprop(app, 'KerfModeSwitch') && ~isempty(app.KerfModeSwitch) && isgraphics(app.KerfModeSwitch)
                    app.KerfModeSwitch.Value = 'Coupled';
                    app.onKerfModeChanged(app.KerfModeSwitch);
                    app.KerfModeSwitch.Enable = 'off';
                end
                if isprop(app, 'ChkDynamicFeed') && ~isempty(app.ChkDynamicFeed) && isgraphics(app.ChkDynamicFeed)
                    app.ChkDynamicFeed.Value = false;
                    app.ChkDynamicFeed.Enable = 'off';
                end
            else
                % Taper Mode: Allow Independent choice
                if isprop(app, 'KerfModeSwitch') && ~isempty(app.KerfModeSwitch) && isgraphics(app.KerfModeSwitch)
                    app.KerfModeSwitch.Enable = 'on';
                end
                if isprop(app, 'ChkDynamicFeed') && ~isempty(app.ChkDynamicFeed) && isgraphics(app.ChkDynamicFeed)
                    app.ChkDynamicFeed.Enable = 'on';
                end
            end

            % 2. CALCULATION LOGIC (Only if model exists)
            if isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch)
                return;
            end

            % Re-run planes + profiles under the new taper mode
            app.invalidateKerf();
            app.updatePlanes();
        end

        % ===========================================================
        % TAB CHANGE HANDLER
        % ===========================================================
        function onTabChanged(app, ~, evt)
            % DEBUG: Trace the lock state on every tab click
            fprintf('--- TAB CHANGE: To %s | ManualLock is currently: %d ---\n', evt.NewValue.Title, app.IsBilletUserModified);
            targetTab = evt.NewValue;
            oldTab    = evt.OldValue;

            % Safely check tab equivalence (handles uninitialized tabs during dev/testing)
            isWelcome  = isequal(targetTab, app.TabWelcome);
            isGuide    = isequal(targetTab, app.TabGuide);
            isModel    = isequal(targetTab, app.TabModel);
            isProfiles = isequal(targetTab, app.TabProfiles);
            isBillet   = isequal(targetTab, app.TabBillet);
            isMachine  = isequal(targetTab, app.TabMachine);
            isCutting  = isequal(targetTab, app.TabCutting);
            isSim      = isequal(targetTab, app.TabSimulation);
            isPost     = isequal(targetTab, app.TabPostProcess);

            needsProfiles = ~isModel && ~isGuide && ~isWelcome;
            needsKerf     = isBillet || isMachine || isCutting || isSim || isPost;
            needsBillet   = isBillet || isMachine || isCutting || isSim || isPost;
            needsMachine  = isMachine || isCutting || isSim || isPost;
            needsCutting  = isCutting || isSim || isPost;

            forceAuto = false;

            % --- LEVEL 1: MODEL ---
            hasModel = ~isempty(app.ModelPatch) && isgraphics(app.ModelPatch);
            % Fix: Only block if moving forward and model is missing
            if needsProfiles && ~hasModel
                app.TabGroup.SelectedTab = app.TabWelcome;
                uialert(app.UIFigure, 'Please load a 3D Model first.', 'Step 1 Missing', 'Icon','warning');
                return;
            end

            % --- LEVEL 2: PROFILES & KERF ---
            hasProfiles = ~isempty(app.LeftProfilePoints) || ~isempty(app.RightProfilePoints);
            hasKerf = app.KerfEnabled;
            missingProfiles = needsProfiles && ~hasProfiles;
            missingKerf     = needsKerf && ~hasKerf;

            if missingProfiles || missingKerf
                if ~forceAuto
                    if missingProfiles
                        manTab = app.TabModel;
                        msg = 'The cutting profiles have not been generated yet.';
                    else
                        manTab = app.TabProfiles;
                        msg = 'Kerf compensation has not been applied.';
                    end

                    sel = uiconfirm(app.UIFigure, ...
                        sprintf('You skipped a step! %s\n\nIt is highly recommended to do this manually.\n\nAlternatively, the app can auto-configure all missing steps up to the %s tab.', msg, targetTab.Title), ...
                        'Step Skipped', ...
                        'Options', {'Go to Manual Step', 'Auto-Configure All', 'Cancel'}, ...
                        'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'warning');

                    if strcmp(sel, 'Go to Manual Step')
                        app.TabGroup.SelectedTab = manTab;
                        return;
                    elseif strcmp(sel, 'Cancel')
                        app.TabGroup.SelectedTab = oldTab;
                        return;
                    else
                        forceAuto = true;
                    end
                end

                if forceAuto
                    if missingProfiles
                        app.onGenerateProfiles();
                        drawnow; pause(0.1);
                    end
                    if missingKerf
                        app.onApplyKerf();
                        drawnow; pause(0.1);
                    end
                end
            end

            % --- LEVEL 3: BILLET ---
            if needsBillet
                isValidBillet = app.syncBilletUI();

                % 1. Size Logic: Auto-fit if size is 0 OR if not modified and invalid
                if sum(app.BilletSize) == 0 || (~isValidBillet && ~app.IsBilletUserModified)
                    app.onAutoFitBillet();
                    isValidBillet = app.syncBilletUI(); % Re-check validity
                end

                % 2. Position Logic: Auto-position if lock is off and still invalid
                if ~isValidBillet && ~app.IsBilletPosUserModified
                    app.onAutoPositionModel();
                    isValidBillet = app.syncBilletUI();
                end

                % 3. Safety Popups (Only if moving FORWARD past the Billet tab)
                if targetTab ~= app.TabBillet && ~isModel && ~isProfiles && ~isWelcome

                    % --- CASE A: CRITICAL ERROR (RED) ---
                    if ~isValidBillet
                        if ~forceAuto
                            sel = uiconfirm(app.UIFigure, ...
                                sprintf('The model is currently outside your manual billet bounds.\n\nWould you like to Auto-Fit the billet/position now, or return to adjust it manually?'), ...
                                'Billet Collision', ...
                                'Options', {'Auto-Fit All', 'Adjust Manually', 'Cancel'}, ...
                                'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'warning');

                            if strcmp(sel, 'Adjust Manually')
                                app.TabGroup.SelectedTab = app.TabBillet;
                                return;
                            elseif strcmp(sel, 'Cancel')
                                app.TabGroup.SelectedTab = oldTab;
                                return;
                            else
                                app.onAutoFitBillet();
                                app.onAutoPositionModel();
                                forceAuto = true;
                            end
                        end

                        % --- CASE B: WASTE WARNING (AMBER) ---
                    else
                        t = app.getTheme();
                        isWarning = isequal(app.BilletLeftPanel.BackgroundColor, t.statWarnBg);

                        if isWarning && ~forceAuto
                            sel = uiconfirm(app.UIFigure, ...
                                sprintf('Billet Warning: %s\n\nAcknowledge and proceed anyway, or return to Billet tab to optimize?', app.TxtBilletStatus.Value{1}), ...
                                'Billet Warning', ...
                                'Options', {'Acknowledge & Continue', 'Optimize Billet', 'Cancel'}, ...
                                'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'warning');

                            if strcmp(sel, 'Optimize Billet')
                                app.TabGroup.SelectedTab = app.TabBillet;
                                return;
                            elseif strcmp(sel, 'Cancel')
                                app.TabGroup.SelectedTab = oldTab;
                                return;
                            end
                            % If 'Acknowledge & Continue', we simply don't 'return',
                            % allowing the tab change to proceed.
                        end
                    end
                end
            end

            % --- LEVEL 4: MACHINE GATEKEEPER ---
            if needsMachine
                % 1. Auto-Trigger: Only if never setup (Init=0) OR if user hasn't locked it (UserModified=0)
                if ~app.IsMachineInit || ~app.IsMachineUserModified
                    app.onResetMachineBilletPosition();
                end

                [isValidMach, pCol, tCol, msgLines] = app.checkMachineState();
                isExtRed   = app.MaxPathExtension > app.WireExt_Red;
                isExtAmber = app.MaxPathExtension > app.WireExt_Amber;

                % Case A: CRITICAL ERROR (Red) - Block movement past Machine Tab
                if ~isValidMach || isExtRed
                    if targetTab ~= app.TabMachine && ~isWelcome && ~isModel && ~isProfiles && ~isBillet
                        reason = "Billet is outside machine limits.";
                        if isExtRed, reason = sprintf("Wire will snap! Extension (%.2fmm) exceeds pulley travel.", app.MaxPathExtension); end
                        uialert(app.UIFigure, reason, 'Machine Safety Error');
                        app.TabGroup.SelectedTab = app.TabMachine;
                        return;
                    end

                    % Case B: WARNING (Amber) - Speed-bump popup when moving FORWARD
                elseif isExtAmber && targetTab ~= app.TabMachine && ~isWelcome && ~isModel && ~isProfiles && ~isBillet
                    if ~forceAuto
                        sel = uiconfirm(app.UIFigure, ...
                            sprintf('Warning: Max wire extension is %.2f mm.\nThis is close to the mechanical pulley limit.\n\nProceed anyway, or return to Machine tab to optimize?', app.MaxPathExtension), ...
                            'Pulley Travel Warning', ...
                            'Options', {'Acknowledge & Continue', 'Return to Machine Tab', 'Cancel'}, ...
                            'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'warning');

                        if strcmp(sel, 'Return to Machine Tab')
                            app.TabGroup.SelectedTab = app.TabMachine;
                            return;
                        elseif strcmp(sel, 'Cancel')
                            app.TabGroup.SelectedTab = oldTab;
                            return;
                        end
                    end
                end
            end

            % --- LEVEL 5: CUTTING STRATEGY GATEKEEPER ---
            if needsCutting
                % 1. Auto-Trigger: Only if never setup (Init=0) OR if user hasn't locked it (UserModified=0)
                if ~app.IsCuttingInit || ~app.IsCuttingUserModified
                    app.onAutoStart(false);
                    app.onAutoEntry(false);
                end

                [isValidCut, pColC, tColC, msgLinesC] = app.validateCuttingStrategy();

                % Case A: CRITICAL ERROR (Red) - Block movement toward Sim/Post
                if ~isValidCut && (targetTab == app.TabSimulation || isPost)
                    if ~forceAuto
                        sel = uiconfirm(app.UIFigure, ...
                            sprintf('The current cutting strategy (Lead-In/Entry) is invalid.\n\nWould you like to Auto-Calculate a safe path, or return to adjust it manually?'), ...
                            'Strategy Error', ...
                            'Options', {'Auto-Calculate', 'Adjust Manually', 'Cancel'}, ...
                            'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'error');

                        if strcmp(sel, 'Adjust Manually')
                            app.TabGroup.SelectedTab = app.TabCutting;
                            return;
                        elseif strcmp(sel, 'Cancel')
                            app.TabGroup.SelectedTab = oldTab;
                            return;
                        else
                            % User chose 'Auto-Calculate'
                            app.onAutoStart(false);
                            app.onAutoEntry(false);
                            forceAuto = true;
                        end
                    end
                end
            end

            % --- EXECUTE SAFE TAB TRANSITION ---
            app.resetInteractionState();
            drawnow; pause(0.05);

            if targetTab == app.TabBillet
                % Landing on Billet tab: Handle Size and Position independently
                if ~app.IsBilletUserModified
                    app.onAutoFitBillet();
                end

                if ~app.IsBilletPosUserModified
                    app.onAutoPositionModel();
                end

                app.syncBilletUI();
                app.refreshBilletPlots();

            elseif targetTab == app.TabMachine
                app.syncMachineUI();

                d3 = 0;
                [ isValidMachF, pColF, tColF, msgLinesF ] = app.checkMachineState();

                app.MachineLeftPanel.BackgroundColor = pColF;
                app.TxtMachineStatus.Value = msgLinesF;
                app.TxtMachineStatus.FontColor = tColF;
                if isValidMachF, app.BtnMachineContinue.Enable = 'on'; else, app.BtnMachineContinue.Enable = 'off'; end
                app.refreshMachinePlot();

            elseif targetTab == app.TabCutting

                d4 = 0;
                [ isValidCutF, pColCF, tColCF, msgLinesCF ] = app.validateCuttingStrategy();

                app.CuttingLeftPanel.BackgroundColor = pColCF;
                app.TxtCuttingStatus.Value = msgLinesCF;
                app.TxtCuttingStatus.FontColor = tColCF;
                if isValidCutF, app.BtnCuttingContinue.Enable = 'on'; else, app.BtnCuttingContinue.Enable = 'off'; end

                app.updateCuttingPlots();
                app.onResetCuttingViewBillet();

            elseif isequal(targetTab, app.TabSimulation)
                % Safely fetch the feed rate if the Post-Process tab exists
                if ~isempty(app.SpinFeedRate) && isgraphics(app.SpinFeedRate)
                    app.LblBaseFeed.Text = sprintf('%.0f', app.SpinFeedRate.Value);
                end
                app.generateSimulationData();

            elseif isequal(targetTab, app.TabPostProcess)
                app.updatePostProcessUI();
                app.generateSimulationData();
                app.onPostProcess();
            end
        end

        function onProfileToleranceChanged(app, src)
            val = src.Value;
            if ~isfinite(val) || val <= 0
                src.Value = app.ProfileTolerance;
                return;
            end

            app.ProfileTolerance = val;
            app.IsCuttingInit = false;

            if app.AppState == 1 && ~isempty(app.ModelPatch) && isgraphics(app.ModelPatch)
                app.IsCuttingInit = false; % <--- ADD THIS
                app.ProfileAxesLocked = true;
                app.updatePlanes();
                app.ProfileAxesLocked = false;
            end
        end

        function onResetProfileTolerance(app)
            defaultTol = HotWireSTEPApp_v6_2.DefaultProfileTolerance;
            app.ProfileTolerance = defaultTol;

            if ~isempty(app.ProfileTolSpinner) && isgraphics(app.ProfileTolSpinner)
                app.ProfileTolSpinner.Value = defaultTol;
            end

            if app.AppState == 1 && ~isempty(app.ModelPatch) && isgraphics(app.ModelPatch)
                app.ProfileAxesLocked = true;
                app.updatePlanes();
                app.ProfileAxesLocked = false;
            end
        end

        function onKerfChanged(app, src)
            val = src.Value;
            if ~isfinite(val)
                src.Value = app.KerfValue;
                return;
            end

            app.KerfValue = val;

            try
                if isprop(app,'AppState') && app.AppState >= 1
                    if ismethod(app,'updatePlanes')
                        app.ProfileAxesLocked = true;
                        app.updatePlanes();
                        app.ProfileAxesLocked = false;
                    end
                end
            catch
            end
        end

        function onApplyKerf(app)
            if isempty(app.LeftProfilePoints) && isempty(app.RightProfilePoints)
                return;
            end

            app.KerfEnabled = true;

            app.BtnProfilesContinue.Enable = 'on';

            % Using spaces inside brackets to prevent markdown parser crashes
            app.BtnProfilesContinue.BackgroundColor =[ 0.1, 0.6, 0.1 ];
            app.BtnProfilesContinue.FontColor       = [ 1, 1, 1 ];

            % Using zeros(0,1) instead of empty brackets to prevent truncation!
            yL = zeros(0,1);
            zL = zeros(0,1);
            xLeft  = 0;

            yR = zeros(0,1);
            zR = zeros(0,1);
            xRight = 0;

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

            wasLocked = app.ProfileAxesLocked;
            app.ProfileAxesLocked = true;
            app.updateProfiles2D(yL, zL, yR, zR, xLeft, xRight);
            app.ProfileAxesLocked = wasLocked;

            t = app.getTheme();

            if isprop(app, 'TxtProfileStatus') && isgraphics(app.TxtProfileStatus)
                % FIX: Use actual class properties instead of local variables
                valL = app.KerfLeftValue;
                valR = app.KerfRightValue;

                if strcmp(app.KerfModeSwitch.Value, 'Coupled')
                    msg = sprintf('Kerf Applied: %.2f mm', valL);
                else
                    msg = sprintf('Kerf Applied (L/R): %.2f / %.2f mm', valL, valR);
                end

                app.TxtProfileStatus.Value = {msg; 'Profiles Valid.'; 'Click Continue.'};
                app.TxtProfileStatus.FontColor = t.statPassTxt;
            end
        end

        function onKerfModeChanged(app, src)
            mode = src.Value;
            isCoupled = strcmp(mode, 'Coupled');

            if isCoupled
                app.KerfRightSpinner.Enable = 'off';
                app.KerfRightValue = app.KerfLeftValue;
                app.KerfRightSpinner.Value = app.KerfLeftValue;

                app.ProfileAxesLocked = true;
                app.onApplyKerf();
                app.ProfileAxesLocked = false;
            else
                app.KerfRightSpinner.Enable = 'on';
            end
        end

        function onKerfLeftChanged(app, src)
            app.KerfLeftValue = src.Value;

            if strcmp(app.KerfModeSwitch.Value, 'Coupled')
                app.KerfRightValue = app.KerfLeftValue;
                if isvalid(app.KerfRightSpinner)
                    app.KerfRightSpinner.Value = app.KerfRightValue;
                end
            end

            app.KerfValue = app.KerfLeftValue;
            app.IsCuttingInit = false;
            app.ProfileAxesLocked = true;
            app.onApplyKerf();
            app.ProfileAxesLocked = false;
        end

        function onKerfRightChanged(app, src)
            app.KerfRightValue = src.Value;

            if strcmp(app.KerfModeSwitch.Value, 'Coupled')
                app.KerfLeftValue = app.KerfRightValue;
                app.KerfLeftSpinner.Value = app.KerfLeftValue;
                app.KerfValue = app.KerfLeftValue;
            end

            app.IsCuttingInit = false;
            app.ProfileAxesLocked = true;
            app.onApplyKerf();
            app.ProfileAxesLocked = false;
        end

        % ===========================================================
        % WELCOME TAB CALLBACKS (FreeCAD Configuration)
        % ===========================================================
        function onBrowseFreeCAD(app)
            [file, path] = uigetfile({'*.exe', 'Executables (*.exe)'}, 'Locate FreeCADCmd.exe', 'C:\Program Files\');
            if isequal(file, 0), return; end % User cancelled

            fullPath = fullfile(path, file);
            app.FreeCADExe = string(fullPath);
            app.FieldFreeCADPath.Value = app.FreeCADExe;

            % Save to user's MATLAB profile permanently
            setpref('HotWireSTEPApp', 'FreeCADPath', app.FreeCADExe);

            uialert(app.UIFigure, 'FreeCAD path saved successfully!', 'Setup Complete', 'Icon', 'success');
        end

        function onFreeCADPathEdited(app, src)
            app.FreeCADExe = string(src.Value);
            setpref('HotWireSTEPApp', 'FreeCADPath', app.FreeCADExe);
        end

        % ===========================================================
        % IMPORT STEP / STL
        % ===========================================================
        function onImportSTEP(app)
            % Check if FreeCAD is configured correctly before opening dialog
            if ~isfile(app.FreeCADExe)
                uialert(app.UIFigure, 'FreeCADCmd.exe not found at the configured path! Please locate it on the Welcome Tab first.', 'FreeCAD Missing', 'Icon', 'error');
                app.TabGroup.SelectedTab = app.TabWelcome;
                return;
            end

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

            % ONLY reset the manual lock on a brand new file import
            app.IsBilletUserModified = false;
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

            app.IsMachineInit = false;
            app.IsCuttingInit = false;

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

            t = app.getTheme(); % <--- FIX: Get theme

            if nargin < 2, resetOffsets = true; end

            if resetOffsets
                app.NumLeftOffset.Value  = 0;
                app.NumRightOffset.Value = modelWidth;

                if ~isempty(app.TxtModelStatus)
                    app.TxtModelStatus.Value = {'Model loaded.', sprintf('Size: %.1f x %.1f x %.1f mm', ...
                        modelWidth, app.ModelYMax-app.ModelYMin, app.ModelZMax-app.ModelZMin)};
                    app.TxtModelStatus.FontColor = t.statPassTxt; % <--- FIX
                end
            else
                if app.NumLeftOffset.Value > modelWidth, app.NumLeftOffset.Value = modelWidth; end
                if app.NumRightOffset.Value > modelWidth, app.NumRightOffset.Value = modelWidth; end

                if ~isempty(app.TxtModelStatus)
                    app.TxtModelStatus.Value = {'Model re-oriented.', 'Check plane positions.'};
                    app.TxtModelStatus.FontColor = t.statWarnTxt; % <--- FIX
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

        end

        function resetPlanes(app)
            if isempty(app.ModelPatch) || ~isvalid(app.ModelPatch)
                return
            end

            app.invalidateKerf();

            app.updateModelBoundsAndDefaultOffsets(true);
            app.updatePlanes();

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
                return;
            end

            if app.AppState == 0
                app.enterState1();
            else
                app.updatePlanes();
            end
        end

        function onContinue(app)
            currTab = app.TabGroup.SelectedTab;

            % --- Pre-Model Navigation (Welcome & Guide) ---
            if isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch)
                if isequal(currTab, app.TabWelcome)
                    nextTab = app.TabGuide;
                elseif isequal(currTab, app.TabGuide)
                    nextTab = app.TabModel;
                else
                    return;
                end

                if ~isempty(nextTab) && isgraphics(nextTab)
                    app.TabGroup.SelectedTab = nextTab;
                    evt = struct('OldValue', currTab, 'NewValue', nextTab);
                    app.onTabChanged(app.TabGroup, evt);
                end
                return;
            end

            % --- Post-Model Navigation Sequence ---
            if isequal(currTab, app.TabWelcome)
                nextTab = app.TabGuide;
            elseif isequal(currTab, app.TabGuide)
                nextTab = app.TabModel;
            elseif isequal(currTab, app.TabModel)
                nextTab = app.TabProfiles;
            elseif isequal(currTab, app.TabProfiles)
                nextTab = app.TabBillet;
            elseif isequal(currTab, app.TabBillet)
                nextTab = app.TabMachine;
            elseif isequal(currTab, app.TabMachine)
                nextTab = app.TabCutting;
            elseif isequal(currTab, app.TabCutting)
                nextTab = app.TabSimulation;
            elseif isequal(currTab, app.TabSimulation)
                nextTab = app.TabPostProcess;
            else
                return;
            end

            % Safety catch if the tab hasn't been built
            if isempty(nextTab) || ~isgraphics(nextTab)
                uialert(app.UIFigure, 'The next tab has not been built yet.', 'Navigation Error');
                return;
            end

            % Visually switch the tab and trigger Gatekeeper
            app.TabGroup.SelectedTab = nextTab;
            evt = struct('OldValue', currTab, 'NewValue', nextTab);
            app.onTabChanged(app.TabGroup, evt);
        end

        % ===========================================================
        % BILLET TAB CALLBACKS
        % ===========================================================
        function updateBilletDefaultsFromMesh(app)
            if isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch)
                return;
            end

            % Simply trigger the smart auto-tools!
            app.onAutoFitBillet();
            app.onAutoPositionModel();
        end

        function isValid = syncBilletUI(app)
            if isempty(app.BilletSizeEdits) || isempty(app.ModelPatch)
                isValid = false;
                return;
            end

            if ~isempty(app.LeftProfilePoints) && ~isempty(app.RightProfilePoints)
                P =[app.LeftProfilePoints; app.RightProfilePoints];
            else
                P = app.ModelPatch.Vertices;
            end

            localMins = min(P,[], 1);
            localMaxs = max(P,[], 1);

            xL = app.ModelXMin + app.NumLeftOffset.Value;
            xR = app.ModelXMin + app.NumRightOffset.Value;

            mMin =[min(xL, xR), localMins(2), localMins(3)];
            mMax =[max(xL, xR), localMaxs(2), localMaxs(3)];
            mDim = mMax - mMin;

            workMin = app.BilletShift + mMin;
            workMax = workMin + mDim;
            bSize = app.BilletSize;

            for i = 1:3
                app.BilletSizeEdits(i).Value = bSize(i);
                app.BilletModelDimLabels(i).Text = sprintf('%.2f mm', mDim(i));
                app.BilletNegOffsetEdits(i).Value = workMin(i);
                app.BilletPosOffsetEdits(i).Value = bSize(i) - workMax(i);
                app.BilletCenterOffsetEdits(i).Value = app.BilletShift(i);
            end

            tol = app.ModelContainmentTol;
            buf = app.ModelEdgeWarningBuffer;
            wasteLimit = app.MaxWasteBuffer;

            % Explicitly calculate gaps for logic clarity
            gapNeg = workMin;           % [X Y Z] gaps at the start side
            gapPos = bSize - workMax;   % [X Y Z] gaps at the end side
            slack  = bSize - mDim;      % Total extra foam in each axis

            % 1. CRITICAL: Outside Bounds (Red)
            isOutside = any(gapNeg < -tol) || any(gapPos < -tol);

            % 2. WARNING: Too Close (Amber) - Only for Y and Z (X=0 is allowed)
            isTooCloseYZ = any(gapNeg(2:3) < buf - 1e-4) || any(gapPos(2:3) < buf - 1e-4);

            % 3. WARNING: Floating (Amber) - Both sides > buf (Y and Z)
            % User should nudge model to at least one edge to save foam.
            isFloatingY = (gapNeg(2) > buf + 1e-4) && (gapPos(2) > buf + 1e-4);
            isFloatingZ = (gapNeg(3) > buf + 1e-4) && (gapPos(3) > buf + 1e-4);

            % 4. WARNING: Foam Waste (Amber)
            % X: Allowed to be 0, so waste triggers if total slack > wasteLimit
            % Y/Z: Trigger if total slack > (required buffer + wasteLimit)
            isWasteX = slack(1) > wasteLimit;
            isWasteY = slack(2) > (buf + wasteLimit);
            isWasteZ = slack(3) > (buf + wasteLimit);

            t = app.getTheme();

            if isOutside
                app.BilletLeftPanel.BackgroundColor = t.statErrBg;
                app.TxtBilletStatus.Value = {'CRITICAL ERROR:', 'Model is outside stock!', 'Adjust billet size or model position.'};
                app.TxtBilletStatus.FontColor = t.statErrTxt;
                isValid = false;
            elseif isTooCloseYZ
                app.BilletLeftPanel.BackgroundColor = t.statWarnBg;
                app.TxtBilletStatus.Value = {sprintf('WARNING: Model is <%.0fmm from Y/Z edges.', buf), 'Check wire clearance.'};
                app.TxtBilletStatus.FontColor = t.statWarnTxt;
                isValid = true;
            elseif isFloatingY || isFloatingZ
                app.BilletLeftPanel.BackgroundColor = t.statWarnBg;
                app.TxtBilletStatus.Value = {'REDUCE FOAM WASTE!', 'Model is floating in the middle of the block.', 'Nudge model to one edge in Y/Z.'};
                app.TxtBilletStatus.FontColor = t.statWarnTxt;
                isValid = true;
            elseif isWasteX || isWasteY || isWasteZ
                app.BilletLeftPanel.BackgroundColor = t.statWarnBg;
                app.TxtBilletStatus.Value = {'REDUCE FOAM WASTE!', 'Billet is significantly larger than model.', 'Consider using a smaller scrap block.'};
                app.TxtBilletStatus.FontColor = t.statWarnTxt;
                isValid = true;
            else
                app.BilletLeftPanel.BackgroundColor = t.statPassBg;
                app.TxtBilletStatus.Value = {'Billet configuration valid.'};
                app.TxtBilletStatus.FontColor = t.statPassTxt;
                isValid = true;
            end
        end

        function onResetBilletViewModel(app)
            app.BilletViewMode = "Model";
            app.refreshBilletPlots();
        end

        function onResetBilletViewBillet(app)
            app.BilletViewMode = "Billet";
            app.refreshBilletPlots();
        end

        function onAutoFitBillet(app)
            if isempty(app.ModelPatch)
                return;
            end

            if ~isempty(app.LeftProfilePoints) && ~isempty(app.RightProfilePoints)
                P = [app.LeftProfilePoints; app.RightProfilePoints];
            else
                P = app.ModelPatch.Vertices;
            end

            localMins = min(P);
            localMaxs = max(P);

            xL = app.ModelXMin + app.NumLeftOffset.Value;
            xR = app.ModelXMin + app.NumRightOffset.Value;

            buf = app.ModelEdgeWarningBuffer;
            tinyBuf = app.ModelXPlacementBuffer;

            bSizeX = abs(xR - xL) + (2.0 * tinyBuf);
            bSizeY = ceil((localMaxs(2) - localMins(2)) + (2.0 * buf));

            % FIX: Round Z up to the nearest millimeter just like Y!
            bSizeZ = ceil((localMaxs(3) - localMins(3)) + (2.0 * buf));

            app.BilletSize = [bSizeX, bSizeY, bSizeZ];
            app.BilletShift =[0 0 0];

            app.IsBilletUserModified = false; % Unlock Size auto-calculation

            % Mark downstream tabs as stale so they re-calculate if not locked
            app.IsMachineInit = false;
            app.IsCuttingInit = false;

            app.syncBilletUI();
            app.refreshBilletPlots();
        end

        function onAutoPositionModel(app)
            if isempty(app.ModelPatch)
                return;
            end

            if ~isempty(app.LeftProfilePoints) && ~isempty(app.RightProfilePoints)
                P = [app.LeftProfilePoints; app.RightProfilePoints];
            else
                P = app.ModelPatch.Vertices;
            end

            localMins = min(P);
            localMaxs = max(P);

            xL = app.ModelXMin + app.NumLeftOffset.Value;
            xR = app.ModelXMin + app.NumRightOffset.Value;

            planeMinX = min(xL, xR);
            tinyBuf = app.ModelXPlacementBuffer;

            oldShift = app.BilletShift;

            app.BilletShift(1) = tinyBuf - planeMinX;
            app.BilletShift(2) = app.ModelEdgeWarningBuffer - localMins(2);
            app.BilletShift(3) = app.BilletSize(3) - app.ModelEdgeWarningBuffer - localMaxs(3);

            diffShift = max(abs(oldShift - app.BilletShift));

            if diffShift > 1e-4
                app.IsCuttingInit = false;
            end

            app.IsBilletPosUserModified = false; % Unlock Position auto-calculation

            % Mark downstream tabs as stale
            app.IsMachineInit = false;
            app.IsCuttingInit = false;

            app.syncBilletUI();
            app.refreshBilletPlots();

            if app.TabGroup.SelectedTab == app.TabMachine
                app.refreshMachinePlot();
            end
        end

        function onResetPosition(app)
            if isempty(app.ModelPatch)
                return;
            end

            app.BilletShift = [0 0 0];
            app.IsCuttingInit = false;
            app.IsBilletUserModified = true; % User forced a reset

            app.syncBilletUI();
            app.refreshBilletPlots();
        end

        function onBilletSizeStep(app, axisIdx, direction)
            delta = direction * app.BilletSizeStep;
            app.BilletSize(axisIdx) = max(0, app.BilletSize(axisIdx) + delta);

            app.IsCuttingInit = false;
            app.IsBilletUserModified = true;

            app.syncBilletUI();
            app.refreshBilletPlots();
        end

        function onBilletSizeEdited(app, axisIdx, src)
            val = src.Value;
            minVal = 1.0;
            maxVal = app.MachineLimitZ;
            if axisIdx == 1, maxVal = app.MachineBedSize(1); end
            if axisIdx == 2, maxVal = app.MachineBedSize(2); end

            if val < minVal
                val = minVal;
            elseif val > maxVal
                val = maxVal;
            end

            src.Value = val;
            app.BilletSize(axisIdx) = val;

            app.IsCuttingInit = false;
            app.IsBilletUserModified = true;

            app.syncBilletUI();
            app.refreshBilletPlots();
        end

        function onBilletOffsetEdited(app, axisIdx, whichField, src)
            val = src.Value;

            % FIX: Use the exact same profile-aware bounds as syncBilletUI!
            if ~isempty(app.LeftProfilePoints) && ~isempty(app.RightProfilePoints)
                P = [app.LeftProfilePoints; app.RightProfilePoints];
            else
                if isempty(app.ModelPatch), return; end
                P = app.ModelPatch.Vertices;
            end

            % Use '1' flag for safe column minimums
            localMins = min(P,[], 1);
            localMaxs = max(P,[], 1);

            xL = app.ModelXMin + app.NumLeftOffset.Value;
            xR = app.ModelXMin + app.NumRightOffset.Value;

            mMin =[min(xL,xR), localMins(2), localMins(3)];
            mMax =[max(xL,xR), localMaxs(2), localMaxs(3)];

            oldShift = app.BilletShift;

            if strcmp(whichField, 'neg')
                app.BilletShift(axisIdx) = val - mMin(axisIdx);
            elseif strcmp(whichField, 'pos')
                app.BilletShift(axisIdx) = app.BilletSize(axisIdx) - mMax(axisIdx) - val;
            elseif strcmp(whichField, 'center')
                app.BilletShift(axisIdx) = val;
            end

            % Shift Entry points to match model movement within billet
            dY = app.BilletShift(2) - oldShift(2);
            dZ = app.BilletShift(3) - oldShift(3);
            app.shiftEntryPoints(dY, dZ);

            app.IsCuttingInit = false;
            app.IsBilletPosUserModified = true; % Lock the position, but not the size

            app.syncBilletUI();
            app.refreshBilletPlots();
        end

        function moveModelInSpace(app, axisIdx, delta)
            app.BilletShift(axisIdx) = app.BilletShift(axisIdx) + delta(1);

            dY = 0;
            dZ = 0;
            if axisIdx == 2
                dY = delta(1);
            end
            if axisIdx == 3
                dZ = delta(1);
            end
            app.shiftEntryPoints(dY, dZ);

            app.IsCuttingInit = false;
            app.IsBilletPosUserModified = true; % Lock the position, but not the size

            app.syncBilletUI();
            app.refreshBilletPlots();

            if app.TabGroup.SelectedTab == app.TabMachine
                app.refreshMachinePlot();
            end
        end

        function onBilletShift(app, axisIdx, delta)
            app.moveModelInSpace(axisIdx, delta);
            app.IsBilletPosUserModified = true; % Lock the position, but not the size
        end

        function refreshBilletPlots(app)
            if isempty(app.ModelPatch)
                return;
            end

            V     = app.ModelPatch.Vertices;
            F     = app.ModelPatch.Faces;
            bSize = app.BilletSize;
            shift = app.BilletShift;

            t = app.getTheme(); % <--- Master Palette

            V_shifted = V + shift;

            if app.BilletViewMode == "Model"
                allMin = min(V_shifted,[], 1);
                allMax = max(V_shifted,[], 1);
            else
                allMin =[ 0, 0, 0 ];
                allMax = bSize;
            end

            span = max(allMax - allMin);
            if span < 1, span = 100; end

            center = (allMin + allMax) / 2.0;
            limitRange = span * 0.6;

            commonX =[ center(1)-limitRange, center(1)+limitRange ];
            commonY =[ center(2)-limitRange, center(2)+limitRange ];
            commonZ =[ center(3)-limitRange, center(3)+limitRange ];

            hasProfiles = ~isempty(app.LeftProfilePoints) && ~isempty(app.RightProfilePoints);

            if hasProfiles
                pL_shifted = app.LeftProfilePoints + shift;
                pR_shifted = app.RightProfilePoints + shift;
            end

            axs  = {app.AxBilletTop, app.AxBilletFront, app.AxBilletRight, app.AxBilletIso};
            dims = {[ 1 2 ], [ 1 3 ], [ 2 3 ],[ 1 2 3 ]};
            labs = {{'X (mm)','Y (mm)'}; {'X (mm)','Z (mm)'}; {'Y (mm)','Z (mm)'}; {'X','Y','Z'}};

            for i = 1:4
                ax = axs{i};
                d = dims{i};

                if isempty(ax) || ~isgraphics(ax), continue; end

                cla(ax);
                hold(ax,'on');

                if i < 4
                    patch(ax, 'Vertices', V_shifted(:,d), 'Faces', F, ...
                        'FaceColor', t.modelColor, 'EdgeColor', 'none', 'FaceAlpha', t.modelAlpha);

                    if hasProfiles
                        % FIX: Use strict RGB for EdgeColor and explicitly set EdgeAlpha
                        patch(ax, 'XData', pL_shifted(:,d(1)), 'YData', pL_shifted(:,d(2)), 'ZData', zeros(size(pL_shifted,1),1), ...
                            'EdgeColor', t.planeRed, 'EdgeAlpha', 0.6, 'FaceColor', 'none', 'LineWidth', 0.75);
                        patch(ax, 'XData', pR_shifted(:,d(1)), 'YData', pR_shifted(:,d(2)), 'ZData', zeros(size(pR_shifted,1),1), ...
                            'EdgeColor', t.planeGreen, 'EdgeAlpha', 0.6, 'FaceColor', 'none', 'LineWidth', 0.75);
                    end

                    bx =[0, bSize(d(1)), bSize(d(1)), 0, 0];
                    by =[0, 0, bSize(d(2)), bSize(d(2)), 0];
                    plot(ax, bx, by, 'Color', t.billetLine, 'LineStyle', '--', 'LineWidth', 1.5);
                else
                    patch(ax, 'Vertices', V_shifted, 'Faces', F, ...
                        'FaceColor', t.modelColor, 'EdgeColor', 'none', 'FaceAlpha', t.modelAlpha);

                    if hasProfiles
                        % FIX: Use strict RGB for EdgeColor and explicitly set EdgeAlpha
                        patch(ax, 'XData', pL_shifted(:, 1), 'YData', pL_shifted(:, 2), 'ZData', pL_shifted(:, 3), ...
                            'EdgeColor', t.planeRed, 'EdgeAlpha', 0.6, 'FaceColor', 'none', 'LineWidth', 0.75);
                        patch(ax, 'XData', pR_shifted(:, 1), 'YData', pR_shifted(:, 2), 'ZData', pR_shifted(:, 3), ...
                            'EdgeColor', t.planeGreen, 'EdgeAlpha', 0.6, 'FaceColor', 'none', 'LineWidth', 0.75);
                    end

                    d1 = 0; % Anti-markdown bug
                    [ bx, by, bz ] = app.makeBoxVertices(0, 0, 0, bSize(1), bSize(2), bSize(3));

                    patch(ax, 'Vertices',[ bx, by, bz ], 'Faces', app.boxFaces, ...
                        'FaceColor', 'none', 'EdgeColor', t.billetLine, 'LineStyle', '--', 'LineWidth', 1.5);

                    view(ax, 3);
                end

                axis(ax, 'equal');
                grid(ax, 'on');
                ax.BackgroundColor = t.panelBg;

                if i==1, xlim(ax, commonX); ylim(ax, commonY); end
                if i==2, xlim(ax, commonX); ylim(ax, commonZ); end
                if i==3, xlim(ax, commonY); ylim(ax, commonZ); end
                if i==4, xlim(ax, commonX); ylim(ax, commonY); zlim(ax, commonZ); end

                xlabel(ax, labs{i}{1}); ylabel(ax, labs{i}{2});
                if i==4, zlabel(ax, labs{i}{3}); end

                set(ax, 'XColor', t.labelCol, 'YColor', t.labelCol, 'ZColor', t.labelCol);
            end

            drawnow limitrate;
        end
        % ===========================================================
        % MACHINE TAB CALLBACKS
        % ===========================================================

        function onMachinePosEdited(app, axisIdx, src)
            val = src.Value;

            oldY = app.MachineBilletPos(2);
            oldZ = app.MachineBilletPos(3);

            if axisIdx == 1
                app.MachineBilletPos(1) = app.MachineBedPos(1) + val;
            else
                app.MachineBilletPos(axisIdx) = val;
            end

            % FIX: Shift Entry points to match Billet movement on the machine bed
            dY = app.MachineBilletPos(2) - oldY;
            dZ = app.MachineBilletPos(3) - oldZ;
            app.shiftEntryPoints(dY, dZ);

            app.syncMachineUI();

            d1 = 0; % Anti-markdown bug
            [isValid, pCol, tCol, txtLines] = app.checkMachineState();

            app.MachineLeftPanel.BackgroundColor = pCol;
            app.TxtMachineStatus.Value = txtLines;
            app.TxtMachineStatus.FontColor = tCol;

            if isValid
                app.BtnMachineContinue.Enable = 'on';
            else
                app.BtnMachineContinue.Enable = 'off';
            end

            app.IsMachineUserModified = true;
            app.IsMachineInit = true;
            app.refreshMachinePlot();
        end

        function onResetMachineBilletPosition(app)
            if isempty(app.ModelPatch)
                return;
            end

            % Physical Bed Constraints
            bedX = app.MachineBedPos(1);
            maxXLimit = max(0, app.MachineBedSize(1) - app.BilletSize(1));

            % 1. X-Center Logic & Tower Path Length Optimization
            % FIX: Generate a strict 50mm grid relative to the left edge of the bed!
            maxRelX = floor(maxXLimit / 50.0) * 50.0;

            if maxRelX >= 0
                testRelXs = 0 : 50.0 : maxRelX;
                testXs = bedX + testRelXs; % Apply absolute machine offset
            else
                testXs = bedX; % Fallback if billet is technically too wide
            end

            % Default to the middle of the available 50mm grid
            bestX = testXs(max(1, ceil(numel(testXs)/2)));

            if ~isempty(app.LeftProfilePoints) && ~isempty(app.RightProfilePoints)

                d1 = 0; % Anti-markdown bug
                [ yL, zL, yR, zR ] = app.getSyncedKerfProfiles();

                if ~isempty(yL)
                    yL_base = yL + app.BilletShift(2);
                    zL_base = zL + app.BilletShift(3);
                    yR_base = yR + app.BilletShift(2);
                    zR_base = zR + app.BilletShift(3);

                    pXL = app.LeftProfilePoints(1,1);
                    pXR = app.RightProfilePoints(1,1);
                    planeDist = abs(pXR - pXL);

                    % --- X Sweep Optimization ---
                    if planeDist > 1e-3
                        bestDiff = inf;
                        centerX = bedX + maxXLimit / 2;

                        % Sweep ONLY the strict 50mm grid increments
                        for x = testXs
                            xL_m = x + app.BilletShift(1) + pXL;
                            xR_m = x + app.BilletShift(1) + pXR;

                            [tL, tR] = HotWireSTEPApp_v6_helpers.projectToTowers(yL_base, zL_base, xL_m, yR_base, zR_base, xR_m, app.MachineSpanX);

                            lenL = sum(hypot(diff(tL.y), diff(tL.z)));
                            lenR = sum(hypot(diff(tR.y), diff(tR.z)));

                            penalty = 1e-6 * abs(x - centerX);
                            diffLen = abs(lenL - lenR) + penalty;

                            if diffLen < bestDiff
                                bestDiff = diffLen;
                                bestX = x;
                            end
                        end
                    end

                    app.MachineBilletPos(1) = bestX;

                    % --- Evaluate Base Tower Heights at new X to solve Y and Z ---
                    xL_m = bestX + app.BilletShift(1) + pXL;
                    xR_m = bestX + app.BilletShift(1) + pXR;[tL, tR] = HotWireSTEPApp_v6_helpers.projectToTowers(yL_base, zL_base, xL_m, yR_base, zR_base, xR_m, app.MachineSpanX);

                    % --- Z Logic (Standardized Stock Heights) ---
                    minProjZ = min([tL.z; tR.z]);

                    if minProjZ >= 0
                        app.MachineBilletPos(3) = 0;
                    else
                        reqZ = -minProjZ;
                        targetZ = ceil(reqZ / 25.0) * 25.0;
                        if targetZ > 0 && targetZ < 50
                            targetZ = 50.0;
                        end
                        app.MachineBilletPos(3) = targetZ;
                    end

                    % --- Y Logic (Multiples of 50mm, min wire Y > 50) ---
                    minProjY = min([tL.y; tR.y]);
                    reqBilletY = max(50.0, 50.0 - minProjY);
                    targetBilletY = ceil(reqBilletY / 50.0) * 50.0;

                    bedD = app.MachineBedSize(2);
                    bY = app.BilletSize(2);
                    maxY = app.MachineBedPos(2) + bedD - bY;

                    app.MachineBilletPos(2) = min(targetBilletY, maxY);
                else
                    app.MachineBilletPos(1) = bestX;
                    app.MachineBilletPos(2) = app.MachineBedPos(2);
                    app.MachineBilletPos(3) = 0;
                end
            else
                app.MachineBilletPos(1) = bestX;
                app.MachineBilletPos(2) = app.MachineBedPos(2);
                app.MachineBilletPos(3) = 0;
            end

            app.IsMachineInit = true;
            app.syncMachineUI();

            d2 = 0;
            [isValid, pCol, tCol, txtLines] = app.checkMachineState();

            app.MachineLeftPanel.BackgroundColor = pCol;
            app.TxtMachineStatus.Value = txtLines;
            app.TxtMachineStatus.FontColor = tCol;

            if isValid
                app.BtnMachineContinue.Enable = 'on';
            else
                app.BtnMachineContinue.Enable = 'off';
            end

            app.IsMachineUserModified = false;
            app.IsMachineInit = true;
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
            ax = app.AxMachine;
            if isempty(ax) || ~isgraphics(ax), return; end

            delete(allchild(ax));
            hold(ax, 'on');

            t = app.getTheme(); % <--- Master Palette

            offX = app.MachineBedPos(1);
            mX = app.MachineSpanX;
            mLimY = app.MachineLimitY;
            mLimZ = app.MachineLimitZ;
            bs = app.MachineBedSize;
            bp = app.MachineBedPos;

            d1 = 0; % Anti-markdown bug
            [ xb, yb, zb ] = app.makeBoxVertices(0, bp(2), -bs(3), bs(1), bs(2), bs(3));

            hBed = patch(ax, 'Vertices',[ xb, yb, zb ], 'Faces', app.boxFaces, ...
                'FaceColor', t.bedCol, 'FaceAlpha', 0.5, 'EdgeColor', t.bedEdge);

            d2 = 0; % Anti-markdown bug
            [ xl, yl, zl ] = app.makeBoxVertices(-offX, 0, 0, mX, mLimY, mLimZ);

            hLim = patch(ax, 'Vertices',[ xl, yl, zl ], 'Faces', app.boxFaces, ...
                'FaceColor', 'none', 'EdgeColor', t.labelCol, 'LineStyle', ':', 'EdgeAlpha', 0.3);

            pY =[ 0; mLimY; mLimY; 0 ];
            pZ =[ 0; 0; mLimZ; mLimZ ];

            hTowerL = patch(ax, 'XData', ones(4,1)*(-offX), 'YData', pY, 'ZData', pZ, 'FaceColor', t.planeRed, ...
                'FaceAlpha', 0.15, 'EdgeColor', t.planeRed, 'LineStyle', '-');

            hTowerR = patch(ax, 'XData', ones(4,1)*(mX-offX), 'YData', pY, 'ZData', pZ, 'FaceColor', t.planeGreen, ...
                'FaceAlpha', 0.15, 'EdgeColor', t.planeGreen, 'LineStyle', '-');

            text(ax, -offX, mLimY*0.98, mLimZ*0.92, {' LEFT',' TOWER'}, 'Color', t.planeRedTxt, 'FontWeight', 'bold', 'FontSize', 9);
            text(ax, mX-offX, mLimY*0.02, mLimZ*0.92, {'RIGHT','TOWER '}, 'Color', t.planeGreenTxt, 'FontWeight', 'bold', 'HorizontalAlignment', 'right', 'FontSize', 9);

            hBillet = gobjects(0); hModel = gobjects(0); hGhostL = gobjects(0); hWireL = gobjects(0);
            isViolated = false;

            if ~isempty(app.ModelPatch) && isgraphics(app.ModelPatch)
                bPlotPos =[ app.MachineBilletPos(1)-offX, app.MachineBilletPos(2), app.MachineBilletPos(3) ];
                totalShift = bPlotPos + app.BilletShift;

                d3 = 0; % Anti-markdown bug
                [ xm, ym, zm ] = app.makeBoxVertices(bPlotPos(1), bPlotPos(2), bPlotPos(3), app.BilletSize(1), app.BilletSize(2), app.BilletSize(3));

                hBillet = patch(ax, 'Vertices',[ xm, ym, zm ], 'Faces', app.boxFaces, ...
                    'FaceColor', t.billetColor, 'FaceAlpha', t.billetAlpha, ...
                    'EdgeColor', t.labelCol, 'LineStyle', '--', 'LineWidth', 1.0);

                Vplot = app.ModelPatch.Vertices + totalShift;
                hModel = patch(ax, 'Vertices', Vplot, 'Faces', app.ModelPatch.Faces, ...
                    'FaceColor', t.modelColor, 'FaceAlpha', t.modelAlpha, 'EdgeColor', 'none');

                if ~isempty(app.LeftProfilePoints) && ~isempty(app.RightProfilePoints)

                    d4 = 0; % Anti-markdown bug
                    [ yS_rawL, zS_rawL, yS_rawR, zS_rawR ] = HotWireSTEPApp_v6_helpers.syncPointCounts(...
                        app.LeftProfilePoints(:,2), app.LeftProfilePoints(:,3), ...
                        app.RightProfilePoints(:,2), app.RightProfilePoints(:,3));

                    xL_world = app.LeftProfilePoints(1,1) + totalShift(1);
                    xR_world = app.RightProfilePoints(1,1) + totalShift(1);

                    hGhostL = plot3(ax, xL_world * ones(size(yS_rawL)), yS_rawL + totalShift(2), zS_rawL + totalShift(3), ...
                        'Color', t.ghostRed, 'LineWidth', 0.75, 'LineStyle', '-');

                    plot3(ax, xR_world * ones(size(yS_rawR)), yS_rawR + totalShift(2), zS_rawR + totalShift(3), ...
                        'Color', t.ghostGreen, 'LineWidth', 0.75, 'LineStyle', '-');

                    d5 = 0; % Anti-markdown bug
                    [ ySyncL, zSyncL, ySyncR, zSyncR ] = app.getSyncedKerfProfiles();

                    if ~isempty(ySyncL)
                        isCCW = strcmp(app.SwitchCutDir.Value, 'Bottom (CCW)');[ySyncL, zSyncL] = app.applyMods(ySyncL, zSyncL, 0, 0, app.SelectedStartIdxL, isCCW);
                        [ySyncR, zSyncR] = app.applyMods(ySyncR, zSyncR, 0, 0, app.SelectedStartIdxR, isCCW);

                        hWireL = plot3(ax, xL_world * ones(size(ySyncL)), ySyncL + totalShift(2), zSyncL + totalShift(3), ...
                            'Color', t.wireKerf, 'LineWidth', 0.75);
                        plot3(ax, xR_world * ones(size(ySyncR)), ySyncR + totalShift(2), zSyncR + totalShift(3), ...
                            'Color', t.wireKerf, 'LineWidth', 0.75);

                        d6 = 0; % Anti-markdown bug
                        [ tL, tR ] = HotWireSTEPApp_v6_helpers.projectToTowers(...
                            ySyncL + totalShift(2), zSyncL + totalShift(3), xL_world + offX, ...
                            ySyncR + totalShift(2), zSyncR + totalShift(3), xR_world + offX, app.MachineSpanX);

                        plot3(ax, ones(size(tL.y))*(-offX), tL.y, tL.z, 'Color', t.planeRed, 'LineWidth', 0.75);
                        plot3(ax, ones(size(tR.y))*(mX-offX), tR.y, tR.z, 'Color', t.planeGreen, 'LineWidth', 0.75);

                        stepInt = max(1, floor(numel(tL.y)/20));
                        idx = 1:stepInt:numel(tL.y);
                        if idx(end) ~= numel(tL.y), idx(end+1) = numel(tL.y); end
                        dotCMap = hsv(numel(idx));

                        bad = (tL.y < 0 | tL.y > mLimY | tL.z < 0 | tL.z > mLimZ | tR.y < 0 | tR.y > mLimY | tR.z < 0 | tR.z > mLimZ);
                        if any(bad), isViolated = true; end

                        for k = 1:numel(idx)
                            currIdx = idx(k);

                            wCol =[ t.wireBaseCol, 0.60 ];
                            if bad(currIdx)
                                wCol =[ 1 0.8 0 0.8 ];
                            end

                            plot3(ax,[ -offX, mX-offX ],[ tL.y(currIdx), tR.y(currIdx) ],[ tL.z(currIdx), tR.z(currIdx) ], ...
                                'Color', wCol, 'LineWidth', 0.5);

                            plot3(ax, xL_world, ySyncL(currIdx) + totalShift(2), zSyncL(currIdx) + totalShift(3), ...
                                '.', 'Color', dotCMap(k,:), 'MarkerSize', 8);

                            plot3(ax, xR_world, ySyncR(currIdx) + totalShift(2), zSyncR(currIdx) + totalShift(3), ...
                                '.', 'Color', dotCMap(k,:), 'MarkerSize', 8);
                        end
                    end
                end
            end

            handles =[ hBed, hLim, hTowerL, hTowerR, hBillet, hModel, hGhostL, hWireL ];
            labels  = {'Machine Bed', 'Travel Limits', 'Left Tower', 'Right Tower', 'Billet Stock', 'Model Mesh', 'Extracted Profile', 'Wire Path (Kerf)'};

            valid = isgraphics(handles);
            if any(valid)
                lgd = legend(ax, handles(valid), labels(valid), 'Location', 'northeast');
                lgd.Box = 'off';
                lgd.TextColor = t.labelCol;
            end

            view(ax, 3); axis(ax, 'equal'); grid(ax, 'on');
            ax.BackgroundColor = t.editBg;
            set(ax, 'XColor', t.labelCol, 'YColor', t.labelCol, 'ZColor', t.labelCol);

            xlim(ax,[ -offX - 100, mX - offX + 100 ]);
            ylim(ax,[ -50, mLimY + 50 ]);
            zlim(ax,[ -bs(3)-20, mLimZ + 80 ]);

            d7 = 0; % Anti-markdown bug
            [ isValid, pCol, tCol, txtLines ] = app.checkMachineState();

            if isViolated
                isValid = false;
                pCol = t.statErrBg;
                tCol = t.statErrTxt;
                txtLines =["CRITICAL ERROR:"; "Toolpath forces tower outside physical limits!"];
            end

            % --- WIRE EXTENSION SAFETY CHECK ---
            if ~isempty(tL) && ~isempty(tR)
                dy_ext = tL.y - tR.y;
                dz_ext = tL.z - tR.z;
                ext_all = hypot(app.MachineSpanX, hypot(dy_ext, dz_ext)) - app.MachineSpanX;
                app.MaxPathExtension = max(ext_all);

                if app.MaxPathExtension > app.WireExt_Red
                    isValid = false; % Hard Block
                    pCol = t.statErrBg;
                    tCol = t.statErrTxt;
                    txtLines = ["CRITICAL ERROR: WIRE OVER-EXTENSION", ...
                        sprintf("Max Extension: %.2f mm", app.MaxPathExtension), ...
                        sprintf("Exceeds Hardware Limit (%.0f mm)!", app.WireExt_Red)];
                elseif app.MaxPathExtension > app.WireExt_Amber
                    % Warning - only apply if not already in a Red error state
                    if isValid
                        pCol = t.statWarnBg;
                        tCol = t.statWarnTxt;
                        txtLines = ["WARNING: WIRE EXTENSION", ...
                            sprintf("Max Extension: %.2f mm", app.MaxPathExtension), ...
                            "Pulley travel is nearly exhausted."];
                    end
                end
            end

            app.MachineLeftPanel.BackgroundColor = pCol;
            app.TxtMachineStatus.Value = txtLines;
            app.TxtMachineStatus.FontColor = tCol;

            if isValid
                app.BtnMachineContinue.Enable = 'on';
            else
                app.BtnMachineContinue.Enable = 'off';
            end

            drawnow limitrate;
        end

        function syncMachineUI(app)
            % Enforces physical boundaries directly on the Spinners

            bX = app.BilletSize(1);
            bY = app.BilletSize(2);
            bZ = app.BilletSize(3);

            bedX = app.MachineBedPos(1);
            bedY = app.MachineBedPos(2);
            bedW = app.MachineBedSize(1);
            bedD = app.MachineBedSize(2);

            % X is relative to bed left edge. Max = Bed Width - Billet Width
            maxX = max(0, bedW - bX);
            app.MachinePosSpinners(1).Limits = [0, maxX];

            % Y is absolute. Min = Bed Front, Max = Bed Depth - Billet Depth
            minY = bedY;
            maxY = max(minY, bedY + bedD - bY);
            app.MachinePosSpinners(2).Limits = [minY, maxY];

            % Z is absolute (Bed surface is 0). Max = Tower Limit - Billet Height
            maxZ = max(0, app.MachineLimitZ - bZ);
            app.MachinePosSpinners(3).Limits = [0, maxZ];

            % Clamp absolute positions to ensure safety
            app.MachineBilletPos(1) = max(bedX, min(bedX + maxX, app.MachineBilletPos(1)));
            app.MachineBilletPos(2) = max(minY, min(maxY, app.MachineBilletPos(2)));
            app.MachineBilletPos(3) = max(0, min(maxZ, app.MachineBilletPos(3)));

            % Map back to UI
            app.MachinePosSpinners(1).Value = app.MachineBilletPos(1) - bedX;
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
        function [isValid, pCol, tCol, msgLines] = validateCuttingStrategy(app)
            % Validates the cutting path against physical constraints and model geometry.

            isValid = true;
            crit = strings(0);
            warn = strings(0);

            % 1. Setup Geometry
            bMinY = app.MachineBilletPos(2);
            bMaxY = app.MachineBilletPos(2) + app.BilletSize(2);
            bMinZ = app.MachineBilletPos(3);
            bMaxZ = app.MachineBilletPos(3) + app.BilletSize(3);

            % Billet Polygon (for intersection checks)
            billetBoxY =[bMinY; bMaxY; bMaxY; bMinY; bMinY];
            billetBoxZ =[bMinZ; bMinZ; bMaxZ; bMaxZ; bMinZ];

            % Get Final Profiles (Machine Absolute) to check for gouging
            offsetY = app.BilletShift(2) + bMinY;
            offsetZ = app.BilletShift(3) + bMinZ;
            [ syncY_L, syncZ_L, syncY_R, syncZ_R ] = app.getSyncedKerfProfiles();

            [ yL, zL ] = app.applyMods(syncY_L, syncZ_L, offsetY, offsetZ, app.SelectedStartIdxL, false);
            [ yR, zR ] = app.applyMods(syncY_R, syncZ_R, offsetY, offsetZ, app.SelectedStartIdxR, false);

            % --- Custom Intersection Helper ---
            % Replaces polyxpoly to avoid Mapping Toolbox dependency.
            % Checks a single line segment (p1 -> p2) against a polyline.
            function [xi, zi] = intersectSegPoly(p1, p2, polyY, polyZ)
                xi = [];
                zi =[];
                y1 = p1(1);
                z1 = p1(2);
                y2 = p2(1);
                z2 = p2(2);
                dy1 = y2 - y1;
                dz1 = z2 - z1;

                for i = 1:(numel(polyY)-1)
                    y3 = polyY(i);
                    z3 = polyZ(i);
                    y4 = polyY(i+1);
                    z4 = polyZ(i+1);
                    dy2 = y4 - y3;
                    dz2 = z4 - z3;

                    den = dy1*dz2 - dz1*dy2;
                    if abs(den) < 1e-9 % Parallel or collinear
                        continue;
                    end

                    t1 = ((y3 - y1)*dz2 - (z3 - z1)*dy2) / den;
                    t2 = ((y3 - y1)*dz1 - (z3 - z1)*dy1) / den;

                    % Use a tiny tolerance to avoid floating point misses on perfect corners
                    if t1 >= -1e-6 && t1 <= 1+1e-6 && t2 >= -1e-6 && t2 <= 1+1e-6
                        xi(end+1) = y1 + t1 * dy1;
                        zi(end+1) = z1 + t1 * dz1;
                    end
                end
            end

            % --- Helper: Check One Side ---
            function checkSide(sideName, lead, link1, link2, profY, profZ)
                % FIX: Catch empty lead points (e.g. from Clear Pts button)
                if isempty(lead)
                    crit(end+1) = sprintf("%s: Missing Lead-In point. Use Auto-Entry or pick manually.", sideName);
                    return;
                end

                % A. Check Proximity (<5mm from Bed or Billet)
                if lead(2) < 5.0
                    warn(end+1) = sprintf("%s: Lead In very close to Bed (<5mm).", sideName);
                end

                distY = max(0, max(bMinY - lead(1), lead(1) - bMaxY));
                distZ = max(0, max(bMinZ - lead(2), lead(2) - bMaxZ));
                if (distY < 5.0 && distZ < 5.0) && (distY > 0 || distZ > 0)
                    warn(end+1) = sprintf("%s: Lead In <5mm from Billet.", sideName);
                end

                % B. CRITICAL: Link Line Collision with Billet
                pRet = [bMinY - 10, bMaxZ/2];
                pathPts = [pRet; link1; link2; lead];
                pathPts = pathPts(~all(pathPts==0, 2), :);

                for k = 1:size(pathPts, 1)-1
                    p1 = pathPts(k,:);
                    p2 = pathPts(k+1,:);
                    d5 = 0; % Anti-markdown bug
                    [ xi, zi ] = intersectSegPoly(p1, p2, billetBoxY, billetBoxZ);

                    if ~isempty(xi)
                        crit(end+1) = sprintf("%s: Rapid move passes THROUGH the billet!", sideName);
                        break;
                    end
                end

                % C. CRITICAL: Lead-In Gouging (Bisecting) Model
                if ~isempty(profY)
                    startPt = [profY(1), profZ(1)];
                    d6 = 0; % Anti-markdown bug
                    [ xi, zi ] = intersectSegPoly([lead(1), lead(2)], [startPt(1), startPt(2)], profY, profZ);

                    validHit = false;
                    for k = 1:numel(xi)
                        distS = hypot(xi(k)-startPt(1), zi(k)-startPt(2));
                        if distS > 1e-3
                            validHit = true;
                        end
                    end

                    if validHit
                        crit(end+1) = sprintf("%s: Lead-In cuts through the part geometry!", sideName);
                    end

                    midPt = (lead + startPt) / 2;
                    if inpolygon(midPt(1), midPt(2), profY, profZ)
                        crit(end+1) = sprintf("%s: Lead-In is inside the part geometry!", sideName);
                    end
                end
            end

            % Check Left
            checkSide("Left", app.EntryPointL, app.EntryPoint2L, app.EntryPoint3L, yL, zL);
            if ~isempty(app.EntryPointR)
                checkSide("Right", app.EntryPointR, app.EntryPoint2R, app.EntryPoint3R, yR, zR);
            end

            t = app.getTheme(); % <--- Master Palette

            if ~isempty(crit)
                isValid = false;
                pCol = t.statErrBg;
                tCol = t.statErrTxt;
                msgLines =["CRITICAL ERROR:"; crit(1)];
            elseif ~isempty(warn)
                isValid = true;
                pCol = t.statWarnBg;
                tCol = t.statWarnTxt;
                msgLines =["Warning:"; warn(1)];
            else
                isValid = true;
                pCol = t.statPassBg;
                tCol = t.statPassTxt;
                msgLines =["Strategy valid.", "Ready to cut."];
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

            % 4. Apply Machine Offsets
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

        function updateCuttingPlots(app)
            if isempty(app.AxCutLeft) || isempty(app.AxCutRight)
                return;
            end

            t = app.getTheme();

            preserveView = true;
            curXL = xlim(app.AxCutLeft);
            isInitialized = ~isequal(curXL, [0 1]);

            limsL = [];
            limsR =[];

            if isInitialized
                limsL = [xlim(app.AxCutLeft); ylim(app.AxCutLeft)];
                limsR =[xlim(app.AxCutRight); ylim(app.AxCutRight)];
            end

            cla(app.AxCutLeft);
            cla(app.AxCutRight);
            hold(app.AxCutLeft,'on');
            hold(app.AxCutRight,'on');

            offsetY = app.BilletShift(2) + app.MachineBilletPos(2);
            offsetZ = app.BilletShift(3) + app.MachineBilletPos(3);
            isCCW   = strcmp(app.SwitchCutDir.Value, 'Bottom (CCW)');

            bedY =[50, 750, 750, 50];
            bedZ =[-20, -20, 0, 0];
            patch(app.AxCutLeft, bedY, bedZ, t.labelCol, 'FaceAlpha', 0.1, 'EdgeColor', 'none', 'HitTest', 'off');
            patch(app.AxCutRight, bedY, bedZ, t.labelCol, 'FaceAlpha', 0.1, 'EdgeColor', 'none', 'HitTest', 'off');

            mBoxY =[0, app.MachineLimitY, app.MachineLimitY, 0, 0];
            mBoxZ =[0, 0, app.MachineLimitZ, app.MachineLimitZ, 0];

            hMachL = plot(app.AxCutLeft, mBoxY, mBoxZ, ':', 'Color', t.labelCol, 'LineWidth', 0.5, 'HitTest', 'off');
            hMachR = plot(app.AxCutRight, mBoxY, mBoxZ, ':', 'Color', t.labelCol, 'LineWidth', 0.5, 'HitTest', 'off');

            bY = app.MachineBilletPos(2);
            bZ = app.MachineBilletPos(3);
            bW = app.BilletSize(2);
            bH = app.BilletSize(3);
            boxY =[bY, bY+bW, bY+bW, bY, bY];
            boxZ = [bZ, bZ, bZ+bH, bZ+bH, bZ];

            hBilletL = plot(app.AxCutLeft, boxY, boxZ, '--', 'Color', t.labelCol, 'LineWidth', 1.5, 'HitTest', 'off');
            hBilletR = plot(app.AxCutRight, boxY, boxZ, '--', 'Color', t.labelCol, 'LineWidth', 1.5, 'HitTest', 'off');

            % 4. Process Data (Kerf -> Sync -> Shift Pipeline)

            x_dummy1 = 0;[syncY_L, syncZ_L, syncY_R, syncZ_R] = app.getSyncedKerfProfiles();

            hGhostL = gobjects(0);
            hGhostR = gobjects(0);

            if ~isempty(app.LeftProfilePoints)
                hGhostL = plot(app.AxCutLeft, app.LeftProfilePoints(:,2) + offsetY, app.LeftProfilePoints(:,3) + offsetZ, ':', 'Color', t.rawMeshCol, 'LineWidth', 0.5, 'HitTest', 'off');
            end

            if ~isempty(app.RightProfilePoints)
                hGhostR = plot(app.AxCutRight, app.RightProfilePoints(:,2) + offsetY, app.RightProfilePoints(:,3) + offsetZ, ':', 'Color', t.rawMeshCol, 'LineWidth', 0.5, 'HitTest', 'off');
            end

            % Apply Start Index Shift and Direction Reversal

            x_dummy2 = 0;
            [yL, zL] = app.applyMods(syncY_L, syncZ_L, offsetY, offsetZ, app.SelectedStartIdxL, isCCW);

            x_dummy3 = 0;
            [yR, zR] = app.applyMods(syncY_R, syncZ_R, offsetY, offsetZ, app.SelectedStartIdxR, isCCW);

            % 5. Draw
            function hD = drawDummyLegendMarker(ax, style, color, mFace, lWidth)
                if nargin < 5
                    lWidth = 1.0;
                end
                hD = plot(ax, NaN, NaN, style, 'Color', color, 'MarkerFaceColor', mFace, 'LineWidth', lWidth);
            end

            hRapidL = gobjects(0); hLeadL = gobjects(0); hStartL = gobjects(0); hPathDummyL = gobjects(0); hEntryDotL = gobjects(0); hLoadL = gobjects(0);

            if ~isempty(yL)
                c = (1:numel(yL))';
                patch(app.AxCutLeft, 'XData', [yL;NaN], 'YData', [zL;NaN], 'CData', [c;NaN], 'FaceColor', 'none', 'EdgeColor', 'interp', 'LineWidth', 1.0, 'HitTest', 'off');
                hPathDummyL = drawDummyLegendMarker(app.AxCutLeft, '-', [0 0.5 1], 'none', 1.0);

                x_dummy4 = 0;[hRapidL, hLeadL, hEntryDotL, hLoadL] = app.drawTravelPath(app.AxCutLeft,[yL(1), zL(1)], [yL(end), zL(end)], app.EntryPointL, app.EntryPoint2L, app.EntryPoint3L);

                if numel(yL) > 1
                    idxNext = 2;
                    while idxNext < numel(yL) && norm([yL(idxNext),zL(idxNext)] - [yL(1),zL(1)]) < 1e-4
                        idxNext = idxNext + 1;
                    end
                    app.drawRotatedMarker(app.AxCutLeft,[yL(1), zL(1)], [yL(idxNext), zL(idxNext)], 'start');
                    hStartL = drawDummyLegendMarker(app.AxCutLeft, '^', [0 1 0], 'none');
                end
            end

            hRapidR = gobjects(0); hLeadR = gobjects(0); hStartR = gobjects(0); hPathDummyR = gobjects(0); hEntryDotR = gobjects(0); hLoadR = gobjects(0);

            if ~isempty(yR)
                c = (1:numel(yR))';
                patch(app.AxCutRight, 'XData', [yR;NaN], 'YData', [zR;NaN], 'CData', [c;NaN], 'FaceColor', 'none', 'EdgeColor', 'interp', 'LineWidth', 1.0, 'HitTest', 'off');
                hPathDummyR = drawDummyLegendMarker(app.AxCutRight, '-', [0 0.5 1], 'none', 1.0);

                x_dummy5 = 0;[hRapidR, hLeadR, hEntryDotR, hLoadR] = app.drawTravelPath(app.AxCutRight,[yR(1), zR(1)], [yR(end), zR(end)], app.EntryPointR, app.EntryPoint2R, app.EntryPoint3R);

                if numel(yR) > 1
                    idxNext = 2;
                    while idxNext < numel(yR) && norm([yR(idxNext),zR(idxNext)] - [yR(1),zR(1)]) < 1e-4
                        idxNext = idxNext + 1;
                    end
                    app.drawRotatedMarker(app.AxCutRight,[yR(1), zR(1)], [yR(idxNext), zR(idxNext)], 'start');
                    hStartR = drawDummyLegendMarker(app.AxCutRight, '^',[0 1 0], 'none');
                end
            end

            % 6. Legends (Dynamic Builder to prevent text mismatch)
            function buildLegend(axTarget, hs, hl, hp, hr, hld, he, hm, hg, tCol)
                hList =[];
                lList = {};
                if isgraphics(hs),  hList(end+1)=hs;  lList{end+1}='Start Point'; end
                if isgraphics(hl),  hList(end+1)=hl;  lList{end+1}='Load Point'; end
                if isgraphics(hp),  hList(end+1)=hp;  lList{end+1}='Cut Path'; end
                if isgraphics(hr),  hList(end+1)=hr;  lList{end+1}='Rapid Links'; end
                if isgraphics(hld), hList(end+1)=hld; lList{end+1}='Lead In'; end
                if isgraphics(he),  hList(end+1)=he;  lList{end+1}='Entry Point'; end
                if isgraphics(hm),  hList(end+1)=hm;  lList{end+1}='Machine Limits'; end
                if isgraphics(hg),  hList(end+1)=hg;  lList{end+1}='Raw Profile'; end

                if ~isempty(hList)
                    lgd = legend(axTarget, hList, lList, 'Location','northeast');
                    lgd.Box = 'off';
                    lgd.TextColor = tCol;
                end
            end

            if ~isgraphics(hEntryDotL)
                hEntryDotL = drawDummyLegendMarker(app.AxCutLeft, '.', t.wireLead, t.wireLead, 1.0);
            end
            if ~isgraphics(hEntryDotR)
                hEntryDotR = drawDummyLegendMarker(app.AxCutRight, '.', t.wireLead, t.wireLead, 1.0);
            end

            buildLegend(app.AxCutLeft, hStartL, hLoadL, hPathDummyL, hRapidL, hLeadL, hEntryDotL, hMachL, hGhostL, t.labelCol);
            buildLegend(app.AxCutRight, hStartR, hLoadR, hPathDummyR, hRapidR, hLeadR, hEntryDotR, hMachR, hGhostR, t.labelCol);

            % --- VALIDATE AND UPDATE STATUS UI ---
            x_dummy6 = 0;
            [isValidCut, pCol, tCol, msgLines] = app.validateCuttingStrategy();

            app.CuttingLeftPanel.BackgroundColor = pCol;
            app.TxtCuttingStatus.Value = msgLines;
            app.TxtCuttingStatus.FontColor = tCol;

            if isValidCut
                app.BtnCuttingContinue.Enable = 'on';
            else
                app.BtnCuttingContinue.Enable = 'off';
            end

            % 7. Restore View
            title(app.AxCutLeft,'Left Tower');
            title(app.AxCutRight,'Right Tower');
            colormap(app.AxCutLeft,'turbo');
            colormap(app.AxCutRight,'turbo');

            if isInitialized
                xlim(app.AxCutLeft, limsL(1,:));
                ylim(app.AxCutLeft, limsL(2,:));
                xlim(app.AxCutRight, limsR(1,:));
                ylim(app.AxCutRight, limsR(2,:));
            else
                axis(app.AxCutLeft,'equal');
                axis(app.AxCutRight,'equal');
            end

            daspect(app.AxCutLeft,[1 1 1]);
            daspect(app.AxCutRight,[1 1 1]);
        end

        function[yL, zL, yR, zR] = getSyncedKerfProfiles(app)
            % Centralized Kerf & Sync logic to guarantee exact 1:1 topology
            if isempty(app.LeftProfilePoints) || isempty(app.RightProfilePoints)
                yL=[]; zL=[]; yR=[]; zR=[];
                return;
            end

            yL = app.LeftProfilePoints(:,2);
            zL = app.LeftProfilePoints(:,3);
            yR = app.RightProfilePoints(:,2);
            zR = app.RightProfilePoints(:,3);

            if app.KerfEnabled
                if app.KerfLeftValue ~= 0
                    [yL, zL] = HotWireSTEPApp_v6_helpers.offsetProfileLoop(yL, zL, app.KerfLeftValue, app.ProfileTolerance);
                end
                if app.KerfRightValue ~= 0
                    [yR, zR] = HotWireSTEPApp_v6_helpers.offsetProfileLoop(yR, zR, app.KerfRightValue, app.ProfileTolerance);
                end
            end

            % --- FIX: ALWAYS re-align start points before syncing! ---
            % This prevents twist when Kerf is 0, ensuring both profiles
            % are anchored to the exact front face before parameter blending.
            [yL, zL] = HotWireSTEPApp_v6_helpers.reorderLoopByMinY(yL, zL);[yR, zR] = HotWireSTEPApp_v6_helpers.reorderLoopByMinY(yR, zR);

            [yL, zL, yR, zR] = HotWireSTEPApp_v6_helpers.syncPointCounts(yL, zL, yR, zR);
        end

        function [yOut, zOut] = applyMods(~, yIn, zIn, offY, offZ, startIdx, isCCW)
            % Applies offsets, user start index, and direction to a synced array
            if isempty(yIn)
                yOut=[]; zOut=[]; return;
            end
            yOut = yIn + offY;
            zOut = zIn + offZ;

            if numel(yOut) > 2
                if abs(yOut(1)-yOut(end)) < 1e-6 && abs(zOut(1)-zOut(end)) < 1e-6
                    yOut(end)=[]; zOut(end)=[];
                end

                N = numel(yOut);
                idx = max(1, min(startIdx, N));
                yOut = circshift(yOut, -(idx - 1));
                zOut = circshift(zOut, -(idx - 1));

                if isCCW
                    yOut(2:end) = flipud(yOut(2:end));
                    zOut(2:end) = flipud(zOut(2:end));
                end

                yOut(end+1) = yOut(1);
                zOut(end+1) = zOut(1);
            end
        end

        function onCutDirectionChanged(app)
            % Triggered when switching between CW (Top First) and CCW (Bottom First)
            app.updateCuttingPlots();
        end

        function onInteractionStatsChanged(app, src)
            % Handles mutual exclusivity and color updates for interaction buttons

            c = app.getInteractionColors();

            % 1. Determine user intent
            wantsToEnable = src.Value;

            % 2. Reset ALL buttons to OFF/Inactive (Clean Slate)
            % This ensures mutual exclusivity
            app.resetInteractionState();

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
                    src.BackgroundColor = c.LinkActive;
                    src.FontColor = c.TextActive;
                elseif isprop(app, 'BtnPickEntry3') && src == app.BtnPickEntry3
                    src.BackgroundColor = c.LinkActive;
                    src.FontColor = c.TextActive;
                end
            end
        end

        function resetInteractionState(app)
            % Turns off all interaction buttons and resets cursor
            c = app.getInteractionColors();

            % 1. Reset Toggle States
            app.BtnPickStart.Value = false;
            app.BtnPickEntry.Value = false;
            app.BtnPickEntry2.Value = false;
            if isprop(app, 'BtnPickEntry3') && isgraphics(app.BtnPickEntry3)
                app.BtnPickEntry3.Value = false;
            end

            % 2. Reset Background Colors
            app.BtnPickStart.BackgroundColor = c.StartInactive;
            app.BtnPickEntry.BackgroundColor = c.EntryInactive;
            app.BtnPickEntry2.BackgroundColor = c.LinkInactive;
            if isprop(app, 'BtnPickEntry3') && isgraphics(app.BtnPickEntry3)
                app.BtnPickEntry3.BackgroundColor = c.LinkInactive;
            end

            % 3. Reset Font Colors (Restored)
            app.BtnPickStart.FontColor = c.TextInactive;
            app.BtnPickEntry.FontColor = c.TextInactive;
            app.BtnPickEntry2.FontColor = c.TextInactive;
            if isprop(app, 'BtnPickEntry3') && isgraphics(app.BtnPickEntry3)
                app.BtnPickEntry3.FontColor = c.TextInactive;
            end

            % 4. Remove Plot Listeners & Reset Cursor
            if isgraphics(app.AxCutLeft), app.AxCutLeft.ButtonDownFcn = []; end
            if isgraphics(app.AxCutRight), app.AxCutRight.ButtonDownFcn = []; end
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

            % Explicitly lock limits and aspect ratio without using 'axis equal'
            xLims = [bY - buffer, bY + bW + buffer];
            yLims =[bZ - buffer, bZ + bH + buffer];

            xlim(app.AxCutLeft, xLims);
            ylim(app.AxCutLeft, yLims);
            daspect(app.AxCutLeft, [1 1 1]);

            xlim(app.AxCutRight, xLims);
            ylim(app.AxCutRight, yLims);
            daspect(app.AxCutRight, [1 1 1]);
        end

        function onCutAxesClick(app, ax, ~, side)
            cp = ax.CurrentPoint(1, 1:2);
            clickY = cp(1);
            clickZ = cp(2);

            % --- CASE 1: SET START POINT ---
            if app.BtnPickStart.Value

                % Safe multi-output call
                chkP = cell(1,4);[chkP{1}, chkP{2}, chkP{3}, chkP{4}] = app.getSyncedKerfProfiles();
                syncY_L = chkP{1}; syncZ_L = chkP{2}; syncY_R = chkP{3}; syncZ_R = chkP{4};

                yData =[];
                zData =[];
                offsetY = app.BilletShift(2) + app.MachineBilletPos(2);
                offsetZ = app.BilletShift(3) + app.MachineBilletPos(3);

                if strcmp(side, 'Left')
                    if ~isempty(syncY_L)
                        yData = syncY_L + offsetY;
                        zData = syncZ_L + offsetZ;
                    end
                else
                    if ~isempty(syncY_R)
                        yData = syncY_R + offsetY;
                        zData = syncZ_R + offsetZ;
                    end
                end

                if isempty(yData)
                    return;
                end

                distances = (yData - clickY).^2 + (zData - clickZ).^2;
                [~, minIdx] = min(distances);

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

                % --- CASE 2: LEAD IN ---
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

                % --- CASE 3: LINK 1 ---
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

                % --- CASE 4: LINK 2 ---
            elseif isprop(app, 'BtnPickEntry3') && app.BtnPickEntry3.Value
                if strcmp(app.SwitchSyncEntry.Value, 'Coupled')
                    app.EntryPoint3L = cp;
                    app.EntryPoint3R = cp;
                else
                    if strcmp(side, 'Left')
                        app.EntryPoint3L = cp;
                    else
                        app.EntryPoint3R = cp;
                    end
                end
            end

            % FIX: Tell the Gatekeeper the user has manually set up the tab!
            app.IsCuttingUserModified = true;
            app.IsCuttingInit = true;
            app.updateCuttingPlots();
        end

        function onSyncToggleChanged(app, src)
            if strcmp(src.Value, 'Coupled')
                app.SelectedStartIdxR = app.SelectedStartIdxL;
                app.IsCuttingInit = true;
                app.updateCuttingPlots();
            end
        end

        function onSyncEntryToggleChanged(app, src)
            if strcmp(src.Value, 'Coupled')
                app.EntryPointR = app.EntryPointL;
                app.EntryPoint2R = app.EntryPoint2L;
                app.EntryPoint3R = app.EntryPoint3L;
                app.IsCuttingInit = true;
                app.updateCuttingPlots();
            end
        end

        function onAutoStart(app, doPlot)
            if nargin < 2
                doPlot = true;
            end

            chkP = cell(1,4);[chkP{1}, chkP{2}, chkP{3}, chkP{4}] = app.getSyncedKerfProfiles();
            yL_b = chkP{1}; yR_b = chkP{3};

            if isempty(yL_b)
                return;
            end

            [~, idxL] = min(yL_b);[~, idxR] = min(yR_b);

            if strcmp(app.SwitchSyncStart.Value, 'Coupled')
                app.SelectedStartIdxL = idxL;
                app.SelectedStartIdxR = idxL;
            else
                app.SelectedStartIdxL = idxL;
                app.SelectedStartIdxR = idxR;
            end

            % FIX: Tell the Gatekeeper Auto-Start succeeded!
            app.IsCuttingUserModified = false;
            app.IsCuttingInit = true;
            if doPlot
                app.updateCuttingPlots();
            end
        end

        function onAutoEntry(app, doPlot)
            if nargin < 2
                doPlot = true;
            end

            chkP = cell(1,4);[chkP{1}, chkP{2}, chkP{3}, chkP{4}] = app.getSyncedKerfProfiles();
            yL = chkP{1}; zL = chkP{2}; yR = chkP{3}; zR = chkP{4};

            if isempty(yL), return; end

            bMinY = app.MachineBilletPos(2);
            bMaxY = app.MachineBilletPos(2) + app.BilletSize(2);
            bMinZ = app.MachineBilletPos(3);
            bMaxZ = app.MachineBilletPos(3) + app.BilletSize(3);

            offY = app.BilletShift(2) + bMinY;
            offZ = app.BilletShift(3) + bMinZ;
            useDualMode = ~isempty(app.EntryPoint2L);

            function[lead, link1, link2] = calcEntryLogic(y, z, startIdx)
                lead=[]; link1=[]; link2=[];
                N = numel(y);
                if startIdx > N || startIdx < 1, startIdx = 1; end

                idxS = startIdx;
                idxP = mod(startIdx-2, N) + 1;
                idxN = mod(startIdx, N) + 1;

                S = [y(idxS), z(idxS)];
                P =[y(idxP), z(idxP)];
                N_pt =[y(idxN), z(idxN)];

                vIn  = (S - P) / (norm(S - P) + 1e-9);
                vOut = (N_pt - S) / (norm(N_pt - S) + 1e-9);

                vBisect =[-vIn(2), vIn(1)] + [-vOut(2), vOut(1)];
                if norm(vBisect) < 1e-3
                    vBisect = [-vIn(2), vIn(1)];
                end
                vBisect = vBisect / norm(vBisect);

                testPt = S + vBisect * 0.1;
                if inpolygon(testPt(1), testPt(2), y, z)
                    vBisect = -vBisect;
                end

                boxMinY = bMinY - 5.0; boxMaxY = bMaxY + 5.0;
                boxMinZ = bMinZ - 5.0; boxMaxZ = bMaxZ + 5.0;

                t_hits =[];
                if abs(vBisect(1)) > 1e-6
                    t1 = (boxMinY - S(1)) / vBisect(1);
                    t2 = (boxMaxY - S(1)) / vBisect(1);
                    if t1 > 1e-3, t_hits(end+1) = t1; end
                    if t2 > 1e-3, t_hits(end+1) = t2; end
                end

                if abs(vBisect(2)) > 1e-6
                    t3 = (boxMinZ - S(2)) / vBisect(2);
                    t4 = (boxMaxZ - S(2)) / vBisect(2);
                    if t3 > 1e-3, t_hits(end+1) = t3; end
                    if t4 > 1e-3, t_hits(end+1) = t4; end
                end

                if isempty(t_hits)
                    t_final = 20.0;
                else
                    t_final = min(t_hits);
                end

                lead = S + vBisect * t_final;
                if lead(2) < 5.0, lead(2) = 5.0; end

                needsRouting = (lead(2) >= bMaxZ) || (lead(1) >= bMaxY);
                if needsRouting
                    safeZ = bMaxZ + app.MachineSafeHeight;
                    link2 = [lead(1), max(safeZ, lead(2))];
                    link1 = [bMinY - 10.0, safeZ];
                end
            end

            yL_s = yL + offY; zL_s = zL + offZ;
            [eL, l1L, l2L] = calcEntryLogic(yL_s, zL_s, app.SelectedStartIdxL);
            app.EntryPointL=eL; app.EntryPoint2L=l1L; app.EntryPoint3L=l2L;

            if strcmp(app.SwitchSyncEntry.Value, 'Coupled')
                app.EntryPointR=eL; app.EntryPoint2R=l1L; app.EntryPoint3R=l2L;
            else
                yR_s = yR + offY; zR_s = zR + offZ;[eR, l1R, l2R] = calcEntryLogic(yR_s, zR_s, app.SelectedStartIdxR);
                app.EntryPointR=eR; app.EntryPoint2R=l1R; app.EntryPoint3R=l2R;
            end

            % FIX: Tell the Gatekeeper Auto-Entry succeeded!
            app.IsCuttingUserModified = false;
            app.IsCuttingInit = true;

            if doPlot
                app.updateCuttingPlots();
            end
        end

        function [hRapid, hLead, hDot, hLoad] = drawTravelPath(app, ax, startPt, endPt, lead, link1, link2)
            hRapid = gobjects(0);
            hLead = gobjects(0);
            hDot = gobjects(0);
            hLoad = gobjects(0);

            if isempty(startPt) || isempty(lead)
                return;
            end

            pZero    =[0, 0];
            pSafe    = [10, 10];
            pLoad    =[app.MachineBilletPos(2), app.MachineBilletPos(3)+app.BilletSize(3)/2];
            pRetract =[pLoad(1)-10, pLoad(2)];

            hLoad = plot(ax, pLoad(1), pLoad(2), 'x', 'MarkerSize', 8, 'Color', [1 0 1], 'LineWidth', 1.5, 'HitTest','off');

            t = app.getTheme();
            % --- INBOUND PATH ---
            pts =[pZero; pSafe; pLoad; pRetract];
            if ~isempty(link1)
                pts =[pts; link1];
            end
            if ~isempty(link2)
                pts =[pts; link2];
            end
            pts = [pts; lead];

            if size(pts,1) > 1
                hRapid = plot(ax, pts(:,1), pts(:,2), '-', 'Color',[0.9 0.8 0], 'LineWidth',0.5, 'HitTest','off');
            end

            hLead = plot(ax, [lead(1), startPt(1)],[lead(2), startPt(2)], '-', 'Color', t.wireLead, 'LineWidth',0.5, 'HitTest','off');
            % --- OUTBOUND PATH (Retrace) ---
            plot(ax,[endPt(1), lead(1)], [endPt(2), lead(2)], '--', 'Color', t.wireLead, 'LineWidth',1.0, 'HitTest','off');

            ptsOut = lead;
            if ~isempty(link2)
                ptsOut = [ptsOut; link2];
            end
            if ~isempty(link1)
                ptsOut = [ptsOut; link1];
            end

            % Retract back to safe point in front of block
            ptsOut =[ptsOut; pRetract];

            % Home Y First for safety
            pHomeY =[0, pRetract(2)];
            ptsOut = [ptsOut; pHomeY; pZero];

            plot(ax, ptsOut(:,1), ptsOut(:,2), '--', 'Color',[0.9 0.8 0], 'LineWidth',0.5, 'HitTest','off');

            % --- DOTS ---
            hDot = plot(ax, lead(1), lead(2), '.', 'Color',[1 0.5 0], 'MarkerSize', 10, 'HitTest', 'off');

            if ~isempty(link1)
                plot(ax, link1(1), link1(2), '.', 'Color',[0.9 0.8 0], 'MarkerSize',10, 'HitTest','off');
            end
            if ~isempty(link2)
                plot(ax, link2(1), link2(2), '.', 'Color',[0.9 0.8 0], 'MarkerSize',10, 'HitTest','off');
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
            app.EntryPoint3L = []; app.EntryPoint3R = [];
            app.IsCuttingInit = true;
            app.updateCuttingPlots();
        end

        function shiftEntryPoints(app, dY, dZ)
            % Shifts all manual entry points by a given delta so they
            % "stick" to the billet when it is moved.
            if dY == 0 && dZ == 0
                return;
            end

            shift2D =[dY, dZ];

            if ~isempty(app.EntryPointL)
                app.EntryPointL = app.EntryPointL + shift2D;
            end
            if ~isempty(app.EntryPointR)
                app.EntryPointR = app.EntryPointR + shift2D;
            end
            if ~isempty(app.EntryPoint2L)
                app.EntryPoint2L = app.EntryPoint2L + shift2D;
            end
            if ~isempty(app.EntryPoint2R)
                app.EntryPoint2R = app.EntryPoint2R + shift2D;
            end
            if ~isempty(app.EntryPoint3L)
                app.EntryPoint3L = app.EntryPoint3L + shift2D;
            end
            if ~isempty(app.EntryPoint3R)
                app.EntryPoint3R = app.EntryPoint3R + shift2D;
            end
        end

        % ===========================================================
        % SIMULATION LOGIC (Final Clean Version)
        % ===========================================================

        function generateSimulationData(app)

            if isempty(app.AxSim) || ~isgraphics(app.AxSim)
                disp('   -> ERROR: AxSim is missing!'); return;
            end

            t = app.getTheme();
            offsetY = app.BilletShift(2) + app.MachineBilletPos(2);
            offsetZ = app.BilletShift(3) + app.MachineBilletPos(3);
            isCCW   = strcmp(app.SwitchCutDir.Value, 'Bottom (CCW)');

            d1 = 0; % Anti-markdown bug
            [syncY_L, syncZ_L, syncY_R, syncZ_R] = app.getSyncedKerfProfiles();

            d2 = 0; % Anti-markdown bug
            [yL, zL] = app.applyMods(syncY_L, syncZ_L, offsetY, offsetZ, app.SelectedStartIdxL, isCCW);
            [yR, zR] = app.applyMods(syncY_R, syncZ_R, offsetY, offsetZ, app.SelectedStartIdxR, isCCW);

            if isempty(yL) || isempty(yR)
                disp('   -> ERROR: applyMods returned empty arrays!');
                uialert(app.UIFigure, 'Could not generate toolpath. Profiles may be empty or invalid.', 'Simulation Error');
                return;
            end

            app.ProfileSyncL = [yL(:), zL(:)];
            app.ProfileSyncR = [yR(:), zR(:)];

            % Helper for Segments
            function pts = mkRapid(lead, link1, link2)
                pZero=[0,0]; pSafe=[10,10];
                pLoad=[app.MachineBilletPos(2), app.MachineBilletPos(3)+app.BilletSize(3)/2];
                pRet=[pLoad(1)-10, pLoad(2)];
                pts=[pZero; pSafe; pLoad; pRet];

                if ~isempty(link1), pts=[pts; link1]; end
                if ~isempty(link2), pts=[pts; link2]; end
                if ~isempty(lead), pts=[pts; lead]; end
            end

            function pts = mkLeadIn(start, lead)
                if isempty(lead)
                    pRet=[app.MachineBilletPos(2)-10, app.MachineBilletPos(3)+app.BilletSize(3)/2];
                    pts=[pRet; start];
                else
                    pts=[lead; start];
                end
            end

            function pts = mkLeadOut(en, lead)
                if isempty(lead)
                    pts=[en; en]; % Fallback
                else
                    pts=[en; lead];
                end
            end

            function pts = mkReturn(lead, link1, link2)
                if isempty(lead)
                    pts = [0, 0]; return;
                end
                pts = lead;
                if ~isempty(link2), pts = [pts; link2];
                end
                if ~isempty(link1), pts = [pts; link1];
                end

                pRetract =[app.MachineBilletPos(2)-10, app.MachineBilletPos(3)+app.BilletSize(3)/2];
                pts = [pts; pRetract;
                    [0, pRetract(2)];
                    [0, 0]];
            end

            rawRapL = mkRapid(app.EntryPointL, app.EntryPoint2L, app.EntryPoint3L);
            rawRapR = mkRapid(app.EntryPointR, app.EntryPoint2R, app.EntryPoint3R);

            rawLiL = mkLeadIn([yL(1),zL(1)], app.EntryPointL);
            rawLiR = mkLeadIn([yR(1),zR(1)], app.EntryPointR);

            rawLoL = mkLeadOut([yL(end),zL(end)], app.EntryPointL);
            rawLoR = mkLeadOut([yR(end),zR(end)], app.EntryPointR);

            rawRetL = mkReturn(app.EntryPointL, app.EntryPoint2L, app.EntryPoint3L);
            rawRetR = mkReturn(app.EntryPointR, app.EntryPoint2R, app.EntryPoint3R);

            % 3. Densify Segments
            function [yLD, zLD, yRD, zRD] = densifySynced(yiL, ziL, yiR, ziR, step)
                if nargin < 5, step = HotWireSTEPApp_v6_2.SimSpatialResolution; end
                N = numel(yiL);
                if N < 2
                    yLD=yiL; zLD=ziL; yRD=yiR; zRD=ziR; return;
                end
                distL = [0; cumsum(hypot(diff(yiL), diff(ziL)))];
                distR = [0; cumsum(hypot(diff(yiR), diff(ziR)))];

                maxL = distL(end); if maxL < 1e-6, maxL = 1; end
                maxR = distR(end); if maxR < 1e-6, maxR = 1; end

                sL = distL / maxL; sR = distR / maxR;
                s_orig = (sL + sR) / 2;
                totalLen = max(distL(end), distR(end));

                nSteps = max(N, ceil(totalLen / step));
                s_smooth = linspace(0, 1, nSteps)';
                s_combined = unique([s_orig; s_smooth]);

                [su, iu] = unique(s_orig, 'stable');
                yLD = interp1(su, yiL(iu), s_combined, 'linear');
                zLD = interp1(su, ziL(iu), s_combined, 'linear');
                yRD = interp1(su, yiR(iu), s_combined, 'linear');
                zRD = interp1(su, ziR(iu), s_combined, 'linear');
            end

            function out = densifyWaypoints(yiL, ziL, yiR, ziR, step)
                if nargin < 5, step = HotWireSTEPApp_v6_2.SimSpatialResolution; end
                N_max = max(numel(yiL), numel(yiR));

                if numel(yiL) < N_max
                    padCount = N_max - numel(yiL);
                    yiL =[yiL; repmat(yiL(end), padCount, 1)];
                    ziL =[ziL; repmat(ziL(end), padCount, 1)];
                end
                if numel(yiR) < N_max
                    padCount = N_max - numel(yiR);
                    yiR = [yiR; repmat(yiR(end), padCount, 1)];
                    ziR = [ziR; repmat(ziR(end), padCount, 1)];
                end

                yLD=[]; zLD=[]; yRD=[]; zRD=[];
                for i = 1:(N_max-1)
                    d1 = hypot(yiL(i+1)-yiL(i), ziL(i+1)-ziL(i));
                    d2 = hypot(yiR(i+1)-yiR(i), ziR(i+1)-ziR(i));
                    N_pts = max(2, ceil(max(d1, d2) / step));

                    yLD =[yLD; linspace(yiL(i), yiL(i+1), N_pts)'];
                    zLD =[zLD; linspace(ziL(i), ziL(i+1), N_pts)'];
                    yRD =[yRD; linspace(yiR(i), yiR(i+1), N_pts)'];
                    zRD =[zRD; linspace(ziR(i), ziR(i+1), N_pts)'];

                    if i < N_max-1
                        yLD(end)=[]; zLD(end)=[]; yRD(end)=[]; zRD(end)=[];
                    end
                end
                out.yL = yLD; out.zL = zLD; out.yR = yRD; out.zR = zRD;
            end

            tmp = densifyWaypoints(rawRapL(:,1), rawRapL(:,2), rawRapR(:,1), rawRapR(:,2));
            dRapL_y = tmp.yL; dRapL_z = tmp.zL; dRapR_y = tmp.yR; dRapR_z = tmp.zR;

            tmp = densifyWaypoints(rawLiL(:,1), rawLiL(:,2), rawLiR(:,1), rawLiR(:,2));
            dLiL_y = tmp.yL; dLiL_z = tmp.zL; dLiR_y = tmp.yR; dLiR_z = tmp.zR;

            d3 = 0; % Anti-markdown bug
            [dProfL_y, dProfL_z, dProfR_y, dProfR_z] = densifySynced(yL, zL, yR, zR);

            tmp = densifyWaypoints(rawLoL(:,1), rawLoL(:,2), rawLoR(:,1), rawLoR(:,2));
            dLoL_y = tmp.yL; dLoL_z = tmp.zL; dLoR_y = tmp.yR; dLoR_z = tmp.zR;

            tmp = densifyWaypoints(rawRetL(:,1), rawRetL(:,2), rawRetR(:,1), rawRetR(:,2));
            dRetL_y = tmp.yL; dRetL_z = tmp.zL; dRetR_y = tmp.yR; dRetR_z = tmp.zR;

            app.SimRapidCutoffIndex  = numel(dRapL_y);
            app.SimProfileStartIndex = app.SimRapidCutoffIndex + numel(dLiL_y);
            app.SimFeedEndIndex      = app.SimProfileStartIndex + numel(dProfL_y);
            app.SimLeadOutEndIndex   = app.SimFeedEndIndex + numel(dLoL_y);

            fullY_L =[dRapL_y; dLiL_y; dProfL_y; dLoL_y; dRetL_y];
            fullZ_L =[dRapL_z; dLiL_z; dProfL_z; dLoL_z; dRetL_z];
            fullY_R =[dRapR_y; dLiR_y; dProfR_y; dLoR_y; dRetR_y];
            fullZ_R =[dRapR_z; dLiR_z; dProfR_z; dLoR_z; dRetR_z];

            if ~isempty(app.LeftProfilePoints)
                xL = app.LeftProfilePoints(1,1);
            else
                xL = app.MachineBilletPos(1);
            end

            if ~isempty(app.RightProfilePoints)
                xR = app.RightProfilePoints(1,1);
            else
                xR = app.MachineBilletPos(1)+10;
            end

            xL = xL + app.BilletShift(1) + app.MachineBilletPos(1);
            xR = xR + app.BilletShift(1) + app.MachineBilletPos(1);

            app.SimPathL =[repmat(xL, numel(fullY_L), 1), fullY_L, fullZ_L];
            app.SimPathR =[repmat(xR, numel(fullY_R), 1), fullY_R, fullZ_R];

            dL = sqrt(sum(diff(app.SimPathL).^2, 2)); dL(isnan(dL)) = 0;
            dR = sqrt(sum(diff(app.SimPathR).^2, 2)); dR(isnan(dR)) = 0;
            app.SimArcLenL =[0; cumsum(dL)];
            app.SimArcLenR =[0; cumsum(dR)];
            app.SimTotalLength = max(app.SimArcLenL(end), app.SimArcLenR(end));
            app.SimPlayDist = 0;

            V = app.SimPathR - app.SimPathL;
            tL = -app.SimPathL(:,1) ./ V(:,1);
            tR = (app.MachineSpanX - app.SimPathL(:,1)) ./ V(:,1);
            app.SimTowerPathL = app.SimPathL + tL .* V;
            app.SimTowerPathR = app.SimPathL + tR .* V;

            % --- 1. CALCULATE PROGRAM BOUNDS (Ignore Homing/Return) ---
            % We only look at points from the start of Lead-In to the end of Lead-Out
            progIdx = (app.SimRapidCutoffIndex):app.SimLeadOutEndIndex;

            % Extract working paths
            workL = app.SimTowerPathL(progIdx, :);
            workR = app.SimTowerPathR(progIdx, :);

            % Tower L (Visual X/Y in G-code)
            app.TowerL_Bounds = [min(workL(:,2)), max(workL(:,2)), ...
                min(workL(:,3)), max(workL(:,3))];
            % Tower R (Visual Z/A in G-code)
            app.TowerR_Bounds = [min(workR(:,2)), max(workR(:,2)), ...
                min(workR(:,3)), max(workR(:,3))];

            % --- 2. UPDATE SIM UI LABELS (G-Code Format) ---
            if isgraphics(app.LblSimExtMin)
                app.LblSimExtMin.Text = sprintf('Min: X=%.2f  Y=%.2f  Z=%.2f  A=%.2f', ...
                    app.TowerL_Bounds(1), app.TowerL_Bounds(3), app.TowerR_Bounds(1), app.TowerR_Bounds(3));

                app.LblSimExtMax.Text = sprintf('Max: X=%.2f Y=%.2f Z=%.2f A=%.2f', ...
                    app.TowerL_Bounds(2), app.TowerL_Bounds(4), app.TowerR_Bounds(2), app.TowerR_Bounds(4));

                app.LblSimExtWire.Text = sprintf('Max Wire Extension:%.2fmm (Limit:%.0fmm)', ...
                    app.MaxPathExtension, app.WireExt_Red);
            end

            nPoints = size(app.SimPathL, 1);
            app.SimSlider.Limits =[1, max(1, nPoints)];
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
            ax = app.AxSim;
            cla(ax);
            hold(ax,'on');
            t = app.getTheme(); % <--- Master Palette

            % Setup Geometry
            offX = app.MachineBedPos(1);
            mSpan = app.MachineSpanX;
            bp = app.MachineBilletPos;
            bSize = app.BilletSize;

            d1 = 0; % Anti-markdown bug
            [xb,yb,zb] = app.makeBoxVertices(0, app.MachineBedPos(2), -20, 1000, 700, 20); % Bed

            patch(ax, 'Vertices',[xb,yb,zb], 'Faces',app.boxFaces, 'FaceColor', t.bedCol, 'FaceAlpha',0.5, 'EdgeColor', t.bedEdge);

            patch(ax, 'XData',ones(4,1)*(-offX), 'YData',[0;750;750;0], 'ZData',[0;0;500;500], 'FaceColor',t.planeRed, 'FaceAlpha',0.15, 'EdgeColor',t.planeRed);
            patch(ax, 'XData',ones(4,1)*(mSpan-offX), 'YData',[0;750;750;0], 'ZData',[0;0;500;500], 'FaceColor',t.planeGreen, 'FaceAlpha',0.15, 'EdgeColor',t.planeGreen);

            % Billet & Model
            bX = bp(1)-offX;
            bY = bp(2);
            bZ = bp(3);

            d2 = 0; % Anti-markdown bug
            [xm,ym,zm] = app.makeBoxVertices(bX,bY,bZ, bSize(1),bSize(2),bSize(3));

            patch(ax, 'Vertices',[xm,ym,zm], 'Faces',app.boxFaces, 'FaceColor', t.billetColor, 'FaceAlpha', t.billetAlpha, 'EdgeColor',t.labelCol, 'LineStyle','--');

            if ~isempty(app.ModelPatch)
                patch(ax, 'Vertices', app.ModelPatch.Vertices+[bX,bY,bZ]+app.BilletShift, 'Faces',app.ModelPatch.Faces, ...
                    'FaceColor', t.modelColor, 'FaceAlpha', t.modelAlpha, 'EdgeColor','none', 'Tag','SimModel');
            end

            % --- NEW: Ghost Profiles in neutral Grey ---
            if ~isempty(app.LeftProfilePoints) && ~isempty(app.RightProfilePoints)

                d3 = 0; % Anti-markdown bug
                [yS_rawL, zS_rawL, yS_rawR, zS_rawR] = HotWireSTEPApp_v6_helpers.syncPointCounts(...
                    app.LeftProfilePoints(:,2), app.LeftProfilePoints(:,3), ...
                    app.RightProfilePoints(:,2), app.RightProfilePoints(:,3));

                totalShift = bp + app.BilletShift;
                xL_world = app.LeftProfilePoints(1,1) + totalShift(1) - offX;
                xR_world = app.RightProfilePoints(1,1) + totalShift(1) - offX;

                plot3(ax, xL_world * ones(size(yS_rawL)), yS_rawL + totalShift(2), zS_rawL + totalShift(3), ...
                    'Color', t.ghostNeutral, 'LineWidth', 0.5, 'LineStyle', '-', 'Tag', 'SimGhostL');
                plot3(ax, xR_world * ones(size(yS_rawR)), yS_rawR + totalShift(2), zS_rawR + totalShift(3), ...
                    'Color', t.ghostNeutral, 'LineWidth', 0.5, 'LineStyle', '-', 'Tag', 'SimGhostR');
            end

            % --- Dynamic Elements ---
            % Wire
            plot3(ax,NaN,NaN,NaN, 'Color',t.wireKerf, 'LineWidth',0.2, 'Tag','SimWire');

            plot3(ax,NaN,NaN,NaN, 'o', 'Color', t.planeRed, 'MarkerEdgeColor', t.planeRed, 'MarkerFaceColor', t.planeRed, 'MarkerSize', 2, 'Tag','SimDotL');
            plot3(ax,NaN,NaN,NaN, 'o', 'Color', t.planeGreen, 'MarkerEdgeColor', t.planeGreen, 'MarkerFaceColor', t.planeGreen, 'MarkerSize', 2, 'Tag','SimDotR');

            plot3(ax,NaN,NaN,NaN, 'o', 'Color', t.planeRed, 'MarkerEdgeColor', t.planeRed, 'MarkerFaceColor', t.planeRed, 'MarkerSize', 2, 'Tag','SimModelDotL');
            plot3(ax,NaN,NaN,NaN, 'o', 'Color', t.planeGreen, 'MarkerEdgeColor', t.planeGreen, 'MarkerFaceColor', t.planeGreen, 'MarkerSize', 2, 'Tag','SimModelDotR');

            % Trails
            tags = {'Rapid','LeadIn','Feed','LeadOut','Return'};
            cols = {[0.9 0.8 0], t.wireLead, t.planeRed, t.wireLead,[0.9 0.8 0]};
            styles = {'-','-','-','--','--'};

            for i=1:5
                colL = cols{i};
                colR = cols{i};

                % Separate Feed Colors so Right Tower isn't Red!
                if i==3
                    colL = t.planeRed;
                    colR = t.planeGreen;
                end

                plot3(ax,NaN,NaN,NaN, styles{i}, 'Color',colL, 'LineWidth',0.5, 'Tag',['SimTower' tags{i} 'L']);
                plot3(ax,NaN,NaN,NaN, styles{i}, 'Color',colR, 'LineWidth',0.5, 'Tag',['SimTower' tags{i} 'R']);

                plot3(ax,NaN,NaN,NaN, styles{i}, 'Color',colL, 'LineWidth',0.5, 'Tag',['SimModel' tags{i} 'L']);
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

            % Calculate extension: dL = sqrt(Span^2 + dy^2 + dz^2) - Span
            dy = pTL(2) - pTR(2);
            dz = pTL(3) - pTR(3);
            ext = hypot(app.MachineSpanX, hypot(dy, dz)) - app.MachineSpanX;

            % Update Gauge
            app.SimGaugeExt.Value = min(ext, app.SimGaugeExt.Limits(2));

        end

        % --- Interaction Handlers ---
        function onSimPlay(app)
            if isempty(app.SimPathL), return; end
            if app.SimPlayDist >= app.SimTotalLength - 1e-3, app.SimPlayDist = 0; end

            if isempty(app.SimTimer) || ~isvalid(app.SimTimer)
                % FIX: Use the global Frame Rate constant to calculate Timer Period
                periodSec = 1.0 / HotWireSTEPApp_v6_2.SimFramesPerSecond;
                app.SimTimer = timer('ExecutionMode', 'fixedRate', 'Period', periodSec, 'TimerFcn', @(~,~)app.onSimTimerTick());
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
            % --- REAL-TIME SPEED SYNC ---
            % Safely fetch feed rate (fallback to default if Post tab isn't built)
            if ~isempty(app.SpinFeedRate) && isgraphics(app.SpinFeedRate)
                feed_mm_min = app.SpinFeedRate.Value;
            else
                feed_mm_min = HotWireSTEPApp_v6_2.DefaultFeedRate;
            end

            feed_mm_sec = feed_mm_min / 60.0;

            % Use the global Frame Rate constant to calculate frame distance
            periodSec = 1.0 / HotWireSTEPApp_v6_2.SimFramesPerSecond;
            baseStepDist = feed_mm_sec * periodSec;

            % Safely fetch speed multiplier
            if ~isempty(app.SimSpeedSpinner) && isgraphics(app.SimSpeedSpinner)
                speedMult = app.SimSpeedSpinner.Value;
            else
                speedMult = 40.0;
            end

            step = baseStepDist * speedMult;

            app.SimPlayDist = app.SimPlayDist + step;

            isDone = false;
            if app.SimPlayDist >= app.SimTotalLength
                app.SimPlayDist = app.SimTotalLength;
                isDone = true;
            end

            idx = app.simIndexAtDistance(app.SimPlayDist);
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
            rawName = "Output";
            if ~isempty(app.CurrentModelName)
                [ ~, rawName, ~ ] = fileparts(app.CurrentModelName);
            end

            rawName = replace(rawName, ' ', '_');
            newName = sprintf("GCode-V1-%s", rawName);

            currentVal = app.FieldFilename.Value;

            if isempty(currentVal) || startsWith(currentVal, "GCode-V1-")
                app.FieldFilename.Value = newName;
            end

            % Update the new status block
            app.updatePostStatus();
        end

        function updatePostStatus(app, isFreshPost)
            if nargin < 2, isFreshPost = false; end % Default: assume parameter changed
            if isempty(app.TxtPostStatus) || ~isvalid(app.TxtPostStatus), return; end

            t = app.getTheme();
            feed = app.SpinFeedRate.Value;
            power = app.SpinPower.Value;

            % 1. Logic: If parameters changed (not a fresh post), invalidate old code
            if ~isFreshPost && ~isempty(app.PP_GCodeLines)
                app.PP_GCodeLines = strings(0);
                app.ListGCode.Items = {'(Parameters changed. Re-run Post-Process...)'};
                app.BtnSaveGCode.Enable = 'off';
                app.BtnSaveGCode.BackgroundColor = [0.3 0.3 0.3];
            end

            msg = strings(0);
            % Default to neutral theme background
            panelBg = t.sideBg;
            textCol = t.labelCol;

            % --- 2. DETERMINE STATUS STATE & COLOR ---
            msg = strings(0);

            % Default to Success (Green) if G-code exists, else Stale (Red)
            if isempty(app.PP_GCodeLines)
                panelBg = t.statErrBg;
                textCol = t.statErrTxt;
                msg = ["STALE G-CODE:", "Parameters changed. Re-run Post-Process."];
            else
                panelBg = t.statPassBg;
                textCol = t.statPassTxt;
                msg(end+1) = sprintf("Success! Generated %d lines.", numel(app.PP_GCodeLines));
            end

            % --- 3. APPLY SAFETY OVERRIDES (Priority: Red > Amber) ---

            % Check A: Wire Extension (Mechanical Limit)
            isExtRed   = app.MaxPathExtension > app.WireExt_Red;
            isExtAmber = app.MaxPathExtension > app.WireExt_Amber;

            if isExtRed
                panelBg = t.statErrBg;
                textCol = t.statErrTxt;
                msg(end+1) = "CRITICAL: Wire Extension exceeds pulley travel!";
            elseif isExtAmber
                % Only upgrade to Amber if we aren't already Red
                if ~isequal(panelBg, t.statErrBg)
                    panelBg = t.statWarnBg;
                    textCol = t.statWarnTxt;
                end
                msg(end+1) = "WARNING: Approaching mechanical pulley limit.";
            end

            % Check B: Feed/Power Balance
            if (power < 25 && feed > 80) || (power > 80 && feed < 30)
                % Only upgrade to Amber if we aren't already Red
                if ~isequal(panelBg, t.statErrBg)
                    panelBg = t.statWarnBg;
                    textCol = t.statWarnTxt;
                end
                msg(end+1) = "WARNING: Unbalanced Power/Feed settings.";
            end

            % Final instruction line
            if ~isempty(app.PP_GCodeLines)
                msg(end+1) = "Verify paths and click Save.";
            end

            % --- 4. APPLY TO UI ---
            app.PostLeftPanel.BackgroundColor = panelBg;
            app.TxtPostStatus.Value = msg;
            app.TxtPostStatus.FontColor = textCol;
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

            % 1. Rapid (Yellow) - Path from Start to Entry Point
            curEnd = min(idx, idxRapidEnd);
            updateT('PostTowerRapidL', towerL, 1, curEnd);
            updateT('PostTowerRapidR', towerR, 1, curEnd);
            updateT('PostModelRapidL', pathL,  1, curEnd);
            updateT('PostModelRapidR', pathR,  1, curEnd);

            % 2. Lead In (Orange) - Path from Entry Point to Profile Start
            if idx > idxRapidEnd
                curEnd = min(idx, idxProfStart);
                % We start drawing from RapidEnd (the Entry Point)
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
                    uialert(app.UIFigure, 'No path data available.', 'Error');
                    return;
                end
            end

            % --- DATA SYNC ---
            app.PP_PathL = zeros(0,3);
            app.PP_PathR = zeros(0,3);
            app.PP_TowerPathL = zeros(0,3);
            app.PP_TowerPathR = zeros(0,3);

            % 2. Prepare Settings
            feed  = round(app.SpinFeedRate.Value);
            power = round(app.SpinPower.Value);
            lines = strings(0,1);
            map = zeros(0,1);
            pathIdx = 0;

            % --- ALIGNMENT & HELPERS ---
            baseX = app.MachineBilletPos(1) + app.BilletShift(1) + app.ModelXMin;
            xM_L = baseX + app.NumLeftOffset.Value;
            xM_R = baseX + app.NumRightOffset.Value;
            xT_L = 0;
            xT_R = app.MachineSpanX;

            mDim = [abs(xM_R - xM_L), app.ModelYMax - app.ModelYMin, app.ModelZMax - app.ModelZMin];

            % Nested Helper 1: Project Model YZ to Tower Coordinates
            function [tx, ty, tz, ta] = project(yL, zL, yR, zR)
                rL = (xT_L - xM_L) / (xM_R - xM_L);
                tyL = yL + (yR - yL) * rL;
                tzL = zL + (zR - zL) * rL;
                rR = (xT_R - xM_L) / (xM_R - xM_L);
                tyR = yL + (yR - yL) * rR;
                tzR = zL + (zR - zL) * rR;
                tx = tyL; ty = tzL; tz = tyR; ta = tzR;
            end

            % Nested Helper 2: Reverse Project for Verification Plotting
            function [mxL, myL, mzL, mxR, myR, mzR] = machineToModelVisual(tx, ty, tz, ta)
                ratioL = (xM_L - xT_L) / (xT_R - xT_L);
                ratioR = (xM_R - xT_L) / (xT_R - xT_L);
                mxL = xM_L; myL = tx + (tz - tx) * ratioL; mzL = ty + (ta - ty) * ratioL;
                mxR = xM_R; myR = tx + (tz - tx) * ratioR; mzR = ty + (ta - ty) * ratioR;
            end

            % Nested Helper 3: Add Line to G-Code list and map path
            function add(code, comment, tx, ty, tz, ta)
                if nargin >= 2 && ~isempty(char(comment))
                    if startsWith(strtrim(comment), '(')
                        s = sprintf('%-35s %s', code, comment);
                    else
                        s = sprintf('%-35s (%s)', code, comment);
                    end
                else
                    s = code;
                end

                lines(end+1) = s;

                if nargin >= 6
                    % Only increment index and record position if we have movement
                    pathIdx = pathIdx + 1;
                    app.PP_TowerPathL(pathIdx,:) = [xT_L, tx, ty];
                    app.PP_TowerPathR(pathIdx,:) = [xT_R, tz, ta];
                    [mxL, myL, mzL, mxR, myR, mzR] = machineToModelVisual(tx, ty, tz, ta);
                    app.PP_PathL(pathIdx,:) = [mxL, myL, mzL];
                    app.PP_PathR(pathIdx,:) = [mxR, myR, mzR];
                end

                % Map this line of G-code to the last known path position
                map(end+1) = max(1, pathIdx);
            end

            % Nested Helper 4: Dynamic Feed G1 Move
            function addDynamicG1(targL, tgtR, prevL, prevR, commentStr)
                [tx, ty, tz, ta] = project(targL(1), targL(2), tgtR(1), tgtR(2));
                [px, py, pz, pa] = project(prevL(1), prevL(2), prevR(1), prevR(2));

                if app.ChkDynamicFeed.Value
                    distL_model = hypot(targL(1) - prevL(1), targL(2) - prevL(2));
                    distR_model = hypot(tgtR(1) - prevR(1), tgtR(2) - prevR(2));
                    dist_Model_Max = max(distL_model, distR_model);
                    dist_Mach4 = sqrt((tx - px)^2 + (ty - py)^2 + (tz - pz)^2 + (ta - pa)^2);

                    if dist_Model_Max > 1e-5
                        dynF = feed * (dist_Mach4 / dist_Model_Max);
                    else
                        dynF = feed;
                    end
                    if dynF > 1500.0, dynF = 1500.0; end
                    add(sprintf('G1 X%.3f Y%.3f Z%.3f A%.3f F%.1f', tx, ty, tz, ta, dynF), commentStr, tx, ty, tz, ta);
                else
                    add(sprintf('G1 X%.3f Y%.3f Z%.3f A%.3f', tx, ty, tz, ta), commentStr, tx, ty, tz, ta);
                end
            end

            % --- 4. G-CODE GENERATION ---
            pSyncL = app.ProfileSyncL;
            pSyncR = app.ProfileSyncR;

            add('%% ------------------------------------------');
            add(sprintf('%%     File: %s', app.FieldFilename.Value));
            add(sprintf('%%    Model: %s', app.CurrentModelName));
            add(sprintf('%%     Date: %s', string(datetime('now'))));
            add(sprintf('%%    Model: X=%.2fmm Y=%.2fmm Z=%.2fmm', mDim));
            add(sprintf('%%   Billet: X=%.2fmm Y=%.2fmm Z=%.2fmm', app.BilletSize));

            uiBilletPos = app.MachineBilletPos;
            uiBilletPos(1) = uiBilletPos(1) - app.MachineBedPos(1);
            add(sprintf('%% Position: X=%.2fmm Y=%.2fmm Z=%.2fmm', uiBilletPos));

            add('% ------------------------------------------');
            add('%%EXTENTS_MIN%%');
            add('%%EXTENTS_MAX%%');
            add('%%WIRE_EXTENSION_MAX%%');
            add('% ------------------------------------------');
            add('G21','Metric');
            add('G90','Absolute');
            add('G94','Feed/min');

            % --- START SEQUENCE ---
            add('G53 G0 X0 Z0', 'Safe Start: Horizontals', 0, 0, 0, 0);
            add('G53 G0 Y0 A0', 'Safe Start: Verticals', 0, 0, 0, 0);

            % --- PHASE 1: LOAD ---
            add('%% --- LOADING ---', '');
            add('G0 X10.00 Y10.00 Z10.00 A10.00', 'Safe Position', 10, 10, 10, 10);
            bY = app.MachineBilletPos(2);
            bZ = app.MachineBilletPos(3) + app.BilletSize(3)/2;
            add(sprintf('G0 X%.3f Y%.3f Z%.3f A%.3f', bY, bZ, bY, bZ), 'Load Position', bY, bZ, bY, bZ);
            add('M00', 'STOP: Load Block');
            bY_Ret = bY - 4.0;
            add(sprintf('G0 X%.3f Y%.3f Z%.3f A%.3f', bY_Ret, bZ, bY_Ret, bZ), 'Retract Safety', bY_Ret, bZ, bY_Ret, bZ);

            % --- PHASE 2: APPROACH & LEAD-IN ---
            add('%% --- APPROACH ---', '');
            e1L = app.EntryPointL;  e1R = app.EntryPointR;
            e2L = app.EntryPoint2L; e2R = app.EntryPoint2R;
            e3L = app.EntryPoint3L; e3R = app.EntryPoint3R;

            if ~isempty(e2L)
                [tx, ty, tz, ta] = project(e2L(1), e2L(2), e2R(1), e2R(2));
                add(sprintf('G0 X%.3f Y%.3f Z%.3f A%.3f', tx, ty, tz, ta), 'Link Point 1', tx, ty, tz, ta);
            end
            if ~isempty(e3L)
                [tx, ty, tz, ta] = project(e3L(1), e3L(2), e3R(1), e3R(2));
                add(sprintf('G0 X%.3f Y%.3f Z%.3f A%.3f', tx, ty, tz, ta), 'Link Point 2', tx, ty, tz, ta);
            end
            if ~isempty(e1L)
                [tx, ty, tz, ta] = project(e1L(1), e1L(2), e1R(1), e1R(2));
                add(sprintf('G0 X%.3f Y%.3f Z%.3f A%.3f', tx, ty, tz, ta), 'Rapid to Entry Point', tx, ty, tz, ta);
            end
            app.PP_RapidEndIndex = pathIdx;

            % Heat Sequence
            add(sprintf('S%d', power), 'Sets Hot Wire Power');
            add('M301', 'Extraction ON > Wait 5s > Power ON');
            add(sprintf('F%d', feed), 'Set Cut Feedrate');

            % Lead-In Cut (The first orange move)
            startL = pSyncL(1,:); startR = pSyncR(1,:);
            if ~isempty(e1L)
                addDynamicG1(startL, startR, e1L, e1R, 'Lead-In Cut to Profile');
            else
                prevL = [bY_Ret, bZ]; prevR = [bY_Ret, bZ];
                addDynamicG1(startL, startR, prevL, prevR, 'Approach Cut to Profile');
            end
            app.PP_ProfileStartIndex = pathIdx;

            % --- PHASE 3: PROFILE ---
            add('%% --- PROFILE CUT ---', '');
            for i = 2:size(pSyncL, 1)
                addDynamicG1(pSyncL(i,:), pSyncR(i,:), pSyncL(i-1,:), pSyncR(i-1,:), '');
            end
            app.PP_ProfileEndIndex = pathIdx;

            % --- PHASE 4: EXIT ---
            add('%% --- EXIT SEQUENCE ---', '');
            if ~isempty(e1L)
                addDynamicG1(e1L, e1R, pSyncL(end,:), pSyncR(end,:), 'Lead-Out Cut to Entry');
            end
            app.PP_LeadOutEndIndex = pathIdx;
            add('M302', 'Hot Wire Power OFF > Wait > Ext OFF');

            % Correct Order for Retraction
            if ~isempty(e3L)
                [tx, ty, tz, ta] = project(e3L(1), e3L(2), e3R(1), e3R(2));
                add(sprintf('G0 X%.3f Y%.3f Z%.3f A%.3f', tx, ty, tz, ta), 'Return to Link 2', tx, ty, tz, ta);
            end
            if ~isempty(e2L)
                [tx, ty, tz, ta] = project(e2L(1), e2L(2), e2R(1), e2R(2));
                add(sprintf('G0 X%.3f Y%.3f Z%.3f A%.3f', tx, ty, tz, ta), 'Return to Link 1', tx, ty, tz, ta);
            end

            bY_RetFinal = app.MachineBilletPos(2) - 10.0;
            bZ_RetFinal = app.MachineBilletPos(3) + app.BilletSize(3) / 2.0;
            [tx, ty, tz, ta] = project(bY_RetFinal, bZ_RetFinal, bY_RetFinal, bZ_RetFinal);
            add(sprintf('G0 X%.3f Y%.3f Z%.3f A%.3f', tx, ty, tz, ta), 'Retract Safety', tx, ty, tz, ta);

            % --- FINAL RETURN (Split G53) ---
            % Step 1: Retract Horizontals (X, Z) to 0, keeping current Vertical height (bZ_RetFinal)
            add('G53 G0 X0 Z0', 'Retract Horizontals', 0, bZ_RetFinal, 0, bZ_RetFinal);

            % Step 2: Retract Verticals (Y, A) to 0
            add('G53 G0 Y0 A0', 'Retract Verticals', 0, 0, 0, 0);

            add('M30', 'End Program');

            % --- FINALIZE ---
            % 1. Extract values from pre-calculated TowerL_Bounds [minY, maxY, minZ, maxZ]
            minX_v = app.TowerL_Bounds(1); maxX_v = app.TowerL_Bounds(2);
            minY_v = app.TowerL_Bounds(3); maxY_v = app.TowerL_Bounds(4);

            minZ_v = app.TowerR_Bounds(1); maxZ_v = app.TowerR_Bounds(2);
            minA_v = app.TowerR_Bounds(3); maxA_v = app.TowerR_Bounds(4);

            % 2. Create formatted G-code comment strings
            mStr = sprintf('%% Extents Min: X=%.2f Y=%.2f Z=%.2f A=%.2f', minX_v, minY_v, minZ_v, minA_v);
            MStr = sprintf('%% Extents Max: X=%.2f Y=%.2f Z=%.2f A=%.2f', maxX_v, maxY_v, maxZ_v, maxA_v);
            EStr = sprintf('%% Max Wire Extension: %.2f mm (Limit: %.0f mm)', app.MaxPathExtension, app.WireExt_Red);

            % 3. Swap the placeholders in the 'lines' string array
            lines = replace(lines, '%%EXTENTS_MIN%%', mStr);
            lines = replace(lines, '%%EXTENTS_MAX%%', MStr);
            lines = replace(lines, '%%WIRE_EXTENSION_MAX%%', EStr);

            % 4. Update UI
            app.PP_GCodeLines = lines;
            app.PP_LineToPathIndex = map;
            app.ListGCode.Items = cellstr(lines);
            app.ListGCode.ItemsData = 1:numel(lines);
            app.ListGCode.Value = 1;
            app.BtnSaveGCode.Enable = 'on';

            if isempty(app.AxSim.Children), app.initSimulationPlot(); end
            app.initPostPlot();
            app.updatePostPlotForSelectedLine(1);
            app.updatePostStatus(true); % Pass 'true' to signify this is a fresh post
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
            if isempty(app.TabGroup) || ~isequal(app.TabGroup.SelectedTab, app.TabPostProcess)
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
        function th = getTheme(app)
            % Central source for all App Colors
            if ispref('HotWireSTEPApp', 'Theme')
                themeStr = getpref('HotWireSTEPApp', 'Theme');
            else
                themeStr = 'Dark';
            end

            isDark = strcmp(themeStr, 'Dark');

            if isDark
                % --- DARK THEME ---
                th.sideBg      =[0.16 0.16 0.16];
                th.panelBg     =[0.12 0.12 0.12];
                th.labelCol    =[0.90 0.90 0.90];
                th.accentBg    =[0.30 0.35 0.45];
                th.editBg      =[0.24 0.24 0.24];
                th.editTxt     =[1.00 1.00 1.00];
                th.readoutBg   =[0.70 0.70 0.70];
                th.readoutTxt  =[0.20 0.20 0.20];

                % FIX: Standard inputs are now dark grey in dark mode!
                th.inputBg     =[0.24 0.24 0.24];
                th.inputTxt    =[1.00 1.00 1.00];

                % FIX: The carefully chosen Billet Shift/Size accent background
                th.shiftBg     = [0.70 0.70 0.80];
                th.shiftTxt    = [0.00 0.00 0.00];

                th.btnBg       = [0.25 0.25 0.25];
                th.btnTxt      = [1.00 1.00 1.00];
                th.axBg        = [0.05 0.05 0.05];

                th.planeRed    = [0.96 0.06 0.06];
                th.planeGreen  = [0.20 1.00 0.35];
                th.planeRedTxt = [0.96 0.40 0.40];
                th.planeGreenTxt = [0.40 1.00 0.50];

                th.wireKerf    = [1.00 0.75 0.00];
                th.wireNeutral = [0.80 0.80 0.80];
                th.rawMeshCol  = [0.60 0.60 0.60];
                th.wireLead    = [1.00 0.50 0.00];

                % Status Box Colors (Red / Amber / Green)
                th.statErrBg   =[0.40 0.16 0.16];
                th.statErrTxt  =[1.00 0.40 0.40];
                th.statWarnBg  =[0.45 0.35 0.10];
                th.statWarnTxt =[1.00 0.80 0.40];
                th.statPassBg  = th.panelBg;
                th.statPassTxt = th.planeGreen;

                % 3D Plotting Elements
                th.modelColor  =[0.50 0.50 0.60];
                th.modelAlpha  = 0.40;
                th.billetColor = [0.30 0.50 0.80];
                th.billetAlpha = 0.20;
                th.billetLine  = 'w';

                th.bedCol      = [0.40 0.40 0.40];
                th.bedEdge     = [0.20 0.20 0.20];
                th.cageCol     = [0.60 0.60 0.60];
                th.wireBaseCol = [0.50 0.50 0.50];

                % Ghost profiles (RGBA with 60% opacity)
                th.ghostRed    = [th.planeRed, 0.6];
                th.ghostGreen  =[th.planeGreen, 0.6];
                th.ghostNeutral=[0.90 0.90 0.90, 0.7];

            else
                % --- LIGHT THEME ---
                th.sideBg      = [0.96 0.96 0.96];
                th.panelBg     = [0.90 0.90 0.90];
                th.labelCol    = [0.15 0.15 0.15];
                th.accentBg    = [0.70 0.70 0.80];
                th.editBg      =[1.00 1.00 1.00];
                th.editTxt     =[0.00 0.00 0.00];
                th.readoutBg   =[0.85 0.85 0.85];
                th.readoutTxt  =[0.20 0.20 0.20];

                % Standard inputs are white in light mode
                th.inputBg     = [1.00 1.00 1.00];
                th.inputTxt    = [0.00 0.00 0.00];

                % The carefully chosen Billet Shift/Size accent background
                th.shiftBg     =[0.70 0.70 0.80];
                th.shiftTxt    =[0.00 0.00 0.00];

                th.btnBg       =[0.85 0.85 0.85];
                th.btnTxt      =[0.00 0.00 0.00];
                th.axBg        =[0.95 0.95 0.95];

                th.planeRed    =[0.80 0.00 0.00];
                th.planeGreen  =[0.00 0.60 0.00];
                th.planeRedTxt =[0.60 0.00 0.00];
                th.planeGreenTxt =[0.00 0.40 0.00];

                th.wireKerf    =[1.00 0.75 0.00];
                th.wireNeutral =[0.20 0.20 0.20];
                th.rawMeshCol  =[0.40 0.40 0.40];
                th.wireLead    =[0.85 0.35 0.00];

                % Status Box Colors
                th.statErrBg   = [1.00 0.80 0.80];
                th.statErrTxt  = [0.80 0.00 0.00];
                th.statWarnBg  = [1.00 0.90 0.70];
                th.statWarnTxt = [0.65 0.30 0.00];
                th.statPassBg  = th.panelBg;
                th.statPassTxt = th.planeGreen;

                th.modelColor  =[0.50 0.50 0.60];
                th.modelAlpha  = 0.30;
                th.billetColor = [0.30 0.50 0.80];
                th.billetAlpha = 0.20;
                th.billetLine  = 'k';

                th.bedCol      = [0.80 0.80 0.80];
                th.bedEdge     = [0.50 0.50 0.50];
                th.cageCol     = [0.30 0.30 0.30];
                th.wireBaseCol = [0.40 0.40 0.40];

                th.ghostRed    = [th.planeRed, 0.6];
                th.ghostGreen  = [th.planeGreen, 0.6];
                th.ghostNeutral=[0.20 0.20 0.20, 0.5];
            end
        end

        function applyTheme(app)
            % Sweeps the UI on startup to replace any hardcoded colors with the active theme.
            t = app.getTheme();
            app.UIFigure.Color = t.sideBg;

            % 1. Paint ALL Physical Tabs
            tabs =[app.TabWelcome, app.TabModel, app.TabProfiles, app.TabBillet, ...
                app.TabMachine, app.TabCutting, app.TabSimulation, app.TabPostProcess];
            for i = 1:numel(tabs)
                if isgraphics(tabs(i))
                    tabs(i).BackgroundColor = t.sideBg;
                end
            end

            % 2. Sweep and update ALL layout grids and panels
            containers = {app.GLWelcome, app.GLModel, app.GLProfiles, app.GLBillet, ...
                app.GLMachine, app.GLCutting, app.GLSimulation, app.GLPostProcess, ...
                app.GLLeft, app.profilesLeft, app.BilletLeftPanel, app.BilletRightPanel, ...
                app.MachineLeftPanel, app.CuttingLeftPanel, ...
                app.SimLeftPanel, app.PostLeftPanel, ...
                app.PanelGCode, app.GridGCode};

            for i = 1:numel(containers)
                c = containers{i};
                if isempty(c) || ~isgraphics(c), continue; end

                c.BackgroundColor = t.sideBg;

                kids = findall(c);
                for j = 1:numel(kids)
                    obj = kids(j);

                    % A. Protect Readouts
                    isReadout = false;
                    if ~isempty(app.BilletModelDimLabels) && any(obj == app.BilletModelDimLabels)
                        isReadout = true;
                    end
                    if isprop(app, 'LblBaseFeed') && ~isempty(app.LblBaseFeed) && any(obj == app.LblBaseFeed)
                        isReadout = true;
                    end
                    if isReadout
                        obj.BackgroundColor = t.readoutBg;
                        obj.FontColor       = t.readoutTxt;
                        continue;
                    end

                    % B. Update Status Boxes to match theme (formerly protected hardcoded dark)
                    if isprop(obj, 'BackgroundColor') && isequal(obj.BackgroundColor, [0.2 0.2 0.2]) && isa(obj, 'matlab.ui.control.TextArea')
                        if t.sideBg(1) < 0.5
                            % Keep it dark for Dark Mode
                            obj.BackgroundColor = [0.15 0.15 0.15];
                        else
                            % Make it very light for Light Mode to ensure text contrast
                            obj.BackgroundColor = [0.98 0.98 0.98];
                        end
                        continue;
                    end

                    % FIX C: Protect Billet Shift & Size Edit Fields
                    isShiftField = false;
                    if ~isempty(app.BilletSizeEdits) && any(obj == app.BilletSizeEdits)
                        isShiftField = true;
                    end
                    if ~isempty(app.BilletCenterOffsetEdits) && any(obj == app.BilletCenterOffsetEdits)
                        isShiftField = true;
                    end

                    % --- Special Case: Plane Offset Spinners ---
                    if obj == app.NumLeftOffset
                        obj.FontColor = t.planeRedTxt;
                        % Create a subtle tinted background (15% Red, 85% Theme Bg)
                        obj.BackgroundColor = t.planeRed * 0.15 + t.sideBg * 0.85;
                        continue; % Skip standard styling for this object
                    elseif obj == app.NumRightOffset
                        obj.FontColor = t.planeGreenTxt;
                        % Create a subtle tinted background (15% Green, 85% Theme Bg)
                        obj.BackgroundColor = t.planeGreen * 0.15 + t.sideBg * 0.85;
                        continue; % Skip standard styling for this object
                    end

                    % D. Standard Component Styling
                    if isa(obj, 'matlab.ui.container.Panel') || isa(obj, 'matlab.ui.container.GridLayout')
                        obj.BackgroundColor = t.sideBg;
                        if isprop(obj, 'ForegroundColor')
                            obj.ForegroundColor = t.labelCol;
                        end
                    elseif isa(obj, 'matlab.ui.control.Label') || isa(obj, 'matlab.ui.control.Switch') || isa(obj, 'matlab.ui.control.CheckBox') || isa(obj, 'matlab.ui.control.Slider')
                        obj.FontColor = t.labelCol;
                    elseif isa(obj, 'matlab.ui.control.TextArea') || isa(obj, 'matlab.ui.control.ListBox')
                        obj.BackgroundColor = t.sideBg;
                        obj.FontColor = t.labelCol;
                    elseif isa(obj, 'matlab.ui.control.NumericEditField') || isa(obj, 'matlab.ui.control.EditField') || isa(obj, 'matlab.ui.control.Spinner')
                        % Apply the special accent color to the protected shift fields!
                        if isShiftField
                            obj.BackgroundColor = t.shiftBg;
                            obj.FontColor       = t.shiftTxt;
                        else
                            obj.BackgroundColor = t.inputBg;
                            obj.FontColor       = t.inputTxt;
                        end
                    elseif isa(obj, 'matlab.ui.control.Button') || isa(obj, 'matlab.ui.control.StateButton')
                        % Safely theme standard buttons without touching Semantic (Green/Red) buttons
                        bg = obj.BackgroundColor;
                        if abs(bg(1)-bg(2)) < 1e-3 && abs(bg(2)-bg(3)) < 1e-3
                            obj.BackgroundColor = t.btnBg;
                            obj.FontColor = t.btnTxt;
                        end
                    end
                end
            end

            % 3. Sweep and update All Axes
            allAxes =[app.AxModel, app.AxLeftProfile, app.AxRightProfile, ...
                app.AxBilletTop, app.AxBilletFront, app.AxBilletRight, app.AxBilletIso, ...
                app.AxMachine, app.AxCutLeft, app.AxCutRight, app.AxSim, app.AxPost];

            for i = 1:numel(allAxes)
                ax = allAxes(i);
                if isgraphics(ax)
                    ax.Color = t.axBg;
                    if isprop(ax, 'BackgroundColor')
                        ax.BackgroundColor = t.sideBg;
                    end
                    ax.XColor = t.labelCol;
                    ax.YColor = t.labelCol;
                    ax.ZColor = t.labelCol;
                    ax.GridColor = t.labelCol;

                    if isprop(ax, 'Title') && isgraphics(ax.Title)
                        ax.Title.Color = t.labelCol;
                    end
                end
            end

            % 4. Sweep and update all Legends
            lgds = findall(app.UIFigure, 'Type', 'legend');
            for i = 1:numel(lgds)
                lgds(i).TextColor = t.labelCol;
            end
        end

        function onThemeToggleChanged(app, src)
            % Ask for confirmation before restarting
            sel = uiconfirm(app.UIFigure, ...
                'Changing the theme requires the application to restart. Any unsaved progress will be lost. Do you wish to restart now?', ...
                'Restart Required', ...
                'Options', {'Restart Now', 'Cancel'}, ...
                'DefaultOption', 1, 'CancelOption', 2, 'Icon', 'info');

            if strcmp(sel, 'Restart Now')
                % Save the new preference
                setpref('HotWireSTEPApp', 'Theme', src.Value);

                % Safely close current app and launch a new instance
                delete(app.UIFigure);
                HotWireSTEPApp_v6_2();
            else
                % Revert the switch visually if they cancelled
                if strcmp(src.Value, 'Dark')
                    src.Value = 'Light';
                else
                    src.Value = 'Dark';
                end
            end
        end

        function cols = getInteractionColors(app)
            t = app.getTheme();
            isDark = app.UIFigure.Color(1) < 0.5;

            cols = struct();

            if isDark
                cols.StartActive   = [0.0 0.8 0.0]; % Green
                cols.StartInactive = [0.15 0.25 0.15];
                cols.EntryActive   = [1.0 0.6 0.0]; % Orange (Lead In)
                cols.EntryInactive = [0.30 0.20 0.10];
                cols.LinkActive    = [0.9 0.8 0.0]; % Yellow (Links)
                cols.LinkInactive  = [0.30 0.30 0.10];
                cols.TextActive    = [0 0 0];
                cols.TextInactive  = [0.9 0.9 0.9];
            else
                cols.StartActive   = [0.4 1.0 0.4];
                cols.StartInactive = [0.90 0.96 0.90];
                cols.EntryActive   = [1.0 0.7 0.4];
                cols.EntryInactive = [0.98 0.94 0.90];
                cols.LinkActive    = [0.9 0.9 0.4];
                cols.LinkInactive  = [0.98 0.98 0.90];
                cols.TextActive    = [0 0 0];
                cols.TextInactive  = [0 0 0];
            end
        end
    end

    methods (Access = private)
        % ===========================================================
        % PRIVATE UI BUILDERS
        % ===========================================================
        % The functions in this block are called exclusively by buildUI().
        % They encapsulate the layout logic for each tab to keep the code
        % modular, prevent variable shadowing, and make the UI easier to edit.

        % TAB 0 (WELCOME)
        function createWelcomeTab(app)
            % Purpose: Builds the Welcome & Setup tab. This tab introduces the
            %          software and provides the one-time FreeCAD engine setup.
            %
            % Layout Strategy:
            %   - Left Panel (320px): Theme toggle and Continue button.
            %   - Right Panel (1x): Scrollable content area containing the Header,
            %     About text, FreeCAD setup, and a pinned Footer.
            %
            % Dependencies: app.getTheme(), HotWireSTEPApp_v6_2.PanelWidth

            % 1. Fetch Theme Colors
            t = app.getTheme();
            sideBg   = t.sideBg;
            panelBg  = t.panelBg;
            labelCol = t.labelCol;
            inputBg  = t.inputBg;
            inputTxt = t.inputTxt;

            % 2. Main Tab Container
            app.TabWelcome = uitab(app.TabGroup, 'Title', 'Welcome & Setup');

            app.GLWelcome = uigridlayout(app.TabWelcome,[1 2]);
            app.GLWelcome.ColumnWidth = {HotWireSTEPApp_v6_2.PanelWidth, '1x'};
            app.GLWelcome.Padding = [5 5 5 5];
            app.GLWelcome.ColumnSpacing = 5;

            %% --- LEFT PANEL (Controls Feel) ---
            leftPnl = uigridlayout(app.GLWelcome, [3 1]);
            leftPnl.Layout.Column = 1;
            % '1x' pushes the theme toggle and button to the bottom
            leftPnl.RowHeight = {'1x', 'fit', HotWireSTEPApp_v6_2.ButtonHeight};
            leftPnl.Padding = [5 5 5 5];
            leftPnl.BackgroundColor = sideBg;

            % Theme Toggle
            glTheme = uigridlayout(leftPnl, [1 2]);
            glTheme.Layout.Row = 2;
            glTheme.ColumnWidth = {'fit', 'fit'};
            glTheme.Padding =[0 0 0 0];
            glTheme.BackgroundColor = sideBg;
            uilabel(glTheme, 'Text', 'App Theme:', 'FontWeight', 'bold', 'FontColor', labelCol);

            if ispref('HotWireSTEPApp', 'Theme'), currentTheme = getpref('HotWireSTEPApp', 'Theme'); else, currentTheme = 'Dark'; end
            app.ThemeSwitch = uiswitch(glTheme, 'slider', 'Items', {'Dark', 'Light'}, 'Value', currentTheme, 'FontColor', labelCol, 'ValueChangedFcn', @(src,evt)app.onThemeToggleChanged(src));

            % Continue Button
            btnWelcomeCont = uibutton(leftPnl, 'Text','Continue to Guide →', 'FontWeight','bold', 'BackgroundColor',[0.1 0.6 0.1], 'FontColor',[1 1 1], 'ButtonPushedFcn',@(~,~)app.onContinue());
            btnWelcomeCont.Layout.Row = 3;

            %% --- RIGHT PANEL (Content) ---
            rightScroll = uipanel(app.GLWelcome, 'Scrollable', 'on', 'BackgroundColor', panelBg, 'BorderType', 'none');
            rightScroll.Layout.Column = 2;

            % 5 Rows: Header, About, FreeCAD, Spacer (1x), Footer
            glRight = uigridlayout(rightScroll, [5 1]);
            glRight.RowHeight = {120, 'fit', 'fit', '1x', 'fit'};
            glRight.BackgroundColor = panelBg;
            glRight.Padding =[20 20 20 20];
            glRight.RowSpacing = 15;

            % --- Header Area ---
            glHead = uigridlayout(glRight, [1 2]);
            glHead.Layout.Row = 1;
            glHead.ColumnWidth = {'1x', 280};
            glHead.Padding = [0 0 0 0];
            glHead.BackgroundColor = panelBg;

            isDark = app.UIFigure.Color(1) < 0.5;
            if isDark, logoName = 'Science_engineering_WHITE.png'; else, logoName = 'Science_engineering_BLACK.png'; end
            appDir = fileparts(mfilename('fullpath'));
            pathOption1 = fullfile(appDir, logoName); pathOption2 = fullfile(appDir, 'src', logoName);

            lblTitle = uilabel(glHead, 'Text', 'CNC Hot Wire G-Code Generator', 'FontSize', 28, 'FontWeight', 'bold', 'FontColor', labelCol, 'VerticalAlignment','center');
            lblTitle.Layout.Column = 1;

            if isfile(pathOption1), app.ImgWelcomeLogo = uiimage(glHead, 'ImageSource', pathOption1);
            elseif isfile(pathOption2), app.ImgWelcomeLogo = uiimage(glHead, 'ImageSource', pathOption2);
            else, app.ImgWelcomeLogo = uiimage(glHead); end
            app.ImgWelcomeLogo.Layout.Column = 2;

            % --- About Section ---
            pnlAbout = uipanel(glRight, 'Title', 'About This Software', 'FontWeight','bold', 'FontSize',14, 'BackgroundColor', sideBg, 'ForegroundColor', labelCol);
            pnlAbout.Layout.Row = 2;
            glAbout = uigridlayout(pnlAbout,[1 1]);
            glAbout.RowHeight = {'fit'}; % Ensures text area expands to fit content
            glAbout.Padding =[0 0 0 0];
            glAbout.BackgroundColor = sideBg;

            txtAbout = {
                'Welcome to the Rapid Prototyping Workshops 4-axis CNC Hot Wire Toolpath and G-code Generator.';
                'This software provides a complete, end-to-end workflow to take you form CAD model to G-code for CNC hot wire foam cutting';
                'Most steps offer auto or manual configuration';
                '';
                'Workflow:';
                '- Import and orient 3D CAD models (STEP/STL).';
                '- Slice models, extract and sync 2D profiles.';
                '- Apply kerf compensation to preserve dimensional accuracy.';
                '- Size and position your model and billet.';
                '- Create collision-free lead-in and exit paths.';
                '- Visually simulate the 4-axis kinematics to verify the cut.';
                '- Post-process and export Mach4-compatible G-code.'
                };
            % Height is calculated roughly based on line count to ensure no scrollbar
            uitextarea(glAbout, 'Value', txtAbout, 'Editable', 'off', 'BackgroundColor', sideBg, 'FontColor', labelCol, 'FontSize', 14, 'Height', 220);

            % --- FreeCAD Setup Section (Step-by-Step) ---
            pnlFC = uipanel(glRight, 'Title', 'Required Setup: FreeCAD Engine', 'FontWeight','bold', 'FontSize',14, 'BackgroundColor', sideBg, 'ForegroundColor', labelCol);
            pnlFC.Layout.Row = 3;

            glFC = uigridlayout(pnlFC, [4 2]);
            glFC.ColumnWidth = {'1x', 300};
            glFC.RowHeight = {'fit', HotWireSTEPApp_v6_2.ButtonHeight, 'fit', HotWireSTEPApp_v6_2.ButtonHeight};
            glFC.Padding =[10 10 10 10];
            glFC.BackgroundColor = sideBg;

            % Intro
            lblIntro = uilabel(glFC, 'Text', 'This app requires FreeCAD (v1.0 or newer) behind the scenes to accurately mesh STEP files. You only need to set this up once!', 'FontColor', labelCol);
            lblIntro.Layout.Row = 1; lblIntro.Layout.Column =[1 2];

            % Step 1
            lblS1 = uilabel(glFC, 'Text', 'Step 1. Download and run the standard Windows Installer.', 'FontColor', labelCol, 'FontWeight', 'bold');
            lblS1.Layout.Row = 2; lblS1.Layout.Column = 1;
            btnDL = uibutton(glFC, 'Text', 'Download FreeCAD', 'FontWeight', 'bold', 'BackgroundColor',[0.2 0.5 0.8], 'FontColor',[1 1 1], 'ButtonPushedFcn', @(~,~)web('https://www.freecad.org/downloads.php', '-browser'));
            btnDL.Layout.Row = 2; btnDL.Layout.Column = 2;

            % Step 2
            lblS2 = uilabel(glFC, 'Text', 'Step 2. Install FreeCAD to the default directory.', 'FontColor', labelCol, 'FontWeight', 'bold');
            lblS2.Layout.Row = 3; lblS2.Layout.Column = [1 2];

            % Step 3
            lblS3 = uilabel(glFC, 'Text', 'Step 3. Locate "FreeCADCmd.exe" (Typically: C:\Program Files\FreeCAD 1.0\bin\)', 'FontColor', labelCol, 'FontWeight', 'bold');
            lblS3.Layout.Row = 4; lblS3.Layout.Column = 1;

            glFCBrowse = uigridlayout(glFC,[1 2]);
            glFCBrowse.Layout.Row = 4; glFCBrowse.Layout.Column = 2;
            glFCBrowse.ColumnWidth = {'1x', 80};
            glFCBrowse.Padding = [0 0 0 0];
            glFCBrowse.BackgroundColor = sideBg;

            if ispref('HotWireSTEPApp', 'FreeCADPath'), app.FreeCADExe = getpref('HotWireSTEPApp', 'FreeCADPath'); else, app.FreeCADExe = "C:\Program Files\FreeCAD 1.0\bin\FreeCADCmd.exe"; end
            app.FieldFreeCADPath = uieditfield(glFCBrowse, 'text', 'Value', app.FreeCADExe, 'BackgroundColor', inputBg, 'FontColor', inputTxt, 'ValueChangedFcn', @(src,evt)app.onFreeCADPathEdited(src));
            btnBrowseFC = uibutton(glFCBrowse, 'Text', 'Browse...', 'FontWeight', 'bold', 'BackgroundColor', t.accentBg, 'FontColor', t.editTxt, 'ButtonPushedFcn', @(~,~)app.onBrowseFreeCAD());

            % --- Spacer Row ---
            % Row 4 in glRight is '1x', which pushes the footer to the bottom of the screen.

            % --- Footer Panels ---
            glFooter = uigridlayout(glRight,[1 3]);
            glFooter.Layout.Row = 5;
            glFooter.ColumnWidth = {'1x', '1x', 305};
            glFooter.RowHeight = {80};
            glFooter.Padding =[0 0 0 0];
            glFooter.ColumnSpacing = 5;
            glFooter.BackgroundColor = panelBg;

            pnlContact = uipanel(glFooter, 'Title', 'Contact', 'FontWeight','bold', 'BackgroundColor', sideBg, 'ForegroundColor', labelCol);
            glContact = uigridlayout(pnlContact,[1 1]); glContact.Padding = [0 0 0 0]; glContact.BackgroundColor = sideBg;
            uitextarea(glContact, 'Value', {'Author: Matthew Richardson'; 'Email: matthew.richardson@bristol.ac.uk'}, 'Editable', 'off', 'BackgroundColor', sideBg, 'FontColor', labelCol);

            pnlLicense = uipanel(glFooter, 'Title', 'License', 'FontWeight','bold', 'BackgroundColor', sideBg, 'ForegroundColor', labelCol);
            glLicense = uigridlayout(pnlLicense,[1 1]); glLicense.Padding =[0 0 0 0]; glLicense.BackgroundColor = sideBg;
            uitextarea(glLicense, 'Value', {'Released under the MIT Open Source License.'; 'Free for academic, personal, or commercial use.'}, 'Editable', 'off', 'BackgroundColor', sideBg, 'FontColor', labelCol);

            pnlSource = uipanel(glFooter, 'Title', 'Source Code', 'FontWeight','bold', 'BackgroundColor', sideBg, 'ForegroundColor', labelCol);
            glSource = uigridlayout(pnlSource,[1 1]); glSource.Padding =[5 5 5 5]; glSource.BackgroundColor = sideBg;
            uibutton(glSource, 'Text', 'View Source on GitHub', 'FontWeight','bold', 'BackgroundColor',[0.2 0.2 0.2], 'FontColor', [1 1 1], 'ButtonPushedFcn', @(~,~)web(app.GitHubLink, '-browser'));
        end

        % TAB 1 (INTERFACE GUIDE)
        function createGuideTab(app)
            % Purpose: Teaches the user the UI layout by mimicking the actual
            %          app structure. Uses dummy components to explain functionality.
            %
            % Dependencies: app.getTheme(), HotWireSTEPApp_v6_2.PanelWidth

            t = app.getTheme();
            sideBg   = t.sideBg;
            panelBg  = t.panelBg;
            labelCol = t.labelCol;

            app.TabGuide = uitab(app.TabGroup, 'Title', 'Interface Guide');

            % Mimic the standard app layout
            app.GLGuide = uigridlayout(app.TabGuide, [1 2]);
            app.GLGuide.ColumnWidth = {HotWireSTEPApp_v6_2.PanelWidth, '1x'};
            app.GLGuide.Padding =[5 5 5 5];
            app.GLGuide.ColumnSpacing = 5;

            %% --- LEFT PANEL (Mimics Controls) ---
            leftPnl = uigridlayout(app.GLGuide,[7 1]);
            leftPnl.Layout.Column = 1;
            % 1x spacer pushes Guidance and Status to the bottom!
            leftPnl.RowHeight = {'fit', 'fit', 'fit', '1x', 'fit', 70, HotWireSTEPApp_v6_2.ButtonHeight};
            leftPnl.Padding = [5 5 5 5];
            leftPnl.BackgroundColor = sideBg;

            % 1. Controls Intro
            pnl1 = uipanel(leftPnl, 'Title', '1. Controls & Inputs', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'BorderType', 'line');
            gl1 = uigridlayout(pnl1, [1 1]); gl1.Padding =[0 0 0 0]; gl1.BackgroundColor = sideBg;
            uitextarea(gl1, 'Value', 'The top of the left panel contains inputs, toggles, and buttons.', 'Editable', 'off', 'BackgroundColor', sideBg, 'FontColor', labelCol);

            % Dummy Controls Panel
            pnlDummy = uipanel(leftPnl, 'Title','Example Controls', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlDummy.Layout.Row = 2;
            gridDummy = uigridlayout(pnlDummy, [3 2]);
            gridDummy.ColumnWidth = {'1x', '1x'};
            gridDummy.Padding=[5 5 5 5];
            gridDummy.BackgroundColor=panelBg;

            uilabel(gridDummy, 'Text', 'Example Toggle:', 'FontColor', labelCol, 'HorizontalAlignment', 'right');
            uiswitch(gridDummy, 'slider', 'Items', {'Off', 'On'}, 'FontColor', labelCol);

            uilabel(gridDummy, 'Text', 'Example Spinner:', 'FontColor', labelCol, 'HorizontalAlignment', 'right');
            uispinner(gridDummy, 'Value', 10.0);

            uibutton(gridDummy, 'Text','Example Button', 'FontWeight','bold');
            uibutton(gridDummy, 'Text','Example Button', 'FontWeight','bold');

            % 2. Guidance (Pushed to bottom by 1x spacer in Row 4)
            pnl2 = uipanel(leftPnl, 'Title', '2. Guidance', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'BorderType', 'line');
            pnl2.Layout.Row = 5;
            gl2 = uigridlayout(pnl2,[1 1]); gl2.Padding =[0 0 0 0]; gl2.BackgroundColor = sideBg;
            uitextarea(gl2, 'Value', 'Guidance blocks provide step-by-step instructions for the current tab.', 'Editable', 'off', 'BackgroundColor', sideBg, 'FontColor', labelCol);

            % 3. Status
            pnl3 = uipanel(leftPnl, 'Title', '3. Status', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'BorderType', 'line');
            pnl3.Layout.Row = 6;
            gl3 = uigridlayout(pnl3, [1 1]); gl3.Padding =[0 0 0 0]; gl3.BackgroundColor = sideBg;
            uitextarea(gl3, 'Value', 'Traffic-light box: Red (Error), Amber (Warning), Green (Safe).', 'Editable', 'off', 'BackgroundColor', t.statPassBg, 'FontColor', t.statPassTxt);

            % Continue Button
            btnCont = uibutton(leftPnl, 'Text', 'Continue to Model →', 'FontWeight', 'bold', 'BackgroundColor',[0.1 0.6 0.1], 'FontColor',[1 1 1], 'ButtonPushedFcn', @(~,~)app.onContinue());
            btnCont.Layout.Row = 7;

            %% --- RIGHT PANEL (Mimics Plot) ---
            rightPnl = uipanel(app.GLGuide, 'Title', '4. Main Plot (Right Side) →', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', 16, 'BorderType', 'line');
            rightPnl.Layout.Column = 2;

            glR = uigridlayout(rightPnl,[2 1]);
            glR.RowHeight = {'fit', '1x'};
            glR.Padding =[10 10 10 10];
            glR.BackgroundColor = sideBg;

            txt = {
                'The large right panel always contains your interactive 2D or 3D visuals.';
                'Move through the tabs at the top of the window one by one, left to right.'
                };
            uitextarea(glR, 'Value', txt, 'Editable', 'off', 'BackgroundColor', sideBg, 'FontColor', labelCol, 'FontSize', 16);

            % Dummy 3D Plot
            axDummy = uiaxes(glR);
            axDummy.BackgroundColor =[0.11 0.11 0.11];
            grid(axDummy, 'on');
            view(axDummy, 3);

            % Generate a cool looking surface
            [X,Y,Z] = peaks(30);
            surf(axDummy, X, Y, Z, 'EdgeColor', 'none');
            colormap(axDummy, 'turbo');

            title(axDummy, 'Interactive 3D Visualizer', 'Color', labelCol);
            axDummy.XColor = labelCol; axDummy.YColor = labelCol; axDummy.ZColor = labelCol;
        end

        % TAB 1 (MODEL)
        function createModelTab(app)
            % Purpose: Builds the Model Import & Orientation tab UI components.
            % Inputs:  app (HotWireSTEPApp_v6_2 instance)
            % Dependencies: app.getTheme()

            % Fetch Theme Colors locally for this function
            t = app.getTheme();
            sideBg   = t.sideBg;
            panelBg  = t.panelBg;
            labelCol = t.labelCol;

            app.TabModel = uitab(app.TabGroup,'Title','Model');
            app.GLModel = uigridlayout(app.TabModel,[1 2]);
            app.GLModel.ColumnWidth   = {320,'1x'};
            app.GLModel.Padding       =[10 10 10 10];
            app.GLModel.ColumnSpacing = 10;

            %% --- LEFT CONTROL PANEL ---
            app.GLLeft = uigridlayout(app.GLModel,[11 1]);
            app.GLLeft.Layout.Column = 1;
            app.GLLeft.BackgroundColor = sideBg;

            % Rows: 1-8 Controls, 9 Guidance (1x), 10 Status (70px), 11 Buttons
            app.GLLeft.RowHeight = {'fit','fit','fit','fit','fit','fit','fit','fit','1x',70,'fit'};
            app.GLLeft.Padding = [10 10 10 10];

            %% --- FILE IMPORT ---
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

            %% --- TAPER MODE ---
            pnl_M_Cut = uipanel(app.GLLeft, 'BackgroundColor', sideBg, 'BorderType', 'line', 'Title', '');
            pnl_M_Cut.Layout.Row = 4;

            grid_M_Cut = uigridlayout(pnl_M_Cut,[1 3]);
            grid_M_Cut.ColumnWidth = {'1x','fit','1x'};
            grid_M_Cut.Padding=[10 0 10 0];
            grid_M_Cut.BackgroundColor = sideBg;

            lbl_M_Sp1 = uilabel(grid_M_Cut,'Text',''); lbl_M_Sp1.Layout.Column=1;

            app.TaperToggle = uiswitch(grid_M_Cut,'slider', 'Items',{'Straight','Tapered'}, 'Value','Straight', ...
                'Tooltip', sprintf('Straight: Prismatic (Identical profiles).\nTapered: Independent Left/Right profiles.'), ...
                'ValueChangedFcn',@(~,~)app.onTaperModeChanged());
            app.TaperToggle.Layout.Column = 2;

            lbl_M_Sp2 = uilabel(grid_M_Cut,'Text',''); lbl_M_Sp2.Layout.Column=3;

            %% --- ORIENTATION ---
            pnl_M_Rot = uipanel(app.GLLeft, 'Title','Model Orientation', 'BackgroundColor',panelBg, 'FontWeight','bold', 'ForegroundColor',labelCol);
            pnl_M_Rot.Layout.Row = 5;

            outer_M_Rot = uigridlayout(pnl_M_Rot,[1 3]);
            outer_M_Rot.ColumnWidth={'1x','fit','1x'};
            outer_M_Rot.Padding=[5 5 5 5];
            outer_M_Rot.BackgroundColor=panelBg;

            app.RotGrid = uigridlayout(outer_M_Rot,[3 4]);
            app.RotGrid.Layout.Column = 2;
            app.RotGrid.ColumnWidth={'fit','fit',70,'fit'};
            app.RotGrid.RowHeight={'fit','fit','fit'};
            app.RotGrid.Padding=[0 0 0 0];
            app.RotGrid.BackgroundColor=panelBg;

            axesLabels = {'X','Y','Z'};
            app.RotEdit = gobjects(1,3);
            for i = 1:3
                lbl_M_Rot = uilabel(app.RotGrid, 'Text',axesLabels{i}, 'FontWeight','bold', 'HorizontalAlignment','center', 'FontColor',labelCol);
                lbl_M_Rot.Layout.Row=i;

                btn_M_Neg = uibutton(app.RotGrid,'Text','-90°', 'ButtonPushedFcn',@(~,~)app.rotateModel([axesLabels{i} 'm']));
                btn_M_Neg.Layout.Row=i;

                app.RotEdit(i) = uieditfield(app.RotGrid,'numeric', 'Limits',[0 360], 'Value',0, 'HorizontalAlignment','center', 'ValueDisplayFormat','%.0f°', ...
                    'Tooltip',['Rotate model around the ' axesLabels{i} ' axis.'], ...
                    'ValueChangedFcn',@(src,~)app.updateRotation(axesLabels{i},src.Value));
                app.RotEdit(i).Layout.Row=i;

                btn_M_Pos = uibutton(app.RotGrid,'Text','+90°', 'ButtonPushedFcn',@(~,~)app.rotateModel([axesLabels{i} 'p']));
                btn_M_Pos.Layout.Row=i;
            end

            btnMResO = uibutton(app.GLLeft, 'Text','Reset Orientation', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.resetOrientation());
            btnMResO.Layout.Row = 6;

            btnMResP = uibutton(app.GLLeft, 'Text','Reset Plot View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.resetPlotView());
            btnMResP.Layout.Row = 7;

            %% --- PLANE OFFSETS ---
            pnl_M_Off = uipanel(app.GLLeft, 'BackgroundColor',panelBg, 'BorderType','line');
            pnl_M_Off.Layout.Row = 8;

            grid_M_Off = uigridlayout(pnl_M_Off,[3 2]);
            grid_M_Off.ColumnWidth={'1x',90};
            grid_M_Off.RowHeight={'fit','fit','fit'};

            lbl_M_OffL = uilabel(grid_M_Off,'Text','Left Plane Offset:','HorizontalAlignment','right','FontWeight','bold', 'FontColor',labelCol);
            lbl_M_OffL.Layout.Row=1; lbl_M_OffL.Layout.Column=1;

            app.NumLeftOffset = uispinner(grid_M_Off, 'Limits',[0 10000], 'Value',0, 'Step',1, ...
                'ValueDisplayFormat','%.1f',...
                'Tooltip', 'Distance from Model Left Face (X Min) to Left Cutting Plane', ...
                'ValueChangedFcn',@(src,evt)app.onPlaneOffsetChanged(src,evt));
            app.NumLeftOffset.Layout.Row=1; app.NumLeftOffset.Layout.Column=2;

            lbl_M_OffR = uilabel(grid_M_Off,'Text','Right Plane Offset:','HorizontalAlignment','right','FontWeight','bold', 'FontColor',labelCol);
            lbl_M_OffR.Layout.Row=2; lbl_M_OffR.Layout.Column=1;

            app.NumRightOffset = uispinner(grid_M_Off, 'Limits',[0 10000], 'Value',0, 'Step',1, ...
                'ValueDisplayFormat','%.1f',...
                'Tooltip', 'Distance from Model Left Face (X Min) to Right Cutting Plane', ...
                'ValueChangedFcn',@(src,evt)app.onPlaneOffsetChanged(src,evt));
            app.NumRightOffset.Layout.Row=2; app.NumRightOffset.Layout.Column=2;

            btn_M_ResPlane = uibutton(grid_M_Off, 'Text','Reset Planes', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.resetPlanes());
            btn_M_ResPlane.Layout.Row=3; btn_M_ResPlane.Layout.Column=[1 2];

            %% --- GUIDANCE ---
            pnlGuide = uipanel(app.GLLeft, 'Title', 'Guidance', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'BorderType', 'line');
            pnlGuide.Layout.Row = 9;
            glGuide = uigridlayout(pnlGuide,[1 1]);
            glGuide.Padding = [2 2 2 2];
            glGuide.BackgroundColor = sideBg;

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
            app.TxtModelGuide = uitextarea(glGuide, 'Editable','off', 'Value', guideText, 'BackgroundColor', sideBg, 'FontColor', labelCol);

            %% --- STATUS ---
            pnlStatus = uipanel(app.GLLeft, 'Title', 'Status', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'BorderType', 'line');
            pnlStatus.Layout.Row = 10;
            glStatus = uigridlayout(pnlStatus,[1 1]);
            glStatus.Padding = [2 2 2 2];
            glStatus.BackgroundColor = sideBg;

            app.TxtModelStatus = uitextarea(glStatus, 'Editable','off', 'Value', {'No model loaded.'}, 'BackgroundColor', t.panelBg, 'FontColor',[1 0.8 0]);

            %% --- ACTION BUTTONS ---
            pnl_M_Btn = uipanel(app.GLLeft, 'BackgroundColor',sideBg, 'BorderType','none');
            pnl_M_Btn.Layout.Row = 11;

            grid_M_Btn = uigridlayout(pnl_M_Btn,[1 2]);
            grid_M_Btn.Padding=[0 0 0 0];
            grid_M_Btn.BackgroundColor=sideBg;

            app.BtnGenerateProfiles = uibutton(grid_M_Btn, 'Text','Generate Profiles', 'FontWeight','bold', 'BackgroundColor',[0.15 0.45 0.8], 'FontColor',[1 1 1], ...
                'Tooltip', 'Slice model at the defined planes.', ...
                'ButtonPushedFcn',@(~,~)app.onGenerateProfiles());

            app.BtnContinue = uibutton(grid_M_Btn, 'Text','Continue →', 'FontWeight','bold', 'BackgroundColor',[0.3 0.3 0.3], 'FontColor',[0.8 0.8 0.8], ...
                'Enable','off', 'ButtonPushedFcn',@(~,~)app.onContinue());

            %% --- RIGHT PANEL: 3D MODEL AXES ---
            app.AxModel = uiaxes(app.GLModel);
            app.AxModel.Layout.Column = 2;
            app.AxModel.BackgroundColor =[0.11 0.11 0.11];

            xlabel(app.AxModel,'X (mm)');
            ylabel(app.AxModel,'Y (mm)');
            zlabel(app.AxModel,'Z (mm)');

            grid(app.AxModel,'on');
            view(app.AxModel,3);
            hold(app.AxModel,'on');
        end

        % TAB 2 (PROFILES)
        function createProfilesTab(app)
            % Purpose: Builds the Profiles extraction and Kerf tab UI components.
            % Inputs:  app (HotWireSTEPApp_v6_2 instance)
            % Dependencies: app.getTheme()

            % Fetch Theme Colors locally
            t = app.getTheme();
            sideBg   = t.sideBg;
            panelBg  = t.panelBg;
            labelCol = t.labelCol;

            app.TabProfiles = uitab(app.TabGroup,'Title','Profiles');

            app.GLProfiles = uigridlayout(app.TabProfiles,[1 2]);
            app.GLProfiles.ColumnWidth = {320,'1x'};
            app.GLProfiles.Padding = [10 10 10 10];

            %% --- LEFT CONTROL PANEL ---
            app.profilesLeft = uigridlayout(app.GLProfiles,[7 1]);
            app.profilesLeft.Layout.Column = 1;

            % Rows: 1-4 Controls, 5 Guidance (1x), 6 Status (70px), 7 Continue
            app.profilesLeft.RowHeight = {'fit','fit','fit','fit','1x',70,'fit'};
            app.profilesLeft.Padding = [10 10 10 10];
            app.profilesLeft.BackgroundColor = sideBg;

            %% --- PROFILE SAMPLING ---
            pnlSampling = uipanel(app.profilesLeft, 'Title','Profile Sampling', ...
                'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlSampling.Layout.Row = 1;

            gridSampling = uigridlayout(pnlSampling,[2 2]);
            gridSampling.ColumnWidth = {'1x',90};
            gridSampling.Padding =[10 5 10 5];

            lblTolerance = uilabel(gridSampling, 'Text','Profile Tolerance [mm]:', ...
                'HorizontalAlignment','right', 'FontWeight','bold', 'FontColor',labelCol);

            app.ProfileTolSpinner = uispinner(gridSampling, ...
                'Limits',[HotWireSTEPApp_v6_2.MinProfileTolerance, HotWireSTEPApp_v6_2.MaxProfileTolerance], ...
                'Value',HotWireSTEPApp_v6_2.DefaultProfileTolerance, ...
                'Step',0.01, ...
                'ValueDisplayFormat','%.2f', ...
                'Tooltip', 'Adjust until the red/green extracted profiles conform to the mesh slice', ...
                'ValueChangedFcn',@(src,~)app.onProfileToleranceChanged(src));
            app.ProfileTolerance = HotWireSTEPApp_v6_2.DefaultProfileTolerance;

            app.ProfilePointCountLabel = uilabel(gridSampling, ...
                'Text','Number of Points (L/R): -- / --', ...
                'HorizontalAlignment','right', 'FontColor',labelCol, 'FontAngle','italic');
            app.ProfilePointCountLabel.Layout.Row = 2;
            app.ProfilePointCountLabel.Layout.Column =[1 2];

            app.BtnResetProfileTol = uibutton(app.profilesLeft, 'Text','Reset Tolerance', 'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~)app.onResetProfileTolerance());
            app.BtnResetProfileTol.Layout.Row = 2;

            app.BtnResetProfilesView = uibutton(app.profilesLeft, 'Text','Reset Profiles View', 'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~)app.resetProfilesView());
            app.BtnResetProfilesView.Layout.Row = 3;

            %% --- KERF COMPENSATION ---
            pnlKerf = uipanel(app.profilesLeft, 'Title','Kerf Compensation', ...
                'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlKerf.Layout.Row = 4;

            gridKerf = uigridlayout(pnlKerf,[5 2]);
            gridKerf.ColumnWidth = {95, '1x'};
            gridKerf.RowHeight = {'fit','fit','fit','fit','fit'};
            gridKerf.Padding = [5 5 5 5];

            lblKerfMode = uilabel(gridKerf, 'Text','Mode:', 'HorizontalAlignment','right', 'FontColor',labelCol);
            lblKerfMode.Layout.Row = 1; lblKerfMode.Layout.Column = 1;

            app.KerfModeSwitch = uiswitch(gridKerf, 'slider', ...
                'Items', {'Coupled', 'Independent'}, ...
                'Value', 'Coupled', ...
                'FontColor', labelCol, ...
                'ValueChangedFcn', @(src,~)app.onKerfModeChanged(src));
            app.KerfModeSwitch.Layout.Row = 1;
            app.KerfModeSwitch.Layout.Column = 2;
            app.KerfModeSwitch.Tooltip = 'Uncoupling is only for tapered parts to compensate for the difference in wire speed between left and right profiles.';

            lblKerfLeft = uilabel(gridKerf, 'Text','Kerf Left[mm]:', 'HorizontalAlignment','right', 'FontColor',labelCol);
            lblKerfLeft.Layout.Row = 2; lblKerfLeft.Layout.Column = 1;

            app.KerfLeftSpinner = uispinner(gridKerf, ...
                'Limits',[HotWireSTEPApp_v6_2.MinKerf, HotWireSTEPApp_v6_2.MaxKerf], ...
                'Value',app.KerfLeftValue, ...
                'Step',0.1, 'ValueDisplayFormat','%.2f', ...
                'Tooltip', 'Set Kerf: Note, offset distance = Kerf/2', ...
                'ValueChangedFcn',@(src,~)app.onKerfLeftChanged(src));
            app.KerfLeftSpinner.Layout.Row = 2; app.KerfLeftSpinner.Layout.Column = 2;

            lblKerfRight = uilabel(gridKerf, 'Text','Kerf Right [mm]:', 'HorizontalAlignment','right', 'FontColor',labelCol);
            lblKerfRight.Layout.Row = 3; lblKerfRight.Layout.Column = 1;

            app.KerfRightSpinner = uispinner(gridKerf, ...
                'Limits',[HotWireSTEPApp_v6_2.MinKerf, HotWireSTEPApp_v6_2.MaxKerf], ...
                'Value',app.KerfRightValue, ...
                'Step',0.1, 'ValueDisplayFormat','%.2f', ...
                'Enable', 'off', ... % Disabled by default (Coupled)
                'ValueChangedFcn',@(src,~)app.onKerfRightChanged(src));
            app.KerfRightSpinner.Layout.Row = 3; app.KerfRightSpinner.Layout.Column = 2;

            app.KerfPointCountLabel = uilabel(gridKerf, 'Text','Number of Points (L/R): 0 / 0', ...
                'HorizontalAlignment','center', 'FontColor',labelCol, 'FontAngle','italic', 'FontSize',10);
            app.KerfPointCountLabel.Layout.Row = 4;
            app.KerfPointCountLabel.Layout.Column = [1 2];

            app.BtnApplyKerf = uibutton(gridKerf, 'Text','Apply Kerf Offset', 'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~)app.onApplyKerf());
            app.BtnApplyKerf.Layout.Row = 5;
            app.BtnApplyKerf.Layout.Column = [1 2];

            %% --- GUIDANCE ---
            pnlGuide = uipanel(app.profilesLeft, 'Title', 'Guidance', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'BorderType', 'line');
            pnlGuide.Layout.Row = 5;
            glGuide = uigridlayout(pnlGuide, [1 1]);
            glGuide.Padding =[2 2 2 2];
            glGuide.BackgroundColor = sideBg;

            guideText = {
                '1. Set the tolerance so the extracted profiles (red/green) conform to the sliced mesh profiles.'
                '   - Smaller tolerance improves accuracy, but increases the number of points and the size of the G-code.'
                ''
                '2. Set and apply Kerf Offset'
                ''
                '3. Check both profiles look correct, then click Continue.'
                ''
                'TIP: Kerf is the width of cut made by a tool or machine.'
                ''
                '- For a hot wire cutter, kerf depends mainly on wire power and feed rate (and can vary with material).'
                ''
                '- An offset must be applied to the profile to compensate.'
                ''
                'Note: the offset distance applied is half the kerf value (Kerf/2).'
                };

            app.TxtProfileGuide = uitextarea(glGuide, 'Editable','off', 'Value', guideText, 'BackgroundColor', sideBg, 'FontColor', labelCol);

            %% --- STATUS ---
            pnlStatus = uipanel(app.profilesLeft, 'Title', 'Status', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'BorderType', 'line');
            pnlStatus.Layout.Row = 6;
            glStatus = uigridlayout(pnlStatus, [1 1]);
            glStatus.Padding = [2 2 2 2];
            glStatus.BackgroundColor = sideBg;

            app.TxtProfileStatus = uitextarea(glStatus, 'Editable','off', 'Value', {''}, 'BackgroundColor', t.panelBg, 'FontColor',[1 0.8 0]);

            %% --- ACTION BUTTONS ---
            app.BtnProfilesContinue = uibutton(app.profilesLeft, 'Text','Continue →', 'FontWeight','bold', ...
                'Enable', 'off', 'BackgroundColor',[0.3 0.3 0.3], ...
                'ButtonPushedFcn',@(~,~)app.onContinue());
            app.BtnProfilesContinue.Layout.Row = 7;

            %% --- RIGHT PANEL: 2D PLOTS ---
            gridRight = uigridlayout(app.GLProfiles,[2 1]);
            gridRight.Layout.Column = 2;
            gridRight.RowHeight = {'1x','1x'};

            app.AxLeftProfile = uiaxes(gridRight);
            app.AxLeftProfile.BackgroundColor =[0.11 0.11 0.11];
            title(app.AxLeftProfile,'Left Profile');
            grid(app.AxLeftProfile,'on');
            axis(app.AxLeftProfile,'equal');

            app.AxRightProfile = uiaxes(gridRight);
            app.AxRightProfile.BackgroundColor =[0.11 0.11 0.11];
            title(app.AxRightProfile,'Right Profile');
            grid(app.AxRightProfile,'on');
            axis(app.AxRightProfile,'equal');
        end

        % TAB 3 (BILLET)
        function createBilletTab(app)
            % Purpose: Builds the Billet sizing and positioning tab UI components.
            % Inputs:  app (HotWireSTEPApp_v6_2 instance)
            % Dependencies: app.getTheme()

            % Fetch Theme Colors locally
            t = app.getTheme();
            sideBg   = t.sideBg;
            panelBg  = t.panelBg;
            labelCol = t.labelCol;
            inputBg  = t.inputBg;
            inputTxt = t.inputTxt;

            app.TabBillet = uitab(app.TabGroup, 'Title', 'Billet');

            app.GLBillet = uigridlayout(app.TabBillet,[1 2]);
            app.GLBillet.ColumnWidth = {320, '1x'};
            app.GLBillet.Padding =[10 10 10 10];

            %% --- LEFT CONTROL PANEL ---
            app.BilletLeftPanel = uigridlayout(app.GLBillet,[8 1]);
            app.BilletLeftPanel.Layout.Column = 1;

            % Rows: 1-5 Controls, 6 Guidance (1x), 7 Status (70px), 8 Continue
            app.BilletLeftPanel.RowHeight = {'fit','fit','fit','fit','fit','1x',70,'fit'};
            app.BilletLeftPanel.Padding =[10 10 10 10];
            app.BilletLeftPanel.BackgroundColor = sideBg;

            %% --- VIEW CONTROLS ---
            pnlView = uipanel(app.BilletLeftPanel, 'Title','View', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlView.Layout.Row = 1;

            gridView = uigridlayout(pnlView,[1 2]);
            gridView.Padding=[5 5 5 5];
            gridView.BackgroundColor=panelBg;

            btnViewModel = uibutton(gridView, 'Text','Model View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetBilletViewModel());
            btnViewBillet = uibutton(gridView, 'Text','Billet View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetBilletViewBillet());

            %% --- AUTO TOOLS ---
            pnlAutoTools = uipanel(app.BilletLeftPanel, 'Title','Auto Tools', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlAutoTools.Layout.Row = 2;

            gridAutoTools = uigridlayout(pnlAutoTools,[1 2]);
            gridAutoTools.Padding=[5 5 5 5];
            gridAutoTools.BackgroundColor=panelBg;

            app.BtnAutoFitBillet = uibutton(gridAutoTools, 'Text', 'Auto-fit Billet', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~)app.onAutoFitBillet());
            app.BtnAutoFitBillet.Tooltip = 'Automatically set billet size to model bounds + 4mm buffer.';

            app.BtnAutoPositionModel = uibutton(gridAutoTools, 'Text', 'Auto-position Model', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~)app.onAutoPositionModel());
            app.BtnAutoPositionModel.Tooltip = 'Center model in X, align 4mm from Y-Min and Z-Min.';

            %% --- SIZE CONTROLS ---
            pnlSize = uipanel(app.BilletLeftPanel, 'Title', 'Billet Size Controls', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold');
            pnlSize.Layout.Row = 3;

            gridSizeOuter = uigridlayout(pnlSize, [1 1]);
            gridSizeOuter.Padding =[5 5 5 5];

            gridSize = uigridlayout(gridSizeOuter, [4 6]);
            gridSize.ColumnWidth = {35, 65, 20, 65, 20, 65};
            gridSize.Padding = [4 4 4 4];
            gridSize.ColumnSpacing = 4;

            uilabel(gridSize, 'Text', 'Axis', 'FontWeight', 'bold', 'FontColor', labelCol, 'HorizontalAlignment', 'center');

            lblStockHeader = uilabel(gridSize, 'Text', 'Stock [mm]', 'FontWeight', 'bold', 'FontColor', labelCol, 'HorizontalAlignment', 'center');
            lblStockHeader.Layout.Column = [3 5];

            lblModelHeader = uilabel(gridSize, 'Text', 'Model', 'FontWeight', 'bold', 'FontColor', labelCol, 'HorizontalAlignment', 'center');
            lblModelHeader.Layout.Column = 6;

            axisLabels = {'X','Y','Z'};
            sizeTooltips = {'Length (Span)', 'Depth (Y)', 'Height (Z)'};

            app.BilletSizeEdits = gobjects(1,3);
            app.BilletSizeMinusBtns = gobjects(1,3);
            app.BilletSizePlusBtns = gobjects(1,3);
            app.BilletModelDimLabels = gobjects(1,3);

            for i = 1:3
                r = i + 1;
                % Row Label
                txtLabel = uilabel(gridSize, 'Text', axisLabels{i}, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'FontColor', labelCol);
                txtLabel.Layout.Row = r;

                % Minus Button
                app.BilletSizeMinusBtns(i) = uibutton(gridSize, 'Text', '-', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~)app.onBilletSizeStep(i,-1));
                app.BilletSizeMinusBtns(i).Layout.Row = r;
                app.BilletSizeMinusBtns(i).Layout.Column = 3;

                % Edit Field
                app.BilletSizeEdits(i) = uieditfield(gridSize, 'numeric', ...
                    'Value', 100, ...
                    'HorizontalAlignment', 'center', ...
                    'ValueDisplayFormat', '%.2f', ...
                    'BackgroundColor',[0.7 0.7 0.8], 'FontColor', [0 0 0], ...
                    'Tooltip', sizeTooltips{i}, ...
                    'ValueChangedFcn', @(src,~)app.onBilletSizeEdited(i,src));
                app.BilletSizeEdits(i).Layout.Row = r;
                app.BilletSizeEdits(i).Layout.Column = 4;

                % Plus Button
                app.BilletSizePlusBtns(i) = uibutton(gridSize, 'Text', '+', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~)app.onBilletSizeStep(i,+1));
                app.BilletSizePlusBtns(i).Layout.Row = r;
                app.BilletSizePlusBtns(i).Layout.Column = 5;

                % Model Dim Readout
                app.BilletModelDimLabels(i) = uilabel(gridSize, 'Text', '(---)', 'HorizontalAlignment', 'center', 'BackgroundColor', t.readoutBg, 'FontColor', t.readoutTxt);
                app.BilletModelDimLabels(i).Layout.Row = r;
                app.BilletModelDimLabels(i).Layout.Column = 6;
            end

            %% --- RESET POSITION ---
            app.BtnResetPosition = uibutton(app.BilletLeftPanel, 'Text', 'Reset Position', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~)app.onResetPosition());
            app.BtnResetPosition.Layout.Row = 4;

            %% --- POSITION CONTROLS ---
            pnlPos = uipanel(app.BilletLeftPanel, 'Title', 'Model Position in Stock', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold');
            pnlPos.Layout.Row = 5;

            gridPos = uigridlayout(pnlPos, [4 6]);
            gridPos.ColumnWidth = {35, 65, 20, 65, 20, 65};
            gridPos.Padding =[4 4 4 4];
            gridPos.ColumnSpacing = 4;

            uilabel(gridPos, 'Text', 'Axis', 'FontWeight', 'bold', 'FontColor', labelCol, 'HorizontalAlignment', 'center');

            lblNegHeader = uilabel(gridPos, 'Text', '-ive Gap', 'FontWeight', 'bold', 'FontColor', labelCol, 'HorizontalAlignment', 'center');
            lblNegHeader.Layout.Column = 2;

            lblShiftHeader = uilabel(gridPos, 'Text', 'Shift[mm]', 'FontWeight', 'bold', 'FontColor', labelCol, 'HorizontalAlignment', 'center');
            lblShiftHeader.Layout.Column =[3 5];

            lblPosHeader = uilabel(gridPos, 'Text', '+ive Gap', 'FontWeight', 'bold', 'FontColor', labelCol, 'HorizontalAlignment', 'center');
            lblPosHeader.Layout.Column = 6;

            app.BilletNegOffsetEdits = gobjects(1,3);
            app.BilletCenterOffsetEdits = gobjects(1,3);
            app.BilletPosOffsetEdits = gobjects(1,3);

            for i = 1:3
                r = i + 1;
                txtLabelP = uilabel(gridPos, 'Text', axisLabels{i}, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'FontColor', labelCol);
                txtLabelP.Layout.Row = r;

                app.BilletNegOffsetEdits(i) = uieditfield(gridPos, 'numeric', 'HorizontalAlignment', 'center', 'ValueDisplayFormat', '%.2f', 'BackgroundColor', inputBg, 'FontColor', inputTxt, 'ValueChangedFcn', @(src,~)app.onBilletOffsetEdited(i,"neg",src));
                app.BilletNegOffsetEdits(i).Layout.Row = r;
                app.BilletNegOffsetEdits(i).Layout.Column = 2;
                app.BilletNegOffsetEdits(i).Tooltip = 'Axis offset between model and billet edge (min axes value)';

                btnMinus = uibutton(gridPos, 'Text', '-', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~)app.onBilletShift(i,-0.5));
                btnMinus.Layout.Row = r;
                btnMinus.Layout.Column = 3;

                app.BilletCenterOffsetEdits(i) = uieditfield(gridPos, 'numeric', 'HorizontalAlignment', 'center', 'ValueDisplayFormat', '%.2f', 'BackgroundColor',[0.7 0.7 0.8], 'FontColor', [0 0 0], 'ValueChangedFcn', @(src,~)app.onBilletOffsetEdited(i,"center",src));
                app.BilletCenterOffsetEdits(i).Layout.Row = r;
                app.BilletCenterOffsetEdits(i).Layout.Column = 4;
                app.BilletCenterOffsetEdits(i).Tooltip = 'Offset in axis relative to imported model origin';

                btnPlus = uibutton(gridPos, 'Text', '+', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~)app.onBilletShift(i,+0.5));
                btnPlus.Layout.Row = r;
                btnPlus.Layout.Column = 5;

                app.BilletPosOffsetEdits(i) = uieditfield(gridPos, 'numeric', 'HorizontalAlignment', 'center', 'ValueDisplayFormat', '%.2f', 'BackgroundColor', inputBg, 'FontColor', inputTxt, 'ValueChangedFcn', @(src,~)app.onBilletOffsetEdited(i,"pos",src));
                app.BilletPosOffsetEdits(i).Layout.Row = r;
                app.BilletPosOffsetEdits(i).Layout.Column = 6;
                app.BilletPosOffsetEdits(i).Tooltip = 'Axis offset between model and billet edge (max axes value)';
            end

            %% --- GUIDANCE ---
            pnlGuide = uipanel(app.BilletLeftPanel, 'Title', 'Guidance', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'BorderType', 'line');
            pnlGuide.Layout.Row = 6;
            glGuide = uigridlayout(pnlGuide, [1 1]);
            glGuide.Padding = [2 2 2 2];
            glGuide.BackgroundColor = sideBg;

            guideTxt = {
                'REDUCE FOAM WASTE!'
                'This tab identifies what size billet is needed and positions the model within the billet.'
                'Find the smallest scrap block in the cupboard that is just large enough to fit the model before trimming on the manual hot wire cutters.'
                'You only need to leave a 4mm boundary/gap around the model in Y and Z.'
                ''
                '1. Use the auto-fit billet and position buttons!'
                ''
                '2. Adjust using the control blocks if needed.'
                };
            app.TxtBilletGuide = uitextarea(glGuide, 'Editable', 'off', 'Value', guideTxt, 'BackgroundColor', sideBg, 'FontColor', labelCol);

            %% --- STATUS ---
            pnlStatus = uipanel(app.BilletLeftPanel, 'Title', 'Status', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'BorderType', 'line');
            pnlStatus.Layout.Row = 7;
            glStatus = uigridlayout(pnlStatus, [1 1]);
            glStatus.Padding = [2 2 2 2];
            glStatus.BackgroundColor = sideBg;

            app.TxtBilletStatus = uitextarea(glStatus, 'Editable', 'off', 'Value', {''}, 'BackgroundColor', t.panelBg, 'FontColor', [1 0.8 0]);

            %% --- ACTION BUTTONS ---
            app.BtnBilletContinue = uibutton(app.BilletLeftPanel, 'Text', 'Continue', 'FontWeight', 'bold', 'BackgroundColor',[0.1 0.6 0.1], 'FontColor',[1 1 1], 'ButtonPushedFcn', @(~,~)app.onContinue());
            app.BtnBilletContinue.Layout.Row = 8;

            %% --- RIGHT PANEL: 4 VIEWS ---
            app.BilletRightPanel = uigridlayout(app.GLBillet,[2 2]);
            app.BilletRightPanel.Layout.Column = 2;
            app.BilletRightPanel.RowHeight = {'1x', '1x'};
            app.BilletRightPanel.ColumnWidth = {'1x', '1x'};
            app.BilletRightPanel.BackgroundColor = panelBg;

            % Top Left
            app.AxBilletTop = uiaxes(app.BilletRightPanel);
            app.AxBilletTop.Layout.Row = 1; app.AxBilletTop.Layout.Column = 1;
            app.AxBilletTop.BackgroundColor =[0.11 0.11 0.11];
            title(app.AxBilletTop, 'Top View (X/Y)');

            % Top Right (ISO)
            app.AxBilletIso = uiaxes(app.BilletRightPanel);
            app.AxBilletIso.Layout.Row = 1; app.AxBilletIso.Layout.Column = 2;
            app.AxBilletIso.BackgroundColor =[0.11 0.11 0.11];
            title(app.AxBilletIso, 'Iso View');
            view(app.AxBilletIso, 3); grid(app.AxBilletIso, 'on');

            % Bottom Left
            app.AxBilletFront = uiaxes(app.BilletRightPanel);
            app.AxBilletFront.Layout.Row = 2; app.AxBilletFront.Layout.Column = 1;
            app.AxBilletFront.BackgroundColor =[0.11 0.11 0.11];
            title(app.AxBilletFront, 'Front View (X/Z)');

            % Bottom Right
            app.AxBilletRight = uiaxes(app.BilletRightPanel);
            app.AxBilletRight.Layout.Row = 2; app.AxBilletRight.Layout.Column = 2;
            app.AxBilletRight.BackgroundColor =[0.11 0.11 0.11];
            title(app.AxBilletRight, 'Right View (Y/Z)');
        end
        
        % TAB 4 (MACHINE)
        function createMachineTab(app)
            % Purpose: Builds the Machine Setup and Billet placement tab UI components.
            % Inputs:  app (HotWireSTEPApp_v6_2 instance)
            % Dependencies: app.getTheme()

            % Fetch Theme Colors locally
            t = app.getTheme();
            sideBg   = t.sideBg;
            panelBg  = t.panelBg;
            labelCol = t.labelCol;

            app.TabMachine = uitab(app.TabGroup, 'Title', 'Machine');

            app.GLMachine = uigridlayout(app.TabMachine,[1 2]);
            app.GLMachine.ColumnWidth = {320, '1x'};
            app.GLMachine.Padding =[10 10 10 10];

            %% --- LEFT CONTROL PANEL ---
            app.MachineLeftPanel = uigridlayout(app.GLMachine,[6 1]);

            % Rows: 1-3 Controls, 4 Guidance (1x), 5 Status (70px), 6 Continue
            app.MachineLeftPanel.RowHeight = {'fit','fit','fit','1x',70,'fit'};
            app.MachineLeftPanel.Padding =[10 10 10 10];
            app.MachineLeftPanel.BackgroundColor = sideBg;

            %% --- VIEW CONTROLS ---
            pnlView = uipanel(app.MachineLeftPanel, 'Title','View', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlView.Layout.Row = 1;

            gridView = uigridlayout(pnlView, [1 2]);
            gridView.Padding=[5 5 5 5];
            gridView.BackgroundColor=panelBg;

            btnViewMachine = uibutton(gridView, 'Text','Machine View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetMachineViewMachine());
            btnViewBillet = uibutton(gridView, 'Text','Billet View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetMachineViewBillet());

            %% --- BILLET PLACEMENT ---
            pnlPlacement = uipanel(app.MachineLeftPanel, 'Title','Billet Placement', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold');
            pnlPlacement.Layout.Row = 2;

            gridPlacement = uigridlayout(pnlPlacement,[4 2]);
            gridPlacement.ColumnWidth={'1x',110};
            gridPlacement.Padding=[10 5 10 5];
            gridPlacement.BackgroundColor=panelBg;

            lblAxisHeader = uilabel(gridPlacement, 'Text','Axis', 'FontWeight','bold', 'FontColor',labelCol);
            lblAxisHeader.Layout.Row=1;

            lblPosHeader = uilabel(gridPlacement, 'Text','Pos [mm]', 'FontWeight','bold', 'FontColor',labelCol);
            lblPosHeader.Layout.Column=2;

            mAxisLabels = {'X (Left Bed Edge)','Y (Home Position)','Z (Bed Surface)'};
            mTooltips   = { ...
                "Distance from the LEFT edge of the physical bed to the left face of the billet.", ...
                "Distance from the front 'HOME' position to the front face of the billet.", ...
                "Distance from the BED SURFACE to the bottom of the billet." ...
                };

            app.MachinePosSpinners = gobjects(1,3);
            for i=1:3
                lblAxisRow = uilabel(gridPlacement, 'Text',mAxisLabels{i}, 'FontColor',labelCol);
                lblAxisRow.Layout.Row=i+1;

                app.MachinePosSpinners(i) = uispinner(gridPlacement, 'Limits',[-500 2000], 'Value',app.MachineBilletPos(i), 'ValueDisplayFormat','%.2f', 'Step',1.0,'Tooltip', mTooltips{i}, 'ValueChangedFcn',@(src,~)app.onMachinePosEdited(i,src));
                app.MachinePosSpinners(i).Layout.Row=i+1;
                app.MachinePosSpinners(i).Layout.Column=2;
            end

            %% --- AUTO TOOLS ---
            pnlAutoTools = uipanel(app.MachineLeftPanel, 'Title','Auto Tools', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlAutoTools.Layout.Row = 3;

            gridAutoTools = uigridlayout(pnlAutoTools,[1 1]);
            gridAutoTools.Padding=[5 5 5 5];
            gridAutoTools.BackgroundColor=panelBg;

            btnAutoPosition = uibutton(gridAutoTools, 'Text','Auto-position Billet', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetMachineBilletPosition());
            btnAutoPosition.Tooltip = 'Optimizes X position to balance tower wire lengths, snaps Z to standard stock heights, and rounds Y to a safe distance.';

            %% --- GUIDANCE ---
            pnlGuide = uipanel(app.MachineLeftPanel, 'Title', 'Guidance', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'BorderType', 'line');
            pnlGuide.Layout.Row = 4;
            glGuide = uigridlayout(pnlGuide, [1 1]);
            glGuide.Padding = [2 2 2 2];
            glGuide.BackgroundColor = sideBg;

            guideMach = {
                '1. Position the stock material securely on the physical machine bed.';
                '';
                'X: Distance from the LEFT edge of the physical bed to the left face of the billet.';
                ''
                'Y: Distance from the front HOME position to the front face of the billet. (Must be >50mm as the sacrificial bed starts at 50mm).';
                ''
                'Z: Height from the bed surface to the bottom of the billet. (Raise by 50, 75, or 100mm to match standard stock packing if needed).';
                '';
                'TAPERED PARTS: Try to position the billet so the left and right tower profile paths are as equal in length as possible.'
                };
            app.TxtMachineGuide = uitextarea(glGuide, 'Editable','off', 'Value', guideMach, 'BackgroundColor', sideBg, 'FontColor', labelCol);

            %% --- STATUS ---
            pnlStatus = uipanel(app.MachineLeftPanel, 'Title', 'Status', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'BorderType', 'line');
            pnlStatus.Layout.Row = 5;
            glStatus = uigridlayout(pnlStatus, [1 1]);
            glStatus.Padding = [2 2 2 2];
            glStatus.BackgroundColor = sideBg;

            app.TxtMachineStatus = uitextarea(glStatus, 'Editable','off', 'Value', {'Machine configuration valid.'}, 'BackgroundColor', t.panelBg, 'FontColor',[1 0.8 0]);

            %% --- ACTION BUTTONS ---
            app.BtnMachineContinue = uibutton(app.MachineLeftPanel, 'Text','Continue', 'FontWeight','bold', 'BackgroundColor',[0.1 0.6 0.1], 'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~)app.onContinue());
            app.BtnMachineContinue.Layout.Row = 6;

            %% --- RIGHT PANEL: 3D MACHINE PLOT ---
            app.AxMachine = uiaxes(app.GLMachine);
            app.AxMachine.Layout.Column=2;
            app.AxMachine.BackgroundColor=[0.05 0.05 0.05];
            grid(app.AxMachine,'on');
            view(app.AxMachine,3);
            hold(app.AxMachine,'on');
        end

        % TAB 5 (CUTTING STRATEGY)
        function createCuttingTab(app)
            % Purpose: Builds the Cutting Strategy (Lead-in/Start points) tab UI components.
            % Inputs:  app (HotWireSTEPApp_v6_2 instance)
            % Dependencies: app.getTheme(), app.getInteractionColors()

            % Fetch Theme Colors locally
            t = app.getTheme();
            sideBg   = t.sideBg;
            panelBg  = t.panelBg;
            labelCol = t.labelCol;

            app.TabCutting = uitab(app.TabGroup, 'Title', 'Cutting Strategy');

            app.GLCutting = uigridlayout(app.TabCutting, [2 2]);
            app.GLCutting.ColumnWidth   = {320, '1x'};
            app.GLCutting.RowHeight     = {'1x', '1x'};
            app.GLCutting.Padding       =[10 10 10 10];
            app.GLCutting.ColumnSpacing = 10;

            %% --- LEFT CONTROL PANEL ---
            % Spans both rows on the left side
            app.CuttingLeftPanel = uigridlayout(app.GLCutting,[7 1]);
            app.CuttingLeftPanel.Layout.Row     = [1 2];
            app.CuttingLeftPanel.Layout.Column  = 1;

            % Rows: 1-4 Controls, 5 Guidance (1x), 6 Status (70px), 7 Continue
            app.CuttingLeftPanel.RowHeight = {'fit','fit','fit','fit','1x',70,'fit'};
            app.CuttingLeftPanel.Padding   =[10 10 10 10];
            app.CuttingLeftPanel.BackgroundColor = sideBg;

            %% --- VIEW CONTROLS ---
            pnlView = uipanel(app.CuttingLeftPanel, 'Title','View', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlView.Layout.Row = 1;

            gridView = uigridlayout(pnlView, [1 2]);
            gridView.Padding=[5 5 5 5];
            gridView.ColumnSpacing=5;
            gridView.BackgroundColor=panelBg;

            btnViewMachine = uibutton(gridView, 'Text','Machine View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetCuttingViewMachine());
            btnViewBillet = uibutton(gridView, 'Text','Billet View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetCuttingViewBillet());

            %% --- AUTO TOOLS ---
            pnlAuto = uipanel(app.CuttingLeftPanel, 'Title','Auto Tools', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlAuto.Layout.Row = 2;

            gridAuto = uigridlayout(pnlAuto, [1 2]);
            gridAuto.Padding=[5 5 5 5];
            gridAuto.ColumnSpacing=5;
            gridAuto.BackgroundColor=panelBg;

            app.btnAutoStart = uibutton(gridAuto, 'Text','Auto Start', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onAutoStart());
            app.btnAutoStart.Tooltip = 'Automatically selects the start point closest to the front of the machine (Minimum Y).';

            app.btnAutoEntry = uibutton(gridAuto, 'Text','Auto Entry', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onAutoEntry());
            app.btnAutoEntry.Tooltip = 'Automatically calculates a perpendicular entry path from outside the billet boundary.';

            %% --- MODES ---
            pnlMode = uipanel(app.CuttingLeftPanel, 'Title','Modes', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlMode.Layout.Row = 3;

            gridMode = uigridlayout(pnlMode,[3 2]);
            gridMode.RowHeight = {'fit','fit','fit'};
            gridMode.ColumnWidth = {75, '1x'};
            gridMode.Padding=[5 5 5 5];
            gridMode.BackgroundColor=panelBg;

            lblDirection = uilabel(gridMode, 'Text','Direction:', 'FontColor',labelCol, 'HorizontalAlignment','right');
            lblDirection.Layout.Row=1;

            app.SwitchCutDir = uiswitch(gridMode, 'slider', 'Items',{'Top (CW)', 'Bottom (CCW)'}, 'Value','Top (CW)', 'ValueChangedFcn',@(~,~)app.onCutDirectionChanged());
            app.SwitchCutDir.Layout.Row=1;
            app.SwitchCutDir.Layout.Column=2;
            app.SwitchCutDir.Tooltip = 'Choses which way around the profile loop the wire goes from the start point';

            lblSyncStart = uilabel(gridMode, 'Text','Start Pts:', 'FontColor',labelCol, 'HorizontalAlignment','right');
            lblSyncStart.Layout.Row=2;

            app.SwitchSyncStart = uiswitch(gridMode, 'slider', 'Items',{'Coupled', 'Independent'}, 'Value','Coupled', 'ValueChangedFcn',@(src,~)app.onSyncToggleChanged(src));
            app.SwitchSyncStart.Layout.Row=2;
            app.SwitchSyncStart.Layout.Column=2;
            app.SwitchSyncStart.Tooltip = 'If there are profile sync issues, decouple and manually select start points for each profile';

            lblSyncEntry = uilabel(gridMode, 'Text','Entry Pts:', 'FontColor',labelCol, 'HorizontalAlignment','right');
            lblSyncEntry.Layout.Row=3;

            app.SwitchSyncEntry = uiswitch(gridMode, 'slider', 'Items',{'Coupled', 'Independent'}, 'Value','Coupled', 'ValueChangedFcn',@(src,~)app.onSyncEntryToggleChanged(src));
            app.SwitchSyncEntry.Layout.Row=3;
            app.SwitchSyncEntry.Layout.Column=2;
            app.SwitchSyncEntry.Tooltip = 'Independent entry points can be useful for very tapered or swept parts, entering from the top to reduce waste material';

            %% --- MOUSE INTERACTION ---
            pnlInteraction = uipanel(app.CuttingLeftPanel, 'Title','Mouse Interaction', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlInteraction.Layout.Row = 4;

            % 4 Rows for buttons
            gridInteraction = uigridlayout(pnlInteraction, [4 2]);
            gridInteraction.RowHeight = {'fit','fit','fit','fit'};
            gridInteraction.Padding=[5 5 5 5];
            gridInteraction.BackgroundColor=panelBg;

            lblInstruction = uilabel(gridInteraction, 'Text','Click plot to set:', 'FontColor',labelCol);
            lblInstruction.Layout.Row=1;
            lblInstruction.Layout.Column=[1 2];

            bCols = app.getInteractionColors();

            % Start (Green) & Lead In (Orange)
            app.BtnPickStart = uibutton(gridInteraction, 'state', 'Text','Start Pt', 'FontWeight','bold', ...
                'BackgroundColor',bCols.StartInactive, 'FontColor',bCols.TextInactive, ...
                'Tooltip','First point on the profile cut.', ...
                'ValueChangedFcn',@(src,evt)app.onInteractionStatsChanged(src));
            app.BtnPickStart.Layout.Row=2; app.BtnPickStart.Layout.Column=1;

            app.BtnPickEntry = uibutton(gridInteraction, 'state', 'Text','Lead In', 'FontWeight','bold', ...
                'BackgroundColor',bCols.EntryInactive, 'FontColor',bCols.TextInactive, ...
                'Tooltip','Point outside billet where cut begins (Orange line).', ...
                'ValueChangedFcn',@(src,evt)app.onInteractionStatsChanged(src));
            app.BtnPickEntry.Layout.Row=2; app.BtnPickEntry.Layout.Column=2;

            % Link 1 & Link 2 (Yellow)
            app.BtnPickEntry2 = uibutton(gridInteraction, 'state', 'Text','Link 1', 'FontWeight','bold', ...
                'BackgroundColor',bCols.LinkInactive, 'FontColor',bCols.TextInactive, ...
                'Tooltip','Rapid move point before Lead In.', ...
                'ValueChangedFcn',@(src,evt)app.onInteractionStatsChanged(src));
            app.BtnPickEntry2.Layout.Row=3; app.BtnPickEntry2.Layout.Column=1;

            app.BtnPickEntry3 = uibutton(gridInteraction, 'state', 'Text','Link 2', 'FontWeight','bold', ...
                'BackgroundColor',bCols.LinkInactive, 'FontColor',bCols.TextInactive, ...
                'Tooltip','Optional 2nd Rapid move point (useful to got over the top of the block.', ...
                'ValueChangedFcn',@(src,evt)app.onInteractionStatsChanged(src));
            app.BtnPickEntry3.Layout.Row=3; app.BtnPickEntry3.Layout.Column=2;

            % Clear
            btnClear = uibutton(gridInteraction, 'Text','Clear Pts', 'FontWeight','bold', ...
                'BackgroundColor',t.accentBg, 'FontColor',t.editTxt, ...
                'Tooltip','Reset entry/link points.', ...
                'ButtonPushedFcn',@(~,~)app.onClearEntries());
            btnClear.Layout.Row=4; btnClear.Layout.Column=[1 2];

            %% --- GUIDANCE ---
            pnlGuide = uipanel(app.CuttingLeftPanel, 'Title', 'Guidance', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'BorderType', 'line');
            pnlGuide.Layout.Row = 5;
            glGuide = uigridlayout(pnlGuide, [1 1]);
            glGuide.Padding = [2 2 2 2];
            glGuide.BackgroundColor = sideBg;

            guideCut = {
                'This tab allows visualisation and modification of the wire path, direction, entry/exit, cut direction.';
                '';
                '1. Set the direction of cut using the toggle. It is usually best to do top first, otherwise the part can shift during the cut, dropping in to the channel left by the bottom of the cut.';
                '';
                '2. Chose the start point. Usually toward the front of the machine.';
                'The wire visits this point twice, which can leave a "witness mark". Hide this on a trailing edge, inside the part, or somewhere not important for smoothness.';
                'You should have rotated using the model tab so this point is toward the front of the machine (Ymin).';
                'If, for tapered parts there are issues with L/R profile sync, you can decouple and manually select different start points for each profile.';
                '';
                '3. Chose entry points. Try the Auto entry button first.';
                'The orange Lead In line is a cutting move and must begin outside the billet.';
                'Set it to minimise the change in direction between the orange line and the start/end of the cut.';
                'If you are entering from the top of the block, or have a lot of sweep, the Link point can route the wire over the top of the block, saving waste material.'
                };
            app.TxtCuttingGuide = uitextarea(glGuide, 'Editable','off', 'Value', guideCut, 'BackgroundColor', sideBg, 'FontColor', labelCol);

            %% --- STATUS ---
            pnlStatus = uipanel(app.CuttingLeftPanel, 'Title', 'Status', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'BorderType', 'line');
            pnlStatus.Layout.Row = 6;
            glStatus = uigridlayout(pnlStatus, [1 1]);
            glStatus.Padding = [2 2 2 2];
            glStatus.BackgroundColor = sideBg;

            app.TxtCuttingStatus = uitextarea(glStatus, 'Editable','off', 'Value', {'Strategy valid.', 'Review paths and continue.'}, 'BackgroundColor', t.panelBg, 'FontColor',[0.4 1 0.4]);

            %% --- ACTION BUTTONS ---
            app.BtnCuttingContinue = uibutton(app.CuttingLeftPanel, 'Text','Continue', 'FontWeight','bold', 'BackgroundColor',[0.1 0.6 0.1], 'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~)app.onContinue());
            app.BtnCuttingContinue.Layout.Row = 7;

            %% --- RIGHT PANEL: 2D CUT PLOTS ---
            app.AxCutLeft = uiaxes(app.GLCutting);
            app.AxCutLeft.Layout.Row=1;
            app.AxCutLeft.Layout.Column=2;
            app.AxCutLeft.BackgroundColor = t.editBg;
            grid(app.AxCutLeft,'on');
            title(app.AxCutLeft,'Left Profile Cut Path');

            app.AxCutRight = uiaxes(app.GLCutting);
            app.AxCutRight.Layout.Row=2;
            app.AxCutRight.Layout.Column=2;
            app.AxCutRight.BackgroundColor = t.editBg;
            grid(app.AxCutRight,'on');
            title(app.AxCutRight,'Right Profile Cut Path');
        end
        
        % TAB 6 (SIMULATION)
        function createSimulationTab(app)
            % Purpose: Builds the Kinematics Simulation tab UI components.
            % Inputs:  app (HotWireSTEPApp_v6_2 instance)
            % Dependencies: app.getTheme()

            % Fetch Theme Colors locally
            t = app.getTheme();
            sideBg   = t.sideBg;
            panelBg  = t.panelBg;
            labelCol = t.labelCol;

            app.TabSimulation = uitab(app.TabGroup, 'Title', 'Simulation');

            app.GLSimulation = uigridlayout(app.TabSimulation, [1 2]);
            app.GLSimulation.ColumnWidth = {320, '1x'};
            app.GLSimulation.Padding =[10 10 10 10];

            %% --- LEFT CONTROL PANEL ---
            app.SimLeftPanel = uigridlayout(app.GLSimulation, [6 1]);
            app.SimLeftPanel.RowHeight = {'fit', 'fit', 'fit', 'fit', '1x', 'fit'};
            app.SimLeftPanel.Padding = [10 10 10 10];
            app.SimLeftPanel.BackgroundColor = sideBg;

            %% --- VIEW CONTROLS ---
            pnlView = uipanel(app.SimLeftPanel, 'Title','View', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlView.Layout.Row = 1;

            gridView = uigridlayout(pnlView, [1 2]);
            gridView.Padding=[5 5 5 5];
            gridView.BackgroundColor=panelBg;

            btnViewMachine = uibutton(gridView, 'Text','Machine View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetSimViewMachine());
            btnViewBillet = uibutton(gridView, 'Text','Billet View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetSimViewBillet());

            %% --- PLAYBACK CONTROLS ---
            pnlPlayback = uipanel(app.SimLeftPanel, 'Title','Playback', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlPlayback.Layout.Row = 2;

            gridPlayback = uigridlayout(pnlPlayback,[2 3]);
            gridPlayback.ColumnWidth={'1x','1x','1x'};
            gridPlayback.RowHeight={'fit','fit'};
            gridPlayback.Padding=[5 5 5 5];
            gridPlayback.BackgroundColor=panelBg;

            % Row 1: Buttons
            app.SimPlayBtn = uibutton(gridPlayback, 'Text','Play', 'FontWeight','bold', 'BackgroundColor',t.accentBg, 'FontColor',t.editTxt, 'ButtonPushedFcn',@(~,~)app.onSimPlay());
            btnPause = uibutton(gridPlayback, 'Text','Pause', 'FontWeight','bold', 'BackgroundColor',panelBg, 'FontColor',labelCol, 'ButtonPushedFcn',@(~,~)app.onSimPause());
            app.SimStopBtn = uibutton(gridPlayback, 'Text','Reset', 'FontWeight','bold', 'BackgroundColor',panelBg, 'FontColor',labelCol, 'ButtonPushedFcn',@(~,~)app.onSimStop());

            % Row 2: Slider + Spinner
            app.SimSlider = uislider(gridPlayback, 'Limits',[1 100], 'Value',1, 'ValueChangedFcn',@(src,~)app.onSimSliderChanging(src));
            app.SimSlider.Layout.Row = 2;
            app.SimSlider.Layout.Column = [1 2];

            app.SimIndexSpinner = uispinner(gridPlayback, 'Limits',[1 100], 'Value',1, 'RoundFractionalValues','on', 'ValueChangedFcn',@(src,~)app.onSimIndexSpinnerChanged(src));
            app.SimIndexSpinner.Layout.Row = 2;
            app.SimIndexSpinner.Layout.Column = 3;

            %% --- SETTINGS ---
            pnlSettings = uipanel(app.SimLeftPanel, 'Title','Settings', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlSettings.Layout.Row = 3;

            gridSettings = uigridlayout(pnlSettings, [2 2]);
            gridSettings.ColumnWidth={'1x', 80}; % 80px strictly matches the spinner/box width
            gridSettings.RowHeight={'fit', 'fit'};
            gridSettings.Padding=[5 5 5 5];
            gridSettings.BackgroundColor=panelBg;

            lblSpeed = uilabel(gridSettings, 'Text','Sim Speed Multiplier:', 'FontColor',labelCol, 'HorizontalAlignment','right');
            lblSpeed.Layout.Row=1; lblSpeed.Layout.Column=1;

            app.SimSpeedSpinner = uispinner(gridSettings, 'Limits',[0.1 60], 'Value',40.0, 'Step',1.0, 'Tooltip', 'Simulation speed as multiple of set feed rate');
            app.SimSpeedSpinner.Layout.Row=1; app.SimSpeedSpinner.Layout.Column=2;

            lblBaseFeed = uilabel(gridSettings, 'Text','Base Feed Rate [mm/min]:', 'FontColor',labelCol, 'HorizontalAlignment','right');
            lblBaseFeed.Layout.Row=2; lblBaseFeed.Layout.Column=1;

            app.LblBaseFeed = uilabel(gridSettings, 'Text', sprintf('%.0f', HotWireSTEPApp_v6_2.DefaultFeedRate), 'HorizontalAlignment', 'center', ...
                'BackgroundColor', t.readoutBg, 'FontColor', t.readoutTxt);
            app.LblBaseFeed.Layout.Row=2; app.LblBaseFeed.Layout.Column=2;

            %% --- LIVE SYSTEM STATUS ---
            pnlStatus = uipanel(app.SimLeftPanel, 'Title','Live System Status', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlStatus.Layout.Row = 4;

            % 5 Rows: R1 Header, R2-R3 Coords, R4 Text, R5 Gauge
            gridStatus = uigridlayout(pnlStatus,[5 5]);
            gridStatus.ColumnWidth = {'fit', 60, '1x', 'fit', 60};
            gridStatus.RowHeight = {'fit', 'fit', 'fit', 'fit', 50};
            gridStatus.Padding =[10 10 10 10];
            gridStatus.BackgroundColor = panelBg;

            lblHeadL = uilabel(gridStatus, 'Text','Left Tower', 'FontWeight','bold', 'FontColor',labelCol, 'HorizontalAlignment','center');
            lblHeadL.Layout.Column = [1 2];

            lblHeadR = uilabel(gridStatus, 'Text','Right Tower', 'FontWeight','bold', 'FontColor',labelCol, 'HorizontalAlignment','center');
            lblHeadR.Layout.Column = [4 5];

            % Row 2: X/Z
            lblX = uilabel(gridStatus, 'Text','X:', 'FontWeight','bold', 'FontColor',t.accentBg, 'HorizontalAlignment','right');
            lblX.Layout.Row=2;

            app.LblReadoutX = uilabel(gridStatus, 'Text','0.00', 'FontName','Monospaced', 'FontColor',labelCol);
            app.LblReadoutX.Layout.Row=2; app.LblReadoutX.Layout.Column=2;

            lblZ = uilabel(gridStatus, 'Text','Z:', 'FontWeight','bold', 'FontColor',t.accentBg, 'HorizontalAlignment','right');
            lblZ.Layout.Row=2; lblZ.Layout.Column=4;

            app.LblReadoutZ = uilabel(gridStatus, 'Text','0.00', 'FontName','Monospaced', 'FontColor',labelCol);
            app.LblReadoutZ.Layout.Row=2; app.LblReadoutZ.Layout.Column=5;

            % Row 3: Y/A
            lblY = uilabel(gridStatus, 'Text','Y:', 'FontWeight','bold', 'FontColor',t.accentBg, 'HorizontalAlignment','right');
            lblY.Layout.Row=3;

            app.LblReadoutY = uilabel(gridStatus, 'Text','0.00', 'FontName','Monospaced', 'FontColor',labelCol);
            app.LblReadoutY.Layout.Row=3; app.LblReadoutY.Layout.Column=2;

            lblA = uilabel(gridStatus, 'Text','A:', 'FontWeight','bold', 'FontColor',t.accentBg, 'HorizontalAlignment','right');
            lblA.Layout.Row=3; lblA.Layout.Column=4;

            app.LblReadoutA = uilabel(gridStatus, 'Text','0.00', 'FontName','Monospaced', 'FontColor',labelCol);
            app.LblReadoutA.Layout.Row=3; app.LblReadoutA.Layout.Column=5;

            % Row 4: Extension Label
            lblGaugeTitle = uilabel(gridStatus);
            lblGaugeTitle.Layout.Row = 4;
            lblGaugeTitle.Layout.Column = [1 5];
            lblGaugeTitle.Text = 'Wire Extension (Pulley Travel) [mm]';
            lblGaugeTitle.FontWeight = 'bold';
            lblGaugeTitle.FontColor = labelCol;
            lblGaugeTitle.HorizontalAlignment = 'center';

            % Row 5: Linear Gauge
            gaugeExt = uigauge(gridStatus, 'linear');
            gaugeExt.Layout.Row = 5;
            gaugeExt.Layout.Column = [1 5];

            % Calculate a clean scale maximum (round up to nearest 10mm)
            scaleMax = ceil((app.WireExt_Red * 1.2) / 10) * 10;

            gaugeExt.MajorTicks = 0:5:scaleMax;
            gaugeExt.Limits = [0, scaleMax];

            % Styling: Muted Industrial Palette
            gaugeExt.ScaleColors =[0.1 0.6 0.1; 0.8 0.5 0.0; 0.7 0.1 0.1];
            gaugeExt.ScaleColorLimits =[0 app.WireExt_Amber; ...
                app.WireExt_Amber app.WireExt_Red; ...
                app.WireExt_Red scaleMax];

            gaugeExt.FontColor = labelCol;
            gaugeExt.FontSize = 8;
            gaugeExt.BackgroundColor = panelBg;

            gaugeExt.Tooltip = {sprintf('Tapered cuts require the wire to change length using a mass pulley system'), ...
                sprintf('This dial shows the live extention reuqired during the simulation'), ...
                sprintf('Green: Safe operation.'), ...
                sprintf('Amber (>%.0fmm): Approaching pulley limit.', app.WireExt_Amber), ...
                sprintf('Red (>%.0fmm): Critical mechanical limit, wire will break!', app.WireExt_Red)};

            app.SimGaugeExt = gaugeExt;

            %% --- PROGRAM EXTENTS ---
            pnlBounds = uipanel(app.SimLeftPanel, 'Title','Program Extents', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlBounds.Layout.Row = 5;

            gridBounds = uigridlayout(pnlBounds, [3 1]);
            gridBounds.RowHeight = {'fit', 'fit', 'fit'};
            gridBounds.Padding =[10 5 10 5];
            gridBounds.RowSpacing = 5;
            gridBounds.BackgroundColor = panelBg;

            app.LblSimExtMin = uilabel(gridBounds, 'Text','Extents Min: ---', 'FontName','Monospaced', 'FontSize', 11, 'FontColor',labelCol);
            app.LblSimExtMin.Layout.Row = 1;

            app.LblSimExtMax = uilabel(gridBounds, 'Text','Extents Max: ---', 'FontName','Monospaced', 'FontSize', 11, 'FontColor',labelCol);
            app.LblSimExtMax.Layout.Row = 2;

            app.LblSimExtWire = uilabel(gridBounds, 'Text','Max Wire Extension: ---', 'FontName','Monospaced', 'FontSize', 11, 'FontColor',t.wireKerf);
            app.LblSimExtWire.Layout.Row = 3;

            %% --- ACTION BUTTONS ---
            % Spacer to push button to bottom
            lblSpacer = uilabel(app.SimLeftPanel, 'Text', '');
            lblSpacer.Layout.Row = 6;

            app.BtnSimContinue = uibutton(app.SimLeftPanel, 'Text','Continue', 'FontWeight','bold', 'BackgroundColor',[0.1 0.6 0.1], 'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~)app.onContinue());
            app.BtnSimContinue.Layout.Row = 7;

            app.SimLeftPanel.RowHeight = {'fit', 'fit', 'fit', 'fit', 'fit', '1x', 'fit'};

            %% --- RIGHT PANEL: 3D SIM PLOT ---
            app.AxSim = uiaxes(app.GLSimulation);
            app.AxSim.Layout.Column = 2;
            app.AxSim.BackgroundColor = [0.05 0.05 0.05];
            xlabel(app.AxSim,'X'); ylabel(app.AxSim,'Y'); zlabel(app.AxSim,'Z');
            grid(app.AxSim,'on'); view(app.AxSim, 3); axis(app.AxSim, 'equal');
        end

        % TAB 7 (POST-PROCESS)
        function createPostProcessTab(app)
            % Purpose: Builds the Post-Processor and G-Code export tab UI components.
            % Inputs:  app (HotWireSTEPApp_v6_2 instance)
            % Dependencies: app.getTheme()

            % Fetch Theme Colors locally
            t = app.getTheme();
            sideBg   = t.sideBg;
            panelBg  = t.panelBg;
            labelCol = t.labelCol;

            app.TabPostProcess = uitab(app.TabGroup, 'Title', 'Post-Process');

            app.GLPostProcess = uigridlayout(app.TabPostProcess,[ 1 2 ]);
            app.GLPostProcess.ColumnWidth   = {320, '1x'};
            app.GLPostProcess.Padding       =[ 10 10 10 10 ];

            %% --- LEFT CONTROL PANEL ---
            app.PostLeftPanel = uigridlayout(app.GLPostProcess,[ 7 1 ]);

            % Rows: 1-3 Controls, 4 GCode (1x), 5 Guidance (1x), 6 Status (70px), 7 Save
            app.PostLeftPanel.RowHeight = {'fit', 'fit', 'fit', '1x', '1x', 70, 'fit'};
            app.PostLeftPanel.Padding =[ 10 10 10 10 ];
            app.PostLeftPanel.BackgroundColor = sideBg;

            %% --- VIEW CONTROLS ---
            pnlView = uipanel(app.PostLeftPanel, 'Title','View', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlView.Layout.Row = 1;

            gridView = uigridlayout(pnlView,[ 1 2 ]);
            gridView.Padding=[ 5 5 5 5 ];
            gridView.BackgroundColor=panelBg;

            btnViewMachine = uibutton(gridView, 'Text','Machine View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetPostViewMachine());
            btnViewBillet = uibutton(gridView, 'Text','Billet View', 'FontWeight','bold', 'ButtonPushedFcn',@(~,~)app.onResetPostViewBillet());

            %% --- SETTINGS (FEED & POWER) ---
            pnlSettings = uipanel(app.PostLeftPanel, 'Title','Cutting Parameters', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlSettings.Layout.Row = 2;

            gridSettings = uigridlayout(pnlSettings,[ 2 3 ]);
            gridSettings.ColumnWidth={'1x', 'fit', 80};
            gridSettings.RowHeight={'fit', 'fit'};
            gridSettings.Padding=[ 5 5 5 5 ];
            gridSettings.BackgroundColor=panelBg;

            app.ChkDynamicFeed = uicheckbox(gridSettings, 'Text', 'Dynamic', 'FontColor', labelCol, 'Value', true);
            app.ChkDynamicFeed.Layout.Row=1; app.ChkDynamicFeed.Layout.Column=1;
            app.ChkDynamicFeed.Tooltip = 'Scale feed rate continuously so the wire maintains constant speed through the foam on tapered parts.';
            app.ChkDynamicFeed.ValueChangedFcn = @(src,evt)app.updatePostStatus();

            lblFeed = uilabel(gridSettings, 'Text','Feed Rate [mm/min]:', 'FontColor',labelCol, 'HorizontalAlignment','right');
            lblFeed.Layout.Row=1; lblFeed.Layout.Column=2;

            app.SpinFeedRate = uispinner(gridSettings, 'Limits',[ 10 500 ], 'Value', HotWireSTEPApp_v6_2.DefaultFeedRate, 'Step',5, 'ValueDisplayFormat','%.0f');
            app.SpinFeedRate.Layout.Row=1; app.SpinFeedRate.Layout.Column=3;
            app.SpinFeedRate.Tooltip = 'Programmed speed of wire, kerf is inversely proportional to speed';
            app.SpinFeedRate.ValueChangedFcn = @(src,evt)app.updatePostStatus();

            lblPower = uilabel(gridSettings, 'Text','Hot Wire Power [%]:', 'FontColor',labelCol, 'HorizontalAlignment','right');
            lblPower.Layout.Row=2; lblPower.Layout.Column=2;

            app.SpinPower = uispinner(gridSettings, 'Limits',[ 10 100 ], 'Value', HotWireSTEPApp_v6_2.DefaultPower, 'Step',1, 'ValueDisplayFormat','%.0f');
            app.SpinPower.Layout.Row=2; app.SpinPower.Layout.Column=3;
            app.SpinPower.Tooltip = 'Programmed wire power, kerf is proportional to wire power';
            app.SpinPower.ValueChangedFcn = @(src,evt)app.updatePostStatus();

            %% --- FILENAME & EXPORT ---
            pnlExport = uipanel(app.PostLeftPanel, 'Title','Filename:', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'BorderType','line');
            pnlExport.Layout.Row = 3;

            gridExport = uigridlayout(pnlExport,[ 2 1 ]);
            gridExport.RowHeight={'fit','fit'};
            gridExport.Padding=[ 5 5 5 5 ];
            gridExport.BackgroundColor=panelBg;

            app.FieldFilename = uieditfield(gridExport, 'text', 'Value', 'GCode-V1-Output.gcode');

            app.BtnPostProcess = uibutton(gridExport, 'Text','Post-Process', 'FontWeight','bold', ...
                'BackgroundColor',t.accentBg, 'FontColor',t.editTxt, 'ButtonPushedFcn',@(~,~)app.onPostProcess());
            app.BtnPostProcess.Tooltip = 'Press to generate g-code';

            %% --- G-CODE VIEWER ---
            app.PanelGCode = uipanel(app.PostLeftPanel, 'Title','G-Code', 'FontWeight','bold', 'BorderType','line');
            app.PanelGCode.Layout.Row = 4;

            app.GridGCode = uigridlayout(app.PanelGCode, [ 2 2 ]);
            app.GridGCode.RowHeight = {'1x', 'fit'};
            app.GridGCode.ColumnWidth = {'1x','1x'};
            app.GridGCode.Padding =[ 5 5 5 5 ];

            app.ListGCode = uilistbox(app.GridGCode, 'Items', {'(Generate to view G-code...)'}, 'ValueChangedFcn', @(src,~)app.onPostLineSelected(src));
            app.ListGCode.Layout.Row = 1;
            app.ListGCode.Layout.Column =[ 1 2 ];
            app.ListGCode.FontName = 'Courier New';

            app.BtnGCodePrev = uibutton(app.GridGCode,'push','Text','◀ Prev', 'ButtonPushedFcn', @(~,~)app.stepPostLine(-1));
            app.BtnGCodePrev.Layout.Row = 2;
            app.BtnGCodePrev.Layout.Column = 1;

            app.BtnGCodeNext = uibutton(app.GridGCode,'push','Text','Next ▶', 'ButtonPushedFcn', @(~,~)app.stepPostLine(+1));
            app.BtnGCodeNext.Layout.Row = 2;
            app.BtnGCodeNext.Layout.Column = 2;

            %% --- GUIDANCE ---
            pnlGuide = uipanel(app.PostLeftPanel, 'Title', 'Guidance', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'BorderType', 'line');
            pnlGuide.Layout.Row = 5;
            glGuide = uigridlayout(pnlGuide, [1 1]);
            glGuide.Padding =[2 2 2 2];
            glGuide.BackgroundColor = sideBg;

            guidePost = {
                '1. Set feed rate and wire power.';
                '2. Press post process, and verify code.';
                '';
                'NOTE:';
                'Feed and power must be balanced to produce the correct kerf.';
                'Set power as low as possible for the block width to preserve fine detail.';
                '';
                'WARNING:';
                'Power too low / Feed too high = wire drag, cut corners, or break.';
                'Power too high / Feed too low = kerf too big, melted details, burned foam.'
                };
            app.TxtPostGuide = uitextarea(glGuide, 'Editable','off', 'Value', guidePost, 'BackgroundColor', sideBg, 'FontColor', labelCol);

            %% --- STATUS ---
            pnlStatus = uipanel(app.PostLeftPanel, 'Title', 'Status', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'BorderType', 'line');
            pnlStatus.Layout.Row = 6;
            glStatus = uigridlayout(pnlStatus,[1 1]);
            glStatus.Padding =[2 2 2 2];
            glStatus.BackgroundColor = sideBg;

            app.TxtPostStatus = uitextarea(glStatus, 'Editable','off', 'Value', {'Ready.'}, 'BackgroundColor',[ 0.2 0.2 0.2 ], 'FontColor',[ 0.9 0.9 0.9 ]);

            %% --- ACTION BUTTONS ---
            app.BtnSaveGCode = uibutton(app.PostLeftPanel, 'Text','Save G-Code', 'FontWeight','bold', ...
                'BackgroundColor',[ 0.1 0.6 0.1 ], 'FontColor',[ 1 1 1 ], 'Enable','off', ...
                'ButtonPushedFcn',@(~,~)app.onSaveGCode());
            app.BtnSaveGCode.Layout.Row = 7;
            app.BtnSaveGCode.Tooltip = 'Press to save g-code as a .tap file ready for mach4';

            %% --- RIGHT PANEL: 3D POST PLOT ---
            app.AxPost = uiaxes(app.GLPostProcess);
            app.AxPost.Layout.Column = 2;
            app.AxPost.BackgroundColor =[ 0.05 0.05 0.05 ];
            xlabel(app.AxPost,'X'); ylabel(app.AxPost,'Y'); zlabel(app.AxPost,'Z');
            grid(app.AxPost,'on'); view(app.AxPost,3); axis(app.AxPost,'equal');
        end

    end
end
