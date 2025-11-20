
function optimize_policy_city(city::City;
    ev_grid=0.0:1.0:5.0, solar_grid=0.0:1.0:6.0,
    years=2025:2030, SCC=4000.0, cost_EV=120.0, cost_Solar=90.0, grid_improve=0.02)

    net_benefit = Array{Float64}(undef, length(ev_grid), length(solar_grid))
    best_nb, best_ev, best_sol = -Inf, 0.0, 0.0
    best_yearly = DataFrame()

    function simulate_policy(ev_g, sol_g)
        total_avoided, total_cost = 0.0, 0.0
        ev, solar, grid = city.ev_percentage, city.solar_percentage, city.grid_co2_per_kwh
        yearly = DataFrame(Year=Int[], Avoided_CO2=Float64[], Program_Cost_₹=Float64[])
        for year in years
            _, _, _, opt_before = estimate_emission(city, ev, solar, grid)
            ev_after, sol_after = min(ev + ev_g, 100.0), min(solar + sol_g, 100.0)
            _, _, _, opt_after  = estimate_emission(city, ev_after, sol_after, grid)
            avoided = max(opt_before - opt_after, 0.0)
            city_cost = city.households * (cost_EV * ev_g + cost_Solar * sol_g)
            total_avoided += avoided
            total_cost += city_cost
            push!(yearly, (Year=year, Avoided_CO2=avoided, Program_Cost_₹=city_cost))
            ev, solar, grid = ev_after, sol_after, grid * (1 - grid_improve)
        end
        return total_avoided, total_cost, yearly
    end

    for (i, ev_g) in enumerate(ev_grid), (j, sol_g) in enumerate(solar_grid)
        avoided, cost, yearly = simulate_policy(ev_g, sol_g)
        nb = avoided * SCC - cost
        net_benefit[i, j] = nb
        if nb > best_nb
            best_nb, best_ev, best_sol = nb, ev_g, sol_g
            best_yearly = yearly
        end
    end

    return best_ev, best_sol, net_benefit, best_yearly, best_nb
end

function plots_for_forecast(city::City, df::DataFrame)
    city_str = city.city
    bar(string.(df.Year),
        [df.Baseline_CO2 ./ 1000 df.Optimized_CO2 ./ 1000],
        label=["Baseline CO₂" "Optimized CO₂"],
        lw=0, framestyle=:box,
        xlabel="Year", ylabel="CO₂ (thousand tons)",
        title="$(city_str) — CO₂ Forecast 2025–2030")
    savefig(joinpath(PLOTS_DIR, "$(city_str)_Forecast_Baseline_vs_Optimized.png"))

    bar(string.(df.Year),
        [df.Elec_CO2 ./ 1000 df.Transport_CO2 ./ 1000],
        label=["Electricity CO₂" "Transport CO₂"],
        lw=0, framestyle=:box,
        xlabel="Year", ylabel="CO₂ (thousand tons)",
        title="$(city_str) — Electricity vs Transport CO₂ (Baseline)")
    savefig(joinpath(PLOTS_DIR, "$(city_str)_Baseline_Elec_Transport.png"))

    plot(string.(df.Year), df.CSI,
         xlabel="Year", ylabel="Climate Stress Index (0–100)",
         title="$(city_str) — Climate Stress Index Trend",
         lw=3, marker=:circle)
    savefig(joinpath(PLOTS_DIR, "$(city_str)_CSI_Trend.png"))
end

function plots_for_policy(city::AbstractString, net_benefit, ev_grid, solar_grid, best_yearly::DataFrame)
    city_str = String(city)

    heatmap(collect(solar_grid), collect(ev_grid), net_benefit,
            xlabel="Solar Growth (%/yr)", ylabel="EV Growth (%/yr)",
            title="$(city_str) — Policy Net Benefit (₹)", colorbar=true)
    savefig(joinpath(PLOTS_DIR, "$(city_str)_Policy_NetBenefit_Heatmap.png"))

    bar(string.(best_yearly.Year), best_yearly.Avoided_CO2 ./ 1000,
        xlabel="Year", ylabel="Avoided CO₂ (thousand tons)",
        title="$(city_str) — Avoided CO₂ by Year (Best Policy)",
        lw=0, framestyle=:box)
    savefig(joinpath(PLOTS_DIR, "$(city_str)_BestPolicy_AvoidedCO2_ByYear.png"))

    bar(string.(best_yearly.Year), best_yearly.Program_Cost_₹ ./ 1e6,
        xlabel="Year", ylabel="Program Cost (₹ million)",
        title="$(city_str) — Program Cost by Year (Best Policy)",
        lw=0, framestyle=:box)
    savefig(joinpath(PLOTS_DIR, "$(city_str)_BestPolicy_Cost_ByYear.png"))
end

function create_ranking_csv(city_df::DataFrame)
    rows = DataFrame(City=String[], Current_CO2=Float64[],
                     Improved_CO2=Float64[], Reduction_Percent=Float64[])
    for r in eachrow(city_df)
        c = city_from_row(r)
        f = forecast_city(c)
        current = f.Optimized_CO2[end]
        _, _, _, improved = estimate_emission(
            c,
            min(c.ev_percentage + 5.0, 100.0),
            min(c.solar_percentage + 5.0, 100.0),
            c.grid_co2_per_kwh,
        )
        reduction = current > 0 ? (current - improved) / current * 100 : 0.0
        push!(rows, (City=c.city, Current_CO2=current,
                     Improved_CO2=improved, Reduction_Percent=round(reduction, digits=2)))
    end
    rows = sort(rows, [:Reduction_Percent], rev=true)
    rows.Rank = collect(1:nrow(rows))
    outpath = joinpath(DATA_DIR, "CO2_Reduction_Ranking.csv")
    CSV.write(outpath, rows[:, [:City, :Current_CO2, :Improved_CO2, :Reduction_Percent, :Rank]])
    println(" Created CO2_Reduction_Ranking.csv at $(outpath)")
    return rows
end

function print_smart_recommendations(city::City, base_forecast::DataFrame,
                                     adj_forecast::DataFrame, best_ev, best_sol, best_nb)
    base_final = base_forecast[end, :]
    adj_final  = adj_forecast[end, :]
    adj_csi_start  = adj_forecast.CSI[1]
    adj_csi_end    = adj_forecast.CSI[end]

    reduction_2030 = adj_final.Reduction_Percent
    csi_improvement = adj_csi_start - adj_csi_end
    city_saving_2030 = base_final.Optimized_CO2 - adj_final.Optimized_CO2
    city_saving_pct  = base_final.Optimized_CO2 > 0 ? city_saving_2030 / base_final.Optimized_CO2 * 100 : 0.0

    println("\n SMART CITY INSIGHTS FOR $(city.city)")
    println("----------------------------------------")
    println("2030 Optimized CO₂ (before household influence): $(formatnum(base_final.Optimized_CO2)) tons")
    println("2030 Optimized CO₂ (after blending your behavior): $(formatnum(adj_final.Optimized_CO2)) tons")
    println("Relative change due to your profile (scaled across city): $(formatnum(city_saving_pct)) %")

    println("\n Climate Stress Index (CSI):")
    println("  Start CSI (2025): $(formatnum(adj_csi_start))")
    println("  End CSI   (2030): $(formatnum(adj_csi_end))")
    println("  Improvement     : $(formatnum(csi_improvement)) points")

    println("\n Policy Engine Recommendation:")
    println("   Best EV growth per year   : $(best_ev)%")
    println("   Best Solar growth per year: $(best_sol)%")
    println("   Net social benefit (2025–2030): ₹$(formatnum(best_nb))")

    println("\n Narrative Summary:")
    if reduction_2030 < 15
        println("  • $(city.city) is on a high-risk trajectory. Current measures only reduce ~$(reduction_2030)% CO₂ by 2030.")
        println("  • Aggressive EV and solar policies are required, along with stricter emission caps and public transport expansion.")
    elseif reduction_2030 < 30
        println("  • $(city.city) shows moderate decarbonization (~$(reduction_2030)% by 2030).")
        println("  • Scaling rooftop solar and EV adoption following the suggested policy can push the city toward climate-safe zones.")
    else
        println("  • $(city.city) is on a strong low-carbon trajectory, with ~$(reduction_2030)% CO₂ reduction by 2030.")
        println("  • The focus should shift to resilience: green cover, heat adaptation, and maintaining clean transport policies.")
    end

    if csi_improvement > 15
        println("  • CSI improves significantly, indicating that air quality and energy mix both move in the right direction.")
    elseif csi_improvement > 5
        println("  • CSI improves modestly. Additional non-energy measures (urban forestry, congestion pricing) can help.")
    else
        println("  • CSI barely improves — structural interventions (industrial shift, transport zoning) may be required.")
    end

   
end
