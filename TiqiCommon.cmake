# Distributed under the OSI-approved BSD 3-Clause License.  See accompanying
# file Copyright.txt or https://cmake.org/licensing for details.
    
#[=======================================================================[.rst:
TiqiCommon
------------------

.. only:: html

  .. contents::

Overview
^^^^^^^^

Provides utility functions to assist in CMake-base workflows for Tiqi projects.
The current set of supported commands is limited to GitLab utility functions for
artifact download and authentication handling.

The following shows a typical example of obtaining a GitLab authentication header used for fetching all artifacts for a specific CI job:

.. code-block:: cmake

  TiqiCommon_GitlabAuthenticationHeader(auth_header)

  TiqiCommon_GitlabArtifactURL(artifact_fetch_url
        "tiqi-projects/my-project"
        CI_JOB_NAME "build"
        GIT_REF "main"
  )

  FetchContent_Declare(
    my-project
    URL ${artifact_fetch_url}
    HTTP_HEADER ${auth_header}
  )

Commands
^^^^^^^^

.. command:: TiqiCommon_GitlabAuthenticationHeader

  .. code-block:: cmake

    TiqiCommon_GitlabAuthenticationHeader(
      <variable_name>
      [GITLAB_HOST <gitlabHostname>]
    )

  Creates a full HTTPS authentication header using either a CI job token or by obtaining a GitLab private token through SSH. The authentication header is stored in the target variable called ``<variable_name>`` within the calling scope.

  .. note:: SSH access to the Gitlab instance must be configured on the system for the token generation to work.
  
  The function has the optional argument ``GITLAB_HOST`` to specify a Gitlab host different from the default ``gitlab.phys.ethz.ch``.

  The command is designed to provide various ways of token caching to avoid generating unnecessary tokens:
  * Token fetching is only done for the first call of the function, successive calls will return a global variable.
  * During the initial configuration step (and if the CI job token variable is not defined), a new token with minimal lifetime is generated through SSH. The token is stored in the CMake cache.
  * Function calls in successive configuration steps (if you make changes to the CMake lists and re-run make/ninja) try to get the token from the CMake cache. The restored token is tested for validity by means of a trial API read. If the token is found to be invalid, a new token is generated through SSH.

.. command:: TiqiCommon_GitlabArtifactURL

  .. code-block:: cmake

    TiqiCommon_GitlabArtifactURL(
      <variable_name>
      <gitlab_project>
      [GITLAB_HOST <gitlabHostname>]
      <artifactIdentification>...
    )

  Constructs a GitLab artifact download URL using various methods as described in the `GitLab documentation <https://docs.gitlab.com/ee/api/job_artifacts.html>`_ and stores it in the target variable called ``<variable_name>``.

  .. note:: The method uses URL encoding to support special characters in project names, job names and other arguments. The resulting URL might not be human readable.

  The function is designed to support all possible download methods described in the GitLab documentation. This involves downloading either a single file (specified by a path) or all files in one zip for a CI job. There are two methods to specify the target job:

  1. Specific job, identified by its job ID.
  2. Latest successful job with a given name, executed for a specific branch or for a specific tag (specified by ref name).

  The two required arguments ``<variable_name>`` and ``<gitlab_project>`` are common to both methods. The ``<gitlab_project>`` can be both a path to the project (URL portion of the project link on gitlab without the https://gitlab-host/ portion, for example ``mygroup/myproject``) or a project ID.

  The following arguments are common to both job identification methods:

  ``GITLAB_HOST``
    The optional argument can be used to specify a Gitlab host different from the default ``gitlab.phys.ethz.ch``.

  ``ARTIFACT_PATHNAME``
    The optional argument can be used to download a specific file from the job artifacts. The fully qualified path format is identical to the format used in the ``.gitlab-ci.yml``.

  The following arguments are required if you want to use ``1.`` as the download method (job specified by job ID).

  ``CI_JOB_ID``
    The CI job ID as shown in the GitLab pipeline information page.

  The following arguments are required if you want to use ``2.`` as the download method (job specified by name and git ref).

  ``CI_JOB_NAME``
    The name of the job as specified in the ``.gitlab-ci.yml``. If you use ``parallel:matrix`` you get the exact job name from the pipeline overview page. A typical job name in this case may be ``build: [MYVAR_A=0, MYVAR_B=1]``.

  ``GIT_REF``
    The name of the branch or tag, for which the latest successful run should be selected.
    
  .. note:: The two download methods and the corresponding arguments are mutually exclusive.

Examples
^^^^^^^^

Download Compressed Sources from the Main-Branch
""""""""""""""""""""""""""""""""""""""""""""""""

.. code-block:: cmake
  


Usage
-----

This module provides helper functions to streamline interactions with GitLab in CMake workflows. The main utilities provided are for creating authentication headers and assembling artifact download URLs. The user must take care to only use the intended public functions and not internal utility functions.

Note: Ensure that this module is included in your CMake project before calling any of its functions.
#]=======================================================================]

#=======================================================================
# Helpers
#=======================================================================

# Internal use, projects must not call this directly. It is
# intended for use by TiqiCommon_GitlabArtifactURL() only.
#
# Use to encode URL parts to support special characters in Gitlab
# api paths.
# Source: https://gitlab.kitware.com/cmake/cmake/-/issues/21274
function(__TiqiCommon_EncodeURI inputString outputVariable)
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

#=======================================================================
# Gitlab Helper Functions
#=======================================================================

# Obtain Gitlab private token through CI variable or SSH and make full
# HTTPS authentication header available as specified variable
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

# Assemble Gitlab artifact download URL through methods described in
# https://docs.gitlab.com/ee/api/job_artifacts.html
function(TiqiCommon_GitlabArtifactURL outputVariable gitlabProject)
	set(oneValueArgs
		GITLAB_HOST
		ARTIFACT_PATHNAME
		CI_JOB_ID
		CI_JOB_NAME
		GIT_REF
	)
	cmake_parse_arguments(PARSE_ARGV 1 ARG "" "${oneValueArgs}" "")

	if(NOT ARG_GITLAB_HOST)
		set(ARG_GITLAB_HOST "gitlab.phys.ethz.ch")
	endif()

	if(NOT ARG_CI_JOB_ID)
		if(NOT ARG_CI_JOB_NAME OR NOT ARG_GIT_REF)
			message(FATAL_ERROR "Gitlab artifact download requires both a job name and a Git ref if no job ID is given.")
		endif()

		__TiqiCommon_EncodeURI(${ARG_CI_JOB_NAME} jobNameEncoded)
		__TiqiCommon_EncodeURI(${ARG_GIT_REF} refEncoded)
	else()
		if(ARG_CI_JOB_NAME OR ARG_GIT_REF)
			message(FATAL_ERROR "Gitlab artifact download by job ID does not allow a job name or a Git ref.")
		endif()

		__TiqiCommon_EncodeURI(${ARG_CI_JOB_ID} jobIdEncoded)
	endif()

	if(ARG_ARTIFACT_PATHNAME)
		__TiqiCommon_EncodeURI(${ARG_ARTIFACT_PATHNAME} pathnameEncoded)
	endif()

	__TiqiCommon_EncodeURI(${gitlabProject} projectEncoded)

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

