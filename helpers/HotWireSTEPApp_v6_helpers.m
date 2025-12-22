classdef HotWireSTEPApp_v6_helpers
    % Helper utilities for HotWireSTEPApp_v6_2
    %
    % Contains:
    %   - importSTEP_FreeCAD : STEP → STL → triangulation (V,F)
    %   - sliceMeshAtX       : Triangle–plane intersection at X = const
    %

    properties (Constant)
        % Minimum number of points for a resampled profile loop
        ProfileResampleMinPoints (1,1) double = 50;

        % Maximum number of points for a resampled profile loop
        % (caps how much a tiny tolerance can explode point count)
        ProfileResampleMaxPoints (1,1) double = 20000;

        % FreeCAD meshing tolerances (STEP -> mesh)
        % These control how finely the STEP geometry is tessellated.
        FreeCADLinearDeflection  (1,1) double = 0.5;   % [mm]
        FreeCADAngularDeflection (1,1) double = 0.3;   % [rad]
    end
    
    methods(Static)

        % ===============================================================
        % STEP → STL → MESH IMPORT USING FREECAD
        % ===============================================================
        function [V,F] = importSTEP_FreeCAD(cadPath, freeCADExe)

            V = [];
            F = [];

            if ~isfile(cadPath)
                warning('STEP file not found: %s', cadPath);
                return;
            end

            if nargin < 2 || ~isfile(freeCADExe)
                warning('FreeCAD executable not found: %s', freeCADExe);
                return;
            end

            % Temporary files
            tmpID  = char(java.util.UUID.randomUUID());
            outSTL = fullfile(tempdir, ['fc_out_' tmpID '.stl']);
            pyFile = fullfile(tempdir, ['fc_' tmpID '.py']);

            % Write FreeCAD python script
            fid = fopen(pyFile,'w');
            if fid < 0
                warning('Failed to create FreeCAD script: %s', pyFile);
                return;
            end

            fprintf(fid,"import FreeCAD, Part, Mesh, MeshPart\n");
            fprintf(fid,"doc = FreeCAD.newDocument()\n");
            fprintf(fid,"shape = Part.Shape()\n");
            fprintf(fid,"shape.read(r'%s')\n", cadPath);
            fprintf(fid, ...
                "mesh = MeshPart.meshFromShape(Shape=shape,LinearDeflection=%g,AngularDeflection=%g)\n", ...
                HotWireSTEPApp_v6_helpers.FreeCADLinearDeflection, ...
                HotWireSTEPApp_v6_helpers.FreeCADAngularDeflection);
            fprintf(fid,"mesh.write(r'%s')\n", outSTL);
            fprintf(fid,"FreeCAD.closeDocument(doc.Name)\n");
            fclose(fid);

            % Run FreeCAD
            cmd = sprintf('"%s" "%s"', freeCADExe, pyFile);
            [status,~] = system(cmd);
            if status ~= 0
                warning('FreeCAD conversion failed.');
                return;
            end

            % Read STL
            if isfile(outSTL)
                raw = stlread(outSTL);
                if isa(raw,"triangulation")
                    F = raw.ConnectivityList;
                    V = raw.Points;
                else
                    [F,V] = stlread(outSTL);
                end
                V = double(V);
                F = double(F);
            else
                warning('STL output not found: %s', outSTL);
            end
        end

        % ===============================================================
        % TRIANGLE–PLANE SLICER  (X = x0)
        % ===============================================================
        function [xs, ys, zs] = sliceMeshAtX(V, F, x0)
            % Return NaN-separated line segments from intersecting a mesh
            % with the plane X = x0.
            %
            % Inputs:
            %   V : Nx3 vertices
            %   F : Mx3 faces
            %   x0: plane X coordinate
            %
            % Outputs:
            %   xs, ys, zs : 1×K vectors (NaN separated for plot3)

            xs = [];
            ys = [];
            zs = [];

            % Loop through triangles
            for k = 1:size(F,1)
                tri = F(k,:);
                A = V(tri(1),:);
                B = V(tri(2),:);
                C = V(tri(3),:);

                X = [A(1), B(1), C(1)];

                % Skip triangles fully on one side
                if all(X < x0) || all(X > x0)
                    continue;
                end

                pts = zeros(2,3);
                count = 0;

                % Check edges A→B, B→C, C→A
                edges = [A;B;C;A];
                for i = 1:3
                    P1 = edges(i,:);
                    P2 = edges(i+1,:);

                    % Sign change or crossing?
                    if (P1(1)-x0)*(P2(1)-x0) <= 0 && P1(1) ~= P2(1)
                        t = (x0 - P1(1)) / (P2(1)-P1(1));
                        if t >= 0 && t <= 1
                            count = count + 1;
                            pts(count,:) = P1 + t*(P2-P1);
                            if count == 2
                                break;  % enough points for one segment
                            end
                        end
                    end
                end

                % If exactly 2 intersection points: record the segment
                if count == 2
                    xs = [xs, pts(1,1), pts(2,1), NaN];
                    ys = [ys, pts(1,2), pts(2,2), NaN];
                    zs = [zs, pts(1,3), pts(2,3), NaN];
                end
            end
        end
        
        % ===============================================================
        % PROFILE LOOP RECONSTRUCTION
        % ===============================================================
        function [yLoop, zLoop] = buildMainProfileLoop(xs, ys, zs)
            % Build an ordered, closed loop from NaN-separated slice
            % segments. Returns the largest closed loop in Y–Z.
            %
            % Inputs:
            %   xs, ys, zs : 1×K vectors from sliceMeshAtX
            %
            % Outputs:
            %   yLoop, zLoop : column vectors forming a closed loop
            %                  (first point == last point), or [] if
            %                  no closed loop could be built.

            yLoop = [];
            zLoop = [];

            if isempty(xs) || all(isnan(xs))
                return;
            end

            % Ensure row vectors
            xs = xs(:).';
            ys = ys(:).';
            zs = zs(:).';

            % Use only finite points
            valid = ~(isnan(xs) | isnan(ys) | isnan(zs));
            idx   = find(valid);
            if numel(idx) < 4
                return; % not enough data
            end

            % sliceMeshAtX emits 2 points per segment: [p1 p2 NaN ...]
            % So idx should have even length; trim last one if needed
            if mod(numel(idx),2) ~= 0
                idx = idx(1:end-1);
            end

            nSeg = numel(idx)/2;
            if nSeg < 2
                return;
            end

            idx1 = idx(1:2:end);
            idx2 = idx(2:2:end);

            p1 = [ys(idx1).', zs(idx1).'];  % each row is [y z]
            p2 = [ys(idx2).', zs(idx2).'];

            % ---------- Build merged node set with tolerance ----------
            allPts = [p1; p2];
            mins   = min(allPts,[],1);
            maxs   = max(allPts,[],1);
            span   = max(maxs - mins);
            if span <= 0
                span = 1;
            end
            tol = 1e-3 * span;  % 0.1% of span

            nodePos  = zeros(0,2);
            nodeCount = 0;
            mapIdx   = zeros(size(allPts,1),1);

            for k = 1:size(allPts,1)
                p = allPts(k,:);
                found = false;
                for n = 1:nodeCount
                    if norm(p - nodePos(n,:)) <= tol
                        mapIdx(k) = n;
                        found = true;
                        break;
                    end
                end
                if ~found
                    nodeCount = nodeCount + 1;
                    nodePos(nodeCount,:) = p;
                    mapIdx(k) = nodeCount;
                end
            end

            % ---------- Build edges for each segment ----------
            edges = zeros(nSeg,2);
            for s = 1:nSeg
                edges(s,1) = mapIdx(s);           % p1 index
                edges(s,2) = mapIdx(s + nSeg);    % p2 index
            end

            % ---------- Walk edges to find closed loops ----------
            used  = false(nSeg,1);
            loops = {};

            for s = 1:nSeg
                if used(s), continue; end

                used(s) = true;
                n1 = edges(s,1);
                n2 = edges(s,2);

                path      = [n1 n2];
                cur       = n2;
                startNode = n1;

                while true
                    % Find an unused edge incident on current node
                    cand = find(~used & (edges(:,1) == cur | edges(:,2) == cur),1);
                    if isempty(cand)
                        break;  % open path
                    end

                    used(cand) = true;
                    e = edges(cand,:);

                    if e(1) == cur
                        nxt = e(2);
                    else
                        nxt = e(1);
                    end

                    path(end+1) = nxt; %#ok<AGROW>
                    cur = nxt;

                    if cur == startNode
                        break;  % closed loop
                    end
                end

                if numel(path) >= 4 && path(1) == path(end)
                    loops{end+1} = path; %#ok<AGROW>
                end
            end

            if isempty(loops)
                return;
            end

            % ---------- Select largest closed loop by perimeter ----------
            bestPerim = -inf;
            bestLoop  = [];

            for i = 1:numel(loops)
                path = loops{i};
                pts  = nodePos(path,:);
                d    = sqrt(sum(diff(pts,1,1).^2,2));
                per  = sum(d);
                if per > bestPerim
                    bestPerim = per;
                    bestLoop  = path;
                end
            end

            if isempty(bestLoop)
                return;
            end

            pts   = nodePos(bestLoop,:);
            yLoop = pts(:,1);
            zLoop = pts(:,2);
        end
        
        % ---------------------------------------------------------------
        % RESAMPLEPROFILEBYTOLERANCE
        % ---------------------------------------------------------------
        function [yR, zR, info] = resampleProfileByTolerance(y, z, tol)
            % RESAMPLEPROFILEBYTOLERANCE Resample a closed profile loop (y,z)
            % so that successive points are spaced by ~tol [mm] in arc length.
            %
            %  INPUTS
            %    y, z : profile coordinates (vectors, any orientation)
            %    tol  : positive scalar [mm], target segment length
            %
            %  OUTPUTS
            %    yR, zR : resampled profile loop (column vectors)
            %
            %  NOTES
            %  - Treats the loop as closed (wraps last->first).
            %  - Collapses any duplicate arc-length samples before interp1,
            %    to avoid "Sample points must be unique" errors.
            %  - Applies a safety clamp on the number of output points.

            % --- Basic validation / normalisation ---
            y = y(:);
            z = z(:);
            yR = y;
            zR = z;
            
            % Default info struct
            info = struct('capHit',false, 'nPoints', numel(yR));

            if numel(y) < 2 || numel(z) < 2 || ~isfinite(tol) || tol <= 0
                return;
            end

            % --- Ensure closure by appending first point at the end ---
            yExt = [y; y(1)];
            zExt = [z; z(1)];

            % --- Arc length along the loop ---
            dSeg = hypot(diff(yExt), diff(zExt));
            s    = [0; cumsum(dSeg)];

            % Collapse duplicate arc-length samples (zero-length segments)
            [sUnique, idxUnique] = unique(s, 'stable');
            yExt = yExt(idxUnique);
            zExt = zExt(idxUnique);

            if numel(sUnique) < 2
                % Not enough unique samples to resample meaningfully
                yR = yExt;
                zR = zExt;
                return;
            end

            totalLen = sUnique(end);
            if totalLen <= 0
                yR = yExt;
                zR = zExt;
                info.nPoints = numel(yR);
                return;
            end

            % --- Target point count from tolerance, with safety bounds ---
            % --- Target point count from tolerance, with safety bounds ---
            rawN    = totalLen / tol;
            nTarget = round(rawN);

            minPoints = HotWireSTEPApp_v6_helpers.ProfileResampleMinPoints;
            maxPoints = HotWireSTEPApp_v6_helpers.ProfileResampleMaxPoints;

            nTarget = max(nTarget, minPoints);     % at least minPoints
            capHit  = nTarget > maxPoints;         % requesting more than cap
            nTarget = min(nTarget, maxPoints);     % enforce cap

            if nTarget < 3
                yR = yExt;
                zR = zExt;
                return;
            end

            sSamples = linspace(0, totalLen, nTarget).';

            % --- Interpolate back onto the loop ---
            yR = interp1(sUnique, yExt, sSamples, 'linear');
            zR = interp1(sUnique, zExt, sSamples, 'linear');
            info.capHit  = capHit;
            info.nPoints = numel(yR);

        end

        function [yKerf, zKerf] = offsetProfileLoop(yLoop, zLoop, kerf)
            %OFFSETPROFILELOOP Polygon offset via polybuffer for a closed Y–Z profile.
            %
            %   [yKerf,zKerf] = offsetProfileLoop(yLoop,zLoop,kerf)
            %
            % Inputs:
            %   yLoop, zLoop : profile loop (row or column, same length)
            %   kerf         : offset distance [mm]
            %
            %   NOTE: POSITIVE kerf expands the loop (wire centreline
            %         moves OUTWARDS relative to the material).
            %
            % Outputs:
            %   yKerf, zKerf : offset loop, same orientation as input.
            %
            % Implementation:
            %   Uses polyshape + polybuffer in the Y–Z plane. If multiple
            %   regions are produced, keeps the largest by area.

            % Default: echo input if nothing sensible can be done
            yKerf = yLoop;
            zKerf = zLoop;

            % Trivial / invalid kerf → no change
            if ~isfinite(kerf) || kerf == 0
                return;
            end

            % Basic validation
            y = yLoop(:);
            z = zLoop(:);

            if numel(y) < 3 || numel(z) < 3 ...
                    || any(~isfinite(y)) || any(~isfinite(z))
                return;
            end

            % Remove NaNs
            valid = isfinite(y) & isfinite(z);
            y = y(valid);
            z = z(valid);
            if numel(y) < 3
                return;
            end

            % Remove duplicate last vertex if it coincides with the first
            spanYZ = max(max(abs([y; z])));
            if spanYZ <= 0
                spanYZ = 1;
            end
            if hypot(y(end) - y(1), z(end) - z(1)) < 1e-9 * spanYZ
                y = y(1:end-1);
                z = z(1:end-1);
            end

            try
                % Build polyshape in the Y–Z plane
                p = polyshape(y, z, 'Simplify', true);

                if isempty(p.Vertices)
                    return;
                end

                % polybuffer with POSITIVE kerf = outward offset
                pb = polybuffer(p, kerf);

                % No geometry after buffer (e.g. huge negative kerf)
                if isempty(pb.Vertices)
                    return;
                end

                % If multiple disjoint regions, keep the largest by area
                regs = regions(pb);
                if numel(regs) > 1
                    a = area(regs);
                    [~, idxMax] = max(a);
                    pb = regs(idxMax);
                end

                % Get boundary of buffered polygon (closed loop)
                [yB, zB] = boundary(pb);

                % Preserve row/column orientation
                if isrow(yLoop)
                    yKerf = yB.';
                    zKerf = zB.';
                else
                    yKerf = yB;
                    zKerf = zB;
                end

            catch ME
                % If polybuffer / polyshape fails (e.g. toolbox missing),
                % just warn and return the original loop.
                warning('offsetProfileLoop:PolybufferFailed', ...
                    'Kerf offset via polybuffer failed (%s). Returning original profile.', ...
                    ME.message);
                yKerf = yLoop;
                zKerf = zLoop;
            end
        end

        function [yOut, zOut] = reorderLoopByMinY(yIn, zIn)
            %REORDERLOOPBYMINY Rotate a closed loop so that the first
            % vertex is the one with the minimum Y (then minimum Z).
            %
            %   [yOut, zOut] = reorderLoopByMinY(yIn, zIn)
            %
            % Inputs:
            %   yIn, zIn : profile loop (row or column, same length)
            %
            % Outputs:
            %   yOut, zOut : reordered loop, closed
            %               (last point duplicates first).
            %
            % NOTE:
            %   - If the loop is already (approximately) closed, we drop
            %     the last duplicate vertex before rotating.
            %   - If there are multiple vertices with the same minimum Y,
            %     we choose the one with the smallest Z.

            yOut = yIn;
            zOut = zIn;

            if isempty(yIn) || numel(yIn) < 2 || numel(zIn) ~= numel(yIn)
                return;
            end

            y = yIn(:);
            z = zIn(:);

            if any(~isfinite(y)) || any(~isfinite(z))
                return;
            end

            % Remove duplicate last vertex if it coincides with the first
            spanYZ = max(max(abs([y; z])));
            if spanYZ <= 0
                spanYZ = 1;
            end

            if hypot(y(end) - y(1), z(end) - z(1)) < 1e-9 * spanYZ
                y = y(1:end-1);
                z = z(1:end-1);
            end

            if numel(y) < 2
                yOut = y;
                zOut = z;
                return;
            end

            % Find index of minimum Y, break ties with minimum Z
            yMin = min(y);
            % Allow for floating-point fuzz on "same Y"
            tolY = 1e-9 * max(abs(yMin), 1);
            idxCandidates = find(abs(y - yMin) <= tolY);

            if numel(idxCandidates) > 1
                [~, k] = min(z(idxCandidates));
                idxStart = idxCandidates(k);
            else
                idxStart = idxCandidates(1);
            end

            % Rotate so idxStart becomes the first point
            yRot = [y(idxStart:end); y(1:idxStart-1)];
            zRot = [z(idxStart:end); z(1:idxStart-1)];

            % Re-close the loop explicitly
            yRot = [yRot; yRot(1)];
            zRot = [zRot; zRot(1)];

            % Match input orientation (row vs column)
            if isrow(yIn)
                yOut = yRot.';
                zOut = zRot.';
            else
                yOut = yRot;
                zOut = zRot;
            end
        end

        % ===============================================================
        % BILLET DEFAULTS FROM MESH
        % ===============================================================
        function billet = computeDefaultBilletFromMesh(V, gapYZ, xPlaneA, xPlaneB)
            %COMPUTEDEFAULTBILLETFROMMESH Default billet from mesh vertices.
            %
            %   - Leaves ~gapYZ clearance around the model in Y and Z.
            %   - Billet height (Z) is rounded UP to 50 / 75 / 100 mm.
            %   - Billet length (X):
            %       * If xPlaneA/xPlaneB are provided and finite:
            %           → matches the distance between the two planes
            %             (billet Xmin/Xmax = plane positions).
            %       * Otherwise:
            %           → falls back to the model X bounding box.
            %
            % Inputs
            %   V        : Nx3 model vertices [X Y Z]
            %   gapYZ    : scalar clearance in Y/Z (mm), default 5
            %   xPlaneA  : X position of first plane (optional)
            %   xPlaneB  : X position of second plane (optional)
            %
            % Output
            %   billet : struct with fields
            %       gapYZ
            %       lengthX, widthY, heightZ
            %       Xmin, Xmax, Ymin, Ymax, Zmin, Zmax
            %       clearLeft, clearRight, clearBottom, clearTop

            % ---- Defaults / validation ----
            if nargin < 2 || ~isscalar(gapYZ) || ~isfinite(gapYZ) || gapYZ <= 0
                gapYZ = 5;   % 5 mm clearance in Y/Z
            end

            billet = struct( ...
                'gapYZ',       gapYZ, ...
                'lengthX',     NaN, ...
                'widthY',      NaN, ...
                'heightZ',     NaN, ...
                'Xmin',        NaN, ...
                'Xmax',        NaN, ...
                'Ymin',        NaN, ...
                'Ymax',        NaN, ...
                'Zmin',        NaN, ...
                'Zmax',        NaN, ...
                'clearLeft',   NaN, ...
                'clearRight',  NaN, ...
                'clearBottom', NaN, ...
                'clearTop',    NaN);

            if isempty(V) || size(V,2) ~= 3
                return;
            end

            % ---- Model bounding box ----
            mins = min(V,[],1);
            maxs = max(V,[],1);

            minX = mins(1);  maxX = maxs(1);
            minY = mins(2);  maxY = maxs(2);
            minZ = mins(3);  maxZ = maxs(3);

            widthYModel  = maxY - minY;   %#ok<NASGU> % kept for clarity / future use
            heightZModel = maxZ - minZ;   %#ok<NASGU>

            % ---- Billet X: prefer plane separation if given ----
            usePlanes = (nargin >= 4) ...
                && all(isfinite([xPlaneA, xPlaneB])) ...
                && (xPlaneA ~= xPlaneB);

            if usePlanes
                billetXmin = min(xPlaneA, xPlaneB);
                billetXmax = max(xPlaneA, xPlaneB);
            else
                % Fallback to model span
                billetXmin = minX;
                billetXmax = maxX;
            end

            % ---- Billet Y: add gapYZ either side ----
            billetYmin = minY - gapYZ;
            billetYmax = maxY + gapYZ;

            % ---- Billet Z: add gapYZ, then snap height to 50/75/100 ----
            rawZmin   = minZ - gapYZ;
            rawZmax   = maxZ + gapYZ;
            rawHeight = rawZmax - rawZmin;

            stockHeights = [50 75 100];  % mm

            h = rawHeight;
            idx = find(stockHeights >= rawHeight - 1e-6, 1, 'first');
            if ~isempty(idx)
                % Round UP to next available stock size
                h = stockHeights(idx);
            else
                % If model is taller than 100mm, just use the actual height
                h = rawHeight;
            end

            % Keep the bottom against the requested clearance, grow upwards
            billetZmin = rawZmin;
            billetZmax = billetZmin + h;

            % ---- Store billet dims / extents ----
            billet.lengthX = billetXmax - billetXmin;
            billet.widthY  = billetYmax - billetYmin;
            billet.heightZ = billetZmax - billetZmin;

            billet.Xmin = billetXmin;
            billet.Xmax = billetXmax;
            billet.Ymin = billetYmin;
            billet.Ymax = billetYmax;
            billet.Zmin = billetZmin;
            billet.Zmax = billetZmax;

            % ---- Actual clearances with snapped height ----
            billet.clearLeft   = minY - billetYmin;   % ≈ gapYZ
            billet.clearRight  = billetYmax - maxY;   % ≈ gapYZ
            billet.clearBottom = minZ - billetZmin;   % = gapYZ
            billet.clearTop    = billetZmax - maxZ;   % ≥ gapYZ (because of rounding)
        end

    end
end
