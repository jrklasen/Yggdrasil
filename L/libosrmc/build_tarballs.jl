using BinaryBuilder, Pkg

name = "libosrmc"
version = v"6.0.0"

sources = [
    DirectorySource("/home/jrklasen/dev/moviro/osrm/libosrmc"),
    ArchiveSource(
        "https://github.com/roblabla/MacOSX-SDKs/releases/download/13.3/MacOSX13.3.sdk.tar.xz",
        "e5d0f958a079106234b3a840f93653308a76d3dcea02d3aa8f2841f8df33050c",
    ),
]

script = raw"""
cd ${WORKSPACE}/srcdir
[[ -d "libosrmc/libosrmc" ]] && cd libosrmc/libosrmc || cd libosrmc

# Set PKG_CONFIG_PATH for OSRM discovery
export PKG_CONFIG_PATH="${prefix}/lib/pkgconfig:${PKG_CONFIG_PATH}"

# macOS-specific setup
if [[ "${target}" == *-apple-* ]]; then
    export MACOSX_DEPLOYMENT_TARGET=11.0
    export EXTRA_CXXFLAGS="-mmacosx-version-min=11.0"

    # Extract SDK for x86_64 macOS if available
    if [[ "${target}" == x86_64-apple-darwin* ]]; then
        SDK_TAR=$(find ${WORKSPACE}/srcdir -name "MacOSX*.sdk.tar.xz" | head -1)
        [[ -f "${SDK_TAR}" ]] && tar --extract --file="${SDK_TAR}" \
            --directory=/opt/${target}/${target}/sys-root/. \
            --strip-components=1 MacOSX13.3.sdk/System MacOSX13.3.sdk/usr 2>/dev/null || true
    fi
fi

# Build using Makefile
make clean
make -j${nproc} PREFIX=${prefix}
make install PREFIX=${prefix}
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
    Dependency("boost_jll"; compat="=1.87.0"),
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
