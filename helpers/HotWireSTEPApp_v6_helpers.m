classdef HotWireSTEPApp_v6_helpers
    % Helper utilities for HotWireSTEPApp_v6_2
    %
    % Contains:
    %   - importSTEP_FreeCAD : STEP → STL → triangulation (V,F)
    %   - sliceMeshAtX       : Triangle–plane intersection at X = const
    %

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
            fprintf(fid,"mesh = MeshPart.meshFromShape(Shape=shape,LinearDeflection=0.5,AngularDeflection=0.3)\n");
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
    end
end
