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

    properties
        % ---------- UI containers ----------
        UIFigure
        TabGroup
        TabModel
        TabProfiles      % reserved for future profile plots

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

        % ---------- Profile generation (future) ----------
        BtnGenerateProfiles   % stub – no heavy logic yet
        BtnContinue           % stub – disabled initially

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

        % ---------- Internal plane reference ----------
        ModelXMin double = 0   % left face of the model in machine X
        ModelXMax double = 0   % right face of the model in machine X

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

            clc;
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
            app.TabProfiles = uitab(app.TabGroup,'Title','Profiles'); % reserved

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
            app.GLLeft.RowHeight     = repmat({'fit'},1,15);
            app.GLLeft.RowHeight{16} = '1x';
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
            btnPanel = uipanel(app.GLLeft, ...
                'BackgroundColor',[0.16 0.16 0.16], ...
                'BorderType','none');
            btnPanel.Layout.Row = 13;

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

        function enterState0(app)
            % STATE 0: model only, no planes, no profiles
            app.AppState = 0;

            % Clear planes and profiles
            app.clearPlanes();
            app.clearProfiles();

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
            % Compute and plot raw intersection profiles for left/right planes.

            if app.AppState == 0 ...
                    || isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch)
                return;
            end

            % Clear previous profile graphics
            app.clearProfiles();

            % --- Current rotated mesh ---
            V = app.ModelPatch.Vertices;
            F = app.ModelPatch.Faces;

            mins = min(V,[],1);
            maxs = max(V,[],1);
            spanVec = maxs - mins;
            span = max(spanVec);
            if span <= 0, span = 1; end

            epsX = 1e-6 * span;

            % Plane positions
            xLeft  = app.ModelXMin + app.NumLeftOffset.Value;
            xRight = app.ModelXMin + app.NumRightOffset.Value;

            % Colours that match your plane system
            leftColor  = [0.96 0.06 0.06];
            rightColor = [0.20 1.00 0.35];

            % ----- LEFT SLICING -----
            [xsL, ysL, zsL] = HotWireSTEPApp_v6_helpers.sliceMeshAtX(V, F, xLeft + epsX);

            if ~isempty(xsL) && any(~isnan(xsL))
                app.LeftProfileLine3D = plot3(app.AxModel, xsL, ysL, zsL, ...
                    'Color', leftColor, 'LineWidth',1.3);

                idx = ~isnan(xsL) & ~isnan(ysL) & ~isnan(zsL);
                app.LeftProfilePoints = [xsL(idx).', ysL(idx).', zsL(idx).'];
            else
                app.LeftProfilePoints = [];
            end

            % ----- RIGHT SLICING -----
            [xsR, ysR, zsR] = HotWireSTEPApp_v6_helpers.sliceMeshAtX(V, F, xRight - epsX);

            if ~isempty(xsR) && any(~isnan(xsR))
                app.RightProfileLine3D = plot3(app.AxModel, xsR, ysR, zsR, ...
                    'Color', rightColor, 'LineWidth',1.3);

                idx = ~isnan(xsR) & ~isnan(ysR) & ~isnan(zsR);
                app.RightProfilePoints = [xsR(idx).', ysR(idx).', zsR(idx).'];
            else
                app.RightProfilePoints = [];
            end

            drawnow limitrate nocallbacks;
        end

        function onTaperModeChanged(app)

            if isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch)
                return;
            end

            % Re-run planes + profiles under the new taper mode
            app.updatePlanes();  % will call computeProfiles() in STATE 1
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
        end

        function autoFitView(app)
            if isempty(app.ModelPatch) || ~isvalid(app.ModelPatch)
                return
            end

            V      = app.ModelPatch.Vertices;
            mins   = min(V,[],1);
            maxs   = max(V,[],1);
            center = mean([mins; maxs],1);

            spanVec = maxs - mins;
            span    = max(spanVec);
            if span <= 0
                span = 1;
                mins = center - span/2;
                maxs = center + span/2;
            end

            pad = 0.35 * span;
            xlim(app.AxModel,[mins(1)-pad maxs(1)+pad]);
            ylim(app.AxModel,[mins(2)-pad maxs(2)+pad]);
            zlim(app.AxModel,[mins(3)-pad maxs(3)+pad]);

            daspect(app.AxModel,[1 1 1]);
            pbaspect(app.AxModel,[1 1 1]);

            app.AxModel.CameraTarget   = center;
            app.AxModel.CameraUpVector = [0 0 1];

            camPos = app.AxModel.CameraPosition;
            dir    = camPos - center;
            dist   = norm(dir);
            if dist == 0
                dir = [1 1 1]/sqrt(3);
            else
                dir = dir / dist;
            end

            newDist = span * 2.2;
            app.AxModel.CameraPosition = center + dir * newDist;

            delete(findall(app.AxModel,'Type','light'));
            camlight(app.AxModel,'headlight');
            lighting(app.AxModel,'gouraud');

            drawnow limitrate nocallbacks;
        end

        function captureHomeView(app)
            if isempty(app.AxModel) || ~isvalid(app.AxModel)
                return
            end

            ax = app.AxModel;
            app.DefaultXLim  = xlim(ax);
            app.DefaultYLim  = ylim(ax);
            app.DefaultZLim  = zlim(ax);
            app.DefaultDataAspectRatio    = ax.DataAspectRatio;
            app.DefaultPlotBoxAspectRatio = ax.PlotBoxAspectRatio;
            app.DefaultCameraPosition     = ax.CameraPosition;
            app.DefaultCameraTarget       = ax.CameraTarget;
            app.DefaultCameraUpVector     = ax.CameraUpVector;
        end

        function resetPlotView(app)
            if isempty(app.ModelPatch) || ~isvalid(app.ModelPatch)
                return
            end

            if isempty(app.DefaultXLim)
                app.autoFitView();
                return
            end

            ax = app.AxModel;
            xlim(ax, app.DefaultXLim);
            ylim(ax, app.DefaultYLim);
            zlim(ax, app.DefaultZLim);

            ax.DataAspectRatio    = app.DefaultDataAspectRatio;
            ax.PlotBoxAspectRatio = app.DefaultPlotBoxAspectRatio;
            ax.CameraPosition     = app.DefaultCameraPosition;
            ax.CameraTarget       = app.DefaultCameraTarget;
            ax.CameraUpVector     = app.DefaultCameraUpVector;

            delete(findall(ax,'Type','light'));
            camlight(ax,'headlight');
            lighting(ax,'gouraud');

            drawnow limitrate nocallbacks;
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

            % OPTION A: After rotation, behave like Reset Planes
            app.updateModelBoundsAndDefaultOffsets(true);
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

            % Reset model bounds & plane offsets to defaults
            app.updateModelBoundsAndDefaultOffsets(true); % reset offsets
            app.updatePlanes();
        end

        % ===========================================================
        % PLANES
        % ===========================================================
        function updateModelBoundsAndDefaultOffsets(app, resetOffsets)
            % Compute model X bounds in machine space and optionally reset
            % the plane offsets so:
            %   left plane offset  = 0 at left face
            %   right plane offset = width at right face

            if isempty(app.ModelPatch) || ~isvalid(app.ModelPatch)
                return
            end

            V = app.ModelPatch.Vertices;
            app.ModelXMin = min(V(:,1));
            app.ModelXMax = max(V(:,1));

            width = app.ModelXMax - app.ModelXMin;
            if width <= 0
                width = 1;
            end

            if nargin < 2
                resetOffsets = true;
            end

            if resetOffsets
                % Left plane at left face (0), right plane at right face (width)
                app.NumLeftOffset.Value  = 0;
                app.NumRightOffset.Value = width;
            end
        end

        function onPlaneOffsetChanged(app, ~, ~)
            if isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch)
                return
            end

            app.updatePlanes();  % this will also call computeProfiles() in STATE 1
        end

        function resetPlanes(app)
            if isempty(app.ModelPatch) || ~isvalid(app.ModelPatch)
                return
            end

            app.updateModelBoundsAndDefaultOffsets(true);
            app.updatePlanes();
        end

        function updatePlanes(app)
            % Draw/update left/right Y–Z planes in machine X

            % Always clear existing plane graphics first
            app.clearPlanes();

            % No model? nothing to do.
            if isempty(app.ModelPatch) || ~isgraphics(app.ModelPatch)
                return
            end

            % In STATE 0 (pre-profile) we do *not* draw planes.
            if app.AppState == 0
                return;
            end

            V = app.ModelPatch.Vertices;
            mins = min(V,[],1);
            maxs = max(V,[],1);
            span = max(maxs - mins);
            if span <= 0
                span = 1;
            end
            pad = 0.2 * span;

            yMin = mins(2) - pad;
            yMax = maxs(2) + pad;
            zMin = mins(3) - pad;
            zMax = maxs(3) + pad;

            width = app.ModelXMax - app.ModelXMin;
            if width <= 0
                width = 1;
            end

            % Offsets are relative to ModelXMin
            xLeft  = app.ModelXMin + app.NumLeftOffset.Value;
            xRight = app.ModelXMin + app.NumRightOffset.Value;

            % Slight clamp to keep planes in a reasonable range
            safeMinX = app.ModelXMin - 2*span;
            safeMaxX = app.ModelXMax + 2*span;

            % Colours (aviation-style port/starboard)
            leftColor  = [0.96 0.06 0.06];  % saturated red
            rightColor = [0.20 1.00 0.35];  % bright green

            % ----- Left plane -----
            if xLeft >= safeMinX && xLeft <= safeMaxX
                XL = [xLeft; xLeft; xLeft; xLeft];
                YL = [yMin;  yMax;  yMax;  yMin];
                ZL = [zMin;  zMin;  zMax;  zMax];

                app.LeftPlanePatch = patch(app.AxModel, ...
                    'XData',XL,'YData',YL,'ZData',ZL, ...
                    'FaceColor',leftColor, ...
                    'FaceAlpha',0.4, ...
                    'EdgeColor','none');

                % Left label – top-left of plane (in camera-facing projection)
                tY = yMax - 0.02*(yMax - yMin);   % slightly inside the top
                tZ = zMax - 0.1*(zMax - zMin);    % slightly inside the top
                app.LeftPlaneText = text(app.AxModel, ...
                    xLeft, tY, tZ, 'Left', ...
                    'HorizontalAlignment','left', ...
                    'VerticalAlignment','top', ...
                    'Color', leftColor * 0.6, ...
                    'FontWeight','bold');
            else
                app.LeftPlanePatch = gobjects(0);
                app.LeftPlaneText  = gobjects(0);
            end

            % ----- Right plane -----
            if xRight >= safeMinX && xRight <= safeMaxX
                XR = [xRight; xRight; xRight; xRight];
                YR = [yMin;   yMax;   yMax;   yMin];
                ZR = [zMin;   zMin;   zMax;   zMax];

                app.RightPlanePatch = patch(app.AxModel, ...
                    'XData',XR,'YData',YR,'ZData',ZR, ...
                    'FaceColor',rightColor, ...
                    'FaceAlpha',0.4, ...
                    'EdgeColor','none');

                % Right label – top-right of plane (in camera-facing projection)
                tY = yMin;   % right side in the default 3D view
                tZ = zMax;   % top edge
                app.RightPlaneText = text(app.AxModel, ...
                    xRight, tY, tZ, 'Right', ...
                    'HorizontalAlignment','right', ...
                    'VerticalAlignment','top', ...
                    'Color', rightColor * 0.45, ...
                    'FontWeight','bold');
            else
                app.RightPlanePatch = gobjects(0);
                app.RightPlaneText  = gobjects(0);
            end

            % In STATE 1, ensure profiles track the latest plane positions
            if app.AppState == 1
                app.computeProfiles();
            end

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
            % For now, just jump to Profiles tab (placeholder behaviour).
            app.TabGroup.SelectedTab = app.TabProfiles;
        end
    end
end
