# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder, Pkg

name = "OSRM"
version = v"6.0.0"

# Collection of sources required to complete build
sources = [
    GitSource("https://github.com/Project-OSRM/osrm-backend.git", "01605f7589e6fe68df3fc690ad001b687128aba7"),
    DirectorySource("./bundled"),
    # OSRM requires C++20, which needs a newer SDK with full ranges support
    ArchiveSource("https://github.com/roblabla/MacOSX-SDKs/releases/download/13.3/MacOSX13.3.sdk.tar.xz",
        "e5d0f958a079106234b3a840f93653308a76d3dcea02d3aa8f2841f8df33050c"),
]

script = raw"""
cd ${WORKSPACE}/srcdir/osrm-backend

# Apple specific patches
if [[ "${target}" == *-apple-darwin* ]]; then
    # Use a newer SDK which supports C++20 ranges
    apple_sdk_root=$WORKSPACE/srcdir/MacOSX13.3.sdk
    sed -i "s!/opt/$target/$target/sys-root!$apple_sdk_root!" $CMAKE_TARGET_TOOLCHAIN
    sed -i "s!/opt/$target/$target/sys-root!$apple_sdk_root!" /opt/bin/$bb_full_target/$target-clang++
    export MACOSX_DEPLOYMENT_TARGET=13.3
    # Exclude duplicate intersection files from GUIDANCE for platforms that link to EXTRACTOR
    sed -i 's|file(GLOB GuidanceGlob src/guidance/\*\.cpp src/extractor/intersection/\*\.cpp)|file(GLOB GuidanceGlob src/guidance/*.cpp)|' CMakeLists.txt
    # Replace the osrm_guidance library definition with version that links to EXTRACTOR
    sed -i '/^add_library(osrm_guidance $<TARGET_OBJECTS:GUIDANCE> $<TARGET_OBJECTS:UTIL>)$/c\
add_library(osrm_guidance $<TARGET_OBJECTS:GUIDANCE> $<TARGET_OBJECTS:UTIL> $<TARGET_OBJECTS:MICROTAR>)\
target_link_libraries(osrm_guidance PRIVATE EXTRACTOR ${LUA_LIBRARIES} BZip2::BZip2 ZLIB::ZLIB EXPAT::EXPAT Boost::iostreams TBB::tbb)' CMakeLists.txt
fi

# Windows specific patches
if [[ "${target}" == *-mingw* ]]; then
    # Ensure console executables by stripping WIN32 from add_executable invocations
    find . -name "CMakeLists.txt" -o -name "*.cmake" | while read f; do
        sed -i '/add_executable(/,/)/{s/ WIN32//g;}' "$f"
        sed -i 's/add_executable(\([^ ]*\) WIN32 /add_executable(\1 /g' "$f"
        sed -i 's/add_executable(\([^ ]*\) WIN32)/add_executable(\1)/g' "$f"
    done
    # Exclude duplicate intersection files from GUIDANCE for platforms that link to EXTRACTOR
    sed -i 's|file(GLOB GuidanceGlob src/guidance/\*\.cpp src/extractor/intersection/\*\.cpp)|file(GLOB GuidanceGlob src/guidance/*.cpp)|' CMakeLists.txt
    # Remove rpath flag for Windows (not supported)
    sed -i '/set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-z,origin")/d' CMakeLists.txt
    # Replace the osrm_guidance library definition with version that links to EXTRACTOR
    sed -i '/^add_library(osrm_guidance $<TARGET_OBJECTS:GUIDANCE> $<TARGET_OBJECTS:UTIL>)$/c\
add_library(osrm_guidance $<TARGET_OBJECTS:GUIDANCE> $<TARGET_OBJECTS:UTIL> $<TARGET_OBJECTS:MICROTAR>)\
target_link_libraries(osrm_guidance PRIVATE EXTRACTOR ${LUA_LIBRARIES} BZip2::BZip2 ZLIB::ZLIB EXPAT::EXPAT Boost::iostreams TBB::tbb)' CMakeLists.txt
fi

# Linux-musl specific patches
if [[ "${target}" == *-linux-musl* ]]; then
    sed -i 's/-Wpedantic/-Wno-pedantic/g; s/-Werror=pedantic/-Wno-error=pedantic/g' CMakeLists.txt
fi

mkdir build && cd build

# Common cmake flags
CMAKE_FLAGS=(
    -DCMAKE_INSTALL_PREFIX=${prefix}
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TARGET_TOOLCHAIN}
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_CXX_STANDARD=20
    -DCMAKE_PREFIX_PATH=${prefix}
    -DBUILD_SHARED_LIBS=ON
    -DBUILD_TESTING=OFF
)

# Apple specific cmake flags
if [[ "${target}" == *-apple-darwin* ]]; then
    CMAKE_FLAGS+=(
        -DENABLE_LTO=OFF
        -DCMAKE_EXE_LINKER_FLAGS="-L${libdir} -ltbb -lz"
        -DCMAKE_SHARED_LINKER_FLAGS="-L${libdir} -ltbb -lz"
        -DBoost_DIR=${libdir}/cmake/Boost-1.87.0/
        -DTBB_DIR=${libdir}/cmake/TBB
        -DLUA_LIBRARIES="${libdir}/liblua.dylib"
        -DLUA_INCLUDE_DIR="${includedir}"
    )
fi

# Windows specific cmake flags
if [[ "${target}" == *-mingw* ]]; then
    # Common flags with -fno-lto consolidated
    LTO_FLAGS="-fno-lto"
    CMAKE_FLAGS+=(
        -DENABLE_LTO=OFF
        -DCMAKE_CXX_FLAGS="-Wno-array-bounds -Wno-uninitialized -Wno-unused-parameter -Wno-maybe-uninitialized ${LTO_FLAGS} -Wno-error -Wno-pedantic"
        -DCMAKE_CXX_FLAGS_RELEASE="-O3 -DNDEBUG ${LTO_FLAGS}"
        -DCMAKE_EXE_LINKER_FLAGS="${LTO_FLAGS} -Wl,-subsystem,console -Wl,--entry=mainCRTStartup -L${libdir} -ltbb12 -lz"
        -DCMAKE_SHARED_LINKER_FLAGS="${LTO_FLAGS} -L${libdir} -ltbb12 -lz"
        -DCMAKE_WINDOWS_EXPORT_ALL_SYMBOLS=ON
        -DCMAKE_CXX_VISIBILITY_PRESET=default
        -DCMAKE_VISIBILITY_INLINES_HIDDEN=OFF
        -DCMAKE_SKIP_RPATH=ON
        -DOSRM_HAS_STD_FORMAT_EXITCODE=0
        -DOSRM_HAS_STD_FORMAT_EXITCODE__TRYRUN_OUTPUT=""
        -DBoost_DIR=${libdir}/cmake/Boost-1.87.0/
        -DTBB_DIR=${libdir}/cmake/TBB
        -DLUA_LIBRARIES="lua54"
        -DLUA_INCLUDE_DIR="${includedir}"
    )
fi

# Linux specific cmake flags
if [[ "${target}" == *-linux-* ]]; then
    CMAKE_FLAGS+=(-DCMAKE_CXX_FLAGS="-Wno-array-bounds -Wno-uninitialized -Wno-error")
fi

# Linux-musl specific cmake flags
if [[ "${target}" == *-linux-musl* ]]; then
    CMAKE_FLAGS+=(
        -DOSRM_HAS_STD_FORMAT_EXITCODE=0
        -DOSRM_HAS_STD_FORMAT_EXITCODE__TRYRUN_OUTPUT=""
    )
fi

cmake .. "${CMAKE_FLAGS[@]}"

cmake --build . --parallel ${nproc}
cmake --install .

cp -r ${WORKSPACE}/srcdir/osrm-backend/profiles ${prefix}/
install_license "${WORKSPACE}/srcdir/osrm-backend/LICENSE.TXT"
"""

platforms = supported_platforms()
platforms = filter(p -> Sys.iswindows(p) || Sys.isapple(p) || Sys.islinux(p), platforms)
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
