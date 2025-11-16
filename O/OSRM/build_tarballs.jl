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

    # Remove -z,origin linker option which is not supported by MinGW on Windows
    sed -i 's/-Wl,-z,origin//g' CMakeLists.txt

    # Remove WIN32 keyword from add_executable calls to ensure console executables
    # This needs to be done via sed as it affects multiple files
    find . -name "CMakeLists.txt" -o -name "*.cmake" | while read f; do
        sed -i '/add_executable(/,/)/{s/ WIN32//g;}' "$f"
        sed -i 's/add_executable(\([^ ]*\) WIN32 /add_executable(\1 /g' "$f"
        sed -i 's/add_executable(\([^ ]*\) WIN32)/add_executable(\1)/g' "$f"
    done
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
    # Find TBB and Zlib library names for linking
    TBB_LIB_NAME=""
    ZLIB_LIB_NAME="z"

    # Try to find TBB library
    TBB_LIB=$(find "${libdir}" "${prefix}/lib" -name "libtbb*.dll.a" -o -name "libtbb*.a" 2>/dev/null | head -1)
    if [ -n "$TBB_LIB" ] && [ -f "$TBB_LIB" ]; then
        # Extract library name (e.g., libtbb12.dll.a -> tbb12)
        TBB_LIB_NAME=$(basename "$TBB_LIB" .dll.a | sed 's/^lib//')
    fi

    # Build linker flags with explicit library linking
    # Allow multiple definitions to handle EXTRACTOR object library being linked into both osrm_extract and osrm_guidance
    EXE_LINKER_FLAGS="-fno-lto -Wl,-subsystem,console -Wl,--entry=mainCRTStartup -L${libdir}"
    SHARED_LINKER_FLAGS="-fno-lto -Wl,--allow-multiple-definition -L${libdir}"

    # Add TBB and Zlib to linker flags if found
    if [ -n "$TBB_LIB_NAME" ]; then
        EXE_LINKER_FLAGS="${EXE_LINKER_FLAGS} -l${TBB_LIB_NAME}"
        SHARED_LINKER_FLAGS="${SHARED_LINKER_FLAGS} -l${TBB_LIB_NAME}"
    fi
    EXE_LINKER_FLAGS="${EXE_LINKER_FLAGS} -l${ZLIB_LIB_NAME}"
    SHARED_LINKER_FLAGS="${SHARED_LINKER_FLAGS} -l${ZLIB_LIB_NAME}"

    CMAKE_FLAGS+=(
        -DENABLE_LTO=OFF
        -DCMAKE_CXX_FLAGS="-Wno-array-bounds -Wno-uninitialized -Wno-unused-parameter -Wno-maybe-uninitialized -fno-lto -Wno-error -Wno-pedantic"
        -DCMAKE_C_FLAGS="-Wno-error -Wno-pedantic"
        -DCMAKE_CXX_FLAGS_RELEASE="-O3 -DNDEBUG -fno-lto"
        -DCMAKE_EXE_LINKER_FLAGS="${EXE_LINKER_FLAGS}"
        -DCMAKE_SHARED_LINKER_FLAGS="${SHARED_LINKER_FLAGS}"
        -DCMAKE_WINDOWS_EXPORT_ALL_SYMBOLS=ON
        -DCMAKE_CXX_VISIBILITY_PRESET=default
        -DCMAKE_VISIBILITY_INLINES_HIDDEN=OFF
        -DCMAKE_SKIP_RPATH=ON
        -DOSRM_HAS_STD_FORMAT_EXITCODE=0
        -DOSRM_HAS_STD_FORMAT_EXITCODE__TRYRUN_OUTPUT=""
    )
    # Help CMake find dependencies on Windows
    if [ -d "${libdir}/cmake/Boost-1.87.0" ]; then
        CMAKE_FLAGS+=(-DBoost_DIR=${libdir}/cmake/Boost-1.87.0/)
    elif [ -d "${prefix}/lib/cmake/Boost-1.87.0" ]; then
        CMAKE_FLAGS+=(-DBoost_DIR=${prefix}/lib/cmake/Boost-1.87.0/)
    fi
    # Find Lua library - check multiple locations and patterns
    # On Windows, libdir is prefix/bin, and Lua installs lua54.dll there
    # Look for import library (.dll.a) which is needed for linking
    LUA_IMPORT_LIB=$(find "${libdir}" "${prefix}/lib" "${bindir}" "${prefix}/bin" \( -name "lua*.dll.a" -o -name "liblua*.a" -o -name "lua*.a" \) 2>/dev/null | head -1)
    if [ -n "$LUA_IMPORT_LIB" ] && [ -f "$LUA_IMPORT_LIB" ]; then
        # Use full path to import library
        CMAKE_FLAGS+=(-DLUA_LIBRARIES="${LUA_IMPORT_LIB}")
    else
        # Try to find the DLL and construct library name
        LUA_DLL=$(find "${libdir}" "${prefix}/lib" "${bindir}" "${prefix}/bin" -name "lua*.dll" 2>/dev/null | head -1)
        if [ -n "$LUA_DLL" ] && [ -f "$LUA_DLL" ]; then
            # Extract library name from DLL (e.g., lua54.dll -> lua54)
            LUA_LIB_NAME=$(basename "$LUA_DLL" .dll)
            CMAKE_FLAGS+=(-DLUA_LIBRARIES="${LUA_LIB_NAME}")
        else
            # Fallback: use lua54 as the library name (standard for Lua 5.4)
            CMAKE_FLAGS+=(-DLUA_LIBRARIES="lua54")
        fi
        # Also set library directory to help CMake find it
        CMAKE_FLAGS+=(-DLUA_LIB_DIR="${libdir}")
    fi
    # Always set include directory
    CMAKE_FLAGS+=(-DLUA_INCLUDE_DIR="${includedir}")
fi

# Find TBB - check multiple locations
if [ -d "${libdir}/cmake/TBB" ]; then
    CMAKE_FLAGS+=(-DTBB_DIR=${libdir}/cmake/TBB)
elif [ -d "${prefix}/lib/cmake/TBB" ]; then
    CMAKE_FLAGS+=(-DTBB_DIR=${prefix}/lib/cmake/TBB)
elif [ -d "${prefix}/lib/cmake/tbb" ]; then
    CMAKE_FLAGS+=(-DTBB_DIR=${prefix}/lib/cmake/tbb)
fi

# On Windows, ensure TBB and Zlib are properly linked
# Add library search paths to linker flags and ensure CMake can find them
if [[ "${target}" == *-mingw* ]]; then
    # Add library directory to CMAKE_LIBRARY_PATH to help FindTBB and FindZLIB
    export CMAKE_LIBRARY_PATH="${libdir}:${prefix}/lib:${CMAKE_LIBRARY_PATH}"
    export CMAKE_PREFIX_PATH="${prefix}:${CMAKE_PREFIX_PATH}"

    # Also add to linker flags to ensure libraries are found
    # The -L flags are already in CMAKE_EXE_LINKER_FLAGS and CMAKE_SHARED_LINKER_FLAGS
    # But we might need to explicitly link them if OSRM's CMakeLists.txt doesn't do it
    # For now, rely on CMake's FindTBB and FindZLIB modules with proper paths
fi

cmake .. "${CMAKE_FLAGS[@]}"

cmake --build . --parallel ${nproc}
cmake --install .

cp -r ${WORKSPACE}/srcdir/osrm-backend/profiles ${prefix}/
install_license "${WORKSPACE}/srcdir/osrm-backend/LICENSE.TXT"
"""

platforms = supported_platforms()
platforms = filter(Sys.iswindows, platforms)
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
