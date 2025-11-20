
const DATA_DIR  = joinpath(pwd(), "data")
const PLOTS_DIR = joinpath(pwd(), "plots")


mkpath(DATA_DIR)
mkpath(PLOTS_DIR)

formatnum(x; digits=2) = round(x, digits=digits)
