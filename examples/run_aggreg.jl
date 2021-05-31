using Logging

push!(LOAD_PATH, dirname(@__DIR__))
using EnergySystemModeling

@info "Creating aggreg_TS directory"
output_dir = "aggreg_out"

mkpath(output_dir)

@info "Loading parameters"
constants_path = "examples//constants"
structure = "8nodes"
structures_path = joinpath("examples//structures",structure)
instance = "small"
instances_path = joinpath(structures_path,"instances",instance)

parameters = Params(constants_path, instances_path)

@info "Creating clusters"
# Number of availability series to be considered in the clustering:
navail = 3;

dnt = transpose(parameters.D_nt)./repeat(transpose(maximum(parameters.D_nt[:,h] for h in 1:size(transpose(parameters.D_nt),1))),8760) |> Array{Float64};

series = hcat(dnt, reshape(permutedims(parameters.A_gnt[1:navail,:,:],[3,1,2]),(size(dnt,1),navail*size(dnt,2)))) |> Array{Float64};

block_size = 2
stopping_k = 1
current_k = size(series,1)
dm = :ward
rep_value = :mean
lseries = size(series,1)
nseries = size(series,2);

# Testing set: ClustInstance
k_cent = copy(series)
weights = ones(lseries) |> Vector{Int}
series_clust = collect(1:lseries)
nclusters = lseries
search_range = 1:(1+lseries-block_size);

global _SeriesInstance = load_series_instance(series,
    block_size,
    current_k,
    stopping_k,
    dm,
    rep_value,
    lseries,
    nseries);

global _ClustInstance = load_clust_instance(k_cent,
    series_clust,
    weights,
    search_range);

k = nclusters

# Dictionary to keep the min distances and respective markers/min_dist found in each iteration
_DistUpdate = Dict{Vector{Bool}, DistUpdate}()

# Dictionaries to store ClustInstance and SeriesInstance
_ClustUpdate = Dict{Int64,ClustInstance}()
_SeriesUpdate = Dict{Int64,SeriesInstance}()

# Define a copy function to get a snapshot of the structs
Base.copy(x::T) where T = T([getfield(x, k) for k ∈ fieldnames(T)]...)

while k >= stopping_k + block_size - 1
    global (k, _DistUpdate) = find_clusters!(_SeriesInstance, _ClustInstance, _DistUpdate)
    
    # Store series_clust and k_cent
    global _ClustUpdate = merge(+,_ClustUpdate,Dict("$k" => copy(_ClustInstance)))
    global _SeriesUpdate = merge(+,_SeriesUpdate,Dict("$k" => copy(_SeriesInstance)))

    if k%10 == 0
        # Saving each 20 steps
        save(joinpath(output_dir,"preliminary","clust_prelim_out.jld2"), _ClustUpdate)
        save(joinpath(output_dir,"preliminary","series_prelim_out.jld2"), _SeriesUpdate)
    end

    if k%1000 == 0
        @info string("Last update: ",round((1 - k/lseries) * 100),"% @ ", now(), ".")
    end
end

save(joinpath(output_dir,"clust_out.jld2"), _ClustUpdate)
save(joinpath(output_dir,"series_out.jld2"), _SeriesUpdate)

# Define a copy function to get a snapshot of the structs
Base.copy(x::T) where T = T([getfield(x, k) for k ∈ fieldnames(T)]...)