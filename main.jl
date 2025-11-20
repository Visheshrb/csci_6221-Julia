
using CSV, DataFrames, Statistics, Printf, Dates
using FilePathsBase: mkpath
using Plots
using Dash
using DashHtmlComponents
using DashCoreComponents
import PlotlyJS

include("utils.jl")
include("model.jl")
include("forecast.jl")
include("policy.jl")
include("dashboard.jl")

println("SMART CITY DECISION SYSTEM ")
print("Enter your city (e.g., Chennai, Mumbai, Delhi, Bangalore, Kolkata): ")
city_name = readline()

city_df = load_or_create_city_df()
city_row_df = pick_city(city_df, city_name)
city_base = city_from_row(city_row_df)

hh = household_module(city_base)

base_forecast = forecast_city(city_base)
add_csi!(base_forecast)

city_adj = adjust_city_with_household(city_base, hh)

println("-- Running adjusted city forecast for $(city_adj.city) (2025–2030) --")
adj_forecast = forecast_city(city_adj)
add_csi!(adj_forecast)

CSV.write(joinpath(DATA_DIR, "Forecast_$(city_adj.city)_BaselineCityAvg.csv"), base_forecast)
CSV.write(joinpath(DATA_DIR, "Forecast_$(city_adj.city)_WithHouseholdBlend.csv"), adj_forecast)
println(" Saved city forecast CSVs in /data.")

plots_for_forecast(city_adj, adj_forecast)
println(" Saved forecast & CSI plots in /plots.")

println("\n-- Optimizing EV/Solar Policy for $(city_adj.city) --")
ev_grid = 0.0:1.0:5.0
solar_grid = 0.0:1.0:6.0

best_ev, best_sol, net_bene, best_yearly, best_nb =
    optimize_policy_city(city_adj; ev_grid=ev_grid, solar_grid=solar_grid)

println("\nBest policy for $(city_adj.city):")
println("  EV growth per year   : $(best_ev)%")
println("  Solar growth per year: $(best_sol)%")
println("  Net Benefit (₹)      : $(formatnum(best_nb))")

plots_for_policy(city_adj.city, net_bene, ev_grid, solar_grid, best_yearly)
CSV.write(joinpath(DATA_DIR, "BestPolicy_$(city_adj.city).csv"), best_yearly)
println(" Policy plots saved in /plots, data saved as BestPolicy_$(city_adj.city).csv.")

print_smart_recommendations(city_adj, base_forecast, adj_forecast,
                            best_ev, best_sol, best_nb)

ranking_df = create_ranking_csv(city_df)
println("\n Model run complete — starting interactive dashboard...")

file_forecast = joinpath(DATA_DIR, "Forecast_$(city_adj.city)_BaselineCityAvg.csv")
df_dash = CSV.read(file_forecast, DataFrame)

build_and_run_dashboard(city_df, city_base, city_adj, df_dash, ranking_df)
