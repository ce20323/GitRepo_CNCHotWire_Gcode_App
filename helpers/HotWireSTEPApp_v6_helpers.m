classdef HotWireSTEPApp_v6_helpers
    % Helper utilities for HotWireSTEPApp_v6_2
    %
    % Contains:
    %   - importSTEP_FreeCAD : STEP -> STL -> triangulation (V,F)
    %   - sliceMeshAtX       : Triangle–plane intersection at X = const
    %

    properties (Constant)

        % --- Profile Sampling ---
        ProfileResampleMinPoints = 50;
        ProfileResampleMaxPoints = 20000;

        % --- FreeCAD Meshing ---
        FreeCADLinearDeflection  = 0.1;
        FreeCADAngularDeflection = 0.1;

        % --- Billet Default Rules ---
        BilletXBuffer   = 0.001;  % mm (brief: +0.001 either side)
        BilletYBuffer   = 5.0;    % mm (brief: 5mm front/back)
        BilletZBuffer   = 10.0;   % mm (brief: model height + 10)
        BilletZMinClear = 5.0;    % mm (brief: min-Z raised 5mm from bottom)
        BilletStockHeights = [50 75 100]; % mm

    end

    methods(Static)

        % ===============================================================
        % STEP -> STL -> MESH IMPORT USING FREECAD
        % ===============================================================
        function [V,F] = importSTEP_FreeCAD(cadPath, freeCADExe)

            V = []; F = [];
            if ~isfile(cadPath), warning('STEP file not found: %s', cadPath); return; end

            if nargin < 2 || ~isfile(freeCADExe)
                warning('FreeCAD executable not found: %s', freeCADExe); return;
            end

            % Temporary files
            tmpID  = char(java.util.UUID.randomUUID());
            outSTL = fullfile(tempdir, ['fc_out_' tmpID '.stl']);
            pyFile = fullfile(tempdir, ['fc_' tmpID '.py']);

            % Write FreeCAD python script
            fid = fopen(pyFile,'w');
            fprintf(fid,"import FreeCAD, Part, Mesh, MeshPart\n");
            fprintf(fid,"doc = FreeCAD.newDocument()\n");
            fprintf(fid,"shape = Part.Shape()\n");
            fprintf(fid,"shape.read(r'%s')\n", cadPath);
            fprintf(fid, "mesh = MeshPart.meshFromShape(Shape=shape,LinearDeflection=%g,AngularDeflection=%g)\n", ...
                HotWireSTEPApp_v6_helpers.FreeCADLinearDeflection, HotWireSTEPApp_v6_helpers.FreeCADAngularDeflection);
            fprintf(fid,"mesh.write(r'%s')\n", outSTL);
            fprintf(fid,"FreeCAD.closeDocument(doc.Name)\n");
            fclose(fid);

            % Run FreeCAD
            [status,~] = system(sprintf('"%s" "%s"', freeCADExe, pyFile));
            if status ~= 0, warning('FreeCAD conversion failed.'); return; end

            % Read STL
            if isfile(outSTL)
                raw = stlread(outSTL);
                F = double(raw.ConnectivityList); V = double(raw.Points);
            else, warning('STL output not found: %s', outSTL); end
        end

        % ===============================================================
        % TRIANGLE–PLANE SLICER  (X = x0)
        % ===============================================================
        function [xs, ys, zs] = sliceMeshAtX(V, F, x0)
            xs = []; ys = []; zs = [];
            for k = 1:size(F,1)
                tri = F(k,:); A = V(tri(1),:); B = V(tri(2),:); C = V(tri(3),:);
                X = [A(1), B(1), C(1)];
                if all(X < x0) || all(X > x0), continue; end
                pts = zeros(2,3); count = 0; edges = [A;B;C;A];
                for i = 1:3
                    P1 = edges(i,:); P2 = edges(i+1,:);
                    if (P1(1)-x0)*(P2(1)-x0) <= 0 && P1(1) ~= P2(1)
                        t = (x0 - P1(1)) / (P2(1)-P1(1));
                        if t >= 0 && t <= 1
                            count = count + 1; pts(count,:) = P1 + t*(P2-P1);
                            if count == 2, break; end
                        end
                    end
                end
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
            yLoop = []; zLoop = []; if isempty(xs) || all(isnan(xs)), return; end
            valid = ~(isnan(xs) | isnan(ys) | isnan(zs)); idx = find(valid);
            if numel(idx) < 4, return; end
            if mod(numel(idx),2) ~= 0, idx = idx(1:end-1); end
            nSeg = numel(idx)/2;
            p1 = [ys(idx(1:2:end)).', zs(idx(1:2:end)).'];
            p2 = [ys(idx(2:2:end)).', zs(idx(2:2:end)).'];
            allPts = [p1; p2]; 
            span = max(max(allPts)-min(allPts));
            tol = 1e-3 * max(span, 1);
            nodePos = zeros(0,2); nodeCount = 0; mapIdx = zeros(size(allPts,1),1);
            for k = 1:size(allPts,1)
                p = allPts(k,:); found = false;
                for n = 1:nodeCount
                    if norm(p - nodePos(n,:)) <= tol, mapIdx(k) = n; found = true; break; end
                end
                if ~found
                    nodeCount = nodeCount + 1; nodePos(nodeCount,:) = p; mapIdx(k) = nodeCount;
                end
            end
            edges = [mapIdx(1:nSeg), mapIdx(nSeg+1:end)];
            used = false(nSeg,1); loops = {};
            for s = 1:nSeg
                if used(s), continue; end
                used(s) = true; cur = edges(s,2); path = [edges(s,1) cur]; startNode = path(1);
                while true
                    cand = find(~used & (edges(:,1) == cur | edges(:,2) == cur),1);
                    if isempty(cand), break; end
                    used(cand) = true; e = edges(cand,:);
                    if e(1) == cur, nxt = e(2); else, nxt = e(1); end
                    path(end+1) = nxt; cur = nxt;
                    if cur == startNode, break; end
                end
                if numel(path) >= 4 && path(1) == path(end), loops{end+1} = path; end
            end
            if isempty(loops), return; end
            [~, bestIdx] = max(cellfun(@(p) sum(sqrt(sum(diff(nodePos(p,:),1,1).^2,2))), loops));
            pts = nodePos(loops{bestIdx},:); yLoop = pts(:,1); zLoop = pts(:,2);
        end

        % ===============================================================
        % RESAMPLING & SYNC HELPERS
        % ===============================================================
        function [yR, zR] = resampleProfileByTolerance(y, z, tol)
            y = y(:); z = z(:); if numel(y) < 2, yR=y; zR=z; return; end
            yExt = [y; y(1)]; zExt = [z; z(1)];

            s = [0; cumsum(hypot(diff(yExt), diff(zExt)))];
            % Ensure unique samples to avoid interp1 errors
            [sU, idxU] = unique(s, 'stable');
            if numel(sU) < 2, yR=y; zR=z; return; end

            totalLen = sU(end);
            N = min(max(round(totalLen/tol), 50), 20000);
            yR = interp1(sU, yExt(idxU), linspace(0, totalLen, N).', 'linear');
            zR = interp1(sU, zExt(idxU), linspace(0, totalLen, N).', 'linear');
        end

        function [yLS, zLS, yRS, zRS] = resampleProfilesSynced(yL, zL, yR, zR, tol)
            % --- STEP 1: Geometric Alignment ---
            % Ensure both loops start at the same relative physical "Nose" (Min Y)
            [yL, zL] = HotWireSTEPApp_v6_helpers.reorderLoopByMinY(yL, zL);
            [yR, zR] = HotWireSTEPApp_v6_helpers.reorderLoopByMinY(yR, zR);

            % --- STEP 2: Calculate Normalized Arc Length ---
            % We match points by % distance around the shape, NOT by point index.
            distL = [0; cumsum(sqrt(diff(yL).^2 + diff(zL).^2))];
            distR = [0; cumsum(sqrt(diff(yR).^2 + diff(zR).^2))];

            totalL = distL(end);
            totalR = distR(end);

            sL = distL / totalL; % 0 to 1
            sR = distR / totalR; % 0 to 1

            % Determine how many points we need based on the larger profile
            N = ceil(max(totalL, totalR) / tol);
            N = max(N, 50); % Minimum resolution
            sTarget = linspace(0, 1, N)';

            % --- STEP 3: Resample using Arc-Length Mapping ---
            % This forces Point 10% on Left to meet Point 10% on Right
            [sLu, iL] = unique(sL, 'stable');
            [sRu, iR] = unique(sR, 'stable');

            yLS = interp1(sLu, yL(iL), sTarget, 'linear');
            zLS = interp1(sLu, zL(iL), sTarget, 'linear');
            yRS = interp1(sRu, yR(iR), sTarget, 'linear');
            zRS = interp1(sRu, zR(iR), sTarget, 'linear');
        end

        function [yLS, zLS, yRS, zRS] = syncPointCounts(yL, zL, yR, zR)
            nL = numel(yL); nR = numel(yR); N = max(nL, nR);
            if nL == nR, yLS = yL; zLS = zL; yRS = yR; zRS = zR; return; end
            yLS = interp1(linspace(0,1,nL), yL(:), linspace(0,1,N), 'linear').';
            zLS = interp1(linspace(0,1,nL), zL(:), linspace(0,1,N), 'linear').';
            yRS = interp1(linspace(0,1,nR), yR(:), linspace(0,1,N), 'linear').';
            zRS = interp1(linspace(0,1,nR), zR(:), linspace(0,1,N), 'linear').';
        end

        function [towerL, towerR] = projectToTowers(yL, zL, xL, yR, zR, xR, spanX)
            towerL.y = yL + (0 - xL) .* (yR - yL) ./ (xR - xL);
            towerL.z = zL + (0 - xL) .* (zR - zL) ./ (xR - xL);
            towerR.y = yL + (spanX - xL) .* (yR - yL) ./ (xR - xL);
            towerR.z = zL + (spanX - xL) .* (zR - zL) ./ (xR - xL);
        end

        function [yK, zK] = offsetProfileLoop(yL, zL, kerf)
            yK = yL; zK = zL; if kerf == 0, return; end
            try
                p = polyshape(yL, zL, 'Simplify', true);
                pb = polybuffer(p, kerf);
                regs = regions(pb); [~,idx] = max(area(regs));
                [yK, zK] = boundary(regs(idx));
            catch, end
        end

        function [y, z] = reorderLoopByMinY(y, z)
            % Robustly finds the "Leading Edge" pole
            % If multiple points have the same Min Y, it picks the mid-Z one
            minY = min(y);
            idxAll = find(abs(y - minY) < 1e-6);
            if numel(idxAll) > 1
                % Pick the point in the middle of the nose curve
                [~, subIdx] = min(abs(z(idxAll) - mean(z(idxAll))));
                idx = idxAll(subIdx);
            else
                idx = idxAll(1);
            end
            y = [y(idx:end); y(1:idx-1)];
            z = [z(idx:end); z(1:idx-1)];
            % Close loop
            y(end+1) = y(1); z(end+1) = z(1);
        end

        function billet = computeDefaultBilletFromMesh(V, xPlaneA, xPlaneB)
            mins = min(V,[],1); maxs = max(V,[],1);
            billet.Xmin = min(xPlaneA, xPlaneB) - 0.001; billet.Xmax = max(xPlaneA, xPlaneB) + 0.001;
            billet.Ymin = mins(2) - 5; billet.Ymax = maxs(2) + 5;
            modelH = maxs(3) - mins(3); rawH = modelH + 10;
            billet.Zmin = mins(3) - 5; billet.Zmax = billet.Zmin + rawH;
        end
    end
end