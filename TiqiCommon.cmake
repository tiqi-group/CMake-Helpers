cmake_minimum_required(VERSION 3.7)

function(TiqiCommon_GitlabAuthenticationHeader outputVariable)
	set(oneValueArgs
		GITLAB_HOST
	)
	cmake_parse_arguments(PARSE_ARGV 1 ARG "" "${oneValueArgs}" "")

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
	set(${outputVariable} "PRIVATE-TOKEN: ${propertyValue}" PARENT_SCOPE)
endfunction()

function(TiqiCommon_EncodeURI inputString outputVariable)
	string(HEX ${inputString} hex)
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
	set(${outputVariable} ${result} PARENT_SCOPE)
endfunction()

function(TiqiCommon_GitlabArtifactURL outputVariable)
	set(oneValueArgs
		GITLAB_HOST
		GITLAB_PROJECT
		ARTIFACT_PATHNAME
		CI_JOB_ID
		CI_JOB_NAME
		GIT_REF
	)
	cmake_parse_arguments(PARSE_ARGV 1 ARG "" "${oneValueArgs}" "")

	if(NOT ARG_GITLAB_HOST)
		set(ARG_GITLAB_HOST "gitlab.phys.ethz.ch")
	endif()

	if(NOT ARG_GITLAB_PROJECT)
		message(FATAL_ERROR "Gitlab artifact download requires either a project ID or a project name.")
	endif()

	if(NOT ARG_CI_JOB_ID)
		if(NOT ARG_CI_JOB_NAME OR NOT ARG_GIT_REF)
			message(FATAL_ERROR "Gitlab artifact download requires both a job name and a Git ref if no job ID is given.")
		endif()

		TiqiCommon_EncodeURI(${ARG_CI_JOB_NAME} jobNameEncoded)
		TiqiCommon_EncodeURI(${ARG_GIT_REF} refEncoded)
	else()
		if(ARG_CI_JOB_NAME OR ARG_GIT_REF)
			message(FATAL_ERROR "Gitlab artifact download by job ID does not allow a job name or a Git ref.")
		endif()

		TiqiCommon_EncodeURI(${ARG_CI_JOB_ID} jobIdEncoded)
	endif()

	if(ARG_ARTIFACT_PATHNAME)
		TiqiCommon_EncodeURI(${ARG_ARTIFACT_PATHNAME} pathnameEncoded)
	endif()

	TiqiCommon_EncodeURI(${ARG_GITLAB_PROJECT} projectEncoded)

	# four different methods to download artifacts (https://docs.gitlab.com/ee/api/job_artifacts.html)
	if(ARG_ARTIFACT_PATHNAME AND ARG_CI_JOB_ID)
		set(downloadURI "projects/${projectEncoded}/jobs/${jobIdEncoded}/artifacts/${pathnameEncoded}")
	elseif(ARG_ARTIFACT_PATHNAME AND NOT ARG_CI_JOB_ID)
		set(downloadURI "projects/${projectEncoded}/jobs/artifacts/${refEncoded}/raw/${pathnameEncoded}?job=${jobNameEncoded}")
	elseif(NOT ARG_ARTIFACT_PATHNAME AND ARG_CI_JOB_ID)
		set(downloadURI "projects/${projectEncoded}/jobs/${jobIdEncoded}/artifacts")
	elseif(NOT ARG_ARTIFACT_PATHNAME AND NOT ARG_CI_JOB_ID)
		set(downloadURI "projects/${projectEncoded}/jobs/artifacts/${refEncoded}/download?job=${jobNameEncoded}")
	endif()

	set(${outputVariable} "https://${ARG_GITLAB_HOST}/api/v4/${downloadURI}" PARENT_SCOPE)
endfunction()

