# CNCHotWire G-Code App

A MATLAB-based application for generating, simulating and exporting G-code for the Rapid Prototyping workshop's four-axis CNC hot-wire foam cutter. The application supports STL and STEP input, coordinated four-axis toolpaths and G-code output for the customised Mach4 profile.

## 🚀 Features

- Import STL and STEP files
- Convert STEP models to mesh data using FreeCAD
- Extract, process and synchronise the left and right cutting profiles
- Apply kerf compensation and configure billet, machine and cutting-strategy settings
- Simulate the coordinated four-axis wire path in MATLAB
- Export Mach4-compatible G-code (`*.tap`)

## 📂 Project Structure

`/src` → Main MATLAB application and Apps-gallery launcher  
`/helpers` → STEP-import and geometry-processing functions  
`/examples` → Sample STEP and STL models  
`/resources/project` → MATLAB project and toolbox-packaging metadata  
`CNCHotWire_GCode_App.prj` → MATLAB project file  
`toolbox.ignore` → File exclusions used when packaging the toolbox

## 🛠 Requirements

- MATLAB R2025b Update 5 is the documented development baseline
- No additional MathWorks products or toolboxes are currently required
- **FreeCAD 1.0 or newer** is required for importing STEP files; direct STL import does not use FreeCAD
- The complete workflow has been tested on Windows. The core application is expected to work on other desktop platforms, but this has not been verified; the current FreeCAD STEP-import route contains Windows-specific code

## ▶️ How to Run

1. Clone the repository, or download its ZIP from GitHub:

   ```bash
   git clone https://github.com/ce20323/GitRepo_CNCHotWire_Gcode_App.git
   ```

2. Open `CNCHotWire_GCode_App.prj` in MATLAB.

3. Run the application from the MATLAB Command Window:

   ```matlab
   app = CNCHotWire_GCodeGenerator;
   ```

4. For STEP import, select `FreeCADCmd.exe` from the application's Welcome tab when prompted.

## 🔧 Development Workflow

- `main` → stable code  
- `feature-xxx` → new features  
- `bugfix-xxx` → bug fixes  

Test changes from source before packaging or merging them into `main`.

## 📄 License

TBD