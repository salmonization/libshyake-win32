cmake_minimum_required(VERSION 3.16)
project(libshyake C)

set(CMAKE_C_STANDARD 99)

option(SHYAKE_BUILD_DLL "Build shyake.dll for P/Invoke users" ON)
option(SHYAKE_BUILD_TESTS "Build test_crypto" ON)

# x86 builds target Windows XP SP3 without SSE
if(CMAKE_SIZEOF_VOID_P EQUAL 4 AND NOT CMAKE_SYSTEM_PROCESSOR MATCHES "ARM")
    add_compile_definitions(_WIN32_WINNT=0x0501)
    if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
        add_compile_options(-march=i686 -mno-sse)
    endif()
endif()

find_package(CURL REQUIRED)

find_package(MbedTLS QUIET)
if(NOT MbedTLS_FOUND)
    find_library(MBEDCRYPTO_LIB mbedcrypto REQUIRED)
    add_library(MbedTLS::mbedcrypto UNKNOWN IMPORTED)
    set_target_properties(MbedTLS::mbedcrypto PROPERTIES
        IMPORTED_LOCATION "${MBEDCRYPTO_LIB}")
endif()

find_library(OQS_LIB oqs REQUIRED)

set(SHYAKE_SOURCES
    src/account.c
    src/crypto_ops.c
    src/enc_dec.c
    src/known_hosts.c
    src/libshyake.c
    src/mail.c
    src/network.c
    src/passphrase.c
    src/shyake_crypto.c
    src/vendor/cJSON/cJSON.c
)

set(SHYAKE_LIBS
    CURL::libcurl
    MbedTLS::mbedcrypto
    ${OQS_LIB}
    advapi32   # RtlGenRandom (SystemFunction036)
)

# static library for the GUI client
add_library(shyake_static STATIC ${SHYAKE_SOURCES})
target_include_directories(shyake_static PUBLIC include PRIVATE src)
target_link_libraries(shyake_static PUBLIC ${SHYAKE_LIBS})
set_target_properties(shyake_static PROPERTIES OUTPUT_NAME shyake)

# DLL for PowerShell / .NET P/Invoke
if(SHYAKE_BUILD_DLL)
    add_library(shyake_shared SHARED ${SHYAKE_SOURCES})
    target_include_directories(shyake_shared PUBLIC include PRIVATE src)
    target_link_libraries(shyake_shared PRIVATE ${SHYAKE_LIBS})
    set_target_properties(shyake_shared PROPERTIES
        OUTPUT_NAME shyake
        WINDOWS_EXPORT_ALL_SYMBOLS ON)
endif()

if(SHYAKE_BUILD_TESTS)
    enable_testing()
    add_executable(test_crypto tests/test_crypto.c)
    target_include_directories(test_crypto PRIVATE src)
    target_link_libraries(test_crypto PRIVATE shyake_static)
    add_test(NAME crypto COMMAND test_crypto)

    # needs a running instance; run manually, not via ctest
    add_executable(test_e2e tests/test_e2e.c)
    target_link_libraries(test_e2e PRIVATE shyake_static)
endif()
