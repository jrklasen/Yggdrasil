using BinaryBuilder, Pkg

name = "libosrmc"
version = v"6.0.0"

sources = [
    DirectorySource("/home/jrklasen/dev/moviro/libosrmc"),
    ArchiveSource(
        "https://github.com/roblabla/MacOSX-SDKs/releases/download/13.3/MacOSX13.3.sdk.tar.xz",
        "e5d0f958a079106234b3a840f93653308a76d3dcea02d3aa8f2841f8df33050c",
    ),
]

script = raw"""
cd ${WORKSPACE}/srcdir
[[ -d "libosrmc/libosrmc" ]] && cd libosrmc/libosrmc || cd libosrmc

export PKG_CONFIG_PATH="${prefix}/lib/pkgconfig:${prefix}/share/pkgconfig:${PKG_CONFIG_PATH}"
export CPPFLAGS="-I${prefix}/include ${CPPFLAGS}"
if [[ "${target}" == *-mingw* ]]; then
    export CPPFLAGS="-I${prefix}/include/osrm ${CPPFLAGS}"
fi
export LDFLAGS="-L${prefix}/lib -Wl,-rpath,${prefix}/lib ${LDFLAGS}"

if [[ -n "${LD_LIBRARY_PATH}" ]]; then
    export LD_LIBRARY_PATH=$(echo "${LD_LIBRARY_PATH}" | tr ':' '\n' | grep -v "destdir" | tr '\n' ':' | sed 's/:$//; s/^://')
fi

if [[ "${target}" == *-apple-* ]]; then
    if [[ "${target}" == x86_64-apple-darwin* ]]; then
        export MACOSX_DEPLOYMENT_TARGET=11.0
        export EXTRA_CXXFLAGS="-mmacosx-version-min=11.0"
        SDK_TAR=$(find ${WORKSPACE}/srcdir -name "MacOSX*.sdk.tar.xz" | head -1)
        [[ -f "${SDK_TAR}" ]] && tar --extract --file="${SDK_TAR}" --directory=/opt/${target}/${target}/sys-root/. --strip-components=1 MacOSX13.3.sdk/System MacOSX13.3.sdk/usr 2>/dev/null || true
    else
        export MACOSX_DEPLOYMENT_TARGET=11.0
        export EXTRA_CXXFLAGS="-mmacosx-version-min=11.0"
    fi
else
    export EXTRA_CXXFLAGS=""
fi

make clean
make -j${nproc} PREFIX=${prefix} VERSION_MAJOR=6 VERSION_MINOR=0 EXTRA_CXXFLAGS="${EXTRA_CXXFLAGS}"
make install PREFIX=${prefix} VERSION_MAJOR=6 VERSION_MINOR=0
"""

platforms = supported_platforms()
platforms = filter(p -> (Sys.isapple(p) || Sys.islinux(p)) && !(Sys.isapple(p) && arch(p) == "x86_64"), platforms)
platforms = expand_cxxstring_abis(platforms)

products = [
    LibraryProduct("libosrmc", :libosrmc; dont_dlopen = true),
    FileProduct("include/osrmc/osrmc.h", :osrmc_header),
]

dependencies = [
    Dependency("CompilerSupportLibraries_jll"),
    Dependency(PackageSpec(name="OSRM_jll", url="https://github.com/jrklasen/OSRM_jll.jl", rev="main")),
    Dependency("boost_jll"),
    Dependency("Expat_jll"; compat="2.6.5"),
    Dependency("Zlib_jll"),
    Dependency("Bzip2_jll"),
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
    julia_compat="1.10",
    preferred_gcc_version = v"13",
)
