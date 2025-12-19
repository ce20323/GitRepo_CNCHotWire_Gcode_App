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
            %OFFSETPROFILELOOP Robust polygon offset for a closed Y–Z profile.
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
            % Method:
            %   - Treats profile as a closed polygon.
            %   - For each edge, builds an outward offset line.
            %   - For each vertex, intersects its two adjacent offset
            %     lines to get the new corner position.
            %   - Uses a miter limit so very sharp corners don't explode.
            %   - Then smooths small concave notches so the kerf path
            %     "bridges" tight internal corners instead of kinking.

            % ----- Basic validation -----
            yKerf = yLoop;
            zKerf = zLoop;

            if kerf == 0
                return;
            end

            y = yLoop(:);
            z = zLoop(:);

            n = numel(y);
            if n < 3 || any(~isfinite(y)) || any(~isfinite(z)) || ~isfinite(kerf)
                return;
            end

            % Ensure closure for geometry; we'll drop the duplicate at the end
            if y(1) ~= y(end) || z(1) ~= z(end)
                y = [y; y(1)];
                z = [z; z(1)];
            end
            N = numel(y) - 1;                      % number of real vertices

            V = [y(1:N), z(1:N)];                  % Nx2 vertices

            % ----- Determine polygon orientation (CCW vs CW) -----
            A = 0.5 * sum( V(:,1) .* circshift(V(:,2),-1) ...
                         - circshift(V(:,1),-1) .* V(:,2) );
            if A == 0
                % Degenerate polygon – nothing clever we can do
                return;
            end

            flipped = false;
            if A < 0
                % Make polygon CCW for a consistent "outward" direction
                V = flipud(V);
                flipped = true;
            end

            % ----- Edge tangents and outward normals -----
            Vnext = circshift(V,-1,1);             % vertex i -> i+1
            E     = Vnext - V;                     % edge vectors
            L     = hypot(E(:,1), E(:,2));
            L(L == 0) = eps;

            % For CCW polygon, outward normal to edge [dy, -dx]/L
            Nrm = [ E(:,2)./L, -E(:,1)./L ];       % Nx2 normals

            % ----- Offset each edge by kerf -----
            % Each edge i defines line:  n_i · p = c_i
            % Offset line:                 n_i · p = c_i + kerf
            c = sum(Nrm .* V, 2);                  % n_i · v_i

            % ----- For each vertex, intersect its two adjacent offset lines -----
            Yk = zeros(N,1);
            Zk = zeros(N,1);

            % Miter limit: maximum allowed ratio |corner shift| / |kerf|
            miterLimit = 4;   % tune if needed

            for i = 1:N
                iPrev = i - 1;
                if iPrev == 0
                    iPrev = N;
                end
                iCurr = i;

                n1 = Nrm(iPrev,:);   c1 = c(iPrev) + kerf;
                n2 = Nrm(iCurr,:);   c2 = c(iCurr) + kerf;

                % Solve [n1; n2] * p = [c1; c2]
                A2 = [n1; n2];
                b2 = [c1; c2];

                % If nearly parallel, use averaged-normal fallback
                if abs(det(A2)) < 1e-8
                    nAvg = n1 + n2;
                    if norm(nAvg) < 1e-8
                        nAvg = n1;   % give up and use one normal
                    end
                    nAvg = nAvg ./ norm(nAvg);
                    pk = V(i,:) + kerf * nAvg;
                else
                    % b2 must be column for A2\b2; result is 2x1
                    pk = (A2 \ b2).';      % row [y z]
                end

                % Miter-length clamp: avoid huge spikes at very sharp corners
                shiftVec = pk - V(i,:);
                mLen     = norm(shiftVec);
                if mLen > miterLimit * abs(kerf)
                    nAvg = n1 + n2;
                    if norm(nAvg) < 1e-8
                        nAvg = n1;
                    end
                    nAvg = nAvg ./ norm(nAvg);
                    pk = V(i,:) + kerf * nAvg;
                end

                Yk(i) = pk(1);
                Zk(i) = pk(2);
            end

            % ----- Concave-corner smoothing (bridge tight internal notches) -----
            P = [Yk, Zk];
            if N >= 4
                % "Small" notch length threshold: a few kerf widths
                smallLen = max(4*abs(kerf), 1e-3);

                for i = 1:N
                    ip = i - 1; if ip == 0, ip = N; end
                    in = i + 1; if in > N, in = 1; end

                    v1 = P(i,:) - P(ip,:);
                    v2 = P(in,:) - P(i,:);

                    if norm(v1) < eps || norm(v2) < eps
                        continue;
                    end

                    % Signed turn at vertex i
                    crossVal = v1(1)*v2(2) - v1(2)*v2(1);

                    % For CCW polygon, cross < 0 => concave corner
                    isConcave = (crossVal < 0);

                    if isConcave ...
                            && norm(v1) < smallLen ...
                            && norm(v2) < smallLen
                        % Replace the vertex by the midpoint of neighbours:
                        % this "bridges" the notch and kills the little kink.
                        P(i,:) = 0.5*(P(ip,:) + P(in,:));
                    end
                end
            end
            Yk = P(:,1);
            Zk = P(:,2);

            % If we flipped orientation to CCW earlier, flip back so the
            % output loop matches the original direction
            if flipped
                Yk = flipud(Yk);
                Zk = flipud(Zk);
            end

            % Return in same row/column orientation as input
            if isrow(yLoop)
                yKerf = Yk.';
                zKerf = Zk.';
            else
                yKerf = Yk;
                zKerf = Zk;
            end
        end

    end
end
