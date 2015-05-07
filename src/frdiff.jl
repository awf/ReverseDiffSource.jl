#########################################################################
#
#   rdiff differentiation for functions
#
#########################################################################

### main function

function rdiff(f::Function, sig0::Tuple; args...)
    # f = tf ; sig0 = (0.,)
    sig = map( typeof, sig0 )
    fs = methods(f, sig)
    length(fs) == 0 && error("no function '$f' found for signature $sig")
    length(fs) > 1  && error("several functions $f found for signature $sig")  # is that possible ?

    fdef  = fs[1].func.code
    fcode = Base.uncompressed_ast(fdef)

    fargs = fcode.args[1]  # function parameters
    cargs = [ (fargs[i], sig0[i]) for i in 1:length(sig0) ]

    ex  = transform(fcode.args[3])
    dex = rdiff(ex; args..., cargs...)

    # Note : new function is created in the same module as original function
    myf = fdef.module.eval( :( $(Expr(:tuple, fargs...)) -> $dex ) )
end

### translation functions to recover a workable expression that can be differentiated

# Simplifies expressions for processing
#  - removes Topnodes and linenumbers, 
#  - replaces GenSym() with actual symbol
function streamline(ex0::Expr)
    ex = copy(ex0)

    ex.head == :call && isa(ex.args[1], TopNode) && (ex.args[1] = ex.args[1].name)

    args = Any[]
    for a in ex.args
        isa(a, LineNumberNode) && continue
        isa(a, Expr) && a.head==:line && continue

        ar = if isa(a,Expr)
                streamline(a)
             elseif isdefined(:GenSym) && isa(a, GenSym)
                symbol("__gensym$(a.id)")
             else
                a
             end
        push!(args, ar)
    end
    Expr(ex.head, args...)   
end

# converts expression to searchable strings
function _e2s(ex::Expr, escape=false)  # ex = ex2.args[1]
    ex.head == :macrocall && ex.args[1] == symbol("@rg_str") && return(ex.args[2])

    if ex.head == :call && ex.args[1] == :gotoifnot
        es = "↑gotoifnot"
        ra = 2:length(ex.args)
    else
        es = "↑$(ex.head)"
        ra = 1:length(ex.args)
    end

    for a in ex.args[ra]
        es *= "→" * _e2s(a, escape)
    end
    return es * "↓"
end

function _e2s(thing, escape=false) # thing = symbol("abcd")
    res = isa(thing, Symbol) ? ":" * string(thing) : repr(thing)
    escape || return(res)
    # now escape characters that would otherwise have a meaning in regex
    i = start(res)
    res2 = ""
    while !done(res,i)
        c, j = next(res,i)
        c in "()+*.\$^[]|?" && (res2 *= "\\")
        res2 *= string(c)
        i = j
    end
    res2
end

function e2s(ex::Expr, escape=false)
    if ex.head in [:body, :block]
        return mapreduce(e -> _e2s(e, escape), *, "", ex.args)
    else
        return _e2s(ex, escape)
    end
end


# converts searchable strings back to expressions
function _s2e(s::AbstractString, pos=1) # s = pre ; pos = 1 ; s = post
    cap = match( r"↑([^→↓]*)(.*)", s, pos )
    if cap == nothing # skip junk characters (Labelnodes,..) and return
        cap = match( r".*?↑(.*)", s, pos )
        cap == nothing && return nothing, endof(s)+1
        return nothing, cap.offsets[1]
    end

    he  = symbol(cap.captures[1])
    ar  = Any[]
    pos = cap.offsets[2]
    while s[pos] == '→' && !done(s, pos)
        cap = match( r"→([^→↓]*)(.*)↓$", s, pos )  # s[pos:end]
        cap == nothing && error("[s2e] unexpected string (2)")
        if cap.captures[1][1] == '↑'
            ex, pos2 = _s2e(s, cap.offsets[1])
        elseif cap.captures[1][1] == ':'
            ex = symbol(cap.captures[1][2:end])
            pos2 = cap.offsets[2]
        else
            ex = parse(cap.captures[1])
            pos2 = cap.offsets[2]
        end
        push!(ar, ex)
        pos = pos2
    end

    c, pos = next(s, pos)
    return Expr(he, ar...), pos
end

function s2e(s::AbstractString) # s = pre
    res = Expr[]
    pos = 1
    while !done(s, pos)
        ex, pos = _s2e(s, pos)
        ex != nothing && push!(res, ex)
    end
    res
end

# regex string (julia v0.3)
exreg = quote
    rg"(?<pre>.*?)"
    rg"(?<g0>:[#_].+?)" = rg"(?<range>.+?)"
    rg"(?<iter>.+)" = start(rg"\g{g0}")
    gotoifnot( !(done(rg"\g{g0}", rg"\g{iter}" )) , rg"(?<lab1>\d+)" )
    rg":\((?<lab2>\d+): \)"
    rg"(?<g1>.+?)" = next(rg"\g{g0}", rg"\g{iter}")
    rg"(?<idx>.+?)" = rg":(?:getfield|tupleref)"(rg"\g{g1}", 1)
    rg"\g{iter}"    = rg":(?:getfield|tupleref)"(rg"\g{g1}", 2)
    rg"(?<in>.*)"
    rg":\((?<lab3>\d+): \)"
    gotoifnot( !(!(done(rg"\g{g0}", rg"\g{iter}"))) , rg"\g{lab2}" )
    rg":\(\g{lab1}: \)"
    rg"(?<post>.*)"
end
# regex string (julia v0.4)
# rexp = quote
#     rg"(?<pre>.*?)"
#     rg"(?<g0>:__gensym\d+)" = rg"(?<range>.+)"
#     rg"(?<iter>.+)" = start(rg"\g{g0}")
#     gotoifnot( !(done(rg"\g{g0}", rg"\g{iter}" )) , rg"(?<lab1>\d+)" )
#     rg":\((?<lab2>\d+): \)"
#     rg"(?<g1>:__gensym\d+)" = next(rg"\g{g0}", rg"\g{iter}")
#     rg"(?<idx>.+)" = getfield(rg"\g{g1}", 1)
#     rg"\g{iter}"   = getfield(rg"\g{g1}", 2)
#     rg"(?<in>.*)"
#     rg":\((?<lab3>\d+): \)"
#     gotoifnot( !(!(done(rg"\g{g0}", rg"\g{iter}"))) , rg"\g{lab2}" )
#     rg":\(\g{lab1}: \)"
#     rg"(?<post>.*)"
# end
rexp = Regex(e2s(streamline(exreg), true))


function _transform(s::AbstractString)
    mm = match(rexp, s)
    if mm != nothing && length(mm.captures) >= 11
        pre, rg, idx, inside, post = mm.captures[[1,3,8,9,11]]
        exin = _transform(inside)
        ef = Expr(:for, Expr(:(=), symbol(idx[2:end]), s2e(rg)[1] ), exin)

        return Expr(:block, [ s2e(pre) ; ef ; s2e(post)]...)
    else
        return Expr(:block, s2e(s)...)
    end
end

function transform(ex::Expr) # ex = fcode.args[3]
    s = e2s(streamline(ex))
    tex = _transform(s)

    # remove return statement at the end
    rex = tex.args[end]
    if rex.head == :return
        tex.args[end] = rex.args[1]
    else
        error("[transform] not return statement found at the end")
    end

    tex
end



