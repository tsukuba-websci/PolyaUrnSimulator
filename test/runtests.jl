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
    ssw_strategy = env -> [1, 2, 3]
    agent = Agent(5, 5, ssw_strategy)
end
