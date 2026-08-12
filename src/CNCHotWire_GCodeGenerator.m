classdef CNCHotWire_GCodeGenerator < handle
    % ===========================================================
    % HOTWIRE CNC G-CODE GENERATOR (V1)
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
    % - Main App: CNCHotWire_GCodeGenerator (UI, State Machine, Plotting)
    % - Helpers: CNCHotWire_GCodeGenerator_Helpers (STEP Import, Geometry Math)
    % ===========================================================

    properties (Constant)
        %% --- PHYSICAL MACHINE LIMITS ---
        MachineSpanX   (1,1) double = 1180;            % [mm] Fixed distance between left and right towers
        MachineLimitY  (1,1) double = 750;             % [mm] Total Y-axis travel (0 to 750)
        MachineLimitZ  (1,1) double = 500;             % [mm] Total Z-axis travel (0 to 500)
        MachineBedPos  (1,3) double = [44, 50, -24];   % [mm] Physical bed origin [X, Y, Z] relative to machine zero (front bottom left)
        MachineBedSize (1,3) double = [1088, 700, 24]; % [mm] Physical 'sacrificail' bed dimensions [X, Y, Z]
        BrassJointOffsetRight (1,1) double = -50.0;    % [mm] Neutral position of brass joint relative to right bed edge (negative = inward/over bed)

        %% --- SAFETY THRESHOLDS ---
        SafetyBuffer_BedEdge   (1,1) double = 10.0;   % [mm] Distance billet is from bed edge to trigger Amber warning
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
        ButtonHeight     (1,1) double = 22;   % [px] Standard height for action buttons
        RowHeightNormal  (1,1) double = 22;   % [px] Standard row height for inputs/spinners
        FontSizeNormal   (1,1) double = 12;   % [pt] Standard font size for labels and text areas
        FontSizeHeader   (1,1) double = 12;   % [pt] Font size for panel headers and emphasis
        FontSizeTitle    (1,1) double = 16;   % [pt] Font size for major titles
        BlockSpacing     (1,1) double = 4;    % [px] Standard spacing between vertical blocks/panels
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
        BtnResetKerf           % Button to reset kerf offset spinner values to default
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
        GitHubLink string = "https://github.com/ce20323/GitRepo_CNCHotWire_Gcode_App" % Link to project repository

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
        KerfLeftValue  (1,1) double = CNCHotWire_GCodeGenerator.DefaultKerf % Independent left kerf value
        KerfRightValue (1,1) double = CNCHotWire_GCodeGenerator.DefaultKerf % Independent right kerf value
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

        %% ===========================================================
        %% --- GROUP 1: LIFECYCLE & INITIALIZATION ---
        %% ===========================================================

        function app = CNCHotWire_GCodeGenerator()
            % Constructor: Called when the app is launched.
            % Closes any existing instances of the app to prevent duplicates,
            % then triggers the UI build process.

            old = findall(0, 'Type', 'figure', 'Name', 'CNC Hot Wire G Code Generator');
            if ~isempty(old)
                delete(old);
            end

            app.buildUI();
        end

        function buildUI(app)
            % Purpose: Main entry point for constructing the user interface.
            % HOW: To prevent this function from becoming a monolithic, unreadable
            % block of code, the actual construction of each tab is delegated to
            % private methods located at the bottom of this class (e.g., createWelcomeTab).

            %% --- MAIN WINDOW SETUP ---
            % Build hidden at the final intended size. This avoids a deployed-app
            % layout issue where resizing the UIFigure after child layouts are created
            % can leave grid layouts stuck at the earlier, smaller figure size.
            app.UIFigure = uifigure('Name', 'CNC Hot Wire G Code Generator', 'Visible', 'off');
            app.UIFigure.CloseRequestFcn = @(src,event)app.onAppClose(src);

            % Key press listener used primarily for scrolling G-Code on the Post tab
            app.UIFigure.WindowKeyPressFcn = @(src,event)app.onKeyPress(src,event);

            % --- Theme & Colors ---
            t = app.getTheme();
            app.UIFigure.Color = t.sideBg;

            % Set the final startup size before constructing any layouts.
            screenSize = get(groot, 'ScreenSize');

            targetW = min(1800, round(screenSize(3) * 0.94));
            targetH = min(1080, round(screenSize(4) * 0.90));

            targetX = max(20, round((screenSize(3) - targetW) / 2));
            targetY = max(40, round((screenSize(4) - targetH) / 2));

            app.UIFigure.Position = [targetX targetY targetW targetH];

            %% --- Tab Group Container ---
            % Use a root grid layout instead of normalized positioning. This is more
            % reliable in deployed apps because all child layout is handled by MATLAB's
            % layout manager rather than by figure-size normalized coordinates.
            rootGrid = uigridlayout(app.UIFigure, [1 1]);
            rootGrid.RowHeight = {'1x'};
            rootGrid.ColumnWidth = {'1x'};
            rootGrid.Padding = [0 0 0 0];
            rootGrid.RowSpacing = 0;
            rootGrid.ColumnSpacing = 0;
            rootGrid.BackgroundColor = t.sideBg;

            app.TabGroup = uitabgroup(rootGrid, ...
                'SelectionChangedFcn', @(src,evt)app.onTabChanged(src,evt));

            app.TabGroup.Layout.Row = 1;
            app.TabGroup.Layout.Column = 1;

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
            app.applyTheme();           % Sweeps the UI to replace hardcoded colors with active theme

            % Show only after the UI is fully constructed and themed.            
            app.UIFigure.Visible = 'on';
            drawnow;

        end

        function delete(app)
            % Destructor: Ensures background timers are killed when the app object is destroyed.
            if ~isempty(app.SimTimer) && isvalid(app.SimTimer)
                stop(app.SimTimer);
                delete(app.SimTimer);
            end
        end

        function onAppClose(app, src)
            % Callback: Triggered when the user clicks the 'X' to close the window.
            if ~isempty(app.SimTimer) && isvalid(app.SimTimer)
                stop(app.SimTimer);
                delete(app.SimTimer);
            end
            delete(src); % Close window
        end

        %% ===========================================================
        %% --- GROUP 2: GLOBAL STATE & NAVIGATION ---
        %% ===========================================================

        function onTabChanged(app, ~, evt)
            % Purpose: The "Gatekeeper" of the application.
            % WHY: Because this is a linear workflow (CAD -> CAM -> GCode),
            %      users cannot jump to the Simulation tab if they haven't loaded a model.
            % HOW: Every time a tab is clicked, this function intercepts the change.
            %      It checks if the prerequisites for the target tab are met.
            %      If not, it blocks the transition and offers to Auto-Calculate the missing steps.

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

            % Determine what data the target tab requires
            needsProfiles = ~isModel && ~isGuide && ~isWelcome;
            needsKerf     = isBillet || isMachine || isCutting || isSim || isPost;
            needsBillet   = isBillet || isMachine || isCutting || isSim || isPost;
            needsMachine  = isMachine || isCutting || isSim || isPost;
            needsCutting  = isCutting || isSim || isPost;

            forceAuto = false;

            %% --- LEVEL 1: MODEL GATEKEEPER ---
            hasModel = ~isempty(app.ModelPatch) && isgraphics(app.ModelPatch);
            if needsProfiles && ~hasModel
                app.TabGroup.SelectedTab = app.TabWelcome;
                uialert(app.UIFigure, 'Please load a 3D Model first.', 'Step 1 Missing', 'Icon','warning');
                return;
            end

            %% --- LEVEL 2: PROFILES & KERF GATEKEEPER ---
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

            %% --- LEVEL 3: BILLET GATEKEEPER ---
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
                        end
                    end
                end
            end

            %% --- LEVEL 4: MACHINE GATEKEEPER ---
            if needsMachine
                % Recalculate only when the machine position is stale and remains
                % automatically controlled. A user-modified position is retained and
                % validated against the updated billet configuration.
                if ~app.IsMachineInit && ~app.IsMachineUserModified
                    app.onResetMachineBilletPosition();
                end
                [ isValidMach, pCol, tCol, msgLines ] = app.checkMachineState();
                isExtRed   = app.MaxPathExtension > app.WireExt_Red;
                isExtAmber = app.MaxPathExtension > app.WireExt_Amber;

                % Case A: CRITICAL ERROR (Red) - Block movement to Sim/Post, but allow Cutting
                if ~isValidMach || isExtRed
                    if isPost
                        reason = "Billet is outside machine limits.";
                        if isExtRed, reason = sprintf("Wire will snap! Extension (%.2fmm) exceeds pulley travel.", app.MaxPathExtension); end
                        uialert(app.UIFigure, reason, 'Machine Safety Error');
                        app.TabGroup.SelectedTab = app.TabMachine;
                        return;
                    end

                    % Case B: WARNING (Amber) - Speed-bump popup when moving FORWARD to Sim/Post
                elseif isExtAmber && (isSim || isPost)
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

            %% --- LEVEL 5: CUTTING STRATEGY GATEKEEPER ---
            if needsCutting
                % Auto-Trigger: Only if never setup (Init=0)
                % If the user has manually modified the points, we respect their lock.
                if ~app.IsCuttingInit
                    if ~app.IsCuttingUserModified
                        app.onAutoStart(false);
                        app.onAutoEntry(false);
                    end
                    app.IsCuttingInit = true;
                end
                [ isValidCut, pColC, tColC, msgLinesC ] = app.validateCuttingStrategy();

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

            %% --- EXECUTE SAFE TAB TRANSITION ---
            % If we made it here, the transition is approved.
            % We now trigger the specific render/update functions for the target tab.

            app.resetInteractionState();
            drawnow; pause(0.05);

            if targetTab == app.TabBillet
                if ~app.IsBilletUserModified
                    app.onAutoFitBillet();
                end
                if ~app.IsBilletPosUserModified
                    app.onAutoPositionModel();
                end
                app.syncBilletUI();
                app.refreshBilletPlots();

            elseif targetTab == app.TabMachine
                app.syncMachineUI();[ isValidMachF, pColF, tColF, msgLinesF ] = app.checkMachineState();
                app.MachineLeftPanel.BackgroundColor = pColF;
                app.TxtMachineStatus.Value = msgLinesF;
                app.TxtMachineStatus.FontColor = tColF;
                app.BtnMachineContinue.Enable = 'on';
                app.refreshMachinePlot();

            elseif targetTab == app.TabCutting[ isValidCutF, pColCF, tColCF, msgLinesCF ] = app.validateCuttingStrategy();
                app.CuttingLeftPanel.BackgroundColor = pColCF;
                app.TxtCuttingStatus.Value = msgLinesCF;
                app.TxtCuttingStatus.FontColor = tColCF;
                if isValidCutF, app.BtnCuttingContinue.Enable = 'on'; else, app.BtnCuttingContinue.Enable = 'off'; end
                app.updateCuttingPlots();
                app.onResetCuttingViewBillet();

            elseif isequal(targetTab, app.TabSimulation)
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

        function onContinue(app)
            % Purpose: Handles the "Continue ->" button clicks found at the bottom
            %          of the left-hand control panels. It programmatically advances
            %          the UI to the next logical tab, which triggers the Gatekeeper.

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

        function enterState0(app)
            % Purpose: Resets the app to "State 0" (Model loaded, but no planes/profiles).
            app.AppState = 0;

            app.clearPlanes();
            app.clearProfiles();
            app.clearProfiles2D();

            % Hard reset the kerf flag for new models
            app.KerfEnabled = false;
            app.clearKerfPaths();

            % Disable the Continue button visually
            if ~isempty(app.BtnContinue) && isgraphics(app.BtnContinue)
                app.BtnContinue.Enable          = 'off';
                app.BtnContinue.BackgroundColor =[0.3 0.3 0.3];
                app.BtnContinue.FontColor       =[0.8 0.8 0.8];
            end
        end

        function enterState1(app)
            % Purpose: Advances the app to "State 1" (Planes and Profiles are active).
            % WHY: Triggered when the user clicks "Generate Profiles".

            if isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch)
                return; % No model → nothing to do
            end

            app.AppState = 1;

            % Enable the Continue button visually
            if ~isempty(app.BtnContinue) && isgraphics(app.BtnContinue)
                app.BtnContinue.Enable          = 'on';
                app.BtnContinue.BackgroundColor =[0.1 0.6 0.1];
                app.BtnContinue.FontColor       =[1 1 1];
            end

            % Draw planes (which indirectly triggers profile computation)
            app.updatePlanes();
        end

        %% ===========================================================
        %% --- GROUP 3: TAB 0 - WELCOME & SETUP ---
        %% ===========================================================

        function onBrowseFreeCAD(app)
            % Purpose: Opens a file dialog for the user to locate the FreeCAD executable.
            % WHY: FreeCAD is required in the background to accurately mesh STEP files.

            [ file, path ] = uigetfile({'*.exe', 'Executables (*.exe)'}, 'Locate FreeCADCmd.exe', 'C:\Program Files\');
            if isequal(file, 0), return; end % User cancelled

            fullPath = fullfile(path, file);
            app.FreeCADExe = string(fullPath);
            app.FieldFreeCADPath.Value = app.FreeCADExe;

            % Save to user's MATLAB profile permanently so they only do this once
            setpref('HotWireSTEPApp', 'FreeCADPath', app.FreeCADExe);

            uialert(app.UIFigure, 'FreeCAD path saved successfully!', 'Setup Complete', 'Icon', 'success');
        end

        function onFreeCADPathEdited(app, src)
            % Purpose: Handles manual text entry for the FreeCAD path.
            app.FreeCADExe = string(src.Value);
            setpref('HotWireSTEPApp', 'FreeCADPath', app.FreeCADExe);
        end

        %% ===========================================================
        %% --- GROUP 4: TAB 2 - MODEL IMPORT & ORIENTATION ---
        %% ===========================================================
        % Note: onImportSTEP, onImportSTL, and plotMesh belong in this group
        % (provided in the first patch).

        %%                    - IMPORT STEP / STL -
        function onImportSTEP(app)
            % Purpose: Handles the selection and import of STEP files.
            %          Validates FreeCAD configuration, displays a progress dialog,
            %          and delegates the actual parsing to the helpers class.

            %% --- 1. FREECAD VALIDATION ---
            if ~isfile(app.FreeCADExe)
                uialert(app.UIFigure, 'FreeCADCmd.exe not found at the configured path! Please locate it on the Welcome Tab first.', 'FreeCAD Missing', 'Icon', 'error');
                app.TabGroup.SelectedTab = app.TabWelcome;
                return;
            end

            %% --- 2. FILE SELECTION ---
            [ file, path ] = uigetfile({'*.step;*.stp'},'Select STEP file');
            if isequal(file, 0), return; end

            d = uiprogressdlg(app.UIFigure, ...
                'Title','Loading STEP File...', ...
                'Message','Converting and loading model. Please wait...', ...
                'Indeterminate','on');

            %% --- 3. IMPORT & INITIALIZE ---
            try
                app.CurrentModelName = string(file);

                % Delegate STEP import to the helpers class
                [ V, F ] = CNCHotWire_GCodeGenerator_Helpers.importSTEP_FreeCAD(fullfile(path, file), app.FreeCADExe);

                if isempty(V)
                    close(d);
                    return;
                end

                app.ModelVerticesOriginal = V;

                % Reset rotation state
                app.RotAngles = [0 0 0];
                for i = 1:3
                    app.RotEdit(i).Value = 0;
                end

                % Reset plane offsets (will be updated from model extents)
                app.NumLeftOffset.Value  = 0;
                app.NumRightOffset.Value = 0;

                % Render the mesh
                app.plotMesh(V, F);

            catch ME
                close(d);
                rethrow(ME);
            end

            app.enterState0();
            close(d);
        end

        function onImportSTL(app)
            % Purpose: Handles the selection and import of STL files.
            %          Reads the mesh data directly and initializes the model state.

            %% --- 1. FILE SELECTION ---
            [ file, path ] = uigetfile({'*.stl'},'Select STL file');
            if isequal(file, 0), return; end

            d = uiprogressdlg(app.UIFigure, ...
                'Title','Loading STL File...', ...
                'Message','Reading mesh. Please wait...', ...
                'Indeterminate','on');

            %% --- 2. IMPORT & INITIALIZE ---
            try
                raw = stlread(fullfile(path, file));
                if isa(raw, "triangulation")
                    F = raw.ConnectivityList;
                    V = raw.Points;
                else
                    [ F, V ] = stlread(fullfile(path, file));
                end
                V = double(V);
                F = double(F);

                app.CurrentModelName      = string(file);
                app.ModelVerticesOriginal = V;

                % Reset rotation state
                app.RotAngles = [0 0 0];
                for i = 1:3
                    app.RotEdit(i).Value = 0;
                end

                % Reset plane offsets
                app.NumLeftOffset.Value  = 0;
                app.NumRightOffset.Value = 0;

                % Render the mesh
                app.plotMesh(V, F);

            catch ME
                close(d);
                rethrow(ME);
            end

            app.enterState0();
            close(d);
        end


        function onLoadExample(app)
            % Purpose: Opens a file dialog directly inside the bundled 'examples' folder to load a model.
            % WHY: Prevents the user from having to manually copy files out of the hidden AppData folder.

            appDir = fileparts(mfilename('fullpath'));

            % Resolve path (handles both source and compiled folder structures)
            if isfolder(fullfile(appDir, 'examples'))
                exPath = fullfile(appDir, 'examples');
            elseif isfolder(fullfile(appDir, '..', 'examples'))
                exPath = fullfile(appDir, '..', 'examples');
            else
                uialert(app.UIFigure, 'Examples folder not found in the installation directory.', 'Error');
                return;
            end

            % Open file dialog starting exactly in the examples folder
            %parserbug
            [ file, path ] = uigetfile({'*.step;*.stp;*.stl', 'CAD Models (*.step, *.stl)'}, 'Load Example Model', exPath);

            if isequal(file, 0), return; end % User cancelled

            fullPath = fullfile(path, file);

            %parserbug
            [ ~, ~, ext ] = fileparts(fullPath);

            % Route to the correct import logic based on file type
            if strcmpi(ext, '.step') || strcmpi(ext, '.stp')
                %% --- STEP IMPORT LOGIC ---
                if ~isfile(app.FreeCADExe)
                    uialert(app.UIFigure, 'FreeCADCmd.exe not found! Please configure it on the Welcome Tab to load STEP examples.', 'FreeCAD Missing', 'Icon', 'error');
                    app.TabGroup.SelectedTab = app.TabWelcome;
                    return;
                end

                d = uiprogressdlg(app.UIFigure, 'Title','Loading Example...', 'Message','Converting STEP. Please wait...', 'Indeterminate','on');
                try
                    app.CurrentModelName = string(file);

                    %parserbug
                    [ V, F ] = CNCHotWire_GCodeGenerator_Helpers.importSTEP_FreeCAD(fullPath, app.FreeCADExe);

                    if isempty(V), close(d); return; end

                    app.ModelVerticesOriginal = V;
                    app.RotAngles = [0 0 0];
                    for i = 1:3, app.RotEdit(i).Value = 0; end
                    app.NumLeftOffset.Value = 0; app.NumRightOffset.Value = 0;
                    app.plotMesh(V, F);
                catch ME
                    close(d); rethrow(ME);
                end
                app.enterState0();
                close(d);

            elseif strcmpi(ext, '.stl')
                %% --- STL IMPORT LOGIC ---
                d = uiprogressdlg(app.UIFigure, 'Title','Loading Example...', 'Message','Reading STL. Please wait...', 'Indeterminate','on');
                try
                    raw = stlread(fullPath);
                    if isa(raw, "triangulation")
                        F = raw.ConnectivityList; V = raw.Points;
                    else
                        %parserbug
                        [ F, V ] = stlread(fullPath);
                    end
                    V = double(V); F = double(F);

                    app.CurrentModelName = string(file);
                    app.ModelVerticesOriginal = V;
                    app.RotAngles = [0 0 0];
                    for i = 1:3, app.RotEdit(i).Value = 0; end
                    app.NumLeftOffset.Value = 0; app.NumRightOffset.Value = 0;
                    app.plotMesh(V, F);
                catch ME
                    close(d); rethrow(ME);
                end
                app.enterState0();
                close(d);
            end
        end

        function onTaperModeChanged(app)
            % Purpose: Handles switching between Straight (Prismatic) and Tapered cuts.
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
                    app.ChkDynamicFeed.Value = true; % Default to true
                end
            end

            if isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch)
                return;
            end

            app.updatePlanes();
        end

        %%                    - PLOTTING (MODEL TAB) -

        function plotMesh(app, V, F)
            % Purpose: Renders the imported 3D mesh in the Model tab's axes.
            % HOW: Initializes the default view, lighting, and bounding box.

            cla(app.AxModel);

            app.ModelPatch = patch(app.AxModel, ...
                'Vertices', V, 'Faces', F, ...
                'FaceColor',[0.7 0.7 0.8], ...
                'FaceAlpha', 0.6, ...
                'EdgeColor',[0.3 0.3 0.4], ...
                'EdgeAlpha', 0.5, ...
                'LineStyle', '-', ...
                'LineWidth', 0.6);

            if strlength(app.CurrentModelName) > 0
                app.FileLabel.Text = "Current File: " + app.CurrentModelName;
            else
                app.FileLabel.Text = "Current File: ---";
            end

            xlabel(app.AxModel, 'X (mm)', 'FontWeight', 'bold');
            ylabel(app.AxModel, 'Y (mm)', 'FontWeight', 'bold');
            zlabel(app.AxModel, 'Z (mm)', 'FontWeight', 'bold');

            grid(app.AxModel, 'on');
            view(app.AxModel, 3);

            delete(findall(app.AxModel, 'Type', 'light'));
            camlight(app.AxModel, 'headlight');
            lighting(app.AxModel, 'gouraud');

            % ONLY reset the manual lock on a brand new file import
            app.IsBilletUserModified = false;

            app.autoFitView();
            drawnow;
            app.captureHomeView();

            app.updateModelBoundsAndDefaultOffsets();
            app.updateBilletDefaultsFromMesh();

            app.BilletRefXMin = app.ModelXMin;
            app.BilletRefYMin = app.ModelYMin;
            app.BilletRefZMin = app.ModelZMin;

            app.IsMachineInit = false;
            app.IsCuttingInit = false;
            if isprop(app, 'FieldFilename') && isgraphics(app.FieldFilename)
                app.updatePostProcessUI();
            end
        end

        function autoFitView(app)
            % Purpose: Automatically scales and centers the 3D camera view.
            % WHY: Ensures the imported model fits perfectly in the window.
            % HOW: Calculates the bounding box, applies padding, locks the aspect
            %      ratio to 1:1:1, and lets MATLAB's native engine handle the camera.

            if isempty(app.ModelPatch) || ~isvalid(app.ModelPatch), return; end

            V      = app.ModelPatch.Vertices;

            %parserbug
            [ mins ] = min(V, [ ], 1);
            %parserbug
            [ maxs ] = max(V, [ ], 1);

            span   = max(maxs - mins);
            if span <= 0, span = 1; end

            pad = app.AutoFitPaddingFactor * span;

            % 1. Lock 1:1:1 aspect ratio so the model doesn't stretch
            daspect(app.AxModel, [1 1 1]);

            % 2. Apply padded limits
            xlim(app.AxModel, [mins(1)-pad, maxs(1)+pad]);
            ylim(app.AxModel, [mins(2)-pad, maxs(2)+pad]);
            zlim(app.AxModel, [mins(3)-pad, maxs(3)+pad]);

            % 3. Reset to standard 3D view and let MATLAB handle the camera math!
            view(app.AxModel, 3);

            app.AxModel.CameraPositionMode  = 'auto';
            app.AxModel.CameraTargetMode    = 'auto';
            app.AxModel.CameraUpVectorMode  = 'auto';
            app.AxModel.CameraViewAngleMode = 'auto';

            % 4. Refresh lighting
            delete(findall(app.AxModel, 'Type', 'light'));
            camlight(app.AxModel, 'headlight');
            lighting(app.AxModel, 'gouraud');

            drawnow limitrate;
        end

        function captureHomeView(app)
            % Purpose: Stores the current camera and axes limits as the "Home" view.
            if isempty(app.AxModel) || ~isvalid(app.AxModel), return; end
            ax = app.AxModel;
            app.DefaultXLim               = xlim(ax);
            app.DefaultYLim               = ylim(ax);
            app.DefaultZLim               = zlim(ax);
            app.DefaultDataAspectRatio    = ax.DataAspectRatio;
            app.DefaultPlotBoxAspectRatio = ax.PlotBoxAspectRatio;
            app.DefaultCameraPosition     = ax.CameraPosition;
            app.DefaultCameraTarget       = ax.CameraTarget;
            app.DefaultCameraUpVector     = ax.CameraUpVector;
            app.DefaultCameraViewAngle    = ax.CameraViewAngle;
        end

        function resetPlotView(app)
            % Purpose: Restores the 3D axes to perfectly fit the model.
            % WHY: Restoring hardcoded camera properties locks the camera into 'manual' mode,
            %      which breaks the 3D rotation tool. Calling autoFitView keeps it in 'auto'.

            app.autoFitView();
        end

        %%                    - ROTATION -
        function updateRotation(app, axisChar, newVal)
            % Purpose: Rotates the 3D model to a specific absolute angle.
            % WHY: Triggered when the user types a specific degree into the rotation edit fields.
            % HOW: Calculates the delta from the current angle, builds a transformation matrix,
            %      and applies it to the mesh vertices around their centroid.

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

            % Build rotation matrix (Z is inverted for UI intuition so + is clockwise)
            switch axisChar
                case 'X'
                    R = makehgtform('xrotate', deg2rad(delta));
                case 'Y'
                    R = makehgtform('yrotate', deg2rad(delta));
                case 'Z'
                    R = makehgtform('zrotate', deg2rad(-delta));
            end

            % Rotate mesh vertices about their centroid
            V = app.ModelPatch.Vertices;
            C = mean(V, 1);
            V = V - C;

            % Apply 4x4 transformation matrix
            V =[ V, ones(size(V,1),1) ] * R.';
            V = V(:, 1:3) + C;
            app.ModelPatch.Vertices = V;

            % Refocus view
            app.autoFitView();

            % Recompute model bounds and reset offsets so planes snap to the new extents
            app.updateModelBoundsAndDefaultOffsets(true);

            % Rotation defines a new "Home" position for the Billet tab
            app.BilletRefXMin = app.ModelXMin;
            app.BilletRefYMin = app.ModelYMin;
            app.BilletRefZMin = app.ModelZMin;
            app.BilletShift   = [0 0 0]; % Reset the UI offset counter

            app.updatePlanes();
        end

        function rotateModel(app, cmd)
            % Purpose: Increments/Decrements the model rotation by 90 degrees.
            % WHY: Triggered by the +/- 90 buttons for quick orthogonal alignment.

            if isempty(app.ModelPatch) || ~isvalid(app.ModelPatch)
                return
            end

            ax = cmd(1);
            d  = cmd(2);

            % 'p' = plus (+90), 'm' = minus (-90)
            theta = 90*(d=='p') - 90*(d=='m');

            % Build rotation matrix for the requested axis
            switch ax
                case 'X'
                    R   = makehgtform('xrotate', deg2rad(theta));
                    idx = 1;
                case 'Y'
                    R   = makehgtform('yrotate', deg2rad(theta));
                    idx = 2;
                case 'Z'
                    R   = makehgtform('zrotate', deg2rad(-theta));
                    idx = 3;
                otherwise
                    return;
            end

            % Update stored angle and edit field (keep within 0-360)
            app.RotAngles(idx)     = mod(app.RotAngles(idx) + theta, 360);
            app.RotEdit(idx).Value = app.RotAngles(idx);

            % Rotate mesh vertices about their centroid
            V = app.ModelPatch.Vertices;
            C = mean(V, 1);
            V = V - C;
            V =[ V, ones(size(V,1),1) ] * R.';
            V = V(:, 1:3) + C;
            app.ModelPatch.Vertices = V;

            % Update view and store as new "home" orientation
            app.autoFitView();
            app.captureHomeView();

            app.updateModelBoundsAndDefaultOffsets(true);

            % Rotation defines a new "Home" position for the Billet tab
            app.BilletRefXMin = app.ModelXMin;
            app.BilletRefYMin = app.ModelYMin;
            app.BilletRefZMin = app.ModelZMin;
            app.BilletShift   = [0 0 0];

            app.updatePlanes();
        end

        function resetOrientation(app)
            % Purpose: Restores the model to its original imported orientation.

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

            % Reset model bounds & plane offsets to defaults
            app.updateModelBoundsAndDefaultOffsets(true);

            app.BilletRefXMin = app.ModelXMin;
            app.BilletRefYMin = app.ModelYMin;
            app.BilletRefZMin = app.ModelZMin;
            app.BilletShift   = [0 0 0];

            app.updatePlanes();
        end

        %%                    - PLANES -

        function updateModelBoundsAndDefaultOffsets(app, resetOffsets)
            % Purpose: Calculates the physical bounding box of the model and updates the UI plane spinners.
            % WHY: The cutting planes are constrained to the physical width of the model.
            % HOW: Finds the min/max of the vertices. The UI displays '0' as the left face
            %      and 'Model Width' as the right face.

            if isempty(app.ModelPatch), return; end
            V = app.ModelPatch.Vertices;

            % Force SCALAR extraction for bounds
            [ mins ] = min(V, [], 1);
            [ maxs ] = max(V,[], 1);

            app.ModelXMin = mins(1); app.ModelXMax = maxs(1);
            app.ModelYMin = mins(2); app.ModelYMax = maxs(2);
            app.ModelZMin = mins(3); app.ModelZMax = maxs(3);

            % Calculate Model Width
            modelWidth = app.ModelXMax - app.ModelXMin;
            if modelWidth < 1, modelWidth = 1; end % Safety fallback

            % Update Limits (0 to Width)
            % User sees 0 as Left Face, Width as Right Face
            app.NumLeftOffset.Limits  = [0, modelWidth];
            app.NumRightOffset.Limits =[0, modelWidth];

            t = app.getTheme();

            if nargin < 2, resetOffsets = true; end

            if resetOffsets
                app.NumLeftOffset.Value  = 0;
                app.NumRightOffset.Value = modelWidth;

                if ~isempty(app.TxtModelStatus)
                    app.TxtModelStatus.Value = {'Model loaded.', sprintf('Size: %.1f x %.1f x %.1f mm', ...
                        modelWidth, app.ModelYMax-app.ModelYMin, app.ModelZMax-app.ModelZMin)};
                    app.TxtModelStatus.FontColor = t.statPassTxt;
                end
            else
                % Clamp values if the model was rotated and became narrower
                if app.NumLeftOffset.Value > modelWidth, app.NumLeftOffset.Value = modelWidth; end
                if app.NumRightOffset.Value > modelWidth, app.NumRightOffset.Value = modelWidth; end

                if ~isempty(app.TxtModelStatus)
                    app.TxtModelStatus.Value = {'Model re-oriented.', 'Check plane positions.'};
                    app.TxtModelStatus.FontColor = t.statWarnTxt;
                end
            end
        end

        function onPlaneOffsetChanged(app, src, ~)
            % Purpose: Callback for when the user manually adjusts the Left/Right plane spinners.
            % WHY: Updates the 3D planes and prevents the user from crossing them.

            if isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch)
                return
            end

            % --- Prevent planes from crossing ---
            if app.NumLeftOffset.Value > app.NumRightOffset.Value
                if src == app.NumLeftOffset
                    % User pushed the left plane past the right plane
                    app.NumLeftOffset.Value = app.NumRightOffset.Value;
                elseif src == app.NumRightOffset
                    % User pushed the right plane past the left plane
                    app.NumRightOffset.Value = app.NumLeftOffset.Value;
                end
            end

            % Moving the planes changes the extracted geometry, so kerf must be recalculated
            app.invalidateKerf();

            % Redraw planes (which indirectly calls computeProfiles and reapplies kerf)
            app.updatePlanes();
        end

        function resetPlanes(app)
            % Purpose: Snaps the cutting planes back to the absolute left and right faces of the model.

            if isempty(app.ModelPatch) || ~isvalid(app.ModelPatch)
                return
            end

            app.updateModelBoundsAndDefaultOffsets(true);
            app.updatePlanes();
        end

        function updatePlanes(app)
            % Purpose: Renders the semi-transparent red and green cutting planes in the 3D view.
            % HOW: Calculates a bounding box slightly larger than the model, creates patch objects
            %      at the specified X offsets, and then triggers profile extraction.

            app.clearPlanes();
            if app.AppState == 0 || isempty(app.ModelPatch), return; end

            % 1. Setup Theme and Geometry
            t = app.getTheme();
            V = app.ModelPatch.Vertices;

            [ mins ] = min(V, [], 1);
            [ maxs ] = max(V,[], 1);

            span = max(maxs - mins);
            if span <= 0, span = 1; end
            pad  = app.PlanePaddingFactor * span;

            % Create a Y-Z bounding box for the planes
            yLims =[mins(2)-pad; maxs(2)+pad; maxs(2)+pad; mins(2)-pad];
            zLims =[mins(3)-pad; mins(3)-pad; maxs(3)+pad; maxs(3)+pad];

            % Calculate absolute X positions based on UI offsets
            xL = app.ModelXMin(1) + app.NumLeftOffset.Value;
            xR = app.ModelXMin(1) + app.NumRightOffset.Value;

            % 2. Math for Label Positions (Keep labels near the top corners)
            tY_L = (maxs(2)+pad) - 0.02*((maxs(2)+pad) - (mins(2)-pad));
            tZ_L = (maxs(3)+pad) - 0.50*(maxs(3) - mins(3));
            tY_R = (mins(2)-pad) + 0.02*((maxs(2)+pad) - (mins(2)-pad));
            tZ_R = (maxs(3)+pad) - 0.10*(maxs(3) - mins(3));

            % 3. Draw Left Plane (Red)
            app.LeftPlanePatch = patch(app.AxModel, 'XData',[xL;xL;xL;xL], 'YData', yLims, 'ZData', zLims, ...
                'FaceColor', t.planeRed, 'FaceAlpha', 0.15, 'EdgeColor', t.planeRed, 'LineStyle','--', 'HandleVisibility','off');
            app.LeftPlaneText = text(app.AxModel, xL, tY_L, tZ_L, {'LEFT','PLANE'}, ...
                'HorizontalAlignment','left', 'VerticalAlignment', 'top', 'Color', t.planeRedTxt, 'FontWeight','bold');

            % 4. Draw Right Plane (Green)
            app.RightPlanePatch = patch(app.AxModel, 'XData',[xR;xR;xR;xR], 'YData', yLims, 'ZData', zLims, ...
                'FaceColor', t.planeGreen, 'FaceAlpha', 0.15, 'EdgeColor', t.planeGreen, 'LineStyle','--', 'HandleVisibility','off');
            app.RightPlaneText = text(app.AxModel, xR, tY_R, tZ_R, {'RIGHT','PLANE '}, ...
                'HorizontalAlignment','right', 'VerticalAlignment', 'top', 'Color', t.planeGreenTxt, 'FontWeight','bold');

            % 5. Maintain Layers and Compute
            if isgraphics(app.LeftPlaneText), uistack(app.LeftPlaneText, 'top'); end
            if isgraphics(app.RightPlaneText), uistack(app.RightPlaneText, 'top'); end

            % Now that planes are visually updated, extract the intersection profiles
            app.computeProfiles();
        end

        %%                    - PROFILE GENERATION (TAB 2 ACTIONS) -

        function onGenerateProfiles(app)
            % Purpose: Transitions the app from State 0 (Model Only) to State 1 (Planes & Profiles Active).
            % WHY: Triggered by the "Generate Profiles" button on the Model tab.

            if isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch)
                return;
            end

            if app.AppState == 0
                app.enterState1();
            else
                % If already in State 1, just force a refresh
                app.updatePlanes();
            end
        end

        %% ===========================================================
        %% --- GROUP 5: TAB 3 - PROFILES & KERF ---
        %% ===========================================================

        function computeProfiles(app)
            % Purpose: Slices the 3D mesh at the Left and Right planes to extract 2D profiles.
            % WHY: This is the core CAM operation converting a 3D CAD model into 2D wire paths.
            % HOW: Uses the helper class to intersect the mesh, build continuous loops,
            %      resample them to a specific tolerance, and store the 3D coordinates.

            if app.AppState == 0 || isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch), return; end

            %% --- 1. SETUP & INITIALIZATION ---
            t = app.getTheme();
            isTaper = strcmp(app.TaperToggle.Value, 'Tapered');

            app.clearProfiles();
            app.clearProfiles2D();
            app.SelectedStartIdxL = 1;
            app.SelectedStartIdxR = 1;

            V = app.ModelPatch.Vertices;
            F = app.ModelPatch.Faces;
            spanX = max(V(:,1)) - min(V(:,1));
            epsX = 1e-6 * max(spanX, 1); % Tiny offset to prevent coplanar math errors

            xLeft  = app.ModelXMin + app.NumLeftOffset.Value;
            xRight = app.ModelXMin + app.NumRightOffset.Value;

            %% --- 2. LEFT PROFILE EXTRACTION ---
            meshL = cell(1,3);
            [ meshL{1}, meshL{2}, meshL{3} ] = CNCHotWire_GCodeGenerator_Helpers.sliceMeshAtX(V, F, xLeft + epsX);
            xsL = meshL{1}; ysL = meshL{2}; zsL = meshL{3};

            if ~isempty(ysL) && any(~isnan(ysL))
                app.LeftProfileRawYZ =[ysL(:), zsL(:)];
            end

            loopL = cell(1,2);
            [ loopL{1}, loopL{2} ] = CNCHotWire_GCodeGenerator_Helpers.buildMainProfileLoop(xsL, ysL, zsL);
            yLoopL = loopL{1}; zLoopL = loopL{2};

            %% --- 3. RIGHT PROFILE EXTRACTION ---
            yLoopR = []; zLoopR =[];
            if isTaper
                meshR = cell(1,3);
                [ meshR{1}, meshR{2}, meshR{3} ] = CNCHotWire_GCodeGenerator_Helpers.sliceMeshAtX(V, F, xRight - epsX);
                xsR = meshR{1}; ysR = meshR{2}; zsR = meshR{3};

                if ~isempty(ysR) && any(~isnan(ysR))
                    app.RightProfileRawYZ = [ysR(:), zsR(:)];
                end

                loopR = cell(1,2);
                [ loopR{1}, loopR{2} ] = CNCHotWire_GCodeGenerator_Helpers.buildMainProfileLoop(xsR, ysR, zsR);
                yLoopR = loopR{1}; zLoopR = loopR{2};
            else
                % Prismatic cut: Right profile is identical to Left
                yLoopR = yLoopL; zLoopR = zLoopL;
                app.RightProfileRawYZ = app.LeftProfileRawYZ;
            end

            %% --- 4. RESAMPLING ---
            % Resample the raw loops based on the user's tolerance setting
            if ~isempty(yLoopL) && ~isempty(yLoopR)
                resmp = cell(1,4);
                [ resmp{1}, resmp{2}, resmp{3}, resmp{4} ] = CNCHotWire_GCodeGenerator_Helpers.resampleProfilesSynced(...
                    yLoopL, zLoopL, yLoopR, zLoopR, app.ProfileTolerance);
                yLoopL = resmp{1}; zLoopL = resmp{2}; yLoopR = resmp{3}; zLoopR = resmp{4};
            end

            %% --- 5. STORAGE & 3D PLOTTING ---
            if ~isempty(yLoopL)
                xVecL = xLeft * ones(numel(yLoopL), 1);
                app.LeftProfileLine3D = plot3(app.AxModel, xVecL, yLoopL, zLoopL, 'Color', t.planeRed, 'LineWidth', 1.4);
                app.LeftProfilePoints = [xVecL, yLoopL, zLoopL];
            else
                app.LeftProfilePoints =[];
            end

            if ~isempty(yLoopR)
                xVecR = xRight * ones(numel(yLoopR), 1);
                app.RightProfileLine3D = plot3(app.AxModel, xVecR, yLoopR, zLoopR, 'Color', t.planeGreen, 'LineWidth', 1.4);
                app.RightProfilePoints =[xVecR, yLoopR, zLoopR];
            else
                app.RightProfilePoints =[];
            end

            %% --- 6. UI UPDATES ---
            nL = size(app.LeftProfilePoints, 1);
            nR = size(app.RightProfilePoints, 1);
            app.updateProfilePointCountLabel(nL, nR);

            % Draw the 2D plots on the Profiles tab
            app.updateProfiles2D(yLoopL, zLoopL, yLoopR, zLoopR, xLeft, xRight);

            if ~isempty(yLoopL)
                app.TxtProfileStatus.Value = {
                    sprintf('Profiles extracted.');
                    sprintf('Left: %d pts', numel(yLoopL));
                    sprintf('Right: %d pts', numel(yLoopR));
                    'Ready to apply Kerf.'
                    };
                app.TxtProfileStatus.FontColor = t.labelCol;
            else
                app.TxtProfileStatus.Value = {'Extraction failed.', 'Check model position.'};
                app.TxtProfileStatus.FontColor = t.statErrTxt;
            end

            drawnow limitrate nocallbacks;
        end

        function updateProfiles2D(app, yL, zL, yR, zR, xLeft, xRight)
            % Purpose: Draws 2D Y-Z profiles on the Profiles tab with shared scaling.
            % HOW: Calculates shared bounding boxes, applies kerf offsets if enabled,
            %      synchronizes point counts, and renders the lines.

            if isempty(app.AxLeftProfile) || ~isgraphics(app.AxLeftProfile) || isempty(app.AxRightProfile) || ~isgraphics(app.AxRightProfile)
                return;
            end

            if isempty(yL) && isempty(yR)
                return;
            end

            %% --- 1. CALCULATE SHARED AXES LIMITS ---
            yAll = [yL(:); yR(:)];
            zAll =[zL(:); zR(:)];
            if isempty(yAll) || isempty(zAll)
                return;
            end

            yMin = min(yAll); yMax = max(yAll);
            zMin = min(zAll); zMax = max(zAll);
            dy = max(yMax - yMin, 1);
            dz = max(zMax - zMin, 1);

            % SMART FIT LOGIC: Prevent wide/short profiles (like airfoils) from
            % squishing into a tiny vertical strip. We enforce a minimum Z-span
            % (e.g., 25% of the Y-span) to utilize the UI container's vertical space.
            min_dz = dy * 0.25;
            if dz < min_dz
                dz_pad_extra = (min_dz - dz) / 2.0;
                zMin = zMin - dz_pad_extra;
                zMax = zMax + dz_pad_extra;
                dz = min_dz;
            end

            % Symmetric 5% padding.
            padY = 0.05 * dy;
            padZ = 0.10 * dz;

            yLim = [ yMin - padY, yMax + padY ];
            zLim = [ zMin - padZ, zMax + padZ ];

            t = app.getTheme();
            app.clearProfiles2D();

            %% --- 2. DETERMINE FINAL PROFILES (Raw or Kerfed) ---
            final_yL = yL; final_zL = zL;
            final_yR = yR; final_zR = zR;

            doKerfL = app.KerfEnabled && ~isempty(yL) && app.KerfLeftValue ~= 0;
            doKerfR = app.KerfEnabled && ~isempty(yR) && app.KerfRightValue ~= 0;

            if doKerfL
                [ final_yL, final_zL ] = CNCHotWire_GCodeGenerator_Helpers.offsetProfileLoop(yL, zL, app.KerfLeftValue, app.ProfileTolerance);
            end

            if doKerfR
                [ final_yR, final_zR ] = CNCHotWire_GCodeGenerator_Helpers.offsetProfileLoop(yR, zR, app.KerfRightValue, app.ProfileTolerance);
            end

            %% --- 3. SYNC POINT COUNTS UNIVERSALLY ---
            % Always sync the final shapes so the UI exactly matches the Simulation.
            if ~isempty(final_yL) && ~isempty(final_yR)
                [ final_yL, final_zL, final_yR, final_zR ] = CNCHotWire_GCodeGenerator_Helpers.syncPointCounts(final_yL, final_zL, final_yR, final_zR);
            end

            nLk = numel(final_yL);
            nRk = numel(final_yR);

            %% --- 4. DRAW PLOTS ---
            % LEFT TOWER
            hold(app.AxLeftProfile,'on');
            if ~isempty(app.LeftProfileRawYZ)
                rawL = app.LeftProfileRawYZ;
                % Thick dotted line sits visibly behind the extracted profile
                app.LeftProfile2DMeshLine = plot(app.AxLeftProfile, rawL(:,1), rawL(:,2), 'Color', t.rawMeshCol, 'LineStyle',':', 'LineWidth', 1.8);
            end
            if ~isempty(yL)
                % Thinner line plotted AFTER the mesh so it layers on top
                app.LeftProfile2DLine = plot(app.AxLeftProfile, yL, zL, 'Color', t.planeRed, 'LineWidth', 0.4, 'linestyle','-');
            end
            if doKerfL && ~isempty(final_yL)
                app.LeftKerf2DLine = plot(app.AxLeftProfile, final_yL, final_zL, 'Color', t.wireKerf, 'LineWidth', 0.75);
            end
            hold(app.AxLeftProfile,'off');

            % RIGHT TOWER
            hold(app.AxRightProfile,'on');
            if ~isempty(app.RightProfileRawYZ)
                rawR = app.RightProfileRawYZ;
                app.RightProfile2DMeshLine = plot(app.AxRightProfile, rawR(:,1), rawR(:,2), 'Color', t.rawMeshCol, 'LineStyle',':', 'LineWidth', 1.8);
            end
            if ~isempty(yR)
                app.RightProfile2DLine = plot(app.AxRightProfile, yR, zR, 'Color', t.planeGreen, 'LineWidth', 0.4, 'linestyle','-');
            end
            if doKerfR && ~isempty(final_yR)
                app.RightKerf2DLine = plot(app.AxRightProfile, final_yR, final_zR, 'Color', t.wireKerf, 'LineWidth', 0.75);
            end
            hold(app.AxRightProfile,'off');

            %% --- 5. UPDATE LABELS & LEGENDS ---
            if app.KerfEnabled && ~isempty(app.KerfPointCountLabel) && all(isgraphics(app.KerfPointCountLabel))
                app.KerfPointCountLabel.Text = sprintf('Kerf Compensated Point Count (L/R): %d / %d', nLk, nRk);
            end

            % Left Legend
            hL = gobjects(0); txtL = {};
            if isgraphics(app.LeftProfile2DMeshLine), hL(end+1)=app.LeftProfile2DMeshLine; txtL{end+1}='Model mesh slice'; end
            if isgraphics(app.LeftProfile2DLine), hL(end+1)=app.LeftProfile2DLine; txtL{end+1}='Extracted profile'; end
            if isgraphics(app.LeftKerf2DLine), hL(end+1)=app.LeftKerf2DLine; txtL{end+1}='Kerf path'; end
            if ~isempty(hL), l=legend(app.AxLeftProfile, hL, txtL, 'Location','northeast'); l.Box='off'; l.TextColor = t.labelCol; end

            % Right Legend
            hR = gobjects(0); txtR = {};
            if isgraphics(app.RightProfile2DMeshLine), hR(end+1)=app.RightProfile2DMeshLine; txtR{end+1}='Model mesh slice'; end
            if isgraphics(app.RightProfile2DLine), hR(end+1)=app.RightProfile2DLine; txtR{end+1}='Extracted profile'; end
            if isgraphics(app.RightKerf2DLine), hR(end+1)=app.RightKerf2DLine; txtR{end+1}='Kerf path'; end
            if ~isempty(hR), l=legend(app.AxRightProfile, hR, txtR, 'Location','northeast'); l.Box='off'; l.TextColor = t.labelCol; end

            %% --- 6. FORMAT AXES ---
            if ~app.ProfileAxesLocked
                xlim(app.AxLeftProfile, yLim); ylim(app.AxLeftProfile, zLim);
                xlim(app.AxRightProfile, yLim); ylim(app.AxRightProfile, zLim);
            end

            daspect(app.AxLeftProfile, [1 1 1]);
            daspect(app.AxRightProfile,[1 1 1]);

            title(app.AxLeftProfile,  sprintf('Left Profile  (X offset = %.2f mm)', xLeft), 'Color', t.labelCol);
            title(app.AxRightProfile, sprintf('Right Profile (X offset = %.2f mm)', xRight), 'Color', t.labelCol);

            xlabel(app.AxLeftProfile, 'Y (mm)', 'Color', t.labelCol, 'FontWeight', 'bold');
            ylabel(app.AxLeftProfile, 'Z (mm)', 'Color', t.labelCol, 'FontWeight', 'bold');
            xlabel(app.AxRightProfile, 'Y (mm)', 'Color', t.labelCol, 'FontWeight', 'bold');
            ylabel(app.AxRightProfile, 'Z (mm)', 'Color', t.labelCol, 'FontWeight', 'bold');

            grid(app.AxLeftProfile,'on');
            grid(app.AxRightProfile,'on');

            app.AxLeftProfile.XColor = t.labelCol; app.AxLeftProfile.YColor = t.labelCol;
            app.AxRightProfile.XColor = t.labelCol; app.AxRightProfile.YColor = t.labelCol;
        end

        function resetProfilesView(app)
            % Purpose: Resets Profiles tab axes limits to fit current profiles.
            %          Uses stored points so it does not trigger a full recompute.

            if isempty(app.AxLeftProfile) || ~isgraphics(app.AxLeftProfile) || isempty(app.AxRightProfile) || ~isgraphics(app.AxRightProfile)
                return;
            end

            yL = []; zL =[];
            yR = []; zR =[];
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

            % Force a full relimit of axes by unlocking and calling the update function
            app.ProfileAxesLocked = false;
            app.updateProfiles2D(yL, zL, yR, zR, xLeft, xRight);
        end

        function updateProfilePointCountLabel(app, nLeft, nRight, capLeft, capRight)
            % Purpose: Updates the read-only "Points (L/R)" label in the Profiles tab.

            if nargin < 2, nLeft  = 0; end
            if nargin < 3, nRight = 0; end
            if nargin < 4, capLeft  = false; end
            if nargin < 5, capRight = false; end

            if isempty(app.ProfilePointCountLabel) || ~isgraphics(app.ProfilePointCountLabel)
                return;
            end

            if nLeft <= 0 && nRight <= 0
                txt = 'Extracted Profile Point Count (L/R): -- / --';
            else
                txt = sprintf('Extracted Profile Point Count (L/R): %d / %d', nLeft, nRight);
            end

            if capLeft || capRight
                txt = [txt '  (max points reached)'];
                warning('ProfileSampler:PointCapHit', 'Profile point cap reached; further reductions in tolerance will not add detail.');
            end

            app.ProfilePointCountLabel.Text = txt;
        end

        %%                    - KERF & TOLERANCE CALLBACKS -

        function onProfileToleranceChanged(app, src)
            % Purpose: Updates the resampling tolerance and triggers a recompute.
            val = src.Value;
            if ~isfinite(val) || val <= 0
                src.Value = app.ProfileTolerance;
                return;
            end

            app.ProfileTolerance = val;
            app.IsCuttingInit = false;

            if app.AppState == 1 && ~isempty(app.ModelPatch) && isgraphics(app.ModelPatch)
                app.ProfileAxesLocked = true;
                app.updatePlanes();
                app.ProfileAxesLocked = false;
            end
        end

        function onResetProfileTolerance(app)
            % Purpose: Resets tolerance to default and triggers a recompute.
            defaultTol = CNCHotWire_GCodeGenerator.DefaultProfileTolerance;
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

        function invalidateKerf(app)
            % Purpose: Central reset for Kerf logic.
            % WHY: Called whenever the model is rotated, planes are moved, or
            %      taper mode changes, as these actions invalidate the current kerf paths.

            app.KerfEnabled = false;
            app.clearKerfPaths();

            % Mute the Continue button visually
            if ~isempty(app.BtnProfilesContinue) && isgraphics(app.BtnProfilesContinue)
                app.BtnProfilesContinue.Enable = 'off';
                app.BtnProfilesContinue.BackgroundColor =[0.3 0.3 0.3];
                app.BtnProfilesContinue.FontColor       =[0.8 0.8 0.8];
            end
        end

        function onKerfModeChanged(app, src)
            % Purpose: Toggles between Coupled (identical) and Independent kerf values.
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
            % Purpose: Updates Left Kerf value. If coupled, mirrors to Right Kerf.
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
            % Purpose: Updates Right Kerf value. If coupled, mirrors to Left Kerf.
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

        function onResetKerf(app)
            % Purpose: Resets kerf values to default and re-applies.
            defaultK = CNCHotWire_GCodeGenerator.DefaultKerf;

            app.KerfLeftValue = defaultK;
            app.KerfRightValue = defaultK;
            app.KerfValue = defaultK;

            if isgraphics(app.KerfLeftSpinner)
                app.KerfLeftSpinner.Value = defaultK;
            end
            if isgraphics(app.KerfRightSpinner)
                app.KerfRightSpinner.Value = defaultK;
            end

            app.IsCuttingInit = false;
            app.ProfileAxesLocked = true;
            app.onApplyKerf();
            app.ProfileAxesLocked = false;
        end

        function onApplyKerf(app)
            % Purpose: Applies the current kerf offset values to the extracted profiles.
            % WHY: Triggered by the "Apply Kerf" button. Unlocks the Continue button.

            if isempty(app.LeftProfilePoints) && isempty(app.RightProfilePoints)
                return;
            end

            app.KerfEnabled = true;

            app.BtnProfilesContinue.Enable = 'on';
            app.BtnProfilesContinue.BackgroundColor =[ 0.1, 0.6, 0.1 ];
            app.BtnProfilesContinue.FontColor       = [ 1, 1, 1 ];

            yL = zeros(0,1); zL = zeros(0,1); xLeft  = 0;
            yR = zeros(0,1); zR = zeros(0,1); xRight = 0;

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

        %%                    - KERF MATH HELPERS -

        function [ yL, zL, yR, zR ] = getSyncedKerfProfiles(app)
            % Purpose: Centralized Kerf & Sync logic to guarantee exact 1:1 topology.
            % WHY: Downstream tabs (Cutting, Sim, Post) rely on this function to get
            %      the absolute "Truth Data" for the toolpaths.

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
                    [ yL, zL ] = CNCHotWire_GCodeGenerator_Helpers.offsetProfileLoop(yL, zL, app.KerfLeftValue, app.ProfileTolerance);
                end
                if app.KerfRightValue ~= 0
                    [ yR, zR ] = CNCHotWire_GCodeGenerator_Helpers.offsetProfileLoop(yR, zR, app.KerfRightValue, app.ProfileTolerance);
                end
            end

            % ALWAYS re-align start points before syncing!
            % This prevents twist when Kerf is 0, ensuring both profiles
            % are anchored to the exact front face before parameter blending.
            [ yL, zL ] = CNCHotWire_GCodeGenerator_Helpers.reorderLoopByMinY(yL, zL);
            [ yR, zR ] = CNCHotWire_GCodeGenerator_Helpers.reorderLoopByMinY(yR, zR);

            [ yL, zL, yR, zR ] = CNCHotWire_GCodeGenerator_Helpers.syncPointCounts(yL, zL, yR, zR);
        end

        function[ yOut, zOut ] = applyMods(~, yIn, zIn, offY, offZ, startIdx, isCCW)
            % Purpose: Applies machine offsets, user start index, and direction to a synced array.
            % WHY: Used by the Cutting Tab and Simulation to transform the raw profiles
            %      into the final machine-ready toolpath.

            if isempty(yIn)
                yOut=[]; zOut=[]; return;
            end

            yOut = yIn + offY;
            zOut = zIn + offZ;

            if numel(yOut) > 2
                % Clean up duplicate end point before shifting
                if abs(yOut(1)-yOut(end)) < 1e-6 && abs(zOut(1)-zOut(end)) < 1e-6
                    yOut(end) = [ ];
                    zOut(end) = [ ];
                end

                N = numel(yOut);
                idx = max(1, min(startIdx, N));
                yOut = circshift(yOut, -(idx - 1));
                zOut = circshift(zOut, -(idx - 1));

                if isCCW
                    yOut(2:end) = flipud(yOut(2:end));
                    zOut(2:end) = flipud(zOut(2:end));
                end

                % Force Loop Closure
                yOut(end+1) = yOut(1);
                zOut(end+1) = zOut(1);
            end
        end

        %% ===========================================================
        %% --- GROUP 6: TAB 4 - BILLET CONFIGURATION ---
        %% ===========================================================

        function updateBilletDefaultsFromMesh(app)
            % Purpose: Initializes the billet size and position when a new model is loaded.
            % WHY: Gives the user a sensible starting point rather than a 0x0x0 block.
            if isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch)
                return;
            end
            app.onAutoFitBillet();
            app.onAutoPositionModel();
        end

        function isValid = syncBilletUI(app)
            % Purpose: Validates the model's position within the billet and updates UI fields/colors.
            % WHY: Ensures the user hasn't positioned the model outside the stock material,
            %      and warns them if they are wasting foam or too close to the edge.
            % HOW: Calculates the bounding box of the profiles (or mesh), compares it against
            %      the billet dimensions, and applies traffic-light colors to the UI panel.

            if isempty(app.BilletSizeEdits) || isempty(app.ModelPatch)
                isValid = false;
                return;
            end

            if ~isempty(app.LeftProfilePoints) && ~isempty(app.RightProfilePoints)
                P = [ app.LeftProfilePoints; app.RightProfilePoints ];
            else
                P = app.ModelPatch.Vertices;
            end


            [ localMins ] = min(P,[], 1);
            [ localMaxs ] = max(P,[], 1);

            xL = app.ModelXMin + app.NumLeftOffset.Value;
            xR = app.ModelXMin + app.NumRightOffset.Value;

            mMin =[ min(xL, xR), localMins(2), localMins(3) ];
            mMax =[ max(xL, xR), localMaxs(2), localMaxs(3) ];
            mDim = mMax - mMin;

            workMin = app.BilletShift + mMin;
            workMax = workMin + mDim;
            bSize = app.BilletSize;

            % Update UI Edit Fields
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

            %% --- SAFETY CHECKS ---
            % 1. CRITICAL: Outside Bounds (Red)
            isOutside = any(gapNeg < -tol) || any(gapPos < -tol);

            % 2. WARNING: Too Close (Amber) - Only for Y and Z (X=0 is allowed)
            isTooCloseYZ = any(gapNeg(2:3) < buf - 1e-4) || any(gapPos(2:3) < buf - 1e-4);

            % 3. WARNING: Floating (Amber) - Both sides > buf (Y and Z)
            isFloatingY = (gapNeg(2) > buf + 1e-4) && (gapPos(2) > buf + 1e-4);
            isFloatingZ = (gapNeg(3) > buf + 1e-4) && (gapPos(3) > buf + 1e-4);

            % 4. WARNING: Foam Waste (Amber)
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
            % Purpose: Switches the 4-way plot to focus tightly on the model.
            app.BilletViewMode = "Model";
            app.refreshBilletPlots();
        end

        function onResetBilletViewBillet(app)
            % Purpose: Switches the 4-way plot to show the entire billet.
            app.BilletViewMode = "Billet";
            app.refreshBilletPlots();
        end

        function onAutoFitBillet(app)
            % Purpose: Automatically sizes the billet to perfectly wrap the model plus a safety buffer.
            if isempty(app.ModelPatch)
                return;
            end

            if ~isempty(app.LeftProfilePoints) && ~isempty(app.RightProfilePoints)
                P = [ app.LeftProfilePoints; app.RightProfilePoints ];
            else
                P = app.ModelPatch.Vertices;
            end

            [ localMins ] = min(P, [], 1);
            [ localMaxs ] = max(P,[], 1);

            xL = app.ModelXMin + app.NumLeftOffset.Value;
            xR = app.ModelXMin + app.NumRightOffset.Value;

            buf = app.ModelEdgeWarningBuffer;
            tinyBuf = app.ModelXPlacementBuffer;

            bSizeX = abs(xR - xL) + (2.0 * tinyBuf);
            bSizeY = ceil((localMaxs(2) - localMins(2)) + (2.0 * buf));
            bSizeZ = ceil((localMaxs(3) - localMins(3)) + (2.0 * buf));

            app.BilletSize =[ bSizeX, bSizeY, bSizeZ ];
            app.IsBilletUserModified = false; % Unlock Size auto-calculation

            app.IsMachineInit = false;
            app.IsCuttingInit = false;

            % If position isn't locked, auto-position it inside the new size!
            if ~app.IsBilletPosUserModified
                app.onAutoPositionModel();
            else
                app.syncBilletUI();
                app.refreshBilletPlots();
            end
        end

        function onAutoPositionModel(app)
            % Purpose: Automatically shifts the model to sit safely inside the billet.
            if isempty(app.ModelPatch)
                return;
            end

            if ~isempty(app.LeftProfilePoints) && ~isempty(app.RightProfilePoints)
                P =[ app.LeftProfilePoints; app.RightProfilePoints ];
            else
                P = app.ModelPatch.Vertices;
            end

            [ localMins ] = min(P,[], 1);
            [ localMaxs ] = max(P,[], 1);

            xL = app.ModelXMin + app.NumLeftOffset.Value;
            xR = app.ModelXMin + app.NumRightOffset.Value;

            planeMinX = min(xL, xR);
            tinyBuf = app.ModelXPlacementBuffer;

            oldShift = app.BilletShift;

            app.BilletShift(1) = tinyBuf - planeMinX;
            app.BilletShift(2) = app.ModelEdgeWarningBuffer - localMins(2);
            app.BilletShift(3) = app.BilletSize(3) - app.ModelEdgeWarningBuffer - localMaxs(3);

            shiftDelta = app.BilletShift - oldShift;

            % Keep existing entry and link points aligned with the shifted geometry.
            app.shiftEntryPoints(shiftDelta(2), shiftDelta(3));

            app.IsBilletPosUserModified = false; % Position remains automatically controlled

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
            % Purpose: Restores the model to its unshifted CAD-derived position.
            if isempty(app.ModelPatch)
                return;
            end

            oldShift = app.BilletShift;
            app.BilletShift = [ 0 0 0 ];

            % Keep existing entry and link points aligned with the shifted geometry.
            shiftDelta = app.BilletShift - oldShift;
            app.shiftEntryPoints(shiftDelta(2), shiftDelta(3));

            app.IsCuttingInit = false;
            app.IsBilletPosUserModified = true; % Retain the deliberate zero-shift position

            app.syncBilletUI();
            app.refreshBilletPlots();
        end

        function onBilletSizeStep(app, axisIdx, direction)
            % Purpose: Increments or decrements the billet size via the +/- buttons.
            delta = direction * app.BilletSizeStep;
            app.BilletSize(axisIdx) = max(0, app.BilletSize(axisIdx) + delta);

            app.IsCuttingInit = false;
            app.IsBilletUserModified = true;

            % If position isn't locked, auto-position it inside the new size!
            if ~app.IsBilletPosUserModified
                app.onAutoPositionModel();
            else
                app.syncBilletUI();
                app.refreshBilletPlots();
            end
        end

        function onBilletSizeEdited(app, axisIdx, src)
            % Purpose: Handles manual text entry for the billet size.
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

            % If position isn't locked, auto-position it inside the new size!
            if ~app.IsBilletPosUserModified
                app.onAutoPositionModel();
            else
                app.syncBilletUI();
                app.refreshBilletPlots();
            end
        end

        function onBilletOffsetEdited(app, axisIdx, whichField, src)
            % Purpose: Handles manual text entry for the model position gaps/shifts.
            val = src.Value;

            if ~isempty(app.LeftProfilePoints) && ~isempty(app.RightProfilePoints)
                P =[ app.LeftProfilePoints; app.RightProfilePoints ];
            else
                if isempty(app.ModelPatch), return; end
                P = app.ModelPatch.Vertices;
            end

            [ localMins ] = min(P, [], 1);
            [ localMaxs ] = max(P,[], 1);

            xL = app.ModelXMin + app.NumLeftOffset.Value;
            xR = app.ModelXMin + app.NumRightOffset.Value;

            mMin =[ min(xL,xR), localMins(2), localMins(3) ];
            mMax =[ max(xL,xR), localMaxs(2), localMaxs(3) ];

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
            % Purpose: Helper to shift the model and update dependent entry points.
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
            % Purpose: Handles the +/- buttons for shifting the model position.
            app.moveModelInSpace(axisIdx, delta);
            app.IsBilletPosUserModified = true; % Lock the position, but not the size
        end

        function refreshBilletPlots(app)
            % Purpose: Updates the 4-way split view on the Billet tab.
            % HOW: Iterates over the 4 axes (Top, Front, Right, Iso), drawing the
            %      model, billet bounding box, and extracted profiles.

            if isempty(app.ModelPatch)
                return;
            end

            V     = app.ModelPatch.Vertices;
            F     = app.ModelPatch.Faces;
            bSize = app.BilletSize;
            shift = app.BilletShift;

            t = app.getTheme(); % Master Palette

            V_shifted = V + shift;

            if app.BilletViewMode == "Model"
                [ allMin ] = min(V_shifted,[], 1);
                [ allMax ] = max(V_shifted,[], 1);
            else
                allMin = [ 0, 0, 0 ];
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
            dims = {[ 1 2 ], [ 1 3 ], [ 2 3 ], [ 1 2 3 ]};
            labs = {{'X (mm)','Y (mm)'}; {'X (mm)','Z (mm)'}; {'Y (mm)','Z (mm)'}; {'X','Y','Z'}};

            for i = 1:4
                ax = axs{i};
                d = dims{i};

                if isempty(ax) || ~isgraphics(ax), continue; end

                cla(ax);
                hold(ax,'on');

                if i < 4
                    % --- 2D ORTHOGRAPHIC VIEWS ---
                    % 1. Draw Model
                    patch(ax, 'Vertices', V_shifted(:,d), 'Faces', F, ...
                        'FaceColor', t.modelColor, 'EdgeColor', 'none', 'FaceAlpha', t.modelAlpha);

                    % 2. Draw Billet Outline FIRST (so it sits behind the profiles)
                    bx =[ 0, bSize(d(1)), bSize(d(1)), 0, 0 ];
                    by =[ 0, 0, bSize(d(2)), bSize(d(2)), 0 ];
                    plot(ax, bx, by, 'Color', t.billetLine, 'LineStyle', '-', 'LineWidth', 0.5);

                    % 3. Draw Profiles LAST (Thicker, fully opaque)
                    if hasProfiles
                        patch(ax, 'XData', pL_shifted(:,d(1)), 'YData', pL_shifted(:,d(2)), 'ZData', zeros(size(pL_shifted,1),1), ...
                            'EdgeColor', t.planeRed, 'EdgeAlpha', 1.0, 'FaceColor', 'none', 'LineWidth', 1.0);
                        patch(ax, 'XData', pR_shifted(:,d(1)), 'YData', pR_shifted(:,d(2)), 'ZData', zeros(size(pR_shifted,1),1), ...
                            'EdgeColor', t.planeGreen, 'EdgeAlpha', 1.0, 'FaceColor', 'none', 'LineWidth', 1.0);
                    end
                else
                    % --- 3D ISOMETRIC VIEW ---
                    % 1. Draw Model
                    patch(ax, 'Vertices', V_shifted, 'Faces', F, ...
                        'FaceColor', t.modelColor, 'EdgeColor', 'none', 'FaceAlpha', t.modelAlpha);

                    % 2. Draw Billet Outline FIRST
                    [ bx, by, bz ] = app.makeBoxVertices(0, 0, 0, bSize(1), bSize(2), bSize(3));
                    patch(ax, 'Vertices', [ bx, by, bz ], 'Faces', app.boxFaces, ...
                        'FaceColor', 'none', 'EdgeColor', t.billetLine, 'LineStyle', '-', 'LineWidth', 0.8, 'EdgeAlpha', 0.3);

                    % 3. Draw Profiles LAST
                    if hasProfiles
                        patch(ax, 'XData', pL_shifted(:, 1), 'YData', pL_shifted(:, 2), 'ZData', pL_shifted(:, 3), ...
                            'EdgeColor', t.planeRed, 'EdgeAlpha', 1.0, 'FaceColor', 'none', 'LineWidth', 1.0);
                        patch(ax, 'XData', pR_shifted(:, 1), 'YData', pR_shifted(:, 2), 'ZData', pR_shifted(:, 3), ...
                            'EdgeColor', t.planeGreen, 'EdgeAlpha', 1.0, 'FaceColor', 'none', 'LineWidth', 1.0);
                    end
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

        %% ===========================================================
        %% --- GROUP 7: TAB 5 - MACHINE SETUP ---
        %% ===========================================================

        function onMachinePosEdited(app, axisIdx, src)
            % Purpose: Handles manual text/spinner entry for the billet's position on the machine bed.
            % WHY: Allows the user to manually override the auto-placement if they have a specific fixture.

            val = src.Value;
            oldY = app.MachineBilletPos(2);
            oldZ = app.MachineBilletPos(3);

            % X is relative to the left edge of the bed in the UI, but absolute in the backend.
            if axisIdx == 1
                app.MachineBilletPos(1) = app.MachineBedPos(1) + val;
            else
                app.MachineBilletPos(axisIdx) = val;
            end

            % HOW: If the billet moves on the bed, the manual entry/link points
            %      (which are tied to the billet) must shift by the exact same amount.
            dY = app.MachineBilletPos(2) - oldY;
            dZ = app.MachineBilletPos(3) - oldZ;
            app.shiftEntryPoints(dY, dZ);

            % Enforce physical boundaries on the spinners
            app.syncMachineUI();

            % Re-evaluate safety (e.g., did they push it off the back of the bed?)
            [ isValid, pCol, tCol, txtLines ] = app.checkMachineState();

            app.MachineLeftPanel.BackgroundColor = pCol;
            app.TxtMachineStatus.Value = txtLines;
            app.TxtMachineStatus.FontColor = tCol;

            app.BtnMachineContinue.Enable = 'on'; % Always allow proceeding to Cutting tab

            % Lock the auto-positioner since the user took manual control
            app.IsMachineUserModified = true;
            app.IsMachineInit = true;

            app.refreshMachinePlot();
        end

        function onResetMachineBilletPosition(app)
            % Purpose: Automatically places the billet on the machine bed in the optimal location.
            % WHY: To minimize wire extension, balance left/right tower travel, and align with
            %      standard physical foam stock heights and bed grid holes.

            if isempty(app.ModelPatch)
                return;
            end

            % Retain the previous machine position so existing entry and link
            % points can follow any Y/Z movement of the complete billet.
            oldMachineY = app.MachineBilletPos(2);
            oldMachineZ = app.MachineBilletPos(3);

            %% --- 1. SETUP & GRID DEFINITION ---
            bedX = app.MachineBedPos(1);
            maxXLimit = max(0, app.MachineBedSize(1) - app.BilletSize(1));

            % HOW: We generate a strict 50mm grid relative to the left edge of the bed.
            % This matches the physical threaded holes on the real CNC machine bed.
            maxRelX = floor(maxXLimit / 50.0) * 50.0;

            if maxRelX >= 0
                testRelXs = 0 : 50.0 : maxRelX;
                testXs = bedX + testRelXs; % Apply absolute machine offset
            else
                testXs = bedX; % Fallback if billet is technically too wide for the grid
            end

            % Default to the physical middle of the available 50mm grid
            bestX = testXs(max(1, ceil(numel(testXs)/2)));

            %% --- 2. X-AXIS OPTIMIZATION (TOWER PATH BALANCING) ---
            if ~isempty(app.LeftProfilePoints) && ~isempty(app.RightProfilePoints)

                % Fetch the synchronized profiles to evaluate path lengths
                [ yL, zL, yR, zR ] = app.getSyncedKerfProfiles();

                if ~isempty(yL)
                    % Shift profiles from model-local to billet-local coordinates
                    yL_base = yL + app.BilletShift(2);
                    zL_base = zL + app.BilletShift(3);
                    yR_base = yR + app.BilletShift(2);
                    zR_base = zR + app.BilletShift(3);

                    pXL = app.LeftProfilePoints(1,1);
                    pXR = app.RightProfilePoints(1,1);
                    planeDist = abs(pXR - pXL);

                    % If the part is tapered (planes are separated), we sweep the grid
                    % to find the X position that makes the Left and Right tower paths
                    % as close to equal length as possible.
                    if planeDist > 1e-3
                        bestDiff = inf;
                        centerX = bedX + maxXLimit / 2;

                        % Sweep ONLY the strict 50mm grid increments
                        for x = testXs
                            xL_m = x + app.BilletShift(1) + pXL;
                            xR_m = x + app.BilletShift(1) + pXR;

                            % Project the toolpath to the physical towers at this test X position
                            [ tL, tR ] = CNCHotWire_GCodeGenerator_Helpers.projectToTowers(yL_base, zL_base, xL_m, yR_base, zR_base, xR_m, app.MachineSpanX);

                            % Calculate total path length for each tower
                            lenL = sum(hypot(diff(tL.y), diff(tL.z)));
                            lenR = sum(hypot(diff(tR.y), diff(tR.z)));

                            % Penalty function: If multiple grid points yield similar path balances,
                            % prefer the one closest to the physical center of the machine bed.
                            penalty = 1e-6 * abs(x - centerX);
                            diffLen = abs(lenL - lenR) + penalty;

                            if diffLen < bestDiff
                                bestDiff = diffLen;
                                bestX = x;
                            end
                        end
                    end

                    app.MachineBilletPos(1) = bestX;

                    %% --- 3. Z-AXIS LOGIC (STOCK HEIGHTS) ---
                    % Re-evaluate the tower heights at the chosen bestX position
                    xL_m = bestX + app.BilletShift(1) + pXL;
                    xR_m = bestX + app.BilletShift(1) + pXR;

                    [ tL, tR ] = CNCHotWire_GCodeGenerator_Helpers.projectToTowers(yL_base, zL_base, xL_m, yR_base, zR_base, xR_m, app.MachineSpanX);

                    % Find the lowest point the wire reaches on either tower
                    minProjZ = min([tL.z; tR.z]);

                    if minProjZ >= 0
                        % Wire never goes below the bed, so billet can sit flat on the bed
                        app.MachineBilletPos(3) = 0;
                    else
                        % Wire dips below the bed! We must raise the billet on packing blocks.
                        % HOW: We snap to standard 25mm increments (e.g., 25, 50, 75mm blocks).
                        reqZ = -minProjZ;
                        targetZ = ceil(reqZ / 25.0) * 25.0;

                        % Force a minimum of 50mm packing if any packing is required at all
                        if targetZ > 0 && targetZ < 50
                            targetZ = 50.0;
                        end
                        app.MachineBilletPos(3) = targetZ;
                    end

                    %% --- 4. Y-AXIS LOGIC (SAFE CLEARANCE) ---
                    % Find the furthest forward the wire reaches
                    minProjY = min([tL.y; tR.y]);

                    % Ensure the wire never gets closer than 50mm to the absolute front of the machine
                    reqBilletY = max(50.0, 50.0 - minProjY);

                    % Snap the Y position to a 50mm grid for easy physical measurement
                    targetBilletY = ceil(reqBilletY / 50.0) * 50.0;

                    bedD = app.MachineBedSize(2);
                    bY = app.BilletSize(2);
                    maxY = app.MachineBedPos(2) + bedD - bY;

                    % Clamp to ensure it doesn't fall off the back of the bed
                    app.MachineBilletPos(2) = min(targetBilletY, maxY);
                else
                    % Fallback if profiles are empty
                    app.MachineBilletPos(1) = bestX;
                    app.MachineBilletPos(2) = app.MachineBedPos(2);
                    app.MachineBilletPos(3) = 0;
                end
            else
                % Fallback if profiles are empty
                app.MachineBilletPos(1) = bestX;
                app.MachineBilletPos(2) = app.MachineBedPos(2);
                app.MachineBilletPos(3) = 0;
            end

            %% --- 5. FINALIZE & UPDATE UI ---
            app.IsMachineInit = true;
            app.syncMachineUI();

            % Keep existing entry and link points aligned with the billet
            % after its final, boundary-constrained machine position is known.
            dY = app.MachineBilletPos(2) - oldMachineY;
            dZ = app.MachineBilletPos(3) - oldMachineZ;
            app.shiftEntryPoints(dY, dZ);

            [ isValid, pCol, tCol, txtLines ] = app.checkMachineState();

            app.MachineLeftPanel.BackgroundColor = pCol;
            app.TxtMachineStatus.Value = txtLines;
            app.TxtMachineStatus.FontColor = tCol;

            app.BtnMachineContinue.Enable = 'on';
            app.IsMachineUserModified = false; % Mark as auto-calculated
            app.refreshMachinePlot();
        end

        function onResetMachineViewMachine(app)
            % Purpose: Resets the 3D view to show the entire machine volume.
            app.resetViewToMachine(app.AxMachine);
        end

        function onResetMachineViewBillet(app)
            % Purpose: Zooms the 3D view tightly onto the billet.
            app.resetViewToBillet(app.AxMachine);
        end

        function refreshMachinePlot(app)
            % Purpose: Renders the 3D machine view, including the bed, towers, billet,
            %          model, and a sweep of the wire path to visualize the cut.
            % WHY: Allows the user to visually verify that the toolpath stays within
            %      the physical limits of the machine and doesn't over-extend the wire.

            ax = app.AxMachine;
            if isempty(ax) || ~isgraphics(ax), return; end

            %% --- 1. SETUP & INITIALIZATION ---
            delete(allchild(ax));
            hold(ax, 'on');

            t = app.getTheme(); % Master Palette

            % Machine geometry constants
            offX = app.MachineBedPos(1);
            mX = app.MachineSpanX;
            mLimY = app.MachineLimitY;
            mLimZ = app.MachineLimitZ;
            bs = app.MachineBedSize;
            bp = app.MachineBedPos;

            %% --- 2. DRAW STATIC MACHINE COMPONENTS ---

            % Draw Machine Bed (Sacrificial foam layer)
            [ xb, yb, zb ] = app.makeBoxVertices(0, bp(2), -bs(3), bs(1), bs(2), bs(3));
            hBed = patch(ax, 'Vertices',[ xb, yb, zb ], 'Faces', app.boxFaces, ...
                'FaceColor', t.bedCol, 'FaceAlpha', 0.5, 'EdgeColor', t.bedEdge);

            % Draw Travel Limits (Dotted Bounding Box)
            [ xl, yl, zl ] = app.makeBoxVertices(-offX, 0, 0, mX, mLimY, mLimZ);
            hLim = patch(ax, 'Vertices', [ xl, yl, zl ], 'Faces', app.boxFaces, ...
                'FaceColor', 'none', 'EdgeColor', t.labelCol, 'LineStyle', ':', 'EdgeAlpha', 0.3);

            % Draw Left and Right Towers (Semi-transparent planes)
            pY = [ 0; mLimY; mLimY; 0 ];
            pZ = [ 0; 0; mLimZ; mLimZ ];

            hTowerL = patch(ax, 'XData', ones(4,1)*(-offX), 'YData', pY, 'ZData', pZ, 'FaceColor', t.planeRed, ...
                'FaceAlpha', 0.15, 'EdgeColor', t.planeRed, 'LineStyle', '-');

            hTowerR = patch(ax, 'XData', ones(4,1)*(mX-offX), 'YData', pY, 'ZData', pZ, 'FaceColor', t.planeGreen, ...
                'FaceAlpha', 0.15, 'EdgeColor', t.planeGreen, 'LineStyle', '-');

            % Tower Labels
            text(ax, -offX, mLimY*0.98, mLimZ*0.92, {' LEFT',' TOWER'}, 'Color', t.planeRedTxt, 'FontWeight', 'bold', 'FontSize', 9);
            text(ax, mX-offX, mLimY*0.02, mLimZ*0.92, {'RIGHT','TOWER '}, 'Color', t.planeGreenTxt, 'FontWeight', 'bold', 'HorizontalAlignment', 'right', 'FontSize', 9);

            %% --- 3. DRAW BILLET & MODEL ---
            hBillet = gobjects(0); hModel = gobjects(0); hGhostL = gobjects(0); hWireL = gobjects(0);
            isViolated = false;

            if ~isempty(app.ModelPatch) && isgraphics(app.ModelPatch)
                bPlotPos =[ app.MachineBilletPos(1)-offX, app.MachineBilletPos(2), app.MachineBilletPos(3) ];
                totalShift = bPlotPos + app.BilletShift;

                % Draw Packing Block (If Billet is raised off the bed)
                if app.MachineBilletPos(3) > 0
                    [ xPack, yPack, zPack ] = app.makeBoxVertices(bPlotPos(1), bPlotPos(2), 0, app.BilletSize(1), app.BilletSize(2), app.MachineBilletPos(3));
                    patch(ax, 'Vertices',[ xPack, yPack, zPack ], 'Faces', app.boxFaces, ...
                        'FaceColor',[0.25 0.25 0.25], 'FaceAlpha', 0.9, 'EdgeColor', t.bedEdge, 'LineStyle', '-', 'HandleVisibility', 'off');
                end

                % Draw Billet (Thin solid lines to prevent aliasing)
                [ xm, ym, zm ] = app.makeBoxVertices(bPlotPos(1), bPlotPos(2), bPlotPos(3), app.BilletSize(1), app.BilletSize(2), app.BilletSize(3));
                hBillet = patch(ax, 'Vertices',[ xm, ym, zm ], 'Faces', app.boxFaces, ...
                    'FaceColor', t.billetColor, 'FaceAlpha', t.billetAlpha, ...
                    'EdgeColor', t.billetLine, 'LineStyle', '-', 'LineWidth', 0.5, 'EdgeAlpha', 0.5);

                % Draw Model Mesh
                Vplot = app.ModelPatch.Vertices + totalShift;
                hModel = patch(ax, 'Vertices', Vplot, 'Faces', app.ModelPatch.Faces, ...
                    'FaceColor', t.modelColor, 'FaceAlpha', t.modelAlpha, 'EdgeColor', 'none');

                %% --- 4. DRAW TOOLPATHS & WIRE SWEEP ---
                if ~isempty(app.LeftProfilePoints) && ~isempty(app.RightProfilePoints)

                    % Draw Ghost Profiles (Raw extracted profiles before kerf/sync)
                    [ yS_rawL, zS_rawL, yS_rawR, zS_rawR ] = CNCHotWire_GCodeGenerator_Helpers.syncPointCounts(...
                        app.LeftProfilePoints(:,2), app.LeftProfilePoints(:,3), ...
                        app.RightProfilePoints(:,2), app.RightProfilePoints(:,3));

                    xL_world = app.LeftProfilePoints(1,1) + totalShift(1);
                    xR_world = app.RightProfilePoints(1,1) + totalShift(1);

                    hGhostL = plot3(ax, xL_world * ones(size(yS_rawL)), yS_rawL + totalShift(2), zS_rawL + totalShift(3), ...
                        'Color', t.ghostRed, 'LineWidth', 0.75, 'LineStyle', '-');

                    plot3(ax, xR_world * ones(size(yS_rawR)), yS_rawR + totalShift(2), zS_rawR + totalShift(3), ...
                        'Color', t.ghostGreen, 'LineWidth', 0.75, 'LineStyle', '-');

                    % Fetch Kerf-Compensated Wire Paths
                    [ ySyncL, zSyncL, ySyncR, zSyncR ] = app.getSyncedKerfProfiles();

                    if ~isempty(ySyncL)
                        isCCW = strcmp(app.SwitchCutDir.Value, 'Bottom (CCW)');

                        % Apply start point shifts and cut direction
                        [ ySyncL, zSyncL ] = app.applyMods(ySyncL, zSyncL, 0, 0, app.SelectedStartIdxL, isCCW);
                        [ ySyncR, zSyncR ] = app.applyMods(ySyncR, zSyncR, 0, 0, app.SelectedStartIdxR, isCCW);

                        % Plot the actual cut paths on the model faces
                        hWireL = plot3(ax, xL_world * ones(size(ySyncL)), ySyncL + totalShift(2), zSyncL + totalShift(3), ...
                            'Color', t.wireKerf, 'LineWidth', 0.75);
                        plot3(ax, xR_world * ones(size(ySyncR)), ySyncR + totalShift(2), zSyncR + totalShift(3), ...
                            'Color', t.wireKerf, 'LineWidth', 0.75);

                        % Project paths outwards to the physical towers
                        [ tL, tR ] = CNCHotWire_GCodeGenerator_Helpers.projectToTowers(...
                            ySyncL + totalShift(2), zSyncL + totalShift(3), xL_world + offX, ...
                            ySyncR + totalShift(2), zSyncR + totalShift(3), xR_world + offX, app.MachineSpanX);

                        plot3(ax, ones(size(tL.y))*(-offX), tL.y, tL.z, 'Color', t.planeRed, 'LineWidth', 0.75);
                        plot3(ax, ones(size(tR.y))*(mX-offX), tR.y, tR.z, 'Color', t.planeGreen, 'LineWidth', 0.75);

                        %% --- SMART WIRE DISTRIBUTION ALGORITHM ---
                        % WHY: Drawing a wire at every single point creates a solid, unreadable wall of color.
                        % HOW: We selectively pick indices to draw the wire based on distance, curvature, and sharp corners.

                        N_pts = numel(tL.y);
                        idx = 1;
                        last_idx = 1;
                        accumulated_angle = 0;

                        % 1. Straight Lines: Target distance between wires (scales with total path length)
                        total_len = sum(hypot(diff(ySyncL), diff(zSyncL)));
                        target_spacing = max(10.0, total_len / 40.0);

                        % 2. Curves: Degrees of cumulative bending before drawing a wire
                        curve_angle_threshold = 10.0;

                        % 3. Minimum Spacing: Prevents crowding/pairing on curves and noisy straights
                        min_spacing = 4.0;

                        % 4. Hard Corners: Always draw if the angle exceeds this (ignores min_spacing)
                        sharp_corner_threshold = 10.0;

                        for i = 2:N_pts-1
                            % Physical distance from the last drawn wire
                            d = hypot(ySyncL(i) - ySyncL(last_idx), zSyncL(i) - zSyncL(last_idx));

                            % Segment vectors and lengths to calculate turning angle
                            v1 =[ ySyncL(i) - ySyncL(i-1), zSyncL(i) - zSyncL(i-1) ];
                            v2 =[ ySyncL(i+1) - ySyncL(i), zSyncL(i+1) - zSyncL(i) ];
                            n1 = norm(v1);
                            n2 = norm(v2);

                            angle_deg = 0;
                            if n1 > 1e-4 && n2 > 1e-4
                                dp = dot(v1, v2) / (n1 * n2);
                                angle_deg = acosd(max(-1, min(1, dp)));
                            end

                            accumulated_angle = accumulated_angle + angle_deg;

                            % Rule 1: Traveled far enough along a gentle curve or straight
                            isSpaced = (d >= target_spacing);

                            % Rule 2: Sharp internal corner (Always draws to show the pivot)
                            isSharp = (angle_deg >= sharp_corner_threshold);

                            % Rule 3: Transition (Start/End of an external curve or straight).
                            % Must bend at least 2 degrees to ignore noisy straight lines.
                            isTransition = (max(n1, n2) > 1.0) && (max(n1, n2) > 3.0 * min(n1, n2)) && (angle_deg > 2.0);

                            % Rule 4: Fanning around smooth curves based on accumulated angle
                            isCurved = (accumulated_angle >= curve_angle_threshold);

                            % Apply the rules (with min_spacing veto for non-sharp moves)
                            if isSharp || ((isSpaced || isTransition || isCurved) && (d >= min_spacing))
                                idx(end+1) = i;
                                last_idx = i;
                                accumulated_angle = 0; % Reset after drawing!
                            end
                        end

                        % Always include the very last point to close the loop
                        idx(end+1) = N_pts;
                        idx = unique(idx);

                        dotCMap = hsv(numel(idx));

                        % Check if the toolpath forces the towers outside physical limits
                        bad = (tL.y < 0 | tL.y > mLimY | tL.z < 0 | tL.z > mLimZ | tR.y < 0 | tR.y > mLimY | tR.z < 0 | tR.z > mLimZ);
                        if any(bad), isViolated = true; end

                        % Fixed length of the hot wire (from left tower to neutral joint position)
                        L_hot = (app.MachineBedPos(1) + app.MachineBedSize(1)) + app.BrassJointOffsetRight;

                        % Draw the selected wires
                        for k = 1:numel(idx)
                            currIdx = idx(k);

                            wCol =[ t.wireBaseCol, 0.60 ];
                            if bad(currIdx)
                                wCol =[ 1 0.8 0 0.8 ]; % Highlight bad segments in amber
                            end

                            % Tower connection points for this step
                            pTL_i =[-offX, tL.y(currIdx), tL.z(currIdx)];
                            pTR_i =[mX-offX, tR.y(currIdx), tR.z(currIdx)];

                            % Calculate Brass Joint Position
                            wireVec = pTR_i - pTL_i;
                            wireLen = norm(wireVec);
                            pJoint_i = pTL_i + wireVec * (L_hot / wireLen);

                            % Draw Hot Wire (Left tower to Brass Joint)
                            plot3(ax, [ pTL_i(1), pJoint_i(1) ],[ pTL_i(2), pJoint_i(2) ],[ pTL_i(3), pJoint_i(3) ], ...
                                'Color', wCol, 'LineWidth', 0.5);

                            % Draw Tension Wire (Brass Joint to Right tower - Thicker, Grey)
                            plot3(ax,[ pJoint_i(1), pTR_i(1) ],[ pJoint_i(2), pTR_i(2) ], [ pJoint_i(3), pTR_i(3) ], ...
                                'Color', [ 0.5 0.5 0.5 0.8 ], 'LineWidth', 1.0);

                            % Draw Brass Joint (Large Orange Dot)
                            plot3(ax, pJoint_i(1), pJoint_i(2), pJoint_i(3), '.', 'Color', t.wireLead, 'MarkerSize', 6);

                            % Draw tracking dots on the model profiles
                            plot3(ax, xL_world, ySyncL(currIdx) + totalShift(2), zSyncL(currIdx) + totalShift(3), ...
                                '.', 'Color', dotCMap(k,:), 'MarkerSize', 8);

                            plot3(ax, xR_world, ySyncR(currIdx) + totalShift(2), zSyncR(currIdx) + totalShift(3), ...
                                '.', 'Color', dotCMap(k,:), 'MarkerSize', 8);
                        end
                    end
                end
            end

            %% --- 5. FORMATTING & LEGEND ---
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

            xlabel(ax, 'X'); ylabel(ax, 'Y'); zlabel(ax, 'Z');

            % Minimal padding to allow towers to fill the screen
            padX = 5; padY = 5; padZ = 40;
            xlim(ax,[ -offX - padX, mX - offX + padX ]);
            ylim(ax,[ -padY, mLimY + padY ]);
            zlim(ax,[ -bs(3) - 20, mLimZ + padZ ]);

            %% --- 6. SAFETY CHECKS & UI UPDATE ---
            [ isValid, pCol, tCol, txtLines ] = app.checkMachineState();

            if isViolated
                isValid = false;
                pCol = t.statErrBg;
                tCol = t.statErrTxt;
                txtLines =["CRITICAL ERROR:"; "Toolpath forces tower outside physical limits!"];
            end

            % --- WIRE EXTENSION SAFETY CHECK ---
            % HOW: Calculates the hypotenuse of the wire stretch between the two towers.
            if ~isempty(app.LeftProfilePoints) && ~isempty(app.RightProfilePoints) && exist('tL', 'var')
                dy_ext = tL.y - tR.y;
                dz_ext = tL.z - tR.z;
                ext_all = hypot(app.MachineSpanX, hypot(dy_ext, dz_ext)) - app.MachineSpanX;
                app.MaxPathExtension = max(ext_all);

                if app.MaxPathExtension > app.WireExt_Red
                    isValid = false; % Hard Block
                    pCol = t.statErrBg;
                    tCol = t.statErrTxt;
                    txtLines =["CRITICAL ERROR: WIRE OVER-EXTENSION", ...
                        sprintf("Max Extension: %.2f mm", app.MaxPathExtension), ...
                        sprintf("Exceeds Hardware Limit (%.0f mm)!", app.WireExt_Red)];
                elseif app.MaxPathExtension > app.WireExt_Amber
                    if isValid
                        pCol = t.statWarnBg;
                        tCol = t.statWarnTxt;
                        txtLines =["WARNING: WIRE EXTENSION", ...
                            sprintf("Max Extension: %.2f mm", app.MaxPathExtension), ...
                            "Pulley travel is nearly exhausted."];
                    end
                end
            end

            app.MachineLeftPanel.BackgroundColor = pCol;
            app.TxtMachineStatus.Value = txtLines;
            app.TxtMachineStatus.FontColor = tCol;

            app.BtnMachineContinue.Enable = 'on';
            drawnow limitrate;
        end

        function syncMachineUI(app)
            % Purpose: Enforces physical boundaries directly on the UI Spinners.
            % WHY: Prevents the user from typing in a value that places the billet
            %      off the edge of the physical machine bed.

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

        function [ isValid, panelCol, textCol, msgLines ] = checkMachineState(app)
            % Purpose: Validates the billet's physical placement on the machine bed.
            % WHY: Ensures the billet doesn't overhang the bed, exceed Z-travel,
            %      or cause the brass wire joint to crash into the foam.
            % HOW: Compares the absolute machine coordinates of the billet against
            %      the physical machine limits defined in the class properties.

            bPos  = app.MachineBilletPos;
            bSize = app.BilletSize;
            bMin = bPos;
            bMax = bPos + bSize;
            bedMin = app.MachineBedPos;
            bedMax = app.MachineBedPos + app.MachineBedSize;
            limZ = [0, app.MachineLimitZ];

            t = app.getTheme(); % Master Palette

            crit = strings(0);

            %% --- 1. Hard Physical Limits ---
            if bMin(1) < bedMin(1) - 0.1 || bMax(1) > bedMax(1) + 0.1, crit(end+1) = "Billet overhangs Bed (X)."; end
            if bMin(2) < bedMin(2) - 0.1 || bMax(2) > bedMax(2) + 0.1, crit(end+1) = "Billet overhangs Bed (Y)."; end
            if bMin(3) < 0 - 0.1, crit(end+1) = "Billet below bed surface (Z < 0)."; end
            if bMax(3) > limZ(2) + 0.1, crit(end+1) = "Billet exceeds max Z travel."; end

            %% --- 2. Wire Extension Collision Check ---
            % The brass joint connects the hot wire to the tension wire.
            % Its neutral position is defined by BrassJointOffsetRight (-50mm).
            rightBedEdge = app.MachineBedPos(1) + app.MachineBedSize(1);
            neutralJointX = rightBedEdge + app.BrassJointOffsetRight;
            minJointX = neutralJointX - app.MaxPathExtension;

            % The gap between the right face of the billet and the brass joint
            % must not be less than the safety buffer.
            if (minJointX - bMax(1)) < app.SafetyBuffer_BedEdge && app.MaxPathExtension > 0
                crit(end+1) = sprintf("CRITICAL: Wire extension pulls brass joint to within %.1fmm of billet (Minimum allowed is %.0fmm).", (minJointX - bMax(1)), app.SafetyBuffer_BedEdge);
            end

            if ~isempty(crit)
                isValid = false;
                panelCol = t.statErrBg;
                textCol = t.statErrTxt;
                msgLines = ["CRITICAL ERROR:"; crit'];
                return;
            end

            warn = strings(0);
            buf = app.SafetyBuffer_BedEdge;

            %% --- 3. Soft Warnings (Proximity) ---
            if (bMin(1) - bedMin(1) < buf), warn(end+1) = sprintf("Close to Left bed edge (<%.0fmm).", buf); end
            if (bedMax(1) - bMax(1) < buf)
                warn(end+1) = sprintf("Close to Right bed edge (<%.0fmm).", buf);
                if strcmp(app.TaperToggle.Value, 'Tapered')
                    warn(end+1) = "TAPER WARNING: Ensure brass wire fixture clears the billet.";
                end
            end
            if (bedMax(2) - bMax(2) < buf), warn(end+1) = sprintf("Close to Back bed edge (<%.0fmm).", buf); end

            if ~isempty(warn)
                isValid = true;
                panelCol = t.statWarnBg;
                textCol = t.statWarnTxt;
                msgLines = ["Warning: Proximity to bed edge."; warn'];
            else
                isValid = true;
                panelCol = t.statPassBg;
                textCol = t.statPassTxt;
                msgLines = ["Machine configuration valid.", "Ready to proceed."];
            end
        end

        %% ===========================================================
        %% --- GROUP 8: TAB 6 - CUTTING STRATEGY ---
        %% ===========================================================

        %%                    - CORE LOGIC & VALIDATION -
        function[ isValid, pCol, tCol, msgLines ] = validateCuttingStrategy(app)
            % Purpose: Validates the cutting path against physical constraints and model geometry.
            % WHY: Prevents the machine from dragging the wire through solid foam during a rapid move,
            %      and ensures the lead-in cut doesn't slice through the actual part.
            % HOW: Uses a custom 2D line-intersection algorithm to check the rapid paths against
            %      the billet bounding box, and the lead-in path against the model profile polygon.

            isValid = true;
            crit = strings(0);
            warn = strings(0);

            %% --- 1. SETUP GEOMETRY ---
            bMinY = app.MachineBilletPos(2);
            bMaxY = app.MachineBilletPos(2) + app.BilletSize(2);
            bMinZ = app.MachineBilletPos(3);
            bMaxZ = app.MachineBilletPos(3) + app.BilletSize(3);

            % Billet Polygon (for intersection checks)
            billetBoxY =[ bMinY; bMaxY; bMaxY; bMinY; bMinY ];
            billetBoxZ =[ bMinZ; bMinZ; bMaxZ; bMaxZ; bMinZ ];

            % Get Final Profiles (Machine Absolute) to check for gouging
            offsetY = app.BilletShift(2) + bMinY;
            offsetZ = app.BilletShift(3) + bMinZ;

            [ syncY_L, syncZ_L, syncY_R, syncZ_R ] = app.getSyncedKerfProfiles();
            [ yL, zL ] = app.applyMods(syncY_L, syncZ_L, offsetY, offsetZ, app.SelectedStartIdxL, false);
            [ yR, zR ] = app.applyMods(syncY_R, syncZ_R, offsetY, offsetZ, app.SelectedStartIdxR, false);

            %% --- NESTED HELPER: INTERSECTION MATH ---
            function [ xi, zi ] = intersectSegPoly(p1, p2, polyY, polyZ)
                % Custom Intersection Helper (Replaces polyxpoly to avoid Mapping Toolbox dependency).
                % Checks a single line segment (p1 -> p2) against a polyline.
                xi = [ ];
                zi = [ ];
                y1 = p1(1); z1 = p1(2);
                y2 = p2(1); z2 = p2(2);
                dy1 = y2 - y1; dz1 = z2 - z1;

                for i = 1:(numel(polyY)-1)
                    y3 = polyY(i); z3 = polyZ(i);
                    y4 = polyY(i+1); z4 = polyZ(i+1);
                    dy2 = y4 - y3; dz2 = z4 - z3;

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

            %% --- NESTED HELPER: SIDE VALIDATION ---
            function checkSide(sideName, lead, link1, link2, profY, profZ)
                % Catch empty lead points (e.g. from Clear Pts button)
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
                pRet = [ bMinY - 10, bMaxZ/2 ];
                pathPts =[ pRet; link1; link2; lead ];
                pathPts = pathPts(~all(pathPts==0, 2), :);

                for k = 1:size(pathPts, 1)-1
                    p1 = pathPts(k,:);
                    p2 = pathPts(k+1,:);

                    [ xi, zi ] = intersectSegPoly(p1, p2, billetBoxY, billetBoxZ);

                    if ~isempty(xi)
                        crit(end+1) = sprintf("%s: Rapid move passes THROUGH the billet!", sideName);
                        break;
                    end
                end

                % C. CRITICAL: Lead-In Gouging (Bisecting) Model
                if ~isempty(profY)
                    startPt = [ profY(1), profZ(1) ];

                    [ xi, zi ] = intersectSegPoly([ lead(1), lead(2) ],[ startPt(1), startPt(2) ], profY, profZ);

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

            %% --- 2. EXECUTE CHECKS ---
            checkSide("Left", app.EntryPointL, app.EntryPoint2L, app.EntryPoint3L, yL, zL);
            if ~isempty(app.EntryPointR)
                checkSide("Right", app.EntryPointR, app.EntryPoint2R, app.EntryPoint3R, yR, zR);
            end

            t = app.getTheme();

            if ~isempty(crit)
                isValid = false;
                pCol = t.statErrBg;
                tCol = t.statErrTxt;
                msgLines = ["CRITICAL ERROR:"; crit(1)];
            elseif ~isempty(warn)
                isValid = true;
                pCol = t.statWarnBg;
                tCol = t.statWarnTxt;
                msgLines = ["Warning:"; warn(1)];
            else
                isValid = true;
                pCol = t.statPassBg;
                tCol = t.statPassTxt;
                msgLines = ["Strategy valid.", "Ready to cut."];
            end
        end

        function shiftEntryPoints(app, dY, dZ)
            % Purpose: Shifts all manual entry points by a given delta.
            % WHY: Ensures the entry points "stick" to the billet if moved or changed on billet or machine tab.
            if dY == 0 && dZ == 0
                return;
            end

            shift2D =[ dY, dZ ];

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

        %%                    - PLOTTING & VISUALIZATION -
        function updateCuttingPlots(app)
            % Purpose: Renders the 2D cutting paths (Left and Right) including
            %          rapid moves, lead-ins, the profile cut, and lead-outs.

            if isempty(app.AxCutLeft) || isempty(app.AxCutRight)
                return;
            end

            t = app.getTheme();

            %% --- 1. PRESERVE VIEW STATE ---
            curXL = xlim(app.AxCutLeft);
            isInitialized = ~isequal(curXL,[ 0 1 ]);

            limsL = [ ]; limsR = [ ];

            if isInitialized
                limsL =[ xlim(app.AxCutLeft); ylim(app.AxCutLeft) ];
                limsR =[ xlim(app.AxCutRight); ylim(app.AxCutRight) ];
            end

            cla(app.AxCutLeft); cla(app.AxCutRight);
            hold(app.AxCutLeft,'on'); hold(app.AxCutRight,'on');

            %% --- 2. SETUP GEOMETRY & OFFSETS ---
            offsetY = app.BilletShift(2) + app.MachineBilletPos(2);
            offsetZ = app.BilletShift(3) + app.MachineBilletPos(3);
            isCCW   = strcmp(app.SwitchCutDir.Value, 'Bottom (CCW)');

            % Draw Bed
            bedY =[ 50, 750, 750, 50 ];
            bedZ =[ -20, -20, 0, 0 ];
            patch(app.AxCutLeft, bedY, bedZ, t.labelCol, 'FaceAlpha', 0.1, 'EdgeColor', 'none', 'HitTest', 'off');
            patch(app.AxCutRight, bedY, bedZ, t.labelCol, 'FaceAlpha', 0.1, 'EdgeColor', 'none', 'HitTest', 'off');

            % Draw Machine Limits
            mBoxY =[ 0, app.MachineLimitY, app.MachineLimitY, 0, 0 ];
            mBoxZ =[ 0, 0, app.MachineLimitZ, app.MachineLimitZ, 0 ];
            hMachL = plot(app.AxCutLeft, mBoxY, mBoxZ, ':', 'Color', t.labelCol, 'LineWidth', 0.5, 'HitTest', 'off');
            hMachR = plot(app.AxCutRight, mBoxY, mBoxZ, ':', 'Color', t.labelCol, 'LineWidth', 0.5, 'HitTest', 'off');

            % Draw Packing Block (If Billet is raised)
            bY = app.MachineBilletPos(2);
            bZ = app.MachineBilletPos(3);
            bW = app.BilletSize(2);
            bH = app.BilletSize(3);

            if bZ > 0
                packY =[ bY, bY+bW, bY+bW, bY, bY ];
                packZ = [ 0, 0, bZ, bZ, 0 ];
                patch(app.AxCutLeft, 'XData', packY, 'YData', packZ, 'FaceColor',[0.25 0.25 0.25], 'FaceAlpha', 0.9, 'EdgeColor', t.bedEdge, 'LineStyle', '-', 'HitTest', 'off');
                patch(app.AxCutRight, 'XData', packY, 'YData', packZ, 'FaceColor',[0.25 0.25 0.25], 'FaceAlpha', 0.9, 'EdgeColor', t.bedEdge, 'LineStyle', '-', 'HitTest', 'off');
            end

            % Draw Billet (Thin solid line with EdgeAlpha to prevent aliasing)
            boxY =[ bY, bY+bW, bY+bW, bY, bY ];
            boxZ =[ bZ, bZ, bZ+bH, bZ+bH, bZ ];
            hBilletL = patch(app.AxCutLeft, 'XData', boxY, 'YData', boxZ, 'FaceColor', 'none', 'EdgeColor', t.billetLine, 'LineStyle', '-', 'LineWidth', 0.5, 'EdgeAlpha', 0.5, 'HitTest', 'off');
            hBilletR = patch(app.AxCutRight, 'XData', boxY, 'YData', boxZ, 'FaceColor', 'none', 'EdgeColor', t.billetLine, 'LineStyle', '-', 'LineWidth', 0.5, 'EdgeAlpha', 0.5, 'HitTest', 'off');

            %% --- 3. PROCESS PATH DATA ---
            [ syncY_L, syncZ_L, syncY_R, syncZ_R ] = app.getSyncedKerfProfiles();

            hGhostL = gobjects(0); hGhostR = gobjects(0);

            if ~isempty(app.LeftProfilePoints)
                hGhostL = plot(app.AxCutLeft, app.LeftProfilePoints(:,2) + offsetY, app.LeftProfilePoints(:,3) + offsetZ, ':', 'Color', t.rawMeshCol, 'LineWidth', 0.5, 'HitTest', 'off');
            end
            if ~isempty(app.RightProfilePoints)
                hGhostR = plot(app.AxCutRight, app.RightProfilePoints(:,2) + offsetY, app.RightProfilePoints(:,3) + offsetZ, ':', 'Color', t.rawMeshCol, 'LineWidth', 0.5, 'HitTest', 'off');
            end

            % Apply Start Index Shift and Direction Reversal
            [ yL, zL ] = app.applyMods(syncY_L, syncZ_L, offsetY, offsetZ, app.SelectedStartIdxL, isCCW);
            [ yR, zR ] = app.applyMods(syncY_R, syncZ_R, offsetY, offsetZ, app.SelectedStartIdxR, isCCW);

            %% --- 4. DRAW CUT PATHS ---
            function hD = drawDummyLegendMarker(ax, style, color, mFace, lWidth)
                if nargin < 5, lWidth = 1.0; end
                hD = plot(ax, NaN, NaN, style, 'Color', color, 'MarkerFaceColor', mFace, 'LineWidth', lWidth);
            end

            % Left Path
            hRapidL = gobjects(0); hLeadL = gobjects(0); hStartL = gobjects(0); hPathDummyL = gobjects(0); hEntryDotL = gobjects(0); hLoadL = gobjects(0);
            if ~isempty(yL)
                c = (1:numel(yL))';
                patch(app.AxCutLeft, 'XData',[ yL; NaN ], 'YData',[ zL; NaN ], 'CData', [ c; NaN ], 'FaceColor', 'none', 'EdgeColor', 'interp', 'LineWidth', 1.0, 'HitTest', 'off');
                hPathDummyL = drawDummyLegendMarker(app.AxCutLeft, '-', [ 0 0.5 1 ], 'none', 1.0);
                [ hRapidL, hLeadL, hEntryDotL, hLoadL ] = app.drawTravelPath(app.AxCutLeft,[ yL(1), zL(1) ], [ yL(end), zL(end) ], app.EntryPointL, app.EntryPoint2L, app.EntryPoint3L);

                if numel(yL) > 1
                    idxNext = 2;
                    while idxNext < numel(yL) && norm([ yL(idxNext),zL(idxNext) ] - [ yL(1),zL(1) ]) < 1e-4
                        idxNext = idxNext + 1;
                    end
                    app.drawRotatedMarker(app.AxCutLeft, [ yL(1), zL(1) ],[ yL(idxNext), zL(idxNext) ], 'start');
                    hStartL = drawDummyLegendMarker(app.AxCutLeft, '^', [ 0 1 0 ], 'none');
                end
            end

            % Right Path
            hRapidR = gobjects(0); hLeadR = gobjects(0); hStartR = gobjects(0); hPathDummyR = gobjects(0); hEntryDotR = gobjects(0); hLoadR = gobjects(0);
            if ~isempty(yR)
                c = (1:numel(yR))';
                patch(app.AxCutRight, 'XData', [ yR; NaN ], 'YData',[ zR; NaN ], 'CData', [ c; NaN ], 'FaceColor', 'none', 'EdgeColor', 'interp', 'LineWidth', 1.0, 'HitTest', 'off');
                hPathDummyR = drawDummyLegendMarker(app.AxCutRight, '-',[ 0 0.5 1 ], 'none', 1.0);

                [ hRapidR, hLeadR, hEntryDotR, hLoadR ] = app.drawTravelPath(app.AxCutRight, [ yR(1), zR(1) ],[ yR(end), zR(end) ], app.EntryPointR, app.EntryPoint2R, app.EntryPoint3R);

                if numel(yR) > 1
                    idxNext = 2;
                    while idxNext < numel(yR) && norm([ yR(idxNext),zR(idxNext) ] -[ yR(1),zR(1) ]) < 1e-4
                        idxNext = idxNext + 1;
                    end
                    app.drawRotatedMarker(app.AxCutRight,[ yR(1), zR(1) ], [ yR(idxNext), zR(idxNext) ], 'start');
                    hStartR = drawDummyLegendMarker(app.AxCutRight, '^',[ 0 1 0 ], 'none');
                end
            end

            %% --- 5. LEGENDS & UI STATUS ---
            function buildLegend(axTarget, hs, hl, hp, hr, hld, he, hm, hg, tCol)
                hList = [ ]; lList = {};
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
                    lgd.Box = 'off'; lgd.TextColor = tCol;
                end
            end

            if ~isgraphics(hEntryDotL), hEntryDotL = drawDummyLegendMarker(app.AxCutLeft, '.', t.wireLead, t.wireLead, 1.0); end
            if ~isgraphics(hEntryDotR), hEntryDotR = drawDummyLegendMarker(app.AxCutRight, '.', t.wireLead, t.wireLead, 1.0); end

            buildLegend(app.AxCutLeft, hStartL, hLoadL, hPathDummyL, hRapidL, hLeadL, hEntryDotL, hMachL, hGhostL, t.labelCol);
            buildLegend(app.AxCutRight, hStartR, hLoadR, hPathDummyR, hRapidR, hLeadR, hEntryDotR, hMachR, hGhostR, t.labelCol);
            [ isValidCut, pCol, tCol, msgLines ] = app.validateCuttingStrategy();

            app.CuttingLeftPanel.BackgroundColor = pCol;
            app.TxtCuttingStatus.Value = msgLines;
            app.TxtCuttingStatus.FontColor = tCol;
            if isValidCut, app.BtnCuttingContinue.Enable = 'on'; else, app.BtnCuttingContinue.Enable = 'off'; end

            %% --- 6. FORMAT AXES ---
            title(app.AxCutLeft,'Left Tower', 'Color', t.labelCol);
            title(app.AxCutRight,'Right Tower', 'Color', t.labelCol);
            colormap(app.AxCutLeft,'turbo'); colormap(app.AxCutRight,'turbo');

            xlabel(app.AxCutLeft, 'Y (mm)', 'Color', t.labelCol, 'FontWeight', 'bold');
            ylabel(app.AxCutLeft, 'Z (mm)', 'Color', t.labelCol, 'FontWeight', 'bold');
            xlabel(app.AxCutRight, 'Y (mm)', 'Color', t.labelCol, 'FontWeight', 'bold');
            ylabel(app.AxCutRight, 'Z (mm)', 'Color', t.labelCol, 'FontWeight', 'bold');

            app.AxCutLeft.XColor = t.labelCol; app.AxCutLeft.YColor = t.labelCol;
            app.AxCutRight.XColor = t.labelCol; app.AxCutRight.YColor = t.labelCol;

            if isInitialized
                xlim(app.AxCutLeft, limsL(1,:)); ylim(app.AxCutLeft, limsL(2,:));
                xlim(app.AxCutRight, limsR(1,:)); ylim(app.AxCutRight, limsR(2,:));
            else
                axis(app.AxCutLeft,'equal'); axis(app.AxCutRight,'equal');
            end

            daspect(app.AxCutLeft, [ 1 1 1 ]); daspect(app.AxCutRight,[ 1 1 1 ]);
        end

        function onResetCuttingViewMachine(app)
            % Purpose: Resets the Cutting Tab view to show the entire machine bed.
            mLimY = app.MachineLimitY;
            mLimZ = app.MachineLimitZ;
            limits =[-50, mLimY+50, -50, mLimZ+50];
            axis(app.AxCutLeft, limits);
            axis(app.AxCutRight, limits);
        end

        function onResetCuttingViewBillet(app)
            % Purpose: Zooms the Cutting Tab view tightly onto the billet with a safe margin.
            bY = app.MachineBilletPos(2);
            bZ = app.MachineBilletPos(3);
            bW = app.BilletSize(2);
            bH = app.BilletSize(3);

            % Use a 10% proportional buffer PLUS a fixed 25mm buffer.
            % The fixed 25mm ensures the standard 10mm retracts and load points
            % are never cropped, even on very small billets.
            buffer = max(bW, bH) * 0.10 + 25.0;

            % ASYMMETRIC LEGEND PADDING: Add 35% extra space to the right side
            % so the legend doesn't cover the toolpaths.
            legendBuffer = buffer + max(bW, bH) * 0.35;

            xLims =[ bY - buffer, bY + bW + legendBuffer ];
            yLims =[ bZ - buffer, bZ + bH + buffer ];

            xlim(app.AxCutLeft, xLims);
            ylim(app.AxCutLeft, yLims);
            daspect(app.AxCutLeft, [ 1 1 1 ]);

            xlim(app.AxCutRight, xLims);
            ylim(app.AxCutRight, yLims);
            daspect(app.AxCutRight,[ 1 1 1 ]);

            drawnow limitrate;
        end

        function[ hRapid, hLead, hDot, hLoad ] = drawTravelPath(app, ax, startPt, endPt, lead, link1, link2)
            % Purpose: Helper function to draw the yellow rapid lines and orange lead-in lines.

            hRapid = gobjects(0);
            hLead = gobjects(0);
            hDot = gobjects(0);
            hLoad = gobjects(0);

            if isempty(startPt) || isempty(lead)
                return;
            end

            pZero    =[ 0, 0 ];
            pSafe    =[ 10, 10 ];
            pLoad    =[ app.MachineBilletPos(2), app.MachineBilletPos(3)+app.BilletSize(3)/2 ];
            pRetract =[ pLoad(1)-10, pLoad(2) ];

            hLoad = plot(ax, pLoad(1), pLoad(2), 'x', 'MarkerSize', 8, 'Color', [ 1 0 1 ], 'LineWidth', 1.5, 'HitTest','off');

            t = app.getTheme();

            % --- INBOUND PATH ---
            pts =[ pZero; pSafe; pLoad; pRetract ];
            if ~isempty(link1)
                pts =[ pts; link1 ];
            end
            if ~isempty(link2)
                pts =[ pts; link2 ];
            end
            pts =[ pts; lead ];

            if size(pts,1) > 1
                hRapid = plot(ax, pts(:,1), pts(:,2), '-', 'Color',[ 0.9 0.8 0 ], 'LineWidth',0.5, 'HitTest','off');
            end

            hLead = plot(ax, [ lead(1), startPt(1) ],[ lead(2), startPt(2) ], '-', 'Color', t.wireLead, 'LineWidth',0.5, 'HitTest','off');

            % --- OUTBOUND PATH (Retrace) ---
            plot(ax,[ endPt(1), lead(1) ], [ endPt(2), lead(2) ], '--', 'Color', t.wireLead, 'LineWidth',1.0, 'HitTest','off');

            ptsOut = lead;
            if ~isempty(link2)
                ptsOut =[ ptsOut; link2 ];
            end
            if ~isempty(link1)
                ptsOut =[ ptsOut; link1 ];
            end

            % Retract back to safe point in front of block
            ptsOut =[ ptsOut; pRetract ];

            % Home Y First for safety
            pHomeY =[ 0, pRetract(2) ];
            ptsOut =[ ptsOut; pHomeY; pZero ];

            plot(ax, ptsOut(:,1), ptsOut(:,2), '--', 'Color',[ 0.9 0.8 0 ], 'LineWidth',0.5, 'HitTest','off');

            % --- DOTS ---
            hDot = plot(ax, lead(1), lead(2), '.', 'Color',[ 1 0.5 0 ], 'MarkerSize', 10, 'HitTest', 'off');

            if ~isempty(link1)
                plot(ax, link1(1), link1(2), '.', 'Color',[ 0.9 0.8 0 ], 'MarkerSize',10, 'HitTest','off');
            end
            if ~isempty(link2)
                plot(ax, link2(1), link2(2), '.', 'Color',[ 0.9 0.8 0 ], 'MarkerSize',10, 'HitTest','off');
            end
        end

        function hMarker = drawRotatedMarker(app, ax, pCurrent, pNext, type)
            % Purpose: Draws a rotated triangle at the start point to indicate cut direction.

            hMarker = gobjects(0);
            v = pNext - pCurrent;
            len = norm(v);

            if len < 1e-6
                return;
            end

            u = v / len;
            scale = 4; % Size mm

            if strcmp(type, 'start')
                % Forward pointing triangle (Green)
                xPoly =[ 0, -1, -1 ] * scale;
                yPoly =[ 0, 0.5, -0.5 ] * scale;
                colFill = 'none'; colEdge =[ 0 1 0 ];
            else
                % Exit Triangle (Red)
                xPoly =[ 0, -1, -1 ] * scale;
                yPoly =[ 0, 0.5, -0.5 ] * scale;
                colFill = 'none'; colEdge =[ 1 0 0 ];
            end

            % Rotation
            theta = atan2(u(2), u(1));
            R =[ cos(theta), -sin(theta); sin(theta), cos(theta) ];
            ptsRot = R * [ xPoly; yPoly ];

            % Translate
            ptsFinal = ptsRot + pCurrent(:);

            % Z-Buffer Safety: Lift it slightly towards camera so it sits on top of lines
            zLift = 0.1;

            hMarker = patch(ax, ptsFinal(1,:), ptsFinal(2,:), ptsFinal(2,:)*0 + zLift, ...
                'FaceColor', colFill, 'EdgeColor', colEdge, 'LineWidth', 1.0, 'HitTest','off');
        end

        %%                    - UI CALLBACKS & INTERACTION -
        function onCutDirectionChanged(app)
            % Purpose: Triggered when switching between CW (Top First) and CCW (Bottom First).
            app.updateCuttingPlots();
        end

        function onInteractionStatsChanged(app, src)
            % Purpose: Handles mutual exclusivity and color updates for the interactive plot buttons.
            % WHY: Ensures only one "Pick Point" mode is active at a time.

            c = app.getInteractionColors();
            wantsToEnable = src.Value;

            % Reset ALL buttons to OFF/Inactive (Clean Slate)
            app.resetInteractionState();

            % If the user wanted to enable a button, turn THAT one back on
            if wantsToEnable
                src.Value = true;
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
            % Purpose: Turns off all interaction buttons and resets the mouse cursor.
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

            % 3. Reset Font Colors
            app.BtnPickStart.FontColor = c.TextInactive;
            app.BtnPickEntry.FontColor = c.TextInactive;
            app.BtnPickEntry2.FontColor = c.TextInactive;
            if isprop(app, 'BtnPickEntry3') && isgraphics(app.BtnPickEntry3)
                app.BtnPickEntry3.FontColor = c.TextInactive;
            end

            % 4. Remove Plot Listeners & Reset Cursor
            if isgraphics(app.AxCutLeft), app.AxCutLeft.ButtonDownFcn = [ ]; end
            if isgraphics(app.AxCutRight), app.AxCutRight.ButtonDownFcn = [ ]; end
            app.UIFigure.Pointer = 'arrow';
        end

        function onCutAxesClick(app, ax, ~, side)
            % Purpose: Handles user clicks on the 2D plots to set Start, Entry, or Link points.

            cp = ax.CurrentPoint(1, 1:2);
            clickY = cp(1);
            clickZ = cp(2);

            % --- CASE 1: SET START POINT ---
            if app.BtnPickStart.Value

                chkP = cell(1,4);
                [ chkP{1}, chkP{2}, chkP{3}, chkP{4} ] = app.getSyncedKerfProfiles();
                syncY_L = chkP{1}; syncZ_L = chkP{2}; syncY_R = chkP{3}; syncZ_R = chkP{4};

                yData = [ ];
                zData = [ ];
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

                [ ~, minIdx ] = min(distances);

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

            % Tell the Gatekeeper the user has manually set up the tab!
            app.IsCuttingUserModified = true;
            app.IsCuttingInit = true;
            app.updateCuttingPlots();
        end

        function onSyncToggleChanged(app, src)
            % Purpose: Handles the Start Point coupling toggle.
            if strcmp(src.Value, 'Coupled')
                app.SelectedStartIdxR = app.SelectedStartIdxL;
                app.IsCuttingInit = true;
                app.updateCuttingPlots();
            end
        end

        function onSyncEntryToggleChanged(app, src)
            % Purpose: Handles the Entry Point coupling toggle.
            if strcmp(src.Value, 'Coupled')
                app.EntryPointR = app.EntryPointL;
                app.EntryPoint2R = app.EntryPoint2L;
                app.EntryPoint3R = app.EntryPoint3L;
                app.IsCuttingInit = true;
                app.updateCuttingPlots();
            end
        end

        %%                    - AUTO TOOLS & ACTIONS -
        function onAutoStart(app, doPlot)
            % Purpose: Automatically selects the start point closest to the front of the machine.
            if nargin < 2
                doPlot = true;
            end

            chkP = cell(1,4);
            [ chkP{1}, chkP{2}, chkP{3}, chkP{4} ] = app.getSyncedKerfProfiles();
            yL_b = chkP{1}; yR_b = chkP{3};

            if isempty(yL_b)
                return;
            end

            [ ~, idxL ] = min(yL_b);
            [ ~, idxR ] = min(yR_b);

            if strcmp(app.SwitchSyncStart.Value, 'Coupled')
                app.SelectedStartIdxL = idxL;
                app.SelectedStartIdxR = idxL;
            else
                app.SelectedStartIdxL = idxL;
                app.SelectedStartIdxR = idxR;
            end

            % Tell the Gatekeeper Auto-Start succeeded!
            app.IsCuttingUserModified = false;
            app.IsCuttingInit = true;
            if doPlot
                app.updateCuttingPlots();
            end
        end

        function onAutoEntry(app, doPlot)
            % Purpose: Automatically calculates a safe, perpendicular entry path from outside the billet.
            % HOW: Calculates the normal vector at the start point, extends it outwards until it clears
            %      the billet bounding box, and creates a lead-in point there.

            if nargin < 2
                doPlot = true;
            end

            chkP = cell(1,4);
            [ chkP{1}, chkP{2}, chkP{3}, chkP{4} ] = app.getSyncedKerfProfiles();
            yL = chkP{1}; zL = chkP{2}; yR = chkP{3}; zR = chkP{4};

            if isempty(yL), return; end

            bMinY = app.MachineBilletPos(2);
            bMaxY = app.MachineBilletPos(2) + app.BilletSize(2);
            bMinZ = app.MachineBilletPos(3);
            bMaxZ = app.MachineBilletPos(3) + app.BilletSize(3);

            offY = app.BilletShift(2) + bMinY;
            offZ = app.BilletShift(3) + bMinZ;

            %% --- NESTED HELPER: ENTRY LOGIC ---
            function [ lead, link1, link2 ] = calcEntryLogic(y, z, startIdx)
                lead = [ ]; link1 = [ ]; link2 = [ ];
                N = numel(y);
                if startIdx > N || startIdx < 1, startIdx = 1; end

                idxS = startIdx;
                idxP = mod(startIdx-2, N) + 1;
                idxN = mod(startIdx, N) + 1;

                S =[ y(idxS), z(idxS) ];
                P = [ y(idxP), z(idxP) ];
                N_pt = [ y(idxN), z(idxN) ];

                % Calculate bisecting normal vector
                vIn  = (S - P) / (norm(S - P) + 1e-9);
                vOut = (N_pt - S) / (norm(N_pt - S) + 1e-9);

                vBisect =[ -vIn(2), vIn(1) ] +[ -vOut(2), vOut(1) ];
                if norm(vBisect) < 1e-3
                    vBisect =[ -vIn(2), vIn(1) ];
                end
                vBisect = vBisect / norm(vBisect);

                % Ensure vector points OUTWARD from the polygon
                testPt = S + vBisect * 0.1;
                if inpolygon(testPt(1), testPt(2), y, z)
                    vBisect = -vBisect;
                end

                boxMinY = bMinY - 5.0; boxMaxY = bMaxY + 5.0;
                boxMinZ = bMinZ - 5.0; boxMaxZ = bMaxZ + 5.0;

                t_hits = [ ];
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

                % If the lead point is above or behind the block, route a safe link path over the top
                needsRouting = (lead(2) >= bMaxZ) || (lead(1) >= bMaxY);
                if needsRouting
                    safeZ = bMaxZ + app.MachineSafeHeight;
                    link2 =[ lead(1), max(safeZ, lead(2)) ];
                    link1 =[ bMinY - 10.0, safeZ ];
                end
            end

            yL_s = yL + offY; zL_s = zL + offZ;

            [ eL, l1L, l2L ] = calcEntryLogic(yL_s, zL_s, app.SelectedStartIdxL);

            app.EntryPointL=eL; app.EntryPoint2L=l1L; app.EntryPoint3L=l2L;

            if strcmp(app.SwitchSyncEntry.Value, 'Coupled')
                app.EntryPointR=eL; app.EntryPoint2R=l1L; app.EntryPoint3R=l2L;
            else
                yR_s = yR + offY; zR_s = zR + offZ;

                [ eR, l1R, l2R ] = calcEntryLogic(yR_s, zR_s, app.SelectedStartIdxR);

                app.EntryPointR=eR; app.EntryPoint2R=l1R; app.EntryPoint3R=l2R;
            end

            % Tell the Gatekeeper Auto-Entry succeeded!
            app.IsCuttingUserModified = false;
            app.IsCuttingInit = true;

            if doPlot
                app.updateCuttingPlots();
            end
        end

        function onClearEntries(app)
            % Purpose: Clears all manual entry and link points.
            app.EntryPointL = [ ]; app.EntryPointR = [ ];
            app.EntryPoint2L = [ ]; app.EntryPoint2R = [ ];
            app.EntryPoint3L = [ ]; app.EntryPoint3R = [ ];
            app.IsCuttingInit = true;
            app.updateCuttingPlots();
        end

        %% ===========================================================
        %% --- GROUP 9: TAB 7 - SIMULATION ---
        %% ===========================================================

        %%                    - DATA GENERATION -

        function generateSimulationData(app)
            % Purpose: Generates high-resolution, interpolated 3D paths for the simulation playback.
            % WHY: The raw G-code/toolpath only contains corner points. To animate the wire smoothly,
            %      we must interpolate points at a fixed spatial resolution along the entire path.
            % HOW: Breaks the path into phases (Rapid, Lead-In, Cut, Lead-Out, Return), densifies
            %      each segment, concatenates them, and calculates cumulative arc lengths for timing.

            if isempty(app.AxSim) || ~isgraphics(app.AxSim)
                disp('   -> ERROR: AxSim is missing!'); return;
            end

            t = app.getTheme();
            offsetY = app.BilletShift(2) + app.MachineBilletPos(2);
            offsetZ = app.BilletShift(3) + app.MachineBilletPos(3);
            isCCW   = strcmp(app.SwitchCutDir.Value, 'Bottom (CCW)');

            % Fetch Truth Data
            [ syncY_L, syncZ_L, syncY_R, syncZ_R ] = app.getSyncedKerfProfiles();

            % Apply user start points and direction
            [ yL, zL ] = app.applyMods(syncY_L, syncZ_L, offsetY, offsetZ, app.SelectedStartIdxL, isCCW);
            [ yR, zR ] = app.applyMods(syncY_R, syncZ_R, offsetY, offsetZ, app.SelectedStartIdxR, isCCW);

            if isempty(yL) || isempty(yR)
                uialert(app.UIFigure, 'Could not generate toolpath. Profiles may be empty or invalid.', 'Simulation Error');
                return;
            end

            app.ProfileSyncL =[ yL(:), zL(:) ];
            app.ProfileSyncR =[ yR(:), zR(:) ];

            %% --- NESTED HELPERS: SEGMENT CREATION ---
            function pts = mkRapid(lead, link1, link2)
                pZero=[ 0, 0 ]; pSafe=[ 10, 10 ];
                pLoad=[ app.MachineBilletPos(2), app.MachineBilletPos(3)+app.BilletSize(3)/2 ];
                pRet=[ pLoad(1)-10, pLoad(2) ];
                pts=[ pZero; pSafe; pLoad; pRet ];

                if ~isempty(link1), pts=[ pts; link1 ]; end
                if ~isempty(link2), pts=[ pts; link2 ]; end
                if ~isempty(lead), pts=[ pts; lead ]; end
            end

            function pts = mkLeadIn(start, lead)
                if isempty(lead)
                    pRet=[ app.MachineBilletPos(2)-10, app.MachineBilletPos(3)+app.BilletSize(3)/2 ];
                    pts=[ pRet; start ];
                else
                    pts=[ lead; start ];
                end
            end

            function pts = mkLeadOut(en, lead)
                if isempty(lead)
                    pts=[ en; en ]; % Fallback
                else
                    pts=[ en; lead ];
                end
            end

            function pts = mkReturn(lead, link1, link2)
                if isempty(lead)
                    pts =[ 0, 0 ]; return;
                end
                pts = lead;
                if ~isempty(link2), pts =[ pts; link2 ]; end
                if ~isempty(link1), pts =[ pts; link1 ]; end

                pRetract =[ app.MachineBilletPos(2)-10, app.MachineBilletPos(3)+app.BilletSize(3)/2 ];
                pts =[ pts; pRetract;[ 0, pRetract(2) ]; [ 0, 0 ] ];
            end

            rawRapL = mkRapid(app.EntryPointL, app.EntryPoint2L, app.EntryPoint3L);
            rawRapR = mkRapid(app.EntryPointR, app.EntryPoint2R, app.EntryPoint3R);

            rawLiL = mkLeadIn([ yL(1), zL(1) ], app.EntryPointL);
            rawLiR = mkLeadIn([ yR(1), zR(1) ], app.EntryPointR);

            rawLoL = mkLeadOut([ yL(end), zL(end) ], app.EntryPointL);
            rawLoR = mkLeadOut([ yR(end), zR(end) ], app.EntryPointR);

            rawRetL = mkReturn(app.EntryPointL, app.EntryPoint2L, app.EntryPoint3L);
            rawRetR = mkReturn(app.EntryPointR, app.EntryPoint2R, app.EntryPoint3R);

            %% --- NESTED HELPERS: DENSIFICATION ---
            function [ yLD, zLD, yRD, zRD ] = densifySynced(yiL, ziL, yiR, ziR, step)
                % Interpolates synced profiles ensuring L and R stay perfectly coupled
                if nargin < 5, step = CNCHotWire_GCodeGenerator.SimSpatialResolution; end
                N = numel(yiL);
                if N < 2
                    yLD=yiL; zLD=ziL; yRD=yiR; zRD=ziR; return;
                end
                distL =[ 0; cumsum(hypot(diff(yiL), diff(ziL))) ];
                distR =[ 0; cumsum(hypot(diff(yiR), diff(ziR))) ];

                maxL = distL(end); if maxL < 1e-6, maxL = 1; end
                maxR = distR(end); if maxR < 1e-6, maxR = 1; end

                sL = distL / maxL; sR = distR / maxR;
                s_orig = (sL + sR) / 2;
                totalLen = max(distL(end), distR(end));

                nSteps = max(N, ceil(totalLen / step));
                s_smooth = linspace(0, 1, nSteps)';
                s_combined = unique([ s_orig; s_smooth ]);

                [ su, iu ] = unique(s_orig, 'stable');
                yLD = interp1(su, yiL(iu), s_combined, 'linear');
                zLD = interp1(su, ziL(iu), s_combined, 'linear');
                yRD = interp1(su, yiR(iu), s_combined, 'linear');
                zRD = interp1(su, ziR(iu), s_combined, 'linear');
            end

            function out = densifyWaypoints(yiL, ziL, yiR, ziR, step)
                % Interpolates independent waypoints (like rapid moves)
                if nargin < 5, step = CNCHotWire_GCodeGenerator.SimSpatialResolution; end
                N_max = max(numel(yiL), numel(yiR));

                % Pad arrays if one side has fewer waypoints
                if numel(yiL) < N_max
                    padCount = N_max - numel(yiL);
                    yiL =[ yiL; repmat(yiL(end), padCount, 1) ];
                    ziL =[ ziL; repmat(ziL(end), padCount, 1) ];
                end
                if numel(yiR) < N_max
                    padCount = N_max - numel(yiR);
                    yiR =[ yiR; repmat(yiR(end), padCount, 1) ];
                    ziR =[ ziR; repmat(ziR(end), padCount, 1) ];
                end

                yLD=[ ]; zLD=[ ]; yRD=[ ]; zRD=[ ];
                for i = 1:(N_max-1)
                    d1 = hypot(yiL(i+1)-yiL(i), ziL(i+1)-ziL(i));
                    d2 = hypot(yiR(i+1)-yiR(i), ziR(i+1)-ziR(i));
                    N_pts = max(2, ceil(max(d1, d2) / step));

                    yLD =[ yLD; linspace(yiL(i), yiL(i+1), N_pts)' ];
                    zLD =[ zLD; linspace(ziL(i), ziL(i+1), N_pts)' ];
                    yRD =[ yRD; linspace(yiR(i), yiR(i+1), N_pts)' ];
                    zRD =[ zRD; linspace(ziR(i), ziR(i+1), N_pts)' ];

                    if i < N_max-1
                        yLD(end)=[ ]; zLD(end)=[ ]; yRD(end)=[ ]; zRD(end)=[ ];
                    end
                end
                out.yL = yLD; out.zL = zLD; out.yR = yRD; out.zR = zRD;
            end

            %% --- 3. EXECUTE DENSIFICATION ---
            tmp = densifyWaypoints(rawRapL(:,1), rawRapL(:,2), rawRapR(:,1), rawRapR(:,2));
            dRapL_y = tmp.yL; dRapL_z = tmp.zL; dRapR_y = tmp.yR; dRapR_z = tmp.zR;

            tmp = densifyWaypoints(rawLiL(:,1), rawLiL(:,2), rawLiR(:,1), rawLiR(:,2));
            dLiL_y = tmp.yL; dLiL_z = tmp.zL; dLiR_y = tmp.yR; dLiR_z = tmp.zR;

            [ dProfL_y, dProfL_z, dProfR_y, dProfR_z ] = densifySynced(yL, zL, yR, zR);

            tmp = densifyWaypoints(rawLoL(:,1), rawLoL(:,2), rawLoR(:,1), rawLoR(:,2));
            dLoL_y = tmp.yL; dLoL_z = tmp.zL; dLoR_y = tmp.yR; dLoR_z = tmp.zR;

            tmp = densifyWaypoints(rawRetL(:,1), rawRetL(:,2), rawRetR(:,1), rawRetR(:,2));
            dRetL_y = tmp.yL; dRetL_z = tmp.zL; dRetR_y = tmp.yR; dRetR_z = tmp.zR;

            % Store phase indices so the visualizer knows when to change trail colors
            app.SimRapidCutoffIndex  = numel(dRapL_y);
            app.SimProfileStartIndex = app.SimRapidCutoffIndex + numel(dLiL_y);
            app.SimFeedEndIndex      = app.SimProfileStartIndex + numel(dProfL_y);
            app.SimLeadOutEndIndex   = app.SimFeedEndIndex + numel(dLoL_y);

            fullY_L =[ dRapL_y; dLiL_y; dProfL_y; dLoL_y; dRetL_y ];
            fullZ_L =[ dRapL_z; dLiL_z; dProfL_z; dLoL_z; dRetL_z ];
            fullY_R =[ dRapR_y; dLiR_y; dProfR_y; dLoR_y; dRetR_y ];
            fullZ_R =[ dRapR_z; dLiR_z; dProfR_z; dLoR_z; dRetR_z ];

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

            % Final 3D Paths (Model Coordinates)
            app.SimPathL =[ repmat(xL, numel(fullY_L), 1), fullY_L, fullZ_L ];
            app.SimPathR =[ repmat(xR, numel(fullY_R), 1), fullY_R, fullZ_R ];

            % Calculate Arc Lengths for timing
            dL = sqrt(sum(diff(app.SimPathL).^2, 2)); dL(isnan(dL)) = 0;
            dR = sqrt(sum(diff(app.SimPathR).^2, 2)); dR(isnan(dR)) = 0;
            app.SimArcLenL =[ 0; cumsum(dL) ];
            app.SimArcLenR =[ 0; cumsum(dR) ];
            app.SimTotalLength = max(app.SimArcLenL(end), app.SimArcLenR(end));
            app.SimPlayDist = 0;

            % Project to Towers
            V_vec = app.SimPathR - app.SimPathL;
            tL = -app.SimPathL(:,1) ./ V_vec(:,1);
            tR = (app.MachineSpanX - app.SimPathL(:,1)) ./ V_vec(:,1);
            app.SimTowerPathL = app.SimPathL + tL .* V_vec;
            app.SimTowerPathR = app.SimPathL + tR .* V_vec;

            %% --- 4. CALCULATE PROGRAM BOUNDS ---
            % We only look at points from the start of Lead-In to the end of Lead-Out
            progIdx = (app.SimRapidCutoffIndex):app.SimLeadOutEndIndex;

            workL = app.SimTowerPathL(progIdx, :);
            workR = app.SimTowerPathR(progIdx, :);

            % Tower L (Visual X/Y in G-code)
            app.TowerL_Bounds =[ min(workL(:,2)), max(workL(:,2)), min(workL(:,3)), max(workL(:,3)) ];
            % Tower R (Visual Z/A in G-code)
            app.TowerR_Bounds =[ min(workR(:,2)), max(workR(:,2)), min(workR(:,3)), max(workR(:,3)) ];

            % Update UI Labels
            if isgraphics(app.LblSimExtMin)
                app.LblSimExtMin.Text = sprintf('Min: X=%.2f  Y=%.2f  Z=%.2f  A=%.2f', ...
                    app.TowerL_Bounds(1), app.TowerL_Bounds(3), app.TowerR_Bounds(1), app.TowerR_Bounds(3));

                app.LblSimExtMax.Text = sprintf('Max: X=%.2f Y=%.2f Z=%.2f A=%.2f', ...
                    app.TowerL_Bounds(2), app.TowerL_Bounds(4), app.TowerR_Bounds(2), app.TowerR_Bounds(4));

                app.LblSimExtWire.Text = sprintf('Max Wire Extension:%.2fmm (Limit:%.0fmm)', ...
                    app.MaxPathExtension, app.WireExt_Red);
            end

            nPoints = size(app.SimPathL, 1);
            app.SimSlider.Limits =[ 1, max(1, nPoints) ];
            app.SimSlider.Value = 1;

            if isprop(app, 'SimIndexSpinner') && ~isempty(app.SimIndexSpinner)
                app.SimIndexSpinner.Limits =[ 1, max(1, nPoints) ];
                app.SimIndexSpinner.Value = 1;
            end

            app.initSimulationPlot();
        end

        function idx = simIndexAtDistance(app, dist)
            % Purpose: Returns the simulation array index corresponding to a physical distance.
            % WHY: Required so the slider can scrub through the animation based on distance traveled.

            dist = max(0, min(dist, app.SimTotalLength));

            if isempty(app.SimArcLenL) || isempty(app.SimArcLenR)
                idx = 1;
                return;
            end

            % Identify which tower path dictates the total length (important for Tapered cuts)
            lenL = app.SimArcLenL(end);
            lenR = app.SimArcLenR(end);

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

        %%                    - PLOTTING & VISUALIZATION -

        function initSimulationPlot(app)
            % Purpose: Initializes the 3D simulation plot with static geometry
            %          (bed, towers, billet, model) and empty dynamic graphics objects.
            % WHY: Drawing static objects once and only updating the X/Y/Z data of
            %      dynamic objects is required for smooth 25fps animation.

            ax = app.AxSim;
            cla(ax);
            hold(ax,'on');
            t = app.getTheme();

            offX = app.MachineBedPos(1);
            mSpan = app.MachineSpanX;
            bp = app.MachineBilletPos;
            bSize = app.BilletSize;
            bs = app.MachineBedSize;

            % 1. Draw Static Machine Components
            [ xb, yb, zb ] = app.makeBoxVertices(0, app.MachineBedPos(2), -bs(3), bs(1), bs(2), bs(3));
            patch(ax, 'Vertices',[ xb, yb, zb ], 'Faces', app.boxFaces, 'FaceColor', t.bedCol, 'FaceAlpha', 0.5, 'EdgeColor', t.bedEdge);

            patch(ax, 'XData', ones(4,1)*(-offX), 'YData',[ 0; 750; 750; 0 ], 'ZData',[ 0; 0; 500; 500 ], 'FaceColor', t.planeRed, 'FaceAlpha', 0.15, 'EdgeColor', t.planeRed);
            patch(ax, 'XData', ones(4,1)*(mSpan-offX), 'YData',[ 0; 750; 750; 0 ], 'ZData',[ 0; 0; 500; 500 ], 'FaceColor', t.planeGreen, 'FaceAlpha', 0.15, 'EdgeColor', t.planeGreen);

            text(ax, -offX, 750*0.98, 500*0.92, {' LEFT',' TOWER'}, 'Color', t.planeRedTxt, 'FontWeight', 'bold', 'FontSize', 9);
            text(ax, mSpan-offX, 750*0.02, 500*0.92, {'RIGHT','TOWER '}, 'Color', t.planeGreenTxt, 'FontWeight', 'bold', 'HorizontalAlignment', 'right', 'FontSize', 9);

            % 2. Draw Billet & Model
            bX = bp(1)-offX; bY = bp(2); bZ = bp(3);

            if bZ > 0
                [ xPack, yPack, zPack ] = app.makeBoxVertices(bX, bY, 0, bSize(1), bSize(2), bZ);
                patch(ax, 'Vertices',[ xPack, yPack, zPack ], 'Faces', app.boxFaces, ...
                    'FaceColor',[ 0.25 0.25 0.25 ], 'FaceAlpha', 0.9, 'EdgeColor', t.bedEdge, 'LineStyle', '-', 'Tag', 'SimPackingBlock');
            end

            [ xm, ym, zm ] = app.makeBoxVertices(bX, bY, bZ, bSize(1), bSize(2), bSize(3));
            patch(ax, 'Vertices',[ xm, ym, zm ], 'Faces', app.boxFaces, 'FaceColor', t.billetColor, 'FaceAlpha', t.billetAlpha, 'EdgeColor', t.billetLine, 'LineStyle', '-', 'LineWidth', 0.5, 'EdgeAlpha', 0.5);

            if ~isempty(app.ModelPatch)
                patch(ax, 'Vertices', app.ModelPatch.Vertices +[ bX, bY, bZ ] + app.BilletShift, 'Faces', app.ModelPatch.Faces, ...
                    'FaceColor', t.modelColor, 'FaceAlpha', t.modelAlpha, 'EdgeColor', 'none', 'Tag', 'SimModel');
            end

            % 3. Draw Ghost Profiles (Raw extracted profiles in neutral grey)
            if ~isempty(app.LeftProfilePoints) && ~isempty(app.RightProfilePoints)
                [ yS_rawL, zS_rawL, yS_rawR, zS_rawR ] = CNCHotWire_GCodeGenerator_Helpers.syncPointCounts(...
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

            % 4. Initialize Dynamic Elements (Empty objects with Tags)
            plot3(ax, NaN, NaN, NaN, 'Color', t.wireKerf, 'LineWidth', 0.5, 'Tag', 'SimWire');
            plot3(ax, NaN, NaN, NaN, 'Color', t.planeRed, 'LineWidth', 0.6, 'Tag', 'SimTensionWire');
            plot3(ax, NaN, NaN, NaN, 'o', 'MarkerFaceColor', t.wireLead, 'MarkerEdgeColor', t.wireLead, 'MarkerSize', 2, 'Tag', 'SimBrassJoint');

            plot3(ax, NaN, NaN, NaN, 'o', 'Color', t.planeRed, 'MarkerEdgeColor', t.planeRed, 'MarkerFaceColor', t.planeRed, 'MarkerSize', 2, 'Tag', 'SimDotL');
            plot3(ax, NaN, NaN, NaN, 'o', 'Color', t.planeGreen, 'MarkerEdgeColor', t.planeGreen, 'MarkerFaceColor', t.planeGreen, 'MarkerSize', 2, 'Tag', 'SimDotR');

            plot3(ax, NaN, NaN, NaN, 'o', 'Color', t.planeRed, 'MarkerEdgeColor', t.planeRed, 'MarkerFaceColor', t.planeRed, 'MarkerSize', 2, 'Tag', 'SimModelDotL');
            plot3(ax, NaN, NaN, NaN, 'o', 'Color', t.planeGreen, 'MarkerEdgeColor', t.planeGreen, 'MarkerFaceColor', t.planeGreen, 'MarkerSize', 2, 'Tag', 'SimModelDotR');

            tags = {'Rapid','LeadIn','Feed','LeadOut','Return'};
            cols = {[ 0.9 0.8 0 ], t.wireLead, t.planeRed, t.wireLead,[ 0.9 0.8 0 ]};
            styles = {'-','-','-','--','--'};

            for i=1:5
                colL = cols{i}; colR = cols{i};
                if i==3
                    colL = t.planeRed; colR = t.planeGreen;
                end

                plot3(ax, NaN, NaN, NaN, styles{i}, 'Color', colL, 'LineWidth', 0.5, 'Tag', ['SimTower' tags{i} 'L']);
                plot3(ax, NaN, NaN, NaN, styles{i}, 'Color', colR, 'LineWidth', 0.5, 'Tag',['SimTower' tags{i} 'R']);

                plot3(ax, NaN, NaN, NaN, styles{i}, 'Color', colL, 'LineWidth', 0.5, 'Tag',['SimModel' tags{i} 'L']);
                plot3(ax, NaN, NaN, NaN, styles{i}, 'Color', colR, 'LineWidth', 0.5, 'Tag',['SimModel' tags{i} 'R']);
            end

            app.updateSimVisuals(1);
            app.onResetSimViewMachine();
        end

        function updateSimVisuals(app, idx)
            % Purpose: The core animation loop. Updates coordinates of existing plot objects.
            % HOW: Finds objects by Tag and replaces their X/Y/Z data arrays.

            if isempty(app.SimPathL), return; end
            idx = max(1, min(idx, size(app.SimPathL,1)));
            offX = app.MachineBedPos(1);

            % Update Wire & Dots
            pTL = app.SimTowerPathL(idx,:) - [ offX, 0, 0 ];
            pTR = app.SimTowerPathR(idx,:) - [ offX, 0, 0 ];

            % Calculate Brass Joint Position (Fixed length hot wire)
            wireVec = pTR - pTL;
            wireLen = norm(wireVec);
            L_hot = (app.MachineBedPos(1) + app.MachineBedSize(1)) + app.BrassJointOffsetRight;
            pJoint = pTL + wireVec * (L_hot / wireLen);

            set(findobj(app.AxSim,'Tag','SimWire'), 'XData',[ pTL(1) pJoint(1) ], 'YData',[ pTL(2) pJoint(2) ], 'ZData',[ pTL(3) pJoint(3) ]);
            set(findobj(app.AxSim,'Tag','SimTensionWire'), 'XData',[ pJoint(1) pTR(1) ], 'YData',[ pJoint(2) pTR(2) ], 'ZData',[ pJoint(3) pTR(3) ]);
            set(findobj(app.AxSim,'Tag','SimBrassJoint'), 'XData', pJoint(1), 'YData', pJoint(2), 'ZData', pJoint(3));

            set(findobj(app.AxSim,'Tag','SimDotL'), 'XData', pTL(1), 'YData', pTL(2), 'ZData', pTL(3));
            set(findobj(app.AxSim,'Tag','SimDotR'), 'XData', pTR(1), 'YData', pTR(2), 'ZData', pTR(3));

            % Update Model Profile Dots
            pML = app.SimPathL(idx,:) - [ offX, 0, 0 ];
            pMR = app.SimPathR(idx,:) -[ offX, 0, 0 ];
            set(findobj(app.AxSim,'Tag','SimModelDotL'), 'XData', pML(1), 'YData', pML(2), 'ZData', pML(3));
            set(findobj(app.AxSim,'Tag','SimModelDotR'), 'XData', pMR(1), 'YData', pMR(2), 'ZData', pMR(3));

            % Nested Helper for Trails
            function upT(tag, data, s, e)
                h = findobj(app.AxSim,'Tag',tag);
                if ~isempty(h)
                    if s > e
                        h.XData =[ ]; h.YData =[ ]; h.ZData =[ ];
                    else
                        dt = data(s:e,:) - [ offX, 0, 0 ];
                        h.XData = dt(:,1); h.YData = dt(:,2); h.ZData = dt(:,3);
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

                % Draw from start up to current idx (clamped by limit)
                if idx > startIdx
                    currEnd = min(idx, endLimit);
                    upT(['SimTower' tagName 'L'], app.SimTowerPathL, startIdx, currEnd);
                    upT(['SimTower' tagName 'R'], app.SimTowerPathR, startIdx, currEnd);
                    upT(['SimModel' tagName 'L'], app.SimPathL, startIdx, currEnd);
                    upT(['SimModel' tagName 'R'], app.SimPathR, startIdx, currEnd);
                else
                    % Clear if not reached yet
                    upT(['SimTower' tagName 'L'],[ ], 1, 0);
                    upT(['SimTower' tagName 'R'],[ ], 1, 0);
                    upT(['SimModel' tagName 'L'],[ ], 1, 0);
                    upT(['SimModel' tagName 'R'],[ ], 1, 0);
                end
            end

            % Update UI Readouts
            app.LblReadoutX.Text = sprintf('%.2f', pTL(2));
            app.LblReadoutY.Text = sprintf('%.2f', pTL(3));
            app.LblReadoutZ.Text = sprintf('%.2f', pTR(2));
            app.LblReadoutA.Text = sprintf('%.2f', pTR(3));

            % Calculate live extension
            dy = pTL(2) - pTR(2);
            dz = pTL(3) - pTR(3);
            ext = hypot(app.MachineSpanX, hypot(dy, dz)) - app.MachineSpanX;
            app.SimGaugeExt.Value = min(ext, app.SimGaugeExt.Limits(2));
        end

        function onResetSimViewMachine(app)
            app.resetViewToMachine(app.AxSim);
        end

        function onResetSimViewBillet(app)
            app.resetViewToBillet(app.AxSim);
        end

        %%                    - PLAYBACK CONTROLS -

        function onSimPlay(app)
            % Purpose: Starts the real-time simulation timer.
            if isempty(app.SimPathL), return; end
            if app.SimPlayDist >= app.SimTotalLength - 1e-3, app.SimPlayDist = 0; end

            if isempty(app.SimTimer) || ~isvalid(app.SimTimer)
                periodSec = 1.0 / CNCHotWire_GCodeGenerator.SimFramesPerSecond;
                app.SimTimer = timer('ExecutionMode', 'fixedRate', 'Period', periodSec, 'TimerFcn', @(~,~)app.onSimTimerTick());
            end
            if strcmp(app.SimTimer.Running, 'off')
                start(app.SimTimer);
                app.SimPlayBtn.Enable = 'off';
            end
        end

        function onSimPause(app)
            % Purpose: Pauses the simulation timer.
            if ~isempty(app.SimTimer) && isvalid(app.SimTimer), stop(app.SimTimer); end
            app.SimPlayBtn.Enable = 'on';
        end

        function onSimStop(app)
            % Purpose: Stops the timer and resets the playback distance to 0.
            app.onSimPause();
            app.SimPlayDist = 0;
            app.syncSimControls(1);
            app.updateSimVisuals(1);
        end

        function onSimTimerTick(app)
            % Purpose: Timer callback. Advances the playback distance based on feed rate and speed multiplier.

            if ~isempty(app.SpinFeedRate) && isgraphics(app.SpinFeedRate)
                feed_mm_min = app.SpinFeedRate.Value;
            else
                feed_mm_min = CNCHotWire_GCodeGenerator.DefaultFeedRate;
            end

            feed_mm_sec = feed_mm_min / 60.0;
            periodSec = 1.0 / CNCHotWire_GCodeGenerator.SimFramesPerSecond;
            baseStepDist = feed_mm_sec * periodSec;

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

        %%                    - UI SYNC & SCRUBBING -

        function onSimSliderChanging(app, src)
            % Purpose: Handles user scrubbing the timeline slider.
            idx = round(src.Value);
            app.setSimFromIndex(idx);
        end

        function onSimIndexSpinnerChanged(app, src)
            % Purpose: Handles user typing a specific index into the spinner.
            idx = round(src.Value);
            app.setSimFromIndex(idx);
        end

        function setSimFromIndex(app, idx)
            % Purpose: Updates simulation state based on a specific index.
            if isempty(app.SimPathL), return; end
            idx = max(1, min(idx, size(app.SimPathL, 1)));

            lenL = 0; lenR = 0;
            if ~isempty(app.SimArcLenL), lenL = app.SimArcLenL(end); end
            if ~isempty(app.SimArcLenR), lenR = app.SimArcLenR(end); end

            if lenR > lenL
                targetArr = app.SimArcLenR;
            else
                targetArr = app.SimArcLenL;
            end

            if idx <= numel(targetArr)
                app.SimPlayDist = targetArr(idx);
            else
                app.SimPlayDist = app.SimTotalLength;
            end

            app.syncSimControls(idx);
            app.updateSimVisuals(idx);
        end

        function syncSimControls(app, idx)
            % Purpose: Updates UI elements to match index (Visual sync only).
            app.SimSlider.Value = idx;
            if isprop(app, 'SimIndexSpinner') && ~isempty(app.SimIndexSpinner)
                app.SimIndexSpinner.Value = idx;
            end
        end

        %% ===========================================================
        %% --- GROUP 10: TAB 8 - POST-PROCESSING ---
        %% ===========================================================

        %%                    - UI & STATUS UPDATES -

        function updatePostProcessUI(app)
            % Purpose: Auto-fills the default G-code filename based on the imported CAD model.

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

            app.updatePostStatus();
        end

        function updatePostStatus(app, isFreshPost)
            % Purpose: Evaluates the safety and freshness of the G-code parameters.
            % WHY: If the user changes the feed rate or power *after* generating G-code,
            %      the existing G-code becomes stale and must be regenerated.

            if nargin < 2, isFreshPost = false; end
            if isempty(app.TxtPostStatus) || ~isvalid(app.TxtPostStatus), return; end

            t = app.getTheme();
            feed = app.SpinFeedRate.Value;
            power = app.SpinPower.Value;

            % 1. Logic: If parameters changed (not a fresh post), invalidate old code
            if ~isFreshPost && ~isempty(app.PP_GCodeLines)
                app.PP_GCodeLines = strings(0);
                app.ListGCode.Items = {'(Parameters changed. Re-run Post-Process...)'};
                app.BtnSaveGCode.Enable = 'off';
                app.BtnSaveGCode.BackgroundColor =[ 0.3 0.3 0.3 ];
                app.BtnSaveGCode.FontColor =[ 0.8 0.8 0.8 ];
            end

            msg = strings(0);
            panelBg = t.sideBg;
            textCol = t.labelCol;

            % 2. Determine Status State
            if isempty(app.PP_GCodeLines)
                panelBg = t.statErrBg;
                textCol = t.statErrTxt;
                msg =[ "STALE G-CODE:", "Parameters changed. Re-run Post-Process." ];
            else
                panelBg = t.statPassBg;
                textCol = t.statPassTxt;
                msg(end+1) = sprintf("Success! Generated %d lines.", numel(app.PP_GCodeLines));
            end

            % 3. Apply Safety Overrides (Priority: Red > Amber)
            isExtRed   = app.MaxPathExtension > app.WireExt_Red;
            isExtAmber = app.MaxPathExtension > app.WireExt_Amber;

            if isExtRed
                panelBg = t.statErrBg;
                textCol = t.statErrTxt;
                msg(end+1) = "CRITICAL: Wire Extension exceeds pulley travel!";
            elseif isExtAmber
                if ~isequal(panelBg, t.statErrBg)
                    panelBg = t.statWarnBg;
                    textCol = t.statWarnTxt;
                end
                msg(end+1) = "WARNING: Approaching mechanical pulley limit.";
            end

            % Check Feed/Power Balance
            if (power < 25 && feed > 80) || (power > 80 && feed < 30)
                if ~isequal(panelBg, t.statErrBg)
                    panelBg = t.statWarnBg;
                    textCol = t.statWarnTxt;
                end
                msg(end+1) = "WARNING: Unbalanced Power/Feed settings.";
            end

            if ~isempty(app.PP_GCodeLines)
                msg(end+1) = "Verify paths and click Save.";
            end

            app.PostLeftPanel.BackgroundColor = panelBg;
            app.TxtPostStatus.Value = msg;
            app.TxtPostStatus.FontColor = textCol;
        end

        function onFilenameChanged(app, src)
            % Purpose: Sanitizes the filename input to prevent OS-level save errors.
            % WHY: Windows and macOS reserve certain characters. If included, fopen() will fail.

            rawName = string(src.Value);

            % Regex pattern for invalid OS filename characters: < > : " / \ | ? *
            invalidPattern = '[<>:"/\\|?*]';

            % Replace any invalid characters with an underscore
            cleanName = regexprep(rawName, invalidPattern, '_');

            % If the name had to be changed, update the UI and notify the user
            if rawName ~= cleanName
                src.Value = cleanName;
                uialert(app.UIFigure, 'Invalid characters (< > : " / \ | ? *) were replaced with underscores.', 'Filename Sanitized', 'Icon', 'info');
            end

            % Trigger the standard status validation (invalidates old G-code if name changed)
            app.updatePostStatus();
        end

        %%                    - G-CODE GENERATION -

        function onPostProcess(app)
            % Purpose: Generates the final Mach4-compatible G-code.
            % HOW: Iterates through the densified simulation path, converting absolute
            %      machine coordinates into G-code strings. Also calculates Dynamic Feed
            %      rates for tapered cuts to ensure constant wire speed through the foam.

            if isempty(app.SimPathL) || isempty(app.ProfileSyncL)
                app.generateSimulationData();
                if isempty(app.SimPathL)
                    uialert(app.UIFigure, 'No path data available.', 'Error');
                    return;
                end
            end

            % Initialize storage arrays
            app.PP_PathL = zeros(0,3);
            app.PP_PathR = zeros(0,3);
            app.PP_TowerPathL = zeros(0,3);
            app.PP_TowerPathR = zeros(0,3);

            feed  = round(app.SpinFeedRate.Value);
            power = round(app.SpinPower.Value);
            lines = strings(0,1);
            map = zeros(0,1);
            pathIdx = 0;

            % Alignment constants
            baseX = app.MachineBilletPos(1) + app.BilletShift(1) + app.ModelXMin;
            xM_L = baseX + app.NumLeftOffset.Value;
            xM_R = baseX + app.NumRightOffset.Value;
            xT_L = 0;
            xT_R = app.MachineSpanX;

            mDim =[ abs(xM_R - xM_L), app.ModelYMax - app.ModelYMin, app.ModelZMax - app.ModelZMin ];

            % Nested Helper 1: Project Model YZ to Tower Coordinates
            function [ tx, ty, tz, ta ] = project(yL, zL, yR, zR)
                rL = (xT_L - xM_L) / (xM_R - xM_L);
                tyL = yL + (yR - yL) * rL;
                tzL = zL + (zR - zL) * rL;
                rR = (xT_R - xM_L) / (xM_R - xM_L);
                tyR = yL + (yR - yL) * rR;
                tzR = zL + (zR - zL) * rR;
                tx = tyL; ty = tzL; tz = tyR; ta = tzR;
            end

            % Nested Helper 2: Reverse Project for Verification Plotting
            function[ mxL, myL, mzL, mxR, myR, mzR ] = machineToModelVisual(tx, ty, tz, ta)
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
                    pathIdx = pathIdx + 1;
                    app.PP_TowerPathL(pathIdx,:) =[ xT_L, tx, ty ];
                    app.PP_TowerPathR(pathIdx,:) =[ xT_R, tz, ta ];

                    [ mxL, myL, mzL, mxR, myR, mzR ] = machineToModelVisual(tx, ty, tz, ta);

                    app.PP_PathL(pathIdx,:) =[ mxL, myL, mzL ];
                    app.PP_PathR(pathIdx,:) =[ mxR, myR, mzR ];
                end

                % Map this line of G-code to the last known path position
                map(end+1) = max(1, pathIdx);
            end

            % Nested Helper 4: Dynamic Feed G1 Move
            function addDynamicG1(targL, tgtR, prevL, prevR, commentStr)
                [ tx, ty, tz, ta ] = project(targL(1), targL(2), tgtR(1), tgtR(2));
                [ px, py, pz, pa ] = project(prevL(1), prevL(2), prevR(1), prevR(2));

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

            %% --- EXECUTE G-CODE GENERATION ---
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
                [ tx, ty, tz, ta ] = project(e2L(1), e2L(2), e2R(1), e2R(2));
                add(sprintf('G0 X%.3f Y%.3f Z%.3f A%.3f', tx, ty, tz, ta), 'Link Point 1', tx, ty, tz, ta);
            end
            if ~isempty(e3L)
                [ tx, ty, tz, ta ] = project(e3L(1), e3L(2), e3R(1), e3R(2));
                add(sprintf('G0 X%.3f Y%.3f Z%.3f A%.3f', tx, ty, tz, ta), 'Link Point 2', tx, ty, tz, ta);
            end
            if ~isempty(e1L)
                [ tx, ty, tz, ta ] = project(e1L(1), e1L(2), e1R(1), e1R(2));
                add(sprintf('G0 X%.3f Y%.3f Z%.3f A%.3f', tx, ty, tz, ta), 'Rapid to Entry Point', tx, ty, tz, ta);
            end
            app.PP_RapidEndIndex = pathIdx;

            % Heat Sequence
            add(sprintf('S%d', power), 'Sets Hot Wire Power');
            add('M301', 'Extraction ON > Wait 5s > Power ON');
            add(sprintf('F%d', feed), 'Set Cut Feedrate');

            % Lead-In Cut
            startL = pSyncL(1,:); startR = pSyncR(1,:);
            if ~isempty(e1L)
                addDynamicG1(startL, startR, e1L, e1R, 'Lead-In Cut to Profile');
            else
                prevL =[ bY_Ret, bZ ]; prevR =[ bY_Ret, bZ ];
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
                [ tx, ty, tz, ta ] = project(e3L(1), e3L(2), e3R(1), e3R(2));
                add(sprintf('G0 X%.3f Y%.3f Z%.3f A%.3f', tx, ty, tz, ta), 'Return to Link 2', tx, ty, tz, ta);
            end
            if ~isempty(e2L)
                [ tx, ty, tz, ta ] = project(e2L(1), e2L(2), e2R(1), e2R(2));
                add(sprintf('G0 X%.3f Y%.3f Z%.3f A%.3f', tx, ty, tz, ta), 'Return to Link 1', tx, ty, tz, ta);
            end

            bY_RetFinal = app.MachineBilletPos(2) - 10.0;
            bZ_RetFinal = app.MachineBilletPos(3) + app.BilletSize(3) / 2.0;
            [ tx, ty, tz, ta ] = project(bY_RetFinal, bZ_RetFinal, bY_RetFinal, bZ_RetFinal);
            add(sprintf('G0 X%.3f Y%.3f Z%.3f A%.3f', tx, ty, tz, ta), 'Retract Safety', tx, ty, tz, ta);

            % --- FINAL RETURN ---
            add('G53 G0 X0 Z0', 'Retract Horizontals', 0, bZ_RetFinal, 0, bZ_RetFinal);
            add('G53 G0 Y0 A0', 'Retract Verticals', 0, 0, 0, 0);
            add('M30', 'End Program');

            % --- FINALIZE METADATA ---
            minX_v = app.TowerL_Bounds(1); maxX_v = app.TowerL_Bounds(2);
            minY_v = app.TowerL_Bounds(3); maxY_v = app.TowerL_Bounds(4);
            minZ_v = app.TowerR_Bounds(1); maxZ_v = app.TowerR_Bounds(2);
            minA_v = app.TowerR_Bounds(3); maxA_v = app.TowerR_Bounds(4);

            mStr = sprintf('%% Extents Min: X=%.2f Y=%.2f Z=%.2f A=%.2f', minX_v, minY_v, minZ_v, minA_v);
            MStr = sprintf('%% Extents Max: X=%.2f Y=%.2f Z=%.2f A=%.2f', maxX_v, maxY_v, maxZ_v, maxA_v);
            EStr = sprintf('%% Max Wire Extension: %.2f mm (Limit: %.0f mm)', app.MaxPathExtension, app.WireExt_Red);

            lines = replace(lines, '%%EXTENTS_MIN%%', mStr);
            lines = replace(lines, '%%EXTENTS_MAX%%', MStr);
            lines = replace(lines, '%%WIRE_EXTENSION_MAX%%', EStr);

            % Update UI
            app.PP_GCodeLines = lines;
            app.PP_LineToPathIndex = map;
            app.ListGCode.Items = cellstr(lines);
            app.ListGCode.ItemsData = 1:numel(lines);
            app.ListGCode.Value = 1;

            app.BtnSaveGCode.Enable = 'on';
            app.BtnSaveGCode.BackgroundColor =[ 0.1 0.6 0.1 ];
            app.BtnSaveGCode.FontColor =[ 1 1 1 ];

            if isempty(app.AxSim.Children), app.initSimulationPlot(); end
            app.initPostPlot();

            app.onResetPostViewMachine();
            app.updatePostPlotForSelectedLine(1);
            app.updatePostStatus(true);
        end

        %%                    - INTERACTIVE VIEWER & PLOTTING -

        function initPostPlot(app)
            % Purpose: Clones the 3D scene from the Simulation tab into the Post tab.
            % WHY: Avoids rebuilding the complex static geometry twice.

            axP = app.AxPost;
            cla(axP); hold(axP,'on');

            if isempty(app.AxSim) || ~isvalid(app.AxSim)
                error('AxSim invalid - cannot clone simulation scene.');
            end

            if isempty(app.AxSim.Children)
                app.initSimulationPlot();
            end

            copyobj(app.AxSim.Children, axP);

            % Rename Sim* tags to Post* tags
            h = findall(axP, '-property', 'Tag');
            for i = 1:numel(h)
                tg = string(h(i).Tag);
                if startsWith(tg, "Sim")
                    h(i).Tag = "Post" + extractAfter(tg, 3);
                end
            end

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
        end

        function updatePostPlotForSelectedLine(app, k)
            % Purpose: Updates the 3D plot to show the wire position for a specific G-code line.
            % HOW: Uses the PP_LineToPathIndex map to find the corresponding 3D coordinate.

            if isempty(app.PP_LineToPathIndex) || isempty(app.PP_PathL) || isempty(app.PP_TowerPathL)
                return;
            end

            k = max(1, min(k, numel(app.PP_LineToPathIndex)));
            idx = app.PP_LineToPathIndex(k);

            % Handle non-movement lines (scroll back to last known position)
            kk = k;
            while (isnan(idx) || idx <= 0) && kk > 1
                kk = kk - 1;
                idx = app.PP_LineToPathIndex(kk);
            end
            if isnan(idx) || idx <= 0, idx = 1; end
            idx = min(idx, size(app.PP_PathL,1));

            ax = app.AxPost;
            offX = app.MachineBedPos(1);

            idxRapidEnd   = app.PP_RapidEndIndex;
            idxProfStart  = app.PP_ProfileStartIndex;
            idxProfEnd    = app.PP_ProfileEndIndex;
            idxLeadOutEnd = app.PP_LeadOutEndIndex;

            towerL = app.PP_TowerPathL; towerR = app.PP_TowerPathR;
            pathL  = app.PP_PathL; pathR  = app.PP_PathR;

            % Update Dots & Wire
            pTL =[ towerL(idx,1) - offX, towerL(idx,2), towerL(idx,3) ];
            pTR =[ towerR(idx,1) - offX, towerR(idx,2), towerR(idx,3) ];
            pML =[ pathL(idx,1) - offX, pathL(idx,2), pathL(idx,3) ];
            pMR =[ pathR(idx,1) - offX, pathR(idx,2), pathR(idx,3) ];

            wireVec = pTR - pTL;
            wireLen = norm(wireVec);
            L_hot = (app.MachineBedPos(1) + app.MachineBedSize(1)) + app.BrassJointOffsetRight;
            pJoint = pTL + wireVec * (L_hot / wireLen);

            set(findobj(ax,'Tag','PostWire'), 'XData',[ pTL(1) pJoint(1) ], 'YData',[ pTL(2) pJoint(2) ], 'ZData',[ pTL(3) pJoint(3) ]);
            set(findobj(ax,'Tag','PostTensionWire'), 'XData',[ pJoint(1) pTR(1) ], 'YData',[ pJoint(2) pTR(2) ], 'ZData',[ pJoint(3) pTR(3) ]);
            set(findobj(ax,'Tag','PostBrassJoint'), 'XData',pJoint(1), 'YData',pJoint(2), 'ZData',pJoint(3));

            set(findobj(ax,'Tag','PostDotL'), 'XData',pTL(1), 'YData',pTL(2), 'ZData',pTL(3));
            set(findobj(ax,'Tag','PostDotR'), 'XData',pTR(1), 'YData',pTR(2), 'ZData',pTR(3));
            set(findobj(ax,'Tag','PostModelDotL'), 'XData',pML(1), 'YData',pML(2), 'ZData',pML(3));
            set(findobj(ax,'Tag','PostModelDotR'), 'XData',pMR(1), 'YData',pMR(2), 'ZData',pMR(3));

            % Nested Helper for Trails
            function updateT(tag, data, s, e)
                h = findobj(ax, 'Tag', tag);
                if ~isempty(h)
                    s = max(1, min(s, size(data,1))); e = max(1, min(e, size(data,1)));
                    if e < s, h.XData=[ ]; h.YData=[ ]; h.ZData=[ ]; return; end
                    dt = data(s:e,:);
                    h.XData = dt(:,1) - offX; h.YData = dt(:,2); h.ZData = dt(:,3);
                end
            end

            function clearT(tags)
                for ii=1:numel(tags)
                    h=findobj(ax,'Tag',tags{ii}); if ~isempty(h), h.XData=[ ]; h.YData=[ ]; h.ZData=[ ]; end
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

        function onPostLineSelected(app, src)
            % Purpose: Triggered when the user clicks a line in the G-code listbox.
            val = src.Value;
            if isempty(val), return; end
            app.PP_SelectedLine = val;
            app.updatePostPlotForSelectedLine(val);
        end

        function stepPostLine(app, delta)
            % Purpose: Steps the G-code viewer forward or backward by a set amount.
            if isempty(app.ListGCode.ItemsData), return; end

            n = numel(app.ListGCode.ItemsData);
            cur = app.PP_SelectedLine;
            if isempty(cur) || cur < 1, cur = 1; end

            nxt = max(1, min(n, cur + delta));
            app.PP_SelectedLine = nxt;
            app.ListGCode.Value = nxt;
            app.updatePostPlotForSelectedLine(nxt);
        end

        function onKeyPress(app, ~, event)
            % Purpose: Allows the user to scrub through the G-code using keyboard arrows.
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

        %%                    - FILE EXPORT -

        function onSaveGCode(app)
            % Purpose: Writes the generated G-code array to a physical .tap or .nc file.

            if isempty(app.PP_GCodeLines)
                uialert(app.UIFigure, 'No G-code generated yet. Please click "Post-Process" first.', 'Save Error');
                return;
            end

            filter = {'*.tap', 'Mach4 G-Code (*.tap)'; ...
                '*.nc',  'Standard G-Code (*.nc)'; ...
                '*.txt', 'Text File (*.txt)'};

            defaultName = app.FieldFilename.Value;

            [ file, path ] = uiputfile(filter, 'Save Toolpath', defaultName);

            if isequal(file, 0), return; end

            fullPath = fullfile(path, file);

            try
                fid = fopen(fullPath, 'w');
                if fid == -1
                    error('Could not create file. Check permissions.');
                end

                % Write Header Delimiter
                fprintf(fid, '%%\r\n');

                % Write G-Code Lines with Windows Line Endings (CRLF) required by Mach4
                for i = 1:numel(app.PP_GCodeLines)
                    lineStr = app.PP_GCodeLines(i);
                    fprintf(fid, '%s\r\n', lineStr);
                end

                % Write Footer Delimiter
                fprintf(fid, '%%\r\n');
                fclose(fid);

                uialert(app.UIFigure,['File saved successfully:' newline fullPath], 'Saved', 'Icon','success');

            catch ME
                if exist('fid', 'var') && fid > -1, fclose(fid); end
                uialert(app.UIFigure, ['Error saving file:' newline ME.message], 'File Error');
            end
        end


        %% ===========================================================
        %% --- GROUP 11: SHARED GRAPHICS & THEME HELPERS ---
        %% ===========================================================
        %%                    - GRAPHICS CLEARING HELPERS -

        function clearPlanes(app)
            % Purpose: Deletes any existing 3D plane graphics and resets handles.
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
            % Purpose: Deletes any existing 3D profile graphics and clears stored data.
            if ~isempty(app.LeftProfileLine3D) && isgraphics(app.LeftProfileLine3D)
                delete(app.LeftProfileLine3D);
            end
            if ~isempty(app.RightProfileLine3D) && isgraphics(app.RightProfileLine3D)
                delete(app.RightProfileLine3D);
            end

            app.LeftProfileLine3D  = gobjects(0);
            app.RightProfileLine3D = gobjects(0);
            app.LeftProfilePoints  = zeros(0,3);
            app.RightProfilePoints = zeros(0,3);
        end

        function clearProfiles2D(app)
            % Purpose: Deletes 2D profile lines on the Profiles tab.
            if ~isempty(app.LeftProfile2DLine) && isgraphics(app.LeftProfile2DLine)
                delete(app.LeftProfile2DLine);
            end
            if ~isempty(app.RightProfile2DLine) && isgraphics(app.RightProfile2DLine)
                delete(app.RightProfile2DLine);
            end
            if ~isempty(app.LeftProfile2DMeshLine) && isgraphics(app.LeftProfile2DMeshLine)
                delete(app.LeftProfile2DMeshLine);
            end
            if ~isempty(app.RightProfile2DMeshLine) && isgraphics(app.RightProfile2DMeshLine)
                delete(app.RightProfile2DMeshLine);
            end
            if ~isempty(app.LeftKerf2DLine) && isgraphics(app.LeftKerf2DLine)
                delete(app.LeftKerf2DLine);
            end
            if ~isempty(app.RightKerf2DLine) && isgraphics(app.RightKerf2DLine)
                delete(app.RightKerf2DLine);
            end

            app.LeftProfile2DLine      = gobjects(0);
            app.RightProfile2DLine     = gobjects(0);
            app.LeftProfile2DMeshLine  = gobjects(0);
            app.RightProfile2DMeshLine = gobjects(0);
            app.LeftKerf2DLine         = gobjects(0);
            app.RightKerf2DLine        = gobjects(0);
        end

        function clearKerfPaths(app)
            % Purpose: Delete only the kerf paths on the Profiles tab.
            if ~isempty(app.LeftKerf2DLine) && isgraphics(app.LeftKerf2DLine)
                delete(app.LeftKerf2DLine);
            end
            if ~isempty(app.RightKerf2DLine) && isgraphics(app.RightKerf2DLine)
                delete(app.RightKerf2DLine);
            end
            app.LeftKerf2DLine  = gobjects(0);
            app.RightKerf2DLine = gobjects(0);
        end

        %%                    - SHARED VIEW HELPERS ---

        function resetViewToMachine(app, ax)
            % Purpose: Standardizes the 3D camera view to show the entire machine bed.
            % WHY: Used by the Machine, Cutting, Simulation, and Post-Process tabs
            %      to provide a consistent "zoomed out" perspective.

            offX = app.MachineBedPos(1);
            mX   = app.MachineSpanX;
            mLimY = app.MachineLimitY;
            mLimZ = app.MachineLimitZ;
            bs = app.MachineBedSize;

            view(ax, 3); axis(ax, 'equal');

            % Minimal padding to allow towers to fill the screen,
            % with just enough Z-padding to prevent label cropping.
            padX = 5;
            padY = 5;
            padZ = 40;

            xlim(ax,[ -offX - padX, mX - offX + padX ]);
            ylim(ax,[ -padY, mLimY + padY ]);
            zlim(ax,[ -bs(3) - 20, mLimZ + padZ ]);

            % Force MATLAB to apply these limits immediately during initialization
            drawnow limitrate;
        end

        function resetViewToBillet(app, ax)
            % Purpose: Standardizes the 3D camera view to focus tightly on the billet.
            % WHY: Used across multiple tabs to inspect the toolpath relative to the stock.

            offX = app.MachineBedPos(1);
            bp   = app.MachineBilletPos; % [X Y Z] absolute machine coords
            bs   = app.BilletSize;       % [W D H]

            % Billet Bounds in Plot Coords (Plot X = MachineX - BedOffset)
            bMin =[ bp(1)-offX, bp(2), bp(3) ];
            bMax = bMin + bs;

            % Calculate relative buffer based on billet size
            maxDim = max(bs);
            if maxDim < 1, maxDim = 100; end
            buffer = maxDim * 0.2;

            % 1. Set Aspect Ratio FIRST
            daspect(ax,[ 1 1 1 ]);

            % 2. Apply Limits
            xlim(ax,[ bMin(1)-buffer, bMax(1)+buffer ]);
            ylim(ax,[ bMin(2)-buffer, bMax(2)+buffer ]);
            zlim(ax,[ bMin(3)-buffer, bMax(3)+buffer ]);

            % 3. Standard View Settings
            view(ax, 3);
            grid(ax, 'on');
        end

        %%                    - 3D DRAWING PRIMITIVES ---

        function[ vx, vy, vz ] = makeBoxVertices(~, x, y, z, dx, dy, dz)
            % Purpose: Returns the 8 vertices for a 3D box at (x,y,z) with size (dx,dy,dz).
            % WHY: Used to draw the machine bed, packing blocks, and billet stock.
            vx =[ x; x+dx; x+dx; x;    x;    x+dx; x+dx; x    ];
            vy =[ y; y;    y+dy; y+dy; y;    y;    y+dy; y+dy ];
            vz =[ z; z;    z;    z;    z+dz; z+dz; z+dz; z+dz ];
        end

        function f = boxFaces(~)
            % Purpose: Returns the face connectivity matrix for a standard 8-vertex box.
            f =[ 1 2 3 4; % Bottom
                5 6 7 8; % Top
                1 2 6 5; % Front
                2 3 7 6; % Right
                3 4 8 7; % Back
                4 1 5 8 ]; % Left
        end

        %%                    - THEME MANAGEMENT ---

        function p = getTabPadding(app)
            % Purpose: Returns the padding for the root grid of each tab.
            % WHY: MATLAB's compiled standalone engine (CEF) has a known bug where it miscalculates
            %      the client area of a uitabgroup, causing the bottom and right edges to crop.
            %      We inject extra padding only when compiled to counteract this shift.

            p = [5, 5, 5, 5]; % Base padding [left, bottom, right, top]

            if isdeployed
                % Add 35px to bottom and right to counteract the CEF crop
                p = p + [0, 35, 35, 0];
            end
        end

        function th = getTheme(app)
            % Purpose: Central source of truth for all App Colors.
            % WHY: Allows the app to seamlessly switch between Light and Dark modes.

            if ispref('HotWireSTEPApp', 'Theme')
                themeStr = getpref('HotWireSTEPApp', 'Theme');
            else
                themeStr = 'Dark';
            end

            isDark = strcmp(themeStr, 'Dark');

            if isDark
                % --- DARK THEME ---
                th.sideBg      =[ 0.16 0.16 0.16 ];
                th.panelBg     =[ 0.12 0.12 0.12 ];
                th.labelCol    =[ 0.90 0.90 0.90 ];
                th.accentBg    =[ 0.30 0.35 0.45 ];
                th.editBg      =[ 0.24 0.24 0.24 ];
                th.editTxt     =[ 1.00 1.00 1.00 ];
                th.readoutBg   =[ 0.70 0.70 0.70 ];
                th.readoutTxt  =[ 0.20 0.20 0.20 ];

                th.inputBg     =[ 0.24 0.24 0.24 ];
                th.inputTxt    =[ 1.00 1.00 1.00 ];

                th.shiftBg     =[ 0.70 0.70 0.80 ];
                th.shiftTxt    =[ 0.00 0.00 0.00 ];

                th.btnBg       =[ 0.25 0.25 0.25 ];
                th.btnTxt      =[ 1.00 1.00 1.00 ];
                th.axBg        =[ 0.05 0.05 0.05 ];

                th.planeRed    =[ 0.96 0.06 0.06 ];
                th.planeGreen  =[ 0.20 1.00 0.35 ];
                th.planeRedTxt =[ 0.96 0.40 0.40 ];
                th.planeGreenTxt =[ 0.40 1.00 0.50 ];

                th.wireKerf    =[ 1.00 0.75 0.00 ];
                th.wireNeutral =[ 0.80 0.80 0.80 ];
                th.rawMeshCol  =[ 0.60 0.60 0.60 ];
                th.wireLead    =[ 1.00 0.50 0.00 ];

                % Status Box Colors (Red / Amber / Green)
                th.statErrBg   =[ 0.40 0.16 0.16 ];
                th.statErrTxt  =[ 1.00 0.40 0.40 ];
                th.statWarnBg  =[ 0.45 0.35 0.10 ];
                th.statWarnTxt =[ 1.00 0.80 0.40 ];
                th.statPassBg  = th.panelBg;
                th.statPassTxt = th.planeGreen;

                % 3D Plotting Elements
                th.modelColor  =[ 0.50 0.50 0.60 ];
                th.modelAlpha  = 0.40;
                th.billetColor =[ 0.30 0.50 0.80 ];
                th.billetAlpha = 0.20;
                th.billetLine  =[ 0.00 0.80 1.00 ]; % Bright Cyan to pop against grid

                th.bedCol      =[ 0.40 0.40 0.40 ];
                th.bedEdge     =[ 0.20 0.20 0.20 ];
                th.cageCol     =[ 0.60 0.60 0.60 ];
                th.wireBaseCol =[ 0.50 0.50 0.50 ];

                % Ghost profiles (RGBA with 60% opacity)
                th.ghostRed    =[ th.planeRed, 0.6 ];
                th.ghostGreen  =[ th.planeGreen, 0.6 ];
                th.ghostNeutral=[ 0.90 0.90 0.90, 0.7 ];

            else
                % --- LIGHT THEME ---
                th.sideBg      =[ 0.96 0.96 0.96 ];
                th.panelBg     =[ 0.90 0.90 0.90 ];
                th.labelCol    =[ 0.15 0.15 0.15 ];
                th.accentBg    =[ 0.70 0.70 0.80 ];
                th.editBg      =[ 1.00 1.00 1.00 ];
                th.editTxt     =[ 0.00 0.00 0.00 ];
                th.readoutBg   =[ 0.85 0.85 0.85 ];
                th.readoutTxt  =[ 0.20 0.20 0.20 ];

                th.inputBg     =[ 1.00 1.00 1.00 ];
                th.inputTxt    =[ 0.00 0.00 0.00 ];

                th.shiftBg     =[ 0.70 0.70 0.80 ];
                th.shiftTxt    =[ 0.00 0.00 0.00 ];

                th.btnBg       =[ 0.85 0.85 0.85 ];
                th.btnTxt      =[ 0.00 0.00 0.00 ];
                th.axBg        =[ 0.95 0.95 0.95 ];

                th.planeRed    =[ 0.80 0.00 0.00 ];
                th.planeGreen  =[ 0.00 0.60 0.00 ];
                th.planeRedTxt =[ 0.60 0.00 0.00 ];
                th.planeGreenTxt =[ 0.00 0.40 0.00 ];

                th.wireKerf    =[ 1.00 0.75 0.00 ];
                th.wireNeutral =[ 0.20 0.20 0.20 ];
                th.rawMeshCol  =[ 0.40 0.40 0.40 ];
                th.wireLead    =[ 0.85 0.35 0.00 ];

                % Status Box Colors
                th.statErrBg   =[ 1.00 0.80 0.80 ];
                th.statErrTxt  =[ 0.80 0.00 0.00 ];
                th.statWarnBg  =[ 1.00 0.90 0.70 ];
                th.statWarnTxt =[ 0.65 0.30 0.00 ];
                th.statPassBg  = th.panelBg;
                th.statPassTxt = th.planeGreen;

                th.modelColor  =[ 0.50 0.50 0.60 ];
                th.modelAlpha  = 0.30;
                th.billetColor =[ 0.30 0.50 0.80 ];
                th.billetAlpha = 0.20;
                th.billetLine  =[ 0.00 0.20 0.80 ]; % Deep Blue to pop against grid

                th.bedCol      =[ 0.80 0.80 0.80 ];
                th.bedEdge     =[ 0.50 0.50 0.50 ];
                th.cageCol     =[ 0.30 0.30 0.30 ];
                th.wireBaseCol =[ 0.40 0.40 0.40 ];

                th.ghostRed    =[ th.planeRed, 0.6 ];
                th.ghostGreen  =[ th.planeGreen, 0.6 ];
                th.ghostNeutral=[ 0.20 0.20 0.20, 0.5 ];
            end
        end

        function applyTheme(app)
            % Purpose: Sweeps the entire UI on startup to replace hardcoded colors with the active theme.
            % WHY: MATLAB's UI components don't natively support CSS-style themes, so we must
            %      programmatically iterate through the component tree and paint them.

            t = app.getTheme();
            app.UIFigure.Color = t.sideBg;

            % 1. Paint ALL Physical Tabs
            tabs =[ app.TabWelcome, app.TabGuide, app.TabModel, app.TabProfiles, app.TabBillet, ...
                app.TabMachine, app.TabCutting, app.TabSimulation, app.TabPostProcess ];
            for i = 1:numel(tabs)
                if isgraphics(tabs(i))
                    tabs(i).BackgroundColor = t.sideBg;
                end
            end

            % 2. Sweep and update ALL layout grids and panels
            containers = {app.GLWelcome, app.GLGuide, app.GLModel, app.GLProfiles, app.GLBillet, ...
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

                    % A. Protect Readouts (Labels that act like disabled edit fields)
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

                    % B. Update Status Boxes to match theme
                    if isprop(obj, 'BackgroundColor') && isequal(obj.BackgroundColor, [ 0.2 0.2 0.2 ]) && isa(obj, 'matlab.ui.control.TextArea')
                        if t.sideBg(1) < 0.5
                            obj.BackgroundColor =[ 0.15 0.15 0.15 ];
                        else
                            obj.BackgroundColor =[ 0.98 0.98 0.98 ];
                        end
                        continue;
                    end

                    % C. Protect Billet Shift & Size Edit Fields (Give them a distinct accent color)
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
                        obj.BackgroundColor = t.planeRed * 0.15 + t.sideBg * 0.85;
                        continue;
                    elseif obj == app.NumRightOffset
                        obj.FontColor = t.planeGreenTxt;
                        obj.BackgroundColor = t.planeGreen * 0.15 + t.sideBg * 0.85;
                        continue;
                        % --- Special Case: Kerf Spinners ---
                    elseif obj == app.KerfLeftSpinner
                        obj.FontColor = t.wireKerf;
                        obj.BackgroundColor = t.planeRed * 0.15 + t.sideBg * 0.85;
                        continue;
                    elseif obj == app.KerfRightSpinner
                        obj.FontColor = t.wireKerf;
                        obj.BackgroundColor = t.planeGreen * 0.15 + t.sideBg * 0.85;
                        continue;
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
            allAxes =[ app.AxModel, app.AxLeftProfile, app.AxRightProfile, ...
                app.AxBilletTop, app.AxBilletFront, app.AxBilletRight, app.AxBilletIso, ...
                app.AxMachine, app.AxCutLeft, app.AxCutRight, app.AxSim, app.AxPost ];

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
            % Purpose: Prompts the user to restart the app to apply the new theme.
            sel = uiconfirm(app.UIFigure, ...
                'Changing the theme requires the application to restart. Any unsaved progress will be lost. Do you wish to restart now?', ...
                'Restart Required', ...
                'Options', {'Restart Now', 'Cancel'}, ...
                'DefaultOption', 1, 'CancelOption', 2, 'Icon', 'info');

            if strcmp(sel, 'Restart Now')
                setpref('HotWireSTEPApp', 'Theme', src.Value);
                delete(app.UIFigure);
                CNCHotWire_GCodeGenerator();
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
            % Purpose: Returns the specific semantic colors used for the Cutting Tab interactive buttons.
            t = app.getTheme();
            isDark = app.UIFigure.Color(1) < 0.5;

            cols = struct();

            if isDark
                cols.StartActive   =[ 0.0 0.8 0.0 ]; % Green
                cols.StartInactive =[ 0.15 0.25 0.15 ];
                cols.EntryActive   =[ 1.0 0.6 0.0 ]; % Orange (Lead In)
                cols.EntryInactive =[ 0.30 0.20 0.10 ];
                cols.LinkActive    =[ 0.9 0.8 0.0 ]; % Yellow (Links)
                cols.LinkInactive  =[ 0.30 0.30 0.10 ];
                cols.TextActive    =[ 0 0 0 ];
                cols.TextInactive  =[ 0.9 0.9 0.9 ];
            else
                cols.StartActive   =[ 0.4 1.0 0.4 ];
                cols.StartInactive =[ 0.90 0.96 0.90 ];
                cols.EntryActive   =[ 1.0 0.7 0.4 ];
                cols.EntryInactive =[ 0.98 0.94 0.90 ];
                cols.LinkActive    =[ 0.9 0.9 0.4 ];
                cols.LinkInactive  =[ 0.98 0.98 0.90 ];
                cols.TextActive    =[ 0 0 0 ];
                cols.TextInactive  =[ 0 0 0 ];
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

        % TAB 0 (WELCOME & SETUP)
        function createWelcomeTab(app)
            % Purpose: Builds the Welcome & Setup tab. This tab introduces the
            %          software and provides the one-time FreeCAD engine setup.
            %
            % Layout Strategy:
            %   - Left Panel (320px): Theme toggle and Continue button.
            %   - Right Panel (1x): Scrollable content area containing the Header,
            %     About text, FreeCAD setup, and a pinned Footer.
            %
            % Dependencies: app.getTheme(), CNCHotWire_GCodeGenerator_V1 UI Constants

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
            app.GLWelcome.ColumnWidth = {CNCHotWire_GCodeGenerator.PanelWidth, '1x'};
            app.GLWelcome.Padding = app.getTabPadding();
            app.GLWelcome.ColumnSpacing = 5;
            app.GLWelcome.BackgroundColor = sideBg;

            %% --- LEFT PANEL (Sidebar Feel) ---
            leftPnl = uigridlayout(app.GLWelcome,[3 1]);
            leftPnl.Layout.Column = 1;
            % '1x' pushes the theme toggle and button to the bottom
            leftPnl.RowHeight = {'1x', 'fit', CNCHotWire_GCodeGenerator.ButtonHeight};
            leftPnl.Padding = [5 5 5 5];
            leftPnl.BackgroundColor = panelBg; % Distinct sidebar shade

            % Theme Toggle
            glTheme = uigridlayout(leftPnl, [1 2]);
            glTheme.Layout.Row = 2;
            glTheme.ColumnWidth = {'fit', 'fit'};
            glTheme.Padding =[0 0 0 0];
            glTheme.BackgroundColor = panelBg;
            uilabel(glTheme, 'Text', 'App Theme:', 'FontWeight', 'bold', 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            if ispref('HotWireSTEPApp', 'Theme'), currentTheme = getpref('HotWireSTEPApp', 'Theme'); else, currentTheme = 'Dark'; end
            app.ThemeSwitch = uiswitch(glTheme, 'slider', 'Items', {'Dark', 'Light'}, 'Value', currentTheme, 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ValueChangedFcn', @(src,evt)app.onThemeToggleChanged(src));

            % Continue Button
            btnWelcomeCont = uibutton(leftPnl, 'Text','Continue to Guide →', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'BackgroundColor',[0.1 0.6 0.1], 'FontColor',[1 1 1], 'ButtonPushedFcn',@(~,~)app.onContinue());
            btnWelcomeCont.Layout.Row = 3;
            %% --- RIGHT PANEL (Content) ---
            rightScroll = uipanel(app.GLWelcome, 'Scrollable', 'on', 'BackgroundColor', sideBg, 'BorderType', 'none');
            rightScroll.Layout.Column = 2;

            % 5 Rows: Header, About, FreeCAD, Spacer (1x), Footer
            glRight = uigridlayout(rightScroll,[5 1]);
            glRight.RowHeight = {120, 220, 'fit', '1x', 'fit'}; % 260px prevents About box scrollbar
            glRight.BackgroundColor = sideBg;
            glRight.Padding =[20 20 20 20];
            glRight.RowSpacing = 15;

            % --- Header Area ---
            glHead = uigridlayout(glRight,[1 2]);
            glHead.Layout.Row = 1;
            glHead.ColumnWidth = {'1x', 280};
            glHead.Padding =[0 0 0 0];
            glHead.BackgroundColor = sideBg;

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
            pnlAbout = uipanel(glRight, 'Title', 'About This Software', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BackgroundColor', panelBg, 'ForegroundColor', labelCol);
            pnlAbout.Layout.Row = 2;
            glAbout = uigridlayout(pnlAbout,[1 1]);
            glAbout.RowHeight = {'1x'};
            glAbout.Padding =[0 0 0 0];
            glAbout.BackgroundColor = panelBg;

            txtAbout = {
                'Welcome to the Rapid Prototyping Workshops 4-axis CNC Hot Wire Toolpath and G-code Generator.';
                'This software provides a complete, end-to-end workflow to take you from CAD model to a G-code program the CNC foam cutter can run.';
                'Most steps offer auto or manual configuration.';
                '';
                'Workflow:';
                '- Export your model form your chosen CAD package, preferably as a STEP file (or STL)';
                '- Import and orient your 3D CAD  model (STEP/STL).';
                '- Slice models, extract and sync 2D profiles.';
                '- Apply kerf compensation to allow for the width of the cut, preserving dimensional accuracy.';
                '- Size and position your model and billet.';
                '- Create collision-free lead-in and exit paths.';
                '- Visually simulate the 4-axis kinematics to verify the cut.';
                '- Post-process and export Mach4-compatible G-code.'
                };
            uitextarea(glAbout, 'Value', txtAbout, 'Editable', 'off', 'BackgroundColor', panelBg, 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            % --- FreeCAD Setup Section (Step-by-Step) ---
            pnlFC = uipanel(glRight, 'Title', 'Required Setup: FreeCAD Engine', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BackgroundColor', panelBg, 'ForegroundColor', labelCol);
            pnlFC.Layout.Row = 3;

            glFC = uigridlayout(pnlFC,[4 2]);
            glFC.ColumnWidth = {'1x', 300};
            glFC.RowHeight = {'fit', CNCHotWire_GCodeGenerator.ButtonHeight, 'fit', CNCHotWire_GCodeGenerator.ButtonHeight};
            glFC.Padding =[10 10 10 10];
            glFC.BackgroundColor = panelBg;

            % Intro
            lblIntro = uilabel(glFC, 'Text', 'This app requires FreeCAD (v1.0 or newer) behind the scenes to accurately mesh STEP files. You only need to set this up once!', 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
            lblIntro.Layout.Row = 1; lblIntro.Layout.Column =[1 2];

            % Step 1
            lblS1 = uilabel(glFC, 'Text', 'Step 1. Download and run the standard Windows Installer.', 'FontColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
            lblS1.Layout.Row = 2; lblS1.Layout.Column = 1;
            btnDL = uibutton(glFC, 'Text', 'Download FreeCAD', 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'BackgroundColor',[0.2 0.5 0.8], 'FontColor',[1 1 1], 'ButtonPushedFcn', @(~,~)web('https://www.freecad.org/downloads.php', '-browser'));
            btnDL.Layout.Row = 2; btnDL.Layout.Column = 2;

            % Step 2
            lblS2 = uilabel(glFC, 'Text', 'Step 2. Install FreeCAD to the default directory.', 'FontColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
            lblS2.Layout.Row = 3; lblS2.Layout.Column = [1 2];

            % Step 3
            lblS3 = uilabel(glFC, 'Text', 'Step 3. Locate "FreeCADCmd.exe" (Typically: C:\Program Files\FreeCAD 1.0\bin\)', 'FontColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
            lblS3.Layout.Row = 4; lblS3.Layout.Column = 1;

            glFCBrowse = uigridlayout(glFC,[1 2]);
            glFCBrowse.Layout.Row = 4; glFCBrowse.Layout.Column = 2;
            glFCBrowse.ColumnWidth = {'1x', 80};
            glFCBrowse.RowHeight = {CNCHotWire_GCodeGenerator.ButtonHeight};
            glFCBrowse.Padding =[0 0 0 0];
            glFCBrowse.BackgroundColor = panelBg;

            if ispref('HotWireSTEPApp', 'FreeCADPath')
                app.FreeCADExe = getpref('HotWireSTEPApp', 'FreeCADPath');
            else
                if ismac
                    app.FreeCADExe = "/Applications/FreeCAD.app/Contents/MacOS/FreeCADCmd";
                elseif ispc
                    app.FreeCADExe = "C:\Program Files\FreeCAD 1.0\bin\FreeCADCmd.exe";
                else
                    app.FreeCADExe = "freecadcmd";
                end
            end

            app.FieldFreeCADPath = uieditfield(glFCBrowse, 'text', 'Value', app.FreeCADExe, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'BackgroundColor', inputBg, 'FontColor', inputTxt, 'ValueChangedFcn', @(src,evt)app.onFreeCADPathEdited(src));
            btnBrowseFC = uibutton(glFCBrowse, 'Text', 'Browse...', 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'BackgroundColor', t.accentBg, 'FontColor', t.editTxt, 'ButtonPushedFcn', @(~,~)app.onBrowseFreeCAD());

            % --- Footer Panels ---
            glFooter = uigridlayout(glRight,[1 3]);
            glFooter.Layout.Row = 5;
            glFooter.ColumnWidth = {'1x', '1x', 305};
            glFooter.RowHeight = {80};
            glFooter.Padding =[0 0 0 0];
            glFooter.ColumnSpacing = 5;
            glFooter.BackgroundColor = sideBg;

            pnlContact = uipanel(glFooter, 'Title', 'Contact', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BackgroundColor', panelBg, 'ForegroundColor', labelCol);
            glContact = uigridlayout(pnlContact,[1 1]); glContact.Padding =[0 0 0 0]; glContact.BackgroundColor = panelBg;
            uitextarea(glContact, 'Value', {'Author: Matthew Richardson'; 'Email: matthew.richardson@bristol.ac.uk'}, 'Editable', 'off', 'BackgroundColor', panelBg, 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            pnlLicense = uipanel(glFooter, 'Title', 'License', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BackgroundColor', panelBg, 'ForegroundColor', labelCol);
            glLicense = uigridlayout(pnlLicense,[1 1]); glLicense.Padding =[0 0 0 0]; glLicense.BackgroundColor = panelBg;
            uitextarea(glLicense, 'Value', {'Released under the MIT Open Source License.'; 'Free for academic, personal, or commercial use.'}, 'Editable', 'off', 'BackgroundColor', panelBg, 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            pnlSource = uipanel(glFooter, 'Title', 'Source Code', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BackgroundColor', panelBg, 'ForegroundColor', labelCol);
            glSource = uigridlayout(pnlSource,[1 1]); glSource.Padding =[5 5 5 5]; glSource.BackgroundColor = panelBg;
            uibutton(glSource, 'Text', 'View Source on GitHub', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'BackgroundColor',[0.2 0.2 0.2], 'FontColor', [1 1 1], 'ButtonPushedFcn', @(~,~)web(app.GitHubLink, '-browser'));
        end

        % TAB 1 (INTERFACE GUIDE)
        function createGuideTab(app)
            % Purpose: Teaches the user the UI layout by mimicking the actual
            %          app structure. Uses dummy components to explain functionality.
            %
            % Dependencies: app.getTheme(), CNCHotWire_GCodeGenerator_V1 UI Constants

            t = app.getTheme();
            sideBg   = t.sideBg;
            panelBg  = t.panelBg;
            labelCol = t.labelCol;

            app.TabGuide = uitab(app.TabGroup, 'Title', 'Interface Guide');

            % Mimic the standard app layout
            app.GLGuide = uigridlayout(app.TabGuide, [1 2]);
            app.GLGuide.ColumnWidth = {CNCHotWire_GCodeGenerator.PanelWidth, '1x'};
            app.GLGuide.Padding = app.getTabPadding();
            app.GLGuide.ColumnSpacing = 5;
            app.GLGuide.BackgroundColor = sideBg;

            %% --- LEFT PANEL (Mimics Controls) ---
            leftPnl = uigridlayout(app.GLGuide,[7 1]);
            leftPnl.Layout.Column = 1;
            % 1x spacer pushes Guidance and Status to the bottom!
            leftPnl.RowHeight = {'fit', 'fit', 'fit', '1x', 'fit', 70, CNCHotWire_GCodeGenerator.ButtonHeight};
            leftPnl.Padding = [5 5 5 5];
            leftPnl.BackgroundColor = panelBg; % Distinct sidebar shade

            % 1. Controls Intro
            pnl1 = uipanel(leftPnl, 'Title', '1. Controls & Inputs', 'BackgroundColor', sideBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType', 'line');
            gl1 = uigridlayout(pnl1, [1 1]); gl1.Padding =[0 0 0 0]; gl1.BackgroundColor = sideBg;
            uitextarea(gl1, 'Value', 'The top of the left panel contains inputs, toggles, and buttons.', 'Editable', 'off', 'BackgroundColor', sideBg, 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            % Dummy Controls Panel
            pnlDummy = uipanel(leftPnl, 'Title','Example Controls', 'BackgroundColor',sideBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlDummy.Layout.Row = 2;
            gridDummy = uigridlayout(pnlDummy, [3 2]);
            gridDummy.ColumnWidth = {'1x', '1x'};
            gridDummy.RowHeight = {CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.ButtonHeight};
            gridDummy.Padding=[5 5 5 5];
            gridDummy.BackgroundColor=sideBg;

            uilabel(gridDummy, 'Text', 'Example Toggle:', 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment', 'right');
            uiswitch(gridDummy, 'slider', 'Items', {'Off', 'On'}, 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            uilabel(gridDummy, 'Text', 'Example Spinner:', 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment', 'right');
            uispinner(gridDummy, 'Value', 10.0, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            uibutton(gridDummy, 'Text','Example Button', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
            uibutton(gridDummy, 'Text','Example Button', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            % 2. Guidance (Pushed to bottom by 1x spacer in Row 4)
            pnl2 = uipanel(leftPnl, 'Title', 'Guidance', 'BackgroundColor', sideBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType', 'line');
            pnl2.Layout.Row = 5;
            gl2 = uigridlayout(pnl2,[1 1]); gl2.Padding =[0 0 0 0]; gl2.BackgroundColor = sideBg;
            uitextarea(gl2, 'Value', 'Guidance blocks provide step-by-step instructions for the current tab.', 'Editable', 'off', 'BackgroundColor', sideBg, 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            % 3. Status
            pnl3 = uipanel(leftPnl, 'Title', 'Status', 'BackgroundColor', sideBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType', 'line');
            pnl3.Layout.Row = 6;
            gl3 = uigridlayout(pnl3, [1 1]); gl3.Padding =[0 0 0 0]; gl3.BackgroundColor = sideBg;
            uitextarea(gl3, 'Value', 'Traffic-light box: Red (Error), Amber (Warning), Green (Safe).', 'Editable', 'off', 'BackgroundColor', t.statPassBg, 'FontColor', t.statPassTxt, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            % Continue Button
            btnCont = uibutton(leftPnl, 'Text', 'Continue to Model →', 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'BackgroundColor',[0.1 0.6 0.1], 'FontColor', [1 1 1], 'ButtonPushedFcn', @(~,~)app.onContinue());
            btnCont.Layout.Row = 7;

            %% --- RIGHT PANEL (Mimics Plot) ---
            rightPnl = uipanel(app.GLGuide, 'Title', '4. Main Plot (Right Side) →', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeTitle, 'BorderType', 'line');
            rightPnl.Layout.Column = 2;

            glR = uigridlayout(rightPnl,[2 1]);
            glR.RowHeight = {'fit', '1x'};
            glR.Padding =[10 10 10 10];
            glR.BackgroundColor = sideBg;

            txt = {
                'The large right panel always contains your interactive 2D or 3D visuals.';
                'Move through the tabs at the top of the window one by one, left to right.'
                };
            uitextarea(glR, 'Value', txt, 'Editable', 'off', 'BackgroundColor', sideBg, 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeTitle);

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

        % TAB 2 (MODEL)
        function createModelTab(app)
            % Purpose: Builds the Model Import & Orientation tab UI components.
            %
            % Layout Strategy:
            %   - Left Panel (320px): Step-by-step controls for importing,
            %     orienting, and slicing the 3D model.
            %   - Right Panel (1x): 3D interactive visualization axes.
            %
            % Dependencies: app.getTheme(), CNCHotWire_GCodeGenerator_V1 UI Constants

            % 1. Fetch Theme Colors locally for this function
            t = app.getTheme();
            sideBg   = t.sideBg;
            panelBg  = t.panelBg;
            labelCol = t.labelCol;

            % 2. Main Tab Container
            app.TabModel = uitab(app.TabGroup,'Title','Model');

            app.GLModel = uigridlayout(app.TabModel,[1 2]);
            app.GLModel.ColumnWidth   = {CNCHotWire_GCodeGenerator.PanelWidth, '1x'};
            app.GLModel.Padding       = app.getTabPadding();
            app.GLModel.ColumnSpacing = 5;
            app.GLModel.BackgroundColor = sideBg;

            %% --- LEFT CONTROL PANEL (Sidebar) ---
            app.GLLeft = uigridlayout(app.GLModel,[8 1]);
            app.GLLeft.Layout.Column = 1;
            app.GLLeft.BackgroundColor = panelBg; % Distinct sidebar shade

            % Rows: 1:View, 2:Import, 3:Taper, 4:Orientation, 5:Planes, 6:Guidance(1x), 7:Status(70px), 8:Buttons
            app.GLLeft.RowHeight = {'fit', 'fit', 'fit', 'fit', 'fit', '1x', 70, CNCHotWire_GCodeGenerator.ButtonHeight};
            app.GLLeft.Padding =[5 5 5 5];
            app.GLLeft.RowSpacing = CNCHotWire_GCodeGenerator.BlockSpacing;

            %% --- VIEW CONTROLS (Unnumbered) ---
            pnlView = uipanel(app.GLLeft, 'Title','View', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlView.Layout.Row = 1;

            gridView = uigridlayout(pnlView,[1 1]);
            gridView.Padding=[5 5 5 5];
            gridView.RowHeight = {CNCHotWire_GCodeGenerator.ButtonHeight};
            gridView.BackgroundColor=panelBg;

            btnMResP = uibutton(gridView, 'Text','Reset Plot View', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.resetPlotView());

            %% --- 1. FILE IMPORT ---
            pnlImport = uipanel(app.GLLeft, 'Title', '1. Import ModelX', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType', 'line');
            pnlImport.Layout.Row = 2;

            gridImport = uigridlayout(pnlImport,[3 2]);
            gridImport.ColumnWidth = {'1x', '1x'};
            gridImport.RowHeight = {CNCHotWire_GCodeGenerator.ButtonHeight, CNCHotWire_GCodeGenerator.ButtonHeight, 'fit'};
            gridImport.Padding =[5 5 5 5];
            gridImport.ColumnSpacing = 5;
            gridImport.BackgroundColor = panelBg;

            app.BtnImportSTEP = uibutton(gridImport, 'Text','Import STEP (recommended)', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, ...
                'Tooltip', 'Load a .STEP file. Uses FreeCAD for accurate mesh generation.', ...
                'ButtonPushedFcn',@(~,~)app.onImportSTEP());
            app.BtnImportSTEP.Layout.Row = 1;
            app.BtnImportSTEP.Layout.Column = [1 2];

            app.BtnImportSTL = uibutton(gridImport, 'Text','Import STL', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, ...
                'Tooltip', 'Load a .STL mesh. Accuracy depends on file export settings.', ...
                'ButtonPushedFcn',@(~,~)app.onImportSTL());
            app.BtnImportSTL.Layout.Row = 2;
            app.BtnImportSTL.Layout.Column = 1;

            btnExamples = uibutton(gridImport, 'Text','📂 Examples', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, ...
                'BackgroundColor', t.accentBg, 'FontColor', t.editTxt, ...
                'Tooltip', 'Open the bundled examples folder', ...
                'ButtonPushedFcn',@(~,~)app.onLoadExample());
            btnExamples.Layout.Row = 2;
            btnExamples.Layout.Column = 2;

            app.FileLabel = uilabel(gridImport, 'Text','Current File: ---', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'FontColor',labelCol);
            app.FileLabel.Layout.Row = 3;
            app.FileLabel.Layout.Column = [1 2];

            %% --- 2. TAPER MODE ---
            pnlTaper = uipanel(app.GLLeft, 'Title', '2. Cut Type', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType', 'line');
            pnlTaper.Layout.Row = 3;

            gridTaper = uigridlayout(pnlTaper,[1 3]);
            gridTaper.ColumnWidth = {'1x','fit','1x'};
            gridTaper.RowHeight = {CNCHotWire_GCodeGenerator.RowHeightNormal};
            gridTaper.Padding=[5 5 5 5];
            gridTaper.BackgroundColor = panelBg;

            uilabel(gridTaper,'Text',''); % Left Spacer

            app.TaperToggle = uiswitch(gridTaper,'slider', 'Items',{'Straight','Tapered'}, 'Value','Straight', ...
                'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'FontColor', labelCol, ...
                'Tooltip', sprintf('Straight: Prismatic (Identical profiles).\nTapered: Independent Left/Right profiles.'), ...
                'ValueChangedFcn',@(~,~)app.onTaperModeChanged());
            app.TaperToggle.Layout.Column = 2;

            uilabel(gridTaper,'Text',''); % Right Spacer

            %% --- 3. ORIENTATION ---
            pnlRot = uipanel(app.GLLeft, 'Title','3. Model Orientation', 'BackgroundColor',panelBg, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'ForegroundColor',labelCol);
            pnlRot.Layout.Row = 4;

            % 3 rows, 7 columns to center the controls and fix the button width
            % Col 1 & 7 act as flexible spacers to keep the block centered
            app.RotGrid = uigridlayout(pnlRot,[3 7]);
            app.RotGrid.ColumnWidth={'1x', 'fit', 'fit', 60, 'fit', CNCHotWire_GCodeGenerator.ButtonHeight, '1x'};
            app.RotGrid.RowHeight={CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.RowHeightNormal};
            app.RotGrid.Padding=[5 5 5 5];
            app.RotGrid.ColumnSpacing = 10; % Increased spacing for better breathing room!
            app.RotGrid.RowSpacing = 2;
            app.RotGrid.BackgroundColor=panelBg;

            axesLabels = {'X','Y','Z'};
            app.RotEdit = gobjects(1,3);
            for i = 1:3
                lblRot = uilabel(app.RotGrid, 'Text',axesLabels{i}, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment','center', 'FontColor',labelCol);
                lblRot.Layout.Row=i; lblRot.Layout.Column=2;

                btnNeg = uibutton(app.RotGrid,'Text','-90°', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.rotateModel([axesLabels{i} 'm']));
                btnNeg.Layout.Row=i; btnNeg.Layout.Column=3;

                app.RotEdit(i) = uieditfield(app.RotGrid,'numeric', 'Limits',[0 360], 'Value',0, 'HorizontalAlignment','center', 'ValueDisplayFormat','%.0f°', ...
                    'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, ...
                    'Tooltip',['Rotate model around the ' axesLabels{i} ' axis.'], ...
                    'ValueChangedFcn',@(src,~)app.updateRotation(axesLabels{i},src.Value));
                app.RotEdit(i).Layout.Row=i; app.RotEdit(i).Layout.Column=4;

                btnPos = uibutton(app.RotGrid,'Text','+90°', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.rotateModel([axesLabels{i} 'p']));
                btnPos.Layout.Row=i; btnPos.Layout.Column=5;
            end

            % Vertical Reset Button spanning all 3 rows
            vertText = sprintf('R\nE\nS\nE\nT');
            btnResO = uibutton(app.RotGrid, 'Text', vertText, 'FontWeight','bold', 'FontSize', 10, 'Tooltip', 'Reset Orientation', 'ButtonPushedFcn',@(~,~)app.resetOrientation());
            btnResO.Layout.Row = [1 3];
            btnResO.Layout.Column = 6;

            %% --- 4. PLANE OFFSETS ---
            pnlOff = uipanel(app.GLLeft, 'Title', '4. Plane Offsets [mm]', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlOff.Layout.Row = 5;

            gridOff = uigridlayout(pnlOff,[2 4]);
            gridOff.ColumnWidth={'fit','1x','fit','1x'};
            gridOff.RowHeight={CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.ButtonHeight};
            gridOff.Padding=[5 5 5 5];
            gridOff.BackgroundColor = panelBg;

            % Left Spinner
            lblOffL = uilabel(gridOff,'Text','Left:','HorizontalAlignment','right','FontWeight','bold', 'FontColor',labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
            lblOffL.Layout.Row=1; lblOffL.Layout.Column=1;

            app.NumLeftOffset = uispinner(gridOff, 'Limits',[0 10000], 'Value',0, 'Step',1, ...
                'ValueDisplayFormat','%.1f', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, ...
                'Tooltip', 'Distance from Model Left Face (X Min) to Left Cutting Plane', ...
                'ValueChangedFcn',@(src,evt)app.onPlaneOffsetChanged(src,evt));
            app.NumLeftOffset.Layout.Row=1; app.NumLeftOffset.Layout.Column=2;

            % Right Spinner
            lblOffR = uilabel(gridOff,'Text','Right:','HorizontalAlignment','right','FontWeight','bold', 'FontColor',labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
            lblOffR.Layout.Row=1; lblOffR.Layout.Column=3;

            app.NumRightOffset = uispinner(gridOff, 'Limits',[0 10000], 'Value',0, 'Step',1, ...
                'ValueDisplayFormat','%.1f', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, ...
                'Tooltip', 'Distance from Model Left Face (X Min) to Right Cutting Plane', ...
                'ValueChangedFcn',@(src,evt)app.onPlaneOffsetChanged(src,evt));
            app.NumRightOffset.Layout.Row=1; app.NumRightOffset.Layout.Column=4;

            % Reset Button
            btnResPlane = uibutton(gridOff, 'Text','Reset Planes', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.resetPlanes());
            btnResPlane.Layout.Row=2; btnResPlane.Layout.Column=[1 4];

            %% --- 5. GUIDANCE ---
            pnlGuide = uipanel(app.GLLeft, 'Title', 'Guidance', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType', 'line');
            pnlGuide.Layout.Row = 6;
            glGuide = uigridlayout(pnlGuide,[1 1]);
            glGuide.Padding =[0 0 0 0]; % Zero padding for max text space
            glGuide.BackgroundColor = panelBg;

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
            app.TxtModelGuide = uitextarea(glGuide, 'Editable','off', 'Value', guideText, 'BackgroundColor', panelBg, 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            %% --- 6. STATUS ---
            pnlStatus = uipanel(app.GLLeft, 'Title', 'Status', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType', 'line');
            pnlStatus.Layout.Row = 7;
            glStatus = uigridlayout(pnlStatus,[1 1]);
            glStatus.Padding =[0 0 0 0];
            glStatus.BackgroundColor = panelBg;

            app.TxtModelStatus = uitextarea(glStatus, 'Editable','off', 'Value', {'No model loaded.'}, 'BackgroundColor', t.panelBg, 'FontColor',[1 0.8 0], 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            %% --- 7. ACTION BUTTONS ---
            gridBtn = uigridlayout(app.GLLeft,[1 2]);
            gridBtn.Layout.Row = 8;
            gridBtn.RowHeight = {CNCHotWire_GCodeGenerator.ButtonHeight};
            gridBtn.Padding=[0 0 0 0];
            gridBtn.BackgroundColor=panelBg;

            app.BtnGenerateProfiles = uibutton(gridBtn, 'Text','Generate Profiles', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'BackgroundColor',[0.15 0.45 0.8], 'FontColor',[1 1 1], ...
                'Tooltip', 'Slice model at the defined planes.', ...
                'ButtonPushedFcn',@(~,~)app.onGenerateProfiles());

            app.BtnContinue = uibutton(gridBtn, 'Text','Continue →', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'BackgroundColor',[0.3 0.3 0.3], 'FontColor',[0.8 0.8 0.8], ...
                'Enable','off', 'ButtonPushedFcn',@(~,~)app.onContinue());

            %% --- RIGHT PANEL: 3D MODEL AXES ---
            app.AxModel = uiaxes(app.GLModel);
            app.AxModel.Layout.Column = 2;
            app.AxModel.BackgroundColor = t.axBg; % Use theme axBg

            xlabel(app.AxModel,'X (mm)');
            ylabel(app.AxModel,'Y (mm)');
            zlabel(app.AxModel,'Z (mm)');

            grid(app.AxModel,'on');
            view(app.AxModel,3);
            hold(app.AxModel,'on');
        end

        % TAB 3 (PROFILES)
        function createProfilesTab(app)
            % Purpose: Builds the Profiles extraction and Kerf tab UI components.
            %
            % Layout Strategy:
            %   - Left Panel (320px): Controls for resampling tolerance and kerf.
            %   - Right Panel (1x): 2D axes for Left and Right profiles.
            %
            % Dependencies: app.getTheme(), CNCHotWire_GCodeGenerator_V1 UI Constants

            % Fetch Theme Colors locally
            t = app.getTheme();
            sideBg   = t.sideBg;
            panelBg  = t.panelBg;
            labelCol = t.labelCol;

            app.TabProfiles = uitab(app.TabGroup,'Title','Profiles');

            app.GLProfiles = uigridlayout(app.TabProfiles,[1 2]);
            app.GLProfiles.ColumnWidth = {CNCHotWire_GCodeGenerator.PanelWidth, '1x'};
            app.GLProfiles.Padding = app.getTabPadding();
            app.GLProfiles.ColumnSpacing = 5;
            app.GLProfiles.BackgroundColor = sideBg;

            %% --- LEFT CONTROL PANEL (Sidebar) ---
            app.profilesLeft = uigridlayout(app.GLProfiles,[6 1]);
            app.profilesLeft.Layout.Column = 1;

            % Rows: 1:View, 2:Sampling, 3:Kerf, 4:Guidance(1x), 5:Status(70px), 6:Continue
            app.profilesLeft.RowHeight = {'fit','fit','fit','1x',70, CNCHotWire_GCodeGenerator.ButtonHeight};
            app.profilesLeft.Padding = [5 5 5 5];
            app.profilesLeft.RowSpacing = CNCHotWire_GCodeGenerator.BlockSpacing;
            app.profilesLeft.BackgroundColor = panelBg;

            %% --- VIEW CONTROLS (Unnumbered) ---
            pnlView = uipanel(app.profilesLeft, 'Title','View', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlView.Layout.Row = 1;

            gridView = uigridlayout(pnlView, [1 1]);
            gridView.Padding=[5 5 5 5];
            gridView.RowHeight = {CNCHotWire_GCodeGenerator.ButtonHeight};
            gridView.BackgroundColor=panelBg;

            app.BtnResetProfilesView = uibutton(gridView, 'Text','Reset Profiles View', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.resetProfilesView());

            %% --- 1. PROFILE SAMPLING ---
            pnlSampling = uipanel(app.profilesLeft, 'Title','1. Profile Sampling', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlSampling.Layout.Row = 2;

            gridSampling = uigridlayout(pnlSampling,[3 2]);
            gridSampling.ColumnWidth = {'1x', 90};
            gridSampling.RowHeight = {CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.ButtonHeight, 'fit'};
            gridSampling.Padding =[5 5 5 5];
            gridSampling.BackgroundColor = panelBg;

            lblTolerance = uilabel(gridSampling, 'Text','Profile Tolerance [mm]:', 'HorizontalAlignment','right', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'FontColor',labelCol);
            lblTolerance.Layout.Row = 1; lblTolerance.Layout.Column = 1;

            app.ProfileTolSpinner = uispinner(gridSampling, 'Limits',[CNCHotWire_GCodeGenerator.MinProfileTolerance, CNCHotWire_GCodeGenerator.MaxProfileTolerance], 'Value',CNCHotWire_GCodeGenerator.DefaultProfileTolerance, 'Step',0.01, 'ValueDisplayFormat','%.2f', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'Tooltip', 'Adjust until the red/green extracted profiles conform to the mesh slice', 'ValueChangedFcn',@(src,~)app.onProfileToleranceChanged(src));
            app.ProfileTolSpinner.Layout.Row = 1; app.ProfileTolSpinner.Layout.Column = 2;
            app.ProfileTolerance = CNCHotWire_GCodeGenerator.DefaultProfileTolerance;

            app.BtnResetProfileTol = uibutton(gridSampling, 'Text','Reset Tolerance', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.onResetProfileTolerance());
            app.BtnResetProfileTol.Layout.Row = 2; app.BtnResetProfileTol.Layout.Column =[1 2];

            app.ProfilePointCountLabel = uilabel(gridSampling, 'Text','Extracted Profile Point Count (L/R): -- / --', 'HorizontalAlignment','center', 'FontColor',labelCol, 'FontAngle','italic', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
            app.ProfilePointCountLabel.Layout.Row = 3; app.ProfilePointCountLabel.Layout.Column =[1 2];

            %% --- 2. KERF COMPENSATION ---
            pnlKerf = uipanel(app.profilesLeft, 'Title','2. Kerf Compensation', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlKerf.Layout.Row = 3;

            gridKerf = uigridlayout(pnlKerf,[5 4]);
            gridKerf.ColumnWidth = {'fit', '1x', 'fit', '1x'};
            gridKerf.RowHeight = {CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.ButtonHeight, CNCHotWire_GCodeGenerator.ButtonHeight, 'fit'};
            gridKerf.Padding =[5 5 5 5];
            gridKerf.BackgroundColor = panelBg;

            lblKerfMode = uilabel(gridKerf, 'Text','Mode:', 'HorizontalAlignment','right', 'FontColor',labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
            lblKerfMode.Layout.Row = 1; lblKerfMode.Layout.Column = 1;

            app.KerfModeSwitch = uiswitch(gridKerf, 'slider', 'Items', {'Coupled', 'Independent'}, 'Value', 'Coupled', 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ValueChangedFcn', @(src,~)app.onKerfModeChanged(src));
            app.KerfModeSwitch.Layout.Row = 1; app.KerfModeSwitch.Layout.Column = [2 4];
            app.KerfModeSwitch.Tooltip = 'Uncoupling is only for tapered parts to compensate for the difference in wire speed between left and right profiles.';

            % Left Kerf
            lblKerfLeft = uilabel(gridKerf, 'Text','Left:', 'HorizontalAlignment','right', 'FontWeight','bold', 'FontColor',labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
            lblKerfLeft.Layout.Row = 2; lblKerfLeft.Layout.Column = 1;

            app.KerfLeftSpinner = uispinner(gridKerf, 'Limits',[CNCHotWire_GCodeGenerator.MinKerf, CNCHotWire_GCodeGenerator.MaxKerf], 'Value',app.KerfLeftValue, 'Step',0.1, 'ValueDisplayFormat','%.2f', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'Tooltip', 'Set Kerf: Note, offset distance = Kerf/2', 'ValueChangedFcn',@(src,~)app.onKerfLeftChanged(src));
            app.KerfLeftSpinner.Layout.Row = 2; app.KerfLeftSpinner.Layout.Column = 2;
            app.KerfLeftSpinner.FontColor = t.wireKerf;
            app.KerfLeftSpinner.BackgroundColor = t.planeRed * 0.15 + panelBg * 0.85;

            % Right Kerf
            lblKerfRight = uilabel(gridKerf, 'Text','Right:', 'HorizontalAlignment','right', 'FontWeight','bold', 'FontColor',labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
            lblKerfRight.Layout.Row = 2; lblKerfRight.Layout.Column = 3;

            app.KerfRightSpinner = uispinner(gridKerf, 'Limits',[CNCHotWire_GCodeGenerator.MinKerf, CNCHotWire_GCodeGenerator.MaxKerf], 'Value',app.KerfRightValue, 'Step',0.1, 'ValueDisplayFormat','%.2f', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'Enable', 'off', 'ValueChangedFcn',@(src,~)app.onKerfRightChanged(src));
            app.KerfRightSpinner.Layout.Row = 2; app.KerfRightSpinner.Layout.Column = 4;
            app.KerfRightSpinner.FontColor = t.wireKerf;
            app.KerfRightSpinner.BackgroundColor = t.planeGreen * 0.15 + panelBg * 0.85;

            % Buttons
            app.BtnResetKerf = uibutton(gridKerf, 'Text','Reset Kerf', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.onResetKerf());
            app.BtnResetKerf.Layout.Row = 3; app.BtnResetKerf.Layout.Column = [1 4];

            app.BtnApplyKerf = uibutton(gridKerf, 'Text','Apply Kerf Offset', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.onApplyKerf());
            app.BtnApplyKerf.Layout.Row = 4; app.BtnApplyKerf.Layout.Column = [1 4];

            % Points Readout
            app.KerfPointCountLabel = uilabel(gridKerf, 'Text','Kerf Compensated Point Count (L/R): 0 / 0', 'HorizontalAlignment','center', 'FontColor',labelCol, 'FontAngle','italic', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
            app.KerfPointCountLabel.Layout.Row = 5; app.KerfPointCountLabel.Layout.Column = [1 4];

            %% --- 3. GUIDANCE ---
            pnlGuide = uipanel(app.profilesLeft, 'Title', 'Guidance', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType', 'line');
            pnlGuide.Layout.Row = 4;
            glGuide = uigridlayout(pnlGuide, [1 1]);
            glGuide.Padding =[0 0 0 0];
            glGuide.BackgroundColor = panelBg;

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

            app.TxtProfileGuide = uitextarea(glGuide, 'Editable','off', 'Value', guideText, 'BackgroundColor', panelBg, 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            %% --- 4. STATUS ---
            pnlStatus = uipanel(app.profilesLeft, 'Title', 'Status', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType', 'line');
            pnlStatus.Layout.Row = 5;
            glStatus = uigridlayout(pnlStatus, [1 1]);
            glStatus.Padding = [0 0 0 0];
            glStatus.BackgroundColor = panelBg;

            app.TxtProfileStatus = uitextarea(glStatus, 'Editable','off', 'Value', {''}, 'BackgroundColor', t.panelBg, 'FontColor',[1 0.8 0], 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            %% --- ACTION BUTTONS ---
            gridBtn = uigridlayout(app.profilesLeft,[1 1]);
            gridBtn.Layout.Row = 6;
            gridBtn.RowHeight = {CNCHotWire_GCodeGenerator.ButtonHeight};
            gridBtn.Padding=[0 0 0 0];
            gridBtn.BackgroundColor=panelBg;

            app.BtnProfilesContinue = uibutton(gridBtn, 'Text','Continue →', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'Enable', 'off', 'BackgroundColor',[0.3 0.3 0.3], 'FontColor',[0.8 0.8 0.8], 'ButtonPushedFcn',@(~,~)app.onContinue());

            %% --- RIGHT PANEL: 2D PLOTS ---
            gridRight = uigridlayout(app.GLProfiles,[2 1]);
            gridRight.Layout.Column = 2;
            gridRight.RowHeight = {'1x','1x'};
            gridRight.Padding = [0 0 0 0];
            gridRight.RowSpacing = 5;
            gridRight.BackgroundColor = sideBg;

            app.AxLeftProfile = uiaxes(gridRight);
            app.AxLeftProfile.BackgroundColor = t.axBg;
            title(app.AxLeftProfile,'Left Profile');
            grid(app.AxLeftProfile,'on');
            axis(app.AxLeftProfile,'equal');

            app.AxRightProfile = uiaxes(gridRight);
            app.AxRightProfile.BackgroundColor = t.axBg;
            title(app.AxRightProfile,'Right Profile');
            grid(app.AxRightProfile,'on');
            axis(app.AxRightProfile,'equal');
        end

        % TAB 4 (BILLET)
        function createBilletTab(app)
            % Purpose: Builds the Billet sizing and positioning tab UI components.
            %
            % Layout Strategy:
            %   - Left Panel (320px): Controls for auto-fitting, manual sizing,
            %     and positioning the model within the stock material.
            %   - Right Panel (1x): 4-way split view (Top, Front, Right, Iso)
            %     to visualize the model inside the billet.
            %
            % Alignment Note: The 'Size' and 'Position' grids use an identical
            % 7-column layout to ensure their input fields align perfectly vertically.
            %
            % Dependencies: app.getTheme(), CNCHotWire_GCodeGenerator_V1 UI Constants

            % 1. Fetch Theme Colors locally
            t = app.getTheme();
            sideBg   = t.sideBg;
            panelBg  = t.panelBg;
            labelCol = t.labelCol;
            inputBg  = t.inputBg;
            inputTxt = t.inputTxt;
            edgeBuffer = app.ModelEdgeWarningBuffer;

            % 2. Main Tab Container
            app.TabBillet = uitab(app.TabGroup, 'Title', 'Billet');

            app.GLBillet = uigridlayout(app.TabBillet,[1 2]);
            app.GLBillet.ColumnWidth = {CNCHotWire_GCodeGenerator.PanelWidth, '1x'};
            app.GLBillet.Padding = app.getTabPadding();
            app.GLBillet.ColumnSpacing = 5;
            app.GLBillet.BackgroundColor = sideBg;

            %% --- LEFT CONTROL PANEL (Sidebar) ---
            app.BilletLeftPanel = uigridlayout(app.GLBillet,[7 1]);
            app.BilletLeftPanel.Layout.Column = 1;

            % Rows: 1:View, 2:Auto, 3:Size, 4:Position, 5:Guidance(1x), 6:Status(70px), 7:Continue
            app.BilletLeftPanel.RowHeight = {'fit','fit','fit','fit','1x',70, CNCHotWire_GCodeGenerator.ButtonHeight};
            app.BilletLeftPanel.Padding =[5 5 5 5];
            app.BilletLeftPanel.RowSpacing = CNCHotWire_GCodeGenerator.BlockSpacing;
            app.BilletLeftPanel.BackgroundColor = panelBg; % Distinct sidebar shade

            %% --- VIEW CONTROLS (Unnumbered) ---
            % Purpose: Toggles the 4-way plot between Billet-centric and Model-centric limits
            pnlView = uipanel(app.BilletLeftPanel, 'Title','View', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlView.Layout.Row = 1;

            gridView = uigridlayout(pnlView,[1 2]);
            gridView.Padding=[5 5 5 5];
            gridView.ColumnSpacing = 5;
            gridView.RowHeight = {CNCHotWire_GCodeGenerator.ButtonHeight};
            gridView.BackgroundColor=panelBg;

            btnViewModel = uibutton(gridView, 'Text','Model View', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.onResetBilletViewModel());
            btnViewBillet = uibutton(gridView, 'Text','Billet View', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.onResetBilletViewBillet());

            %% --- 1. AUTO TOOLS ---
            % Purpose: One-click buttons to perfectly size and position the billet
            pnlAutoTools = uipanel(app.BilletLeftPanel, 'Title','1. Auto Tools', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlAutoTools.Layout.Row = 2;

            gridAutoTools = uigridlayout(pnlAutoTools,[1 2]);
            gridAutoTools.Padding=[5 5 5 5];
            gridAutoTools.ColumnSpacing = 5;
            gridAutoTools.RowHeight = {CNCHotWire_GCodeGenerator.ButtonHeight};
            gridAutoTools.BackgroundColor=panelBg;

            app.BtnAutoFitBillet = uibutton(gridAutoTools, 'Text', 'Auto-fit Billet', 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn', @(~,~)app.onAutoFitBillet());
            app.BtnAutoFitBillet.Tooltip = sprintf('Size the billet from the active cutting geometry with %g mm Y/Z edge buffers.', edgeBuffer);
            app.BtnAutoPositionModel = uibutton(gridAutoTools, 'Text', 'Auto-position Model', 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn', @(~,~)app.onAutoPositionModel());
            app.BtnAutoPositionModel.Tooltip = sprintf('Position the model near the left, front and top billet faces using the configured %g mm Y/Z edge buffer.', edgeBuffer);
            %% --- 2. SIZE CONTROLS ---
            % Purpose: Manual overrides for the physical stock dimensions
            pnlSize = uipanel(app.BilletLeftPanel, 'Title', '2. Billet Size Controls', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType', 'line');
            pnlSize.Layout.Row = 3;

            % 7-Column Grid to perfectly match the Position block below it.
            % Col 1 increased to 40px to prevent 'Axis' cropping.
            gridSize = uigridlayout(pnlSize, [4 7]);
            gridSize.ColumnWidth = {40, '1x', 26, 55, 26, '1x', CNCHotWire_GCodeGenerator.ButtonHeight};
            gridSize.RowHeight = {CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.RowHeightNormal};
            gridSize.Padding =[5 5 5 5];
            gridSize.ColumnSpacing = 4;
            gridSize.RowSpacing = 2;
            gridSize.BackgroundColor = panelBg;

            % Headers
            uilabel(gridSize, 'Text', 'Axis', 'FontWeight', 'bold', 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment', 'center');

            lblStockHeader = uilabel(gridSize, 'Text', 'Stock [mm]', 'FontWeight', 'bold', 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment', 'center');
            lblStockHeader.Layout.Column = [3 5]; % Spans the -, Edit, and + columns

            lblModelHeader = uilabel(gridSize, 'Text', 'Model', 'FontWeight', 'bold', 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment', 'center');
            lblModelHeader.Layout.Column =[6 7]; % Spans into dummy column to prevent cropping!

            axisLabels = {'X','Y','Z'};
            sizeTooltips = {'Length (Span)', 'Depth (Y)', 'Height (Z)'};

            app.BilletSizeEdits = gobjects(1,3);
            app.BilletSizeMinusBtns = gobjects(1,3);
            app.BilletSizePlusBtns = gobjects(1,3);
            app.BilletModelDimLabels = gobjects(1,3);

            for i = 1:3
                r = i + 1;
                % Axis Label (Col 1)
                txtLabel = uilabel(gridSize, 'Text', axisLabels{i}, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
                txtLabel.Layout.Row = r; txtLabel.Layout.Column = 1;

                % Minus Button (Col 3)
                app.BilletSizeMinusBtns(i) = uibutton(gridSize, 'Text', '-', 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn', @(~,~)app.onBilletSizeStep(i,-1));
                app.BilletSizeMinusBtns(i).Layout.Row = r; app.BilletSizeMinusBtns(i).Layout.Column = 3;

                % Edit Field (Col 4)
                app.BilletSizeEdits(i) = uieditfield(gridSize, 'numeric', 'Value', 100, 'HorizontalAlignment', 'center', 'ValueDisplayFormat', '%.2f', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'Tooltip', sizeTooltips{i}, 'ValueChangedFcn', @(src,~)app.onBilletSizeEdited(i,src));
                app.BilletSizeEdits(i).Layout.Row = r; app.BilletSizeEdits(i).Layout.Column = 4;
                % Note: Background color is applied by applyTheme() using t.shiftBg

                % Plus Button (Col 5)
                app.BilletSizePlusBtns(i) = uibutton(gridSize, 'Text', '+', 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn', @(~,~)app.onBilletSizeStep(i,+1));
                app.BilletSizePlusBtns(i).Layout.Row = r; app.BilletSizePlusBtns(i).Layout.Column = 5;

                % Model Dim Readout (Col 6 & 7)
                app.BilletModelDimLabels(i) = uilabel(gridSize, 'Text', '(---)', 'HorizontalAlignment', 'center', 'BackgroundColor', t.readoutBg, 'FontColor', t.readoutTxt, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
                app.BilletModelDimLabels(i).Layout.Row = r; app.BilletModelDimLabels(i).Layout.Column = [6 7];
            end

            %% --- 3. POSITION CONTROLS ---
            % Purpose: Manual overrides for shifting the model inside the stock
            pnlPos = uipanel(app.BilletLeftPanel, 'Title', '3. Model Position in Stock', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType', 'line');
            pnlPos.Layout.Row = 4;

            % 7-Column Grid matching the Size block exactly.
            % Col 7 holds the vertical Reset button spanning rows 2-4.
            gridPos = uigridlayout(pnlPos, [4 7]);
            gridPos.ColumnWidth = {40, '1x', 26, 55, 26, '1x', CNCHotWire_GCodeGenerator.ButtonHeight};
            gridPos.RowHeight = {CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.RowHeightNormal};
            gridPos.Padding =[5 5 5 5];
            gridPos.ColumnSpacing = 4;
            gridPos.RowSpacing = 2;
            gridPos.BackgroundColor = panelBg;

            % Headers
            uilabel(gridPos, 'Text', 'Axis', 'FontWeight', 'bold', 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment', 'center');

            lblNegHeader = uilabel(gridPos, 'Text', '-ive Gap', 'FontWeight', 'bold', 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment', 'center');
            lblNegHeader.Layout.Column = 2;

            lblShiftHeader = uilabel(gridPos, 'Text', 'Shift[mm]', 'FontWeight', 'bold', 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment', 'center');
            lblShiftHeader.Layout.Column =[3 5]; % Spans -, Edit, +

            lblPosHeader = uilabel(gridPos, 'Text', '+ive Gap', 'FontWeight', 'bold', 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment', 'center');
            lblPosHeader.Layout.Column = 6;

            app.BilletNegOffsetEdits = gobjects(1,3);
            app.BilletCenterOffsetEdits = gobjects(1,3);
            app.BilletPosOffsetEdits = gobjects(1,3);

            for i = 1:3
                r = i + 1;
                % Axis Label (Col 1)
                txtLabelP = uilabel(gridPos, 'Text', axisLabels{i}, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
                txtLabelP.Layout.Row = r; txtLabelP.Layout.Column = 1;

                % Negative Gap Edit (Col 2)
                app.BilletNegOffsetEdits(i) = uieditfield(gridPos, 'numeric', 'HorizontalAlignment', 'center', 'ValueDisplayFormat', '%.2f', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'BackgroundColor', inputBg, 'FontColor', inputTxt, 'ValueChangedFcn', @(src,~)app.onBilletOffsetEdited(i,"neg",src));
                app.BilletNegOffsetEdits(i).Layout.Row = r; app.BilletNegOffsetEdits(i).Layout.Column = 2;
                app.BilletNegOffsetEdits(i).Tooltip = 'Axis offset between model and billet edge (min axes value)';

                % Minus Button (Col 3)
                btnMinus = uibutton(gridPos, 'Text', '-', 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn', @(~,~)app.onBilletShift(i,-0.5));
                btnMinus.Layout.Row = r; btnMinus.Layout.Column = 3;

                % Center Shift Edit (Col 4)
                app.BilletCenterOffsetEdits(i) = uieditfield(gridPos, 'numeric', 'HorizontalAlignment', 'center', 'ValueDisplayFormat', '%.2f', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ValueChangedFcn', @(src,~)app.onBilletOffsetEdited(i,"center",src));
                app.BilletCenterOffsetEdits(i).Layout.Row = r; app.BilletCenterOffsetEdits(i).Layout.Column = 4;
                app.BilletCenterOffsetEdits(i).Tooltip = 'Offset in axis relative to imported model origin';
                % Note: Background color is applied by applyTheme() using t.shiftBg

                % Plus Button (Col 5)
                btnPlus = uibutton(gridPos, 'Text', '+', 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn', @(~,~)app.onBilletShift(i,+0.5));
                btnPlus.Layout.Row = r; btnPlus.Layout.Column = 5;

                % Positive Gap Edit (Col 6)
                app.BilletPosOffsetEdits(i) = uieditfield(gridPos, 'numeric', 'HorizontalAlignment', 'center', 'ValueDisplayFormat', '%.2f', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'BackgroundColor', inputBg, 'FontColor', inputTxt, 'ValueChangedFcn', @(src,~)app.onBilletOffsetEdited(i,"pos",src));
                app.BilletPosOffsetEdits(i).Layout.Row = r; app.BilletPosOffsetEdits(i).Layout.Column = 6;
                app.BilletPosOffsetEdits(i).Tooltip = 'Axis offset between model and billet edge (max axes value)';
            end

            % Vertical Reset Button (Col 7, spanning rows 2-4)
            vertText = sprintf('R\nE\nS\nE\nT');
            app.BtnResetPosition = uibutton(gridPos, 'Text', vertText, 'FontWeight', 'bold', 'FontSize', 10, 'Tooltip', 'Reset Position', 'ButtonPushedFcn', @(~,~)app.onResetPosition());
            app.BtnResetPosition.Layout.Row =[2 4];
            app.BtnResetPosition.Layout.Column = 7;

            %% --- 4. GUIDANCE ---
            % Purpose: Instructions for reducing foam waste
            pnlGuide = uipanel(app.BilletLeftPanel, 'Title', 'Guidance', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType', 'line');
            pnlGuide.Layout.Row = 5;
            glGuide = uigridlayout(pnlGuide, [1 1]);
            glGuide.Padding =[0 0 0 0]; % Zero padding for max text space
            glGuide.BackgroundColor = panelBg;

            guideTxt = {
                'REDUCE FOAM WASTE!'
                'This tab identifies what size billet is needed and positions the model within the billet.'
                'Find the smallest scrap block in the cupboard that is just large enough to fit the model before trimming on the manual hot wire cutters.'
                sprintf('The configured boundary around the model in Y and Z is %g mm.', edgeBuffer)
                ''
                '1. Use the auto-fit billet and position buttons!'
                ''
                '2. Adjust using the control blocks if needed.'
                };
            app.TxtBilletGuide = uitextarea(glGuide, 'Editable', 'off', 'Value', guideTxt, 'BackgroundColor', panelBg, 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            %% --- 5. STATUS ---
            % Purpose: Traffic light feedback for model containment
            pnlStatus = uipanel(app.BilletLeftPanel, 'Title', 'Status', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType', 'line');
            pnlStatus.Layout.Row = 6;
            glStatus = uigridlayout(pnlStatus,[1 1]);
            glStatus.Padding =[0 0 0 0];
            glStatus.BackgroundColor = panelBg;

            app.TxtBilletStatus = uitextarea(glStatus, 'Editable', 'off', 'Value', {''}, 'BackgroundColor', t.panelBg, 'FontColor', [1 0.8 0], 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            %% --- 6. ACTION BUTTONS ---
            gridBtn = uigridlayout(app.BilletLeftPanel,[1 1]);
            gridBtn.Layout.Row = 7;
            gridBtn.RowHeight = {CNCHotWire_GCodeGenerator.ButtonHeight};
            gridBtn.Padding=[0 0 0 0];
            gridBtn.BackgroundColor=panelBg;

            app.BtnBilletContinue = uibutton(gridBtn, 'Text', 'Continue →', 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'BackgroundColor',[0.1 0.6 0.1], 'FontColor',[1 1 1], 'ButtonPushedFcn', @(~,~)app.onContinue());

            %% --- RIGHT PANEL: 4 VIEWS ---
            app.BilletRightPanel = uigridlayout(app.GLBillet,[2 2]);
            app.BilletRightPanel.Layout.Column = 2;
            app.BilletRightPanel.RowHeight = {'1x', '1x'};
            app.BilletRightPanel.ColumnWidth = {'1x', '1x'};
            app.BilletRightPanel.Padding = [0 0 0 0];
            app.BilletRightPanel.RowSpacing = 5;
            app.BilletRightPanel.ColumnSpacing = 5;
            app.BilletRightPanel.BackgroundColor = sideBg;

            % Top Left
            app.AxBilletTop = uiaxes(app.BilletRightPanel);
            app.AxBilletTop.Layout.Row = 1; app.AxBilletTop.Layout.Column = 1;
            app.AxBilletTop.BackgroundColor = t.axBg;
            title(app.AxBilletTop, 'Top View (X/Y)');

            % Top Right (ISO)
            app.AxBilletIso = uiaxes(app.BilletRightPanel);
            app.AxBilletIso.Layout.Row = 1; app.AxBilletIso.Layout.Column = 2;
            app.AxBilletIso.BackgroundColor = t.axBg;
            title(app.AxBilletIso, 'Iso View');
            view(app.AxBilletIso, 3); grid(app.AxBilletIso, 'on');

            % Bottom Left
            app.AxBilletFront = uiaxes(app.BilletRightPanel);
            app.AxBilletFront.Layout.Row = 2; app.AxBilletFront.Layout.Column = 1;
            app.AxBilletFront.BackgroundColor = t.axBg;
            title(app.AxBilletFront, 'Front View (X/Z)');

            % Bottom Right
            app.AxBilletRight = uiaxes(app.BilletRightPanel);
            app.AxBilletRight.Layout.Row = 2; app.AxBilletRight.Layout.Column = 2;
            app.AxBilletRight.BackgroundColor = t.axBg;
            title(app.AxBilletRight, 'Right View (Y/Z)');
        end

        % TAB 5 (MACHINE)
        function createMachineTab(app)
            % Purpose: Builds the Machine Setup and Billet placement tab UI components.
            %
            % Layout Strategy:
            %   - Left Panel (320px): Controls for machine view, auto-positioning,
            %     and manual billet placement on the machine bed.
            %   - Right Panel (1x): 3D interactive visualization of the machine.
            %
            % Dependencies: app.getTheme(), CNCHotWire_GCodeGenerator_V1 UI Constants

            % 1. Fetch Theme Colors locally
            t = app.getTheme();
            sideBg   = t.sideBg;
            panelBg  = t.panelBg;
            labelCol = t.labelCol;

            % 2. Main Tab Container
            app.TabMachine = uitab(app.TabGroup, 'Title', 'Machine');

            app.GLMachine = uigridlayout(app.TabMachine,[1 2]);
            app.GLMachine.ColumnWidth = {CNCHotWire_GCodeGenerator.PanelWidth, '1x'};
            app.GLMachine.Padding = app.getTabPadding();
            app.GLMachine.ColumnSpacing = 5;
            app.GLMachine.BackgroundColor = sideBg;

            %% --- LEFT CONTROL PANEL (Sidebar) ---
            app.MachineLeftPanel = uigridlayout(app.GLMachine,[6 1]);

            % Rows: 1:View, 2:Auto, 3:Placement, 4:Guidance(1x), 5:Status(70px), 6:Continue
            app.MachineLeftPanel.RowHeight = {'fit','fit','fit','1x',70, CNCHotWire_GCodeGenerator.ButtonHeight};
            app.MachineLeftPanel.Padding =[5 5 5 5];
            app.MachineLeftPanel.RowSpacing = CNCHotWire_GCodeGenerator.BlockSpacing;
            app.MachineLeftPanel.BackgroundColor = panelBg; % Distinct sidebar shade

            %% --- VIEW CONTROLS (Unnumbered) ---
            pnlView = uipanel(app.MachineLeftPanel, 'Title','View', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlView.Layout.Row = 1;

            gridView = uigridlayout(pnlView,[1 2]);
            gridView.Padding=[5 5 5 5];
            gridView.ColumnSpacing = 5;
            gridView.RowHeight = {CNCHotWire_GCodeGenerator.ButtonHeight};
            gridView.BackgroundColor=panelBg;

            btnViewMachine = uibutton(gridView, 'Text','Machine View', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.onResetMachineViewMachine());
            btnViewBillet = uibutton(gridView, 'Text','Billet View', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.onResetMachineViewBillet());

            %% --- 1. AUTO TOOLS ---
            pnlAutoTools = uipanel(app.MachineLeftPanel, 'Title','1. Auto Tools', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlAutoTools.Layout.Row = 2;

            gridAutoTools = uigridlayout(pnlAutoTools,[1 1]);
            gridAutoTools.Padding=[5 5 5 5];
            gridAutoTools.RowHeight = {CNCHotWire_GCodeGenerator.ButtonHeight};
            gridAutoTools.BackgroundColor=panelBg;

            btnAutoPosition = uibutton(gridAutoTools, 'Text','Auto-position Billet', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.onResetMachineBilletPosition());
            btnAutoPosition.Tooltip = 'Optimizes X position to balance tower wire lengths, snaps Z to standard stock heights, and rounds Y to a safe distance.';

            %% --- 2. BILLET PLACEMENT ---
            pnlPlacement = uipanel(app.MachineLeftPanel, 'Title','2. Billet Placement', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlPlacement.Layout.Row = 3;

            gridPlacement = uigridlayout(pnlPlacement,[4 2]);
            gridPlacement.ColumnWidth={'1x',110};
            gridPlacement.RowHeight={CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.RowHeightNormal};
            gridPlacement.Padding=[10 5 10 5];
            gridPlacement.BackgroundColor=panelBg;

            lblAxisHeader = uilabel(gridPlacement, 'Text','Axis', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'FontColor',labelCol);
            lblAxisHeader.Layout.Row=1;

            lblPosHeader = uilabel(gridPlacement, 'Text','Pos [mm]', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'FontColor',labelCol);
            lblPosHeader.Layout.Column=2;

            mAxisLabels = {'X (Left Bed Edge)','Y (Home Position)','Z (Bed Surface)'};
            mTooltips   = { ...
                "Distance from the LEFT edge of the physical bed to the left face of the billet.", ...
                "Distance from the front 'HOME' position to the front face of the billet.", ...
                "Distance from the BED SURFACE to the bottom of the billet." ...
                };

            app.MachinePosSpinners = gobjects(1,3);
            for i=1:3
                lblAxisRow = uilabel(gridPlacement, 'Text',mAxisLabels{i}, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'FontColor',labelCol);
                lblAxisRow.Layout.Row=i+1;

                app.MachinePosSpinners(i) = uispinner(gridPlacement, 'Limits',[-500 2000], 'Value',app.MachineBilletPos(i), 'ValueDisplayFormat','%.2f', 'Step',1.0, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'Tooltip', mTooltips{i}, 'ValueChangedFcn',@(src,~)app.onMachinePosEdited(i,src));
                app.MachinePosSpinners(i).Layout.Row=i+1;
                app.MachinePosSpinners(i).Layout.Column=2;
            end

            %% --- 3. GUIDANCE ---
            pnlGuide = uipanel(app.MachineLeftPanel, 'Title', 'Guidance', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType', 'line');
            pnlGuide.Layout.Row = 4;
            glGuide = uigridlayout(pnlGuide,[1 1]);
            glGuide.Padding = [0 0 0 0];
            glGuide.BackgroundColor = panelBg;

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
            app.TxtMachineGuide = uitextarea(glGuide, 'Editable','off', 'Value', guideMach, 'BackgroundColor', panelBg, 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            %% --- 4. STATUS ---
            pnlStatus = uipanel(app.MachineLeftPanel, 'Title', 'Status', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType', 'line');
            pnlStatus.Layout.Row = 5;
            glStatus = uigridlayout(pnlStatus,[1 1]);
            glStatus.Padding = [0 0 0 0];
            glStatus.BackgroundColor = panelBg;

            app.TxtMachineStatus = uitextarea(glStatus, 'Editable','off', 'Value', {'Machine configuration valid.'}, 'BackgroundColor', t.panelBg, 'FontColor',[1 0.8 0], 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            %% --- 5. ACTION BUTTONS ---
            gridBtn = uigridlayout(app.MachineLeftPanel,[1 1]);
            gridBtn.Layout.Row = 6;
            gridBtn.RowHeight = {CNCHotWire_GCodeGenerator.ButtonHeight};
            gridBtn.Padding=[0 0 0 0];
            gridBtn.BackgroundColor=panelBg;

            app.BtnMachineContinue = uibutton(gridBtn, 'Text','Continue →', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'BackgroundColor',[0.1 0.6 0.1], 'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~)app.onContinue());

            %% --- RIGHT PANEL: 3D MACHINE PLOT ---
            app.AxMachine = uiaxes(app.GLMachine);
            app.AxMachine.Layout.Column=2;
            app.AxMachine.BackgroundColor=t.axBg;
            grid(app.AxMachine,'on');
            view(app.AxMachine,3);
            hold(app.AxMachine,'on');
        end

        % TAB 6 (CUTTING STRATEGY)
        function createCuttingTab(app)
            % Purpose: Builds the Cutting Strategy (Lead-in/Start points) tab UI components.
            %
            % Layout Strategy:
            %   - Left Panel (320px): Controls for auto/manual selection of start
            %     points, lead-in paths, and cut direction.
            %   - Right Panel (1x): 2D axes showing the left and right cut paths.
            %
            % Dependencies: app.getTheme(), app.getInteractionColors(), CNCHotWire_GCodeGenerator_V1 UI Constants

            % 1. Fetch Theme Colors locally
            t = app.getTheme();
            sideBg   = t.sideBg;
            panelBg  = t.panelBg;
            labelCol = t.labelCol;

            % 2. Main Tab Container
            app.TabCutting = uitab(app.TabGroup, 'Title', 'Cutting Strategy');

            app.GLCutting = uigridlayout(app.TabCutting, [2 2]);
            app.GLCutting.ColumnWidth   = {CNCHotWire_GCodeGenerator.PanelWidth, '1x'};
            app.GLCutting.RowHeight     = {'1x', '1x'};
            app.GLCutting.Padding       = app.getTabPadding();
            app.GLCutting.ColumnSpacing = 5;
            app.GLCutting.BackgroundColor = sideBg;

            %% --- LEFT CONTROL PANEL (Sidebar) ---
            % Spans both rows on the left side
            app.CuttingLeftPanel = uigridlayout(app.GLCutting,[7 1]);
            app.CuttingLeftPanel.Layout.Row     = [1 2];
            app.CuttingLeftPanel.Layout.Column  = 1;

            % Rows: 1:View, 2:Auto, 3:Modes, 4:Interaction, 5:Guidance(1x), 6:Status(70px), 7:Continue
            app.CuttingLeftPanel.RowHeight = {'fit','fit','fit','fit','1x',70, CNCHotWire_GCodeGenerator.ButtonHeight};
            app.CuttingLeftPanel.Padding   = [5 5 5 5];
            app.CuttingLeftPanel.RowSpacing = CNCHotWire_GCodeGenerator.BlockSpacing;
            app.CuttingLeftPanel.BackgroundColor = panelBg; % Distinct sidebar shade

            %% --- VIEW CONTROLS (Unnumbered) ---
            pnlView = uipanel(app.CuttingLeftPanel, 'Title','View', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlView.Layout.Row = 1;

            gridView = uigridlayout(pnlView, [1 2]);
            gridView.Padding=[5 5 5 5];
            gridView.ColumnSpacing=5;
            gridView.RowHeight = {CNCHotWire_GCodeGenerator.ButtonHeight};
            gridView.BackgroundColor=panelBg;

            btnViewMachine = uibutton(gridView, 'Text','Machine View', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.onResetCuttingViewMachine());
            btnViewBillet = uibutton(gridView, 'Text','Billet View', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.onResetCuttingViewBillet());

            %% --- 1. AUTO TOOLS ---
            pnlAuto = uipanel(app.CuttingLeftPanel, 'Title','1. Auto Tools', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlAuto.Layout.Row = 2;

            gridAuto = uigridlayout(pnlAuto, [1 2]);
            gridAuto.Padding=[5 5 5 5];
            gridAuto.ColumnSpacing=5;
            gridAuto.RowHeight = {CNCHotWire_GCodeGenerator.ButtonHeight};
            gridAuto.BackgroundColor=panelBg;

            app.btnAutoStart = uibutton(gridAuto, 'Text','Auto Start', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.onAutoStart());
            app.btnAutoStart.Tooltip = 'Automatically selects the start point closest to the front of the machine (Minimum Y).';

            app.btnAutoEntry = uibutton(gridAuto, 'Text','Auto Entry', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.onAutoEntry());
            app.btnAutoEntry.Tooltip = 'Automatically calculates a perpendicular entry path from outside the billet boundary.';

            %% --- 2. MODES ---
            pnlMode = uipanel(app.CuttingLeftPanel, 'Title','2. Modes', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlMode.Layout.Row = 3;

            gridMode = uigridlayout(pnlMode,[3 2]);
            gridMode.RowHeight = {CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.RowHeightNormal};
            gridMode.ColumnWidth = {75, '1x'};
            gridMode.Padding=[5 5 5 5];
            gridMode.BackgroundColor=panelBg;

            lblDirection = uilabel(gridMode, 'Text','Direction:', 'FontColor',labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment','right');
            lblDirection.Layout.Row=1;

            app.SwitchCutDir = uiswitch(gridMode, 'slider', 'Items',{'Top (CW)', 'Bottom (CCW)'}, 'Value','Top (CW)', 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ValueChangedFcn',@(~,~)app.onCutDirectionChanged());
            app.SwitchCutDir.Layout.Row=1;
            app.SwitchCutDir.Layout.Column=2;
            app.SwitchCutDir.Tooltip = 'Choses which way around the profile loop the wire goes from the start point';

            lblSyncStart = uilabel(gridMode, 'Text','Start Pts:', 'FontColor',labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment','right');
            lblSyncStart.Layout.Row=2;

            app.SwitchSyncStart = uiswitch(gridMode, 'slider', 'Items',{'Coupled', 'Independent'}, 'Value','Coupled', 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ValueChangedFcn',@(src,~)app.onSyncToggleChanged(src));
            app.SwitchSyncStart.Layout.Row=2;
            app.SwitchSyncStart.Layout.Column=2;
            app.SwitchSyncStart.Tooltip = 'If there are profile sync issues, decouple and manually select start points for each profile';

            lblSyncEntry = uilabel(gridMode, 'Text','Entry Pts:', 'FontColor',labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment','right');
            lblSyncEntry.Layout.Row=3;

            app.SwitchSyncEntry = uiswitch(gridMode, 'slider', 'Items',{'Coupled', 'Independent'}, 'Value','Coupled', 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ValueChangedFcn',@(src,~)app.onSyncEntryToggleChanged(src));
            app.SwitchSyncEntry.Layout.Row=3;
            app.SwitchSyncEntry.Layout.Column=2;
            app.SwitchSyncEntry.Tooltip = 'Independent entry points can be useful for very tapered or swept parts, entering from the top to reduce waste material';

            %% --- 3. MOUSE INTERACTION ---
            pnlInteraction = uipanel(app.CuttingLeftPanel, 'Title','3. Mouse Interaction', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlInteraction.Layout.Row = 4;

            % 4 Rows for buttons
            gridInteraction = uigridlayout(pnlInteraction, [4 2]);
            gridInteraction.RowHeight = {'fit', CNCHotWire_GCodeGenerator.ButtonHeight, CNCHotWire_GCodeGenerator.ButtonHeight, CNCHotWire_GCodeGenerator.ButtonHeight};
            gridInteraction.Padding=[5 5 5 5];
            gridInteraction.BackgroundColor=panelBg;

            lblInstruction = uilabel(gridInteraction, 'Text','Click plot to set:', 'FontColor',labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
            lblInstruction.Layout.Row=1;
            lblInstruction.Layout.Column=[1 2];

            bCols = app.getInteractionColors();

            % Start (Green) & Lead In (Orange)
            app.BtnPickStart = uibutton(gridInteraction, 'state', 'Text','Start Pt', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, ...
                'BackgroundColor',bCols.StartInactive, 'FontColor',bCols.TextInactive, ...
                'Tooltip','First point on the profile cut.', ...
                'ValueChangedFcn',@(src,evt)app.onInteractionStatsChanged(src));
            app.BtnPickStart.Layout.Row=2; app.BtnPickStart.Layout.Column=1;

            app.BtnPickEntry = uibutton(gridInteraction, 'state', 'Text','Lead In', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, ...
                'BackgroundColor',bCols.EntryInactive, 'FontColor',bCols.TextInactive, ...
                'Tooltip','Point outside billet where cut begins (Orange line).', ...
                'ValueChangedFcn',@(src,evt)app.onInteractionStatsChanged(src));
            app.BtnPickEntry.Layout.Row=2; app.BtnPickEntry.Layout.Column=2;

            % Link 1 & Link 2 (Yellow)
            app.BtnPickEntry2 = uibutton(gridInteraction, 'state', 'Text','Link 1', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, ...
                'BackgroundColor',bCols.LinkInactive, 'FontColor',bCols.TextInactive, ...
                'Tooltip','Rapid move point before Lead In.', ...
                'ValueChangedFcn',@(src,evt)app.onInteractionStatsChanged(src));
            app.BtnPickEntry2.Layout.Row=3; app.BtnPickEntry2.Layout.Column=1;

            app.BtnPickEntry3 = uibutton(gridInteraction, 'state', 'Text','Link 2', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, ...
                'BackgroundColor',bCols.LinkInactive, 'FontColor',bCols.TextInactive, ...
                'Tooltip','Optional 2nd Rapid move point (useful to got over the top of the block.', ...
                'ValueChangedFcn',@(src,evt)app.onInteractionStatsChanged(src));
            app.BtnPickEntry3.Layout.Row=3; app.BtnPickEntry3.Layout.Column=2;

            % Clear
            btnClear = uibutton(gridInteraction, 'Text','Clear Pts', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, ...
                'BackgroundColor',t.accentBg, 'FontColor',t.editTxt, ...
                'Tooltip','Reset entry/link points.', ...
                'ButtonPushedFcn',@(~,~)app.onClearEntries());
            btnClear.Layout.Row=4; btnClear.Layout.Column=[1 2];

            %% --- GUIDANCE (Unnumbered) ---
            pnlGuide = uipanel(app.CuttingLeftPanel, 'Title', 'Guidance', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType', 'line');
            pnlGuide.Layout.Row = 5;
            glGuide = uigridlayout(pnlGuide, [1 1]);
            glGuide.Padding = [0 0 0 0]; % Zero padding for max text space
            glGuide.BackgroundColor = panelBg;

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
            app.TxtCuttingGuide = uitextarea(glGuide, 'Editable','off', 'Value', guideCut, 'BackgroundColor', panelBg, 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            %% --- STATUS (Unnumbered) ---
            pnlStatus = uipanel(app.CuttingLeftPanel, 'Title', 'Status', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType', 'line');
            pnlStatus.Layout.Row = 6;
            glStatus = uigridlayout(pnlStatus, [1 1]);
            glStatus.Padding = [0 0 0 0];
            glStatus.BackgroundColor = panelBg;

            app.TxtCuttingStatus = uitextarea(glStatus, 'Editable','off', 'Value', {'Strategy valid.', 'Review paths and continue.'}, 'BackgroundColor', t.panelBg, 'FontColor',[0.4 1 0.4], 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            %% --- ACTION BUTTONS ---
            gridBtn = uigridlayout(app.CuttingLeftPanel,[1 1]);
            gridBtn.Layout.Row = 7;
            gridBtn.RowHeight = {CNCHotWire_GCodeGenerator.ButtonHeight};
            gridBtn.Padding=[0 0 0 0];
            gridBtn.BackgroundColor=panelBg;

            app.BtnCuttingContinue = uibutton(gridBtn, 'Text','Continue →', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'BackgroundColor',[0.1 0.6 0.1], 'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~)app.onContinue());

            %% --- RIGHT PANEL: 2D CUT PLOTS ---
            app.AxCutLeft = uiaxes(app.GLCutting);
            app.AxCutLeft.Layout.Row=1;
            app.AxCutLeft.Layout.Column=2;
            app.AxCutLeft.BackgroundColor = t.axBg;
            grid(app.AxCutLeft,'on');
            title(app.AxCutLeft,'Left Profile Cut Path');

            app.AxCutRight = uiaxes(app.GLCutting);
            app.AxCutRight.Layout.Row=2;
            app.AxCutRight.Layout.Column=2;
            app.AxCutRight.BackgroundColor = t.axBg;
            grid(app.AxCutRight,'on');
            title(app.AxCutRight,'Right Profile Cut Path');
        end

        % TAB 7 (SIMULATION)
        function createSimulationTab(app)
            % Purpose: Builds the Kinematics Simulation tab UI components.
            %
            % Layout Strategy:
            %   - Left Panel (320px): Dashboard controls for playback, speed
            %     settings, live coordinate readouts, and program extents.
            %   - Right Panel (1x): 3D interactive kinematics simulation axes.
            %
            % Dependencies: app.getTheme(), CNCHotWire_GCodeGenerator_V1 UI Constants

            % 1. Fetch Theme Colors locally
            t = app.getTheme();
            sideBg   = t.sideBg;
            panelBg  = t.panelBg;
            labelCol = t.labelCol;

            % 2. Main Tab Container
            app.TabSimulation = uitab(app.TabGroup, 'Title', 'Simulation');

            app.GLSimulation = uigridlayout(app.TabSimulation, [1 2]);
            app.GLSimulation.ColumnWidth = {CNCHotWire_GCodeGenerator.PanelWidth, '1x'};
            app.GLSimulation.Padding = app.getTabPadding();
            app.GLSimulation.ColumnSpacing = 5;
            app.GLSimulation.BackgroundColor = sideBg;

            %% --- LEFT CONTROL PANEL (Sidebar) ---
            app.SimLeftPanel = uigridlayout(app.GLSimulation, [7 1]);
            app.SimLeftPanel.Layout.Column = 1;

            % Rows: 1:View, 2:Playback, 3:Settings, 4:Status, 5:Extents, 6:Spacer(1x), 7:Continue
            app.SimLeftPanel.RowHeight = {'fit', 'fit', 'fit', 'fit', 'fit', '1x', CNCHotWire_GCodeGenerator.ButtonHeight};
            app.SimLeftPanel.Padding = [5 5 5 5];
            app.SimLeftPanel.RowSpacing = CNCHotWire_GCodeGenerator.BlockSpacing;
            app.SimLeftPanel.BackgroundColor = panelBg; % Distinct sidebar shade

            %% --- VIEW CONTROLS ---
            pnlView = uipanel(app.SimLeftPanel, 'Title','View', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlView.Layout.Row = 1;

            gridView = uigridlayout(pnlView,[1 2]);
            gridView.Padding=[5 5 5 5];
            gridView.ColumnSpacing = 5;
            gridView.RowHeight = {CNCHotWire_GCodeGenerator.ButtonHeight};
            gridView.BackgroundColor=panelBg;

            btnViewMachine = uibutton(gridView, 'Text','Machine View', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.onResetSimViewMachine());
            btnViewBillet = uibutton(gridView, 'Text','Billet View', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.onResetSimViewBillet());

            %% --- PLAYBACK CONTROLS ---
            pnlPlayback = uipanel(app.SimLeftPanel, 'Title','Playback', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlPlayback.Layout.Row = 2;

            gridPlayback = uigridlayout(pnlPlayback,[2 3]);
            gridPlayback.ColumnWidth={'1x','1x','1x'};
            gridPlayback.RowHeight={CNCHotWire_GCodeGenerator.ButtonHeight, CNCHotWire_GCodeGenerator.RowHeightNormal};
            gridPlayback.Padding=[5 5 5 5];
            gridPlayback.ColumnSpacing = 5;
            gridPlayback.RowSpacing = 5;
            gridPlayback.BackgroundColor=panelBg;

            % Row 1: Buttons
            app.SimPlayBtn = uibutton(gridPlayback, 'Text','Play', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'BackgroundColor',t.accentBg, 'FontColor',t.editTxt, 'ButtonPushedFcn',@(~,~)app.onSimPlay());
            btnPause = uibutton(gridPlayback, 'Text','Pause', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'BackgroundColor',panelBg, 'FontColor',labelCol, 'ButtonPushedFcn',@(~,~)app.onSimPause());
            app.SimStopBtn = uibutton(gridPlayback, 'Text','Reset', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'BackgroundColor',panelBg, 'FontColor',labelCol, 'ButtonPushedFcn',@(~,~)app.onSimStop());

            % Row 2: Slider + Spinner
            app.SimSlider = uislider(gridPlayback, 'Limits',[1 100], 'Value',1, 'ValueChangedFcn',@(src,~)app.onSimSliderChanging(src));
            app.SimSlider.Layout.Row = 2;
            app.SimSlider.Layout.Column = [1 2];

            app.SimIndexSpinner = uispinner(gridPlayback, 'Limits',[1 100], 'Value',1, 'RoundFractionalValues','on', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ValueChangedFcn',@(src,~)app.onSimIndexSpinnerChanged(src));
            app.SimIndexSpinner.Layout.Row = 2;
            app.SimIndexSpinner.Layout.Column = 3;

            %% --- SETTINGS ---
            pnlSettings = uipanel(app.SimLeftPanel, 'Title','Settings', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlSettings.Layout.Row = 3;

            gridSettings = uigridlayout(pnlSettings, [2 2]);
            gridSettings.ColumnWidth={'1x', 80}; % 80px strictly matches the spinner/box width
            gridSettings.RowHeight={CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.RowHeightNormal};
            gridSettings.Padding=[5 5 5 5];
            gridSettings.ColumnSpacing = 5;
            gridSettings.RowSpacing = 2;
            gridSettings.BackgroundColor=panelBg;

            lblSpeed = uilabel(gridSettings, 'Text','Sim Speed Multiplier:', 'FontColor',labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment','right');
            lblSpeed.Layout.Row=1; lblSpeed.Layout.Column=1;

            app.SimSpeedSpinner = uispinner(gridSettings, 'Limits',[0.1 60], 'Value',40.0, 'Step',1.0, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'Tooltip', 'Simulation speed as multiple of set feed rate');
            app.SimSpeedSpinner.Layout.Row=1; app.SimSpeedSpinner.Layout.Column=2;

            lblBaseFeed = uilabel(gridSettings, 'Text','Base Feed Rate[mm/min]:', 'FontColor',labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment','right');
            lblBaseFeed.Layout.Row=2; lblBaseFeed.Layout.Column=1;

            app.LblBaseFeed = uilabel(gridSettings, 'Text', sprintf('%.0f', CNCHotWire_GCodeGenerator.DefaultFeedRate), 'HorizontalAlignment', 'center', ...
                'BackgroundColor', t.readoutBg, 'FontColor', t.readoutTxt, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
            app.LblBaseFeed.Layout.Row=2; app.LblBaseFeed.Layout.Column=2;

            %% --- LIVE SYSTEM STATUS ---
            pnlStatus = uipanel(app.SimLeftPanel, 'Title','Live System Status', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlStatus.Layout.Row = 4;

            % 5 Rows: R1 Header, R2-R3 Coords, R4 Text, R5 Gauge
            gridStatus = uigridlayout(pnlStatus, [5 5]);
            gridStatus.ColumnWidth = {'fit', 60, '1x', 'fit', 60};
            gridStatus.RowHeight = {'fit', 'fit', 'fit', 'fit', 50};
            gridStatus.Padding = [5 5 5 5];
            gridStatus.BackgroundColor = panelBg;

            lblHeadL = uilabel(gridStatus, 'Text','Left Tower', 'FontWeight','bold', 'FontColor',labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment','center');
            lblHeadL.Layout.Column = [1 2];

            lblHeadR = uilabel(gridStatus, 'Text','Right Tower', 'FontWeight','bold', 'FontColor',labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment','center');
            lblHeadR.Layout.Column = [4 5];

            % Row 2: X/Z
            lblX = uilabel(gridStatus, 'Text','X:', 'FontWeight','bold', 'FontColor',t.accentBg, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment','right');
            lblX.Layout.Row=2;

            app.LblReadoutX = uilabel(gridStatus, 'Text','0.00', 'FontName','Monospaced', 'FontColor',labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
            app.LblReadoutX.Layout.Row=2; app.LblReadoutX.Layout.Column=2;

            lblZ = uilabel(gridStatus, 'Text','Z:', 'FontWeight','bold', 'FontColor',t.accentBg, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment','right');
            lblZ.Layout.Row=2; lblZ.Layout.Column=4;

            app.LblReadoutZ = uilabel(gridStatus, 'Text','0.00', 'FontName','Monospaced', 'FontColor',labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
            app.LblReadoutZ.Layout.Row=2; app.LblReadoutZ.Layout.Column=5;

            % Row 3: Y/A
            lblY = uilabel(gridStatus, 'Text','Y:', 'FontWeight','bold', 'FontColor',t.accentBg, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment','right');
            lblY.Layout.Row=3;

            app.LblReadoutY = uilabel(gridStatus, 'Text','0.00', 'FontName','Monospaced', 'FontColor',labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
            app.LblReadoutY.Layout.Row=3; app.LblReadoutY.Layout.Column=2;

            lblA = uilabel(gridStatus, 'Text','A:', 'FontWeight','bold', 'FontColor',t.accentBg, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment','right');
            lblA.Layout.Row=3; lblA.Layout.Column=4;

            app.LblReadoutA = uilabel(gridStatus, 'Text','0.00', 'FontName','Monospaced', 'FontColor',labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
            app.LblReadoutA.Layout.Row=3; app.LblReadoutA.Layout.Column=5;

            % Row 4: Extension Label
            lblGaugeTitle = uilabel(gridStatus);
            lblGaugeTitle.Layout.Row = 4;
            lblGaugeTitle.Layout.Column = [1 5];
            lblGaugeTitle.Text = 'Wire Extension (Pulley Travel) [mm]';
            lblGaugeTitle.FontWeight = 'bold';
            lblGaugeTitle.FontColor = labelCol;
            lblGaugeTitle.FontSize = CNCHotWire_GCodeGenerator.FontSizeNormal;
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
            gaugeExt.FontSize = 8; % Keep small to fit ticks
            gaugeExt.BackgroundColor = panelBg;

            gaugeExt.Tooltip = {sprintf('Tapered cuts require the wire to change length using a mass pulley system'), ...
                sprintf('This dial shows the live extention required during the simulation'), ...
                sprintf('Green: Safe operation.'), ...
                sprintf('Amber (>%.0fmm): Approaching pulley limit.', app.WireExt_Amber), ...
                sprintf('Red (>%.0fmm): Critical mechanical limit, wire will break!', app.WireExt_Red)};

            app.SimGaugeExt = gaugeExt;

            %% --- PROGRAM EXTENTS ---
            pnlBounds = uipanel(app.SimLeftPanel, 'Title','Program Extents', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlBounds.Layout.Row = 5;

            gridBounds = uigridlayout(pnlBounds, [3 1]);
            gridBounds.RowHeight = {'fit', 'fit', 'fit'};
            gridBounds.Padding =[5 5 5 5];
            gridBounds.RowSpacing = 2;
            gridBounds.BackgroundColor = panelBg;

            app.LblSimExtMin = uilabel(gridBounds, 'Text','Extents Min: ---', 'FontName','Monospaced', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'FontColor',labelCol);
            app.LblSimExtMin.Layout.Row = 1;

            app.LblSimExtMax = uilabel(gridBounds, 'Text','Extents Max: ---', 'FontName','Monospaced', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'FontColor',labelCol);
            app.LblSimExtMax.Layout.Row = 2;

            app.LblSimExtWire = uilabel(gridBounds, 'Text','Max Wire Extension: ---', 'FontName','Monospaced', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'FontColor',t.wireKerf);
            app.LblSimExtWire.Layout.Row = 3;

            %% --- ACTION BUTTONS ---
            gridBtn = uigridlayout(app.SimLeftPanel,[1 1]);
            gridBtn.Layout.Row = 7;
            gridBtn.RowHeight = {CNCHotWire_GCodeGenerator.ButtonHeight};
            gridBtn.Padding=[0 0 0 0];
            gridBtn.BackgroundColor=panelBg;

            app.BtnSimContinue = uibutton(gridBtn, 'Text','Continue →', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'BackgroundColor',[0.1 0.6 0.1], 'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~)app.onContinue());

            %% --- RIGHT PANEL: 3D SIM PLOT ---
            app.AxSim = uiaxes(app.GLSimulation);
            app.AxSim.Layout.Column = 2;
            app.AxSim.BackgroundColor = t.axBg;
            xlabel(app.AxSim,'X'); ylabel(app.AxSim,'Y'); zlabel(app.AxSim,'Z');
            grid(app.AxSim,'on'); view(app.AxSim, 3); axis(app.AxSim, 'equal');
        end

        % TAB 8 (POST-PROCESS)
        function createPostProcessTab(app)
            % Purpose: Builds the Post-Processor and G-Code export tab UI components.
            %
            % Layout Strategy:
            %   - Left Panel (320px): Controls for feed/power, G-code generation,
            %     and an interactive G-code viewer listbox.
            %   - Right Panel (1x): 3D axes for verifying the generated G-code path.
            %
            % Dependencies: app.getTheme(), CNCHotWire_GCodeGenerator_V1 UI Constants

            % 1. Fetch Theme Colors locally
            t = app.getTheme();
            sideBg   = t.sideBg;
            panelBg  = t.panelBg;
            labelCol = t.labelCol;
            inputBg  = t.inputBg;
            inputTxt = t.inputTxt;

            % 2. Main Tab Container
            app.TabPostProcess = uitab(app.TabGroup, 'Title', 'Post-Process');

            app.GLPostProcess = uigridlayout(app.TabPostProcess,[1 2]);
            app.GLPostProcess.ColumnWidth   = {CNCHotWire_GCodeGenerator.PanelWidth, '1x'};
            app.GLPostProcess.Padding       = app.getTabPadding();
            app.GLPostProcess.ColumnSpacing = 5;
            app.GLPostProcess.BackgroundColor = sideBg;

            %% --- LEFT CONTROL PANEL (Sidebar) ---
            app.PostLeftPanel = uigridlayout(app.GLPostProcess,[7 1]);

            % Rows: 1:View, 2:Settings, 3:Export, 4:GCode(1x), 5:Save, 6:Guidance(1x), 7:Status(70px)
            app.PostLeftPanel.RowHeight = {'fit', 'fit', 'fit', '1x', CNCHotWire_GCodeGenerator.ButtonHeight, '1x', 70};
            app.PostLeftPanel.Padding =[5 5 5 5];
            app.PostLeftPanel.RowSpacing = CNCHotWire_GCodeGenerator.BlockSpacing;
            app.PostLeftPanel.BackgroundColor = panelBg; % Distinct sidebar shade

            %% --- VIEW CONTROLS (Unnumbered) ---
            pnlView = uipanel(app.PostLeftPanel, 'Title','View', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlView.Layout.Row = 1;

            gridView = uigridlayout(pnlView,[1 2]);
            gridView.Padding=[5 5 5 5];
            gridView.ColumnSpacing=5; % Matches Cutting Tab for consistency!
            gridView.RowHeight = {CNCHotWire_GCodeGenerator.ButtonHeight};
            gridView.BackgroundColor=panelBg;

            btnViewMachine = uibutton(gridView, 'Text','Machine View', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.onResetPostViewMachine());
            btnViewBillet = uibutton(gridView, 'Text','Billet View', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn',@(~,~)app.onResetPostViewBillet());

            %% --- 1. SETTINGS (FEED & POWER) ---
            pnlSettings = uipanel(app.PostLeftPanel, 'Title','1. Cutting Parameters', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlSettings.Layout.Row = 2;

            gridSettings = uigridlayout(pnlSettings, [2 3]);
            gridSettings.ColumnWidth={'1x', 'fit', 80};
            gridSettings.RowHeight={CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.RowHeightNormal};
            gridSettings.Padding=[5 5 5 5];
            gridSettings.ColumnSpacing=5;
            gridSettings.RowSpacing=2;
            gridSettings.BackgroundColor=panelBg;

            app.ChkDynamicFeed = uicheckbox(gridSettings, 'Text', 'Dynamic', 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'Value', true);
            app.ChkDynamicFeed.Layout.Row=1; app.ChkDynamicFeed.Layout.Column=1;
            app.ChkDynamicFeed.Tooltip = 'Scale feed rate continuously so the wire maintains constant speed through the foam on tapered parts.';
            app.ChkDynamicFeed.ValueChangedFcn = @(src,evt)app.updatePostStatus();

            lblFeed = uilabel(gridSettings, 'Text','Feed Rate [mm/min]:', 'FontColor',labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment','right');
            lblFeed.Layout.Row=1; lblFeed.Layout.Column=2;

            app.SpinFeedRate = uispinner(gridSettings, 'Limits',[10 500], 'Value', CNCHotWire_GCodeGenerator.DefaultFeedRate, 'Step',5, 'ValueDisplayFormat','%.0f', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
            app.SpinFeedRate.Layout.Row=1; app.SpinFeedRate.Layout.Column=3;
            app.SpinFeedRate.Tooltip = 'Programmed speed of wire, kerf is inversely proportional to speed';
            app.SpinFeedRate.ValueChangedFcn = @(src,evt)app.updatePostStatus();

            lblPower = uilabel(gridSettings, 'Text','Hot Wire Power [%]:', 'FontColor',labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'HorizontalAlignment','right');
            lblPower.Layout.Row=2; lblPower.Layout.Column=2;

            app.SpinPower = uispinner(gridSettings, 'Limits',[10 100], 'Value', CNCHotWire_GCodeGenerator.DefaultPower, 'Step',1, 'ValueDisplayFormat','%.0f', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);
            app.SpinPower.Layout.Row=2; app.SpinPower.Layout.Column=3;
            app.SpinPower.Tooltip = 'Programmed wire power, kerf is proportional to wire power';
            app.SpinPower.ValueChangedFcn = @(src,evt)app.updatePostStatus();

            %% --- 2. FILENAME & EXPORT ---
            pnlExport = uipanel(app.PostLeftPanel, 'Title','2. Filename:', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            pnlExport.Layout.Row = 3;

            gridExport = uigridlayout(pnlExport,[2 1]);
            gridExport.RowHeight={CNCHotWire_GCodeGenerator.RowHeightNormal, CNCHotWire_GCodeGenerator.ButtonHeight};
            gridExport.Padding=[5 5 5 5];
            gridExport.RowSpacing=5;
            gridExport.BackgroundColor=panelBg;

            app.FieldFilename = uieditfield(gridExport, 'text', 'Value', 'GCode-V1-Output.gcode', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'BackgroundColor', inputBg, 'FontColor', inputTxt, 'ValueChangedFcn', @(src,~)app.onFilenameChanged(src));
            app.BtnPostProcess = uibutton(gridExport, 'Text','Post-Process', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, ...
                'BackgroundColor',t.accentBg, 'FontColor',t.editTxt, 'ButtonPushedFcn',@(~,~)app.onPostProcess());
            app.BtnPostProcess.Tooltip = 'Press to generate g-code';

            %% --- 3. G-CODE VIEWER ---
            app.PanelGCode = uipanel(app.PostLeftPanel, 'Title','3. G-Code', 'BackgroundColor',panelBg, 'ForegroundColor',labelCol, 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType','line');
            app.PanelGCode.Layout.Row = 4;

            app.GridGCode = uigridlayout(app.PanelGCode, [2 2]);
            app.GridGCode.RowHeight = {'1x', CNCHotWire_GCodeGenerator.ButtonHeight};
            app.GridGCode.ColumnWidth = {'1x','1x'};
            app.GridGCode.Padding =[5 5 5 5];
            app.GridGCode.ColumnSpacing=5;
            app.GridGCode.BackgroundColor=panelBg;

            app.ListGCode = uilistbox(app.GridGCode, 'Items', {'(Generate to view G-code...)'}, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'BackgroundColor', sideBg, 'FontColor', labelCol, 'ValueChangedFcn', @(src,~)app.onPostLineSelected(src));
            app.ListGCode.Layout.Row = 1;
            app.ListGCode.Layout.Column =[1 2];
            app.ListGCode.FontName = 'Courier New';

            app.BtnGCodePrev = uibutton(app.GridGCode,'push','Text','◀ Prev', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn', @(~,~)app.stepPostLine(-1));
            app.BtnGCodePrev.Layout.Row = 2;
            app.BtnGCodePrev.Layout.Column = 1;

            app.BtnGCodeNext = uibutton(app.GridGCode,'push','Text','Next ▶', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, 'ButtonPushedFcn', @(~,~)app.stepPostLine(+1));
            app.BtnGCodeNext.Layout.Row = 2;
            app.BtnGCodeNext.Layout.Column = 2;

            %% --- 5. ACTION BUTTONS ---
            gridBtn = uigridlayout(app.PostLeftPanel,[1 1]);
            gridBtn.Layout.Row = 5;
            gridBtn.RowHeight = {CNCHotWire_GCodeGenerator.ButtonHeight};
            gridBtn.Padding=[0 0 0 0];
            gridBtn.BackgroundColor=panelBg;

            % Initializes as grey/disabled to match the Continue buttons on other tabs
            app.BtnSaveGCode = uibutton(gridBtn, 'Text','Save G-Code', 'FontWeight','bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal, ...
                'BackgroundColor',[0.3 0.3 0.3], 'FontColor',[0.8 0.8 0.8], 'Enable','off', ...
                'ButtonPushedFcn',@(~,~)app.onSaveGCode());
            app.BtnSaveGCode.Tooltip = 'Press to save g-code as a .tap file ready for mach4';

            %% --- 6. GUIDANCE ---
            pnlGuide = uipanel(app.PostLeftPanel, 'Title', 'Guidance', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType', 'line');
            pnlGuide.Layout.Row = 6;
            glGuide = uigridlayout(pnlGuide,[1 1]);
            glGuide.Padding =[0 0 0 0];
            glGuide.BackgroundColor = panelBg;

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
            app.TxtPostGuide = uitextarea(glGuide, 'Editable','off', 'Value', guidePost, 'BackgroundColor', panelBg, 'FontColor', labelCol, 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            %% --- 7. STATUS ---
            pnlStatus = uipanel(app.PostLeftPanel, 'Title', 'Status', 'BackgroundColor', panelBg, 'ForegroundColor', labelCol, 'FontWeight', 'bold', 'FontSize', CNCHotWire_GCodeGenerator.FontSizeHeader, 'BorderType', 'line');
            pnlStatus.Layout.Row = 7;
            glStatus = uigridlayout(pnlStatus,[1 1]);
            glStatus.Padding =[0 0 0 0];
            glStatus.BackgroundColor = panelBg;

            app.TxtPostStatus = uitextarea(glStatus, 'Editable','off', 'Value', {'Ready.'}, 'BackgroundColor', t.panelBg, 'FontColor',[0.9 0.9 0.9], 'FontSize', CNCHotWire_GCodeGenerator.FontSizeNormal);

            %% --- RIGHT PANEL: 3D POST PLOT ---
            app.AxPost = uiaxes(app.GLPostProcess);
            app.AxPost.Layout.Column = 2;
            app.AxPost.BackgroundColor = t.axBg;
            xlabel(app.AxPost,'X'); ylabel(app.AxPost,'Y'); zlabel(app.AxPost,'Z');
            grid(app.AxPost,'on'); view(app.AxPost,3); axis(app.AxPost,'equal');
        end

        % TAB DEBUG
        function createDebugNoTabPage(app, parent, t)
            % Purpose:
            % Diagnostic standalone page that bypasses uitabgroup/uitab completely.
            % It displays measured layout sizes inside the UI so we can compare
            % source MATLAB vs deployed EXE without relying on console output.

            sideBg = t.sideBg;
            panelBg = t.panelBg;

            app.DebugOuterGrid = uigridlayout(parent, [1 2]);
            outer = app.DebugOuterGrid;

            outer.RowHeight = {'1x'};
            outer.ColumnWidth = {CNCHotWire_GCodeGenerator.PanelWidth, 800};
            outer.Padding = [0 0 0 0];
            outer.RowSpacing = 0;
            outer.ColumnSpacing = 10;
            outer.BackgroundColor

            %% --- LEFT PANEL ---
            leftPnl = uigridlayout(outer, [3 1]);
            leftPnl.Layout.Row = 1;
            leftPnl.Layout.Column = 1;
            leftPnl.RowHeight = {'1x', 'fit', CNCHotWire_GCodeGenerator.ButtonHeight};
            leftPnl.Padding = [5 5 5 5];
            leftPnl.RowSpacing = 8;
            leftPnl.BackgroundColor = panelBg;

            titleLbl = uilabel(leftPnl);
            titleLbl.Text = 'NO TABGROUP DIAGNOSTIC';
            titleLbl.HorizontalAlignment = 'center';
            titleLbl.VerticalAlignment = 'top';
            titleLbl.FontWeight = 'bold';
            titleLbl.FontColor = [1 1 1];
            titleLbl.Layout.Row = 1;

            themeRow = uigridlayout(leftPnl, [1 4]);
            themeRow.Layout.Row = 2;
            themeRow.ColumnWidth = {'fit', 'fit', 'fit', 'fit'};
            themeRow.RowHeight = {'fit'};
            themeRow.Padding = [0 0 0 0];
            themeRow.ColumnSpacing = 8;
            themeRow.BackgroundColor = panelBg;

            uilabel(themeRow, ...
                'Text', 'App Theme:', ...
                'FontWeight', 'bold', ...
                'FontColor', [1 1 1]);

            uilabel(themeRow, ...
                'Text', 'Dark', ...
                'FontColor', [1 1 1]);

            uilabel(themeRow, ...
                'Text', '[theme switch placeholder]', ...
                'FontColor', [1 1 1]);

            uilabel(themeRow, ...
                'Text', 'Light', ...
                'FontColor', [1 1 1]);

            btn = uibutton(leftPnl, ...
                'Text', 'Diagnostic Button →', ...
                'FontWeight', 'bold');
            btn.Layout.Row = 3;

            %% --- RIGHT PANEL ---
            right = uigridlayout(outer, [5 1]);
            right.Layout.Row = 1;
            right.Layout.Column = 2;
            right.RowHeight = {120, 260, 'fit', '1x', 'fit'};
            right.Padding = [20 20 20 20];
            right.RowSpacing = 15;
            right.BackgroundColor = sideBg;

            header = uilabel(right);
            header.Layout.Row = 1;
            header.Text = 'CNC Hot Wire G-Code Generator';
            header.FontSize = 28;
            header.FontWeight = 'bold';
            header.FontColor = [1 1 1];
            header.HorizontalAlignment = 'center';

            aboutPanel = uipanel(right, ...
                'Title', 'Layout Debug Info', ...
                'BackgroundColor', panelBg, ...
                'ForegroundColor', [1 1 1]);
            aboutPanel.Layout.Row = 2;

            aboutGrid = uigridlayout(aboutPanel, [1 1]);
            aboutGrid.Padding = [5 5 5 5];
            aboutGrid.BackgroundColor = panelBg;

            app.DebugAboutText = uilabel(aboutGrid);
            app.DebugAboutText.Text = 'Debug info will appear here after layout completes...';
            app.DebugAboutText.FontColor = [1 1 1];
            app.DebugAboutText.VerticalAlignment = 'top';
            app.DebugAboutText.WordWrap = 'on';

            setupPanel = uipanel(right, ...
                'Title', 'Required Setup: FreeCAD Engine', ...
                'BackgroundColor', panelBg, ...
                'ForegroundColor', [1 1 1]);
            setupPanel.Layout.Row = 3;

            setupGrid = uigridlayout(setupPanel, [3 1]);
            setupGrid.RowHeight = {'fit', 'fit', 'fit'};
            setupGrid.Padding = [10 10 10 10];
            setupGrid.BackgroundColor = panelBg;

            uilabel(setupGrid, ...
                'Text', 'Step 1. Download and run the standard Windows Installer.', ...
                'FontWeight', 'bold', ...
                'FontColor', [1 1 1]);

            uilabel(setupGrid, ...
                'Text', 'Step 2. Install FreeCAD to the default directory.', ...
                'FontWeight', 'bold', ...
                'FontColor', [1 1 1]);

            uilabel(setupGrid, ...
                'Text', 'Step 3. Locate FreeCADCmd.exe.', ...
                'FontWeight', 'bold', ...
                'FontColor', [1 1 1]);

            footer = uigridlayout(right, [1 3]);
            footer.Layout.Row = 5;
            footer.ColumnWidth = {'1x', '1x', '1x'};
            footer.Padding = [0 0 0 0];
            footer.ColumnSpacing = 8;
            footer.BackgroundColor = sideBg;

            for k = 1:3
                p = uipanel(footer, ...
                    'Title', sprintf('Footer %d', k), ...
                    'BackgroundColor', panelBg, ...
                    'ForegroundColor', [1 1 1]);
                p.Layout.Row = 1;
                p.Layout.Column = k;

                g = uigridlayout(p, [1 1]);
                g.BackgroundColor = panelBg;
                g.Padding = [5 5 5 5];

                lbl = uilabel(g, ...
                    'Text', sprintf('Footer block %d should be visible.', k), ...
                    'FontColor', [1 1 1]);
                lbl.WordWrap = 'on';
            end
            app.DebugAboutText.Text = 'DEBUG TEXT OBJECT IS CONNECTED';
        end

        function updateDebugLayoutInfo(app, rootGrid)
            % Purpose:
            % Update the diagnostic text block after the UI has completed layout.
            % Uses getpixelposition rather than uigridlayout.Position, because
            % uigridlayout.Position can report misleading default values.

            try
                drawnow;

                screenSize = get(groot, 'ScreenSize');
                ppi = get(groot, 'ScreenPixelsPerInch');

                figPos = app.UIFigure.Position;

                try
                    figInner = app.UIFigure.InnerPosition;
                catch
                    figInner = [NaN NaN NaN NaN];
                end

                try
                    rootPixLocal = getpixelposition(rootGrid, false);
                catch
                    rootPixLocal = [NaN NaN NaN NaN];
                end

                try
                    rootPixAbs = getpixelposition(rootGrid, true);
                catch
                    rootPixAbs = [NaN NaN NaN NaN];
                end

                try
                    outerPixLocal = getpixelposition(app.DebugOuterGrid, false);
                catch
                    outerPixLocal = [NaN NaN NaN NaN];
                end

                try
                    outerPixAbs = getpixelposition(app.DebugOuterGrid, true);
                catch
                    outerPixAbs = [NaN NaN NaN NaN];
                end

                app.DebugAboutText.Text = sprintf([ ...
                    'DEPLOYED: %d\n\n', ...
                    'ScreenSize: [%.0f %.0f %.0f %.0f]\n', ...
                    'PPI: %.0f\n\n', ...
                    'UIFigure.Position:      [%.0f %.0f %.0f %.0f]\n', ...
                    'UIFigure.InnerPosition: [%.0f %.0f %.0f %.0f]\n\n', ...
                    'rootGrid pixel local:   [%.0f %.0f %.0f %.0f]\n', ...
                    'rootGrid pixel abs:     [%.0f %.0f %.0f %.0f]\n\n', ...
                    'outerGrid pixel local:  [%.0f %.0f %.0f %.0f]\n', ...
                    'outerGrid pixel abs:    [%.0f %.0f %.0f %.0f]\n\n', ...
                    'Interpretation:\n', ...
                    '- Figure/InnerPosition should be close to the visible window size.\n', ...
                    '- rootGrid local size should be close to the figure client size.\n', ...
                    '- outerGrid local size should be close to rootGrid size.\n'], ...
                    isdeployed, ...
                    screenSize(1), screenSize(2), screenSize(3), screenSize(4), ...
                    ppi, ...
                    figPos(1), figPos(2), figPos(3), figPos(4), ...
                    figInner(1), figInner(2), figInner(3), figInner(4), ...
                    rootPixLocal(1), rootPixLocal(2), rootPixLocal(3), rootPixLocal(4), ...
                    rootPixAbs(1), rootPixAbs(2), rootPixAbs(3), rootPixAbs(4), ...
                    outerPixLocal(1), outerPixLocal(2), outerPixLocal(3), outerPixLocal(4), ...
                    outerPixAbs(1), outerPixAbs(2), outerPixAbs(3), outerPixAbs(4));

            catch ME
                try
                    app.DebugAboutText.Text = sprintf('Debug update failed:\n%s', ME.message);
                catch
                    warning('Debug update failed before DebugAboutText existed: %s', ME.message);
                end
            end
        end

    end
end