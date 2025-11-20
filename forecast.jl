
function forecast_city(city::City; years=2025:2030)
    results = DataFrame()
    ev, solar, grid = city.ev_percentage, city.solar_percentage, city.grid_co2_per_kwh
    for year in years
        elec_t, trans_t, total, opt = estimate_emission(city, ev, solar, grid)
        reduction = total > 0 ? (total - opt) / total * 100 : 0.0
        aqi_future = Int(round(city.aqi * (1 - reduction / 100 * 0.6)))
        push!(results, (
            City = city.city,
            Year = year,
            Baseline_CO2 = total,
            Optimized_CO2 = opt,
            Elec_CO2 = elec_t,
            Transport_CO2 = trans_t,
            EV = ev,
            Solar = solar,
            AQI = aqi_future,
            Reduction_Percent = round(reduction, digits=2)
        ))
        ev    = min(ev + 2.0, 100.0)
        solar = min(solar + 2.5, 100.0)
        grid  = grid * (1 - 0.02)
    end
    return results
end

function add_csi!(df::DataFrame)
    base_max = maximum(df.Baseline_CO2)
    aqi_max  = maximum(df.AQI)
    solar_gap = 100 .- df.Solar
    solar_gap_max = maximum(solar_gap)
    raw = 0.5 .* (df.Baseline_CO2 ./ base_max) .+
          0.3 .* (df.AQI ./ aqi_max) .+
          0.2 .* (solar_gap ./ solar_gap_max)
    raw_min, raw_max = minimum(raw), maximum(raw)
    df.CSI = 100 .* (raw .- raw_min) ./ (raw_max - raw_min + eps())
    return df
end

function forecast_for_city(name::AbstractString, city_df::DataFrame, default_city::City, df_dash::DataFrame)
    if any(r -> r.city == name, eachrow(city_df))
        c = get_city(name, city_df, default_city)
        f = forecast_city(c)
        add_csi!(f)
        return f
    else
        return df_dash
    end
end
