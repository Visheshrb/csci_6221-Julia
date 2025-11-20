
function build_and_run_dashboard(city_df::DataFrame, city_base::City, city_adj::City,
                                 df_dash::DataFrame, ranking_df::DataFrame)
    app = dash()

    app.layout = html_div([
        html_h1("Smart City Planner Dashboard", style=Dict("textAlign" => "center")),

        html_div([
            html_label("Select a city:", style=Dict("fontWeight" => "bold")),
            dcc_dropdown(
                id="city_selector",
                options=[Dict("label"=>c, "value"=>c) for c in unique(ranking_df.City)],
                value=city_adj.city
            )
        ], style=Dict("width"=>"50%", "margin"=>"auto")),

        html_br(),

        html_h3("CO₂ Baseline vs Optimized"),
        dcc_graph(id="trend_plot"),

        html_h3("Electricity vs Transport CO₂"),
        dcc_graph(id="elec_transport_plot"),

        html_h3("Climate Stress Index (CSI) Trend"),
        dcc_graph(id="csi_plot"),

        html_h3("Policy Net Benefit Heatmap"),
        dcc_graph(id="policy_heatmap_plot"),

        html_h3("Best Policy — Avoided CO₂ by Year"),
        dcc_graph(id="policy_avoided_plot"),

        html_h3("Best Policy — Program Cost by Year"),
        dcc_graph(id="policy_cost_plot"),

        html_h3("City Ranking Overview"),
        dcc_graph(id="ranking_plot"),

        html_h3("Recommendations"),
        html_div(id="recommendations_box", style=Dict("fontSize"=>"16px", "padding"=>"8px"))
    ])

    callback!(app, Output("trend_plot", "figure"), Input("city_selector", "value")) do city
        subdf = forecast_for_city(city, city_df, city_base, df_dash)
        t1 = PlotlyJS.bar(x=subdf.Year, y=subdf.Baseline_CO2, name="Baseline CO₂")
        t2 = PlotlyJS.bar(x=subdf.Year, y=subdf.Optimized_CO2, name="Optimized CO₂")
        PlotlyJS.Plot(
            [t1, t2],
            PlotlyJS.Layout(
                title="CO₂ Levels for $city (2025–2030)",
                xaxis=PlotlyJS.attr(title="Year"),
                yaxis=PlotlyJS.attr(title="CO₂ (tons)"),
                barmode="group"
            )
        )
    end

    callback!(app, Output("elec_transport_plot", "figure"), Input("city_selector", "value")) do city
        subdf = forecast_for_city(city, city_df, city_base, df_dash)
        t1 = PlotlyJS.bar(x=subdf.Year, y=subdf.Elec_CO2, name="Electricity CO₂")
        t2 = PlotlyJS.bar(x=subdf.Year, y=subdf.Transport_CO2, name="Transport CO₂")
        PlotlyJS.Plot(
            [t1, t2],
            PlotlyJS.Layout(
                title="Electricity vs Transport CO₂ — $city",
                xaxis=PlotlyJS.attr(title="Year"),
                yaxis=PlotlyJS.attr(title="CO₂ (tons)"),
                barmode="group"
            )
        )
    end

    callback!(app, Output("csi_plot", "figure"), Input("city_selector", "value")) do city
        subdf = forecast_for_city(city, city_df, city_base, df_dash)
        t = PlotlyJS.scatter(
            x=subdf.Year, y=subdf.CSI,
            mode="lines+markers", name="CSI"
        )
        PlotlyJS.Plot(
            [t],
            PlotlyJS.Layout(
                title="Climate Stress Index Trend — $city",
                xaxis=PlotlyJS.attr(title="Year"),
                yaxis=PlotlyJS.attr(title="CSI (0–100)")
            )
        )
    end

    callback!(app, Output("policy_heatmap_plot", "figure"), Input("city_selector", "value")) do city
        c = get_city(city, city_df, city_base)
        ev_grid = 0.0:1.0:5.0
        solar_grid = 0.0:1.0:6.0
        _, _, net_bene, _, _ = optimize_policy_city(c; ev_grid=ev_grid, solar_grid=solar_grid)
        h = PlotlyJS.heatmap(
            x=collect(solar_grid),
            y=collect(ev_grid),
            z=net_bene,
            colorbar=PlotlyJS.attr(title="Net Benefit (₹)")
        )
        PlotlyJS.Plot(
            [h],
            PlotlyJS.Layout(
                title="Policy Net Benefit — $city",
                xaxis=PlotlyJS.attr(title="Solar Growth (%/yr)"),
                yaxis=PlotlyJS.attr(title="EV Growth (%/yr)")
            )
        )
    end

    callback!(app, Output("policy_avoided_plot", "figure"), Input("city_selector", "value")) do city
        c = get_city(city, city_df, city_base)
        ev_grid = 0.0:1.0:5.0
        solar_grid = 0.0:1.0:6.0
        _, _, _, best_yearly, _ = optimize_policy_city(c; ev_grid=ev_grid, solar_grid=solar_grid)
        t = PlotlyJS.bar(
            x=best_yearly.Year,
            y=best_yearly.Avoided_CO2,
            name="Avoided CO₂"
        )
        PlotlyJS.Plot(
            [t],
            PlotlyJS.Layout(
                title="Best Policy — Avoided CO₂ by Year ($city)",
                xaxis=PlotlyJS.attr(title="Year"),
                yaxis=PlotlyJS.attr(title="Avoided CO₂ (tons)")
            )
        )
    end

    callback!(app, Output("policy_cost_plot", "figure"), Input("city_selector", "value")) do city
        c = get_city(city, city_df, city_base)
        ev_grid = 0.0:1.0:5.0
        solar_grid = 0.0:1.0:6.0
        _, _, _, best_yearly, _ = optimize_policy_city(c; ev_grid=ev_grid, solar_grid=solar_grid)
        t = PlotlyJS.bar(
            x=best_yearly.Year,
            y=best_yearly.Program_Cost_₹ ./ 1e6,
            name="Program Cost"
        )
        PlotlyJS.Plot(
            [t],
            PlotlyJS.Layout(
                title="Best Policy — Program Cost by Year ($city)",
                xaxis=PlotlyJS.attr(title="Year"),
                yaxis=PlotlyJS.attr(title="Cost (₹ million)")
            )
        )
    end

    callback!(app, Output("ranking_plot", "figure"), Input("city_selector", "value")) do _city
        if nrow(ranking_df) == 0
            return PlotlyJS.Plot([], PlotlyJS.Layout(title="No ranking data available"))
        end
        t = PlotlyJS.bar(
            x=ranking_df.City,
            y=ranking_df.Reduction_Percent,
            text=ranking_df.Reduction_Percent,
            textposition="auto"
        )
        PlotlyJS.Plot(
            [t],
            PlotlyJS.Layout(
                title="CO₂ Reduction by City (2030 estimate)",
                xaxis=PlotlyJS.attr(title="City"),
                yaxis=PlotlyJS.attr(title="Reduction (%)")
            )
        )
    end

    callback!(app, Output("recommendations_box", "children"), Input("city_selector", "value")) do city
        f = forecast_for_city(city, city_df, city_base, df_dash)
        aqi = f.AQI[1]
        recs = String[]
        if aqi > 90
            push!(recs, "Improve public transport and traffic management.")
            push!(recs, "Increase urban greenery and tree plantation.")
        elseif aqi > 70
            push!(recs, "Promote rooftop solar energy.")
            push!(recs, "Encourage electric vehicle adoption.")
        else
            push!(recs, "Maintain clean energy practices and low emissions.")
            push!(recs, "Expand eco-friendly infrastructure.")
        end
        html_ul([html_li(r) for r in recs])
    end

    println(" Launching interactive dashboard at http://127.0.0.1:8050 ...")
    run_server(app, "127.0.0.1", debug=true)
end
