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
    export MACOSX_DEPLOYMENT_TARGET=13.3
    export EXTRA_CXXFLAGS="-mmacosx-version-min=13.3"

    # Extract SDK for x86_64 macOS if available
    if [[ "${target}" == x86_64-apple-darwin* ]]; then
        SDK_TAR=$(find ${WORKSPACE}/srcdir -name "MacOSX*.sdk.tar.xz" | head -1)
        if [[ -f "${SDK_TAR}" ]]; then
            apple_sdk_root=${WORKSPACE}/srcdir/MacOSX13.3.sdk
            tar --extract --file="${SDK_TAR}" \
                --directory=${WORKSPACE}/srcdir \
                --strip-components=1 2>/dev/null || true
            # Update toolchain to use the SDK
            if [[ -f "$CMAKE_TARGET_TOOLCHAIN" ]]; then
                sed -i "s!/opt/$target/$target/sys-root!$apple_sdk_root!" "$CMAKE_TARGET_TOOLCHAIN"
            fi
            if [[ -f "/opt/bin/$bb_full_target/$target-clang++" ]]; then
                sed -i "s!/opt/$target/$target/sys-root!$apple_sdk_root!" "/opt/bin/$bb_full_target/$target-clang++"
            fi
        fi
    fi
fi

# Build using Makefile
make clean
make -j${nproc} PREFIX=${prefix}
make install PREFIX=${prefix}
"""

platforms = supported_platforms()
platforms = filter(p -> Sys.iswindows(p) || Sys.isapple(p) || Sys.islinux(p), platforms)
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
