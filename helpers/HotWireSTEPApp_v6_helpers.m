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

    end
end
