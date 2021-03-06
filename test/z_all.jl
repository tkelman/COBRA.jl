#-------------------------------------------------------------------------------------------
#=
    Purpose:    Test all reactions (serial)
    Author:     Laurent Heirendt - LCSB - Luxembourg
    Date:       October 2016
=#

#-------------------------------------------------------------------------------------------

using Base.Test

if !isdefined(:includeCOBRA) includeCOBRA = true end

# output information
testFile = @__FILE__

nWorkers = 1

# create a pool and use the COBRA module if the testfile is run in a loop
if includeCOBRA

    solverName = :GLPKMathProgInterface
    connectSSHWorkers = false
    include("$(Pkg.dir("COBRA"))/src/connect.jl")

    # create a parallel pool and determine its size
    if isdefined(:nWorkers) && isdefined(:connectSSHWorkers)
        workersPool, nWorkers = createPool(nWorkers, connectSSHWorkers)
    end

    using COBRA
end

# include a common deck for running tests
include("$(Pkg.dir("COBRA"))/config/solverCfg.jl")

# change the COBRA solver
solver = changeCobraSolver(solverName, solParams)

# test a non-supported solver
@test_throws ErrorException changeCobraSolver("mySolver")

# test some functions that are known to throw errors
print_with_color(:yellow, "\n>> The following tests might throw warning messages. <<\n\n")

# test if an error is thrown when myModel.mat does not exist
@test_throws ErrorException loadModel("myModel.mat")

# test if an error is thrown when the matrix A does not exist
@test_throws ErrorException loadModel("ecoli_core_model.mat", "A")

# test if an error is thrown when the matrix A does not exist
@test_throws ErrorException loadModel("ecoli_core_model.mat", "R")

# test if an error is thrown when the struct myModel does not exist
@test_throws ErrorException loadModel("ecoli_core_model.mat", "S", "myModel")

# call other fields of the model
@test_throws ErrorException loadModel("ecoli_core_model.mat","S","model",["ubTest","lb","osense","c","b","csense","rxns","mets"])
@test_throws ErrorException loadModel("ecoli_core_model.mat","S","model",["ub","lbTest","osense","c","b","csense","rxns","mets"])
@test_throws ErrorException loadModel("ecoli_core_model.mat","S","model",["ub","lb","osense","cTest","b","csense","rxns","mets"])
@test_throws ErrorException loadModel("ecoli_core_model.mat","S","model",["ub","lb","osense","c","bTest","csense","rxns","mets"])
@test_throws ErrorException loadModel("ecoli_core_model.mat","S","model",["ub","lb","osense","c","b","csense","rxnsTest","mets"])
@test_throws ErrorException loadModel("ecoli_core_model.mat","S","model",["ub","lb","osense","c","b","csense","rxns","metsTest"])

# connect SSH workers that are not reachable
@test createPool(1, false) == (workers(),1)
@test_throws ErrorException workersPool, nWorkers = createPool(0, false)
@test_throws ErrorException workersPool, nWorkers = createPool(nWorkers+1, true)

# connect twice the same number of workers
@test createPool(4) == (workers(),4)
@test createPool(2) == (workers(),2)

# load a new version of the model
model=loadModel("ecoli_core_model.mat")

# run a model with more reactions on the reaction list than in the model
nWorkers = 1
rxnsList = 1:length(model.rxns)+1
minFlux, maxFlux, optSol, fbaSol, fvamin, fvamax, statussolmin, statussolmax = distributedFBA(model, solver, nWorkers, 90.0, "min", rxnsList)

# test preFBA! with min
optSol, fbaSol = preFBA!(model, solver, 90.0, "min")

# test if model does not have an objective (no return values)
model.c = 0.0*model.c
@test_throws MethodError optSol, fbaSol = preFBA!(model, solver, 90.0, "min")

# set a wrong solver handle
model=loadModel("ecoli_core_model.mat")
solver = changeCobraSolver(solverName, solParams)
solver.handle = -1
@test_throws ErrorException solveCobraLP(model, solver)
@test_throws ErrorException buildCobraLP(model, solver)

# test if an infeasible solution status is returned
solver = changeCobraSolver(solverName, solParams)
m = MathProgBase.HighLevelInterface.buildlp([1.0,0.0],[2.0 1.0],'<',-1.0,solver.handle)
retObj, retFlux, retStat = loopFBA(m, 1, 2)
if solverName == "Clp" || solverName == "Gurobi" || solverName == "CPLEX" || solverName == "Mosek"
    @test retStat[1] == 0 # infeasible
else
    @test retStat[1] == 5 # undocumented status
end

# load the test model
modelTest = loadModel("ecoli_core_model.mat", "S", "modelTest")
@test modelTest.osense == -1
@test modelTest.csense == fill('E',length(modelTest.b))

# test buildlp and solvelp for an unbounded problem
m = MathProgBase.HighLevelInterface.buildlp([-1.0,-1.0],[-1.0 2.0],'<',[0.0],solver.handle)
sol = MathProgBase.HighLevelInterface.solvelp(m)
if solver.name == "Clp" || solver.name == "Gurobi" || solver.name == "GLPK" || solver.name == "Mosek"
    @test sol.status == :Unbounded
elseif solverName == "CPLEX"
    @test sol.status == :InfeasibleOrUnbounded
end

# solve an unbounded problem using loopFBA
m = MathProgBase.HighLevelInterface.buildlp([0.0,-1.0],[-1.0 2.0],'<',[0.0],solver.handle)
retObj, retFlux, retStat = loopFBA(m, 1, 2, 2, 1)
if solver.name == "Clp" || solver.name == "Gurobi" || solver.name == "GLPK" || solver.name == "Mosek"
    @test retStat == [2, -1] # unbounded and not solved
elseif solver.name == "CPLEX"
    @test retStat == [4, -1] # unbounded and not solved
end
