module PolyaUrnSimulator

using ProgressMeter
using StatsBase

export Environment, Gene, init!, step!, ssw_strategy!, wsw_strategy!

HistoryRecord = Tuple{Int,Int}

function noreffill(x, n)
    return [deepcopy(x) for _ in 1:n]
end

struct Gene
    rho::Int
    nu::Int
    recentness::Float64
    activeness::Float64
    degree::Float64
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
    histories::Vector{Vector{Int}}

    # Gene
    gene::Gene

    # 履歴
    history::Vector{HistoryRecord}
end

function Environment(gene::Gene)
    return Environment(
        [], # urns
        [], # buffers
        [], # urn_sizes
        0,  # urn_size
        [],
        gene,
        [], # history
    )
end

"""
    init!(env::Environment, init_agents::Vector{Agent})

実験環境を初期化する

`init_agents` は必ず2体のエージェントを指定する必要がある
"""
function init!(env::Environment)
    env.urns = [[2], [1]]
    env.buffers = [[], []]
    env.urn_sizes = [1, 1]
    env.total_urn_size = 2

    for aid in enumerate([1, 2])
        # 初期エージェントが初期状態でバッファに持っているエージェントを作成
        append!(env.urns, noreffill(Int[], env.gene.nu + 1))
        append!(env.urn_sizes, zeros(env.gene.nu + 1))
        append!(env.buffers, noreffill(Int[], env.gene.nu + 1))

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
    caller::Int = get_caller(env)

    "アクションを起こされる終点のエージェント"
    called::Int = get_called(env, caller)

    append!(env.history, [(caller, called)])
    append!(env.histories[caller], [called])
    append!(env.histories[called], [caller])

    ##### <<< Model Rule (2) #####

    ##### Model Rule (5) >>> #####
    # もしcalledエージェントが今まで呼ばれたことの無いエージェント(=壺が空のエージェント)である場合
    if env.urn_sizes[called] == 0
        # nu_plus_one個のエージェントを生成
        generate_agent_count = env.gene.nu + 1
        append!(env.urns, noreffill(Int[], generate_agent_count))
        append!(env.buffers, noreffill(Int[], generate_agent_count))
        append!(env.urn_sizes, noreffill(0, generate_agent_count))

        # 生成したエージェントをcalledエージェントの壺とメモリバッファに追加
        generated_agents = collect((length(env.urns) - env.nus[called]):length(env.urns))
        append!(env.urns[called], generated_agents)
        append!(env.buffers[called], generated_agents)
        env.urn_sizes[called] += length(generated_agents)
        env.total_urn_size += length(generated_agents)
    end
    ##### <<< Model Rule (5) #####

    ##### Model Rule (3) >>> #####
    append!(env.urns[caller], noreffill(called, env.gene.rho))
    env.urn_sizes[caller] += env.gene.rho
    env.total_urn_size += env.gene.rho

    append!(env.urns[called], noreffill(caller, env.gene.rho))
    env.urn_sizes[called] += env.gene.rho
    env.total_urn_size += env.gene.rho
    ##### <<< Model Rule (3) #####

    ##### Model Rule (4) >>> #####
    # メモリバッファを交換する
    append!(env.urns[caller], env.buffers[called])
    env.urn_sizes[caller] += env.gene.nu + 1
    env.total_urn_size += env.gene.nu + 1

    append!(env.urns[called], env.buffers[caller])
    env.urn_sizes[called] += env.gene.nu + 1
    env.total_urn_size += env.gene.nu + 1

    env.buffers[caller] = get_recommendees(env, caller)
    env.buffers[callee] = get_recommendees(env, called)
    ##### <<< Model Rule (4) #####

end

function poppush!(v::Vector{T}, e::T) where {T}
    pop!(v)
    pushfirst!(v, e)
end

function get_recommendees(env::Environment, aid::Int)
    candidates = env.urns[aid] |> unique
    history = env.histories[aid]

    recentnesses = sort(candidates; by=x -> findlast(history == x)) * env.gene.recentness

    priorities = sort(recentnesses)
    return priorities[1:(env.gene.nu + 1)]
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
