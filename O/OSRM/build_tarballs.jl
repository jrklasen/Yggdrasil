# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder, Pkg

name = "OSRM"
version = v"6.0.0"

# Collection of sources required to complete build
sources = [
    GitSource("https://github.com/Project-OSRM/osrm-backend.git", "01605f7589e6fe68df3fc690ad001b687128aba7"),
    DirectorySource("./bundled"),
]

script = raw"""
cd ${WORKSPACE}/srcdir/osrm-backend

if [[ "${target}" == *-linux-musl* ]]; then
    sed -i 's/-Wpedantic/-Wno-pedantic/g; s/-Werror=pedantic/-Wno-error=pedantic/g' CMakeLists.txt
fi

if [[ "${target}" == *-mingw* ]]; then
    # Apply Windows patch
    atomic_patch -p1 ${WORKSPACE}/srcdir/patches/windows-fixes.patch
fi

mkdir build && cd build

CMAKE_FLAGS=(
    -DCMAKE_INSTALL_PREFIX=${prefix}
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TARGET_TOOLCHAIN}
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_CXX_STANDARD=20
    -DCMAKE_PREFIX_PATH=${prefix}
    -DBUILD_SHARED_LIBS=ON
    -DBUILD_TESTING=OFF
)

# Linux-specific CXX flags
if [[ "${target}" == *-linux-* ]]; then
    CMAKE_FLAGS+=(-DCMAKE_CXX_FLAGS="-Wno-array-bounds -Wno-uninitialized -Wno-error")
fi

if [[ "${target}" == *-linux-musl* ]]; then
    CMAKE_FLAGS+=(
        -DOSRM_HAS_STD_FORMAT_EXITCODE=0
        -DOSRM_HAS_STD_FORMAT_EXITCODE__TRYRUN_OUTPUT=""
    )
fi

if [[ "${target}" == *-mingw* ]]; then
    # Build linker flags for console executables and shared libs
    # Allow multiple definitions to handle EXTRACTOR object library being linked into both osrm_extract and osrm_guidance
    EXE_LINKER_FLAGS="-fno-lto -Wl,-subsystem,console -Wl,--entry=mainCRTStartup"
    SHARED_LINKER_FLAGS="-fno-lto -Wl,--allow-multiple-definition"

    CMAKE_FLAGS+=(
        -DENABLE_LTO=OFF
        -DCMAKE_CXX_FLAGS="-Wno-array-bounds -Wno-uninitialized -fno-lto -Wno-error -Wno-pedantic"
        -DCMAKE_C_FLAGS="-Wno-error -Wno-pedantic"
        -DCMAKE_EXE_LINKER_FLAGS="${EXE_LINKER_FLAGS}"
        -DCMAKE_SHARED_LINKER_FLAGS="${SHARED_LINKER_FLAGS}"
        -DCMAKE_SKIP_RPATH=ON
        -DOSRM_HAS_STD_FORMAT_EXITCODE=0
        -DOSRM_HAS_STD_FORMAT_EXITCODE__TRYRUN_OUTPUT=""
    )
    # Help CMake find Boost's config package, which currently ships in a nested directory
    BOOST_DIR=$(find "${prefix}" -type d -name "Boost-1.87.0" -path "*/cmake/*" 2>/dev/null | head -1)
    if [ -n "$BOOST_DIR" ] && [ -d "$BOOST_DIR" ]; then
        CMAKE_FLAGS+=(-DBoost_DIR=${BOOST_DIR})
    fi
    # Help CMake find Lua library on Windows
    LUA_LIB=$(find "${libdir}" "${prefix}/lib" "${bindir}" "${prefix}/bin" \( -name "lua*.dll.a" -o -name "liblua*.a" \) 2>/dev/null | head -1)
    if [ -n "$LUA_LIB" ] && [ -f "$LUA_LIB" ]; then
        CMAKE_FLAGS+=(-DLUA_LIBRARIES="${LUA_LIB}")
    else
        CMAKE_FLAGS+=(-DLUA_LIBRARIES="lua54")
    fi
    CMAKE_FLAGS+=(-DLUA_INCLUDE_DIR="${includedir}")
fi

cmake .. "${CMAKE_FLAGS[@]}"

cmake --build . --parallel ${nproc}
cmake --install .

cp -r ${WORKSPACE}/srcdir/osrm-backend/profiles ${prefix}/
install_license "${WORKSPACE}/srcdir/osrm-backend/LICENSE.TXT"
"""

platforms = supported_platforms()
platforms = filter(p -> Sys.iswindows(p) || Sys.islinux(p), platforms)
platforms = expand_cxxstring_abis(platforms)

# The products that we will ensure are always built
products = [
    ExecutableProduct("osrm-extract", :osrm_extract),
    ExecutableProduct("osrm-contract", :osrm_contract),
    ExecutableProduct("osrm-partition", :osrm_partition),
    ExecutableProduct("osrm-customize", :osrm_customize),
    ExecutableProduct("osrm-routed", :osrm_routed),
    ExecutableProduct("osrm-datastore", :osrm_datastore),
    ExecutableProduct("osrm-components", :osrm_components),
    LibraryProduct("libosrm", :libosrm; dont_dlopen=true),  # Cannot be loaded in sandbox
    FileProduct("profiles/bicycle.lua", :bicycle_lua),
    FileProduct("profiles/car.lua", :car_lua),
    FileProduct("profiles/foot.lua", :foot_lua),
    FileProduct("profiles/lib/access.lua", :lib_access_lua),
    FileProduct("profiles/lib/maxspeed.lua", :lib_maxspeed_lua),
    FileProduct("profiles/lib/profile_debugger.lua", :lib_profile_debugger_lua),
    FileProduct("profiles/lib/set.lua", :lib_set_lua),
    FileProduct("profiles/lib/utils.lua", :lib_utils_lua),
    FileProduct("profiles/lib/destination.lua", :lib_destination_lua),
    FileProduct("profiles/lib/measure.lua", :lib_measure_lua),
    FileProduct("profiles/lib/relations.lua", :lib_relations_lua),
    FileProduct("profiles/lib/tags.lua", :lib_tags_lua),
    FileProduct("profiles/lib/way_handlers.lua", :lib_way_handlers_lua),
    FileProduct("profiles/lib/guidance.lua", :lib_guidance_lua),
    FileProduct("profiles/lib/pprint.lua", :lib_pprint_lua),
    FileProduct("profiles/lib/sequence.lua", :lib_sequence_lua),
    FileProduct("profiles/lib/traffic_signal.lua", :lib_traffic_signal_lua),
]

# Dependencies that must be installed before this package can be built
dependencies = [
    Dependency("boost_jll"; compat="=1.87.0"),
    Dependency("Lua_jll"; compat="~5.4.9"),
    Dependency("oneTBB_jll"; compat="2022.0.0"),
    Dependency("Expat_jll"; compat="2.6.5"),
    Dependency("XML2_jll"; compat="~2.14.1"),
    Dependency("libzip_jll"),
    Dependency("Bzip2_jll"),
    Dependency("Zlib_jll"),
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies;
               julia_compat="1.10", preferred_gcc_version=v"13")
