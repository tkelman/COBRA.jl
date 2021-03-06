#-------------------------------------------------------------------------------------------
#=
    Purpose:    Create and initialize a pool of workers (local and via SSH)
    Author:     Laurent Heirendt - LCSB - Luxembourg
    Date:       September 2016
=#

#-------------------------------------------------------------------------------------------
"""
    createPool(localWorkers, connectSSHWorkers)

Function used to create a pool of parallel workers that are either local or connected via SSH.

# INPUTS

- `localWorkers`:   Number of local workers to connect.
                    If `connectSSH` is `true`, the number of localWorkers is 1 (host).

# OPTIONAL INPUTS

- `connectSSH`:     Boolean that indicates whether additional nodes should be connected via SSH.
                    (default: `false`)

# OUTPUTS

- `workers()`:      Array of IDs of the connected workers (local and SSH workers)
- `nWorkers`:       Total number of connect workers (local and SSH workers)

# EXAMPLES

Minimum working example:
```julia
julia> createPool(localWorkers)
```

See also: `workers()`, `nprocs()`, `addprocs()`, `gethostname()`

"""

function createPool(localWorkers::Int, connectSSH::Bool=false)

    # load cores on remote nodes
    if connectSSH
        localWorkers = 0

        # load the SSH configuration
        if is_windows()
            include("$(dirname(pwd()))\config\\sshCfg.jl")
        else
            include("$(dirname(pwd()))/config/sshCfg.jl")
        end

        #count the total number of workers
        remoteWorkers = 0
        for i = 1:length(sshWorkers[1,:])
            remoteWorkers = remoteWorkers + sshWorkers[i]["procs"]
        end

    else #no remote SSH nodes
        remoteWorkers = 0 #specify that no remote workers are used
        if localWorkers == 0
            error("At least one worker is required in the pool. Please set `localWorkers` > 0.")
        end
    end

    nWorkers = localWorkers + remoteWorkers

    # connect all required workers
    if nWorkers <= 1
        info("Sequential version - Depending on the model size, expect long execution times.")

    else
        info("Parallel version - Connecting the $nWorkers workers ...")

        # print a warning for already connected threads
        if nprocs() > nWorkers
            print_with_color(:blue, "$nWorkers workers already connected. No further workers to connect.\n")

        # add local threads
        elseif localWorkers > 0
            addprocs(localWorkers)
            print_with_color(:blue, "$(nworkers()) local workers are connected. (+1) on host: $(gethostname())\n")

        # add remote threads
        elseif connectSSH && nworkers() < nWorkers

            info("Connecting SSH nodes ...")

            # loop through the workers to be connected
            for i in 1:length(sshWorkers)
                println(" >> Connecting ", sshWorkers[i]["procs"], " workers on ", sshWorkers[i]["usernode"])

                try
                    addprocs([(sshWorkers[i]["usernode"],sshWorkers[i]["procs"])],topology=:master_slave, tunnel=true,dir=sshWorkers[i]["dir"],sshflags=sshWorkers[i]["flags"],exeflags=`--depwarn=no`,exename=sshWorkers[i]["exename"])

                    info("Connected ", sshWorkers[i]["procs"], " workers on ",  sshWorkers[i]["usernode"])
                    remoteWorkers += sshWorkers[i]["procs"]
                catch
                    error("Cannot connect $nWorkers via SSH. Check your `sshCfg.jl` file.")
                end
            end

            nWorkers = nworkers() + 1
        end
    end

    return workers(), nWorkers
end

export createPool

#------------------------------------------------------------------------------------------
