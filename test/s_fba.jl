#-------------------------------------------------------------------------------------------
#=
    Purpose:    Test a single FBA
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

# load an external mat file
model = loadModel("ecoli_core_model.mat", "S", "model")

modelOrig = model

nWorkers = 1
rxnsList = 13
rxnsOptMode = 1  # maximization

# -------------------------------------------------------------------------------------

for s = 0:2

    # launch the distributedFBA process
    startTime   = time()
    minFlux, maxFlux, optSol, fbaSol, fvamin, fvamax, statussolmin, statussolmax = distributedFBA(model, solver, nWorkers, 10.0, "min", rxnsList, s, rxnsOptMode, false)
    solTime = time() - startTime

    # Test numerical values - test on ceil as different numerical precision with different solvers
    @test ceil(maximum(maxFlux)) == 1.0
    @test ceil(minimum(maxFlux)) == 0.0
    @test ceil(maximum(minFlux)) == 0.0
    @test ceil(minimum(minFlux)) == 0.0
    @test ceil(norm(maxFlux))    == 1.0
    @test ceil(norm(minFlux))    == 0.0
    @test abs((model.c'*fbaSol)[1] - optSol) < 1e-9

    # print a solution summary
    printSolSummary(testFile, optSol, maxFlux, minFlux, solTime, nWorkers, solverName)
end

# -------------------------------------------------------------------------------------

# reload an external mat file
model = modelOrig

# launch the distributedFBA process with only 1 reaction
startTime   = time()
minFlux, maxFlux, optSol  = distributedFBA(model, solver, nWorkers, 100.0, "", rxnsList, 0, rxnsOptMode, false);
solTime = time() - startTime

fbaSolution = solveCobraLP(model, solver)  # in the model, objective is assumed to be maximized
fbaObj = fbaSolution.objval
fbaSol = fbaSolution.sol

@test abs(maxFlux[rxnsList] - fbaObj) < 1e-9

# print a solution summary
printSolSummary(testFile, optSol, maxFlux, minFlux, solTime, nWorkers, solverName)

# -------------------------------------------------------------------------------------

# reload an external mat file
model = modelOrig

model.osense = 1  # minimization - in the model, objective is assumed to be maximized
rxnsOptMode = -1  # minimization
startTime   = time()
minFlux, maxFlux, optSol  = distributedFBA(model, solver, nWorkers, 100.0, "", rxnsList, 0, rxnsOptMode, false);
solTime = time() - startTime

fbaSolution = solveCobraLP(model, solver)
fbaObj = fbaSolution.objval
fbaSol = fbaSolution.sol

@test abs(minFlux[rxnsList] - fbaObj) < 1e-9

# save the variables to the current directory
saveDistributedFBA("testFile.mat")

# remove the file to clean up
run(`rm testFile.mat`)

# print a solution summary
printSolSummary(testFile, optSol, maxFlux, minFlux, solTime, nWorkers, solverName)
