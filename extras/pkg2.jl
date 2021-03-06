# module Pkg2

function parse_requires(readable)
    reqs = Requires()
    for line in eachline(readable)
        ismatch(r"^\s*(?:#|$)", line) && continue
        fields = split(replace(line, r"#.*$", ""))
        pkg = shift!(fields)
        if !all(_->ismatch(Base.VERSION_REGEX,_), fields)
            error("invalid requires entry for $pkg: $fields")
        end
        vers = [convert(VersionNumber,_) for _ in fields]
        if !issorted(vers)
            error("invalid requires entry for $pkg: $vers")
        end
        ivals = VersionInterval[]
        if isempty(vers)
            push!(ivals, VersionInterval(typemin(VersionNumber),typemax(VersionNumber)))
        else
            isodd(length(vers)) && push!(vers, typemax(VersionNumber))
            while !isempty(vers)
                push!(ivals, VersionInterval(shift!(vers), shift!(vers)))
            end
        end
        reqs[pkg] = has(reqs,pkg) ? intersect(reqs[pkg], ivals) : ivals
    end
    return reqs
end
parse_requires(file::String) = isfile(file) ? open(parse_requires,file) : Requires()

function merge_requires!(A::Requires, B::Requires)
    for (pkg, ivals) in B
        A[pkg] = has(A,pkg) ? intersect(A[pkg], ivals) : ivals
    end
    return A
end

function available()
    pkgs = Dict{ByteString,Dict{VersionNumber,Available}}()
    for pkg in readdir("METADATA")
        isfile("METADATA", pkg, "url") || continue
        versdir = joinpath("METADATA", pkg, "versions")
        isdir(versdir) || continue
        for ver in readdir(versdir)
            ismatch(Base.VERSION_REGEX, ver) || continue
            isfile(versdir, ver, "sha1") || continue
            has(pkgs,pkg) || (pkgs[pkg] = eltype(pkgs)[2]())
            pkgs[pkg][convert(VersionNumber,ver)] = Available(
                readchomp(joinpath(versdir, ver, "sha1")),
                parse_requires(joinpath(versdir, ver, "requires"))
            )
        end
    end
    return pkgs
end

isinstalled(pkg::String) =
    pkg != "METADATA" && pkg != "REQUIRE" && isfile(pkg, "src", "$pkg.jl")

function isfixed(pkg::String)
    isinstalled(pkg) || error("$pkg is not an installed package.")
    isfile("METADATA", pkg, "url") || return true
    ispath(pkg, ".git") || return true
    cd(pkg) do
        Git.dirty() && return true
        Git.attached() && return true
        for line in eachline(`git branch -r --contains`)
            return false
        end
        return true
    end
end

function installed()
    pkgs = Dict{ByteString,Installed}()
    for pkg in readdir()
        isinstalled(pkg) || continue
        pkgs[pkg] = isfixed(pkg) ? Fixed(
            typemax(VersionNumber), # TODO: figure out a proxy version number
            parse_requires(joinpath(pkg, "REQUIRE"))
        ) : Free()
    end
    return pkgs
end

# end # module
