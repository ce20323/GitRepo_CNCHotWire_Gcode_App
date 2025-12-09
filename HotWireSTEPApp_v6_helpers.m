classdef HotWireSTEPApp_v6_helpers
    % Helper utilities for HotWireSTEPApp_v6_2
    % Currently:
    %   - importSTEP_FreeCAD: STEP → STL via FreeCAD, then into [V,F]

    methods(Static)
        function [V,F] = importSTEP_FreeCAD(cadPath, freeCADExe)
            % IMPORTSTEP_FREECAD  Use FreeCADCmd to convert a STEP file
            % into an STL, then load the STL as a triangulated mesh.
            %
            %   [V,F] = HotWireSTEPApp_v6_helpers.importSTEP_FreeCAD(cadPath, freeCADExe)
            %
            % Inputs:
            %   cadPath   - full path to the STEP (.step / .stp) file
            %   freeCADExe - full path to FreeCADCmd.exe
            %
            % Outputs:
            %   V - Nx3 double array of vertex coordinates
            %   F - Mx3 double array of triangle indices

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

            % Create temporary filenames
            tmpID  = char(java.util.UUID.randomUUID());
            outSTL = fullfile(tempdir, ['fc_out_' tmpID '.stl']);
            pyFile = fullfile(tempdir, ['fc_' tmpID '.py']);

            % Write the FreeCAD Python script
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

            % Build system command
            cmd = sprintf('"%s" "%s"', freeCADExe, pyFile);
            [status, out] = system(cmd); %#ok<ASGLU>
            % You can uncomment the next line if you want to see FreeCAD output:
            % disp(out);

            if status ~= 0
                warning('FreeCAD conversion failed (status %d).', status);
                return;
            end

            % Read STL if it was successfully created
            if isfile(outSTL)
                raw = stlread(outSTL);
                if isa(raw,"triangulation")
                    F = raw.ConnectivityList;
                    V = raw.Points;
                else
                    [F,V] = stlread(outSTL); %#ok<*STLREAD>
                end
                V = double(V);
                F = double(F);
            else
                warning('Expected STL output not found: %s', outSTL);
            end
        end
    end
end
