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
            % Clean Inputs (Remove duplicates/micro-steps < 0.001mm)
            function [x,y] = clean_path(x,y)
                if numel(x) < 2, return; end
                d2 = [1; (diff(x).^2 + diff(y).^2)];
                keep = d2 > 1e-8;
                x = x(keep); y = y(keep);
                if (x(1)~=x(end) || y(1)~=y(end)), x(end+1)=x(1); y(end+1)=y(1); end
            end

            [yL, zL] = clean_path(yL, zL);
            [yR, zR] = clean_path(yR, zR);

            % 1. Align Start Points & Winding
            [yL, zL] = HotWireSTEPApp_v6_helpers.reorderLoopByMinY(yL, zL);
            [yR, zR] = HotWireSTEPApp_v6_helpers.reorderLoopByMinY(yR, zR);

            areaL = sum((yL(1:end-1).*zL(2:end)) - (yL(2:end).*zL(1:end-1)));
            areaR = sum((yR(1:end-1).*zR(2:end)) - (yR(2:end).*zR(1:end-1)));
            if sign(areaL) ~= sign(areaR)
                yR = flipud(yR); zR = flipud(zR);
                [yR, zR] = HotWireSTEPApp_v6_helpers.reorderLoopByMinY(yR, zR);
            end

            % 2. Baseline Generation (Oversample)
            distL = [0; cumsum(hypot(diff(yL), diff(zL)))];
            distR = [0; cumsum(hypot(diff(yR), diff(zR)))];
            maxLen = max(distL(end), distR(end));

            baselineRes = 0.1;
            N = ceil(maxLen / baselineRes);
            N = max(N, 1000);

            s_rawL = distL / distL(end); s_rawR = distR / distR(end);
            s_fine = linspace(0, 1, N)';

            [suL, iuL] = unique(s_rawL,'stable'); [suR, iuR] = unique(s_rawR,'stable');

            yLf = interp1(suL, yL(iuL), s_fine, 'linear');
            zLf = interp1(suL, zL(iuL), s_fine, 'linear');
            yRf = interp1(suR, yR(iuR), s_fine, 'linear');
            zRf = interp1(suR, zR(iuR), s_fine, 'linear');

            % 3. RDP Reduction (Iterative 4D)
            pts4D = [yLf, zLf, yRf, zRf];
            keepMask = false(N, 1);
            keepMask(1) = true; keepMask(end) = true;

            stack = [1, N];

            while ~isempty(stack)
                idxEnd = stack(end);
                idxStart = stack(end-1);
                stack(end-1:end) = [];

                if idxEnd - idxStart < 2
                    continue;
                end

                P1 = pts4D(idxStart, :);
                P2 = pts4D(idxEnd, :);

                rng = (idxStart+1):(idxEnd-1);
                Pts = pts4D(rng, :);

                V = P2 - P1;
                lenSq = sum(V.^2);
                W = bsxfun(@minus, Pts, P1);

                if lenSq < 1e-12
                    distsSq = sum(W.^2, 2);
                else
                    t = (W * V') / lenSq;
                    t = max(0, min(1, t)); % Clamp
                    Closest = bsxfun(@plus, P1, bsxfun(@times, t, V));
                    distsSq = sum((Pts - Closest).^2, 2);
                end

                [maxSq, localIdx] = max(distsSq);

                if maxSq > (tol^2)
                    splitIdx = rng(localIdx);
                    keepMask(splitIdx) = true;
                    stack = [stack, splitIdx, idxEnd];
                    stack = [stack, idxStart, splitIdx];
                end
            end

            % 4. Final Extract
            yLS = pts4D(keepMask, 1); zLS = pts4D(keepMask, 2);
            yRS = pts4D(keepMask, 3); zRS = pts4D(keepMask, 4);

            yLS(end) = yLS(1); zLS(end) = zLS(1);
            yRS(end) = yRS(1); zRS(end) = zRS(1);
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

        function [yo, zo] = offsetProfileLoop(yIn, zIn, kerf)
            % ===========================================================
            % OFFSET PROFILE LOOP: Kerf compensation via polybuffer
            % ===========================================================
            % Default fallback to input
            yo = yIn; zo = zIn;

            % 1. Validation & Input Prep
            if ~isfinite(kerf) || kerf == 0, return; end
            y = yIn(:); z = zIn(:);

            % Remove non-finite data
            valid = isfinite(y) & isfinite(z);
            y = y(valid); z = z(valid);
            if numel(y) < 3, return; end

            % 2. Pre-clean (Remove Mesh artifacts)
            % Mesh slicing often creates tiny duplicate points.
            % 'Unique' prevents the "Duplicate Vertices" warning at the source.
            inputPoints = round([y, z], 8);
            [~, uniqueIdx] = unique(inputPoints, 'rows', 'stable');
            y = y(uniqueIdx);
            z = z(uniqueIdx);

            % 3. Targeted Warning Suppression
            % We silence 'all' inside this scope to ensure silence.
            % onCleanup ensures warnings are restored even if the function crashes.
            originalState = warning('off', 'all');
            cleanupObj = onCleanup(@() warning(originalState));

            try
                % 4. Create Polyshape
                pgon = polyshape(y, z, 'Simplify', true);
                if pgon.NumRegions == 0, return; end

                % 5. Perform Buffer (The Kerf Offset)
                % polybuffer is the standard core MATLAB method
                pgonOut = polybuffer(pgon, kerf);
                if pgonOut.NumRegions == 0, return; end

                % 6. Handle Multi-Region Results
                % In case of complex kerf artifacts, keep the largest shape
                if pgonOut.NumRegions > 1
                    areaList = area(pgonOut.regions);
                    [~, maxIdx] = max(areaList);
                    pgonOut = pgonOut.regions(maxIdx);
                end

                % 7. Extract Final Boundary
                % 'boundary' returns a closed loop [N+1 x 1]
                [yo, zo] = boundary(pgonOut);

            catch
                % Silently fall back to input on failure
                return;
            end

            % 8. Transpose back if necessary to match input
            if isrow(yIn), yo = yo.'; zo = zo.'; end
        end

        function [y, z] = reorderLoopByMinY(y, z)
            % 1. Force to Column Vectors
            y = y(:); z = z(:);

            % 2. Remove tailing point duplicate for math
            if numel(y) > 1 && abs(y(1)-y(end)) < 1e-6 && abs(z(1)-z(end)) < 1e-6
                ytemp = y(1:end-1); ztemp = z(1:end-1);
            else
                ytemp = y; ztemp = z;
            end

            % 3. Find Geometric Centroid
            cy = mean(ytemp);
            [~, startIdx] = min(ytemp - cy);

            % 4. Reorder (Using SEMICOLON for vertical concatenation)
            y = [ytemp(startIdx:end); ytemp(1:startIdx-1)];
            z = [ztemp(startIdx:end); ztemp(1:startIdx-1)];

            % 5. Force exact closure
            y(end+1) = y(1);
            z(end+1) = z(1);
        end

        function billet = computeDefaultBilletFromMesh(V, xPlaneA, xPlaneB)
            mins = min(V,[],1); maxs = max(V,[],1);

            % X Logic: Fit to cutting planes + buffer
            billet.Xmin = min(xPlaneA, xPlaneB) - 0.001;
            billet.Xmax = max(xPlaneA, xPlaneB) + 0.001;

            % Y Logic: Fit to model + 5mm
            billet.Ymin = mins(2) - 5;
            billet.Ymax = maxs(2) + 5;

            % Z Logic: Stock Selection
            modelH = maxs(3) - mins(3);
            requiredH = modelH + 10; % Minimum requirement

            % Get standard stocks
            stocks = HotWireSTEPApp_v6_helpers.BilletStockHeights; % [50 75 100]

            % Default to custom height
            stockH = requiredH;

            % Attempt to snap to standard stock
            for i = 1:numel(stocks)
                if requiredH <= stocks(i)
                    stockH = stocks(i);
                    break;
                end
            end

            % Apply Z (raising min-Z by 5mm as per original logic)
            billet.Zmin = mins(3) - 5;
            billet.Zmax = billet.Zmin + stockH;
        end

    end
end