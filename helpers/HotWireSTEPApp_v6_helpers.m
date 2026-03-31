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

            V = [];
            F =[];

            cadPath = char(cadPath);
            freeCADExe = char(freeCADExe);
            [~, modelName, ext] = fileparts(cadPath);

            disp(['[HotWire CAM] Importing ', modelName, ext, ' via FreeCAD...']);

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

            % Convert backslashes to forward slashes for Python string safety
            safeCadPath = strrep(cadPath, '\', '/');
            safeOutSTL  = strrep(outSTL, '\', '/');

            % Write FreeCAD python script
            fid = fopen(pyFile,'w');
            fprintf(fid,"import sys\n");
            fprintf(fid,"import FreeCAD, Part, Mesh, MeshPart\n");
            fprintf(fid,"doc = FreeCAD.newDocument()\n");
            fprintf(fid,"shape = Part.Shape()\n");
            fprintf(fid,"shape.read(r'%s')\n", safeCadPath);
            fprintf(fid, "mesh = MeshPart.meshFromShape(Shape=shape,LinearDeflection=%g,AngularDeflection=%g)\n", ...
                HotWireSTEPApp_v6_helpers.FreeCADLinearDeflection, HotWireSTEPApp_v6_helpers.FreeCADAngularDeflection);
            fprintf(fid,"mesh.write(r'%s')\n", safeOutSTL);
            fprintf(fid,"FreeCAD.closeDocument(doc.Name)\n");
            fclose(fid);

            % The Bulletproof Windows CMD workaround[fcDir, fcName, fcExt] = fileparts(freeCADExe);
            fcExeName = [fcName, fcExt];
            cmdStr = sprintf('cd /d "%s" & %s "%s"', fcDir, fcExeName, pyFile);

            [status, cmdout] = system(cmdStr);

            if status ~= 0
                disp('[HotWire CAM ERROR] FreeCAD Execution Failed.');
                disp(['Attempted Command: ', cmdStr]);
                disp('FreeCAD Console Output:');
                disp(cmdout);
                warning('FreeCAD conversion failed. See command window for details.');
                return;
            end

            % Read STL
            if isfile(outSTL)
                raw = stlread(outSTL);
                F = double(raw.ConnectivityList);
                V = double(raw.Points);
                disp(['[HotWire CAM] Import successful. Mesh generated with ', num2str(size(V,1)), ' vertices.']);
            else
                disp('[HotWire CAM ERROR] FreeCAD finished, but STL file was not generated.');
                warning('STL output not found: %s', outSTL);
            end
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
            yLoop = [];
            zLoop =[];
            if isempty(xs) || all(isnan(xs))
                return;
            end

            valid = ~(isnan(xs) | isnan(ys) | isnan(zs));
            idx = find(valid);

            if numel(idx) < 4
                return;
            end

            if mod(numel(idx),2) ~= 0
                idx = idx(1:end-1);
            end

            nSeg = numel(idx)/2;
            p1 =[ys(idx(1:2:end)).', zs(idx(1:2:end)).'];
            p2 =[ys(idx(2:2:end)).', zs(idx(2:2:end)).'];
            allPts = [p1; p2];

            % FIX: Use a strict absolute tolerance so sharp trailing edges aren't welded!
            tol = 1e-5;

            nodePos = zeros(0,2);
            nodeCount = 0;
            mapIdx = zeros(size(allPts,1),1);

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

            edges =[mapIdx(1:nSeg), mapIdx(nSeg+1:end)];
            used = false(nSeg,1);
            loops = {};

            for s = 1:nSeg
                if used(s), continue; end
                used(s) = true;
                cur = edges(s,2);
                path =[edges(s,1) cur];
                startNode = path(1);

                while true
                    cand = find(~used & (edges(:,1) == cur | edges(:,2) == cur),1);
                    if isempty(cand), break; end
                    used(cand) = true;
                    e = edges(cand,:);
                    if e(1) == cur
                        nxt = e(2);
                    else
                        nxt = e(1);
                    end
                    path(end+1) = nxt;
                    cur = nxt;
                    if cur == startNode, break; end
                end

                if numel(path) >= 4 && path(1) == path(end)
                    loops{end+1} = path;
                end
            end

            if isempty(loops)
                return;
            end

            [~, bestIdx] = max(cellfun(@(p) sum(sqrt(sum(diff(nodePos(p,:),1,1).^2,2))), loops));
            pts = nodePos(loops{bestIdx},:);
            yLoop = pts(:,1);
            zLoop = pts(:,2);
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

        function[yLS, zLS, yRS, zRS] = resampleProfilesSynced(yL, zL, yR, zR, tol)
            function [x,y] = clean_path(x,y)
                if numel(x) < 2
                    return;
                end
                d2 =[1; (diff(x).^2 + diff(y).^2)];
                keep = d2 > 1e-8;
                x = x(keep);
                y = y(keep);
                if (x(1)~=x(end) || y(1)~=y(end))
                    x(end+1) = x(1);
                    y(end+1) = y(1);
                end
            end

            d1 = 0; % Anti-markdown bug
            [yL, zL] = clean_path(yL, zL);

            d2 = 0; % Anti-markdown bug
            [yR, zR] = clean_path(yR, zR);

            if numel(yL) < 3 || numel(yR) < 3
                yLS = yL;
                zLS = zL;
                yRS = yR;
                zRS = zR;
                return;
            end

            d3 = 0; % Anti-markdown bug[yL, zL] = HotWireSTEPApp_v6_helpers.reorderLoopByMinY(yL, zL);

            d4 = 0; % Anti-markdown bug[yR, zR] = HotWireSTEPApp_v6_helpers.reorderLoopByMinY(yR, zR);

            areaL = sum((yL(1:end-1).*zL(2:end)) - (yL(2:end).*zL(1:end-1)));
            areaR = sum((yR(1:end-1).*zR(2:end)) - (yR(2:end).*zR(1:end-1)));

            if sign(areaL) ~= sign(areaR)
                yR = flipud(yR);
                zR = flipud(zR);

                d5 = 0; % Anti-markdown bug[yR, zR] = HotWireSTEPApp_v6_helpers.reorderLoopByMinY(yR, zR);
            end

            distL =[0; cumsum(hypot(diff(yL), diff(zL)))];
            distR =[0; cumsum(hypot(diff(yR), diff(zR)))];
            maxLen = max(distL(end), distR(end));

            if maxLen < 1e-6
                yLS = yL;
                zLS = zL;
                yRS = yR;
                zRS = zR;
                return;
            end

            baselineRes = 0.1;
            N = ceil(maxLen / baselineRes);
            N = max(N, 1000);

            s_rawL = distL / distL(end);
            s_rawR = distR / distR(end);

            s_rawL(isnan(s_rawL)) = 0;
            s_rawR(isnan(s_rawR)) = 0;

            % Guard bounds to ensure perfect 0-1 mapping
            s_rawL(1) = 0; s_rawL(end) = 1;
            s_rawR(1) = 0; s_rawR(end) = 1;

            s_fine = linspace(0, 1, N)';

            % Exact grid merging (No rounding!) preserves exact corner vertices
            s_eval = unique([s_fine; s_rawL; s_rawR]);

            d6 = 0; % Anti-markdown bug
            [suL, iuL] = unique(s_rawL, 'stable');

            d7 = 0; % Anti-markdown bug
            [suR, iuR] = unique(s_rawR, 'stable');

            yLf = interp1(suL, yL(iuL), s_eval, 'linear');
            zLf = interp1(suL, zL(iuL), s_eval, 'linear');
            yRf = interp1(suR, yR(iuR), s_eval, 'linear');
            zRf = interp1(suR, zR(iuR), s_eval, 'linear');

            % Independent 2D RDP checks prevent 4D twisting/smoothing
            pts4D = [yLf, zLf, yRf, zRf];
            keepMask = false(size(pts4D, 1), 1);
            keepMask(1) = true;
            keepMask(end) = true;

            stack =[1, size(pts4D, 1)];

            while ~isempty(stack)
                idxEnd = stack(end);
                idxStart = stack(end-1);
                stack(end-1:end) =[];

                if idxEnd - idxStart < 2
                    continue;
                end

                P1_L = pts4D(idxStart, 1:2);
                P2_L = pts4D(idxEnd, 1:2);
                Pts_L = pts4D((idxStart+1):(idxEnd-1), 1:2);

                P1_R = pts4D(idxStart, 3:4);
                P2_R = pts4D(idxEnd, 3:4);
                Pts_R = pts4D((idxStart+1):(idxEnd-1), 3:4);

                % Left deviation
                V_L = P2_L - P1_L;
                lenSq_L = sum(V_L.^2);
                W_L = bsxfun(@minus, Pts_L, P1_L);

                if lenSq_L < 1e-12
                    distsSq_L = sum(W_L.^2, 2);
                else
                    t_L = (W_L * V_L') / lenSq_L;
                    t_L = max(0, min(1, t_L));
                    Closest_L = bsxfun(@plus, P1_L, bsxfun(@times, t_L, V_L));
                    distsSq_L = sum((Pts_L - Closest_L).^2, 2);
                end

                % Right deviation
                V_R = P2_R - P1_R;
                lenSq_R = sum(V_R.^2);
                W_R = bsxfun(@minus, Pts_R, P1_R);

                if lenSq_R < 1e-12
                    distsSq_R = sum(W_R.^2, 2);
                else
                    t_R = (W_R * V_R') / lenSq_R;
                    t_R = max(0, min(1, t_R));
                    Closest_R = bsxfun(@plus, P1_R, bsxfun(@times, t_R, V_R));
                    distsSq_R = sum((Pts_R - Closest_R).^2, 2);
                end

                % We split if EITHER side exceeds tolerance
                max_distsSq = max(distsSq_L, distsSq_R);

                d8 = 0; % Anti-markdown bug
                [maxSq, localIdx] = max(max_distsSq);

                if maxSq > (tol^2)
                    splitIdx = idxStart + localIdx;
                    keepMask(splitIdx) = true;
                    stack =[stack, splitIdx, idxEnd];
                    stack = [stack, idxStart, splitIdx];
                end
            end

            yLS = pts4D(keepMask, 1);
            zLS = pts4D(keepMask, 2);
            yRS = pts4D(keepMask, 3);
            zRS = pts4D(keepMask, 4);

            yLS(end) = yLS(1);
            zLS(end) = zLS(1);
            yRS(end) = yRS(1);
            zRS(end) = zRS(1);
        end

        function [yLS, zLS, yRS, zRS] = syncPointCounts(yL, zL, yR, zR)
            function [x, y] = clean(x, y)
                if numel(x) < 2
                    return;
                end
                dist =[1; sqrt(diff(x).^2 + diff(y).^2)];
                keep = dist > 1e-6;
                x = x(keep);
                y = y(keep);
                if (numel(x) > 2) && (hypot(x(1)-x(end), y(1)-y(end)) > 1e-6)
                    x(end+1) = x(1);
                    y(end+1) = y(1);
                end
            end[yL, zL] = clean(yL, zL);
            [yR, zR] = clean(yR, zR);

            function s = getArcParam(y, z)
                if numel(y) < 2
                    s=zeros(size(y));
                    return;
                end
                d =[0; cumsum(hypot(diff(y), diff(z)))];
                maxD = d(end);
                if maxD < 1e-6
                    maxD = 1;
                end
                s = d / maxD;
            end

            sL = getArcParam(yL, zL);
            sR = getArcParam(yR, zR);

            if isempty(sL) || isempty(sR)
                yLS = yL;
                zLS = zL;
                yRS = yR;
                zRS = zR;
                return;
            end

            if numel(sL) == numel(sR) && max(abs(sL - sR)) < 1e-3
                yLS = yL;
                zLS = zL;
                yRS = yR;
                zRS = zR;
                return;
            end

            sL(1) = 0; sL(end) = 1;
            sR(1) = 0; sR(end) = 1;

            % Exact grid merging (No rounding!)
            s_target = unique([sL; sR]);

            [sL_u, idxL] = unique(sL, 'stable');
            [sR_u, idxR] = unique(sR, 'stable');

            yLS = interp1(sL_u, yL(idxL), s_target, 'linear');
            zLS = interp1(sL_u, zL(idxL), s_target, 'linear');
            yRS = interp1(sR_u, yR(idxR), s_target, 'linear');
            zRS = interp1(sR_u, zR(idxR), s_target, 'linear');
        end

        function [towerL, towerR] = projectToTowers(yL, zL, xL, yR, zR, xR, spanX)
            towerL.y = yL + (0 - xL) .* (yR - yL) ./ (xR - xL);
            towerL.z = zL + (0 - xL) .* (zR - zL) ./ (xR - xL);
            towerR.y = yL + (spanX - xL) .* (yR - yL) ./ (xR - xL);
            towerR.z = zL + (spanX - xL) .* (zR - zL) ./ (xR - xL);
        end

        function [yo, zo] = offsetProfileLoop(yIn, zIn, kerf, tol)
            yo = yIn;
            zo = zIn;
            if nargin < 4
                tol = 0;
            end

            if ~isfinite(kerf) || kerf == 0
                return;
            end

            y = yIn(:);
            z = zIn(:);
            valid = isfinite(y) & isfinite(z);
            y = y(valid);
            z = z(valid);

            if numel(y) < 3
                return;
            end

            offsetDist = kerf / 2.0;

            inputPoints = round([y, z], 8);

            [~, uniqueIdx] = unique(inputPoints, 'rows', 'stable');

            y = y(uniqueIdx);
            z = z(uniqueIdx);

            originalState = warning('off', 'all');
            cleanupObj = onCleanup(@() warning(originalState));

            try
                pgon = polyshape(y, z, 'Simplify', true);
                if pgon.NumRegions == 0
                    return;
                end

                pgonOut = polybuffer(pgon, offsetDist);
                if pgonOut.NumRegions == 0
                    return;
                end

                if pgonOut.NumRegions > 1
                    areaList = area(pgonOut.regions);

                    [~, maxIdx] = max(areaList);

                    pgonOut = pgonOut.regions(maxIdx);
                end
                [yo, zo] = boundary(pgonOut);

                nanIdx = find(isnan(yo), 1);
                if ~isempty(nanIdx)
                    yo = yo(1:nanIdx-1);
                    zo = zo(1:nanIdx-1);
                end

            catch
                return;
            end

            if tol > 0 && numel(yo) > 5
                pts =[yo, zo];
                N = size(pts, 1);
                keepMask = false(N, 1);
                keepMask(1) = true;
                keepMask(end) = true;

                stack = [1, N];

                while ~isempty(stack)
                    idxEnd = stack(end);
                    idxStart = stack(end-1);
                    stack(end-1:end) =[];

                    if idxEnd - idxStart < 2
                        continue;
                    end

                    P1 = pts(idxStart, :);
                    P2 = pts(idxEnd, :);
                    rng = (idxStart+1):(idxEnd-1);
                    Pts = pts(rng, :);

                    V = P2 - P1;
                    lenSq = sum(V.^2);
                    W = bsxfun(@minus, Pts, P1);

                    if lenSq < 1e-12
                        distsSq = sum(W.^2, 2);
                    else
                        t = (W * V') / lenSq;
                        t = max(0, min(1, t));
                        Closest = bsxfun(@plus, P1, bsxfun(@times, t, V));
                        distsSq = sum((Pts - Closest).^2, 2);
                    end
                    [maxSq, localIdx] = max(distsSq);

                    if maxSq > (tol^2)
                        splitIdx = rng(localIdx);
                        keepMask(splitIdx) = true;
                        stack =[stack, splitIdx, idxEnd];
                        stack = [stack, idxStart, splitIdx];
                    end
                end

                yo = pts(keepMask, 1);
                zo = pts(keepMask, 2);
            end

            [yo, zo] = HotWireSTEPApp_v6_helpers.reorderLoopByMinY(yo, zo);

            if isrow(yIn)
                yo = yo.';
                zo = zo.';
            end
        end

        function [yOut, zOut] = reorderLoopByMinY(y, z)
            % 1. Force to Column Vectors
            y = y(:); z = z(:);

            % 2. Remove tailing point duplicate
            if numel(y) > 1 && abs(y(1)-y(end)) < 1e-6 && abs(z(1)-z(end)) < 1e-6
                y(end) = []; z(end) =[];
            end

            if numel(y) < 3
                yOut = y; zOut = z; return;
            end

            % 3. Find Bounding Box Center in Z and Front Face (min Y)
            % FIX: Use true bounding box center, NOT point average!
            cz = (min(z) + max(z)) / 2.0;
            minY = min(y);

            % 4. Check for intersections with Z = cz along the front face
            % This detects if we need to split a long vertical edge
            N = numel(y);
            insert_idx = -1;
            best_yi = inf;

            for i = 1:N
                i_next = mod(i, N) + 1;
                z1 = z(i); z2 = z(i_next);
                y1 = y(i); y2 = y(i_next);

                % Does segment cross centroid Z?
                if (z1 - cz) * (z2 - cz) <= 0 && z1 ~= z2
                    t = (cz - z1) / (z2 - z1);
                    yi = y1 + t * (y2 - y1);

                    % Is it on the front face? (within a 0.01mm tolerance)
                    if abs(yi - minY) < 1e-2
                        insert_idx = i;
                        best_yi = yi;
                        break; % Found the split point
                    end
                end
            end

            % 5. Reorder or Inject
            if insert_idx > 0
                % INJECT: Split the front face and insert a point exactly at the Z-centroid!
                y_new =[y(1:insert_idx); best_yi; y(insert_idx+1:end)];
                z_new =[z(1:insert_idx); cz;      z(insert_idx+1:end)];

                startIdx = insert_idx + 1;
                yOut =[y_new(startIdx:end); y_new(1:startIdx-1)];
                zOut =[z_new(startIdx:end); z_new(1:startIdx-1)];
            else
                % FALLBACK: Find existing points on the front face
                front_indices = find(abs(y - minY) < 1e-3);

                if isempty(front_indices)
                    [~, startIdx] = min(y);
                else
                    % Pick the one closest to Z-centroid
                    [~, local_idx] = min(abs(z(front_indices) - cz));
                    startIdx = front_indices(local_idx);
                end

                yOut =[y(startIdx:end); y(1:startIdx-1)];
                zOut = [z(startIdx:end); z(1:startIdx-1)];
            end

            % 6. Force exact closure
            yOut(end+1) = yOut(1);
            zOut(end+1) = zOut(1);
        end

        function billet = computeDefaultBilletFromMesh(V, xPlaneA, xPlaneB, bufferY, bufferZ)
            % Calculates billet size with configurable buffers.

            if nargin < 4, bufferY = 5.0; end
            if nargin < 5, bufferZ = 5.0; end

            mins = min(V,[],1); maxs = max(V,[],1);

            % X Logic
            billet.Xmin = min(xPlaneA, xPlaneB) - 0.001;
            billet.Xmax = max(xPlaneA, xPlaneB) + 0.001;

            % Y Logic
            billet.Ymin = mins(2) - bufferY;
            billet.Ymax = maxs(2) + bufferY;

            % Z Logic (Stock Selection)
            modelH = maxs(3) - mins(3);
            requiredH = modelH + (bufferZ * 2);

            stocks = HotWireSTEPApp_v6_helpers.BilletStockHeights;
            stockH = requiredH;

            for i = 1:numel(stocks)
                if requiredH <= stocks(i)
                    stockH = stocks(i);
                    break;
                end
            end

            billet.Zmin = mins(3) - bufferZ;
            billet.Zmax = billet.Zmin + stockH;
        end

    end
end