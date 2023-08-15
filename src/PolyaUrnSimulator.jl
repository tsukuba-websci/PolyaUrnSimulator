module PolyaUrnSimulator

using ProgressMeter
using StatsBase

export Environment, Agent, init!, step!, ssw_strategy!, wsw_strategy!

HistoryRecord = Tuple{Int,Int}

function noreffill(x, n)
    return [deepcopy(x) for _ in 1:n]
end

"""
    Environment(urns, buffers, urn_sizes, total_urn_size, rhos, nus, nu_plus_ones, strategies, history, get_caller, who_update_buffer)

実験環境を定義する
"""
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
    get_called::Function
    who_update_buffer
end

"""
    Environment(; get_caller=get_caller, who_update_buffer::Symbol=:both)

実験環境を定義する

## Parameters
- `get_caller::Function{Environment -> Int}` : 起点エージェントを選択する挙動をデフォルトから変更する
- `who_update_buffer::Symbol` : 各ステップで誰がバッファを更新するか定義 (`:both` (デフォルト) or `:caller` or `:called`) 
"""
function Environment(; get_caller=get_caller, get_called=get_called,who_update_buffer::Symbol=:both)
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
            get_called,
            who_update_buffer,
        )
    end
end

struct Agent
    rho::Int
    nu::Int
    strategy::Function
    nu_plus_one::Int

    """
        Agent(rho::Int, nu::Int, strategy::Function)

    エージェントを定義する
    """
    Agent(rho::Int, nu::Int, strategy::Function) = begin
        new(rho, nu, strategy, nu + 1)
    end
end

"""
    init!(env::Environment, init_agents::Vector{Agent})

実験環境を初期化する

`init_agents` は必ず2体のエージェントを指定する必要がある
"""
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
        append!(env.urns, noreffill(Int[], agent.nu_plus_one))
        append!(env.urn_sizes, zeros(agent.nu_plus_one))
        append!(env.buffers, noreffill(Int[], agent.nu_plus_one))
        # TODO: 初期値以外の値を持ったエージェントを追加できるようにする
        append!(env.rhos, noreffill(env.rhos[1], agent.nu_plus_one))
        append!(env.nus, noreffill(env.nus[1], agent.nu_plus_one))
        append!(env.nu_plus_ones, noreffill(env.nu_plus_ones[1], agent.nu_plus_one))
        append!(env.strategies, fill(env.strategies[1], agent.nu_plus_one))

        # 初期エージェントが初期状態でバッファに持っているエージェントを設定
        init_potential_agent_ids = collect((length(env.urns) - agent.nu):length(env.urns))
        append!(env.urns[aid], init_potential_agent_ids)
        append!(env.buffers[aid], init_potential_agent_ids)
        env.urn_sizes[aid] += length(init_potential_agent_ids)
        env.total_urn_size += length(init_potential_agent_ids)
    end
end

"""
    step!(env::Environment)

与えられた実験環境のステップを1ステップ進める
"""
function step!(env::Environment)
    ##### Model Rule (2) >>> #####
    "アクションを起こす起点のエージェント"
    caller::Int = env.get_caller(env)

    "アクションを起こされる終点のエージェント"
    called::Int = env.get_called(env, caller)
    ##### <<< Model Rule (2) #####

    ##### Model Rule (5) >>> #####
    # もしcalledエージェントが今まで呼ばれたことの無いエージェント(=壺が空のエージェント)である場合
    if env.urn_sizes[called] == 0
        # nu_plus_one個のエージェントを生成
        generate_agent_count = env.nu_plus_ones[called]
        append!(env.urns, noreffill(Int[], generate_agent_count))
        append!(env.buffers, noreffill(Int[], generate_agent_count))
        append!(env.urn_sizes, noreffill(0, generate_agent_count))

        # TODO: 初期値以外の値を持ったエージェントを追加できるようにする
        append!(env.rhos, noreffill(env.rhos[1], generate_agent_count))
        append!(env.nus, noreffill(env.nus[1], generate_agent_count))
        append!(env.nu_plus_ones, noreffill(env.nu_plus_ones[1], generate_agent_count))
        append!(env.strategies, fill(env.strategies[1], generate_agent_count))

        # 生成したエージェントをcalledエージェントの壺とメモリバッファに追加
        generated_agents = collect((length(env.urns) - env.nus[called]):length(env.urns))
        append!(env.urns[called], generated_agents)
        append!(env.buffers[called], generated_agents)
        env.urn_sizes[called] += length(generated_agents)
        env.total_urn_size += length(generated_agents)
    end
    ##### <<< Model Rule (5) #####

    ##### Model Rule (4) >>> #####
    if !((caller, called) ∈ env.history) && !((called, caller) ∈ env.history)

        # If the strategy is WSW, the memory buffer should be calculated before the exchange
        if (env.strategies[caller] == wsw_strategy!) & (env.strategies[called] == wsw_strategy!) # if it is the wsw_strategy
            if env.who_update_buffer ∈ [:caller, :both]
                    env.strategies[caller](env, caller)
            end
            if env.who_update_buffer ∈ [:called, :both]
                    env.strategies[called](env, called)
            end
        end

        # メモリバッファを交換する
        append!(env.urns[caller], env.buffers[called])
        env.urn_sizes[caller] += env.nu_plus_ones[called]
        env.total_urn_size += env.nu_plus_ones[called]

        append!(env.urns[called], env.buffers[caller])
        env.urn_sizes[called] += env.nu_plus_ones[caller]
        env.total_urn_size += env.nu_plus_ones[caller]

        # If the strategy is SSW, the memory buffer should be updated after each interaction
        if (env.strategies[caller] == ssw_strategy!) & (env.strategies[called] == ssw_strategy!)
            if env.who_update_buffer ∈ [:caller, :both]
                env.strategies[caller](env, caller)
            end
            if env.who_update_buffer ∈ [:called, :both]
                env.strategies[called](env, called)
            end
        end
    end
    ##### <<< Model Rule (4) #####

    ##### Model Rule (3) >>> #####
    append!(env.urns[caller], noreffill(called, env.rhos[caller]))
    env.urn_sizes[caller] += env.rhos[caller]
    env.total_urn_size += env.rhos[caller]

    append!(env.urns[called], noreffill(caller, env.rhos[called]))
    env.urn_sizes[called] += env.rhos[called]
    env.total_urn_size += env.rhos[called]
    ##### <<< Model Rule (3) #####

    append!(env.history, [(caller, called)])

end

function poppush!(v::Vector{T}, e::T) where {T}
    pop!(v)
    pushfirst!(v, e)
end

function ssw_strategy!(env::Environment, aid::Int)
    if length(env.history) > 0
        _last::Tuple{Int,Int} = last(env.history)
        exchanged = _last[1] == aid ? _last[2] : _last[1]
        if !(exchanged in env.buffers[aid])
            poppush!(env.buffers[aid], exchanged)
        end
    end
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

end
