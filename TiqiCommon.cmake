function(uriencode input output_variable)
    string(HEX "${input}" hex)
    string(LENGTH "${hex}" length)
    math(EXPR last "${length} - 1")
    set(result "")
    foreach(i RANGE ${last})
        math(EXPR even "${i} % 2")
        if("${even}" STREQUAL "0")
            string(SUBSTRING "${hex}" "${i}" 2 char)
            string(APPEND result "%${char}")
        endif()
    endforeach()
    set("${output_variable}" ${result} PARENT_SCOPE)
endfunction()

# Function to get access token for GitLab API
function(get_access_token)
    if(DEFINED ENV{CI_JOB_TOKEN})
        set(gitlab_api_header "JOB-TOKEN: $ENV{CI_JOB_TOKEN}" CACHE STRING "GitLab API Header")
    else()
        execute_process(
            COMMAND ssh git@gitlab.phys.ethz.ch personal_access_token sdk-artifact-devil-server read_api 0
            RESULT_VARIABLE ssh_result
            OUTPUT_VARIABLE ssh_output
        )
        if(ssh_result)
            message(FATAL_ERROR "Failed to generate personal access token using SSH.")
        else()
            string(REGEX MATCH "Token: ([^\n]+)" _ ${ssh_output})
            string(STRIP ${CMAKE_MATCH_1} gitlab_private_token)
            set(gitlab_api_header "PRIVATE-TOKEN: ${gitlab_private_token}" CACHE STRING "GitLab API Header")
        endif()
    endif()
    message(STATUS "Using GitLab API header: ${gitlab_api_header}")
endfunction()

# Function to download SDK
function(download_sdk)
    include(FetchContent)
    FetchContent_Declare(
        sdk
        URL "${sdk_artifact_url}/${sdk_artifact_ref}/raw/${sdk_artifact_file}?job=${sdk_artifact_job_name}"
        HTTP_HEADER "${gitlab_api_header}"
        PATCH_COMMAND "${sdk_artifact_patch_command}"
        DOWNLOAD_EXTRACT_TIMESTAMP FALSE
    )
    FetchContent_MakeAvailable(sdk)
endfunction()

# Function to check if the toolchain file exists and update the SDK if it's
# older than a week
function(check_and_update_sdk)
    if(EXISTS "${CMAKE_TOOLCHAIN_FILE}")
        file(TIMESTAMP "${CMAKE_TOOLCHAIN_FILE}" SDK_TIMESTAMP_SEC "%s" UTC)
        string(TIMESTAMP CURRENT_TIME_SEC "%s" UTC)
        math(EXPR TIME_DIFF_HOURS "(${CURRENT_TIME_SEC} - ${SDK_TIMESTAMP_SEC}) / 3600")
        if(TIME_DIFF_HOURS LESS 168) # 168 hours = 1 week
            message(STATUS "SDK is up to date. Skipping download.")
        else()
            message(STATUS "The SDK is older than a week, updating...")
            get_access_token()
            download_sdk()
        endif()
    else()
        message(STATUS "The SDK is not found, downloading...")
        get_access_token()
        download_sdk()
    endif()
endfunction()

