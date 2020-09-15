########################################################################################
# Post-Processing: Smoothing and uncertainty calibration
########################################################################################
function calibrate!(integ::ODEFilterIntegrator)

    @unpack state_estimates, sigmas = integ
    for s in state_estimates
        s.Σ .*= sigmas[end]
    end
end




function smooth_all!(integ::ODEFilterIntegrator)

    @unpack state_estimates, times, sigmas = integ
    @unpack A!, Q! = integ.constants
    @unpack Ah, Qh = integ.cache
    # x_pred is just used as a cache here

    for i in length(state_estimates)-1:-1:2
        dt = times[i+1] - times[i]
        A!(Ah, dt)
        Q!(Qh, dt, sigmas[i])
        # @info "Smoothing" i dt sigmas[i] sigmas[i]==0
        smooth!(state_estimates[i], state_estimates[i+1], Ah, Qh, integ)
    end
end


function smooth(x_curr, x_next, Ah, Qh, integ)
    x_out = copy(x_curr)
    smooth!(x_out, x_next, Ah, Qh, integ)
    return x_out
end
function smooth!(x_curr, x_next, Ah, Qh, integ)
    # x_curr is the state at time t_n (filter estimate) that we want to smooth
    # x_next is the state at time t_{n+1}, already smoothed, which we use for smoothing

    @unpack d, q = integ.constants
    @unpack x_tmp = integ.cache
    x_pred = x_tmp


    # Prediction: t -> t+1
    mul!(x_pred.μ, Ah, x_curr.μ)
    x_pred.Σ .= Ah * x_curr.Σ * Ah' .+ Qh


    # Smoothing
    P = copy(x_curr.Σ)
    try
        inv(Symmetric(x_pred.Σ))
    catch
        @warn "Inverse not working" x_pred.Σ x_curr.Σ x_next.Σ
        IP = integ.constants.InvPrecond
        @info "Without the preconditioning:" IP*x_pred.Σ*IP' IP*x_curr.Σ*IP' IP*x_next.Σ*IP'
    end
    P_p_inv = inv(Symmetric(x_pred.Σ))
    G = x_curr.Σ * Ah' * P_p_inv
    x_curr.μ .+= G * (x_next.μ .- x_pred.μ)

    # Vanilla:
    # x_curr.Σ .+= G * (x_next.Σ .- x_pred.Σ) * G'
    # Joseph-Form:
    P = copy(x_curr.Σ)
    C_tilde = Ah
    K_tilde = P * Ah' * P_p_inv
    P_s = ((I - K_tilde*C_tilde) * P * (I - K_tilde*C_tilde)'
           + K_tilde * Qh * K_tilde' + G * x_next.Σ * G')
    x_curr.Σ .= P_s


    # Sanity: Make sure that the diagonal of P is non-negative
    minval = minimum(diag(x_curr.Σ))
    if abs(minval) < eps(eltype(x_curr.Σ))
    # if abs(minval) < 1e-12
        for i in 1:(d*(q+1))
            x_curr.Σ[i,i] -= minval
        end
    end
    minval = minimum(diag(x_curr.Σ))
    if minval < 0
        @info "Error while smoothing: negative variances!" P x_pred.Σ x_next.Σ x_curr.Σ Ah Qh G
        @info "Solver used" integ.constants.q integ.sigma_estimator integ.steprule integ.smooth

        display(P)
        # display((I - K_tilde*C_tilde) * P * (I - K_tilde*C_tilde)')
        # display(K_tilde * Qh * K_tilde')
        # display(G * x_next.Σ * G')

        error("Encountered negative variances during smoothing")
    end
    @assert all(diag(x_curr.Σ) .>= 0) "The covariance `P` might be NaN! Make sure that the covariances during the solve make sense."

    return nothing
end


"""Vanilla SMOOTH, without fancy checks or pre-allocation

Use this to test any "advanced" implementation against.
Requires the PREDICTed state.
"""
function smooth(x_curr::Gaussian, x_next_pred::Gaussian, x_next_smoothed::Gaussian, Ah::AbstractMatrix)

    P_p_inv = inv(Symmetric(x_next_pred.Σ))
    Gain = x_curr.Σ * Ah' * P_p_inv

    x_curr_smoothed = Gaussian(
        x_curr.μ + Gain * (x_next_smoothed.μ - x_next_pred.μ),
        x_curr.Σ + Gain * (x_next_smoothed.Σ - x_next_pred.Σ) * Gain'
    )
    return x_curr_smoothed, Gain
end
