
struct City
    city::String
    households::Int
    avgelectricity_kwh::Float64
    grid_co2_per_kwh::Float64
    transport_co2_perhousehold::Float64
    ev_percentage::Float64
    solar_percentage::Float64
    aqi::Int
end

function load_or_create_city_df()
    datafile = joinpath(DATA_DIR, "city_data.csv")
    if !isfile(datafile)
        println("  No city_data.csv found — creating default dataset at $(datafile).")
        CSV.write(datafile, DataFrame(
            City = ["Chennai","Mumbai","Delhi","Bangalore","Kolkata"],
            Households = [10000,12000,15000,11000,9000],
            AvgElectricity_kWh = [350,400,420,370,360],
            Grid_CO2_per_kWh = [0.82,0.91,0.95,0.78,0.80],
            Transport_CO2_perHousehold = [180,220,250,190,200],
            EV_Percentage = [15,10,8,18,12],
            Solar_Percentage = [20,15,10,22,18],
            AQI = [82,102,115,78,88]
        ))
    end

    df = CSV.read(datafile, DataFrame)
    rename!(df, names(df) .=> [lowercase(replace(string(n), r"[\s\(\)/]+" => "_")) for n in names(df)])

    df.avgelectricity_kwh = Float64.(df.avgelectricity_kwh)
    df.grid_co2_per_kwh = Float64.(df.grid_co2_per_kwh)
    df.transport_co2_perhousehold = Float64.(df.transport_co2_perhousehold)
    df.ev_percentage = Float64.(df.ev_percentage)
    df.solar_percentage = Float64.(df.solar_percentage)

    return df
end

function pick_city(df::DataFrame, city_name::String)
    names_lc = lowercase.(df.city)
    idx = findfirst(==(lowercase(city_name)), names_lc)
    if isnothing(idx)
        println("  City '$(city_name)' not found. Available: ", join(df.city, ", "))
        println("  Defaulting to: ", df.city[1])
        return df[1, :]
    else
        return df[idx, :]
    end
end

function city_from_row(row)
    City(
        String(row.city),
        Int(row.households),
        Float64(row.avgelectricity_kwh),
        Float64(row.grid_co2_per_kwh),
        Float64(row.transport_co2_perhousehold),
        Float64(row.ev_percentage),
        Float64(row.solar_percentage),
        Int(row.aqi)
    )
end

get_city(name::AbstractString, city_df::DataFrame, default::City) = begin
    for r in eachrow(city_df)
        if r.city == name
            return city_from_row(r)
        end
    end
    default
end

function estimate_emission(city::City, ev::Float64, solar::Float64, grid::Float64)
    elec = city.avgelectricity_kwh * grid * city.households * 365 / 1000
    
    ev_reduction = 1 - (ev / 100 * 0.40)

    trans = city.transport_co2_perhousehold * ev_reduction * city.households * 365 / 1000

    total = elec + trans
    reduction_factor = (solar * 0.6 + ev * 0.4) / 100
    optimized = total * (1 - reduction_factor)
    return elec, trans, total, optimized
end

function household_module(city::City)
    println("\n Household Emission & Cost (City-adjusted)")
    print("Enter YOUR average daily electricity use (kWh): ")
    elec = parse(Float64, readline())
    print("Enter YOUR daily vehicle distance (km): ")
    km = parse(Float64, readline())
    print("Do you currently use an EV? (yes/no): ")
    ev_use = lowercase(readline())
    print("Do you have rooftop solar? (yes/no): ")
    solar_use = lowercase(readline())

    grid_co2 = city.grid_co2_per_kwh
    fuel_co2_per_km, ev_co2_per_km = 0.18, 0.05
    cost_per_kwh, fuel_cost_per_km = 8.0, 8.5 / 15

    yearly_elec_co2 = elec * grid_co2 * 365
    yearly_trans_co2 = km * (ev_use == "yes" ? ev_co2_per_km : fuel_co2_per_km) * 365
    total_co2 = yearly_elec_co2 + yearly_trans_co2

    yearly_elec_cost = elec * 365 * cost_per_kwh
    yearly_fuel_cost = km * 365 * (ev_use == "yes" ? 1.5 : fuel_cost_per_km * 100)
    total_cost = yearly_elec_cost + yearly_fuel_cost

    println("\n Household Summary (City: $(city.city))")
    println("   Annual CO₂: $(formatnum(total_co2)) kg")
    println("   Annual energy/fuel cost: ₹$(formatnum(total_cost))")

    potential_solar_saving = solar_use == "no" ? 0.15 * yearly_elec_cost : 0.0
    potential_ev_saving    = ev_use == "no"   ? 0.25 * yearly_fuel_cost : 0.0
    potential_co2_drop     = total_co2 * 0.20

    println("\n Recommendations for YOU:")
    if solar_use == "no"
        println("    Install rooftop solar → save ≈ ₹$(formatnum(potential_solar_saving)) / year")
    end
    if ev_use == "no"
        println("   Switch to EV → reduce transport CO₂ by ~25% and save ≈ ₹$(formatnum(potential_ev_saving)) / year")
    end
    println("  Estimated personal CO₂ reduction potential: $(formatnum(potential_co2_drop)) kg (~20%)\n")

    return (elec=elec, km=km, ev_use=ev_use, solar_use=solar_use,
            total_co2=total_co2, total_cost=total_cost)
end

function adjust_city_with_household(city::City, hh)
    hh_transport_kg_per_day = hh.km * 0.18
    new_avg_elec = 0.9 * city.avgelectricity_kwh + 0.1 * hh.elec
    new_transport = 0.9 * city.transport_co2_perhousehold + 0.1 * hh_transport_kg_per_day
    return City(
        city.city,
        city.households,
        new_avg_elec,
        city.grid_co2_per_kwh,
        new_transport,
        city.ev_percentage,
        city.solar_percentage,
        city.aqi
    )
end
