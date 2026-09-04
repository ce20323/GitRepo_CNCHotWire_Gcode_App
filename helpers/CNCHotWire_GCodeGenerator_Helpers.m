classdef CNCHotWire_GCodeGenerator_Helpers
    % ===========================================================
    % HOTWIRE CNC G-CODE GENERATOR - MATH & GEOMETRY HELPERS
    %
    % Purpose: A static utility class containing the heavy mathematical
    %          and geometric algorithms required by the main application.
    % WHY: Keeps the main UI class clean and separates the "View/Controller"
    %      logic from the "Model/Math" logic.
    % ===========================================================

    properties (Constant)

        % --- Profile Sampling ---
        ProfileResampleMinPoints = 50;
        ProfileResampleMaxPoints = 20000;

        % --- FreeCAD Meshing ---
        FreeCADLinearDeflection  = 0.1;
        FreeCADAngularDeflection = 0.1;

        % --- Billet Default Rules ---
        BilletXBuffer   = 0.001;  % [mm] Tiny offset to prevent coplanar math errors
        BilletYBuffer   = 5.0;    % [mm] Default safe distance from front/back faces
        BilletZBuffer   = 10.0;   % [mm] Default safe distance from top/bottom faces
        BilletZMinClear = 5.0;    % [mm] Minimum clearance from the bed
        BilletStockHeights =[50 75 100]; % [mm] Standard physical foam block thicknesses

    end

    methods(Static)

        %% ===============================================================
        %% --- GROUP 1: FILE I/O & MESHING ---
        %% ===============================================================

        function [ V, F ] = importSTEP_FreeCAD(cadPath, freeCADExe)
            % Purpose: Converts a STEP file into a triangulated 3D mesh using FreeCAD.
            % WHY: MATLAB does not natively parse STEP geometry into meshes without expensive toolboxes.
            % HOW: Dynamically writes a Python script, executes FreeCAD in headless mode via the
            %      command line to generate a temporary STL, and then reads that STL into MATLAB.

            V = [];
            F =[];

            cadPath = char(cadPath);
            freeCADExe = char(freeCADExe);

            [ ~, modelName, ext ] = fileparts(cadPath);

            disp(['[HotWire CAM] Importing ', modelName, ext, ' via FreeCAD...']);

            if ~isfile(cadPath)
                warning('STEP file not found: %s', cadPath);
                return;
            end

            if nargin < 2 || ~isfile(freeCADExe)
                warning('FreeCAD executable not found: %s', freeCADExe);
                return;
            end

            %% --- 1. PREPARE TEMPORARY FILES ---
            tmpID  = char(java.util.UUID.randomUUID());
            outSTL = fullfile(tempdir, ['fc_out_' tmpID '.stl']);
            pyFile = fullfile(tempdir, ['fc_' tmpID '.py']);

            % Convert backslashes to forward slashes for Python string safety
            safeCadPath = strrep(cadPath, '\', '/');
            safeOutSTL  = strrep(outSTL, '\', '/');

            %% --- 2. WRITE PYTHON SCRIPT ---
            fid = fopen(pyFile,'w');
            fprintf(fid,"import sys\n");
            fprintf(fid,"import FreeCAD, Part, Mesh, MeshPart\n");
            fprintf(fid,"doc = FreeCAD.newDocument()\n");
            fprintf(fid,"shape = Part.Shape()\n");
            fprintf(fid,"shape.read(r'%s')\n", safeCadPath);

            % Apply meshing deflections (lower = higher resolution mesh)
            fprintf(fid, "mesh = MeshPart.meshFromShape(Shape=shape,LinearDeflection=%g,AngularDeflection=%g)\n", ...
                CNCHotWire_GCodeGenerator_Helpers.FreeCADLinearDeflection, CNCHotWire_GCodeGenerator_Helpers.FreeCADAngularDeflection);

            fprintf(fid,"mesh.write(r'%s')\n", safeOutSTL);
            fprintf(fid,"FreeCAD.closeDocument(doc.Name)\n");
            fclose(fid);

            %% --- 3. EXECUTE FREECAD ---
            % The Bulletproof Windows CMD workaround: Change directory to the FreeCAD bin folder first
            [ fcDir, fcName, fcExt ] = fileparts(freeCADExe);

            fcExeName = [fcName, fcExt];
            cmdStr = sprintf('cd /d "%s" & %s "%s"', fcDir, fcExeName, pyFile);

            [ status, cmdout ] = system(cmdStr);

            if status ~= 0
                disp('[HotWire CAM ERROR] FreeCAD Execution Failed.');
                disp(['Attempted Command: ', cmdStr]);
                disp('FreeCAD Console Output:');
                disp(cmdout);
                warning('FreeCAD conversion failed. See command window for details.');
                return;
            end

            %% --- 4. READ GENERATED STL ---
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

        %% ===============================================================
        %% --- GROUP 2: MESH SLICING & LOOP EXTRACTION ---
        %% ===============================================================

        function[ xs, ys, zs ] = sliceMeshAtX(V, F, x0)
            % Purpose: Intersects a 3D triangle mesh with a 2D plane at a specific X coordinate.
            % WHY: To extract the raw 2D cross-section (profile) of the model at the Left/Right cutting planes.
            % HOW: Iterates through every face. If the face spans across the X-plane, it calculates
            %      the exact 3D intersection points of the triangle's edges.

            xs = []; ys = []; zs =[];

            for k = 1:size(F,1)
                tri = F(k,:);
                A = V(tri(1),:);
                B = V(tri(2),:);
                C = V(tri(3),:);

                X =[A(1), B(1), C(1)];

                % Fast rejection: If all 3 vertices are on the same side of the plane, skip it.
                if all(X < x0) || all(X > x0), continue; end

                pts = zeros(2,3);
                count = 0;
                edges =[A; B; C; A]; % Close the loop for easy iteration

                % Check each of the 3 edges of the triangle
                for i = 1:3
                    P1 = edges(i,:);
                    P2 = edges(i+1,:);

                    % If the edge crosses the plane...
                    if (P1(1)-x0)*(P2(1)-x0) <= 0 && P1(1) ~= P2(1)
                        % Calculate interpolation factor 't'
                        t = (x0 - P1(1)) / (P2(1)-P1(1));

                        if t >= 0 && t <= 1
                            count = count + 1;
                            pts(count,:) = P1 + t*(P2-P1);
                            if count == 2, break; end % A plane can only intersect a triangle at 2 points max
                        end
                    end
                end

                % If we found a valid intersection line segment across this face, store it.
                % We append NaN to break the line segments for plotting purposes later.
                if count == 2
                    xs = [xs, pts(1,1), pts(2,1), NaN];
                    ys = [ys, pts(1,2), pts(2,2), NaN];
                    zs =[zs, pts(1,3), pts(2,3), NaN];
                end
            end
        end

        function [ yLoop, zLoop ] = buildMainProfileLoop(xs, ys, zs)
            % Purpose: Converts a "soup" of disconnected line segments into a continuous, ordered polygon loop.
            % WHY: The slicer returns random, unordered segments. CNC machines need a continuous path.
            % HOW: Welds coincident vertices together to form a graph, then walks the edges to find
            %      closed loops. If multiple loops exist (e.g., a hollow tube), it returns the longest one.

            yLoop = [];
            zLoop =[];

            if isempty(xs) || all(isnan(xs))
                return;
            end

            % 1. Clean out the NaNs used for plotting separation
            valid = ~(isnan(xs) | isnan(ys) | isnan(zs));
            idx = find(valid);

            if numel(idx) < 4
                return;
            end

            if mod(numel(idx),2) ~= 0
                idx = idx(1:end-1);
            end

            % 2. Extract start (p1) and end (p2) points of every segment
            nSeg = numel(idx)/2;
            p1 = [ys(idx(1:2:end)).', zs(idx(1:2:end)).'];
            p2 =[ys(idx(2:2:end)).', zs(idx(2:2:end)).'];
            allPts = [p1; p2];

            % 3. Weld coincident vertices
            % Use a strict absolute tolerance so sharp trailing edges aren't accidentally welded!
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

            % 4. Build Edge Graph
            edges =[mapIdx(1:nSeg), mapIdx(nSeg+1:end)];
            used = false(nSeg,1);
            loops = {};

            % 5. Walk the graph to find closed loops
            for s = 1:nSeg
                if used(s), continue; end
                used(s) = true;
                cur = edges(s,2);
                path = [edges(s,1) cur];
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

                % Only keep valid, closed loops
                if numel(path) >= 4 && path(1) == path(end)
                    loops{end+1} = path;
                end
            end

            if isempty(loops)
                return;
            end

            % 6. Select the primary loop
            % If there are multiple loops (e.g., internal holes), we assume the longest
            % perimeter is the outer boundary we want to cut.
            [ ~, bestIdx ] = max(cellfun(@(p) sum(sqrt(sum(diff(nodePos(p,:),1,1).^2,2))), loops));

            pts = nodePos(loops{bestIdx},:);
            yLoop = pts(:,1);
            zLoop = pts(:,2);
        end

        %% ===============================================================
        %% --- GROUP 3: PROFILE RESAMPLING & SYNCING ---
        %% ===============================================================

        function [ yR, zR ] = resampleProfileByTolerance(y, z, tol)
            % Purpose: Reduces the number of points in a single profile while maintaining shape.
            % WHY: Raw mesh slices can have thousands of points, which chokes the CNC controller.
            % HOW: Calculates cumulative arc length, interpolates to a fine grid, and applies tolerance.

            y = y(:); z = z(:);
            if numel(y) < 2, yR=y; zR=z; return; end

            yExt =[ y; y(1) ]; zExt =[ z; z(1) ];

            s =[ 0; cumsum(hypot(diff(yExt), diff(zExt))) ];

            % Ensure unique samples to avoid interp1 errors
            [ sU, idxU ] = unique(s, 'stable');
            if numel(sU) < 2, yR=y; zR=z; return; end

            totalLen = sU(end);
            N = min(max(round(totalLen/tol), 50), 20000);
            yR = interp1(sU, yExt(idxU), linspace(0, totalLen, N).', 'linear');
            zR = interp1(sU, zExt(idxU), linspace(0, totalLen, N).', 'linear');
        end

        function [ anchorL, anchorR, info ] = findFeatureAnchorPairs( ...
                yL, zL, yR, zR, minCornerAngleDeg, detectionMode)
            % Purpose: Finds corresponding anchors using either one notch
            % pattern or all detected sharp corners.
            %
            % WHY: Notch matching permits unrelated outer corners, whereas
            % Matched Corners requires the complete corner sequences to agree.
            % Both approaches must preserve cyclic traversal correspondence.
            %
            % HOW: Share corner detection and clustering, then apply the
            % selected matching rule. Existing callers retain notch behaviour
            % unless they explicitly request Matched Corners.

            if nargin < 5
                minCornerAngleDeg = 25.0;
            end

            if nargin < 6
                detectionMode = "Notch Anchors";
            end

            detectionMode = string(detectionMode);

            anchorL = zeros(0, 2);
            anchorR = zeros(0, 2);

            info = struct( ...
                'Valid', false, ...
                'Message', "", ...
                'AnchorCount', 0, ...
                'CandidateCountL', 0, ...
                'CandidateCountR', 0, ...
                'PatternCountL', 0, ...
                'PatternCountR', 0);

            [ yLWork, zLWork ] = cleanOpenLoop(yL, zL);
            [ yRWork, zRWork ] = cleanOpenLoop(yR, zR);

            if numel(yLWork) < 4 || numel(yRWork) < 4
                info.Message = "Insufficient profile points for feature detection.";
                return;
            end

            areaL = signedLoopArea(yLWork, zLWork);
            areaR = signedLoopArea(yRWork, zRWork);

            if abs(areaL) < 1e-12 || abs(areaR) < 1e-12
                info.Message = "A profile has insufficient enclosed area.";
                return;
            end

            % Put both profiles into the same traversal direction before matching
            % their ordered corner sequences.
            if sign(areaL) ~= sign(areaR)
                yRWork = flipud(yRWork);
                zRWork = flipud(zRWork);
            end

            % Retain the complete candidate sequences as well as the notch
            % result so both modes use identical corner-detection rules.
            [ idxL, candidateCountL, patternCountL, cornersL, turnsL ] = ...
                findSingleNotch(yLWork, zLWork, minCornerAngleDeg);

            [ idxR, candidateCountR, patternCountR, cornersR, turnsR ] = ...
                findSingleNotch(yRWork, zRWork, minCornerAngleDeg);

            info.CandidateCountL = candidateCountL;
            info.CandidateCountR = candidateCountR;
            info.PatternCountL = patternCountL;
            info.PatternCountR = patternCountR;

            if detectionMode == "Matched Corners"
                % Purpose: Pair every detected corner without relying on the
                % independently selected starting vertex of either profile.
                %
                % WHY: Equal counts alone do not establish correspondence.
                % Repeated corner signatures may permit several equally
                % plausible cyclic pairings.
                %
                % HOW: Compare signed turning angles for every cyclic shift
                % of the right sequence. Reject incompatible sequences and
                % require a clear margin over the next compatible result.

                maxPairDifferenceDeg = 20.0;
                minScoreSeparationDeg = 5.0;

                if candidateCountL < 3 || ...
                        candidateCountL ~= candidateCountR

                    info.Message = string(sprintf( ...
                        ['Matched Corners requires equal corner counts ' ...
                        'with at least three per profile. Found L/R: %d / %d.'], ...
                        candidateCountL, candidateCountR));
                    return;
                end

                cornerCount = candidateCountL;
                turnsLDeg = turnsL(:) * 180.0 / pi;
                turnsRDeg = turnsR(:) * 180.0 / pi;
                matchScores = inf(cornerCount, 1);

                for shiftNumber = 0:cornerCount-1
                    candidateTurnsR = circshift(turnsRDeg, -shiftNumber);

                    % Convex corners must pair with convex corners, and
                    % concave corners with concave corners. Small overall
                    % scores must not hide one incompatible anchor.
                    if any(sign(turnsLDeg) ~= sign(candidateTurnsR))
                        continue;
                    end

                    angleDifference = turnsLDeg - candidateTurnsR;

                    if any(abs(angleDifference) > maxPairDifferenceDeg)
                        continue;
                    end

                    matchScores(shiftNumber + 1) = ...
                        sqrt(mean(angleDifference.^2));
                end

                [ sortedScores, rankedMatches ] = sort(matchScores);

                if ~isfinite(sortedScores(1))
                    info.Message = ...
                        "The detected corner sequences are not compatible.";
                    return;
                end

                % Reject repeated or nearly repeated signatures rather than
                % using array order or minimum-Y position as a tie-breaker.
                if isfinite(sortedScores(2)) && ...
                        sortedScores(2) - sortedScores(1) < ...
                        minScoreSeparationDeg

                    info.Message = ...
                        "The detected corners have an ambiguous cyclic match.";
                    return;
                end

                bestShift = rankedMatches(1) - 1;
                pairedCornersR = circshift(cornersR(:), -bestShift);

                anchorL = [ yLWork(cornersL), zLWork(cornersL) ];
                anchorR = [ ...
                    yRWork(pairedCornersR), zRWork(pairedCornersR) ];

                info.Valid = true;
                info.AnchorCount = cornerCount;
                info.MatchRmsDeg = sortedScores(1);
                info.NextMatchRmsDeg = sortedScores(2);
                info.Message = string(sprintf( ...
                    'Matched %d ordered corner pairs.', cornerCount));
                return;
            end

            % Keep the existing notch recognition as the default route.
            % Reject unknown modes rather than silently choosing a strategy.
            if detectionMode ~= "Notch Anchors"
                info.Message = "Unknown anchor detection mode.";
                return;
            end

            if patternCountL ~= 1 || patternCountR ~= 1
                info.Message = string(sprintf( ...
                    ['Notch Anchors requires exactly one unambiguous notch '...
                    'pattern on each profile. Found L/R: %d / %d.'], ...
                    patternCountL, patternCountR));
                return;
            end

            anchorL = [ yLWork(idxL), zLWork(idxL) ];
            anchorR = [ yRWork(idxR), zRWork(idxR) ];

            if size(anchorL, 1) ~= 4 || size(anchorR, 1) ~= 4
                anchorL = zeros(0, 2);
                anchorR = zeros(0, 2);
                info.Message = "The detected feature did not contain four anchors.";
                return;
            end

            info.Valid = true;
            info.AnchorCount = 4;
            info.Message = "Matched four ordered notch-corner anchor pairs.";

            function [ yo, zo ] = cleanOpenLoop(yi, zi)
                yi = yi(:);
                zi = zi(:);

                valid = isfinite(yi) & isfinite(zi);
                yi = yi(valid);
                zi = zi(valid);

                if numel(yi) < 2
                    yo = yi;
                    zo = zi;
                    return;
                end

                % Remove consecutive duplicate points.
                distanceFromPrevious = [ inf; hypot(diff(yi), diff(zi)) ];
                keep = distanceFromPrevious > 1e-8;

                yo = yi(keep);
                zo = zi(keep);

                % Work internally with an open representation of the closed loop.
                if numel(yo) > 1 && ...
                        hypot(yo(1) - yo(end), zo(1) - zo(end)) <= 1e-8
                    yo(end) = [];
                    zo(end) = [];
                end
            end

            function areaValue = signedLoopArea(y, z)
                nextIdx = [ 2:numel(y), 1 ];
                areaValue = sum( ...
                    y .* z(nextIdx) - ...
                    y(nextIdx) .* z);
            end

            function [ anchorIdx, candidateCount, patternCount, ...
                    cornerIdx, cornerTurn ] = ...
                    findSingleNotch(y, z, angleThresholdDeg)

                anchorIdx = zeros(0, 1);
                candidateCount = 0;
                patternCount = 0;
                % Initialise the additional outputs for early-return cases,
                % including profiles with no qualifying sharp corners.
                cornerIdx = zeros(0, 1);
                cornerTurn = zeros(0, 1);

                n = numel(y);
                if n < 4
                    return;
                end

                previousIdx = [ n, 1:(n-1) ];
                nextIdx = [ 2:n, 1 ];

                incomingY = y - y(previousIdx);
                incomingZ = z - z(previousIdx);
                outgoingY = y(nextIdx) - y;
                outgoingZ = z(nextIdx) - z;

                incomingLength = hypot(incomingY, incomingZ);
                outgoingLength = hypot(outgoingY, outgoingZ);

                usable = incomingLength > 1e-10 & ...
                    outgoingLength > 1e-10;

                crossValue = incomingY .* outgoingZ - ...
                    incomingZ .* outgoingY;

                dotValue = incomingY .* outgoingY + ...
                    incomingZ .* outgoingZ;

                turnAngle = nan(n, 1);
                turnAngle(usable) = atan2( ...
                    crossValue(usable), dotValue(usable));

                % Normalise the sign so convex corners are positive and concave
                % corners are negative regardless of traversal direction.
                loopArea = signedLoopArea(y, z);
                turnAngle = turnAngle * sign(loopArea);

                thresholdRadians = angleThresholdDeg * pi / 180.0;

                cornerIdx = find( ...
                    isfinite(turnAngle) & ...
                    abs(turnAngle) >= thresholdRadians);

                if isempty(cornerIdx)
                    return;
                end

                perimeter = sum(hypot( ...
                    diff([ y; y(1) ]), ...
                    diff([ z; z(1) ])));

                % Collapse multiple nearby detections belonging to the same
                % physical corner.
                mergeDistance = max(1e-8, 0.002 * perimeter);

                [ cornerIdx, cornerTurn ] = mergeCornerClusters( ...
                    cornerIdx, turnAngle, y, z, mergeDistance);

                candidateCount = numel(cornerIdx);

                if candidateCount < 4
                    return;
                end

                matches = zeros(0, 4);

                for k = 1:candidateCount
                    secondCorner = mod(k, candidateCount) + 1;
                    previousCorner = mod(k - 2, candidateCount) + 1;
                    followingCorner = mod(k + 1, candidateCount) + 1;

                    % Recognise the ordered notch signature:
                    % mouth -> internal -> internal -> mouth.
                    if cornerTurn(previousCorner) > 0 && ...
                            cornerTurn(k) < 0 && ...
                            cornerTurn(secondCorner) < 0 && ...
                            cornerTurn(followingCorner) > 0

                        matches(end+1, :) = [ ... %#ok<AGROW>
                            cornerIdx(previousCorner), ...
                            cornerIdx(k), ...
                            cornerIdx(secondCorner), ...
                            cornerIdx(followingCorner) ];
                    end
                end

                patternCount = size(matches, 1);

                if patternCount == 1
                    anchorIdx = matches(1, :).';
                end
            end

            function [ idxOut, turnOut ] = mergeCornerClusters( ...
                    idxIn, turnAll, y, z, mergeDistance)

                idxIn = idxIn(:);

                if numel(idxIn) <= 1
                    idxOut = idxIn;
                    turnOut = turnAll(idxOut);
                    return;
                end

                groups = cell(1, 1);
                groups{1} = idxIn(1);

                for j = 2:numel(idxIn)
                    currentIdx = idxIn(j);
                    previousCandidateIdx = groups{end}(end);

                    sameTurnSense = ...
                        turnAll(currentIdx) * turnAll(previousCandidateIdx) > 0;

                    closeTogether = hypot( ...
                        y(currentIdx) - y(previousCandidateIdx), ...
                        z(currentIdx) - z(previousCandidateIdx)) <= mergeDistance;

                    if sameTurnSense && closeTogether
                        groups{end}(end+1) = currentIdx;
                    else
                        groups{end+1} = currentIdx; %#ok<AGROW>
                    end
                end

                % Merge a cluster that crosses the stored loop start/end.
                if numel(groups) > 1
                    firstIdx = groups{1}(1);
                    lastIdx = groups{end}(end);

                    sameTurnSense = turnAll(firstIdx) * turnAll(lastIdx) > 0;

                    closeTogether = hypot( ...
                        y(firstIdx) - y(lastIdx), ...
                        z(firstIdx) - z(lastIdx)) <= mergeDistance;

                    if sameTurnSense && closeTogether
                        groups{1} = [ groups{end}, groups{1} ];
                        groups(end) = [];
                    end
                end

                idxOut = zeros(numel(groups), 1);

                for j = 1:numel(groups)
                    members = groups{j};
                    [ ~, strongest ] = max(abs(turnAll(members)));
                    idxOut(j) = members(strongest);
                end

                idxOut = sort(idxOut);
                turnOut = turnAll(idxOut);
            end
        end

        function [ yLS, zLS, yRS, zRS, info ] = ...
                resampleProfilesFeatureAnchored( ...
                yL, zL, yR, zR, tol, detectionMode)
            % Purpose: Synchronises profiles between corresponding anchors
            % selected by either Notch Anchors or Matched Corners.
            %
            % WHY: Both modes require the same cyclic section resampling.
            % Only the rule used to identify corresponding anchors differs.
            %
            % HOW: Pass the selected mode to the detector, then preserve its
            % paired anchors while resampling each intervening section.
            % Existing five-argument callers retain notch behaviour.

            if nargin < 6
                detectionMode = "Notch Anchors";
            end

            yLS = [];
            zLS = [];
            yRS = [];
            zRS = [];

            info = struct( ...
                'Valid', false, ...
                'Message', "", ...
                'AnchorCount', 0, ...
                'AnchorIndices', zeros(0, 1), ...
                'AnchorPointsL', zeros(0, 2), ...
                'AnchorPointsR', zeros(0, 2), ...
                'SectionCount', 0, ...
                'OutputPointCount', 0);

            if nargin < 5 || ~isscalar(tol) || ~isfinite(tol) || tol <= 0
                info.Message = "A positive finite profile tolerance is required.";
                return;
            end

            if numel(yL) ~= numel(zL) || numel(yR) ~= numel(zR)
                info.Message = "Each profile must contain matching Y and Z arrays.";
                return;
            end

            [ yL, zL ] = cleanClosedLoop(yL, zL);
            [ yR, zR ] = cleanClosedLoop(yR, zR);

            if numel(yL) < 4 || numel(yR) < 4
                info.Message = "Insufficient profile points for anchored resampling.";
                return;
            end

            % Use the same automatic start alignment as the existing method.
            [ yL, zL ] = ...
                CNCHotWire_GCodeGenerator_Helpers.reorderLoopByMinY(yL, zL);

            [ yR, zR ] = ...
                CNCHotWire_GCodeGenerator_Helpers.reorderLoopByMinY(yR, zR);

            areaL = signedArea(yL, zL);
            areaR = signedArea(yR, zR);

            if abs(areaL) < 1e-12 || abs(areaR) < 1e-12
                info.Message = "A profile has insufficient enclosed area.";
                return;
            end

            % Match traversal directions before locating and pairing anchors.
            if sign(areaL) ~= sign(areaR)
                yR = flipud(yR);
                zR = flipud(zR);

                [ yR, zR ] = ...
                    CNCHotWire_GCodeGenerator_Helpers.reorderLoopByMinY(yR, zR);
            end

            % Use the existing 25-degree corner threshold for both modes.
            % The detector determines correspondence; the resampler must
            % not replace it with independent minimum-Y pairing.
            [ anchorL, anchorR, detectedInfo ] = ...
                CNCHotWire_GCodeGenerator_Helpers.findFeatureAnchorPairs( ...
                yL, zL, yR, zR, 25.0, detectionMode);

            info = detectedInfo;
            info.AnchorIndices = zeros(0, 1);
            info.AnchorPointsL = zeros(0, 2);
            info.AnchorPointsR = zeros(0, 2);
            info.SectionCount = 0;
            info.OutputPointCount = 0;

            if ~detectedInfo.Valid
                return;
            end

            % Do not report success until all resampling checks have passed.
            info.Valid = false;

            [ anchorIdxL, anchorsLocatedL ] = ...
                locateAnchors(yL, zL, anchorL);

            [ anchorIdxR, anchorsLocatedR ] = ...
                locateAnchors(yR, zR, anchorR);

            if ~anchorsLocatedL || ~anchorsLocatedR
                info.Message = ...
                    "A detected feature anchor could not be located on its profile.";
                return;
            end

            % Purpose: Establish a common cyclic origin at a matched anchor.
            %
            % WHY: Independently chosen minimum-Y origins can place matching
            % anchors on opposite sides of the array boundary. For example,
            % right indices [4; 1; 2; 3] describe a valid cyclic sequence,
            % although they are not numerically increasing.
            %
            % HOW: Order the pairs around the left loop, then rotate each
            % profile to the first matched pair. Remap the anchor indices
            % relative to those origins and check their traversal order.
            % This establishes correspondence only; the operator can later
            % select a different cut start by rotating both outputs together.

            [ anchorIdxL, pathOrder ] = sort(anchorIdxL);
            anchorIdxR = anchorIdxR(pathOrder);
            anchorL = anchorL(pathOrder, :);
            anchorR = anchorR(pathOrder, :);

            % The cleaned profiles contain an explicit closing duplicate.
            % Exclude that duplicate from cyclic indexing and rotation.
            openCountL = numel(yL) - 1;
            openCountR = numel(yR) - 1;

            firstAnchorL = anchorIdxL(1);
            firstAnchorR = anchorIdxR(1);

            relativeIdxL = ...
                mod(anchorIdxL - firstAnchorL, openCountL) + 1;
            relativeIdxR = ...
                mod(anchorIdxR - firstAnchorR, openCountR) + 1;

            % A single boundary wrap is valid. Repeated anchors or a truly
            % incompatible paired order remain invalid after rebasing.
            % Never sort the right indices independently: that would change
            % which physical features are paired.
            if any(diff(relativeIdxL) <= 0) || ...
                    any(diff(relativeIdxR) <= 0)

                info.Message = ...
                    "The feature anchors do not have the same traversal order.";
                return;
            end

            rotationL = [ firstAnchorL:openCountL, 1:firstAnchorL-1 ];
            rotationR = [ firstAnchorR:openCountR, 1:firstAnchorR-1 ];

            yL = yL(rotationL);
            zL = zL(rotationL);
            yR = yR(rotationR);
            zR = zR(rotationR);

            % Preserve column-vector outputs and restore exactly one closing
            % point after rotating the unique vertices.
            yL = yL(:);
            zL = zL(:);
            yR = yR(:);
            zR = zR(:);

            yL(end+1, 1) = yL(1);
            zL(end+1, 1) = zL(1);
            yR(end+1, 1) = yR(1);
            zR(end+1, 1) = zR(1);

            anchorIdxL = relativeIdxL;
            anchorIdxR = relativeIdxR;

            % Each section runs from one matched anchor to the next.
            % The final section returns to the first anchor through closure.
            % Anchor 1 already occupies row 1, so do not prepend another
            % breakpoint at row 1 and create a zero-length section.
            breakpointsL = [ anchorIdxL; numel(yL) ];
            breakpointsR = [ anchorIdxR; numel(yR) ];

            allPoints = zeros(0, 4);
            sectionCount = numel(breakpointsL) - 1;

            for sectionIdx = 1:sectionCount
                firstL = breakpointsL(sectionIdx);
                lastL = breakpointsL(sectionIdx + 1);

                firstR = breakpointsR(sectionIdx);
                lastR = breakpointsR(sectionIdx + 1);

                sectionL = [ ...
                    yL(firstL:lastL), ...
                    zL(firstL:lastL) ];

                sectionR = [ ...
                    yR(firstR:lastR), ...
                    zR(firstR:lastR) ];

                [ sectionPoints, sectionValid ] = ...
                    synchroniseOpenSection(sectionL, sectionR, tol);

                if ~sectionValid
                    info.Message = string(sprintf( ...
                        'Feature-anchor section %d could not be resampled.', ...
                        sectionIdx));
                    return;
                end

                % Adjacent sections share one anchor. Retain it only once so the
                % wire does not visit the same point twice.
                if sectionIdx > 1
                    sectionPoints(1, :) = [];
                end

                allPoints = [ allPoints; sectionPoints ]; %#ok<AGROW>
            end

            if size(allPoints, 1) < 2 || any(~isfinite(allPoints), 'all')
                info.Message = ...
                    "Feature-anchor resampling produced invalid profile data.";
                return;
            end

            % Remove only movement blocks in which neither side moves. Movement
            % on one side while the other remains stationary is valid.
            movementL = hypot( ...
                diff(allPoints(:, 1)), ...
                diff(allPoints(:, 2)));

            movementR = hypot( ...
                diff(allPoints(:, 3)), ...
                diff(allPoints(:, 4)));

            keep = [ true; movementL > 1e-9 | movementR > 1e-9 ];
            allPoints = allPoints(keep, :);

            % Retain one explicit closing point.
            allPoints(end, :) = allPoints(1, :);

            outputAnchorIdx = zeros(size(anchorL, 1), 1);

            coordinateScale = max([ ...
                max(yL) - min(yL), ...
                max(zL) - min(zL), ...
                max(yR) - min(yR), ...
                max(zR) - min(zR), ...
                1.0 ]);

            anchorTolerance = 1e-6 * coordinateScale;

            for anchorNumber = 1:size(anchorL, 1)
                distanceL = hypot( ...
                    allPoints(:, 1) - anchorL(anchorNumber, 1), ...
                    allPoints(:, 2) - anchorL(anchorNumber, 2));

                distanceR = hypot( ...
                    allPoints(:, 3) - anchorR(anchorNumber, 1), ...
                    allPoints(:, 4) - anchorR(anchorNumber, 2));

                matchedRow = find( ...
                    distanceL <= anchorTolerance & ...
                    distanceR <= anchorTolerance, ...
                    1, 'first');

                if isempty(matchedRow)
                    info.Message = string(sprintf( ...
                        'Matched feature anchor %d was not retained.', ...
                        anchorNumber));
                    return;
                end

                outputAnchorIdx(anchorNumber) = matchedRow;
            end

            if any(diff(outputAnchorIdx) <= 0)
                info.Message = ...
                    "The resampled feature anchors are not in traversal order.";
                return;
            end

            yLS = allPoints(:, 1);
            zLS = allPoints(:, 2);
            yRS = allPoints(:, 3);
            zRS = allPoints(:, 4);

            info.Valid = true;
            info.Message = string(sprintf( ...
                'Matched %d feature anchors across %d proportional sections.', ...
                size(anchorL, 1), sectionCount));

            info.AnchorCount = size(anchorL, 1);
            info.AnchorIndices = outputAnchorIdx;
            info.AnchorPointsL = anchorL;
            info.AnchorPointsR = anchorR;
            info.SectionCount = sectionCount;
            info.OutputPointCount = size(allPoints, 1);

            function [ yo, zo ] = cleanClosedLoop(yi, zi)
                yi = yi(:);
                zi = zi(:);

                valid = isfinite(yi) & isfinite(zi);
                yi = yi(valid);
                zi = zi(valid);

                if isempty(yi)
                    yo = yi;
                    zo = zi;
                    return;
                end

                distanceFromPrevious = [ inf; hypot(diff(yi), diff(zi)) ];
                keepPoint = distanceFromPrevious > 1e-8;

                yo = yi(keepPoint);
                zo = zi(keepPoint);

                if numel(yo) > 1 && ...
                        hypot(yo(1) - yo(end), zo(1) - zo(end)) > 1e-8
                    yo(end+1) = yo(1);
                    zo(end+1) = zo(1);
                end
            end

            function areaValue = signedArea(y, z)
                yOpen = y(:);
                zOpen = z(:);

                if numel(yOpen) > 1 && ...
                        hypot( ...
                        yOpen(1) - yOpen(end), ...
                        zOpen(1) - zOpen(end)) <= 1e-8

                    yOpen(end) = [];
                    zOpen(end) = [];
                end

                nextIdx = [ 2:numel(yOpen), 1 ];

                areaValue = sum( ...
                    yOpen .* zOpen(nextIdx) - ...
                    yOpen(nextIdx) .* zOpen);
            end

            function [ indices, success ] = locateAnchors(y, z, anchors)
                indices = zeros(size(anchors, 1), 1);
                success = false;

                searchCount = numel(y);

                if searchCount > 1 && ...
                        hypot(y(1) - y(end), z(1) - z(end)) <= 1e-8
                    searchCount = searchCount - 1;
                end

                scale = max([ ...
                    max(y) - min(y), ...
                    max(z) - min(z), ...
                    1.0 ]);

                matchTolerance = 1e-6 * scale;

                for anchorNumber = 1:size(anchors, 1)
                    distances = hypot( ...
                        y(1:searchCount) - anchors(anchorNumber, 1), ...
                        z(1:searchCount) - anchors(anchorNumber, 2));

                    [ minimumDistance, nearestIdx ] = min(distances);

                    if minimumDistance > matchTolerance
                        return;
                    end

                    indices(anchorNumber) = nearestIdx;
                end

                if numel(unique(indices)) ~= numel(indices)
                    return;
                end

                success = true;
            end

            function [ pointsOut, success ] = ...
                    synchroniseOpenSection(pointsL, pointsR, tolerance)

                pointsOut = zeros(0, 4);
                success = false;

                if size(pointsL, 1) < 2 || size(pointsR, 1) < 2
                    return;
                end

                distanceL = [ ...
                    0; ...
                    cumsum(hypot( ...
                    diff(pointsL(:, 1)), ...
                    diff(pointsL(:, 2)))) ];

                distanceR = [ ...
                    0; ...
                    cumsum(hypot( ...
                    diff(pointsR(:, 1)), ...
                    diff(pointsR(:, 2)))) ];

                lengthL = distanceL(end);
                lengthR = distanceR(end);

                if lengthL <= 1e-10 || lengthR <= 1e-10
                    return;
                end

                parameterL = distanceL / lengthL;
                parameterR = distanceR / lengthR;

                parameterL(1) = 0;
                parameterL(end) = 1;
                parameterR(1) = 0;
                parameterR(end) = 1;

                baselineResolution = 0.1;

                finePointCount = max( ...
                    200, ...
                    ceil(max(lengthL, lengthR) / baselineResolution) + 1);

                finePointCount = min( ...
                    finePointCount, ...
                    CNCHotWire_GCodeGenerator_Helpers.ProfileResampleMaxPoints);

                fineParameter = linspace(0, 1, finePointCount).';

                % Preserve every original section vertex in the evaluation grid.
                evaluationParameter = unique([ ...
                    fineParameter; ...
                    parameterL; ...
                    parameterR ]);

                [ parameterLU, indexLU ] = unique(parameterL, 'stable');
                [ parameterRU, indexRU ] = unique(parameterR, 'stable');

                yLFine = interp1( ...
                    parameterLU, pointsL(indexLU, 1), ...
                    evaluationParameter, 'linear');

                zLFine = interp1( ...
                    parameterLU, pointsL(indexLU, 2), ...
                    evaluationParameter, 'linear');

                yRFine = interp1( ...
                    parameterRU, pointsR(indexRU, 1), ...
                    evaluationParameter, 'linear');

                zRFine = interp1( ...
                    parameterRU, pointsR(indexRU, 2), ...
                    evaluationParameter, 'linear');

                densePoints = [ yLFine, zLFine, yRFine, zRFine ];

                pointsOut = simplifyPairedPolyline( ...
                    densePoints, tolerance);

                success = size(pointsOut, 1) >= 2 && ...
                    all(isfinite(pointsOut), 'all');
            end

            function pointsOut = simplifyPairedPolyline(pointsIn, tolerance)
                pointCount = size(pointsIn, 1);

                if pointCount <= 2
                    pointsOut = pointsIn;
                    return;
                end

                keepMask = false(pointCount, 1);
                keepMask(1) = true;
                keepMask(end) = true;

                stack = [ 1, pointCount ];

                while ~isempty(stack)
                    endIdx = stack(end);
                    startIdx = stack(end-1);
                    stack(end-1:end) = [];

                    if endIdx - startIdx < 2
                        continue;
                    end

                    interiorIdx = (startIdx + 1):(endIdx - 1);

                    startL = pointsIn(startIdx, 1:2);
                    endL = pointsIn(endIdx, 1:2);
                    interiorL = pointsIn(interiorIdx, 1:2);

                    startR = pointsIn(startIdx, 3:4);
                    endR = pointsIn(endIdx, 3:4);
                    interiorR = pointsIn(interiorIdx, 3:4);

                    errorSqL = pointToSegmentErrorSquared( ...
                        interiorL, startL, endL);

                    errorSqR = pointToSegmentErrorSquared( ...
                        interiorR, startR, endR);

                    combinedErrorSq = max(errorSqL, errorSqR);
                    [ maximumErrorSq, localIdx ] = max(combinedErrorSq);

                    if maximumErrorSq > tolerance^2
                        splitIdx = interiorIdx(localIdx);
                        keepMask(splitIdx) = true;

                        stack = [ stack, splitIdx, endIdx ]; %#ok<AGROW>
                        stack = [ stack, startIdx, splitIdx ]; %#ok<AGROW>
                    end
                end

                pointsOut = pointsIn(keepMask, :);
            end

            function errorSquared = pointToSegmentErrorSquared( ...
                    points, segmentStart, segmentEnd)

                segmentVector = segmentEnd - segmentStart;
                segmentLengthSquared = sum(segmentVector.^2);

                relativePoints = bsxfun(@minus, points, segmentStart);

                if segmentLengthSquared < 1e-12
                    errorSquared = sum(relativePoints.^2, 2);
                    return;
                end

                projection = ...
                    (relativePoints * segmentVector.') / ...
                    segmentLengthSquared;

                projection = max(0, min(1, projection));

                closestPoints = bsxfun( ...
                    @plus, ...
                    segmentStart, ...
                    bsxfun(@times, projection, segmentVector));

                errorSquared = sum((points - closestPoints).^2, 2);
            end
        end

        function[ yLS, zLS, yRS, zRS ] = resampleProfilesSynced(yL, zL, yR, zR, tol)
            % Purpose: Resamples Left and Right profiles simultaneously to ensure 1:1 point topology.
            % WHY: 4-axis CNC requires exactly the same number of points on the left and right profiles
            %      so the controller knows how to interpolate the wire between them.
            % HOW: 1. Aligns both profiles to start at the exact same physical feature (Front Face).
            %      2. Checks winding direction (CW/CCW) and flips one if they are mismatched.
            %      3. Interpolates both onto a highly dense, shared parametric grid (0 to 1).
            %      4. Runs a custom 4D Ramer-Douglas-Peucker (RDP) algorithm to strip out unnecessary
            %         points while guaranteeing the deviation never exceeds the user's tolerance.

            function[ x, y ] = clean_path(x,y)
                if numel(x) < 2
                    return;
                end
                d2 =[ 1; (diff(x).^2 + diff(y).^2) ];
                keep = d2 > 1e-8;
                x = x(keep);
                y = y(keep);
                if (x(1)~=x(end) || y(1)~=y(end))
                    x(end+1) = x(1);
                    y(end+1) = y(1);
                end
            end

            [ yL, zL ] = clean_path(yL, zL);
            [ yR, zR ] = clean_path(yR, zR);

            if numel(yL) < 3 || numel(yR) < 3
                yLS = yL; zLS = zL; yRS = yR; zRS = zR;
                return;
            end

            % 1. Align start points to the front face
            [ yL, zL ] = CNCHotWire_GCodeGenerator_Helpers.reorderLoopByMinY(yL, zL);
            [ yR, zR ] = CNCHotWire_GCodeGenerator_Helpers.reorderLoopByMinY(yR, zR);

            % 2. Ensure winding directions match by calculating polygon area
            areaL = sum((yL(1:end-1).*zL(2:end)) - (yL(2:end).*zL(1:end-1)));
            areaR = sum((yR(1:end-1).*zR(2:end)) - (yR(2:end).*zR(1:end-1)));

            if sign(areaL) ~= sign(areaR)
                yR = flipud(yR);
                zR = flipud(zR);
                [ yR, zR ] = CNCHotWire_GCodeGenerator_Helpers.reorderLoopByMinY(yR, zR);
            end

            % 3. Calculate parametric arc lengths (0 to 1)
            distL =[ 0; cumsum(hypot(diff(yL), diff(zL))) ];
            distR =[ 0; cumsum(hypot(diff(yR), diff(zR))) ];
            maxLen = max(distL(end), distR(end));

            if maxLen < 1e-6
                yLS = yL; zLS = zL; yRS = yR; zRS = zR;
                return;
            end

            % 4. Create a dense, shared parametric grid
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
            s_eval = unique([ s_fine; s_rawL; s_rawR ]);

            [ suL, iuL ] = unique(s_rawL, 'stable');
            [ suR, iuR ] = unique(s_rawR, 'stable');

            yLf = interp1(suL, yL(iuL), s_eval, 'linear');
            zLf = interp1(suL, zL(iuL), s_eval, 'linear');
            yRf = interp1(suR, yR(iuR), s_eval, 'linear');
            zRf = interp1(suR, zR(iuR), s_eval, 'linear');

            % 5. 4D Ramer-Douglas-Peucker (RDP) Algorithm
            % We treat the [yL, zL, yR, zR] coordinates as a single 4D point.
            % We only remove a point if its removal causes BOTH the left and right
            % 2D profiles to deviate by less than the user's tolerance.

            pts4D =[ yLf, zLf, yRf, zRf ];
            keepMask = false(size(pts4D, 1), 1);
            keepMask(1) = true;
            keepMask(end) = true;

            stack =[ 1, size(pts4D, 1) ];

            while ~isempty(stack)
                idxEnd = stack(end);
                idxStart = stack(end-1);
                stack(end-1:end) =[ ];

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

                [ maxSq, localIdx ] = max(max_distsSq);

                if maxSq > (tol^2)
                    splitIdx = idxStart + localIdx;
                    keepMask(splitIdx) = true;
                    stack =[ stack, splitIdx, idxEnd ];
                    stack =[ stack, idxStart, splitIdx ];
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

        function [ yLS, zLS, yRS, zRS ] = syncPointCounts(yL, zL, yR, zR)
            % Purpose: A lightweight synchronizer used after Kerf is applied.
            % WHY: Applying kerf (polybuffer) can slightly alter the point count of a profile.
            %      This function forces them back into a 1:1 topology without running the heavy RDP algorithm.

            function[ x, y ] = clean(x, y)
                if numel(x) < 2
                    return;
                end
                dist =[ 1; sqrt(diff(x).^2 + diff(y).^2) ];
                keep = dist > 1e-6;
                x = x(keep);
                y = y(keep);
                if (numel(x) > 2) && (hypot(x(1)-x(end), y(1)-y(end)) > 1e-6)
                    x(end+1) = x(1);
                    y(end+1) = y(1);
                end
            end

            [ yL, zL ] = clean(yL, zL);
            [ yR, zR ] = clean(yR, zR);

            function s = getArcParam(y, z)
                if numel(y) < 2
                    s=zeros(size(y));
                    return;
                end
                d =[ 0; cumsum(hypot(diff(y), diff(z))) ];
                maxD = d(end);
                if maxD < 1e-6
                    maxD = 1;
                end
                s = d / maxD;
            end

            sL = getArcParam(yL, zL);
            sR = getArcParam(yR, zR);

            if isempty(sL) || isempty(sR)
                yLS = yL; zLS = zL; yRS = yR; zRS = zR;
                return;
            end

            if numel(sL) == numel(sR) && max(abs(sL - sR)) < 1e-3
                yLS = yL; zLS = zL; yRS = yR; zRS = zR;
                return;
            end

            sL(1) = 0; sL(end) = 1;
            sR(1) = 0; sR(end) = 1;

            % Exact grid merging (No rounding!)
            s_target = unique([ sL; sR ]);

            [ sL_u, idxL ] = unique(sL, 'stable');
            [ sR_u, idxR ] = unique(sR, 'stable');

            yLS = interp1(sL_u, yL(idxL), s_target, 'linear');
            zLS = interp1(sL_u, zL(idxL), s_target, 'linear');
            yRS = interp1(sR_u, yR(idxR), s_target, 'linear');
            zRS = interp1(sR_u, zR(idxR), s_target, 'linear');
        end

        %% ===============================================================
        %% --- GROUP 4: GEOMETRY MODIFICATION & KINEMATICS ---
        %% ===============================================================

        function [ towerL, towerR ] = projectToTowers(yL, zL, xL, yR, zR, xR, spanX)
            % Purpose: Projects a 3D model toolpath outwards onto the physical machine towers.
            % WHY: The CNC controller only knows how to move the Left and Right towers. It doesn't
            %      know where the billet is. We must calculate where the towers need to be to make
            %      the wire intersect the model at the correct coordinates.
            % HOW: Uses similar triangles / linear extrapolation from the model planes to the tower planes.

            towerL.y = yL + (0 - xL) .* (yR - yL) ./ (xR - xL);
            towerL.z = zL + (0 - xL) .* (zR - zL) ./ (xR - xL);

            towerR.y = yL + (spanX - xL) .* (yR - yL) ./ (xR - xL);
            towerR.z = zL + (spanX - xL) .* (zR - zL) ./ (xR - xL);
        end

        function [ yo, zo ] = offsetProfileLoop(yIn, zIn, kerf, tol)
            % Purpose: Expands or shrinks a 2D profile to compensate for the thickness of the hot wire.
            % WHY: If we cut exactly on the line, the part will be too small by half the width of the wire.
            % HOW: Converts the points into a MATLAB 'polyshape', applies 'polybuffer', and extracts the new boundary.

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

            % Offset distance is half the kerf (radius of the wire cut)
            offsetDist = kerf / 2.0;

            % Rounding prevents microscopic self-intersections that crash polyshape
            inputPoints = round([ y, z ], 8);

            [ ~, uniqueIdx ] = unique(inputPoints, 'rows', 'stable');

            y = y(uniqueIdx);
            z = z(uniqueIdx);

            % Suppress polyshape warnings (e.g., "Polygon is self-intersecting")
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

                % If polybuffer creates multiple islands, keep the largest one
                if pgonOut.NumRegions > 1
                    areaList = area(pgonOut.regions);
                    [ ~, maxIdx ] = max(areaList);
                    pgonOut = pgonOut.regions(maxIdx);
                end

                [ yo, zo ] = boundary(pgonOut);

                nanIdx = find(isnan(yo), 1);
                if ~isempty(nanIdx)
                    yo = yo(1:nanIdx-1);
                    zo = zo(1:nanIdx-1);
                end

            catch
                return;
            end

            % If a tolerance is provided, run RDP to clean up the dense arcs created by polybuffer
            if tol > 0 && numel(yo) > 5
                pts =[ yo, zo ];
                N = size(pts, 1);
                keepMask = false(N, 1);
                keepMask(1) = true;
                keepMask(end) = true;

                stack =[ 1, N ];

                while ~isempty(stack)
                    idxEnd = stack(end);
                    idxStart = stack(end-1);
                    stack(end-1:end) =[ ];

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

                    [ maxSq, localIdx ] = max(distsSq);

                    if maxSq > (tol^2)
                        splitIdx = rng(localIdx);
                        keepMask(splitIdx) = true;
                        stack =[ stack, splitIdx, idxEnd ];
                        stack =[ stack, idxStart, splitIdx ];
                    end
                end

                yo = pts(keepMask, 1);
                zo = pts(keepMask, 2);
            end

            % Re-align the start point to the front face after buffering
            [ yo, zo ] = CNCHotWire_GCodeGenerator_Helpers.reorderLoopByMinY(yo, zo);

            if isrow(yIn)
                yo = yo.';
                zo = zo.';
            end
        end

        function [ yOut, zOut ] = reorderLoopByMinY(y, z)
            % Purpose: Aligns the start point of a profile loop to the physical front face of the model.
            % WHY: If Left and Right profiles start at different physical features, the 4-axis
            %      interpolation will twist the wire through the foam, destroying the part.
            % HOW: Finds the minimum Y value (front face). If the front face is a tall vertical flat,
            %      it injects a new point exactly at the Z-centroid to guarantee perfect alignment.

            % 1. Force to Column Vectors
            y = y(:); z = z(:);

            % 2. Remove tailing point duplicate
            if numel(y) > 1 && abs(y(1)-y(end)) < 1e-6 && abs(z(1)-z(end)) < 1e-6
                y(end) =[ ]; z(end) =[ ];
            end

            if numel(y) < 3
                yOut = y; zOut = z; return;
            end

            % 3. Find Bounding Box Center in Z and Front Face (min Y)
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
                y_new =[ y(1:insert_idx); best_yi; y(insert_idx+1:end) ];
                z_new =[ z(1:insert_idx); cz;      z(insert_idx+1:end) ];

                startIdx = insert_idx + 1;
                yOut =[ y_new(startIdx:end); y_new(1:startIdx-1) ];
                zOut =[ z_new(startIdx:end); z_new(1:startIdx-1) ];
            else
                % FALLBACK: Find existing points on the front face
                front_indices = find(abs(y - minY) < 1e-3);

                if isempty(front_indices)
                    [ ~, startIdx ] = min(y);
                else
                    % Pick the one closest to Z-centroid
                    [ ~, local_idx ] = min(abs(z(front_indices) - cz));
                    startIdx = front_indices(local_idx);
                end

                yOut =[ y(startIdx:end); y(1:startIdx-1) ];
                zOut =[ z(startIdx:end); z(1:startIdx-1) ];
            end

            % 6. Force exact closure
            yOut(end+1) = yOut(1);
            zOut(end+1) = zOut(1);
        end

        function billet = computeDefaultBilletFromMesh(V, xPlaneA, xPlaneB, bufferY, bufferZ)
            % Purpose: Calculates the default physical dimensions of the foam stock required.
            % WHY: Used by the Billet tab's "Auto-Fit" button.
            % HOW: Takes the bounding box of the model, adds safety buffers, and snaps the Z-height
            %      to standard physical foam block thicknesses (e.g., 50mm, 75mm, 100mm).

            if nargin < 4, bufferY = 5.0; end
            if nargin < 5, bufferZ = 5.0; end

            [ mins ] = min(V, [ ], 1);
            [ maxs ] = max(V, [ ], 1);

            % X Logic
            billet.Xmin = min(xPlaneA, xPlaneB) - 0.001;
            billet.Xmax = max(xPlaneA, xPlaneB) + 0.001;

            % Y Logic
            billet.Ymin = mins(2) - bufferY;
            billet.Ymax = maxs(2) + bufferY;

            % Z Logic (Stock Selection)
            modelH = maxs(3) - mins(3);
            requiredH = modelH + (bufferZ * 2);

            stocks = CNCHotWire_GCodeGenerator_Helpers.BilletStockHeights;
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