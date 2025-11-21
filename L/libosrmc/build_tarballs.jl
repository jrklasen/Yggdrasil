using BinaryBuilder, Pkg

name = "libosrmc"
version = v"6.0.0"

sources = [
    ArchiveSource(
        "https://github.com/jrklasen/libosrmc/archive/refs/heads/osrm-6.tar.gz",
        "4f60dc352fae87a5d83e9c3db7cfb2f4d7fb26d2e56bbb0af2629a4caf2edc7d",
    ),
]

script = raw"""
cd ${WORKSPACE}/srcdir/libosrmc-osrm-6/libosrmc

export PKG_CONFIG_PATH="${prefix}/lib/pkgconfig:${prefix}/share/pkgconfig:${PKG_CONFIG_PATH}"
export CPPFLAGS="-I${prefix}/include ${CPPFLAGS}"
export LDFLAGS="-L${prefix}/lib ${LDFLAGS}"

make -j${nproc} \
    PREFIX=${prefix} \
    VERSION_MAJOR=6 \
    VERSION_MINOR=0

make install \
    PREFIX=${prefix} \
    VERSION_MAJOR=6 \
    VERSION_MINOR=0
"""

platforms = [Platform("x86_64", "linux"; cxxstring_abi = "cxx11")]

products = [
    LibraryProduct("libosrmc", :libosrmc; dont_dlopen = true),
    FileProduct("include/osrmc/osrmc.h", :osrmc_header),
]

dependencies = [
    Dependency(PackageSpec(name = "OSRM_jll", url = "https://github.com/jrklasen/OSRM_jll.jl")),
    Dependency("CompilerSupportLibraries_jll"),
]

build_tarballs(
    ARGS,
    name,
    version,
    sources,
    script,
    platforms,
    products,
    dependencies;
    preferred_gcc_version = v"13",
)
