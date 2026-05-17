using Pkg
Pkg.add(url="https://github.com/SimonDanisch/BonitoBook.jl")
using DrWatson
@quickactivate @__DIR__
using BonitoBook

BonitoBook.book(projectdir("notebooks", "ABC_birds.ipynb"))