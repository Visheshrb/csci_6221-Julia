README – How to Run main.jl

Install Julia 1.9+ from https://julialang.org/downloads/


Open Julia and install packages using:
using Pkg; Pkg.add(["CSV","DataFrames","Plots","Dash","PlotlyJS","Statistics","FilePathsBase","Dates"])

Place all project files (main.jl, utils.jl, model.jl, forecast.jl, policy.jl, dashboard.jl) in one folder.

When you run the program, the folders data/ and plots/ are created automatically.

Open a terminal in the project folder.

Run the full system using: julia main.jl

Enter your city name when prompted (e.g., Delhi, Chennai).

Answer the household questions to personalize the model.

The program generates CSVs in data/ and graphs in plots/ automatically.

Open the dashboard at http://127.0.0.1:8050
 to view all results interactively.
