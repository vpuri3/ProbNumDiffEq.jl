
function DiffEqBase.__init(
    prob::DiffEqBase.AbstractODEProblem{uType,tType,false},
    alg::AbstractEK,
    timeseries_init=(),
    ts_init=(),
    ks_init=(),
    recompile::Type{Val{recompile_flag}}=Val{true};
    kwargs...,
) where {uType,tType,recompile_flag}
    @warn "The given problem is in out-of-place form. Since the algorithms in this " *
          "package are written for in-place problems, it will be automatically converted."
    if prob.f isa DynamicalODEFunction
        if !(prob.problem_type isa SecondOrderODEProblem)
            error(
                "DynamicalODEProblems that are not SecondOrderODEProblems " *
                "are currently not supported",
            )
        end
        f1!(dv, v, u, p, t) = dv .= prob.f.f1(v, u, p, t)
        # f2!(du, v, u, p, t) = du .= prob.f.f2(v, u, p, t)
        _prob = SecondOrderODEProblem(
            f1!,
            # f2!,
            prob.u0.x[1],
            prob.u0.x[2],
            prob.tspan,
            prob.p;
            prob.kwargs...,
        )
    else
        f!(du, u, p, t) = du .= prob.f(u, p, t)
        _prob = ODEProblem(
            ODEFunction(
                f!,
                jac=isnothing(prob.f.jac) ? nothing :
                    (ddu, u, p, t) -> ddu .= prob.f.jac(u, p, t),
                analytic=prob.f.analytic,
            ),
            prob.u0,
            prob.tspan,
            prob.p;
            prob.kwargs...,
        )
    end
    return DiffEqBase.__init(
        _prob,
        alg,
        timeseries_init,
        ts_init,
        ks_init,
        recompile;
        kwargs...,
    )
end
