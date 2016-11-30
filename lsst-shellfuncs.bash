#!/bin/bash

function _check_executable() {
    local exe
    exe=$1
    if [ -z "$(which ${exe})" ]; then
	echo 1>&2 "${exe} not found"
	(exit 1)
    fi
}

function _retrieve_aws_metadata() {
    local path
    path=$1
    check_curl
    rc=$?
    if [ ${rc} -ne 0 ]; then
	return
    fi
    url="http://169.254.169.254/latest/meta-data/${path}"
    curl -s ${url}
}

function _parse_aws_creds() {
    local creds
    creds=$1
    local field
    field=$2
    echo "${creds}" | cut -d ',' -f ${field}
}

function check_jq() {
    _check_executable jq
}

function check_aws() {
    _check_executable aws
}

function check_curl() {
    _check_executable curl
}

function check_git() {
    _check_executable git
}

function check_git_lfs() {
    check_git
    rc=$?
    if [ "${rc}" -ne 0 ]; then
	(exit ${rc})
    fi
    _check_executable git-lfs
}

function get_aws_instance_id() {
    _retrieve_aws_metadata instance-id
}

function get_aws_region() {
    local r
    echo -n "$(echo "$(get_aws_availability_zone)" | rev | cut -c 2- | rev)"
}

function get_aws_availability_zone() {
    _retrieve_aws_metadata placement/availability-zone
}

function get_aws_creds() {
    # Returns access key / secret key / token
    check_aws
    rc=$?
    if [ ${rc} -ne 0 ]; then
	return
    fi
    check_jq
    rc=$?
    if [ ${rc} -ne 0 ]; then
	return
    fi
    local iid
    iid=$(get_aws_instance_id)
    local region
    reg=$(get_aws_region)
    local role
    role=$(aws ec2 describe-instances --instance-ids ${iid} --region=${reg} \
	       | jq -r .Reservations[0].Instances[0].IamInstanceProfile.Arn \
	       | cut -d '/' -f 2)
    _retrieve_aws_metadata iam/security-credentials/${role} \
	| jq -r '[.AccessKeyId,.SecretAccessKey,.Token] | @csv' \
	| tr -d '"'
}

function clear_aws_variables() {
    unset AWS_DEFAULT_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY \
	  AWS_SESSION_TOKEN
}

function set_aws_variables() {
    if [ -z "${AWS_DEFAULT_REGION}" ]; then
	AWS_DEFAULT_REGION=$(get_aws_region)
	export AWS_DEFAULT_REGION
    fi
    if [ -z "${AWS_ACCESS_KEY_ID}" ] || [ -z "${AWS_SECRET_ACCESS_KEY}" ] \
	   || [ -z "${AWS_SESSION_TOKEN}" ]; then
	creds=$(get_aws_creds)
	if [ -z "${creds}" ]; then
	    echo 1>&2 "Could not retrieve AWS credentials"
	    return
	fi
	if [ -z "${AWS_ACCESS_KEY_ID}" ]; then
            AWS_ACCESS_KEY_ID=$(_parse_aws_creds ${creds} 1)
            export AWS_ACCESS_KEY_ID
	fi
	if [ -z "${AWS_SECRET_ACCESS_KEY}" ]; then
            AWS_SECRET_ACCESS_KEY=$(_parse_aws_creds ${creds} 2)
            export AWS_SECRET_ACCESS_KEY
	fi
	if [ -z "${AWS_SESSION_TOKEN}" ]; then
            AWS_SESSION_TOKEN=$(_parse_aws_creds ${creds} 3)
            export AWS_SESSION_TOKEN
	fi
    fi
}

function refresh_aws_session_token() {
    creds=$(get_aws_creds)
    unset AWS_SESSION_TOKEN
    AWS_SESSION_TOKEN=$(_parse_aws_creds ${creds} 3)
    export AWS_SESSION_TOKEN
}

function check_github_lfs() {
    check_git_lfs
    rc=$?
    if [ ${rc} -ne 0 ]; then
	return
    fi
    gcf="${HOME}/.gitconfig"
    grep -q '^\[lfs\]$' ${gcf} >/dev/null 2>&1
    rc=$?
    if [ ${rc} -ne 0 ]; then
	git config --global lfs.batch false
	git lfs install
    fi
    grep -q '^# Cache anonymous access to DM Git LFS S3 servers$' ${gcf} \
	 >/dev/null 2>&1
    rc=$?
    if [ ${rc} -ne 0 ]; then
	cat <<'EOF' >> ${gcf}
# Cache anonymous access to DM Git LFS S3 servers
[credential "https://lsst-sqre-prod-git-lfs.s3-us-west-2.amazonaws.com"]
    helper = store
[credential "https://s3.lsst.codes"]
    helper = store

# Cache anonymous access to DM Git LFS server
[credential "https://git-lfs.lsst.codes"]
    helper = store
EOF
    fi
    local credfile
    credfile="${HOME}/.git-credentials"
    grep -q '^https:\/\/:@lsst-sqre-prod-git-lfs.s3-us-west-2.amazonaws.com' \
	 ${credfile} >/dev/null 2>&1
    rc=$?
    if [ ${rc} -ne 0 ]; then
	cat <<'EOF' >> ${credfile}
https://:@lsst-sqre-prod-git-lfs.s3-us-west-2.amazonaws.com
https://:@s3.lsst.codes
https://:@git-lfs.lsst.codes
EOF
    fi    
}
