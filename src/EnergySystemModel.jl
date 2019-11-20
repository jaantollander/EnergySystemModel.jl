module EnergySystemModel

using JuMP

export Specs, energy_system_model

"""Specs"""
struct Specs
    investment_planning::Bool  # Capcity expansion
    economic_dispatch::Bool
    unit_commitment::Bool
    ramping_limits::Bool  # SU & SD costs
    voltage_angles::Bool
    security_level::Bool
    storage::Bool
end

"""Create energy system model."""
function energy_system_model(
        specs::Specs,
        Tech::Vector{Int64},    # Technologies set
        Nodes::Vector{Int64},   # Nodes set
        Lines::Vector{Int64},   # Trans. lines set
        Tsteps::Vector{Int64},  # Time steps set
        g_min::Vector{Float64}, # Min generation threshold
        B::Vector{Float64},     # Susceptance
        rup::Vector{Float64},   # Ramp up limits
        rdw::Vector{Float64},   # Ramp down limits
        GC::Vector{Float64},    # Generation cost
        TC::Vector{Float64},    # Transmission cost
        GEC::Vector{Float64},   # Generation expansion cost
        TEC::Float64,           # Transmission expansion cost
        GFC::Vector{Float64},   # Generation fixed cost
        SUC::Vector{Float64},   # Starting up cost
        SDC::Vector{Float64},   # Shutting down cost
        TFC::Vector{Float64},   # Transmission fixed cost
        RTech::Vector{Int64},   # Renewables listing required for renewables share
        demand::Vector{Float64},# total demand of each Node at each Tstep
        RES::Float64,           # renewables share
        Tbar::Float64,          # transmission max investment
        Gbar::Vector{Float64}  # generation expansion max investment
        )::Model
    # Create an instance of JuMP model.
    model = Model()

    ## Variables
    #@variable(model, f[l in Lines, h in Tsteps])                # transmission decision
    @variable(model, 0 <= g[t in Tech, n in Nodes, h in Tsteps]) # power output of generators
    @variable(model, 0 <= gen_cap[t in Tech, n in Nodes])        # generation capacity (to be fixed)
    #@variable(model, 0 <= trans_cap[l in Lines])                # transmission capacity (to be fixed)
    @variable(model, 0 <= lol[n in Nodes, h in Tsteps])          # loss of load introduced   Having this as a common variable, applies for any case
    #@variable(model, 0 <= RES[n in Nodes])                      # Renewables share to be fixed
    #@fix_value(RES, 0.3, force = true)

    # Investment Planning
    @variable(model, 0 <= gen_inv[t in Tech, n in Nodes])  # generation expansion
    @variable(model, 0 <= trans_inv[l in Lines])           # transmission expansion
    #@variable(model, 0 <= Gbar[t in Tech])                # generation expansion budget (to be fixed)
    #@variable(model, 0 <= Tbar)                           # transmission expansion budget (to be fixed)
    #@fix_value(Gbar)
    #@fix_value(Tbar)

    # Unit Commitment
    @variable(model, u[t in Tech, n in Nodes, h in Tsteps], Bin)     # Binary status of generators
    @variable(model, z[l in Lines, h in Tsteps], Bin)                # Binary status of trans. lines
    @variable(model, su[t in Tech, n in Nodes, h in Tsteps], Bin)    # Binary var. for starting up (generation)
    @variable(model, sd[t in Tech, n in Nodes, h in Tsteps], Bin)    # Binary var. for shutting down (generation)

    # Voltage Angles
    @variable(model, 0 <= θ[n in Nodes, h in Tsteps, d in 1:2])   # Bus angles (from-to)

    # Storage
    @variable(model, 0 <= battery_level[n in Nodes, h in Tsteps])  # Battery level variable
    @variable(model, 0 <= battery_investment[n in Nodes])          # investment in Battery for each node
    #@variable(model, 0 <= battery_capacity[n in Nodes])           # Will be fixed

    ## Costs. Required for defining the objective.
    cost0 = 0
    cost1 = 0
    cost3 = 0
    cost4 = 0

    ## Constraints
    cost0 = @expression(model, sum(g[t,n,h]*GC[t] for t in Tech, n in Nodes, h in Tsteps) )#+
    #sum(f[l,h]*TC[l] for l in Lines, h in Tsteps))

    if specs.investment_planning
        # Maximum generation
        @constraint(model, [t in Tech, n in Nodes, h in Tsteps], g[t,n,h] <= gen_inv[t,n])
        # Maximum transmission
        # @constraint(model, [l in Lines, h in Tsteps], f[l,h] <= trans_inv[l])
        # Maximum transmission, negative
        # @constraint(model, [l in Lines, h in Tsteps], f[l,h] >= -trans_inv[l])
        # Maximum ge. invest.
        @constraint(model, [t in Tech], sum(gen_inv[t,n] for n in Nodes) <= Gbar[t])
        # Maximum trans. invest.
        # @constraint(model, sum(trans_inv[l] for l in Lines) <= Tbar)
        # Renewables share    #TODO doesn't work. is now limited by just having a limitation on production
        # @NLconstraint(model, [t in Tech, n in Nodes, h in Tsteps], sum(g[t,n,h] for h in Tsteps, t in RTech)/(sum(g[t,n,h] for h in Tsteps, t in Tech)) >= RES)
        @constraint(model, [t in [1,2,3], n in Nodes, h in Tsteps], sum(g[t,n,h] for h in Tsteps ) <= 600000)

        ## Expansion costs
        cost1 = @expression(model, sum(gen_inv[t,n]*GEC[t] for t in Tech, n in Nodes))# +
        #sum(trans_inv[l]*TEC for l in Lines))
    end

    # Case when battery is introduced
    if specs.investment_planning && specs.storage
        @constraint(model, [t in Tech, n in Nodes, h in Tsteps], battery_level[n,h] <= battery_investment[n])
        # Storage investments introduced TODO Include both incest and capacity

        @constraint(
            model,
            [t in Tech, n in Nodes, h in Tsteps[Tsteps.>1], l in Lines],
            demand[h] - lol[n,h] == sum(g[t,n,h] for t in Tech)
            + battery_level[n, h-1] - battery_level[n, h]
            + sum(Float64[f[l] for l in 1:length(Lines) if Lines[l][2] == n])    #Balance introduced with
            - sum(Float64[f[l] for l in 1:length(Lines) if Lines[l][1] == n])
        )
        #TODO DEMAND

        #NOTE: Outflow for Node 1:
        #sum(Float64[flow[l] for l in 1:length(Lines) if Lines[l][1] == 1])

        #Outflow for Node n:
        #sum(Float64[flow[l] for l in 1:length(Lines) if Lines[l][1] == n])
        #Inflow for Node n:
        #sum(Float64[flow[l] for l in 1:length(Lines) if Lines[l][2] == n])

        # TODO: should be given as a parameter
        battery_investment_cost = 40000 #PUT A PROPER NUMBER there TODO do properly

        cost4 = @expression(model, battery_investment[n]*battery_investment_cost )
    # elseif specs.investment_planning
    #     @constraint(model, [t in Tech, n in Nodes, h in Tsteps], #, l in Lines],
    #     demand[h] - lol[n,h] .<= sum(g[t,n,h] for t in Tech)
    #     #+ sum(Float64[f[l] for l in Lines if Lines[l][2] == n])
    #     #- sum(Float64[f[l] for l in Lines if Lines[l][1] == n])
    #     ) #TODO DEMAND
    end

    if specs.unit_commitment
        # Generation cap (depending on the investment)
        @constraint(model, [t in Tech, n in Nodes, h in Tsteps], g[t,n,h] <= gen_cap[t,n]*u[t,n,h])
        # Minimum start-up power
        @constraint(model, [t in Tech, n in Nodes, h in Tsteps], g[t,n,h] >= g_min[t]*u[t,n,h])
        # If it's commited at t-1 it cannot start up at t
        @constraint(model, [t in Tech, n in Nodes, h in Tsteps[Tsteps.>1]], 1 - u[t,n,h-1] >= su[t,n,h])
        # If it's not commited at t-1 it cannot shut down at t
        @constraint(model, [t in Tech, n in Nodes, h in Tsteps[Tsteps.>1]], u[t,n,h-1] >= sd[t,n,h])
        # Plugs u, su, and sd variables
        @constraint(model, [t in Tech, n in Nodes, h in Tsteps[Tsteps.>1]], u[t,n,h] - u[t,n,h-1] == su[t,n,h] - sd[t,n,h])

        ## Unit Commitment costs
        cost3 = @expression(model, sum(u[t,n,h].*GFC[t] for t in Tech, n in Nodes, h in Tsteps) +
            sum(su[t,n,h].*SUC[t] for t in Tech, n in Nodes, h in Tsteps) +
            sum(sd[t,n,h].*SDC[t] for t in Tech, n in Nodes, h in Tsteps) +
            sum(z[l,h].*TFC[l] for l in Lines, h in Tsteps) )
    elseif specs.economic_dispatch
        # Generation cap (depending on the investment)
        @constraint(model, [t in Tech, n in Nodes, h in Tsteps], g[t,n,h] <= gen_cap[t,n])
        # Minimum start-up power
        @constraint(model, [t in Tech, n in Nodes, h in Tsteps], g[t,n,h] >= g_min[t])
    end

    if specs.ramping_limits
        @constraint(model, [t in Tech, n in Nodes, h in Tsteps[Tsteps.>1]], g[t,n,h] - g[t,n,h-1] >= rup[t])
        @constraint(model, [t in Tech, n in Nodes, h in Tsteps[Tsteps.>1]], g[t,n,h-1] - g[t,n,h] >= rdw[t])
    end

    if specs.voltage_angles
        # Faraday law for accounting voltage angles
        @constraint(model,
            [t in Tech, l in Lines, n in Nodes, n_bar in Nodes, h in Tsteps[Tsteps.>1]],
            ( θ[n,h,1] - θ[n_bar,h,2] ) * B[l] == g[t,n,h] - g[t,n_bar,h])
    end

    ## Objective
    @objective(model, Min , cost0 + cost1 + cost3 + cost4)

    return model
end

end # module
