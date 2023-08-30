cmake_minimum_required(VERSION 3.7)

function(TiqiCommon_ExportGitlabToken)
	set(oneValueArgs
		GITLAB_HOST
	)
	cmake_parse_arguments(PARSE_ARGV 0 ARG "" "${oneValueArgs}" "")

	if(NOT ARG_GITLAB_HOST)
		set(ARG_GITLAB_HOST "gitlab.phys.ethz.ch")
	endif()

	get_property(alreadyDefined GLOBAL PROPERTY "__TiqiCommon_gitlab_token" DEFINED)
	if(NOT alreadyDefined)

		if(DEFINED ENV{CI_JOB_TOKEN})
			define_property(GLOBAL PROPERTY "__TiqiCommon_gitlab_token")
			set_property(GLOBAL PROPERTY "__TiqiCommon_gitlab_token" $ENV{CI_JOB_TOKEN})
		else()
			set(gitlabHost ${ARG_GITLAB_HOST})

			if(NOT DEFINED _TIQI_COMMON_GITLAB_TOKEN)
				set(_TIQI_COMMON_GITLAB_TOKEN "dummy" CACHE INTERNAL "")
			endif()

			file(
				DOWNLOAD "https://${gitlabHost}/api/v4/user"
				HTTPHEADER "PRIVATE-TOKEN: ${_TIQI_COMMON_GITLAB_TOKEN}"
				STATUS downloadStatus
			)
			list(GET downloadStatus 0 statusCode)

			if(NOT statusCode EQUAL 0)
				execute_process(
					COMMAND ssh git@${gitlabHost} personal_access_token cmake_access_token read_api,read_repository 0
					RESULT_VARIABLE ssh_result
					OUTPUT_VARIABLE ssh_output
				)
				if(ssh_result)
					message(FATAL_ERROR "Failed to generate personal access token using SSH.")
				else()
					message(STATUS "Created new Gitlab access token")
					string(REGEX MATCH "Token: ([^\n]+)" _ ${ssh_output})
					string(STRIP ${CMAKE_MATCH_1} gitlab_private_token)
					set(_TIQI_COMMON_GITLAB_TOKEN ${gitlab_private_token} CACHE INTERNAL "")
				endif()
			endif()

			define_property(GLOBAL PROPERTY "__TiqiCommon_gitlab_token")
			set_property(GLOBAL PROPERTY "__TiqiCommon_gitlab_token" ${_TIQI_COMMON_GITLAB_TOKEN})
		endif()
	endif()

	get_property(propertyValue GLOBAL PROPERTY "__TiqiCommon_gitlab_token")
	set(GITLAB_PRIVATE_TOKEN ${propertyValue} PARENT_SCOPE)
	set(GITLAB_PRIVATE_TOKEN_HEADER "PRIVATE-TOKEN: ${propertyValue}" PARENT_SCOPE)
endfunction()


