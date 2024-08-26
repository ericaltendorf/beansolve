using JuMP, HiGHS, Test

######################################################################
# Domain model

# Use this to declare struct fields which are solvable for
struct SolveVar{T}
	v::Union{T, JuMP.VariableRef}
end

struct Amt
	number::SolveVar{Float64}
	asset::String
end

struct Posting
	units::Amt
	cost::Union{Amt, Nothing}
	price::Union{Amt, Nothing}
end

struct Tx
	postings::Vector{Posting}
end

function validate_tx(tx::Tx)
	@assert length(tx.postings) > 0
	@assert all([p.cost.asset == p.price.asset for p in tx.postings
		if p.cost !== nothing && p.price !== nothing])
end

function posting_value(p::Posting, numeraire::String)
	if p.units.asset == numeraire
		return p.units.number.v
	elseif p.price !== nothing && p.price.asset == numeraire
		return p.units.number.v * p.price.number.v
	elseif p.cost !== nothing && p.cost.asset == numeraire
		return p.units.number.v * p.cost.number.v
	else
		throw(ErrorException("Can't compute value of posting: $p"))
	end
end

function balance(tx::Tx, numeraire::String)
	return sum([posting_value(p, numeraire) for p in tx.postings])
end

function set_constraints(model::Model)
	@constraint(model, balance(tx, "USD") == 0)
end

######################################################################
# Setup code for examples

function reset_model()
	model = Model(HiGHS.Optimizer)
	return model
end

function run(tx::Tx, model::Model)
	validate_tx(tx)
	set_constraints(model)
	optimize!(model)
end

# Create a "parameter" float (i.e. one with supplied, fixed value)
function par(val::Float64)
	return SolveVar{Float64}(val)
end

# Create a "variable" float (i.e., one the model will solve for)
function var(model::Model)
	@variable(model, x)
	return SolveVar{Float64}(x)
end

######################################################################
# Examples

# Infer units of an underspecified posting
model = reset_model()
missing_leg = var(model)
tx = Tx([
	Posting(Amt(par(10.0), "USD"), nothing, nothing),
	Posting(Amt(par(-5.0), "USD"), nothing, nothing),
	Posting(Amt(missing_leg, "USD"), nothing, nothing),
])
run(tx, model)
@test value(missing_leg.v) == -5.0

# Infer price (exchange rate)
model = reset_model()
exchange_rate = var(model)
tx = Tx([
	Posting(Amt(par(-10.0), "USD"), nothing, nothing),
	Posting(Amt(par(12.5), "EUR"), nothing, Amt(exchange_rate, "USD"))
])
run(tx, model)
@test value(exchange_rate.v) == 0.8

# Infer capital gains
model = reset_model()
cap_gains = var(model)
tx = Tx([
	Posting(Amt(par(1200.0), "USD"), nothing, nothing),
	Posting(Amt(par(-10.0), "HOOL"), Amt(par(100.0), "USD"), nothing),
	Posting(Amt(cap_gains, "USD"), nothing, nothing),
])
run(tx, model)
@test value(cap_gains.v) == -200.0
