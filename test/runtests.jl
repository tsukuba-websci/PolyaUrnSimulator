using PolyaUrnSimulator
using Test

@testset "初期状態に到達できる" begin
    gene = Gene(1, 1, 0.1, 0.1, 0.1)
    env = Environment(gene)
    init!(env)

    @test length(env.urns) == 6
    @test env.urns[1] == [2, 3, 4]
    @test env.urns[2] == [1, 5, 6]
    @test env.urns[3] == []
end

@testset "1回相互作用できる" begin
    @testset "最近性のみを見る場合" begin
        gene = Gene(
            1, # rho
            1, # nu
            1, # recentness
            0, # activeness
            0, # degree
        )
        env = Environment(gene)
        init!(env)

        interact!(env, 1, 2)

        @test env.buffers[1] == [2, 6]
        @test env.buffers[2] == [1, 4]
    end
end

@testset "100回相互作用できる" begin
    @testset "最近性のみを見る場合" begin
        gene = Gene(
            1, # rho
            1, # nu
            1, # recentness
            0, # activeness
            0, # degree
        )
        env = Environment(gene)
        init!(env)

        for _ in 1:100
            step!(env)
        end
    end
end

@testset "10000回相互作用できる" begin
    gene = Gene(
        1, # rho
        1, # nu
        1, # recentness
        0, # activeness
        0, # degree
    )
    env = Environment(gene)
    init!(env)

    @time for _ in 1:10000
        step!(env)
    end
end
