# CNCHotWire G-Code App

A MATLAB-based application for generating, simulating, and exporting G-code for CNC hot-wire foam cutting machines. The tool integrates with Mach4 and Pokeys systems and supports STL/STEP input, multi-axis toolpaths, and custom cutting logic.

## 🚀 Features

- Import STL and STEP files
- Generate 2D and 3D toolpaths for hot-wire cutting
- Adjustable cut parameters (speed, offsets, alignment)
- Toolpath visualisation inside MATLAB
- Exports G-code compatible with Mach4
- Modular code structure for easy maintenance

## 📂 Project Structure

/src              → Main MATLAB code  
/helpers          → Utility functions  
/examples         → Sample geometry files  
/docs             → Project documentation  
/data             → CAD models for testing

## 🛠 Requirements

- MATLAB R2021a or later  
- Optional:  
  - Image Processing Toolbox (for previews)  
  - Curve Fitting Toolbox (for smoothing)

## ▶️ How to Run

1. Clone the repository:
   git clone https://github.com/ce20323/GitRepo_CNCHotWire_Gcode_App.git

2. Add the folder to the MATLAB path:
   addpath(genpath('GitRepo_CNCHotWire_Gcode_App'));

3. Run the main script (replace "main" with your actual start file):
   main

## 🔧 Development Workflow

- main → stable code  
- feature-xxx → new features  
- bugfix-xxx → bug fixes  

## 📄 License

TBD