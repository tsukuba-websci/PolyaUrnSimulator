module PolyaUrnSimulator

using ProgressMeter
using StatsBase

export SSW!,
    WSW!, run_simulation, Environment, Agent, init!, step!, ssw_strategy!, wsw_strategy!

HistoryRecord = Tuple{Int,Int}

mutable struct Environment
    # 環境の状態
    urns::Vector{Vector{Int}}
    buffers::Vector{Vector{Int}}
    urn_sizes::Vector{Int}
    total_urn_size::Int

    # Agent
    rhos::Vector{Int}
    nus::Vector{Int}
    nu_plus_ones::Vector{Int}
    strategies::Vector{Function}

    # 履歴
    history::Vector{HistoryRecord}

    # 環境の振る舞い
    get_caller::Function
    who_update_buffer
end

function Environment(; get_caller=get_caller, who_update_buffer::Symbol=:both)
    begin
        if !(who_update_buffer ∈ [:both, :caller, :called])
            throw(ArgumentError("who_update_bufferは `:both` `:caller` `:called` のいずれかです"))
        end

        Environment(
            [], # urns
            [], # buffers
            [], # urn_sizes
            0,  # urn_size
            [], # rhos
            [], # nus
            [], # nu_plus_ones
            [], # strategies
            [], # history
            get_caller,
            who_update_buffer,
        )
    end
end

struct Agent
    rho::Int
    nu::Int
    strategy::Function
    nu_plus_one::Int

    Agent(rho::Int, nu::Int, strategy::Function) = begin
        new(rho, nu, strategy, nu + 1)
    end
end

function init!(env::Environment, init_agents::Vector{Agent})
    if length(init_agents) != 2
        throw(ArgumentError("初期エージェントは必ず2体です"))
    end

    env.urns = [[2], [1]]
    env.buffers = [[], []]
    env.urn_sizes = [1, 1]
    env.total_urn_size = 2

    env.rhos = map(a -> a.rho, init_agents)
    env.nus = map(a -> a.nu, init_agents)
    env.nu_plus_ones = map(a -> a.nu_plus_one, init_agents)
    env.strategies = map(a -> a.strategy, init_agents)

    for (aid, agent) in enumerate(init_agents)
        # 初期エージェントが初期状態でバッファに持っているエージェントを作成
        append!(env.urns, fill(Int[], agent.nu_plus_one))
        append!(env.urn_sizes, zeros(agent.nu_plus_one))
        append!(env.buffers, fill(Int[], agent.nu_plus_one))
        # TODO: 初期値以外の値を持ったエージェントを追加できるようにする
        append!(env.rhos, fill(env.rhos[1], agent.nu_plus_one))
        append!(env.nus, fill(env.nus[1], agent.nu_plus_one))
        append!(env.nu_plus_ones, fill(env.nu_plus_ones[1], agent.nu_plus_one))
        append!(env.strategies, fill(env.strategies[1], agent.nu_plus_one))

        # 初期エージェントが初期状態でバッファに持っているエージェントを設定
        init_potential_agent_ids = collect((length(env.urns) - agent.nu):length(env.urns))
        append!(env.urns[aid], init_potential_agent_ids)
        append!(env.buffers[aid], init_potential_agent_ids)
        env.urn_sizes[aid] += length(init_potential_agent_ids)
        env.total_urn_size += length(init_potential_agent_ids)
    end
end

function step!(env::Environment)
    ##### Model Rule (2) >>> #####
    "アクションを起こす起点のエージェント"
    caller::Int = env.get_caller(env)

    "アクションを起こされる終点のエージェント"
    called::Int = get_called(env, caller)

    append!(env.history, [(caller, called)])
    ##### <<< Model Rule (2) #####

    ##### Model Rule (5) >>> #####
    # もしcalledエージェントが今まで呼ばれたことの無いエージェント(=壺が空のエージェント)である場合
    if env.urn_sizes[called] == 0
        # nu_plus_one個のエージェントを生成
        for _ in 1:env.nu_plus_ones[called]
            append!(env.urns, Vector{Int}[Int[]])
            append!(env.buffers, Vector{Int}[Int[]])
            append!(env.urn_sizes, Int[0])

            # TODO: 初期値以外の値を持ったエージェントを追加できるようにする
            append!(env.rhos, [env.rhos[1]])
            append!(env.nus, [env.nus[1]])
            append!(env.nu_plus_ones, [env.nu_plus_ones[1]])
            append!(env.strategies, [env.strategies[1]])
        end

        # 生成したエージェントをcalledエージェントの壺とメモリバッファに追加
        generated_agents = collect((length(env.urns) - env.nus[called]):length(env.urns))
        append!(env.urns[called], generated_agents)
        append!(env.buffers[called], generated_agents)
        env.urn_sizes[called] += length(generated_agents)
        env.total_urn_size += length(generated_agents)
    end
    ##### <<< Model Rule (5) #####

    ##### Model Rule (3) >>> #####
    append!(env.urns[caller], fill(called, env.rhos[caller]))
    env.urn_sizes[caller] += env.rhos[caller]
    env.total_urn_size += env.rhos[caller]

    append!(env.urns[called], fill(caller, env.rhos[called]))
    env.urn_sizes[called] += env.rhos[called]
    env.total_urn_size += env.rhos[called]
    ##### <<< Model Rule (3) #####

    ##### Model Rule (4) >>> #####
    # メモリバッファを交換する
    append!(env.urns[caller], env.buffers[called])
    env.urn_sizes[caller] += env.nu_plus_ones[called]
    env.total_urn_size += env.nu_plus_ones[called]

    append!(env.urns[called], env.buffers[caller])
    env.urn_sizes[called] += env.nu_plus_ones[caller]
    env.total_urn_size += env.nu_plus_ones[caller]

    # メモリバッファを更新する
    if env.who_update_buffer ∈ [:caller, :both]
        env.strategies[caller](env, caller)
    end
    if env.who_update_buffer ∈ [:called, :both]
        env.strategies[called](env, called)
    end
    ##### <<< Model Rule (4) #####

end

function poppush!(v::Vector{T}, e::T) where {T}
    pop!(v)
    pushfirst!(v, e)
end

function SSW!(_::Int, buffer::Vector{Int}, urn::Vector{Int}, exchanged::Int)
    if !(exchanged in buffer)
        poppush!(buffer, exchanged)
    end
end

function ssw_strategy!(env::Environment, aid::Int)
    _last::Tuple{Int,Int} = last(env.history)
    exchanged = _last[1] == aid ? _last[2] : _last[1]
    if !(exchanged in env.buffers[aid])
        poppush!(env.buffers[aid], exchanged)
    end
end

function WSW!(buffer_size::Int, buffer::Vector{Int}, urn::Vector{Int}, exchanged::Int)
    set = Set{Int}()
    while length(set) != buffer_size
        push!(set, rand(urn))
    end
    buffer .= collect(set)
end

function wsw_strategy!(env::Environment, aid::Int)
    env.buffers[aid] .= sample(env.urns[aid], env.nu_plus_ones[aid]; replace=false)
end

"""
アクションの呼び出され側ノードを選ぶ
アクションの呼び出し側ノードの壺内からランダムに1個選び出す
"""
function get_called(env::Environment, caller::Int)::Int
    caller_urns::Vector{Int} = env.urns[caller]
    while true
        called = rand(caller_urns)
        if called != caller
            return called
        end
    end
    throw(BoundsError())
end

"""
アクションの呼び出し側ノードを選ぶ
各々のノードが持つ壺の重さに比例する確率でノードを選ぶ
"""
function get_caller(env::Environment)::Int
    # 壺のサイズに基づいてインタラクションの起点ノードを選択
    return sample(Weights(env.urn_sizes))
end

function interact!(
    rho::Int,
    nu_plus_one::Int,
    strategy!::Function,
    node_urns::Vector{Vector{Int}},
    node_buffers::Vector{Vector{Int}},
    node_urn_sizes::Vector{Int},
    total_urn_size::Int,
    history::Vector{Tuple{Int,Int}};
    async_strategy::Bool=false,
    get_caller::Function,
)
    ##### Model Rule (2) >>> #####

    "アクションを起こす起点のノード"
    caller = get_caller(node_urn_sizes)

    "アクションを起こされる終点のノード"
    called = get_called(node_urns[caller], caller)

    append!(history, [(caller, called)])

    ##### <<< Model Rule (2) #####

    ##### Model Rule (5) >>> #####

    # もしcalledノードが今まで呼ばれたことの無いノード(=壺が空のノード)である場合
    if node_urn_sizes[called] == 0

        # nu_plus_one個のノードを生成
        for _ in 1:nu_plus_one
            append!(node_urns, Vector{Int}[Int[]])
            append!(node_buffers, Vector{Int}[Int[]])
            append!(node_urn_sizes, Int[0])
        end

        # 生成したノードをcalledノードの壺とメモリバッファに追加
        for i in 1:nu_plus_one
            idx = length(node_urns) - (i - 1)
            append!(node_urns[called], Int[idx])
            append!(node_buffers[called], Int[idx])
            node_urn_sizes[called] += 1
            total_urn_size += 1
        end
    end

    ##### <<< Model Rule (5) #####

    ##### Model Rule (3) >>> #####
    append!(node_urns[caller], fill(called::Int, rho))
    node_urn_sizes[caller] += rho
    total_urn_size += rho

    append!(node_urns[called], fill(caller::Int, rho))
    node_urn_sizes[called] += rho
    total_urn_size += rho

    ##### <<< Model Rule (3) #####

    ##### Model Rule (4) >>> #####
    # メモリバッファを交換する
    append!(node_urns[caller], node_buffers[called])
    node_urn_sizes[caller] += nu_plus_one
    total_urn_size += nu_plus_one

    append!(node_urns[called], node_buffers[caller])
    node_urn_sizes[called] += nu_plus_one
    total_urn_size += nu_plus_one

    # メモリバッファを更新する
    strategy!(nu_plus_one, node_buffers[caller], node_urns[caller], called)
    if !async_strategy # async_strategyモードのときは、呼び出し側のノードのみがメモリバッファを更新する
        strategy!(nu_plus_one, node_buffers[called], node_urns[called], caller)
    end
    ##### <<< Model Rule (4) #####
end

"""壺モデルを最初から走らせる
## returns
`(history, node_urns, node_buffers)`
"""
function run_simulation(
    rho::Int,
    nu::Int,
    strategy!::Function,
    steps::Int;
    get_caller::Function=get_caller,
    async_strategy::Bool=false,
    show_progress::Bool=true,
)
    nu_plus_one = nu + 1

    ##### Model Rule (1) >>> #####

    # 初期値の設定
    "壺"
    node_urns::Vector{Vector{Int}} = [[2], [1]]

    "メモリバッファ"
    node_buffers::Vector{Vector{Int}} = [Int[], Int[]]

    "壺のサイズ"
    node_urn_sizes = Int[1, 1]

    "系内に存在する全ての壺のサイズの合計" # 系内のノードの壺サイズを全て毎回計算すると計算時間がかかるので、保持しておく
    total_urn_size::Int = 2 # 最初は2つのノードがそれぞれお互いを持っているので 2

    "履歴"
    history = Tuple{Int,Int}[]

    # 初期ノードが初期状態でメモリバッファに持っているノードを作成
    for i in 1:(2 * nu_plus_one)
        push!(node_urns, Int[])
        push!(node_urn_sizes, 0)
        push!(node_buffers, Int[])
    end

    # 初期ノードが初期状態でメモリバッファに持っているノードを設定
    for i in 1:nu_plus_one
        push!(node_urns[1], 2 + i)
        node_urn_sizes[1] += 1
        total_urn_size += 1
        push!(node_urns[2], 2 + i + nu_plus_one)
        node_urn_sizes[2] += 1
        total_urn_size += 1

        push!(node_buffers[1], 2 + i)
        push!(node_buffers[2], 2 + i + nu_plus_one)
    end

    ##### <<< Model Rule (1) #####

    p = Progress(length(1:steps); showspeed=true, enabled=show_progress)

    @inbounds @simd for _ in 1:steps
        interact!(
            rho,
            nu_plus_one,
            strategy!,
            node_urns,
            node_buffers,
            node_urn_sizes,
            total_urn_size,
            history;
            async_strategy=async_strategy,
            get_caller=get_caller,
        )
        ProgressMeter.next!(p)
    end

    return (history, node_urns, node_buffers)
end

"""壺モデルを途中から走らせる
## returns
`(history, node_urns, node_buffers)`
"""
function run_simulation(
    rho::Int,
    nu_plus_one::Int,
    strategy!::Function,
    node_urns::Vector{Vector{Int}},
    node_buffers::Vector{Vector{Int}},
    steps::Int;
    async_strategy::Bool=false,
    show_progress::Bool=true,
)
    node_urn_sizes::Vector{Int} = map(length, node_urns)
    total_urn_size::Int = sum(node_urn_sizes)

    history::Vector{Tuple{Int,Int}} = Tuple{Int,Int}[]

    p = Progress(steps; showspeed=true, enabled=show_progress)

    for _ in 1:steps
        interact!(
            rho,
            nu_plus_one,
            strategy!,
            node_urns,
            node_buffers,
            node_urn_sizes,
            total_urn_size,
            history;
            async_strategy=async_strategy,
        )
        next!(p)
    end

    return (history, node_urns, node_buffers)
end

end
