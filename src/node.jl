#########################################################################
#
#   ExNode type definition and related functions
#
#########################################################################

#####  ExNode type  ######

mutable struct ExNode{T}
    main                    # main payload
    parents::Vector{Any}    # parent nodes
    precedence::Vector{Any} # nodes that should be evaluated before (but are not parents)
    val                     # value
    alloc::Bool             # Allocation ? Forbids fusions

    ExNode{T}(main)                        where T = new{T}(   main,   Any[], Any[], NaN, false)
    ExNode{T}(main,parents)                   where T = new{T}(   main, parents, Any[], NaN, false)
    ExNode{T}(main,parents, prec, val, alloc) where T = new{T}(   main, parents,  prec, val, alloc)
end

copy(x::ExNode{T}) where {T} = ExNode{T}( x.main, # copy(x.main),
                                  copy(x.parents),
                                  copy(x.precedence),
                                  # copy(x.val),
                                  x.val,
                                  x.alloc)

copy(x::ExNode{:for}) = 
    ExNode{:for}(Any[ x.main[1], copy(x.main[2]) ],    # make a copy of subgraph
                 copy(x.parents),
                 copy(x.precedence),
                 # copy(x.val),
                 x.val,
                 x.alloc)

const NConst     = ExNode{:constant}  # for constant
const NExt       = ExNode{:external}  # external var
const NCall      = ExNode{:call}      # function call
const NComp      = ExNode{:comp}      # comparison operator
const NRef       = ExNode{:ref}       # getindex
const NDot       = ExNode{:dot}       # getfield
const NSRef      = ExNode{:subref}    # setindex
const NSDot      = ExNode{:subdot}    # setfield
const NFor       = ExNode{:for}       # for loop
const NIn        = ExNode{:within}    # reference to var set in a loop

const awfx = NConst(1.0)

subtype(n::ExNode{T}) where {T} = T

function show(io::IO, res::ExNode)
    pl = join( map(x->isa(x,NFor) ? "subgraph" : repr(x.main), res.parents) , " / ")
    print(io, "[$(subtype(res))] $(repr(res.main)) ($(repr(res.val)))")
    length(pl) > 0 && print(io, ", from = $pl")
end
