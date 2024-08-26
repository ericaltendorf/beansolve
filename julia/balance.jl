using JuMP, HiGHS, Test

######################################################################
# Infra

# Use this to declare struct fields which are solvable for
struct SolveVar{T}
	v::Union{T, JuMP.VariableRef}
end

# Use this to mark instance fields as to be solved for
function unk(model::Model)
	@variable(model, x)
	return SolveVar{Float64}(x)
end

######################################################################
# Domain

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

function posting_value(p::Posting, numeraire::String)
	if p.units.asset == numeraire
		return p.units.number.v
	else
		return 0.0
	end
end

function balance_by_asset(tx::Tx, asset::String)
	postings = [p for p in tx.postings if p.units.asset == asset]
	if length(postings) == 0
		return 0
	else
		return sum([posting_value(p, asset) for p in postings])
	end
end

function set_constraints(model::Model)
	@constraint(model, balance_by_asset(tx, "USD") == 0)
end

######################################################################
# Examples

model = Model(HiGHS.Optimizer)

# Two known transactions and one variable to solve for
expect_n5 = unk(model)
tx = Tx([
	Posting(Amt(SolveVar{Float64}(10.0), "USD"), nothing, nothing
	),
	Posting(Amt(SolveVar{Float64}(-5.0), "USD"), nothing, nothing
	),
	Posting(Amt(expect_n5, "USD"), nothing, nothing
	)
])
set_constraints(model)
optimize!(model)

@test value(expect_n5.v) == -5.0