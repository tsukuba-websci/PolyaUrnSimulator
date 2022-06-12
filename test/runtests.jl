using PolyaUrnSimulator
using Test

function return_type_test(result)
    @test typeof(result[1]) == Vector{Tuple{Int,Int}}
    @test typeof(result[2]) == Vector{Vector{Int}}
    @test typeof(result[3]) == Vector{Vector{Int}}
end

@testset "SSWの通常モードでシミュレーションを実行" begin
    result = run_simulation(5, 5, SSW!, 100)

    # 返り値の型があっているかチェック
    return_type_test(result)

    # 履歴の長さがあっているかチェック
    @test length(result[1]) == 100
end

@testset "WSWの通常モードでシミュレーションを実行" begin
    result = run_simulation(5, 5, WSW!, 100)

    # 返り値の型があっているかチェック
    return_type_test(result)

    # 履歴の長さがあっているかチェック
    @test length(result[1]) == 100
end

@testset "Environment構造体の初期化" begin
    @testset "Environmentを初期化できる" begin
        env = Environment()
        @test typeof(env) <: Environment
    end

    @testset "Environmentにget_callerを渡せる" begin
        _get_caller = env -> 1
        env = Environment(; get_caller=_get_caller)
        @test typeof(env) <: Environment
    end

    @testset "who_update_bufferに予期しない値を入れると例外をスローする" begin
        @test_throws ArgumentError Environment(who_update_buffer=:boo)
    end
end

@testset "Agent構造体の初期化" begin
    strategy = env -> [1, 2, 3]
    agent = Agent(5, 5, strategy)

    @test agent.rho == 5
    @test agent.nu == 5
    @test agent.nu_plus_one == 6
end

@testset "実験環境を準備する" begin
    @testset "初期状態に到達できる(1)" begin
        strategy = env -> [1, 2, 3]
        env = Environment()
        init_agents = [Agent(2, 2, strategy), Agent(2, 2, strategy)]
        init!(env, init_agents)

        @test env.urns == [[2, 3, 4, 5], [1, 6, 7, 8], [], [], [], [], [], []]
        @test env.buffers == [[3, 4, 5], [6, 7, 8], [], [], [], [], [], []]
        @test env.urn_sizes == [4, 4, 0, 0, 0, 0, 0, 0]
        @test env.total_urn_size == 8
    end

    @testset "初期状態に到達できる(2)" begin
        strategy = env -> [1, 2, 3]
        env = Environment()
        init_agents = [Agent(1, 1, strategy), Agent(1, 1, strategy)]
        init!(env, init_agents)

        @test env.urns == [[2, 3, 4], [1, 5, 6], [], [], [], []]
        @test env.buffers == [[3, 4], [5, 6], [], [], [], []]
        @test env.urn_sizes == [3, 3, 0, 0, 0, 0]
        @test env.total_urn_size == 6
    end

    @testset "初期エージェントが2体ではないときは例外をスローする" begin
        strategy = env -> [1, 2, 3]
        env = Environment()
        init_agents = [Agent(1, 1, strategy)]
        @test_throws ArgumentError init!(env, init_agents)
    end
end
